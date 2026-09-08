-- =====================================================================
-- Where every asset is, and what the province holds in total.
--
-- Assets reach a CSC by three different routes, and any answer to "how
-- many switches do we have" has to gather all three or it undercounts:
--
--   1. an `assets` row pinned to a network node
--   2. an `assets` row pinned to a curated `segments` edge
--   3. a `segment_asset` row entered against the working register
--
-- v_asset_placement flattens the three into one shape, and the roll-ups
-- below build on it, so a new route only has to be added in one place.
--
-- UNITS ARE NEVER MIXED. asset_types measures poles in `nos` and
-- conductor in `km`, and both land in the same quantity column. Every
-- roll-up here groups by unit_of_measure, so nothing ever adds a count of
-- poles to a length of line.
--
-- Safe to run more than once.
-- =====================================================================

CREATE OR REPLACE VIEW v_asset_placement AS

-- 1. Pinned to a node.
SELECT
  a.asset_id                       AS source_id,
  'assets'                         AS source,
  a.asset_code                     AS asset_code,
  a.asset_type_id                  AS asset_type_id,
  n.csc_id                         AS csc_id,
  'node'                           AS attached_to,
  n.node_code                      AS attached_ref,
  a.quantity                       AS quantity,
  a.unit_of_measure                AS unit_of_measure
FROM assets a
JOIN network_nodes n ON n.node_id = a.node_id
WHERE a.status = 'ACTIVE'
  AND a.node_id IS NOT NULL

UNION ALL

-- 2. Pinned to a curated segment.
SELECT
  a.asset_id,
  'assets',
  a.asset_code,
  a.asset_type_id,
  s.csc_id,
  'segment',
  s.segment_code,
  a.quantity,
  a.unit_of_measure
FROM assets a
JOIN segments s ON s.segment_id = a.segment_id
WHERE a.status = 'ACTIVE'
  AND a.segment_id IS NOT NULL

UNION ALL

-- 3. Entered against the working register, through the dashboard.
SELECT
  sa.segment_asset_id,
  'segment_asset',
  sr.segment_code,
  sa.asset_type_id,
  sr.csc_id,
  'segment',
  sr.segment_code,
  sa.quantity,
  sa.unit_of_measure
FROM segment_asset sa
JOIN segment_register sr ON sr.register_id = sa.register_id
WHERE sr.status = 'ACTIVE';


-- ---------------------------------------------------------------------
-- One row per asset type: the province total, and how widely it is used.
--
-- `placements` is how many separate records hold it, which is not the
-- same as the quantity: one record can carry thirty poles.
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_asset_totals AS
SELECT
  t.asset_type_id,
  COALESCE(c.category_name, 'Other') AS category_name,
  t.type_name,
  p.unit_of_measure,
  COUNT(*)                          AS placements,
  COUNT(DISTINCT p.csc_id)          AS csc_count,
  COUNT(DISTINCT d.area_id)         AS area_count,
  SUM(p.quantity)                   AS total_quantity,
  SUM(CASE WHEN p.source = 'segment_asset' THEN p.quantity ELSE 0 END)
                                    AS entered_here_quantity
FROM v_asset_placement p
JOIN asset_types t       ON t.asset_type_id = p.asset_type_id
LEFT JOIN asset_categories c ON c.category_id = t.category_id
JOIN csc_depots d        ON d.csc_id = p.csc_id
GROUP BY t.asset_type_id, c.category_name, t.type_name, p.unit_of_measure;


-- ---------------------------------------------------------------------
-- The same totals broken down by where they sit, for "assigned to whom".
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_asset_by_csc AS
SELECT
  d.csc_id,
  d.csc_code,
  d.csc_name,
  a.area_id,
  a.area_name,
  t.asset_type_id,
  COALESCE(c.category_name, 'Other') AS category_name,
  t.type_name,
  p.unit_of_measure,
  COUNT(*)        AS placements,
  SUM(p.quantity) AS total_quantity
FROM v_asset_placement p
JOIN asset_types t        ON t.asset_type_id = p.asset_type_id
LEFT JOIN asset_categories c ON c.category_id = t.category_id
JOIN csc_depots d         ON d.csc_id  = p.csc_id
JOIN areas a              ON a.area_id = d.area_id
GROUP BY d.csc_id, d.csc_code, d.csc_name, a.area_id, a.area_name,
         t.asset_type_id, c.category_name, t.type_name, p.unit_of_measure;
