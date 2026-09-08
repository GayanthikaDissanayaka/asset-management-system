<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Asset;
use Illuminate\Http\Request;

class AssetController extends Controller
{
    public function index(Request $request)
    {
        $query = Asset::with('assetType');

        if ($request->filled('asset_type_id')) {
            $query->where('asset_type_id', $request->asset_type_id);
        }

        if ($request->filled('status')) {
            $query->where('status', $request->status);
        }

        if ($request->filled('condition_status')) {
            $query->where('condition_status', $request->condition_status);
        }

        return response()->json(
            $query->paginate(50)
        );
    }

    public function store(Request $request)
    {
        $validated = $request->validate([
            'asset_code'              => 'required|string|max:100',
            'asset_type_id'           => 'required|integer|exists:asset_types,asset_type_id',
            'node_id'                 => 'nullable|integer|exists:network_nodes,node_id',
            'segment_id'              => 'nullable|integer|exists:segments,segment_id',
            'oriented_to_segment_id'  => 'nullable|integer|exists:segments,segment_id',
            'quantity'                => 'required|numeric|min:0',
            'unit_of_measure'         => 'nullable|string|max:20',
            'capacity_kva'             => 'nullable|numeric',
            'material'                 => 'nullable|string|max:100',
            'install_date'             => 'nullable|date',
            'condition_status'        => 'nullable|string|max:50',
            'status'                   => 'nullable|string|max:50',
            'remarks'                  => 'nullable|string',
        ]);

        $asset = Asset::create($validated);

        return response()->json($asset, 201);
    }

    public function show(Asset $asset)
    {
        return response()->json(
            $asset->load([
                'assetType',
                'maintenanceLogs'
            ])
        );
    }

    public function update(Request $request, Asset $asset)
    {
        $validated = $request->validate([
            'asset_code'              => 'sometimes|string|max:100',
            'asset_type_id'           => 'sometimes|integer|exists:asset_types,asset_type_id',
            'node_id'                 => 'nullable|integer|exists:network_nodes,node_id',
            'segment_id'              => 'nullable|integer|exists:segments,segment_id',
            'oriented_to_segment_id'  => 'nullable|integer|exists:segments,segment_id',
            'quantity'                => 'sometimes|numeric|min:0',
            'unit_of_measure'         => 'nullable|string|max:20',
            'capacity_kva'             => 'nullable|numeric',
            'material'                 => 'nullable|string|max:100',
            'install_date'             => 'nullable|date',
            'condition_status'        => 'nullable|string|max:50',
            'status'                   => 'nullable|string|max:50',
            'remarks'                  => 'nullable|string',
        ]);

        $asset->update($validated);

        return response()->json($asset);
    }

    public function destroy(Asset $asset)
    {
        $asset->delete();

        return response()->json(null, 204);
    }
}