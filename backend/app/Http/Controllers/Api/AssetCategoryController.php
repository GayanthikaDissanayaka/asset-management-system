<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AssetCategory;

class AssetCategoryController extends Controller
{
    public function index()
    {
        return response()->json(AssetCategory::with('assetTypes')->get());
    }

    public function show(AssetCategory $assetCategory)
    {
        return response()->json($assetCategory->load('assetTypes'));
    }
}
