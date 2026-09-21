<?php

namespace App\Models\Concerns;

use App\Support\IdSequence;

/**
 * Gives a model its readable primary key on insert.
 *
 * The keys in this database are codes -- USR-003, AST-0072 -- so the
 * database no longer supplies one. Without this, Eloquent would insert a
 * row with an empty key: MySQL does not complain about '' in a varchar
 * primary key, so the FIRST such row saves silently and every one after
 * it fails on a duplicate key. That is a nasty way to find out, which is
 * why this sits on the model rather than at each call site.
 *
 * Only fills a key that is empty, so a caller that wants to choose one
 * -- a seeder importing fixed codes, say -- still can.
 */
trait HasSequencedId
{
    public static function bootHasSequencedId(): void
    {
        static::creating(function ($model) {
            $key = $model->getKeyName();

            if (blank($model->getAttribute($key))) {
                $model->setAttribute($key, IdSequence::next($model->getTable()));
            }
        });
    }
}
