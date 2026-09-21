<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use App\Support\IdSequence;
use Illuminate\Validation\Rule;

/**
 * Line length and segment entry.
 *
 * Everything here reads segment_register, which is the working register:
 * 1,325 segments across all seventeen CSCs. It is deliberately NOT the
 * `segments` table, which holds only the fourteen curated graph edges.
 *
 * A CSC routinely has many segments. None of these endpoints collapse
 * them: the roll-ups report a segment_count beside every total, and
 * `segments` returns them one row each.
 */
class NetworkController extends Controller
{
    /** Conductor types live in this asset category. */
    private const CONDUCTOR_CATEGORY = 'Conductor';

    /* ============================== READS ============================= */

    // Length and segment count per area
    public function lineLengthByArea()
    {
        return response()->json(
            DB::table('v_line_length_by_area')->orderByDesc('total_km')->get()
        );
    }

    // Length and segment count per CSC
    public function lineLengthByCsc()
    {
        return response()->json(
            DB::table('v_line_length_by_csc')->orderByDesc('total_km')->get()
        );
    }

    // Length and segment count per feeder
    public function lineLengthByFeeder()
    {
        return response()->json(
            DB::table('v_line_length_by_feeder')->orderByDesc('total_km')->get()
        );
    }

    /**
     * HV line length, grouped at whichever level is asked for.
     *
     * Reads v_segment_csc_share rather than segment_register directly, so
     * a segment crossing a CSC boundary contributes only its own portion
     * to each CSC and to each area. That is the whole reason the share
     * view exists, and it is why province, area and CSC totals here add
     * up to the same number instead of drifting apart.
     *
     * The filters narrow the same query rather than switching to a
     * different one, so a figure never changes meaning depending on which
     * combination is selected.
     */
    public function hvLength(Request $request)
    {
        $v = $request->validate([
            'level'   => ['nullable', Rule::in(['province', 'area', 'csc', 'feeder'])],
            'area_id' => ['nullable', 'string', 'max:12', Rule::exists('areas', 'area_id')],
            'province_id' => ['nullable', 'string', 'max:12', Rule::exists('provinces', 'province_id')],
            'csc_id'  => ['nullable', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],
            'voltage' => ['nullable', Rule::in(['33kV', '11kV', '400V'])],
        ]);

        $level = $v['level'] ?? 'area';

        $base = fn () => DB::table('v_segment_csc_share as s')
            ->join('segment_register as sr', 'sr.segment_register_id', '=', 's.segment_register_id')
            ->join('csc_depots as d', 'd.csc_id', '=', 's.csc_id')
            ->join('areas as a', 'a.area_id', '=', 'd.area_id')
            ->leftJoin('feeders as f', 'f.feeder_id', '=', 'sr.feeder_id')
            ->when(
                $v['area_id'] ?? null,
                fn ($q, $id) => $q->where('a.area_id', $id)
            )
            ->when(
                $v['csc_id'] ?? null,
                fn ($q, $id) => $q->where('d.csc_id', $id)
            )
            ->when(
                $v['province_id'] ?? null,
                fn ($q, $id) => $q->where('a.province_id', $id)
            )
            ->when(
                $v['voltage'] ?? null,
                fn ($q, $volt) => $q->where('sr.voltage_level', $volt)
            );

        $grouping = [
            'province' => [
                ['a.province_id as group_id', 'p.province_name as group_name', 'p.province_name as group_code'],
                ['a.province_id', 'p.province_name'],
            ],
            'area' => [
                ['a.area_id as group_id', 'a.area_name as group_name', 'a.area_code as group_code'],
                ['a.area_id', 'a.area_name', 'a.area_code'],
            ],
            'csc' => [
                ['d.csc_id as group_id', 'd.csc_name as group_name', 'd.csc_code as group_code'],
                ['d.csc_id', 'd.csc_name', 'd.csc_code'],
            ],
            'feeder' => [
                ['f.feeder_id as group_id', 'f.feeder_name as group_name', 'f.feeder_code as group_code'],
                ['f.feeder_id', 'f.feeder_name', 'f.feeder_code'],
            ],
        ];

        [$select, $groupBy] = $grouping[$level];

        $query = $base();

        if ($level === 'province') {
            $query->join('provinces as p', 'p.province_id', '=', 'a.province_id');
        }

        $rows = $query
            ->selectRaw(implode(', ', $select))
            ->selectRaw('COUNT(*) as segment_count')
            ->selectRaw('COALESCE(SUM(s.is_split), 0) as crossing_count')
            ->selectRaw('COUNT(DISTINCT d.csc_id) as csc_count')
            ->selectRaw('COUNT(DISTINCT sr.feeder_id) as feeder_count')
            ->selectRaw('COALESCE(SUM(s.length_km), 0) as total_km')
            ->selectRaw('ROUND(COALESCE(AVG(s.length_km), 0), 3) as mean_km')
            ->selectRaw('COALESCE(MAX(s.length_km), 0) as longest_km')
            ->groupByRaw(implode(', ', $groupBy))
            ->orderByDesc('total_km')
            ->get();

        // Totals come from the same filtered set, so the footer always
        // matches the rows above it.
        $totals = $base()
            ->selectRaw('COUNT(*) as segment_count')
            ->selectRaw('COUNT(DISTINCT s.segment_register_id) as distinct_segments')
            ->selectRaw('COALESCE(SUM(s.is_split), 0) as crossing_count')
            ->selectRaw('COUNT(DISTINCT d.csc_id) as csc_count')
            ->selectRaw('COUNT(DISTINCT a.area_id) as area_count')
            ->selectRaw('COUNT(DISTINCT sr.feeder_id) as feeder_count')
            ->selectRaw('COALESCE(SUM(s.length_km), 0) as total_km')
            ->first();

        return response()->json([
            'level'   => $level,
            'filters' => [
                'area_id' => $v['area_id'] ?? null,
                'csc_id'  => $v['csc_id'] ?? null,
                'voltage' => $v['voltage'] ?? null,
            ],
            'totals'  => $totals,
            'rows'    => $rows,
        ]);
    }

