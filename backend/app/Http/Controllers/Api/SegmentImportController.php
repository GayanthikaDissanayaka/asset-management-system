<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Support\PlaceResolver;
use App\Support\SheetReader;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use PhpOffice\PhpSpreadsheet\IOFactory;

/**
 * Loading segments from an uploaded spreadsheet.
 *
 * Its own file because it writes to the register -- segment_register,
 * segment_csc and segment_asset. Read-only spreadsheet work (exports,
 * reports, the template) stays in SpreadsheetController.
 *
 * TAKE WHAT IS WANTED, IGNORE THE REST. SheetReader finds the heading row
 * wherever it is and recognises each column under the names people use,
 * so a sheet with a title block, "Seg ID" instead of segment_code, and
 * a dozen unrelated columns loads without editing. What was used and
 * what was ignored is reported back, so nothing is dropped silently.
 *
 * A row with a problem that does not make the segment wrong -- an unknown
 * feeder, an unreadable voltage -- still loads, with a warning. A row
 * whose place cannot be worked out is refused, because a segment filed
 * under the wrong CSC is worse than one that did not load.
 *
 * Rows sharing a segment ID are one segment with several CSC portions.
 * Everything is checked before anything is written, and the write runs
 * in one transaction.
 */
class SegmentImportController extends Controller
{
    public function import(Request $request)
    {
        $request->validate([
            'file'    => ['required', 'file', 'mimes:xlsx,xls,csv,txt', 'max:10240'],
            // Transformer workbooks preview first; confirm=1 applies.
            'confirm' => ['nullable', 'boolean'],
        ]);

        $upload    = $request->file('file');
        $extension = strtolower($upload->getClientOriginalExtension());

        /*
         * .xlsx is a zip archive, so reading it needs PHP's zip extension.
         * The older .xls format is not zipped and does not.
         */
        if ($extension === 'xlsx' && ! class_exists(\ZipArchive::class)) {
            return response()->json([
                'message' => 'This server cannot read .xlsx files because PHP\'s zip extension is switched off. '
                    . 'Save the sheet as CSV and upload that, or enable it by removing the semicolon from '
                    . '";extension=zip" in php.ini and restarting Apache.',
                'code'    => 'ZIP_EXTENSION_MISSING',
            ], 422);
        }

        try {
            $reader = match ($extension) {
                'csv', 'txt' => IOFactory::createReader('Csv'),
                'xls'        => IOFactory::createReader('Xls'),
                default      => IOFactory::createReader('Xlsx'),
            };
            $reader->setReadDataOnly(true);

            $book = $reader->load($upload->getRealPath());
        } catch (\Throwable $e) {
            return response()->json([
                'message' => 'That file could not be read as a spreadsheet: ' . $e->getMessage(),
            ], 422);
        }

        /*
         * A transformer workbook rather than a segment sheet? Its tables
         * are recognised by their SIN, serial and substation columns, and
         * a separate importer handles them -- one that previews changes
         * to existing transformers before writing anything.
         */
        $transformers = app(TransformerImportController::class)->importBook($book, $request);
        if ($transformers !== null) {
            return $transformers;
        }

        $sheetReader = new SheetReader();
        $sheet       = $sheetReader->read($book);

        if (! $sheet['ok']) {
            return response()->json(['message' => $sheet['message']], 422);
        }

        $col = $sheet['fields'];
        $cell = fn (array $raw, string $field) => isset($col[$field])
            ? trim((string) ($raw[$col[$field]] ?? ''))
            : '';

        $places  = new PlaceResolver();
        $feeders = $this->feederIndex();

        $groups      = [];
        $errors      = [];
        $warnings    = [];
        $resolutions = [];

        foreach ($sheet['rows'] as [$lineNo, $raw]) {
            $code = $cell($raw, 'segment_code');
            $csc  = $cell($raw, 'csc');
            $area = $cell($raw, 'area');

            if ($code === '' && $csc === '') {
                // A totals line, a note under the table: not a segment.
                continue;
            }

            if ($code === '') {
                $errors[] = ['row' => $lineNo, 'message' => 'No segment ID on this row.'];
                continue;
            }

            /* Resolved once per distinct place rather than per row. */
            $placeKey = mb_strtolower($csc . '|' . $area);

            if (! isset($resolutions[$placeKey])) {
                $hit = $places->resolve($csc, $area);

                $resolutions[$placeKey] = [
                    'given_csc'  => $csc,
                    'given_area' => $area ?: null,
                    'ok'         => $hit['ok'],
                    'csc_id'     => $hit['csc_id'],
                    'csc_code'   => $hit['csc']->csc_code ?? null,
                    'csc_name'   => $hit['csc']->csc_name ?? null,
                    'area_name'  => $hit['csc']->area_name ?? null,
                    'matched_by' => $hit['matched_by'],
                    'message'    => $hit['message'],
                    'rows'       => 0,
                ];
            }

            $resolutions[$placeKey]['rows']++;
            $place = $resolutions[$placeKey];

            if (! $place['ok']) {
                $errors[] = ['row' => $lineNo, 'message' => $place['message']];
                continue;
            }

            $voltage = $this->voltage($cell($raw, 'voltage_level'));
            if ($voltage === false) {
                $warnings[] = [
                    'row'     => $lineNo,
                    'message' => "Voltage '{$cell($raw, 'voltage_level')}' not recognised; recorded as 33kV.",
                ];
                $voltage = null;
            }

            $feederText = $cell($raw, 'feeder_code');
            $feederId   = null;
            if ($feederText !== '') {
                $feederId = $feeders[SheetReader::key($feederText)] ?? null;
                if ($feederId === null) {
                    $warnings[] = [
                        'row'     => $lineNo,
                        'message' => "Feeder '{$feederText}' is not in the register; the segment was loaded without one.",
                    ];
                }
            }

            $groups[$code] ??= [
                'code'      => $code,
                'portions'  => [],
                'items'     => [],
                'feeder_id' => null,
                'voltage'   => '33kV',
                'remarks'   => null,
                'first_row' => $lineNo,
            ];
            $g = &$groups[$code];

            $cscId = (int) $place['csc_id'];
            $g['portions'][$cscId] = ($g['portions'][$cscId] ?? 0)
                + $this->numeric($raw[$col['length_km'] ?? -1] ?? null);

            if ($feederId !== null && $g['feeder_id'] === null) {
                $g['feeder_id'] = $feederId;
            }
            if ($voltage) {
                $g['voltage'] = $voltage;
            }

            $remark = $cell($raw, 'remarks');
            if ($remark !== '' && $g['remarks'] === null) {
                $g['remarks'] = mb_substr($remark, 0, 2000);
            }

            // Asset quantities are summed across a segment's rows.
            foreach ($sheet['assets'] as $index => $typeId) {
                $value = $this->numeric($raw[$index] ?? null);
                if ($value > 0) {
                    $g['items'][$typeId] = ($g['items'][$typeId] ?? 0) + $value;
                }
            }

            unset($g);
        }

        $columns = $this->describeColumns($sheet, $sheetReader);

        if (! isset($col['length_km'])) {
            $warnings[] = [
                'row'     => $sheet['header_row'],
                'message' => 'No length column was found, so segments were loaded with 0 km. '
                    . "Head a column 'Length (km)' to load lengths.",
            ];
        }

        if (empty($groups)) {
            return response()->json([
                'message'  => 'No usable rows were found.',
                'created'  => 0,
                'columns'  => $columns,
                'places'   => $this->placeList($resolutions),
                'skipped'  => [],
                'errors'   => $errors,
                'warnings' => $warnings,
            ], 422);
        }

        [$created, $skipped] = $this->write($groups);

        $placeList   = $this->placeList($resolutions);
        $interpreted = $placeList->where('ok', true)->whereIn('matched_by', ['alias', 'fuzzy'])->count();

        return response()->json([
            'message' => $created > 0
                ? "Loaded {$created} segments into "
                    . $placeList->where('ok', true)->count() . ' CSCs.'
                    . ($interpreted > 0
                        ? " {$interpreted} place name(s) were matched by alias or spelling — check the list."
                        : '')
                : 'Nothing was loaded.',
            'created'  => $created,
            'columns'  => $columns,
            'places'   => $placeList,
            'skipped'  => $skipped,
            'errors'   => $errors,
            'warnings' => $warnings,
        ], $created > 0 ? 201 : 422);
    }

