import React, { useMemo } from 'react';

import { toArray, num, pick, formatNumber, readUnits, readKva } from './data';

/**
 * The province headline figures.
 *
 * Sources, and why:
 *
 *   areaTotals   v_transformer_totals_by_area — one row per area, so the
 *                province total is the sum across those five rows.
 *   cscSummary   v_depot_dashboard — one row per CSC, all seventeen,
 *                including those with nothing recorded yet.
 *
 * Deliberately NOT sourced from the asset-register views. Those mix
 * units of measure inside a single total_quantity column: poles counted
 * in `nos` sit beside line lengths in `km`. Summing that column gives a
 * number with no meaning, which is what the previous "Total Assets" tile
 * was showing. Network length is reported here on its own, in km, and
 * nothing adds it to a count.
 */
const SummaryCards = ({ areaTotals, cscSummary }) => {
  const stats = useMemo(() => {
    const areaRows = toArray(areaTotals);
    const cscRows = toArray(cscSummary);

    return {
      transformers: areaRows.reduce((sum, r) => sum + readUnits(r), 0),
      installedKva: areaRows.reduce((sum, r) => sum + readKva(r), 0),
      areaCount: areaRows.length,
      cscCount: cscRows.length,
      cscsWithTransformers: cscRows.filter((r) => readUnits(r) > 0).length,
      networkKm: cscRows.reduce(
        (sum, r) => sum + num(pick(r, 'network_km', 'networkKm')),
        0
      ),
      cscsMapped: cscRows.filter(
        (r) => num(pick(r, 'network_km', 'networkKm')) > 0
      ).length,
    };
  }, [areaTotals, cscSummary]);

  const cards = [
    {
      label: 'Transformers',
      value: formatNumber(stats.transformers),
      hint: `Recorded in ${stats.cscsWithTransformers} of ${stats.cscCount} CSCs`,
      accent: 'accent-1',
    },
    {
      label: 'Installed kVA',
      value: formatNumber(stats.installedKva),
      hint: 'Nameplate capacity across the fleet',
      accent: 'accent-2',
    },
    {
      label: 'CSCs',
      value: formatNumber(stats.cscCount),
      hint: 'Consumer service centres in the province',
      accent: 'accent-3',
    },
    {
      label: 'Areas',
      value: formatNumber(stats.areaCount),
      hint: 'Operational areas in Uva Province',
      accent: 'accent-4',
    },
    {
      label: 'Network Mapped',
      value: `${formatNumber(stats.networkKm, 1)} km`,
      hint: `Asset register piloted in ${stats.cscsMapped} CSCs`,
      accent: 'accent-5',
    },
  ];

  return (
    <div className="summary-cards">
      {cards.map((card) => (
        <div className={`summary-card ${card.accent}`} key={card.label}>
          <span className="summary-label">{card.label}</span>
          <span className="summary-value">{card.value}</span>
          <span className="summary-hint">{card.hint}</span>
        </div>
      ))}
    </div>
  );
};

export default SummaryCards;
