-- =====================================================================
-- CEB Uva Province — Network Asset Management System
-- Database: MySQL 8.x (works in phpMyAdmin / XAMPP)
-- =====================================================================
-- Hierarchy modeled from field notes:
--   Province -> Area (5) -> Depot/CSC (17) -> Feeder -> Segment/Asset
--   Asset Category -> Asset Type -> Quantity/Unit
--
-- Depot total  = SUM(assets) where depot_id = X
-- Area total   = SUM(depot totals) where area_id = X
-- Province total = SUM(area totals)
-- =====================================================================

CREATE DATABASE IF NOT EXISTS ceb_uva_assets
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ceb_uva_assets;

SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------
-- 1. ORGANIZATIONAL HIERARCHY
-- ---------------------------------------------------------------------

CREATE TABLE provinces (
    province_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    province_name   VARCHAR(100) NOT NULL UNIQUE,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE areas (
    area_id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    province_id     INT UNSIGNED NOT NULL,
    area_no         TINYINT UNSIGNED NOT NULL,     -- 01..05 from your reference sheet
    area_name       VARCHAR(100) NOT NULL,          -- Mahiyanganaya, Badulla, Diyathalawa, Monaragala, Wellawaya
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (province_id) REFERENCES provinces(province_id) ON DELETE CASCADE,
    UNIQUE KEY uq_area (province_id, area_name)
) ENGINE=InnoDB;

CREATE TABLE depots (
    depot_id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    area_id         INT UNSIGNED NOT NULL,
    csc_name        VARCHAR(100) NOT NULL,          -- e.g. Rideemaliyadda, Passara, Ella
    csc_code        VARCHAR(20)  NULL,               -- internal short code if CEB has one
    page_no         VARCHAR(10)  NULL,               -- links to the single-line-diagram book (01..17)
    latitude        DECIMAL(10,7) NULL,
    longitude       DECIMAL(10,7) NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (area_id) REFERENCES areas(area_id) ON DELETE CASCADE,
    UNIQUE KEY uq_depot (area_id, csc_name)
) ENGINE=InnoDB;

-- 33kV feeders coming out of each CSC/substation (F1, F2, F3 ... from your notes)
CREATE TABLE feeders (
    feeder_id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    depot_id        INT UNSIGNED NOT NULL,
    feeder_code     VARCHAR(20) NOT NULL,            -- F1, F2, F3
    feeder_name     VARCHAR(100) NULL,               -- e.g. "Town", "Nonwakula"
    voltage_kv      DECIMAL(5,2) DEFAULT 33.00,
    status          ENUM('active','proposed','decommissioned') DEFAULT 'active',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (depot_id) REFERENCES depots(depot_id) ON DELETE CASCADE,
    UNIQUE KEY uq_feeder (depot_id, feeder_code)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. ASSET TAXONOMY
-- ---------------------------------------------------------------------

CREATE TABLE asset_categories (
    category_id     INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    category_name   VARCHAR(100) NOT NULL UNIQUE,   -- Transformer, Substation, Switchgear, Cable, Conductor, Pole, Power Line
    description     VARCHAR(255) NULL
) ENGINE=InnoDB;

CREATE TABLE asset_types (
    type_id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    category_id     INT UNSIGNED NOT NULL,
    type_name       VARCHAR(100) NOT NULL,          -- Distribution Transformer, LBS, RMU, Isolator, Concrete Pole...
    unit_of_measure ENUM('nos','km','m','kVA') DEFAULT 'nos',
    is_line_asset   BOOLEAN DEFAULT FALSE,           -- TRUE for conductors/lines measured by length via segments
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES asset_categories(category_id) ON DELETE CASCADE,
    UNIQUE KEY uq_type (category_id, type_name)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. ASSET REGISTER (point assets: transformers, poles, switches, etc.)
-- ---------------------------------------------------------------------

CREATE TABLE users (
    user_id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    email           VARCHAR(150) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    role            ENUM('admin','area_engineer','depot_engineer','field_technician','viewer') NOT NULL,
    depot_id        INT UNSIGNED NULL,               -- home depot, if applicable
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (depot_id) REFERENCES depots(depot_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE assets (
    asset_id        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    segment_no      VARCHAR(30) NOT NULL,            -- natural/business key, e.g. "1SOM-011" style code from as-built diagrams
    asset_type_id   INT UNSIGNED NOT NULL,
    depot_id        INT UNSIGNED NOT NULL,
    feeder_id       INT UNSIGNED NULL,
    quantity        DECIMAL(10,3) NOT NULL DEFAULT 1, -- e.g. 1 transformer, or km for a line stretch
    capacity_kva    DECIMAL(10,2) NULL,               -- for transformers/substations
    material        VARCHAR(50)  NULL,                -- Concrete/Wooden for poles, Copper/ACSR type for conductors
    latitude        DECIMAL(10,7) NULL,
    longitude       DECIMAL(10,7) NULL,
    status          ENUM('active','faulty','under_repair','decommissioned') DEFAULT 'active',
    installed_date  DATE NULL,
    installed_by    INT UNSIGNED NULL,
    last_verified_by INT UNSIGNED NULL,
    last_verified_at DATETIME NULL,
    remarks         TEXT NULL,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (asset_type_id) REFERENCES asset_types(type_id),
    FOREIGN KEY (depot_id) REFERENCES depots(depot_id) ON DELETE CASCADE,
    FOREIGN KEY (feeder_id) REFERENCES feeders(feeder_id) ON DELETE SET NULL,
    FOREIGN KEY (installed_by) REFERENCES users(user_id) ON DELETE SET NULL,
    FOREIGN KEY (last_verified_by) REFERENCES users(user_id) ON DELETE SET NULL,
    UNIQUE KEY uq_segment (depot_id, segment_no),
    INDEX idx_asset_type (asset_type_id),
    INDEX idx_asset_depot (depot_id),
    INDEX idx_asset_feeder (feeder_id),
    INDEX idx_asset_location (latitude, longitude)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. LINE SEGMENTS (MV/LV conductor runs — measured by length, not count)
-- ---------------------------------------------------------------------

CREATE TABLE line_segments (
    segment_id      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    segment_code    VARCHAR(30) NOT NULL,
    feeder_id       INT UNSIGNED NOT NULL,
    asset_type_id   INT UNSIGNED NOT NULL,           -- points to Conductor type (Copper, Weasel, Raccoon, Lynx, Fly, Zebra, ABC)
    voltage_level   ENUM('LV','MV','HV') NOT NULL,
    from_point      VARCHAR(150) NULL,
    to_point        VARCHAR(150) NULL,
    length_km       DECIMAL(8,3) NOT NULL,
    status          ENUM('active','faulty','proposed','decommissioned') DEFAULT 'active',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (feeder_id) REFERENCES feeders(feeder_id) ON DELETE CASCADE,
    FOREIGN KEY (asset_type_id) REFERENCES asset_types(type_id),
    UNIQUE KEY uq_segment_code (feeder_id, segment_code),
    INDEX idx_seg_voltage (voltage_level)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. MAINTENANCE / ACTIVITY LOG (who touched what, and when)
-- ---------------------------------------------------------------------

CREATE TABLE maintenance_logs (
    log_id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    asset_id        BIGINT UNSIGNED NULL,
    segment_id      BIGINT UNSIGNED NULL,
    action_type     ENUM('installed','inspected','repaired','replaced','decommissioned') NOT NULL,
    performed_by    INT UNSIGNED NOT NULL,
    performed_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    remarks         TEXT NULL,
    photo_path      VARCHAR(255) NULL,
    FOREIGN KEY (asset_id) REFERENCES assets(asset_id) ON DELETE CASCADE,
    FOREIGN KEY (segment_id) REFERENCES line_segments(segment_id) ON DELETE CASCADE,
    FOREIGN KEY (performed_by) REFERENCES users(user_id),
    INDEX idx_log_asset (asset_id),
    INDEX idx_log_segment (segment_id),
    INDEX idx_log_date (performed_at),
    CONSTRAINT chk_log_target CHECK (asset_id IS NOT NULL OR segment_id IS NOT NULL)
) ENGINE=InnoDB;

SET FOREIGN_KEY_CHECKS = 1;

-- =====================================================================
-- 6. SEED DATA — organizational hierarchy from your notes
-- =====================================================================

INSERT INTO provinces (province_name) VALUES ('Uva');

INSERT INTO areas (province_id, area_no, area_name) VALUES
(1, 1, 'Mahiyanganaya'),
(1, 2, 'Badulla'),
(1, 3, 'Diyathalawa'),
(1, 4, 'Monaragala'),
(1, 5, 'Wellawaya');

INSERT INTO depots (area_id, csc_name, page_no) VALUES
(1, 'Mahiyanganaya', '01'),
(1, 'Rideemaliyadda', '02'),
(1, 'Kandaketiya', '03'),
(2, 'Badulla', '04'),
(2, 'Haliela', '05'),
(2, 'Passara', '06'),
(3, 'Diyathalawa', '07'),
(3, 'Bandarawela', '08'),
(3, 'Welimada', '09'),
(3, 'Uva-paranagama', '10'),
(3, 'Ella', '11'),
(4, 'Monaragala', '12'),
(4, 'Dambagalla', '13'),
(4, 'Bibila', '14'),
(5, 'Wellawaya', '15'),
(5, 'Buttala', '16'),
(5, 'Thanamalwila', '17');

-- Asset categories
INSERT INTO asset_categories (category_name) VALUES
('Transformer'),
('Substation'),
('Switchgear'),
('Cable'),
('Conductor'),
('Pole'),
('Power Line');

-- Asset types per category (from your "Assets" and "Conductors" notes)
INSERT INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset) VALUES
(1, 'Distribution Transformer', 'nos', FALSE),
(2, 'Distribution Substation', 'nos', FALSE),
(2, 'Grid Substation', 'nos', FALSE),
(3, 'LBS (Load Break Switch)', 'nos', FALSE),
(3, 'RMU (Ring Main Unit)', 'nos', FALSE),
(3, 'Isolator', 'nos', FALSE),
(4, 'Underground Cable', 'km', TRUE),
(5, 'Copper Conductor', 'km', TRUE),
(5, 'Weasel Conductor', 'km', TRUE),
(5, 'Raccoon Conductor', 'km', TRUE),
(5, 'Lynx Conductor', 'km', TRUE),
(5, 'Fly Conductor', 'km', TRUE),
(5, 'Zebra Conductor', 'km', TRUE),
(5, 'ABC (Aerial Bundled Cable)', 'km', TRUE),
(6, 'Concrete Pole', 'nos', FALSE),
(6, 'Wooden Pole', 'nos', FALSE),
(7, 'LV Line', 'km', TRUE),
(7, 'MV Line', 'km', TRUE),
(7, 'HV Line', 'km', TRUE);

-- =====================================================================
-- 7. DASHBOARD SUMMARY VIEWS
--    These give you the depot -> area -> province roll-up directly.
-- =====================================================================

-- Depot-wise asset count, broken down by category/type
CREATE OR REPLACE VIEW vw_depot_asset_summary AS
SELECT
    d.depot_id,
    d.csc_name       AS depot_name,
    a.area_id,
    a.area_name,
    ac.category_id,
    ac.category_name,
    at.type_id,
    at.type_name,
    at.unit_of_measure,
    SUM(ast.quantity) AS total_quantity
FROM assets ast
JOIN asset_types at        ON ast.asset_type_id = at.type_id
JOIN asset_categories ac   ON at.category_id = ac.category_id
JOIN depots d               ON ast.depot_id = d.depot_id
JOIN areas a                ON d.area_id = a.area_id
GROUP BY d.depot_id, ac.category_id, at.type_id;

-- Depot totals across ALL asset types (single number per depot)
CREATE OR REPLACE VIEW vw_depot_totals AS
SELECT depot_id, depot_name, area_id, area_name, SUM(total_quantity) AS depot_total
FROM vw_depot_asset_summary
GROUP BY depot_id;

-- Area totals (sum of depot totals belonging to that area)
CREATE OR REPLACE VIEW vw_area_totals AS
SELECT area_id, area_name, SUM(depot_total) AS area_total
FROM vw_depot_totals
GROUP BY area_id;

-- Province total (sum of all 17 depot totals)
CREATE OR REPLACE VIEW vw_province_total AS
SELECT SUM(depot_total) AS province_total FROM vw_depot_totals;

-- Line-asset (conductor) length roll-up, depot-wise, since these are km not "nos"
CREATE OR REPLACE VIEW vw_depot_line_length_summary AS
SELECT
    d.depot_id,
    d.csc_name AS depot_name,
    ls.voltage_level,
    at.type_name AS conductor_type,
    SUM(ls.length_km) AS total_length_km
FROM line_segments ls
JOIN feeders f      ON ls.feeder_id = f.feeder_id
JOIN depots d       ON f.depot_id = d.depot_id
JOIN asset_types at ON ls.asset_type_id = at.type_id
GROUP BY d.depot_id, ls.voltage_level, at.type_id;

-- "Last touched" view — who last worked on each asset (for the handover problem you described)
CREATE OR REPLACE VIEW vw_asset_last_activity AS
SELECT
    ast.asset_id,
    ast.segment_no,
    d.csc_name AS depot_name,
    at.type_name,
    ml.action_type,
    u.name AS performed_by,
    ml.performed_at
FROM assets ast
JOIN depots d ON ast.depot_id = d.depot_id
JOIN asset_types at ON ast.asset_type_id = at.type_id
LEFT JOIN maintenance_logs ml ON ml.asset_id = ast.asset_id
LEFT JOIN users u ON ml.performed_by = u.user_id
WHERE ml.log_id = (
    SELECT MAX(ml2.log_id) FROM maintenance_logs ml2 WHERE ml2.asset_id = ast.asset_id
) OR ml.log_id IS NULL;
