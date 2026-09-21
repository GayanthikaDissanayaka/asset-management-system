-- =====================================================================
-- Column comments for ceb_uva_ams
--
-- Adds a description to every column of every real table, so anyone
-- opening the database in phpMyAdmin can read what a column means
-- without reading the application. Nothing else changes: no column
-- type, no key, no constraint, no row.
--
-- Each statement re-states the column's definition EXACTLY as it stands
-- in database/ceb_uva_ams.sql, because MySQL has no COMMENT ON COLUMN
-- and MODIFY COLUMN is the only way to attach one. Re-typing a
-- definition by hand is how a varchar(30) quietly becomes a
-- varchar(20), so these were copied from the schema, not written out.
--
-- HOW TO RUN
--   phpMyAdmin -> ceb_uva_ams -> Import -> this file
--   or:  mysql -u root ceb_uva_ams < database/add-column-comments.sql
--
-- Safe to run more than once: setting the same comment twice is the
-- same as setting it once.
--
-- The narrative version, with the table relationships, is in
-- docs/data-dictionary.md. When you change a column's meaning, change
-- it in both.
-- =====================================================================


-- ------------------------------------------------------------------
-- areas
-- ------------------------------------------------------------------
ALTER TABLE `areas` MODIFY COLUMN `area_no` tinyint(3) unsigned NOT NULL COMMENT 'CEB''s own area numbering from the source workbook.';
ALTER TABLE `areas` MODIFY COLUMN `area_code` varchar(10) NOT NULL COMMENT 'Short code used across the UI, e.g. BDL.';
ALTER TABLE `areas` MODIFY COLUMN `area_name` varchar(100) NOT NULL COMMENT 'Display name, e.g. Badulla.';
ALTER TABLE `areas` MODIFY COLUMN `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '0 hides it from the pickers without deleting it.';
ALTER TABLE `areas` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';

-- ------------------------------------------------------------------
-- asset_categories
-- ------------------------------------------------------------------
ALTER TABLE `asset_categories` MODIFY COLUMN `category_code` varchar(20) NOT NULL COMMENT 'Short code.';
ALTER TABLE `asset_categories` MODIFY COLUMN `category_name` varchar(80) NOT NULL COMMENT 'Display name; the "Main asset" column in the UI.';
ALTER TABLE `asset_categories` MODIFY COLUMN `description` varchar(255) DEFAULT NULL COMMENT 'What belongs in this category.';
ALTER TABLE `asset_categories` MODIFY COLUMN `display_order` smallint(5) unsigned NOT NULL DEFAULT 100 COMMENT 'Sort order in the UI. Lower first.';
ALTER TABLE `asset_categories` MODIFY COLUMN `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '0 hides it without deleting it.';

