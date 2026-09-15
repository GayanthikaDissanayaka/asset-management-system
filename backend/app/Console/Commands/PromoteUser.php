<?php

namespace App\Console\Commands;

use App\Models\Role;
use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Grants a role from the command line.
 *
 * This exists to solve a bootstrap problem. Account approval happens in
 * the dashboard, but that screen is for administrators, and a system with
 * no administrator has nobody who can open it. The very first one has to
 * be made outside the application.
 *
 * Hand-written SQL would do it, but this checks what the raw UPDATE
 * cannot: that the account exists, that the role exists, and that a role
 * naming a place is given one. It also clears scope_assigned, which is
 * what takes the account out of the pending queue — an UPDATE that sets
 * role_id alone leaves the person an administrator who still shows up as
 * awaiting approval.
 *
 *   php artisan user:promote someone@edl.lk ADMIN
 *   php artisan user:promote someone@edl.lk ENGINEER --csc=BDL-CSC01
 *   php artisan user:promote --list
 */
class PromoteUser extends Command
{
    protected $signature = 'user:promote
                            {email? : Email address or username of the account}
                            {role? : ADMIN, AREA_ENGINEER, ENGINEER, TECHNICIAN or VIEWER}
                            {--area= : Area code, e.g. BDL, for an Area Engineer}
                            {--csc= : CSC code, e.g. BDL-CSC01, for an Engineer or Technician}
                            {--list : Show every account and its current role}';

    protected $description = 'Grant a role to a user account, including the first administrator';

    public function handle(): int
    {
        if ($this->option('list') || ! $this->argument('email')) {
            return $this->listUsers();
        }

        $login = strtolower(trim($this->argument('email')));

        $user = User::whereRaw('LOWER(email) = ?', [$login])
            ->orWhereRaw('LOWER(username) = ?', [$login])
            ->first();

        if (! $user) {
            $this->error("No account found for '{$login}'.");
            $this->line('Run   php artisan user:promote --list   to see the accounts.');

            return self::FAILURE;
        }

        $roleCode = strtoupper(trim((string) $this->argument('role')));

        if ($roleCode === '') {
            $roleCode = $this->choice(
                'Which role should this account hold?',
                Role::orderBy('role_id')->pluck('role_code')->all(),
                'VIEWER'
            );
        }

        $role = Role::where('role_code', $roleCode)->first();

        if (! $role) {
            $this->error("'{$roleCode}' is not a role. Available: "
                . Role::orderBy('role_id')->pluck('role_code')->implode(', '));

            return self::FAILURE;
        }

        // Resolve the scope by code, so nobody has to look up an id.
        $areaId = null;
        $cscId  = null;

        if ($this->option('area')) {
            $areaId = DB::table('areas')
                ->whereRaw('UPPER(area_code) = ?', [strtoupper($this->option('area'))])
                ->value('area_id');

            if (! $areaId) {
                $this->error("No area with code '{$this->option('area')}'.");

                return self::FAILURE;
            }
        }

        if ($this->option('csc')) {
            $csc = DB::table('csc_depots')
                ->whereRaw('UPPER(csc_code) = ?', [strtoupper($this->option('csc'))])
                ->first();

            if (! $csc) {
                $this->error("No CSC with code '{$this->option('csc')}'.");

                return self::FAILURE;
            }

            $cscId  = $csc->csc_id;
            $areaId = $areaId ?: $csc->area_id;
        }

        // The same rules the approval screen applies, so the two cannot
        // disagree about what a valid grant looks like.
        if ($roleCode === 'AREA_ENGINEER' && ! $areaId) {
            $this->error('An Area Engineer needs an area. Pass --area=BDL, for example.');

            return self::FAILURE;
        }

        if (in_array($roleCode, ['ENGINEER', 'TECHNICIAN'], true) && ! $cscId) {
            $this->error('That role needs a CSC. Pass --csc=BDL-CSC01, for example.');

            return self::FAILURE;
        }

        $was = $user->role?->role_code ?? 'none';

        $user->forceFill([
            'role_id'           => $role->role_id,
            'requested_role_id' => null,
            'area_id'           => $areaId,
            'csc_id'            => $cscId,
            'scope_assigned'    => 1,
            'is_active'         => true,
        ])->save();

        $this->info("{$user->full_name} ({$user->email}) is now {$role->role_name}.");
        $this->line("  was: {$was}");
        if ($areaId || $cscId) {
            $this->line('  scope: ' . collect([
                $areaId ? DB::table('areas')->where('area_id', $areaId)->value('area_name') . ' area' : null,
                $cscId ? DB::table('csc_depots')->where('csc_id', $cscId)->value('csc_name') . ' CSC' : null,
            ])->filter()->implode(', '));
        }
        $this->newLine();
        $this->line('They can sign in at the usual login page. Existing sessions pick');
        $this->line('the new role up on their next page load, without signing in again.');

        return self::SUCCESS;
    }

    private function listUsers(): int
    {
        $rows = DB::table('users as u')
            ->join('roles as r', 'r.role_id', '=', 'u.role_id')
            ->leftJoin('areas as a', 'a.area_id', '=', 'u.area_id')
            ->leftJoin('csc_depots as d', 'd.csc_id', '=', 'u.csc_id')
            ->select([
                'u.user_id', 'u.email', 'u.full_name', 'r.role_code',
                'a.area_code', 'd.csc_code', 'u.scope_assigned', 'u.is_active',
            ])
            ->orderBy('u.user_id')
            ->get();

        if ($rows->isEmpty()) {
            $this->warn('There are no accounts yet.');

            return self::SUCCESS;
        }

        $this->table(
            ['#', 'Email', 'Name', 'Role', 'Area', 'CSC', 'Approved', 'Active'],
            $rows->map(fn ($r) => [
                $r->user_id,
                $r->email,
                $r->full_name,
                $r->role_code,
                $r->area_code ?: '-',
                $r->csc_code ?: '-',
                $r->scope_assigned ? 'yes' : 'PENDING',
                $r->is_active ? 'yes' : 'no',
            ])->all()
        );

        if (! $rows->contains(fn ($r) => $r->role_code === 'ADMIN' && $r->is_active)) {
            $this->newLine();
            $this->warn('There is no active administrator, so nobody can open the Approvals screen.');
            $this->line('Make one with:  php artisan user:promote <email> ADMIN');
        }

        return self::SUCCESS;
    }
}
