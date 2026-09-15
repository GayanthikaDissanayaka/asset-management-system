import React from 'react';

import { num, formatNumber } from '../Dashboard/Components/data';
import { SERIES } from '../Dashboard/Components/palette';

/*
 * The main assets, and what is inside each one.
 *
 * A card is a category — Transformer, Switchgear, Conductor, Pole.
 * Opening it reveals the types it contains, which is the drill-down:
 * "Transformer" opens into Distribution, Bulk, Bulk & Distribution and
 * Mini Hydro, each with its own count.
 *
 * QUANTITIES ARE PER UNIT, ALWAYS. A category can hold more than one
 * unit of measure, and a card showing a single number would be adding
 * kilometres of line to counts of poles. Each unit gets its own figure
 * with its own label, side by side.
 *
 * The colour is positional, taken from the validated palette in the
 * order categories are displayed, and it is decoration: every value is
 * written out as text beside it, so the card does not depend on anyone
 * telling the colours apart.
 */

const decimalsFor = (unit) => (unit === 'km' ? 3 : 0);

const CategoryCards = ({ categories, openId, onToggle, typeFilter, onPickType }) => {
  if (!categories || categories.length === 0) {
    return <div className="chart-empty">Nothing matches these filters.</div>;
  }

  return (
    <div className="ax-cards">
      {categories.map((cat, index) => {
        const colour = SERIES[index % SERIES.length];
        const isOpen = openId === cat.category_id;
        const empty = num(cat.records) === 0;

        return (
          <article
            key={cat.category_id}
            className={`ax-card${isOpen ? ' is-open' : ''}${empty ? ' is-empty' : ''}`}
            style={{ '--ax-accent': colour }}
          >
            <button
              type="button"
              className="ax-card-head"
              aria-expanded={isOpen}
              onClick={() => onToggle(isOpen ? null : cat.category_id)}
            >
              <span className="ax-card-title">
                <span className="ax-card-dot" aria-hidden="true" />
                {cat.category_name}
              </span>

              <span className="ax-card-values">
                {cat.by_unit.map((u) => (
                  <span key={u.unit_of_measure} className="ax-card-value">
                    {formatNumber(u.quantity, decimalsFor(u.unit_of_measure))}
                    <em>{u.unit_of_measure}</em>
                  </span>
                ))}
              </span>

              <span className="ax-card-meta">
                {formatNumber(cat.records)}{' '}
                {num(cat.records) === 1 ? 'record' : 'records'}
                {' · '}
                {cat.type_count} {cat.type_count === 1 ? 'type' : 'types'}
                {num(cat.csc_count) > 0 && ` · ${cat.csc_count} CSCs`}
              </span>

              <span className="ax-card-chevron" aria-hidden="true">
                {isOpen ? '−' : '+'}
              </span>
            </button>

            {isOpen && (
              <ul className="ax-types">
                {cat.types.map((t) => {
                  const selected = String(typeFilter) === String(t.asset_type_id);

                  return (
                    <li key={t.asset_type_id}>
                      <button
                        type="button"
                        className={`ax-type${selected ? ' is-selected' : ''}${
                          num(t.quantity) === 0 ? ' is-zero' : ''
                        }`}
                        /* Selecting a type filters the whole page to it,
                           and selecting it again clears the filter, so
                           there is always a way back without hunting for
                           a reset button. */
                        onClick={() =>
                          onPickType(selected ? '' : String(t.asset_type_id))
                        }
                        title={
                          selected
                            ? 'Showing only this type. Select again to clear.'
                            : `Show only ${t.type_name}`
                        }
                      >
                        <span className="ax-type-name">{t.type_name}</span>

                        <span className="ax-type-value">
                          {formatNumber(t.quantity, decimalsFor(t.unit_of_measure))}
                          <em>{t.unit_of_measure}</em>
                        </span>

                        <span className="ax-type-meta">
                          {num(t.records) === 0
                            ? 'none recorded'
                            : `${formatNumber(t.records)} in ${t.csc_count} ${
                                num(t.csc_count) === 1 ? 'CSC' : 'CSCs'
                              }`}
                        </span>
                      </button>
                    </li>
                  );
                })}
              </ul>
            )}
          </article>
        );
      })}
    </div>
  );
};

export default CategoryCards;
