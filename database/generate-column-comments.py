"""
Generates database/add-column-comments.sql.

Each statement re-states the column's EXACT definition as it appears in
database/ceb_uva_ams.sql and appends a COMMENT. MySQL has no
"COMMENT ON COLUMN", so MODIFY COLUMN is the only way, and restating a
definition by hand is how a varchar(30) quietly becomes a varchar(20).
Copying it verbatim from the dump is what makes this safe.
"""
import io, re, json, os, sys

ROOT = sys.argv[1]
DUMP = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'database', 'ceb_uva_ams.sql')
OUT = os.path.join(ROOT, 'database', 'add-column-comments.sql')

# ---------------------------------------------------------------- comments

C = {}

def t(table, **cols):
    for k, v in cols.items():
        C[f'{table}.{k}'] = ' '.join(v.split())

t('id_sequences',
  table_name='PK. The table these codes are for. One row per table that has a generated key.',
  id_column='Which column of that table the code goes in.',
  id_prefix="The letters the code starts with: SRG, CSC, TRF. Unique, so a code says which table it came from on sight.",
  pad_width='How many digits follow the dash. 5 gives SRG-01328; 3 gives CSC-018.',
  last_number='The highest number handed out so far. IdSequence (app/Support) locks this row, adds one, and formats the result. It can run ahead of the real rows: a rolled-back insert keeps its number, because a gap is harmless and a duplicate is not.',
  description='What the table holds, in a few words, for whoever opens this table first.')

t('provinces',
  province_id='PK. Province. Uva is the only one loaded.',
  province_code='Short code, e.g. UVA.',
  province_name='Display name.',
  is_active='0 hides it from the pickers without deleting it.',
  created_at='Row created.')

t('areas',
  area_id='PK. Operational area; Uva has five.',
  province_id='FK -> provinces.province_id.',
  area_no="CEB's own area numbering from the source workbook.",
  area_code='Short code used across the UI, e.g. BDL.',
  area_name='Display name, e.g. Badulla.',
  is_active='0 hides it from the pickers without deleting it.',
  created_at='Row created.')

t('csc_depots',
  csc_id='PK. Consumer Service Centre; Uva has seventeen. The CSC is the place every asset and every metre of line belongs to.',
  area_id='FK -> areas.area_id.',
  csc_code='Short code used across the UI and in asset_code.',
  csc_name='Display name.',
  depot_type='CSC or depot.',
  page_no='Page in the source workbook this CSC was read from.',
  contact_officer='Officer responsible. Free text.',
  contact_phone='Contact number. Free text.',
  latitude='Decimal degrees, WGS84. NULL where not surveyed.',
  longitude='Decimal degrees, WGS84. NULL where not surveyed.',
  is_active='0 hides it from the pickers without deleting it.',
  created_at='Row created.')

t('feeders',
  feeder_id='PK. HV feeder.',
  feeder_code='Short code, the name people use for it.',
  feeder_name='Full name.',
  origin_csc_id='FK -> csc_depots.csc_id. The CSC the feeder starts in. A feeder may run through several; this is only where it begins.',
  source_name='Grid substation feeding it.',
  external_source='1 when fed from outside the province.',
  voltage_level='33kV, 11kV or 400V.',
  status='ACTIVE, PLANNED or RETIRED.',
  remarks='Free text.',
  created_at='Row created.',
  updated_at='Row last changed.')

t('asset_categories',
  category_id='PK. Main asset: Transformer, Switchgear, Conductor, Pole.',
  category_code='Short code.',
  category_name='Display name; the "Main asset" column in the UI.',
  description='What belongs in this category.',
  display_order='Sort order in the UI. Lower first.',
  is_active='0 hides it without deleting it.')

t('asset_types',
  asset_type_id='PK. A specific type within a category, e.g. Distribution transformer.',
  category_id='FK -> asset_categories.category_id.',
  type_code='Short code, used in asset_code and to derive transformers.transformer_type.',
  type_name='Display name.',
  unit_of_measure="THE AUTHORITY ON UNITS: 'nos' for counted things, 'km' for measured line. Every write path reads the unit from HERE and never from the request, so no entry can put kilometres in a column the roll-ups add up as a count.",
  is_line_asset='1 for things measured along the line rather than counted at a point.',
  rated_kva='Nameplate rating where the type has a fixed one. NULL otherwise.',
  allow_decimal='1 when a fractional quantity is meaningful, e.g. km. 0 for whole counts like poles.',
  display_order='Sort order in the UI. Lower first.',
  is_active='0 hides it from the pickers without deleting it.',
  created_at='Row created.')

