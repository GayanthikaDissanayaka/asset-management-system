<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Support\PlaceResolver;
use App\Support\TransformerSheetReader as Reader;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use App\Support\IdSequence;
use PhpOffice\PhpSpreadsheet\Spreadsheet;

/**
 * Loading a transformer workbook -- one sheet per CSC, SIN numbers,
 * substations, capacities, serial numbers, manufacturers, fly lengths.
 *
 * Its own file because it writes to the transformer register. It is
 * reached through the one Import button: SegmentImportController hands
 * any workbook that holds transformer tables to this class.
 *
 * ONLY WHAT IS IN THE FILE. Each row is matched to a transformer already
 * in the register by its old SIN, new SIN or serial number. A matched
 * transformer has only the fields the file actually carries changed, and
 * a blank cell never clears a stored value -- a sheet without a
 * manufacturer column does not erase manufacturers. A row matching
 * nothing becomes a new transformer.
 *
 * PREVIEW FIRST. Because this changes records that already exist, an
 * upload first returns what WOULD change -- how many would be added,
 * which fields of which transformers would be updated, and from what to
 * what -- and writes nothing. The same file sent again with confirm=1
 * applies exactly that. Nothing is stored between the two requests; the
 * file is simply read twice.
 *
 * WHERE A NEW TRANSFORMER GOES. A CSC column on the row wins; otherwise
 * the sheet's name ("Badulla" is Badulla CSC); otherwise the SIN prefix
 * (UBB is Badulla, UMB is Bibila) learned from the register itself. A
 * matched transformer is never moved to a different CSC by an import --
 * a disagreement is reported instead.
 */
class TransformerImportController extends Controller
{
    /** How many new / updated rows are listed in the response. */
    private const SAMPLE = 60;

    private const NUMERIC = [
        'capacity_kva', 'fly_length_km', 'combined_fly_length_km',
        'free_wayleave_km', 'wayleave_distance_km', 'total_distance_km',
    ];

    private const IDENTIFIERS = ['old_sin_no', 'new_sin_no', 'transformer_no'];

    private const CONDITIONS = ['NEW', 'GOOD', 'FAIR', 'POOR', 'FAULTY', 'UNKNOWN'];