-- ------------------------------------------------------------------
-- asset_types
-- ------------------------------------------------------------------
ALTER TABLE `asset_types` MODIFY COLUMN `type_code` varchar(30) NOT NULL COMMENT 'Short code, used in asset_code and to derive transformers.transformer_type.';
ALTER TABLE `asset_types` MODIFY COLUMN `type_name` varchar(100) NOT NULL COMMENT 'Display name.';
ALTER TABLE `asset_types` MODIFY COLUMN `unit_of_measure` enum('nos','km','m','kVA','kW') NOT NULL DEFAULT 'nos' COMMENT 'THE AUTHORITY ON UNITS: ''nos'' for counted things, ''km'' for measured line. Every write path reads the unit from HERE and never from the request, so no entry can put kilometres in a column the roll-ups add up as a count.';
ALTER TABLE `asset_types` MODIFY COLUMN `is_line_asset` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 for things measured along the line rather than counted at a point.';
ALTER TABLE `asset_types` MODIFY COLUMN `rated_kva` int(10) unsigned DEFAULT NULL COMMENT 'Nameplate rating where the type has a fixed one. NULL otherwise.';
ALTER TABLE `asset_types` MODIFY COLUMN `allow_decimal` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 when a fractional quantity is meaningful, e.g. km. 0 for whole counts like poles.';
ALTER TABLE `asset_types` MODIFY COLUMN `display_order` smallint(5) unsigned NOT NULL DEFAULT 100 COMMENT 'Sort order in the UI. Lower first.';
ALTER TABLE `asset_types` MODIFY COLUMN `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '0 hides it from the pickers without deleting it.';
ALTER TABLE `asset_types` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';

-- ------------------------------------------------------------------
-- assets
-- ------------------------------------------------------------------
ALTER TABLE `assets` MODIFY COLUMN `asset_code` varchar(40) DEFAULT NULL COMMENT 'Human-readable code, generated on insert as {csc_code}-{type_code}-{next number}. This is the identifier to quote, not asset_id.';
ALTER TABLE `assets` MODIFY COLUMN `quantity` decimal(12,3) NOT NULL DEFAULT 1.000 COMMENT 'How many, or how far. Read with unit_of_measure; the two are meaningless apart.';
ALTER TABLE `assets` MODIFY COLUMN `unit_of_measure` enum('nos','km','m','kVA','kW') NOT NULL DEFAULT 'nos' COMMENT 'Copied from asset_types on insert. ''nos'' or ''km''. NEVER add across different units.';
ALTER TABLE `assets` MODIFY COLUMN `capacity_kva` decimal(10,2) DEFAULT NULL COMMENT 'Nameplate rating for this holding, where the type has one.';
ALTER TABLE `assets` MODIFY COLUMN `material` varchar(50) DEFAULT NULL COMMENT 'Material where it distinguishes otherwise identical items, e.g. pole type.';
ALTER TABLE `assets` MODIFY COLUMN `install_date` date DEFAULT NULL COMMENT 'When it went in, if known.';
ALTER TABLE `assets` MODIFY COLUMN `condition_status` enum('NEW','GOOD','FAIR','POOR','FAULTY','UNKNOWN') NOT NULL DEFAULT 'UNKNOWN' COMMENT 'NEW, GOOD, FAIR, POOR, FAULTY or UNKNOWN.';
ALTER TABLE `assets` MODIFY COLUMN `status` enum('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE, PLANNED or RETIRED.';
ALTER TABLE `assets` MODIFY COLUMN `remarks` varchar(500) DEFAULT NULL COMMENT 'Free text.';
ALTER TABLE `assets` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';
ALTER TABLE `assets` MODIFY COLUMN `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Row last changed.';
ALTER TABLE `assets` MODIFY COLUMN `last_verified_at` datetime DEFAULT NULL COMMENT 'When it was last checked on the ground.';

