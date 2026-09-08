<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Feeder extends Model
{
    protected $primaryKey = 'feeder_id';
    protected $fillable = ['depot_id', 'feeder_code', 'feeder_name', 'voltage_kv', 'status'];

    public function depot()
    {
        return $this->belongsTo(Depot::class, 'depot_id');
    }

    public function assets()
    {
        return $this->hasMany(Asset::class, 'feeder_id');
    }

    public function lineSegments()
    {
        return $this->hasMany(LineSegment::class, 'feeder_id');
    }
}
