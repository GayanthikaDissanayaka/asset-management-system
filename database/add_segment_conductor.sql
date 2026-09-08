-- =====================================================================
-- Per-segment asset quantities, plus the length roll-ups the dashboard
-- reads. Safe to run more than once.
--
-- WHY THIS EXISTS
--
-- segment_register carries one length_km per segment, which is the
-- segment's route length. It cannot record what that segment is built
-- from: a single 33 kV run can be part Copper, part Weasel, part Raccoon,
-- part Lynx, and it carries switchgear and substations along it.
--
-- The obvious home would have been the `assets` table, which already has
-- the whole vocabulary. But assets.segment_id is a foreign key to
-- `segments`, which holds 14 curated graph edges, while the working
-- register in segment_register holds 1,325 rows whose segment_id is null
-- throughout. Hanging conductor lengths off `assets` would mean inventing
-- a `segments` row for every register entry first.
--
-- So quantities hang off the register directly, and asset_types stays the
-- vocabulary. One table covers both halves of the entry form: conductor
-- runs are stored in km, counted items such as switchgear in nos.
-- =====================================================================

-- The first cut of this file created a conductor-only table. It is
-- replaced by the general one below; dropping is safe because nothing
-- was ever written to it.
DROP VIEW  IF EXISTS v_conductor_length_by_csc;
DROP TABLE IF EXISTS segment_conductor;


-- register_id and asset_type_id are INT UNSIGNED to match the columns
-- they reference. A signed INT here fails with errno 150.
CREATE TABLE IF NOT EXISTS segment_asset (
  segment_asset_id INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  register_id      INT UNSIGNED  NOT NULL,
  asset_type_id    INT UNSIGNED  NOT NULL,
  quantity         DECIMAL(12,4) NOT NULL DEFAULT 0.0000,
  unit_of_measure  ENUM('nos','km','m','kVA','kW') NOT NULL DEFAULT 'nos',
  remarks          VARCHAR(255)  NULL,
  created_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at       DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (segment_asset_id),

  -- One row per asset type per segment. A second Copper entry for the
  -- same segment is an update, not an insert.
  UNIQUE KEY uq_segment_asset (register_id, asset_type_id),
  KEY idx_sa_asset_type (asset_type_id),

  CONSTRAINT fk_sa_register
    FOREIGN KEY (register_id) REFERENCES segment_register (register_id)
    ON DELETE CASCADE,

  CONSTRAINT fk_sa_asset_type
    FOREIGN KEY (asset_type_id) REFERENCES asset_types (asset_type_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------
-- Length by area.
--
-- LEFT JOIN so an area with no segments recorded still returns a row with
-- zero. An area missing from this list would look like it does not exist
-- rather than like it has nothing entered yet.
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_line_length_by_area AS
SELECT
  a.area_id,
  a.area_code,
  a.area_name,
  COUNT(DISTINCT d.csc_id)                 AS csc_count,
  COUNT(sr.register_id)                    AS segment_count,
  COUNT(DISTINCT sr.feeder_id)             AS feeder_count,
  COALESCE(SUM(sr.length_km), 0)           AS total_km,
  ROUND(COALESCE(AVG(sr.length_km), 0), 3) AS mean_km,
  COALESCE(MAX(sr.length_km), 0)           AS longest_km
FROM areas a
JOIN csc_depots d
  ON d.area_id = a.area_id
LEFT JOIN segment_register sr
  ON sr.csc_id = d.csc_id
 AND sr.status = 'ACTIVE'
GROUP BY a.area_id, a.area_code, a.area_name;


-- ---------------------------------------------------------------------
-- What each CSC is built from, by asset type. Empty until the dashboard's
-- add form starts writing to segment_asset.
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_segment_asset_by_csc AS
SELECT
  d.csc_id,
  d.csc_code,
  d.csc_name,
  a.area_id,
  a.area_name,
  c.category_name,
  t.asset_type_id,
  t.type_name,
  sa.unit_of_measure,
  COUNT(DISTINCT sa.register_id) AS segment_count,
  SUM(sa.quantity)               AS total_quantity
FROM segment_asset sa
JOIN segment_register sr ON sr.register_id   = sa.register_id
JOIN csc_depots       d  ON d.csc_id         = sr.csc_id
JOIN areas            a  ON a.area_id        = d.area_id
JOIN asset_types      t  ON t.asset_type_id  = sa.asset_type_id
LEFT JOIN asset_categories c ON c.category_id = t.category_id
WHERE sr.status = 'ACTIVE'
GROUP BY d.csc_id, d.csc_code, d.csc_name,
         a.area_id, a.area_name,
         c.category_name, t.asset_type_id, t.type_name, sa.unit_of_measure;
