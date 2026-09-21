<?php

namespace App\Models;

use App\Models\Concerns\HasSequencedId;

use Illuminate\Database\Eloquent\Model;

class MaintenanceLog extends Model
{
    use HasSequencedId;

    // Renamed from `log_id` when the keys became text codes (MNT-00001).
    protected $primaryKey = 'maintenance_log_id';

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
    public $timestamps = false;
    protected $fillable = [
        'asset_id', 'segment_id', 'action_type', 'performed_by',
        'performed_at', 'remarks', 'photo_path',
    ];

    public function asset()
    {
        return $this->belongsTo(Asset::class, 'asset_id');
    }

    public function segment()
    {
        return $this->belongsTo(LineSegment::class, 'segment_id');
    }

    public function performedBy()
    {
        return $this->belongsTo(User::class, 'performed_by');
    }
}
