# API endpoints (v1)

All routes are prefixed with `/api` and require `auth:sanctum` unless noted.

## Hierarchy (read-only)
- `GET /areas` — list all areas, with depots
- `GET /areas/{id}`
- `GET /depots` — list all depots, with area
- `GET /depots/{id}` — with feeders + assets
- `GET /feeders` — list all feeders, with depot
- `GET /feeders/{id}` — with assets + line segments
- `GET /asset-categories` — with asset types
- `GET /asset-types` — with category

## Asset register
- `GET /assets?depot_id=&asset_type_id=&status=` — filterable, paginated
- `POST /assets` — create
- `GET /assets/{id}` — with type, depot, feeder, maintenance logs
- `PUT /assets/{id}` — update
- `DELETE /assets/{id}`

## Maintenance
- `POST /maintenance-logs` — log an install/repair/inspect/replace action
- `GET /assets/{id}/logs` — history for one asset

## Dashboard (roll-ups)
- `GET /dashboard/depot-summary` — full category/type breakdown per depot
- `GET /dashboard/depot-totals` — one number per depot
- `GET /dashboard/area-totals` — one number per area
- `GET /dashboard/province-total` — single province-wide total
- `GET /dashboard/line-lengths` — conductor length totals, depot-wise
- `GET /dashboard/last-activity` — most recent action per asset (handover tracking)