t('assets',
  asset_id='PK. One holding of one asset type at one CSC. CURRENT STATE: this row is edited as things change. The history is in assets_used.',
  asset_code='Human-readable code, generated on insert as {csc_code}-{type_code}-{next number}. This is the identifier to quote, not asset_id.',
  asset_type_id='FK -> asset_types.asset_type_id.',
  csc_id='FK -> csc_depots.csc_id. The CSC that holds it. Set for anything entered through the Assets page.',
  node_id='FK -> network_nodes.node_id. Where it physically sits, when known. NULL for a plain holding.',
  segment_id='FK -> segments.segment_id. The segment it sits on, when known. NULL for a plain holding.',
  oriented_to_segment_id='FK -> segments.segment_id. For a switch, the segment it faces.',
  quantity='How many, or how far. Read with unit_of_measure; the two are meaningless apart.',
  unit_of_measure="Copied from asset_types on insert. 'nos' or 'km'. NEVER add across different units.",
  capacity_kva='Nameplate rating for this holding, where the type has one.',
  material='Material where it distinguishes otherwise identical items, e.g. pole type.',
  install_date='When it went in, if known.',
  condition_status='NEW, GOOD, FAIR, POOR, FAULTY or UNKNOWN.',
  status='ACTIVE, PLANNED or RETIRED.',
  remarks='Free text.',
  created_by='FK -> users.user_id. Who entered it.',
  created_at='Row created.',
  updated_by='FK -> users.user_id. Who last changed it.',
  updated_at='Row last changed.',
  last_verified_by='FK -> users.user_id. Who last checked it on the ground.',
  last_verified_at='When it was last checked on the ground.')

t('assets_used',
  asset_usage_id='PK. HISTORY: one line of one entry, as it was entered. Never edited. assets holds the current state; this holds what happened.',
  asset_id='FK -> assets.asset_id, for a counted holding. NULL when the entry was a transformer.',
  transformer_id='FK -> transformers.transformer_id, for a transformer. NULL when the entry was a counted holding.',
  asset_type_id='FK -> asset_types.asset_type_id.',
  csc_id='FK -> csc_depots.csc_id.',
  area_id='FK -> areas.area_id. Stored alongside the CSC so history stays true even if a CSC is moved to another area later.',
  quantity='How many, or how far, in this line of the entry.',
  unit_of_measure="'nos' or 'km', copied from asset_types.",
  condition_status='Condition as entered.',
  capacity_kva='Rating as entered.',
  used_on='The date entered on the form, if any.',
  used_for='Free-text note from the form.',
  batch_ref='One random reference shared by every line of a single submission, so an entry can be read back as the one act it was.',
  recorded_by='FK -> users.user_id. Who entered it.',
  recorded_at='When it was entered.')

t('transformers',
  transformer_id='PK. ONE ROW PER PHYSICAL UNIT. Transformers are individual plant with serial numbers, not a quantity, which is why they are not held in assets.',
  csc_id='FK -> csc_depots.csc_id.',
  node_id='FK -> network_nodes.node_id, where known.',
  asset_id='FK -> assets.asset_id, where the unit is also a holding row.',
  asset_type_id='FK -> asset_types.asset_type_id.',
  old_sin_no="CEB's previous SIN number. Either SIN may be blank; the pair is how a unit is looked up.",
  new_sin_no="CEB's current SIN number.",
  substation_name='The substation this unit serves.',
  transformer_type='Distribution, Bulk, Bulk & Distribution or Bulk (MHP). Derived from the asset type on entry.',
  capacity_kva='Nameplate rating. Summed as "installed kVA" across the province.',
  transformer_no='Manufacturer serial number. Must be unique: the same unit entered twice is the error the check exists to catch.',
  manufacturer='Who made it.',
  fly_length_km='From the transformer import sheet, "Fly length (km)".',
  combined_fly_length_km='From the transformer import sheet, "Combined fly length (km)".',
  free_wayleave_km='From the transformer import sheet, "Free wayleave (km)".',
  wayleave_distance_km='From the transformer import sheet, "Distance to wayleave (km)".',
  total_distance_km='From the transformer import sheet, "Total distance (km)".',
  quantity='Always 1. A row here IS one unit; the column exists so the transformer register can be read with the same shape as assets.',
  condition_status='NEW, GOOD, FAIR, POOR, FAULTY or UNKNOWN.',
  status='ACTIVE, PLANNED or RETIRED.',
  install_date='When it went in, if known.',
  latitude='Decimal degrees, WGS84.',
  longitude='Decimal degrees, WGS84.',
  remarks='Free text.',
  source_file="Where the row came from: 'dashboard-entry' for one typed into the application, otherwise the name of the imported file.",
  created_at='Row created.',
  updated_at='Row last changed.')

