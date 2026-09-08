-- =====================================================================
--  CEB UVA PROVINCE - ELECTRICAL DISTRIBUTION ASSET MANAGEMENT SYSTEM
--  Deliverable 1 of 9 : Complete database schema
--
--  Target   : MySQL 8.0.16+ / MariaDB 10.4+  (InnoDB, utf8mb4)
--  Tested on: MariaDB 10.11
--  Run with : mysql -u root -p < ceb_ams_schema.sql
--             (or import through phpMyAdmin - DELIMITER blocks are supported)
--
--  DESIGN NOTE - READ BEFORE CHANGING ANYTHING
--  -------------------------------------------
--  The network is a GRAPH, not a list of lines:
--      network_nodes  = points  (substation, switch position, tee, gantry, dead end)
--      segments       = spans   (the line BETWEEN exactly two nodes)
--      assets         = attach to a node XOR a segment, never both
--
--  A switch is stored ONCE, on the node. Any number of segments may touch
--  that node; the switch row still exists exactly once, so double counting
--  is structurally impossible instead of being something a query has to
--  defend against. Adjacency is DERIVED (see v_node_segments) - never stored.
--
--  COUNTING CONTRACT:
--      point assets -> GROUP BY network_nodes.csc_id
--      span  assets -> GROUP BY segments.csc_id
--      everything reads v_asset_rollup. Do not write your own rollup.
-- =====================================================================

DROP DATABASE IF EXISTS ceb_uva_ams;
CREATE DATABASE ceb_uva_ams
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;
USE ceb_uva_ams;

SET FOREIGN_KEY_CHECKS = 1;


-- =====================================================================
-- SECTION 1 : ORGANISATIONAL HIERARCHY
--             Province -> Area -> CSC/Depot
-- =====================================================================

