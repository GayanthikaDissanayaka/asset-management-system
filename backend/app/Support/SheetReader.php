<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;
use PhpOffice\PhpSpreadsheet\Spreadsheet;

/**
 * Finds the useful part of an uploaded workbook and ignores the rest.
 *
 * THE PROBLEM. The importer used to insist that row 1 of sheet 1 held a
 * heading spelled exactly `segment_code`. Real CEB sheets do not look
 * like that. They have a title and a date in the first rows, the table
 * starts further down, the column is headed "Seg ID" or "Segment No",
 * and there are columns nobody asked about -- surveyor, photo, GPS. Any
 * of those produced "The sheet is missing a 'segment_code' column" and
 * the whole file was refused.
 *
 * WHAT THIS DOES.
 *
 *   1. Looks through the first sheets and their first rows for the row
 *      that reads most like a heading row, so title rows above the
 *      table do not matter.
 *
 *   2. Recognises each wanted column under the names people actually
 *      use, first by exact name, then by a looser pattern.
 *
 *   3. Recognises asset columns by type name, short form or code --
 *      "RC Pole", "Recloser", "LBS", "Copper".
 *
 *   4. Ignores everything else, and REPORTS what it ignored, so a column
 *      that was meant to load and did not is visible rather than
 *      silently dropped.
 *
 * WHAT IT WILL NOT DO. Invent a segment ID or a CSC. A segment needs an
 * identifier and a place; without those columns the sheet is refused
 * with a message naming the headings it did find.
 */
class SheetReader
{
    /** Rows searched for the heading row, per sheet. */
    private const SCAN_ROWS = 25;

    /** Sheets searched in a workbook. A cover sheet first is common. */
    private const SCAN_SHEETS = 10;

    /**
     * Exact heading names, after normalising (lower case, punctuation
     * and spaces to underscores, a trailing unit such as "(km)" dropped).
     */
    private const FIELDS = [
        'segment_code' => [
            'segment_code', 'segment_id', 'seg_id', 'segid', 'seg_code',
            'segment', 'segment_no', 'seg_no', 'segment_number', 'seg_number',
            'segment_ref', 'section_id', 'section_code', 'line_segment',
        ],
        'csc' => [
            'csc_code', 'csc', 'csc_name', 'depot', 'depot_code', 'depot_name',
            'consumer_service_centre', 'consumer_service_center',
            'service_centre', 'service_center', 'centre', 'center',
        ],
        'area' => [
            'area', 'area_code', 'area_name', 'ceb_area', 'operational_area',
        ],
        'length_km' => [
            'length_km', 'length', 'km', 'route_length', 'line_length',
            'segment_length', 'distance', 'distance_km', 'length_in_km',
            'total_length', 'mv_length', 'hv_length',
        ],
        'feeder_code' => [
            'feeder_code', 'feeder', 'feeder_no', 'feeder_name', 'feeder_id',
        ],
        'voltage_level' => [
            'voltage_level', 'voltage', 'kv', 'voltage_kv', 'system_voltage',
        ],
        'remarks' => [
            'remarks', 'remark', 'notes', 'note', 'comment', 'comments', 'description',
        ],
    ];

    /**
     * Looser patterns, tried only on headings nothing else claimed.
     *
     * Ordered on purpose: a heading such as "Segment Length" matches both
     * the segment pattern and the length pattern, and it is a length.
     * Earlier fields claim a heading first.
     */
    private const PATTERNS = [
        'length_km'     => '/(^|_)(length|distance)(_|$)/',
        'feeder_code'   => '/(^|_)feeder(_|$)/',
        'voltage_level' => '/(^|_)(voltage|kv)(_|$)/',
        'csc'           => '/(^|_)(csc|depot)(_|$)/',
        'area'          => '/(^|_)area(_|$)/',
        'remarks'       => '/(^|_)(remarks?|notes?|comments?)(_|$)/',
        'segment_code'  => '/(^|_)(seg|segment|section)(_|$)/',
    ];

    /** How each field is described back to the person importing. */
    public const FIELD_LABELS = [
        'segment_code'  => 'Segment ID',
        'csc'           => 'CSC',
        'area'          => 'Area',
        'length_km'     => 'Length (km)',
        'feeder_code'   => 'Feeder',
        'voltage_level' => 'Voltage',
        'remarks'       => 'Remarks',
    ];

    /** normalised key => asset_type_id, only for keys naming one type. */
    private array $assetKeys;

    /** asset_type_id => type_name */
    private array $assetNames = [];

