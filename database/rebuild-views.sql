-- =====================================================================
-- Rebuild the views for ceb_uva_ams
--
-- WHY THIS FILE EXISTS
--
-- The database was migrated to text primary keys (SRG-00001, CSC-004,
-- USR-001) and the key columns were renamed with it:
--
--     used_id      -> asset_usage_id
--     alias_id     -> csc_alias_id
--     log_id       -> maintenance_log_id
--     register_id  -> segment_register_id
--
-- The views were never updated, so none of them could be created any
-- more -- the first one fails on "Unknown column 'u.used_id'". A later
-- import left mysqldump's empty placeholder TABLES behind under the view
-- names, which is why every dashboard figure read zero: the queries were
-- succeeding against empty tables.
--
-- This file drops that wreckage and rebuilds the views against the
-- current column names.
--
-- WHAT IS NOT REBUILT -- 10 views nothing reads, dropped deliberately:
--     v_data_quality_issues   v_node_degree          v_node_segments
--     v_segment_adjacency     v_segment_asset_by_csc v_segment_detail
--     v_segment_link_quality  v_substation_capacity  v_switchgear_by_csc
--     v_transformer_data_quality
--
-- Their definitions are still in database/ceb_uva_ams.sql if one is
-- wanted back.
--
-- v_transformer_rollup IS rebuilt even though no application code names
-- it: v_depot_dashboard is built on top of it.
--
-- HOW TO RUN
--     mysql -u root ceb_uva_ams < database/rebuild-views.sql
--   or phpMyAdmin -> ceb_uva_ams -> Import.
--
-- Safe to run repeatedly. Order matters and is handled: a view that
-- feeds another is created first.
-- =====================================================================

-- ---------- clear the wreckage ----------
DROP VIEW IF EXISTS `v_data_quality_issues`;
DROP TABLE IF EXISTS `v_data_quality_issues`;
DROP VIEW IF EXISTS `v_node_degree`;
DROP TABLE IF EXISTS `v_node_degree`;
DROP VIEW IF EXISTS `v_node_segments`;
DROP TABLE IF EXISTS `v_node_segments`;
DROP VIEW IF EXISTS `v_segment_adjacency`;
DROP TABLE IF EXISTS `v_segment_adjacency`;
DROP VIEW IF EXISTS `v_segment_asset_by_csc`;
DROP TABLE IF EXISTS `v_segment_asset_by_csc`;
DROP VIEW IF EXISTS `v_segment_detail`;
DROP TABLE IF EXISTS `v_segment_detail`;
DROP VIEW IF EXISTS `v_segment_link_quality`;
DROP TABLE IF EXISTS `v_segment_link_quality`;
DROP VIEW IF EXISTS `v_substation_capacity`;
DROP TABLE IF EXISTS `v_substation_capacity`;
DROP VIEW IF EXISTS `v_switchgear_by_csc`;
DROP TABLE IF EXISTS `v_switchgear_by_csc`;
DROP VIEW IF EXISTS `v_transformer_data_quality`;
DROP TABLE IF EXISTS `v_transformer_data_quality`;

-- ---------- rebuild, dependencies first ----------

DROP VIEW IF EXISTS `v_assets_used`;
DROP TABLE IF EXISTS `v_assets_used`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_assets_used`  AS SELECT `u`.`asset_usage_id` AS `asset_usage_id`, `u`.`batch_ref` AS `batch_ref`, `u`.`asset_id` AS `asset_id`, `u`.`asset_type_id` AS `asset_type_id`, `t`.`type_code` AS `type_code`, coalesce(`t`.`type_name`,'Unclassified') AS `type_name`, coalesce(`c`.`category_id`,0) AS `category_id`, coalesce(`c`.`category_name`,'Unclassified') AS `category_name`, `u`.`quantity` AS `quantity`, `u`.`unit_of_measure` AS `unit_of_measure`, `u`.`condition_status` AS `condition_status`, `u`.`capacity_kva` AS `capacity_kva`, `u`.`csc_id` AS `csc_id`, `d`.`csc_code` AS `csc_code`, `d`.`csc_name` AS `csc_name`, `u`.`area_id` AS `area_id`, `ar`.`area_code` AS `area_code`, `ar`.`area_name` AS `area_name`, `p`.`province_name` AS `province_name`, `u`.`used_on` AS `used_on`, `u`.`used_for` AS `used_for`, `u`.`recorded_at` AS `recorded_at`, `u`.`recorded_by` AS `recorded_by`, `us`.`full_name` AS `recorded_by_name` FROM ((((((`assets_used` `u` left join `asset_types` `t` on(`t`.`asset_type_id` = `u`.`asset_type_id`)) left join `asset_categories` `c` on(`c`.`category_id` = `t`.`category_id`)) join `csc_depots` `d` on(`d`.`csc_id` = `u`.`csc_id`)) join `areas` `ar` on(`ar`.`area_id` = `u`.`area_id`)) join `provinces` `p` on(`p`.`province_id` = `ar`.`province_id`)) left join `users` `us` on(`us`.`user_id` = `u`.`recorded_by`)) ;

DROP VIEW IF EXISTS `v_assets_used_by_csc`;
DROP TABLE IF EXISTS `v_assets_used_by_csc`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_assets_used_by_csc`  AS SELECT `v_assets_used`.`csc_id` AS `csc_id`, `v_assets_used`.`csc_code` AS `csc_code`, `v_assets_used`.`csc_name` AS `csc_name`, `v_assets_used`.`area_id` AS `area_id`, `v_assets_used`.`area_code` AS `area_code`, `v_assets_used`.`area_name` AS `area_name`, `v_assets_used`.`category_id` AS `category_id`, `v_assets_used`.`category_name` AS `category_name`, `v_assets_used`.`asset_type_id` AS `asset_type_id`, `v_assets_used`.`type_name` AS `type_name`, `v_assets_used`.`unit_of_measure` AS `unit_of_measure`, count(0) AS `entries`, sum(`v_assets_used`.`quantity`) AS `total_quantity`, min(`v_assets_used`.`recorded_at`) AS `first_entry`, max(`v_assets_used`.`recorded_at`) AS `last_entry` FROM `v_assets_used` GROUP BY `v_assets_used`.`csc_id`, `v_assets_used`.`csc_code`, `v_assets_used`.`csc_name`, `v_assets_used`.`area_id`, `v_assets_used`.`area_code`, `v_assets_used`.`area_name`, `v_assets_used`.`category_id`, `v_assets_used`.`category_name`, `v_assets_used`.`asset_type_id`, `v_assets_used`.`type_name`, `v_assets_used`.`unit_of_measure` ;

