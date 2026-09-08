<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AssetType extends Model
{
    protected $table = 'asset_types';

    protected $primaryKey = 'asset_type_id';

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