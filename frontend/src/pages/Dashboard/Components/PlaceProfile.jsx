import React, { useEffect, useMemo, useState } from 'react';

import axiosClient from '../../../api/axiosClient';
import { SERIES } from './palette';
import { toArray, num, pick, formatNumber, readUnits, readKva } from './data';
import { describePlace } from './PlaceFilter';

/*
 * One place, described -- instead of a table of rows.
 *
 * Shown in the register card whenever the dashboard is narrowed to a
 * province, an area or a CSC. It answers what someone who searched for
 * "Badulla" actually wants to know, in the order they want it:
 *
 *   1. the place's headline figures;
 *   2. the places inside it, as cards -- select one to open it, so the
 *      province opens into areas and an area into CSCs;
 *   3. its feeders, what it holds, and the segments added most recently.
 *
 * The figures come from the same rows as the tiles above (per-CSC, so a
 * profile always agrees with the tiles), and the feeder lengths come from
 * the CSC share view, so a feeder crossing into a neighbouring CSC is
 * credited here only with the kilometres inside this place.
 *
 * UNITS ARE NEVER MIXED. Counted assets and measured line are listed
 * apart; nothing adds poles to kilometres.
 */

const LEVEL_LABEL = { province: 'Province', area: 'Area', csc: 'CSC' };

const FEEDERS_SHOWN = 6;