t('switchgear',
  switchgear_id='PK. One switch, breaker or recloser.',
  csc_id='FK -> csc_depots.csc_id.',
  asset_type_id='FK -> asset_types.asset_type_id.',
  node_id='FK -> network_nodes.node_id, where known.',
  asset_id='FK -> assets.asset_id, where it is also a holding row.',
  switch_code='The code on the unit. How it is referred to in the field.',
  switch_name='Display name.',
  nearest_substation='Where it is, in words.',
  status='ACTIVE, PLANNED or RETIRED.',
  remarks='Free text.',
  source_file="'dashboard-entry' or the name of the imported file.",
  created_at='Row created.',
  updated_at='Row last changed.')

t('segment_register',
  segment_register_id='PK. THE WORKING HV SEGMENT REGISTER. Every length figure in the application is built from this table, not from segments.',
  csc_id='FK -> csc_depots.csc_id. For a segment crossing a boundary this is the CSC holding the LARGEST share; the parts are in segment_csc.',
  feeder_id='FK -> feeders.feeder_id.',
  segment_id='FK -> segments.segment_id, when this row has been matched to the node model. Usually NULL.',
  segment_code="The code CEB uses for the run, e.g. BDSM010. Unique per CSC, not globally: two CSCs may each use the same code for their own run.",
  length_km='Total length of the whole segment. For a crossing segment this is the sum of its segment_csc parts, NOT the part inside csc_id.',
  voltage_level='33kV, 11kV or 400V.',
  status='ACTIVE, PLANNED or RETIRED.',
  remarks='Free text.',
  source_file="'dashboard-entry' for a row typed into the application, otherwise the name of the imported spreadsheet.",
  created_at='Row created.',
  updated_at='Row last changed.')

t('segment_csc',
  segment_csc_id='PK. One CSC\'s SHARE of a segment that crosses a boundary.',
  segment_register_id='FK -> segment_register.segment_register_id.',
  csc_id='FK -> csc_depots.csc_id.',
  length_km='The kilometres of this segment INSIDE this CSC. Summing these is what makes area and province totals reconcile instead of double-counting a crossing run.',
  remarks='Free text.',
  created_at='Row created.',
  updated_at='Row last changed.')

t('segment_asset',
  segment_asset_id='PK. What a segment carries: poles, conductor and so on.',
  segment_register_id='FK -> segment_register.segment_register_id.',
  asset_type_id='FK -> asset_types.asset_type_id.',
  quantity='How many, or how far. Read with unit_of_measure.',
  unit_of_measure="'nos' or 'km', copied from asset_types on insert, never taken from the request.",
  remarks='Free text.',
  created_at='Row created.',
  updated_at='Row last changed.')

t('segment_switchgear',
  segment_switchgear_id='PK. Links a register row to a switch that sits on it.',
  segment_register_id='FK -> segment_register.segment_register_id.',
  switchgear_id='FK -> switchgear.switchgear_id. NULL while only the text reference is known.',
  switch_ref='The switch as written on the source sheet, before it was matched to a switchgear row.')

t('segment_transformer',
  segment_transformer_id='PK. Links a register row to a transformer that sits on it.',
  segment_register_id='FK -> segment_register.segment_register_id.',
  transformer_id='FK -> transformers.transformer_id. NULL while only the text reference is known.',
  transformer_ref='The transformer as written on the source sheet, before it was matched to a transformer row.')

