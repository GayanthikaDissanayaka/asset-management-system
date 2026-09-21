import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';

import axiosClient from '../../api/axiosClient';
import DataTable from '../Dashboard/Components/DataTable';
import { num, formatNumber } from '../Dashboard/Components/data';
import { useCurrentUser, canWriteNetwork } from '../Dashboard/Components/session';
import { downloadFromApi } from '../Dashboard/Components/fileTransfer';
import NotificationBell from '../Dashboard/Components/NotificationBell';

import TransformerLookup from './TransformerLookup';
import TransformerDialog from './TransformerDialog';
import CategoryTable from './CategoryTable';
import AddAssetsDialog from './AddAssetsDialog';

import edlMark from '../Auth/edl-mark.png';

import '../Dashboard/Dashbord.css';
import './assets.css';

const VIEWS = [
  { key: 'types', label: 'Asset types' },
  { key: 'places', label: 'By place' },
  { key: 'all', label: 'All assets' },
  { key: 'records', label: 'Records' },
];

const ALL_COLUMNS = [
  {
    key: 'type_name',
    label: 'Asset type',
    render: (r) => (
      <>
        <span className="depot-name">{r.type_name}</span>
        <span className="depot-code">{r.type_code}</span>
      </>
    ),
  },
  { key: 'category_name', label: 'Main asset' },
  {
    
    key: 'quantity',
    label: 'Quantity held',
    numeric: true,
    render: (r) => (
      <>
        {formatNumber(r.quantity, r.unit_of_measure === 'km' ? 3 : 0)}{' '}
        <em className="ax-unit">{r.unit_of_measure}</em>
      </>
    ),
  },
  { key: 'records', label: 'Records', numeric: true, total: 'sum' },
  { key: 'csc_count', label: 'CSCs', numeric: true },
  { key: 'area_count', label: 'Areas', numeric: true },
];

/* One row per individual record. Both registers land here, so the source
   is shown under the code rather than left for the reader to infer. */
const RECORD_COLUMNS = [
  {
    key: 'asset_code',
    label: 'Asset',
    render: (r) => (
      <>
        <span className="depot-name">{r.asset_code || '—'}</span>
        <span className="depot-code">{r.source}</span>
      </>
    ),
  },
  { key: 'type_name', label: 'Type' },
  { key: 'category_name', label: 'Main asset' },
  {
    key: 'quantity',
    label: 'Quantity',
    numeric: true,
    render: (r) => (
      <>
        {formatNumber(r.quantity, r.unit_of_measure === 'km' ? 3 : 0)}{' '}
        <em className="ax-unit">{r.unit_of_measure}</em>
      </>
    ),
  },
  {
    key: 'csc_name',
    label: 'Where',
    render: (r) => (
      <>
        <span className="depot-name">{r.csc_name}</span>
        <span className="depot-code">{r.area_name}</span>
      </>
    ),
  },
  {
    key: 'attached_ref',
    label: 'Attached to',
    render: (r) => (
      <>
        {r.attached_ref || '—'}
        <span className="depot-code">{r.attached_to}</span>
      </>
    ),
  },
  {
    key: 'condition_status',
    label: 'Condition',
    render: (r) => (r.condition_status === 'UNKNOWN' ? '—' : r.condition_status),
  },
];

const PLACE_LEVELS = [
  { key: 'province', label: 'Province' },
  { key: 'area', label: 'Area' },
  { key: 'csc', label: 'CSC' },
];

/*
 * The headline figures, and the table behind each.
 *
 * A tile is deliberately one number with one line under it — that is all
 * a page should ask someone to read before they have chosen what they
 * came for. Selecting it switches the panel below to the table that
 * number came from, which is the whole shape of this page: a short
 * summary first, working detail on request.
 */
