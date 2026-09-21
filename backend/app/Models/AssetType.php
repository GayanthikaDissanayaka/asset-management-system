<?php

namespace App\Models;

use App\Models\Concerns\HasSequencedId;

use Illuminate\Database\Eloquent\Model;

class AssetType extends Model
{
    use HasSequencedId;

    protected $table = 'asset_types';

    protected $primaryKey = 'asset_type_id';

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
        'category_id',
        'type_code',
        'type_name',
        'unit_of_measure',
        'is_line_asset',
        'rated_kva',
        'allow_decimal',
        'display_order',
        'is_active',
    ];

    public function category()
    {
        return $this->belongsTo(
            AssetCategory::class,
            'category_id',
            'category_id'
        );
    }

    public function assets()
    {
        return $this->hasMany(
            Asset::class,
            'asset_type_id',
            'asset_type_id'
        );
    }
}