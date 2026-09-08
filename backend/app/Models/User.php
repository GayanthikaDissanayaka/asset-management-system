<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens;

    protected $primaryKey = 'user_id';

    protected $fillable = [
        'role_id',
        'area_id',
        'csc_id',
        'username',
        'password_hash',
        'full_name',
        'designation',
        'email',
        'is_active',
    ];

    protected $hidden = ['password_hash'];

    protected $casts = [
        'is_active'       => 'boolean',
        'last_login_at'   => 'datetime',
        'locked_until'    => 'datetime',
        'failed_attempts' => 'integer',
    ];

    /**
     * This schema stores the password hash in `password_hash`, not `password`.
     */
    public function getAuthPassword()
    {
        return $this->password_hash;
    }

    public function role()
    {
        return $this->belongsTo(Role::class, 'role_id');
    }

    public function area()
    {
        return $this->belongsTo(Area::class, 'area_id');
    }
}
