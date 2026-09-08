<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class LineSegment extends Model
{
    protected $primaryKey = 'segment_id';
    protected $fillable = [
        'segment_code', 'feeder_id', 'asset_type_id', 'voltage_level',
        'from_point', 'to_point', 'length_km', 'status',
    ];

    public function feeder()
    {
        return $this->belongsTo(Feeder::class, 'feeder_id');
    }

    public function assetType()
    {
        return $this->belongsTo(AssetType::class, 'asset_type_id');
    }

    public function maintenanceLogs()
    {
        return $this->hasMany(MaintenanceLog::class, 'segment_id');
    }
}
