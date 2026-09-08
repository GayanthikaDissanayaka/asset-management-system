# CEB Uva Province — Network Asset Management System

Frontend: React + Bootstrap · Backend: PHP/Laravel · DB: MySQL/phpMyAdmin
Local env: Apache/XAMPP · GIS: ArcGIS Pro + ArcGIS Maps SDK for JS · Charts: Chart.js

## Setup

### 1. Database
1. Start MySQL (via XAMPP).
2. In phpMyAdmin, import `database/database_schema.sql`. This creates the
   `ceb_uva_assets` database, all tables, the dashboard summary views, and
   seeds the 5 areas / 17 depots / asset categories & types.

### 2. Backend (Laravel)
```
cd backend
composer install
cp .env.example .env
php artisan key:generate
php artisan migrate        # only if you want migrations instead of the raw SQL import
php artisan db:seed        # loads AreaDepotSeeder + AssetTypeSeeder
php artisan serve
```

### 3. Frontend (React)
```
cd frontend
npm install
npm start
```

## Structure
See `docs/project_structure.md` for the full folder layout and build order,
and `docs/api-spec.md` for the REST endpoints.

## Notes
- `assets.segment_no` is a human-readable field code (matches your as-built
  diagram references) kept alongside the numeric `asset_id` primary key.
- Dashboard totals (`vw_depot_totals`, `vw_area_totals`, `vw_province_total`)
  are SQL views — the depot -> area -> province roll-up happens in the
  database, not in PHP or React.
