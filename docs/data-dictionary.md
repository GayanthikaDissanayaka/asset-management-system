# Data dictionary

What each table is for and how they fit together.

The per-column descriptions live **in the database itself** — run
`database/add-column-comments.sql` once and phpMyAdmin shows a
description beside every column, in the Structure tab and in the column
tooltips. This page is the map above those comments: which table to look
in, and which of two similar-looking tables is the real one.

For where data *enters* the system, see [data-flow.md](data-flow.md).

---

## Reading the schema

Two conventions run through the whole database.

**Every key is a readable code, and most tables also carry CEB's own
field code.** `segment_register.segment_register_id` is `SRG-01327`; its
field code is `BDSM010`.

The keys were integers until September 2026. They are now text codes
allocated from the `id_sequences` table — prefix, dash, zero-padded
number — so a row identifies itself on sight in phpMyAdmin, in a report,
or in a foreign key, without joining anything.

| | |
|---|---|
| **Who allocates one** | `IdSequence::next()` in `app/Support/IdSequence.php`, never the database |
| **Format** | `{prefix}-{number padded to pad_width}`, both from `id_sequences` |
| **Eloquent** | every model sets `$incrementing = false` and `$keyType = 'string'`, and uses the `HasSequencedId` trait |
| **Gaps** | expected. A rolled-back insert keeps its number, because a gap is harmless and a duplicate key is not |

Zero padding is what makes sorting the codes as text give the same order
as sorting the numbers they replaced.

| Table | Key | Code people use |
|---|---|---|
| `id_sequences` | `table_name` | — (it is the allocator itself) |
| `provinces` | `province_id` | `province_code` |
| `areas` | `area_id` | `area_code` |
| `csc_depots` | `csc_id` | `csc_code` |
| `feeders` | `feeder_id` | `feeder_code` |
| `asset_categories` | `category_id` | `category_code` |
| `asset_types` | `asset_type_id` | `type_code` |
| `assets` | `asset_id` | `asset_code` — generated `{csc_code}-{type_code}-{n}` |
| `segment_register` | `segment_register_id` | `segment_code` — e.g. `BDSM010` |
| `switchgear` | `switchgear_id` | `switch_code` |
| `transformers` | `transformer_id` | `new_sin_no` / `old_sin_no` + `transformer_no` |
| `users` | `user_id` | `employee_no` |

`segment_code` is unique **per CSC**, not globally: two CSCs may each use
the same code for their own run, which is why `segment_register` has a
unique key on `(csc_id, segment_code)` rather than on the code alone.

**A quantity is never stored without its unit.** Wherever there is a
`quantity` there is a `unit_of_measure` beside it, and the unit is copied
from `asset_types.unit_of_measure` when the row is written — never taken
from the request. Poles are counted in `nos`, line is measured in `km`,
and **a total that adds across units is meaningless**. Any query you
write should group by `unit_of_measure` or filter to one.

---

## The place hierarchy

```
provinces ──< areas ──< csc_depots
                            │
                            └──< everything else
```

Every asset, transformer, switch and metre of line belongs to exactly
one **CSC** (Consumer Service Centre). Areas and province totals are
roll-ups of the CSCs beneath them — nothing is stored at area level, so
the levels cannot drift apart.

`csc_aliases` holds the other spellings source spreadsheets have used for
a CSC, so an import can match "Badulla CSC" to the right row.

---

## The two segment tables — read this before querying lengths

There are two, and they are not interchangeable.

### `segment_register` — the working register. **Use this one.**

Every HV length figure in the application is built from it. It is what
the spreadsheets were loaded into and what the "+ HV Length" form writes.
Roughly 3,400 km across seventeen CSCs.

Its companions:

- **`segment_csc`** — for a segment that crosses a CSC boundary, one row
  per CSC with the kilometres *inside that CSC*. A segment wholly inside
  one CSC has **no** rows here; the view falls back to the register row.
  This is what makes area and province totals reconcile instead of
  counting a crossing run twice.
- **`segment_asset`** — what the segment carries: poles, conductor.
- **`segment_switchgear`**, **`segment_transformer`** — link a register
  row to plant sitting on it. The `*_ref` column holds the reference as
  written on the source sheet, kept even when it has not been matched to
  a real row yet.