    /* ============================== WRITE ============================= */

    private function write(array $groups): array
    {
        $created = 0;
        $skipped = [];

        DB::transaction(function () use ($groups, &$created, &$skipped) {
            $units = DB::table('asset_types')->pluck('unit_of_measure', 'asset_type_id');

            foreach ($groups as $g) {
                // Largest portion owns the register row, as the form does.
                arsort($g['portions']);
                $primaryCscId = (int) array_key_first($g['portions']);
                $totalKm      = round(array_sum($g['portions']), 4);
                $isSplit      = count($g['portions']) > 1;

                $clash = DB::table('segment_register')
                    ->where('csc_id', $primaryCscId)
                    ->where('segment_code', $g['code'])
                    ->exists();

                if ($clash) {
                    $skipped[] = [
                        'row'     => $g['first_row'],
                        'code'    => $g['code'],
                        'message' => 'Already in the register for this CSC.',
                    ];
                    continue;
                }

                $registerId = DB::table('segment_register')->insertGetId([
                    'csc_id'        => $primaryCscId,
                    'feeder_id'     => $g['feeder_id'],
                    'segment_id'    => null,
                    'segment_code'  => $g['code'],
                    'length_km'     => $totalKm,
                    'voltage_level' => $g['voltage'],
                    'status'        => 'ACTIVE',
                    'remarks'       => $g['remarks'],
                    'source_file'   => 'excel-import',
                    'created_at'    => now(),
                    'updated_at'    => now(),
                ]);

                if ($isSplit) {
                    foreach ($g['portions'] as $cscId => $km) {
                        DB::table('segment_csc')->insert([
                            'register_id' => $registerId,
                            'csc_id'      => $cscId,
                            'length_km'   => round($km, 4),
                            'created_at'  => now(),
                            'updated_at'  => now(),
                        ]);
                    }
                }

                foreach ($g['items'] as $typeId => $qty) {
                    DB::table('segment_asset')->insert([
                        'register_id'     => $registerId,
                        'asset_type_id'   => $typeId,
                        'quantity'        => round($qty, 4),
                        'unit_of_measure' => $units[$typeId] ?? 'nos',
                        'created_at'      => now(),
                        'updated_at'      => now(),
                    ]);
                }

                $created++;
            }
        });

        return [$created, $skipped];
    }

