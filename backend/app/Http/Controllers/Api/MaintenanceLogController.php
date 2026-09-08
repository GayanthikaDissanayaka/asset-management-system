<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\MaintenanceLog;
use Illuminate\Http\Request;

class MaintenanceLogController extends Controller
{
    public function store(Request $request)
    {
        $validated = $request->validate([
            'asset_id'    => 'nullable|integer|exists:assets,asset_id',
            'segment_id'  => 'nullable|integer|exists:line_segments,segment_id',
            'action_type' => 'required|in:installed,inspected,repaired,replaced,decommissioned',
            'remarks'     => 'nullable|string',
        ]);

        $log = MaintenanceLog::create($validated + [
            'performed_by' => $request->user()->user_id,
            'performed_at' => now(),
        ]);

        return response()->json($log, 201);
    }

    public function forAsset(int $assetId)
    {
        return response()->json(
            MaintenanceLog::where('asset_id', $assetId)
                ->with('performedBy')
                ->orderByDesc('performed_at')
                ->get()
        );
    }
}