DROP VIEW IF EXISTS `v_asset_last_activity`;
DROP TABLE IF EXISTS `v_asset_last_activity`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_asset_last_activity`  AS SELECT `a`.`asset_id` AS `asset_id`, `a`.`asset_code` AS `asset_code`, `t`.`type_name` AS `type_name`, coalesce(`dn`.`csc_name`,`ds`.`csc_name`) AS `csc_name`, `ml`.`action_type` AS `action_type`, `u`.`full_name` AS `performed_by`, `ml`.`performed_at` AS `performed_at`, `ml`.`remarks` AS `remarks` FROM (((((((`assets` `a` join `asset_types` `t` on(`t`.`asset_type_id` = `a`.`asset_type_id`)) left join `network_nodes` `n` on(`n`.`node_id` = `a`.`node_id`)) left join `csc_depots` `dn` on(`dn`.`csc_id` = `n`.`csc_id`)) left join `segments` `s` on(`s`.`segment_id` = `a`.`segment_id`)) left join `csc_depots` `ds` on(`ds`.`csc_id` = `s`.`csc_id`)) left join `maintenance_logs` `ml` on(`ml`.`maintenance_log_id` = (select max(`m2`.`maintenance_log_id`) from `maintenance_logs` `m2` where `m2`.`asset_id` = `a`.`asset_id`))) left join `users` `u` on(`u`.`user_id` = `ml`.`performed_by`)) ;

DROP VIEW IF EXISTS `v_asset_placement`;
DROP TABLE IF EXISTS `v_asset_placement`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_asset_placement`  AS SELECT `a`.`asset_id` AS `source_id`, 'assets' AS `source`, `a`.`asset_code` AS `asset_code`, `a`.`asset_type_id` AS `asset_type_id`, `n`.`csc_id` AS `csc_id`, 'node' AS `attached_to`, `n`.`node_code` AS `attached_ref`, `a`.`quantity` AS `quantity`, `a`.`unit_of_measure` AS `unit_of_measure`, `a`.`capacity_kva` AS `capacity_kva`, `a`.`condition_status` AS `condition_status`, `a`.`created_at` AS `recorded_at` FROM (`assets` `a` join `network_nodes` `n` on(`n`.`node_id` = `a`.`node_id`)) WHERE `a`.`status` = 'ACTIVE' AND `a`.`node_id` is not null union all select `a`.`asset_id` AS `asset_id`,'assets' AS `assets`,`a`.`asset_code` AS `asset_code`,`a`.`asset_type_id` AS `asset_type_id`,`s`.`csc_id` AS `csc_id`,'segment' AS `segment`,`s`.`segment_code` AS `segment_code`,`a`.`quantity` AS `quantity`,`a`.`unit_of_measure` AS `unit_of_measure`,`a`.`capacity_kva` AS `capacity_kva`,`a`.`condition_status` AS `condition_status`,`a`.`created_at` AS `created_at` from (`assets` `a` join `segments` `s` on(`s`.`segment_id` = `a`.`segment_id`)) where `a`.`status` = 'ACTIVE' and `a`.`segment_id` is not null union all select `a`.`asset_id` AS `asset_id`,'assets' AS `assets`,`a`.`asset_code` AS `asset_code`,`a`.`asset_type_id` AS `asset_type_id`,`a`.`csc_id` AS `csc_id`,'csc' AS `csc`,`d`.`csc_code` AS `csc_code`,`a`.`quantity` AS `quantity`,`a`.`unit_of_measure` AS `unit_of_measure`,`a`.`capacity_kva` AS `capacity_kva`,`a`.`condition_status` AS `condition_status`,`a`.`created_at` AS `created_at` from (`assets` `a` join `csc_depots` `d` on(`d`.`csc_id` = `a`.`csc_id`)) where `a`.`status` = 'ACTIVE' and `a`.`csc_id` is not null and `a`.`node_id` is null and `a`.`segment_id` is null union all select `sa`.`segment_asset_id` AS `segment_asset_id`,'segment_asset' AS `segment_asset`,`sr`.`segment_code` AS `segment_code`,`sa`.`asset_type_id` AS `asset_type_id`,`sr`.`csc_id` AS `csc_id`,'segment' AS `segment`,`sr`.`segment_code` AS `segment_code`,`sa`.`quantity` AS `quantity`,`sa`.`unit_of_measure` AS `unit_of_measure`,NULL AS `NULL`,'UNKNOWN' AS `UNKNOWN`,`sa`.`created_at` AS `created_at` from (`segment_asset` `sa` join `segment_register` `sr` on(`sr`.`segment_register_id` = `sa`.`segment_register_id`)) where `sr`.`status` = 'ACTIVE' union all select `tx`.`transformer_id` AS `transformer_id`,'transformers' AS `transformers`,coalesce(nullif(`tx`.`new_sin_no`,''),nullif(`tx`.`old_sin_no`,''),concat('TX-',`tx`.`transformer_id`)) AS `Name_exp_3`,`tx`.`asset_type_id` AS `asset_type_id`,`tx`.`csc_id` AS `csc_id`,'transformer' AS `transformer`,`tx`.`substation_name` AS `substation_name`,`tx`.`quantity` AS `quantity`,'nos' AS `nos`,`tx`.`capacity_kva` AS `capacity_kva`,`tx`.`condition_status` AS `condition_status`,`tx`.`created_at` AS `created_at` from `transformers` `tx` where `tx`.`status` = 'ACTIVE' union all select `sw`.`switchgear_id` AS `switchgear_id`,'switchgear' AS `switchgear`,`sw`.`switch_code` AS `switch_code`,`sw`.`asset_type_id` AS `asset_type_id`,`sw`.`csc_id` AS `csc_id`,'switchgear' AS `switchgear`,coalesce(nullif(`sw`.`switch_name`,''),`sw`.`nearest_substation`) AS `COALESCE(NULLIF(sw.switch_name, ''), sw.nearest_substation)`,1 AS `1`,'nos' AS `nos`,NULL AS `NULL`,'UNKNOWN' AS `UNKNOWN`,`sw`.`created_at` AS `created_at` from `switchgear` `sw` where `sw`.`status` = 'ACTIVE'  ;