    public function __construct()
    {
        $this->assetKeys = $this->buildAssetIndex();
    }

    /**
     * @return array{
     *   ok: bool, message?: string,
     *   sheet?: string, header_row?: int,
     *   fields?: array<string,int>, field_headers?: array<string,string>,
     *   assets?: array<int,int>, asset_headers?: array<int,string>,
     *   ignored?: array<int,string>, rows?: array<int,array{0:int,1:array}>
     * }
     */
    public function read(Spreadsheet $book): array
    {
        $best     = null;
        $fallback = null;

        $sheetCount = min($book->getSheetCount(), self::SCAN_SHEETS);

        for ($s = 0; $s < $sheetCount; $s++) {
            $sheet = $book->getSheet($s);
            $grid  = $sheet->toArray(null, true, false, false);

            $scan = min(count($grid), self::SCAN_ROWS);

            for ($r = 0; $r < $scan; $r++) {
                $mapping = $this->mapHeadings($grid[$r] ?? []);
                $score   = count($mapping['fields']) + count($mapping['assets']);

                // The row with the most text in it, remembered only to
                // describe what was found if nothing qualifies.
                $texts = array_filter(
                    $grid[$r] ?? [],
                    fn ($v) => is_string($v) && trim($v) !== '' && ! is_numeric($v)
                );
                if (! $fallback || count($texts) > $fallback['text_count']) {
                    $fallback = [
                        'sheet'      => $sheet->getTitle(),
                        'row'        => $r + 1,
                        'headings'   => array_values(array_map('trim', $texts)),
                        'text_count' => count($texts),
                    ];
                }

                if (! isset($mapping['fields']['segment_code'], $mapping['fields']['csc'])) {
                    continue;
                }

                if (! $best || $score > $best['score']) {
                    $best = [
                        'score'   => $score,
                        'sheet'   => $sheet->getTitle(),
                        'row'     => $r,
                        'grid'    => $grid,
                        'mapping' => $mapping,
                    ];
                }
            }
        }

        if (! $best) {
            return [
                'ok'      => false,
                'message' => $this->explainMissing($fallback),
            ];
        }

        $m = $best['mapping'];

        $rows = [];
        foreach (array_slice($best['grid'], $best['row'] + 1, null, true) as $i => $raw) {
            $hasValue = array_filter($raw, fn ($v) => $v !== null && trim((string) $v) !== '');
            if ($hasValue) {
                // Sheet row numbers are 1-based.
                $rows[] = [$i + 1, $raw];
            }
        }

        return [
            'ok'            => true,
            'sheet'         => $best['sheet'],
            'header_row'    => $best['row'] + 1,
            'fields'        => $m['fields'],
            'field_headers' => $m['field_headers'],
            'assets'        => $m['assets'],
            'asset_headers' => $m['asset_headers'],
            'ignored'       => $m['ignored'],
            'rows'          => $rows,
        ];
    }

    /** The asset type's name, for reporting which columns were read. */
    public function assetName(int $assetTypeId): string
    {
        return $this->assetNames[$assetTypeId] ?? "type {$assetTypeId}";
    }

    /** "Hali Ela" and "hali-ela" become the same key. */
    public static function key(string $text): string
    {
        $h = preg_replace('/\s*\((?:nos|km|m|kva|kw)\)\s*$/i', '', trim($text));

        return trim(preg_replace('/[^a-z0-9]+/', '_', strtolower($h)), '_');
    }

    /* ============================== INTERNALS ========================= */

