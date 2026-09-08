import React, { useMemo } from 'react';
import { PieChart, Pie, Cell, Tooltip, ResponsiveContainer } from 'recharts';

import {
  SERIES,
  SLICE_CAP,
  INK,
  TOOLTIP_STYLE,
  TOOLTIP_LABEL_STYLE,
} from './palette';
import { toArray, pick, num, groupSum, formatNumber } from './data';

/**
 * The transformer fleet split by type, from v_transformer_capacity_mix
 * through /dashboard/transformer-capacity-mix.
 *
 * That view returns one row per capacity rating per type per depot, so
 * the 192 rows collapse here into a handful of types. Grouping on type
 * rather than capacity is deliberate: there are 26 distinct ratings, and
 * ratings are an ordered scale, which would need a single-hue ramp
 * rather than the categorical palette this chart draws with.
 *
 * The tail folds into "Other" past the slice cap, rather than reusing a
 * colour. A generated extra hue collapses onto an existing one under
 * colour blindness, and a ring stops being readable past six segments.
 *
 * The legend prints each share as text. That matters because two of the
 * palette slots sit below 3:1 against white, so the numbers must be
 * readable without relying on the colour.
 */
const TransformerMixChart = ({ data }) => {
  const { slices, total, foldedCount } = useMemo(() => {
    const grouped = groupSum(
      toArray(data),
      (r) => pick(r, 'transformer_type', 'transformerType') || 'Unspecified',
      (r) => pick(r, 'transformer_type', 'transformerType') || 'Unspecified',
      (r) => num(pick(r, 'unit_count', 'unitCount', 'transformer_units'))
    ).filter((d) => d.value > 0);

    const sum = grouped.reduce((acc, d) => acc + d.value, 0);

    if (grouped.length <= SLICE_CAP) {
      return { slices: grouped, total: sum, foldedCount: 0 };
    }

    const head = grouped.slice(0, SLICE_CAP - 1);
    const tail = grouped.slice(SLICE_CAP - 1);
    head.push({
      key: '__other__',
      label: 'Other',
      value: tail.reduce((acc, d) => acc + d.value, 0),
    });
    return { slices: head, total: sum, foldedCount: tail.length };
  }, [data]);

  if (slices.length === 0) {
    return <div className="chart-empty">No transformer mix available.</div>;
  }

  const share = (value) => (total > 0 ? (num(value) / total) * 100 : 0);

  return (
    <div className="donut-block">
      <div className="donut-plot">
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={slices}
              dataKey="value"
              nameKey="label"
              cx="50%"
              cy="50%"
              innerRadius="58%"
              outerRadius="92%"
              paddingAngle={2}
              stroke={INK.surface}
              strokeWidth={1}
              isAnimationActive={false}
            >
              {slices.map((entry, index) => (
                <Cell key={entry.key} fill={SERIES[index % SERIES.length]} />
              ))}
            </Pie>
            <Tooltip
              formatter={(value, name) => [
                `${formatNumber(value)} units  (${share(value).toFixed(1)}%)`,
                name,
              ]}
              contentStyle={TOOLTIP_STYLE}
              labelStyle={TOOLTIP_LABEL_STYLE}
            />
          </PieChart>
        </ResponsiveContainer>
      </div>

      <ul className="donut-legend">
        {slices.map((entry, index) => (
          <li key={entry.key}>
            <span
              className="donut-swatch"
              style={{ background: SERIES[index % SERIES.length] }}
            />
            <span className="donut-name" title={entry.label}>
              {entry.key === '__other__' && foldedCount > 0
                ? `Other (${foldedCount})`
                : entry.label}
            </span>
            <span className="donut-share">{share(entry.value).toFixed(1)}%</span>
          </li>
        ))}
      </ul>
    </div>
  );
};

export default TransformerMixChart;
