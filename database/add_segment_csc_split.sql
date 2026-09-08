-- =====================================================================
-- Segments that cross a CSC boundary.
--
-- THE PROBLEM
--
-- segment_register carries one csc_id per segment, so a segment is owned
-- outright by a single CSC. Real 33 kV runs do not respect boundaries: a
-- segment can start in one CSC and finish in another. Attributing the
-- whole length to whichever CSC happens to be on the row overstates that
-- CSC, understates its neighbour, and — when the two sit in different
-- areas — puts kilometres in the wrong area total.
--
-- THE FIX
--
-- segment_csc holds the split: one row per CSC the segment touches, with
-- the length inside that CSC. A segment with nothing in segment_csc is
-- wholly inside its register csc_id, which is every one of the 1,325 rows
-- imported so far, so the split is additive and changes no existing
-- number.
--
-- v_segment_csc_share below is the single place that decides which of the
-- two applies. Every length roll-up reads it rather than reading
-- segment_register directly, so the rule cannot drift between views.
--
-- Safe to run more than once.
-- =====================================================================

CREATE TABLE IF NOT EXISTS segment_csc (
  segment_csc_id INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  register_id    INT UNSIGNED  NOT NULL,
  csc_id         INT UNSIGNED  NOT NULL,
  length_km      DECIMAL(10,4) NOT NULL DEFAULT 0.0000,
  remarks        VARCHAR(255)  NULL,
  created_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP
                               ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (segment_csc_id),

  -- A CSC appears at most once per segment. Two entries for the same CSC
  -- are one portion, not two.
  UNIQUE KEY uq_segment_csc (register_id, csc_id),
  KEY idx_sc_csc (csc_id),

  CONSTRAINT fk_segcsc_register
    FOREIGN KEY (register_id) REFERENCES segment_register (register_id)
    ON DELETE CASCADE,

  CONSTRAINT fk_segcsc_csc
    FOREIGN KEY (csc_id) REFERENCES csc_depots (csc_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------
-- Who owns which kilometres.
--
-- A split segment contributes one row per CSC it touches. An unsplit one
-- contributes a single row for its register CSC. `is_split` lets a report
-- tell a boundary-crossing segment from an ordinary one.
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_segment_csc_share AS
SELECT
  sc.register_id,
  sc.csc_id,
  sc.length_km,
  1 AS is_split
FROM segment_csc sc
JOIN segment_register sr ON sr.register_id = sc.register_id
WHERE sr.status = 'ACTIVE'

UNION ALL

SELECT
  sr.register_id,
  sr.csc_id,
  COALESCE(sr.length_km, 0) AS length_km,
  0 AS is_split
FROM segment_register sr
WHERE sr.status = 'ACTIVE'
  AND NOT EXISTS (
    SELECT 1 FROM segment_csc sc2 WHERE sc2.register_id = sr.register_id
  );


-- ---------------------------------------------------------------------
-- Length per CSC, counting only the kilometres inside that CSC.
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_line_length_by_csc AS
SELECT
  d.csc_id,
  d.csc_code,
  d.csc_name,
  a.area_id,
  a.area_name,
  COUNT(s.register_id)                    AS segment_count,
  SUM(s.is_split)                         AS crossing_count,
  COALESCE(SUM(s.length_km), 0)           AS total_km,
  ROUND(COALESCE(AVG(s.length_km), 0), 3) AS mean_km,
  COALESCE(MAX(s.length_km), 0)           AS longest_km
FROM v_segment_csc_share s
JOIN csc_depots d ON d.csc_id  = s.csc_id
JOIN areas      a ON a.area_id = d.area_id
GROUP BY d.csc_id, d.csc_code, d.csc_name, a.area_id, a.area_name;


-- ---------------------------------------------------------------------
-- Length per area.
--
-- This is the roll-up the split exists for. Because it sums CSC portions
-- rather than whole segments, a segment running from a CSC in one area
-- into a CSC in another puts only its own kilometres in each area.
--
-- segment_count is segments TOUCHING the area. A segment crossing between
-- two areas is counted by both, so these counts sum to more than the
-- province's distinct segment count once splits exist. The kilometres do
-- not double: those are portions.
--
-- LEFT JOIN so an area with nothing recorded still returns a zero row
-- rather than vanishing from the list.
-- ---------------------------------------------------------------------

CREATE OR REPLACE VIEW v_line_length_by_area AS
SELECT
  a.area_id,
  a.area_code,
  a.area_name,
  COUNT(DISTINCT d.csc_id)                AS csc_count,
  COUNT(s.register_id)                    AS segment_count,
  COALESCE(SUM(s.is_split), 0)            AS crossing_count,
  COUNT(DISTINCT sr.feeder_id)            AS feeder_count,
  COALESCE(SUM(s.length_km), 0)           AS total_km,
  ROUND(COALESCE(AVG(s.length_km), 0), 3) AS mean_km,
  COALESCE(MAX(s.length_km), 0)           AS longest_km
FROM areas a
JOIN csc_depots d
  ON d.area_id = a.area_id
LEFT JOIN v_segment_csc_share s
  ON s.csc_id = d.csc_id
LEFT JOIN segment_register sr
  ON sr.register_id = s.register_id
GROUP BY a.area_id, a.area_code, a.area_name;
