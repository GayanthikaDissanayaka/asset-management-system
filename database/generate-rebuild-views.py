"""
Generates database/rebuild-views.sql.

The view definitions come from the Sep-17 dump, which predates the move
to text primary keys. Three things are done to them:

  1. the corrupted `nullunion allselect` runs are repaired (the dump lost
     some newlines, gluing two keywords into one token);
  2. the renamed key columns are renamed in the definitions;
  3. the 10 views nothing reads are left out, and the DEFINER is dropped
     so the views are not pinned to root@localhost.
"""
import io, re, os, sys

ROOT = sys.argv[1]
DUMP = os.path.join(ROOT, 'database', 'ceb_uva_ams.sql')
OUT = os.path.join(ROOT, 'database', 'rebuild-views.sql')

# Columns the text-key migration renamed. Every one is a primary key or a
# foreign key to one; no other column changed name.
RENAMES = {
    'used_id': 'asset_usage_id',
    'alias_id': 'csc_alias_id',
    'log_id': 'maintenance_log_id',
    'register_id': 'segment_register_id',
}

# Nothing in the application reads these, and no surviving view depends
# on them. v_node_degree and v_node_segments only ever fed
# v_data_quality_issues, so all three go together.
DROP = [
    'v_data_quality_issues',
    'v_node_degree',
    'v_node_segments',
    'v_segment_adjacency',
    'v_segment_asset_by_csc',
    'v_segment_detail',
    'v_segment_link_quality',
    'v_substation_capacity',
    'v_switchgear_by_csc',
    'v_transformer_data_quality',
]

"""
v_search_index is rewritten rather than recovered.

Its first UNION branch -- the transformer one -- was destroyed in the
dump: everything between SELECT and FROM is gone. That branch is also
where MySQL takes the view's output column names from, which is why the
surviving branches carry auto-generated rubbish like `Name_exp_4` and
`'segment' COLLATE utf8mb4_unicode_ci` as column names. Even a perfect
recovery of the missing text would give a view whose columns are named
after expressions.

So it is written out here instead, from the contract SearchController
depends on: ten columns -- kind, entity_id, code, title, subtitle,
place, csc_id, area_id, status, keywords -- across the seven kinds in
its KIND_ORDER. The shape of each branch follows the surviving ones.

COLLATE on every text expression is deliberate: the branches mix column
values with string literals, and without it MariaDB refuses the UNION
with "Illegal mix of collations".
"""
SEARCH_INDEX = """CREATE ALGORITHM=UNDEFINED SQL SECURITY INVOKER VIEW `v_search_index` AS
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
LEFT JOIN `asset_types` `t` ON `t`.`asset_type_id` = `a`.`asset_type_id`"""

raw = io.open(DUMP, encoding='utf-8', errors='replace').read()

# (1) Repair: `is not null` + `union all` + `select` lost the newlines
# between them and became one unparseable token.
repaired = raw.replace('nullunion allselect', 'null union all select')

stmts = re.findall(
    r'(CREATE ALGORITHM[^;]*?VIEW `(\w+)`\s+AS\s+.*?);\s*\n', repaired, re.S
)

order = []
bodies = {}
for body, name in stmts:
    if name in DROP:
        continue
    # (2) rename the migrated key columns
    for old, new in RENAMES.items():
        body = re.sub(r'`%s`' % old, '`%s`' % new, body)
    # (3) unpin from root@localhost; INVOKER runs as whoever queries it
    body = re.sub(r'DEFINER=`[^`]*`@`[^`]*` ', '', body)
    body = body.replace('SQL SECURITY DEFINER', 'SQL SECURITY INVOKER')
    # The dump's copy of this one is unrecoverable; use the rewrite above.
    if name == 'v_search_index':
        body = SEARCH_INDEX
    order.append(name)
    bodies[name] = body

# A view that feeds another must be created first. Sorting by dependency
# rather than alphabetically is what lets this file run top to bottom.
deps = {
    n: {o for o in bodies if o != n and re.search(r'`%s`' % o, bodies[n])}
    for n in bodies
}
sorted_names, placed = [], set()
while len(sorted_names) < len(bodies):
    progressed = False
    for n in order:
        if n in placed:
            continue
        if deps[n] <= placed:
            sorted_names.append(n)
            placed.add(n)
            progressed = True
    if not progressed:                      # cycle: emit the rest as-is
        for n in order:
            if n not in placed:
                sorted_names.append(n)
                placed.add(n)

out = ["""-- =====================================================================
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

"""]

out.append('-- ---------- clear the wreckage ----------\n')
for n in DROP:
    out.append(f'DROP VIEW IF EXISTS `{n}`;\nDROP TABLE IF EXISTS `{n}`;\n')
out.append('\n')

out.append('-- ---------- rebuild, dependencies first ----------\n\n')
for n in sorted_names:
    out.append(f'DROP VIEW IF EXISTS `{n}`;\n')
    out.append(f'DROP TABLE IF EXISTS `{n}`;   -- the failed import left one\n')
    out.append(bodies[n] + ';\n\n')

io.open(OUT, 'w', encoding='utf-8', newline='\n').write(''.join(out))
print(f'wrote {OUT}')
print(f'rebuilt : {len(sorted_names)} views')
print(f'dropped : {len(DROP)} unused views')
print('order   :', ', '.join(sorted_names[:5]), '...')
