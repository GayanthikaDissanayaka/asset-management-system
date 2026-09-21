<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use App\Support\IdSequence;
use Illuminate\Validation\Rule;

/**
 * The asset explorer.
 *
 * Everything here reads v_asset_register, which is one flat row per
 * asset record with its full place and full classification. Six
 * endpoints group that one view six ways -- totals, categories, types,
 * places, individual records -- so no two answers on the page can
 * disagree about what the province holds.
 *
 * Before v_asset_register existed the roll-ups saw 61 records, because
 * they read the `assets` table alone and the province keeps its real
 * data in `transformers` (1,717) and `switchgear` (1,355). The view
 * gathers all three registers. See database/add_asset_explorer_views.sql.
 *
 * UNITS. asset_types measures poles in `nos` and conductor in `km`, and
 * both arrive in the same quantity column. Every total here is reported
 * per unit_of_measure and never as one number, because a count of poles
 * added to a length of line is not a quantity of anything.
 */
class AssetExplorerController extends Controller
{
    /* ============================== READS ============================= */

    /**
     * The headline figures for whatever is currently filtered.
     *
     * Records and quantities are different questions and both are asked:
     * one `assets` row can carry forty poles, so 14 pole records are 186
     * poles.
     */
    public function summary(Request $request)
    {
        $filters = $this->filters($request);

        $byUnit = $this->scoped($filters)
            ->select('unit_of_measure')
            ->selectRaw('COUNT(*) AS records')
            ->selectRaw('SUM(quantity) AS quantity')
            ->groupBy('unit_of_measure')
            ->orderBy('unit_of_measure')
            ->get();

        $spread = $this->scoped($filters)
            ->selectRaw('COUNT(*) AS records')
            ->selectRaw('COUNT(DISTINCT csc_id)      AS csc_count')
            ->selectRaw('COUNT(DISTINCT area_id)     AS area_count')
            ->selectRaw('COUNT(DISTINCT category_id) AS category_count')
            ->selectRaw('COUNT(DISTINCT asset_type_id) AS type_count')
            ->first();

        // Named separately because they are what the province is asked
        // about most, and because both are whole registers of their own.
        $registers = $this->scoped($filters)
            ->whereIn('category_name', ['Transformer', 'Switchgear'])
            ->select('category_name')
            ->selectRaw('SUM(quantity) AS quantity')
            ->groupBy('category_name')
            ->pluck('quantity', 'category_name');

        return response()->json([
            'records'        => (int) ($spread->records ?? 0),
            'csc_count'      => (int) ($spread->csc_count ?? 0),
            'area_count'     => (int) ($spread->area_count ?? 0),
            'category_count' => (int) ($spread->category_count ?? 0),
            'type_count'     => (int) ($spread->type_count ?? 0),
            'by_unit'        => $byUnit,
            'counted_units'  => (float) ($byUnit->firstWhere('unit_of_measure', 'nos')->quantity ?? 0),
            'line_km'        => (float) ($byUnit->firstWhere('unit_of_measure', 'km')->quantity ?? 0),
            'transformers'   => (float) ($registers['Transformer'] ?? 0),
            'switchgear'     => (float) ($registers['Switchgear'] ?? 0),
        ]);
    }

