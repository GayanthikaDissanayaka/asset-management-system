import React, { useMemo } from 'react';
import {
  BarChart,
  Bar,
  Cell,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  LabelList,
  ResponsiveContainer,
} from 'recharts';

import { SERIES, INK, TOOLTIP_STYLE, TOOLTIP_LABEL_STYLE } from './palette';
import { formatNumber } from './data';

/**
 * Transformers per CSC inside one area, for when the dashboard is
 * filtered to a place.
 *
 * "Transformers by Area" draws one bar per area, so once the dashboard is
 * narrowed to Badulla it would draw a single bar -- a chart that says
 * nothing. This one steps down a level and shows the CSCs inside the
 * chosen area instead.
 *
 * When one CSC is chosen, the others in its area stay on the chart in a
 * muted tone and the chosen one keeps the full colour. Showing it alone
 * would lose the comparison that makes the number mean anything; showing
 * all at full strength would hide which one was asked about. Every bar
 * still carries its value as text, so the muted bars stay readable.
 */

const TOP_N = 8;
const MUTED = '#DCCBD2';

const TransformerPlaceChart = ({ rows, highlightKey, emptyMessage, onPick }) => {
  const chartData = useMemo(() => {
    const sorted = [...(rows || [])].sort((a, b) => b.value - a.value);
    if (sorted.length <= TOP_N) return sorted;

    const top = sorted.slice(0, TOP_N);
    const rest = sorted.slice(TOP_N);

    // Never fold the chosen CSC into "Other".
    const chosen = rest.find((r) => String(r.key) === String(highlightKey));
    const folded = rest.filter((r) => r !== chosen);
    if (chosen) top[TOP_N - 1] = chosen;

    top.push({
      key: '__other__',
      label: `Other (${folded.length})`,
      value: folded.reduce((s, r) => s + r.value, 0),
    });
    return top;
  }, [rows, highlightKey]);

  if (chartData.length === 0) {
    return <div className="chart-empty">{emptyMessage || 'Nothing recorded here.'}</div>;
  }

  const hasHighlight = highlightKey !== undefined && highlightKey !== null && highlightKey !== '';

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
            width={104}
            tickLine={false}
            axisLine={false}
            interval={0}
            tick={{ fontSize: 10.5, fill: INK.secondary }}
          />
          <Tooltip
            cursor={{ fill: 'rgba(163, 29, 82, 0.07)' }}
            formatter={(value) => [formatNumber(value), 'Transformers']}
            contentStyle={TOOLTIP_STYLE}
            labelStyle={TOOLTIP_LABEL_STYLE}
          />
          <Bar
            dataKey="value"
            radius={[0, 4, 4, 0]}
            maxBarSize={14}
            isAnimationActive={false}
            onClick={
              onPick
                ? (entry) => {
                    const key = entry?.payload?.key ?? entry?.key;
                    if (key !== '__other__') onPick(key);
                  }
                : undefined
            }
            style={onPick ? { cursor: 'pointer' } : undefined}
          >
            {chartData.map((d) => (
              <Cell
                key={d.key}
                fill={
                  !hasHighlight || String(d.key) === String(highlightKey)
                    ? SERIES[0]
                    : MUTED
                }
              />
            ))}
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

export default TransformerPlaceChart;