DROP VIEW IF EXISTS `v_asset_register`;
DROP TABLE IF EXISTS `v_asset_register`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_asset_register`  AS SELECT `p`.`source` AS `source`, `p`.`source_id` AS `source_id`, `p`.`asset_code` AS `asset_code`, `p`.`attached_to` AS `attached_to`, `p`.`attached_ref` AS `attached_ref`, `p`.`quantity` AS `quantity`, `p`.`unit_of_measure` AS `unit_of_measure`, `p`.`capacity_kva` AS `capacity_kva`, `p`.`condition_status` AS `condition_status`, `p`.`recorded_at` AS `recorded_at`, `p`.`asset_type_id` AS `asset_type_id`, `t`.`type_code` AS `type_code`, coalesce(`t`.`type_name`,'Unclassified') AS `type_name`, coalesce(`c`.`category_id`,0) AS `category_id`, coalesce(`c`.`category_name`,'Unclassified') AS `category_name`, coalesce(`c`.`display_order`,999) AS `category_order`, coalesce(`t`.`display_order`,999) AS `type_order`, `d`.`csc_id` AS `csc_id`, `d`.`csc_code` AS `csc_code`, `d`.`csc_name` AS `csc_name`, `ar`.`area_id` AS `area_id`, `ar`.`area_code` AS `area_code`, `ar`.`area_name` AS `area_name`, `pr`.`province_id` AS `province_id`, `pr`.`province_name` AS `province_name` FROM (((((`v_asset_placement` `p` join `csc_depots` `d` on(`d`.`csc_id` = `p`.`csc_id`)) join `areas` `ar` on(`ar`.`area_id` = `d`.`area_id`)) join `provinces` `pr` on(`pr`.`province_id` = `ar`.`province_id`)) left join `asset_types` `t` on(`t`.`asset_type_id` = `p`.`asset_type_id`)) left join `asset_categories` `c` on(`c`.`category_id` = `t`.`category_id`)) ;

DROP VIEW IF EXISTS `v_asset_rollup`;
DROP TABLE IF EXISTS `v_asset_rollup`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_asset_rollup`  AS SELECT 'POINT' AS `attach_layer`, `a`.`asset_id` AS `asset_id`, `a`.`asset_code` AS `asset_code`, `a`.`asset_type_id` AS `asset_type_id`, `t`.`type_name` AS `type_name`, `t`.`type_code` AS `type_code`, `c`.`category_id` AS `category_id`, `c`.`category_name` AS `category_name`, `t`.`unit_of_measure` AS `unit_of_measure`, `t`.`rated_kva` AS `rated_kva`, `a`.`quantity` AS `quantity`, `a`.`condition_status` AS `condition_status`, `a`.`install_date` AS `install_date`, `n`.`node_id` AS `node_id`, NULL AS `segment_id`, NULL AS `feeder_id`, `n`.`csc_id` AS `csc_id`, `d`.`csc_code` AS `csc_code`, `d`.`csc_name` AS `csc_name`, `d`.`area_id` AS `area_id`, `ar`.`area_code` AS `area_code`, `ar`.`area_name` AS `area_name`, `ar`.`province_id` AS `province_id`, `p`.`province_name` AS `province_name` FROM ((((((`assets` `a` join `asset_types` `t` on(`t`.`asset_type_id` = `a`.`asset_type_id`)) join `asset_categories` `c` on(`c`.`category_id` = `t`.`category_id`)) join `network_nodes` `n` on(`n`.`node_id` = `a`.`node_id`)) join `csc_depots` `d` on(`d`.`csc_id` = `n`.`csc_id`)) join `areas` `ar` on(`ar`.`area_id` = `d`.`area_id`)) join `provinces` `p` on(`p`.`province_id` = `ar`.`province_id`)) WHERE `a`.`node_id` is not null AND `a`.`status` = 'ACTIVE'union all select 'SPAN' AS `attach_layer`,`a`.`asset_id` AS `asset_id`,`a`.`asset_code` AS `asset_code`,`a`.`asset_type_id` AS `asset_type_id`,`t`.`type_name` AS `type_name`,`t`.`type_code` AS `type_code`,`c`.`category_id` AS `category_id`,`c`.`category_name` AS `category_name`,`t`.`unit_of_measure` AS `unit_of_measure`,`t`.`rated_kva` AS `rated_kva`,`a`.`quantity` AS `quantity`,`a`.`condition_status` AS `condition_status`,`a`.`install_date` AS `install_date`,NULL AS `node_id`,`s`.`segment_id` AS `segment_id`,`s`.`feeder_id` AS `feeder_id`,`s`.`csc_id` AS `csc_id`,`d`.`csc_code` AS `csc_code`,`d`.`csc_name` AS `csc_name`,`d`.`area_id` AS `area_id`,`ar`.`area_code` AS `area_code`,`ar`.`area_name` AS `area_name`,`ar`.`province_id` AS `province_id`,`p`.`province_name` AS `province_name` from ((((((`assets` `a` join `asset_types` `t` on(`t`.`asset_type_id` = `a`.`asset_type_id`)) join `asset_categories` `c` on(`c`.`category_id` = `t`.`category_id`)) join `segments` `s` on(`s`.`segment_id` = `a`.`segment_id`)) join `csc_depots` `d` on(`d`.`csc_id` = `s`.`csc_id`)) join `areas` `ar` on(`ar`.`area_id` = `d`.`area_id`)) join `provinces` `p` on(`p`.`province_id` = `ar`.`province_id`)) where `a`.`segment_id` is not null and `a`.`status` = 'ACTIVE'  ;

