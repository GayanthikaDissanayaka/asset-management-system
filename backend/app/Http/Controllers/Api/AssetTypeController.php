<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AssetType;

class AssetTypeController extends Controller
{
    public function index()
    {
        return response()->json(AssetType::with('category')->get());
    }

    public function show(AssetType $assetType)
    {
        return response()->json($assetType->load('category'));
    }
}
