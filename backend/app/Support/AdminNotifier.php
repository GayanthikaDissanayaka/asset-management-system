<?php

namespace App\Support;

use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * Writes and closes the notifications administrators receive.
 *
 * Kept out of AuthController and AdminController so the rule for who is
 * told what lives in one place: a registration tells every active
 * administrator, and a decision by any one of them closes the message
 * for all of them.
 *
 * NEVER THROWS. A notification is a courtesy on top of the real event.
 * If the notifications table is missing or the insert fails, the
 * registration or approval must still succeed; the failure is reported
 * to the log instead.
 */
class AdminNotifier
{
    public const ACCESS_REQUEST = 'ACCESS_REQUEST';

    /** A new account is waiting for a role. Tell every administrator. */
    public static function accessRequested(User $user): void
    {
        try {
            $admins = DB::table('users as u')
                ->join('roles as r', 'r.role_id', '=', 'u.role_id')
                ->where('r.role_code', 'ADMIN')
                ->where('u.is_active', 1)
                ->where('u.user_id', '!=', $user->user_id)
                ->pluck('u.user_id');

            if ($admins->isEmpty()) {
                return;
            }

            $requested = $user->requested_role_id
                ? DB::table('roles')->where('role_id', $user->requested_role_id)->value('role_name')
                : null;

            $place = collect([
                $user->csc_id ? DB::table('csc_depots')->where('csc_id', $user->csc_id)->value('csc_name') : null,
                $user->area_id ? DB::table('areas')->where('area_id', $user->area_id)->value('area_name') : null,
            ])->filter()->implode(' · ');

            $body = collect([
                $user->designation,
                'asks for ' . ($requested ?: 'access'),
                $place ?: null,
            ])->filter()->implode(' · ');

            DB::table('notifications')->insert(
                // One code per row, not one for the batch: each notice is
                // its own row and needs its own key now that the database
                // does not allocate them.
                $admins->map(fn ($adminId) => [
                    'notification_id' => IdSequence::next('notifications'),
                    'recipient_id'    => $adminId,
                    'type'            => self::ACCESS_REQUEST,
                    'title'           => "Access request from {$user->full_name}",
                    'body'            => mb_substr($body, 0, 500),
                    'subject_user_id' => $user->user_id,
                    'link'            => '/dashboard?approvals=open',
                    'created_at'      => now(),
                ])->all()
            );
        } catch (\Throwable $e) {
            report($e);
        }
    }

    /**
     * A request was decided. Close it for every administrator, so nobody
     * keeps being prompted about something already handled.
     */
    public static function requestResolved(string $subjectUserId, string $resolution): void
    {
        try {
            DB::table('notifications')
                ->where('type', self::ACCESS_REQUEST)
                ->where('subject_user_id', $subjectUserId)
                ->where('status', 'OPEN')
                ->update([
                    'status'      => 'RESOLVED',
                    'resolution'  => $resolution,
                    'resolved_at' => now(),
                    'read_at'     => DB::raw('COALESCE(read_at, NOW())'),
                ]);
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
