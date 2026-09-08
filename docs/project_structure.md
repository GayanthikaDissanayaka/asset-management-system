# Uva Province Network Asset Management System — Project Structure

Stack: **React + Bootstrap** (frontend) · **PHP/Laravel** (backend) · **MySQL/phpMyAdmin** (DB)
· **Apache/XAMPP** (local) · **ArcGIS Pro + ArcGIS Maps SDK for JS** (GIS) · **Chart.js** (charts)
· **REST API + Axios** · **Git/GitHub**

Run frontend and backend as two separate repos/folders (recommended — keeps deploys independent).

```
ceb-uva-assets/
├── backend/                          # Laravel API
│   ├── app/
│   │   ├── Http/
│   │   │   ├── Controllers/
│   │   │   │   ├── Api/
│   │   │   │   │   ├── AreaController.php
│   │   │   │   │   ├── DepotController.php
│   │   │   │   │   ├── FeederController.php
│   │   │   │   │   ├── AssetCategoryController.php
│   │   │   │   │   ├── AssetTypeController.php
│   │   │   │   │   ├── AssetController.php
│   │   │   │   │   ├── LineSegmentController.php
│   │   │   │   │   ├── MaintenanceLogController.php
│   │   │   │   │   ├── DashboardController.php    # depot/area/province summaries
│   │   │   │   │   ├── ReportController.php        # PHPSpreadsheet exports
│   │   │   │   │   └── AuthController.php
│   │   │   ├── Middleware/
│   │   │   └── Requests/                            # form validation classes
│   │   ├── Models/
│   │   │   ├── Province.php
│   │   │   ├── Area.php
│   │   │   ├── Depot.php
│   │   │   ├── Feeder.php
│   │   │   ├── AssetCategory.php
│   │   │   ├── AssetType.php
│   │   │   ├── Asset.php
│   │   │   ├── LineSegment.php
│   │   │   ├── MaintenanceLog.php
│   │   │   └── User.php
│   │   └── Services/
│   │       ├── AssetSummaryService.php              # roll-up logic (depot->area->province)
│   │       └── SegmentCodeService.php                # generates/validates segment_no keys
│   ├── database/
│   │   ├── migrations/                               # one file per table in database_schema.sql
│   │   ├── seeders/
│   │   │   ├── AreaDepotSeeder.php                    # loads the 5 areas / 17 depots
│   │   │   └── AssetTypeSeeder.php                    # loads categories/types
│   │   └── factories/
│   ├── routes/
│   │   └── api.php
│   ├── config/
│   ├── .env                                           # DB_DATABASE=ceb_uva_assets etc.
│   └── composer.json
│
├── frontend/                          # React app
│   ├── public/
│   ├── src/
│   │   ├── api/
│   │   │   └── axiosClient.js                         # base Axios instance + auth interceptor
│   │   ├── components/
│   │   │   ├── layout/ (Sidebar, Navbar, Breadcrumbs)
│   │   │   ├── charts/ (AssetsByCategoryChart, DepotComparisonChart, TrendChart)
│   │   │   ├── map/ (AssetMap.jsx — ArcGIS Maps SDK wrapper)
│   │   │   └── tables/ (AssetTable, MaintenanceLogTable)
│   │   ├── pages/
│   │   │   ├── Dashboard/                             # province-level overview
│   │   │   ├── Areas/AreaDetail.jsx
│   │   │   ├── Depots/DepotDetail.jsx
│   │   │   ├── Assets/ (AssetList, AssetForm, AssetDetail)
│   │   │   ├── Feeders/FeederDetail.jsx
│   │   │   ├── Reports/ReportBuilder.jsx
│   │   │   └── Auth/ (Login)
│   │   ├── context/ (AuthContext.jsx)
│   │   ├── hooks/ (useAssetSummary.js, useDebounce.js)
│   │   ├── utils/
│   │   ├── App.jsx
│   │   └── index.js
│   └── package.json
│
├── database/
│   └── database_schema.sql             # full schema + seed data (see attached file)
│
├── docs/
│   ├── ERD.png
│   └── api-spec.md
│
└── README.md
```

## Suggested build order

1. **Database first** — import `database_schema.sql` via phpMyAdmin, confirm the seed
   data (5 areas, 17 depots, 7 categories, 19 asset types) looks right against your
   single-line diagrams.
2. **Laravel migrations** — mirror each table from the SQL file as an Eloquent migration
   so the schema is version-controlled in Git, not just sitting in phpMyAdmin.
3. **Core CRUD API** — Depots → Asset Types → Assets → Line Segments → Maintenance Logs,
   in that order, since each depends on the one before it existing.
4. **Dashboard endpoints** — wrap the SQL views (`vw_depot_totals`, `vw_area_totals`,
   `vw_province_total`, `vw_asset_last_activity`) in a `DashboardController` so the
   frontend never has to compute roll-ups itself.
5. **React shell + charts** — province-level dashboard first (Chart.js bar/pie by
   category), then drill-down pages per area/depot.
6. **ArcGIS layer** — once `assets.latitude/longitude` and `line_segments` have real
   data, plot them as a feature layer so techs can click a pole/transformer on the map
   and see its history.
7. **Reports** — PHPSpreadsheet export of the depot/area/province summary tables.

## Naming convention note

Your notes call out **"Primary key – Segments"** — I've kept `segment_no` as a
human-readable **business key** (unique per depot) on the `assets` table, separate
from the auto-increment `asset_id` used for joins. That way your field codes from the
as-built diagrams (the kind of code visible on the single-line diagram, e.g.
`1SOM-011`) stay intact and searchable, while the database still gets a clean numeric
primary key for performance.
