/* =====================================================================
   Shared helpers for reading the dashboard API.

   Two facts about the backend drive all of this:

     1. MySQL returns SUM() and DECIMAL columns as STRINGS through the
        PDO driver, so "312230.00" and "397" arrive as text. Every value
        goes through num() before arithmetic.

     2. The views return one row per breakdown, not one row per entity,
        so a total is a sum across rows rather than a single field.

   These used to be copy-pasted into each chart. They live here now so a
   fix lands once.
   ===================================================================== */

export function toArray(payload) {
  if (Array.isArray(payload)) return payload;
  if (!payload || typeof payload !== 'object') return [];
  for (const key of ['data', 'rows', 'result', 'results', 'items']) {
    if (Array.isArray(payload[key])) return payload[key];
  }
  return [];
}

export function num(value) {
  if (value === null || value === undefined || value === '') return 0;
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

export function pick(row, ...keys) {
  if (!row) return undefined;
  for (const k of keys) {
    if (row[k] !== undefined && row[k] !== null) return row[k];
  }
  return undefined;
}

/** Sums valueFn over rows sharing a key, returned largest first. */
export function groupSum(rows, keyFn, labelFn, valueFn) {
  const map = new Map();
  for (const row of rows) {
    const key = keyFn(row);
    if (key === undefined || key === null) continue;
    const existing = map.get(key);
    if (existing) {
      existing.value += valueFn(row);
    } else {
      map.set(key, { key, label: labelFn(row), value: valueFn(row) });
    }
  }
  return Array.from(map.values()).sort((a, b) => b.value - a.value);
}

export function formatNumber(value, decimals = 0) {
  return num(value).toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

/* ------------------------------------------------------------------ */
/* Column readers. The views name things consistently, but the older
   asset endpoints use different spellings for the same idea, so each
   reader lists the alternatives it accepts. */

export const readAreaId = (r) => pick(r, 'area_id', 'areaId');
export const readAreaName = (r) =>
  pick(r, 'area_name', 'areaName', 'area_code') || 'Unknown';

/* CSC is the term used throughout. `depot_*` appears only as a fallback,
   because a few older views still spell the same column that way. */
export const readCscId = (r) => pick(r, 'csc_id', 'cscId', 'depot_id');
export const readCscName = (r) =>
  pick(r, 'csc_name', 'cscName', 'depot_name', 'csc_code') || 'Unknown';

/** Transformer units. v_transformer_* uses transformer_units; the
    per-CSC dashboard view calls the same figure transformer_count. */
export const readUnits = (r) =>
  num(pick(r, 'transformer_units', 'transformer_count', 'unit_count'));

export const readKva = (r) => num(pick(r, 'installed_kva', 'installedKva'));