    /**
     * Returns null when the workbook holds no transformer table, so the
     * caller can try it as a segment sheet instead.
     */
    public function importBook(Spreadsheet $book, Request $request)
    {
        $sheets = (new Reader())->read($book);

        if (empty($sheets)) {
            return null;
        }

        $apply = $request->boolean('confirm');

        $existing = DB::table('transformers')->get([
            'transformer_id', 'csc_id', 'asset_type_id',
            'old_sin_no', 'new_sin_no', 'transformer_no', 'substation_name',
            'transformer_type', 'capacity_kva', 'manufacturer',
            'fly_length_km', 'combined_fly_length_km', 'free_wayleave_km',
            'wayleave_distance_km', 'total_distance_km', 'condition_status', 'remarks',
        ]);

        $bySin    = [];
        $bySerial = [];
        foreach ($existing as $t) {
            foreach (['old_sin_no', 'new_sin_no'] as $c) {
                $k = Reader::idKey($t->$c);
                if ($k !== '') {
                    $bySin[$k] ??= $t;
                }
            }
            $k = Reader::idKey($t->transformer_no);
            if ($k !== '') {
                $bySerial[$k] ??= $t;
            }
        }

        $cscNames  = DB::table('csc_depots as d')
            ->join('areas as a', 'a.area_id', '=', 'd.area_id')
            ->get(['d.csc_id', 'd.csc_name', 'a.area_name'])
            ->keyBy('csc_id');
        $places    = new PlaceResolver();
        $prefixCsc = $this->prefixIndex($existing);
        $typeIds   = DB::table('asset_types')->pluck('asset_type_id', 'type_code');

        $new       = [];
        $updates   = [];
        $unchanged = 0;
        $errors    = [];
        $warnings  = [];
        $sheetInfo = [];
        $seen      = [];

        foreach ($sheets as $sheet) {
            $col  = $sheet['fields'];
            $cell = fn (array $raw, string $f) => isset($col[$f])
                ? trim((string) ($raw[$col[$f]] ?? ''))
                : '';

            $sheetPlace = $places->resolve($sheet['sheet'], null);

            $info = [
                'sheet'      => $sheet['sheet'],
                'header_row' => $sheet['header_row'],
                'place'      => $sheetPlace['ok']
                    ? "{$sheetPlace['csc']->csc_name} CSC · {$sheetPlace['csc']->area_name} area"
                    : null,
                'place_note' => $sheetPlace['ok']
                    ? 'New transformers on this sheet go to the CSC named by the sheet.'
                    : "The sheet name '{$sheet['sheet']}' is not a CSC, so each row's CSC comes from its CSC column or SIN prefix.",
                'used'       => collect($sheet['field_headers'])
                    ->map(fn ($heading, $field) => ['heading' => $heading, 'read_as' => Reader::LABELS[$field] ?? $field])
                    ->values(),
                'ignored'    => $sheet['ignored'],
                'rows'       => 0,
                'new'        => 0,
                'updated'    => 0,
                'unchanged'  => 0,
            ];

            foreach ($sheet['rows'] as [$lineNo, $raw]) {
                $v = [
                    'old_sin_no'             => $cell($raw, 'old_sin_no') ?: $cell($raw, 'sin_no'),
                    'new_sin_no'             => $cell($raw, 'new_sin_no'),
                    'substation_name'        => $cell($raw, 'substation_name'),
                    'transformer_type'       => $cell($raw, 'transformer_type'),
                    'capacity_kva'           => $cell($raw, 'capacity_kva'),
                    'transformer_no'         => $cell($raw, 'serial_no'),
                    'manufacturer'           => $cell($raw, 'manufacturer'),
                    'fly_length_km'          => $cell($raw, 'fly_length_km'),
                    'combined_fly_length_km' => $cell($raw, 'combined_fly_length_km'),
                    'free_wayleave_km'       => $cell($raw, 'free_wayleave_km'),
                    'wayleave_distance_km'   => $cell($raw, 'wayleave_distance_km'),
                    'total_distance_km'      => $cell($raw, 'total_distance_km'),
                    'condition_status'       => strtoupper($cell($raw, 'condition_status')),
                    'remarks'                => $cell($raw, 'remarks'),
                ];

                // Only what the row actually says. Blank never overwrites.
                $v = array_filter($v, fn ($x) => $x !== '');

                // A totals line or a note under the table.
                if (! isset($v['old_sin_no']) && ! isset($v['new_sin_no'])
                    && ! isset($v['transformer_no']) && ! isset($v['substation_name'])) {
                    continue;
                }

                // "Total", "Sub total", "Grand total" written in the SIN column.
                $firstId = $v['old_sin_no'] ?? $v['new_sin_no'] ?? $v['transformer_no'] ?? '';
                if (! isset($v['substation_name']) && preg_match('/^\s*(grand\s*|sub\s*-?\s*)?totals?\b/i', $firstId)) {
                    continue;
                }

                $info['rows']++;

                foreach (self::NUMERIC as $f) {
                    if (! isset($v[$f])) {
                        continue;
                    }
                    $n = $this->number($v[$f]);
                    if ($n === null) {
                        if (preg_match('/\d/', $v[$f])) {
                            $warnings[] = $this->note($sheet, $lineNo, "'{$v[$f]}' in " . Reader::LABELS[$f] . ' is not a number; left as it was.');
                        }
                        unset($v[$f]);
                    } else {
                        $v[$f] = $n;
                    }
                }

                if (isset($v['condition_status']) && ! in_array($v['condition_status'], self::CONDITIONS, true)) {
                    unset($v['condition_status']);
                }

                // The same transformer twice in one file: the first row wins.
                $dupKey = Reader::idKey($v['old_sin_no'] ?? $v['new_sin_no'] ?? $v['transformer_no'] ?? '');
                if ($dupKey !== '') {
                    if (isset($seen[$dupKey])) {
                        $warnings[] = $this->note($sheet, $lineNo, "Also on {$seen[$dupKey]}; that row was used and this one skipped.");
                        continue;
                    }
                    $seen[$dupKey] = "{$sheet['sheet']} row {$lineNo}";
                }

                $match = null;
                foreach (['old_sin_no', 'new_sin_no'] as $c) {
                    if (! $match && isset($v[$c])) {
                        $match = $bySin[Reader::idKey($v[$c])] ?? null;
                    }
                }
                if (! $match && isset($v['transformer_no'])) {
                    $match = $bySerial[Reader::idKey($v['transformer_no'])] ?? null;
                }

                $label = $v['old_sin_no'] ?? $v['new_sin_no'] ?? $v['transformer_no'] ?? $v['substation_name'];

                /* ---------------------------------------- already recorded */
                if ($match) {
                    $rowCsc = $cell($raw, 'csc');
                    if ($rowCsc !== '') {
                        $hit = $places->resolve($rowCsc, $cell($raw, 'area'));
                        if ($hit['ok'] && (string) $hit['csc_id'] !== (string) $match->csc_id) {
                            $warnings[] = $this->note($sheet, $lineNo,
                                "{$label} is recorded in {$cscNames[$match->csc_id]->csc_name} CSC but the file says {$hit['csc']->csc_name}; it was not moved.");
                        }
                    }

                    $changes = [];
                    foreach ($v as $field => $to) {
                        $from = $match->$field;

                        if (in_array($field, self::NUMERIC, true)) {
                            if ($from !== null && abs((float) $from - (float) $to) < 0.0005) {
                                continue;
                            }
                        } elseif (in_array($field, self::IDENTIFIERS, true)) {
                            if (Reader::idKey($from) === Reader::idKey($to)) {
                                continue;
                            }
                        } elseif ($from !== null && trim((string) $from) === (string) $to) {
                            continue;
                        }

                        $changes[$field] = ['from' => $from, 'to' => $to];
                    }

                    if (empty($changes)) {
                        $unchanged++;
                        $info['unchanged']++;
                        continue;
                    }

                    $updates[] = [
                        'id'      => (string) $match->transformer_id,
                        'sheet'   => $sheet['sheet'],
                        'row'     => $lineNo,
                        'label'   => $label,
                        'name'    => $match->substation_name,
                        'csc'     => $cscNames[$match->csc_id]->csc_name ?? null,
                        'changes' => $changes,
                        'type_id' => isset($changes['transformer_type'])
                            ? $this->typeId($v['transformer_type'], $typeIds, $match->asset_type_id)
                            : null,
                    ];
                    $info['updated']++;
                    continue;
                }

                /* ----------------------------------------------------- new */
                // Without a SIN or serial the unit could never be matched
                // again, so a second import would record it twice.
                if (! isset($v['old_sin_no']) && ! isset($v['new_sin_no']) && ! isset($v['transformer_no'])) {
                    $errors[] = $this->note($sheet, $lineNo, "{$label} has no SIN or serial number, so it was not added. Fill in either and import again.");
                    continue;
                }

                if (! isset($v['substation_name'])) {
                    $errors[] = $this->note($sheet, $lineNo, "{$label} is not in the register and the row has no substation name, which a new transformer needs.");
                    continue;
                }

                [$cscId, $from] = $this->placeFor($cell($raw, 'csc'), $cell($raw, 'area'), $sheetPlace, $v, $places, $prefixCsc);

                if (! $cscId) {
                    $errors[] = $this->note($sheet, $lineNo, "Could not tell which CSC {$label} belongs to. Name the sheet after the CSC or add a CSC column.");
                    continue;
                }

                $new[] = [
                    'sheet'      => $sheet['sheet'],
                    'row'        => $lineNo,
                    'csc_id'     => $cscId,
                    'csc'        => $cscNames[$cscId]->csc_name ?? null,
                    'place_from' => $from,
                    'values'     => $v,
                    'type_id'    => $this->typeId($v['transformer_type'] ?? '', $typeIds, null),
                ];
                $info['new']++;
            }

            $sheetInfo[] = $info;
        }

        if ($apply) {
            $this->write($new, $updates, $request->user()?->getKey());
        }

        $counts = [
            'rows'      => array_sum(array_column($sheetInfo, 'rows')),
            'new'       => count($new),
            'updated'   => count($updates),
            'unchanged' => $unchanged,
            'errors'    => count($errors),
        ];

        return response()->json([
            'kind'    => 'transformers',
            'preview' => ! $apply,
            'applied' => $apply,
            'message' => $apply
                ? "Added {$counts['new']} " . ($counts['new'] === 1 ? 'transformer' : 'transformers')
                    . " and updated {$counts['updated']}. {$counts['unchanged']} already matched the register."
                : "Nothing has been written yet. This file would add {$counts['new']} "
                    . ($counts['new'] === 1 ? 'transformer' : 'transformers')
                    . " and update {$counts['updated']}; {$counts['unchanged']} already match the register. Check the lists below, then apply.",
            'counts'   => $counts,
            'created'  => $apply ? $counts['new'] : 0,
            'updated'  => $apply ? $counts['updated'] : 0,
            'sheets'   => $sheetInfo,
            'new'      => array_map(fn ($n) => [
                'sheet'      => $n['sheet'],
                'row'        => $n['row'],
                'sin'        => $n['values']['old_sin_no'] ?? $n['values']['new_sin_no'] ?? null,
                'serial'     => $n['values']['transformer_no'] ?? null,
                'substation' => $n['values']['substation_name'],
                'capacity'   => $n['values']['capacity_kva'] ?? null,
                'csc'        => $n['csc'],
                'place_from' => $n['place_from'],
            ], array_slice($new, 0, self::SAMPLE)),
            'updates'  => array_map(fn ($u) => [
                'sheet'   => $u['sheet'],
                'row'     => $u['row'],
                'label'   => $u['label'],
                'name'    => $u['name'],
                'csc'     => $u['csc'],
                'changes' => collect($u['changes'])->map(fn ($c, $f) => [
                    'field' => Reader::LABELS[$f] ?? $f,
                    'from'  => $c['from'],
                    'to'    => $c['to'],
                ])->values(),
            ], array_slice($updates, 0, self::SAMPLE)),
            'errors'   => $errors,
            'warnings' => $warnings,
        ]);
    }