    /** Voltage levels actually present in the register, for the filter. */
    public function voltageLevels()
    {
        return response()->json(
            DB::table('segment_register')
                ->where('status', 'ACTIVE')
                ->select('voltage_level')
                ->distinct()
                ->orderBy('voltage_level')
                ->pluck('voltage_level')
        );
    }

    /** Province totals per asset type, gathered from every placement route. */
    public function assetTotals()
    {
        return response()->json(
            DB::table('v_asset_totals')
                ->orderBy('unit_of_measure')
                ->orderByDesc('total_quantity')
                ->get()
        );
    }

    /** The same assets broken down by the CSC they are assigned to. */
    public function assetsByCsc(Request $request)
    {
        $validated = $request->validate([
            'asset_type_id' => ['nullable', 'string', 'max:12', Rule::exists('asset_types', 'asset_type_id')],
            'csc_id'        => ['nullable', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],
        ]);

        return response()->json(
            DB::table('v_asset_by_csc')
                ->when(
                    $validated['asset_type_id'] ?? null,
                    fn ($q, $id) => $q->where('asset_type_id', $id)
                )
                ->when(
                    $validated['csc_id'] ?? null,
                    fn ($q, $id) => $q->where('csc_id', $id)
                )
                ->orderBy('csc_name')
                ->orderByDesc('total_quantity')
                ->get()
        );
    }