const PlaceProfile = ({
  place,
  placeOptions,
  depotSummary,
  lineLengths,
  lineByCsc,
  assetCategories,
  dataVersion,
  onPickPlace,
}) => {
  const level = place?.cscId ? 'csc' : place?.areaId ? 'area' : place?.provinceId ? 'province' : null;

  const areaById = useMemo(
    () => new Map((placeOptions?.areas || []).map((a) => [String(a.area_id), a])),
    [placeOptions]
  );

  /* ---------------------------------------------------------- figures */

  const depotRows = useMemo(() => {
    const rows = toArray(depotSummary);
    if (level === 'csc') return rows.filter((r) => String(pick(r, 'csc_id')) === String(place.cscId));
    if (level === 'area') return rows.filter((r) => String(pick(r, 'area_id')) === String(place.areaId));
    if (level === 'province') {
      return rows.filter((r) => {
        const province =
          pick(r, 'province_id') ?? areaById.get(String(pick(r, 'area_id')))?.province_id;
        return String(province) === String(place.provinceId);
      });
    }
    return [];
  }, [depotSummary, level, place, areaById]);

  const kmRows = useMemo(() => {
    if (level === 'csc') {
      return toArray(lineByCsc).filter((r) => String(r.csc_id) === String(place.cscId));
    }
    if (level === 'area') {
      return toArray(lineLengths).filter((r) => String(r.area_id) === String(place.areaId));
    }
    if (level === 'province') {
      return toArray(lineLengths).filter(
        (r) => String(areaById.get(String(r.area_id))?.province_id) === String(place.provinceId)
      );
    }
    return [];
  }, [level, place, lineByCsc, lineLengths, areaById]);

  const totals = useMemo(
    () => ({
      transformers: depotRows.reduce((s, r) => s + readUnits(r), 0),
      kva: depotRows.reduce((s, r) => s + readKva(r), 0),
      km: kmRows.reduce((s, r) => s + num(r.total_km), 0),
      segments: kmRows.reduce((s, r) => s + num(r.segment_count), 0),
    }),
    [depotRows, kmRows]
  );

  /* ---------------------------------------------- the places inside it */

  const childRows = useMemo(() => {
    if (level === 'province') {
      return (placeOptions?.areas || [])
        .filter((a) => String(a.province_id) === String(place.provinceId))
        .map((a) => {
          const rows = depotRows.filter((r) => String(pick(r, 'area_id')) === String(a.area_id));
          const km = toArray(lineLengths).find((r) => String(r.area_id) === String(a.area_id));
          return {
            key: `area-${a.area_id}`,
            name: a.area_name,
            code: a.area_code,
            transformers: rows.reduce((s, r) => s + readUnits(r), 0),
            kva: rows.reduce((s, r) => s + readKva(r), 0),
            km: num(km?.total_km),
            segments: num(km?.segment_count),
            next: { provinceId: String(a.province_id), areaId: String(a.area_id), cscId: '' },
          };
        });
    }

    if (level === 'area') {
      return (placeOptions?.cscs || [])
        .filter((c) => String(c.area_id) === String(place.areaId))
        .map((c) => {
          const row = depotRows.find((r) => String(pick(r, 'csc_id')) === String(c.csc_id));
          const km = toArray(lineByCsc).find((r) => String(r.csc_id) === String(c.csc_id));
          return {
            key: `csc-${c.csc_id}`,
            name: c.csc_name,
            code: c.csc_code,
            transformers: row ? readUnits(row) : 0,
            kva: row ? readKva(row) : 0,
            km: num(km?.total_km),
            segments: num(km?.segment_count),
            next: { provinceId: place.provinceId, areaId: String(c.area_id), cscId: String(c.csc_id) },
          };
        });
    }

    return [];
  }, [level, place, placeOptions, depotRows, lineLengths, lineByCsc]);

  // Longest line first. A copy is sorted, never the memoised rows.
  const children = useMemo(
    () => [...childRows].sort((a, b) => b.km - a.km),
    [childRows]
  );

  /* ------------------------------------------------ feeders + segments */

  const [feeders, setFeeders] = useState(null);
  const [segments, setSegments] = useState(null);

  useEffect(() => {
    if (!level) return undefined;

    let cancelled = false;
    setFeeders(null);
    setSegments(null);

    const scope = {
      province_id: level === 'province' ? place.provinceId : undefined,
      area_id: level === 'area' ? place.areaId : undefined,
      csc_id: level === 'csc' ? place.cscId : undefined,
    };

    axiosClient
      .get('/network/hv-length', { params: { level: 'feeder', ...scope } })
      .then(({ data }) => {
        if (!cancelled) setFeeders(toArray(data?.rows));
      })
      .catch(() => {
        if (!cancelled) setFeeders([]);
      });

    // Newest first, so a segment entered a minute ago is at the top.
    axiosClient
      .get('/network/segments', {
        params: { limit: 6, area_id: scope.area_id, csc_id: scope.csc_id },
      })
      .then(({ data }) => {
        if (!cancelled) setSegments(toArray(data));
      })
      .catch(() => {
        if (!cancelled) setSegments([]);
      });

    return () => {
      cancelled = true;
    };
  }, [level, place.provinceId, place.areaId, place.cscId, dataVersion]);

  const namedFeeders = (feeders || []).filter((f) => f.group_code || f.group_name);
  const unassignedKm = (feeders || [])
    .filter((f) => !f.group_code && !f.group_name)
    .reduce((s, f) => s + num(f.total_km), 0);

  /* ------------------------------------------------------------ assets */

  const { counted, measured } = useMemo(() => {
    const c = [];
    const m = [];
    for (const cat of toArray(assetCategories)) {
      for (const u of cat.by_unit || []) {
        if (num(u.quantity) <= 0) continue;
        const row = { key: `${cat.category_id}-${u.unit_of_measure}`, name: cat.category_name, qty: num(u.quantity), unit: u.unit_of_measure };
        (u.unit_of_measure === 'nos' ? c : m).push(row);
      }
    }
    c.sort((a, b) => b.qty - a.qty);
    m.sort((a, b) => b.qty - a.qty);
    return { counted: c, measured: m };
  }, [assetCategories]);

  if (!level) return null;

  const title = describePlace(place, placeOptions);
  const countedTotal = counted.reduce((s, r) => s + r.qty, 0);
  const area = place.areaId ? areaById.get(String(place.areaId)) : null;

  return (
    <div className="pp">
      {/* ---------------------------------------------- headline strip */}
      <div className="pp-head">
        <div className="pp-title">
          <span className="pp-kicker">{LEVEL_LABEL[level]}</span>
          <h3>{title}</h3>

          {/* Up one level, without going back to the pickers. */}
          {level === 'csc' && area && (
            <button
              type="button"
              className="link-button pp-up"
              onClick={() => onPickPlace({ provinceId: place.provinceId, areaId: place.areaId, cscId: '' })}
            >
              &uarr; Whole {area.area_name} area
            </button>
          )}
          {level === 'area' && (
            <button
              type="button"
              className="link-button pp-up"
              onClick={() => onPickPlace({ provinceId: place.provinceId, areaId: '', cscId: '' })}
            >
              &uarr; Whole province
            </button>
          )}
        </div>

        <dl className="pp-figures">
          <div>
            <dt>Transformers</dt>
            <dd>{formatNumber(totals.transformers)}</dd>
          </div>
          <div>
            <dt>Installed kVA</dt>
            <dd>{formatNumber(totals.kva)}</dd>
          </div>
          <div>
            <dt>HV line</dt>
            <dd>
              {formatNumber(totals.km, 2)} <small>km</small>
            </dd>
          </div>
          <div>
            <dt>Segments</dt>
            <dd>{formatNumber(totals.segments)}</dd>
          </div>
          <div>
            <dt>Feeders</dt>
            <dd>{feeders === null ? '…' : formatNumber(namedFeeders.length)}</dd>
          </div>
          <div>
            <dt>Counted assets</dt>
            <dd>
              {formatNumber(countedTotal)} <small>nos</small>
            </dd>
          </div>
        </dl>
      </div>

      {/* ------------------------------------- the places inside it */}
      {children.length > 0 && (
        <section className="pp-section">
          <h4>
            {level === 'province' ? 'Areas' : 'CSCs'} in {title}
            <span className="pp-hint">select one to open it</span>
          </h4>

          <div className="pp-cards">
            {children.map((c, i) => {
              const share = totals.km > 0 ? (c.km / totals.km) * 100 : 0;
              return (
                <button
                  key={c.key}
                  type="button"
                  className="pp-card"
                  style={{ '--pp-accent': SERIES[i % SERIES.length] }}
                  onClick={() => onPickPlace(c.next)}
                  aria-label={`Open ${c.name}`}
                >
                  <span className="pp-card-name">
                    {c.name}
                    {c.code && <em>{c.code}</em>}
                  </span>
                  <span className="pp-card-figs">
                    <strong>{formatNumber(c.transformers)}</strong> transformers ·{' '}
                    {formatNumber(c.kva)} kVA
                  </span>
                  <span className="pp-card-km">
                    {formatNumber(c.km, 2)} km · {formatNumber(c.segments)} segments
                  </span>
                  <span className="pp-bar" aria-hidden="true">
                    <span style={{ width: `${Math.min(share, 100)}%` }} />
                  </span>
                  <span className="pp-card-share">{share.toFixed(1)}% of the line here</span>
                </button>
              );
            })}
          </div>
        </section>
      )}

      {/* ------------------------------ feeders, assets, recent segments */}
      <div className="pp-columns">
        <section className="pp-section">
          <h4>Feeders</h4>
          {feeders === null ? (
            <p className="pp-empty">Loading feeders…</p>
          ) : namedFeeders.length === 0 ? (
            <p className="pp-empty">No feeders recorded here.</p>
          ) : (
            <>
              <ul className="pp-list">
                {namedFeeders.slice(0, FEEDERS_SHOWN).map((f) => (
                  <li key={f.group_id ?? f.group_code}>
                    <span className="pp-strong">{f.group_code || f.group_name}</span>
                    <span className="pp-num">
                      {formatNumber(f.total_km, 2)} km · {formatNumber(f.segment_count)} seg
                    </span>
                  </li>
                ))}
              </ul>
              {(namedFeeders.length > FEEDERS_SHOWN || unassignedKm > 0) && (
                <p className="pp-more">
                  {namedFeeders.length > FEEDERS_SHOWN &&
                    `+${namedFeeders.length - FEEDERS_SHOWN} more feeders. `}
                  {unassignedKm > 0 && `${formatNumber(unassignedKm, 2)} km has no feeder recorded.`}
                </p>
              )}
            </>
          )}
        </section>

        <section className="pp-section">
          <h4>What it holds</h4>
          {counted.length === 0 && measured.length === 0 ? (
            <p className="pp-empty">No assets recorded here.</p>
          ) : (
            <ul className="pp-list">
              {counted.map((a) => (
                <li key={a.key}>
                  <span className="pp-strong">{a.name}</span>
                  <span className="pp-num">
                    {formatNumber(a.qty)} <small>nos</small>
                  </span>
                </li>
              ))}
              {measured.map((a) => (
                <li key={a.key} className="pp-measured">
                  <span className="pp-strong">{a.name}</span>
                  <span className="pp-num">
                    {formatNumber(a.qty, 2)} <small>{a.unit}</small>
                  </span>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="pp-section">
          <h4>Latest segments</h4>
          {segments === null ? (
            <p className="pp-empty">Loading segments…</p>
          ) : segments.length === 0 ? (
            <p className="pp-empty">No segments recorded here.</p>
          ) : (
            <ul className="pp-list">
              {segments.map((s) => (
                <li key={s.register_id}>
                  <span>
                    <span className="pp-strong">{s.segment_code}</span>
                    <span className="pp-sub">
                      {[s.csc_name, s.feeder_code].filter(Boolean).join(' · ')}
                    </span>
                  </span>
                  <span className="pp-num">{formatNumber(s.length_km, 3)} km</span>
                </li>
              ))}
            </ul>
          )}
        </section>
      </div>
    </div>
  );
};

export default PlaceProfile;
