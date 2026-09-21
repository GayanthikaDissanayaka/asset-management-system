<?php

namespace App\Models;

use App\Models\Concerns\HasSequencedId;

use Illuminate\Database\Eloquent\Model;

class LineSegment extends Model
{
    use HasSequencedId;

    protected $primaryKey = 'segment_id';

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
