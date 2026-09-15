import React, { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';

import axiosClient from '../../../api/axiosClient';
import { SERIES } from './palette';
import { toArray, num, pick, formatNumber, readUnits, readKva } from './data';
import { placeParams } from './PlaceFilter';

/*
 * What is behind a headline tile.
 *
 * Each tile on the dashboard is one number. Clicking it opens the
 * breakdown that number was added up from, for the same place the
 * dashboard is showing:
 *
 *   Transformers   by type, and the units themselves with serial numbers
 *   Installed kVA  by capacity rating, and by CSC
 *   CSCs           every CSC in view with its figures
 *   Areas          every area in view with its figures
 *   HV line        by area, by CSC, or by feeder, one level below the place
 *
 * Every row that is a place can be selected, which narrows the whole
 * dashboard to it. Every row in a list adds up to the tile it came from,
 * because both are built from the same per-CSC rows.
 */

const TITLES = {
  transformers: 'Transformers',
  kva: 'Installed capacity',
  cscs: 'Consumer service centres',
  areas: 'Areas',
  hv: 'HV line',
};

const PAGE = 40;

/** A list of bars, each row optionally selectable. */
const BarList = ({ items, unit, decimals = 0, emptyText }) => {
  if (!items.length) return <p className="td-empty">{emptyText || 'Nothing recorded here.'}</p>;

  const total = items.reduce((s, i) => s + i.value, 0);

  return (
    <ul className="td-bars">
      {items.map((item, idx) => {
        const share = total > 0 ? (item.value / total) * 100 : 0;
        const body = (
          <>
            <span className="td-bar-name">
              {item.label}
              {item.sub && <em>{item.sub}</em>}
            </span>
            <span className="td-bar-value">
              {formatNumber(item.value, decimals)}
              {unit && <small> {unit}</small>}
            </span>
            <span className="td-bar-track" aria-hidden="true">
              <span
                style={{ width: `${Math.min(share, 100)}%`, background: SERIES[idx % SERIES.length] }}
              />
            </span>
            <span className="td-bar-share">
              {share.toFixed(1)}%{item.extra ? ` · ${item.extra}` : ''}
            </span>
          </>
        );

        return (
          <li key={item.key}>
            {item.onClick ? (
              <button type="button" className="td-bar is-clickable" onClick={item.onClick}>
                {body}
              </button>
            ) : (
              <div className="td-bar">{body}</div>
            )}
          </li>
        );
      })}
    </ul>
  );
};

const TileDetailDialog = ({
  kind,
  onClose,
  scopeLabel,
  place,
  placeOptions,
  depotRows,
  mixRows,
  lineLengths,
  lineByCsc,
  onPickPlace,
}) => {
  const navigate = useNavigate();

  useEffect(() => {
    if (!kind) return undefined;
    const onKey = (e) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [kind, onClose]);

  const areaById = useMemo(
    () => new Map((placeOptions?.areas || []).map((a) => [String(a.area_id), a])),
    [placeOptions]
  );

  const pickCsc = (row) => {
    onPickPlace({
      provinceId: String(pick(row, 'province_id') ?? areaById.get(String(pick(row, 'area_id')))?.province_id ?? ''),
      areaId: String(pick(row, 'area_id') ?? ''),
      cscId: String(pick(row, 'csc_id')),
    });
    onClose();
  };

  const pickArea = (areaId) => {
    onPickPlace({
      provinceId: String(areaById.get(String(areaId))?.province_id ?? ''),
      areaId: String(areaId),
      cscId: '',
    });
    onClose();
  };

  const kmByCsc = useMemo(
    () => new Map(toArray(lineByCsc).map((r) => [String(r.csc_id), r])),
    [lineByCsc]
  );

  /* ------------------------------------------------------ the lists */

  const byType = useMemo(() => {
    const m = new Map();
    for (const r of toArray(mixRows)) {
      const k = pick(r, 'transformer_type') || 'Unspecified';
      m.set(k, (m.get(k) || 0) + num(pick(r, 'unit_count', 'transformer_units')));
    }
    return Array.from(m, ([label, value]) => ({ key: label, label, value }))
      .filter((i) => i.value > 0)
      .sort((a, b) => b.value - a.value);
  }, [mixRows]);

  const byRating = useMemo(() => {
    const m = new Map();
    for (const r of toArray(mixRows)) {
      const rating = num(pick(r, 'capacity_kva'));
      const cur = m.get(rating) || { units: 0, kva: 0 };
      cur.units += num(pick(r, 'unit_count', 'transformer_units'));
      cur.kva += num(pick(r, 'installed_kva'));
      m.set(rating, cur);
    }
    return Array.from(m, ([rating, v]) => ({
      key: `r-${rating}`,
      label: rating > 0 ? `${formatNumber(rating)} kVA units` : 'Rating not recorded',
      value: v.kva,
      extra: `${formatNumber(v.units)} units`,
    }))
      .filter((i) => i.value > 0)
      .sort((a, b) => b.value - a.value);
  }, [mixRows]);

  const cscItems = (valueOf, extraOf) =>
    toArray(depotRows)
      .map((r) => ({
        key: `c-${pick(r, 'csc_id')}`,
        label: pick(r, 'csc_name') || 'Unknown',
        sub: pick(r, 'area_name'),
        value: valueOf(r),
        extra: extraOf ? extraOf(r) : undefined,
        onClick: () => pickCsc(r),
      }))
      .sort((a, b) => b.value - a.value);

  const areaItems = useMemo(() => {
    const m = new Map();
    for (const r of toArray(depotRows)) {
      const id = String(pick(r, 'area_id'));
      const cur = m.get(id) || { name: pick(r, 'area_name'), transformers: 0, kva: 0, cscs: 0 };
      cur.transformers += readUnits(r);
      cur.kva += readKva(r);
      cur.cscs += 1;
      m.set(id, cur);
    }
    return Array.from(m, ([id, v]) => {
      const km = toArray(lineLengths).find((l) => String(l.area_id) === id);
      return {
        key: `a-${id}`,
        label: v.name || 'Unknown',
        value: v.transformers,
        extra: `${formatNumber(v.cscs)} CSCs · ${formatNumber(v.kva)} kVA · ${formatNumber(num(km?.total_km), 2)} km`,
        onClick: () => pickArea(id),
      };
    }).sort((a, b) => b.value - a.value);
    // pickArea only closes over stable setters.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [depotRows, lineLengths]);

  /* HV line one level below the place in view. */
  const [feeders, setFeeders] = useState(null);

  useEffect(() => {
    if (kind !== 'hv' || !place?.cscId) return;
    setFeeders(null);
    axiosClient
      .get('/network/hv-length', { params: { level: 'feeder', csc_id: place.cscId } })
      .then(({ data }) => setFeeders(toArray(data?.rows)))
      .catch(() => setFeeders([]));
  }, [kind, place?.cscId]);

  const hvItems = useMemo(() => {
    if (place?.cscId) {
      return (feeders || [])
        .map((f) => ({
          key: `f-${f.group_id ?? 'none'}`,
          label: f.group_code || f.group_name || 'No feeder recorded',
          value: num(f.total_km),
          extra: `${formatNumber(f.segment_count)} segments`,
        }))
        .sort((a, b) => b.value - a.value);
    }

    if (place?.areaId) {
      return toArray(lineByCsc)
        .filter((r) => String(r.area_id) === String(place.areaId))
        .map((r) => ({
          key: `c-${r.csc_id}`,
          label: r.csc_name,
          value: num(r.total_km),
          extra: `${formatNumber(r.segment_count)} segments`,
          onClick: () => pickCsc(r),
        }))
        .sort((a, b) => b.value - a.value);
    }

    return toArray(lineLengths)
      .filter(
        (r) =>
          !place?.provinceId ||
          String(areaById.get(String(r.area_id))?.province_id) === String(place.provinceId)
      )
      .map((r) => ({
        key: `a-${r.area_id}`,
        label: r.area_name,
        value: num(r.total_km),
        extra: `${formatNumber(r.segment_count)} segments`,
        onClick: () => pickArea(r.area_id),
      }))
      .sort((a, b) => b.value - a.value);
    // pickCsc / pickArea only close over stable setters.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [place, feeders, lineByCsc, lineLengths, areaById]);

  /* The transformers themselves, with serial numbers. */
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [units, setUnits] = useState(null);

  useEffect(() => {
    setPage(1);
  }, [search, place?.provinceId, place?.areaId, place?.cscId]);

  useEffect(() => {
    if (kind !== 'transformers') return undefined;

    let cancelled = false;
    const timer = setTimeout(() => {
      axiosClient
        .get('/network/transformers', {
          params: {
            ...placeParams(place),
            search: search.trim() || undefined,
            page,
            limit: PAGE,
          },
        })
        .then(({ data }) => {
          if (!cancelled) setUnits(data);
        })
        .catch(() => {
          if (!cancelled) setUnits({ rows: [], total: 0, page: 1, last_page: 1 });
        });
    }, search ? 300 : 0);

    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [kind, place, search, page]);

  if (!kind) return null;

  const sum = (rows, fn) => toArray(rows).reduce((s, r) => s + fn(r), 0);

  return (
    <div className="dialog-backdrop" role="presentation" onClick={onClose}>
      <div
        className="dialog td-dialog"
        role="dialog"
        aria-modal="true"
        aria-label={TITLES[kind]}
        onClick={(e) => e.stopPropagation()}
      >
        <header className="dialog-head">
          <div>
            <h2>{TITLES[kind]}</h2>
            <p>{scopeLabel || 'The whole province'} · select a place to narrow the dashboard to it</p>
          </div>
          <button type="button" className="dialog-close" onClick={onClose} aria-label="Close">
            &times;
          </button>
        </header>

        <div className="dialog-body td-body">
          {kind === 'transformers' && (
            <>
              <section className="td-section">
                <h3>
                  By type <span>{formatNumber(sum(depotRows, readUnits))} units</span>
                </h3>
                <BarList items={byType} unit="units" />
              </section>

              <section className="td-section">
                <h3>
                  The transformers
                  <span>{units ? `${formatNumber(units.total)} found` : 'loading…'}</span>
                </h3>

                <input
                  type="search"
                  className="register-search td-search"
                  placeholder="Find by SIN, serial number, substation or manufacturer"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  aria-label="Find a transformer"
                />

                {units && units.rows.length === 0 ? (
                  <p className="td-empty">No transformers match.</p>
                ) : (
                  <ul className="td-units">
                    {(units?.rows || []).map((t) => (
                      <li key={t.transformer_id}>
                        <button
                          type="button"
                          className="td-unit"
                          onClick={() => navigate(`/assets?transformer=${t.transformer_id}`)}
                          title="Open this transformer in full"
                        >
                          <span className="td-unit-main">
                            <strong>{t.substation_name}</strong>
                            <em>{t.csc_name}</em>
                          </span>
                          <span className="td-unit-ids">
                            <span>SIN {t.new_sin_no || t.old_sin_no || '—'}</span>
                            <span>Serial {t.transformer_no || 'not recorded'}</span>
                          </span>
                          <span className="td-unit-meta">
                            {[
                              t.type_name,
                              t.capacity_kva ? `${formatNumber(t.capacity_kva)} kVA` : null,
                              t.manufacturer,
                            ]
                              .filter(Boolean)
                              .join(' · ')}
                          </span>
                        </button>
                      </li>
                    ))}
                  </ul>
                )}

                {units && units.last_page > 1 && (
                  <div className="td-pager">
                    <button
                      type="button"
                      className="dash-btn-quiet dash-btn-sm"
                      onClick={() => setPage((p) => Math.max(1, p - 1))}
                      disabled={units.page <= 1}
                    >
                      &larr; Previous
                    </button>
                    <span>
                      Page {units.page} of {units.last_page}
                    </span>
                    <button
                      type="button"
                      className="dash-btn-quiet dash-btn-sm"
                      onClick={() => setPage((p) => p + 1)}
                      disabled={units.page >= units.last_page}
                    >
                      Next &rarr;
                    </button>
                  </div>
                )}
              </section>
            </>
          )}

          {kind === 'kva' && (
            <div className="td-columns">
              <section className="td-section">
                <h3>
                  By rating <span>{formatNumber(sum(depotRows, readKva))} kVA installed</span>
                </h3>
                <BarList items={byRating} unit="kVA" />
              </section>
              <section className="td-section">
                <h3>By CSC</h3>
                <BarList
                  items={cscItems(readKva, (r) => `${formatNumber(readUnits(r))} units`)}
                  unit="kVA"
                />
              </section>
            </div>
          )}

          {kind === 'cscs' && (
            <section className="td-section">
              <h3>
                {formatNumber(toArray(depotRows).length)} CSCs <span>ranked by transformers</span>
              </h3>
              <BarList
                items={cscItems(readUnits, (r) => {
                  const km = kmByCsc.get(String(pick(r, 'csc_id')));
                  return `${formatNumber(readKva(r))} kVA · ${formatNumber(num(km?.total_km), 2)} km`;
                })}
                unit="units"
              />
            </section>
          )}

          {kind === 'areas' && (
            <section className="td-section">
              <h3>
                {formatNumber(areaItems.length)} areas <span>ranked by transformers</span>
              </h3>
              <BarList items={areaItems} unit="units" />
            </section>
          )}

          {kind === 'hv' && (
            <section className="td-section">
              <h3>
                {place?.cscId ? 'By feeder' : place?.areaId ? 'By CSC' : 'By area'}
                <span>{formatNumber(hvItems.reduce((s, i) => s + i.value, 0), 2)} km</span>
              </h3>
              {place?.cscId && feeders === null ? (
                <p className="td-empty">Loading feeders…</p>
              ) : (
                <BarList items={hvItems} unit="km" decimals={2} />
              )}
            </section>
          )}
        </div>

        <footer className="dialog-foot">
          <span />
          <div className="dialog-foot-right">
            <button type="button" className="dash-btn-primary" onClick={onClose}>
              Close
            </button>
          </div>
        </footer>
      </div>
    </div>
  );
};

export default TileDetailDialog;
