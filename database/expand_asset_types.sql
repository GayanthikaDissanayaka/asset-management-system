-- =====================================================================
-- Expand asset taxonomy: run this in phpMyAdmin's SQL tab
-- (Databases > ceb_uva_assets > SQL), or import as a .sql file.
-- Safe to re-run: uses INSERT IGNORE, so already-existing rows are skipped.
-- =====================================================================

USE ceb_uva_assets;

-- ---------------------------------------------------------------------
-- 1. Substation split by capacity (kVA ratings)
-- ---------------------------------------------------------------------
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, '100kVA Substation', 'nos', FALSE FROM asset_categories WHERE category_name = 'Substation';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, '160kVA Substation', 'nos', FALSE FROM asset_categories WHERE category_name = 'Substation';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, '250kVA Substation', 'nos', FALSE FROM asset_categories WHERE category_name = 'Substation';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, '400kVA Substation', 'nos', FALSE FROM asset_categories WHERE category_name = 'Substation';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, '630kVA Substation', 'nos', FALSE FROM asset_categories WHERE category_name = 'Substation';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, '1000kVA Substation', 'nos', FALSE FROM asset_categories WHERE category_name = 'Substation';

-- Gantry (structure at the substation)
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Gantry', 'nos', FALSE FROM asset_categories WHERE category_name = 'Substation';

-- ---------------------------------------------------------------------
-- 2. Switchgear split by operation/type
-- ---------------------------------------------------------------------
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Remote Switch', 'nos', FALSE FROM asset_categories WHERE category_name = 'Switchgear';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Manual Switch', 'nos', FALSE FROM asset_categories WHERE category_name = 'Switchgear';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'AR (Auto Recloser)', 'nos', FALSE FROM asset_categories WHERE category_name = 'Switchgear';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'LBS', 'nos', FALSE FROM asset_categories WHERE category_name = 'Switchgear';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'DDLO', 'nos', FALSE FROM asset_categories WHERE category_name = 'Switchgear';

-- ---------------------------------------------------------------------
-- 3. Conductor: make sure Fly and ABC exist (harmless if already present)
-- ---------------------------------------------------------------------
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Fly', 'km', TRUE FROM asset_categories WHERE category_name = 'Conductor';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'ABC', 'km', TRUE FROM asset_categories WHERE category_name = 'Conductor';

-- ---------------------------------------------------------------------
-- 4. Poles: Wooden and RC (Reinforced Concrete)
-- ---------------------------------------------------------------------
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Wooden', 'nos', FALSE FROM asset_categories WHERE category_name = 'Pole';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'RC', 'nos', FALSE FROM asset_categories WHERE category_name = 'Pole';

-- ---------------------------------------------------------------------
-- 5. Power Line: split by structure type (pole-mounted vs tower-mounted)
-- ---------------------------------------------------------------------
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Pole Line', 'km', TRUE FROM asset_categories WHERE category_name = 'Power Line';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Tower Line', 'km', TRUE FROM asset_categories WHERE category_name = 'Power Line';

-- ---------------------------------------------------------------------
-- 6. New asset categories: Boundary Meter, Bulk Supply, Mini Hydro, Solar Plant
-- ---------------------------------------------------------------------
INSERT IGNORE INTO asset_categories (category_name) VALUES ('Boundary Meter');
INSERT IGNORE INTO asset_categories (category_name) VALUES ('Bulk Supply');
INSERT IGNORE INTO asset_categories (category_name) VALUES ('Mini Hydro');
INSERT IGNORE INTO asset_categories (category_name) VALUES ('Solar Plant');

INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Boundary Meter', 'nos', FALSE FROM asset_categories WHERE category_name = 'Boundary Meter';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Bulk Supply Point', 'nos', FALSE FROM asset_categories WHERE category_name = 'Bulk Supply';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Mini Hydro Plant', 'nos', FALSE FROM asset_categories WHERE category_name = 'Mini Hydro';
INSERT IGNORE INTO asset_types (category_id, type_name, unit_of_measure, is_line_asset)
SELECT category_id, 'Solar PV Plant', 'nos', FALSE FROM asset_categories WHERE category_name = 'Solar Plant';

-- ---------------------------------------------------------------------
-- Check the results
-- ---------------------------------------------------------------------
SELECT ac.category_name, at.type_name, at.unit_of_measure, at.is_line_asset
FROM asset_types at
JOIN asset_categories ac ON at.category_id = ac.category_id
ORDER BY ac.category_name, at.type_name;