-- ------------------------------------------------------------------
-- assets_used
-- ------------------------------------------------------------------
ALTER TABLE `assets_used` MODIFY COLUMN `quantity` decimal(12,3) NOT NULL COMMENT 'How many, or how far, in this line of the entry.';
ALTER TABLE `assets_used` MODIFY COLUMN `unit_of_measure` enum('nos','km','m','kVA','kW') NOT NULL DEFAULT 'nos' COMMENT '''nos'' or ''km'', copied from asset_types.';
ALTER TABLE `assets_used` MODIFY COLUMN `condition_status` enum('NEW','GOOD','FAIR','POOR','FAULTY','UNKNOWN') NOT NULL DEFAULT 'UNKNOWN' COMMENT 'Condition as entered.';
ALTER TABLE `assets_used` MODIFY COLUMN `capacity_kva` decimal(10,2) DEFAULT NULL COMMENT 'Rating as entered.';
ALTER TABLE `assets_used` MODIFY COLUMN `used_on` date DEFAULT NULL COMMENT 'The date entered on the form, if any.';
ALTER TABLE `assets_used` MODIFY COLUMN `used_for` varchar(500) DEFAULT NULL COMMENT 'Free-text note from the form.';
ALTER TABLE `assets_used` MODIFY COLUMN `batch_ref` char(32) NOT NULL COMMENT 'One random reference shared by every line of a single submission, so an entry can be read back as the one act it was.';
ALTER TABLE `assets_used` MODIFY COLUMN `recorded_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'When it was entered.';

-- ------------------------------------------------------------------
-- audit_log
-- ------------------------------------------------------------------
ALTER TABLE `audit_log` MODIFY COLUMN `table_name` varchar(64) NOT NULL COMMENT 'Table that changed.';
ALTER TABLE `audit_log` MODIFY COLUMN `action` enum('INSERT','UPDATE','DELETE') NOT NULL COMMENT 'INSERT, UPDATE or DELETE.';
ALTER TABLE `audit_log` MODIFY COLUMN `changed_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'When.';
ALTER TABLE `audit_log` MODIFY COLUMN `old_values` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'JSON of the row before. NULL for an insert.' CHECK (json_valid(`old_values`));
ALTER TABLE `audit_log` MODIFY COLUMN `new_values` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'JSON of the row after. NULL for a delete.' CHECK (json_valid(`new_values`));
ALTER TABLE `audit_log` MODIFY COLUMN `ip_address` varchar(45) DEFAULT NULL COMMENT 'Where the request came from.';
ALTER TABLE `audit_log` MODIFY COLUMN `note` varchar(255) DEFAULT NULL COMMENT 'Free text.';

-- ------------------------------------------------------------------
-- csc_aliases
-- ------------------------------------------------------------------
ALTER TABLE `csc_aliases` MODIFY COLUMN `alias_name` varchar(100) NOT NULL COMMENT 'The name as written in the source file.';
ALTER TABLE `csc_aliases` MODIFY COLUMN `source_file` varchar(80) DEFAULT NULL COMMENT 'Which file used this spelling.';

-- ------------------------------------------------------------------
-- csc_depots
-- ------------------------------------------------------------------
ALTER TABLE `csc_depots` MODIFY COLUMN `csc_code` varchar(15) NOT NULL COMMENT 'Short code used across the UI and in asset_code.';
ALTER TABLE `csc_depots` MODIFY COLUMN `csc_name` varchar(100) NOT NULL COMMENT 'Display name.';
ALTER TABLE `csc_depots` MODIFY COLUMN `depot_type` enum('CSC','DEPOT','SUB_DEPOT') NOT NULL DEFAULT 'CSC' COMMENT 'CSC or depot.';
ALTER TABLE `csc_depots` MODIFY COLUMN `page_no` varchar(10) DEFAULT NULL COMMENT 'Page in the source workbook this CSC was read from.';
ALTER TABLE `csc_depots` MODIFY COLUMN `contact_officer` varchar(100) DEFAULT NULL COMMENT 'Officer responsible. Free text.';
ALTER TABLE `csc_depots` MODIFY COLUMN `contact_phone` varchar(25) DEFAULT NULL COMMENT 'Contact number. Free text.';
ALTER TABLE `csc_depots` MODIFY COLUMN `latitude` decimal(10,7) DEFAULT NULL COMMENT 'Decimal degrees, WGS84. NULL where not surveyed.';
ALTER TABLE `csc_depots` MODIFY COLUMN `longitude` decimal(10,7) DEFAULT NULL COMMENT 'Decimal degrees, WGS84. NULL where not surveyed.';
ALTER TABLE `csc_depots` MODIFY COLUMN `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '0 hides it from the pickers without deleting it.';
ALTER TABLE `csc_depots` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';

-- ------------------------------------------------------------------
-- feeders
-- ------------------------------------------------------------------
ALTER TABLE `feeders` MODIFY COLUMN `feeder_code` varchar(30) NOT NULL COMMENT 'Short code, the name people use for it.';
ALTER TABLE `feeders` MODIFY COLUMN `feeder_name` varchar(120) NOT NULL COMMENT 'Full name.';
ALTER TABLE `feeders` MODIFY COLUMN `source_name` varchar(120) DEFAULT NULL COMMENT 'Grid substation feeding it.';
ALTER TABLE `feeders` MODIFY COLUMN `external_source` varchar(80) DEFAULT NULL COMMENT '1 when fed from outside the province.';
ALTER TABLE `feeders` MODIFY COLUMN `voltage_level` enum('33kV','11kV','400V') NOT NULL DEFAULT '33kV' COMMENT '33kV, 11kV or 400V.';
ALTER TABLE `feeders` MODIFY COLUMN `status` enum('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE, PLANNED or RETIRED.';
ALTER TABLE `feeders` MODIFY COLUMN `remarks` varchar(255) DEFAULT NULL COMMENT 'Free text.';
ALTER TABLE `feeders` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';
ALTER TABLE `feeders` MODIFY COLUMN `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Row last changed.';

-- ------------------------------------------------------------------
-- id_sequences
-- ------------------------------------------------------------------
ALTER TABLE `id_sequences` MODIFY COLUMN `description` varchar(120) NOT NULL COMMENT 'What the table holds, in a few words, for whoever opens this table first.';

-- ------------------------------------------------------------------
-- maintenance_logs
-- ------------------------------------------------------------------
ALTER TABLE `maintenance_logs` MODIFY COLUMN `action_type` enum('installed','inspected','repaired','replaced','relocated','decommissioned') NOT NULL COMMENT 'What was done.';
ALTER TABLE `maintenance_logs` MODIFY COLUMN `performed_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'When it was done.';
ALTER TABLE `maintenance_logs` MODIFY COLUMN `remarks` text DEFAULT NULL COMMENT 'Free text.';
ALTER TABLE `maintenance_logs` MODIFY COLUMN `photo_path` varchar(255) DEFAULT NULL COMMENT 'Path to a photograph, where one was taken.';
ALTER TABLE `maintenance_logs` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';

-- ------------------------------------------------------------------
-- network_nodes
-- ------------------------------------------------------------------
ALTER TABLE `network_nodes` MODIFY COLUMN `node_code` varchar(30) NOT NULL COMMENT 'Code for the point.';
ALTER TABLE `network_nodes` MODIFY COLUMN `node_kind` enum('GANTRY','SUBSTATION','SWITCH_POSITION','TEE_OFF','DEAD_END','BOUNDARY','BULK_SUPPLY','GENERATION','JUNCTION') NOT NULL COMMENT 'What sort of point it is.';
ALTER TABLE `network_nodes` MODIFY COLUMN `name` varchar(150) NOT NULL COMMENT 'Display name.';
ALTER TABLE `network_nodes` MODIFY COLUMN `latitude` decimal(10,7) DEFAULT NULL COMMENT 'Decimal degrees, WGS84.';
ALTER TABLE `network_nodes` MODIFY COLUMN `longitude` decimal(10,7) DEFAULT NULL COMMENT 'Decimal degrees, WGS84.';
ALTER TABLE `network_nodes` MODIFY COLUMN `ownership_source` enum('UPSTREAM_RULE','MANUAL_OVERRIDE','GEOGRAPHIC') NOT NULL DEFAULT 'UPSTREAM_RULE' COMMENT 'Who owns or maintains it.';
ALTER TABLE `network_nodes` MODIFY COLUMN `ownership_note` varchar(500) DEFAULT NULL COMMENT 'Free text about ownership.';
ALTER TABLE `network_nodes` MODIFY COLUMN `is_line_end` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 when the line stops here.';
ALTER TABLE `network_nodes` MODIFY COLUMN `status` enum('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE, PLANNED or RETIRED.';
ALTER TABLE `network_nodes` MODIFY COLUMN `remarks` varchar(255) DEFAULT NULL COMMENT 'Free text.';
ALTER TABLE `network_nodes` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';
ALTER TABLE `network_nodes` MODIFY COLUMN `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Row last changed.';

-- ------------------------------------------------------------------
-- node_shared_with
-- ------------------------------------------------------------------
ALTER TABLE `node_shared_with` MODIFY COLUMN `share_reason` varchar(255) DEFAULT NULL COMMENT 'Why it is shared.';
ALTER TABLE `node_shared_with` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';

-- ------------------------------------------------------------------
-- notifications
-- ------------------------------------------------------------------
ALTER TABLE `notifications` MODIFY COLUMN `type` varchar(40) NOT NULL COMMENT 'What kind of notice it is.';
ALTER TABLE `notifications` MODIFY COLUMN `title` varchar(160) NOT NULL COMMENT 'Headline shown in the bell.';
ALTER TABLE `notifications` MODIFY COLUMN `body` varchar(500) DEFAULT NULL COMMENT 'Longer text.';
ALTER TABLE `notifications` MODIFY COLUMN `link` varchar(200) DEFAULT NULL COMMENT 'Where selecting it takes you.';
ALTER TABLE `notifications` MODIFY COLUMN `status` enum('OPEN','RESOLVED') NOT NULL DEFAULT 'OPEN' COMMENT 'Whether it still needs action.';
ALTER TABLE `notifications` MODIFY COLUMN `resolution` varchar(20) DEFAULT NULL COMMENT 'What was decided, once it does not.';
ALTER TABLE `notifications` MODIFY COLUMN `read_at` datetime DEFAULT NULL COMMENT 'When the recipient opened it. NULL means unread, which is what the bell counts.';
ALTER TABLE `notifications` MODIFY COLUMN `resolved_at` datetime DEFAULT NULL COMMENT 'When it was acted on.';
ALTER TABLE `notifications` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';

-- ------------------------------------------------------------------
-- password_resets
-- ------------------------------------------------------------------
ALTER TABLE `password_resets` MODIFY COLUMN `token_hash` char(64) NOT NULL COMMENT 'Hash of the emailed token. Never the token itself.';
ALTER TABLE `password_resets` MODIFY COLUMN `expires_at` datetime NOT NULL COMMENT 'After this the token is refused.';
ALTER TABLE `password_resets` MODIFY COLUMN `used_at` datetime DEFAULT NULL COMMENT 'When it was spent. A token is single-use.';
ALTER TABLE `password_resets` MODIFY COLUMN `requested_ip` varchar(45) DEFAULT NULL COMMENT 'Where the request came from.';
ALTER TABLE `password_resets` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';

-- ------------------------------------------------------------------
-- personal_access_tokens
-- ------------------------------------------------------------------
ALTER TABLE `personal_access_tokens` MODIFY COLUMN `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT COMMENT 'PK. Laravel Sanctum API tokens. Framework table -- do not hand-edit.';
ALTER TABLE `personal_access_tokens` MODIFY COLUMN `tokenable_type` varchar(255) NOT NULL COMMENT 'Model class the token belongs to.';
ALTER TABLE `personal_access_tokens` MODIFY COLUMN `name` text NOT NULL COMMENT 'Label for the token.';
ALTER TABLE `personal_access_tokens` MODIFY COLUMN `token` varchar(64) NOT NULL COMMENT 'Hash of the token. Never the token itself.';
ALTER TABLE `personal_access_tokens` MODIFY COLUMN `abilities` text DEFAULT NULL COMMENT 'What the token may do.';
ALTER TABLE `personal_access_tokens` MODIFY COLUMN `last_used_at` timestamp NULL DEFAULT NULL COMMENT 'Last request that presented it.';
ALTER TABLE `personal_access_tokens` MODIFY COLUMN `expires_at` timestamp NULL DEFAULT NULL COMMENT 'After this the token is refused.';
ALTER TABLE `personal_access_tokens` MODIFY COLUMN `created_at` timestamp NULL DEFAULT NULL COMMENT 'Row created.';
ALTER TABLE `personal_access_tokens` MODIFY COLUMN `updated_at` timestamp NULL DEFAULT NULL COMMENT 'Row last changed.';

-- ------------------------------------------------------------------
-- provinces
-- ------------------------------------------------------------------
ALTER TABLE `provinces` MODIFY COLUMN `province_code` varchar(10) NOT NULL COMMENT 'Short code, e.g. UVA.';
ALTER TABLE `provinces` MODIFY COLUMN `province_name` varchar(100) NOT NULL COMMENT 'Display name.';
ALTER TABLE `provinces` MODIFY COLUMN `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '0 hides it from the pickers without deleting it.';
ALTER TABLE `provinces` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';

-- ------------------------------------------------------------------
-- roles
-- ------------------------------------------------------------------
ALTER TABLE `roles` MODIFY COLUMN `role_code` varchar(20) NOT NULL COMMENT 'ADMIN, and the other codes the middleware checks. The code is what authorisation tests, never the name.';
ALTER TABLE `roles` MODIFY COLUMN `role_name` varchar(50) NOT NULL COMMENT 'Display name.';
ALTER TABLE `roles` MODIFY COLUMN `description` varchar(255) DEFAULT NULL COMMENT 'What this role may do.';

-- ------------------------------------------------------------------
-- segment_asset
-- ------------------------------------------------------------------
ALTER TABLE `segment_asset` MODIFY COLUMN `quantity` decimal(12,4) NOT NULL DEFAULT 0.0000 COMMENT 'How many, or how far. Read with unit_of_measure.';
ALTER TABLE `segment_asset` MODIFY COLUMN `unit_of_measure` enum('nos','km','m','kVA','kW') NOT NULL DEFAULT 'nos' COMMENT '''nos'' or ''km'', copied from asset_types on insert, never taken from the request.';
ALTER TABLE `segment_asset` MODIFY COLUMN `remarks` varchar(255) DEFAULT NULL COMMENT 'Free text.';
ALTER TABLE `segment_asset` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';
ALTER TABLE `segment_asset` MODIFY COLUMN `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Row last changed.';

-- ------------------------------------------------------------------
-- segment_csc
-- ------------------------------------------------------------------
ALTER TABLE `segment_csc` MODIFY COLUMN `length_km` decimal(10,4) NOT NULL DEFAULT 0.0000 COMMENT 'The kilometres of this segment INSIDE this CSC. Summing these is what makes area and province totals reconcile instead of double-counting a crossing run.';
ALTER TABLE `segment_csc` MODIFY COLUMN `remarks` varchar(255) DEFAULT NULL COMMENT 'Free text.';
ALTER TABLE `segment_csc` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';
ALTER TABLE `segment_csc` MODIFY COLUMN `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Row last changed.';

