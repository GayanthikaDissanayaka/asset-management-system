<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

/**
 * Works out which CSC a spreadsheet row belongs to.
 *
 * THE PROBLEM. The importer used to demand an exact `csc_code` --
 * "BDL-CSC01". Nobody in the province writes that. Their sheets say
 * "Badulla", "Hali Ela", "Mahiyangana", "Bibile", sometimes with an area
 * column beside it and sometimes not. Every one of those was rejected as
 * an unknown CSC, which made the importer useless for the sheets it
 * existed to load.
 *
 * WHAT THIS DOES. It accepts whatever the row says -- code, name, or a
 * known alias -- and resolves it to one CSC, using the area column to
 * settle the case where a name could mean more than one place. It
 * reports HOW each row matched, because "loaded 400 rows" is not
 * trustworthy unless you can see what they were taken to mean.
 *
 * WHAT IT WILL NOT DO. Guess. If a name matches two CSCs and there is no
 * area to separate them, the row is refused and both candidates are
 * named. If the row's area contradicts the CSC it named, that is
 * reported rather than silently resolved either way -- a row assigned to
 * the wrong place is worse than a row that failed to load, because
 * nobody goes looking for it.
 *
 * Matching is progressively looser, and every match records its
 * confidence so the caller can show it:
 *
 *   code      exact CSC code                       BDL-CSC01
 *   name      exact CSC name                       Badulla
 *   alias     a name in csc_aliases                Hali Ela -> Haliela
 *   fuzzy     any of the above ignoring case,      "hali-ela", "BIBILE"
 *             spaces, hyphens and punctuation
 */
class PlaceResolver
{
    /** csc_id => (object) csc_id, csc_code, csc_name, area_id, area_code, area_name */
    private $cscs;

    /** normalised key => [csc_id, ...] for each match strategy */
    private array $byCode = [];
    private array $byName = [];
    private array $byAlias = [];

    private array $areaByKey = [];

    /** Literal alias spellings, so a recorded alias is not reported as a guess. */
    private array $aliasExact = [];

    public function __construct()
    {
        $this->cscs = DB::table('csc_depots as d')
            ->join('areas as a', 'a.area_id', '=', 'd.area_id')
            ->select([
                'd.csc_id', 'd.csc_code', 'd.csc_name',
                'a.area_id', 'a.area_code', 'a.area_name',
            ])
            ->get()
            ->keyBy('csc_id');

        foreach ($this->cscs as $csc) {
            $this->push($this->byCode, $csc->csc_code, $csc->csc_id);
            $this->push($this->byName, $csc->csc_name, $csc->csc_id);

            $this->push($this->areaByKey, $csc->area_code, $csc->area_id);
            $this->push($this->areaByKey, $csc->area_name, $csc->area_id);
        }

        /*
         * The alias table is the province's own record of what its CSCs
         * get called in practice -- "Mahiyangana" for Mahiyanganaya,
         * "Bibile" for Bibila. It already existed and the importer was
         * ignoring it entirely.
         */
        foreach (DB::table('csc_aliases')->get() as $alias) {
            $this->push($this->byAlias, $alias->alias_name, $alias->csc_id);
            $this->aliasExact[$alias->alias_name] = true;
        }
    }

    /**
     * Resolves one row's place.
     *
     * @param  string|null  $csc   whatever the row gave for the CSC
     * @param  string|null  $area  whatever the row gave for the area, if anything
     * @return array{ok:bool, csc_id:?int, csc:?object, matched_by:?string, message:?string}
     */
    public function resolve(?string $csc, ?string $area = null): array
    {
        $cscText  = trim((string) $csc);
        $areaText = trim((string) $area);

        // An area on its own is not a place. Assets and segments belong
        // to a CSC, and picking one of an area's CSCs to stand for the
        // rest would invent data.
        if ($cscText === '') {
            return $this->fail(
                $areaText === ''
                    ? 'No CSC given, and no area to work it out from.'
                    : "Only an area ('{$areaText}') was given. A row needs the CSC, because an area has several."
            );
        }

        $areaId = $this->resolveArea($areaText);

        if ($areaText !== '' && $areaId === null) {
            return $this->fail("Unknown area '{$areaText}'.");
        }

        foreach ([
            'code'  => $this->byCode,
            'name'  => $this->byName,
            'alias' => $this->byAlias,
        ] as $how => $index) {
            $hit = $this->lookup($index, $cscText, $areaId, $how, $cscText, $areaText);
            if ($hit !== null) {
                return $hit;
            }
        }

        /*
         * Nothing matched even loosely. Naming the near misses is what
         * turns "unknown CSC" into something the reader can act on --
         * usually a typo or an alias worth adding to csc_aliases.
         */
        return $this->fail(
            "Could not match '{$cscText}' to a CSC." . $this->suggest($cscText)
        );
    }

