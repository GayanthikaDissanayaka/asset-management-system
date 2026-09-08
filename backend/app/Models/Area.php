<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Area extends Model
{
    protected $primaryKey = 'area_id';
    protected $fillable = ['province_id', 'area_no', 'area_name'];

    public function province()
    {
        return $this->belongsTo(Province::class, 'province_id');
    }

    public function depots()
    {
        return $this->hasMany(Depot::class, 'area_id');
    }
}