    /* ============================== WRITE ============================= */

    private function write(array $new, array $updates, ?string $userId): void
    {
        DB::transaction(function () use ($new, $updates) {
            foreach ($new as $n) {
                $v = $n['values'];

                DB::table('transformers')->insert([
                        'transformer_id'   => IdSequence::next('transformers'),
                    'csc_id'                 => $n['csc_id'],
                    'asset_type_id'          => $n['type_id'],
                    'old_sin_no'             => isset($v['old_sin_no']) ? mb_substr($v['old_sin_no'], 0, 40) : null,
                    'new_sin_no'             => isset($v['new_sin_no']) ? mb_substr($v['new_sin_no'], 0, 40) : null,
                    'substation_name'        => mb_substr($v['substation_name'], 0, 255),
                    'transformer_type'       => isset($v['transformer_type']) ? mb_substr($v['transformer_type'], 0, 60) : null,
                    'capacity_kva'           => $v['capacity_kva'] ?? null,
                    'transformer_no'         => isset($v['transformer_no']) ? mb_substr($v['transformer_no'], 0, 60) : null,
                    'manufacturer'           => isset($v['manufacturer']) ? mb_substr($v['manufacturer'], 0, 80) : null,
                    'fly_length_km'          => $v['fly_length_km'] ?? null,
                    'combined_fly_length_km' => $v['combined_fly_length_km'] ?? null,
                    'free_wayleave_km'       => $v['free_wayleave_km'] ?? null,
                    'wayleave_distance_km'   => $v['wayleave_distance_km'] ?? null,
                    'total_distance_km'      => $v['total_distance_km'] ?? null,
                    'quantity'               => 1,
                    'condition_status'       => $v['condition_status'] ?? 'UNKNOWN',
                    'status'                 => 'ACTIVE',
                    'remarks'                => $v['remarks'] ?? null,
                    'source_file'            => 'excel-import',
                    'created_at'             => now(),
                    'updated_at'             => now(),
                ]);
            }

            foreach ($updates as $u) {
                $set = ['updated_at' => now()];
                foreach ($u['changes'] as $field => $c) {
                    $set[$field] = $c['to'];
                }
                if ($u['type_id']) {
                    $set['asset_type_id'] = $u['type_id'];
                }

                DB::table('transformers')->where('transformer_id', $u['id'])->update($set);
            }
        });
    }