    /**
     * Individual segments, newest first, optionally narrowed.
     *
     * A CSC with three segments returns three rows here. That is the
     * point: the roll-ups above give the total, this gives the parts.
     *
     * Newest first matters for finding something just entered: a segment
     * added through the dashboard is the first row returned, and carries
     * source_file = 'dashboard-entry' so the UI can mark it.
     */
    public function segments(Request $request)
    {
        $validated = $request->validate([
            'csc_id'    => ['nullable', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],
            'area_id'   => ['nullable', 'string', 'max:12', Rule::exists('areas', 'area_id')],
            'feeder_id' => ['nullable', 'string', 'max:12', Rule::exists('feeders', 'feeder_id')],
            'search'    => ['nullable', 'string', 'max:120'],
            'source'    => ['nullable', Rule::in(['all', 'entered', 'imported'])],
            'limit'     => ['nullable', 'integer', 'min:1', 'max:2000'],
        ]);

        $limit = $validated['limit'] ?? 300;

        $rows = DB::table('segment_register as sr')
            ->join('csc_depots as d', 'd.csc_id', '=', 'sr.csc_id')
            ->join('areas as a', 'a.area_id', '=', 'd.area_id')
            ->leftJoin('feeders as f', 'f.feeder_id', '=', 'sr.feeder_id')
            ->when(
                $validated['csc_id'] ?? null,
                fn ($q, $id) => $q->where('sr.csc_id', $id)
            )
            ->when(
                $validated['area_id'] ?? null,
                fn ($q, $id) => $q->where('d.area_id', $id)
            )
            ->when(
                $validated['feeder_id'] ?? null,
                fn ($q, $id) => $q->where('sr.feeder_id', $id)
            )
            /*
             * Free-text find, so a segment just entered can be located by
             * its code without scrolling 1,300 rows.
             */
            ->when(
                trim($validated['search'] ?? '') !== '',
                function ($q) use ($validated) {
                    $term = '%' . trim($validated['search']) . '%';
                    $q->where(function ($w) use ($term) {
                        $w->where('sr.segment_code', 'like', $term)
                          ->orWhere('d.csc_name', 'like', $term)
                          ->orWhere('d.csc_code', 'like', $term)
                          ->orWhere('f.feeder_code', 'like', $term);
                    });
                }
            )
            // 'entered' is anything added through this application, as
            // opposed to the spreadsheet loads the register began as.
            ->when(
                ($validated['source'] ?? 'all') !== 'all',
                fn ($q) => ($validated['source'] === 'entered')
                    ? $q->whereIn('sr.source_file', ['dashboard-entry', 'excel-import'])
                    : $q->where(function ($w) {
                        $w->whereNull('sr.source_file')
                          ->orWhereNotIn('sr.source_file', ['dashboard-entry', 'excel-import']);
                    })
            )
            ->select([
                'sr.segment_register_id',
                'sr.segment_code',
                'sr.length_km',
                'sr.voltage_level',
                'sr.status',
                'sr.remarks',
                'sr.source_file',
                'sr.created_at',
                'd.csc_id',
                'd.csc_code',
                'd.csc_name',
                'a.area_id',
                'a.area_name',
                'f.feeder_id',
                'f.feeder_code',
                'f.feeder_name',
            ])
            ->orderByDesc('sr.segment_register_id')
            ->limit($limit)
            ->get();

        // Attach the per-segment breakdown in one extra query rather than
        // one per row.
        $breakdown = DB::table('segment_asset as sa')
            ->join('asset_types as t', 't.asset_type_id', '=', 'sa.asset_type_id')
            ->whereIn('sa.segment_register_id', $rows->pluck('segment_register_id'))
            ->select([
                'sa.segment_register_id',
                'sa.asset_type_id',
                'sa.quantity',
                'sa.unit_of_measure',
                't.type_name',
            ])
            ->get()
            ->groupBy('segment_register_id');

        // The CSCs a segment runs through, for the ones that cross a
        // boundary. Absent means the segment sits wholly in its own CSC.
        $portions = DB::table('segment_csc as sc')
            ->join('csc_depots as d', 'd.csc_id', '=', 'sc.csc_id')
            ->join('areas as a', 'a.area_id', '=', 'd.area_id')
            ->whereIn('sc.segment_register_id', $rows->pluck('segment_register_id'))
            ->select([
                'sc.segment_register_id',
                'sc.csc_id',
                'sc.length_km',
                'd.csc_code',
                'd.csc_name',
                'a.area_name',
            ])
            ->orderByDesc('sc.length_km')
            ->get()
            ->groupBy('segment_register_id');

        $rows = $rows->map(function ($row) use ($breakdown, $portions) {
            $row->items = $breakdown->get($row->segment_register_id, collect())->values();

            $parts = $portions->get($row->segment_register_id, collect())->values();
            $row->csc_portions = $parts;
            $row->csc_count = $parts->count() > 0 ? $parts->count() : 1;

            return $row;
        });

        return response()->json($rows);
    }

    /**
     * Everything the entry form needs to build its dropdowns, in one call.
     */
    public function formOptions()
    {
        return response()->json([
            'provinces' => DB::table('provinces')
                ->select('province_id', 'province_name')
                ->orderBy('province_name')
                ->get(),

            'areas' => DB::table('areas')
                ->select('area_id', 'province_id', 'area_code', 'area_name')
                ->where('is_active', 1)
                ->orderBy('area_name')
                ->get(),

            'cscs' => DB::table('csc_depots')
                ->select('csc_id', 'area_id', 'csc_code', 'csc_name')
                ->where('is_active', 1)
                ->orderBy('csc_name')
                ->get(),

            'feeders' => DB::table('feeders')
                ->select('feeder_id', 'feeder_code', 'feeder_name', 'origin_csc_id', 'voltage_level')
                ->orderBy('feeder_code')
                ->get(),

            // Split so the form can put conductors on step one and
            // counted items on step two without hard-coding ids.
            'conductorTypes' => $this->assetTypes(self::CONDUCTOR_CATEGORY),
            'countedTypes'   => $this->countedAssetTypes(),

            'voltageLevels' => ['33kV', '11kV', '400V'],
        ]);
    }

