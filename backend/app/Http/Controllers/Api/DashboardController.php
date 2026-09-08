<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Support\Facades\DB;

class DashboardController extends Controller
{
    // Full asset breakdown by depot
    public function depotAssetSummary()
    {
        return response()->json(
            DB::table('v_depot_dashboard')->get()
        );
    }

    // Total assets by CSC/depot
    public function depotTotals()
    {
        return response()->json(
            DB::table('v_totals_by_csc')->get()
        );
    }

    // Total assets by area
    public function areaTotals()
    {
        return response()->json(
            DB::table('v_totals_by_area')->get()
        );
    }

    // Province-wide total
    public function provinceTotal()
    {
        return response()->json(
            DB::table('v_totals_by_province')->get()
        );
    }

    /*
     * Transformer roll-ups.
     *
     * These carry the province's complete picture: 1,711 units across all
     * five areas and thirteen of the seventeen depots. The asset-register
     * views above are still a pilot covering Badulla and Haliela only, so
     * the dashboard leads with these instead.
     *
     * Note that the asset views mix units of measure — `nos` and `km` sit
     * in the same total_quantity column — so their totals must never be
     * summed across rows without filtering on unit_of_measure first.
     */

    // Transformer units and installed kVA per area
    public function transformerAreaTotals()
    {
        return response()->json(
            DB::table('v_transformer_totals_by_area')->get()
        );
    }

    // Transformer units and installed kVA per depot
    public function transformerDepotTotals()
    {
        return response()->json(
            DB::table('v_transformer_totals_by_csc')->get()
        );
    }

    // Units and kVA broken down by capacity rating and transformer type
    public function transformerCapacityMix()
    {
        return response()->json(
            DB::table('v_transformer_capacity_mix')->get()
        );
    }

    // Line-length information
    public function depotLineLengths()
    {
        return response()->json(
            DB::table('v_asset_rollup')->get()
        );
    }

    // Last activity for assets
    public function assetLastActivity()
    {
        return response()->json(
            DB::table('v_asset_last_activity')->get()
        );
    }
}