    /**
     * Categories, each carrying the types inside it.
     *
     * This is the drill-down in one payload: the page draws a card per
     * category, and opening one reveals its types without a second
     * request. Two round trips would let the card and its contents be
     * filtered differently for a moment, and show a category whose types
     * did not add up to it.
     *
     * A category with nothing in it is still returned, so the list is a
     * catalogue of what can be recorded rather than only what has been.
     */
    public function catalog(Request $request)
    {
        $filters = $this->filters($request);

        $rows = $this->scoped($filters)
            ->select([
                'category_id', 'category_name', 'category_order',
                'asset_type_id', 'type_code', 'type_name', 'type_order',
                'unit_of_measure',
            ])
            ->selectRaw('COUNT(*) AS records')
            ->selectRaw('SUM(quantity) AS quantity')
            ->selectRaw('COUNT(DISTINCT csc_id) AS csc_count')
            ->selectRaw('COUNT(DISTINCT area_id) AS area_count')
            ->groupBy(
                'category_id', 'category_name', 'category_order',
                'asset_type_id', 'type_code', 'type_name', 'type_order',
                'unit_of_measure'
            )
            ->get();

        /*
         * The per-category distinct counts, asked of the database rather
         * than folded up from the type rows above.
         *
         * A category spread over ten CSCs through several types is in
         * ten CSCs, but no single type need be in more than three, so
         * taking the largest type's figure would report three. Only the
         * database can answer a COUNT(DISTINCT) across the group.
         */
        $perCategory = $this->scoped($filters)
            ->select('category_id')
            ->selectRaw('COUNT(DISTINCT csc_id) AS csc_count')
            ->selectRaw('COUNT(DISTINCT area_id) AS area_count')
            ->selectRaw('COUNT(DISTINCT asset_type_id) AS type_count')
            ->groupBy('category_id')
            ->get()
            ->keyBy('category_id');

        // Types that exist in the catalogue but hold nothing under the
        // current filters, so a CSC with no reclosers says "0 reclosers"
        // instead of leaving the reader to notice the absence.
        $empty = DB::table('asset_types as t')
            ->join('asset_categories as c', 'c.category_id', '=', 't.category_id')
            ->where('t.is_active', 1)
            ->whereNotIn('t.asset_type_id', $rows->pluck('asset_type_id')->filter()->all() ?: [0])
            ->select([
                'c.category_id', 'c.category_name',
                'c.display_order as category_order',
                't.asset_type_id', 't.type_code', 't.type_name',
                't.display_order as type_order', 't.unit_of_measure',
            ])
            ->selectRaw('0 AS records')
            ->selectRaw('0 AS quantity')
            ->selectRaw('0 AS csc_count')
            ->selectRaw('0 AS area_count')
            ->get();

        $categories = $rows->concat($empty)
            ->groupBy('category_id')
            ->map(function ($types, $categoryId) use ($perCategory) {
                $first = $types->first();
                $agg   = $perCategory[$categoryId] ?? null;

                return [
                    'category_id'   => (string) $categoryId,
                    'category_name' => $first->category_name,
                    'order'         => (int) $first->category_order,
                    'records'       => (int) $types->sum('records'),
                    'csc_count'     => (int) ($agg->csc_count ?? 0),
                    'area_count'    => (int) ($agg->area_count ?? 0),

                    // Every type the catalogue defines for this category,
                    // including the ones holding nothing — the card is a
                    // list of what can be recorded, not only what has been.
                    'type_count'    => $types->count(),

                    // Per unit, never one number. A category can hold two
                    // units at once: Power Line is km, but the same card
                    // must not imply its km and a neighbour's nos add up.
                    'by_unit' => $types
                        ->groupBy('unit_of_measure')
                        ->map(fn ($g, $unit) => [
                            'unit_of_measure' => $unit,
                            'quantity'        => (float) $g->sum('quantity'),
                            'records'         => (int) $g->sum('records'),
                        ])
                        ->values(),

                    'types' => $types
                        ->sortBy([['type_order', 'asc'], ['type_name', 'asc']])
                        ->map(fn ($t) => [
                            'asset_type_id'   => (string) $t->asset_type_id,
                            'type_code'       => $t->type_code,
                            'type_name'       => $t->type_name,
                            'unit_of_measure' => $t->unit_of_measure,
                            'records'         => (int) $t->records,
                            'quantity'        => (float) $t->quantity,
                            'csc_count'       => (int) $t->csc_count,
                            'area_count'      => (int) $t->area_count,
                        ])
                        ->values(),
                ];
            })
            ->sortBy([['order', 'asc'], ['category_name', 'asc']])
            ->values();

        return response()->json($categories);
    }

    /**
     * The same assets grouped by place, at whichever level is asked for.
     *
     * province / area / csc. The totals reconcile across all three
     * because every level groups the same filtered view -- an asset
     * belongs to exactly one CSC, so unlike line length there is no
     * share to apportion.
     */
    public function breakdown(Request $request)
    {
        $validated = $request->validate([
            'level' => ['nullable', Rule::in(['province', 'area', 'csc'])],
        ]);

        $level = $validated['level'] ?? 'csc';

        [$idColumn, $nameColumn, $codeColumn] = match ($level) {
            'province' => ['province_id', 'province_name', 'province_name'],
            'area'     => ['area_id', 'area_name', 'area_code'],
            default    => ['csc_id', 'csc_name', 'csc_code'],
        };

        $filters = $this->filters($request);

        /*
         * Two queries, because the two questions group differently.
         *
         * Quantities must be split by unit, or poles and kilometres end
         * up in one column. Distinct counts must NOT be, because a place
         * holding 22 counted types and 3 measured types holds 25 types,
         * and taking the larger of the two sub-totals would report 22.
         * The same trap applies to any COUNT(DISTINCT) folded up in PHP.
         */
        $perPlace = $this->scoped($filters)
            ->select([
                "{$idColumn} as group_id",
                "{$nameColumn} as group_name",
                "{$codeColumn} as group_code",
            ])
            ->selectRaw('COUNT(*) AS records')
            ->selectRaw('COUNT(DISTINCT asset_type_id) AS type_count')
            ->groupBy('group_id', 'group_name', 'group_code')
            ->get()
            ->keyBy('group_id');

        $perUnit = $this->scoped($filters)
            ->select(["{$idColumn} as group_id", 'unit_of_measure'])
            ->selectRaw('SUM(quantity) AS quantity')
            ->groupBy('group_id', 'unit_of_measure')
            ->get()
            ->groupBy('group_id');

        $places = $perPlace
            ->map(function ($place, $groupId) use ($perUnit) {
                $units = $perUnit[$groupId] ?? collect();

                return [
                    'group_id'    => (int) $groupId,
                    'group_name'  => $place->group_name,
                    'group_code'  => $place->group_code,
                    'records'     => (int) $place->records,
                    'type_count'  => (int) $place->type_count,
                    'counted_qty' => (float) $units->where('unit_of_measure', 'nos')->sum('quantity'),
                    'line_km'     => (float) $units->where('unit_of_measure', 'km')->sum('quantity'),
                ];
            })
            ->sortByDesc('records')
            ->values();

        return response()->json([
            'level' => $level,
            'rows'  => $places,
        ]);
    }

