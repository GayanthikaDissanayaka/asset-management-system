<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Support\Facades\DB;

class DashboardController extends Controller
{
    /**
     * Everything the dashboard needs on first paint, in ONE response.
     *
     * WHY THIS EXISTS
     *
     * The dashboard used to open by firing seven requests at once:
     * three roll-ups here, two length views, the place pickers and the
     * asset catalogue. In a browser those look parallel, and against
     * Apache they are. Against `php artisan serve` they are not —
     * PHP's built-in server handles ONE request at a time, so the
     * seven queue up and the page waits for the slowest possible
     * arrangement of them: seven full Laravel boots, one after another.
     *
     * That is why the dashboard felt slow on localhost and fine in
     * production. One boot instead of seven is the whole fix, and it
     * costs nothing in production either — the five queries run inside
     * a single request rather than five.
     *
     * WHAT IT RETURNS — each key is exactly what the old endpoint gave,
     * so the individual routes below still work and nothing else had to
     * change:
     *
     *   area_totals    v_transformer_totals_by_area   GET dashboard/transformer-area-totals
     *   capacity_mix   v_transformer_capacity_mix     GET dashboard/transformer-capacity-mix
     *   depot_summary  v_depot_dashboard              GET dashboard/depot-summary
     *   length_by_area v_line_length_by_area          GET network/length/by-area
     *   length_by_csc  v_line_length_by_csc           GET network/length/by-csc
     *
     * Read-only: five SELECTs against views, no writes, no side effects.
     */
    public function bootstrap()
    {
        return response()->json([
            'area_totals'    => DB::table('v_transformer_totals_by_area')->get(),
            'capacity_mix'   => DB::table('v_transformer_capacity_mix')->get(),
            'depot_summary'  => DB::table('v_depot_dashboard')->get(),
            // Ordered exactly as the standalone routes order them, so a
            // caller can swap between the two without anything shifting.
            'length_by_area' => DB::table('v_line_length_by_area')->orderByDesc('total_km')->get(),
            'length_by_csc'  => DB::table('v_line_length_by_csc')->orderByDesc('total_km')->get(),
        ]);
    }

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