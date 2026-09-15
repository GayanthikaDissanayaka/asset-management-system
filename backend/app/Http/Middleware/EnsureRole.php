<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Role gate.
 *
 * Used as `role:ADMIN,AREA_ENGINEER,ENGINEER` after `auth:sanctum`, which
 * has already established who the caller is. This only answers whether
 * they are allowed to do the thing.
 *
 * The two failures are kept distinct on purpose, because the frontend
 * treats them differently:
 *
 *   401  no token, or a token that is no longer valid -> sign in again
 *   403  signed in, but this role cannot do this      -> tell them why
 *
 * Roles are compared on role_code (ADMIN, AREA_ENGINEER, ENGINEER,
 * TECHNICIAN, VIEWER) rather than role_id, so renumbering the roles table
 * cannot silently widen access.
 */
class EnsureRole
{
    /** Holds every permission, on every route, without being listed. */
    private const FULL_ACCESS_ROLE = 'ADMIN';

    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();

        if (! $user) {
            return response()->json([
                'message' => 'Sign in to continue.',
            ], 401);
        }

        if (! $user->is_active) {
            return response()->json([
                'message' => 'This account has been deactivated.',
            ], 403);
        }

        $code = $user->role?->role_code;

        /*
         * An administrator passes every role check, whether or not ADMIN
         * was named on the route. Otherwise adding a route gated
         * `role:ENGINEER` would silently lock out the one person who is
         * supposed to be able to do everything, and each new gate would
         * have to remember to list ADMIN again.
         */
        if ($code === self::FULL_ACCESS_ROLE) {
            return $next($request);
        }

        if (! $code || ! in_array($code, $roles, true)) {
            return response()->json([
                'message' => 'Your role does not allow this. An administrator can widen your access.',
                'required_roles' => array_values($roles),
                'your_role'      => $code,
            ], 403);
        }

        return $next($request);
    }
}