t('segments',
  segment_id='PK. The NODE-BASED model of the network, kept for GIS work. NOT written by the application and NOT what any length figure is built from -- see segment_register for that.',
  segment_code='Code for the run.',
  feeder_id='FK -> feeders.feeder_id.',
  csc_id='FK -> csc_depots.csc_id.',
  from_node_id='FK -> network_nodes.node_id. Where the run starts.',
  to_node_id='FK -> network_nodes.node_id. Where it ends.',
  from_point='Start point in words, where there is no node.',
  to_point='End point in words, where there is no node.',
  circuit_no='Circuit number where a route carries more than one.',
  length_km='Length of the run.',
  voltage_level='33kV, 11kV or 400V.',
  is_normally_open='1 when the run is normally open, i.e. not carrying load.',
  is_reversible='1 when it can be fed from either end.',
  status='ACTIVE, PLANNED or RETIRED.',
  remarks='Free text.',
  created_by='FK -> users.user_id.',
  created_at='Row created.',
  updated_by='FK -> users.user_id.',
  updated_at='Row last changed.')

t('network_nodes',
  node_id='PK. A point on the network: substation, pole, tee-off. Part of the GIS model; not written by the application.',
  node_code='Code for the point.',
  csc_id='FK -> csc_depots.csc_id.',
  node_kind='What sort of point it is.',
  name='Display name.',
  latitude='Decimal degrees, WGS84.',
  longitude='Decimal degrees, WGS84.',
  ownership_source='Who owns or maintains it.',
  ownership_note='Free text about ownership.',
  is_line_end='1 when the line stops here.',
  status='ACTIVE, PLANNED or RETIRED.',
  remarks='Free text.',
  created_by='FK -> users.user_id.',
  created_at='Row created.',
  updated_by='FK -> users.user_id.',
  updated_at='Row last changed.')

t('node_shared_with',
  node_id='FK -> network_nodes.node_id. Part of the PK with csc_id.',
  csc_id='FK -> csc_depots.csc_id. A second CSC that also uses this point.',
  share_reason='Why it is shared.',
  created_at='Row created.')

t('csc_aliases',
  csc_alias_id='PK. Another name a source spreadsheet used for a CSC, so an import can match it.',
  csc_id='FK -> csc_depots.csc_id.',
  alias_name='The name as written in the source file.',
  source_file='Which file used this spelling.')

t('users',
  user_id='PK.',
  role_id='FK -> roles.role_id. NULL until an administrator approves the account; that is what "pending" means.',
  requested_role_id='FK -> roles.role_id. The role asked for at sign-up. Kept after approval so the request can be audited.',
  area_id='FK -> areas.area_id. The area this user may see.',
  csc_id='FK -> csc_depots.csc_id. The CSC this user may see.',
  username='Sign-in name. Unique.',
  employee_no="CEB employee number. The human identifier for a person.",
  password_hash='Bcrypt hash. Never a password.',
  full_name='Display name.',
  designation='Job title.',
  email='Contact address.',
  phone='Contact number.',
  registration_source='How the account was created.',
  scope_assigned='1 once an administrator has set the area and CSC above.',
  email_verified_at='When the address was confirmed. NULL if never.',
  is_active='0 blocks sign-in without deleting the account.',
  last_login_at='Last successful sign-in.',
  failed_attempts='Consecutive failed sign-ins. Reset on success.',
  locked_until='Sign-in refused until this time, after too many failures.',
  created_at='Row created.',
  updated_at='Row last changed.')

t('roles',
  role_id='PK.',
  role_code='ADMIN, and the other codes the middleware checks. The code is what authorisation tests, never the name.',
  role_name='Display name.',
  description='What this role may do.')

t('password_resets',
  reset_id='PK.',
  user_id='FK -> users.user_id.',
  token_hash='Hash of the emailed token. Never the token itself.',
  expires_at='After this the token is refused.',
  used_at='When it was spent. A token is single-use.',
  requested_ip='Where the request came from.',
  created_at='Row created.')

t('personal_access_tokens',
  id='PK. Laravel Sanctum API tokens. Framework table -- do not hand-edit.',
  tokenable_type='Model class the token belongs to.',
  tokenable_id='Key of that model, i.e. users.user_id.',
  name='Label for the token.',
  token='Hash of the token. Never the token itself.',
  abilities='What the token may do.',
  last_used_at='Last request that presented it.',
  expires_at='After this the token is refused.',
  created_at='Row created.',
  updated_at='Row last changed.')

t('notifications',
  notification_id='PK. One item in the bell menu.',
  recipient_id='FK -> users.user_id. Who sees it.',
  type='What kind of notice it is.',
  title='Headline shown in the bell.',
  body='Longer text.',
  subject_user_id='FK -> users.user_id. Who the notice is ABOUT, e.g. the person requesting access.',
  link='Where selecting it takes you.',
  status='Whether it still needs action.',
  resolution='What was decided, once it does not.',
  read_at='When the recipient opened it. NULL means unread, which is what the bell counts.',
  resolved_at='When it was acted on.',
  created_at='Row created.')