    /* ============================= HELPERS ============================ */

    /** What the file was read as: which heading fed which field. */
    private function describeColumns(array $sheet, SheetReader $reader): array
    {
        $used = [];
        foreach ($sheet['field_headers'] as $field => $header) {
            $used[] = ['heading' => $header, 'read_as' => SheetReader::FIELD_LABELS[$field] ?? $field];
        }

        $assets = [];
        foreach ($sheet['asset_headers'] as $index => $header) {
            $assets[] = ['heading' => $header, 'read_as' => $reader->assetName($sheet['assets'][$index])];
        }

        return [
            'sheet'      => $sheet['sheet'],
            'header_row' => $sheet['header_row'],
            'used'       => $used,
            'assets'     => $assets,
            'ignored'    => $sheet['ignored'],
        ];
    }

    private function placeList(array $resolutions)
    {
        return collect($resolutions)
            ->sortByDesc('rows')
            ->values()
            ->map(fn ($p) => [
                'given'       => $p['given_area'] ? "{$p['given_csc']} ({$p['given_area']})" : $p['given_csc'],
                'assigned_to' => $p['ok'] ? "{$p['csc_name']} CSC · {$p['area_name']} area" : null,
                'csc_code'    => $p['csc_code'],
                'matched_by'  => $p['matched_by'],
                'rows'        => $p['rows'],
                'ok'          => $p['ok'],
                'message'     => $p['message'],
            ]);
    }

    /** Feeder codes matched loosely: "Badulla F8" finds BADULLAF8. */
    private function feederIndex(): array
    {
        $index = [];
        foreach (DB::table('feeders')->get(['feeder_id', 'feeder_code', 'feeder_name']) as $f) {
            foreach ([$f->feeder_code, $f->feeder_name] as $form) {
                $key = SheetReader::key((string) $form);
                if ($key !== '') {
                    $index[$key] ??= (int) $f->feeder_id;
                    $index[str_replace('_', '', $key)] ??= (int) $f->feeder_id;
                }
            }
        }

        return $index;
    }

    /**
     * "33 kV", "33KV", "33" -> 33kV; "0.4", "400" -> 400V.
     * null when blank, false when present but unreadable.
     */
    private function voltage(string $text): string|null|false
    {
        if ($text === '') {
            return null;
        }

        $digits = preg_replace('/[^0-9.]/', '', $text);

        return match (true) {
            $digits === '33'                        => '33kV',
            $digits === '11'                        => '11kV',
            in_array($digits, ['400', '0.4'], true) => '400V',
            default                                 => false,
        };
    }

    private function numeric($value): float
    {
        if ($value === null || $value === '') {
            return 0.0;
        }
        $clean = preg_replace('/[^0-9.\-]/', '', (string) $value);

        return is_numeric($clean) ? (float) $clean : 0.0;
    }
}
