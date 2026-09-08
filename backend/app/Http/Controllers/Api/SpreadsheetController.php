<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use PhpOffice\PhpSpreadsheet\IOFactory;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Style\Alignment;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Excel in and out.
 *
 * The register began life as spreadsheets — every one of the 1,325
 * imported segments still carries the workbook it came from in
 * source_file — so getting data back out as a workbook, and loading a new
 * one in, is how this register is actually worked with.
 *
 * The asset columns of the template are generated from asset_types rather
 * than hard-coded. Add a conductor to the catalogue and the next template
 * download has a column for it, and the importer accepts it, with no code
 * change here.
 */
class SpreadsheetController extends Controller
{
    /* ============================== EXPORT ============================ */

    /**
     * The whole register as one workbook, a sheet per view.
     *
     * `?view=` narrows it to a single sheet for anyone who only wants one.
     */
    public function export(Request $request): StreamedResponse
    {
        $validated = $request->validate([
            'view' => ['nullable', 'string', 'in:areas,cscs,feeders,segments,assets,asset-by-csc'],
        ]);

        $sheets = [
            'areas'        => ['Areas', fn () => $this->rowsFrom('v_line_length_by_area', 'total_km')],
            'cscs'         => ['CSCs', fn () => $this->rowsFrom('v_line_length_by_csc', 'total_km')],
            'feeders'      => ['Feeders', fn () => $this->rowsFrom('v_line_length_by_feeder', 'total_km')],
            'segments'     => ['Segments', fn () => $this->segmentRows()],
            'assets'       => ['Assets', fn () => $this->rowsFrom('v_asset_totals', 'total_quantity')],
            'asset-by-csc' => ['Assets by CSC', fn () => $this->rowsFrom('v_asset_by_csc', 'total_quantity')],
        ];

        if (! empty($validated['view'])) {
            $sheets = [$validated['view'] => $sheets[$validated['view']]];
        }

        $book = new Spreadsheet();
        $book->removeSheetByIndex(0);

        foreach ($sheets as [$title, $loader]) {
            $rows = $loader();
            $sheet = $book->createSheet();
            $sheet->setTitle($title);
            $this->writeTable($sheet, $rows);
        }

        $book->setActiveSheetIndex(0);

        $name = 'uva-network-register-' . now()->format('Y-m-d') . '.xlsx';

        return $this->download($book, $name);
    }

    /**
     * The register as a written report rather than a data dump.
     *
     * Three levels, because that is how the register is read and signed
     * off: the province as a whole, then each area, then each CSC. Every
     * level answers the same question — what is installed here, how much
     * of it, and over how much line — so the three can be compared
     * without re-deriving anything.
     *
     * The raw sheets follow the report, so anyone who wants to pivot the
     * numbers themselves has them in the same file.
     */
    public function report(): StreamedResponse
    {
        $book = new Spreadsheet();
        $book->removeSheetByIndex(0);

        $data = $this->gatherReportData();

        $this->buildProvinceSheet($book, $data);
        $this->buildAreaSheet($book, $data);
        $this->buildCscSheet($book, $data);

        // The underlying tables, after the narrative.
        foreach ([
            'Data · Areas'    => fn () => $this->rowsFrom('v_line_length_by_area', 'total_km'),
            'Data · CSCs'     => fn () => $this->rowsFrom('v_line_length_by_csc', 'total_km'),
            'Data · Feeders'  => fn () => $this->rowsFrom('v_line_length_by_feeder', 'total_km'),
            'Data · Segments' => fn () => $this->segmentRows(),
            'Data · Assets'   => fn () => $this->rowsFrom('v_asset_totals', 'total_quantity'),
        ] as $title => $loader) {
            $sheet = $book->createSheet();
            $sheet->setTitle($title);
            $this->writeTable($sheet, $loader());
        }

        $book->setActiveSheetIndex(0);

        return $this->download(
            $book,
            'uva-network-asset-report-' . now()->format('Y-m-d') . '.xlsx'
        );
    }