t('audit_log',
  audit_id='PK. What changed, who changed it, and what it was before.',
  table_name='Table that changed.',
  record_id='Primary key of the row that changed.',
  action='INSERT, UPDATE or DELETE.',
  changed_by='FK -> users.user_id.',
  changed_at='When.',
  old_values='JSON of the row before. NULL for an insert.',
  new_values='JSON of the row after. NULL for a delete.',
  ip_address='Where the request came from.',
  note='Free text.')

t('maintenance_logs',
  maintenance_log_id='PK. Work done on a thing.',
  asset_id='FK -> assets.asset_id. One of the four targets is set.',
  segment_id='FK -> segments.segment_id.',
  node_id='FK -> network_nodes.node_id.',
  transformer_id='FK -> transformers.transformer_id.',
  action_type='What was done.',
  performed_by='FK -> users.user_id.',
  performed_at='When it was done.',
  remarks='Free text.',
  photo_path='Path to a photograph, where one was taken.',
  created_at='Row created.')

# ----------------------------------------------------------------- build

txt = io.open(DUMP, encoding='utf-8', errors='replace').read()
lines = txt.split('\n')
views = set(re.findall(r'VIEW `(\w+)`', txt))

# AUTO_INCREMENT is NOT in this dump's CREATE TABLE statements -- it is
# attached afterwards by its own ALTER. MODIFY COLUMN replaces the whole
# column definition, so restating one of these 25 primary keys without
# AUTO_INCREMENT would silently strip it and break every insert in the
# application. Collect them and put the attribute back.
auto = {
    (m.group(1), m.group(2))
    for m in re.finditer(
        r'ALTER TABLE `(\w+)`\s*\n\s*MODIFY `(\w+)` [^;]*?AUTO_INCREMENT', txt
    )
}

tables = {}
i = 0
while i < len(lines):
    m = re.match(r'CREATE TABLE `(\w+)` \($', lines[i])
    if m:
        name, cols, j = m.group(1), [], i + 1
        while j < len(lines) and not lines[j].startswith(')'):
            line = lines[j].rstrip().rstrip(',')
            c = re.match(r'\s*`(\w+)` (.+)$', line)
            if c:
                cols.append((c.group(1), c.group(2)))
            j += 1
        if name not in views:
            tables[name] = cols
        i = j
    i += 1

missing, out = [], []
out.append("""-- =====================================================================
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

""")

for name in sorted(tables):
    out.append(f'\n-- {"-" * 66}\n-- {name}\n-- {"-" * 66}\n')
    for col, definition in tables[name]:
        key = f'{name}.{col}'
        # The text-key migration already commented the key columns with
        # their code format ("Format ARE-01"). Those stay: this file only
        # fills the blanks.
        if 'COMMENT ' in definition:
            continue

        comment = C.get(key)
        if comment is None:
            missing.append(key)
            continue
        escaped = comment.replace('\\', '\\\\').replace("'", "''")
        # Put AUTO_INCREMENT back where the schema attaches it separately.
        # Only the column attribute -- the trailing "AUTO_INCREMENT=6" in
        # those ALTERs is the table's next value, not part of a column.
        suffix = ' AUTO_INCREMENT' if (name, col) in auto else ''
        body = f'{definition}{suffix}'

        # MariaDB fixes the order of a column definition's clauses:
        # COMMENT comes BEFORE an inline CHECK, not after it. audit_log's
        # two json_valid() columns are the only ones here that carry one,
        # and appending the comment blindly is a syntax error.
        check = re.search(r'\s+CHECK \(.*\)$', body)
        if check:
            body = f"{body[:check.start()]} COMMENT '{escaped}'{check.group(0)}"
        else:
            body = f"{body} COMMENT '{escaped}'"

        out.append(f'ALTER TABLE `{name}` MODIFY COLUMN `{col}` {body};\n')

io.open(OUT, 'w', encoding='utf-8', newline='\n').write(''.join(out))

total = sum(len(v) for v in tables.values())
print(f'wrote {OUT}')
print(f'{total - len(missing)}/{total} columns commented')
print(f'{len(auto)} AUTO_INCREMENT columns preserved')
if missing:
    print('MISSING:', ', '.join(missing))
