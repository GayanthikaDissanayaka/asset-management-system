<?php

namespace App\Models;

use App\Models\Concerns\HasSequencedId;

use Illuminate\Database\Eloquent\Model;

class Depot extends Model
{
    use HasSequencedId;

    /*
     * The table is `csc_depots` and its key is `csc_id`. Without the
     * $table line Eloquent would look for a `depots` table, which has
     * never existed -- "depot" was the old word for what the rest of
     * the system now calls a CSC.
     */
    protected $table = 'csc_depots';

    protected $primaryKey = 'csc_id';

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
    protected $fillable = ['area_id', 'csc_name', 'csc_code', 'page_no', 'latitude', 'longitude'];

    public function area()
    {
        return $this->belongsTo(Area::class, 'area_id');
    }

    public function feeders()
    {
        return $this->hasMany(Feeder::class, 'origin_csc_id');
    }

    public function assets()
    {
        return $this->hasMany(Asset::class, 'csc_id');
    }
}
