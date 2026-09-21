import React, { useMemo } from 'react';

import DataTable from '../Dashboard/Components/DataTable';
import { num, formatNumber } from '../Dashboard/Components/data';

/*
 * The main assets, and what is inside each one — as a table.
 *
 * A row is a category: Transformer, Switchgear, Conductor, Pole. Opening
 * it reveals the types it contains, which is the drill-down:
 * "Transformer" opens into Distribution, Bulk, Bulk & Distribution and
 * Mini Hydro, each with its own count. Selecting a type filters the whole
 * page to it, and selecting it again clears the filter, so there is
 * always a way back without hunting for a reset button.
 *
 * This replaced a grid of cards. The figures here are comparisons —
 * which category holds the most, which types have nothing recorded — and
 * a column you can sort answers that in one click, where a card grid
 * makes you read every card and hold the numbers in your head.
 *
 * QUANTITIES ARE PER UNIT, ALWAYS. A category can hold more than one
 * unit of measure, so counted items and measured line get their own
 * columns rather than one total that would add poles to kilometres.
 */

const decimalsFor = (unit) => (unit === 'km' ? 3 : 0);

const unitQuantity = (category, unit) =>
  num((category.by_unit || []).find((u) => u.unit_of_measure === unit)?.quantity);

const CATEGORY_COLUMNS = [
  {
    key: 'category_name',
    label: 'Main asset',
    render: (r) => (
      <>
        <span className="depot-name">{r.category_name}</span>
        <span className="depot-code">
          {r.type_count} {num(r.type_count) === 1 ? 'type' : 'types'} inside
        </span>
      </>
    ),
  },
  { key: 'counted_qty', label: 'Counted nos', numeric: true, total: 'sum' },
  { key: 'line_km', label: 'Line km', numeric: true, decimals: 3, total: 'sum' },
  { key: 'records', label: 'Records', numeric: true, total: 'sum', share: true },
  { key: 'csc_count', label: 'CSCs', numeric: true },
  { key: 'area_count', label: 'Areas', numeric: true },
];

const CategoryTable = ({ categories, typeFilter, onPickType }) => {
  const rows = useMemo(
    () =>
      (categories || []).map((cat) => ({
        ...cat,
        counted_qty: unitQuantity(cat, 'nos'),
        line_km: unitQuantity(cat, 'km'),
      })),
    [categories]
  );

  if (!categories || categories.length === 0) {
    return <div className="chart-empty">Nothing matches these filters.</div>;
  }

  return (
    <DataTable
      columns={CATEGORY_COLUMNS}
      rows={rows}
      rowKey={(r) => `cat-${r.category_id}`}
      initialSortKey="records"
      footerLabel="All main assets"
      emptyMessage="Nothing matches these filters."
      isRowMuted={(r) => num(r.records) === 0}
      expandRender={(cat) => (
        <DataTable
          columns={[
            {
              key: 'type_name',
              label: 'Asset type',
              render: (t) => (
                <>
                  <span className="depot-name">{t.type_name}</span>
                  <span className="depot-code">{t.type_code}</span>
                </>
              ),
            },
            {
              key: 'quantity',
              label: 'Quantity held',
              numeric: true,
              render: (t) => (
                <>
                  {formatNumber(t.quantity, decimalsFor(t.unit_of_measure))}{' '}
                  <em className="ax-unit">{t.unit_of_measure}</em>
                </>
              ),
            },
            { key: 'records', label: 'Records', numeric: true, total: 'sum' },
            { key: 'csc_count', label: 'CSCs', numeric: true },
            { key: 'area_count', label: 'Areas', numeric: true },
          ]}
          rows={cat.types || []}
          rowKey={(t) => `type-${t.asset_type_id}`}
          initialSortKey="quantity"
          footerLabel={`Types in ${cat.category_name}`}
          emptyMessage="No types defined for this main asset."
          dense
          isRowMuted={(t) => num(t.records) === 0}
          isRowActive={(t) => String(typeFilter) === String(t.asset_type_id)}
          onRowClick={(t) =>
            onPickType(
              String(typeFilter) === String(t.asset_type_id) ? '' : String(t.asset_type_id)
            )
          }
          rowTitle={(t) =>
            String(typeFilter) === String(t.asset_type_id)
              ? 'Showing only this type. Select again to clear.'
              : `Show only ${t.type_name}`
          }
        />
      )}
    />
  );
};

export default CategoryTable;