    /**
     * A blank workbook shaped exactly as the importer expects, with the
     * codes to use listed on a second sheet so nobody has to guess them.
     */
    public function template(Request $request): StreamedResponse
    {
        $asCsv = $request->query('format') === 'csv';

        $book = new Spreadsheet();

        $sheet = $book->getActiveSheet();
        $sheet->setTitle('Segments');

        $headers = array_merge(
            ['segment_code', 'csc_code', 'length_km', 'feeder_code', 'voltage_level', 'remarks'],
            $this->assetColumnHeaders()
        );

        $sheet->fromArray($headers, null, 'A1');

        // One worked example, including a segment split over two CSCs.
        $sheet->fromArray([
            ['BDSM900', 'BDL-CSC01', 6.400, '', '33kV', 'example — delete this row'],
            ['BDSM900', 'MAH-CSC02', 3.850, '', '33kV', 'same segment, the part inside the next CSC'],
        ], null, 'A2');

        $this->styleHeader($sheet, count($headers));
        $sheet->freezePane('D2');

        /* CSV holds one sheet, so the notes and code list are dropped and
           only the fillable grid is returned. Worth offering, because a
           CSV can be loaded back without PHP's zip extension. */
        if ($asCsv) {
            return $this->downloadCsv($book, 'uva-segment-import-template.csv');
        }

        $notes = $book->createSheet();
        $notes->setTitle('How to use');
        $notes->fromArray([
            ['How this sheet is read'],
            [''],
            ['One row per CSC that a segment runs through.'],
            ['A segment inside a single CSC is one row.'],
            ['A segment crossing a boundary repeats the same segment_code on'],
            ['each row, with that row\'s csc_code and the kilometres inside it.'],
            ['Those portions are what area totals add up, so each area is'],
            ['credited only with the line inside it.'],
            [''],
            ['length_km is the length in THAT row\'s CSC, not the whole segment.'],
            ['The whole length is worked out by adding the rows up.'],
            [''],
            ['Asset columns are quantities on the segment. The unit is in the'],
            ['column heading. Leave blank where there are none. When a segment'],
            ['spans several rows the asset columns are added together.'],
            [''],
            ['segment_code and csc_code are required. Everything else is'],
            ['optional. A segment_code already present for that CSC is'],
            ['skipped and reported, never overwritten.'],
        ], null, 'A1');
        $notes->getColumnDimension('A')->setWidth(70);
        $notes->getStyle('A1')->getFont()->setBold(true);

        $refs = $book->createSheet();
        $refs->setTitle('Codes');
        $refRows = [['CSC code', 'CSC name', 'Area', 'Feeder codes for this CSC']];

        $feedersByCsc = DB::table('feeders')
            ->select('origin_csc_id', 'feeder_code')
            ->get()
            ->groupBy('origin_csc_id');

        foreach (
            DB::table('csc_depots as d')
                ->join('areas as a', 'a.area_id', '=', 'd.area_id')
                ->select('d.csc_id', 'd.csc_code', 'd.csc_name', 'a.area_name')
                ->orderBy('a.area_name')->orderBy('d.csc_name')->get() as $csc
        ) {
            $refRows[] = [
                $csc->csc_code,
                $csc->csc_name,
                $csc->area_name,
                $feedersByCsc->get($csc->csc_id, collect())->pluck('feeder_code')->implode(', '),
            ];
        }

        $refs->fromArray($refRows, null, 'A1');
        $this->styleHeader($refs, 4);
        foreach (range('A', 'D') as $col) {
            $refs->getColumnDimension($col)->setAutoSize(true);
        }

        $book->setActiveSheetIndex(0);

        return $this->download($book, 'uva-segment-import-template.xlsx');
    }

    /* ============================== IMPORT ============================ */

