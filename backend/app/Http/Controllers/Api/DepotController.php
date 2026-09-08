<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Depot;

class DepotController extends Controller
{
    public function index()
    {
        return response()->json(Depot::with('area')->get());
    }

    public function show(Depot $depot)
    {
        return response()->json($depot->load(['area', 'feeders', 'assets']));
    }
}
