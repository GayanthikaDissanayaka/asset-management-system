<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Feeder;

class FeederController extends Controller
{
    public function index()
    {
        return response()->json(Feeder::with('depot')->get());
    }

    public function show(Feeder $feeder)
    {
        return response()->json($feeder->load(['depot', 'assets', 'lineSegments']));
    }
}
