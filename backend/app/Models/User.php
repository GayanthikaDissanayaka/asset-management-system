<?php

namespace App\Models;

use App\Models\Concerns\HasSequencedId;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasSequencedId;
    use HasApiTokens;

    protected $primaryKey = 'user_id';

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
        'role_id',
        'requested_role_id',
        'area_id',
        'csc_id',
        'username',
        'employee_no',
        'password_hash',
        'full_name',
        'designation',
        'email',
        'phone',
        'registration_source',
        'scope_assigned',
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

    /** What the applicant asked for at sign-up, not what they hold. */
    public function requestedRole()
    {
        return $this->belongsTo(Role::class, 'requested_role_id');
    }
}
