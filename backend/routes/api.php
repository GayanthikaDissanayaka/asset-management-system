<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\AdminController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\AreaController;
use App\Http\Controllers\Api\DepotController;
use App\Http\Controllers\Api\FeederController;
use App\Http\Controllers\Api\AssetCategoryController;
use App\Http\Controllers\Api\AssetTypeController;
use App\Http\Controllers\Api\AssetController;
use App\Http\Controllers\Api\MaintenanceLogController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\AssetExplorerController;
use App\Http\Controllers\Api\NetworkController;
use App\Http\Controllers\Api\SearchController;
use App\Http\Controllers\Api\SegmentImportController;
use App\Http\Controllers\Api\TransformerEntryController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\SpreadsheetController;

// Authentication
Route::prefix('auth')->group(function () {
    Route::get('registration-options', [AuthController::class, 'registrationOptions']);
    Route::post('register', [AuthController::class, 'register']);
    Route::post('login', [AuthController::class, 'login']);

    Route::middleware('auth:sanctum')->group(function () {
        Route::get('me', [AuthController::class, 'me']);
        Route::post('logout', [AuthController::class, 'logout']);
    });
});

Route::prefix('admin')
    ->middleware(['auth:sanctum', 'role:ADMIN'])
    ->group(function () {
        Route::get('pending-users', [AdminController::class, 'pendingUsers']);
        Route::get('users', [AdminController::class, 'users']);
        Route::get('grantable-roles', [AdminController::class, 'grantableRoles']);
        Route::post('users/{user}/approve', [AdminController::class, 'approve']);
        Route::post('users/{user}/decline', [AdminController::class, 'decline']);
    });

Route::middleware('auth:sanctum')->group(function () {

    Route::get('search', [SearchController::class, 'index']);

    Route::get('notifications', [NotificationController::class, 'index']);
    Route::post('notifications/read-all', [NotificationController::class, 'markAllRead']);
    Route::post('notifications/{notification}/read', [NotificationController::class, 'markRead'])
        ->whereNumber('notification');

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

    Route::prefix('network')->group(function () {
        Route::get('length/by-area', [NetworkController::class, 'lineLengthByArea']);
        Route::get('length/by-csc', [NetworkController::class, 'lineLengthByCsc']);
        Route::get('length/by-feeder', [NetworkController::class, 'lineLengthByFeeder']);

        // HV length, grouped and filtered on demand
        Route::get('hv-length', [NetworkController::class, 'hvLength']);
        Route::get('voltage-levels', [NetworkController::class, 'voltageLevels']);

        Route::get('segments', [NetworkController::class, 'segments']);
        Route::get('form-options', [NetworkController::class, 'formOptions']);

        // Every asset the province holds, and where it is assigned
        Route::get('assets/totals', [NetworkController::class, 'assetTotals']);
        Route::get('assets/by-csc', [NetworkController::class, 'assetsByCsc']);

        Route::get('assets/summary', [AssetExplorerController::class, 'summary']);
        Route::get('assets/catalog', [AssetExplorerController::class, 'catalog']);
        Route::get('assets/breakdown', [AssetExplorerController::class, 'breakdown']);
        Route::get('assets/records', [AssetExplorerController::class, 'records']);
        Route::get('assets/options', [AssetExplorerController::class, 'options']);

        Route::get('assets/types', [AssetExplorerController::class, 'typeCatalogue']);

        // The usage log: what was entered, where and by whom. History,
        // not current state — see database/add_assets_used.sql.
        Route::get('assets/used', [AssetExplorerController::class, 'used']);

        // Find one transformer by id, SIN number, works number or the
        // substation it serves, then read it in full.
        Route::get('transformers/search', [AssetExplorerController::class, 'searchTransformers']);
        // The units in a place, with serial numbers, for the Transformers tile.
        Route::get('transformers', [AssetExplorerController::class, 'listTransformers']);
        Route::get('transformers/{transformer}', [AssetExplorerController::class, 'showTransformer'])
            ->whereNumber('transformer');

        // Excel out
        Route::get('report', [SpreadsheetController::class, 'report']);
        Route::get('export', [SpreadsheetController::class, 'export']);
        Route::get('import-template', [SpreadsheetController::class, 'template']);

        Route::get('reports/saved', [SpreadsheetController::class, 'savedReports']);
        Route::get('reports/download', [SpreadsheetController::class, 'downloadSaved']);

        Route::middleware(['auth:sanctum', 'role:ADMIN,AREA_ENGINEER,ENGINEER'])
            ->group(function () {
                Route::post('segments', [NetworkController::class, 'storeSegment']);
                // Loading a spreadsheet of segments. Its own controller
                // because it writes to the register.
                Route::post('import', [SegmentImportController::class, 'import']);

                
                Route::post('assets/records', [AssetExplorerController::class, 'storeRecords']);

                Route::post('transformers', [TransformerEntryController::class, 'store']);

                Route::post('reports/save', [SpreadsheetController::class, 'saveReport']);
            });
    });
});
