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
const SummaryCards = ({ cscSummary, lineLengths, scopeLabel, onOpen }) => {
  const stats = useMemo(() => {
    const cscRows = toArray(cscSummary);
    const lengthRows = toArray(lineLengths);

    return {
      /*
       * HV line, from v_line_length_by_area — the working segment
       * register, 3,441 km across all seventeen CSCs.
       *
       * NOT v_depot_dashboard.network_km, which is the ASSET register's
       * line and is piloted in two CSCs. That is what this tile used to
       * read, so the front page announced 16.3 km while the HV Length
       * page in the same application said 3,441.31 km. Both numbers were
       * correct about different things, which is exactly what makes a
       * headline figure misleading: nobody reads a tile labelled
       * "Network" as "the part of the network in two CSCs".
       */
      hvLengthKm: lengthRows.reduce(
        (sum, r) => sum + num(pick(r, 'total_km', 'totalKm')),
        0
      ),
      hvSegments: lengthRows.reduce(
        (sum, r) => sum + num(pick(r, 'segment_count', 'segmentCount')),
        0
      ),

      /* Counted from the per-CSC rows, not the per-area ones, so the
         tiles can be narrowed to a single CSC as well as to an area.
         Both add up to the same 1,711 units and 312,230 kVA. */
      transformers: cscRows.reduce((sum, r) => sum + readUnits(r), 0),
      installedKva: cscRows.reduce((sum, r) => sum + readKva(r), 0),
      areaCount: new Set(cscRows.map((r) => pick(r, 'area_id', 'areaId'))).size,
      cscCount: cscRows.length,
      cscsWithTransformers: cscRows.filter((r) => readUnits(r) > 0).length,
    };
  }, [cscSummary, lineLengths]);

  const cards = [
    {
      kind: 'transformers',
      label: 'Transformers',
      value: formatNumber(stats.transformers),
      hint: `Recorded in ${stats.cscsWithTransformers} of ${stats.cscCount} CSCs`,
      accent: 'accent-1',
    },
    {
      kind: 'kva',
      label: 'Installed kVA',
      value: formatNumber(stats.installedKva),
      hint: 'Nameplate capacity across the fleet',
      accent: 'accent-2',
    },
    {
      kind: 'cscs',
      label: 'CSCs',
      value: formatNumber(stats.cscCount),
      hint: scopeLabel ? `In ${scopeLabel}` : 'Consumer service centres in the province',
      accent: 'accent-3',
    },
    {
      kind: 'areas',
      label: 'Areas',
      value: formatNumber(stats.areaCount),
      hint: scopeLabel ? `In ${scopeLabel}` : 'Operational areas in Uva Province',
      accent: 'accent-4',
    },
    {
      kind: 'hv',
      label: 'HV Line',
      value: `${formatNumber(stats.hvLengthKm, 2)} km`,
      hint: scopeLabel
        ? `Across ${formatNumber(stats.hvSegments)} segments in ${scopeLabel}`
        : `Across ${formatNumber(stats.hvSegments)} segments in all ${stats.cscCount} CSCs`,
      accent: 'accent-5',
    },
  ];

  return (
    <div className="summary-cards">
      {/* Each tile opens the breakdown it was added up from. */}
      {cards.map((card) =>
        onOpen ? (
          <button
            type="button"
            className={`summary-card is-clickable ${card.accent}`}
            key={card.label}
            onClick={() => onOpen(card.kind)}
            title={`${card.label}: see the breakdown`}
          >
            <span className="summary-label">
              {card.label}
              <span className="summary-more" aria-hidden="true">Details &rarr;</span>
            </span>
            <span className="summary-value">{card.value}</span>
            <span className="summary-hint">{card.hint}</span>
          </button>
        ) : (
          <div className={`summary-card ${card.accent}`} key={card.label}>
            <span className="summary-label">{card.label}</span>
            <span className="summary-value">{card.value}</span>
            <span className="summary-hint">{card.hint}</span>
          </div>
        )
      )}
    </div>
  );
};

export default SummaryCards;
