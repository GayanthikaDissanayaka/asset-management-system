-- =====================================================================
--  CEB UVA PROVINCE - NETWORK ASSET MANAGEMENT SYSTEM
--  UNIFIED DATABASE SCHEMA  (single-file build)
--
--  Target   : MySQL 8.0.16+ / MariaDB 10.4+   (InnoDB, utf8mb4)
--  Import   : phpMyAdmin > Import, or  mysql -u root -p < ceb_uva_ams_unified.sql
--
--  This file merges four earlier files into one consistent database:
--    * database_schema.sql            -> the 5-area / 17-CSC hierarchy,
--                                        conductor list, maintenance log
--    * expand_asset_types.sql         -> kVA-split substations, switchgear,
--                                        pole and power-line types, the
--                                        boundary-meter / bulk / MHP / solar
--                                        categories
--    * ceb_ams_schema.sql             -> the three-layer graph model, roles
--                                        and users, audit trail, triggers,
--                                        reporting views, sp_split_segment
--    * transformer_asset_management.sql -> 1,717 real transformer records
--                                        from the Transformer excel sheet
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
--      transformers -> GROUP BY transformers.csc_id
--      everything reads v_asset_rollup / v_transformer_rollup.
--      Do not write your own rollup.
--
--  WARNING: the next statement DROPS the database. Comment it out if you
--  are re-importing over live data.
-- =====================================================================

DROP DATABASE IF EXISTS ceb_uva_ams;
CREATE DATABASE ceb_uva_ams
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;
USE ceb_uva_ams;

SET FOREIGN_KEY_CHECKS = 1;