DROP VIEW IF EXISTS `v_asset_totals`;
DROP TABLE IF EXISTS `v_asset_totals`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_asset_totals`  AS SELECT `t`.`asset_type_id` AS `asset_type_id`, coalesce(`c`.`category_name`,'Other') AS `category_name`, `t`.`type_name` AS `type_name`, `p`.`unit_of_measure` AS `unit_of_measure`, count(0) AS `placements`, count(distinct `p`.`csc_id`) AS `csc_count`, count(distinct `d`.`area_id`) AS `area_count`, sum(`p`.`quantity`) AS `total_quantity`, sum(case when `p`.`source` = 'segment_asset' then `p`.`quantity` else 0 end) AS `entered_here_quantity` FROM (((`v_asset_placement` `p` join `asset_types` `t` on(`t`.`asset_type_id` = `p`.`asset_type_id`)) left join `asset_categories` `c` on(`c`.`category_id` = `t`.`category_id`)) join `csc_depots` `d` on(`d`.`csc_id` = `p`.`csc_id`)) GROUP BY `t`.`asset_type_id`, `c`.`category_name`, `t`.`type_name`, `p`.`unit_of_measure` ;

DROP VIEW IF EXISTS `v_line_length_by_feeder`;
DROP TABLE IF EXISTS `v_line_length_by_feeder`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_line_length_by_feeder`  AS SELECT `f`.`feeder_id` AS `feeder_id`, `f`.`feeder_code` AS `feeder_code`, `f`.`feeder_name` AS `feeder_name`, `f`.`origin_csc_id` AS `origin_csc_id`, `f`.`external_source` AS `external_source`, count(distinct `sr`.`csc_id`) AS `depots_crossed`, count(0) AS `segment_count`, sum(`sr`.`length_km`) AS `total_km` FROM (`segment_register` `sr` join `feeders` `f` on(`f`.`feeder_id` = `sr`.`feeder_id`)) WHERE `sr`.`status` = 'ACTIVE' GROUP BY `f`.`feeder_id`, `f`.`feeder_code`, `f`.`feeder_name`, `f`.`origin_csc_id`, `f`.`external_source` ;

DROP VIEW IF EXISTS `v_pending_users`;
DROP TABLE IF EXISTS `v_pending_users`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_pending_users`  AS SELECT `u`.`user_id` AS `user_id`, `u`.`username` AS `username`, `u`.`employee_no` AS `employee_no`, `u`.`full_name` AS `full_name`, `u`.`designation` AS `designation`, `u`.`email` AS `email`, `u`.`phone` AS `phone`, `u`.`created_at` AS `created_at`, `r`.`role_code` AS `role_code`, `r`.`role_name` AS `role_name`, `rq`.`role_code` AS `requested_role_code`, `rq`.`role_name` AS `requested_role_name`, `a`.`area_id` AS `area_id`, `a`.`area_name` AS `area_name`, `d`.`csc_id` AS `csc_id`, `d`.`csc_code` AS `csc_code`, `d`.`csc_name` AS `csc_name` FROM ((((`users` `u` join `roles` `r` on(`r`.`role_id` = `u`.`role_id`)) left join `roles` `rq` on(`rq`.`role_id` = `u`.`requested_role_id`)) left join `areas` `a` on(`a`.`area_id` = `u`.`area_id`)) left join `csc_depots` `d` on(`d`.`csc_id` = `u`.`csc_id`)) WHERE `u`.`registration_source` = 'SELF_REGISTERED' AND `u`.`scope_assigned` = 0 AND `u`.`is_active` = 1 ;

DROP VIEW IF EXISTS `v_search_index`;
DROP TABLE IF EXISTS `v_search_index`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_search_index` AS
SELECT 'transformer' COLLATE utf8mb4_unicode_ci AS `kind`,
       `tx`.`transformer_id`                    AS `entity_id`,
       COALESCE(NULLIF(`tx`.`new_sin_no`,''), NULLIF(`tx`.`old_sin_no`,''), `tx`.`transformer_no`)
           COLLATE utf8mb4_unicode_ci           AS `code`,
       CONCAT_WS(' - ', `tx`.`substation_name`, CONCAT(FORMAT(`tx`.`capacity_kva`,0),' kVA'))
           COLLATE utf8mb4_unicode_ci           AS `title`,
       CONCAT_WS(' / ', COALESCE(`t`.`type_name`, `tx`.`transformer_type`), `tx`.`manufacturer`)
           COLLATE utf8mb4_unicode_ci           AS `subtitle`,
       CONCAT(`d`.`csc_name`,' CSC / ',`ar`.`area_name`)
           COLLATE utf8mb4_unicode_ci           AS `place`,
       `d`.`csc_id`                             AS `csc_id`,
       `ar`.`area_id`                           AS `area_id`,
       `tx`.`status` COLLATE utf8mb4_unicode_ci AS `status`,
       LCASE(CONCAT_WS(' ', `tx`.`new_sin_no`, `tx`.`old_sin_no`, `tx`.`transformer_no`,
                       `tx`.`substation_name`, `tx`.`manufacturer`, `tx`.`transformer_type`,
                       `d`.`csc_name`, `d`.`csc_code`, `ar`.`area_name`, `ar`.`area_code`))
           COLLATE utf8mb4_unicode_ci           AS `keywords`
FROM `transformers` `tx`
JOIN `csc_depots` `d` ON `d`.`csc_id` = `tx`.`csc_id`
JOIN `areas` `ar`     ON `ar`.`area_id` = `d`.`area_id`
LEFT JOIN `asset_types` `t` ON `t`.`asset_type_id` = `tx`.`asset_type_id`

UNION ALL
SELECT 'switchgear' COLLATE utf8mb4_unicode_ci,
       `sw`.`switchgear_id`,
       `sw`.`switch_code` COLLATE utf8mb4_unicode_ci,
       COALESCE(NULLIF(`sw`.`switch_name`,''), `sw`.`nearest_substation`, `sw`.`switch_code`)
           COLLATE utf8mb4_unicode_ci,
       COALESCE(`t`.`type_name`,'Switchgear') COLLATE utf8mb4_unicode_ci,
       CONCAT(`d`.`csc_name`,' CSC / ',`ar`.`area_name`) COLLATE utf8mb4_unicode_ci,
       `d`.`csc_id`, `ar`.`area_id`,
       `sw`.`status` COLLATE utf8mb4_unicode_ci,
       LCASE(CONCAT_WS(' ', `sw`.`switch_code`, `sw`.`switch_name`, `sw`.`nearest_substation`,
                       `d`.`csc_name`, `d`.`csc_code`, `ar`.`area_name`, `ar`.`area_code`))
           COLLATE utf8mb4_unicode_ci
