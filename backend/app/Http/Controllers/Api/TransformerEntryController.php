<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Support\PlaceHoldings;
use App\Support\TransformerSheetReader;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use App\Support\IdSequence;
use Illuminate\Validation\Rule;

/**
 * Adding transformers through the application, with their serial numbers.
 *
 * Its own file because it writes: a row in the transformer register for
 * each unit, and the same entry in the assets_used log.
 *
 * WHY TRANSFORMERS ARE NOT ADDED LIKE POLES. A pole holding is a quantity
 * -- "40 RC poles at Welimada" -- and the asset register stores it as a
 * count. A transformer is an individual piece of plant with its own
 * serial number, SIN number and substation, and the province already
 * keeps them one row each in `transformers`. Recording "3 transformers"
 * as a count would put them somewhere the transformer register, the
 * lookup and the reports never look, and lose the serial numbers.
 *
 * SERIAL NUMBERS MUST BE NEW. A serial or SIN already in the register is
 * refused and the existing transformer is named, because the same unit
 * entered twice is the error this check exists to catch.
 */
class TransformerEntryController extends Controller
{
    /** Register type text for each transformer asset type. */
    private const REGISTER_TYPE = [
        'TX_DIST'      => 'Distribution',
        'TX_BULK'      => 'Bulk',
        'TX_BULK_DIST' => 'Bulk & Distribution',
        'TX_MHP'       => 'Bulk (MHP)',
    ];