-- =====================================================================
-- SECTION 1 : ORGANISATIONAL HIERARCHY
--             Province -> Area (5) -> CSC/Depot (17)
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
    area_no         TINYINT UNSIGNED NOT NULL,   -- 01..05 from the reference sheet
    area_code       VARCHAR(10)  NOT NULL,
    area_name       VARCHAR(100) NOT NULL,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (area_id),
    UNIQUE KEY uq_area_code (area_code),
    UNIQUE KEY uq_area_name (province_id, area_name),
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
    page_no         VARCHAR(10)  NULL,   -- page in the single-line-diagram book (01..17)
    contact_officer VARCHAR(100) NULL,
    contact_phone   VARCHAR(25)  NULL,
    latitude        DECIMAL(10,7) NULL,
    longitude       DECIMAL(10,7) NULL,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (csc_id),
    UNIQUE KEY uq_csc_code (csc_code),
    UNIQUE KEY uq_csc_name (area_id, csc_name),
    KEY ix_csc_area (area_id),
    CONSTRAINT fk_csc_area FOREIGN KEY (area_id)
        REFERENCES areas (area_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT chk_csc_lat CHECK (latitude  IS NULL OR (latitude  BETWEEN  -90 AND  90)),
    CONSTRAINT chk_csc_lon CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- ---------------------------------------------------------------------
-- csc_aliases
-- The four source files spelled the same depot several different ways
-- ("Hali Ela" / "Haliela", "Kandeketiya" / "Kandaketiya", "Mahiyanagana"
-- / "Mahiyanganaya"). Every alias that appeared in any source file is
-- recorded here so future imports can resolve a name to one csc_id
-- instead of silently creating a duplicate depot.
-- ---------------------------------------------------------------------
CREATE TABLE csc_aliases (
    alias_id        INT UNSIGNED NOT NULL AUTO_INCREMENT,
    csc_id          INT UNSIGNED NOT NULL,
    alias_name      VARCHAR(100) NOT NULL,
    source_file     VARCHAR(80)  NULL,
    PRIMARY KEY (alias_id),
    UNIQUE KEY uq_alias_name (alias_name),
    KEY ix_alias_csc (csc_id),
    CONSTRAINT fk_alias_csc FOREIGN KEY (csc_id)
        REFERENCES csc_depots (csc_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SECTION 2 : SECURITY - ROLES AND USERS
-- =====================================================================

CREATE TABLE roles (
    role_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    role_code       VARCHAR(20)  NOT NULL,   -- ADMIN | AREA_ENGINEER | ENGINEER | TECHNICIAN | VIEWER
    role_name       VARCHAR(50)  NOT NULL,
    description     VARCHAR(255) NULL,
    PRIMARY KEY (role_id),
    UNIQUE KEY uq_role_code (role_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE users (
    user_id         INT UNSIGNED NOT NULL AUTO_INCREMENT,
    role_id         INT UNSIGNED NOT NULL,
    -- Scope of the account. csc_id NULL + area_id NULL = province-wide.
    -- PHP must check this on every write.
    area_id         INT UNSIGNED NULL,
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
    KEY ix_users_area (area_id),
    CONSTRAINT fk_users_role FOREIGN KEY (role_id)
        REFERENCES roles (role_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_users_area FOREIGN KEY (area_id)
        REFERENCES areas (area_id) ON DELETE RESTRICT ON UPDATE CASCADE,
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
    feeder_code     VARCHAR(30)  NOT NULL,   -- F1, F2, BDL-F1 ...
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
--
-- from_point / to_point carry the free-text landmark names that the old
-- line_segments table used, for depots that have not been surveyed into
-- proper nodes yet.
-- ---------------------------------------------------------------------
CREATE TABLE segments (
    segment_id      INT UNSIGNED NOT NULL AUTO_INCREMENT,
    segment_code    VARCHAR(30)  NOT NULL,
    feeder_id       INT UNSIGNED NOT NULL,
    csc_id          INT UNSIGNED NOT NULL,   -- owning depot -> counts here
    from_node_id    INT UNSIGNED NOT NULL,   -- nominal source side
    to_node_id      INT UNSIGNED NOT NULL,   -- nominal load side
    from_point      VARCHAR(150) NULL,       -- landmark label, display only
    to_point        VARCHAR(150) NULL,       -- landmark label, display only
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
    KEY ix_segment_voltage (voltage_level),
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
    description     VARCHAR(255) NULL,
    display_order   SMALLINT UNSIGNED NOT NULL DEFAULT 100,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    PRIMARY KEY (category_id),
    UNIQUE KEY uq_category_code (category_code),
    UNIQUE KEY uq_category_name (category_name)
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
    unit_of_measure ENUM('nos','km','m','kVA','kW') NOT NULL DEFAULT 'nos',
    is_line_asset   TINYINT(1)   NOT NULL DEFAULT 0,
    rated_kva       INT UNSIGNED NULL,   -- substations, for the capacity mix chart
    -- Whether whole numbers are required (poles, switches) vs decimals (km).
    allow_decimal   TINYINT(1)   NOT NULL DEFAULT 0,
    display_order   SMALLINT UNSIGNED NOT NULL DEFAULT 100,
    is_active       TINYINT(1)   NOT NULL DEFAULT 1,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (asset_type_id),
    UNIQUE KEY uq_type_code (type_code),
    UNIQUE KEY uq_type_name (category_id, type_name),
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
    unit_of_measure ENUM('nos','km','m','kVA','kW') NOT NULL DEFAULT 'nos',
    capacity_kva    DECIMAL(10,2) NULL,      -- transformers / substations
    material        VARCHAR(50)  NULL,       -- Concrete / Wooden, ACSR type, ...
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
    last_verified_by INT UNSIGNED NULL,
    last_verified_at DATETIME    NULL,
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
    CONSTRAINT fk_asset_verified_by FOREIGN KEY (last_verified_by)
        REFERENCES users (user_id) ON DELETE SET NULL ON UPDATE CASCADE,
    -- The core rule: a node XOR a segment, never both, never neither.
    CONSTRAINT chk_asset_one_layer CHECK ((node_id IS NULL) <> (segment_id IS NULL)),
    -- Orientation only makes sense for a point asset. That rule lives in
    -- trg_assets_bi/bu because this column keeps ON DELETE SET NULL.
    CONSTRAINT chk_asset_qty CHECK (quantity > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SECTION 6 : TRANSFORMER REGISTER
--
-- The transformer sheet is a nameplate inventory, not topology: it has
-- SIN numbers, serial numbers, capacity and a substation name, but no
-- surveyed node. So it gets its own table rather than being forced into
-- assets, where every row would need a node_id it does not have.
--
--   csc_id   is NOT NULL and is the counting key. It works on day one.
--   node_id  is NULL until the depot is surveyed. Fill it in later and
--            the transformer joins the graph without any data migration.
--   asset_id links to a matching row in assets if one is ever created.
--
-- Roll these up through v_transformer_rollup, never by hand.
-- =====================================================================

CREATE TABLE transformers (
    transformer_id  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    csc_id          INT UNSIGNED NOT NULL,   -- owning depot -> counts here
    node_id         INT UNSIGNED NULL,       -- filled in once surveyed
    asset_id        BIGINT UNSIGNED NULL,    -- matching assets row, if any
    asset_type_id   INT UNSIGNED NULL,       -- TX_DIST / TX_BULK / ...
    old_sin_no      VARCHAR(40)  NULL,       -- previous CEB SIN
    new_sin_no      VARCHAR(40)  NULL,       -- current CEB SIN
    substation_name VARCHAR(255) NOT NULL,
    transformer_type VARCHAR(60) NULL,       -- raw label from the source sheet
    capacity_kva    DECIMAL(10,2) NULL,
    transformer_no  VARCHAR(60)  NULL,       -- serial / plate number
    quantity        INT UNSIGNED NOT NULL DEFAULT 1,
    condition_status ENUM('NEW','GOOD','FAIR','POOR','FAULTY','UNKNOWN')
                     NOT NULL DEFAULT 'UNKNOWN',
    status          ENUM('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE',
    install_date    DATE         NULL,
    latitude        DECIMAL(10,7) NULL,
    longitude       DECIMAL(10,7) NULL,
    remarks         TEXT         NULL,
    source_file     VARCHAR(80)  NULL,       -- provenance of the row
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP
                                 ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (transformer_id),
    KEY ix_tx_csc (csc_id),
    KEY ix_tx_node (node_id),
    KEY ix_tx_asset (asset_id),
    KEY ix_tx_type (asset_type_id),
    KEY ix_tx_new_sin (new_sin_no),
    KEY ix_tx_old_sin (old_sin_no),
    KEY ix_tx_serial (transformer_no),
    KEY ix_tx_capacity (capacity_kva),
    KEY ix_tx_raw_type (transformer_type),
    KEY ix_tx_geo (latitude, longitude),
    CONSTRAINT fk_tx_csc FOREIGN KEY (csc_id)
        REFERENCES csc_depots (csc_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_tx_node FOREIGN KEY (node_id)
        REFERENCES network_nodes (node_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_tx_asset FOREIGN KEY (asset_id)
        REFERENCES assets (asset_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_tx_type FOREIGN KEY (asset_type_id)
        REFERENCES asset_types (asset_type_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT chk_tx_qty CHECK (quantity > 0),
    CONSTRAINT chk_tx_kva CHECK (capacity_kva IS NULL OR capacity_kva > 0),
    CONSTRAINT chk_tx_lat CHECK (latitude  IS NULL OR (latitude  BETWEEN  -90 AND  90)),
    CONSTRAINT chk_tx_lon CHECK (longitude IS NULL OR (longitude BETWEEN -180 AND 180))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SECTION 7 : MAINTENANCE / ACTIVITY LOG
--             Who touched what, and when - the handover problem.
-- =====================================================================

CREATE TABLE maintenance_logs (
    log_id          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    asset_id        BIGINT UNSIGNED NULL,
    segment_id      INT UNSIGNED NULL,
    node_id         INT UNSIGNED NULL,
    transformer_id  BIGINT UNSIGNED NULL,
    action_type     ENUM('installed','inspected','repaired','replaced',
                         'relocated','decommissioned') NOT NULL,
    performed_by    INT UNSIGNED NOT NULL,
    performed_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    remarks         TEXT         NULL,
    photo_path      VARCHAR(255) NULL,
    created_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (log_id),
    KEY ix_log_asset (asset_id),
    KEY ix_log_segment (segment_id),
    KEY ix_log_node (node_id),
    KEY ix_log_transformer (transformer_id),
    KEY ix_log_date (performed_at),
    CONSTRAINT fk_log_asset FOREIGN KEY (asset_id)
        REFERENCES assets (asset_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_log_segment FOREIGN KEY (segment_id)
        REFERENCES segments (segment_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_log_node FOREIGN KEY (node_id)
        REFERENCES network_nodes (node_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_log_transformer FOREIGN KEY (transformer_id)
        REFERENCES transformers (transformer_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_log_user FOREIGN KEY (performed_by)
        REFERENCES users (user_id) ON DELETE RESTRICT ON UPDATE CASCADE
    -- "At least one target" is enforced by trg_maint_bi / trg_maint_bu in
    -- section 10, NOT by a CHECK. MySQL 8 and MariaDB both refuse a CHECK
    -- constraint that references a column whose foreign key has a
    -- cascading action, and ON DELETE CASCADE on these four columns is
    -- worth more: deleting an asset should take its log entries with it.
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SECTION 8 : AUDIT TRAIL
--
-- PHP must run  SET @app_user_id = :user_id;  immediately after opening
-- the PDO connection. The triggers read that session variable; without
-- it changed_by is NULL.
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
-- SECTION 9 : REPORTING VIEWS
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
-- SECTION 10 : TRIGGERS
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
-- SECTION 11 : STORED PROCEDURE - splitting a segment at a boundary
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

-- ---------------------------------------------------------------------
-- maintenance_logs : every entry must name something it happened to.
-- This is the CHECK that could not live on the table, because those four
-- columns carry cascading foreign keys.
-- ---------------------------------------------------------------------
DELIMITER $$

CREATE TRIGGER trg_maint_bi BEFORE INSERT ON maintenance_logs
FOR EACH ROW
BEGIN
    IF NEW.asset_id IS NULL AND NEW.segment_id IS NULL
       AND NEW.node_id IS NULL AND NEW.transformer_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A maintenance entry must reference an asset, segment, node or transformer.';
    END IF;
END$$

CREATE TRIGGER trg_maint_bu BEFORE UPDATE ON maintenance_logs
FOR EACH ROW
BEGIN
    IF NEW.asset_id IS NULL AND NEW.segment_id IS NULL
       AND NEW.node_id IS NULL AND NEW.transformer_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A maintenance entry must reference an asset, segment, node or transformer.';
    END IF;
END$$

-- ---------------------------------------------------------------------
-- transformers : keep the register consistent with the taxonomy.
-- If a transformer is linked to an asset type, that type must belong to
-- a point category - a transformer is never a span asset.
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_tx_bi BEFORE INSERT ON transformers
FOR EACH ROW
BEGIN
    DECLARE v_is_line TINYINT(1);
    IF NEW.asset_type_id IS NOT NULL THEN
        SELECT is_line_asset INTO v_is_line
          FROM asset_types WHERE asset_type_id = NEW.asset_type_id;
        IF v_is_line = 1 THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'A transformer cannot be classified as a line (span) asset type.';
        END IF;
    END IF;
END$$

-- ---------- audit : transformers ----------
CREATE TRIGGER trg_tx_ai AFTER INSERT ON transformers
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, new_values)
    VALUES ('transformers', NEW.transformer_id, 'INSERT', @app_user_id,
            JSON_OBJECT('csc_id', NEW.csc_id, 'substation_name', NEW.substation_name,
                        'capacity_kva', NEW.capacity_kva, 'new_sin_no', NEW.new_sin_no,
                        'transformer_no', NEW.transformer_no, 'status', NEW.status));
END$$

CREATE TRIGGER trg_tx_au AFTER UPDATE ON transformers
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, old_values, new_values)
    VALUES ('transformers', NEW.transformer_id, 'UPDATE', @app_user_id,
            JSON_OBJECT('csc_id', OLD.csc_id, 'substation_name', OLD.substation_name,
                        'capacity_kva', OLD.capacity_kva, 'new_sin_no', OLD.new_sin_no,
                        'transformer_no', OLD.transformer_no, 'status', OLD.status),
            JSON_OBJECT('csc_id', NEW.csc_id, 'substation_name', NEW.substation_name,
                        'capacity_kva', NEW.capacity_kva, 'new_sin_no', NEW.new_sin_no,
                        'transformer_no', NEW.transformer_no, 'status', NEW.status));
END$$

CREATE TRIGGER trg_tx_ad AFTER DELETE ON transformers
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, changed_by, old_values)
    VALUES ('transformers', OLD.transformer_id, 'DELETE', @app_user_id,
            JSON_OBJECT('csc_id', OLD.csc_id, 'substation_name', OLD.substation_name,
                        'capacity_kva', OLD.capacity_kva, 'new_sin_no', OLD.new_sin_no));
END$$

DELIMITER ;


-- ---------------------------------------------------------------------
-- TRANSFORMER VIEWS
-- The transformer register counts on transformers.csc_id, exactly the
-- same contract the asset rollup uses. Keeping it as a separate view
-- rather than folding it into v_asset_rollup means a transformer that
-- ALSO has an assets row (once a depot is surveyed and asset_id is
-- filled in) can be excluded here without touching the asset side.
-- ---------------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_transformer_rollup AS
SELECT
    tx.transformer_id,
    tx.old_sin_no,
    tx.new_sin_no,
    tx.substation_name,
    tx.transformer_type,
    tx.capacity_kva,
    tx.transformer_no,
    tx.quantity,
    tx.condition_status,
    tx.status,
    tx.node_id,
    tx.asset_id,
    tx.asset_type_id,
    t.type_code,
    t.type_name,
    tx.csc_id,
    d.csc_code,
    d.csc_name,
    d.area_id,
    ar.area_code,
    ar.area_name,
    ar.province_id,
    p.province_name
FROM transformers tx
JOIN csc_depots  d  ON d.csc_id      = tx.csc_id
JOIN areas       ar ON ar.area_id    = d.area_id
JOIN provinces   p  ON p.province_id = ar.province_id
LEFT JOIN asset_types t ON t.asset_type_id = tx.asset_type_id
WHERE tx.status = 'ACTIVE';


-- Depot-level transformer counts and installed capacity.
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_transformer_totals_by_csc AS
SELECT province_id, province_name, area_id, area_code, area_name,
       csc_id, csc_code, csc_name,
       COUNT(*)                                    AS transformer_records,
       SUM(quantity)                               AS transformer_units,
       SUM(COALESCE(capacity_kva, 0) * quantity)   AS installed_kva
FROM v_transformer_rollup
GROUP BY province_id, province_name, area_id, area_code, area_name,
         csc_id, csc_code, csc_name;


CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_transformer_totals_by_area AS
SELECT province_id, province_name, area_id, area_code, area_name,
       COUNT(*)                                    AS transformer_records,
       SUM(quantity)                               AS transformer_units,
       SUM(COALESCE(capacity_kva, 0) * quantity)   AS installed_kva
FROM v_transformer_rollup
GROUP BY province_id, province_name, area_id, area_code, area_name;


-- Capacity mix for the dashboard doughnut chart, from real nameplate data.
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_transformer_capacity_mix AS
SELECT province_id, area_id, area_name, csc_id, csc_name,
       capacity_kva,
       transformer_type,
       COUNT(*)                                    AS unit_count,
       SUM(COALESCE(capacity_kva, 0) * quantity)   AS installed_kva
FROM v_transformer_rollup
WHERE capacity_kva IS NOT NULL
GROUP BY province_id, area_id, area_name, csc_id, csc_name,
         capacity_kva, transformer_type;


-- ---------------------------------------------------------------------
-- v_depot_dashboard : one row per depot, the headline numbers.
-- This is what the depot landing page and the province summary read.
-- ---------------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_depot_dashboard AS
SELECT
    d.csc_id,
    d.csc_code,
    d.csc_name,
    d.page_no,
    ar.area_id,
    ar.area_no,
    ar.area_name,
    p.province_id,
    p.province_name,
    COALESCE((SELECT COUNT(*) FROM network_nodes n
               WHERE n.csc_id = d.csc_id AND n.status = 'ACTIVE'), 0) AS node_count,
    COALESCE((SELECT COUNT(*) FROM segments s
               WHERE s.csc_id = d.csc_id AND s.status = 'ACTIVE'), 0) AS segment_count,
    COALESCE((SELECT SUM(s.length_km) FROM segments s
               WHERE s.csc_id = d.csc_id AND s.status = 'ACTIVE'), 0) AS network_km,
    COALESCE((SELECT SUM(r.quantity) FROM v_asset_rollup r
               WHERE r.csc_id = d.csc_id), 0)                         AS asset_quantity,
    COALESCE((SELECT COUNT(*) FROM v_transformer_rollup tr
               WHERE tr.csc_id = d.csc_id), 0)                        AS transformer_count,
    COALESCE((SELECT SUM(COALESCE(tr.capacity_kva,0) * tr.quantity)
                FROM v_transformer_rollup tr
               WHERE tr.csc_id = d.csc_id), 0)                        AS installed_kva
FROM csc_depots d
JOIN areas     ar ON ar.area_id    = d.area_id
JOIN provinces p  ON p.province_id = ar.province_id
WHERE d.is_active = 1;


-- ---------------------------------------------------------------------
-- v_asset_last_activity : who last touched each asset, for handovers.
-- ---------------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_asset_last_activity AS
SELECT
    a.asset_id,
    a.asset_code,
    t.type_name,
    COALESCE(dn.csc_name, ds.csc_name) AS csc_name,
    ml.action_type,
    u.full_name    AS performed_by,
    ml.performed_at,
    ml.remarks
FROM assets a
JOIN asset_types t         ON t.asset_type_id = a.asset_type_id
LEFT JOIN network_nodes n  ON n.node_id       = a.node_id
LEFT JOIN csc_depots   dn  ON dn.csc_id       = n.csc_id
LEFT JOIN segments     s   ON s.segment_id    = a.segment_id
LEFT JOIN csc_depots   ds  ON ds.csc_id       = s.csc_id
LEFT JOIN maintenance_logs ml
       ON ml.log_id = (SELECT MAX(m2.log_id) FROM maintenance_logs m2
                        WHERE m2.asset_id = a.asset_id)
LEFT JOIN users u          ON u.user_id       = ml.performed_by;


-- ---------------------------------------------------------------------
-- v_transformer_data_quality : gaps in the imported nameplate data.
-- Separate from v_data_quality_issues because these are import-cleanup
-- items for the depot clerks, not topology errors for the engineers.
-- ---------------------------------------------------------------------
CREATE OR REPLACE SQL SECURITY INVOKER VIEW v_transformer_data_quality AS
SELECT 'TX_NO_SIN' AS issue_code, 'WARNING' AS severity,
       tx.transformer_id AS entity_id, tx.csc_id,
       CONCAT('Transformer at "', tx.substation_name, '" has no SIN number.') AS description
FROM transformers tx
WHERE tx.status = 'ACTIVE' AND tx.old_sin_no IS NULL AND tx.new_sin_no IS NULL

UNION ALL
SELECT 'TX_NO_SERIAL', 'INFO', tx.transformer_id, tx.csc_id,
       CONCAT('Transformer at "', tx.substation_name, '" has no serial / plate number.')
FROM transformers tx
WHERE tx.status = 'ACTIVE' AND tx.transformer_no IS NULL

UNION ALL
SELECT 'TX_NO_CAPACITY', 'ERROR', tx.transformer_id, tx.csc_id,
       CONCAT('Transformer at "', tx.substation_name, '" has no kVA rating, ',
              'so it is missing from every capacity total.')
FROM transformers tx
WHERE tx.status = 'ACTIVE' AND tx.capacity_kva IS NULL

UNION ALL
SELECT 'TX_NOT_ON_NETWORK', 'INFO', tx.transformer_id, tx.csc_id,
       CONCAT('Transformer at "', tx.substation_name, '" is not linked to a network node yet.')
FROM transformers tx
WHERE tx.status = 'ACTIVE' AND tx.node_id IS NULL

UNION ALL
SELECT 'TX_DUPLICATE_SERIAL', 'WARNING', tx.transformer_id, tx.csc_id,
       CONCAT('Serial number ', tx.transformer_no, ' appears on more than one transformer.')
FROM transformers tx
JOIN (SELECT transformer_no FROM transformers
       WHERE transformer_no IS NOT NULL AND status = 'ACTIVE'
       GROUP BY transformer_no HAVING COUNT(*) > 1) dup
  ON dup.transformer_no = tx.transformer_no
WHERE tx.status = 'ACTIVE';


-- =====================================================================
-- SECTION 12 : SEED DATA - MASTER HIERARCHY
--
-- The 5 areas and 17 CSCs come from the reference sheet (page_no is the
-- page in the single-line-diagram book). Where the four source files
-- spelled a depot differently, the reference-sheet spelling wins and the
-- other spellings are recorded in csc_aliases.
--
-- Coordinates are approximate town centres, good enough to place a pin
-- on the map. Replace them with surveyed values when available.
-- =====================================================================

INSERT INTO provinces (province_id, province_code, province_name) VALUES
(1, 'UVA', 'Uva');

INSERT INTO areas (area_id, province_id, area_no, area_code, area_name) VALUES
(1, 1, 1, 'MAH', 'Mahiyanganaya'),
(2, 1, 2, 'BDL', 'Badulla'),
(3, 1, 3, 'DIY', 'Diyathalawa'),
(4, 1, 4, 'MON', 'Monaragala'),
(5, 1, 5, 'WEL', 'Wellawaya');

INSERT INTO csc_depots (csc_id, area_id, csc_code, csc_name, depot_type, page_no, latitude, longitude) VALUES
-- Area 1 : Mahiyanganaya
(1,  1, 'MAH-CSC01', 'Mahiyanganaya',  'CSC',   '01', 7.3300000, 81.0000000),
(2,  1, 'MAH-CSC02', 'Rideemaliyadda', 'DEPOT', '02', 7.2333000, 81.0833000),
(3,  1, 'MAH-CSC03', 'Kandaketiya',    'DEPOT', '03', 7.1667000, 81.0500000),
-- Area 2 : Badulla
(4,  2, 'BDL-CSC01', 'Badulla',        'CSC',   '04', 6.9895000, 81.0557000),
(5,  2, 'BDL-CSC02', 'Haliela',        'DEPOT', '05', 6.9614000, 81.0244000),
(6,  2, 'BDL-CSC03', 'Passara',        'DEPOT', '06', 6.9147000, 81.1519000),
-- Area 3 : Diyathalawa
(7,  3, 'DIY-CSC01', 'Diyathalawa',    'CSC',   '07', 6.8158000, 80.9622000),
(8,  3, 'DIY-CSC02', 'Bandarawela',    'DEPOT', '08', 6.8330000, 80.9870000),
(9,  3, 'DIY-CSC03', 'Welimada',       'DEPOT', '09', 6.9053000, 80.9142000),
(10, 3, 'DIY-CSC04', 'Uva-paranagama', 'DEPOT', '10', 6.8833000, 80.9333000),
(11, 3, 'DIY-CSC05', 'Ella',           'DEPOT', '11', 6.8667000, 81.0466000),
-- Area 4 : Monaragala
(12, 4, 'MON-CSC01', 'Monaragala',     'CSC',   '12', 6.8720000, 81.3487000),
(13, 4, 'MON-CSC02', 'Dambagalla',     'DEPOT', '13', 6.7833000, 81.2833000),
(14, 4, 'MON-CSC03', 'Bibila',         'DEPOT', '14', 7.1600000, 81.2200000),
-- Area 5 : Wellawaya
(15, 5, 'WEL-CSC01', 'Wellawaya',      'CSC',   '15', 6.7378000, 81.1022000),
(16, 5, 'WEL-CSC02', 'Buttala',        'DEPOT', '16', 6.7597000, 81.2400000),
(17, 5, 'WEL-CSC03', 'Thanamalwila',   'DEPOT', '17', 6.4167000, 81.1500000);

-- Every alternative spelling found in the four source files. Import
-- scripts should resolve a depot name through this table, not by an
-- exact match on csc_name.
INSERT INTO csc_aliases (csc_id, alias_name, source_file) VALUES
(1,  'Mahiyanagana',      'transformer_asset_management.sql'),
(1,  'Mahiyangana',       'transformer_asset_management.sql'),
(3,  'Kandeketiya',       'transformer_asset_management.sql'),
(5,  'Hali Ela',          'transformer_asset_management.sql'),
(5,  'Hali-Ela',          'ceb_ams_schema.sql'),
(7,  'Diyatalawa',        'transformer_asset_management.sql'),
(10, 'Uvaparanagama',     'transformer_asset_management.sql'),
(14, 'Bibile',            'ceb_ams_schema.sql'),
(17, 'Tanamalvilla',      'transformer_asset_management.sql'),
(4,  'Badulla Town',      'ceb_ams_schema.sql');

-- NOTE. ceb_ams_schema.sql also contained five depot names that do not
-- appear on the 17-page reference sheet: Meegahakiula, Haputale,
-- Boralanda, Keppetipola and Girandurukotte. They are left out rather
-- than guessed at. If they are real depots, uncomment and assign the
-- right area, then renumber nothing else - csc_id is an AUTO_INCREMENT
-- surrogate and the rest of the schema does not care.
--
-- INSERT INTO csc_depots (area_id, csc_code, csc_name, depot_type, latitude, longitude) VALUES
-- (2, 'BDL-CSC04', 'Meegahakiula',    'DEPOT', 7.0725000, 81.1247000),
-- (3, 'DIY-CSC06', 'Haputale',        'DEPOT', 6.7683000, 80.9514000),
-- (3, 'DIY-CSC07', 'Boralanda',       'DEPOT', 6.8489000, 80.8903000),
-- (3, 'DIY-CSC08', 'Keppetipola',     'DEPOT', 6.8783000, 80.8506000),
-- (1, 'MAH-CSC04', 'Girandurukotte',  'DEPOT', 7.4667000, 81.0167000);


-- =====================================================================
-- SECTION 13 : SEED DATA - ROLES AND USERS
-- =====================================================================

INSERT INTO roles (role_id, role_code, role_name, description) VALUES
(1, 'ADMIN',         'Administrator',   'Full access to all areas, master data and users.'),
(2, 'AREA_ENGINEER', 'Area Engineer',   'Create and edit network and assets for every depot in the assigned area.'),
(3, 'ENGINEER',      'Depot Engineer',  'Create and edit network and assets for the assigned CSC only.'),
(4, 'TECHNICIAN',    'Field Technician','Record inspections and maintenance for the assigned CSC.'),
(5, 'VIEWER',        'Viewer',          'Read-only access to dashboards, maps and reports.');

-- Demo passwords: Admin@123 / Engineer@123 / Viewer@123
-- CHANGE THESE before any deployment outside XAMPP.
INSERT INTO users (user_id, role_id, area_id, csc_id, username, password_hash,
                   full_name, designation, email) VALUES
(1, 1, NULL, NULL, 'admin',        '$2y$10$SN1gMsGheEI4VM2gRf6Bc./0hb0Y/oLme8E4Q3SBToIckjX6SIf2y',
     'System Administrator', 'IT Administrator', 'admin@ceb.lk'),
(2, 3, 2,    4,    'eng.badulla',  '$2y$10$MhIMqtH.kSp5/h.rLNICrujpDTRYXFkuv7pSzP0n.oVKU.bw4Gj/a',
     'K. Jayasekara', 'Electrical Engineer - Badulla', 'ee.badulla@ceb.lk'),
(3, 3, 2,    5,    'eng.haliela',  '$2y$10$MhIMqtH.kSp5/h.rLNICrujpDTRYXFkuv7pSzP0n.oVKU.bw4Gj/a',
     'S. Wijeratne', 'Electrical Engineer - Haliela', 'ee.haliela@ceb.lk'),
(4, 5, NULL, NULL, 'dgm.uva',      '$2y$10$LBYagDKb8LPDhb4b1CiZtO.2XC.Nv/AaIPqfonBklAGr00.TBlA9O',
     'Provincial Management', 'DGM Uva', 'dgm.uva@ceb.lk');


-- =====================================================================
-- SECTION 14 : SEED DATA - ASSET TAXONOMY
--
-- The union of the taxonomy in database_schema.sql, the additions in
-- expand_asset_types.sql, and the coded types in ceb_ams_schema.sql.
--
-- is_line_asset means "attaches to a segment", NOT "is measured in km".
-- Poles are a span asset counted in 'nos'; read the flag strictly.
-- =====================================================================

INSERT INTO asset_categories (category_id, category_code, category_name, display_order, description) VALUES
(1,  'SUBSTATION',     'Substation',     10, 'Distribution and grid substations, gantries.'),
(2,  'TRANSFORMER',    'Transformer',    20, 'Transformer units, tracked separately in the transformers table.'),
(3,  'SWITCHGEAR',     'Switchgear',     30, 'Switches, reclosers, isolators, DDLOs.'),
(4,  'CABLE',          'Cable',          40, 'Underground cable runs.'),
(5,  'CONDUCTOR',      'Conductor',      50, 'Overhead conductor by type.'),
(6,  'POLE',           'Pole',           60, 'Supporting structures.'),
(7,  'POWER_LINE',     'Power Line',     70, 'Line length by structure type and voltage.'),
(8,  'BOUNDARY_METER', 'Boundary Meter', 80, 'Metering at depot and bulk boundaries.'),
(9,  'BULK_SUPPLY',    'Bulk Supply',    90, 'Bulk supply take-off points.'),
(10, 'MINI_HYDRO',     'Mini Hydro',    100, 'Embedded mini hydro generation.'),
(11, 'SOLAR_PLANT',    'Solar Plant',   110, 'Embedded solar PV generation.');

INSERT INTO asset_types (asset_type_id, category_id, type_code, type_name, unit_of_measure,
                         is_line_asset, rated_kva, allow_decimal, display_order) VALUES
-- Substations (POINT)
(1,  1, 'SS_100',    'Substation 100 kVA',        'nos', 0,  100, 0, 10),
(2,  1, 'SS_160',    'Substation 160 kVA',        'nos', 0,  160, 0, 20),
(3,  1, 'SS_250',    'Substation 250 kVA',        'nos', 0,  250, 0, 30),
(4,  1, 'SS_400',    'Substation 400 kVA',        'nos', 0,  400, 0, 40),
(5,  1, 'SS_630',    'Substation 630 kVA',        'nos', 0,  630, 0, 50),
(6,  1, 'SS_1000',   'Substation 1000 kVA',       'nos', 0, 1000, 0, 60),
(7,  1, 'GANTRY',    'Gantry',                    'nos', 0, NULL, 0, 70),
(8,  1, 'SS_DIST',   'Distribution Substation',   'nos', 0, NULL, 0, 80),
(9,  1, 'SS_GRID',   'Grid Substation',           'nos', 0, NULL, 0, 90),
-- Transformers (POINT) - the classes used by the transformer sheet
(10, 2, 'TX_DIST',   'Distribution Transformer',           'nos', 0, NULL, 0, 10),
(11, 2, 'TX_BULK',   'Bulk Transformer',                   'nos', 0, NULL, 0, 20),
(12, 2, 'TX_BULK_DIST','Bulk & Distribution Transformer',  'nos', 0, NULL, 0, 30),
(13, 2, 'TX_MHP',    'Mini Hydro / Generation Transformer','nos', 0, NULL, 0, 40),
-- Switchgear (POINT) - the reason the node layer exists
(14, 3, 'SW_REMOTE', 'Remote Switch',             'nos', 0, NULL, 0, 10),
(15, 3, 'SW_MANUAL', 'Manual Switch',             'nos', 0, NULL, 0, 20),
(16, 3, 'SW_AR',     'Auto Recloser (AR)',        'nos', 0, NULL, 0, 30),
(17, 3, 'SW_LBS',    'Load Break Switch (LBS)',   'nos', 0, NULL, 0, 40),
(18, 3, 'SW_DDLO',   'DDLO',                      'nos', 0, NULL, 0, 50),
(19, 3, 'SW_RMU',    'Ring Main Unit (RMU)',      'nos', 0, NULL, 0, 60),
(20, 3, 'SW_ISO',    'Isolator',                  'nos', 0, NULL, 0, 70),
-- Cable (SPAN)
(21, 4, 'CB_UG',     'Underground Cable',         'km',  1, NULL, 1, 10),
-- Conductor (SPAN)
(22, 5, 'CN_COPPER', 'Copper Conductor',          'km',  1, NULL, 1, 10),
(23, 5, 'CN_WEASEL', 'Weasel Conductor',          'km',  1, NULL, 1, 20),
(24, 5, 'CN_RACCOON','Raccoon Conductor',         'km',  1, NULL, 1, 30),
(25, 5, 'CN_LYNX',   'Lynx Conductor',            'km',  1, NULL, 1, 40),
(26, 5, 'CN_FLY',    'Fly Conductor',             'km',  1, NULL, 1, 50),
(27, 5, 'CN_ZEBRA',  'Zebra Conductor',           'km',  1, NULL, 1, 60),
(28, 5, 'CN_ABC',    'ABC (Aerial Bundled Cable)','km',  1, NULL, 1, 70),
-- Poles (SPAN, counted in nos)
(29, 6, 'PL_WOOD',   'Wooden Pole',               'nos', 1, NULL, 0, 10),
(30, 6, 'PL_RC',     'RC (Concrete) Pole',        'nos', 1, NULL, 0, 20),
-- Power line (SPAN)
(31, 7, 'LN_POLE',   'Pole Line',                 'km',  1, NULL, 1, 10),
(32, 7, 'LN_TOWER',  'Tower Line',                'km',  1, NULL, 1, 20),
(33, 7, 'LN_LV',     'LV Line',                   'km',  1, NULL, 1, 30),
(34, 7, 'LN_MV',     'MV Line',                   'km',  1, NULL, 1, 40),
(35, 7, 'LN_HV',     'HV Line',                   'km',  1, NULL, 1, 50),
-- Others (POINT)
(36, 8,  'BM_STD',   'Boundary Meter',            'nos', 0, NULL, 0, 10),
(37, 9,  'BSP_STD',  'Bulk Supply Point',         'nos', 0, NULL, 0, 10),
(38, 10, 'MH_PLANT', 'Mini Hydro Plant',          'nos', 0, NULL, 0, 10),
(39, 11, 'SOLAR_PV', 'Solar PV Plant',            'nos', 0, NULL, 0, 10);


-- =====================================================================
-- SECTION 15 : SEED DATA - WORKED NETWORK EXAMPLE
--
-- A full surveyed network for two depots, Badulla (csc_id 4) and Haliela
-- (csc_id 5), carried over from ceb_ams_schema.sql. It exists to
-- demonstrate the four cases the model was built for:
--     the boundary switch, the tee-off, the normally-open ring tie,
--     and embedded generation.
-- Three deliberate data-quality defects are included so the data-quality
-- report has something to show on day one.
--
-- The other 15 depots have transformer data (section 16) but no surveyed
-- topology yet. That is the expected state, not an error.
-- =====================================================================

-- ---------------- feeders ----------------
-- BDL-F1 originates in Badulla and runs into Haliela: proof that a
-- feeder legitimately crosses depots while a segment never does.
INSERT INTO feeders (feeder_id, feeder_code, feeder_name, origin_csc_id, source_name, voltage_level) VALUES
(1, 'BDL-F1', 'Badulla GSS Feeder 1 - Hali-Ela Road', 4, 'Badulla Grid Substation', '33kV'),
(2, 'BDL-F3', 'Badulla GSS Feeder 3 - Ella Road',     4, 'Badulla Grid Substation', '33kV');

-- ---------------- nodes (LAYER 1) ----------------
INSERT INTO network_nodes (node_id, node_code, csc_id, node_kind, name, latitude, longitude,
                           ownership_source, ownership_note, is_line_end, status, created_by) VALUES
(1,  'N-BDL-001', 4, 'GANTRY',          'Badulla Grid Substation Gantry', 6.9930000, 81.0490000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 2),
(2,  'N-BDL-002', 4, 'SUBSTATION',      'Muthiyangana Substation',        6.9902000, 81.0561000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 2),
(3,  'N-BDL-003', 4, 'SWITCH_POSITION', 'Bogoda Road AR Position',        6.9871000, 81.0603000, 'UPSTREAM_RULE',NULL, 0, 'ACTIVE', 2),
(4,  'N-BDL-004', 4, 'TEE_OFF',         'Kanupelella Tee-off',            6.9826000, 81.0665000, 'UPSTREAM_RULE',NULL, 0, 'ACTIVE', 2),
(5,  'N-BDL-005', 4, 'SUBSTATION',      'Kanupelella Substation',         6.9784000, 81.0721000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 2),
(6,  'N-BDL-006', 4, 'DEAD_END',        'Kanupelella Line End',           6.9750000, 81.0768000, 'UPSTREAM_RULE',NULL, 1, 'ACTIVE', 2),
-- THE BOUNDARY CASE. The switch here separates Badulla from Haliela.
-- Ownership rule 3 gives it to the depot owning the upstream segment
-- (SEG-BDL-F1-06, Badulla), and Haliela is recorded as a sharer below so
-- it still appears on their map and asset list.
(7,  'N-BDL-007', 4, 'BOUNDARY',        'Haliela Boundary Switch',        6.9705000, 81.0402000, 'UPSTREAM_RULE',
     'Boundary between Badulla and Haliela. Owned by Badulla per the upstream-segment rule.', 0, 'ACTIVE', 2),
(8,  'N-HLE-008', 5, 'SUBSTATION',      'Haliela Town Substation',        6.9614000, 81.0244000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 3),
(9,  'N-HLE-009', 5, 'SWITCH_POSITION', 'Ambatenna LBS Position',         6.9550000, 81.0180000, 'UPSTREAM_RULE',NULL, 0, 'ACTIVE', 3),
(10, 'N-HLE-010', 5, 'TEE_OFF',         'Ambatenna Tee-off',              6.9502000, 81.0121000, 'UPSTREAM_RULE',NULL, 0, 'ACTIVE', 3),
(11, 'N-HLE-011', 5, 'SUBSTATION',      'Uduwara Substation',             6.9455000, 81.0068000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 3),
(12, 'N-HLE-012', 5, 'DEAD_END',        'Uduwara Line End',               6.9430000, 81.0015000, 'UPSTREAM_RULE',NULL, 1, 'ACTIVE', 3),
-- THE RING CASE. A normally-open tie between feeder 1 and feeder 3.
-- There is no permanent upstream side, so the upstream rule cannot
-- decide ownership and an explicit override is required.
(13, 'N-HLE-013', 5, 'SWITCH_POSITION', 'Ella Road NO Tie Point',         6.9390000, 81.0180000, 'MANUAL_OVERRIDE',
     'Normally-open tie between BDL-F1 and BDL-F3. No permanent upstream side, so ownership is assigned to Haliela by field responsibility.', 0, 'ACTIVE', 3),
-- THE EMBEDDED GENERATION CASE. Power flows from this node into the
-- network, so "upstream" points the other way.
(14, 'N-HLE-014', 5, 'GENERATION',      'Uma Oya Mini Hydro Interconnection', 6.9525000, 81.0245000, 'GEOGRAPHIC',
     NULL, 0, 'ACTIVE', 3),
(15, 'N-HLE-015', 5, 'SUBSTATION',      'Ella Road Substation',           6.9345000, 81.0225000, 'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 3),
-- Deliberate data-quality defects for the report to catch:
--   orphan node, missing coordinates, and a substation node with no
--   substation asset recorded against it.
(16, 'N-BDL-016', 4, 'TEE_OFF',         'Proposed Badulla Bypass Tee',    NULL,      NULL,       'GEOGRAPHIC',   NULL, 0, 'ACTIVE', 2),
(17, 'N-HLE-017', 5, 'SUBSTATION',      'Ambatenna Substation (uncounted)', 6.9540000, 81.0150000, 'GEOGRAPHIC', NULL, 0, 'ACTIVE', 3);

-- Ownership rule 4: shared visibility, never shared counting.
INSERT INTO node_shared_with (node_id, csc_id, share_reason) VALUES
(7,  5, 'Haliela operates this switch during outages but Badulla owns and maintains it.'),
(13, 4, 'Badulla crews may operate the tie when back-feeding BDL-F1.');

-- ---------------- segments (LAYER 2) ----------------
-- Every segment sits inside exactly one depot. SEG-06 stops at the
-- boundary node and SEG-07 starts from it, which is how the line from
-- Badulla into Haliela is represented without crossing the boundary.
INSERT INTO segments (segment_id, segment_code, feeder_id, csc_id, from_node_id, to_node_id,
                      length_km, voltage_level, is_normally_open, is_reversible, status, created_by) VALUES
(1,  'SEG-BDL-F1-01', 1, 4, 1,  2,  1.200, '33kV', 0, 0, 'ACTIVE', 2),
(2,  'SEG-BDL-F1-02', 1, 4, 2,  3,  0.950, '33kV', 0, 0, 'ACTIVE', 2),
(3,  'SEG-BDL-F1-03', 1, 4, 3,  4,  1.400, '33kV', 0, 0, 'ACTIVE', 2),
(4,  'SEG-BDL-F1-04', 1, 4, 4,  5,  1.100, '33kV', 0, 0, 'ACTIVE', 2),
(5,  'SEG-BDL-F1-05', 1, 4, 5,  6,  0.850, '33kV', 0, 0, 'ACTIVE', 2),
(6,  'SEG-BDL-F1-06', 1, 4, 4,  7,  2.300, '33kV', 0, 0, 'ACTIVE', 2),  -- upstream of the boundary
(7,  'SEG-HLE-F1-07', 1, 5, 7,  8,  1.750, '33kV', 0, 0, 'ACTIVE', 3),  -- downstream of the boundary
(8,  'SEG-HLE-F1-08', 1, 5, 8,  9,  1.050, '33kV', 0, 1, 'ACTIVE', 3),
(9,  'SEG-HLE-F1-09', 1, 5, 9,  10, 1.600, '33kV', 0, 0, 'ACTIVE', 3),
(10, 'SEG-HLE-F1-10', 1, 5, 10, 11, 0.900, '33kV', 0, 1, 'ACTIVE', 3),
(11, 'SEG-HLE-F1-11', 1, 5, 10, 12, 0.700, '33kV', 0, 0, 'ACTIVE', 3),
(12, 'SEG-HLE-F1-12', 1, 5, 14, 9,  0.450, '33kV', 0, 1, 'ACTIVE', 3),  -- mini hydro infeed
(13, 'SEG-HLE-F1-13', 1, 5, 11, 13, 1.200, '33kV', 1, 1, 'ACTIVE', 3),  -- to the NO tie
(14, 'SEG-HLE-F3-14', 2, 5, 13, 15, 0.800, '33kV', 1, 1, 'ACTIVE', 3);  -- other feeder, same tie node

-- ---------------- assets (LAYER 3) ----------------
-- POINT ASSETS - attached to node_id only.
INSERT INTO assets (asset_code, asset_type_id, node_id, oriented_to_segment_id, quantity,
                    unit_of_measure, capacity_kva, install_date, condition_status, remarks, created_by) VALUES
('BDL-GAN-001',  7,  1,  NULL, 1, 'nos', NULL, '2012-06-15', 'GOOD', 'Grid substation outgoing gantry.', 2),
('BDL-BSP-001', 37,  1,  NULL, 1, 'nos', NULL, '2012-06-15', 'GOOD', 'Bulk supply take-off point.', 2),
('BDL-SS-002',   4,  2,  NULL, 1, 'nos',  400, '2015-03-20', 'GOOD', '400 kVA town substation.', 2),
('BDL-AR-003',  16,  3,  NULL, 1, 'nos', NULL, '2019-11-02', 'GOOD', 'Auto recloser on Bogoda Road.', 2),
-- THE TEE-OFF CASE. Two LBS on one node, one per outgoing branch. Both
-- count once each against Badulla; oriented_to_segment_id records which
-- branch each faces and is display only.
('BDL-LBS-004A',17,  4,  4,    1, 'nos', NULL, '2018-05-10', 'GOOD', 'LBS facing the Kanupelella branch.', 2),
('BDL-LBS-004B',17,  4,  6,    1, 'nos', NULL, '2018-05-10', 'FAIR', 'LBS facing the Haliela branch.', 2),
('BDL-SS-005',   2,  5,  NULL, 1, 'nos',  160, '2016-08-01', 'GOOD', '160 kVA substation.', 2),
('BDL-DDLO-006',18,  6,  NULL, 1, 'nos', NULL, '2016-08-01', 'FAIR', 'Line-end DDLO.', 2),
-- The boundary switch: ONE row, on the node, owned by Badulla.
('BDL-MSW-007', 15,  7,  NULL, 1, 'nos', NULL, '2014-02-18', 'GOOD',
    'Boundary switch between Badulla and Haliela. Counted once, under Badulla.', 2),
('BDL-BM-007',  36,  7,  NULL, 1, 'nos', NULL, '2014-02-18', 'GOOD', 'Boundary metering point.', 2),
('HLE-SS-008',   3,  8,  NULL, 1, 'nos',  250, '2013-09-12', 'GOOD', '250 kVA Haliela town substation.', 3),
('HLE-LBS-009', 17,  9,  NULL, 1, 'nos', NULL, '2020-01-25', 'NEW',  'LBS at Ambatenna.', 3),
('HLE-RSW-010', 14, 10,  10,   1, 'nos', NULL, '2021-07-30', 'NEW',  'Remote switch facing the Uduwara branch.', 3),
('HLE-SS-011',   1, 11,  NULL, 1, 'nos',  100, '2017-04-05', 'FAIR', '100 kVA substation.', 3),
('HLE-DDLO-012',18, 12,  NULL, 1, 'nos', NULL, '2017-04-05', 'POOR', 'Line-end DDLO.', 3),
('HLE-MSW-013', 15, 13,  NULL, 1, 'nos', NULL, '2015-12-01', 'GOOD', 'Normally-open tie switch.', 3),
('HLE-MH-014',  38, 14,  NULL, 1, 'nos', NULL, '2019-02-14', 'GOOD', 'Uma Oya mini hydro, 1.2 MW.', 3),
('HLE-SS-015',   5, 15,  NULL, 1, 'nos',  630, '2018-10-20', 'GOOD', '630 kVA substation.', 3),
('HLE-PV-015',  39, 15,  NULL, 1, 'nos', NULL, '2022-03-11', 'NEW',  'Rooftop solar PV plant connected here.', 3);

-- SPAN ASSETS - attached to segment_id only.
-- Conductor km, pole line km and pole counts, per segment.
INSERT INTO assets (asset_type_id, segment_id, quantity, unit_of_measure, install_date,
                    condition_status, remarks, created_by) VALUES
-- Badulla
(26,  1, 1.200, 'km',  '2012-06-15', 'GOOD', NULL, 2),
(31,  1, 1.200, 'km',  '2012-06-15', 'GOOD', NULL, 2),
(30,  1, 14,    'nos', '2012-06-15', 'GOOD', NULL, 2),
(26,  2, 0.950, 'km',  '2012-06-15', 'GOOD', NULL, 2),
(31,  2, 0.950, 'km',  '2012-06-15', 'GOOD', NULL, 2),
(30,  2, 11,    'nos', '2012-06-15', 'GOOD', NULL, 2),
(26,  3, 1.400, 'km',  '2013-01-20', 'GOOD', NULL, 2),
(31,  3, 1.400, 'km',  '2013-01-20', 'GOOD', NULL, 2),
(29,  3, 16,    'nos', '2013-01-20', 'FAIR', NULL, 2),
(28,  4, 1.100, 'km',  '2016-08-01', 'GOOD', NULL, 2),
(31,  4, 1.100, 'km',  '2016-08-01', 'GOOD', NULL, 2),
(30,  4, 12,    'nos', '2016-08-01', 'GOOD', NULL, 2),
(28,  5, 0.850, 'km',  '2016-08-01', 'GOOD', NULL, 2),
(31,  5, 0.850, 'km',  '2016-08-01', 'GOOD', NULL, 2),
(29,  5, 10,    'nos', '2016-08-01', 'POOR', NULL, 2),
(26,  6, 2.300, 'km',  '2014-02-18', 'GOOD', NULL, 2),
(31,  6, 2.300, 'km',  '2014-02-18', 'GOOD', NULL, 2),
(30,  6, 26,    'nos', '2014-02-18', 'GOOD', NULL, 2),
-- Haliela
(26,  7, 1.750, 'km',  '2014-02-18', 'GOOD', NULL, 3),
(31,  7, 1.750, 'km',  '2014-02-18', 'GOOD', NULL, 3),
(30,  7, 20,    'nos', '2014-02-18', 'GOOD', NULL, 3),
(26,  8, 1.050, 'km',  '2013-09-12', 'FAIR', NULL, 3),
(31,  8, 1.050, 'km',  '2013-09-12', 'FAIR', NULL, 3),
(29,  8, 12,    'nos', '2013-09-12', 'FAIR', NULL, 3),
(26,  9, 1.600, 'km',  '2013-09-12', 'GOOD', NULL, 3),
(31,  9, 1.600, 'km',  '2013-09-12', 'GOOD', NULL, 3),
(30,  9, 18,    'nos', '2013-09-12', 'GOOD', NULL, 3),
(28, 10, 0.900, 'km',  '2017-04-05', 'GOOD', NULL, 3),
(31, 10, 0.900, 'km',  '2017-04-05', 'GOOD', NULL, 3),
(30, 10, 10,    'nos', '2017-04-05', 'GOOD', NULL, 3),
(28, 11, 0.700, 'km',  '2017-04-05', 'FAIR', NULL, 3),
(31, 11, 0.700, 'km',  '2017-04-05', 'FAIR', NULL, 3),
(29, 11, 8,     'nos', '2017-04-05', 'POOR', NULL, 3),
(26, 12, 0.450, 'km',  '2019-02-14', 'NEW',  'Mini hydro interconnection line.', 3),
(31, 12, 0.450, 'km',  '2019-02-14', 'NEW',  NULL, 3),
(30, 12, 6,     'nos', '2019-02-14', 'NEW',  NULL, 3),
(26, 13, 1.200, 'km',  '2015-12-01', 'GOOD', NULL, 3),
(31, 13, 1.200, 'km',  '2015-12-01', 'GOOD', NULL, 3),
(30, 13, 14,    'nos', '2015-12-01', 'GOOD', NULL, 3),
(26, 14, 0.800, 'km',  '2018-10-20', 'GOOD', NULL, 3),
(31, 14, 0.800, 'km',  '2018-10-20', 'GOOD', NULL, 3),
(30, 14, 9,     'nos', '2018-10-20', 'GOOD', NULL, 3);


-- =====================================================================
-- SECTION 16 : SEED DATA - TRANSFORMER REGISTER
--
-- 1717 transformer records carried over from transformer_asset_management.sql
-- (originally generated from "Transformer excel.xlsx").
--
-- Changes made during the merge:
--   * The source file's own provinces / areas / cscs / transformer_assets
--     tables are gone. Depot names were resolved against the 17-CSC
--     reference sheet, so 'Hali Ela' -> Haliela (csc_id 5),
--     'Kandeketiya' -> Kandaketiya (3), 'Mahiyanagana' -> Mahiyanganaya (1),
--     'Diyatalawa' -> Diyathalawa (7), 'Uvaparanagama' -> Uva-paranagama (10),
--     'Tanamalvilla' -> Thanamalwila (17), 'Bibila' -> Bibila (14).
--   * The free-text transformer_type is kept verbatim AND mapped to an
--     asset_type_id so the register joins the taxonomy. Labels that did
--     not map are flagged in remarks rather than guessed at.
--   * node_id is NULL everywhere: the transformer sheet has no topology.
--     Fill it in as each depot is surveyed; nothing else has to change.
--
-- Depots with no rows here (Monaragala) simply had none in the source
-- sheet. That is a gap in the source data, not a schema problem.
-- =====================================================================

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(4, 'UBB G01', NULL, 'Rideepana MHP', 'Bulk (MHP)', 1750.00, NULL, 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB G02', NULL, 'Soranathota MHP', 'Bulk (MHP)', 1400.00, NULL, 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB G03', NULL, 'Udawela MHP', 'Bulk', 1400.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 055', NULL, 'Lower King Street', 'Distribution', 250.00, 'T12U025030051', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 141', NULL, 'Capital City', 'Bulk', 100.00, 'T16U010030594', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 056', NULL, 'Kokowaththa', 'Distribution', 400.00, 'T12U040030054', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Lower Street New', 'Distribution', 160.00, 'T18U025030465', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 057', NULL, 'Sri Lanka Telecom - Badulla I', 'Bulk & Distribution', 250.00, 'T00U2503146', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 058', NULL, 'Sri Lanka Telecom - Badulla II', 'Distribution', 160.00, 'T14U016030332', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 132', NULL, 'Sancy RD (Wel Bodiya)', 'Distribution', 250.00, 'T10U025030071', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 059', NULL, 'Bus Stand - Badulla', 'Distribution', 1000.00, 'T12U100030017', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 060', NULL, 'Post Office Complex', 'Bulk', 250.00, 'T01U02503024', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 061', NULL, 'Cargills Food City', 'Distribution', 400.00, 'T18U040030177', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 114', NULL, 'Ministry of Health Service', 'Bulk', 250.00, 'T15U025030011', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 062', NULL, 'Library', 'Bulk', 250.00, 'T02U02503120', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 063', NULL, 'Badulupitiya', 'Distribution', 250.00, 'T11U025030030', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 125', NULL, 'Winzent Dias Ground', 'Bulk', 160.00, 'T14U016030101', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 064', NULL, 'Malwaththa', 'Distribution', 250.00, 'T18U025030178', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 065', NULL, 'Hegoda', 'Distribution', 250.00, 'T13U025030083', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 066', NULL, 'Technical College Badulupitiya', 'Distribution', 160.00, 'T18U016030484', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 033', NULL, 'Pahalagama (Mahalu niwasaya)', 'Distribution', 160.00, 'T21U025030151', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 067', NULL, 'Provincial Council', 'Bulk', 400.00, 'T18U040030015', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 068', NULL, 'CEB Badulla', 'Distribution', 250.00, 'T18U025030412', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 140', NULL, 'Kailash Fashions', 'Bulk', 100.00, 'T10U010030390', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 113', NULL, 'Kachcheriya', 'Bulk', 400.00, 'T12U040030007', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 069', NULL, 'Welekade', 'Distribution', 250.00, 'T05U025030188', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 071', NULL, 'Hospital I', 'Bulk', 630.00, 'T16U063030001', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 070', NULL, 'Hospital II', 'Bulk', 630.00, 'T07U063030039', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 072', NULL, 'Daya Gunasekara MW Junction', 'Distribution', 250.00, 'T08U025030100', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 138', NULL, 'Classic Water PVT LTD', 'Bulk', 100.00, 'T16U010030523', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 073', NULL, 'Pin Arawa Water Pump House', 'Bulk & Distribution', 250.00, 'T/95/2503132', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 119', NULL, 'Kammanankada Junction', 'Distribution', 100.00, 'T20U016030793', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 116', NULL, 'Yampana Waththa', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 074', NULL, 'Sumanathissagama', 'Distribution', 250.00, 'T11U025030041', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 081', NULL, 'Mailagasthenna', 'Distribution', 200.00, 'T03U02503134', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 082', NULL, 'Petroliem Coperation', 'Bulk', 250.00, 'T01U02503091', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 083', NULL, 'Nikathenna Water Pump', 'Distribution', 100.00, 'T18U0250301137', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 131', NULL, 'Mailagasthenna Tea Factory', 'Bulk', 250.00, 'T18U025030456', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 139', NULL, 'Higurugamuwa New', 'Distribution', 160.00, 'T15U016030311', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 084', NULL, 'Kanupelella', 'Distribution', 250.00, 'T05U025030145', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 085', NULL, 'Rockhill Technical College', 'Distribution', 160.00, 'T15U016030066', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 088', NULL, 'Dunuwangiya', 'Distribution', 250.00, 'T21U025030107', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 086', NULL, 'Welikemulla', 'Distribution', 100.00, 'T16U016030111', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 087', NULL, 'Goradiyawaka', 'Distribution', 100.00, 'T22U010030152', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 075', NULL, 'Kumarasingha MW Water Pump House', 'Distribution', 250.00, 'T08U040030082', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 076', NULL, 'Siddartha College', 'Distribution', 500.00, 'T16U040030076', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 146', NULL, 'Viharagoda New', 'Distribution', 160.00, 'T18U016030706', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 089', NULL, 'Meri Gold Garment', 'Bulk', 250.00, 'T/92/3728', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 142', NULL, 'CEB DGM Office', 'Bulk', 250.00, 'T17U025030074', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 077', NULL, 'Hindagoda', 'Distribution', 250.00, 'T03U02503105', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 078', NULL, 'University Of Uva Wellassa I', 'Bulk', 250.00, 'T/92/3780', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 115', NULL, 'University Of Uva Wellassa V', 'Bulk', 1000.00, 'T12U100030022', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 091', NULL, 'Badulusirigama', 'Distribution', 250.00, 'T01U02503120', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 080', NULL, 'University of Uva Wellassa III', 'Bulk', 630.00, 'T05U063030028', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 079', NULL, 'University of Uva wellassa II', 'Distribution', 100.00, 'T20U016030484', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 094', NULL, '2nd Mile Post - Water Pump House', 'Bulk & Distribution', 160.00, 'T20U016030560', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 090', NULL, 'Kalugalpitiya', 'Bulk & Distribution', 250.00, 'T12U025030096', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 145', NULL, 'Rockhill Water Pump House', 'Bulk', 250.00, 'T18U025030228', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 092', NULL, 'WeeriyaPura', 'Distribution', 160.00, 'T17U016030055', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 093', NULL, 'Uva Wellassa University IV', 'Bulk', 630.00, 'T07U063030009', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 095', NULL, 'Janawasama- Hingurugamuwa', 'Distribution', 250.00, 'T17U025030034', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 096', NULL, 'Malangamuwa', 'Distribution', 160.00, 'T18U016030746', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 097', NULL, '3rd Mile Post', 'Distribution', 160.00, 'T18U16030047', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 099', NULL, 'Veenithagama', 'Distribution', 250.00, 'T01U02503115', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 101', NULL, 'Thelbaddagama', 'Distribution', 160.00, 'T08U01603048', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 102', NULL, 'Westmalt', 'Distribution', 100.00, 'T09U010030619', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 103', NULL, 'Thelbadda Factory', 'Bulk & Distribution', 400.00, 'T12U040030060', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 104', NULL, 'Elle Arawa', 'Distribution', 100.00, 'T99U01003296', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 120', NULL, 'Elle Arawa New', 'Distribution', 100.00, 'T12U010030554', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 105', NULL, 'Ampitiya', 'Distribution', 250.00, 'T2018/D0469', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 111', NULL, 'Heennarangolla', 'Distribution', 160.00, 'T21U010030031', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 106', NULL, 'Muthumala', 'Distribution', 160.00, 'T17U016030014', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 107', NULL, 'Galliha', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 108', NULL, 'Urumeethanna', 'Distribution', 100.00, 'T05U010030249', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 130', NULL, 'Kohanawela', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 109', NULL, 'Kahataruppa', 'Distribution', 160.00, 'T12U016030228', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 110', NULL, 'Palawaththa', 'Distribution', 100.00, 'T19U010030082', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 122', NULL, 'Gadadigolla', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 100', NULL, 'Veenithagama II', 'Distribution', 100.00, 'T17U010030212', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Green gold Housing Sceem', 'Distribution', 100.00, 'T02U01003178', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 098', NULL, 'Wewassa Waththa II', 'Distribution', 250.00, 'T99U01003355', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 045', NULL, 'Eladaluwa Garment', 'Bulk & Distribution', 160.00, 'T19U040030018', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 046', NULL, 'Eladaluwa Water Pump', 'Bulk & Distribution', 160.00, 'T/91/13468', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 048', NULL, 'Eladaluwa (Cetell Tower)', 'Distribution', 100.00, 'T06U010030078', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 047', NULL, 'Dematawelhinna', 'Distribution', 160.00, 'T/95/1003067', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 049', NULL, 'Hapuwaththa', 'Distribution', 160.00, 'T17U016030085', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 050', NULL, 'Silpolagama', 'Distribution', 100.00, 'T05U010030240', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 051', NULL, 'Jugdje''s Hill', 'Distribution', 250.00, 'T09U25030149', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 052', NULL, 'Katupalallagama', 'Distribution', 160.00, 'T/04/1603208', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 053', NULL, 'Keselkotuwa', 'Bulk & Distribution', 400.00, 'T12U040030004', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 054', NULL, 'Kirioruwa', 'Distribution', 100.00, 'T98U01003409', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 137', NULL, 'Mediriya Water Project', 'Bulk', 100.00, 'T16U025030156', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 001', NULL, 'Madiriya', 'Distribution', 400.00, 'T17U0400315', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 143', NULL, 'Perlin New', 'Bulk', 100.00, 'T17U010030222', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 002', NULL, 'Cancer Hospital', 'Bulk', 1000.00, 'T07I100080084', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 128', NULL, 'Heritage Hotel', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 129', NULL, 'Welagedara', 'Distribution', 160.00, 'T16U016030572', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 004', NULL, 'Rathwaththa MW', 'Distribution', 250.00, 'T17U025030091', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 129', NULL, 'Onex', 'Bulk', 100.00, '109780', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 005', NULL, 'Kailagoda Junction', 'Distribution', 400.00, 'T02U04003016', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(4, 'UBB 144', NULL, 'RDSH', 'Bulk', 250.00, 'T17U025030089', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 034', NULL, 'Andeniya', 'Distribution', 100.00, 'T93U1003278', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 035', NULL, 'Nelumgama', 'Distribution', 160.00, 'T12U016030244', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 036', NULL, 'Nelumwewa', 'Distribution', 160.00, 'T14U016080086', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 037', NULL, 'Sirimalgoda', 'Distribution', 160.00, 'T05U016030091', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 039', NULL, 'Cullen Estate', 'Distribution', 250.00, '337657', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 038', NULL, 'Katukale', 'Distribution', 160.00, 'T12U010030394', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 040', NULL, 'Damanwara', 'Distribution', 100.00, 'T10U010030453', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 041', NULL, 'Wekada', 'Distribution', 100.00, 'T00U01003246', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 042', NULL, 'Kosgolla', 'Distribution', 100.00, 'T98U01003289', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 043', NULL, 'Kuttiyagolla', 'Distribution', 160.00, 'T16U16030074', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 044', NULL, 'Athgala', 'Distribution', 100.00, 'T09U010030158', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 006', NULL, 'Suvinithagama', 'Distribution', 400.00, 'T18U040030165', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 007', NULL, 'Medapathana', 'Bulk & Distribution', 160.00, 'T07U025080023', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 008', NULL, 'Rideepana', 'Distribution', 160.00, 'T12016030066', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 009', NULL, 'Madithale', 'Distribution', 160.00, 'T10U01603083', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 010', NULL, 'Pitapola', 'Distribution', 100.00, '118974', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 012', NULL, 'Welihida', 'Distribution', 100.00, 'T98U01003398', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 011', NULL, 'Kohowila', 'Distribution', 100.00, 'T11U010030245', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 013', NULL, 'Penaketiya', 'Distribution', 100.00, 'T05U010030028', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 118', NULL, 'Meegahawela', 'Distribution', 100.00, 'T16U010030105', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 136', NULL, 'Batuyaya-Thaldena', 'Distribution', 100.00, 'T10U010030632', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 121', NULL, 'Pudumaoya - Pussalawa', 'Distribution', 100.00, '109788', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 014', NULL, 'Waththekale', 'Distribution', 100.00, 'T09U010030499', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 015', NULL, 'Egodawela', 'Distribution', 100.00, 'T18U010030119', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 016', NULL, 'Meegaspitiya', 'Distribution', 100.00, 'T21U010030423', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 017', NULL, 'Bostal Camp', 'Distribution', 100.00, 'T/92/13658', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 112', NULL, 'Disanayaka Metal Crusher -Theldena', 'Bulk', 160.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, 'UBB 018', NULL, 'Pallekanda', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Mortuary', 'Distribution', 250.00, 'T19U010030239', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Lanka Tile', 'Distribution', 100.00, 'T17U016030109', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Puwakgodamulla', 'Distribution', 100.00, 'T18U016030250', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Passara Road-3rd Mile Post- (Kovila Asala)', 'Distribution', 100.00, 'T19U010030438', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Peelipothagama Road', 'Distribution', 100.00, 'T17U010030028', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Mercantile Credit Building (Cargills Food City)', 'Distribution', 250.00, 'T20U025030056', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Abdul Hameed (MKB)', 'Bulk', 100.00, 'T20U010030075', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Kahataruppa New', 'Distribution', 100.00, 'T09U010080783', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Labour Department', 'Bulk', 250.00, 'T21U025030190', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Uva wellassa library hall', 'Bulk', 630.00, 'T21U063030047', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Cargils food city Bandarawela road', 'Bulk', 250.00, 'T22U025030068', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Central Hospital new', 'Bulk', 630.00, 'T22U063030008', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Imbulgoda (Rockhill new)', 'Distribution', 100.00, 'T22U010030314', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Blosom Tea Factory', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Meegaspitiya New', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Welkele', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Lanka Sathosa', 'Bulk', 160.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(4, NULL, NULL, 'Aryuwedaya Badulla', 'Distribution', 250.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Bambarapana MHP', 'Bulk (MHP)', 2500.00, NULL, 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH 002', 'UBH 002', 'Yelwerton', 'Distribution', 100.00, 'T99U01009532', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH 004', 'UBH 004', 'Kollumandiya', 'Bulk & Distribution', 100.00, 'T.971003232', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH 003', 'UBH 003', 'Serandib', 'Distribution', 300.00, '516417', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH 005', 'UBH 005', 'Mahathenna', 'Distribution', 100.00, 'T.06-U010030229', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH 006', 'UBH 006', 'Sarnia Factory', 'Bulk & Distribution', 400.00, 'T.03.U04003059', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-007', 'UBH-007', 'Kandegedara', 'Bulk & Distribution', 250.00, 'T.18U025030491', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-008', 'UBH-008', 'Galkotuwegama', 'Distribution', 100.00, 'T06U010030215', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-101', 'UBH-101', 'Thangamale', 'Distribution', 100.00, 'T.10U010030774', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-010', 'UBH-010', 'Pussellakanda', 'Distribution', 100.00, 'T.18.U010030562', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-102', 'UBH-102', 'Kohana', 'Distribution', 100.00, 'T..02.U01003355', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-113', 'UBH-113', 'Panjolla', 'Distribution', 100.00, '114807', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-009', 'UBH-009', 'Keenakele', 'Distribution', 160.00, '31472', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Keenakele New', 'Distribution', 100.00, 'T.11.0010030150', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-011', 'UBH-011', 'Dikpitiya', 'Distribution', 100.00, 'T.21 U010030424', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-012', 'UBH-012', 'Thennepanguwa', 'Distribution', 160.00, 'T.19U016080081', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-014', 'UBH-014', 'Jangulla', 'Distribution', 100.00, 'T.08.U010030523', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-015', 'UBH-015', 'Uva Katawala', 'Bulk & Distribution', 160.00, 'T.15.U016030260', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-017', 'UBH-017', 'Ketawala', 'Distribution', 100.00, 'T.00U01003237', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-019', 'UBH-019', 'Deegalla', 'Distribution', 160.00, 'T/981603154', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-016', 'UBH-016', 'Landewala', 'Distribution', 100.00, '114798', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-126', 'UBH-126', 'Bogoda Metal Crusher', 'Bulk', 100.00, 'T18U010030118', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-103', 'UBH-103', 'Kobbeketiya', 'Distribution', 100.00, 'T.11U010030130', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-018', 'UBH-018', 'Panakanniya', 'Distribution', 100.00, 'T/19/U010030441', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-020', 'UBH-020', 'Dehigolla Kandura', 'Distribution', 160.00, 'T04U016030179', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-021', 'UBH-021', 'Lunugalla', 'Distribution', 100.00, 'T.03.U01003178', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-022', 'UBH-022', 'Meeriyakele', 'Distribution', 100.00, 'T08U010030517', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-023', 'UBH-023', 'Narangala', 'Bulk & Distribution', 400.00, 'T/09/U04003092', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-024', 'UBH-024', 'Bokonoruwa', 'Distribution', 160.00, 'T14U016030161', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-120', 'UBH-120', 'Jayasekara Metal Crusher', 'Bulk', 100.00, 'T21U063030014', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-112', 'UBH-112', 'Athukatiya', 'Distribution', 100.00, '114696', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-001', 'UBH-001', 'Bogahamadiththa', 'Distribution', 160.00, 'T18.U025030180', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-032', 'UBH-032', 'Queens Town', 'Bulk & Distribution', 100.00, 'T.0.2.U01003158', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-033', 'UBH-033', 'Hethekma', 'Distribution', 250.00, '6273011', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-034', 'UBH-034', 'CEB', 'Bulk & Distribution', 250.00, 'T.23U025030013', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-035', 'UBH-035', 'Pet Zone', 'Distribution', 100.00, 'T06U016030032', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-036', 'UBH-036', 'Orzone', 'Bulk', 630.00, 'T.07U063030038', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH 127', 'UBH 127', 'AG Office-Hali ela', 'Distribution', 160.00, 'T-18.U025030391', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-122', 'UBH-122', 'Videsha Sewa', 'Bulk', 400.00, 'T.16.U04003008', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-037', 'UBH-037', 'Urban Council', 'Distribution', 250.00, 'T 0 5 U025030154', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-038', 'UBH-038', 'Haliela Telecom', 'Distribution', 160.00, 'T.12-U016030231', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-041', 'UBH-041', 'Haliela Town', 'Distribution', 160.00, 'T.17U025030088', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-039', 'UBH-039', 'Dialog Udadompe', 'Bulk', 100.00, 'T.17U010030068', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-040', 'UBH-040', 'Ambawaka', 'Distribution', 100.00, 'T/97/01002257', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-042', 'UBH-042', 'Kingswood', 'Bulk', 250.00, 'T.11.U.025030073', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-043', 'UBH-043', 'Unagolla Watta', 'Bulk & Distribution', 100.00, 'T.18U010030325', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-124', 'UBH-124', 'Egodagama', 'Distribution', 100.00, 'T.17U010030003', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-044', 'UBH-044', 'Rokathenna Factory', 'Bulk & Distribution', 600.00, 'T.36/300no337762', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-045', 'UBH-045', 'Rokathanna Estate', 'Distribution', 100.00, 'T.03U01003320', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-046', 'UBH-046', '5th Mile Post', 'Distribution', 200.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-055', 'UBH-055', 'Keeriyagolla', 'Distribution', 100.00, '99/U01003071', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-054', 'UBH-054', 'Mawalagoda', 'Distribution', 100.00, 'T.22U010030055', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-056', 'UBH-056', 'Dikwela Estate', 'Bulk & Distribution', 250.00, 'T.18.U025030142', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(5, 'UBH-057', 'UBH-057', 'Udagama', 'Distribution', 100.00, 'T.96/U01003441', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-118', 'UBH-118', 'Wijewardana Metal Crusher', 'Bulk', 100.00, 'T.16.U010030339', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-058', 'UBH-058', 'Etampitiya Garment', 'Bulk & Distribution', 400.00, 'T.18.U040030179', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-059', 'UBH-059', 'Neliathugoda', 'Distribution', 100.00, 'T.16U010030628', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-081', 'UBH-081', 'Glenpin Factory', 'Bulk & Distribution', 400.00, 'T.08.U040030078', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-080', 'UBH-080', 'Senamale', 'Distribution', 100.00, '74369', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-076', 'UBH-076', 'Kandana', 'Distribution', 250.00, 'T00U02503127', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-123', 'UBH-123', 'Dialog Kandana', 'Distribution', 100.00, 'T.17-U010030124', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-077', 'UBH-077', 'Wewalhinna', 'Distribution', 160.00, 'T/91/13470', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-078', 'UBH-078', 'Medagama', 'Distribution', 160.00, 'T.18.U016030538', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-079', 'UBH-079', 'Rilpola', 'Distribution', 100.00, '160600241-58', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-074', 'UBH-074', 'Kottagoda', 'Distribution', 100.00, 'T.18U010030183', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-075', 'UBH-075', 'Diyanawela', 'Distribution', 100.00, 'T 18U010030239', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-074', 'UBH-074', 'Bulathwatta', 'Distribution', 100.00, '93-1003186', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-070', 'UBH-070', 'Nallamale', 'Distribution', 100.00, 'T.00 U01003407', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-071', 'UBH-071', 'Memale Factory', 'Distribution', 630.00, 'T/90/4149', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-072', 'UBH-072', 'Namunukula (Telecome)', 'Distribution', 160.00, 'T14-U016030330', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-073', 'UBH-073', 'MTV (Sirasa)', 'Bulk', 100.00, 'T.14.U.016030347', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-069', 'UBH-069', 'Springvalley', 'Distribution', 160.00, 'T.19/U.0250370', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-068', 'UBH-068', 'Nawala Estate', 'Distribution', 100.00, 'T.10.U010030677', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-065', 'UBH-065', 'Gawarawela Temple', 'Distribution', 100.00, 'T 931003356', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-066', 'UBH-066', 'Gawarawela II', 'Distribution', 160.00, 'T.10.U016030345', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-067', 'UBH-067', 'Otube Watta', 'Distribution', 100.00, 'T08U010030215', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Walasbedda II', 'Distribution', 160.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Cargills Haliela', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-053', 'UBH-053', 'Demodara Factory', 'Bulk & Distribution', 400.00, 'T00U04003042', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-052', 'UBH-052', 'Demodara', 'Distribution', 160.00, 'T18U025030452', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-051', 'UBH-051', 'Walasbedda', 'Bulk & Distribution', 300.00, '46830', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-119', 'UBH-119', 'Water Bord - Uduwara', 'Bulk', 1000.00, 'T13U100030008', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-050', 'UBH-050', 'Milk Board', 'Bulk & Distribution', 100.00, 'T10U010030482', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-115', 'UBH-115', 'Daragala Pathana', 'Distribution', 100.00, '109733', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-049', 'UBH-049', '7th Mile Post', 'Distribution', 160.00, 'D14U0116030344', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-048', 'UBH-048', 'Rosette', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-047', 'UBH-047', '6th Mile Post', 'Distribution', 160.00, 'L 13.U016030183', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-061', 'UBH-061', 'ST. James', 'Distribution', 100.00, '08.U010030512', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-060', 'UBH-060', 'Kirinda', 'Distribution', 100.00, '95-1003094', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, 'UBH-062', 'UBH-062', 'Moretota', 'Distribution', 100.00, 'T-17-U010030092', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Indian housing scheme', 'Distribution', 100.00, 'T.19 U010030088', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Spring valley new', 'Distribution', 100.00, 'T.20.U-016030199', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'AG O‌ffice', 'Bulk', 250.00, 'T.21.U025030040', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Maluwegoda', 'Distribution', 100.00, 'T.21U010030398', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Udawela', 'Bulk', 100.00, 'T.08U010080522', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Ellanda- Demodara', 'Distribution', 100.00, 'T21 010030312', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Udenigama', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(5, NULL, NULL, 'Walasbedda New', 'Distribution', 160.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP G1', 'SEE HYDRO I', 'Bulk (MHP)', 4000.00, NULL, 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP G2', 'SEE HYDRO II', 'Bulk (MHP)', 1600.00, NULL, 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 001', 'Tea Factory - Tholabowaththa', 'Bulk', 100.00, 'T.03.U02503110', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 002', 'Tholabowaththa', 'Distribution', 160.00, 'T.20.U016030099', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 003', 'Eltab waththa', 'Bulk & Distribution', 400.00, 'T.12.U040030066', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 004', 'Medawelagama', 'Distribution', 100.00, 'T.18.U010030029', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 005', 'Geradiella', 'Distribution', 100.00, 'T.21.U010030114', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 006', 'Rubberwaththa', 'Distribution', 100.00, '74348', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 007', 'Madugasthalawa', 'Distribution', 100.00, 'T.918220', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 008', 'Thennuge/ Pinella', 'Distribution', 160.00, 'T.17.U016030089', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 009', 'Waradhola', 'Distribution', 100.00, 'T.14.U010030365', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 010', 'Amunumulla', 'Distribution', 100.00, 'T/91/8357', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 011', 'Medapathana/ Galakulugolla', 'Distribution', 100.00, '308228', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 012', 'Passara II (Near the Fair)', 'Distribution', 250.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 013', 'Passara III (Central College)', 'Distribution', 160.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 014', 'Powerloom/ Kithulkele', 'Distribution', 100.00, 'T.18.U016030865', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 015', 'Sapurodha/ Pallegama', 'Distribution', 100.00, 'T.20.U016030497', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 016', 'Meeriyabedda', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 017', 'Telecom Tower Passara', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 018', 'Telecom Passara', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 019', 'Passara I (Gemunu School)', 'Distribution', 250.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 020', 'Milk Board', 'Distribution', 100.00, 'T.94.1003282', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 021', 'Gonagala', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 022', 'Sangabo Mawatha', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 023', 'Maussagolla', 'Distribution', 100.00, 'T.21.U016030208', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 024', 'Parapawa I (Godapita)', 'Distribution', 160.00, 'T.20.U016030099', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 025', 'Parapawa II (Near Temple)', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 026', 'Bibilegama II (Ethpattiya)', 'Distribution', 100.00, 'T.00.U01003334', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 027', 'Gonakella State', 'Bulk & Distribution', 630.00, 'T.18.U063030030', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 028', 'TRI - Tea Research Laboratory', 'Distribution', 100.00, 'T.00.U01003196', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 029', 'Palgahathenna', 'Distribution', 160.00, 'T.19.V016030179', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 030', 'Ury Factory', 'Bulk & Distribution', 250.00, 'T.09.U025030158', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 031', 'Pelgahathenna Training Centre Ury', 'Bulk', 100.00, 'T/99/U01003490', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 032', 'Udagama (Near Temple)', 'Distribution', 100.00, 'T.00.U01008298', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 033', 'Udagama (Diyakillapotha)', 'Distribution', 100.00, 'T.19.U010030240', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 034', 'Kirigala', 'Distribution', 100.00, 'T.03.U01003136', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 035', 'Agarathenna (Near Kovil)', 'Distribution', 100.00, 'T.09.U010030243', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 036', 'Welgolla', 'Distribution', 100.00, 'T.09.U010030234', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 037', 'Welgolla II (Polgahawaththa)', 'Distribution', 100.00, 'T/94/1003082', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 038', 'Wewessa Factory', 'Bulk & Distribution', 250.00, 'T.06.U025030016', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 039', 'Tholabowaththa II (Jayanthi School)', 'Distribution', 100.00, 'T/92/8605', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 040', 'Gamewela', 'Distribution', 100.00, 'T.21.U010030420', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 041', 'Gedawila', 'Distribution', 100.00, 'T.18.U010030291', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 042', 'Passara waththa/ Meedumpitiya', 'Bulk & Distribution', 300.00, 'T.2018-D0501', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 043', 'Ellawaththa', 'Distribution', 100.00, 'T.04.U010030374', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 044', 'Millabedda', 'Distribution', 160.00, 'T.16.U016030380', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 045', 'Hoptan Estate', 'Bulk & Distribution', 630.00, 'T.12.U063030029', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 046', 'Kehelwaththa', 'Distribution', 100.00, 'T.01.U01003043', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 047', 'Yapamma Keenagoda', 'Distribution', 100.00, 'T.19.U010030013', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 048', 'Shawlands', 'Bulk & Distribution', 250.00, 'T.2018-A0410', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 049', 'Sumudugama', 'Distribution', 250.00, 'T.05.U025030142', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 050', 'Lunugala', 'Distribution', 250.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 051', 'Janathapura', 'Distribution', 100.00, 'T.00.U01003459', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 052', 'Lunugalagama', 'Distribution', 100.00, 'T.03.U01003153', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 053', 'Alakolagala', 'Distribution', 100.00, 'E 1063770', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(6, NULL, 'UBP 054', 'Adawaththa', 'Bulk & Distribution', 250.00, 'T.00.U02503345', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 055', 'Arawakumbura', 'Distribution', 100.00, '99.U01003199', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 056', 'Udagama/ Kiramanagoda', 'Distribution', 100.00, 'T.05.U010030008', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 057', 'Mahadowa Waththa', 'Bulk & Distribution', 400.00, '3739', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 058', 'Madolsima Repeat Station', 'Distribution', 100.00, 'T.02.U01003187', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 059', 'Dialog Telecom', 'Bulk', 400.00, 'T.08.11040080081', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 060', 'Mahadowa Bungalow', 'Distribution', 160.00, 'T.17.U016030092', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 061', 'Telecom Madolsima', 'Bulk', 100.00, '0 308378', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 062', 'Madolsima', 'Distribution', 150.00, '90810197', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 063', 'Werellapathana', 'Bulk & Distribution', 300.00, 'T.03.U02503057', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 064', 'Galloolla Waththa', 'Bulk & Distribution', 150.00, 'T.15.U016030058', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 065', 'Batawaththa Estate', 'Bulk & Distribution', 300.00, '3.37793', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 066', 'Metigahathenna (I) Hospital/ Wewabedda', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 067', 'Metigahathenna II', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 068', 'Bakinilanda', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 069', 'Ekiriya', 'Distribution', 100.00, 'T.02.U01003670', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 070', 'Kokagala Waththa', 'Bulk & Distribution', 250.00, 'T.19.U025030056', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 071', 'Elamanna', 'Distribution', 100.00, 'T.08.U010030103', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 072', 'Ragala', 'Distribution', 100.00, 'T.02.U01003643', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 073', 'Pitamaruwa', 'Distribution', 100.00, 'T.86.2434', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 074', 'Robary Waththa', 'Bulk & Distribution', 500.00, '28.0001.2435', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 078', 'Maussagolla Waththa (EGK)', 'Distribution', 100.00, 'T.09.U010030177', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 079', 'Kanawerella (Galpathuketiya)', 'Distribution', 160.00, 'T.21.U016030279', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 080', 'kanawerella Factory', 'Bulk & Distribution', 400.00, 'T.02.U04003022', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 081', 'Wewekelle', 'Bulk & Distribution', 100.00, '11003/6', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 082', 'Bibilegama I', 'Distribution', 160.00, 'T.10.0016030234', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 083', 'Kandahena Estate', 'Bulk & Distribution', 160.00, 'T.17.U016030052', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 084', 'Bootawatta', 'Distribution', 100.00, 'T.05.U010030048', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 085', 'Dewathura', 'Distribution', 100.00, 'T.01.U01003357', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 086', 'Miyanakandura', 'Distribution', 100.00, 'T.U1.U01003359', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 087', 'Ranugalla', 'Distribution', 100.00, 'T.10.U010030580', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 088', 'Dambagahawela', 'Distribution', 100.00, 'T.02.U01003090', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 103', 'Galbokka', 'Distribution', 100.00, 'T.09.U010030444', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 104', 'Kendagahamadapathana', 'Distribution', 100.00, 'T.11.U010030485', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 105', 'Maduwaththa', 'Distribution', 100.00, 'T.11.U010034426', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 106', 'Kirigalpoththa', 'Distribution', 100.00, 'T.11U010030203', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 107', 'Bathwewa', 'Distribution', 100.00, 'T.U010030208', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 108', 'Kehelwaththagama', 'Distribution', 100.00, '308065', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 109', 'Udakiruwa I (Udathenna)', 'Distribution', 100.00, '114728', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 110', 'Udakiruwa', 'Distribution', 100.00, '114825', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 111', 'Udaothumba', 'Distribution', 100.00, 'T.21.U010030037', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 112', 'Galwelagama', 'Distribution', 100.00, '109810', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 113', 'Itithampala', 'Distribution', 100.00, '144697', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 114', 'Sooriyagolla', 'Distribution', 100.00, '114721', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 115', 'Diggala', 'Distribution', 100.00, '114713', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 116', 'Udawaththa (Yapamma)', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 117', 'Udakiruwa III (Ethundamuwawa)', 'Distribution', 100.00, '114719', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 118', 'Alubogolla', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 119', 'Peessagama', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 120', 'Dehigolla', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 121', 'Daysbrook', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 122', 'Galloolla Pahalagama', 'Distribution', 100.00, 'T.15.U010030029', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 123', 'Pallekiruwa I', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 124', 'Pallekiruwa (Near the school)', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 125', 'Janathapura North', 'Distribution', 100.00, 'T.16.U010030135', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 126', 'Pahala Galliha', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 127', 'Lunugala Police/ Udapanguwa', 'Distribution', 100.00, 'T.18.U016030855', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 128', 'Wetakewewa', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 129', 'ICC (BULK) (Substation has been Removed)', 'Bulk', 160.00, NULL, 1, 11, 'Source sheet records this unit as removed (quantity 0).', 'RETIRED', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 130', 'Waradola Metal Crusher', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 131', 'Pallekiruwa - Weheragoda', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 132', 'Kasala Kalamanakaranaya Meedumpitiya', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 133', 'Hoptan dialog tower', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 134', 'Papalagama', 'Distribution', 100.00, 'T.18.U010030017', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 136', 'Parkwaththa', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 137', 'Tholabowatta Near Kovil', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 138', 'Akiriya New', 'Distribution', 100.00, 'T.18.U010030715', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 139', 'Kalukele', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 140', 'One way', 'Distribution', 100.00, 'T.21.U02503005', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 141', 'Gonakele Estate Badulla RD,10th MP', 'Distribution', 100.00, 'T.18.U010030728', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 142', 'Welgolla Moragaspathana', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 143', 'Mahathenna (Meeriyabedda metal crusher)', 'Distribution', 100.00, 'T.11.U010030198', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(6, NULL, 'UBP 144', 'Hoptan Hospital', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB G01', 'Tannewatha MHP', 'Bulk (MHP)', 1000.00, NULL, 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 001', 'Hotel School', 'Bulk', 250.00, 'T.04.U025080044', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 002', 'Diyabibila', 'Distribution', 100.00, 'T.09.U010030171', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 003', 'St. Thomas College', 'Distribution', 250.00, 'T.01.U025030099', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 004', 'Wewathenna', 'Bulk & Distribution', 250.00, 'NOT CLEAR', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 005', 'Amunudowa', 'Distribution', 250.00, 'T.13.U025030113', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 006', 'Aislaby Estate', 'Bulk & Distribution', 400.00, 'T.01.U04003039', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 007', 'Kirioruwa', 'Distribution', 100.00, 'T.18.U025030460', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 008', 'Katugaha Junction DDLO', 'Distribution', 100.00, 'T.99.UO1003478', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 009', 'Maliththa', 'Distribution', 160.00, 'T.06.UO16030037', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 010', 'Kurukude', 'Distribution', 160.00, '74729', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 011', 'Uva Highland', 'Bulk & Distribution', 400.00, 'T.11.U040030029', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 012', 'Abayapura', 'Distribution', 100.00, 'T/95/1003257', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 013', 'Aththalagedara', 'Distribution', 100.00, 'T.11.U010030083', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 014', 'Perahettiya', 'Distribution', 100.00, 'T.99.U0100354', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 015', 'Ellawala Estate', 'Bulk & Distribution', 200.00, 'NOT CLEAR', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 016', 'Dehiwinna', 'Distribution', 160.00, 'T.18.U016030276', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 017', 'Wellawala', 'Distribution', 100.00, 'T.99.U01003189', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 018', 'Etampitiya Town', 'Distribution', 100.00, 'T.12.U016030247', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 019', 'Ettampitiya Estate', 'Distribution', 400.00, 'T.93.4003012', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 020', 'Udagama', 'Distribution', 100.00, 'T.06.U010080359', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 021', 'Gawela', 'Distribution', 160.00, 'T.06.U016030243', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 022', 'Weragama', 'Distribution', 100.00, 'T.02.U01003052', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 023', 'Neluwa Kosgahatenna', 'Distribution', 100.00, 'T.09.U010030389', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 024', 'Batawala', 'Distribution', 100.00, 'T/98/01003045', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 025', 'Pahala Katugaha', 'Distribution', 100.00, 'T.21.U010030333', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 026', 'Neluwa Watte', 'Bulk & Distribution', 400.00, 'T/97/4003002', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(8, NULL, 'UDB 027', 'Ambewela', 'Distribution', 160.00, 'T.01.U01603147', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 028', 'Neluwa Junction', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 029', 'St James Estate', 'Bulk', 500.00, 'NOT CLEAR', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 030', 'Ambegoda', 'Distribution', 250.00, 'T.18.U025030272', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 031', 'Diganatenna', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 032', 'Konthahela', 'Distribution', 100.00, 'T.18.U010030482', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 033', 'Panangala', 'Distribution', 100.00, 'T.98.U01003268', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 034', 'Mathatilla', 'Distribution', 100.00, 'T.12.U010030333', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 035', 'Belipola', 'Distribution', 100.00, 'NOT CLEAR', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 036', 'Mirahawatta (RDA)', 'Distribution', 160.00, 'T.16.U016030235', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 037', 'Mirahawatta Uma Oya Project', 'Bulk', 250.00, 'T.13.U25030144', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 038', 'Mirahawatta School', 'Distribution', 100.00, 'T.11.U010030346', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 039', 'Amunumulla', 'Distribution', 100.00, '9801003234', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 040', 'Malpotha', 'Distribution', 160.00, 'T.18.U016030776', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 041', 'Welikadagama', 'Distribution', 100.00, 'T.03.U01003023', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 042', 'Dayaraba', 'Distribution', 160.00, 'T.18.U016030623', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 043', 'Ambatenna Estate', 'Bulk & Distribution', 160.00, 'T.01.U01603146', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 044', 'Perera Mawatha', 'Distribution', 100.00, 'T/19/U016030669', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 045', 'Nayabedda Estate', 'Bulk & Distribution', 400.00, 'T.94.403036', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 046', 'Poonagala Road (Galwala)', 'Distribution', 160.00, 'T.17.U016030081', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 047', 'Poonagala Road Kovila', 'Distribution', 160.00, 'T/91/13486', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 048', 'Jalasa Kanda', 'Bulk & Distribution', 160.00, '971603123', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 049', 'S.L.B.C. Nayabedda', 'Bulk', 250.00, 'T.12.U025030204', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 050', 'St. Catherine', 'Distribution', 100.00, 'T.14.U010030240', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 051', 'ITN Nayanabedda', 'Bulk & Distribution', 100.00, 'T.02.U01603013', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 052', 'MTT Nayanabedda', 'Bulk', 250.00, 'T.06.U025030083', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 053', 'Craig Estate', 'Bulk & Distribution', 400.00, 'T.04.U040030035', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 054', 'Balagalaella Estate', 'Bulk & Distribution', 250.00, 'S.17919125', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 055', 'Liyanagahawela Town', 'Distribution', 160.00, 'T.19.U016030207', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 056', 'Liyanagahawela Telecom', 'Bulk', 50.00, 'T.1087931446', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 057', 'Walkers', 'Distribution', 100.00, 'T.19.U016030660', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 058', 'St.Thomas Junction', 'Distribution', 250.00, 'T.17.U025030105', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 059', 'Bandarawela MC Ground', 'Distribution', 400.00, 'T.01.U02503114', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 060', 'Bandarawela Hospital', 'Distribution', 160.00, 'T.19.U025030141', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 061', 'Attalapitiya', 'Distribution', 160.00, 'T.17.U016030133', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 062', 'Bandarawela cargills', 'Distribution', 400.00, 'T.01.U04003044', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 063', 'Cargills Food City', 'Bulk', 800.00, 'T.18.U080030021', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 064', 'Bandarawela Telecom', 'Bulk', 250.00, 'T.01.U02503092', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 065', 'Dharmawijaya Mawatha', 'Distribution', 250.00, 'T.17..U025030165', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 066', 'Commercial Center', 'Bulk', 630.00, 'T.03.U06303021', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 067', 'Bandarawela Temple', 'Distribution', 250.00, 'T.06.U025030053', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 068', 'Thanthiriya', 'Distribution', 250.00, 'T.17.U025030129', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 069', 'Kinigama', 'Distribution', 250.00, 'T.05.U025030062', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 070', 'Meeriyagha Junction', 'Distribution', 250.00, 'T.18.U025030093', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 071', 'Mahaulpotha', 'Distribution', 100.00, 'T.10.U016030328', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 072', 'Uduhulpotha', 'Distribution', 100.00, 'T.01.U01603134', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 073', 'Ethwill Garment', 'Bulk', 100.00, 'T.02.U1003029', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 074', 'Suramyagama', 'Distribution', 160.00, 'T.17.U016030095', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 075', 'Vishaka Road SLT', 'Bulk', 100.00, 'T.02.U01003015', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 076', 'Gediyaroda', 'Distribution', 100.00, 'T.12.U016030371', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 077', 'Uva Praja BC', 'Bulk & Distribution', 100.00, 'T.02.U01003017', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 078', 'Kabillawela North', 'Distribution', 250.00, 'T.18.U025030500', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 079', 'Bindunuwewa Junction', 'Distribution', 160.00, 'T.17.U016030093', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 080', 'Dikarawa', 'Distribution', 100.00, 'T.01.U01003331', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 081', 'Bindunuwewa Farm', 'Distribution', 250.00, 'T.01.U025031001', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 082', 'Yowun Senankaya', 'Bulk & Distribution', 100.00, 'T.03.U01003249', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 083', 'Training College Bindunuwewa', 'Bulk & Distribution', 100.00, 'T.01.U01003322', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 084', 'Maduwelpathana', 'Distribution', 250.00, 'T.08.U025030059', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 085', 'Katugaha Junction II New', 'Distribution', 100.00, '1606000242', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 086', 'Dharamapala School', 'Distribution', 160.00, 'T.19.U016030128', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 087', 'Amunudowa New (Hapathgamuwa Bridge)', 'Distribution', 100.00, '100', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 088', 'Attampitiya Junction NEW', 'Distribution', 160.00, 'T.21.U016030792', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 089', 'Craig Estate New', 'Distribution', 100.00, 'T.20.U010030247', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 117', 'Liyangahawela Estate', 'Bulk & Distribution', 160.00, 'T/98/01603129', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 118', 'Ampitakanda Telecom', 'Bulk & Distribution', 100.00, 'T.02.U0103148', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 119', 'Poonagala Estate', 'Bulk', 630.00, 'T.17.U063030028', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 120', 'Udahena Poonagala', 'Distribution', 100.00, 'T.08.U010030322', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 121', 'Mahakanda Estate', 'Bulk & Distribution', 160.00, 'SD0150/83', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 122', 'Ampitikanda', 'Bulk & Distribution', 200.00, '6502120', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 123', 'Arnold Village', 'Distribution', 100.00, 'T.03.U01603233', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 124', 'Arnoll', 'Distribution', 160.00, 'T.09.U010030315', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 125', 'Kabaragala', 'Distribution', 100.00, 'T.99.U01003187', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 126', 'Makaldeniya', 'Distribution', 100.00, 'T.03.U01003185', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 127', 'New Bus Stand- Bandarawela', 'Distribution', 100.00, '114757', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 128', 'Wee Gabadawa', 'Distribution', 100.00, '114711', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 129', 'Bandara Eliya New', 'Distribution', 100.00, '114747', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 130', 'Dyaraba Dam Site I (substation has been Removed)', 'Removed the Substation', 100.00, NULL, 1, NULL, 'Unmapped source type label: Removed the Substation | Source sheet records this unit as removed (quantity 0).', 'RETIRED', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 131', 'Dyaraba Dam Site II (substation has been Removed)', 'Removed the Substation', 1000.00, NULL, 1, NULL, 'Unmapped source type label: Removed the Substation | Source sheet records this unit as removed (quantity 0).', 'RETIRED', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 132', 'Mirahawaththa Uma Oya Project (Office Complex)', 'Bulk', 160.00, 'T.13.U016030256', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 133', 'Premarathna Garage', 'Distribution', 100.00, 'T.18.U016030858', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 136', 'Kithmina (Account has been Finalized)', 'Finalized the account', 100.00, NULL, 1, NULL, 'Unmapped source type label: Finalized the account | Source sheet records this unit as removed (quantity 0).', 'RETIRED', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 138', 'Udaperuwa', 'Distribution', 100.00, 'T.17.U010030064', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 139', 'Makaldeniya Housing Scheme', 'Distribution', 100.00, 'T.16.U010030097', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 140', 'ITN Nayabedda II', 'Bulk', 100.00, 'T.16.U010030306', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 141', 'Ranayaya Tea Factory', 'Bulk', 160.00, 'T.04.U016030260', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 142', 'Base Hospital Bandarawela', 'Bulk', 160.00, 'T.19.U016030626', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 143', 'Kanmark Hotel', 'Bulk', 100.00, 'T.16.U01030468', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 145', 'K-Life', 'Bulk', 630.00, 'T.16.U063030037', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 148', 'People Network', 'Bulk', 100.00, 'T.16.U010030596', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 151', 'Iconic Land Mark', 'Bulk', 1000.00, 'T.18.U100030011', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB153', 'Fakhri Food', 'Bulk', 250.00, 'T.18.U025030051', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB157', 'King Rose Metal Crusher', 'Bulk', 400.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB158', 'Ampitikanda Housing Scheme', 'Distribution', 160.00, 'T.18.U016030279', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB160', 'Poonagala New Housing Scheme', 'Distribution', 160.00, 'T.22.U016030117', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 164', 'NDB Bank Bandarawela', 'Distribution', 160.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 166', 'Water Purification Plant-Attampitiya', 'Bulk', 400.00, 'T.18.U040030102', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 167', 'Booster Pump House 2- Attampitiya', 'Bulk', 250.00, 'T.18.U025030479', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 168', 'Booster Pump House 1- Attampitiya', 'Bulk', 160.00, 'T.18.U016030428', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 169', 'Kalu Ambagaha Watta Army Camp (Close to Mini Hydro Power)', 'Bulk & Distribution', 100.00, 'T.20.U010030192', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 170', 'CIB Shopping Center', 'Bulk', 250.00, 'T.18.U025030471', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(8, NULL, 'UDB 173', 'Dehivinna New', 'Distribution', 160.00, 'T.21.U010030339', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 174', 'Nayabadda New Housing Scheme', 'Distribution', 100.00, 'T.18.U010030692', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 175', 'Kurukude New', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 176', 'Mahaulpotha II', 'Distribution', 100.00, 'T.20U010030180', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 177', 'Kirioruwa Thelinwewa', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 178', 'Sri Sangaraja Piriwena', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 179', 'Maligathanna', 'Distribution', 160.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 180', 'Dyraba dam side', 'Bulk', 160.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 181', 'Poonagala Housing Scheme II', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 182', 'Lassana Flower Nurseries', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 183', 'Croft Hill Land Sale', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB184', 'Mirahalgamuwa Etampitiya', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB185', 'New Nagaswewa Shopping Complex', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB186', 'Ishara Garment', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB187', 'Kabaragala Re-Settlement (Scheme)', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(8, NULL, 'UDB 188', 'Poonagala Estate Hosing Project', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 001', 'Mirahawaththa', 'Distribution', 100.00, 'T.00.U01003239', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 002', 'Dyaraaba', 'Distribution', 400.00, '391289', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 003', 'Balathota Ella', 'Distribution', 100.00, 'T.05.U01003056', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 004', 'Koskanuwewela', 'Distribution', 100.00, 'T.97.01603239', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 005', 'Ketakella', 'Distribution', 160.00, 'T.06.U010030038', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 006', 'Dikkapitiya Temple', 'Distribution', 100.00, 'T.99.U01003529', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 007', 'Dikkapitiya TC', 'Distribution', 160.00, 'T.87.2877', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 008', 'Yalpathwela', 'Distribution', 100.00, '98160003164', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 009', 'Dambawinna Wewa', 'Distribution', 100.00, 'T.94.1003270', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 010', 'Dambawinna CEB', 'Distribution', 250.00, 'T.16.U025030051', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 011', 'Ruwansiri', 'Bulk', 250.00, 'T.13U025030097', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 012', 'Amunumulla', 'Distribution', 160.00, 'T.22.U016030017', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 013', 'Amunnekadura', 'Distribution', 160.00, 'T.18.U016030700', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 014', 'Hingurugamuwa', 'Distribution', 250.00, 'T.18.U025030482', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 015', 'Yodunwewa', 'Distribution', 100.00, 'T.06.U010030374', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 016', 'Nedungamuwa Rathpaha', 'Distribution', 100.00, 'T.93.1003494', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 017', 'Guruthalawa Alugolla', 'Distribution', 100.00, 'T.21.U016030234', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 018', 'Bogahakumbura', 'Distribution', 100.00, 'T.18.U02503027', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 019', 'Udubadana', 'Distribution', 160.00, 'T.05.U016030058', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 020', 'Thennakonwela', 'Distribution', 100.00, 'T.00.U01003064', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 021', 'Guruthalawa', 'Distribution', 250.00, 'T.11.U025030033', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 022', 'Nickel Field', 'Distribution', 250.00, 'T08.U025080141', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 023', 'Mahathenna', 'Distribution', 160.00, 'T.17.U016030124', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 024', 'Timber Depot Boralanda', 'Bulk & Distribution', 250.00, 'T.08.U.250030031', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 025', 'Boralanda Town', 'Distribution', 250.00, 'T.16.U025030183', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 026', 'Pitapola', 'Distribution', 160.00, 'T.16.U.016030053', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 027', 'Galedanda', 'Distribution', 250.00, 'T.17.U025030102', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 028', 'Hinnarangolla', 'Distribution', 160.00, 'T.16.U016030068', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 029', 'Quality Seed', 'Bulk & Distribution', 100.00, 'T.07.U016030248', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 030', 'Wangiyakumbura', 'Distribution', 160.00, 'T.13.U016030184', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 031', 'Olugama', 'Distribution', 100.00, 'T.97.1003079', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 032', 'Foliage Boralanda', 'Bulk', 250.00, 'T.16.U025030100', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 033', 'Kandepuhulpola', 'Distribution', 100.00, 'T.94.1003200', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 034', 'T.C Welimda', 'Distribution', 250.00, 'T.19.U040030061', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 035', 'Welimada Town saranga', 'Distribution', 250.00, 'T.11.U025030072', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 036', 'Welimada Town II (AG Office)', 'Distribution', 250.00, 'T.15.U025030050', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 037', 'Ambrosia Tea Factory', 'Bulk', 160.00, 'T.04.U16030079', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 038', 'Landegama', 'Distribution', 100.00, 'T.21.U016030446', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 039', 'Uva Benhead Estate', 'Distribution', 100.00, 'T.88.7708', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 040', 'Nedungamuwa III (Temple)', 'Distribution', 100.00, 'T.89.7999', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 041', 'Nedungamuwa School', 'Distribution', 160.00, 'T.98.U01003352', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 042', 'Madowita', 'Distribution', 100.00, '94.1003112', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 043', 'Kalubululanda Telecom', 'Bulk & Distribution', 100.00, '98.01003203', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 044', 'Amarakoongama', 'Distribution', 160.00, 'T.14.U016030039', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 045', 'Wemulla Tea Factory', 'Bulk', 400.00, 'T.99.U04003086', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 046', 'Nugathalawa', 'Distribution', 150.00, '516330', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 047', 'TRI Star Apperal', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 048', 'Welimadagama', 'Distribution', 100.00, 'T.04.U010030309', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 049', 'Iluka Galwala', 'Bulk', 100.00, 'T.04.U010030414', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 050', 'Girambe Dimuthugama', 'Distribution', 160.00, '74739', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 051', 'Ambagasdowa Estae', 'Bulk & Distribution', 250.00, 'T.04.U025030034', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 052', 'Dimuthugama I (Thotupala)', 'Distribution', 160.00, 'T.18.U016030214', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 053', 'Dimuthugama II (Temple)', 'Distribution', 160.00, 'T.18.U016030064', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 054', 'Ella Dimuthugama', 'Distribution', 100.00, 'T.99.U01003228', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 055', 'T.C Daragala', 'Distribution', 250.00, '942503008', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 056', 'Sucharithagama', 'Distribution', 250.00, 'T.18.U025030155', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 057', 'Hiuje Farm', 'Bulk', 250.00, 'T0.8.U025030137', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 058', 'Erabadda', 'Distribution', 100.00, 'T.22.U016030294', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 059', 'CTB Keppettipola', 'Bulk & Distribution', 100.00, 'T.22.U025030059', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 060', 'S.T.C Keppetipola', 'Bulk & Distribution', 400.00, 'T.00.U04003043', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 061', 'Vidurupola', 'Distribution', 160.00, '74437', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 062', 'DEC Keppettipola', 'Distribution', 160.00, 'T.99.U01603523', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 063', 'MPCS Keppetipola', 'Bulk & Distribution', 250.00, 'T.923685', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 064', 'Gawarammana I', 'Distribution', 160.00, 'T.17.U16030140', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 065', 'Gawarammana II (Nisshanka)', 'Distribution', 100.00, 'T.09.U10030250', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 066', 'Idamegama', 'Distribution', 160.00, 'T.98.1603007', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 067', 'Hewanakumbura I (Temple)', 'Distribution', 250.00, 'T.570D.34837', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 068', 'Hewanakumbura 2 (Ambagasdowa)', 'Distribution', 100.00, 'T.01.U.01003066', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 069', 'Glench', 'Distribution', 100.00, 'T.08.U010030003', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 070', 'Haggala Tea Factory', 'Distribution', 250.00, 'T.17U025030106', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 071', 'Balungala', 'Distribution', 160.00, 'T.21.U016030253', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 072', 'Silmiyapura', 'Distribution', 160.00, 'T.07.U016030258', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 073', 'Rendapola', 'Distribution', 160.00, 'T12U016030252', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 074', 'Naleen Farm', 'Distribution', 100.00, 'T.18.U016030663', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 075', 'Warwick Estate', 'Bulk & Distribution', 160.00, 'T.17.U016030084', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 076', 'Haggala', 'Distribution', 250.00, 'T.13.U02503051', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 077', 'Haddaula', 'Distribution', 100.00, 'T.99.U01003359', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 078', 'Divithotawela Kanda', 'Distribution', 160.00, 'T.14.U010030296', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 079', 'SLT - Welimada', 'Bulk', 100.00, 'T.02.U01003171', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 080', 'Broughing Estate', 'Bulk & Distribution', 160.00, 'T.13.U2503047', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 081', 'T.C Puhulpola', 'Distribution', 250.00, 'T.06.U.25030040', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 082', 'Kotawera', 'Distribution', 160.00, '74355', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 083', 'Bogahakumbura Town', 'Distribution', 160.00, 'T.16.U.01603044', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 084', 'Karagahabedda (Thenna)', 'Distribution', 100.00, '308097', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(9, NULL, 'UDW 085', 'Cargils Welimada', 'Bulk', 160.00, 'T.13.U016030136', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 086', 'Water Board Daragala', 'Bulk', 160.00, 'T.10.U016030355', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 087', 'CEC Kande Puhulpola', 'Bulk', 1000.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 088', 'Morogolla Umanadigama', 'Distribution', 100.00, '114789', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 089', 'Puhul pola new Village', 'Distribution', 100.00, '114734', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 090', 'PLP Dyraba', 'Bulk', 400.00, 'T.12.U040030028', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 091', 'Welimada Hospital', 'Bulk', 250.00, 'T.12U040030056', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 092', 'Jaggro PVT LTD', 'Bulk', 250.00, 'T.15.U025030138', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 093', 'Uma Oya Dam Side', 'Bulk', 1000.00, 'T.07.U100030018', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 094', 'Jayarathna Flowerist', 'Bulk & Distribution', 100.00, 'T.16.U010030140', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 095', 'Savora Timber', 'Bulk', 100.00, 'T.16.UD10030504', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 096', 'Lassana Flora', 'Bulk', 100.00, 'T.17.U010030029', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 097', 'Viyala Kumbura', 'Distribution', 100.00, 'T.08.U010030323', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 098', 'Nandana Hotel', 'Bulk & Distribution', 100.00, 'T.20.U025030144', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 099', 'Keppatipola Dairy Products', 'Bulk', 100.00, 'T.16.U010030276', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 100', 'Heritage Daries Lanka', 'Bulk', 100.00, 'T.17.010030170', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 101', 'Prime Land Moragolla', 'Distribution', 100.00, 'T.17.U010030208', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 102', 'AbayasiriI Metal Crusher', 'Bulk', 100.00, 'T.17.U010030090', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 103', 'Police Collage Hinnarangolla', 'Bulk', 160.00, 'T.17.UD16030077', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 104', 'Bogahakumbura School', 'Distribution', 100.00, 'T.18.U010030018', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 105', 'Aluthwaththa - Galahagama Rd', 'Distribution', 100.00, 'T.18.U.010030433', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 106', 'Gambedda', 'Distribution', 100.00, 'T.18.U010030477', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 107', 'Veewalahulawa', 'Distribution', 100.00, 'T.18.U010030485', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 108', 'Nedun Plant', 'Bulk', 100.00, 'T.18.U010030607', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 109', 'Seenimale', 'Distribution', 100.00, 'T.18.U0100303', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 110', '3rd Mile Post Boralanda Rd', 'Distribution', 100.00, 'T.19.U010030343', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 111', 'Wathugodawela Boralanda', 'Distribution', 100.00, 'T.18.U010030478', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 112', 'Bio Tech Boralanda', 'Bulk', 100.00, 'T.19.U010030366', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 113', 'Boralanda School', 'Distribution', 160.00, 'T.17.U016030051', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 114', 'Jagro Farm Martin Watta', 'Bulk & Distribution', 160.00, 'T.20U016030575', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 115', 'Swarnahansa School', 'Distribution', 100.00, 'T.20.U010030279', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 116', 'Wellawaththa', 'Distribution', 160.00, 'T.20.016030581', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 117', 'Habaragalawatta', 'Distribution', 100.00, 'T.22.U010030033', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 118', 'Onelta Real Estate', 'Distribution', 100.00, '91.8231', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 119', 'Welimada Post Office', 'Distribution', 160.00, 'T.18.U016030260', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 120', 'Pellivinna', 'Distribution', 100.00, 'T.19.U010030557', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 121', 'Welimada Pola', 'Bulk', 160.00, 'T.20.U016030581', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 122', 'Malikthenna', 'Distribution', 100.00, 'T.22.U010030157', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 123', 'Wakkadahinna', 'Distribution', 160.00, 'T.20.U016030564', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 124', 'Padinawela', 'Distribution', 100.00, 'T.19.U010030429', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 125', 'P.L.P Construction Udumulla', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 126', 'Court Complex Welimada', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 127', '6th Mile Post Guruthalawa', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 128', 'Seed Potato Farm Ohiya Road', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 129', 'Animal Farm- Boralanda', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 130', 'Damro Nugathalawa', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 131', 'Milton Shed- Keppetipola', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 132', 'Divithotawela Cemetery', 'Distribution', 160.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 133', 'Animal Farm- Boralanda -2', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(9, NULL, 'UDW 134', 'Keppetipola Shopping Complex', 'Distribution', 400.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Tokiyo Super (Batalayaya Denro)', 'Bulk (DPP)', 5000.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 048', 'UBM 048', 'Dehigolla Temple', 'Distribution', 250.00, 'T.11.u025030029', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 047', 'UBM 047', 'Habarawewa', 'Distribution', 160.00, 'T.17.u016030074', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM148', 'UBM148', 'Kovilyaya', 'Distribution', 100.00, 'T.11.u010030406', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 213', 'UBM 213', 'Darshana Metal Crusher', 'Bulk', 400.00, 'T.17.u040030005', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 046', 'UBM 046', 'Dehigolla New (Sunanda)', 'Distribution', 250.00, 'T.18.u025030413', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 045', 'UBM 045', 'C.T.B.', 'Distribution', 400.00, 'T.18.u040030054', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 042', 'UBM 042', 'Maliban Garment II', 'Bulk', 1000.00, 'T.12.u100030016', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 041', 'UBM 041', 'Maliban Garment I', 'Bulk', 1000.00, 'T.07.u10003009', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 199', 'UBM 199', 'New Town (Infront of the Samanala Hotel)', 'Bulk & Distribution', 400.00, 'T.16.u040030049', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 214', 'UBM 214', 'Cargllis Food City', 'Bulk', 100.00, 'T.17.u010030115', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 067', 'UBM 067', 'Water Bord Gamudawa', 'Distribution', 100.00, '7700', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 066', 'UBM 066', 'Gamudawa (AG Office)', 'Distribution', 250.00, '3374', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 044', 'UBM 044', 'Tile Factory', 'Bulk & Distribution', 500.00, '4715', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Meegahapitiya', 'Distribution', 100.00, 'T.18.U010030724', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 221', 'UBM 221', 'Sorabora Village', 'Bulk', 100.00, 'T.07.u010030240', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 068', 'UBM 068', 'Soraborawewa', 'Distribution', 250.00, 'T.17.u025030090', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 036', 'UBM 036', 'Police Mahiyanganaya', 'Distribution', 250.00, 'T.18.u025030191', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 039', 'UBM 039', 'Telecom (Old Wala)', 'Distribution', 250.00, 'T.01.u02503107', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 043', 'UBM 043', 'Gamudawa CO-Operative Shop', 'Bulk', 160.00, 'T.03.u01603301', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 038', 'UBM 038', 'President', 'Distribution', 160.00, 'T.16.u016030222', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 037', 'UBM 037', 'Gabo Apparel', 'Bulk', 250.00, 'T/91/3674', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 040', 'UBM 040', 'Telecom (Badulla)', 'Bulk', 50.00, '5240', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 217', 'UBM 217', 'Rideekotaliya', 'Distribution', 160.00, 'T.18.u016030058', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 031', 'UBM 031', 'Pooja Nagaraya I (Wala)', 'Distribution', 200.00, '33761-9', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 034', 'UBM 034', 'Infront Of Hospital (Mochariya)', 'Distribution', 250.00, '883385', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 033', 'UBM 033', 'Mahiyanganaya Hospital', 'Bulk', 1000.00, 'T.07.u100030029', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 029', 'UBM 029', 'Telecom poojanagaraya', 'Distribution', 250.00, 'T.18.u025030193', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 028', 'UBM 028', 'Nippon Rice Mill', 'Distribution', 100.00, 'T.99.u01003503', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 032', 'UBM 032', 'Saman Dewalaya', 'Distribution', 250.00, 'T.11.u025030097', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 035', 'UBM 035', 'Water Board', 'Bulk', 630.00, 'T.15.u.063030014', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 030', 'UBM 030', 'Elawela', 'Distribution', 100.00, 'T.99.u01003233', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 026', 'UBM 026', 'Dambarawa', 'Distribution', 160.00, 'T.14.u016030337', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 021', 'UBM 021', '20 Mile Post', 'Distribution', 250.00, 'T.17.u025030067', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 207', 'UBM 207', 'Rohana Junction', 'Distribution', 100.00, 'T.15.u010030300', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 182', 'UBM 182', 'A.A Holding', 'Bulk', 100.00, 'T.12.u010030509', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 153', 'UBM 153', 'Rohana Nagaraya Idiripita', 'Distribution', 100.00, 'T.11.u010030382', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 168', 'UBM 168', '8 Ela Agalawatta (Mapakadawewa)', 'Distribution', 100.00, 'T.16.u010030143', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 020', 'UBM 020', '19 Mile Post', 'Distribution', 160.00, 'T.92/13/765', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 176', 'UBM 176', 'Kudawewa (Dambagolla)', 'Distribution', 100.00, 'T.12.u010030161', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 162', 'UBM 162', 'Dambarawewa', 'Distribution', 100.00, 'T.08.u010030298', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 116', 'UBM 116', 'Idalgasyaya (Rabukyaya)', 'Distribution', 100.00, 'T.10.u010030465', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 159', 'UBM 159', 'Parakum Pedesa', 'Distribution', 100.00, 'T.01.u01003202', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 211', 'UBM 211', 'Dehigolla Milk Center', 'Distribution', 100.00, 'T.16.u010030253', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 049', 'UBM 049', 'Jayasanka Metal Crusher', 'Bulk', 160.00, 'T.05.u016030100', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 052', 'UBM 052', 'Laxiri Metal Crusher', 'Bulk', 160.00, 'T.07.u016030254', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 053', 'UBM 053', 'Jayalath Metal Crusher', 'Bulk', 160.00, 'T.09.u016030213', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 210', 'UBM 210', 'Nandana Metal Crusher', 'Bulk', 160.00, 'T.16.u016030120', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 050', 'UBM 050', 'Top Rock Metal Crusher', 'Bulk', 100.00, 'T.06.u010030026', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 051', 'UBM 051', 'Tom Rock Metal Crusher', 'Bulk', 630.00, 'T.21.u063030073', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(1, 'UBM 054', 'UBM 054', 'Serana', 'Distribution', 160.00, 'T.18.u016030092', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 124', 'UBM 124', 'Seranagama', 'Distribution', 100.00, 'T.10.u010030289', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 193', 'UBM 193', 'Serana Yaya 8 (Yaya 8 Ela Rd- Seranagama)', 'Distribution', 100.00, 'T.17.u010030065', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 156', 'UBM 156', 'Puwakgaswela', 'Distribution', 100.00, 'T.10.u010030558', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 055', 'UBM 055', '49 Mile Post', 'Distribution', 100.00, 'T.02.u01003051', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 056', 'UBM 056', 'Senevigama', 'Distribution', 160.00, 'T.12.u016030373', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 057', 'UBM 057', 'Senevigama Wewa', 'Distribution', 100.00, 'T.00.58R136', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 019', 'UBM 019', 'Gemunupura Junction', 'Distribution', 160.00, 'T.21.U016030795', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 017', 'UBM 017', 'Shadeline Garment 1', 'Bulk', 1000.00, 'T.07.u100030011', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 018', 'UBM 018', 'Shadeline Garment II', 'Bulk', 1000.00, 'T.07.u100030017', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 016', 'UBM 016', 'Abeypura', 'Distribution', 160.00, 'T.18.u016030473', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 015', 'UBM 015', 'Gamunupura 17 Ela', 'Distribution', 160.00, 'T.16.u016030338', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 126', 'UBM 126', 'Weheragalayaya', 'Distribution', 100.00, 'T.03.u01003245', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 125', 'UBM 125', 'Paranagama', 'Distribution', 160.00, 'T.10.u016030150', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 175', 'UBM 175', 'Nelligaswewa', 'Distribution', 100.00, '109729', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 058', 'UBM 058', '50th Mile post', 'Distribution', 160.00, 'T.10.u016030340', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 146', 'UBM 146', 'Welampala School', 'Distribution', 100.00, 'T.11.u010030320', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 144', 'UBM 144', 'Konkotanmulla', 'Distribution', 100.00, 'T.11.u010030266', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 151', 'UBM 151', 'Kuda Oya', 'Distribution', 100.00, 'T.11.u010030356', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 059', 'UBM 059', 'Welampala', 'Distribution', 100.00, 'T.15.u010030085', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 060', 'UBM 060', 'Keselpotha Yaya 12', 'Distribution', 250.00, 'T.18.U025030463', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 117', 'UBM 117', 'Warapitiya', 'Distribution', 100.00, 'T.10.u010030176', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 166', 'UBM 166', 'Gadaboyaya Junction', 'Distribution', 100.00, 'T.12.u010030067', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 167', 'UBM 167', 'Gadaboyaya Gama II', 'Distribution', 100.00, 'T.12.u010030035', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 169', 'UBM 169', 'Kolonbedda', 'Distribution', 100.00, 'T.12.u010030233', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 163', 'UBM 163', 'Ikiriyagoda', 'Distribution', 100.00, 'T.12.u010030019', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 164', 'UBM 164', 'Kolayaya', 'Distribution', 100.00, 'T.12.u010030022', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 136', 'UBM 136', 'Youth Society (Tharuna Viyaparaya)', 'Distribution', 100.00, 'T.11.u010030176', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 145', 'UBM 145', 'Kongas Junction', 'Distribution', 100.00, 'T.11.u010030454', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 149', 'UBM 149', 'Galthalawa', 'Distribution', 100.00, 'T.11.u010030462', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 181', 'UBM 181', 'DSI Rajarata Farm', 'Bulk', 250.00, 'T.12.u025030036', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 190', 'UBM 190', 'Dole Farm', 'Bulk', 400.00, 'T.10.u040030050', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 061', 'UBM 061', 'Beligalla', 'Distribution', 100.00, 'T.01.u01003345', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 062', 'UBM 062', 'Bimmalamulla', 'Distribution', 100.00, 'T.09.u010030430', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 198', 'UBM 198', '54 MP Galkada', 'Distribution', 100.00, '308062', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 119', 'UBM 119', 'Wathuyaya (Dambana)', 'Distribution', 100.00, 'T.09.u010030704', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 205', 'UBM 205', 'Bo Eta Yaya Bedda', 'Distribution', 100.00, '109779', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 120', 'UBM 120', 'Gurukumbura', 'Distribution', 100.00, 'T.09.u010030781', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 063', 'UBM 063', 'Dambana', 'Distribution', 100.00, 'T/98/u01003388', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 187', 'UBM 187', 'Godaporuyaya', 'Distribution', 100.00, '114813', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 186', 'UBM 186', 'Moraketiya', 'Distribution', 100.00, '308151', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 140', 'UBM 140', 'Kandubadda I', 'Distribution', 100.00, 'T.11.u010030037', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 141', 'UBM 141', 'Metihakka', 'Distribution', 100.00, 'T.11.u010030146', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 138', 'UBM 138', 'Imbulemulla', 'Distribution', 100.00, 'T.11.u010030103', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 139', 'UBM 139', 'Talawegama', 'Distribution', 100.00, 'T/99/u01003508', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 184', 'UBM 184', 'Kukulapola', 'Distribution', 100.00, 'T.11.u010030044', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 064', 'UBM 064', 'Wewaththa Dialog Tower', 'Distribution', 100.00, 'T.09.u010030051', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 065', 'UBM 065', 'Wewatta', 'Distribution', 100.00, 'T.19.u010030510', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 154', 'UBM 154', 'Kannalkumbura', 'Distribution', 100.00, 'T.10.u010030614', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 155', 'UBM 155', 'Katukumbura', 'Distribution', 100.00, 'T.15.u010030186', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 208', 'UBM 208', 'Embalawatta Village', 'Distribution', 100.00, '109813', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 197', 'UBM 197', 'Abalawatta', 'Distribution', 100.00, '109815', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 127', 'UBM 127', 'Koruppa', 'Distribution', 100.00, 'T.10.u010030556', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 128', 'UBM 128', 'Gurumada Gangeyaya', 'Distribution', 100.00, 'T.10.u010030543', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 069', 'UBM 069', 'Kapurugasmulla', 'Distribution', 100.00, 'T.02.u01003560', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 070', 'UBM 070', 'Thalagamuwa', 'Distribution', 100.00, 'T.19.u010030043', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 071', 'UBM 071', 'Haddathtawa', 'Distribution', 160.00, 'T.21.U016030782', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 161', 'UBM 161', 'Haddaththawa (Gangeyaya II)', 'Distribution', 100.00, 'T.12.u010030086', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 072', 'UBM 072', 'Nidahangala', 'Distribution', 160.00, 'T.22.u016030080', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 219', 'UBM 219', 'Kahaniyagoda Junction', 'Distribution', 100.00, 'T.18.u010030396', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 212', 'UBM 212', 'Mahamewna Asapuwa', 'Bulk', 100.00, 'T.16.u010030592', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 074', 'UBM 074', 'New Makulgolla (Bogaha Asala)', 'Distribution', 100.00, 'T.10.u010030030', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 075', 'UBM 075', 'Makulgolla (Kanaththa Asala)', 'Distribution', 100.00, '74325', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 123', 'UBM 123', 'Watawana School', 'Distribution', 100.00, 'T.10.u010030347', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 191', 'UBM 191', 'Nawarathn Metal Crusher', 'Bulk', 250.00, 'T.21.U025030091', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 122', 'UBM 122', 'Ambagaspattiya (Watawana I)', 'Distribution', 100.00, 'T.10.u010030537', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 076', 'UBM 076', 'Meegahahena', 'Distribution', 100.00, 'T.01.u01003214', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 077', 'UBM 077', 'Galporuyaya', 'Distribution', 100.00, 'T/97/1003078', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 137', 'UBM 137', 'Pahala Dematan Ella', 'Distribution', 100.00, 'T.10.u010030760', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 073', 'UBM 073', 'Akkara 80', 'Distribution', 100.00, 'T.18.u010030736', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 078', 'UBM 078', 'Bathalayaya - Mahaweli', 'Distribution', 250.00, 'T.18.u025030373', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 207', 'UBM 207', 'Barrier Junction', 'Distribution', 100.00, 'T.18.U010030481', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 206', 'UBM 206', 'Bandara Metal Crushers', 'Bulk', 630.00, 'T.17.u063030029', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 079', 'UBM 079', 'Aluthtarama Agri Farm', 'Bulk', 100.00, 'T.08.u010030226', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 080', 'UBM 080', 'C.T.C', 'Distribution', 160.00, 'T.20.U016030164', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 216', 'UBM 216', 'Devika Metal Crusher', 'Bulk', 250.00, 'T.17.u025030457', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 081', 'UBM 081', 'Viranagama', 'Distribution', 160.00, 'T.19.u016030679', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 082', 'UBM 082', 'Bathalayaya - Water Board', 'Distribution', 160.00, 'T.05.u016030028', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Ballavidda Wewa', 'Distribution', 100.00, 'T.19.U010030069', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 172', 'UBM 172', 'Bandara Metal Crusher', 'Bulk', 160.00, 'T.12.u016030488', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 083', 'UBM 083', 'Sunil Metal Crusher', 'Bulk', 160.00, 'T.17.u016030045', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 131', 'UBM 131', 'Kashanpitiya', 'Distribution', 100.00, 'T.10.u010030563', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 084', 'UBM 084', 'Giralagolla', 'Distribution', 100.00, 'T.18.U010030447', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 085', 'UBM 085', 'Hanguma', 'Distribution', 100.00, '114834', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 086', 'UBM 086', 'Millathtawa', 'Distribution', 100.00, 'T.03.u01003139', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 087', 'UBM 087', 'Methmalgama', 'Distribution', 100.00, 'T.09.u010030527', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 093', 'UBM 093', 'G/Kotte Telecom', 'Bulk', 100.00, 'T/95/1003096', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 215', 'UBM 215', 'Giradurukotte Hospital', 'Bulk', 100.00, 'T.16.u010030237', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 088', 'UBM 088', 'Giradurukotte Police', 'Distribution', 100.00, 'T.18.u010030109', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 189', 'UBM 189', 'Giradurukotta Water Board', 'Bulk', 100.00, '308167', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 089', 'UBM 089', 'Giradurukotta Tample', 'Distribution', 250.00, 'T.17.u025030111', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 173', 'UBM 173', 'Sathwa Govipala', 'Bulk', 50.00, '10428004', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 091', 'UBM 091', 'Agalaoya', 'Distribution', 100.00, 'T.16.u010030574', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 092', 'UBM 092', 'Ulhitiyagama Dam', 'Distribution', 100.00, 'T.10.u010030470', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 121', 'UBM 121', 'Diyawara Gammanaya', 'Distribution', 160.00, 'T.05.u016030151', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 090', 'UBM 090', 'Welangaspitiya', 'Distribution', 100.00, 'T.21.U010030450', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 220', 'UBM 220', 'Crusher Junction', 'Distribution', 100.00, '391193', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 200', 'UBM 200', 'Kohombagodayaya', 'Distribution', 100.00, 'T.06.u010030013', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 094', 'UBM 094', 'Karmanthapuraya G/Kotte', 'Distribution', 400.00, 'T.08.u04003079', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 095', 'UBM 095', 'Kandauda G/Kotte', 'Bulk & Distribution', 400.00, 'T.18.u040030002', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(1, 'UBM 150', 'UBM 150', 'Agalaoya Temple', 'Distribution', 100.00, 'T.11.u010030364', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 097', 'UBM 097', 'Jayanthipura', 'Distribution', 100.00, 'T.03.u01003142', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 099', 'UBM 099', 'Pahalarathkinda', 'Distribution', 100.00, 'E1063765', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 165', 'UBM 165', 'Kudawila (Rathkinda)', 'Distribution', 100.00, 'T.12.u010030063', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 192', 'UBM 192', 'Rathkinda Wanawagawa', 'Distribution', 100.00, '109739', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 194', 'UBM 194', 'Rathkida Wewa', 'Distribution', 100.00, '109787', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 222', 'UBM 222', 'D W Rice Mill (Danapala)', 'Bulk', 100.00, 'T.16.u010030564', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 096', 'UBM 096', 'Danidu Rice Mill', 'Bulk', 400.00, 'T.18.u040030169', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 100', 'UBM 100', 'Agriculture G/Kotte', 'Distribution', 100.00, 'T.03.u0100335', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 098', 'UBM 098', 'Hobariyawa', 'Distribution', 160.00, 'T.19.u016030141', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 101', 'UBM 101', 'Hobariyawa (Sumanarathne)', 'Distribution', 100.00, 'T.09.u010030166', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 103', 'UBM 103', 'Ulhitiyagama', 'Distribution', 100.00, 'T.17.u010030214', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 102', 'UBM 102', 'Belaganwewa', 'Distribution', 100.00, 'T.99.u01003448', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 104', 'UBM 104', 'Bogampitiya Junction (Budupilime Asala)', 'Distribution', 100.00, 'T.98.u01003359', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 105', 'UBM 105', 'Ginnoruwa', 'Distribution', 160.00, 'T.06.u016030242', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 160', 'UBM 160', 'Ginnoruwa Sarabhumi', 'Distribution', 100.00, 'T.11.u010030421', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 106', 'UBM 106', 'Elhenpitiya', 'Distribution', 100.00, '109809', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 107', 'UBM 107', 'Hebarawa', 'Distribution', 160.00, 'T.84.2653', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 108', 'UBM 108', 'Aluyatawewa', 'Distribution', 100.00, 'T.12.u010030191', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 210', 'UBM 210', 'Dikpitiya (Aluyatawela)', 'Distribution', 100.00, 'T.16.u010030259', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 109', 'UBM 109', 'Walasgala', 'Distribution', 100.00, 'T.16.u010030142', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 118', 'UBM 118', 'Rotalawela Uda Kotasa (Rotalawela II)', 'Distribution', 160.00, 'T.10.u016030148', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 110', 'UBM 110', 'Rotalawela School', 'Distribution', 160.00, 'T.12.u016030274', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 142', 'UBM 142', 'Rotalawela Nawa Gammanaya', 'Distribution', 100.00, 'T.11.u010030205', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 111', 'UBM 111', 'Diulapelessa', 'Distribution', 160.00, 'T.22.u016030094', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 143', 'UBM 143', 'Diulapelessa Dambana Kotasa', 'Distribution', 100.00, 'T.11.u010030344', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 112', 'UBM 112', 'Diulapelessa Udawewa', 'Distribution', 160.00, 'T.10.u016030164', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 113', 'UBM 113', 'Teldeniya School', 'Distribution', 100.00, 'T.11.u010030313', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 204', 'UBM 204', 'Bogampitiyagama', 'Distribution', 100.00, 'T.12.u010030313', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 114', 'UBM 114', 'Teldeniya Junction', 'Distribution', 100.00, '99/u/01003369', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, 'UBM 115', 'UBM 115', 'Ulhitiya Rice Mill Complex', 'Distribution', 400.00, 'T/93/3905', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Ulhitiya II (Pol Thawana)', 'Distribution', 100.00, 'T.18.U010030773', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, '21 Mile Post', 'Distribution', 100.00, 'T.19.u010030313', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, '18 Mile Post', 'Distribution', 100.00, 'T.16.u010030255', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Sunil Metal Crusher II Watawana', 'Bulk', 100.00, 'T.19.u010030483', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Akkara 50', 'Distribution', 100.00, 'T.20.U010030016', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, '45 Mile Post', 'Distribution', 160.00, 'T.16.U016030571', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Welimada yaya', 'Distribution', 100.00, 'T.20.U010030289', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Rotalawela gange Yaya', 'Distribution', 100.00, 'T.18.U010030709', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Diyawara Gammanaya Junction New', 'Distribution', 100.00, 'T.16.U010030112', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Lakbo metal crusher', 'Bulk', 400.00, 'T.18.U040030148', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Rainbo', 'Bulk', 100.00, 'T.21.u010030536', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Industrial Place Mahiyanganaya', 'Bulk', 250.00, 'T.21.U025030074', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Bandara Filling Station', 'Bulk', 100.00, 'T.22.U010030002', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'KHR De Silwa (Dambana)', 'Bulk', 250.00, 'T.22.U025030002', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Shopping Complex Mahiyangana', 'Distribution', 630.00, 'T.02.UD1003095', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, '51 Mile Post', 'Distribution', 160.00, 'T.21.u010030289', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Athula Farm', 'Bulk', 250.00, 'T.22.U025030049', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Civimech Farm', 'Bulk', 400.00, 'T.18.U040030167', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Water Board Ulhitiya Intake', 'Bulk', 250.00, 'T.22.U025030057', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Senanigama', 'Distribution', 160.00, 'T.21.u016030461', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Divisional Secretariat Building Mahiyangana', 'Bulk', 250.00, 'T.14.O025030100', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Mahiyanganaya Hospital OPD', 'Bulk', 400.00, 'T.18.u040030182', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Thekkawetiya Hobariyawa', 'Distribution', 100.00, 'T/22/u016030270', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Arawaththa', 'Distribution', 250.00, 'T.21.u010030369', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Mahiyangana Town Clock Tower', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'UVA Solar', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Aluththarama', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Ceylon Eco Spices', 'Bulk', 160.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(1, NULL, NULL, 'Kiulathalawa', 'Distribution', 160.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 085', 'UDB 085', 'Chelsy', 'Bulk & Distribution', 160.00, 'T/17/U016030023', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 086', 'UDB 086', 'Dambagolla', 'Distribution', 100.00, 'T/03/U01003296', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 147', 'UDB 147', 'Dambagolla Saif Estate', 'Bulk', 800.00, 'T/14/U080030005', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 087', 'UDB 087', 'Piyarapandowa', 'Distribution', 100.00, 'T/99/U01009480', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 089', 'UDB 089', 'Halpe Watta', 'Bulk & Distribution', 160.00, 'T/03/U06303014', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 088', 'UDB 088', 'Millagama', 'Distribution', 100.00, 'T/12/U016030502', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 090', 'UDB 090', 'Hettipola Watte', 'Bulk', 100.00, 'T/94/1003268', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 159', 'UDB 159', 'Kumbalwela Asapuwa', 'Distribution', 100.00, 'T/17/U010030202', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 091', 'UDB 091', 'Kumbalwela', 'Distribution', 250.00, 'T/04/U25030128', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 092', 'UDB 092', 'Dowa', 'Distribution', 100.00, 'T/94/U01003505', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 093', 'UDB 093', 'Halpe', 'Distribution', 160.00, 'T/21/U025030186', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 135', 'UDB 135', 'Millagama Water Project', 'Distribution', 100.00, 'T/15/U010030271', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 152', 'UDB 152', 'Demodara Metal Crusher New', 'Bulk', 100.00, 'T/19/U010030087', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 094', 'UDB 094', 'Kinalan Estate', 'Bulk & Distribution', 250.00, NULL, 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 099', 'UDB 099', 'Kitalella Dialog', 'Distribution', 100.00, 'T/11/U025030022', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 150', 'UDB 150', 'Kital Ella Temple', 'Distribution', 160.00, 'T/18/U040030131', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 100', 'UDB 100', 'Pahala Ella', 'Distribution', 100.00, 'T/18/U040030117', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 101', 'UDB 101', 'Kitalella', 'Distribution', 400.00, 'T/18/U040030130', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 102', 'UDB 102', 'Makulella Kurudugolla', 'Distribution', 100.00, 'T/18/U010030332', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 103', 'UDB 103', 'Heeloya Boralanda', 'Distribution', 160.00, 'T/18/U016030812', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Uva Dikkarawatta', 'Distribution', 100.00, 'T/18/U010030717', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 137', 'UDB 137', 'Ampitiya junction', 'Distribution', 160.00, 'T/16/U16030034', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 105', 'UDB 105', 'Kande Arawa', 'Distribution', 160.00, 'T/18/U016030719', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 106', 'UDB 106', 'Makulella Medapathana', 'Distribution', 100.00, 'T/00/U01003421', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 104', 'UDB 104', 'Heeloya', 'Distribution', 100.00, 'T/21/U016030459', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 115', 'UDB 115', 'Ambadandegama', 'Distribution', 160.00, 'T/16/U016030569', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 116', 'UDB 116', 'Laksirigama', 'Distribution', 250.00, 'T/14/U25030091', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 107', 'UDB 107', 'Rawana Ella', 'Distribution', 100.00, 'T/02/U1003546', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 108', 'UDB 108', 'Karandagolla', 'Distribution', 160.00, 'T/11/U010030432', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 154', 'UDB 154', 'Ella Jungle Resort', 'Bulk', 100.00, 'T/17U010030069', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 165', 'UDB 165', 'Perera & Sons Hotel', 'Bulk', 250.00, 'T/14/U025030105', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 144', 'UDB 144', 'Sadinnawela', 'Distribution', 100.00, 'T/16/U010030589', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 110', 'UDB 110', 'Karadagolla Uma Oya Housing Scheme I', 'Bulk', 400.00, 'T/12/U040030031', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 111', 'UDB 111', 'Karadagolla Uma Oya Housing Scheme II (Substation has been Removed)', 'Bulk', 100.00, NULL, 1, 11, 'Source sheet records this unit as removed (quantity 0).', 'RETIRED', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Uma Oya Tunnel', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 109', 'UDB 109', 'Hunuketiya', 'Distribution', 100.00, 'T/4524', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 114', 'UDB 114', 'Karandagolla Kurugama', 'Distribution', 100.00, '109777', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 112', 'UDB 112', 'Mat Office', 'Bulk', 400.00, 'T/12/U040030090', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 113', 'UDB 113', 'Ella AGA Office-New II', 'Distribution', 160.00, 'T/18/U016030481', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 134', 'UDB 134', 'Ella AGA Office', 'Distribution', 250.00, 'T/18/U025030149', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(11, 'UDB 163', 'UDB 163', 'Ella Grand View Hotel', 'Bulk', 400.00, 'T/18/U040030118', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 096', 'UDB 096', 'Ella Town', 'Distribution', 400.00, 'T/18/U040030193', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 161', 'UDB 161', 'Ella Grand Hotel', 'Bulk', 100.00, 'T/18/U010030474', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 162', 'UDB 162', 'Ella Katharagama Dewalaye', 'Distribution', 400.00, 'T/18/U040030129', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 155', 'UDB 155', 'Ella Police', 'Distribution', 160.00, 'T/18/U025030368', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 171', 'UDB 171', 'Ella Pradeshiya Sabhawa', 'Distribution', 100.00, 'T/18/U016030333', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 097', 'UDB 097', 'Southerland', 'Distribution', 160.00, 'T/18/U040030076', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 149', 'UDB 149', '98 Acress Resort Hotel', 'Bulk', 250.00, 'T/16/U010030525', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 098', 'UDB 098', 'Newburg', 'Bulk & Distribution', 250.00, '9885711', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 102', 'UBP 102', 'Gowussa', 'Distribution', 100.00, '99/T/U01003150', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 100', 'UBP 100', 'Ballaketuwa', 'Distribution', 100.00, 'T/20/U16030568', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 101', 'UBP 101', 'Kandekumbura', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 097', 'UBP 097', 'Nawelagama I (Maussawa)', 'Distribution', 100.00, 'T/16/U016030544', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 098', 'UBP 098', 'Nawelagama II (Near Temple)', 'Distribution', 100.00, 'T/98/01003204', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 099', 'UBP 099', 'Hindagala', 'Bulk & Distribution', 400.00, '591510', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 095', 'UBP 095', 'Telecom Namunukula', 'Bulk & Distribution', 160.00, 'T/99/U01009365', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 096', 'UBP 096', 'CV 2', 'Distribution', 100.00, 'T/09/U010030167', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 090', 'UBP 090', 'Tonacombe Hospital', 'Bulk & Distribution', 100.00, NULL, 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 091', 'UBP 091', 'Tonacom Factory / Thanne Kumbura', 'Bulk & Distribution', 300.00, '19910', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 094', 'UBP 094', 'Kalugala State', 'Distribution', 150.00, 'THE36/150', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 092', 'UBP 092', 'Dodamgolla', 'Distribution', 100.00, 'T/04/U010030370', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 093', 'UBP 093', 'Ilukpalassa', 'Distribution', 100.00, 'T/06/U010030235', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 089', 'UBP 089', 'Pinarawa', 'Bulk & Distribution', 160.00, '31498', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 095', 'UDB 095', 'Gotuwala', 'Distribution', 160.00, 'T/18/U016030055', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 146', 'UDB 146', 'Gotuwela Water Project', 'Bulk', 250.00, 'T/99/U02503348', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBH 076', 'UBH 076', 'Baddewela', 'Distribution', 100.00, 'T/06/U10030182', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBH 077', 'UBH 077', 'Gawarakele', 'Bulk & Distribution', 100.00, 'JNE/104/9', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 076', 'UBP 076', 'Helapupula', 'Distribution', 100.00, '7961', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 075', 'UBP 075', 'Galtenhena', 'Distribution', 100.00, 'T/99/U01003220', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 077', 'UBP 077', 'Nahawilawaththa Estate', 'Distribution', 100.00, 'T/19/U10030348', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UBP 135', 'UBP 135', 'CVE', 'Distribution', 100.00, 'T/17/U/010030129', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 172', 'UDB 172', 'Gotuwala Madhuragama', 'Distribution', 100.00, 'T/19/U010030213', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, 'UDB 173', 'UDB 173', 'Amba Estate', 'Distribution', 100.00, 'T/97/1003159', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Pool Club Hotel', 'Bulk', 400.00, 'T/14/U/040030015', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Ella Water stone', 'Bulk', 250.00, 'T/21/U025030175', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'On Rock', 'Bulk', 100.00, 'T/22/U010030232', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Rathnagiri Estate', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Nature First', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, '3rd Mile Post', 'Distribution', 160.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Weedagama Metal Crusher', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Flower Garden', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Rajakotuwa', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Southerland New', 'Bulk', 400.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Cargills', 'Bulk', 160.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Alloff Brand [BIVO Investment (PVT) LTD]', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(11, NULL, NULL, 'Tea Dalu', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 010', 'UBM 010', 'P.T.S', 'Bulk & Distribution', 250.00, 'T11U025030080', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 011', 'UBM 011', 'Dikkandayaya', 'Distribution', 160.00, 'T.15.U016030152', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 180', 'UBM 180', 'Tissapura Temple', 'Distribution', 100.00, 'T11U010030770', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 203', 'UBM 203', 'Thissapura Yaya 3', 'Distribution', 100.00, 'T12U010030460', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 012', 'UBM 012', 'Thissapura School', 'Distribution', 250.00, 'T12U025030026', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 014', 'UBM 014', 'Keselpotha yaya 11', 'Distribution', 160.00, 'T97U01003355', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 013', 'UBM 013', 'Gamakumbura', 'Distribution', 100.00, 'T.04.U010030402', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 183', 'UBM 183', 'Thissapura Yaya I (Gamakumbura Dakuna)', 'Distribution', 100.00, '109793', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 185', 'UBM 185', 'Nagadeepa (Hirassagoda)', 'Distribution', 100.00, '308095', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 129', 'UBM 129', 'Aluketiyawa I Junction', 'Distribution', 100.00, 'T10U010030430', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 218', 'UBM 218', 'Kuralewela', 'Distribution', 100.00, 'T18U010030032', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 130', 'UBM 130', 'Alhenthalawa', 'Distribution', 100.00, 'T10U010030787', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 132', 'UBM 132', 'Wak Arawa', 'Distribution', 100.00, 'T10U010030683', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 133', 'UBM 133', 'Aluketiya (Eldeniya)', 'Distribution', 100.00, 'T10U010030665', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 009', 'UBM 009', '16MP Mahaweli', 'Distribution', 160.00, 'T15U016030186', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 157', 'UBM 157', 'Kirimatiya 15MP', 'Distribution', 100.00, 'T11U010030362', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 179', 'UBM 179', 'Galahitiyawa', 'Distribution', 100.00, '308207', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 008', 'UBM 008', 'Andaulpotha Junction', 'Distribution', 160.00, 'T16U016030253', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 170', 'UBM 170', 'Pahala Batuyaya', 'Distribution', 100.00, 'T11U010030225', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 196', 'UBM 196', 'Galeyaya', 'Distribution', 100.00, '109761', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 118', 'UMB 118', 'Welanketiya', 'Distribution', 100.00, 'T12U010030403', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 075', 'UMB 075', 'Uraniya', 'Distribution', 100.00, 'T09U010030713', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 171', 'UMB 171', 'Uraniya Junction New', 'Distribution', 100.00, 'T18U010030490', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Uraniya Hospital', 'Bulk', 100.00, 'T19U010030068', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 096', 'UMB 096', 'Mahapitiya', 'Distribution', 100.00, 'T11U010030118', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 072', 'UMB 072', 'Nagadeepa', 'Distribution', 100.00, 'T09U010030170', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 057', 'UMB 057', 'Rideemaliyadda 10th Mile Post', 'Distribution', 160.00, 'T05U016030142', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 104', 'UMB 104', 'Kotagamwella', 'Distribution', 100.00, 'T12U010030256', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 070', 'UMB 070', 'Rideemaliyadda 9th Mile Post', 'Distribution', 160.00, 'T12U016030136', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 098', 'UMB 098', 'Yakahalpotha', 'Distribution', 160.00, 'T12U010030012', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 056', 'UMB 056', 'Rideemaliyadda 8th Mile Post', 'Distribution', 100.00, 'T00U01003093', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 060', 'UMB 060', 'Kanugolla', 'Distribution', 100.00, '74564', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 077', 'UMB 077', 'Kandegama', 'Distribution', 100.00, 'T10U010030175', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 123', 'UMB 123', 'Dunukewela', 'Distribution', 100.00, '308081', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 065', 'UMB 065', 'Hapola (Periyapelessa)', 'Distribution', 100.00, 'T.08.U.010030356', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 053', 'UMB 053', 'Peragaspitiya', 'Distribution', 160.00, 'T18U016030678', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 054', 'UMB 054', 'Mallahawa', 'Distribution', 160.00, 'T18U016030690', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 068', 'UMB 068', 'LIihiniyalanda (Sandasirigama)', 'Distribution', 100.00, 'T08U010030094', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 083', 'UMB 083', 'Inipaduregoda', 'Distribution', 100.00, 'T22U010030049', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 055', 'UMB 055', 'Kotagama', 'Distribution', 100.00, 'T22U010030049', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 081', 'UMB 081', 'Butarawa', 'Distribution', 100.00, 'T10U010030088', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 048', 'UMB 048', 'Diyakobala', 'Distribution', 160.00, 'T10U016030209', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 107', 'UMB 107', 'Pilaketiya', 'Distribution', 100.00, 'T12U010030508', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 051', 'UMB 051', 'Pethiyagoda', 'Distribution', 100.00, 'T02U01003362', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 122', 'UMB 122', 'Nellipalaketiya', 'Distribution', 100.00, '109762', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 112', 'UMB 112', 'Kinihiriwella', 'Distribution', 100.00, 'T12U010030341', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 052', 'UMB 052', 'Yalwela', 'Distribution', 100.00, '308277', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 119', 'UMB 119', 'Neluwa', 'Distribution', 100.00, '808277', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 106', 'UMB 106', 'Unampitiya', 'Distribution', 100.00, 'T12U010030253', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 113', 'UMB 113', 'Bakinidadugolla', 'Distribution', 100.00, 'T12U10030336', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 109', 'UMB 109', 'Helagama Kudalunuka', 'Distribution', 100.00, 'T12U01003032', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 059', 'UMB 059', 'Kudalunuka', 'Distribution', 100.00, '74467', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 088', 'UMB 088', 'Morana', 'Distribution', 100.00, 'T10U01003613', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 092', 'UMB 092', 'Dikwela / Bohitiyawa', 'Distribution', 100.00, 'T10U01003026', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(2, 'UMB 091', 'UMB 091', 'Polwagawa', 'Distribution', 100.00, 'T10U010030505', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 049', 'UMB 049', 'Galbokka', 'Distribution', 100.00, 'T02U01003184', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 094', 'UMB 094', 'Yal Arawa', 'Distribution', 100.00, 'T10U010030824', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 090', 'UMB 090', 'Bulugahalinda', 'Distribution', 100.00, 'T11U01003114', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 050', 'UMB 050', 'Dehigama I', 'Distribution', 100.00, 'T03U01003109', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 086', 'UMB 086', 'Serupitiya I', 'Distribution', 100.00, 'T10U010030595', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 087', 'UMB 087', 'Serupitiya II', 'Distribution', 100.00, 'T10U010030676', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 089', 'UMB 089', 'Dehigama II', 'Distribution', 100.00, 'T10U010030694', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 164', 'UMB 164', 'Mirehana', 'Distribution', 100.00, '114794', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 108', 'UMB 108', 'Edagala', 'Distribution', 100.00, 'T12U010030450', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 041', 'UMB 041', 'Akiriyankumbura', 'Distribution', 100.00, 'T03U01003175', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 115', 'UMB 115', 'Kandiya Arawa', 'Distribution', 100.00, 'T97/01003296', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 114', 'UMB 114', 'Kadapalla', 'Distribution', 100.00, 'T12U010030539', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 111', 'UMB 111', 'Kalugahakolaya', 'Distribution', 100.00, 'T12U010030548', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 080', 'UMB 080', 'Dankumbura', 'Distribution', 100.00, 'T10U010030079', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 042', 'UMB 042', 'Aralupitiya', 'Distribution', 100.00, '74495', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 134', 'UBM 134', 'Damunuketiya', 'Distribution', 100.00, 'T11U010030056', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 147', 'UBM 147', 'Wadiyagama Bubula', 'Distribution', 100.00, 'T11U010030461', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 209', 'UBM 209', 'CBL Agro', 'Bulk', 250.00, 'T12U025030215', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 007', 'UBM 007', 'Kuruvithenna', 'Distribution', 100.00, 'T11U010030043', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 188', 'UBM 188', 'Rathmalketiya (Beeralinda)', 'Distribution', 100.00, '109732', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 006', 'UBM 006', 'Dambagahapitiya', 'Distribution', 100.00, 'T09U010030097', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 195', 'UBM 195', 'Thambagoda Uduyaya', 'Distribution', 100.00, '109782', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 171', 'UBM 171', 'Weeragolla', 'Distribution', 100.00, 'T12U010030099', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 005', 'UBM 005', 'Pinnagolla', 'Distribution', 100.00, 'T10U010030024', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 152', 'UBM 152', 'Galgodayaya', 'Distribution', 100.00, 'T11U010030188', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 002', 'UBM 002', 'Mahagama School', 'Distribution', 100.00, '74627', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 178', 'UBM 178', 'Udoova Mahagama', 'Distribution', 100.00, 'T12U010030458', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 003', 'UBM 003', 'Baladangolla', 'Distribution', 100.00, 'T08U010030519', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 004', 'UBM 004', 'Urakote', 'Distribution', 100.00, 'T08U010030114', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UMB 099', 'UMB 099', 'Ritigaha Arawa', 'Distribution', 100.00, 'T11U010030263', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 001', 'UBM 001', 'Dikyaya', 'Distribution', 100.00, '74497', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, 'UBM 201', 'UBM 201', 'Gurupanwela Kohana', 'Distribution', 100.00, '109758', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Morana (Lihiniyaya)', 'Distribution', 100.00, 'T17U010030140', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Hapola New', 'Distribution', 100.00, 'T18U010030148', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Kandyan eye green product', 'Bulk', 100.00, 'T/98/U01003386', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Nimal Metal Crusher', 'Bulk', 160.00, 'T17U016030023', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Diriyagama', 'Distribution', 100.00, 'T04U010030277', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Morana New', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Dikkendayaya II', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Weeragolla II', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Bubula', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Gaduguduwawa', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Malheewa New', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'VJ Bulding', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(2, NULL, NULL, 'Karagahawela ( New )', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Loggal Oya Bio Mas', 'Bulk (DPP)', 2000.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Badulu Oya MHP', 'Bulk (MHP)', 5800.00, NULL, 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Loggal oya MHP', 'Bulk (MHP)', 1350.00, NULL, 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 019', 'UBB 019', '10th Maile post ( Thaldena)', 'Distribution', 250.00, 'T12U025030078', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 127', 'UBB 127', 'Thaldena Kohana', 'Distribution', 100.00, 'T15U010030264', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 020', 'UBB 020', 'Makulugolla -Meegahakiula', 'Distribution', 100.00, '114702', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 021', 'UBB 021', 'Keselwaththa', 'Distribution', 100.00, 'T16U010030477', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 022', 'UBB 022', 'Komarika', 'Distribution', 100.00, 'T01U01003340', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 023', 'UBB 023', 'Ketawaththa', 'Distribution', 160.00, 'T17U016030129', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 134', 'UBB 134', 'Bogahapathana', 'Distribution', 100.00, 'T16U010030240', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 133', 'UBB 133', 'Meegolla', 'Distribution', 100.00, 'T16U010030064', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 024', 'UBB 024', 'Wendesiyaya', 'Distribution', 100.00, 'T10U010030791', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 123', 'UBB 123', 'Siyambalagaslanda', 'Distribution', 100.00, '114725', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 025', 'UBB 025', 'Kalugahakadura', 'Distribution', 100.00, '114726', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 124', 'UBB 124', 'El Landa', 'Distribution', 100.00, '114698', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 126', 'UBB 126', 'Polwatta', 'Distribution', 100.00, '114837', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 135', 'UBB 135', 'Wewa Thenna', 'Distribution', 100.00, 'T15U010030154', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 026', 'UBB 026', 'Meegaha Kiula Town', 'Distribution', 160.00, 'T14U016030133', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 027', 'UBB 027', 'Aggala Ulpatha', 'Distribution', 100.00, 'T03U01003329', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 028', 'UBB 028', 'Athuruela', 'Distribution', 100.00, 'T10U10030621', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 029', 'UBB 029', 'Godayagama', 'Distribution', 100.00, '74429', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 030', 'UBB 030', 'Karadagahamada', 'Distribution', 100.00, 'T16U010030233', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 117', 'UBB 117', 'Kirigalalanda Karadagahada', 'Distribution', 100.00, '308069', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Arawa New', 'Distribution', 100.00, 'T18U010030625', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 031', 'UBB 031', 'Polgaha Arawa', 'Distribution', 100.00, 'T99U01003613', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBB 032', 'UBB 032', 'Mahiyangana Road -16th Mile Post', 'Distribution', 160.00, 'T17U016030116', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 108', 'UBH 108', 'Kathik Engineering Finalized Account (Substation has been Removed)', 'Bulk', 100.00, NULL, 1, 11, 'Source sheet records this unit as removed (quantity 0).', 'RETIRED', 'transformer_asset_management.sql'),
(3, 'UBH 114', 'UBH 114', 'Vihara Landa', 'Distribution', 100.00, '114738', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 082', 'UBH 082', 'Balagolla', 'Distribution', 160.00, '9213767', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 083', 'UBH 083', 'RDA', 'Bulk', 250.00, 'T10U025030024', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Maliban Texttile 1', 'Bulk', 100.00, 'T10U010030567', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 121', 'UBH 121', 'Maliban Textile II', 'Bulk (HT)', 2000.00, 'A9739', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 125', 'UBH 125', 'Jayasiri Rice Mill', 'Bulk & Distribution', 160.00, 'T18U010030003', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 084', 'UBH 084', 'Karametiya', 'Distribution', 160.00, 'T15U016030124', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 107', 'UBH 107', 'Wooling Lanka', 'Bulk (HT)', 2400.00, 'T10U040030023', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, '21 Mile Post', 'Distribution', 100.00, 'T20U010030250', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 111', 'UBH 111', 'Gigiripudama', 'Distribution', 160.00, 'T20U0160302787', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 085', 'UBH 085', 'Bubula', 'Distribution', 100.00, 'T06U010030135', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 086', 'UBH 086', 'Kadapoththawa', 'Distribution', 160.00, 'T13U016030123', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 087', 'UBH 087', 'Badulu oya', 'Distribution', 160.00, '18U0160030395', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 088', 'UBH 088', 'Kandaketiya Town', 'Distribution', 250.00, 'T22U025030014', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 089', 'UBH 089', 'Kandeketiya Telecom', 'Distribution', 100.00, 'T08U010030516', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 090', 'UBH 090', 'Welaoya', 'Distribution', 100.00, 'T99U01003218', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 091', 'UBH 091', 'Mahakele', 'Distribution', 100.00, 'T07U010030229', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 093', 'UBH 093', 'Buddankotte', 'Distribution', 100.00, 'T16U010030060', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 092', 'UBH 092', 'Minipe', 'Bulk & Distribution', 100.00, 'T928436', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 095', 'UBH 095', 'Ulpotha', 'Distribution', 100.00, 'T22U010030213', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, '24 Mile Post', 'Distribution', 100.00, '99U01003398', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 094', 'UBH 094', 'Wallewela Thenna', 'Distribution', 100.00, 'T06U010030162', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 096', 'UBH 096', 'Kiriwehera', 'Distribution', 100.00, 'T09U010030222', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 109', 'UBH 109', 'Maladumgolla', 'Distribution', 100.00, '114820', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 106', 'UBH 106', 'Karakole', 'Distribution', 100.00, 'T11U0010030200', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 097', 'UBH 097', 'Maliyadda', 'Distribution', 100.00, 'T11U010030014', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 116', 'UBH 116', 'Narangasthenna', 'Distribution', 100.00, '1109737', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(3, 'UBH 098', 'UBH 098', 'Thalagahakumbura', 'Distribution', 100.00, 'T11U010030115', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 099', 'UBH 099', 'Pallewela', 'Distribution', 100.00, 'T94010030502', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 100', 'UBH 100', 'Mudagamuwa', 'Distribution', 100.00, 'T18U010030107', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 104', 'UBH 104', 'Bathmedilla', 'Distribution', 160.00, 'T014U016030349', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 031', 'UBH 031', 'Hapathgamuwa', 'Distribution', 100.00, 'T05U010030126', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 029', 'UBH 029', 'Wasanagama', 'Distribution', 100.00, 'T971003160', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 030', 'UBH 030', 'Thunnewa', 'Distribution', 100.00, 'T10U010030089', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 028', 'UBH 028', 'Godunna', 'Distribution', 100.00, 'Not Clear', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 027', 'UBH 027', 'Beramada', 'Distribution', 100.00, 'T03U01003305', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 026', 'UBH 026', 'Galauda', 'Distribution', 160.00, 'T18U016030101', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 025', 'UBH 025', 'Labugasthalawa', 'Distribution', 100.00, 'T10U010040226', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 016', 'UBH 016', 'Bopitiya', 'Distribution', 100.00, '74408', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBH 110', 'UBH 110', 'Lindahena', 'Distribution', 100.00, '114799', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBM 022', 'UBM 022', 'Pagaragammana', 'Distribution', 160.00, 'T19U016030180', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBM 023', 'UBM 023', 'Dabagolla', 'Distribution', 100.00, '74563', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBM 174', 'UBM 174', 'Alikadura', 'Distribution', 100.00, 'T12U010030330', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBM 024', 'UBM 024', 'Medaoya', 'Distribution', 100.00, 'T00U01003423', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBM 135', 'UBM 135', 'Weerasekara Metal Crusher', 'Bulk', 400.00, 'T19U040030028', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBM 177', 'UBM 177', 'Pideniyapitiya', 'Distribution', 100.00, 'T012U010030544', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBM 202', 'UBM 202', 'Sun Building Industries', 'Bulk', 630.00, 'T10U063030028', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, 'UBM 025', 'UBM 025', 'Punagawewa', 'Distribution', 100.00, 'T09U010030176', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'New Liyangaha Arawa Metal Crusher', 'Bulk', 400.00, 'T19U040030006', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Mudagamuwa New', 'Distribution', 100.00, 'T18U010030756', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Loggal Oya Wood Chipper', 'Bulk', 630.00, 'T18U063030060', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Karametiya Dialog', 'Distribution', 100.00, 'T16U010030540', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Danidu Complex', 'Bulk & Distribution', 250.00, 'T18U025030296', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Karametiya New', 'Distribution', 100.00, 'T03U01003129', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Thalpitigala Resovior Project', 'Bulk', 100.00, 'T21U010030435', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Farmac International', 'Bulk', 160.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Nimsara Metal Crusher', 'Bulk', 1000.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Kandaketiya Pradeshiya Saba', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Disanayake Solar', 'Bulk', 630.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Helapitiya', 'Bulk & Distribution', 100.00, NULL, 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(3, NULL, NULL, 'Unapite Pvt (Ltd) Solar', 'Bulk', 630.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 302', 'UMM 302', 'Weliyaya II (Near the filling station)', 'Distribution', 100.00, 'T.06.U010030309', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 152', 'UMM 152', 'Kalulandayaya', 'Distribution', 100.00, 'T.10.U010030447', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 071', 'UMM 071', 'Batugammana', 'Distribution', 160.00, 'T.18.U0.16030422', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 072', 'UMM 072', 'Kotigalhela', 'Distribution', 100.00, 'T.00.U0.1003422', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 157', 'UMM 157', 'Miyanawaththa', 'Distribution', 100.00, 'T.10.U010030732', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 073', 'UMM 073', 'Weliyaya (Walanda)', 'Distribution', 160.00, 'T.14.U016030359', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 074', 'UMM 074', 'Therela', 'Distribution', 160.00, 'T.18.U016030251', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 221', 'UMM 221', 'Iluklanda Boragoda', 'Distribution', 100.00, 'T.10.U010030427', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 116', 'UMM 116', 'Bolgalla Araluwinna', 'Distribution', 100.00, '1006R.136', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 101', 'UMM 101', 'Obbegoda (Ellekona)', 'Distribution', 160.00, 'T.18.U016030100', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 149', 'UMM 149', 'Gonathalawa', 'Distribution', 100.00, 'T.10.U010030169', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 125', 'UMM 125', 'Pump House of Pitamulla (Piyarathana school)', 'Distribution', 100.00, 'T.08.U01003088', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 135', 'UMM 135', 'Galbokka', 'Distribution', 160.00, 'T.12.U016030067', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 181', 'UMM 181', 'Udumulla', 'Distribution', 100.00, '308229', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 102', 'UMM 102', 'Dambagalla I (Near the police station)', 'Distribution', 160.00, 'T.U01600266', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 303', 'UMM 303', 'Dambagalla II (Near the Govijana sewa office)', 'Distribution', 100.00, 'T.7.U030046', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 223', 'UMM 223', 'Surathura Kalugaha arawa', 'Bulk', 100.00, '114797', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 253', 'UMM 253', 'Alpitiya Elhena', 'Distribution', 100.00, '114840', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 218', 'UMM 218', 'Watawanagama Jambugaslanda', 'Distribution', 100.00, '114765', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 134', 'UMM 134', 'Kottagala I', 'Distribution', 100.00, 'T.09.U10030178', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 144', 'UMM 144', 'Kottagala Godana', 'Distribution', 100.00, 'T.09.U010030797', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 162', 'UMM 162', 'Kottagala III (Kossalpola)', 'Distribution', 100.00, 'T.10.U010030376', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 106', 'UMM 106', 'Meegahapitiya', 'Distribution', 100.00, '109768', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 240', 'UMM 240', 'Puwakgoda', 'Distribution', 100.00, '114777', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 299', 'UMM 299', 'Yakiniwewa Wewpitiya', 'Distribution', 100.00, 'T.15.U010030059', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 107', 'UMM 107', 'Ihawa Gangodagama', 'Distribution', 100.00, 'T.03.U01003150', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 216', 'UMM 216', 'Meeyagala', 'Distribution', 100.00, 'T.109725', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 298', 'UMM 298', 'Meeyagala II (Galge kotuwa)', 'Distribution', 100.00, 'T.16.U010030303', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 272', 'UMM 272', 'Kiriwelgoda', 'Distribution', 100.00, '1189322', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 108', 'UMM 108', 'Kolladeniya', 'Distribution', 100.00, 'T.22.U010030065', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 145', 'UMM 145', 'Kolladeniya Gangoda Arawa', 'Distribution', 100.00, 'T.09.U010030791', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 209', 'UMM 209', 'Perapitiya', 'Distribution', 100.00, '109767', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 109', 'UMM 109', 'Mari Arawa', 'Distribution', 100.00, 'T02.U0.1003325', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 165', 'UMM 165', 'Madiyagolla Alayaya', 'Distribution', 100.00, 'T.11.U010030175', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 117', 'UMM 117', 'Polgahagama', 'Distribution', 100.00, '74357', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 238', 'UMM 238', 'Alugalge I (Alugalge Village)', 'Distribution', 100.00, '114808', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 234', 'UMM 234', 'Alugalge II (Galkotuwa)', 'Distribution', 160.00, 'T.14.U016030048', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 139', 'UMM 139', 'Medabedda', 'Distribution', 100.00, 'T.09.U010030501', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 120', 'UMM 120', 'Nagahamada', 'Distribution', 100.00, 'T.08.U010030179', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 103', 'UMM 103', 'Namaloya Janapadaya', 'Distribution', 100.00, 'T.05.U010030051', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 191', 'UMM 191', 'Alumada', 'Distribution', 100.00, 'T.12.U010030114', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 191', 'UMM 191', 'Ruwalwela', 'Distribution', 100.00, 'T.12.U010030144', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 189', 'UMM 189', 'Koratiya Thambana II', 'Distribution', 100.00, 'T.12.U010030255', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 188', 'UMM 188', 'Thambana Panguwa', 'Distribution', 100.00, 'T.10.U010030570', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 226', 'UMM 226', 'Thambana III (Hewanpitiya)', 'Distribution', 100.00, 'T.12.U010030550', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 231', 'UMM 231', 'Thabana IV Iluk Arawa', 'Distribution', 100.00, '114716', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 235', 'UMM 235', 'Thambana V (Urumuththewa)', 'Distribution', 100.00, '114732', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 180', 'UMM 180', 'Deliwa', 'Distribution', 160.00, 'T.13.U016030042', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 269', 'UMM 269', 'Thalkotayaya Kobbewa', 'Distribution', 100.00, 'T.14.U010030388', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 264', 'UMM 264', 'Bandarawadiy II Deliwa', 'Distribution', 100.00, 'T.14.U010030404', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 265', 'UMM 265', 'Kobbewa II', 'Distribution', 100.00, '114839', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 284', 'UMM 284', 'Diganayaya', 'Distribution', 100.00, 'T.15.U010030055', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 294', 'UMM 294', 'Kolongahayata', 'Distribution', 100.00, 'T.16.U010030243', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 292', 'UMM 292', 'Baduluwela uda arawa', 'Distribution', 100.00, 'T.16.U010030241', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 293', 'UMM 293', 'Wewelanda', 'Distribution', 100.00, 'T.16.U010030236', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 104', 'UMM 104', 'Aratugaswela', 'Distribution', 160.00, 'T.14.U016030117', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 174', 'UMM 174', 'Thampalawela', 'Distribution', 100.00, 'T.19.U010030442', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 205', 'UMM 205', 'Ilukpitiya Katukuramandiya', 'Distribution', 100.00, '109753', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 105', 'UMM 105', 'Pangura', 'Distribution', 100.00, 'T.01.U01003333', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 105', 'UMM 105', 'Udukumbura', 'Distribution', 100.00, '308124', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 075', 'UMM 075', 'Galabedda I (Near the Galabedda school)', 'Distribution', 100.00, 'T.02.U01003186', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 193', 'UMM 193', 'Ambalanda Alupathgala', 'Distribution', 160.00, 'T.12.U016030475', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 076', 'UMM 076', 'Galabedda II (Near the Dialog tower)', 'Distribution', 100.00, 'COIU010003109', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 249', 'UMM 249', 'Kiwlalanda Beraliyapola', 'Distribution', 100.00, '114821', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 044', 'UMM 044', 'Kolonwinna', 'Distribution', 100.00, 'T21.U010030319', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 267', 'UMM 267', 'Aluthwaththa Wedikumbura', 'Distribution', 100.00, 'T14.U010030401', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(13, 'UMM 077', 'UMM 077', 'Beraliyapola', 'Distribution', 100.00, 'T12.U010030118', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 078', 'UMM 078', 'Miridiya Sewana', 'Bulk & Distribution', 100.00, 'T06.U010030030', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 196', 'UMM 196', 'Thimbirigaspitiya', 'Distribution', 100.00, 'T12.U010030465', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 079', 'UMM 079', 'Madukotanpudama', 'Distribution', 100.00, '109819', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 187', 'UMM 187', 'Koramba Pallebedda', 'Distribution', 100.00, 'T12.U010030272', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 080', 'UMM 080', 'Maganda Oya kosselpola', 'Distribution', 100.00, 'T99.U01003598', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 256', 'UMM 256', 'Hekirilla Maganda Oya', 'Distribution', 100.00, '114735', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 155', 'UMM 155', 'Maha Arawa (Pihillabedda I)', 'Distribution', 100.00, 'T10.U010030596', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 156', 'UMM 156', 'Maha Arawa Pihillabedda II', 'Distribution', 100.00, 'T10.U010030461', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 201', 'UMM 201', 'Filling Centre Dombagahawela', 'Distribution', 100.00, '308018', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 201', 'UMM 201', 'Neelawabedda', 'Distribution', 100.00, 'U010030028', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 161', 'UMM 161', 'Diyakolayaya', 'Distribution', 100.00, 'T10.U010030579', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 146', 'UMM 146', 'Kahagolla', 'Distribution', 100.00, 'T10.U010030036', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 082', 'UMM 082', 'Dombagahawela', 'Distribution', 160.00, 'T.16.U016030477', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 133', 'UMM 133', 'Dematabedda', 'Distribution', 100.00, '74518', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 172', 'UMM 172', 'AMTRAD (Uva Mahajana Sugar Cane)', 'Bulk', 160.00, 'T10.U016030348', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 083', 'UMM 083', 'P.S.C.O. Kodayana', 'Bulk & Distribution', 100.00, 'T15.U010030288', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 219', 'UMM 219', 'Mirisyaya Nugagahakiwla', 'Distribution', 100.00, '114699', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 278', 'UMM 278', 'CIC II Kodayana', 'Bulk', 630.00, '63030042', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 085', 'UMM 085', 'Kodayana', 'Distribution', 100.00, 'T05.U010030159', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 147', 'UMM 147', 'Balabedda', 'Distribution', 100.00, '74493', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 086', 'UMM 086', 'Karanagama', 'Distribution', 100.00, 'T03.U01003316', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 208', 'UMM 208', 'Thibbatulanda', 'Distribution', 100.00, '109791', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 287', 'UMM 287', 'Karana Helabada', 'Distribution', 100.00, 'T10.U010030564', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 087', 'UMM 087', 'Galwetiya Karanagama', 'Distribution', 100.00, 'T.03.U01003308', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 088', 'UMM 088', 'Guruhela Saddathissagama', 'Distribution', 100.00, 'T02.U01003645', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 259', 'UMM 259', 'Dehiaththayaya', 'Distribution', 100.00, '114746', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 089', 'UMM 089', 'Mayuragama Ethimale', 'Distribution', 100.00, 'T.', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 090', 'UMM 090', 'Wila Oya Water Supply', 'Distribution', 100.00, 'T22.U010030057', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 227', 'UMM 227', 'Kadurugoda', 'Distribution', 100.00, '109757', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 275', 'UMM 275', 'Wila Oya Batulanda', 'Distribution', 100.00, 'T04U010030288', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 215', 'UMM 215', 'Udikkapuara I', 'Distribution', 100.00, '109795', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 262', 'UMM 262', 'Udikkapuara II', 'Distribution', 100.00, '114781', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 127', 'UMM 127', 'Pahatha Arawa', 'Distribution', 100.00, 'T08.U010030518', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 129', 'UMM 129', 'Polkotan Arawa', 'Distribution', 100.00, 'T22.U010030058', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 290', 'UMM 290', 'Kiralana Uragoda', 'Distribution', 100.00, 'T16.U010030037', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 132', 'UMM 132', 'Ampitiya', 'Distribution', 100.00, 'T08.U010030601', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 130', 'UMM 130', 'Bohitiya Kolonwinna', 'Distribution', 100.00, 'T08.U010030596', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 279', 'UMM 279', 'Kapuyaya', 'Distribution', 100.00, 'T14.U010030394', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 182', 'UMM 182', 'Wattegama', 'Distribution', 100.00, 'T12.U010030244', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 307', 'UMM 307', 'Moramal Pokuna Watta', 'Distribution', 100.00, 'T17.U010030045', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 301', 'UMM 301', 'Ethimale plantation', 'Bulk', 100.00, 'T17.U010030149', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 091', 'UMM 091', 'Ethimale Wila Oya', 'Distribution', 160.00, 'T9213.577', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 092', 'UMM 092', 'Gamagala Ethimale', 'Distribution', 100.00, 'T17.U016030087', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 093', 'UMM 093', '60 Potion Ethimale', 'Distribution', 100.00, 'T02.U01003170', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 094', 'UMM 094', 'Jayaminigama Water Board', 'Distribution', 100.00, 'T06.U010030280', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 095', 'UMM 095', 'Gemunupura (Akkara 50) Kumbukeyaya', 'Distribution', 160.00, 'T12.U016030162', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 266', 'UMM 266', 'Perakumpura', 'Distribution', 100.00, '119023', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 096', 'UMM 096', 'Ethimale 70 Pottion', 'Distribution', 160.00, 'T09.U016030066', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 194', 'UMM 194', 'Wattarama', 'Distribution', 100.00, 'T12.U010030324', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 098', 'UMM 098', 'Ethimale Water Board', 'Distribution', 100.00, 'T04.U010030408', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 097', 'UMM 097', 'Ethimale Thissapura', 'Distribution', 100.00, 'T20.U010030178', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 159', 'UMM 159', 'Siripura Ethimale', 'Distribution', 100.00, 'E1063921', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 158', 'UMM 158', 'Siripura Kota Para', 'Distribution', 100.00, 'මැකී ඇත.', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 099', 'UMM 099', 'Ariyasirigama', 'Distribution', 100.00, '74483', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 228', 'UMM 228', 'Karakolagaspitiya', 'Distribution', 100.00, '114756', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 126', 'UMM 126', 'Mahakandawila Water Supply', 'Distribution', 100.00, 'T08.U010030281', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 277', 'UMM 277', 'Hewenpitiya II (Kebiliththa RD)', 'Distribution', 100.00, '119002', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 236', 'UMM 236', 'Hewenpitiya I (dewpudagama)Sub', 'Distribution', 100.00, '114817', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 100', 'UMM 100', 'Kotiyagala', 'Distribution', 100.00, 'T09.U010030246', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 260', 'UMM 260', 'Kammalyaya', 'Distribution', 100.00, '114830', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 241', 'UMM 241', 'Kekalana I', 'Distribution', 100.00, '114759', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 242', 'UMM 242', 'Kekalana II', 'Distribution', 100.00, '114804', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, '5 star Grain Solution', 'Bulk', 630.00, 'T16.U063030006', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 251', 'UMM 251', 'KST Ever Green', 'Bulk', 400.00, 'T11.U040030030', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 237', 'UMM 237', 'Walahagala Kiwleyaya', 'Distribution', 100.00, 'T16.U010030190', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 160', 'UMM 160', 'Ceylon Agro', 'Bulk', 100.00, 'T10.U010030802', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 173', 'UMM 173', 'Kiuleyaya Mandagala', 'Distribution', 100.00, '114828', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 274', 'UMM 274', 'Kiuleyaya 40 Village', 'Distribution', 100.00, 'T04.U010030367', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 148', 'UMM 148', 'Hiripitiya', 'Distribution', 100.00, 'T10.U010030181', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 210', 'UMM 210', 'Madugama', 'Distribution', 100.00, '109726', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 308', 'UMM 308', 'Madugama Ethimale Plantation', 'Bulk (HT)', 2000.00, 'MV Bulk', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 140', 'UMM 140', 'Kaluobba', 'Distribution', 100.00, 'T00.U010030788', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 197', 'UMM 197', 'Sooriyathalawa', 'Distribution', 100.00, 'E1063800', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 243', 'UMM 243', 'Kaluobba Sooriyathalawa II (Welimadayaya)Sub', 'Distribution', 100.00, '114783', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, 'UMM 309', 'UMM 309', 'Namaloya II (Janapadaya)', 'Distribution', 100.00, 'T18.U010030721', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Bandarawadiya Water Supply', 'Distribution', 100.00, 'T.18.U01003072', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Obbegoda II', 'Distribution', 160.00, 'T.18.U016030606', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Galbokka II', 'Distribution', 100.00, 'T.18.U010030722', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Kodayana II', 'Distribution', 100.00, 'T.19.U010030084', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Batugammana II', 'Distribution', 100.00, 'T.19U010030426', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Wattegama II', 'Distribution', 100.00, 'T.18.U010030773', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Maliban Waththegama', 'Bulk', 100.00, 'T.22.U010030070', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Papaladeniya', 'Distribution', 100.00, 'T.21U010030458', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Welikatuwa', 'Distribution', 100.00, 'T.05.U010030208', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Kaluobba Water Treatment Plant', 'Bulk', 160.00, 'T/22/U016030278', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Dombagahawela Town (Near the BOC)', 'Distribution', 160.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Baduluwela School Net plus plus', 'Bulk', 160.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Star Agri Businesses Kotiyagala', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Acwell Engineering Liyangolla', 'Bulk', 630.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(13, NULL, NULL, 'Acwell Engineering Kodayana', 'Bulk', 630.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 135', 'UMB 135', 'Malabatuhela', 'Distribution', 100.00, '109763', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 002', 'UMB 002', 'Yalkumbura I (Tengoda)', 'Distribution', 160.00, 'T14U016030156', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 001', 'UMB 001', 'Yalkumbura II', 'Distribution', 100.00, 'T00U01003068', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 071', 'UMB 071', 'Madipitiya', 'Distribution', 100.00, 'T16U010030627', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 058', 'UMB 058', 'Unagolla', 'Distribution', 100.00, '74503', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 003', 'UMB 003', 'Hewelwela', 'Distribution', 250.00, 'T09U016030063', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 029', 'UMB 029', 'Badullagammana', 'Distribution', 250.00, 'T19U025030067', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 030', 'UMB 030', 'C.T.B. Bibila', 'Distribution', 100.00, 'T10U010030403', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 031', 'UMB 031', 'MPCS - Bibila', 'Distribution', 100.00, 'T16U010030047', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(14, 'UMB 032', 'UMB 032', 'Rathupasketiya Bibila', 'Distribution', 160.00, 'T16U1600024159', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 170', 'UMB 170', 'Sapphire Fashion', 'Bulk', 160.00, 'T18U016030036', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 174', 'UMB 174', 'CSC Bibila', 'Distribution', 250.00, 'T18U025030382', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 033', 'UMB 033', 'Telecom Bibila', 'Distribution', 400.00, 'T05U040030012', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 160', 'UMB 160', 'Danasiri', 'Bulk', 160.00, 'T14U016030379', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 043', 'UMB 043', 'Police - Bibila', 'Distribution', 250.00, 'T11U025030028', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 101', 'UMB 101', 'Bibila Hospital', 'Bulk', 400.00, 'T18U40030077', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 044', 'UMB 044', 'Powerloom - Bibila', 'Distribution', 100.00, 'T18U010030063', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 079', 'UMB 079', 'Welihandiya', 'Distribution', 100.00, 'T10U010030361', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 085', 'UMB 085', 'Sikuralanda', 'Distribution', 160.00, 'T10U016030152', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 034', 'UMB 034', 'Moraththamulla', 'Distribution', 100.00, 'T02U01003352', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 102', 'UMB 102', 'Thabahitiyawa', 'Distribution', 100.00, 'T12U010030082', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 035', 'UMB 035', 'Nagala', 'Distribution', 100.00, '74567', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 124', 'UMB 124', 'Balagolla', 'Distribution', 100.00, '109790', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 178', 'UMB 178', 'Kindagala', 'Distribution', 100.00, '928449', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 128', 'UMB 128', 'Korakahana', 'Distribution', 100.00, '109805', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 067', 'UMB 067', 'Delgolla', 'Distribution', 100.00, 'T05U010030299', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 069', 'UMB 069', 'Thotillaketiya', 'Distribution', 100.00, 'T08U010030292', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 036', 'UMB 036', 'Hamapola', 'Distribution', 100.00, 'T03U01003149', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 163', 'UMB 163', 'Welangadewa', 'Distribution', 100.00, 'T15U010030078', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 146', 'UMB 146', 'Bellanwela', 'Distribution', 100.00, '114753', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 132', 'UMB 132', 'Thiththawelkiula', 'Distribution', 100.00, '109806', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 151', 'UMB 151', 'Akkara 60/90', 'Distribution', 100.00, 'T08U010030352', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 103', 'UMB 103', 'Pikiriya', 'Distribution', 100.00, 'T18U010030052', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 038', 'UMB 038', 'Jana Udana Gammana', 'Distribution', 100.00, 'T02U01003346', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 037', 'UMB 037', 'Pitakumbura', 'Distribution', 160.00, 'T16U016030498', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 142', 'UMB 142', '07th Mile Post', 'Distribution', 100.00, '114729', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 153', 'UMB 153', 'Maldam Ambe', 'Distribution', 100.00, '114754', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 150', 'UMB 150', 'Serawa', 'Distribution', 100.00, '114717', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 145', 'UMB 145', 'Perena', 'Distribution', 100.00, '114735', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 149', 'UMB 149', 'Hamanawa', 'Distribution', 100.00, '114790', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 144', 'UMB 144', 'Medalanda', 'Distribution', 160.00, 'T13U016030268', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 143', 'UMB 143', 'Katugashinna', 'Distribution', 160.00, 'T14U016030052', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 158', 'UMB 158', 'Mahagama Karadugala', 'Distribution', 100.00, '114769', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 157', 'UMB 157', 'Karadugala', 'Distribution', 100.00, '114796', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 139', 'UMB 139', 'Rathugala', 'Distribution', 100.00, '109798', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 130', 'UMB 130', 'Galgamuwa', 'Distribution', 100.00, 'T09U010030173', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 129', 'UMB 129', 'Meeyanthalawa', 'Distribution', 100.00, 'T12U010030187', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 148', 'UMB 148', 'Udadambuwa', 'Distribution', 100.00, '109817', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 133', 'UMB 133', 'Nawa Siri Pathana', 'Distribution', 100.00, 'T08U010080212', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 131', 'UMB 131', 'Hadabima', 'Distribution', 100.00, '109804', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 147', 'UMB 147', 'Nelliyadda', 'Distribution', 100.00, 'T03U01003163', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 140', 'UMB 140', 'Rathmalgaha Ella', 'Distribution', 100.00, '109735', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 154', 'UMB 154', 'Mullegama', 'Distribution', 100.00, '114741', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 156', 'UMB 156', 'Heen Waththa', 'Distribution', 100.00, '114811', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 155', 'UMB 155', 'Arala Uhana', 'Distribution', 100.00, '114767', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Atharagalla', 'Distribution', 100.00, 'T16U010030324', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 004', 'UMB 004', 'Dodamgolla I', 'Distribution', 100.00, 'T17U010030034', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 005', 'UMB 005', 'Dodamgolla II', 'Distribution', 160.00, '74690', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 062', 'UMB 062', 'Kanulwela', 'Distribution', 100.00, 'T12U010030396', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 165', 'UMB 165', 'Thalagolla', 'Distribution', 100.00, 'T16U010030510', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 006', 'UMB 006', 'Ruhunuputha', 'Bulk & Distribution', 630.00, 'T07U063030002', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 110', 'UMB 110', 'Mahayaya', 'Distribution', 100.00, '308367', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 007', 'UMB 007', 'Yakunnawa', 'Distribution', 100.00, 'T15U01003040', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 084', 'UMB 084', 'Dunumawa', 'Distribution', 100.00, 'T10U010030081', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 008', 'UMB 008', 'Badiyawa', 'Distribution', 100.00, 'T04U10030301', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 137', 'UMB 137', 'Wepathdeniya', 'Distribution', 100.00, '114733', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 009', 'UMB 009', 'Wayadena', 'Distribution', 100.00, 'T00U01003144', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 082', 'UMB 082', 'Godigamuwa', 'Distribution', 100.00, 'T10U010030498', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 134', 'UMB 134', 'Ahugoda', 'Distribution', 100.00, '114742', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 010', 'UMB 010', 'Dahamgama', 'Distribution', 100.00, '1063755', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 011', 'UMB 011', 'Kotabowa', 'Distribution', 160.00, 'T16U016030244', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 138', 'UMB 138', 'Aluthwela', 'Distribution', 100.00, '114762', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 074', 'UMB 074', 'Kalugahawadiya', 'Distribution', 100.00, 'T09U010030248', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 141', 'UMB 141', 'Egoda Kalugahawadiya', 'Distribution', 100.00, '114766', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 012', 'UMB 012', 'Senapathiya', 'Distribution', 160.00, 'T20U016030371', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 013', 'UMB 013', 'Nannapurawa I (5 MP)', 'Distribution', 160.00, 'T/89/13189', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 177', 'UMB 177', 'Senpathigama', 'Distribution', 100.00, 'T07U010030138', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 014', 'UMB 014', 'Bibilamulla', 'Distribution', 160.00, 'T20U016030576', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 015', 'UMB 015', 'Nannapurawa II', 'Distribution', 160.00, 'T11U016030387', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 179', 'UMB 179', 'Koongolla', 'Distribution', 100.00, 'T19U010020249', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 016', 'UMB 016', 'Nannapurawa III (7 MP)', 'Distribution', 160.00, 'T19U016030192', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 093', 'UMB 093', 'Gallidamulla', 'Distribution', 100.00, 'T11U010030041', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 161', 'UMB 161', 'Ellakona Gonamada', 'Distribution', 100.00, '114750', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 017', 'UMB 017', 'Nakkalagoda', 'Distribution', 160.00, 'T08U016030301', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 180', 'UMB 180', 'Monaragala Road 8 MP', 'Distribution', 100.00, 'T18U010030713', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 018', 'UMB 018', 'Ayurweda', 'Distribution', 160.00, 'T19U016030667', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 019', 'UMB 019', 'Herad Aperal', 'Bulk', 250.00, 'T/91/3652', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 020', 'UMB 020', 'Medagama Town', 'Distribution', 250.00, 'T21U025030083', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 061', 'UMB 061', 'Pitadeniya', 'Distribution', 100.00, '74443', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 136', 'UMB 136', 'Udawela Piyawinna', 'Distribution', 100.00, '114801', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 021', 'UMB 021', 'Ranminigama', 'Distribution', 100.00, 'T14U010030358', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 022', 'UMB 022', 'Alana', 'Distribution', 100.00, 'T02U01003328', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 100', 'UMB 100', 'Mahagangoda', 'Distribution', 100.00, 'T11U01003358', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 162', 'UMB 162', 'Yatiella', 'Distribution', 100.00, 'T14U010030371', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 172', 'UMB 172', 'Meegahawagura New', 'Distribution', 160.00, 'T21U016030238', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 073', 'UMB 073', 'Meegahawagura', 'Distribution', 100.00, 'T09U010030297', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 078', 'UMB 078', 'Thimbirya Rathupasketiya', 'Distribution', 100.00, 'T16U010030166', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 024', 'UMB 024', 'Mallagama', 'Distribution', 100.00, 'T06U010030028', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 117', 'UMB 117', 'Nagahawatta', 'Distribution', 100.00, '308391', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 152', 'UMB 152', 'Dambagaspitiya (Mellagama)', 'Distribution', 100.00, 'T14U010030301', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 023', 'UMB 023', 'Thimbiriya', 'Distribution', 100.00, 'T16U010030034', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 025', 'UMB 025', '11 MP (Kapulanda)', 'Distribution', 160.00, 'T18U016030614', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 026', 'UMB 026', 'Bakinigahawela', 'Distribution', 160.00, 'T14U016030351', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 076', 'UMB 076', 'Kudagala', 'Distribution', 100.00, 'T10U010030013', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 027', 'UMB 027', 'Keenagoda', 'Distribution', 100.00, 'T18U010030728', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 066', 'UMB 066', 'Pubbara', 'Distribution', 100.00, 'T08U01003007', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 173', 'UMB 173', 'Kirawanahela', 'Distribution', 100.00, 'T19U010030044', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 063', 'UMB 063', 'Polgahapitiya', 'Distribution', 100.00, 'T08U010030019', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 127', 'UMB 127', 'Ampitiya', 'Distribution', 160.00, 'T13U016030112', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(14, 'UMB 095', 'UMB 095', 'Moragahamada', 'Distribution', 100.00, 'T11U010030077', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 028', 'UMB 028', 'Raththanadeniya', 'Distribution', 160.00, 'T16U016030602', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 125', 'UMB 125', 'Horagolla', 'Distribution', 100.00, '109722', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 167', 'UMB 167', '17th Mile Post New', 'Distribution', 100.00, 'T16U010030401', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UBM 120', 'UBM 120', 'Weumada', 'Distribution', 100.00, '109751', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 039', 'UMB 039', 'Ussagala', 'Distribution', 160.00, 'T21U016030002', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 159', 'UMB 159', 'Malwattha Beeriwewa', 'Distribution', 100.00, 'T08U010030173', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 176', 'UMB 176', 'CEC Metal Crusher', 'Bulk', 400.00, 'T18U040030190', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 105', 'UMB 105', 'Ilukapathana', 'Distribution', 100.00, 'T12U010030405', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 116', 'UMB 116', '41 Kanuwa', 'Distribution', 100.00, '308222', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 040', 'UMB 040', 'Kanawegalla', 'Distribution', 100.00, 'T02U01003156', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 045', 'UMB 045', 'Interlock Garment', 'Bulk & Distribution', 100.00, 'T99U01003182', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 046', 'UMB 046', 'Gonakura Arawa', 'Distribution', 100.00, 'T/94/1003075', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 121', 'UMB 121', 'Singhapura', 'Distribution', 100.00, '308197', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 047', 'UMB 047', 'Wagama', 'Distribution', 160.00, 'T18U016030712', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 064', 'UMB 064', 'Bibila Watta', 'Distribution', 100.00, 'T18U010030475', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 126', 'UMB 126', 'Dehigahalanda', 'Distribution', 100.00, '109816', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, 'UMB 097', 'UMB 097', 'Herath Gedara', 'Distribution', 100.00, 'NO', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Gal Oya Sisila (Water Project)', 'Bulk & Distribution', 160.00, 'T18U016030605', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Bibile Pradeshiya Sabawa', 'Distribution', 160.00, 'T20U016030375', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Lindakumbura', 'Distribution', 160.00, 'T14U016030378', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Dahangama New', 'Distribution', 100.00, 'T21U010030377', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Kotabowa Junction', 'Distribution', 100.00, 'T21U010050573', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Bokuhera', 'Distribution', 100.00, 'U98U01003303', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Bakinigahwela new', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Cargills food city bibila', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Kinnarabowa', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Badullagammana temple', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'Rathugala Net plus plus', 'Bulk', 630.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(14, NULL, NULL, 'P.L Office Bibile (Bulk)', 'Bulk', 160.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 001', 'Koslanda Estate', 'Bulk & Distribution', 250.00, 'T.22.U.025030034', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 002', 'Koslanda Town', 'Distribution', 100.00, 'T.03.U.01003045', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 003', 'Koslanda Telecom', 'Bulk & Distribution', 100.00, 'T.01.U.01003042', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 004', 'Udumulla', 'Distribution', 100.00, 'T.17.U.010030009', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 005', 'Naulla', 'Distribution', 100.00, 'T.03.U.01003272', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 006', 'Kelipanawela', 'Distribution', 100.00, 'T.03.U.01003231', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 007', 'Diyaluma', 'Distribution', 100.00, 'T.00.U.01003397', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 008', 'Kolongasthenna', 'Distribution', 100.00, 'T.03.U.01003291', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 009', 'Uva Mawelagama', 'Distribution', 100.00, 'T.271003231', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 010', 'Rosbery Estate', 'Bulk', 100.00, 'T.21.U.010030143', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 011', 'Nikapitiya', 'Distribution', 160.00, 'T.17.U.01603007', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 012', 'Heewelkandura', 'Distribution', 100.00, 'T.02.U.01003177', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 013', 'Ice Peella', 'Distribution', 100.00, 'TD3.U.01003153', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 014', 'Paragasmankada', 'Distribution', 250.00, '117063', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 015', 'Wellawaya Telecom', 'Bulk & Distribution', 160.00, 'T.14.U.016030048', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 016', 'Dimbulamuraya', 'Distribution', 250.00, 'T.18.U.025030158', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 017', 'Peraketiya', 'Distribution', 100.00, 'T.00.U.1003303', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 018', 'Weerasekaragama', 'Distribution', 400.00, 'T/92/3845', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 019', 'Malwaththawela', 'Distribution', 100.00, 'T/99/U.01003439', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 020', 'Kaduruketha', 'Distribution', 100.00, 'T/09.U.010030465', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 021', 'Gampanguwa', 'Distribution', 100.00, 'T.98.U.01003254', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 022', 'Hinguregala', 'Distribution', 160.00, '941603107', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 023', 'Randeniya', 'Distribution', 160.00, 'T.21.U.016030353', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 024', 'Siyambalagunaya', 'Distribution', 100.00, 'T.02.U.01003027', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 025', 'Warunagama', 'Distribution', 160.00, 'T.13.U.01603025', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 026', 'Pelwatta Block 3', 'Distribution', 100.00, 'T.12U010030461', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 027', 'Anapallama School Lane', 'Distribution', 100.00, 'T.03.U.01003152', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 028', 'Kandiyagama 1', 'Distribution', 100.00, 'T.08.U.010030004', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 029', 'Anapallama Water Pump House (Remove & sent to Buttala CSC)', 'Bulk', 100.00, 'T.18.U.010030006', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 030', 'Pelwatta Block I', 'Distribution', 100.00, '99/T/U0/1009961', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 035', 'Kumaradasa Mawatha', 'Distribution', 250.00, 'T/18.U.025030287', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 036', 'Yalabowa Water Board', 'Bulk', 250.00, 'T/15/U.025030033', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 037', 'Yalabowa Housing Scheme', 'Distribution', 100.00, 'T.99.U.01003079', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 038', 'Sellaba Junction', 'Distribution', 250.00, 'T.20.U.025030005', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 039', 'Anjaligama', 'Distribution', 100.00, 'T.19.U.01003460', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 040', 'Buduruwagala', 'Distribution', 100.00, 'T.15U/010030080', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 041', 'Handapanagala Watta', 'Distribution', 160.00, 'T.19.U.016030670', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 042', 'Protex Garment', 'Bulk', 250.00, 'T.99.U.92503245', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 043', 'Keheliya Junction', 'Distribution', 100.00, 'T.10.U.010030608', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 044', 'Keheliyagama', 'Distribution', 100.00, 'T.10.U.010030087', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 045', 'Dehigas Handiya', 'Distribution', 100.00, 'T/00U01003050', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 046', 'Weherayaya Colonya I', 'Distribution', 100.00, 'T.97.01003292', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 047', 'Siripuragama', 'Distribution', 100.00, 'T.03.U01003242', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 048', 'Weherayaya', 'Distribution', 250.00, 'T.18.U.25030090', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 049', 'Randenigodayaya', 'Distribution', 160.00, 'T.06.U.016030043', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 050', 'Maha Aragama', 'Distribution', 100.00, 'T.06.U.010030371', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 051', 'Handapanagala', 'Distribution', 100.00, 'T.17.U.010030048', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 052', 'Pubuduwewagama', 'Distribution', 100.00, '109772', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 053', 'Block 9 - 11', 'Distribution', 160.00, 'T.03.U.01603035', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 054', 'Ethiliwewa Colonya III', 'Distribution', 100.00, 'T.02.U.01003028', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 055', 'DS Gama', 'Distribution', 100.00, 'T.98.01003289', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 056', 'Ethiliwewa', 'Distribution', 100.00, '74526', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 057', 'Thelulla Temple', 'Distribution', 100.00, '114814', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 058', 'Thelulla Janapadaya', 'Distribution', 100.00, 'T.21.U.010030523', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 074', 'Morahela', 'Distribution', 100.00, 'T.20.U.010030155', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 075', 'Thanakumbukayaya', 'Distribution', 100.00, '34430', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 078', 'Vocational Training Center', 'Bulk', 100.00, 'T/008136', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 080', 'Kotabakma', 'Distribution', 100.00, 'T.09.U.010030174', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 081', 'Kandiyagama II', 'Distribution', 100.00, '74597', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 086', 'Medagalagama', 'Distribution', 100.00, 'T.08.U.010030509', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 087', 'Ulkanda Dewala Road', 'Distribution', 100.00, 'T.09.U.010030172', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 090', 'Upul Metal Crusher', 'Bulk', 160.00, 'T.08.U.016030442', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 092', 'Block 10', 'Distribution', 160.00, 'T.09.U.016030069', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 093', 'Galpoththa Ara', 'Distribution', 100.00, 'T.09.U.010030292', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 094', 'Dematath Aragama', 'Distribution', 100.00, 'T.09.U.010030464', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 095', 'Dehilandayaya', 'Distribution', 100.00, 'T.09.U.010030465', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 096', 'Welyayagama', 'Distribution', 100.00, 'T.09.U.010030422', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 097', 'Block 14', 'Distribution', 160.00, 'T.09.U.016030218', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 098', 'Kirindi Oya Pump House', 'Bulk', 100.00, '74509', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 099', 'Weeraththagalayaya', 'Distribution', 100.00, 'T.09.U.010030730', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(15, NULL, 'UWW 100', 'Iduruyaya DDLO', 'Distribution', 100.00, 'T.09.U.010030775', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 101', 'Yalabowa (Mahawelamulla)', 'Distribution', 160.00, 'T.20.U.016030558', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 103', 'Diggalayaya', 'Distribution', 100.00, 'T.10.U.010030096', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 107', 'Maha Aragama II (Close to Temple)', 'Distribution', 100.00, 'T.10.U.010030455', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 108', '20 Yaya', 'Distribution', 100.00, 'T.10.U.0010030464', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 109', 'Naigal Ara', 'Distribution', 100.00, 'T.10.U.010030479', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 111', 'Maha Aragama III (Near The School)', 'Distribution', 100.00, 'T.10.U.010030733', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 112', 'Ulkandagama', 'Distribution', 100.00, 'T.10.U.010030540', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 113', 'Olugala', 'Distribution', 100.00, 'T.10.U.010030379', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 114', 'Malewanayaya', 'Distribution', 100.00, 'T92-8845', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 115', 'Neluwagala', 'Distribution', 100.00, 'T.10.U.010030727', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 116', 'Ethiliwewa Junction', 'Distribution', 160.00, 'T.17.U.016030050', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 117', 'Dakunumahathenna', 'Distribution', 100.00, 'T/10.U10030689', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 120', 'Wellawaya Town', 'Distribution', 250.00, 'T/18.U.025030279', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 121', 'Lemasthota MHP', 'Bulk (MHP)', 1750.00, 'T.00.1R.282', 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 142', 'Ranawarawa Randeniya', 'Distribution', 100.00, 'T.12.U.010030206', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 143', 'Uthuru Mahathenna', 'Distribution', 100.00, 'T.12.U.010030009', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 147', 'Keeriyagolla', 'Distribution', 100.00, '(5046)/0308023', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 148', 'Hinguruara (Galpoththa Ara)', 'Distribution', 100.00, '109778', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 149', 'Yoda Ara I', 'Distribution', 100.00, '109776', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 150', 'Wellawaya MHP', 'Bulk (MHP)', 1500.00, 'T.00.1R.374', 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 153', 'Bulugaha Indilanda', 'Distribution', 100.00, 'T.19.U.010030309', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 154', 'Warunagama Army Camp', 'Bulk', 160.00, 'T.12.U.016030451', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 155', 'Ayurvedic Medicine Center', 'Bulk', 100.00, 'E.1063926', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 156', 'Wellawaya Hospital', 'Bulk', 400.00, 'T.12.U.040030058', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 157', 'Ambaragala Watta', 'Distribution', 100.00, '60735/16', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 158', 'Cargills Food City Wellawaya', 'Bulk', 100.00, '114819', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 159', 'Ethiliwewa Mola Para', 'Distribution', 100.00, '109723', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 160', 'C.S.T. Randeniya', 'Bulk', 830.00, 'U.083030019', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 161', 'Diyahitithenna', 'Distribution', 100.00, 'T.12.U.010030488', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 162', 'Yoda Ara (Meedeniya)', 'Distribution', 100.00, 'E.1064082', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 163', 'New City (Thelulla)', 'Distribution', 100.00, '114703', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 164', 'Diulgasmulla', 'Distribution', 100.00, '109760', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 165', 'Meegas Aragama', 'Distribution', 100.00, '109784', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 167', 'Uma Oya Gammanaya', 'Distribution', 100.00, '114709', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 168', 'Thelulla Janapadaya (Wathura Peella)', 'Distribution', 160.00, 'T.20.U.016030534', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 169', 'Ken 7', 'Distribution', 100.00, 'T.18.U.010030116', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 172', 'Dematath Aragama (Aluthwela)', 'Distribution', 100.00, '114782', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 173', 'Ranasinghagama', 'Distribution', 100.00, 'T.14.0010030292', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 175', 'Buduruwagala School', 'Distribution', 100.00, 'T.93/1003500', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 177', 'Pahala Warunagama', 'Distribution', 100.00, '118997', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 178', 'Wellawaya Budumedura', 'Distribution', 250.00, 'T.21.U.025030001', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 179', 'Lemasthota Upper MHP', 'Bulk (MHP)', 1600.00, 'T.00.1R.647', 1, 13, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 180', 'Jetwing hotel - Kaduruketha', 'Bulk', 100.00, 'T.06.U.016030329', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 181', 'Diyabethma - Aluthwela', 'Distribution', 100.00, 'T.00.U.01003031', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 182', 'Thelulla R-7 Ganga Para', 'Distribution', 100.00, 'T.08.U.010030318', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 183', 'Aluthwela Umaoya Project', 'Bulk', 100.00, 'T.16.U.010030095', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 184', 'Aluthwela Ranawiru Mawatha', 'Distribution', 100.00, 'T.16.010030461', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW186', 'Udawadiya', 'Distribution', 100.00, 'T.16.U.010030513', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 187', 'Kosgolla', 'Distribution', 100.00, 'T.16.U.010030300', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 188', 'Henawala', 'Distribution', 100.00, 'T.16.U.010030550', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 191', 'Handapanagala I Ela', 'Distribution', 100.00, 'T.03.U01003022', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 193', 'Wandama Nelna Farm', 'Bulk', 100.00, 'T.20.U.01003391', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 196', 'Ethiliwewa Kandeyaya', 'Distribution', 100.00, 'T.18.U.010030169', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 199', 'Ranawiripura', 'Distribution', 100.00, 'T.18.U.010030266', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 201', 'Randenigodayaya (Near the river)', 'Distribution', 100.00, 'T.19.U.010030153', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 202', 'Alikota Ara', 'Bulk & Distribution', 100.00, 'T.19.U.010030089', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 203', 'Yalabowa National Youth Corps', 'Bulk', 100.00, 'T.20.U.010030171', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 205', 'Kalupahana Metal Crusher (Randeniya)', 'Bulk', 160.00, 'T.18.U.016030875', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 206', 'sripathi Rice Mill', 'Bulk', 100.00, 'T.20.U.010030160', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 207', 'Bulugala Arannya', 'Distribution', 100.00, 'T.19.U.010030484', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 209', 'Mirisskade Junction', 'Distribution', 160.00, 'T.21.U.016030058', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 210', 'Hingurukauwa Hospital', 'Distribution', 100.00, 'T.21.U.010030552', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 211', 'Rathmalwehera Temple', 'Distribution', 100.00, 'T.12.U010030045', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 212', 'Koslanda Nakatiya', 'Distribution', 100.00, 'T.16.U010030450', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 213', 'Kotaweheragala Temple', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 214', 'Nikapitiya Madapara', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 215', 'Malewanayaya (Metel Crusher)', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 216', 'Ginibord Handiya', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 217', 'Rohana Gems Solar', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(15, NULL, 'UWW 218', 'Wanniarachchi Bulding Solar', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Milla Oya Sammani Power MHP', 'Bulk & Distribution (MHP)', 1630.00, NULL, 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 001', 'UMM 001', 'Vykumbura Group', 'Bulk', 100.00, 'T.11.U01003012', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 173', 'UMM 173', 'Akkara 100 (8 Mile Post)', 'Distribution', 100.00, 'T.18.U010030718', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 002', 'UMM 002', 'Kandukaragama', 'Distribution', 100.00, 'T.06.U010030168', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 003', 'UMM 003', 'Wadagahakiula', 'Distribution', 100.00, 'T.11.U010030170', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 004', 'UMM 004', 'Walasella', 'Distribution', 100.00, 'T.11U010030499', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 006', 'UMM 006', 'Karandawaththa', 'Distribution', 100.00, 'T.06.U01003086', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 007', 'UMM 007', 'Madama Junction', 'Distribution', 100.00, '109802', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 008', 'UMM 008', 'Pusbedda', 'Distribution', 100.00, 'T.00.U01003053', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 009', 'UMM 009', 'Karavila', 'Distribution', 100.00, '99/UO/100/3371', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 010', 'UMM 010', 'Ella Karavila', 'Distribution', 100.00, '308247', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 011', 'UMM 011', 'Dummalathenna Thenneyaya', 'Distribution', 100.00, 'T.12.U01603127', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 012', 'UMM 012', 'Alupotha', 'Distribution', 160.00, 'T.01.U01603127', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 013', 'UMM 013', 'Alupotha Bangalagoda Water Board', 'Distribution', 100.00, 'T.18.U010030228', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 014', 'UMM 014', 'Kalugahawadiya Ambalanthenna I', 'Distribution', 100.00, '109764', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 015', 'UMM 015', 'Badalkumbura I (Near the Hospital)', 'Distribution', 400.00, 'T.12.U040030097', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 016', 'UMM 016', 'Vasipana', 'Distribution', 160.00, 'T.22.U16030137', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 017', 'UMM 017', 'Ambalanthenna II Bogahapelessa', 'Distribution', 100.00, 'T.03.U01003126', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 018', 'UMM 018', 'Bogahapellassa', 'Distribution', 100.00, 'T022U010030288', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 019', 'UMM 019', 'Meegahayaya', 'Distribution', 100.00, '74520', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 020', 'UMM 020', 'Welanhinna', 'Distribution', 100.00, 'T.01.U01003070', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 021', 'UMM 021', 'Karametiya', 'Distribution', 100.00, '74531', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 023', 'UMM 023', 'Maligathenna Junction II', 'Distribution', 250.00, 'T.16.U016030077', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 022', 'UMM 022', 'Badalkumbura II', 'Distribution', 160.00, 'T.18.U016030591', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 170', 'UMM 170', 'Malgashinna II 12th Mile Post', 'Distribution', 160.00, 'T.18.U010030186', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 024', 'UMM 024', 'Kudugala Malgashinna', 'Distribution', 100.00, 'T.12.U010030469', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 175', 'UMM 175', 'Near the Nishshanka Central College', 'Distribution', 160.00, 'T.17.U016030113', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 040', 'UMM 040', 'Alankandura', 'Distribution', 100.00, '109818', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 041', 'UMM 041', 'Namiriththa Meeegahayaya', 'Distribution', 100.00, 'T.03.U01003254', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(16, 'UMM 042', 'UMM 042', 'Punsisigama', 'Distribution', 160.00, 'T.18.U016030316', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 043', 'UMM 043', 'Pelwaththa Suger Co. Badalkumbura', 'Bulk & Distribution', 160.00, 'T.13.U016030186', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 044', 'UMM 044', 'Elamanayaya', 'Distribution', 100.00, '109773', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 045', 'UMM 045', 'Weheragoda', 'Distribution', 160.00, 'T.20.U016030206', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 046', 'UMM 046', 'Pitiya (5th Mile Post) Badalkumbura', 'Distribution', 100.00, '109734', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 047', 'UMM 047', 'Muthukeliyawa', 'Distribution', 100.00, '114755', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 171', 'UMM 171', 'Medalanda', 'Distribution', 100.00, 'T.18.U010080731', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 179', 'UMM 179', 'Katugahagalge Temple Road', 'Distribution', 100.00, 'T.20.U010030072', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 048', 'UMM 048', 'Water Supply Katugahagalge', 'Distribution', 100.00, 'T.03.U01003256', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 049', 'UMM 049', 'Katugahagalge Ganga Para New', 'Distribution', 100.00, 'T.18.U010030469', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 050', 'UMM 050', 'Water Pump Lunugala Janapadaya', 'Distribution', 100.00, 'T.03.U01003184', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 051', 'UMM 051', 'Lunugala Colony', 'Distribution', 100.00, 'T.99.U01003612', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 169', 'UMM 169', 'Kandiyalanda Lunugala Colony', 'Distribution', 100.00, 'T.19.U01003002', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 052', 'UMM 052', 'Katugahagalge', 'Distribution', 100.00, 'T.08.U010030104', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 053', 'UMM 053', 'Rajakandiya Dickyaya', 'Distribution', 100.00, 'T.11.U010030102', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 054', 'UMM 054', 'Dickyaya', 'Bulk & Distribution', 250.00, 'T.20.U025030123', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 138', 'UMM 138', 'Tri-Star Garment', 'Bulk', 250.00, 'T.15.U025030154', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 139', 'UMM 139', 'Industrial Colony', 'Distribution', 250.00, 'T.923683', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 140', 'UMM 140', 'Industrial Colony Stores Buttala', 'Bulk', 250.00, 'T.15.U025030072', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 141', 'UMM 141', 'Wood Industrial Zone I', 'Distribution', 250.00, 'T.09.U025030159', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 142', 'UMM 142', 'Wood Industrial Zone II', 'Distribution', 250.00, 'T.09.U025030157', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 143', 'UMM 143', 'Wood Industrial Zone III', 'Distribution', 250.00, 'T.08.U25030143', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 144', 'UMM 144', 'Miami Industrial Colony', 'Bulk', 400.00, 'T.08.U040030018', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 192', 'UMW 192', 'Buttala Army Camp', 'Bulk', 630.00, 'T.17.U063030016', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 130', 'UMW 130', 'Gammuda Handiya (Buttala)', 'Distribution', 250.00, 'T.06.U025030033', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 127', 'UMW 127', 'Buttala Town', 'Distribution', 400.00, 'T.07.U040030051', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 194', 'UMW 194', 'Buttala Dutugemunu School', 'Distribution', 160.00, 'T.18.U016030057', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 152', 'UMW 152', 'Buttala Cargills', 'Bulk & Distribution', 160.00, 'T.21.U016030448', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 174', 'UMW 174', 'Sri Ramya Central', 'Bulk', 100.00, '118959', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 195', 'UMW 195', 'Buttala Okkampitiya Road', 'Distribution', 100.00, 'T.18.U010030140', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 061', 'UMW 061', 'Buttala Katharagama Road', 'Distribution', 160.00, 'T.01.U01003183', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 144', 'UMW 144', 'ALuthwela II', 'Distribution', 100.00, 'T.12.U010030271', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 062', 'UMW 062', 'Geradibakiniya Junction', 'Distribution', 250.00, 'T.13.U016030056', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 133', 'UMW 133', 'Medagama Nelumgama (Karawila Kotuwa)', 'Distribution', 100.00, 'T.10.U010030503', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 204', 'UMW 204', 'Tharindu Rice Mill', 'Bulk', 100.00, 'T.20.U010030184', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 063', 'UMW 063', 'Aluthwela', 'Distribution', 100.00, 'T.18.U010030460', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 140', 'UMW 140', 'Weweyaya Waguruwela', 'Distribution', 100.00, 'T.11.U010030419', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 064', 'UMW 064', 'Waguruwela', 'Distribution', 100.00, '7911', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 145', 'UMW 145', 'Wekada Yatiyallathota', 'Distribution', 100.00, 'T.012.U010030219', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 198', 'UMW 198', 'Dole Lanka VI', 'Bulk', 250.00, 'T.18.U025030156', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 088', 'UMW 088', 'Dole Lanka I', 'Bulk', 250.00, 'T.08.U025030055', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 089', 'UMW 089', 'Dole Lanka II', 'Bulk', 400.00, 'T.07.U040030053', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 091', 'UMW 091', 'Koonketiya Raja Mawatha', 'Distribution', 100.00, 'T.11.U010030395', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 171', 'UMW 171', 'Welpath Ara', 'Distribution', 100.00, '114885', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 065', 'UMW 065', 'Koonketiya 18th Mile Post', 'Distribution', 100.00, 'T.03.U01003665', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 146', 'UMW 146', 'Walliammagama 17 Mile Post', 'Distribution', 100.00, '308100', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 066', 'UMW 066', 'Koonketiya 19th Mile Post', 'Distribution', 100.00, 'T.03.U01003151', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 126', 'UMW 126', 'Galapita Aragama', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 176', 'UMW 176', 'Pelassawewa Village', 'Distribution', 100.00, 'T.15.U010030014', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 125', 'UMW 125', 'Gonagan Ara', 'Distribution', 100.00, '74466', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 124', 'UMW 124', 'Diyakiriththa', 'Distribution', 100.00, 'T.08.U010030319', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 110', 'UMW 110', 'Block 15-16', 'Distribution', 100.00, 'T.10.U010030037', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 104', 'UMW 104', 'Dole Lanka III', 'Bulk', 400.00, 'T.10.U0400348', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 105', 'UMW 105', 'Dole Lanka IV', 'Bulk', 400.00, 'T.08.U040030076', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 106', 'UMW 106', 'Dole Lanka V', 'Bulk', 400.00, 'T.10.U0400341', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 200', 'UMW 200', 'Buttala Udagama', 'Distribution', 160.00, 'T.18.U016030770', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 128', 'UMW 128', 'Buttala Hospital', 'Distribution', 250.00, 'T.12.U025030108', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 129', 'UMW 129', 'Yudaganawa Temple', 'Distribution', 100.00, 'T.05.U01003068', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 138', 'UMW 138', 'Yudagana Akkara 50', 'Distribution', 100.00, 'T.09.U010030182', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 134', 'UMW 134', 'D.M.P. Metal Crusher', 'Bulk', 400.00, 'T.12.U025030203', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 170', 'UMW 170', 'Yudagana Dharmasena Gal Mola', 'Bulk', 250.00, 'T.18.U040030124', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 131', 'UMW 131', 'Yudaganawa Janapadaya I (Co-Op City)', 'Distribution', 160.00, '4501', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 137', 'UMW 137', 'Yudagana Junction', 'Distribution', 250.00, 'T.22.U025030009', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 132', 'UMW 132', 'Yudagana Janadaya II (Close to School)', 'Distribution', 100.00, 'T.00.U01003143', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 122', 'UMW 122', 'Yatiyallathota', 'Distribution', 100.00, 'T.09.U010030361', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 067', 'UMW 067', 'Ambakolawewa', 'Distribution', 100.00, 'T.02.U01003197', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 139', 'UMW 139', 'Unawatunagama', 'Distribution', 160.00, 'T.020.U016030500', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 068', 'UMW 068', 'Burutha Road', 'Distribution', 100.00, 'T.05.U010030129', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 085', 'UMW 085', 'Burutha Road II', 'Distribution', 160.00, 'T.21.U016030437', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 123', 'UMW 123', 'Walugolla', 'Distribution', 100.00, 'T.09.U010030169', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 069', 'UMW 069', 'Pelwatta Suger Company', 'Bulk', 1000.00, 'T.12.U0100030019', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 070', 'UMW 070', 'Pelwatta Distilary', 'Bulk & Distribution', 630.00, '956303018', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 072', 'UMW 072', 'Pelwatta Diary Industry', 'Bulk', 400.00, 'T.18.U040030034', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 071', 'UMW 071', 'Pelwatta Milk Powder Industry', 'Bulk & Distribution', 800.00, 'T.18.U080030010', 1, 12, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 059', 'UMW 059', 'Kukurampola', 'Distribution', 160.00, 'T.20.U01603030479', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 060', 'UMW 060', 'Welimadayaya', 'Distribution', 100.00, 'T.18.U010030175', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 185', 'UMW 185', 'Kovilpelessa', 'Distribution', 100.00, 'T.16.U010030313', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 135', 'UMW 135', 'Gampalu Kotuwa (Block 6)', 'Distribution', 100.00, 'T.09.U010030316', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 119', 'UMW 119', 'Janawasa 10-20', 'Distribution', 100.00, 'T.011.U01003007', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 136', 'UMW 136', 'Mahasenpura', 'Distribution', 100.00, 'T.09.U010030618', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 189', 'UMW 189', 'Kalupahana Metal Crusher (Sahana Metal Crusher )', 'Bulk', 100.00, 'T.16.U010030478', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 073', 'UMW 073', 'Kumaragama Block 4', 'Distribution', 100.00, 'T.11.U0100369', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 141', 'UMW 141', 'Block 5', 'Distribution', 100.00, '114758', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 034', 'UMW 034', 'Pelwatta Vijaya Road', 'Distribution', 160.00, 'T.16.U016030032', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 079', 'UMW 079', 'Wewewelayaya', 'Distribution', 100.00, 'T.002R136', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 077', 'UMW 077', 'Manampitiya', 'Distribution', 100.00, 'T.0015R136', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 151', 'UMW 151', 'Horabokka Amunelanda DDLO', 'Distribution', 100.00, '109731', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 032', 'UMW 032', 'Horabokka', 'Distribution', 100.00, 'T021U010030334', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 076', 'UMW 076', 'Moratuwagama', 'Distribution', 100.00, '74327', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 197', 'UMW 197', 'Unitam Metal Crusher Moratuwagama', 'Bulk', 630.00, 'T.18.U063030009', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 082', 'UMW 082', 'Moratuwagama II', 'Distribution', 100.00, '114739', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW190', 'UMW190', 'Horabokka Suger Company (Sirikatha Cane Mill)', 'Bulk', 100.00, 'T.18.U010030486', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 084', 'UMW 084', 'Uda Arawa', 'Distribution', 100.00, 'T.09.U010030056', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 118', 'UMW 118', 'Bubula', 'Distribution', 100.00, 'T.11.U010030183', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 102', 'UMW 102', 'Uda Arawa (Peraketiya)', 'Distribution', 100.00, 'T.10.U01003006', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 166', 'UMW 166', 'Kehel agala', 'Distribution', 100.00, '114805', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 033', 'UMW 033', 'Hingurukaduwa', 'Distribution', 160.00, 'T.19.U016030088', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMW 031', 'UMW 031', 'Pelwatta Junction', 'Distribution', 250.00, 'T.14.U025030087', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 025', 'UMM 025', 'Madugahapattiya (Badalkumbura)', 'Distribution', 100.00, 'T.11.U010030351', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, 'UMM 026', 'UMM 026', 'Pussellawa', 'Distribution', 160.00, 'T.14.U016030064', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql');

INSERT INTO transformers (csc_id, old_sin_no, new_sin_no, substation_name,
        transformer_type, capacity_kva, transformer_no, quantity,
        asset_type_id, remarks, status, source_file) VALUES
(16, 'UMW 083', 'UMW 083', 'Buttala Telecom Neluwayaya', 'Bulk', 100.00, 'T/97/100/3072', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, '3K Tyre Factory', 'Bulk', 100.00, '109789', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Okuruwawa New', 'Distribution', 100.00, 'T.21.U010030272', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Anapalama Water Pump', 'Distribution', 100.00, 'T.18.U010030006', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Budugalena', 'Distribution', 100.00, 'T.21.U010030429', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Kukurampola New', 'Distribution', 100.00, 'T.17.U010030085', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Galgodayaya', 'Bulk', 160.00, 'T.05.U010030280', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Farmer"s fertilizer (Gonagodalla Road)', 'Bulk', 250.00, 'T.21U025050197', 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Narannwaththa', 'Distribution', 100.00, 'T.22U010030228', 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Peace lity lanka (Pvt) Ltd', 'Bulk', 630.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Wickramarathna Solar', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Bandara solar', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Bio Green Fram (pvt) Ltd', 'Bulk', 100.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Dutugemunu School Road', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Herath Solar', 'Bulk', 160.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Dodamwaththa', 'Distribution', 100.00, NULL, 1, 10, NULL, 'ACTIVE', 'transformer_asset_management.sql'),
(16, NULL, NULL, 'Multipurpose Co-Operative Society', 'Bulk', 250.00, NULL, 1, 11, NULL, 'ACTIVE', 'transformer_asset_management.sql');


-- The audit log is populated automatically by the triggers above. Clear
-- the seed noise so the trail starts from real user activity.
DELETE FROM audit_log;
ALTER TABLE audit_log AUTO_INCREMENT = 1;


-- =====================================================================
-- SECTION 17 : POST-IMPORT SANITY CHECKS
--
-- Run these once after importing. Every one of them should return a
-- sensible number; if any errors, the import did not complete.
-- =====================================================================

-- 1. Hierarchy: expect 1 province, 5 areas, 17 depots.
-- SELECT (SELECT COUNT(*) FROM provinces)  AS provinces,
--        (SELECT COUNT(*) FROM areas)      AS areas,
--        (SELECT COUNT(*) FROM csc_depots) AS depots;

-- 2. Taxonomy: expect 11 categories, 39 types.
-- SELECT (SELECT COUNT(*) FROM asset_categories) AS categories,
--        (SELECT COUNT(*) FROM asset_types)      AS types;

-- 3. Transformers: expect 1717 rows, 1715 active, 2 retired.
-- SELECT status, COUNT(*) FROM transformers GROUP BY status;

-- 4. Nothing orphaned: every transformer must resolve to a real depot.
-- SELECT COUNT(*) AS orphaned_transformers
--   FROM transformers t LEFT JOIN csc_depots d ON d.csc_id = t.csc_id
--  WHERE d.csc_id IS NULL;

-- 5. Type mapping coverage: how many transformer rows did not map to a
--    taxonomy type. Any row here has its original label in remarks.
-- SELECT COUNT(*) AS unmapped_type FROM transformers WHERE asset_type_id IS NULL;

-- 6. The headline dashboard, one row per depot.
-- SELECT * FROM v_depot_dashboard ORDER BY area_no, csc_code;

-- 7. Transformer capacity per area.
-- SELECT * FROM v_transformer_totals_by_area ORDER BY area_id;

-- 8. Asset rollup for the two surveyed depots.
-- SELECT * FROM v_totals_by_csc ORDER BY csc_id, category_id, asset_type_id;

-- 9. Data quality worklist.
-- SELECT * FROM v_data_quality_issues ORDER BY severity, issue_code;
-- SELECT issue_code, severity, COUNT(*) FROM v_transformer_data_quality
--  GROUP BY issue_code, severity;


-- =====================================================================
-- WHAT WAS MERGED, AND WHAT WAS DECIDED
--
-- 1. TOPOLOGY MODEL. Three source files had an asset table; only
--    ceb_ams_schema.sql modelled the network as a graph. That model won.
--    The flat assets.depot_id + assets.feeder_id design from
--    database_schema.sql is gone, because it cannot represent a switch
--    that sits between two depots without either double counting it or
--    arbitrarily assigning it to one feeder.
--
-- 2. LINE SEGMENTS. database_schema.sql had a separate line_segments
--    table with from_point / to_point text labels. That is now the
--    segments table, and the two text columns survive as display-only
--    landmark labels for depots not yet surveyed into nodes.
--
-- 3. DEPOT LIST. Three different depot lists existed. The 17-CSC
--    reference sheet (with page_no 01..17) is authoritative. Alternative
--    spellings are in csc_aliases; five names that appeared only in
--    ceb_ams_schema.sql and match nothing on the sheet are left
--    commented out in section 12 rather than invented into existence.
--
-- 4. TAXONOMY. The union of all three taxonomies, with type_code as the
--    stable key. Conductor types from database_schema.sql (Copper,
--    Weasel, Raccoon, Lynx, Zebra) are kept alongside the Fly and ABC
--    types from expand_asset_types.sql. Substations keep both the
--    kVA-split types and the generic Distribution / Grid types.
--
-- 5. TRANSFORMERS. Given their own table rather than being forced into
--    assets, because the sheet is a nameplate inventory with no node to
--    attach to. transformers.csc_id makes them countable today;
--    transformers.node_id lets them join the graph later with no
--    migration. Two rows the source marked as removed are imported with
--    status RETIRED rather than dropped, so their SIN numbers stay
--    searchable.
--
-- 6. USERS AND ROLES. The five-value role list from database_schema.sql
--    merged into the roles table from ceb_ams_schema.sql, so roles stay
--    editable data instead of being frozen in an ENUM.
--
-- END OF SCHEMA
-- =====================================================================
