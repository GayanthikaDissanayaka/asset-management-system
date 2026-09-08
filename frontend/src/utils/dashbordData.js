/**
 * Helpers shared by the dashboard components.
 *
 * Two facts about this backend drive everything here:
 *
 * 1. MySQL returns DECIMAL and SUM() results as STRINGS through most drivers.
 *    "446.530" is not a number, and Recharts renders nothing for it. Every
 *    value that reaches a chart goes through num() first.
 *
 * 2. The reporting views return ONE ROW PER CATEGORY PER DEPOT, not one row
 *    per depot. v_totals_by_csc has a row for Badulla/Conductor, another for
 *    Badulla/Pole, and so on. So the components aggregate before charting.
 */

/** Unwrap whatever shape the API returned into a plain array. */
export function toArray(payload) {
  if (Array.isArray(payload)) return payload;
  if (!payload || typeof payload !== 'object') return [];
  for (const key of ['data', 'rows', 'result', 'results', 'items']) {
    if (Array.isArray(payload[key])) return payload[key];
  }
  return [];
}

/** Coerce to a finite number. Handles null, undefined and numeric strings. */
export function num(value) {
  if (value === null || value === undefined || value === '') return 0;
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Read the first key that exists on the row.
 * Guards against the backend sending camelCase while the views use snake_case.
 */
export function pick(row, ...keys) {
  if (!row) return undefined;
  for (const k of keys) {
    if (row[k] !== undefined && row[k] !== null) return row[k];
  }
  return undefined;
}

/**
 * Group rows and sum a value per group.
 * Returns [{ key, label, value }] sorted by value descending.
 */
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

/** 12345.6 -> "12,346" */
export function formatNumber(value, decimals = 0) {
  return num(value).toLocaleString('en-US', {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

/** Shared palette so every chart colours the same category the same way. */
export const CHART_COLORS = [
  '#2E6DA4', '#41A08C', '#D08C34', '#8E6BB5', '#C25A5A',
  '#5C8F3E', '#3E8FA8', '#B5843C', '#7A6BAF', '#A85A7C',
  '#4F7EA8', '#5AA37E',
];

export function colorAt(index) {
  return CHART_COLORS[index % CHART_COLORS.length];
}