    /**
     * Individual asset records -- "view all assets".
     *
     * Paged, because the unfiltered answer is over three thousand rows
     * and sending them all would make the browser do the filtering the
     * database has already done.
     */
    public function records(Request $request)
    {
        $validated = $request->validate([
            'page'  => ['nullable', 'integer', 'min:1'],
            'limit' => ['nullable', 'integer', 'min:1', 'max:500'],
            'sort'  => ['nullable', Rule::in(['recorded_at', 'quantity', 'asset_code', 'type_name', 'csc_name'])],
            'dir'   => ['nullable', Rule::in(['asc', 'desc'])],
        ]);

        $filters = $this->filters($request);
        $limit   = $validated['limit'] ?? 50;
        $page    = $validated['page'] ?? 1;
        $sort    = $validated['sort'] ?? 'recorded_at';
        $dir     = $validated['dir'] ?? 'desc';

        $total = $this->scoped($filters)->count();

        $rows = $this->scoped($filters)
            ->select([
                'source', 'source_id', 'asset_code', 'attached_to', 'attached_ref',
                'quantity', 'unit_of_measure', 'capacity_kva', 'condition_status',
                'recorded_at', 'asset_type_id', 'type_name', 'category_id',
                'category_name', 'csc_id', 'csc_code', 'csc_name',
                'area_id', 'area_name', 'province_name',
            ])
            ->orderBy($sort, $dir)
            // A stable tiebreak, or two records sharing a timestamp can
            // swap places between pages and one of them is never seen.
            ->orderBy('source')
            ->orderBy('source_id')
            ->forPage($page, $limit)
            ->get();

        return response()->json([
            'rows'      => $rows,
            'total'     => $total,
            'page'      => $page,
            'limit'     => $limit,
            'last_page' => max(1, (int) ceil($total / $limit)),
        ]);
    }

    /** Everything the filters and the add form need to draw themselves. */
    public function options()
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

            'categories' => DB::table('asset_categories')
                ->select('category_id', 'category_code', 'category_name')
                ->where('is_active', 1)
                ->orderBy('display_order')
                ->get(),

            'types' => DB::table('asset_types as t')
                ->join('asset_categories as c', 'c.category_id', '=', 't.category_id')
                ->where('t.is_active', 1)
                ->select([
                    't.asset_type_id', 't.category_id', 't.type_code', 't.type_name',
                    't.unit_of_measure', 't.allow_decimal', 'c.category_name',
                ])
                ->orderBy('c.display_order')
                ->orderBy('t.display_order')
                ->get(),

