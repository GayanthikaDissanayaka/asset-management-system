<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\AreaController;
use App\Http\Controllers\Api\DepotController;
use App\Http\Controllers\Api\FeederController;
use App\Http\Controllers\Api\AssetCategoryController;
use App\Http\Controllers\Api\AssetTypeController;
use App\Http\Controllers\Api\AssetController;
use App\Http\Controllers\Api\MaintenanceLogController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\NetworkController;
use App\Http\Controllers\Api\SpreadsheetController;

// Authentication
Route::prefix('auth')->group(function () {
    Route::post('register', [AuthController::class, 'register']);
    Route::post('login', [AuthController::class, 'login']);

    Route::middleware('auth:sanctum')->group(function () {
        Route::get('me', [AuthController::class, 'me']);
        Route::post('logout', [AuthController::class, 'logout']);
    });
});

// Route::middleware('auth:sanctum')->group(function () {
Route::group([], function () {

    // Hierarchy (read-mostly reference data)
    Route::apiResource('areas', AreaController::class)->only(['index', 'show']);
    Route::apiResource('depots', DepotController::class)->only(['index', 'show']);
    Route::apiResource('feeders', FeederController::class)->only(['index', 'show']);
    Route::apiResource('asset-categories', AssetCategoryController::class)->only(['index', 'show']);
    Route::apiResource('asset-types', AssetTypeController::class)->only(['index', 'show']);

    // Asset register
    Route::apiResource('assets', AssetController::class);

    // Maintenance / activity log
    Route::post('maintenance-logs', [MaintenanceLogController::class, 'store']);
    Route::get('assets/{asset}/logs', [MaintenanceLogController::class, 'forAsset']);

    // Dashboard roll-ups (depot -> area -> province)
    Route::prefix('dashboard')->group(function () {
        Route::get('depot-summary', [DashboardController::class, 'depotAssetSummary']);
        Route::get('depot-totals', [DashboardController::class, 'depotTotals']);
        Route::get('area-totals', [DashboardController::class, 'areaTotals']);
        Route::get('province-total', [DashboardController::class, 'provinceTotal']);
        // Transformer roll-ups — the complete province dataset
        Route::get('transformer-area-totals', [DashboardController::class, 'transformerAreaTotals']);
        Route::get('transformer-depot-totals', [DashboardController::class, 'transformerDepotTotals']);
        Route::get('transformer-capacity-mix', [DashboardController::class, 'transformerCapacityMix']);

        Route::get('line-lengths', [DashboardController::class, 'depotLineLengths']);
        Route::get('last-activity', [DashboardController::class, 'assetLastActivity']);
    });

    /*
     * Network length and segment entry.
     *
     * The three roll-ups answer "how much line" at each level, and each
     * reports a segment count beside its total, so a CSC holding several
     * segments is never mistaken for one. `segments` returns those parts
     * individually.
     */
    Route::prefix('network')->group(function () {
        Route::get('length/by-area', [NetworkController::class, 'lineLengthByArea']);
        Route::get('length/by-csc', [NetworkController::class, 'lineLengthByCsc']);
        Route::get('length/by-feeder', [NetworkController::class, 'lineLengthByFeeder']);

        Route::get('segments', [NetworkController::class, 'segments']);
        Route::get('form-options', [NetworkController::class, 'formOptions']);

        // Every asset the province holds, and where it is assigned
        Route::get('assets/totals', [NetworkController::class, 'assetTotals']);
        Route::get('assets/by-csc', [NetworkController::class, 'assetsByCsc']);

        // Excel out
        Route::get('report', [SpreadsheetController::class, 'report']);
        Route::get('export', [SpreadsheetController::class, 'export']);
        Route::get('import-template', [SpreadsheetController::class, 'template']);

        /*
         * WRITES. Everything above only reads; these two change the
         * register, so they require a signed-in user whose role is
         * allowed to record network data.
         *
         * Sanctum issues the bearer token at /api/auth/login, and the
         * React client already attaches it to every request. A viewer
         * gets 403 here, not 401: they are known, just not permitted.
         *
         * To close the reads as well, wrap the whole `network` prefix
         * group in ->middleware('auth:sanctum'). That is deliberately not
         * done yet, because the dashboard is currently reachable without
         * signing in and turning it on is a decision, not a detail.
         */
        Route::middleware(['auth:sanctum', 'role:ADMIN,AREA_ENGINEER,ENGINEER'])
            ->group(function () {
                Route::post('segments', [NetworkController::class, 'storeSegment']);
                Route::post('import', [SpreadsheetController::class, 'import']);
            });
    });
});
