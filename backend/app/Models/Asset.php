<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Asset extends Model
{
    protected $table = 'assets';

    protected $primaryKey = 'asset_id';

    protected $fillable = [
        'asset_code',
        'asset_type_id',
        'node_id',
        'segment_id',
        'oriented_to_segment_id',
        'quantity',
        'unit_of_measure',
        'capacity_kva',
        'material',
        'install_date',
        'condition_status',
        'status',
        'remarks',
        'created_by',
        'updated_by',
        'last_verified_by',
        'last_verified_at',
    ];

    public function assetType()
    {
        return $this->belongsTo(
            AssetType::class,
            'asset_type_id',
            'asset_type_id'
        );
    }

    public function maintenanceLogs()
    {
        return $this->hasMany(
            MaintenanceLog::class,
            'asset_id',
            'asset_id'
        );
    }
}