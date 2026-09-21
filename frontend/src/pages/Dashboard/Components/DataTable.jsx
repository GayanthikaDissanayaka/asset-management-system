import React, { useMemo, useState } from 'react';

import { num, formatNumber } from './data';

/*
 * The one table every screen uses.
 *
 * Sorting, a totals row and a share bar were already here. Three things
 * were added so that a table can be the drill-down rather than only the
 * summary, which is what the rest of the application now relies on:
 *
 *   onRowClick   the row becomes a button — Enter and Space work too, so
 *                opening a place from a table is not a mouse-only move.
 *   expandRender the row opens in place and shows whatever the caller
 *                draws inside it, normally a second table. Categories
 *                open into their types this way.
 *   maxHeight    long tables scroll under their own sticky header
 *                instead of pushing the page down.
 *
 * Numbers stay right-aligned and tabular so columns of figures line up
 * on the decimal point; that is most of what makes a dense table
 * readable at a glance.
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
  isRowActive,
  onRowClick,
  rowTitle,
  expandRender,
  dense = false,
  maxHeight,
  showFooter = true,
}) => {
  const [sortKey, setSortKey] = useState(
    initialSortKey || columns.find((c) => c.numeric)?.key || columns[0].key
  );
  const [sortDir, setSortDir] = useState(initialSortDir);
  const [openKeys, setOpenKeys] = useState(() => new Set());

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

  const toggleOpen = (key) =>
    setOpenKeys((prev) => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });

  if (!rows || rows.length === 0) {
    return <div className="chart-empty">{emptyMessage}</div>;
  }

  const shareColumn = columns.find((c) => c.share);
  const shareTotal = shareColumn ? totals[shareColumn.key] : 0;
  const span = columns.length + (expandRender ? 1 : 0) + (shareColumn ? 1 : 0);

  return (
    <div
      className={`depot-table-wrapper${maxHeight ? ' is-scrolled' : ''}`}
      style={maxHeight ? { maxHeight } : undefined}
    >
      <table className={`depot-table${dense ? ' is-dense' : ''}`}>
        <thead>
          <tr>
            {expandRender && <th className="dt-expand-head" aria-label="Open" />}

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
          {sorted.map((row) => {
            const key = rowKey(row);
            const open = openKeys.has(key);
            const clickable = Boolean(onRowClick);

            const classes = [
              isRowMuted && isRowMuted(row) ? 'is-empty' : '',
              isRowActive && isRowActive(row) ? 'is-active' : '',
              clickable ? 'is-clickable' : '',
              open ? 'is-open' : '',
            ]
              .filter(Boolean)
              .join(' ');

            return (
              <React.Fragment key={key}>
                <tr
                  className={classes || undefined}
                  title={rowTitle ? rowTitle(row) : undefined}
                  onClick={clickable ? () => onRowClick(row) : undefined}
                  role={clickable ? 'button' : undefined}
                  tabIndex={clickable ? 0 : undefined}
                  onKeyDown={
                    clickable
                      ? (e) => {
                          if (e.key === 'Enter' || e.key === ' ') {
                            e.preventDefault();
                            onRowClick(row);
                          }
                        }
                      : undefined
                  }
                >
                  {expandRender && (
                    <td className="dt-expand-cell">
                      <button
                        type="button"
                        className="dt-expander"
                        aria-expanded={open}
                        aria-label={open ? 'Close' : 'Open'}
                        onClick={(e) => {
                          e.stopPropagation();
                          toggleOpen(key);
                        }}
                      >
                        {open ? '−' : '+'}
                      </button>
                    </td>
                  )}

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

                {expandRender && open && (
                  <tr className="dt-sub-row">
                    <td colSpan={span} className="dt-sub-cell">
                      <div className="dt-sub">{expandRender(row)}</div>
                    </td>
                  </tr>
                )}
              </React.Fragment>
            );
          })}
        </tbody>

        {showFooter && (
        <tfoot>
          <tr>
            {expandRender && <td className="dt-expand-cell" />}

            {columns.map((c, i) => {
              if (i === 0) {
                return (
                  <td key={c.key}>
                    {footerLabel ? `${footerLabel} (${sorted.length})` : `${sorted.length} rows`}
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
        )}
      </table>
    </div>
  );
};

export default DataTable;