    /**
     * WHERE THIS DATA COMES FROM AND WHERE IT LANDS
     *
     *   Screen    Assets -> "+ Add assets", with a transformer type chosen
     *   File      frontend/src/pages/Assets/AddAssetsDialog.jsx
     *   Route     POST /api/network/transformers
     *
     *   transformers       one row per PHYSICAL UNIT
     *     transformer_no   <- the line's Serial number box
     *     old_sin_no       <- the line's old SIN box (blank -> NULL)
     *     new_sin_no       <- the line's new SIN box (blank -> NULL)
     *     substation_name  <- the line's Substation box
     *     transformer_type <- DERIVED from the asset type's type_code,
     *                         via REGISTER_TYPE above
     *     capacity_kva     <- the line's kVA box
     *     manufacturer     <- the line's Manufacturer box
     *     csc_id           <- the CSC dropdown
     *     install_date     <- the form footer, shared by every line
     *     remarks          <- the form footer, shared by every line
     *     quantity         <- fixed 1: a row here IS one unit
     *     status           <- fixed ACTIVE
     *     source_file      <- fixed 'dashboard-entry'
     *
     *   assets_used        the same entry in the history log, with
     *                      transformer_id pointing at the row just
     *                      created and asset_id left NULL.
     *
     * The full map for every write in the application is in
     * docs/data-flow.md.
     */
    public function store(Request $request)
    {
        $data = $request->validate([
            'csc_id'       => ['required', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],
            'install_date' => ['nullable', 'date'],
            'remarks'      => ['nullable', 'string', 'max:500'],

            'transformers'                    => ['required', 'array', 'min:1', 'max:20'],
            'transformers.*.asset_type_id'    => ['required', 'string', 'max:12', Rule::exists('asset_types', 'asset_type_id')],
            'transformers.*.serial_no'        => ['required', 'string', 'max:60'],
            'transformers.*.old_sin_no'       => ['nullable', 'string', 'max:40'],
            'transformers.*.new_sin_no'       => ['nullable', 'string', 'max:40'],
            'transformers.*.substation_name'  => ['required', 'string', 'max:255'],
            'transformers.*.capacity_kva'     => ['nullable', 'numeric', 'min:0', 'max:100000'],
            'transformers.*.manufacturer'     => ['nullable', 'string', 'max:80'],
            'transformers.*.condition_status' => ['nullable', Rule::in(['NEW', 'GOOD', 'FAIR', 'POOR', 'FAULTY', 'UNKNOWN'])],
        ], [
            'transformers.*.serial_no.required'       => 'Every transformer needs its serial number.',
            'transformers.*.substation_name.required' => 'Every transformer needs the substation it serves.',
        ]);

        $types = DB::table('asset_types as t')
            ->join('asset_categories as c', 'c.category_id', '=', 't.category_id')
            ->where('c.category_name', 'Transformer')
            ->get(['t.asset_type_id', 't.type_code', 't.type_name'])
            ->keyBy('asset_type_id');

        $items = collect($data['transformers']);

        foreach ($items as $i => $item) {
            if (! isset($types[$item['asset_type_id']])) {
                return $this->refuse("Line " . ($i + 1) . ' is not a transformer type.');
            }
        }

        /* ------------------------------- serial and SIN must be new */

        $key = fn ($v) => TransformerSheetReader::idKey($v);

        $serials = $items->map(fn ($t) => $key($t['serial_no']));
        if ($serials->duplicates()->isNotEmpty()) {
            return $this->refuse('The same serial number is entered twice: ' . $items[$serials->duplicates()->keys()->first()]['serial_no'] . '.');
        }

        $register = DB::table('transformers')
            ->get(['transformer_id', 'old_sin_no', 'new_sin_no', 'transformer_no', 'substation_name']);

        $bySerial = [];
        $bySin    = [];
        foreach ($register as $r) {
            if ($key($r->transformer_no) !== '') {
                $bySerial[$key($r->transformer_no)] ??= $r;
            }
            foreach (['old_sin_no', 'new_sin_no'] as $c) {
                if ($key($r->$c) !== '') {
                    $bySin[$key($r->$c)] ??= $r;
                }
            }
        }

        foreach ($items as $item) {
            if ($hit = $bySerial[$key($item['serial_no'])] ?? null) {
                return $this->refuse("Serial number {$item['serial_no']} is already recorded, for {$hit->substation_name} (record {$hit->transformer_id}).");
            }
            foreach (['old_sin_no', 'new_sin_no'] as $c) {
                if (! empty($item[$c]) && ($hit = $bySin[$key($item[$c])] ?? null)) {
                    return $this->refuse("SIN number {$item[$c]} is already recorded, for {$hit->substation_name} (record {$hit->transformer_id}).");
                }
            }
        }

        $place    = PlaceHoldings::place((string) $data['csc_id']);
        $userId   = $request->user()?->getKey();
        $batchRef = bin2hex(random_bytes(16));

        $saved = DB::transaction(function () use ($items, $types, $place, $data, $userId, $batchRef) {
            $written = [];

            foreach ($items as $item) {
                $type = $types[$item['asset_type_id']];

                $id = IdSequence::next('transformers');

                DB::table('transformers')->insert([
                    'transformer_id'   => $id,
                    'csc_id'           => $place->csc_id,
                    'asset_type_id'    => $type->asset_type_id,
                    'old_sin_no'       => trim($item['old_sin_no'] ?? '') ?: null,
                    'new_sin_no'       => trim($item['new_sin_no'] ?? '') ?: null,
                    'substation_name'  => trim($item['substation_name']),
                    'transformer_type' => self::REGISTER_TYPE[$type->type_code] ?? $type->type_name,
                    'capacity_kva'     => $item['capacity_kva'] ?? null,
                    'transformer_no'   => trim($item['serial_no']),
                    'manufacturer'     => trim($item['manufacturer'] ?? '') ?: null,
                    'quantity'         => 1,
                    'condition_status' => $item['condition_status'] ?? 'UNKNOWN',
                    'status'           => 'ACTIVE',
                    'install_date'     => $data['install_date'] ?? null,
                    'remarks'          => $data['remarks'] ?? null,
                    'source_file'      => 'dashboard-entry',
                    'created_at'       => now(),
                    'updated_at'       => now(),
                ]);

                // The usage log, against the transformer row just created.
                DB::table('assets_used')->insert([
                    'asset_usage_id'   => IdSequence::next('assets_used'),
                    'asset_id'         => null,
                    'transformer_id'   => $id,
                    'asset_type_id'    => $type->asset_type_id,
                    'csc_id'           => $place->csc_id,
                    'area_id'          => $place->area_id,
                    'quantity'         => 1,
                    'unit_of_measure'  => 'nos',
                    'condition_status' => $item['condition_status'] ?? 'UNKNOWN',
                    'capacity_kva'     => $item['capacity_kva'] ?? null,
                    'used_on'          => $data['install_date'] ?? null,
                    'used_for'         => mb_substr(trim(($data['remarks'] ?? '') . ' · serial ' . $item['serial_no'], ' ·'), 0, 500),
                    'batch_ref'        => $batchRef,
                    'recorded_by'      => $userId,
                ]);

                $written[] = [
                    'transformer_id'  => $id,
                    'asset_type_id'   => (string) $type->asset_type_id,
                    'type_name'       => $type->type_name,
                    'category_name'   => 'Transformer',
                    'quantity'        => 1.0,
                    'unit_of_measure' => 'nos',
                    'serial_no'       => trim($item['serial_no']),
                    'substation_name' => trim($item['substation_name']),
                ];
            }

            return $written;
        });

        return response()->json([
            'message' => count($saved) === 1
                ? "Transformer {$saved[0]['serial_no']} saved to {$place->csc_name} CSC."
                : count($saved) . " transformers saved to {$place->csc_name} CSC.",

            'place' => [
                'csc_id'        => (string) $place->csc_id,
                'csc_code'      => $place->csc_code,
                'csc_name'      => $place->csc_name,
                'area_id'       => (string) $place->area_id,
                'area_name'     => $place->area_name,
                'province_name' => $place->province_name,
            ],

            'added'        => $saved,
            'added_totals' => [['unit_of_measure' => 'nos', 'quantity' => (float) count($saved)]],

            'place_totals'     => PlaceHoldings::totals((string) $place->csc_id),
            'place_categories' => PlaceHoldings::categories((string) $place->csc_id),
            'batch_ref'        => $batchRef,
        ], 201);
    }

    private function refuse(string $message)
    {
        return response()->json(['message' => $message], 422);
    }
}