    /** Every CSC, for building a reference list in the template. */
    public function all()
    {
        return $this->cscs;
    }

    /* ============================== INTERNALS ========================= */

    private function lookup(
        array $index,
        string $text,
        ?string $areaId,
        string $how,
        string $cscText,
        string $areaText
    ): ?array {
        $ids = $index[$this->key($text)] ?? [];

        if (empty($ids)) {
            return null;
        }

        // More than one CSC answers to this. The area column is the only
        // thing that can separate them; without it, refuse and say so.
        if (count($ids) > 1) {
            if ($areaId === null) {
                $names = implode(', ', array_map(
                    fn ($id) => "{$this->cscs[$id]->csc_code} ({$this->cscs[$id]->area_name})",
                    $ids
                ));

                return $this->fail(
                    "'{$cscText}' matches more than one CSC: {$names}. Add an area column to say which."
                );
            }

            $ids = array_values(array_filter(
                $ids,
                fn ($id) => $this->cscs[$id]->area_id === $areaId
            ));

            if (count($ids) !== 1) {
                return $this->fail(
                    "'{$cscText}' does not name exactly one CSC in the '{$areaText}' area."
                );
            }
        }

        $csc = $this->cscs[$ids[0]];

        /*
         * The row named an area AND a CSC, and they disagree. Trusting
         * either one silently would file the row somewhere nobody will
         * look for it, so it is refused and both are quoted.
         */
        if ($areaId !== null && $csc->area_id !== $areaId) {
            return $this->fail(
                "Row says area '{$areaText}' but '{$cscText}' is {$csc->csc_name} CSC, "
                . "which is in {$csc->area_name}. Fix one of them."
            );
        }

        return [
            'ok'         => true,
            'csc_id'     => (string) $csc->csc_id,
            'csc'        => $csc,
            // "fuzzy" when the text only matched after normalising, so
            // the reader can see which rows were interpreted rather than
            // read literally.
            'matched_by' => $this->isExact($how, $text, $csc) ? $how : 'fuzzy',
            'message'    => null,
        ];
    }

    /**
     * Whether the text matched the way it was written, rather than only
     * after normalising.
     *
     * A recorded alias counts as exact: "Hali Ela" is the province's own
     * spelling, held in csc_aliases on purpose, and reporting it as a
     * guess would tell the reader to go and check something that was
     * never uncertain.
     */
    private function isExact(string $how, string $text, object $csc): bool
    {
        return match ($how) {
            'code'  => $text === $csc->csc_code,
            'name'  => $text === $csc->csc_name,
            'alias' => isset($this->aliasExact[$text]),
            default => false,
        };
    }

    private function resolveArea(string $text): ?string
    {
        if ($text === '') {
            return null;
        }

        $ids = $this->areaByKey[$this->key($text)] ?? [];

        return count($ids) === 1 ? (int) $ids[0] : null;
    }

    /** Near misses, so an unmatched name points somewhere useful. */
    private function suggest(string $text): string
    {
        $key   = $this->key($text);
        $close = [];

        foreach ($this->cscs as $csc) {
            $candidates = [$csc->csc_name, $csc->csc_code];
            foreach ($candidates as $candidate) {
                similar_text($key, $this->key($candidate), $percent);
                if ($percent >= 70) {
                    $close[] = "{$csc->csc_name} ({$csc->csc_code})";
                    break;
                }
            }
        }

        $close = array_slice(array_unique($close), 0, 3);

        return $close ? ' Did you mean: ' . implode(', ', $close) . '?' : '';
    }

    private function fail(string $message): array
    {
        return [
            'ok'         => false,
            'csc_id'     => null,
            'csc'        => null,
            'matched_by' => null,
            'message'    => $message,
        ];
    }

    private function push(array &$index, ?string $text, $id): void
    {
        $key = $this->key((string) $text);
        if ($key === '') {
            return;
        }
        $index[$key] ??= [];
        if (! in_array($id, $index[$key], true)) {
            $index[$key][] = $id;
        }
    }

    /**
     * The loose form of a place name: lowercase, with everything that is
     * not a letter or digit removed. "Hali-Ela", "hali ela" and
     * "HALI_ELA" all become "haliela", which is also what the CSC name
     * "Haliela" becomes.
     */
    private function key(string $text): string
    {
        return preg_replace('/[^a-z0-9]+/', '', strtolower(trim($text)));
    }
}
