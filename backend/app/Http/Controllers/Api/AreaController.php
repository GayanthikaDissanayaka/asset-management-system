<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Area;

class AreaController extends Controller
{
    public function index()
    {
        return response()->json(Area::with('depots')->get());
    }

    public function show(Area $area)
    {
        return response()->json($area->load('depots'));
    }
}