FROM `switchgear` `sw`
JOIN `csc_depots` `d` ON `d`.`csc_id` = `sw`.`csc_id`
JOIN `areas` `ar`     ON `ar`.`area_id` = `d`.`area_id`
LEFT JOIN `asset_types` `t` ON `t`.`asset_type_id` = `sw`.`asset_type_id`

UNION ALL
SELECT 'segment' COLLATE utf8mb4_unicode_ci,
       `sr`.`segment_register_id`,
       `sr`.`segment_code` COLLATE utf8mb4_unicode_ci,
       CONCAT(`sr`.`segment_code`,' - ',FORMAT(`sr`.`length_km`,3),' km')
           COLLATE utf8mb4_unicode_ci,
       CONCAT_WS(' / ', `sr`.`voltage_level`, `f`.`feeder_code`) COLLATE utf8mb4_unicode_ci,
       CONCAT(`d`.`csc_name`,' CSC / ',`ar`.`area_name`) COLLATE utf8mb4_unicode_ci,
       `d`.`csc_id`, `ar`.`area_id`,
       `sr`.`status` COLLATE utf8mb4_unicode_ci,
       LCASE(CONCAT_WS(' ', `sr`.`segment_code`, `sr`.`voltage_level`, `f`.`feeder_code`,
                       `f`.`feeder_name`, `d`.`csc_name`, `d`.`csc_code`,
                       `ar`.`area_name`, `ar`.`area_code`)) COLLATE utf8mb4_unicode_ci
FROM `segment_register` `sr`
JOIN `csc_depots` `d` ON `d`.`csc_id` = `sr`.`csc_id`
JOIN `areas` `ar`     ON `ar`.`area_id` = `d`.`area_id`
LEFT JOIN `feeders` `f` ON `f`.`feeder_id` = `sr`.`feeder_id`

UNION ALL
SELECT 'csc' COLLATE utf8mb4_unicode_ci,
       `d`.`csc_id`,
       `d`.`csc_code` COLLATE utf8mb4_unicode_ci,
       `d`.`csc_name` COLLATE utf8mb4_unicode_ci,
       COALESCE(`d`.`depot_type`,'CSC') COLLATE utf8mb4_unicode_ci,
       `ar`.`area_name` COLLATE utf8mb4_unicode_ci,
       `d`.`csc_id`, `ar`.`area_id`,
       'ACTIVE' COLLATE utf8mb4_unicode_ci,
       LCASE(CONCAT_WS(' ', `d`.`csc_name`, `d`.`csc_code`,
                       `ar`.`area_name`, `ar`.`area_code`)) COLLATE utf8mb4_unicode_ci
FROM `csc_depots` `d`
JOIN `areas` `ar` ON `ar`.`area_id` = `d`.`area_id`

UNION ALL
SELECT 'area' COLLATE utf8mb4_unicode_ci,
       `ar`.`area_id`,
       `ar`.`area_code` COLLATE utf8mb4_unicode_ci,
       `ar`.`area_name` COLLATE utf8mb4_unicode_ci,
       'Operational area' COLLATE utf8mb4_unicode_ci,
       `p`.`province_name` COLLATE utf8mb4_unicode_ci,
       NULL, `ar`.`area_id`,
       'ACTIVE' COLLATE utf8mb4_unicode_ci,
       LCASE(CONCAT_WS(' ', `ar`.`area_name`, `ar`.`area_code`,
                       `p`.`province_name`)) COLLATE utf8mb4_unicode_ci
FROM `areas` `ar`
JOIN `provinces` `p` ON `p`.`province_id` = `ar`.`province_id`

UNION ALL
SELECT 'feeder' COLLATE utf8mb4_unicode_ci,
       `f`.`feeder_id`,
       `f`.`feeder_code` COLLATE utf8mb4_unicode_ci,
       COALESCE(NULLIF(`f`.`feeder_name`,''), `f`.`feeder_code`) COLLATE utf8mb4_unicode_ci,
       CONCAT_WS(' / ', `f`.`voltage_level`, `f`.`source_name`) COLLATE utf8mb4_unicode_ci,
       COALESCE(CONCAT(`d`.`csc_name`,' CSC'),'Province') COLLATE utf8mb4_unicode_ci,
       `d`.`csc_id`, `ar`.`area_id`,
       `f`.`status` COLLATE utf8mb4_unicode_ci,
       LCASE(CONCAT_WS(' ', `f`.`feeder_code`, `f`.`feeder_name`, `f`.`source_name`,
                       `d`.`csc_name`, `ar`.`area_name`)) COLLATE utf8mb4_unicode_ci
FROM `feeders` `f`
LEFT JOIN `csc_depots` `d` ON `d`.`csc_id` = `f`.`origin_csc_id`
LEFT JOIN `areas` `ar`     ON `ar`.`area_id` = `d`.`area_id`

UNION ALL
SELECT 'asset' COLLATE utf8mb4_unicode_ci,
       `a`.`asset_id`,
       `a`.`asset_code` COLLATE utf8mb4_unicode_ci,
       CONCAT_WS(' - ', COALESCE(`t`.`type_name`,'Asset'),
                 CONCAT(FORMAT(`a`.`quantity`,0),' ',`a`.`unit_of_measure`))
           COLLATE utf8mb4_unicode_ci,
       COALESCE(`a`.`condition_status`,'UNKNOWN') COLLATE utf8mb4_unicode_ci,
       CONCAT(`d`.`csc_name`,' CSC / ',`ar`.`area_name`) COLLATE utf8mb4_unicode_ci,
       `d`.`csc_id`, `ar`.`area_id`,
       `a`.`status` COLLATE utf8mb4_unicode_ci,
       LCASE(CONCAT_WS(' ', `a`.`asset_code`, `t`.`type_name`,
                       `d`.`csc_name`, `d`.`csc_code`,
                       `ar`.`area_name`, `ar`.`area_code`)) COLLATE utf8mb4_unicode_ci
FROM `assets` `a`
JOIN `csc_depots` `d` ON `d`.`csc_id` = `a`.`csc_id`
JOIN `areas` `ar`     ON `ar`.`area_id` = `d`.`area_id`
LEFT JOIN `asset_types` `t` ON `t`.`asset_type_id` = `a`.`asset_type_id`;

