<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * A signed-in user's notifications.
 *
 * Its own file because it changes stored state (read and unread). The
 * rows are written by App\Support\AdminNotifier when someone registers
 * and closed by it when a request is decided.
 *
 * Every query here is limited to the caller's own rows. There is no way
 * to read or mark another user's notifications.
 */
class NotificationController extends Controller
{
    /**
     * The inbox, plus the live count of waiting access requests.
     *
     * The badge is driven by `pending_requests` -- counted straight from
     * v_pending_users -- rather than by unread notifications. A request
     * made before an administrator's account existed has no notification
     * addressed to them, and the badge must still not say zero while
     * someone is waiting.
     */
    public function index(Request $request)
    {
        $user    = $request->user();
        $isAdmin = $user->role?->role_code === 'ADMIN';

        $mine = fn () => DB::table('notifications')->where('recipient_id', $user->user_id);

        return response()->json([
            'unread_count' => $mine()
                ->where('status', 'OPEN')
                ->whereNull('read_at')
                ->count(),

            'pending_requests' => $isAdmin
                ? DB::table('v_pending_users')->count()
                : 0,

            'items' => $mine()
                ->orderByDesc('notification_id')
                ->limit(20)
                ->get([
                    'notification_id', 'type', 'title', 'body', 'link',
                    'subject_user_id', 'status', 'resolution',
                    'read_at', 'created_at',
                ]),
        ]);
    }

    /** One notification seen. */
    public function markRead(Request $request, string $notification)
    {
        $updated = DB::table('notifications')
            ->where('notification_id', $notification)
            ->where('recipient_id', $request->user()->user_id)
            ->whereNull('read_at')
            ->update(['read_at' => now()]);

        return response()->json(['updated' => $updated]);
    }

    /** Everything seen at once. */
    public function markAllRead(Request $request)
    {
        $updated = DB::table('notifications')
            ->where('recipient_id', $request->user()->user_id)
            ->whereNull('read_at')
            ->update(['read_at' => now()]);

        return response()->json(['updated' => $updated]);
    }
}
