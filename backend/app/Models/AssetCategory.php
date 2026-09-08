<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class AssetCategory extends Model
{
    protected $primaryKey = 'category_id';
    protected $fillable = ['category_name', 'description'];

    public function assetTypes()
    {
        return $this->hasMany(AssetType::class, 'category_id');
    }
}
