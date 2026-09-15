<?php

namespace App\Support;

use PhpOffice\PhpSpreadsheet\Spreadsheet;

/**
 * Finds transformer tables in an uploaded workbook.
 *
 * The province's transformer workbooks look nothing like a segment
 * sheet: one sheet per CSC, named for it ("Badulla"), a title block
 * above the table, and headings such as "Old Sin No", "Name Of the
 * Substation", "Capacity (kVA)", "SERIAL NO", "Manuf." and the fly-length
 * and wayleave distances. None of those is a segment ID or a CSC, so the
 * segment importer refused them outright.
 *
 * This recognises such a table on any sheet, reads the columns it knows,
 * and reports every other column as ignored. A sheet counts as a
 * transformer table when it has something that identifies a transformer
 * (a SIN or serial number) and something that describes one (the
 * substation or the capacity).
 */
class TransformerSheetReader
{
    private const SCAN_ROWS = 25;

    /** A workbook with a sheet per CSC can have seventeen. */
    private const SCAN_SHEETS = 40;

    /** Normalised heading names (see SheetReader::key) per stored field. */
    public const FIELDS = [
        'old_sin_no'             => ['old_sin_no', 'old_sin', 'old_sin_number', 'sin_old'],
        'new_sin_no'             => ['new_sin_no', 'new_sin', 'new_sin_number', 'sin_new'],
        'sin_no'                 => ['sin_no', 'sin', 'sin_number'],
        'substation_name'        => [
            'name_of_the_substation', 'name_of_substation', 'substation_name',
            'substation', 'sub_station', 'sub_station_name',
        ],
        'transformer_type'       => ['type', 'transformer_type', 'tx_type', 'type_of_transformer'],
        'capacity_kva'           => ['capacity', 'capacity_kva', 'kva', 'rating', 'rating_kva', 'transformer_capacity'],
        'serial_no'              => [
            'serial_no', 'serial', 'serial_number', 'transformer_serial_no',
            'transformer_no', 'tx_no', 'works_no',
        ],
        'manufacturer'           => ['manuf', 'manufacturer', 'make', 'manufacturer_name', 'brand', 'manufactured_by'],
        'fly_length_km'          => ['fly_length', 'fly_length_km'],
        'combined_fly_length_km' => ['combined_fly_length', 'combined_fly_length_km'],
        'free_wayleave_km'       => ['free_waleave', 'free_wayleave', 'free_way_leave'],
        'wayleave_distance_km'   => ['distance_to_waleave', 'distance_to_wayleave', 'distance_to_way_leave'],
        'total_distance_km'      => ['total_distance', 'total_distance_km'],
        'csc'                    => ['csc', 'csc_code', 'csc_name', 'depot', 'depot_name'],
        'area'                   => ['area', 'area_name', 'area_code'],
        'condition_status'       => ['condition', 'condition_status'],
        'remarks'                => ['remarks', 'remark', 'notes', 'comment', 'comments'],
    ];

    /** How each field is named back to the person importing. */
    public const LABELS = [
        'old_sin_no'             => 'Old SIN no.',
        'new_sin_no'             => 'New SIN no.',
        'sin_no'                 => 'SIN no.',
        'substation_name'        => 'Substation',
        'transformer_type'       => 'Type',
        'capacity_kva'           => 'Capacity (kVA)',
        'serial_no'              => 'Serial no.',
        'transformer_no'         => 'Serial no.',
        'manufacturer'           => 'Manufacturer',
        'fly_length_km'          => 'Fly length (km)',
        'combined_fly_length_km' => 'Combined fly length (km)',
        'free_wayleave_km'       => 'Free wayleave (km)',
        'wayleave_distance_km'   => 'Distance to wayleave (km)',
        'total_distance_km'      => 'Total distance (km)',
        'csc'                    => 'CSC',
        'area'                   => 'Area',
        'condition_status'       => 'Condition',
        'remarks'                => 'Remarks',
    ];

    /**
     * Every transformer table in the workbook, one entry per sheet.
     * An empty array means this is not a transformer workbook at all.
     */
    public function read(Spreadsheet $book): array
    {
        $found = [];
        $count = min($book->getSheetCount(), self::SCAN_SHEETS);

        for ($s = 0; $s < $count; $s++) {
            $sheet = $book->getSheet($s);
            $grid  = $sheet->toArray(null, true, false, false);
            $best  = null;

            for ($r = 0; $r < min(count($grid), self::SCAN_ROWS); $r++) {
                $map = $this->mapHeadings($grid[$r] ?? []);

                if (! $this->qualifies($map['fields'])) {
                    continue;
                }

                if (! $best || count($map['fields']) > count($best['map']['fields'])) {
                    $best = ['row' => $r, 'map' => $map];
                }
            }

            if (! $best) {
                continue;
            }

            $rows = [];
            foreach (array_slice($grid, $best['row'] + 1, null, true) as $i => $raw) {
                $hasValue = array_filter($raw, fn ($v) => $v !== null && trim((string) $v) !== '');
                if ($hasValue) {
                    $rows[] = [$i + 1, $raw];
                }
            }

            $found[] = [
                'sheet'         => $sheet->getTitle(),
                'header_row'    => $best['row'] + 1,
                'fields'        => $best['map']['fields'],
                'field_headers' => $best['map']['field_headers'],
                'ignored'       => $best['map']['ignored'],
                'rows'          => $rows,
            ];
        }

        return $found;
    }

    /**
     * SIN and serial numbers compared without spaces, hyphens or case,
     * so "UBB 055", "UBB-055" and "ubb055" are one transformer.
     */
    public static function idKey(?string $value): string
    {
        return strtoupper(preg_replace('/[^A-Za-z0-9]/', '', (string) $value));
    }

    private function qualifies(array $fields): bool
    {
        $identifies = isset($fields['old_sin_no']) || isset($fields['new_sin_no'])
            || isset($fields['sin_no']) || isset($fields['serial_no']);

        $describes = isset($fields['substation_name']) || isset($fields['capacity_kva']);

        return $identifies && $describes;
    }

    private function mapHeadings(array $cells): array
    {
        $fields  = [];
        $headers = [];
        $ignored = [];

        foreach ($cells as $i => $cell) {
            if ($cell === null || is_numeric($cell) || trim((string) $cell) === '') {
                continue;
            }

            $key = SheetReader::key((string) $cell);
            $hit = null;

            foreach (self::FIELDS as $field => $names) {
                if (! isset($fields[$field]) && in_array($key, $names, true)) {
                    $hit = $field;
                    break;
                }
            }

            if ($hit) {
                $fields[$hit]  = $i;
                $headers[$hit] = trim((string) $cell);
            } else {
                $ignored[] = trim((string) $cell);
            }
        }

        return ['fields' => $fields, 'field_headers' => $headers, 'ignored' => $ignored];
    }
}
