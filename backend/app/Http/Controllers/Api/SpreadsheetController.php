<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
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
            'view' => ['nullable', 'string', 'in:areas,cscs,feeders,segments,assets,asset-by-csc,asset-types,assets-used,assets-used-by-csc'],
        ]);

        $book = $this->buildExportBook($validated['view'] ?? null);

        $name = 'uva-network-register-' . now()->format('Y-m-d') . '.xlsx';

        return $this->download($book, $name);
    }

    /**
     * The single sheets the export can produce, and where each reads
     * from. Named once here so the download, the ?view= form and the
     * saved-report endpoint all offer exactly the same list.
     */
    private function exportSheets(): array
    {
        return [
            'areas'        => ['Areas', fn () => $this->rowsFrom('v_line_length_by_area', 'total_km')],
            'cscs'         => ['CSCs', fn () => $this->rowsFrom('v_line_length_by_csc', 'total_km')],
            'feeders'      => ['Feeders', fn () => $this->rowsFrom('v_line_length_by_feeder', 'total_km')],
            'segments'     => ['Segments', fn () => $this->segmentRows()],
            'assets'       => ['Assets', fn () => $this->rowsFrom('v_asset_totals', 'total_quantity')],
            'asset-by-csc' => ['Assets by CSC', fn () => $this->rowsFrom('v_asset_by_csc', 'total_quantity')],

            // The full catalogue from asset_categories and asset_types,
            // so types holding nothing are in the file too.
            'asset-types'  => ['Asset types', fn () => $this->assetTypeRows()],

            /* The usage log. This is history, not current state: what was
               entered, where it went, when, and by whom. `assets` can
               only say what a place has now, because a corrected
               quantity overwrites the one it corrected. */
            'assets-used'        => ['Assets used', fn () => $this->usedRows()],
            'assets-used-by-csc' => ['Used by CSC', fn () => $this->rowsFrom('v_assets_used_by_csc', 'total_quantity')],
        ];
    }

    /**
     * The export workbook, built once and used by both the download and
     * the save-to-reports-folder endpoint.
     *
     * Shared deliberately: a saved report that differed from the one the
     * browser downloaded would be the worst kind of bug, because both
     * look right on their own and only disagree when somebody compares
     * them months later.
     */
    private function buildExportBook(?string $view = null): Spreadsheet
    {
        $sheets = $this->exportSheets();

        if (! empty($view)) {
            $sheets = [$view => $sheets[$view]];
        }

        $book = new Spreadsheet();
        $book->removeSheetByIndex(0);

        foreach ($sheets as [$title, $loader]) {
            $sheet = $book->createSheet();
            $sheet->setTitle($title);
            $this->writeTable($sheet, $loader());
        }

        $book->setActiveSheetIndex(0);

        return $book;
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
        return $this->download(
            $this->buildReportBook(),
            'uva-network-asset-report-' . now()->format('Y-m-d') . '.xlsx'
        );
    }

    /** The written report workbook. Shared by download and save. */
    private function buildReportBook(): Spreadsheet
    {
        $book = new Spreadsheet();
        $book->removeSheetByIndex(0);

        $data = $this->gatherReportData();

        $this->buildProvinceSheet($book, $data);
        $this->buildAreaSheet($book, $data);
        $this->buildCscSheet($book, $data);

        // The underlying tables, after the narrative.
        foreach ([
            'Data · Areas'       => fn () => $this->rowsFrom('v_line_length_by_area', 'total_km'),
            'Data · CSCs'        => fn () => $this->rowsFrom('v_line_length_by_csc', 'total_km'),
            'Data · Feeders'     => fn () => $this->rowsFrom('v_line_length_by_feeder', 'total_km'),
            'Data · Segments'    => fn () => $this->segmentRows(),
            'Data · Assets'      => fn () => $this->rowsFrom('v_asset_totals', 'total_quantity'),
            'Data · Asset types' => fn () => $this->assetTypeRows(),

            /* The usage log, as its own sheets. It answers a question
               none of the sheets above can: not what is held now, but
               what was entered, when, and by whom. */
            'Data · Assets used'  => fn () => $this->usedRows(),
            'Data · Used by CSC'  => fn () => $this->rowsFrom('v_assets_used_by_csc', 'total_quantity'),
        ] as $title => $loader) {
            $sheet = $book->createSheet();
            $sheet->setTitle($title);
            $this->writeTable($sheet, $loader());
        }

        $book->setActiveSheetIndex(0);

        return $book;
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
            ['segment_code', 'csc_code', 'area', 'length_km', 'feeder_code', 'voltage_level', 'remarks'],
            $this->assetColumnHeaders()
        );

        $sheet->fromArray($headers, null, 'A1');

        /* Worked examples: a segment split over two CSCs, and a row
           naming its CSC the way people actually write it, to show that
           the code is not required. */
        $sheet->fromArray([
            ['BDSM900', 'BDL-CSC01', 'Badulla', 6.400, '', '33kV', 'example — delete this row'],
            ['BDSM900', 'MAH-CSC02', '', 3.850, '', '33kV', 'same segment, the part inside the next CSC'],
            ['BDSM901', 'Hali Ela', '', 2.100, '', '33kV', 'a name works too — so does a known alias'],
        ], null, 'A2');

        $this->styleHeader($sheet, count($headers));
        $sheet->freezePane('E2');

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
            ['segment_code and the CSC are required. Everything else is'],
            ['optional. A segment_code already present for that CSC is'],
            ['skipped and reported, never overwritten.'],
            [''],
            ['NAMING THE PLACE'],
            [''],
            ['The CSC column takes the code (BDL-CSC01), the name (Badulla)'],
            ['or a known alias (Hali Ela, Bibile, Mahiyangana). Case, spaces'],
            ['and hyphens do not matter. The column may be headed csc_code,'],
            ['csc or depot.'],
            [''],
            ['The area column is optional and only used to tell two places'],
            ['apart if a name could mean either. If the area you give does'],
            ['not contain the CSC you named, the row is refused rather than'],
            ['filed under a guess -- a row put in the wrong place is worse'],
            ['than one that failed to load, because nobody goes looking.'],
            [''],
            ['An area on its own is not enough. An area has several CSCs and'],
            ['choosing one to stand for the rest would invent data.'],
            [''],
            ['After loading, the result lists every place name in the sheet'],
            ['and the CSC it was filed under. Check that list.'],
        ], null, 'A1');
        $notes->getColumnDimension('A')->setWidth(70);
        $notes->getStyle('A1')->getFont()->setBold(true);

        $refs = $book->createSheet();
        $refs->setTitle('Codes');

        /* The aliases are listed because they are accepted on import,
           and a spelling that works is no use to anybody who cannot see
           that it works. */
        $refRows = [[
            'CSC code', 'CSC name', 'Area',
            'Also accepted as', 'Feeder codes for this CSC',
        ]];

        $feedersByCsc = DB::table('feeders')
            ->select('origin_csc_id', 'feeder_code')
            ->get()
            ->groupBy('origin_csc_id');

        $aliasesByCsc = DB::table('csc_aliases')
            ->select('csc_id', 'alias_name')
            ->get()
            ->groupBy('csc_id');

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
                $aliasesByCsc->get($csc->csc_id, collect())->pluck('alias_name')->implode(', '),
                $feedersByCsc->get($csc->csc_id, collect())->pluck('feeder_code')->implode(', '),
            ];
        }

        $refs->fromArray($refRows, null, 'A1');
        $this->styleHeader($refs, 5);
        foreach (range('A', 'E') as $col) {
            $refs->getColumnDimension($col)->setAutoSize(true);
        }

        $book->setActiveSheetIndex(0);

        return $this->download($book, 'uva-segment-import-template.xlsx');
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
            ->select('sc.segment_register_id', 'd.csc_code', 'sc.length_km')
            ->get()
            ->groupBy('segment_register_id');

        return DB::table('segment_register as sr')
            ->join('csc_depots as d', 'd.csc_id', '=', 'sr.csc_id')
            ->join('areas as a', 'a.area_id', '=', 'd.area_id')
            ->leftJoin('feeders as f', 'f.feeder_id', '=', 'sr.feeder_id')
            ->select([
                'sr.segment_code', 'd.csc_code', 'd.csc_name', 'a.area_name',
                'f.feeder_code', 'sr.voltage_level', 'sr.length_km',
                'sr.status', 'sr.source_file', 'sr.remarks', 'sr.segment_register_id',
            ])
            ->orderByDesc('sr.segment_register_id')
            ->get()
            ->map(function ($r) use ($portions) {
                $parts = $portions->get($r->segment_register_id, collect());
                $row = (array) $r;
                unset($row['segment_register_id']);
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

    /**
     * The first of several acceptable headings that the sheet actually
     * has, or null.
     *
     * Sheets in the wild head the same column "CSC", "Depot" or
     * "csc_code", and insisting on one spelling is how an importer ends
     * up rejecting the files it was written to load.
     */
    /* ========================= SAVED REPORTS ========================== */

    /**
     * Where generated reports are kept on disk.
     *
     * A folder inside the project rather than storage/app, so it shows up
     * in the editor's file tree beside everything else and can be opened,
     * mailed or committed without going hunting for it.
     */
    private function reportsPath(string $file = ''): string
    {
        $dir = realpath(base_path('..')) . DIRECTORY_SEPARATOR . 'reports';

        if (! is_dir($dir)) {
            mkdir($dir, 0755, true);
        }

        return $file === '' ? $dir : $dir . DIRECTORY_SEPARATOR . $file;
    }

    /**
     * Builds a report and keeps a copy in the project's reports/ folder.
     *
     * The download endpoints stream a file to the browser and keep
     * nothing. That is fine for "let me look at this now", and useless
     * for "what did the register say at the end of last month" -- the
     * answer to that has to have been written down at the time, because
     * the register has moved on since.
     *
     * So this writes the file, and `savedReports` lists what has been
     * written. The filename carries the date and time for the same
     * reason: two reports built the same day are different documents.
     */
    public function saveReport(Request $request)
    {
        $validated = $request->validate([
            'view'  => ['nullable', 'string', 'in:report,areas,cscs,feeders,segments,assets,asset-by-csc,asset-types,assets-used,assets-used-by-csc'],
            'label' => ['nullable', 'string', 'max:60'],
        ]);

        $view = $validated['view'] ?? 'report';

        // Rebuilt through the same code paths the downloads use, so a
        // saved file and a downloaded one can never differ.
        $book = $view === 'report'
            ? $this->buildReportBook()
            : $this->buildExportBook($view);

        $label = trim($validated['label'] ?? '');
        $slug  = $label !== ''
            ? '-' . strtolower(preg_replace('/[^A-Za-z0-9]+/', '-', $label))
            : '';

        $name = sprintf(
            'uva-%s-%s%s.xlsx',
            $view,
            now()->format('Y-m-d-His'),
            trim($slug, '-') === '' ? '' : $slug
        );

        $path = $this->reportsPath($name);

        (new Xlsx($book))->save($path);

        return response()->json([
            'message'  => "Saved to reports/{$name}",
            'file'     => $name,
            'bytes'    => filesize($path),
            'saved_at' => now()->toDateTimeString(),

            // The full path, because the point of saving into the
            // project is being able to go and open it.
            'path'     => $path,
        ], 201);
    }

    /** Everything written to reports/, newest first. */
    public function savedReports()
    {
        $dir = $this->reportsPath();

        $files = collect(glob($dir . DIRECTORY_SEPARATOR . '*.xlsx') ?: [])
            ->map(fn ($p) => [
                'file'     => basename($p),
                'bytes'    => filesize($p),
                'saved_at' => date('Y-m-d H:i:s', filemtime($p)),
                'stamp'    => filemtime($p),
            ])
            ->sortByDesc('stamp')
            ->values()
            ->map(fn ($f) => collect($f)->except('stamp')->all());

        return response()->json([
            'folder' => $dir,
            'count'  => $files->count(),
            'files'  => $files,
        ]);
    }

    /**
     * Downloads one previously saved report.
     *
     * The name is matched against the directory listing rather than
     * joined onto a path: a filename arriving from the browser must
     * never be able to walk out of reports/ and read something else.
     */
    public function downloadSaved(Request $request)
    {
        $validated = $request->validate([
            'file' => ['required', 'string', 'max:200'],
        ]);

        $dir   = $this->reportsPath();
        $known = collect(glob($dir . DIRECTORY_SEPARATOR . '*.xlsx') ?: [])
            ->keyBy(fn ($p) => basename($p));

        $path = $known[$validated['file']] ?? null;

        if (! $path) {
            return response()->json([
                'message' => 'That report is not in the reports folder.',
            ], 404);
        }

        return response()->download($path);
    }

    /**
     * The usage log in readable order: newest first, because the reason
     * to open it is usually "what went out recently".
     */
    private function usedRows(): array
    {
        return DB::table('v_assets_used')
            ->select([
                'recorded_at', 'used_on', 'category_name', 'type_name',
                'quantity', 'unit_of_measure', 'condition_status',
                'csc_code', 'csc_name', 'area_name', 'province_name',
                'used_for', 'recorded_by_name', 'batch_ref',
            ])
            ->orderByDesc('recorded_at')
            ->orderByDesc('asset_usage_id')
            ->get()
            ->map(fn ($r) => (array) $r)
            ->all();
    }

    /**
     * Every type the catalogue defines, with what is held against it.
     *
     * Driven from asset_categories and asset_types rather than from the
     * holdings, so a type with nothing recorded still appears -- that a
     * type has no records is itself worth seeing in a report.
     */
    private function assetTypeRows(): array
    {
        $held = DB::table('v_asset_register')
            ->select('asset_type_id')
            ->selectRaw('COUNT(*) AS records')
            ->selectRaw('SUM(quantity) AS quantity')
            ->selectRaw('COUNT(DISTINCT csc_id) AS csc_count')
            ->groupBy('asset_type_id')
            ->get()
            ->keyBy('asset_type_id');

        return DB::table('asset_types as t')
            ->join('asset_categories as c', 'c.category_id', '=', 't.category_id')
            ->select([
                'c.category_name', 't.type_code', 't.type_name',
                't.unit_of_measure', 't.is_active',
            ])
            ->addSelect('t.asset_type_id')
            ->orderBy('c.display_order')
            ->orderBy('t.display_order')
            ->get()
            ->map(function ($t) use ($held) {
                $h = $held[$t->asset_type_id] ?? null;

                return [
                    'category_name'   => $t->category_name,
                    'type_code'       => $t->type_code,
                    'type_name'       => $t->type_name,
                    'unit_of_measure' => $t->unit_of_measure,
                    'quantity_held'   => (float) ($h->quantity ?? 0),
                    'records'         => (int) ($h->records ?? 0),
                    'csc_count'       => (int) ($h->csc_count ?? 0),
                    'is_active'       => $t->is_active ? 'yes' : 'no',
                ];
            })
            ->all();
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
