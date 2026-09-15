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
  readAreaId,
  readAreaName,
  readUnits,
} from './data';

/* ---------------------------------------------------------------------
   NOTE ON THE NAME. This component is called AreaChart, and Recharts also
   exports a component called AreaChart. Importing that one here would
   collide with the declaration below and throw at module load. This file
   imports BarChart only.

   Reads v_transformer_totals_by_area through /dashboard/transformer-area-
   totals. Transformers rather than the general asset register, because
   that register currently covers one area and the transformer data covers
   all five.

   Horizontal bars, because area names are long enough that vertical
   columns would need angled tick labels, which do not survive being
   shrunk into a third of the dashboard width.

   Every bar is the SAME colour. Areas are nominal, so there is no order
   for a colour ramp to express, and tinting each bar by its own value
   would spend the identity channel restating the length the reader can
   already see.
   --------------------------------------------------------------------- */

const AreaChart = ({ data, onPick }) => {
  const chartData = useMemo(
    () =>
      // groupSum sorts descending, and in a vertical-layout chart Recharts
      // draws the first row at the TOP, so the largest area leads. Do not
      // reverse it.
      groupSum(toArray(data), readAreaId, readAreaName, readUnits),
    [data]
  );

  if (chartData.length === 0) {
    return <div className="chart-empty">No area totals available.</div>;
  }

  return (
    <div className="chart-wrapper">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          data={chartData}
          layout="vertical"
          margin={{ top: 2, right: 46, left: 2, bottom: 2 }}
          barCategoryGap="26%"
        >
          <CartesianGrid stroke={INK.grid} horizontal={false} />
          {/* The value axis is hidden: at this size the bar-end labels
              carry the numbers more legibly than a tick strip would. */}
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
            cursor={{ fill: 'rgba(163, 29, 82, 0.06)' }}
            formatter={(value) => [formatNumber(value), 'Transformers']}
            contentStyle={TOOLTIP_STYLE}
            labelStyle={TOOLTIP_LABEL_STYLE}
          />
          <Bar
            dataKey="value"
            fill={SERIES[0]}
            radius={[0, 4, 4, 0]}
            maxBarSize={16}
            isAnimationActive={false}
            /* Selecting an area's bar narrows the dashboard to it. */
            onClick={onPick ? (entry) => onPick(entry?.payload?.key ?? entry?.key) : undefined}
            style={onPick ? { cursor: 'pointer' } : undefined}
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

export default AreaChart;