const TOTAL_TILES = [
  {
    kind: 'records',
    label: 'Asset records',
    accent: 'accent-1',
    view: 'records',
    title: 'Every individual record, row by row',
    value: (s) => formatNumber(s?.records),
    hint: (s, filtered) =>
      filtered ? 'Matching the filters' : 'Across the whole province',
  },
  {
    kind: 'counted',
    label: 'Counted items',
    accent: 'accent-2',
    view: 'all',
    title: 'Every asset type, and what is held against each',
    value: (s) => (
      <>
        {formatNumber(s?.counted_units)} <em className="ax-unit">nos</em>
      </>
    ),
    hint: () => 'Transformers, switches, poles and plant',
  },
  {
    kind: 'line',
    label: 'Line recorded',
    accent: 'accent-3',
    view: 'places',
    title: 'Line and counted items, place by place',
    value: (s) => (
      <>
        {formatNumber(s?.line_km, 3)} <em className="ax-unit">km</em>
      </>
    ),
    hint: () => 'Conductor and line, kept apart',
  },
  {
    kind: 'transformers',
    label: 'Transformers',
    accent: 'accent-4',
    view: 'types',
    title: 'The main assets, opening into their types',
    value: (s) => formatNumber(s?.transformers),
    hint: (s) => `${formatNumber(s?.switchgear)} switchgear beside them`,
  },
  {
    kind: 'spread',
    label: 'Spread',
    accent: 'accent-5',
    view: 'places',
    title: 'Province, area and CSC totals',
    value: (s) => (
      <>
        {formatNumber(s?.csc_count)} <em className="ax-unit">CSCs</em>
      </>
    ),
    hint: (s) =>
      `in ${formatNumber(s?.area_count)} areas · ${formatNumber(
        s?.type_count
      )} asset types`,
  },
];

const EMPTY_FILTERS = {
  provinceId: '',
  areaId: '',
  cscId: '',
  categoryId: '',
  assetTypeId: '',
  condition: '',
  search: '',
};

const placeColumns = (level) => [
  {
    key: 'group_name',
    label: level === 'province' ? 'Province' : level === 'area' ? 'Area' : 'CSC',
    render: (r) => (
      <>
        <span className="depot-name">{r.group_name}</span>
        {r.group_code && r.group_code !== r.group_name && (
          <span className="depot-code">{r.group_code}</span>
        )}
      </>
    ),
  },
  { key: 'records', label: 'Records', numeric: true, total: 'sum', share: true },
  { key: 'type_count', label: 'Types', numeric: true },
  { key: 'counted_qty', label: 'Counted nos', numeric: true, total: 'sum' },
  { key: 'line_km', label: 'Line km', numeric: true, decimals: 3, total: 'sum' },
];

const RECORDS_PER_PAGE = 50;

const DOWNLOADS = [
  {
    key: 'report',
    label: 'Full report (province, area, CSC)',
    path: '/network/report',
    file: 'uva-network-asset-report.xlsx',
  },
  {
    key: 'assets-used',
    label: 'Used assets — every entry',
    path: '/network/export?view=assets-used',
    file: 'uva-assets-used.xlsx',
  },
  {
    key: 'assets-used-by-csc',
    label: 'Used assets — totalled by CSC',
    path: '/network/export?view=assets-used-by-csc',
    file: 'uva-assets-used-by-csc.xlsx',
  },
  {
    key: 'asset-types',
    label: 'Asset catalogue (all types)',
    path: '/network/export?view=asset-types',
    file: 'uva-asset-types.xlsx',
  },
  {
    key: 'asset-by-csc',
    label: 'Assets held, by CSC',
    path: '/network/export?view=asset-by-csc',
    file: 'uva-assets-by-csc.xlsx',
  },
];

