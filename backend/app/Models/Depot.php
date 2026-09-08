<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Depot extends Model
{
    protected $primaryKey = 'depot_id';
    protected $fillable = ['area_id', 'csc_name', 'csc_code', 'page_no', 'latitude', 'longitude'];

    public function area()
    {
        return $this->belongsTo(Area::class, 'area_id');
    }

    public function feeders()
    {
        return $this->hasMany(Feeder::class, 'depot_id');
    }

    public function assets()
    {
        return $this->hasMany(Asset::class, 'depot_id');
    }
}