    /**
     * Loads a workbook of segments.
     *
     * Rows sharing a segment_code are one segment with several CSC
     * portions. Everything is validated and grouped before anything is
     * written, and the whole load runs in one transaction, so a workbook
     * with a bad row halfway down does not leave half a register behind.
     */
    public function import(Request $request)
    {
        $request->validate([
            'file' => ['required', 'file', 'mimes:xlsx,xls,csv,txt', 'max:10240'],
        ]);

        $upload    = $request->file('file');
        $extension = strtolower($upload->getClientOriginalExtension());

        /*
         * Reading .xlsx means unzipping it, and PHP's zip extension is
         * optional. Writing does not need it, so export works either way;
         * without it, import has to say so plainly rather than dying in
         * PhpSpreadsheet with "Class ZipArchive not found".
         */
        if (in_array($extension, ['xlsx', 'xls'], true) && ! class_exists(\ZipArchive::class)) {
            return response()->json([
                'message' => 'This server cannot read .xlsx files because PHP\'s zip extension is switched off. '
                    . 'Save the sheet as CSV and upload that, or enable it by removing the semicolon from '
                    . '";extension=zip" in php.ini and restarting Apache.',
                'code'    => 'ZIP_EXTENSION_MISSING',
            ], 422);
        }

        try {
            // Chosen by extension rather than sniffed, so a CSV is never
            // mistaken for something that needs unzipping.
            $reader = match ($extension) {
                'csv', 'txt' => IOFactory::createReader('Csv'),
                'xls'        => IOFactory::createReader('Xls'),
                default      => IOFactory::createReader('Xlsx'),
            };
            $reader->setReadDataOnly(true);

            $sheet = $reader->load($upload->getRealPath())->getSheet(0);
        } catch (\Throwable $e) {
            return response()->json([
                'message' => 'That file could not be read as a spreadsheet: ' . $e->getMessage(),
            ], 422);
        }

        $rows = $sheet->toArray(null, true, false, false);

        if (count($rows) < 2) {
            return response()->json([
                'message' => 'The first sheet has no data rows below its headings.',
            ], 422);
        }

        $headers = array_map(
            fn ($h) => $this->normaliseHeader((string) $h),
            array_shift($rows)
        );

        $required = ['segment_code', 'csc_code'];
        foreach ($required as $needed) {
            if (! in_array($needed, $headers, true)) {
                return response()->json([
                    'message' => "The sheet is missing a '{$needed}' column. Download the template to see the expected headings.",
                ], 422);
            }
        }

        $cscByCode    = DB::table('csc_depots')->pluck('csc_id', 'csc_code');
        $feederByCode = DB::table('feeders')->pluck('feeder_id', 'feeder_code');
        $typeByName   = $this->assetTypesByNormalisedName();
        $voltages     = ['33kV', '11kV', '400V'];

        $groups = [];
        $errors = [];

        foreach ($rows as $index => $raw) {
            $lineNo = $index + 2; // header is row 1
            $row = $this->rowToMap($headers, $raw);

            $code = trim((string) ($row['segment_code'] ?? ''));
            $csc  = trim((string) ($row['csc_code'] ?? ''));

            if ($code === '' && $csc === '') {
                continue; // blank spacer row
            }

            if ($code === '') {
                $errors[] = ['row' => $lineNo, 'message' => 'segment_code is empty.'];
                continue;
            }
            if (! isset($cscByCode[$csc])) {
                $errors[] = ['row' => $lineNo, 'message' => "Unknown csc_code '{$csc}'."];
                continue;
            }

            $voltage = trim((string) ($row['voltage_level'] ?? ''));
            if ($voltage !== '' && ! in_array($voltage, $voltages, true)) {
                $errors[] = ['row' => $lineNo, 'message' => "voltage_level '{$voltage}' is not one of 33kV, 11kV, 400V."];
                continue;
            }

            $feederCode = trim((string) ($row['feeder_code'] ?? ''));
            if ($feederCode !== '' && ! isset($feederByCode[$feederCode])) {
                $errors[] = ['row' => $lineNo, 'message' => "Unknown feeder_code '{$feederCode}'."];
                continue;
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

            $cscId = (int) $cscByCode[$csc];
            $g['portions'][$cscId] = ($g['portions'][$cscId] ?? 0)
                + (float) $this->numeric($row['length_km'] ?? null);

            if ($feederCode !== '' && $g['feeder_id'] === null) {
                $g['feeder_id'] = (int) $feederByCode[$feederCode];
            }
            if ($voltage !== '') {
                $g['voltage'] = $voltage;
            }
            $remark = trim((string) ($row['remarks'] ?? ''));
            if ($remark !== '' && $g['remarks'] === null) {
                $g['remarks'] = mb_substr($remark, 0, 2000);
            }

            // Asset columns are summed across the segment's rows, so it
            // does not matter which row of a split they were typed on.
            foreach ($typeByName as $normalised => $type) {
                $value = $this->numeric($row[$normalised] ?? null);
                if ($value > 0) {
                    $g['items'][$type->asset_type_id] =
                        ($g['items'][$type->asset_type_id] ?? 0) + $value;
                }
            }

            unset($g);
        }

        if (empty($groups)) {
            return response()->json([
                'message' => 'No usable rows were found.',
                'created' => 0,
                'skipped' => 0,
                'errors'  => $errors,
            ], 422);
        }

        $created = 0;
        $skipped = [];

        DB::transaction(function () use ($groups, &$created, &$skipped) {
            $units = DB::table('asset_types')->pluck('unit_of_measure', 'asset_type_id');

            foreach ($groups as $g) {
                // Largest portion owns the register row, matching what the
                // dashboard form does.
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

        return response()->json([
            'message' => $created > 0
                ? "Loaded {$created} segments."
                : 'Nothing was loaded.',
            'created' => $created,
            'skipped' => $skipped,
            'errors'  => $errors,
        ], $created > 0 ? 201 : 422);
    }

    /* ============================= HELPERS ============================ */

    /* ======================== REPORT CONSTRUCTION ===================== */

    /** Every query the report needs, in one place, keyed for lookup. */
    private function gatherReportData(): array
    {
        $assetRows = DB::table('v_asset_by_csc')->get();

        return [
            'areas'      => DB::table('v_line_length_by_area')->orderBy('area_name')->get(),
            'cscs'       => DB::table('v_line_length_by_csc')->orderBy('area_name')->orderBy('csc_name')->get(),
            'txByArea'   => DB::table('v_transformer_totals_by_area')->get()->keyBy('area_id'),
            'txByCsc'    => DB::table('v_transformer_totals_by_csc')->get()->keyBy('csc_id'),
            'assetTotal' => DB::table('v_asset_totals')
                ->orderBy('category_name')->orderBy('type_name')->get(),
            'assetByCsc'  => $assetRows->groupBy('csc_id'),
            'assetByArea' => $this->rollUpAssets($assetRows, 'area_id'),
            'feederCount' => DB::table('feeders')->count(),
        ];
    }

    /**
     * Sums CSC-level asset rows up to a coarser level.
     *
     * Grouped by type AND unit, never by type alone: the same column
     * carries kilometres of conductor and counts of poles, so collapsing
     * the unit would add lengths to counts.
     */
    private function rollUpAssets($rows, string $key)
    {
        return $rows->groupBy($key)->map(function ($group) {
            return $group
                ->groupBy(fn ($r) => $r->asset_type_id . '|' . $r->unit_of_measure)
                ->map(function ($same) {
                    $first = $same->first();
                    return (object) [
                        'category_name'   => $first->category_name,
                        'type_name'       => $first->type_name,
                        'unit_of_measure' => $first->unit_of_measure,
                        'placements'      => $same->sum('placements'),
                        'total_quantity'  => $same->sum('total_quantity'),
                    ];
                })
                ->sortBy([['category_name', 'asc'], ['type_name', 'asc']])
                ->values();
        });
    }

    private function buildProvinceSheet(Spreadsheet $book, array $data): void
    {
        $sheet = $book->createSheet();
        $sheet->setTitle('Province');

        $row = $this->reportHeading(
            $sheet,
            'CEB Uva Province — Network Asset Report',
            'Every asset recorded in the register, and the line it sits on.'
        );

        $totalKm  = $data['areas']->sum('total_km');
        $segments = DB::table('segment_register')->where('status', 'ACTIVE')->count();
        $tx       = $data['txByArea']->sum('transformer_units');
        $kva      = $data['txByArea']->sum('installed_kva');

        $row = $this->sectionHeading($sheet, $row, 'Province at a glance');
        $row = $this->factRows($sheet, $row, [
            ['Operational areas',        $data['areas']->count(),          '0'],
            ['Consumer service centres', $data['cscs']->count(),           '0'],
            ['Feeders',                  $data['feederCount'],             '0'],
            ['Segments recorded',        $segments,                        '#,##0'],
            ['Total line length (km)',   $totalKm,                         '#,##0.000'],
            ['Transformers',             $tx,                              '#,##0'],
            ['Installed capacity (kVA)', $kva,                             '#,##0'],
        ]);

        $row++;
        $row = $this->sectionHeading($sheet, $row, 'Assets in use across the province');
        $this->assetTable($sheet, $row, $data['assetTotal'], true);

        $this->sizeReportColumns($sheet);
    }

    private function buildAreaSheet(Spreadsheet $book, array $data): void
    {
        $sheet = $book->createSheet();
        $sheet->setTitle('By Area');

        $row = $this->reportHeading(
            $sheet,
            'Assets by area',
            'Line length here is the share inside each area, so a segment '
            . 'crossing a boundary is counted once in each, for its own part only.'
        );

        foreach ($data['areas'] as $area) {
            $tx = $data['txByArea']->get($area->area_id);

            $row = $this->sectionHeading(
                $sheet,
                $row,
                "{$area->area_name} ({$area->area_code})"
            );

            $row = $this->factRows($sheet, $row, [
                ['CSCs',                     $area->csc_count,               '0'],
                ['Segments',                 $area->segment_count,           '#,##0'],
                ['Crossing a CSC boundary',  $area->crossing_count,          '0'],
                ['Feeders',                  $area->feeder_count,            '0'],
                ['Line length (km)',         $area->total_km,                '#,##0.000'],
                ['Transformers',             $tx->transformer_units ?? 0,    '#,##0'],
                ['Installed capacity (kVA)', $tx->installed_kva ?? 0,        '#,##0'],
            ]);

            $assets = $data['assetByArea']->get($area->area_id, collect());
            $row = $this->assetTable($sheet, $row, $assets, false);
            $row += 2;
        }

        $this->sizeReportColumns($sheet);
    }

    private function buildCscSheet(Spreadsheet $book, array $data): void
    {
        $sheet = $book->createSheet();
        $sheet->setTitle('By CSC');

        $row = $this->reportHeading(
            $sheet,
            'Assets by consumer service centre',
            'A CSC holding several segments shows the count beside its total.'
        );

        foreach ($data['cscs'] as $csc) {
            $tx = $data['txByCsc']->get($csc->csc_id);

            $row = $this->sectionHeading(
                $sheet,
                $row,
                "{$csc->csc_name} ({$csc->csc_code}) — {$csc->area_name} area"
            );

            $row = $this->factRows($sheet, $row, [
                ['Segments',                 $csc->segment_count,            '#,##0'],
                ['Crossing a CSC boundary',  $csc->crossing_count,           '0'],
                ['Line length (km)',         $csc->total_km,                 '#,##0.000'],
                ['Longest segment (km)',     $csc->longest_km,               '#,##0.000'],
                ['Transformers',             $tx->transformer_units ?? 0,    '#,##0'],
                ['Installed capacity (kVA)', $tx->installed_kva ?? 0,        '#,##0'],
            ]);

            $assets = $data['assetByCsc']->get($csc->csc_id, collect())
                ->sortBy([['category_name', 'asc'], ['type_name', 'asc']])
                ->values();

            $row = $this->assetTable($sheet, $row, $assets, false);
            $row += 2;
        }

        $this->sizeReportColumns($sheet);
    }

    /* ---------------------- report styling helpers -------------------- */

    private function reportHeading($sheet, string $title, string $subtitle): int
    {
        $sheet->setCellValue('A1', $title);
        $sheet->getStyle('A1')->getFont()->setBold(true)->setSize(16)
            ->getColor()->setARGB('FF6B002C');

        $sheet->setCellValue('A2', $subtitle);
        $sheet->getStyle('A2')->getFont()->setItalic(true)->setSize(10)
            ->getColor()->setARGB('FF7E7178');

        $sheet->setCellValue('A3', 'Generated ' . now()->format('j F Y, H:i'));
        $sheet->getStyle('A3')->getFont()->setSize(9)
            ->getColor()->setARGB('FF7E7178');

        return 5;
    }

    private function sectionHeading($sheet, int $row, string $text): int
    {
        $sheet->setCellValue("A{$row}", $text);
        $style = $sheet->getStyle("A{$row}:G{$row}");
        $style->getFont()->setBold(true)->setSize(11)
            ->getColor()->setARGB('FFFFFFFF');
        $style->getFill()->setFillType(Fill::FILL_SOLID)
            ->getStartColor()->setARGB('FF6B002C');
        $sheet->getRowDimension($row)->setRowHeight(19);

        return $row + 1;
    }

    /** Label in column A, figure in column B, one pair per row. */
    private function factRows($sheet, int $row, array $facts): int
    {
        foreach ($facts as [$label, $value, $format]) {
            $sheet->setCellValue("A{$row}", $label);
            $sheet->setCellValue("B{$row}", $value === null ? 0 : (float) $value);
            $sheet->getStyle("B{$row}")->getNumberFormat()->setFormatCode($format);
            $sheet->getStyle("B{$row}")->getFont()->setBold(true);
            $sheet->getStyle("A{$row}")->getFont()->getColor()->setARGB('FF52514E');
            $row++;
        }

        return $row;
    }

    /**
     * "How many assets are used here", as a table.
     *
     * Quantity is not totalled at the foot. The column holds kilometres
     * of conductor beside counts of poles, and a single sum down it would
     * be adding the two together.
     */
    private function assetTable($sheet, int $row, $assets, bool $wide): int
    {
        $headers = $wide
            ? ['Category', 'Asset', 'Unit', 'Quantity', 'Records', 'CSCs', 'Areas']
            : ['Category', 'Asset', 'Unit', 'Quantity', 'Records'];

        $sheet->fromArray($headers, null, "A{$row}");
        $last = chr(ord('A') + count($headers) - 1);
        $style = $sheet->getStyle("A{$row}:{$last}{$row}");
        $style->getFont()->setBold(true)->setSize(9)
            ->getColor()->setARGB('FF52514E');
        $style->getFill()->setFillType(Fill::FILL_SOLID)
            ->getStartColor()->setARGB('FFF4EDF0');
        $row++;

        if ($assets->isEmpty()) {
            $sheet->setCellValue("A{$row}", 'Nothing recorded here yet.');
            $sheet->getStyle("A{$row}")->getFont()->setItalic(true)
                ->getColor()->setARGB('FF7E7178');
            return $row + 1;
        }

        foreach ($assets as $a) {
            $values = [
                $a->category_name,
                $a->type_name,
                $a->unit_of_measure,
                (float) $a->total_quantity,
                (int) $a->placements,
            ];
            if ($wide) {
                $values[] = (int) ($a->csc_count ?? 0);
                $values[] = (int) ($a->area_count ?? 0);
            }

            $sheet->fromArray($values, null, "A{$row}");
            $sheet->getStyle("D{$row}")->getNumberFormat()
                ->setFormatCode($a->unit_of_measure === 'nos' ? '#,##0' : '#,##0.000');
            $row++;
        }

        return $row;
    }

    private function sizeReportColumns($sheet): void
    {
        $sheet->getColumnDimension('A')->setWidth(34);
        $sheet->getColumnDimension('B')->setWidth(32);
        foreach (['C', 'D', 'E', 'F', 'G'] as $col) {
            $sheet->getColumnDimension($col)->setWidth(13);
        }
    }

    /* ============================= HELPERS ============================ */

    private function rowsFrom(string $view, string $orderBy): array
    {
        return DB::table($view)->orderByDesc($orderBy)->get()
            ->map(fn ($r) => (array) $r)->all();
    }

    private function segmentRows(): array
    {
        $portions = DB::table('segment_csc as sc')
            ->join('csc_depots as d', 'd.csc_id', '=', 'sc.csc_id')
            ->select('sc.register_id', 'd.csc_code', 'sc.length_km')
            ->get()
            ->groupBy('register_id');

        return DB::table('segment_register as sr')
            ->join('csc_depots as d', 'd.csc_id', '=', 'sr.csc_id')
            ->join('areas as a', 'a.area_id', '=', 'd.area_id')
            ->leftJoin('feeders as f', 'f.feeder_id', '=', 'sr.feeder_id')
            ->select([
                'sr.segment_code', 'd.csc_code', 'd.csc_name', 'a.area_name',
                'f.feeder_code', 'sr.voltage_level', 'sr.length_km',
                'sr.status', 'sr.source_file', 'sr.remarks', 'sr.register_id',
            ])
            ->orderByDesc('sr.register_id')
            ->get()
            ->map(function ($r) use ($portions) {
                $parts = $portions->get($r->register_id, collect());
                $row = (array) $r;
                unset($row['register_id']);
                $row['crosses_cscs'] = $parts->count() ?: 1;
                $row['csc_split'] = $parts
                    ->map(fn ($p) => "{$p->csc_code}: {$p->length_km}")
                    ->implode(' | ');
                return $row;
            })
            ->all();
    }

    /** Column headings for every asset type, unit included. */
    private function assetColumnHeaders(): array
    {
        return DB::table('asset_types')
            ->orderBy('asset_type_id')
            ->get()
            ->map(fn ($t) => "{$t->type_name} ({$t->unit_of_measure})")
            ->all();
    }

    private function assetTypesByNormalisedName()
    {
        return DB::table('asset_types')
            ->select('asset_type_id', 'type_name', 'unit_of_measure')
            ->get()
            ->keyBy(fn ($t) => $this->normaliseHeader($t->type_name));
    }

    /**
     * Headings are matched loosely: case, spaces, punctuation and a
     * trailing unit in brackets are all ignored, so "Copper Conductor
     * (km)", "copper_conductor" and "Copper Conductor" are one column.
     */
    private function normaliseHeader(string $header): string
    {
        $h = preg_replace('/\s*\([^)]*\)\s*$/', '', trim($header));
        $h = strtolower($h);
        $h = preg_replace('/[^a-z0-9]+/', '_', $h);
        return trim($h, '_');
    }

    private function rowToMap(array $headers, array $raw): array
    {
        $map = [];
        foreach ($headers as $i => $key) {
            if ($key === '') {
                continue;
            }
            $map[$key] = $raw[$i] ?? null;
        }
        return $map;
    }

    private function numeric($value): float
    {
        if ($value === null || $value === '') {
            return 0.0;
        }
        $clean = preg_replace('/[^0-9.\-]/', '', (string) $value);
        return is_numeric($clean) ? (float) $clean : 0.0;
    }

    private function writeTable($sheet, array $rows): void
    {
        if (empty($rows)) {
            $sheet->setCellValue('A1', 'No rows.');
            return;
        }

        $headers = array_keys($rows[0]);
        $sheet->fromArray($headers, null, 'A1');
        $sheet->fromArray(array_map('array_values', $rows), null, 'A2');

        $this->styleHeader($sheet, count($headers));
        $sheet->freezePane('A2');

        $lastColumn = $sheet->getHighestColumn();
        foreach (range('A', $lastColumn) as $col) {
            $sheet->getColumnDimension($col)->setAutoSize(true);
        }
    }

    private function styleHeader($sheet, int $columnCount): void
    {
        $last = $sheet->getCell([$columnCount, 1])->getColumn();
        $style = $sheet->getStyle("A1:{$last}1");
        $style->getFont()->setBold(true)->getColor()->setARGB('FFFFFFFF');
        $style->getFill()->setFillType(Fill::FILL_SOLID)
            ->getStartColor()->setARGB('FF6B002C');
        $style->getAlignment()->setVertical(Alignment::VERTICAL_CENTER);
        $sheet->getRowDimension(1)->setRowHeight(20);
    }

    private function downloadCsv(Spreadsheet $book, string $filename): StreamedResponse
    {
        $writer = new \PhpOffice\PhpSpreadsheet\Writer\Csv($book);
        $writer->setUseBOM(true); // so Excel opens it as UTF-8

        return response()->streamDownload(function () use ($writer, $book) {
            $writer->save('php://output');
            $book->disconnectWorksheets();
        }, $filename, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    private function download(Spreadsheet $book, string $filename): StreamedResponse
    {
        $writer = new Xlsx($book);

        return response()->streamDownload(function () use ($writer, $book) {
            $writer->save('php://output');
            $book->disconnectWorksheets();
        }, $filename, [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ]);
    }
}