### `segments` and `network_nodes` — the GIS model. **Not in use.**

A fuller node-to-node model of the network (`from_node_id`, `to_node_id`,
`is_normally_open`), kept for ArcGIS work. **No application code writes
to these tables and no length figure comes from them.** If you query
`segments` expecting the register, you will get the wrong answer.

> `segment_register.segment_id` is the join between the two, for rows
> that have been matched. It is usually `NULL`.

---

## The asset tables

### `assets` — current state

One row per *holding*: "40 RC poles at Welimada". Edited as things
change. `csc_id` says where it is held; `node_id` and `segment_id` say
where it physically sits, when that is known, and are `NULL` for a plain
holding.

### `assets_used` — history

The same entries as they were made, never edited. `batch_ref` ties
together every line of one submission, so an entry can be read back as
the single act it was rather than as unrelated rows sharing a timestamp.

`assets` answers *what is held now*. `assets_used` answers *what was
entered, when, and by whom*. Both are written in one transaction, so
they cannot disagree.

### `transformers` — one row per physical unit

Not held in `assets`, because a transformer is an individual piece of
plant with a serial number, not a quantity. `transformer_no` (the
manufacturer serial) must be unique — the same unit entered twice is
exactly the mistake that check exists to catch. `quantity` is always
`1`.

The `fly_length_km`, `combined_fly_length_km`, `free_wayleave_km`,
`wayleave_distance_km` and `total_distance_km` columns come straight
from the transformer import spreadsheet's columns of the same names.

### `switchgear` — one row per switch, breaker or recloser

`source_file` on `transformers`, `switchgear` and `segment_register` is
`dashboard-entry` for a row typed into the application, and otherwise
the name of the file it was imported from. That is how anyone looking at
a row later can tell where it came from.

---

## Accounts

`users.role_id` is **`NULL` until an administrator approves the
account** — that is what "pending" means, and `v_pending_users` is
simply the rows where it is null. `requested_role_id` keeps what was
asked for at sign-up, so the decision can be audited afterwards.

Authorisation tests `roles.role_code`, never `role_name`, so a role can
be renamed for display without changing who can do what.

`password_resets.token_hash` and `personal_access_tokens.token` store
**hashes**, never the token itself.

---

## The views

**23** `v_*` views do the roll-ups in SQL rather than in PHP or React,
so every screen showing "transformers by area" is showing the same
arithmetic.

They are rebuilt by `database/rebuild-views.sql`, which is the file to
run after any change to a column they read — the text-key migration
renamed four columns and left every view uncreatable until it was run.
Ten further views that nothing read were dropped at the same time; their
definitions are still in `database/ceb_uva_ams.sql` if one is wanted
back.

The ones worth knowing:

| View | Answers |
|---|---|
| `v_depot_dashboard` | one row per CSC: transformers, installed kVA, network km |
| `v_transformer_totals_by_area` | transformers and kVA per area |
| `v_transformer_capacity_mix` | units and kVA by transformer type and rating |
| `v_line_length_by_area` / `_by_csc` / `_by_feeder` | HV length roll-ups |
| `v_segment_csc_share` | **the one that apportions a crossing segment.** Every length figure ultimately comes through here |
| `v_asset_placement` | the four ways an asset can be placed, unified |
| `v_asset_register` / `v_asset_rollup` / `v_asset_totals` | the asset register at three levels |
| `v_search_index` | what global search looks in |
| `v_pending_users` | accounts awaiting approval |

Because these are views, a row written by the application appears in
every total immediately. Nothing is cached and nothing needs
recalculating.

---

## Keeping this true

When you change what a column means:

1. edit its comment in `database/generate-column-comments.py` and
   re-run it against a fresh structure dump, then run the SQL it writes;
2. run `database/rebuild-views.sql` if any view reads that column —
   a renamed column does not break a view until something queries it,
   and then it breaks all of them at once;
3. update this page if it changes which table someone should query.

Both generators live beside the SQL they produce, so the file and the
reason for it stay together.
