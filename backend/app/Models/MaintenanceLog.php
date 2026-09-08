<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class MaintenanceLog extends Model
{
    protected $primaryKey = 'log_id';
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
