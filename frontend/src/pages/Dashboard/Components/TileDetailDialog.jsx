import React, { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';

import axiosClient from '../../../api/axiosClient';
import DataTable from './DataTable';
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
 * All of it is tables. A tile is the simple answer; this is the working
 * detail, so it is sortable, totalled and column-aligned — someone
 * checking a figure needs to rank, compare and add up, which a list of
 * bars cannot do.
 *
 * Every row that is a place can be selected, which narrows the whole
 * dashboard to it. Every row adds up to the tile it came from, because
 * both are built from the same per-CSC rows.
 */

const TITLES = {
  transformers: 'Transformers',
  kva: 'Installed capacity',
  cscs: 'Consumer service centres',
  areas: 'Areas',
  hv: 'HV line',
};

const PAGE = 40;

/** Name over code, the two-line cell used across every table. */
const nameCell = (name, sub) => (
  <>
    <span className="depot-name">{name}</span>
    {sub && <span className="depot-code">{sub}</span>}
  </>
);

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

  const openCsc = (row) => {
    onPickPlace({
      provinceId: String(row.province_id ?? areaById.get(String(row.area_id))?.province_id ?? ''),
      areaId: String(row.area_id ?? ''),
      cscId: String(row.csc_id),
    });
    onClose();
  };

  const openArea = (row) => {
    onPickPlace({
      provinceId: String(areaById.get(String(row.area_id))?.province_id ?? ''),
      areaId: String(row.area_id),
      cscId: '',
    });
    onClose();
  };

  const kmByCsc = useMemo(
    () => new Map(toArray(lineByCsc).map((r) => [String(r.csc_id), r])),
    [lineByCsc]
  );

  /* ----------------------------------------------------- the tables */

  const byType = useMemo(() => {
    const m = new Map();
    for (const r of toArray(mixRows)) {
      const k = pick(r, 'transformer_type') || 'Unspecified';
      m.set(k, (m.get(k) || 0) + num(pick(r, 'unit_count', 'transformer_units')));
    }
    return Array.from(m, ([type_name, units]) => ({ key: type_name, type_name, units }))
      .filter((i) => i.units > 0);
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
      rating,
      rating_label: rating > 0 ? `${formatNumber(rating)} kVA` : 'Not recorded',
      units: v.units,
      kva: v.kva,
    })).filter((i) => i.kva > 0);
  }, [mixRows]);

  /* One row per CSC, carrying everything any of the tables needs, so
     each table picks columns out of the same set of rows rather than
     rebuilding them. */
  const cscRows = useMemo(
    () =>
      toArray(depotRows).map((r) => {
        const cscId = pick(r, 'csc_id');
        const km = kmByCsc.get(String(cscId));
        return {
          key: `c-${cscId}`,
          csc_id: cscId,
          area_id: pick(r, 'area_id'),
          province_id: pick(r, 'province_id'),
          csc_name: pick(r, 'csc_name') || 'Unknown',
          area_name: pick(r, 'area_name') || '',
          transformers: readUnits(r),
          kva: readKva(r),
          km: num(km?.total_km),
          segments: num(km?.segment_count),
        };
      }),
    [depotRows, kmByCsc]
  );

  const areaRows = useMemo(() => {
    const m = new Map();
    for (const r of cscRows) {
      const id = String(r.area_id);
      const cur = m.get(id) || { area_name: r.area_name, transformers: 0, kva: 0, cscs: 0 };
      cur.transformers += r.transformers;
      cur.kva += r.kva;
      cur.cscs += 1;
      m.set(id, cur);
    }
    return Array.from(m, ([id, v]) => {
      const km = toArray(lineLengths).find((l) => String(l.area_id) === id);
      return {
        key: `a-${id}`,
        area_id: id,
        area_name: v.area_name || 'Unknown',
        cscs: v.cscs,
        transformers: v.transformers,
        kva: v.kva,
        km: num(km?.total_km),
        segments: num(km?.segment_count),
      };
    });
  }, [cscRows, lineLengths]);

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

  const hvLevel = place?.cscId ? 'feeder' : place?.areaId ? 'csc' : 'area';

  const hvRows = useMemo(() => {
    if (hvLevel === 'feeder') {
      return (feeders || []).map((f) => ({
        key: `f-${f.group_id ?? 'none'}`,
        name: f.group_code || f.group_name || 'No feeder recorded',
        sub: f.group_code && f.group_name !== f.group_code ? f.group_name : '',
        km: num(f.total_km),
        segments: num(f.segment_count),
        mean_km: num(f.mean_km),
      }));
    }

    if (hvLevel === 'csc') {
      return toArray(lineByCsc)
        .filter((r) => String(r.area_id) === String(place.areaId))
        .map((r) => ({
          key: `c-${r.csc_id}`,
          name: r.csc_name,
          sub: '',
          km: num(r.total_km),
          segments: num(r.segment_count),
          mean_km: num(r.segment_count) > 0 ? num(r.total_km) / num(r.segment_count) : 0,
          csc_id: r.csc_id,
          area_id: r.area_id,
        }));
    }

    return toArray(lineLengths)
      .filter(
        (r) =>
          !place?.provinceId ||
          String(areaById.get(String(r.area_id))?.province_id) === String(place.provinceId)
      )
      .map((r) => ({
        key: `a-${r.area_id}`,
        name: r.area_name,
        sub: '',
        km: num(r.total_km),
        segments: num(r.segment_count),
        mean_km: num(r.segment_count) > 0 ? num(r.total_km) / num(r.segment_count) : 0,
        area_id: r.area_id,
      }));
  }, [hvLevel, feeders, lineByCsc, lineLengths, place, areaById]);

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

  const CSC_COLUMNS = [
    { key: 'csc_name', label: 'CSC', render: (r) => nameCell(r.csc_name, r.area_name) },
    { key: 'transformers', label: 'Transformers', numeric: true, total: 'sum', share: true },
    { key: 'kva', label: 'Installed kVA', numeric: true, total: 'sum' },
    { key: 'km', label: 'HV km', numeric: true, decimals: 2, total: 'sum' },
    { key: 'segments', label: 'Segments', numeric: true, total: 'sum' },
  ];

  const AREA_COLUMNS = [
    { key: 'area_name', label: 'Area', render: (r) => nameCell(r.area_name, `${formatNumber(r.cscs)} CSCs`) },
    { key: 'transformers', label: 'Transformers', numeric: true, total: 'sum', share: true },
    { key: 'kva', label: 'Installed kVA', numeric: true, total: 'sum' },
    { key: 'km', label: 'HV km', numeric: true, decimals: 2, total: 'sum' },
    { key: 'segments', label: 'Segments', numeric: true, total: 'sum' },
  ];

  const HV_COLUMNS = [
    {
      key: 'name',
      label: hvLevel === 'feeder' ? 'Feeder' : hvLevel === 'csc' ? 'CSC' : 'Area',
      render: (r) => nameCell(r.name, r.sub),
    },
    { key: 'km', label: 'HV length km', numeric: true, decimals: 3, total: 'sum', share: true },
    { key: 'segments', label: 'Segments', numeric: true, total: 'sum' },
    { key: 'mean_km', label: 'Mean km', numeric: true, decimals: 3 },
  ];

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
            <p>{scopeLabel || 'The whole province'} · select a row to narrow the dashboard to it</p>
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

                <DataTable
                  columns={[
                    { key: 'type_name', label: 'Transformer type' },
                    { key: 'units', label: 'Units', numeric: true, total: 'sum', share: true },
                  ]}
                  rows={byType}
                  rowKey={(r) => r.key}
                  initialSortKey="units"
                  footerLabel="All types"
                  emptyMessage="No transformers recorded here."
                  dense
                />
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

                {!units ? (
                  <p className="td-empty">Loading transformers…</p>
                ) : (
                  <DataTable
                    columns={[
                      {
                        key: 'substation_name',
                        label: 'Substation',
                        render: (t) => nameCell(t.substation_name, t.csc_name),
                      },
                      {
                        key: 'new_sin_no',
                        label: 'SIN',
                        render: (t) => t.new_sin_no || t.old_sin_no || '—',
                      },
                      {
                        key: 'transformer_no',
                        label: 'Serial',
                        render: (t) => t.transformer_no || '—',
                      },
                      { key: 'type_name', label: 'Type' },
                      { key: 'capacity_kva', label: 'kVA', numeric: true },
                      {
                        key: 'manufacturer',
                        label: 'Manufacturer',
                        render: (t) => t.manufacturer || '—',
                      },
                    ]}
                    rows={units.rows || []}
                    rowKey={(t) => `t-${t.transformer_id}`}
                    initialSortKey="capacity_kva"
                    footerLabel="On this page"
                    emptyMessage="No transformers match."
                    dense
                    maxHeight={340}
                    onRowClick={(t) => navigate(`/assets?transformer=${t.transformer_id}`)}
                    rowTitle={() => 'Open this transformer in full'}
                  />
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
            <>
              <section className="td-section">
                <h3>
                  By rating <span>{formatNumber(sum(depotRows, readKva))} kVA installed</span>
                </h3>

                <DataTable
                  columns={[
                    { key: 'rating_label', label: 'Rating' },
                    { key: 'units', label: 'Units', numeric: true, total: 'sum' },
                    { key: 'kva', label: 'Installed kVA', numeric: true, total: 'sum', share: true },
                  ]}
                  rows={byRating}
                  rowKey={(r) => r.key}
                  initialSortKey="kva"
                  footerLabel="All ratings"
                  emptyMessage="No capacity recorded here."
                  dense
                />
              </section>

              <section className="td-section">
                <h3>
                  By CSC <span>select a row to open that CSC</span>
                </h3>

                <DataTable
                  columns={[
                    { key: 'csc_name', label: 'CSC', render: (r) => nameCell(r.csc_name, r.area_name) },
                    { key: 'kva', label: 'Installed kVA', numeric: true, total: 'sum', share: true },
                    { key: 'transformers', label: 'Units', numeric: true, total: 'sum' },
                  ]}
                  rows={cscRows}
                  rowKey={(r) => r.key}
                  initialSortKey="kva"
                  footerLabel="Total"
                  emptyMessage="Nothing recorded here."
                  dense
                  maxHeight={360}
                  onRowClick={openCsc}
                  rowTitle={(r) => `Narrow the dashboard to ${r.csc_name}`}
                  isRowMuted={(r) => r.kva === 0}
                />
              </section>
            </>
          )}

          {kind === 'cscs' && (
            <section className="td-section">
              <h3>
                {formatNumber(cscRows.length)} CSCs <span>select a row to open one</span>
              </h3>

              <DataTable
                columns={CSC_COLUMNS}
                rows={cscRows}
                rowKey={(r) => r.key}
                initialSortKey="transformers"
                footerLabel="Total"
                emptyMessage="No CSCs in view."
                dense
                maxHeight={420}
                onRowClick={openCsc}
                rowTitle={(r) => `Narrow the dashboard to ${r.csc_name}`}
                isRowMuted={(r) => r.transformers === 0}
              />
            </section>
          )}

          {kind === 'areas' && (
            <section className="td-section">
              <h3>
                {formatNumber(areaRows.length)} areas <span>select a row to open one</span>
              </h3>

              <DataTable
                columns={AREA_COLUMNS}
                rows={areaRows}
                rowKey={(r) => r.key}
                initialSortKey="transformers"
                footerLabel="Total"
                emptyMessage="No areas in view."
                dense
                maxHeight={420}
                onRowClick={openArea}
                rowTitle={(r) => `Narrow the dashboard to ${r.area_name}`}
                isRowMuted={(r) => r.transformers === 0}
              />
            </section>
          )}

          {kind === 'hv' && (
            <section className="td-section">
              <h3>
                {hvLevel === 'feeder' ? 'By feeder' : hvLevel === 'csc' ? 'By CSC' : 'By area'}
                <span>
                  {formatNumber(hvRows.reduce((s, i) => s + i.km, 0), 2)} km
                </span>
              </h3>

              {hvLevel === 'feeder' && feeders === null ? (
                <p className="td-empty">Loading feeders…</p>
              ) : (
                <DataTable
                  columns={HV_COLUMNS}
                  rows={hvRows}
                  rowKey={(r) => r.key}
                  initialSortKey="km"
                  footerLabel="Total"
                  emptyMessage="No line recorded here."
                  dense
                  maxHeight={420}
                  onRowClick={
                    hvLevel === 'csc'
                      ? openCsc
                      : hvLevel === 'area'
                      ? openArea
                      : undefined
                  }
                  rowTitle={
                    hvLevel === 'feeder'
                      ? undefined
                      : (r) => `Narrow the dashboard to ${r.name}`
                  }
                  isRowMuted={(r) => r.km === 0}
                />
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