DROP VIEW IF EXISTS `v_segment_csc_share`;
DROP TABLE IF EXISTS `v_segment_csc_share`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_segment_csc_share`  AS SELECT `sc`.`segment_register_id` AS `segment_register_id`, `sc`.`csc_id` AS `csc_id`, `sc`.`length_km` AS `length_km`, 1 AS `is_split` FROM (`segment_csc` `sc` join `segment_register` `sr` on(`sr`.`segment_register_id` = `sc`.`segment_register_id`)) WHERE `sr`.`status` = 'ACTIVE'union all select `sr`.`segment_register_id` AS `segment_register_id`,`sr`.`csc_id` AS `csc_id`,coalesce(`sr`.`length_km`,0) AS `length_km`,0 AS `is_split` from `segment_register` `sr` where `sr`.`status` = 'ACTIVE' and !exists(select 1 from `segment_csc` `sc2` where `sc2`.`segment_register_id` = `sr`.`segment_register_id` limit 1)  ;

DROP VIEW IF EXISTS `v_totals_by_area`;
DROP TABLE IF EXISTS `v_totals_by_area`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_totals_by_area`  AS SELECT `v_asset_rollup`.`province_id` AS `province_id`, `v_asset_rollup`.`province_name` AS `province_name`, `v_asset_rollup`.`area_id` AS `area_id`, `v_asset_rollup`.`area_code` AS `area_code`, `v_asset_rollup`.`area_name` AS `area_name`, `v_asset_rollup`.`category_id` AS `category_id`, `v_asset_rollup`.`category_name` AS `category_name`, `v_asset_rollup`.`asset_type_id` AS `asset_type_id`, `v_asset_rollup`.`type_name` AS `type_name`, `v_asset_rollup`.`unit_of_measure` AS `unit_of_measure`, sum(`v_asset_rollup`.`quantity`) AS `total_quantity` FROM `v_asset_rollup` GROUP BY `v_asset_rollup`.`province_id`, `v_asset_rollup`.`province_name`, `v_asset_rollup`.`area_id`, `v_asset_rollup`.`area_code`, `v_asset_rollup`.`area_name`, `v_asset_rollup`.`category_id`, `v_asset_rollup`.`category_name`, `v_asset_rollup`.`asset_type_id`, `v_asset_rollup`.`type_name`, `v_asset_rollup`.`unit_of_measure` ;

DROP VIEW IF EXISTS `v_totals_by_csc`;
DROP TABLE IF EXISTS `v_totals_by_csc`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_totals_by_csc`  AS SELECT `v_asset_rollup`.`province_id` AS `province_id`, `v_asset_rollup`.`province_name` AS `province_name`, `v_asset_rollup`.`area_id` AS `area_id`, `v_asset_rollup`.`area_code` AS `area_code`, `v_asset_rollup`.`area_name` AS `area_name`, `v_asset_rollup`.`csc_id` AS `csc_id`, `v_asset_rollup`.`csc_code` AS `csc_code`, `v_asset_rollup`.`csc_name` AS `csc_name`, `v_asset_rollup`.`category_id` AS `category_id`, `v_asset_rollup`.`category_name` AS `category_name`, `v_asset_rollup`.`asset_type_id` AS `asset_type_id`, `v_asset_rollup`.`type_name` AS `type_name`, `v_asset_rollup`.`unit_of_measure` AS `unit_of_measure`, sum(`v_asset_rollup`.`quantity`) AS `total_quantity`, count(0) AS `record_count` FROM `v_asset_rollup` GROUP BY `v_asset_rollup`.`province_id`, `v_asset_rollup`.`province_name`, `v_asset_rollup`.`area_id`, `v_asset_rollup`.`area_code`, `v_asset_rollup`.`area_name`, `v_asset_rollup`.`csc_id`, `v_asset_rollup`.`csc_code`, `v_asset_rollup`.`csc_name`, `v_asset_rollup`.`category_id`, `v_asset_rollup`.`category_name`, `v_asset_rollup`.`asset_type_id`, `v_asset_rollup`.`type_name`, `v_asset_rollup`.`unit_of_measure` ;

DROP VIEW IF EXISTS `v_totals_by_province`;
DROP TABLE IF EXISTS `v_totals_by_province`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_totals_by_province`  AS SELECT `v_asset_rollup`.`province_id` AS `province_id`, `v_asset_rollup`.`province_name` AS `province_name`, `v_asset_rollup`.`category_id` AS `category_id`, `v_asset_rollup`.`category_name` AS `category_name`, `v_asset_rollup`.`asset_type_id` AS `asset_type_id`, `v_asset_rollup`.`type_name` AS `type_name`, `v_asset_rollup`.`unit_of_measure` AS `unit_of_measure`, sum(`v_asset_rollup`.`quantity`) AS `total_quantity` FROM `v_asset_rollup` GROUP BY `v_asset_rollup`.`province_id`, `v_asset_rollup`.`province_name`, `v_asset_rollup`.`category_id`, `v_asset_rollup`.`category_name`, `v_asset_rollup`.`asset_type_id`, `v_asset_rollup`.`type_name`, `v_asset_rollup`.`unit_of_measure` ;

