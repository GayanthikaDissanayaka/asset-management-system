# Where the data goes

Every place this application writes to the database, and what it writes.

Read it as: **screen → endpoint → tables → columns**. Each write endpoint
carries the same map as a comment above its method, so the answer is also
in the code you are reading when you need it.

Nothing else writes. Everything not listed here is a `SELECT`.

---

## 1. Record assets against a CSC

| | |
|---|---|
| **Screen** | Assets page → **+ Add assets** |
| **File** | `frontend/src/pages/Assets/AddAssetsDialog.jsx` |
| **Endpoint** | `POST /api/network/assets/records` |
| **Handler** | `AssetExplorerController::storeRecords()` |
| **Who may** | roles allowed to write network data |

**Writes two tables, in one transaction, one pair of rows per line of the form.**

### `assets` — current state, edited later

| Column | Comes from |
|---|---|
| `asset_id` | **generated** by `IdSequence::next('assets')` — `AST-0072` |
| `asset_code` | **generated**: `{csc_code}-{type_code}-{next number}` |
| `asset_type_id` | the line's Asset type dropdown |
| `csc_id` | the CSC dropdown (one CSC for the whole form) |
| `quantity` | the line's Quantity box |
| `unit_of_measure` | **the asset-type catalogue**, never the request |
| `capacity_kva` | the line's kVA box, where the type has one |
| `install_date`, `remarks` | the form footer, shared by every line |
| `condition_status` | the line's Condition dropdown, else `UNKNOWN` |
| `status` | fixed `ACTIVE` |
| `created_by`, `updated_by` | the signed-in user |
| `node_id`, `segment_id` | `NULL` — this route records holdings, not placement |

### `assets_used` — history, never edited

Same figures again, plus `batch_ref` (one random reference for the whole
submission) and `recorded_by`. `assets` answers *what is held now*;
`assets_used` answers *what was entered, when, by whom*. They are written
in one transaction so they cannot disagree.

> **Why `unit_of_measure` is not taken from the request:** poles are counted
> in `nos` and line is measured in `km`. If the browser could choose the
> unit, one mistaken request would put kilometres in a column every
> roll-up adds up as a count.

---

## 2. Record transformers

| | |
|---|---|
| **Screen** | Assets page → **+ Add assets** → a transformer type |
| **File** | `frontend/src/pages/Assets/AddAssetsDialog.jsx` |
| **Endpoint** | `POST /api/network/transformers` |
| **Handler** | `TransformerEntryController::store()` |

Transformers have their own register because each unit is an individual
thing with a serial number, not a quantity.

### `transformers` — one row per physical unit

| Column | Comes from |
|---|---|
| `old_sin_no`, `new_sin_no` | the line's SIN boxes (blank → `NULL`) |
| `transformer_no` | the line's Serial number box |
| `substation_name` | the line's Substation box |
| `transformer_type` | **derived** from the chosen asset type's `type_code` |
| `capacity_kva`, `manufacturer` | the line's boxes |
| `csc_id` | the CSC dropdown |
| `quantity` | fixed `1` — a row is one unit |
| `source_file` | fixed `dashboard-entry`, so entered rows can be told from imported ones |

### `assets_used`

The same entry in the history log, with `transformer_id` pointing at the
row just created and `asset_id` left `NULL`.

---

## 3. Record an HV segment

| | |
|---|---|
| **Screen** | HV Length → Network Register → **+ HV Length** |
| **File** | `frontend/src/pages/Dashboard/Components/AddSegmentDialog.jsx` |
| **Endpoint** | `POST /api/network/segments` |
| **Handler** | `NetworkController::storeSegment()` |

**Writes up to three tables in one transaction.**

### `segment_register` — one row per segment

| Column | Comes from |
|---|---|
| `segment_register_id` | **generated** by `IdSequence::next('segment_register')` — `SRG-01328` |
| `segment_code` | the Segment code box — **unique per CSC** |
| `csc_id` | **derived**: the CSC holding the largest share of the length |
| `feeder_id` | the Feeder dropdown |
| `length_km` | **derived**: the sum of every CSC portion entered |
| `voltage_level` | the Voltage dropdown, else `33kV` |
| `status` | the Status dropdown, else `ACTIVE` |
| `source_file` | fixed `dashboard-entry` |

### `segment_csc` — only when the segment crosses a boundary

One row per CSC with the kilometres inside that CSC. A segment wholly
inside one CSC gets **no** rows here: `v_segment_csc_share` falls back to
the register row, so writing one portion would duplicate it.

This is what makes area and province totals reconcile — a run crossing
from one area into another contributes only its own part to each.

### `segment_asset` — what the segment carries

One row per line of the form: `asset_type_id`, `quantity`, and
`unit_of_measure` **read from the asset-type catalogue**, as above.

---

## 4. Import a spreadsheet of segments

| | |
|---|---|
| **Screen** | Dashboard sidebar → **Import** |
| **File** | `frontend/src/pages/Dashboard/Components/ImportDialog.jsx` |
| **Endpoint** | `POST /api/network/import` |
| **Handler** | `SegmentImportController::import()` |

Writes the **same three tables** as §3, row by row, with `source_file`
set to the uploaded file's name instead of `dashboard-entry`.

Runs as a preview first: nothing is written until the request says to
apply it. A segment code that already exists for the same CSC is
reported as a clash and skipped, not overwritten.

---

## 5. Save a report into the project

| | |
|---|---|
| **Screen** | Reports page → **Save to project** |
| **File** | `frontend/src/pages/Reports/ReportsPage.jsx` |
| **Endpoint** | `POST /api/network/reports/save` |
| **Handler** | `SpreadsheetController::saveReport()` |

Writes a **file** to the project's `reports/` folder. No table.

---

## 6. Accounts

| Screen | Endpoint | Writes |
|---|---|---|
| Register | `POST /api/auth/register` | `users` (pending, no role yet) |
| Login | `POST /api/auth/login` | `personal_access_tokens` |
| Logout | `POST /api/auth/logout` | deletes the current token |
| Forgot / reset password | `POST /api/auth/forgot-password`, `/reset-password` | `password_resets`, then `users.password_hash` |
| Approvals dialog | `POST /api/admin/users/{user}/approve` · `/decline` | `users.role_id`, `users.csc_id`, `users.status` |
| Notification bell | `POST /api/notifications/{id}/read` · `/read-all` | `notifications.read_at` |

---

## The rule the write paths follow

**The browser sends what the user typed. It never sends what the
database can work out for itself.**

Primary keys are part of that. They are codes now (`SRG-01328`), and
`IdSequence` allocates every one inside the same transaction as the
insert — a request cannot choose its own key.

Units of measure, asset codes, `source_file`, the owning CSC of a
crossing segment, totals and timestamps are all decided on the server —
from the catalogue, from the other values in the request, or from the
signed-in user. A request cannot set them even by trying.

That is why a bad or hostile request can produce a wrong *entry*, but not
a row that breaks the roll-ups everyone reads.
