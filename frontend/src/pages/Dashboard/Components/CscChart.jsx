import React, { useMemo } from 'react';
import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  LabelList,
  ResponsiveContainer,
} from 'recharts';

import { SERIES, INK, TOOLTIP_STYLE, TOOLTIP_LABEL_STYLE } from './palette';
import {
  toArray,
  groupSum,
  formatNumber,
  readCscId,
  readCscName,
  readUnits,
} from './data';

/**
 * Transformers by CSC, from v_transformer_totals_by_csc through
 * /dashboard/transformer-depot-totals.
 *
 * Horizontal so CSC names stay readable. Shows the top eight and folds
 * the rest into one bar, so the chart still reconciles with the province
 * figure. Every CSC is listed in the table below.
 *
 * One colour for every bar: CSCs are nominal, so there is no order for
 * a colour ramp to carry. The hue differs from the area chart only to
 * tell the two cards apart, not to encode anything.
 */
const TOP_N = 8;

const CscChart = ({ data }) => {
  const chartData = useMemo(() => {
    const grouped = groupSum(
      toArray(data),
      readCscId,
      readCscName,
      readUnits
    );

    if (grouped.length <= TOP_N) return grouped;

    // Recharts draws the first row at the TOP in a vertical-layout chart,
    // so the descending sort already reads largest-first and the folded
    // remainder appended last lands at the bottom, where it belongs.
    const top = grouped.slice(0, TOP_N);
    const rest = grouped.slice(TOP_N);
    top.push({
      key: '__other__',
      label: `Other (${rest.length})`,
      value: rest.reduce((sum, d) => sum + d.value, 0),
    });
    return top;
  }, [data]);

  if (chartData.length === 0) {
    return <div className="chart-empty">No CSC totals available.</div>;
  }

  return (
    <div className="chart-wrapper">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          data={chartData}
          layout="vertical"
          margin={{ top: 2, right: 46, left: 2, bottom: 2 }}
          barCategoryGap="22%"
        >
          <CartesianGrid stroke={INK.grid} horizontal={false} />
          <XAxis type="number" hide />
          <YAxis
            type="category"
            dataKey="label"
            width={92}
            tickLine={false}
            axisLine={false}
            /* Without interval={0} Recharts thins colliding category
               ticks, which on a short card silently leaves bars with no
               name against them. */
            interval={0}
            tick={{ fontSize: 10.5, fill: INK.secondary }}
          />
          <Tooltip
            cursor={{ fill: 'rgba(42, 120, 214, 0.07)' }}
            formatter={(value) => [formatNumber(value), 'Transformers']}
            contentStyle={TOOLTIP_STYLE}
            labelStyle={TOOLTIP_LABEL_STYLE}
          />
          <Bar
            dataKey="value"
            fill={SERIES[5]}
            radius={[0, 4, 4, 0]}
            maxBarSize={14}
            isAnimationActive={false}
          >
            <LabelList
              dataKey="value"
              position="right"
              offset={7}
              formatter={(v) => formatNumber(v)}
              style={{ fontSize: 11, fontWeight: 600, fill: INK.secondary }}
            />
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};

export default CscChart;