CREATE TABLE provinces (
    province_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    province_code   VARCHAR(10)  NOT NULL,
    province_name   VARCHAR(100) NOT NULL,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (province_id),
    UNIQUE KEY uq_province_code (province_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE areas (
    area_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    province_id     INT UNSIGNED NOT NULL,
    area_code       VARCHAR(10)  NOT NULL,
    area_name       VARCHAR(100) NOT NULL,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (area_id),
    UNIQUE KEY uq_area_code (area_code),
    KEY ix_areas_province (province_id),
    CONSTRAINT fk_areas_province FOREIGN KEY (province_id)
        REFERENCES provinces (province_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE csc_depots (
    csc_id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    area_id         INT UNSIGNED NOT NULL,
    csc_code        VARCHAR(15)  NOT NULL,
    csc_name        VARCHAR(100) NOT NULL,
    depot_type      ENUM('CSC','DEPOT','SUB_DEPOT') NOT NULL DEFAULT 'CSC',
    contact_officer VARCHAR(100) NULL,
    contact_phone   VARCHAR(25)  NULL,
    latitude        DECIMAL(10,7) NULL,
    longitude       DECIMAL(10,7) NULL,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (csc_id),
    UNIQUE KEY uq_csc_code (csc_code),
    KEY ix_csc_area (area_id),
    CONSTRAINT fk_csc_area FOREIGN KEY (area_id)
        REFERENCES areas (area_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_csc_lat CHECK (latitude  IS NULL OR (latitude  BETWEEN  -90 AND  90)),
    CONSTRAINT chk_csc_lon CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SECTION 2 : SECURITY - ROLES AND USERS
-- =====================================================================

CREATE TABLE roles (
    role_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    role_code       VARCHAR(20)  NOT NULL,   -- ADMIN | ENGINEER | VIEWER
    role_name       VARCHAR(50)  NOT NULL,
    description     VARCHAR(255) NULL,
    PRIMARY KEY (role_id),
    UNIQUE KEY uq_role_code (role_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE users (
    user_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    role_id         INT UNSIGNED NOT NULL,
    -- Scope of an ENGINEER. NULL = province-wide (ADMIN, or a VIEWER with
    -- no depot restriction). PHP must check this on every write.
    csc_id          INT UNSIGNED NULL,
    username        VARCHAR(50)  NOT NULL,
    password_hash   VARCHAR(255) NOT NULL,   -- PHP password_hash(), BCRYPT
    full_name       VARCHAR(120) NOT NULL,
    designation     VARCHAR(100) NULL,
    email           VARCHAR(150) NULL,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    last_login_at   DATETIME     NULL,
    failed_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    locked_until    DATETIME     NULL,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id),
    UNIQUE KEY uq_username (username),
    UNIQUE KEY uq_user_email (email),
    KEY ix_users_role (role_id),
    KEY ix_users_csc (csc_id),
    CONSTRAINT fk_users_role FOREIGN KEY (role_id)
        REFERENCES roles (role_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_users_csc FOREIGN KEY (csc_id)
        REFERENCES csc_depots (csc_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SECTION 3 : NETWORK TOPOLOGY  (the three-layer model)
-- =====================================================================

-- ---------------------------------------------------------------------
-- feeders
-- A feeder is an MV outgoing from a grid substation / gantry. It MAY run
-- across several depots and even across areas, so origin_csc_id records
-- only where it starts. It is METADATA - it is NEVER used for counting.
-- Ownership for counting always comes from segments.csc_id / nodes.csc_id.
-- ---------------------------------------------------------------------
CREATE TABLE feeders (
    feeder_id       INT UNSIGNED NOT NULL AUTO_INCREMENT,
    feeder_code     VARCHAR(30)  NOT NULL,
    feeder_name     VARCHAR(120) NOT NULL,
    origin_csc_id   INT UNSIGNED NOT NULL,   -- depot where the feeder originates
    source_name     VARCHAR(120) NULL,       -- e.g. 'Badulla Grid Substation'
    voltage_level   ENUM('33kV','11kV','400V') NOT NULL DEFAULT '33kV',
    status          ENUM('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE',
    remarks         VARCHAR(255) NULL,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (feeder_id),
    UNIQUE KEY uq_feeder_code (feeder_code),
    KEY ix_feeder_origin_csc (origin_csc_id),
    CONSTRAINT fk_feeder_origin_csc FOREIGN KEY (origin_csc_id)
        REFERENCES csc_depots (csc_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------
-- network_nodes  (LAYER 1 - points)
--
-- A node is any point where the network is defined or changes: a
-- substation, a switch position, a tee-off, a gantry, a dead end, a
-- depot boundary, a generation interconnection.
--
-- csc_id is THE owning depot and the ONLY value used to count point
-- assets. Deliberately there is no feeder_id here: a tie node can be the
-- boundary between two different feeders, so a node cannot belong to one.
-- ---------------------------------------------------------------------
CREATE TABLE network_nodes (
    node_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    node_code       VARCHAR(30)  NOT NULL,
    csc_id          INT UNSIGNED NOT NULL,   -- owning depot -> counts here
    node_kind       ENUM('GANTRY','SUBSTATION','SWITCH_POSITION','TEE_OFF',
                         'DEAD_END','BOUNDARY','BULK_SUPPLY','GENERATION',
                         'JUNCTION') NOT NULL,
    name            VARCHAR(150) NOT NULL,
    latitude        DECIMAL(10,7) NULL,
    longitude       DECIMAL(10,7) NULL,
    -- How csc_id above was decided. MANUAL_OVERRIDE requires a reason.
    ownership_source ENUM('UPSTREAM_RULE','MANUAL_OVERRIDE','GEOGRAPHIC')
                     NOT NULL DEFAULT 'UPSTREAM_RULE',
    ownership_note  VARCHAR(500) NULL,
    -- Legitimate line end (single-segment DDLO). Suppresses the
    -- "switch node with only one segment" data-quality warning.
    is_line_end     TINYINT(1)   NOT NULL DEFAULT 0,
    status          ENUM('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE',
    remarks         VARCHAR(255) NULL,
    created_by      INT UNSIGNED NULL,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by      INT UNSIGNED NULL,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (node_id),
    UNIQUE KEY uq_node_code (node_code),
    KEY ix_node_csc (csc_id),
    KEY ix_node_kind (node_kind),
    KEY ix_node_geo (latitude, longitude),
    CONSTRAINT fk_node_csc FOREIGN KEY (csc_id)
        REFERENCES csc_depots (csc_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_node_created_by FOREIGN KEY (created_by)
        REFERENCES users (user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_node_updated_by FOREIGN KEY (updated_by)
        REFERENCES users (user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_node_lat CHECK (latitude  IS NULL OR (latitude  BETWEEN  -90 AND  90)),
    CONSTRAINT chk_node_lon CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180)),
    -- Ownership rule 3: an override must carry a written reason.
    CONSTRAINT chk_node_override_note CHECK (
        ownership_source <> 'MANUAL_OVERRIDE'
        OR (ownership_note IS NOT NULL AND CHAR_LENGTH(TRIM(ownership_note)) >= 10)
    )
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------
-- segments  (LAYER 2 - spans)
--
-- A segment is the line between EXACTLY TWO nodes, nominally directional
-- from the source side (from_node_id) toward the load side (to_node_id).
--
-- Ownership rule 1: a segment may never cross a depot boundary. Split it
-- at the boundary node (see sp_split_segment) so each half has one csc_id.
--
-- "Nominal" matters on a ring: when the normally-open point is moved,
-- real power flow reverses but from/to stay as recorded. Direction is a
-- bookkeeping convention for the upstream ownership rule, not a live
-- statement about flow.
-- ---------------------------------------------------------------------
CREATE TABLE segments (
    segment_id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    segment_code    VARCHAR(30)  NOT NULL,
    feeder_id       INT UNSIGNED NOT NULL,
    csc_id          INT UNSIGNED NOT NULL,   -- owning depot -> counts here
    from_node_id    INT UNSIGNED NOT NULL,   -- nominal source side
    to_node_id      INT UNSIGNED NOT NULL,   -- nominal load side
    circuit_no      TINYINT UNSIGNED NOT NULL DEFAULT 1,  -- 2 for double circuit
    length_km       DECIMAL(8,3) NOT NULL DEFAULT 0.000,
    voltage_level   ENUM('33kV','11kV','400V') NOT NULL DEFAULT '33kV',
    -- TRUE where the segment sits behind a normally-open point, i.e. the
    -- nominal direction can legitimately reverse under a switching plan.
    is_normally_open TINYINT(1)  NOT NULL DEFAULT 0,
    -- TRUE when the span can be back-fed from the load side (ring, or
    -- embedded generation downstream). Warns the UI that "upstream" is
    -- not a permanent property here.
    is_reversible   TINYINT(1)   NOT NULL DEFAULT 0,
    status          ENUM('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE',
    remarks         VARCHAR(255) NULL,
    created_by      INT UNSIGNED NULL,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by      INT UNSIGNED NULL,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (segment_id),
    UNIQUE KEY uq_segment_code (segment_code),
    -- Prevents accidentally entering the same span twice; circuit_no
    -- still allows a genuine double circuit between the same two nodes.
    UNIQUE KEY uq_segment_span (feeder_id, from_node_id, to_node_id, circuit_no),
    KEY ix_segment_csc (csc_id),
    KEY ix_segment_feeder (feeder_id),
    KEY ix_segment_from (from_node_id),
    KEY ix_segment_to (to_node_id),
    CONSTRAINT fk_segment_feeder FOREIGN KEY (feeder_id)
        REFERENCES feeders (feeder_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_segment_csc FOREIGN KEY (csc_id)
        REFERENCES csc_depots (csc_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    -- ON DELETE RESTRICT: a node referenced by any segment cannot be deleted.
    -- NOTE: ON UPDATE RESTRICT, not CASCADE. MySQL 8 / MariaDB refuse a CHECK
    -- constraint on a column whose foreign key has a cascading action, and
    -- chk_segment_not_self below matters more. These are AUTO_INCREMENT
    -- surrogate keys that never change, so nothing is lost.
    CONSTRAINT fk_segment_from_node FOREIGN KEY (from_node_id)
        REFERENCES network_nodes (node_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_segment_to_node FOREIGN KEY (to_node_id)
        REFERENCES network_nodes (node_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_segment_created_by FOREIGN KEY (created_by)
        REFERENCES users (user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_segment_updated_by FOREIGN KEY (updated_by)
        REFERENCES users (user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_segment_not_self CHECK (from_node_id <> to_node_id),
    CONSTRAINT chk_segment_length CHECK (length_km >= 0 AND length_km <= 500)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------
-- node_shared_with
-- Other depots that also operate or view this node. Ownership rule 4:
-- shared visibility WITHOUT shared counting. Reports must never read
-- this table - it exists for maps, asset lists and switching access.
-- ---------------------------------------------------------------------
CREATE TABLE node_shared_with (
    node_id         INT UNSIGNED NOT NULL,
    csc_id          INT UNSIGNED NOT NULL,
    share_reason    VARCHAR(255) NULL,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (node_id, csc_id),
    KEY ix_shared_csc (csc_id),
    CONSTRAINT fk_shared_node FOREIGN KEY (node_id)
        REFERENCES network_nodes (node_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_shared_csc FOREIGN KEY (csc_id)
        REFERENCES csc_depots (csc_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SECTION 4 : ASSET TAXONOMY
-- =====================================================================

CREATE TABLE asset_categories (
    category_id     INT UNSIGNED NOT NULL AUTO_INCREMENT,
    category_code   VARCHAR(20)  NOT NULL,
    category_name   VARCHAR(80)  NOT NULL,
    display_order   SMALLINT UNSIGNED NOT NULL DEFAULT 100,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    PRIMARY KEY (category_id),
    UNIQUE KEY uq_category_code (category_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- is_line_asset drives the whole asset-entry form:
--   TRUE  -> SPAN asset  -> must attach to segment_id
--   FALSE -> POINT asset -> must attach to node_id
-- Enforced by trigger trg_assets_bi / trg_assets_bu below.
CREATE TABLE asset_types (
    asset_type_id   INT UNSIGNED NOT NULL AUTO_INCREMENT,
    category_id     INT UNSIGNED NOT NULL,
    type_code       VARCHAR(30)  NOT NULL,
    type_name       VARCHAR(100) NOT NULL,
    unit_of_measure ENUM('nos','km','kVA','kW') NOT NULL DEFAULT 'nos',
    is_line_asset   TINYINT(1)   NOT NULL DEFAULT 0,
    rated_kva       INT UNSIGNED NULL,   -- substations, for the capacity mix chart
    -- Whether whole numbers are required (poles, switches) vs decimals (km).
    allow_decimal   TINYINT(1)   NOT NULL DEFAULT 0,
    display_order   SMALLINT UNSIGNED NOT NULL DEFAULT 100,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    PRIMARY KEY (asset_type_id),
    UNIQUE KEY uq_type_code (type_code),
    KEY ix_type_category (category_id),
    KEY ix_type_line_flag (is_line_asset),
    CONSTRAINT fk_type_category FOREIGN KEY (category_id)
        REFERENCES asset_categories (category_id) ON DELETE RESTRICT ON UPDATE CASCADE
    -- Deliberately no constraint tying is_line_asset to km. Poles are a span
    -- asset (recorded per segment) but are counted in 'nos', so the routing
    -- flag and the unit are independent.
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SECTION 5 : ASSETS  (LAYER 3)
--
-- Exactly one of node_id / segment_id is populated. The CHECK below is
-- the structural guarantee; trg_assets_bi additionally verifies the
-- chosen layer matches asset_types.is_line_asset, which a CHECK cannot
-- do because it spans two tables.
-- =====================================================================

CREATE TABLE assets (
    asset_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    asset_code      VARCHAR(40)  NULL,       -- utility tag / plate number
    asset_type_id   INT UNSIGNED NOT NULL,
    node_id         INT UNSIGNED NULL,       -- point asset
    segment_id      INT UNSIGNED NULL,       -- span asset
    -- Display only. For a switch at a tee-off, records which branch the
    -- switch faces. NEVER used for counting - see the counting contract.
    oriented_to_segment_id INT UNSIGNED NULL,
    quantity        DECIMAL(12,3) NOT NULL DEFAULT 1.000,
    unit_of_measure ENUM('nos','km','kVA','kW') NOT NULL DEFAULT 'nos',
    install_date    DATE         NULL,
    condition_status ENUM('NEW','GOOD','FAIR','POOR','FAULTY','UNKNOWN')
                     NOT NULL DEFAULT 'UNKNOWN',
    status          ENUM('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE',
    remarks         VARCHAR(500) NULL,
    created_by      INT UNSIGNED NULL,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_by      INT UNSIGNED NULL,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (asset_id),
    UNIQUE KEY uq_asset_code (asset_code),
    KEY ix_asset_type (asset_type_id),
    KEY ix_asset_node (node_id),
    KEY ix_asset_segment (segment_id),
    KEY ix_asset_status (status),
    CONSTRAINT fk_asset_type FOREIGN KEY (asset_type_id)
        REFERENCES asset_types (asset_type_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    -- ON UPDATE RESTRICT for the same reason as in segments: these two
    -- columns carry chk_asset_one_layer, the core rule of the whole model.
    CONSTRAINT fk_asset_node FOREIGN KEY (node_id)
        REFERENCES network_nodes (node_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_asset_segment FOREIGN KEY (segment_id)
        REFERENCES segments (segment_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_asset_oriented FOREIGN KEY (oriented_to_segment_id)
        REFERENCES segments (segment_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_asset_created_by FOREIGN KEY (created_by)
        REFERENCES users (user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_asset_updated_by FOREIGN KEY (updated_by)
        REFERENCES users (user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    -- The core rule: a node XOR a segment, never both, never neither.
    CONSTRAINT chk_asset_one_layer CHECK ((node_id IS NULL) <> (segment_id IS NULL)),
    -- Orientation only makes sense for a point asset. That rule lives in
    -- trg_assets_bi/bu because this column keeps ON DELETE SET NULL.
    CONSTRAINT chk_asset_qty CHECK (quantity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SECTION 6 : AUDIT TRAIL
--
-- PHP must run  SET @app_user_id = :user_id;  immediately after opening
-- the PDO connection (see config/db.php in deliverable 2). The triggers
-- read that session variable; without it changed_by is NULL.
-- =====================================================================

CREATE TABLE audit_log (
    audit_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    table_name      VARCHAR(64)  NOT NULL,
    record_id       BIGINT UNSIGNED NOT NULL,
    action          ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    changed_by      INT UNSIGNED NULL,
    changed_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    old_values      JSON         NULL,
    new_values      JSON         NULL,
    ip_address      VARCHAR(45)  NULL,
    note            VARCHAR(255) NULL,
    PRIMARY KEY (audit_id),
    KEY ix_audit_record (table_name, record_id),
    KEY ix_audit_when (changed_at),
    KEY ix_audit_user (changed_by),
    CONSTRAINT fk_audit_user FOREIGN KEY (changed_by)
        REFERENCES users (user_id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SECTION 7 : REPORTING VIEWS
--             PHP, Chart.js and PhpSpreadsheet all read these, so every
--             surface shows the same numbers.
-- =====================================================================

-- ---------------------------------------------------------------------
-- v_node_segments : DERIVED adjacency.
-- "Which segments does this switch separate?" is answered here, at query
-- time, from the segments that reference the node. Adjacency is never
-- stored. FOR DISPLAY AND TRACING ONLY - never join this into a count.
-- ---------------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_node_segments AS
SELECT
    n.node_id,
    n.node_code,
    n.name              AS node_name,
    n.csc_id            AS node_csc_id,
    s.segment_id,
    s.segment_code,
    s.feeder_id,
    s.csc_id            AS segment_csc_id,
    s.length_km,
    s.voltage_level,
    s.status            AS segment_status,
    CASE WHEN s.to_node_id = n.node_id THEN 'UPSTREAM_OF_NODE'
         ELSE 'DOWNSTREAM_OF_NODE' END AS relation,
    CASE WHEN s.to_node_id = n.node_id THEN s.from_node_id
         ELSE s.to_node_id END          AS other_node_id
FROM network_nodes n
JOIN segments s
  ON n.node_id = s.from_node_id
  OR n.node_id = s.to_node_id;


-- Degree of every node (how many segments touch it) plus how many of
-- those are on the feeding side. Used by the data-quality checks.
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_node_degree AS
SELECT
    n.node_id,
    n.node_code,
    n.csc_id,
    COUNT(s.segment_id) AS segment_count,
    SUM(CASE WHEN s.to_node_id   = n.node_id THEN 1 ELSE 0 END) AS upstream_count,
    SUM(CASE WHEN s.from_node_id = n.node_id THEN 1 ELSE 0 END) AS downstream_count
FROM network_nodes n
LEFT JOIN segments s
  ON (n.node_id = s.from_node_id OR n.node_id = s.to_node_id)
 AND s.status <> 'RETIRED'
GROUP BY n.node_id, n.node_code, n.csc_id;


-- ---------------------------------------------------------------------
-- v_asset_rollup : THE single source of truth for every count.
--
-- Branch 1 = point assets, owner taken from network_nodes.csc_id
-- Branch 2 = span  assets, owner taken from segments.csc_id
--
-- A switch appears once, in branch 1, no matter how many segments touch
-- its node - which is exactly why switches are never joined to segments
-- for counting. Roll this up by csc_id / area_id / province_id.
-- ---------------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_asset_rollup AS
SELECT
    'POINT'             AS attach_layer,
    a.asset_id,
    a.asset_code,
    a.asset_type_id,
    t.type_name,
    t.type_code,
    c.category_id,
    c.category_name,
    t.unit_of_measure,
    t.rated_kva,
    a.quantity,
    a.condition_status,
    a.install_date,
    n.node_id,
    NULL                AS segment_id,
    NULL                AS feeder_id,
    n.csc_id,
    d.csc_code,
    d.csc_name,
    d.area_id,
    ar.area_code,
    ar.area_name,
    ar.province_id,
    p.province_name
FROM assets a
JOIN asset_types      t  ON t.asset_type_id = a.asset_type_id
JOIN asset_categories c  ON c.category_id   = t.category_id
JOIN network_nodes    n  ON n.node_id       = a.node_id
JOIN csc_depots       d  ON d.csc_id        = n.csc_id
JOIN areas            ar ON ar.area_id      = d.area_id
JOIN provinces        p  ON p.province_id   = ar.province_id
WHERE a.node_id IS NOT NULL
  AND a.status = 'ACTIVE'

UNION ALL

SELECT
    'SPAN'              AS attach_layer,
    a.asset_id,
    a.asset_code,
    a.asset_type_id,
    t.type_name,
    t.type_code,
    c.category_id,
    c.category_name,
    t.unit_of_measure,
    t.rated_kva,
    a.quantity,
    a.condition_status,
    a.install_date,
    NULL                AS node_id,
    s.segment_id,
    s.feeder_id,
    s.csc_id,
    d.csc_code,
    d.csc_name,
    d.area_id,
    ar.area_code,
    ar.area_name,
    ar.province_id,
    p.province_name
FROM assets a
JOIN asset_types      t  ON t.asset_type_id = a.asset_type_id
JOIN asset_categories c  ON c.category_id   = t.category_id
JOIN segments         s  ON s.segment_id    = a.segment_id
JOIN csc_depots       d  ON d.csc_id        = s.csc_id
JOIN areas            ar ON ar.area_id      = d.area_id
JOIN provinces        p  ON p.province_id   = ar.province_id
WHERE a.segment_id IS NOT NULL
  AND a.status = 'ACTIVE';


-- Convenience rollups for the dashboard and the Excel reports.
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_totals_by_csc AS
SELECT province_id, province_name, area_id, area_code, area_name,
       csc_id, csc_code, csc_name,
       category_id, category_name, asset_type_id, type_name, unit_of_measure,
       SUM(quantity) AS total_quantity,
       COUNT(*)      AS record_count
FROM v_asset_rollup
GROUP BY province_id, province_name, area_id, area_code, area_name,
         csc_id, csc_code, csc_name,
         category_id, category_name, asset_type_id, type_name, unit_of_measure;

CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_totals_by_area AS
SELECT province_id, province_name, area_id, area_code, area_name,
       category_id, category_name, asset_type_id, type_name, unit_of_measure,
       SUM(quantity) AS total_quantity
FROM v_asset_rollup
GROUP BY province_id, province_name, area_id, area_code, area_name,
         category_id, category_name, asset_type_id, type_name, unit_of_measure;

CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_totals_by_province AS
SELECT province_id, province_name,
       category_id, category_name, asset_type_id, type_name, unit_of_measure,
       SUM(quantity) AS total_quantity
FROM v_asset_rollup
GROUP BY province_id, province_name,
         category_id, category_name, asset_type_id, type_name, unit_of_measure;

-- Substation capacity mix for the dashboard doughnut chart.
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_substation_capacity AS
SELECT province_id, area_id, area_name, csc_id, csc_name,
       rated_kva, type_name,
       SUM(quantity)             AS unit_count,
       SUM(quantity * rated_kva) AS installed_kva
FROM v_asset_rollup
WHERE rated_kva IS NOT NULL
GROUP BY province_id, area_id, area_name, csc_id, csc_name, rated_kva, type_name;


-- ---------------------------------------------------------------------
-- v_data_quality_issues
-- Everything the schema cannot hard-block but an engineer should review.
-- Drives report #4 in the reports module.
-- ---------------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_data_quality_issues AS
-- 1. Node not referenced by any segment.
SELECT 'ORPHAN_NODE' AS issue_code, 'WARNING' AS severity, 'network_nodes' AS entity,
       n.node_id AS entity_id, n.node_code AS entity_code, n.csc_id,
       CONCAT('Node "', n.name, '" is not referenced by any segment.') AS description
FROM network_nodes n
JOIN v_node_degree g ON g.node_id = n.node_id
WHERE g.segment_count = 0 AND n.status = 'ACTIVE'

UNION ALL
-- 2. A switch normally separates two or more segments. One segment is
--    legal only at a line end (set network_nodes.is_line_end = 1).
SELECT 'SWITCH_NODE_SINGLE_SEGMENT', 'WARNING', 'network_nodes',
       n.node_id, n.node_code, n.csc_id,
       CONCAT('Node "', n.name, '" carries switchgear but touches only one segment. ',
              'Confirm it is a line-end DDLO and set is_line_end.')
FROM network_nodes n
JOIN v_node_degree g ON g.node_id = n.node_id
WHERE g.segment_count = 1
  AND n.is_line_end = 0
  AND n.status = 'ACTIVE'
  AND EXISTS (SELECT 1 FROM assets a
              JOIN asset_types t ON t.asset_type_id = a.asset_type_id
              JOIN asset_categories c ON c.category_id = t.category_id
              WHERE a.node_id = n.node_id AND c.category_code = 'SWITCHGEAR'
                AND a.status = 'ACTIVE')

UNION ALL
-- 3. The owning depot is not one of the depots that actually touch the
--    node and is not even listed as a sharer - almost always a typo.
SELECT 'NODE_OWNER_NOT_ADJACENT', 'ERROR', 'network_nodes',
       n.node_id, n.node_code, n.csc_id,
       CONCAT('Owning depot of node "', n.name, '" does not own any adjacent segment.')
FROM network_nodes n
JOIN v_node_degree g ON g.node_id = n.node_id
WHERE g.segment_count > 0
  AND n.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM v_node_segments vs
                  WHERE vs.node_id = n.node_id AND vs.segment_csc_id = n.csc_id)
  AND NOT EXISTS (SELECT 1 FROM node_shared_with sh
                  WHERE sh.node_id = n.node_id AND sh.csc_id = n.csc_id)

UNION ALL
-- 4. Manual ownership overrides, listed for periodic management review.
SELECT 'OWNERSHIP_OVERRIDE', 'INFO', 'network_nodes',
       n.node_id, n.node_code, n.csc_id,
       CONCAT('Ownership manually overridden: ', COALESCE(n.ownership_note, ''))
FROM network_nodes n
WHERE n.ownership_source = 'MANUAL_OVERRIDE' AND n.status = 'ACTIVE'

UNION ALL
-- 5. Node with no coordinates cannot be plotted on the ArcGIS map.
SELECT 'NODE_MISSING_COORDINATES', 'WARNING', 'network_nodes',
       n.node_id, n.node_code, n.csc_id,
       CONCAT('Node "', n.name, '" has no latitude/longitude.')
FROM network_nodes n
WHERE (n.latitude IS NULL OR n.longitude IS NULL) AND n.status = 'ACTIVE'

UNION ALL
-- 6. Substation / gantry / generation nodes are topology only. The
--    countable thing is the asset row, so a node of that kind with no
--    matching asset will silently be missing from every total.
SELECT 'NODE_KIND_WITHOUT_ASSET', 'ERROR', 'network_nodes',
       n.node_id, n.node_code, n.csc_id,
       CONCAT('Node kind ', n.node_kind, ' has no corresponding asset record, ',
              'so it is not being counted anywhere.')
FROM network_nodes n
WHERE n.status = 'ACTIVE'
  AND n.node_kind IN ('SUBSTATION','GANTRY','GENERATION','BULK_SUPPLY')
  AND NOT EXISTS (SELECT 1 FROM assets a WHERE a.node_id = n.node_id AND a.status = 'ACTIVE')

UNION ALL
-- 7. Zero-length active segment.
SELECT 'SEGMENT_ZERO_LENGTH', 'WARNING', 'segments',
       s.segment_id, s.segment_code, s.csc_id,
       CONCAT('Segment "', s.segment_code, '" has length 0.000 km.')
FROM segments s
WHERE s.length_km <= 0 AND s.status = 'ACTIVE'

UNION ALL
-- 8. Active segment with no conductor recorded against it.
SELECT 'SEGMENT_NO_CONDUCTOR', 'WARNING', 'segments',
       s.segment_id, s.segment_code, s.csc_id,
       CONCAT('Segment "', s.segment_code, '" has no conductor asset.')
FROM segments s
WHERE s.status = 'ACTIVE'
  AND NOT EXISTS (SELECT 1 FROM assets a
                  JOIN asset_types t ON t.asset_type_id = a.asset_type_id
                  JOIN asset_categories c ON c.category_id = t.category_id
                  WHERE a.segment_id = s.segment_id AND c.category_code = 'CONDUCTOR'
                    AND a.status = 'ACTIVE')

UNION ALL
-- 9. Conductor km wildly out of step with the span length. Tolerance is
--    generous because a double circuit legitimately gives about 2x.
SELECT 'CONDUCTOR_LENGTH_MISMATCH', 'WARNING', 'segments',
       s.segment_id, s.segment_code, s.csc_id,
       CONCAT('Conductor total ', ROUND(x.cond_km,3), ' km against a span of ',
              s.length_km, ' km. Check for a data entry error.')
FROM segments s
JOIN (SELECT a.segment_id, SUM(a.quantity) AS cond_km
      FROM assets a
      JOIN asset_types t ON t.asset_type_id = a.asset_type_id
      JOIN asset_categories c ON c.category_id = t.category_id
      WHERE c.category_code = 'CONDUCTOR' AND a.status = 'ACTIVE'
      GROUP BY a.segment_id) x ON x.segment_id = s.segment_id
WHERE s.status = 'ACTIVE' AND s.length_km > 0
  AND (x.cond_km < s.length_km * 0.8 OR x.cond_km > s.length_km * 2.4)

UNION ALL
-- 10. A depot listed as sharing a node it already owns.
SELECT 'REDUNDANT_SHARE', 'INFO', 'node_shared_with',
       n.node_id, n.node_code, n.csc_id,
       'Owning depot is also listed in node_shared_with.'
FROM network_nodes n
JOIN node_shared_with sh ON sh.node_id = n.node_id AND sh.csc_id = n.csc_id;


-- =====================================================================
-- SECTION 8 : TRIGGERS
-- =====================================================================
DELIMITER $$

-- ---------- assets : layer validation ----------
-- A CHECK constraint cannot look at asset_types, so the is_line_asset
-- rule is enforced here. Deliverable 6 validates it again in PHP so the
-- user sees a friendly English message instead of a SQL error.
CREATE TRIGGER trg_assets_bi BEFORE INSERT ON assets
FOR EACH ROW
BEGIN
    DECLARE v_is_line TINYINT(1);
    DECLARE v_uom     VARCHAR(10);
    DECLARE v_decimal TINYINT(1);

    SELECT is_line_asset, unit_of_measure, allow_decimal
      INTO v_is_line, v_uom, v_decimal
      FROM asset_types WHERE asset_type_id = NEW.asset_type_id;

    IF v_is_line = 1 AND NEW.segment_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This is a line (span) asset and must be attached to a segment, not a node.';
    END IF;

    IF v_is_line = 0 AND NEW.node_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This is a point asset and must be attached to a node, not a segment.';
    END IF;

    IF v_decimal = 0 AND NEW.quantity <> FLOOR(NEW.quantity) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This asset type is counted in whole numbers only.';
    END IF;

    IF NEW.oriented_to_segment_id IS NOT NULL AND NEW.node_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Only a point asset on a node can face a particular branch.';
    END IF;

    -- The unit always follows the type; never trust the form field.
    SET NEW.unit_of_measure = v_uom;
END$$

CREATE TRIGGER trg_assets_bu BEFORE UPDATE ON assets
FOR EACH ROW
BEGIN
    DECLARE v_is_line TINYINT(1);
    DECLARE v_uom     VARCHAR(10);
    DECLARE v_decimal TINYINT(1);

    SELECT is_line_asset, unit_of_measure, allow_decimal
      INTO v_is_line, v_uom, v_decimal
      FROM asset_types WHERE asset_type_id = NEW.asset_type_id;

    IF v_is_line = 1 AND NEW.segment_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This is a line (span) asset and must be attached to a segment, not a node.';
    END IF;

    IF v_is_line = 0 AND NEW.node_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This is a point asset and must be attached to a node, not a segment.';
    END IF;

    IF v_decimal = 0 AND NEW.quantity <> FLOOR(NEW.quantity) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This asset type is counted in whole numbers only.';
    END IF;

    IF NEW.oriented_to_segment_id IS NOT NULL AND NEW.node_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Only a point asset on a node can face a particular branch.';
    END IF;

    SET NEW.unit_of_measure = v_uom;
END$$

-- ---------- node_shared_with : a depot cannot share with itself ----------
CREATE TRIGGER trg_shared_bi BEFORE INSERT ON node_shared_with
FOR EACH ROW
BEGIN
    DECLARE v_owner INT UNSIGNED;
    SELECT csc_id INTO v_owner FROM network_nodes WHERE node_id = NEW.node_id;
    IF v_owner = NEW.csc_id THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'This depot already owns the node; it does not need a share entry.';
    END IF;
END$$

-- ---------- audit : assets ----------
CREATE TRIGGER trg_assets_ai AFTER INSERT ON assets
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, new_values)
    VALUES ('assets', NEW.asset_id, 'INSERT', @app_user_id,
            JSON_OBJECT('asset_type_id', NEW.asset_type_id, 'node_id', NEW.node_id,
                        'segment_id', NEW.segment_id, 'quantity', NEW.quantity,
                        'condition_status', NEW.condition_status, 'status', NEW.status));
END$$

CREATE TRIGGER trg_assets_au AFTER UPDATE ON assets
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, old_values, new_values)
    VALUES ('assets', NEW.asset_id, 'UPDATE', @app_user_id,
            JSON_OBJECT('asset_type_id', OLD.asset_type_id, 'node_id', OLD.node_id,
                        'segment_id', OLD.segment_id, 'quantity', OLD.quantity,
                        'condition_status', OLD.condition_status, 'status', OLD.status),
            JSON_OBJECT('asset_type_id', NEW.asset_type_id, 'node_id', NEW.node_id,
                        'segment_id', NEW.segment_id, 'quantity', NEW.quantity,
                        'condition_status', NEW.condition_status, 'status', NEW.status));
END$$

CREATE TRIGGER trg_assets_ad AFTER DELETE ON assets
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, old_values)
    VALUES ('assets', OLD.asset_id, 'DELETE', @app_user_id,
            JSON_OBJECT('asset_type_id', OLD.asset_type_id, 'node_id', OLD.node_id,
                        'segment_id', OLD.segment_id, 'quantity', OLD.quantity,
                        'condition_status', OLD.condition_status, 'status', OLD.status));
END$$

-- ---------- audit : network_nodes ----------
CREATE TRIGGER trg_nodes_ai AFTER INSERT ON network_nodes
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, new_values)
    VALUES ('network_nodes', NEW.node_id, 'INSERT', @app_user_id,
            JSON_OBJECT('node_code', NEW.node_code, 'csc_id', NEW.csc_id,
                        'node_kind', NEW.node_kind, 'name', NEW.name,
                        'ownership_source', NEW.ownership_source, 'status', NEW.status));
END$$

CREATE TRIGGER trg_nodes_au AFTER UPDATE ON network_nodes
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, old_values, new_values)
    VALUES ('network_nodes', NEW.node_id, 'UPDATE', @app_user_id,
            JSON_OBJECT('node_code', OLD.node_code, 'csc_id', OLD.csc_id,
                        'node_kind', OLD.node_kind, 'name', OLD.name,
                        'ownership_source', OLD.ownership_source,
                        'ownership_note', OLD.ownership_note, 'status', OLD.status),
            JSON_OBJECT('node_code', NEW.node_code, 'csc_id', NEW.csc_id,
                        'node_kind', NEW.node_kind, 'name', NEW.name,
                        'ownership_source', NEW.ownership_source,
                        'ownership_note', NEW.ownership_note, 'status', NEW.status));
END$$

CREATE TRIGGER trg_nodes_ad AFTER DELETE ON network_nodes
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, old_values)
    VALUES ('network_nodes', OLD.node_id, 'DELETE', @app_user_id,
            JSON_OBJECT('node_code', OLD.node_code, 'csc_id', OLD.csc_id,
                        'node_kind', OLD.node_kind, 'name', OLD.name));
END$$

-- ---------- audit : segments ----------
CREATE TRIGGER trg_segments_ai AFTER INSERT ON segments
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, new_values)
    VALUES ('segments', NEW.segment_id, 'INSERT', @app_user_id,
            JSON_OBJECT('segment_code', NEW.segment_code, 'feeder_id', NEW.feeder_id,
                        'csc_id', NEW.csc_id, 'from_node_id', NEW.from_node_id,
                        'to_node_id', NEW.to_node_id, 'length_km', NEW.length_km,
                        'status', NEW.status));
END$$

CREATE TRIGGER trg_segments_au AFTER UPDATE ON segments
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, old_values, new_values)
    VALUES ('segments', NEW.segment_id, 'UPDATE', @app_user_id,
            JSON_OBJECT('segment_code', OLD.segment_code, 'csc_id', OLD.csc_id,
                        'from_node_id', OLD.from_node_id, 'to_node_id', OLD.to_node_id,
                        'length_km', OLD.length_km, 'status', OLD.status),
            JSON_OBJECT('segment_code', NEW.segment_code, 'csc_id', NEW.csc_id,
                        'from_node_id', NEW.from_node_id, 'to_node_id', NEW.to_node_id,
                        'length_km', NEW.length_km, 'status', NEW.status));
END$$

CREATE TRIGGER trg_segments_ad AFTER DELETE ON segments
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, old_values)
    VALUES ('segments', OLD.segment_id, 'DELETE', @app_user_id,
            JSON_OBJECT('segment_code', OLD.segment_code, 'csc_id', OLD.csc_id,
                        'from_node_id', OLD.from_node_id, 'to_node_id', OLD.to_node_id,
                        'length_km', OLD.length_km));
END$$

DELIMITER ;


-- =====================================================================
-- SECTION 9 : STORED PROCEDURE - splitting a segment at a boundary
--
-- Ownership rule 1 says no segment may cross a depot boundary. When a
-- line is found to run from one CSC into another, call this to split it
-- at the boundary node. The original segment becomes the first half so
-- existing foreign keys stay valid; span assets are apportioned pro rata
-- by length, with any rounding remainder left on the first half.
-- =====================================================================
DELIMITER $$

CREATE PROCEDURE sp_split_segment (
    IN p_segment_id      INT UNSIGNED,
    IN p_split_node_id   INT UNSIGNED,   -- existing boundary node
    IN p_first_length_km DECIMAL(8,3),   -- length of the upstream half
    IN p_second_csc_id   INT UNSIGNED,   -- depot owning the downstream half
    IN p_new_code_suffix VARCHAR(10)
)
SQL SECURITY INVOKER
BEGIN
    DECLARE v_total_len  DECIMAL(8,3);
    DECLARE v_to_node    INT UNSIGNED;
    DECLARE v_feeder     INT UNSIGNED;
    DECLARE v_code       VARCHAR(30);
    DECLARE v_voltage    VARCHAR(10);
    DECLARE v_new_seg    INT UNSIGNED;
    DECLARE v_ratio      DECIMAL(10,6);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT length_km, to_node_id, feeder_id, segment_code, voltage_level
      INTO v_total_len, v_to_node, v_feeder, v_code, v_voltage
      FROM segments WHERE segment_id = p_segment_id FOR UPDATE;

    IF v_total_len IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Segment not found.';
    END IF;

    IF p_first_length_km <= 0 OR p_first_length_km >= v_total_len THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'The split length must be greater than zero and less than the segment length.';
    END IF;

    SET v_ratio = p_first_length_km / v_total_len;

    -- Downstream half.
    INSERT INTO segments (segment_code, feeder_id, csc_id, from_node_id, to_node_id,
                          length_km, voltage_level, status, remarks, created_by)
    VALUES (CONCAT(v_code, '-', p_new_code_suffix), v_feeder, p_second_csc_id,
            p_split_node_id, v_to_node, v_total_len - p_first_length_km,
            v_voltage, 'ACTIVE',
            CONCAT('Created by splitting ', v_code, ' at the depot boundary.'),
            @app_user_id);
    SET v_new_seg = LAST_INSERT_ID();

    -- Original becomes the upstream half.
    UPDATE segments
       SET to_node_id = p_split_node_id,
           length_km  = p_first_length_km,
           updated_by = @app_user_id
     WHERE segment_id = p_segment_id;

    -- Apportion span assets. Whole-number types keep the remainder on the
    -- first half so nothing is lost to rounding.
    INSERT INTO assets (asset_type_id, segment_id, quantity, unit_of_measure,
                        install_date, condition_status, status, remarks, created_by)
    SELECT a.asset_type_id, v_new_seg,
           CASE WHEN t.allow_decimal = 1
                THEN ROUND(a.quantity * (1 - v_ratio), 3)
                ELSE FLOOR(a.quantity * (1 - v_ratio)) END,
           a.unit_of_measure, a.install_date, a.condition_status, a.status,
           CONCAT('Apportioned from ', v_code, ' on split.'), @app_user_id
      FROM assets a
      JOIN asset_types t ON t.asset_type_id = a.asset_type_id
     WHERE a.segment_id = p_segment_id
       AND a.status = 'ACTIVE'
       AND CASE WHEN t.allow_decimal = 1
                THEN ROUND(a.quantity * (1 - v_ratio), 3)
                ELSE FLOOR(a.quantity * (1 - v_ratio)) END > 0;

    UPDATE assets a
      JOIN asset_types t ON t.asset_type_id = a.asset_type_id
       SET a.quantity = CASE WHEN t.allow_decimal = 1
                             THEN ROUND(a.quantity * v_ratio, 3)
                             ELSE a.quantity - FLOOR(a.quantity * (1 - v_ratio)) END,
           a.updated_by = @app_user_id
     WHERE a.segment_id = p_segment_id AND a.status = 'ACTIVE';

    COMMIT;

    SELECT p_segment_id AS upstream_segment_id, v_new_seg AS downstream_segment_id;
END$$

DELIMITER ;


-- =====================================================================
-- SECTION 10 : SEED DATA
--   Province + all 5 areas + all 17 CSCs (master data)
--   Full network for ONE area (Badulla) and TWO depots
--   (Badulla Town and Hali-Ela), including the boundary switch case.
--   Three deliberate data-quality defects are included at the end so the
--   data-quality report has something to show on day one.
-- =====================================================================

INSERT INTO provinces (province_id, province_code, province_name) VALUES
(1, 'UVA', 'Uva');

INSERT INTO areas (area_id, province_id, area_code, area_name) VALUES
(1, 1, 'BDL', 'Badulla'),
(2, 1, 'BWL', 'Bandarawela'),
(3, 1, 'WLM', 'Welimada'),
(4, 1, 'MNR', 'Monaragala'),
(5, 1, 'BBL', 'Bibile');

INSERT INTO csc_depots (csc_id, area_id, csc_code, csc_name, depot_type, latitude, longitude) VALUES
-- Area 1 : Badulla
(1,  1, 'BDL-CSC01', 'Badulla Town',      'CSC',   6.9895000, 81.0557000),
(2,  1, 'BDL-CSC02', 'Hali-Ela',          'CSC',   6.9614000, 81.0244000),
(3,  1, 'BDL-CSC03', 'Passara',           'DEPOT', 6.9147000, 81.1519000),
(4,  1, 'BDL-CSC04', 'Meegahakiula',      'DEPOT', 7.0725000, 81.1247000),
-- Area 2 : Bandarawela
(5,  2, 'BWL-CSC01', 'Bandarawela',       'CSC',   6.8330000, 80.9870000),
(6,  2, 'BWL-CSC02', 'Diyatalawa',        'DEPOT', 6.8158000, 80.9622000),
(7,  2, 'BWL-CSC03', 'Haputale',          'DEPOT', 6.7683000, 80.9514000),
(8,  2, 'BWL-CSC04', 'Ella',              'DEPOT', 6.8667000, 81.0466000),
-- Area 3 : Welimada
(9,  3, 'WLM-CSC01', 'Welimada',          'CSC',   6.9053000, 80.9142000),
(10, 3, 'WLM-CSC02', 'Boralanda',         'DEPOT', 6.8489000, 80.8903000),
(11, 3, 'WLM-CSC03', 'Keppetipola',       'DEPOT', 6.8783000, 80.8506000),
-- Area 4 : Monaragala
(12, 4, 'MNR-CSC01', 'Monaragala',        'CSC',   6.8720000, 81.3487000),
(13, 4, 'MNR-CSC02', 'Wellawaya',         'DEPOT', 6.7378000, 81.1022000),
(14, 4, 'MNR-CSC03', 'Buttala',           'DEPOT', 6.7597000, 81.2400000),
-- Area 5 : Bibile
(15, 5, 'BBL-CSC01', 'Bibile',            'CSC',   7.1600000, 81.2200000),
(16, 5, 'BBL-CSC02', 'Mahiyanganaya',     'DEPOT', 7.3300000, 81.0000000),
(17, 5, 'BBL-CSC03', 'Girandurukotte',    'DEPOT', 7.4667000, 81.0167000);

INSERT INTO roles (role_id, role_code, role_name, description) VALUES
(1, 'ADMIN',    'Administrator',  'Full access to all provinces, master data and users.'),
(2, 'ENGINEER', 'Engineer',       'Create and edit network and assets for the assigned CSC only.'),
(3, 'VIEWER',   'Viewer',         'Read-only access to dashboards, maps and reports.');

-- Demo passwords: Admin@123 / Engineer@123 / Viewer@123
-- Change these before any deployment outside XAMPP.
INSERT INTO users (user_id, role_id, csc_id, username, password_hash, full_name, designation, email) VALUES
(1, 1, NULL, 'admin',    '$2y$10$SN1gMsGheEI4VM2gRf6Bc./0hb0Y/oLme8E4Q3SBToIckjX6SIf2y',
     'System Administrator', 'IT Administrator', 'admin@ceb.lk'),
(2, 2, 1,    'eng.badulla',  '$2y$10$MhIMqtH.kSp5/h.rLNICrujpDTRYXFkuv7pSzP0n.oVKU.bw4Gj/a',
     'K. Jayasekara', 'Electrical Engineer - Badulla Town', 'ee.badulla@ceb.lk'),
(3, 2, 2,    'eng.halieala', '$2y$10$MhIMqtH.kSp5/h.rLNICrujpDTRYXFkuv7pSzP0n.oVKU.bw4Gj/a',
     'S. Wijeratne', 'Electrical Engineer - Hali-Ela', 'ee.haliela@ceb.lk'),
(4, 3, NULL, 'dgm.uva',  '$2y$10$LBYagDKb8LPDhb4b1CiZtO.2XC.Nv/AaIPqfonBklAGr00.TBlA9O',
     'Provincial Management', 'DGM Uva', 'dgm.uva@ceb.lk');

-- ---------------- taxonomy ----------------
INSERT INTO asset_categories (category_id, category_code, category_name, display_order) VALUES
(1, 'SUBSTATION',     'Substation',     10),
(2, 'SWITCHGEAR',     'Switchgear',     20),
(3, 'CONDUCTOR',      'Conductor',      30),
(4, 'POLE',           'Pole',           40),
(5, 'POWER_LINE',     'Power Line',     50),
(6, 'BOUNDARY_METER', 'Boundary Meter', 60),
(7, 'BULK_SUPPLY',    'Bulk Supply',    70),
(8, 'MINI_HYDRO',     'Mini Hydro',     80),
(9, 'SOLAR_PLANT',    'Solar Plant',    90);

INSERT INTO asset_types (asset_type_id, category_id, type_code, type_name, unit_of_measure,
                         is_line_asset, rated_kva, allow_decimal, display_order) VALUES
-- Substations (point)
(1, 1, 'SS_100',   'Substation 100 kVA',  'nos', 0,  100, 0, 10),
(2, 1, 'SS_160',   'Substation 160 kVA',  'nos', 0,  160, 0, 20),
(3, 1, 'SS_250',   'Substation 250 kVA',  'nos', 0,  250, 0, 30),
(4, 1, 'SS_400',   'Substation 400 kVA',  'nos', 0,  400, 0, 40),
(5, 1, 'SS_630',   'Substation 630 kVA',  'nos', 0,  630, 0, 50),
(6, 1, 'SS_1000',  'Substation 1000 kVA', 'nos', 0, 1000, 0, 60),
(7, 1, 'GANTRY',   'Gantry',              'nos', 0, NULL, 0, 70),
-- Switchgear (point) - the reason the node layer exists
(8,  2, 'SW_REMOTE', 'Remote Switch',     'nos', 0, NULL, 0, 10),
(9,  2, 'SW_MANUAL', 'Manual Switch',     'nos', 0, NULL, 0, 20),
(10, 2, 'SW_AR',     'Auto Recloser (AR)','nos', 0, NULL, 0, 30),
(11, 2, 'SW_LBS',    'Load Break Switch (LBS)', 'nos', 0, NULL, 0, 40),
(12, 2, 'SW_DDLO',   'DDLO',              'nos', 0, NULL, 0, 50),
-- Conductor (span)
(13, 3, 'CN_FLY',   'Fly Conductor',      'km',  1, NULL, 1, 10),
(14, 3, 'CN_ABC',   'ABC Conductor',      'km',  1, NULL, 1, 20),
-- Poles (span)
(15, 4, 'PL_WOOD',  'Wooden Pole',        'nos', 1, NULL, 0, 10),
(16, 4, 'PL_RC',    'RC Pole',            'nos', 1, NULL, 0, 20),
-- Power line (span)
(17, 5, 'LN_POLE',  'Pole Line',          'km',  1, NULL, 1, 10),
(18, 5, 'LN_TOWER', 'Tower Line',         'km',  1, NULL, 1, 20),
-- Others (point)
(19, 6, 'BM_STD',   'Boundary Meter',     'nos', 0, NULL, 0, 10),
(20, 7, 'BSP_STD',  'Bulk Supply Point',  'nos', 0, NULL, 0, 10),
(21, 8, 'MH_PLANT', 'Mini Hydro Plant',   'nos', 0, NULL, 0, 10),
(22, 9, 'SOLAR_PV', 'Solar PV Plant',     'nos', 0, NULL, 0, 10);

-- NOTE on poles: is_line_asset = 1 even though the unit is 'nos'. A pole
-- count is recorded against a span, so it routes to segment_id like
-- conductor does. Read is_line_asset strictly as "attaches to a segment",
-- not as "is measured in km".

-- ---------------- feeders ----------------
-- BDL-F1 originates in Badulla Town and runs into Hali-Ela: proof that a
-- feeder legitimately crosses depots while a segment never does.
INSERT INTO feeders (feeder_id, feeder_code, feeder_name, origin_csc_id, source_name, voltage_level) VALUES
(1, 'BDL-F1', 'Badulla GSS Feeder 1 - Hali-Ela Road', 1, 'Badulla Grid Substation', '33kV'),
(2, 'BDL-F3', 'Badulla GSS Feeder 3 - Ella Road',     1, 'Badulla Grid Substation', '33kV');

-- ---------------- nodes (LAYER 1) ----------------
INSERT INTO network_nodes (node_id, node_code, csc_id, node_kind, name, latitude, longitude,
                           ownership_source, ownership_note, is_line_end, status, created_by) VALUES
(1,  'N-BDL-001', 1, 'GANTRY',          'Badulla Grid Substation Gantry', 6.9930000, 81.0490000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 2),
(2,  'N-BDL-002', 1, 'SUBSTATION',      'Muthiyangana Substation',        6.9902000, 81.0561000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 2),
(3,  'N-BDL-003', 1, 'SWITCH_POSITION', 'Bogoda Road AR Position',        6.9871000, 81.0603000, 'UPSTREAM_RULE',NULL, 0, 'ACTIVE', 2),
(4,  'N-BDL-004', 1, 'TEE_OFF',         'Kanupelella Tee-off',            6.9826000, 81.0665000, 'UPSTREAM_RULE',NULL, 0, 'ACTIVE', 2),
(5,  'N-BDL-005', 1, 'SUBSTATION',      'Kanupelella Substation',         6.9784000, 81.0721000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 2),
(6,  'N-BDL-006', 1, 'DEAD_END',        'Kanupelella Line End',           6.9750000, 81.0768000, 'UPSTREAM_RULE',NULL, 1, 'ACTIVE', 2),
-- THE BOUNDARY CASE. The switch here separates Badulla Town from
-- Hali-Ela. Ownership rule 3 gives it to the depot owning the upstream
-- segment (SEG-BDL-F1-06, Badulla Town), and Hali-Ela is recorded as a
-- sharer below so it still appears on their map and asset list.
(7,  'N-BDL-007', 1, 'BOUNDARY',        'Hali-Ela Boundary Switch',       6.9705000, 81.0402000, 'UPSTREAM_RULE',
     'Boundary between Badulla Town and Hali-Ela. Owned by Badulla Town per the upstream-segment rule.', 0, 'ACTIVE', 2),
(8,  'N-HLE-008', 2, 'SUBSTATION',      'Hali-Ela Town Substation',       6.9614000, 81.0244000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 3),
(9,  'N-HLE-009', 2, 'SWITCH_POSITION', 'Ambatenna LBS Position',         6.9550000, 81.0180000, 'UPSTREAM_RULE',NULL, 0, 'ACTIVE', 3),
(10, 'N-HLE-010', 2, 'TEE_OFF',         'Ambatenna Tee-off',              6.9502000, 81.0121000, 'UPSTREAM_RULE',NULL, 0, 'ACTIVE', 3),
(11, 'N-HLE-011', 2, 'SUBSTATION',      'Uduwara Substation',             6.9455000, 81.0068000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 3),
(12, 'N-HLE-012', 2, 'DEAD_END',        'Uduwara Line End',               6.9430000, 81.0015000, 'UPSTREAM_RULE',NULL, 1, 'ACTIVE', 3),
-- THE RING CASE. A normally-open tie between feeder 1 and feeder 3.
-- There is no permanent upstream side, so the upstream rule cannot
-- decide ownership and an explicit override is required.
(13, 'N-HLE-013', 2, 'SWITCH_POSITION', 'Ella Road NO Tie Point',         6.9390000, 81.0180000, 'MANUAL_OVERRIDE',
     'Normally-open tie between BDL-F1 and BDL-F3. No permanent upstream side, so ownership is assigned to Hali-Ela by field responsibility.', 0, 'ACTIVE', 3),
-- THE EMBEDDED GENERATION CASE. Power flows from this node into the
-- network, so "upstream" points the other way.
(14, 'N-HLE-014', 2, 'GENERATION',      'Uma Oya Mini Hydro Interconnection', 6.9525000, 81.0245000, 'GEOGRAPHIC',
     NULL, 0, 'ACTIVE', 3),
(15, 'N-HLE-015', 2, 'SUBSTATION',      'Ella Road Substation',           6.9345000, 81.0225000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 3),
-- Deliberate data-quality defects for the report to catch:
--   orphan node, missing coordinates, and (below) a substation node with
--   no substation asset recorded against it.
(16, 'N-BDL-016', 1, 'TEE_OFF',         'Proposed Badulla Bypass Tee',    NULL,      NULL,       'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 2),
(17, 'N-HLE-017', 2, 'SUBSTATION',      'Ambatenna Substation (uncounted)', 6.9540000, 81.0150000, 'GEOGRAPHIC', NULL, 0, 'ACTIVE', 3);

-- Ownership rule 4: shared visibility, never shared counting.
INSERT INTO node_shared_with (node_id, csc_id, share_reason) VALUES
(7,  2, 'Hali-Ela operates this switch during outages but Badulla Town owns and maintains it.'),
(13, 1, 'Badulla Town crews may operate the tie when back-feeding BDL-F1.');

-- ---------------- segments (LAYER 2) ----------------
-- Every segment sits inside exactly one depot. SEG-06 stops at the
-- boundary node and SEG-07 starts from it, which is how the line from
-- Badulla into Hali-Ela is represented without crossing the boundary.
INSERT INTO segments (segment_id, segment_code, feeder_id, csc_id, from_node_id, to_node_id,
                      length_km, voltage_level, is_normally_open, is_reversible, status, created_by) VALUES
(1,  'SEG-BDL-F1-01', 1, 1, 1,  2,  1.200, '33kV', 0, 0, 'ACTIVE', 2),
(2,  'SEG-BDL-F1-02', 1, 1, 2,  3,  0.950, '33kV', 0, 0, 'ACTIVE', 2),
(3,  'SEG-BDL-F1-03', 1, 1, 3,  4,  1.400, '33kV', 0, 0, 'ACTIVE', 2),
(4,  'SEG-BDL-F1-04', 1, 1, 4,  5,  1.100, '33kV', 0, 0, 'ACTIVE', 2),
(5,  'SEG-BDL-F1-05', 1, 1, 5,  6,  0.850, '33kV', 0, 0, 'ACTIVE', 2),
(6,  'SEG-BDL-F1-06', 1, 1, 4,  7,  2.300, '33kV', 0, 0, 'ACTIVE', 2),  -- upstream of the boundary
(7,  'SEG-HLE-F1-07', 1, 2, 7,  8,  1.750, '33kV', 0, 0, 'ACTIVE', 3),  -- downstream of the boundary
(8,  'SEG-HLE-F1-08', 1, 2, 8,  9,  1.050, '33kV', 0, 1, 'ACTIVE', 3),
(9,  'SEG-HLE-F1-09', 1, 2, 9,  10, 1.600, '33kV', 0, 0, 'ACTIVE', 3),
(10, 'SEG-HLE-F1-10', 1, 2, 10, 11, 0.900, '33kV', 0, 1, 'ACTIVE', 3),
(11, 'SEG-HLE-F1-11', 1, 2, 10, 12, 0.700, '33kV', 0, 0, 'ACTIVE', 3),
(12, 'SEG-HLE-F1-12', 1, 2, 14, 9,  0.450, '33kV', 0, 1, 'ACTIVE', 3),  -- mini hydro infeed
(13, 'SEG-HLE-F1-13', 1, 2, 11, 13, 1.200, '33kV', 1, 1, 'ACTIVE', 3),  -- to the NO tie
(14, 'SEG-HLE-F3-14', 2, 2, 13, 15, 0.800, '33kV', 1, 1, 'ACTIVE', 3);  -- other feeder, same tie node

-- ---------------- assets (LAYER 3) ----------------
-- POINT ASSETS - attached to node_id only.
INSERT INTO assets (asset_code, asset_type_id, node_id, oriented_to_segment_id, quantity,
                    unit_of_measure, install_date, condition_status, remarks, created_by) VALUES
('BDL-GAN-001',  7,  1,  NULL, 1, 'nos', '2012-06-15', 'GOOD', 'Grid substation outgoing gantry.', 2),
('BDL-BSP-001', 20,  1,  NULL, 1, 'nos', '2012-06-15', 'GOOD', 'Bulk supply take-off point.', 2),
('BDL-SS-002',   4,  2,  NULL, 1, 'nos', '2015-03-20', 'GOOD', '400 kVA town substation.', 2),
('BDL-AR-003',  10,  3,  NULL, 1, 'nos', '2019-11-02', 'GOOD', 'Auto recloser on Bogoda Road.', 2),
-- THE TEE-OFF CASE. Two LBS on one node, one per outgoing branch. Both
-- count once each against Badulla Town; oriented_to_segment_id records
-- which branch each faces and is display only.
('BDL-LBS-004A',11,  4,  4,    1, 'nos', '2018-05-10', 'GOOD', 'LBS facing the Kanupelella branch.', 2),
('BDL-LBS-004B',11,  4,  6,    1, 'nos', '2018-05-10', 'FAIR', 'LBS facing the Hali-Ela branch.', 2),
('BDL-SS-005',   2,  5,  NULL, 1, 'nos', '2016-08-01', 'GOOD', '160 kVA substation.', 2),
('BDL-DDLO-006',12,  6,  NULL, 1, 'nos', '2016-08-01', 'FAIR', 'Line-end DDLO.', 2),
-- The boundary switch: ONE row, on the node, owned by Badulla Town.
('BDL-MSW-007',  9,  7,  NULL, 1, 'nos', '2014-02-18', 'GOOD',
    'Boundary switch between Badulla Town and Hali-Ela. Counted once, under Badulla Town.', 2),
('BDL-BM-007',  19,  7,  NULL, 1, 'nos', '2014-02-18', 'GOOD', 'Boundary metering point.', 2),
('HLE-SS-008',   3,  8,  NULL, 1, 'nos', '2013-09-12', 'GOOD', '250 kVA Hali-Ela town substation.', 3),
('HLE-LBS-009', 11,  9,  NULL, 1, 'nos', '2020-01-25', 'NEW',  'LBS at Ambatenna.', 3),
('HLE-RSW-010',  8, 10,  10,   1, 'nos', '2021-07-30', 'NEW',  'Remote switch facing the Uduwara branch.', 3),
('HLE-SS-011',   1, 11,  NULL, 1, 'nos', '2017-04-05', 'FAIR', '100 kVA substation.', 3),
('HLE-DDLO-012',12, 12,  NULL, 1, 'nos', '2017-04-05', 'POOR', 'Line-end DDLO.', 3),
('HLE-MSW-013',  9, 13,  NULL, 1, 'nos', '2015-12-01', 'GOOD', 'Normally-open tie switch.', 3),
('HLE-MH-014',  21, 14,  NULL, 1, 'nos', '2019-02-14', 'GOOD', 'Uma Oya mini hydro, 1.2 MW.', 3),
('HLE-SS-015',   5, 15,  NULL, 1, 'nos', '2018-10-20', 'GOOD', '630 kVA substation.', 3),
('HLE-PV-015',  22, 15,  NULL, 1, 'nos', '2022-03-11', 'NEW',  'Rooftop solar PV plant connected here.', 3);

-- SPAN ASSETS - attached to segment_id only.
-- Conductor km, pole line km and pole counts, per segment.
INSERT INTO assets (asset_type_id, segment_id, quantity, unit_of_measure, install_date,
                    condition_status, remarks, created_by) VALUES
-- Badulla Town
(13,  1, 1.200, 'km',  '2012-06-15', 'GOOD', NULL, 2),
(17,  1, 1.200, 'km',  '2012-06-15', 'GOOD', NULL, 2),
(16,  1, 14,    'nos', '2012-06-15', 'GOOD', NULL, 2),
(13,  2, 0.950, 'km',  '2012-06-15', 'GOOD', NULL, 2),
(17,  2, 0.950, 'km',  '2012-06-15', 'GOOD', NULL, 2),
(16,  2, 11,    'nos', '2012-06-15', 'GOOD', NULL, 2),
(13,  3, 1.400, 'km',  '2013-01-20', 'GOOD', NULL, 2),
(17,  3, 1.400, 'km',  '2013-01-20', 'GOOD', NULL, 2),
(15,  3, 16,    'nos', '2013-01-20', 'FAIR', NULL, 2),
(14,  4, 1.100, 'km',  '2016-08-01', 'GOOD', NULL, 2),
(17,  4, 1.100, 'km',  '2016-08-01', 'GOOD', NULL, 2),
(16,  4, 12,    'nos', '2016-08-01', 'GOOD', NULL, 2),
(14,  5, 0.850, 'km',  '2016-08-01', 'GOOD', NULL, 2),
(17,  5, 0.850, 'km',  '2016-08-01', 'GOOD', NULL, 2),
(15,  5, 10,    'nos', '2016-08-01', 'POOR', NULL, 2),
(13,  6, 2.300, 'km',  '2014-02-18', 'GOOD', NULL, 2),
(17,  6, 2.300, 'km',  '2014-02-18', 'GOOD', NULL, 2),
(16,  6, 26,    'nos', '2014-02-18', 'GOOD', NULL, 2),
-- Hali-Ela
(13,  7, 1.750, 'km',  '2014-02-18', 'GOOD', NULL, 3),
(17,  7, 1.750, 'km',  '2014-02-18', 'GOOD', NULL, 3),
(16,  7, 20,    'nos', '2014-02-18', 'GOOD', NULL, 3),
(13,  8, 1.050, 'km',  '2013-09-12', 'FAIR', NULL, 3),
(17,  8, 1.050, 'km',  '2013-09-12', 'FAIR', NULL, 3),
(15,  8, 12,    'nos', '2013-09-12', 'FAIR', NULL, 3),
(13,  9, 1.600, 'km',  '2013-09-12', 'GOOD', NULL, 3),
(17,  9, 1.600, 'km',  '2013-09-12', 'GOOD', NULL, 3),
(16,  9, 18,    'nos', '2013-09-12', 'GOOD', NULL, 3),
(14, 10, 0.900, 'km',  '2017-04-05', 'GOOD', NULL, 3),
(17, 10, 0.900, 'km',  '2017-04-05', 'GOOD', NULL, 3),
(16, 10, 10,    'nos', '2017-04-05', 'GOOD', NULL, 3),
(14, 11, 0.700, 'km',  '2017-04-05', 'FAIR', NULL, 3),
(17, 11, 0.700, 'km',  '2017-04-05', 'FAIR', NULL, 3),
(15, 11, 8,     'nos', '2017-04-05', 'POOR', NULL, 3),
(13, 12, 0.450, 'km',  '2019-02-14', 'NEW',  'Mini hydro interconnection line.', 3),
(17, 12, 0.450, 'km',  '2019-02-14', 'NEW',  NULL, 3),
(16, 12, 6,     'nos', '2019-02-14', 'NEW',  NULL, 3),
(13, 13, 1.200, 'km',  '2015-12-01', 'GOOD', NULL, 3),
(17, 13, 1.200, 'km',  '2015-12-01', 'GOOD', NULL, 3),
(16, 13, 14,    'nos', '2015-12-01', 'GOOD', NULL, 3),
(13, 14, 0.800, 'km',  '2018-10-20', 'GOOD', NULL, 3),
(17, 14, 0.800, 'km',  '2018-10-20', 'GOOD', NULL, 3),
(16, 14, 9,     'nos', '2018-10-20', 'GOOD', NULL, 3);

-- The audit log is populated automatically by the triggers above. Clear
-- the seed noise so the trail starts from real user activity.
DELETE FROM audit_log;

-- =====================================================================
-- END OF SCHEMA
-- =====================================================================
