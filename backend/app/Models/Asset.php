<?php

namespace App\Models;

use App\Models\Concerns\HasSequencedId;

use Illuminate\Database\Eloquent\Model;

class Asset extends Model
{
    use HasSequencedId;

    protected $table = 'assets';

    protected $primaryKey = 'asset_id';

    /*
     * The primary keys in this database are TEXT, not auto-increment
     * integers: 'USR-001', 'CSC-004', 'SRG-00001'. Eloquent assumes an
     * incrementing integer key unless told otherwise, and casts the key
     * to int when it looks one up -- which turns 'USR-001' into 0 and
     * finds nothing. That is what made every signed-in request come back
     * 401 "Sign in to continue."
     *
     * New keys are allocated from the id_sequences table, never by the
     * database, so incrementing is false as well.
     */
    public $incrementing = false;
    protected $keyType = 'string';

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