-- ------------------------------------------------------------------
-- segment_register
-- ------------------------------------------------------------------
ALTER TABLE `segment_register` MODIFY COLUMN `segment_code` varchar(30) NOT NULL COMMENT 'The code CEB uses for the run, e.g. BDSM010. Unique per CSC, not globally: two CSCs may each use the same code for their own run.';
ALTER TABLE `segment_register` MODIFY COLUMN `length_km` decimal(9,4) DEFAULT NULL COMMENT 'Total length of the whole segment. For a crossing segment this is the sum of its segment_csc parts, NOT the part inside csc_id.';
ALTER TABLE `segment_register` MODIFY COLUMN `voltage_level` enum('33kV','11kV','400V') NOT NULL DEFAULT '33kV' COMMENT '33kV, 11kV or 400V.';
ALTER TABLE `segment_register` MODIFY COLUMN `status` enum('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE, PLANNED or RETIRED.';
ALTER TABLE `segment_register` MODIFY COLUMN `remarks` text DEFAULT NULL COMMENT 'Free text.';
ALTER TABLE `segment_register` MODIFY COLUMN `source_file` varchar(80) DEFAULT NULL COMMENT '''dashboard-entry'' for a row typed into the application, otherwise the name of the imported spreadsheet.';
ALTER TABLE `segment_register` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';
ALTER TABLE `segment_register` MODIFY COLUMN `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Row last changed.';

-- ------------------------------------------------------------------
-- segment_switchgear
-- ------------------------------------------------------------------
ALTER TABLE `segment_switchgear` MODIFY COLUMN `switch_ref` varchar(30) NOT NULL COMMENT 'The switch as written on the source sheet, before it was matched to a switchgear row.';

-- ------------------------------------------------------------------
-- segment_transformer
-- ------------------------------------------------------------------
ALTER TABLE `segment_transformer` MODIFY COLUMN `transformer_ref` varchar(60) NOT NULL COMMENT 'The transformer as written on the source sheet, before it was matched to a transformer row.';

-- ------------------------------------------------------------------
-- segments
-- ------------------------------------------------------------------
ALTER TABLE `segments` MODIFY COLUMN `segment_code` varchar(30) NOT NULL COMMENT 'Code for the run.';
ALTER TABLE `segments` MODIFY COLUMN `from_point` varchar(150) DEFAULT NULL COMMENT 'Start point in words, where there is no node.';
ALTER TABLE `segments` MODIFY COLUMN `to_point` varchar(150) DEFAULT NULL COMMENT 'End point in words, where there is no node.';
ALTER TABLE `segments` MODIFY COLUMN `circuit_no` tinyint(3) unsigned NOT NULL DEFAULT 1 COMMENT 'Circuit number where a route carries more than one.';
ALTER TABLE `segments` MODIFY COLUMN `length_km` decimal(8,3) NOT NULL DEFAULT 0.000 COMMENT 'Length of the run.';
ALTER TABLE `segments` MODIFY COLUMN `voltage_level` enum('33kV','11kV','400V') NOT NULL DEFAULT '33kV' COMMENT '33kV, 11kV or 400V.';
ALTER TABLE `segments` MODIFY COLUMN `is_normally_open` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 when the run is normally open, i.e. not carrying load.';
ALTER TABLE `segments` MODIFY COLUMN `is_reversible` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 when it can be fed from either end.';
ALTER TABLE `segments` MODIFY COLUMN `status` enum('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE, PLANNED or RETIRED.';
ALTER TABLE `segments` MODIFY COLUMN `remarks` varchar(255) DEFAULT NULL COMMENT 'Free text.';
ALTER TABLE `segments` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';
ALTER TABLE `segments` MODIFY COLUMN `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Row last changed.';

-- ------------------------------------------------------------------
-- switchgear
-- ------------------------------------------------------------------
ALTER TABLE `switchgear` MODIFY COLUMN `switch_code` varchar(30) NOT NULL COMMENT 'The code on the unit. How it is referred to in the field.';
ALTER TABLE `switchgear` MODIFY COLUMN `switch_name` varchar(200) DEFAULT NULL COMMENT 'Display name.';
ALTER TABLE `switchgear` MODIFY COLUMN `nearest_substation` varchar(120) DEFAULT NULL COMMENT 'Where it is, in words.';
ALTER TABLE `switchgear` MODIFY COLUMN `status` enum('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE, PLANNED or RETIRED.';
ALTER TABLE `switchgear` MODIFY COLUMN `remarks` text DEFAULT NULL COMMENT 'Free text.';
ALTER TABLE `switchgear` MODIFY COLUMN `source_file` varchar(80) DEFAULT NULL COMMENT '''dashboard-entry'' or the name of the imported file.';
ALTER TABLE `switchgear` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';
ALTER TABLE `switchgear` MODIFY COLUMN `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Row last changed.';

-- ------------------------------------------------------------------
-- transformers
-- ------------------------------------------------------------------
ALTER TABLE `transformers` MODIFY COLUMN `old_sin_no` varchar(40) DEFAULT NULL COMMENT 'CEB''s previous SIN number. Either SIN may be blank; the pair is how a unit is looked up.';
ALTER TABLE `transformers` MODIFY COLUMN `new_sin_no` varchar(40) DEFAULT NULL COMMENT 'CEB''s current SIN number.';
ALTER TABLE `transformers` MODIFY COLUMN `substation_name` varchar(255) NOT NULL COMMENT 'The substation this unit serves.';
ALTER TABLE `transformers` MODIFY COLUMN `transformer_type` varchar(60) DEFAULT NULL COMMENT 'Distribution, Bulk, Bulk & Distribution or Bulk (MHP). Derived from the asset type on entry.';
ALTER TABLE `transformers` MODIFY COLUMN `capacity_kva` decimal(10,2) DEFAULT NULL COMMENT 'Nameplate rating. Summed as "installed kVA" across the province.';
ALTER TABLE `transformers` MODIFY COLUMN `transformer_no` varchar(60) DEFAULT NULL COMMENT 'Manufacturer serial number. Must be unique: the same unit entered twice is the error the check exists to catch.';
ALTER TABLE `transformers` MODIFY COLUMN `manufacturer` varchar(80) DEFAULT NULL COMMENT 'Who made it.';
ALTER TABLE `transformers` MODIFY COLUMN `fly_length_km` decimal(9,3) DEFAULT NULL COMMENT 'From the transformer import sheet, "Fly length (km)".';
ALTER TABLE `transformers` MODIFY COLUMN `combined_fly_length_km` decimal(9,3) DEFAULT NULL COMMENT 'From the transformer import sheet, "Combined fly length (km)".';
ALTER TABLE `transformers` MODIFY COLUMN `free_wayleave_km` decimal(9,3) DEFAULT NULL COMMENT 'From the transformer import sheet, "Free wayleave (km)".';
ALTER TABLE `transformers` MODIFY COLUMN `wayleave_distance_km` decimal(9,3) DEFAULT NULL COMMENT 'From the transformer import sheet, "Distance to wayleave (km)".';
ALTER TABLE `transformers` MODIFY COLUMN `total_distance_km` decimal(9,3) DEFAULT NULL COMMENT 'From the transformer import sheet, "Total distance (km)".';
ALTER TABLE `transformers` MODIFY COLUMN `quantity` int(10) unsigned NOT NULL DEFAULT 1 COMMENT 'Always 1. A row here IS one unit; the column exists so the transformer register can be read with the same shape as assets.';
ALTER TABLE `transformers` MODIFY COLUMN `condition_status` enum('NEW','GOOD','FAIR','POOR','FAULTY','UNKNOWN') NOT NULL DEFAULT 'UNKNOWN' COMMENT 'NEW, GOOD, FAIR, POOR, FAULTY or UNKNOWN.';
ALTER TABLE `transformers` MODIFY COLUMN `status` enum('ACTIVE','PLANNED','RETIRED') NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE, PLANNED or RETIRED.';
ALTER TABLE `transformers` MODIFY COLUMN `install_date` date DEFAULT NULL COMMENT 'When it went in, if known.';
ALTER TABLE `transformers` MODIFY COLUMN `latitude` decimal(10,7) DEFAULT NULL COMMENT 'Decimal degrees, WGS84.';
ALTER TABLE `transformers` MODIFY COLUMN `longitude` decimal(10,7) DEFAULT NULL COMMENT 'Decimal degrees, WGS84.';
ALTER TABLE `transformers` MODIFY COLUMN `remarks` text DEFAULT NULL COMMENT 'Free text.';
ALTER TABLE `transformers` MODIFY COLUMN `source_file` varchar(80) DEFAULT NULL COMMENT 'Where the row came from: ''dashboard-entry'' for one typed into the application, otherwise the name of the imported file.';
ALTER TABLE `transformers` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';
ALTER TABLE `transformers` MODIFY COLUMN `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Row last changed.';

-- ------------------------------------------------------------------
-- users
-- ------------------------------------------------------------------
ALTER TABLE `users` MODIFY COLUMN `username` varchar(50) NOT NULL COMMENT 'Sign-in name. Unique.';
ALTER TABLE `users` MODIFY COLUMN `employee_no` varchar(30) DEFAULT NULL COMMENT 'CEB employee number. The human identifier for a person.';
ALTER TABLE `users` MODIFY COLUMN `password_hash` varchar(255) NOT NULL COMMENT 'Bcrypt hash. Never a password.';
ALTER TABLE `users` MODIFY COLUMN `full_name` varchar(120) NOT NULL COMMENT 'Display name.';
ALTER TABLE `users` MODIFY COLUMN `designation` varchar(100) DEFAULT NULL COMMENT 'Job title.';
ALTER TABLE `users` MODIFY COLUMN `email` varchar(150) DEFAULT NULL COMMENT 'Contact address.';
ALTER TABLE `users` MODIFY COLUMN `phone` varchar(25) DEFAULT NULL COMMENT 'Contact number.';
ALTER TABLE `users` MODIFY COLUMN `registration_source` enum('ADMIN_CREATED','SELF_REGISTERED') NOT NULL DEFAULT 'ADMIN_CREATED' COMMENT 'How the account was created.';
ALTER TABLE `users` MODIFY COLUMN `scope_assigned` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1 once an administrator has set the area and CSC above.';
ALTER TABLE `users` MODIFY COLUMN `email_verified_at` datetime DEFAULT NULL COMMENT 'When the address was confirmed. NULL if never.';
ALTER TABLE `users` MODIFY COLUMN `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '0 blocks sign-in without deleting the account.';
ALTER TABLE `users` MODIFY COLUMN `last_login_at` datetime DEFAULT NULL COMMENT 'Last successful sign-in.';
ALTER TABLE `users` MODIFY COLUMN `failed_attempts` tinyint(3) unsigned NOT NULL DEFAULT 0 COMMENT 'Consecutive failed sign-ins. Reset on success.';
ALTER TABLE `users` MODIFY COLUMN `locked_until` datetime DEFAULT NULL COMMENT 'Sign-in refused until this time, after too many failures.';
ALTER TABLE `users` MODIFY COLUMN `created_at` datetime NOT NULL DEFAULT current_timestamp() COMMENT 'Row created.';
ALTER TABLE `users` MODIFY COLUMN `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() COMMENT 'Row last changed.';