    private function mapHeadings(array $cells): array
    {
        $fields = [];
        $fieldHeaders = [];
        $assets = [];
        $assetHeaders = [];
        $claimed = [];

        $keys = [];
        foreach ($cells as $i => $cell) {
            if ($cell === null || is_numeric($cell) || trim((string) $cell) === '') {
                continue;
            }
            $keys[$i] = self::key((string) $cell);
        }

        // 1. Exact field names.
        foreach (self::FIELDS as $field => $names) {
            foreach ($keys as $i => $key) {
                if (! isset($claimed[$i]) && ! isset($fields[$field]) && in_array($key, $names, true)) {
                    $fields[$field]       = $i;
                    $fieldHeaders[$field] = trim((string) $cells[$i]);
                    $claimed[$i]          = true;
                }
            }
        }

        // 2. Asset columns, before the loose patterns, so "HV Line" is an
        //    asset quantity and not mistaken for anything else.
        foreach ($keys as $i => $key) {
            if (! isset($claimed[$i]) && isset($this->assetKeys[$key])) {
                $assets[$i]       = $this->assetKeys[$key];
                $assetHeaders[$i] = trim((string) $cells[$i]);
                $claimed[$i]      = true;
            }
        }

        // 3. Loose patterns on whatever is left.
        foreach (self::PATTERNS as $field => $pattern) {
            if (isset($fields[$field])) {
                continue;
            }
            foreach ($keys as $i => $key) {
                if (isset($claimed[$i]) || ! preg_match($pattern, $key)) {
                    continue;
                }
                // "Segment count" or "segment type" is not an identifier.
                if ($field === 'segment_code' && preg_match('/(count|length|km|type|total)/', $key)) {
                    continue;
                }
                $fields[$field]       = $i;
                $fieldHeaders[$field] = trim((string) $cells[$i]);
                $claimed[$i]          = true;
                break;
            }
        }

        $ignored = [];
        foreach ($keys as $i => $key) {
            if (! isset($claimed[$i])) {
                $ignored[] = trim((string) $cells[$i]);
            }
        }

        return [
            'fields'        => $fields,
            'field_headers' => $fieldHeaders,
            'assets'        => $assets,
            'asset_headers' => $assetHeaders,
            'ignored'       => $ignored,
        ];
    }

    /**
     * Every way an asset column might be headed, keeping only the keys
     * that point at exactly one type -- "dist" could be a distribution
     * transformer or a distribution substation, so it matches neither.
     */
    private function buildAssetIndex(): array
    {
        $candidates = [];

        foreach (DB::table('asset_types')->get(['asset_type_id', 'type_code', 'type_name']) as $t) {
            $id = (int) $t->asset_type_id;
            $this->assetNames[$id] = $t->type_name;

            $forms = [
                $t->type_name,
                preg_replace('/\s*\([^)]*\)\s*/', ' ', $t->type_name),
                $t->type_code,
            ];

            // The short form in brackets: "Auto Recloser (AR)" -> AR.
            if (preg_match('/\(([^)]+)\)/', $t->type_name, $m)) {
                $forms[] = $m[1];
            }

            // The distinguishing half of the code: CN_COPPER -> copper.
            if (str_contains($t->type_code, '_')) {
                $forms[] = substr($t->type_code, strpos($t->type_code, '_') + 1);
            }

            // Single words of the name, so "Recloser" finds Auto Recloser
            // and "Gantry" finds Gantry. Words shared by several types --
            // "pole", "switch", "line" -- are dropped below as ambiguous.
            $bare = preg_replace('/\s*\([^)]*\)\s*/', ' ', $t->type_name);
            foreach (preg_split('/[^A-Za-z]+/', $bare) as $word) {
                if (strlen($word) >= 4) {
                    $forms[] = $word;
                }
            }

            foreach ($forms as $form) {
                $key = self::key((string) $form);
                if (strlen($key) < 2 || ctype_digit($key)) {
                    continue;
                }
                $candidates[$key][$id] = true;
            }
        }

        $index = [];
        foreach ($candidates as $key => $ids) {
            if (count($ids) === 1) {
                $index[$key] = (int) array_key_first($ids);
            }
        }

        // Field names are never asset names, whatever a code suffix says.
        foreach (self::FIELDS as $names) {
            foreach ($names as $name) {
                unset($index[$name]);
            }
        }

        return $index;
    }

    private function explainMissing(?array $fallback): string
    {
        $wanted = "Name one column 'Seg ID' (or 'Segment ID' / 'segment_code') and one 'CSC' "
            . "(or 'Depot' / 'csc_code'). Every other column is optional, and columns the "
            . 'system does not recognise are simply ignored.';

        if (! $fallback || empty($fallback['headings'])) {
            return 'No heading row was found in this file — it looks empty. ' . $wanted;
        }

        $shown = implode(', ', array_slice($fallback['headings'], 0, 12));
        if (count($fallback['headings']) > 12) {
            $shown .= ', …';
        }

        $mapping = $this->mapHeadings($fallback['headings']);
        $missing = [];
        if (! isset($mapping['fields']['segment_code'])) {
            $missing[] = 'a segment ID';
        }
        if (! isset($mapping['fields']['csc'])) {
            $missing[] = 'a CSC';
        }

        return 'Could not find ' . implode(' or ', $missing ?: ['the segment columns'])
            . " in this file. The headings on row {$fallback['row']} of sheet "
            . "'{$fallback['sheet']}' are: {$shown}. " . $wanted;
    }
}
