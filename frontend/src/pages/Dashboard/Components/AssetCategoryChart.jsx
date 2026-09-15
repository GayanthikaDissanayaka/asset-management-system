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

/**
 * What the province holds, by kind of asset — from /network/assets/catalog,
 * which reads v_asset_register across all three registers.
 *
 * This card replaced "Transformers by CSC". That chart and "Transformers
 * by Area" were the same measure at two levels, so the dashboard showed
 * transformer counts twice and never showed the other 1,400-odd assets
 * at all. Area keeps the transformer view; this one answers the question
 * nothing on the page answered: what else is out there.
 *
 * UNITS ARE NOT MIXED. asset_types counts switchgear and poles in `nos`
 * and measures conductor and line in `km`. Only the counted categories
 * are charted, because a bar of 1,362 beside a bar of 32.5 would invite
 * a comparison between a number of switches and a length of wire. The
 * measured categories are named in the card's subtitle and broken down
 * properly on the Assets page.
 */

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
              style={{ fontSize: 11, fontWeight: 600, fill: INK.secondary }}
            />
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
};

export default AssetCategoryChart;
