<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Role;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

/**
 * Account approval.
 *
 * Self-registration deliberately grants nothing: a new account is a
 * VIEWER with scope_assigned = 0, which is what puts it in
 * v_pending_users. This is the other half of that — how an administrator
 * turns a request into real access.
 *
 * Approving does three things at once, because they only make sense
 * together: it sets the role, it sets the area and CSC that role applies
 * to, and it marks the scope assigned so the account leaves the queue.
 *
 * Every route here is behind `role:ADMIN`.
 */
class AdminController extends Controller
{
    /** Roles an administrator may grant. */
    private const GRANTABLE_ROLES = [
        'ADMIN', 'AREA_ENGINEER', 'ENGINEER', 'TECHNICIAN', 'VIEWER',
    ];

    /** Accounts waiting for a decision, oldest first. */
    public function pendingUsers()
    {
        return response()->json(
            DB::table('v_pending_users')->orderBy('created_at')->get()
        );
    }

    /**
     * Everyone with an account, so an administrator can see who holds
     * what and change it later, not only at sign-up.
     */
    public function users()
    {
        return response()->json(
            DB::table('users as u')
                ->join('roles as r', 'r.role_id', '=', 'u.role_id')
                ->leftJoin('areas as a', 'a.area_id', '=', 'u.area_id')
                ->leftJoin('csc_depots as d', 'd.csc_id', '=', 'u.csc_id')
                ->select([
                    'u.user_id', 'u.username', 'u.full_name', 'u.designation',
                    'u.email', 'u.phone', 'u.is_active', 'u.scope_assigned',
                    'u.registration_source', 'u.last_login_at', 'u.created_at',
                    'r.role_code', 'r.role_name',
                    'a.area_id', 'a.area_name',
                    'd.csc_id', 'd.csc_name',
                ])
                ->orderByDesc('u.created_at')
                ->get()
        );
    }

    /** The roles that can be granted, for the approval picker. */
    public function grantableRoles()
    {
        return response()->json(
            DB::table('roles')
                ->select('role_id', 'role_code', 'role_name', 'description')
                ->whereIn('role_code', self::GRANTABLE_ROLES)
                ->orderBy('role_id')
                ->get()
        );
    }

    /**
     * Grants a role and the scope it applies to.
     *
     * A Depot Engineer without a CSC, or an Area Engineer without an
     * area, would hold a role that points at nothing, so the scope those
     * roles need is required rather than optional.
     */
    public function approve(Request $request, string $userId)
    {
        $data = $request->validate([
            'role_code' => ['required', Rule::in(self::GRANTABLE_ROLES)],
            'area_id'   => ['nullable', 'string', 'max:12', Rule::exists('areas', 'area_id')],
            'csc_id'    => ['nullable', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],
        ]);

        $user = User::find($userId);

        if (! $user) {
            return response()->json(['message' => 'No such user.'], 404);
        }

        if ($user->user_id === $request->user()->user_id) {
            return response()->json([
                'message' => 'You cannot change your own role. Ask another administrator.',
            ], 422);
        }

        $role = Role::where('role_code', $data['role_code'])->first();

        $areaId = $data['area_id'] ?? null;
        $cscId  = $data['csc_id'] ?? null;

        if ($data['role_code'] === 'AREA_ENGINEER' && ! $areaId) {
            return response()->json([
                'message' => 'An Area Engineer needs an area.',
                'errors'  => ['area_id' => ['Choose the area this engineer covers.']],
            ], 422);
        }

        if (in_array($data['role_code'], ['ENGINEER', 'TECHNICIAN'], true) && ! $cscId) {
            return response()->json([
                'message' => 'That role needs a CSC.',
                'errors'  => ['csc_id' => ['Choose the CSC this person works at.']],
            ], 422);
        }

        // A CSC belongs to an area, so the two must agree.
        if ($cscId) {
            $cscAreaId = DB::table('csc_depots')->where('csc_id', $cscId)->value('area_id');
            if ($areaId && (int) $cscAreaId !== (int) $areaId) {
                return response()->json([
                    'message' => 'That CSC is not in the chosen area.',
                    'errors'  => ['csc_id' => ['That CSC is not in the chosen area.']],
                ], 422);
            }
            $areaId = $areaId ?: $cscAreaId;
        }

        $user->forceFill([
            'role_id'           => $role->role_id,
            'requested_role_id' => null,
            'area_id'           => $areaId,
            'csc_id'            => $cscId,
            'scope_assigned'    => 1,
            'is_active'         => true,
        ])->save();

        // The request is decided; stop prompting every administrator about it.
        \App\Support\AdminNotifier::requestResolved($user->user_id, 'approved');

        /*
         * Existing tokens carry no role of their own — the role is read
         * from the user on every request — so the change takes effect on
         * their next call without forcing a new sign-in.
         */
        return response()->json([
            'message' => "{$user->full_name} is now {$role->role_name}.",
            'user'    => [
                'id'        => $user->user_id,
                'full_name' => $user->full_name,
                'role'      => $role->role_code,
                'area_id'   => $areaId,
                'csc_id'    => $cscId,
            ],
        ]);
    }

    /**
     * Turns a request down.
     *
     * The account is deactivated rather than deleted: the record of who
     * asked, and when, is worth keeping, and login already refuses an
     * inactive account.
     */
    public function decline(Request $request, string $userId)
    {
        $user = User::find($userId);

        if (! $user) {
            return response()->json(['message' => 'No such user.'], 404);
        }

        if ($user->user_id === $request->user()->user_id) {
            return response()->json([
                'message' => 'You cannot deactivate your own account.',
            ], 422);
        }

        $user->forceFill(['is_active' => false])->save();
        $user->tokens()->delete();

        \App\Support\AdminNotifier::requestResolved($user->user_id, 'declined');

        return response()->json([
            'message' => "{$user->full_name}'s access has been withdrawn.",
        ]);
    }
}
