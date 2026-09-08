<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Role extends Model
{
    protected $primaryKey = 'role_id';
    public $timestamps = false;

    protected $fillable = ['role_code', 'role_name', 'description'];

    public function users()
    {
        return $this->hasMany(User::class, 'role_id');
    }
}
