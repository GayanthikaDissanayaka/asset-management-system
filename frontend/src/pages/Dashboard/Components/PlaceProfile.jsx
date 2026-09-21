import React, { useEffect, useMemo, useState } from 'react';

import axiosClient from '../../../api/axiosClient';
import DataTable from './DataTable';
import { toArray, num, pick, formatNumber, readUnits, readKva } from './data';
import { describePlace } from './PlaceFilter';

/*
 * One place, described — one table at a time.
 *
 * Shown in the dashboard's single panel whenever a tab other than
 * Overview is chosen. Each tab is one answer about the place the
 * dashboard is narrowed to:
 *
 *   places     the areas or CSCs inside it — select a row to open it,
 *              so the province opens into areas and an area into CSCs
 *   feeders    HV line by feeder, longest first
 *   assets     what is held here: counted items beside measured line
 *   segments   the segments entered most recently, newest first
 *
 * Which tab is showing is the parent's business, not this component's:
 * the tabs sit in the panel's own toolbar alongside Overview, so there
 * is one row of tabs on the dashboard rather than two.
 *
 * Tables rather than cards, because every one of these is a ranking —
 * which CSC has the most line, which feeder is longest, what is held
 * here and how much. A card grid hides that ordering; a column you can
 * sort is the ranking.
 *
 * The figures come from the same rows as the tiles above (per-CSC, so
 * this always agrees with the tiles), and the feeder lengths come from
 * the CSC share view, so a feeder crossing into a neighbouring CSC is
 * credited here only with the kilometres inside this place.
 *
 * UNITS ARE NEVER MIXED. Counted assets and measured line get separate
 * tables; nothing adds poles to kilometres.
 */

const LEVEL_LABEL = { province: 'Province', area: 'Area', csc: 'CSC' };

/* Every tab is the same height, so switching between them does not move
   the page under the reader, and the panel stays a fixed size — which is
   what keeps the dashboard to one screen. */
const PANEL_HEIGHT = 250;

const nameCell = (name, sub) => (
  <>
    <span className="depot-name">{name}</span>
    {sub && <span className="depot-code">{sub}</span>}
  </>
);

