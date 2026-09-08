<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Role;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    private const MAX_FAILED_ATTEMPTS = 5;
    private const LOCK_MINUTES = 15;

    public function register(Request $request)
    {
        $data = $request->validate([
            'full_name' => 'required|string|min:3|max:120',
            'email'     => 'required|email|max:150',
            'phone'     => 'nullable|string|max:25',
            'password'  => 'required|string|min:10',
        ]);

        if (User::where('email', strtolower($data['email']))->exists()) {
            return response()->json([
                'message' => 'An account with this email already exists.',
            ], 409);
        }

        $viewerRoleId = Role::where('role_code', 'VIEWER')->value('role_id') ?? 5;

        $user = User::create([
            'role_id'       => $viewerRoleId,
            'username'      => $this->uniqueUsername($data['email']),
            'password_hash' => Hash::make($data['password']),
            'full_name'     => $data['full_name'],
            'email'         => strtolower($data['email']),
            'is_active'     => true,
        ]);

        $token = $user->createToken('web')->plainTextToken;

        return response()->json([
            'token' => $token,
            'user'  => $this->shape($user),
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
        ];
    }
}
