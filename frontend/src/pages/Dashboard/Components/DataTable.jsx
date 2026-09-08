import React, { useMemo, useState } from 'react';

import { num, formatNumber } from './data';

/**
 * A sortable table driven by a column config.
 *
 * The register card shows five different roll-ups. They differ only in
 * their columns, so they share this one component rather than each
 * carrying its own copy of the sorting, the sticky header and the totals
 * row.
 *
 * A column is:
 *   key      field on the row
 *   label    heading text
 *   numeric  right-aligned, tabular figures, sorts high-to-low first
 *   decimals fraction digits for numeric columns (default 0)
 *   total    'sum' to total the column in the footer, or omit
 *   render   optional cell renderer, (row) => node
 *   share    true to draw the proportion bar against the column total
 */
const DataTable = ({
  columns,
  rows,
  rowKey,
  initialSortKey,
  initialSortDir = 'desc',
  footerLabel,
  emptyMessage = 'Nothing recorded yet.',
  isRowMuted,
}) => {
  const [sortKey, setSortKey] = useState(
    initialSortKey || columns.find((c) => c.numeric)?.key || columns[0].key
  );
  const [sortDir, setSortDir] = useState(initialSortDir);

  const sorted = useMemo(() => {
    const list = [...(rows || [])];
    const dir = sortDir === 'asc' ? 1 : -1;
    list.sort((a, b) => {
      const av = a[sortKey];
      const bv = b[sortKey];
      if (typeof av === 'string' || typeof bv === 'string') {
        return String(av ?? '').localeCompare(String(bv ?? '')) * dir;
      }
      return (num(av) - num(bv)) * dir;
    });
    return list;
  }, [rows, sortKey, sortDir]);

  const totals = useMemo(() => {
    const acc = {};
    for (const c of columns) {
      if (c.total === 'sum') {
        acc[c.key] = sorted.reduce((s, r) => s + num(r[c.key]), 0);
      }
    }
    return acc;
  }, [sorted, columns]);

  const changeSort = (column) => {
    if (column.key === sortKey) {
      setSortDir(sortDir === 'asc' ? 'desc' : 'asc');
    } else {
      setSortKey(column.key);
      setSortDir(column.numeric ? 'desc' : 'asc');
    }
  };

  const arrow = (key) => {
    if (key !== sortKey) return '';
    return sortDir === 'asc' ? ' ▲' : ' ▼';
  };

  if (!rows || rows.length === 0) {
    return <div className="chart-empty">{emptyMessage}</div>;
  }

  const shareColumn = columns.find((c) => c.share);
  const shareTotal = shareColumn ? totals[shareColumn.key] : 0;

  return (
    <div className="depot-table-wrapper">
      <table className="depot-table">
        <thead>
          <tr>
            {columns.map((c) => (
              <th
                key={c.key}
                className={c.numeric ? 'numeric' : undefined}
                style={c.width ? { width: c.width } : undefined}
                onClick={() => changeSort(c)}
                aria-sort={
                  c.key === sortKey
                    ? sortDir === 'asc'
                      ? 'ascending'
                      : 'descending'
                    : 'none'
                }
              >
                {c.label}
                {arrow(c.key)}
              </th>
            ))}
            {shareColumn && <th className="numeric">Share</th>}
          </tr>
        </thead>

        <tbody>
          {sorted.map((row) => (
            <tr
              key={rowKey(row)}
              className={isRowMuted && isRowMuted(row) ? 'is-empty' : undefined}
            >
              {columns.map((c) => (
                <td key={c.key} className={c.numeric ? 'numeric' : undefined}>
                  {c.render
                    ? c.render(row)
                    : c.numeric
                    ? formatNumber(row[c.key], c.decimals ?? 0)
                    : row[c.key] || ''}
                </td>
              ))}

              {shareColumn && (
                <td className="numeric">
                  <div className="share-cell">
                    <div className="share-bar">
                      <div
                        className="share-fill"
                        style={{
                          width: `${
                            shareTotal > 0
                              ? Math.min(
                                  (num(row[shareColumn.key]) / shareTotal) * 100,
                                  100
                                )
                              : 0
                          }%`,
                        }}
                      />
                    </div>
                    <span>
                      {shareTotal > 0
                        ? ((num(row[shareColumn.key]) / shareTotal) * 100).toFixed(1)
                        : '0.0'}
                      %
                    </span>
                  </div>
                </td>
              )}
            </tr>
          ))}
        </tbody>

        <tfoot>
          <tr>
            {columns.map((c, i) => {
              if (i === 0) {
                return (
                  <td key={c.key}>
                    {footerLabel} ({sorted.length})
                  </td>
                );
              }
              if (c.total === 'sum') {
                return (
                  <td key={c.key} className="numeric strong">
                    {formatNumber(totals[c.key], c.decimals ?? 0)}
                  </td>
                );
              }
              return <td key={c.key} className={c.numeric ? 'numeric' : undefined} />;
            })}
            {shareColumn && <td className="numeric">100.0%</td>}
          </tr>
        </tfoot>
      </table>
    </div>
  );
};

export default DataTable;