DROP VIEW IF EXISTS `v_transformer_detail`;
DROP TABLE IF EXISTS `v_transformer_detail`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_transformer_detail`  AS SELECT `tx`.`transformer_id` AS `transformer_id`, `tx`.`old_sin_no` AS `old_sin_no`, `tx`.`new_sin_no` AS `new_sin_no`, `tx`.`substation_name` AS `substation_name`, `tx`.`transformer_type` AS `transformer_type`, `tx`.`capacity_kva` AS `capacity_kva`, `tx`.`transformer_no` AS `transformer_no`, `tx`.`manufacturer` AS `manufacturer`, `tx`.`fly_length_km` AS `fly_length_km`, `tx`.`combined_fly_length_km` AS `combined_fly_length_km`, `tx`.`free_wayleave_km` AS `free_wayleave_km`, `tx`.`wayleave_distance_km` AS `wayleave_distance_km`, `tx`.`total_distance_km` AS `total_distance_km`, `tx`.`quantity` AS `quantity`, `tx`.`condition_status` AS `condition_status`, `tx`.`status` AS `status`, `tx`.`install_date` AS `install_date`, `tx`.`latitude` AS `latitude`, `tx`.`longitude` AS `longitude`, `tx`.`remarks` AS `remarks`, `tx`.`source_file` AS `source_file`, `tx`.`created_at` AS `created_at`, `tx`.`updated_at` AS `updated_at`, `tx`.`asset_type_id` AS `asset_type_id`, `t`.`type_code` AS `type_code`, coalesce(`t`.`type_name`,'Unclassified') AS `type_name`, coalesce(`c`.`category_name`,'Unclassified') AS `category_name`, `d`.`csc_id` AS `csc_id`, `d`.`csc_code` AS `csc_code`, `d`.`csc_name` AS `csc_name`, `ar`.`area_id` AS `area_id`, `ar`.`area_code` AS `area_code`, `ar`.`area_name` AS `area_name`, `pr`.`province_id` AS `province_id`, `pr`.`province_name` AS `province_name`, (select count(0) from `segment_transformer` `st` where `st`.`transformer_id` = `tx`.`transformer_id`) AS `segment_links` FROM (((((`transformers` `tx` join `csc_depots` `d` on(`d`.`csc_id` = `tx`.`csc_id`)) join `areas` `ar` on(`ar`.`area_id` = `d`.`area_id`)) join `provinces` `pr` on(`pr`.`province_id` = `ar`.`province_id`)) left join `asset_types` `t` on(`t`.`asset_type_id` = `tx`.`asset_type_id`)) left join `asset_categories` `c` on(`c`.`category_id` = `t`.`category_id`)) ;

DROP VIEW IF EXISTS `v_transformer_rollup`;
DROP TABLE IF EXISTS `v_transformer_rollup`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_transformer_rollup`  AS SELECT `tx`.`transformer_id` AS `transformer_id`, `tx`.`old_sin_no` AS `old_sin_no`, `tx`.`new_sin_no` AS `new_sin_no`, `tx`.`substation_name` AS `substation_name`, `tx`.`transformer_type` AS `transformer_type`, `tx`.`capacity_kva` AS `capacity_kva`, `tx`.`transformer_no` AS `transformer_no`, `tx`.`quantity` AS `quantity`, `tx`.`condition_status` AS `condition_status`, `tx`.`status` AS `status`, `tx`.`node_id` AS `node_id`, `tx`.`asset_id` AS `asset_id`, `tx`.`asset_type_id` AS `asset_type_id`, `t`.`type_code` AS `type_code`, `t`.`type_name` AS `type_name`, `tx`.`csc_id` AS `csc_id`, `d`.`csc_code` AS `csc_code`, `d`.`csc_name` AS `csc_name`, `d`.`area_id` AS `area_id`, `ar`.`area_code` AS `area_code`, `ar`.`area_name` AS `area_name`, `ar`.`province_id` AS `province_id`, `p`.`province_name` AS `province_name` FROM ((((`transformers` `tx` join `csc_depots` `d` on(`d`.`csc_id` = `tx`.`csc_id`)) join `areas` `ar` on(`ar`.`area_id` = `d`.`area_id`)) join `provinces` `p` on(`p`.`province_id` = `ar`.`province_id`)) left join `asset_types` `t` on(`t`.`asset_type_id` = `tx`.`asset_type_id`)) WHERE `tx`.`status` = 'ACTIVE' ;

DROP VIEW IF EXISTS `v_transformer_totals_by_area`;
DROP TABLE IF EXISTS `v_transformer_totals_by_area`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_transformer_totals_by_area`  AS SELECT `v_transformer_rollup`.`province_id` AS `province_id`, `v_transformer_rollup`.`province_name` AS `province_name`, `v_transformer_rollup`.`area_id` AS `area_id`, `v_transformer_rollup`.`area_code` AS `area_code`, `v_transformer_rollup`.`area_name` AS `area_name`, count(0) AS `transformer_records`, sum(`v_transformer_rollup`.`quantity`) AS `transformer_units`, sum(coalesce(`v_transformer_rollup`.`capacity_kva`,0) * `v_transformer_rollup`.`quantity`) AS `installed_kva` FROM `v_transformer_rollup` GROUP BY `v_transformer_rollup`.`province_id`, `v_transformer_rollup`.`province_name`, `v_transformer_rollup`.`area_id`, `v_transformer_rollup`.`area_code`, `v_transformer_rollup`.`area_name` ;

DROP VIEW IF EXISTS `v_transformer_totals_by_csc`;
DROP TABLE IF EXISTS `v_transformer_totals_by_csc`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_transformer_totals_by_csc`  AS SELECT `v_transformer_rollup`.`province_id` AS `province_id`, `v_transformer_rollup`.`province_name` AS `province_name`, `v_transformer_rollup`.`area_id` AS `area_id`, `v_transformer_rollup`.`area_code` AS `area_code`, `v_transformer_rollup`.`area_name` AS `area_name`, `v_transformer_rollup`.`csc_id` AS `csc_id`, `v_transformer_rollup`.`csc_code` AS `csc_code`, `v_transformer_rollup`.`csc_name` AS `csc_name`, count(0) AS `transformer_records`, sum(`v_transformer_rollup`.`quantity`) AS `transformer_units`, sum(coalesce(`v_transformer_rollup`.`capacity_kva`,0) * `v_transformer_rollup`.`quantity`) AS `installed_kva` FROM `v_transformer_rollup` GROUP BY `v_transformer_rollup`.`province_id`, `v_transformer_rollup`.`province_name`, `v_transformer_rollup`.`area_id`, `v_transformer_rollup`.`area_code`, `v_transformer_rollup`.`area_name`, `v_transformer_rollup`.`csc_id`, `v_transformer_rollup`.`csc_code`, `v_transformer_rollup`.`csc_name` ;

