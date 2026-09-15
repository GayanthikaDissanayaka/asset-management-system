<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * One search box over the whole province.
 *
 * Reads v_search_index, which flattens transformers, switchgear,
 * segments, CSCs, areas, feeders and the general asset register into one
 * shape. See database/add_search_index.sql.
 *
 * NOT A PUBLIC SEARCH ENGINE. This indexes the province operational
 * record for the staff who own it, and sits behind auth:sanctum like
 * every other read. Nothing here is crawlable; the application ships
 * with a noindex robots rule precisely so it never becomes so.
 *
 * RANKING. An engineer who types a complete SIN number wants that
 * transformer, not the four hundred records that happen to contain those
 * characters somewhere. So an exact hit on an identifier outranks a name
 * match, which outranks a prefix, which outranks an appearance anywhere
 * in the keywords. Ties break towards the smaller, more specific kinds:
 * "badulla" should surface the Badulla area and CSC above the eight
 * feeders named after them.
 */
class SearchController extends Controller
{
    /** How many of any one kind may appear in the shortlist. */
    private const PER_KIND_CAP = 5;

    /**
     * Kinds in the order they are offered, which is roughly smallest and
     * most specific first. Used as the tie-break so a search matching an
     * area and forty segments equally does not bury the area.
     */
    private const KIND_ORDER = [
        'area', 'csc', 'feeder', 'transformer', 'switchgear', 'asset', 'segment',
    ];

    public function index(Request $request)
    {
        $validated = $request->validate([
            'q'     => ['required', 'string', 'min:2', 'max:120'],
            'kind'  => ['nullable', Rule::in(self::KIND_ORDER)],
            'limit' => ['nullable', 'integer', 'min:1', 'max:50'],
        ]);

        $term  = trim($validated['q']);
        $limit = $validated['limit'] ?? 12;

        // A term of "%" would otherwise match every row in the index.
        $escaped = str_replace(['\\', '%', '_'], ['\\\\', '\%', '\_'], mb_strtolower($term));

        $matches = fn ($q) => $q
            ->from('v_search_index')
            ->whereRaw('keywords LIKE ?', ["%{$escaped}%"])
            ->when(
                $validated['kind'] ?? null,
                fn ($qq, $kind) => $qq->where('kind', $kind)
            );

        // How many of each kind match in total, so the box can say what
        // it is not showing rather than implying the shortlist is all
        // there is.
        $counts = $matches(DB::query())
            ->select('kind')
            ->selectRaw('COUNT(*) AS total')
            ->groupBy('kind')
            ->pluck('total', 'kind');

        $score = <<<'SQL'
            CASE
                WHEN LOWER(code)  = ?                      THEN 100
                WHEN LOWER(title) = ?                      THEN 95
                WHEN LOWER(code)  LIKE CONCAT(?, '%')      THEN 80
                WHEN LOWER(title) LIKE CONCAT(?, '%')      THEN 70
                WHEN LOWER(title) LIKE CONCAT('%', ?, '%') THEN 50
                ELSE 30
            END
        SQL;

        /*
         * Deliberately over-fetched. The per-kind cap below is applied
         * after ranking, so taking only `limit` rows here would let one
         * crowded kind fill the list and leave nothing to promote in its
         * place.
         */
        $rows = $matches(DB::query())
            ->select([
                'kind', 'entity_id', 'code', 'title', 'subtitle',
                'place', 'csc_id', 'area_id', 'status',
            ])
            ->selectRaw("{$score} AS score", array_fill(0, 5, $escaped))
            ->orderByDesc('score')
            ->orderByRaw('FIELD(kind, ' . implode(', ', array_map(
                fn ($k) => DB::getPdo()->quote($k),
                self::KIND_ORDER
            )) . ')')
            ->orderByRaw('CHAR_LENGTH(title)')
            ->limit(120)
            ->get();

        $seen    = [];
        $results = [];

        foreach ($rows as $row) {
            $kind = $row->kind;
            $seen[$kind] = ($seen[$kind] ?? 0) + 1;

            // One kind may not crowd out the others. Without this,
            // "badulla" returns eight feeders and the reader never sees
            // that there is a Badulla area and a Badulla CSC.
            if ($seen[$kind] > self::PER_KIND_CAP) {
                continue;
            }

            $row->score = (int) $row->score;
            $results[]  = $row;

            if (count($results) >= $limit) {
                break;
            }
        }

        return response()->json([
            'query'   => $term,
            'total'   => (int) $counts->sum(),
            'counts'  => $counts,
            'results' => $results,
        ]);
    }
}