            'conditions' => ['NEW', 'GOOD', 'FAIR', 'POOR', 'FAULTY', 'UNKNOWN'],
        ]);
    }

    /**
     * The asset catalogue, straight from `asset_categories` and
     * `asset_types`.
     *
     * The other reads start from what has been recorded and describe the
     * classification as a side effect, so a type nobody has entered
     * simply does not appear. This one starts from the two reference
     * tables, so every category and every type the database defines is
     * listed whether or not anything has been recorded against it, and
     * the holdings are joined on.
     *
     * That is the difference between "here is what we have" and "here is
     * everything we can record, and how much of each we have" — the
     * second is what tells a reader that the province holds no Zebra
     * conductor at all, rather than leaving them to notice a gap.
     */
    public function typeCatalogue(Request $request)
    {
        $filters = $this->filters($request);

        // What is actually held, per type, under the current filters.
        $held = $this->scoped($filters)
            ->select('asset_type_id')
            ->selectRaw('COUNT(*) AS records')
            ->selectRaw('SUM(quantity) AS quantity')
            ->selectRaw('COUNT(DISTINCT csc_id) AS csc_count')
            ->selectRaw('COUNT(DISTINCT area_id) AS area_count')
            ->groupBy('asset_type_id')
            ->get()
            ->keyBy('asset_type_id');

        $rows = DB::table('asset_types as t')
            ->join('asset_categories as c', 'c.category_id', '=', 't.category_id')
            ->select([
                't.asset_type_id', 't.type_code', 't.type_name',
                't.unit_of_measure', 't.is_line_asset', 't.rated_kva',
                't.allow_decimal', 't.is_active',
                't.display_order as type_order',
                'c.category_id', 'c.category_code', 'c.category_name',
                'c.display_order as category_order',
            ])
            ->orderBy('c.display_order')
            ->orderBy('c.category_id')
            ->orderBy('t.display_order')
            ->orderBy('t.asset_type_id')
            ->get()
            ->map(function ($t) use ($held) {
                $h = $held[$t->asset_type_id] ?? null;

                return [
                    'asset_type_id'   => (string) $t->asset_type_id,
                    'type_code'       => $t->type_code,
                    'type_name'       => $t->type_name,
                    'unit_of_measure' => $t->unit_of_measure,
                    'is_line_asset'   => (bool) $t->is_line_asset,
                    'allow_decimal'   => (bool) $t->allow_decimal,
                    'rated_kva'       => $t->rated_kva !== null ? (int) $t->rated_kva : null,
                    'is_active'       => (bool) $t->is_active,
                    'category_id'     => (string) $t->category_id,
                    'category_code'   => $t->category_code,
                    'category_name'   => $t->category_name,

                    'records'    => (int) ($h->records ?? 0),
                    'quantity'   => (float) ($h->quantity ?? 0),
                    'csc_count'  => (int) ($h->csc_count ?? 0),
                    'area_count' => (int) ($h->area_count ?? 0),
                ];
            });

        return response()->json([
            'rows' => $rows->values(),

            'category_count' => $rows->pluck('category_id')->unique()->count(),
            'type_count'     => $rows->count(),

            // Per unit, never one number: `nos` and `km` do not add.
            'totals' => $rows
                ->groupBy('unit_of_measure')
                ->map(fn ($g, $unit) => [
                    'unit_of_measure' => $unit,
                    'types'           => $g->count(),
                    'records'         => (int) $g->sum('records'),
                    'quantity'        => (float) $g->sum('quantity'),
                ])
                ->values(),
        ]);
    }

    /**
     * The usage log: every asset entry made through the application.
     *
     * Reads v_assets_used, which is history rather than current state.
     * `assets` says what a place has now; this says what was put in and
     * when, and is never edited. Asking the first "what did we issue to
     * Welimada in March" cannot work, because a corrected quantity
     * overwrites the figure it corrected.
     */
    public function used(Request $request)
    {
        $validated = $request->validate([
            'csc_id'        => ['nullable', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],
            'area_id'       => ['nullable', 'string', 'max:12', Rule::exists('areas', 'area_id')],
            'asset_type_id' => ['nullable', 'string', 'max:12', Rule::exists('asset_types', 'asset_type_id')],
            'batch_ref'     => ['nullable', 'string', 'size:32'],
            'limit'         => ['nullable', 'integer', 'min:1', 'max:500'],
            'page'          => ['nullable', 'integer', 'min:1'],
        ]);

        $base = fn () => DB::table('v_assets_used')
            ->when($validated['csc_id'] ?? null, fn ($q, $v) => $q->where('csc_id', $v))
            ->when($validated['area_id'] ?? null, fn ($q, $v) => $q->where('area_id', $v))
            ->when($validated['asset_type_id'] ?? null, fn ($q, $v) => $q->where('asset_type_id', $v))
            ->when($validated['batch_ref'] ?? null, fn ($q, $v) => $q->where('batch_ref', $v));

        $limit = $validated['limit'] ?? 50;
        $page  = $validated['page'] ?? 1;

        return response()->json([
            'rows' => $base()
                ->orderByDesc('recorded_at')
                ->orderByDesc('asset_usage_id')
                ->forPage($page, $limit)
                ->get(),

            'total' => $base()->count(),

            // Per unit, never one number.
            'totals' => $base()
                ->select('unit_of_measure')
                ->selectRaw('COUNT(*) AS entries')
                ->selectRaw('SUM(quantity) AS quantity')
                ->groupBy('unit_of_measure')
                ->get(),

            'page'  => $page,
            'limit' => $limit,
        ]);
    }

    /* ========================== TRANSFORMERS ========================== */

    /**
     * Find a transformer by name or by number.
     *
     * "Name or ID" covers five different things in this data, and an
     * engineer holding a paper record does not know which one they have:
     * the numeric id, the old SIN, the new SIN, the works number, or the
     * substation name. All five are matched.
     *
     * An exact hit on any identifier is returned first, so typing a
     * complete SIN number lands on that transformer rather than on
     * whatever else happens to contain those characters.
     */
    public function searchTransformers(Request $request)
    {
        $validated = $request->validate([
            'q'     => ['required', 'string', 'min:1', 'max:120'],
            'limit' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);

        $term = trim($validated['q']);
        $like = '%' . str_replace(['%', '_'], ['\%', '\_'], $term) . '%';

        $rows = DB::table('v_transformer_detail')
            ->where(function ($q) use ($like, $term) {
                $q->where('old_sin_no', 'like', $like)
                  ->orWhere('new_sin_no', 'like', $like)
                  ->orWhere('transformer_no', 'like', $like)
                  ->orWhere('substation_name', 'like', $like);

                if (ctype_digit($term)) {
                    $q->orWhere('transformer_id', (string) $term);
                }
            })
            ->select([
                'transformer_id', 'old_sin_no', 'new_sin_no', 'transformer_no',
                'substation_name', 'transformer_type', 'type_name', 'capacity_kva',
                'condition_status', 'status', 'csc_id', 'csc_name', 'csc_code',
                'area_name', 'province_name',
            ])
            // Exact identifier matches first, then substation name, then
            // the rest of the partial matches.
            ->orderByRaw(
                '(old_sin_no = ? OR new_sin_no = ? OR transformer_no = ? OR transformer_id = ?) DESC',
                [$term, $term, $term, ctype_digit($term) ? (int) $term : -1]
            )
            ->orderByRaw('(substation_name = ?) DESC', [$term])
            ->orderBy('substation_name')
            ->limit($validated['limit'] ?? 25)
            ->get();

        return response()->json([
            'query' => $term,
            'count' => $rows->count(),
            'rows'  => $rows,
        ]);
    }

    /**
     * The transformers in a place, with their serial numbers.
     *
     * For the dashboard's Transformers tile: clicking it lists the units
     * behind the number. Active transformers only, paged, narrowed by the
     * same province / area / CSC as the rest of the dashboard.
     */
    public function listTransformers(Request $request)
    {
        $v = $request->validate([
            'province_id' => ['nullable', 'string', 'max:12', Rule::exists('provinces', 'province_id')],
            'area_id'     => ['nullable', 'string', 'max:12', Rule::exists('areas', 'area_id')],
            'csc_id'      => ['nullable', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],
            'search'      => ['nullable', 'string', 'max:120'],
            'page'        => ['nullable', 'integer', 'min:1'],
            'limit'       => ['nullable', 'integer', 'min:1', 'max:200'],
        ]);

        $base = fn () => DB::table('v_transformer_detail')
            ->where('status', 'ACTIVE')
            ->when($v['province_id'] ?? null, fn ($q, $id) => $q->where('province_id', $id))
            ->when($v['area_id'] ?? null, fn ($q, $id) => $q->where('area_id', $id))
            ->when($v['csc_id'] ?? null, fn ($q, $id) => $q->where('csc_id', $id))
            ->when(trim($v['search'] ?? '') !== '', function ($q) use ($v) {
                $term = '%' . trim($v['search']) . '%';
                $q->where(fn ($w) => $w->where('old_sin_no', 'like', $term)
                    ->orWhere('new_sin_no', 'like', $term)
                    ->orWhere('transformer_no', 'like', $term)
                    ->orWhere('substation_name', 'like', $term)
                    ->orWhere('manufacturer', 'like', $term));
            });

        $limit = $v['limit'] ?? 50;
        $page  = $v['page'] ?? 1;
        $total = $base()->count();

        return response()->json([
            'total'     => $total,
            'page'      => $page,
            'limit'     => $limit,
            'last_page' => max(1, (int) ceil($total / $limit)),
            'rows'      => $base()
                ->orderBy('csc_name')
                ->orderBy('substation_name')
                ->forPage($page, $limit)
                ->get([
                    'transformer_id', 'old_sin_no', 'new_sin_no', 'transformer_no',
                    'manufacturer', 'substation_name', 'transformer_type', 'type_name',
                    'capacity_kva', 'condition_status', 'csc_name', 'area_name',
                ]),
        ]);
    }

    /**
     * One transformer in full, with the segments that name it and what
     * else its CSC holds.
     */
    public function showTransformer(string $transformer)
    {
        $row = DB::table('v_transformer_detail')
            ->where('transformer_id', $transformer)
            ->first();

        if (! $row) {
            return response()->json([
                'message' => "No transformer with id {$transformer}.",
            ], 404);
        }

        // The register segments that name this unit. transformer_ref is
        // kept beside the id because some links were matched by
        // reference text and never resolved to a row.
        $segments = DB::table('segment_transformer as st')
            ->join('segment_register as sr', 'sr.segment_register_id', '=', 'st.segment_register_id')
            ->leftJoin('feeders as f', 'f.feeder_id', '=', 'sr.feeder_id')
            ->where('st.transformer_id', $transformer)
            ->select([
                'sr.segment_register_id', 'sr.segment_code', 'sr.length_km',
                'sr.voltage_level', 'sr.status',
                'f.feeder_code', 'f.feeder_name',
                'st.transformer_ref',
            ])
            ->orderBy('sr.segment_code')
            ->get();

        // What the transformer sits among, so the detail answers "where
        // is it" with a place rather than only a name.
        $neighbourhood = DB::table('v_asset_register')
            ->where('csc_id', $row->csc_id)
            ->select('category_name', 'unit_of_measure')
            ->selectRaw('COUNT(*) AS records')
            ->selectRaw('SUM(quantity) AS quantity')
            ->groupBy('category_name', 'unit_of_measure')
            ->orderByDesc('records')
            ->get();

        return response()->json([
            'transformer'  => $row,
            'segments'     => $segments,
            'csc_holdings' => $neighbourhood,
        ]);
    }

    /* ============================== WRITE ============================= */

    /**
     * Records assets against a place, and reports what that place now
     * holds.
     *
     * The summary is the point of the endpoint, not a courtesy. Somebody
     * entering forty poles for Welimada wants to know what Welimada has
     * after the entry, and going back to a list to work that out is how
     * the same forty poles get entered twice.
     *
     * Written as `assets` rows carrying csc_id, which is the fourth
     * placement branch in v_asset_placement. They appear in every total
     * on this page, in the CSC breakdown, and in the exported report,
     * immediately -- the views read them, so nothing has to be
     * recalculated.
     *
     * Transactional. A half-saved batch would report a place total that
     * never existed.
     *
     * WHERE THIS DATA COMES FROM AND WHERE IT LANDS
     *
     *   Screen    Assets -> "+ Add assets"
     *   File      frontend/src/pages/Assets/AddAssetsDialog.jsx
     *   Route     POST /api/network/assets/records
     *
     *   assets             CURRENT STATE, edited later. One row per line
     *                      of the form.
     *     asset_code       <- GENERATED {csc_code}-{type_code}-{n}
     *     asset_type_id    <- the line's Asset type dropdown
     *     csc_id           <- the CSC dropdown (one for the whole form)
     *     quantity         <- the line's Quantity box
     *     unit_of_measure  <- THE ASSET-TYPE CATALOGUE, never the request
     *     capacity_kva     <- the line's kVA box, where the type has one
     *     condition_status <- the line's Condition dropdown, else UNKNOWN
     *     install_date     <- the form footer, shared by every line
     *     remarks          <- the form footer, shared by every line
     *     status           <- fixed ACTIVE
     *     created_by       <- the signed-in user
     *     updated_by       <- the signed-in user
     *     node_id          <- NULL: this route records holdings, not
     *     segment_id       <- NULL: where a thing physically sits
     *
     *   assets_used        HISTORY, never edited. The same figures again,
     *                      plus batch_ref (one reference for the whole
     *                      submission) and recorded_by. Written in the
     *                      same transaction, so the two cannot disagree
     *                      about what was entered.
     *
     * The full map for every write in the application is in
     * docs/data-flow.md.
     */
    public function storeRecords(Request $request)
    {
        $data = $request->validate([
            'csc_id' => ['required', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],

            'items'                   => ['required', 'array', 'min:1', 'max:40'],
            'items.*.asset_type_id'   => ['required', 'string', 'max:12', Rule::exists('asset_types', 'asset_type_id')],
            'items.*.quantity'        => ['required', 'numeric', 'min:0.001', 'max:100000'],
            'items.*.capacity_kva'    => ['nullable', 'numeric', 'min:0', 'max:1000000'],
            'items.*.condition_status' => ['nullable', Rule::in(['NEW', 'GOOD', 'FAIR', 'POOR', 'FAULTY', 'UNKNOWN'])],

            'install_date' => ['nullable', 'date'],
            'remarks'      => ['nullable', 'string', 'max:500'],
        ]);

        $csc = DB::table('csc_depots as d')
            ->join('areas as a', 'a.area_id', '=', 'd.area_id')
            ->join('provinces as p', 'p.province_id', '=', 'a.province_id')
            ->where('d.csc_id', $data['csc_id'])
            ->select([
                'd.csc_id', 'd.csc_code', 'd.csc_name',
                'a.area_id', 'a.area_name', 'p.province_name',
            ])
            ->first();

        /*
         * Collapse repeated lines before writing. Two lines of RC poles
         * in one submission is one holding of RC poles, and keeping them
         * apart would make the place read as having two pole records.
         *
         * Condition and capacity are part of the grouping key, not
         * something merged away: 40 NEW poles and 5 POOR poles are two
         * different holdings, and folding them into 45 NEW would invent
         * a condition for five poles nobody claimed.
         */
        $items = collect($data['items'])
            ->groupBy(fn ($item) => implode('|', [
                $item['asset_type_id'],
                $item['condition_status'] ?? 'UNKNOWN',
                $item['capacity_kva'] ?? '',
            ]))
            ->map(fn ($group) => [
                'asset_type_id'    => (string) $group->first()['asset_type_id'],
                'quantity'         => (float) $group->sum('quantity'),
                'capacity_kva'     => $group->first()['capacity_kva'] ?? null,
                'condition_status' => $group->first()['condition_status'] ?? 'UNKNOWN',
            ])
            ->values();

        $types = DB::table('asset_types as t')
            ->leftJoin('asset_categories as c', 'c.category_id', '=', 't.category_id')
            ->whereIn('t.asset_type_id', $items->pluck('asset_type_id'))
            ->select([
                't.asset_type_id', 't.type_code', 't.type_name',
                't.unit_of_measure', 't.allow_decimal', 'c.category_name',
            ])
            ->get()
            ->keyBy('asset_type_id');

        // A count of poles is a whole number. Accepting 3.5 reclosers
        // would put a quantity in the register that cannot be verified
        // against anything in the field.
        foreach ($items as $item) {
            $type = $types[$item['asset_type_id']];
            if (! $type->allow_decimal && fmod($item['quantity'], 1.0) !== 0.0) {
                return response()->json([
                    'message' => "{$type->type_name} is counted in whole {$type->unit_of_measure}; "
                        . "{$item['quantity']} is not a whole number.",
                ], 422);
            }
        }

        $userId = $request->user()?->getKey();

        /* One reference for the whole submission, so the lines of a
           single entry can be read back as the one act they were rather
           than as unrelated rows sharing a timestamp. */
        $batchRef = bin2hex(random_bytes(16));

        $saved = DB::transaction(function () use ($items, $types, $csc, $data, $userId, $batchRef) {
            $written = [];

            foreach ($items as $item) {
                $type = $types[$item['asset_type_id']];

                $assetId = IdSequence::next('assets');

                DB::table('assets')->insert([
                    'asset_id'         => $assetId,
                    'asset_code'       => $this->nextAssetCode($csc->csc_code, $type->type_code),
                    'asset_type_id'    => $item['asset_type_id'],
                    'csc_id'           => $csc->csc_id,
                    'node_id'          => null,
                    'segment_id'       => null,
                    'quantity'         => $item['quantity'],
                    'unit_of_measure'  => $type->unit_of_measure,
                    'capacity_kva'     => $item['capacity_kva'],
                    'install_date'     => $data['install_date'] ?? null,
                    'condition_status' => $item['condition_status'],
                    'status'           => 'ACTIVE',
                    'remarks'          => $data['remarks'] ?? null,
                    'created_by'       => $userId,
                    'updated_by'       => $userId,
                ]);

                /*
                 * The same entry in the usage log.
                 *
                 * `assets` is current state and gets edited; this is
                 * history and never does. Written in the same
                 * transaction so the two cannot disagree about what was
                 * entered — a log missing an entry that happened would
                 * be worse than no log.
                 */
                DB::table('assets_used')->insert([
                    'asset_usage_id'   => IdSequence::next('assets_used'),
                    'asset_id'         => $assetId,
                    'asset_type_id'    => $item['asset_type_id'],
                    'csc_id'           => $csc->csc_id,
                    'area_id'          => $csc->area_id,
                    'quantity'         => $item['quantity'],
                    'unit_of_measure'  => $type->unit_of_measure,
                    'condition_status' => $item['condition_status'],
                    'capacity_kva'     => $item['capacity_kva'],
                    'used_on'          => $data['install_date'] ?? null,
                    'used_for'         => $data['remarks'] ?? null,
                    'batch_ref'        => $batchRef,
                    'recorded_by'      => $userId,
                ]);

                $written[] = [
                    'asset_id'        => $assetId,
                    'asset_type_id'   => (string) $item['asset_type_id'],
                    'type_name'       => $type->type_name,
                    'category_name'   => $type->category_name ?? 'Unclassified',
                    'quantity'        => (float) $item['quantity'],
                    'unit_of_measure' => $type->unit_of_measure,
                ];
            }

            return $written;
        });

        return response()->json([
            // "Records", not "types" — one type recorded in two
            // conditions is two records, and saying "2 asset types"
            // would misdescribe what was written.
            'message' => count($saved) === 1
                ? "Saved to {$csc->csc_name} CSC."
                : count($saved) . " records saved to {$csc->csc_name} CSC.",

            'place' => [
                'csc_id'        => (string) $csc->csc_id,
                'csc_code'      => $csc->csc_code,
                'csc_name'      => $csc->csc_name,
                'area_id'       => (string) $csc->area_id,
                'area_name'     => $csc->area_name,
                'province_name' => $csc->province_name,
            ],

            // What this entry added.
            'added'        => $saved,
            'added_totals' => collect($saved)
                ->groupBy('unit_of_measure')
                ->map(fn ($g, $unit) => [
                    'unit_of_measure' => $unit,
                    'quantity'        => (float) $g->sum('quantity'),
                ])
                ->values(),

            // What the place holds now, which is the figure worth
            // checking before entering anything else.
            'place_totals'     => $this->placeTotals($csc->csc_id),
            'place_categories' => $this->placeCategories($csc->csc_id),

            // The usage-log reference for this submission, so the entry
            // can be found again as one act.
            'batch_ref'        => $batchRef,
        ], 201);
    }

    /* ============================= HELPERS ============================ */

    /** Reads the filter parameters every endpoint above understands. */
    private function filters(Request $request): array
    {
        return $request->validate([
            'province_id'   => ['nullable', 'string', 'max:12', Rule::exists('provinces', 'province_id')],
            'area_id'       => ['nullable', 'string', 'max:12', Rule::exists('areas', 'area_id')],
            'csc_id'        => ['nullable', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],
            'category_id'   => ['nullable', 'string', 'max:12'],
            'asset_type_id' => ['nullable', 'string', 'max:12', Rule::exists('asset_types', 'asset_type_id')],
            'condition'     => ['nullable', Rule::in(['NEW', 'GOOD', 'FAIR', 'POOR', 'FAULTY', 'UNKNOWN'])],
            'source'        => ['nullable', Rule::in(['assets', 'transformers', 'switchgear', 'segment_asset'])],
            'search'        => ['nullable', 'string', 'max:120'],
        ]);
    }

    /**
     * v_asset_register, narrowed.
     *
     * Every endpoint starts here, so a filter added once applies to the
     * tiles, the cards, the breakdown and the list together. A page
     * where the total and the table answered different questions would
     * be worse than one with no filters at all.
     */
    private function scoped(array $f)
    {
        return DB::table('v_asset_register')
            ->when($f['province_id'] ?? null, fn ($q, $v) => $q->where('province_id', $v))
            ->when($f['area_id'] ?? null, fn ($q, $v) => $q->where('area_id', $v))
            ->when($f['csc_id'] ?? null, fn ($q, $v) => $q->where('csc_id', $v))
            ->when($f['asset_type_id'] ?? null, fn ($q, $v) => $q->where('asset_type_id', $v))
            ->when($f['condition'] ?? null, fn ($q, $v) => $q->where('condition_status', $v))
            ->when($f['source'] ?? null, fn ($q, $v) => $q->where('source', $v))
            // category_id 0 is the Unclassified bucket, so this tests for
            // null rather than truthiness -- `when` would skip a zero.
            ->when(
                ($f['category_id'] ?? null) !== null,
                fn ($q) => $q->where('category_id', (string) $f['category_id'])
            )
            ->when(
                trim($f['search'] ?? '') !== '',
                function ($q) use ($f) {
                    $term = '%' . trim($f['search']) . '%';
                    $q->where(function ($w) use ($term) {
                        $w->where('asset_code', 'like', $term)
                          ->orWhere('attached_ref', 'like', $term)
                          ->orWhere('type_name', 'like', $term)
                          ->orWhere('csc_name', 'like', $term)
                          ->orWhere('csc_code', 'like', $term);
                    });
                }
            );
    }

    /** Per-unit totals held by one CSC. */
    private function placeTotals(string $cscId)
    {
        return DB::table('v_asset_register')
            ->where('csc_id', $cscId)
            ->select('unit_of_measure')
            ->selectRaw('COUNT(*) AS records')
            ->selectRaw('SUM(quantity) AS quantity')
            ->groupBy('unit_of_measure')
            ->orderBy('unit_of_measure')
            ->get();
    }

    /** Category breakdown for one CSC. */
    private function placeCategories(string $cscId)
    {
        return DB::table('v_asset_register')
            ->where('csc_id', $cscId)
            ->select('category_id', 'category_name', 'unit_of_measure')
            ->selectRaw('COUNT(*) AS records')
            ->selectRaw('SUM(quantity) AS quantity')
            ->groupBy('category_id', 'category_name', 'unit_of_measure')
            ->orderByDesc('records')
            ->get();
    }

    /**
     * A free asset_code for a new record.
     *
     * asset_code is unique across the table, so the sequence is taken
     * from what already exists under this prefix rather than from a
     * count, which would collide the moment a record was retired.
     */
    private function nextAssetCode(string $cscCode, string $typeCode): string
    {
        $prefix = substr("{$cscCode}-{$typeCode}", 0, 33) . '-';

        $last = DB::table('assets')
            ->where('asset_code', 'like', $prefix . '%')
            ->orderByDesc('asset_code')
            ->value('asset_code');

        $next = $last ? ((int) substr($last, strlen($prefix))) + 1 : 1;

        return $prefix . str_pad((string) $next, 4, '0', STR_PAD_LEFT);
    }
}