const AssetsPage = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const user = useCurrentUser();
  const mayWrite = canWriteNetwork(user);

  const [view, setView] = useState('types');
  const [placeLevel, setPlaceLevel] = useState('csc');
  const [filters, setFilters] = useState(EMPTY_FILTERS);

  const [options, setOptions] = useState(null);
  const [optionsError, setOptionsError] = useState('');

  const [summary, setSummary] = useState(null);
  const [categories, setCategories] = useState([]);
  const [places, setPlaces] = useState([]);
  const [catalogue, setCatalogue] = useState(null);
  const [records, setRecords] = useState(null);
  const [page, setPage] = useState(1);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const [transformerId, setTransformerId] = useState(null);
  const [addOpen, setAddOpen] = useState(false);
  const [notice, setNotice] = useState('');

  const [download, setDownload] = useState('report');
  const [downloading, setDownloading] = useState(false);

  /* The filter values, in the shape the API expects. Built once and
     shared by every request, which is what keeps the panels agreeing. */
  const params = useMemo(
    () => ({
      province_id: filters.provinceId || undefined,
      area_id: filters.areaId || undefined,
      csc_id: filters.cscId || undefined,
      category_id: filters.categoryId === '' ? undefined : filters.categoryId,
      asset_type_id: filters.assetTypeId || undefined,
      condition: filters.condition || undefined,
      search: filters.search.trim() || undefined,
    }),
    [filters]
  );

  const loadOptions = useCallback(() => {
    setOptionsError('');
    axiosClient
      .get('/network/assets/options')
      .then(({ data }) => setOptions(data))
      .catch(() =>
        setOptionsError('Could not load the areas, CSCs and asset types.')
      );
  }, []);

  useEffect(loadOptions, [loadOptions]);

  useEffect(() => {
    const tx = searchParams.get('transformer');
    const areaId = searchParams.get('area_id');
    const cscId = searchParams.get('csc_id');
    const term = searchParams.get('search');

    if (tx) setTransformerId(Number(tx));

    if (areaId || cscId || term) {
      setFilters({
        ...EMPTY_FILTERS,
        areaId: areaId || '',
        cscId: cscId || '',
        search: term || '',
      });

      // Place and text searches show the matching records, not a card
      // summary that cannot expose each individual asset.
      if (cscId || term) setView('records');
    }
  }, [searchParams]);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');

    try {
      const [sum, cat, place, types] = await Promise.all([
        axiosClient.get('/network/assets/summary', { params }),
        axiosClient.get('/network/assets/catalog', { params }),
        axiosClient.get('/network/assets/breakdown', {
          params: { ...params, level: placeLevel },
        }),
        // Straight from asset_categories and asset_types.
        axiosClient.get('/network/assets/types', { params }),
      ]);

      setSummary(sum.data);
      setCategories(cat.data || []);
      setPlaces(place.data?.rows || []);
      setCatalogue(types.data || null);
    } catch (err) {
      setError(
        err.response
          ? `The server returned ${err.response.status}.`
          : 'Could not reach the API. Check that Laravel is running on port 8000.'
      );
    } finally {
      setLoading(false);
    }
  }, [params, placeLevel]);

  useEffect(() => {
    load();
  }, [load]);

  /* The record list is paged and only fetched when it is on screen.
     Pulling three thousand rows to render a card grid would be work
     nobody asked for. */
  useEffect(() => {
    if (view !== 'records') return;

    let cancelled = false;

    axiosClient
      .get('/network/assets/records', {
        params: { ...params, page, limit: RECORDS_PER_PAGE },
      })
      .then(({ data }) => {
        if (!cancelled) setRecords(data);
      })
      .catch(() => {
        if (!cancelled) setRecords({ rows: [], total: 0, last_page: 1, page: 1 });
      });

    return () => {
      cancelled = true;
    };
  }, [view, params, page]);

  // Any change of filter starts the list again at the first page, or a
  // narrowed result would open on page 7 of 2 and look empty.
  useEffect(() => setPage(1), [params]);

  const setFilter = (name, value) => {
    setFilters((f) => {
      const next = { ...f, [name]: value };
      if (name === 'provinceId') {
        next.areaId = '';
        next.cscId = '';
      }
      if (name === 'areaId') next.cscId = '';
      // Picking a category clears a type from another category, which
      // would otherwise leave the page filtered to nothing.
      if (name === 'categoryId') next.assetTypeId = '';
      return next;
    });

    // A type, CSC or text search needs row-level detail, so move straight
    // to the paged records table when one is entered.
    if (['assetTypeId', 'cscId', 'search'].includes(name) && String(value).trim()) {
      setView('records');
    }
  };

  /* A row in the "by place" table is a place, so selecting it goes into
     that place: a province opens its areas, an area opens its CSCs, and a
     CSC — which has nothing below it — opens its records. */
  const openPlaceRow = (row) => {
    if (placeLevel === 'province') {
      setFilter('provinceId', String(row.group_id));
      setPlaceLevel('area');
      return;
    }
    if (placeLevel === 'area') {
      setFilter('areaId', String(row.group_id));
      setPlaceLevel('csc');
      return;
    }
    setFilter('cscId', String(row.group_id));
  };

  const typeChoices = useMemo(
    () =>
      (options?.types || []).filter(
        (t) =>
          !filters.categoryId ||
          String(t.category_id) === String(filters.categoryId)
      ),
    [options, filters.categoryId]
  );

  const cscChoices = useMemo(
    () =>
      (options?.cscs || []).filter(
        (c) => !filters.areaId || String(c.area_id) === String(filters.areaId)
      ),
    [options, filters.areaId]
  );

  const filtered = useMemo(
    () => Object.values(filters).some((v) => String(v).trim() !== ''),
    [filters]
  );

  const activeType = useMemo(
    () =>
      (options?.types || []).find(
        (t) => String(t.asset_type_id) === String(filters.assetTypeId)
      ),
    [options, filters.assetTypeId]
  );

  const goBack = () => {
    if (window.history.state?.idx > 0) navigate(-1);
    else navigate('/dashboard');
  };

  const runDownload = async () => {
    const choice = DOWNLOADS.find((d) => d.key === download);
    if (!choice) return;

    setDownloading(true);
    setError('');
    try {
      // Fetched as a blob rather than linked, so the request carries the
      // Authorization header a plain <a href> would drop.
      const name = await downloadFromApi(choice.path, choice.file);
      setNotice(`Downloaded ${name}.`);
    } catch (err) {
      setError(
        err.response
          ? `Could not build that file (${err.response.status}).`
          : 'Could not reach the API to build the file.'
      );
    } finally {
      setDownloading(false);
    }
  };

  const onSaved = (data) => {
    setNotice(
      `${data.message} ${data.place.csc_name} now holds ` +
        data.place_totals
          .map(
            (t) =>
              `${formatNumber(t.quantity, t.unit_of_measure === 'km' ? 3 : 0)} ${
                t.unit_of_measure
              }`
          )
          .join(' and ') +
        '.'
    );
    load();
  };

  return (
    <div className="dashboard-page ax-page">
      <header className="dashboard-header">
        <div className="dashboard-identity">
          <button type="button" className="dashboard-back" onClick={goBack}>
            &larr; Back
          </button>

          <img src={edlMark} alt="" className="dashboard-logo" width={32} height={32} />

          <div className="dashboard-titles">
            <h1>Assets</h1>
            <p>CEB Uva Province &middot; transformers, switchgear, lines and plant</p>
          </div>
        </div>

        <div className="dashboard-actions">
          {/* Access requests reach an administrator on every page, not
              only on the dashboard. */}
          <NotificationBell />

          <button
            type="button"
            className="approvals-button"
            onClick={() => navigate('/dashboard')}
          >
            Dashboard
          </button>

          <button
            type="button"
            className="approvals-button"
            onClick={() => navigate('/hv-length')}
          >
            HV Length
          </button>

          {/* Offered to everyone and disabled with a reason, rather than
              hidden. A viewer who cannot find the button assumes the
              feature is missing; one who sees it greyed knows to ask. */}
          <button
            type="button"
            className="ax-add-button"
            onClick={() => setAddOpen(true)}
            disabled={!mayWrite}
            title={
              mayWrite
                ? 'Record assets against a CSC'
                : 'Your role does not allow recording assets. An administrator can widen your access.'
            }
          >
            + Add assets
          </button>

          <button className="refresh-button" onClick={load} disabled={loading}>
            {loading ? 'Loading...' : '↻ Refresh'}
          </button>
        </div>
      </header>

      {notice && (
        <div className="dashboard-inline-notice">
          {notice}
          <button type="button" className="link-button" onClick={() => setNotice('')}>
            Dismiss
          </button>
        </div>
      )}

      {/* Requirement in its own right, and independent of the filters
          below: somebody looking up one transformer by number does not
          want the answer hidden because the page is filtered to another
          area. */}
      <TransformerLookup onOpen={setTransformerId} />

      <section className="ax-filters">
        <label className="ax-filter">
          <span>Province</span>
          <select
            value={filters.provinceId}
            onChange={(e) => setFilter('provinceId', e.target.value)}
          >
            <option value="">All provinces</option>
            {(options?.provinces || []).map((p) => (
              <option key={p.province_id} value={p.province_id}>
                {p.province_name}
              </option>
            ))}
          </select>
        </label>

        <label className="ax-filter">
          <span>Area</span>
          <select
            value={filters.areaId}
            onChange={(e) => setFilter('areaId', e.target.value)}
          >
            <option value="">All areas</option>
            {(options?.areas || [])
              .filter(
                (a) =>
                  !filters.provinceId ||
                  String(a.province_id) === String(filters.provinceId)
              )
              .map((a) => (
              <option key={a.area_id} value={a.area_id}>
                {a.area_name} ({a.area_code})
              </option>
            ))}
          </select>
        </label>

        <label className="ax-filter">
          <span>CSC</span>
          <select
            value={filters.cscId}
            onChange={(e) => setFilter('cscId', e.target.value)}
          >
            <option value="">
              {filters.areaId ? 'All in this area' : 'All CSCs'}
            </option>
            {cscChoices.map((c) => (
              <option key={c.csc_id} value={c.csc_id}>
                {c.csc_name} ({c.csc_code})
              </option>
            ))}
          </select>
        </label>

        <label className="ax-filter">
          <span>Main asset</span>
          <select
            value={filters.categoryId}
            onChange={(e) => setFilter('categoryId', e.target.value)}
          >
            <option value="">All categories</option>
            {(options?.categories || []).map((c) => (
              <option key={c.category_id} value={c.category_id}>
                {c.category_name}
              </option>
            ))}
          </select>
        </label>

        <label className="ax-filter">
          <span>Asset type</span>
          <select
            value={filters.assetTypeId}
            onChange={(e) => setFilter('assetTypeId', e.target.value)}
          >
            <option value="">All asset types</option>
            {typeChoices.map((t) => (
              <option key={t.asset_type_id} value={t.asset_type_id}>
                {t.type_name} ({t.type_code})
              </option>
            ))}
          </select>
        </label>

        <label className="ax-filter">
          <span>Condition</span>
          <select
            value={filters.condition}
            onChange={(e) => setFilter('condition', e.target.value)}
          >
            <option value="">Any condition</option>
            {(options?.conditions || []).map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>

        <label className="ax-filter ax-filter-grow">
          <span>Search</span>
          <input
            type="search"
            value={filters.search}
            placeholder="Asset code, substation, switch or CSC"
            onChange={(e) => setFilter('search', e.target.value)}
          />
        </label>

        {/* Downloads sit beside the filters rather than in the header,
            because the header already carries four buttons and this is
            the row people are already working in. The files are the
            whole register, not the current filter — a report that
            silently omitted whatever was filtered out would be a
            dangerous thing to sign off. */}
        <label className="ax-filter ax-filter-download">
          <span>Download</span>
          <select
            value={download}
            onChange={(e) => setDownload(e.target.value)}
          >
            {DOWNLOADS.map((d) => (
              <option key={d.key} value={d.key}>
                {d.label}
              </option>
            ))}
          </select>
        </label>

        <div className="ax-filter ax-filter-actions">
          <button
            type="button"
            className="dash-btn-primary dash-btn-sm"
            onClick={runDownload}
            disabled={downloading}
            title="Builds an Excel file of the whole register, not the current filter"
          >
            {downloading ? 'Building...' : '↓ Excel'}
          </button>

          <button
            type="button"
            className="dash-btn-quiet dash-btn-sm"
            onClick={() => setFilters(EMPTY_FILTERS)}
            disabled={!filtered}
          >
            Clear filters
          </button>
        </div>
      </section>

      {/* A type filter is set by clicking a card, far from the filter
          row, so it says so here where the numbers it changed are. */}
      {activeType && (
        <div className="ax-active-filter">
          Showing <strong>{activeType.type_name}</strong> only.
          <button
            type="button"
            className="link-button"
            onClick={() => setFilter('assetTypeId', '')}
          >
            Show all types
          </button>
        </div>
      )}

      {error && <div className="register-error">{error}</div>}

      {/* The five figures worth knowing before anything else. Each one
          opens the table it was added up from, so the page starts simple
          and the detail is one click away rather than all at once. */}
      <section className="summary-cards ax-totals">
        {TOTAL_TILES.map((tile) => (
          <button
            type="button"
            key={tile.kind}
            className={`summary-card is-clickable ${tile.accent}`}
            onClick={() => setView(tile.view)}
            title={tile.title}
          >
            <span className="summary-label">
              {tile.label}
              <span className="summary-more" aria-hidden="true">
                Details &rarr;
              </span>
            </span>
            <span className="summary-value">{tile.value(summary)}</span>
            <span className="summary-hint">{tile.hint(summary, filtered)}</span>
          </button>
        ))}
      </section>

      <section className="dashboard-card ax-main">
        <div className="register-toolbar">
          <div className="register-tabs" role="tablist" aria-label="Asset view">
            {VIEWS.map((v) => (
              <button
                key={v.key}
                type="button"
                role="tab"
                aria-selected={view === v.key}
                className={`register-tab${view === v.key ? ' is-active' : ''}`}
                onClick={() => setView(v.key)}
              >
                {v.label}
              </button>
            ))}
          </div>

          <div className="register-toolbar-right">
            {view === 'places' && (
              <div className="register-tabs" role="tablist" aria-label="Grouping level">
                {PLACE_LEVELS.map((l) => (
                  <button
                    key={l.key}
                    type="button"
                    role="tab"
                    aria-selected={placeLevel === l.key}
                    className={`register-tab${placeLevel === l.key ? ' is-active' : ''}`}
                    onClick={() => setPlaceLevel(l.key)}
                  >
                    {l.label}
                  </button>
                ))}
              </div>
            )}

            <span className="register-summary">
              {view === 'records' && records
                ? `${formatNumber(records.total)} records · page ${records.page} of ${records.last_page}`
                : view === 'places'
                ? `${formatNumber(places.length)} places`
                : view === 'all' && catalogue
                ? `${formatNumber(catalogue.type_count)} types in ${formatNumber(
                    catalogue.category_count
                  )} categories`
                : `${formatNumber(categories.length)} categories`}
            </span>
          </div>
        </div>

        {/* ------------------------- asset types ------------------------- */}
        {view === 'types' && (
          <>
            <p className="ax-block-hint ax-view-hint">
              Each row is a main asset. Open one with <strong>+</strong> to see the
              types inside it, and select a type to open its records. Counted
              items and line are in separate columns because they are different
              units.
            </p>

            <CategoryTable
              categories={categories}
              typeFilter={filters.assetTypeId}
              onPickType={(id) => setFilter('assetTypeId', id)}
            />
          </>
        )}

        {/* -------------------------- by place --------------------------- */}
        {view === 'places' && (
          <>
            <p className="ax-block-hint ax-view-hint">
              An asset belongs to exactly one CSC, so these levels all add up to
              the same records. Counted items and line are kept in separate
              columns because they are different units. Select a row to open
              the place inside it.
            </p>

            <DataTable
              columns={placeColumns(placeLevel)}
              rows={places}
              rowKey={(r) => `${placeLevel}-${r.group_id}`}
              initialSortKey="records"
              footerLabel="Total"
              emptyMessage="Nothing matches these filters."
              isRowMuted={(r) => num(r.records) === 0}
              onRowClick={openPlaceRow}
              rowTitle={(r) =>
                placeLevel === 'csc'
                  ? `Every record in ${r.group_name}`
                  : `Open ${r.group_name}`
              }
            />
          </>
        )}

        {/* ------------- all assets, from the two reference tables ------- */}
        {view === 'all' && (
          <>
            <p className="ax-block-hint ax-view-hint">
              Every category and type defined in <code>asset_categories</code> and{' '}
              <code>asset_types</code>, with what is held against each. Types
              holding nothing are listed too — that a type has no records is
              itself worth seeing. Select a row to open that type's records.
            </p>

            <DataTable
              columns={ALL_COLUMNS}
              rows={catalogue?.rows || []}
              rowKey={(r) => `type-${r.asset_type_id}`}
              initialSortKey="records"
              footerLabel="All types"
              emptyMessage="No asset types are defined."
              isRowMuted={(r) => num(r.records) === 0}
              isRowActive={(r) =>
                String(filters.assetTypeId) === String(r.asset_type_id)
              }
              onRowClick={(r) =>
                setFilter(
                  'assetTypeId',
                  String(filters.assetTypeId) === String(r.asset_type_id)
                    ? ''
                    : String(r.asset_type_id)
                )
              }
              rowTitle={(r) =>
                String(filters.assetTypeId) === String(r.asset_type_id)
                  ? 'Showing only this type. Select again to clear.'
                  : `Show only ${r.type_name}`
              }
              maxHeight={560}
            />
          </>
        )}

        {/* ------------------------- all records ------------------------- */}
        {view === 'records' && (
          <>
            <p className="ax-block-hint ax-view-hint">
              Every individual record, newest first. Transformers and switchgear
              come from their own registers; anything entered through this page
              shows as held by a CSC.
            </p>

            {!records ? (
              <div className="chart-empty">Loading records...</div>
            ) : records.rows.length === 0 ? (
              <div className="chart-empty">Nothing matches these filters.</div>
            ) : (
              <>
                <DataTable
                  columns={RECORD_COLUMNS}
                  rows={records.rows}
                  rowKey={(r) => `${r.source}-${r.source_id}`}
                  initialSortKey="quantity"
                  footerLabel="On this page"
                  emptyMessage="Nothing matches these filters."
                  maxHeight={560}
                />

                <div className="ax-pager">
                  <button
                    type="button"
                    className="dash-btn-quiet dash-btn-sm"
                    onClick={() => setPage((p) => Math.max(1, p - 1))}
                    disabled={records.page <= 1}
                  >
                    &larr; Previous
                  </button>

                  <span>
                    {formatNumber((records.page - 1) * records.limit + 1)}–
                    {formatNumber(
                      Math.min(records.page * records.limit, records.total)
                    )}{' '}
                    of {formatNumber(records.total)}
                  </span>

                  <button
                    type="button"
                    className="dash-btn-quiet dash-btn-sm"
                    onClick={() => setPage((p) => p + 1)}
                    disabled={records.page >= records.last_page}
                  >
                    Next &rarr;
                  </button>
                </div>
              </>
            )}
          </>
        )}
      </section>

      <TransformerDialog
        transformerId={transformerId}
        onClose={() => setTransformerId(null)}
      />

      <AddAssetsDialog
        open={addOpen}
        options={options}
        optionsError={optionsError}
        onClose={() => setAddOpen(false)}
        onSaved={onSaved}
      />
    </div>
  );
};

export default AssetsPage;
