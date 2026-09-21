<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use RuntimeException;

/**
 * Allocates the next primary key for a table.
 *
 * WHY THIS EXISTS
 *
 * The keys in this database are readable codes -- SRG-01327, CSC-017,
 * TRF-02113 -- not auto-increment integers. That is what makes a row
 * identifiable on sight, in phpMyAdmin or in a report, without joining
 * anything. The cost is that the database no longer hands out the next
 * key, so something has to, and that something is the id_sequences
 * table:
 *
 *     table_name   id_column   id_prefix   pad_width   last_number
 *     ----------   ---------   ---------   ---------   -----------
 *     csc_depots   csc_id      CSC         3           17
 *
 * which yields CSC-018 next.
 *
 * LOCKING. Two people adding a segment at the same moment must not both
 * be handed SRG-01328. The row is read with lockForUpdate(), so the
 * second request waits for the first to commit -- exactly what
 * AUTO_INCREMENT used to do for free, and the reason every caller must
 * already be inside a transaction.
 *
 * The number is bumped even if the insert that asked for it is rolled
 * back, so the sequence can run ahead of the highest row. That is
 * deliberate: a gap in the codes is harmless, while two rows sharing one
 * is a corrupted register.
 */
class IdSequence
{
    /**
     * The next key for $table, e.g. 'SRG-01328'.
     *
     * Wraps itself in a transaction when the caller has not already
     * opened one. Read-then-write in autocommit is the race this has to
     * avoid: two requests would both read last_number = 1327 and both
     * write 1328, and the second insert would fail on the primary key.
     * Inside a transaction the second request waits at lockForUpdate()
     * until the first commits, and reads 1328.
     */
    public static function next(string $table): string
    {
        if (! DB::transactionLevel()) {
            return DB::transaction(fn () => self::allocate($table));
        }

        return self::allocate($table);
    }

    private static function allocate(string $table): string
    {
        $row = DB::table('id_sequences')
            ->where('table_name', $table)
            ->lockForUpdate()
            ->first();

        if (! $row) {
            throw new RuntimeException(
                "No id_sequences row for '{$table}'. Add one giving its "
                . 'id_column, id_prefix and pad_width before inserting.'
            );
        }

        $next = (int) $row->last_number + 1;

        DB::table('id_sequences')
            ->where('table_name', $table)
            ->update(['last_number' => $next]);

        return self::format($row->id_prefix, $next, (int) $row->pad_width);
    }

    /** Several at once, for a batch insert. */
    public static function nextMany(string $table, int $count): array
    {
        return array_map(fn () => self::next($table), range(1, max($count, 0)));
    }

    /** 'SRG', 1328, 5 -> 'SRG-01328'. */
    public static function format(string $prefix, int $number, int $padWidth): string
    {
        return $prefix . '-' . str_pad((string) $number, $padWidth, '0', STR_PAD_LEFT);
    }
}