DROP VIEW IF EXISTS `v_asset_by_csc`;
DROP TABLE IF EXISTS `v_asset_by_csc`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_asset_by_csc`  AS SELECT `d`.`csc_id` AS `csc_id`, `d`.`csc_code` AS `csc_code`, `d`.`csc_name` AS `csc_name`, `a`.`area_id` AS `area_id`, `a`.`area_name` AS `area_name`, `t`.`asset_type_id` AS `asset_type_id`, coalesce(`c`.`category_name`,'Other') AS `category_name`, `t`.`type_name` AS `type_name`, `p`.`unit_of_measure` AS `unit_of_measure`, count(0) AS `placements`, sum(`p`.`quantity`) AS `total_quantity` FROM ((((`v_asset_placement` `p` join `asset_types` `t` on(`t`.`asset_type_id` = `p`.`asset_type_id`)) left join `asset_categories` `c` on(`c`.`category_id` = `t`.`category_id`)) join `csc_depots` `d` on(`d`.`csc_id` = `p`.`csc_id`)) join `areas` `a` on(`a`.`area_id` = `d`.`area_id`)) GROUP BY `d`.`csc_id`, `d`.`csc_code`, `d`.`csc_name`, `a`.`area_id`, `a`.`area_name`, `t`.`asset_type_id`, `c`.`category_name`, `t`.`type_name`, `p`.`unit_of_measure` ;

DROP VIEW IF EXISTS `v_depot_dashboard`;
DROP TABLE IF EXISTS `v_depot_dashboard`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_depot_dashboard`  AS SELECT `d`.`csc_id` AS `csc_id`, `d`.`csc_code` AS `csc_code`, `d`.`csc_name` AS `csc_name`, `d`.`page_no` AS `page_no`, `ar`.`area_id` AS `area_id`, `ar`.`area_no` AS `area_no`, `ar`.`area_name` AS `area_name`, `p`.`province_id` AS `province_id`, `p`.`province_name` AS `province_name`, coalesce((select count(0) from `network_nodes` `n` where `n`.`csc_id` = `d`.`csc_id` and `n`.`status` = 'ACTIVE'),0) AS `node_count`, coalesce((select count(0) from `segments` `s` where `s`.`csc_id` = `d`.`csc_id` and `s`.`status` = 'ACTIVE'),0) AS `segment_count`, coalesce((select sum(`s`.`length_km`) from `segments` `s` where `s`.`csc_id` = `d`.`csc_id` and `s`.`status` = 'ACTIVE'),0) AS `network_km`, coalesce((select sum(`r`.`quantity`) from `v_asset_rollup` `r` where `r`.`csc_id` = `d`.`csc_id`),0) AS `asset_quantity`, coalesce((select count(0) from `v_transformer_rollup` `tr` where `tr`.`csc_id` = `d`.`csc_id`),0) AS `transformer_count`, coalesce((select sum(coalesce(`tr`.`capacity_kva`,0) * `tr`.`quantity`) from `v_transformer_rollup` `tr` where `tr`.`csc_id` = `d`.`csc_id`),0) AS `installed_kva` FROM ((`csc_depots` `d` join `areas` `ar` on(`ar`.`area_id` = `d`.`area_id`)) join `provinces` `p` on(`p`.`province_id` = `ar`.`province_id`)) WHERE `d`.`is_active` = 1 ;

DROP VIEW IF EXISTS `v_line_length_by_area`;
DROP TABLE IF EXISTS `v_line_length_by_area`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_line_length_by_area`  AS SELECT `a`.`area_id` AS `area_id`, `a`.`area_code` AS `area_code`, `a`.`area_name` AS `area_name`, count(distinct `d`.`csc_id`) AS `csc_count`, count(`s`.`segment_register_id`) AS `segment_count`, coalesce(sum(`s`.`is_split`),0) AS `crossing_count`, count(distinct `sr`.`feeder_id`) AS `feeder_count`, coalesce(sum(`s`.`length_km`),0) AS `total_km`, round(coalesce(avg(`s`.`length_km`),0),3) AS `mean_km`, coalesce(max(`s`.`length_km`),0) AS `longest_km` FROM (((`areas` `a` join `csc_depots` `d` on(`d`.`area_id` = `a`.`area_id`)) left join `v_segment_csc_share` `s` on(`s`.`csc_id` = `d`.`csc_id`)) left join `segment_register` `sr` on(`sr`.`segment_register_id` = `s`.`segment_register_id`)) GROUP BY `a`.`area_id`, `a`.`area_code`, `a`.`area_name` ;

DROP VIEW IF EXISTS `v_line_length_by_csc`;
DROP TABLE IF EXISTS `v_line_length_by_csc`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_line_length_by_csc`  AS SELECT `d`.`csc_id` AS `csc_id`, `d`.`csc_code` AS `csc_code`, `d`.`csc_name` AS `csc_name`, `a`.`area_id` AS `area_id`, `a`.`area_name` AS `area_name`, count(`s`.`segment_register_id`) AS `segment_count`, sum(`s`.`is_split`) AS `crossing_count`, coalesce(sum(`s`.`length_km`),0) AS `total_km`, round(coalesce(avg(`s`.`length_km`),0),3) AS `mean_km`, coalesce(max(`s`.`length_km`),0) AS `longest_km` FROM ((`v_segment_csc_share` `s` join `csc_depots` `d` on(`d`.`csc_id` = `s`.`csc_id`)) join `areas` `a` on(`a`.`area_id` = `d`.`area_id`)) GROUP BY `d`.`csc_id`, `d`.`csc_code`, `d`.`csc_name`, `a`.`area_id`, `a`.`area_name` ;

DROP VIEW IF EXISTS `v_transformer_capacity_mix`;
DROP TABLE IF EXISTS `v_transformer_capacity_mix`;   -- the failed import left one
CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_transformer_capacity_mix`  AS SELECT `v_transformer_rollup`.`province_id` AS `province_id`, `v_transformer_rollup`.`area_id` AS `area_id`, `v_transformer_rollup`.`area_name` AS `area_name`, `v_transformer_rollup`.`csc_id` AS `csc_id`, `v_transformer_rollup`.`csc_name` AS `csc_name`, `v_transformer_rollup`.`capacity_kva` AS `capacity_kva`, `v_transformer_rollup`.`transformer_type` AS `transformer_type`, count(0) AS `unit_count`, sum(coalesce(`v_transformer_rollup`.`capacity_kva`,0) * `v_transformer_rollup`.`quantity`) AS `installed_kva` FROM `v_transformer_rollup` WHERE `v_transformer_rollup`.`capacity_kva` is not null GROUP BY `v_transformer_rollup`.`province_id`, `v_transformer_rollup`.`area_id`, `v_transformer_rollup`.`area_name`, `v_transformer_rollup`.`csc_id`, `v_transformer_rollup`.`csc_name`, `v_transformer_rollup`.`capacity_kva`, `v_transformer_rollup`.`transformer_type` ;

