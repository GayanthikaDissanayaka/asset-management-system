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
import { toArray, num, formatNumber } from './data';

/** Only categories counted in whole items belong on one bar axis. */
const COUNTED_UNIT = 'nos';

const AssetCategoryChart = ({ data }) => {
  const chartData = useMemo(
    () =>
      toArray(data)
        .map((category) => {
          const counted = (category.by_unit || []).find(
            (u) => u.unit_of_measure === COUNTED_UNIT
          );

          return {
            key: category.category_id,
            label: category.category_name,
            value: num(counted?.quantity),
          };
        })
        // A category with nothing counted in it is not a zero worth
        // drawing; it is a category measured in kilometres, or empty.
        .filter((row) => row.value > 0)
        .sort((a, b) => b.value - a.value),
    [data]
  );

  if (chartData.length === 0) {
    return <div className="chart-empty">No asset totals available.</div>;
  }

  return (
    <div className="chart-wrapper">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart
          data={chartData}
          layout="vertical"
          margin={{ top: 2, right: 52, left: 2, bottom: 2 }}
          barCategoryGap="22%"
        >
          <CartesianGrid stroke={INK.grid} horizontal={false} />
          <XAxis type="number" hide />
          <YAxis
            type="category"
            dataKey="label"
            width={104}
            tickLine={false}
            axisLine={false}
            /* Without interval={0} Recharts thins colliding category
               ticks, which on a short card silently leaves bars with no
               name against them. */
            interval={0}
            tick={{ fontSize: 10.5, fill: INK.secondary }}
          />
          <Tooltip
            cursor={{ fill: 'rgba(27, 175, 122, 0.08)' }}
            formatter={(value) => [`${formatNumber(value)} nos`, 'Held']}
            contentStyle={TOOLTIP_STYLE}
            labelStyle={TOOLTIP_LABEL_STYLE}
          />
          <Bar
            dataKey="value"
            fill={SERIES[2]}
            radius={[0, 4, 4, 0]}
            maxBarSize={14}
            isAnimationActive={false}
          >
            {/* Aqua measures below 3:1 on white, so every bar carries its
                value as text rather than relying on the fill being read. */}
            <LabelList
              dataKey="value"
              position="right"
              offset={7}
              formatter={(v) => formatNumber(v)}
              style={{ fontSize: 12, fontWeight: 600, fill: INK.secondary }}
            />
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};

export default AssetCategoryChart;
