<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

/**
 * What one CSC holds, for the summary shown after something is added.
 *
 * Read from v_asset_register, which gathers the transformer register,
 * the switchgear register and the asset register, so a transformer just
 * added appears in these totals at once.
 *
 * Per unit of measure, never one number: counted items and kilometres
 * are different quantities.
 */
class PlaceHoldings
{
    /** The CSC with its area and province, or null. */
    public static function place(int $cscId): ?object
    {
        return DB::table('csc_depots as d')
            ->join('areas as a', 'a.area_id', '=', 'd.area_id')
            ->join('provinces as p', 'p.province_id', '=', 'a.province_id')
            ->where('d.csc_id', $cscId)
            ->select([
                'd.csc_id', 'd.csc_code', 'd.csc_name',
                'a.area_id', 'a.area_name', 'p.province_name',
            ])
            ->first();
    }

    public static function totals(int $cscId)
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

    public static function categories(int $cscId)
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
}
