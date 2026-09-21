<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Role;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    private const MAX_FAILED_ATTEMPTS = 5;
    private const LOCK_MINUTES = 15;

    /**
     * Roles an applicant may ask for. ADMIN is absent on purpose: nobody
     * requests administrator through a public form.
     */
    private const REQUESTABLE_ROLES = ['AREA_ENGINEER', 'ENGINEER', 'TECHNICIAN', 'VIEWER'];

    /**
     * What the sign-up form needs to fill its pickers.
     *
     * Public, because it is needed before anyone has an account.
     */
    public function registrationOptions()
    {
        return response()->json([
            'areas' => DB::table('areas')
                ->select('area_id', 'area_code', 'area_name')
                ->where('is_active', 1)
                ->orderBy('area_name')
                ->get(),

            'cscs' => DB::table('csc_depots')
                ->select('csc_id', 'area_id', 'csc_code', 'csc_name')
                ->where('is_active', 1)
                ->orderBy('csc_name')
                ->get(),

            'roles' => DB::table('roles')
                ->select('role_id', 'role_code', 'role_name', 'description')
                ->whereIn('role_code', self::REQUESTABLE_ROLES)
                ->orderBy('role_id')
                ->get(),
        ]);
    }

    /**
     * Self-registration.
     *
     * EVERY new account starts as VIEWER, whatever role was asked for.
     * The requested role is recorded, never granted: a public form that
     * let people choose their own permissions would let anyone give
     * themselves edit rights over the province's asset register.
     *
     * What the form does capture is who is asking — designation, and the
     * area and CSC they work in — written with
     * registration_source = SELF_REGISTERED and scope_assigned = 0, which
     * is what puts the account into v_pending_users for an administrator
     * to act on. Previously neither column was set, so a self-registered
     * user was stored as though an administrator had created them and
     * already assigned their scope, and the approval queue stayed empty.
     */
    public function register(Request $request)
    {
        $data = $request->validate([
            'full_name'   => 'required|string|min:3|max:120',
            'email'       => 'required|email|max:150',
            'phone'       => 'nullable|string|max:25',
            'password'    => 'required|string|min:10',

            'designation' => 'nullable|string|max:100',
            'area_id'     => ['nullable', 'string', 'max:12', Rule::exists('areas', 'area_id')],
            'csc_id'      => ['nullable', 'string', 'max:12', Rule::exists('csc_depots', 'csc_id')],
            'requested_role' => ['nullable', Rule::in(self::REQUESTABLE_ROLES)],
        ]);

        $email = strtolower(trim($data['email']));

        if (User::where('email', $email)->exists()) {
            return response()->json([
                'message' => 'An account with this email already exists.',
            ], 409);
        }

        $viewerRoleId = Role::where('role_code', 'VIEWER')->value('role_id') ?? 5;

        $requestedRoleId = ! empty($data['requested_role'])
            ? Role::where('role_code', $data['requested_role'])->value('role_id')
            : null;

        $user = User::create([
            'role_id'             => $viewerRoleId,
            'requested_role_id'   => $requestedRoleId,
            'area_id'             => $data['area_id'] ?? null,
            'csc_id'              => $data['csc_id'] ?? null,
            'username'            => $this->uniqueUsername($email),
            'password_hash'       => Hash::make($data['password']),
            'full_name'           => trim($data['full_name']),
            'designation'         => trim($data['designation'] ?? '') ?: null,
            'email'               => $email,
            'phone'               => trim($data['phone'] ?? '') ?: null,
            'registration_source' => 'SELF_REGISTERED',
            'scope_assigned'      => 0,
            'is_active'           => true,
        ]);

        // Tell every administrator a request is waiting, rather than
        // leaving it for someone to find in the Approvals dialog.
        \App\Support\AdminNotifier::accessRequested($user);

        $token = $user->createToken('web')->plainTextToken;

        return response()->json([
            'token'   => $token,
            'user'    => $this->shape($user),
            'pending' => true,
            'message' => 'Account created with read-only access. An administrator will '
                . 'assign your role and depot before you can record or edit data.',
        ], 201);
    }

    public function login(Request $request)
    {
        $data = $request->validate([
            'email'    => 'required|string',
            'password' => 'required|string',
        ]);

        $login = strtolower(trim($data['email']));

        $user = User::where('email', $login)
            ->orWhere('username', $login)
            ->first();

        if (! $user) {
            $this->fail();
        }

        if ($user->locked_until && $user->locked_until->isFuture()) {
            return response()->json([
                'message' => 'Account locked. Try again later.',
            ], 423);
        }

        if (! Hash::check($data['password'], $user->password_hash)) {
            $user->failed_attempts++;
            if ($user->failed_attempts >= self::MAX_FAILED_ATTEMPTS) {
                $user->locked_until = now()->addMinutes(self::LOCK_MINUTES);
                $user->failed_attempts = 0;
            }
            $user->save();
            $this->fail();
        }

        if (! $user->is_active) {
            return response()->json([
                'message' => 'This account has been deactivated.',
            ], 403);
        }

        $user->forceFill([
            'failed_attempts' => 0,
            'locked_until'    => null,
            'last_login_at'   => now(),
        ])->save();

        $token = $user->createToken('web')->plainTextToken;

        return response()->json([
            'token' => $token,
            'user'  => $this->shape($user),
        ]);
    }

    public function me(Request $request)
    {
        return response()->json($this->shape($request->user()));
    }

    public function logout(Request $request)
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'Signed out.']);
    }

    private function fail(): never
    {
        throw ValidationException::withMessages([
            'email' => ['That email and password combination is not recognised.'],
        ]);
    }

    private function uniqueUsername(string $email): string
    {
        $base = Str::slug(Str::before($email, '@'), '_') ?: 'user';
        $base = Str::limit($base, 40, '');
        $name = $base;
        $i = 1;
        while (User::where('username', $name)->exists()) {
            $name = $base . $i++;
        }

        return $name;
    }

    private function shape(User $user): array
    {
        return [
            'id'          => $user->user_id,
            'full_name'   => $user->full_name,
            'username'    => $user->username,
            'email'       => $user->email,
            'role_id'     => $user->role_id,
            'role'        => $user->role?->role_code,
            'area_id'     => $user->area_id,
            'csc_id'      => $user->csc_id,
            'employee_no' => $user->employee_no,
            'designation' => $user->designation,

            // True while a self-registered account is still waiting for an
            // administrator to assign its role and depot. The dashboard
            // reads this to explain why editing is unavailable.
            'awaiting_approval' => $user->registration_source === 'SELF_REGISTERED'
                && ! $user->scope_assigned,
            'requested_role' => $user->requestedRole?->role_code,
        ];
    }
}