    /* ============================== WRITE ============================= */

    /**
     * Records one segment, the CSCs it runs through, and what it carries.
     *
     * WHERE THIS DATA COMES FROM AND WHERE IT LANDS
     *
     *   Screen    HV Length -> Network Register -> "+ HV Length"
     *   File      frontend/src/pages/Dashboard/Components/AddSegmentDialog.jsx
     *   Route     POST /api/network/segments
     *
     *   segment_register   one row, the segment itself
     *     segment_code     <- the Segment code box (unique per CSC)
     *     csc_id           <- DERIVED: the CSC holding the largest share
     *     feeder_id        <- the Feeder dropdown
     *     length_km        <- DERIVED: sum of every CSC portion entered
     *     voltage_level    <- the Voltage dropdown, else 33kV
     *     status           <- the Status dropdown, else ACTIVE
     *     source_file      <- fixed 'dashboard-entry', so entered rows
     *                         can be told apart from imported ones
     *
     *   segment_csc        one row per CSC, ONLY when it crosses a
     *                      boundary (see the comment at the insert)
     *     length_km        <- that CSC's box in the form
     *
     *   segment_asset      one row per line of "what it carries"
     *     quantity         <- the line's Quantity box
     *     unit_of_measure  <- THE ASSET-TYPE CATALOGUE, never the
     *                         request: poles are counted in nos and line
     *                         measured in km, and a request that could
     *                         choose would put km in a column the
     *                         roll-ups add up as a count.
     *
     * The full map for every write in the application is in
     * docs/data-flow.md.
     *
     * A segment may list several CSCs. Each carries the kilometres inside
     * that CSC, and those portions are what the area roll-up sums, so a
     * run crossing from one area into another puts only its own share in
     * each. The register row keeps the largest portion's CSC as its
     * owner, which is what the single csc_id column can express.
     *
     * Wrapped in a transaction: a segment whose portions failed to save
     * would read as wholly owned by one CSC rather than as a failure.
     */
    public function storeSegment(Request $request)
    {
        $data = $request->validate([
            'cscs'             => ['required', 'array', 'min:1', 'max:6'],
            'cscs.*.csc_id'    => ['required', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],
            'cscs.*.length_km' => ['nullable', 'numeric', 'min:0', 'max:100000'],

            'feeder_id'     => ['nullable', 'string', 'max:12', Rule::exists('feeders', 'feeder_id')],
            'segment_code'  => ['required', 'string', 'max:60'],
            'voltage_level' => ['nullable', Rule::in(['33kV', '11kV', '400V'])],
            'status'        => ['nullable', Rule::in(['ACTIVE', 'PLANNED', 'RETIRED'])],
            'remarks'       => ['nullable', 'string', 'max:2000'],

            'items'                 => ['nullable', 'array', 'max:60'],
            'items.*.asset_type_id' => ['required', 'string', 'max:12', Rule::exists('asset_types', 'asset_type_id')],
            'items.*.quantity'      => ['required', 'numeric', 'min:0', 'max:1000000'],
        ]);

        $code = trim($data['segment_code']);

        // Portions, largest first, one per CSC. A CSC named twice is one
        // portion: the lengths are added rather than the second winning.
        $portions = collect($data['cscs'])
            ->groupBy('csc_id')
            ->map(fn ($rows, $cscId) => [
                'csc_id'    => (string) $cscId,
                'length_km' => round($rows->sum(fn ($r) => (float) ($r['length_km'] ?? 0)), 4),
            ])
            ->sortByDesc('length_km')
            ->values();

        $primaryCscId = $portions->first()['csc_id'];
        $totalKm      = round($portions->sum('length_km'), 4);
        $isSplit      = $portions->count() > 1;

        // Segment codes repeat across CSCs in this dataset, so uniqueness
        // is only enforced within the owning CSC.
        $clash = DB::table('segment_register')
            ->where('csc_id', $primaryCscId)
            ->where('segment_code', $code)
            ->exists();

        if ($clash) {
            return response()->json([
                'message' => "Segment {$code} already exists for this CSC.",
                'errors'  => ['segment_code' => ["Segment {$code} already exists for this CSC."]],
            ], 422);
        }

        $items = collect($data['items'] ?? [])
            ->filter(fn ($i) => (float) $i['quantity'] > 0)
            ->values();

        // The unit belongs to the asset type, so it is read from the
        // catalogue rather than taken from the request.
        $units = DB::table('asset_types')
            ->whereIn('asset_type_id', $items->pluck('asset_type_id'))
            ->pluck('unit_of_measure', 'asset_type_id');

        $registerId = DB::transaction(function () use (
            $data, $code, $items, $units, $portions, $primaryCscId, $totalKm, $isSplit
        ) {
            /* The keys are readable codes now (SRG-01328), so the
               database does not hand one out -- id_sequences does, and
               insert() replaces insertGetId(), which only ever worked
               because the column used to be AUTO_INCREMENT. */
            $registerId = IdSequence::next('segment_register');

            DB::table('segment_register')->insert([
                'segment_register_id' => $registerId,
                'csc_id'        => $primaryCscId,
                'feeder_id'     => $data['feeder_id'] ?? null,
                'segment_id'    => null,
                'segment_code'  => $code,
                'length_km'     => $totalKm,
                'voltage_level' => $data['voltage_level'] ?? '33kV',
                'status'        => $data['status'] ?? 'ACTIVE',
                'remarks'       => $data['remarks'] ?? null,
                'source_file'   => 'dashboard-entry',
                'created_at'    => now(),
                'updated_at'    => now(),
            ]);

            /*
             * Only a crossing segment gets portion rows. Writing a single
             * portion for a segment wholly inside one CSC would duplicate
             * what the register row already says, and v_segment_csc_share
             * falls back to the register row precisely when no portions
             * exist.
             */
            if ($isSplit) {
                foreach ($portions as $portion) {
                    DB::table('segment_csc')->insert([
                        'segment_csc_id'      => IdSequence::next('segment_csc'),
                        'segment_register_id' => $registerId,
                        'csc_id'      => $portion['csc_id'],
                        'length_km'   => $portion['length_km'],
                        'created_at'  => now(),
                        'updated_at'  => now(),
                    ]);
                }
            }

            foreach ($items as $item) {
                DB::table('segment_asset')->insert([
                    'segment_asset_id'  => IdSequence::next('segment_asset'),
                    'segment_register_id'     => $registerId,
                    'asset_type_id'   => $item['asset_type_id'],
                    'quantity'        => $item['quantity'],
                    'unit_of_measure' => $units[$item['asset_type_id']] ?? 'nos',
                    'created_at'      => now(),
                    'updated_at'      => now(),
                ]);
            }

            return $registerId;
        });

        return response()->json([
            'message' => $isSplit
                ? "Segment {$code} saved across {$portions->count()} CSCs."
                : "Segment {$code} saved.",
            'segment_register_id'  => $registerId,
            'total_km'     => $totalKm,
            'csc_portions' => $portions->count(),
            'items_saved'  => $items->count(),
        ], 201);
    }

    /* ============================= HELPERS ============================ */

    private function assetTypes(string $categoryName)
    {
        return DB::table('asset_types as t')
            ->join('asset_categories as c', 'c.category_id', '=', 't.category_id')
            ->where('c.category_name', $categoryName)
            ->select('t.asset_type_id', 't.type_name', 't.unit_of_measure', 'c.category_name')
            ->orderBy('t.asset_type_id')
            ->get();
    }

    private function countedAssetTypes()
    {
        return DB::table('asset_types as t')
            ->leftJoin('asset_categories as c', 'c.category_id', '=', 't.category_id')
            ->where('t.unit_of_measure', 'nos')
            ->select('t.asset_type_id', 't.type_name', 't.unit_of_measure', 'c.category_name')
            /*
             * By id, not by category name. The ids are already grouped by
             * category and run in the order an engineer thinks about the
             * network: substations, transformers, switchgear, poles, then
             * the one-off plant. Sorting alphabetically instead buries
             * switchgear under "Boundary Meter".
             */
            ->orderBy('t.asset_type_id')
            ->get();
    }
}