const PlaceProfile = ({
  place,
  placeOptions,
  depotSummary,
  lineLengths,
  lineByCsc,
  assetCategories,
  dataVersion,
  onPickPlace,
  tab = 'places',
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

  /* ---------------------------------------------- the places inside it */

  const children = useMemo(() => {
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

  /* ------------------------------------------------ feeders + segments

     Only fetched for the tabs that show them. The dashboard used to ask
     for both on every place change whether or not anyone was looking at
     them. */

  const [feeders, setFeeders] = useState(null);
  const [segments, setSegments] = useState(null);

  const scope = useMemo(
    () => ({
      province_id: level === 'province' ? place.provinceId : undefined,
      area_id: level === 'area' ? place.areaId : undefined,
      csc_id: level === 'csc' ? place.cscId : undefined,
    }),
    [level, place.provinceId, place.areaId, place.cscId]
  );

  useEffect(() => {
    if (!level || tab !== 'feeders') return undefined;

    let cancelled = false;
    setFeeders(null);

    axiosClient
      .get('/network/hv-length', { params: { level: 'feeder', ...scope } })
      .then(({ data }) => {
        if (!cancelled) setFeeders(toArray(data?.rows));
      })
      .catch(() => {
        if (!cancelled) setFeeders([]);
      });

    return () => {
      cancelled = true;
    };
  }, [level, tab, scope, dataVersion]);

  useEffect(() => {
    if (!level || tab !== 'segments') return undefined;

    let cancelled = false;
    setSegments(null);

    // Newest first, so a segment entered a minute ago is at the top.
    axiosClient
      .get('/network/segments', {
        params: { limit: 12, area_id: scope.area_id, csc_id: scope.csc_id },
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
  }, [level, tab, scope, dataVersion]);

  const feederRows = useMemo(
    () =>
      (feeders || [])
        .filter((f) => f.group_code || f.group_name)
        .map((f) => ({
          key: `f-${f.group_id ?? 'none'}`,
          name: f.group_code || f.group_name,
          sub: f.group_name && f.group_name !== f.group_code ? f.group_name : '',
          km: num(f.total_km),
          segments: num(f.segment_count),
        })),
    [feeders]
  );

  const segmentRows = useMemo(
    () =>
      (segments || []).map((s) => ({
        key: `s-${s.segment_register_id}`,
        /* Sorted on the register id, not the code: "newest first" is the
           order things were entered in, and segment codes do not run in
           that order. The column is not shown — the id is plumbing.

           Kept as a STRING. These ids are now text codes like
           'SRG-00001', so num() would read every one of them as 0 and
           the sort would do nothing. They are zero-padded to a fixed
           width, which is what makes sorting them as text give the same
           order as sorting the numbers they used to be. */
        seq: String(s.segment_register_id ?? ''),
        code: s.segment_code || `#${s.segment_register_id}`,
        where: s.feeder_code || s.csc_name || '',
        km: num(s.length_km),
        voltage: s.voltage_level || '—',
      })),
    [segments]
  );

  /* ------------------------------------------------------------ assets */

  const { counted, measured } = useMemo(() => {
    const c = [];
    const m = [];
    for (const cat of toArray(assetCategories)) {
      for (const u of cat.by_unit || []) {
        if (num(u.quantity) <= 0) continue;
        const row = {
          key: `${cat.category_id}-${u.unit_of_measure}`,
          name: cat.category_name,
          qty: num(u.quantity),
          unit: u.unit_of_measure,
        };
        (u.unit_of_measure === 'nos' ? c : m).push(row);
      }
    }
    return { counted: c, measured: m };
  }, [assetCategories]);

  if (!level) return null;

  const title = describePlace(place, placeOptions);
  const area = place.areaId ? areaById.get(String(place.areaId)) : null;
  const unassignedKm = (feeders || [])
    .filter((f) => !f.group_code && !f.group_name)
    .reduce((s, f) => s + num(f.total_km), 0);

  const HINTS = {
    places: 'select a row to open it',
    feeders:
      unassignedKm > 0
        ? `${formatNumber(unassignedKm, 2)} km not on a feeder`
        : 'HV line by feeder, longest first',
    assets: 'counted items and measured line, never added together',
    segments: 'newest first',
  };

  return (
    <div className="pp">
      {/* One line, not a figures strip: the tiles above already carry
          this place's headline numbers, and printing them twice was half
          the height of this card. */}
      <div className="pp-bar">
        <span className="pp-kicker">{LEVEL_LABEL[level]}</span>
        <strong className="pp-name">{title}</strong>

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

        <span className="pp-hint">{HINTS[tab]}</span>
      </div>

      {tab === 'places' && (
        <DataTable
          columns={[
            {
              key: 'name',
              label: level === 'province' ? 'Area' : 'CSC',
              render: (r) => nameCell(r.name, r.code),
            },
            { key: 'transformers', label: 'Transformers', numeric: true, total: 'sum' },
            { key: 'kva', label: 'Installed kVA', numeric: true, total: 'sum' },
            { key: 'km', label: 'HV km', numeric: true, decimals: 2, total: 'sum', share: true },
            { key: 'segments', label: 'Segments', numeric: true, total: 'sum' },
          ]}
          rows={children}
          rowKey={(r) => r.key}
          initialSortKey="km"
          footerLabel={level === 'province' ? 'All areas' : 'All CSCs'}
          emptyMessage="Nothing inside this place yet."
          onRowClick={(r) => onPickPlace(r.next)}
          rowTitle={(r) => `Open ${r.name}`}
          isRowMuted={(r) => r.km === 0 && r.transformers === 0}
          maxHeight={PANEL_HEIGHT}
        />
      )}

      {tab === 'feeders' &&
        (feeders === null ? (
          <div className="chart-empty">Loading feeders…</div>
        ) : (
          <DataTable
            columns={[
              { key: 'name', label: 'Feeder', render: (r) => nameCell(r.name, r.sub) },
              { key: 'km', label: 'HV km', numeric: true, decimals: 2, total: 'sum', share: true },
              { key: 'segments', label: 'Segments', numeric: true, total: 'sum' },
            ]}
            rows={feederRows}
            rowKey={(r) => r.key}
            initialSortKey="km"
            footerLabel="All feeders"
            emptyMessage="No feeders recorded here."
            dense
            maxHeight={PANEL_HEIGHT}
          />
        ))}

      {tab === 'assets' && (
        <div className="pp-two-up">
          <DataTable
            columns={[
              { key: 'name', label: 'Counted' },
              { key: 'qty', label: 'nos', numeric: true, total: 'sum', share: true },
            ]}
            rows={counted}
            rowKey={(r) => r.key}
            initialSortKey="qty"
            footerLabel="Counted"
            emptyMessage="Nothing counted here yet."
            dense
            maxHeight={PANEL_HEIGHT}
          />

          <DataTable
            columns={[
              { key: 'name', label: 'Measured' },
              { key: 'qty', label: 'km', numeric: true, decimals: 3, total: 'sum', share: true },
            ]}
            rows={measured}
            rowKey={(r) => r.key}
            initialSortKey="qty"
            footerLabel="Measured"
            emptyMessage="No line recorded against an asset here."
            dense
            maxHeight={PANEL_HEIGHT}
          />
        </div>
      )}

      {tab === 'segments' &&
        (segments === null ? (
          <div className="chart-empty">Loading segments…</div>
        ) : (
          <DataTable
            columns={[
              { key: 'code', label: 'Segment', render: (r) => nameCell(r.code, r.where) },
              { key: 'voltage', label: 'Voltage' },
              { key: 'km', label: 'km', numeric: true, decimals: 3, total: 'sum' },
            ]}
            rows={segmentRows}
            rowKey={(r) => r.key}
            initialSortKey="seq"
            initialSortDir="desc"
            footerLabel="Latest"
            emptyMessage="No segments recorded here."
            dense
            maxHeight={PANEL_HEIGHT}
          />
        ))}
    </div>
  );
};

export default PlaceProfile;
