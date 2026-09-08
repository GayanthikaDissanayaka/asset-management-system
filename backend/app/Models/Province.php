<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Province extends Model
{
    protected $primaryKey = 'province_id';
    protected $fillable = ['province_name'];

    public function areas()
    {
        return $this->hasMany(Area::class, 'province_id');
    }
}