    /* ============================= HELPERS ============================ */

    /** [csc_id, how it was decided] for a transformer not yet recorded. */
    private function placeFor(string $csc, string $area, array $sheetPlace, array $v, PlaceResolver $places, array $prefixCsc): array
    {
        if ($csc !== '') {
            $hit = $places->resolve($csc, $area);
            if ($hit['ok']) {
                return [(string) $hit['csc_id'], 'CSC column'];
            }
        }

        if ($sheetPlace['ok']) {
            return [(string) $sheetPlace['csc_id'], 'sheet name'];
        }

        foreach (['old_sin_no', 'new_sin_no'] as $c) {
            $prefix = $this->prefix($v[$c] ?? '');
            if ($prefix !== '' && isset($prefixCsc[$prefix])) {
                return [$prefixCsc[$prefix], "SIN prefix {$prefix}"];
            }
        }

        return [null, null];
    }

    /**
     * SIN prefix -> CSC, learned from the register: UBB is Badulla
     * because Badulla's transformers are numbered UBB. A prefix is only
     * trusted when at least 80% of the transformers carrying it are in
     * one CSC.
     */
    private function prefixIndex($existing): array
    {
        $counts = [];
        foreach ($existing as $t) {
            foreach (['old_sin_no', 'new_sin_no'] as $c) {
                $p = $this->prefix($t->$c);
                if ($p !== '') {
                    $counts[$p][$t->csc_id] = ($counts[$p][$t->csc_id] ?? 0) + 1;
                }
            }
        }

        $index = [];
        foreach ($counts as $prefix => $byCsc) {
            arsort($byCsc);
            $top = (int) array_key_first($byCsc);
            if ($byCsc[$top] / array_sum($byCsc) >= 0.8) {
                $index[$prefix] = $top;
            }
        }

        return $index;
    }

    private function prefix(?string $sin): string
    {
        return preg_match('/^\s*([A-Za-z]{2,4})/', (string) $sin, $m) ? strtoupper($m[1]) : '';
    }

    /** The asset type for a register type such as "Bulk & Distribution". */
    private function typeId(string $text, $typeIds, $fallback)
    {
        $t = strtolower($text);

        $code = match (true) {
            $t === ''                                          => null,
            str_contains($t, 'mhp') || str_contains($t, 'hydro') => 'TX_MHP',
            str_contains($t, 'bulk') && str_contains($t, 'dist') => 'TX_BULK_DIST',
            str_contains($t, 'bulk')                           => 'TX_BULK',
            str_contains($t, 'dist')                           => 'TX_DIST',
            default                                            => null,
        };

        return $code && isset($typeIds[$code]) ? (int) $typeIds[$code] : $fallback;
    }

    private function number($value): ?float
    {
        $clean = preg_replace('/[^0-9.\-]/', '', (string) $value);

        return $clean !== '' && is_numeric($clean) ? (float) $clean : null;
    }

    private function note(array $sheet, int $row, string $message): array
    {
        return ['sheet' => $sheet['sheet'], 'row' => $row, 'message' => $message];
    }
}
