import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import axiosClient from '../../../api/axiosClient';
import DataTable from './DataTable';
import AddSegmentDialog from './AddSegmentDialog';
import ImportDialog from './ImportDialog';
import { downloadFromApi } from './fileTransfer';
import { useCurrentUser, canWriteNetwork } from './session';
import { num, formatNumber } from './data';
import { EMPTY_PLACE, describePlace, isPlaceSet } from './PlaceFilter';

/**
 * The register card: one table, six ways of reading it.
 *
 *   Transformers  units and capacity per CSC
 *   Areas         line length rolled up to the five operational areas
 *   CSCs          line length per consumer service centre
 *   Feeders       line length per feeder, including feeders crossing CSCs
 *   Segments      the individual segments, one row each, searchable
 *   Assets        every asset type, its total, and how widely it is used
 *
 * Every roll-up prints a segment count beside its total. A CSC with three
 * segments is three segments here, never one.
 *
 * The Crossing column counts segments running through more than one CSC.
 * Their length is split, so each CSC and each area is credited only with
 * the kilometres inside it.
 */

/* Anything added through this application rather than the original bulk
   loads. Marking them is how a just-entered segment is found again. */
const ENTERED_SOURCES = ['dashboard-entry', 'excel-import'];

const NAME_CELL = (nameKey, codeKey) => (row) =>
  (
    <>
      <span className="depot-name">{row[nameKey] || 'Unknown'}</span>
      {row[codeKey] && <span className="depot-code">{row[codeKey]}</span>}
    </>
  );

const VIEWS = {
  transformers: {
    label: 'Transformers',
    endpoint: null, // supplied by the dashboard, already loaded
    footerLabel: 'Province total',
    sort: 'transformers',
    empty: 'No CSC summary available.',
    columns: [
      { key: 'name', label: 'CSC', render: NAME_CELL('name', 'code') },
      { key: 'area', label: 'Area' },
      { key: 'transformers', label: 'Transformers', numeric: true, total: 'sum', share: true },
      { key: 'kva', label: 'Installed kVA', numeric: true, total: 'sum' },
      /* HV line inside each CSC, from the segment register -- the same
         source as the HV Line tile, so column and tile agree. */
      { key: 'networkKm', label: 'HV km', numeric: true, decimals: 2, total: 'sum' },
    ],
  },

  areas: {
    label: 'Areas',
    endpoint: '/network/length/by-area',
    footerLabel: 'Province total',
    sort: 'total_km',
    empty: 'No area lengths available.',
    columns: [
      { key: 'area_name', label: 'Area', render: NAME_CELL('area_name', 'area_code') },
      { key: 'csc_count', label: 'CSCs', numeric: true, total: 'sum' },
      /*
       * Segments TOUCHING the area, so a segment crossing between two
       * areas is counted by both. The per-row figure is what that area
       * holds, but the column is deliberately not totalled: adding them
       * would report more segments than exist. The Segments tab is the
       * authoritative list, and the kilometres beside these counts are
       * exact because those are split portions.
       */
      { key: 'segment_count', label: 'Segments', numeric: true },
      { key: 'crossing_count', label: 'Crossing', numeric: true },
      { key: 'feeder_count', label: 'Feeders', numeric: true },
      { key: 'total_km', label: 'Total km', numeric: true, decimals: 2, total: 'sum', share: true },
      { key: 'mean_km', label: 'Mean km', numeric: true, decimals: 3 },
    ],
  },

  cscs: {
    label: 'CSCs',
    endpoint: '/network/length/by-csc',
    footerLabel: 'Province total',
    sort: 'total_km',
    empty: 'No CSC lengths available.',
    columns: [
      { key: 'csc_name', label: 'CSC', render: NAME_CELL('csc_name', 'csc_code') },
      { key: 'area_name', label: 'Area' },
      // Touching, not owned. Not totalled, for the reason above.
      { key: 'segment_count', label: 'Segments', numeric: true },
      { key: 'crossing_count', label: 'Crossing', numeric: true },
      { key: 'total_km', label: 'Total km', numeric: true, decimals: 2, total: 'sum', share: true },
      { key: 'mean_km', label: 'Mean km', numeric: true, decimals: 3 },
      { key: 'longest_km', label: 'Longest km', numeric: true, decimals: 3 },
    ],
  },

  feeders: {
    label: 'Feeders',
    endpoint: '/network/length/by-feeder',
    footerLabel: 'All feeders',
    sort: 'total_km',
    empty: 'No feeder lengths available.',
    columns: [
      { key: 'feeder_code', label: 'Feeder', render: NAME_CELL('feeder_code', 'feeder_name') },
      { key: 'external_source', label: 'Source' },
      { key: 'depots_crossed', label: 'CSCs crossed', numeric: true },
      { key: 'segment_count', label: 'Segments', numeric: true, total: 'sum' },
      { key: 'total_km', label: 'Total km', numeric: true, decimals: 2, total: 'sum', share: true },
    ],
  },

  segments: {
    label: 'Segments',
    searchable: true,
    footerLabel: 'Segments listed',
    sort: 'length_km',
    empty: 'No segments match.',
    columns: [
      {
        key: 'segment_code',
        label: 'Segment ID',
        render: (row) => (
          <>
            <span className="depot-name">{row.segment_code}</span>
            {ENTERED_SOURCES.includes(row.source_file) && (
              <span
                className="source-pill"
                title={
                  row.source_file === 'dashboard-entry'
                    ? 'Added with the Add segment button'
                    : 'Loaded from a spreadsheet'
                }
              >
                {row.source_file === 'dashboard-entry' ? 'added here' : 'imported'}
              </span>
            )}
          </>
        ),
      },
      { key: 'csc_name', label: 'CSC', render: NAME_CELL('csc_name', 'csc_code') },
      { key: 'area_name', label: 'Area' },
      { key: 'feeder_code', label: 'Feeder' },
      {
        key: 'csc_count',
        label: 'CSCs',
        numeric: true,
        render: (row) =>
          num(row.csc_count) > 1 ? (
            <span
              className="crossing-pill"
              title={row.csc_portions
                ?.map((p) => `${p.csc_name}: ${Number(p.length_km).toFixed(3)} km`)
                .join('\n')}
            >
              {row.csc_count}
            </span>
          ) : (
            '1'
          ),
      },
      { key: 'voltage_level', label: 'Voltage' },
      { key: 'length_km', label: 'Length km', numeric: true, decimals: 3, total: 'sum' },
    ],
  },

  assets: {
    label: 'Assets',
    endpoint: '/network/assets/totals',
    footerLabel: 'Asset types',
    sort: 'total_quantity',
    empty: 'No assets recorded.',
    columns: [
      { key: 'type_name', label: 'Asset', render: NAME_CELL('type_name', 'category_name') },
      { key: 'unit_of_measure', label: 'Unit' },
      /*
       * NOT totalled. This column holds kilometres of conductor beside
       * counts of poles, so a sum down it would add lengths to counts.
       * The strip above states the two separately.
       */
      { key: 'total_quantity', label: 'Total', numeric: true, decimals: 3 },
      { key: 'placements', label: 'Records', numeric: true, total: 'sum' },
      { key: 'csc_count', label: 'CSCs', numeric: true },
      { key: 'area_count', label: 'Areas', numeric: true },
    ],
  },
};

const ROW_KEYS = {
  transformers: (r) => r.id,
  areas: (r) => r.area_id,
  cscs: (r) => r.csc_id,
  feeders: (r) => r.feeder_id,
  segments: (r) => r.register_id,
  assets: (r) => `${r.asset_type_id}-${r.unit_of_measure}`,
};

/* Module scope, so the callbacks below can use it without carrying it as
   a dependency that changes every render. */
const describeError = (err) =>
  err.response
    ? `The server returned ${err.response.status}.`
    : 'Could not reach the API. Check that Laravel is running on port 8000.';

const NetworkRegister = ({
  cscSummaryRows,
  onToast,
  focus,
  place = EMPTY_PLACE,
  placeOptions,
  dataVersion = 0,
  onDataChanged,
  profile,
}) => {
  const [view, setView] = useState('transformers');
  const [cache, setCache] = useState({});
  const [segmentRows, setSegmentRows] = useState(undefined);
  const [search, setSearch] = useState('');
  const [loadingView, setLoadingView] = useState(false);
  const [viewError, setViewError] = useState('');

  const [options, setOptions] = useState(null);
  const [optionsError, setOptionsError] = useState('');
  const [addOpen, setAddOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);
  const [exporting, setExporting] = useState(false);

  const config = VIEWS[view];

  /*
   * The dashboard's place filter.
   *
   * Every tab narrows to the chosen province, area or CSC, so picking
   * "Badulla" shows Badulla's transformers, its line, its feeders, its
   * segments and its assets together. Rows that carry only a CSC are
   * placed in their area through the CSC list; rows that carry only an
   * area are placed in their province through the area list.
   */
  const placeActive = isPlaceSet(place);
  const placeLabel = describePlace(place, placeOptions);

  /*
   * Profile or table.
   *
   * With a place chosen, the card opens on the place profile -- the
   * place described, with the places inside it as cards -- because that
   * is what somebody who searched for a place wants to see. The table is
   * one click away. With no place chosen there is nothing to profile, so
   * the table is all there is.
   */
  const [mode, setMode] = useState('profile');
  const wasActive = useRef(placeActive);
  useEffect(() => {
    if (placeActive && !wasActive.current) setMode('profile');
    wasActive.current = placeActive;
  }, [placeActive]);

  const showProfile = placeActive && Boolean(profile) && mode === 'profile';

  const { cscById, areaById } = useMemo(() => {
    const cscMap = new Map();
    const areaMap = new Map();
    for (const c of placeOptions?.cscs || []) cscMap.set(String(c.csc_id), c);
    for (const a of placeOptions?.areas || []) areaMap.set(String(a.area_id), a);
    return { cscById: cscMap, areaById: areaMap };
  }, [placeOptions]);

  const inPlace = useCallback(
    (r) => {
      if (!placeActive) return true;

      const csc = r.csc_id ?? r.origin_csc_id;
      const hasCsc = csc !== undefined && csc !== null;
      const areaId = r.area_id ?? (hasCsc ? cscById.get(String(csc))?.area_id : undefined);
      const hasArea = areaId !== undefined && areaId !== null;
      const provinceId =
        r.province_id ?? (hasArea ? areaById.get(String(areaId))?.province_id : undefined);

      if (place.cscId) {
        if (hasCsc) return String(csc) === String(place.cscId);
        // An area row: keep the area the chosen CSC belongs to.
        const cscArea = cscById.get(String(place.cscId))?.area_id;
        return hasArea && String(areaId) === String(cscArea);
      }

      if (place.areaId) {
        return hasArea && String(areaId) === String(place.areaId);
      }

      return (
        provinceId !== undefined &&
        provinceId !== null &&
        String(provinceId) === String(place.provinceId)
      );
    },
    [placeActive, place.cscId, place.areaId, place.provinceId, cscById, areaById]
  );

  /* Something was added -- here, on another page, or by someone else --
     so every cached tab is stale. Skipped on first render, which has
     nothing cached yet. */
  const seenVersion = useRef(dataVersion);
  useEffect(() => {
    if (dataVersion === seenVersion.current) return;
    seenVersion.current = dataVersion;
    setCache({});
    setSegmentRows(undefined);
  }, [dataVersion]);

  /* The global search asking for a particular tab and term.
     Applied only when `focus` actually changes, so it steers the
     register on arrival and then leaves it alone — otherwise a reader
     who switched tabs afterwards would be dragged back on every
     render. */
  useEffect(() => {
    if (!focus) return;
    if (focus.view && VIEWS[focus.view]) setView(focus.view);
    setSearch(focus.search || '');
  }, [focus]);

  /* Confirmed against the server on mount, so a role widened by an
     administrator takes effect on the next page load rather than only
     after signing out and back in.

     Greying the buttons is a courtesy, not the gate: the API checks the
     same roles on every write. */
  const user = useCurrentUser();
  const mayWrite = canWriteNetwork(user);
  const writeBlockedReason = user
    ? `Signed in as ${user.role || 'a viewer'}, which cannot record network data.`
    : 'Sign in with an engineer account to record network data.';

  const fetchView = useCallback(async (key) => {
    const target = VIEWS[key];
    if (!target.endpoint) return;

    setViewError('');
    setLoadingView(true);
    try {
      const { data } = await axiosClient.get(target.endpoint);
      setCache((c) => ({ ...c, [key]: data || [] }));
    } catch (err) {
      console.error(`Failed to load ${key}:`, err);
      setViewError(describeError(err));
    } finally {
      setLoadingView(false);
    }
  }, []);

  useEffect(() => {
    if (config.endpoint && cache[view] === undefined) {
      fetchView(view);
    }
  }, [view, config.endpoint, cache, fetchView]);

  /* The Assets tab's province totals cannot be narrowed to a place, so
     when a place is chosen it reads the per-CSC breakdown instead and
     adds that up for the place. */
  useEffect(() => {
    if (view !== 'assets' || !placeActive || cache.assetsByCsc !== undefined) return;

    axiosClient
      .get('/network/assets/by-csc')
      .then(({ data }) => setCache((c) => ({ ...c, assetsByCsc: data || [] })))
      .catch((err) => setViewError(describeError(err)));
  }, [view, placeActive, cache.assetsByCsc]);

  /* Segments are fetched with the search term rather than cached, and the
     keystrokes are debounced so typing does not fire a request per
     letter. */
  const loadSegments = useCallback(async (term) => {
    setViewError('');
    setLoadingView(true);
    try {
      const { data } = await axiosClient.get('/network/segments', {
        params: {
          limit: 500,
          search: term || undefined,
          area_id: place.areaId || undefined,
          csc_id: place.cscId || undefined,
        },
      });
      setSegmentRows(data || []);
    } catch (err) {
      console.error('Failed to load segments:', err);
      setViewError(describeError(err));
      setSegmentRows([]);
    } finally {
      setLoadingView(false);
    }
  }, [place.areaId, place.cscId]);

  useEffect(() => {
    if (view !== 'segments') return undefined;
    const timer = setTimeout(() => loadSegments(search.trim()), search ? 350 : 0);
    return () => clearTimeout(timer);
  }, [view, search, loadSegments, dataVersion]);

  const loadOptions = useCallback(async () => {
    setOptionsError('');
    try {
      const { data } = await axiosClient.get('/network/form-options');
      setOptions(data);
    } catch (err) {
      console.error('Failed to load form options:', err);
      setOptions(null);
      setOptionsError(
        err.response
          ? `Could not load the areas and CSCs: the server returned ${err.response.status}.`
          : 'Could not load the areas and CSCs. Check that Laravel is running on port 8000.'
      );
    }
  }, []);

  const openAdd = () => {
    setAddOpen(true);
    if (!options) loadOptions();
  };

  /* The report, not the raw dump. It opens with the province, then a
     block per area, then a block per CSC, each answering what is
     installed there and over how much line. The raw tables follow it in
     the same workbook for anyone who wants to pivot them. */
  const runExport = async () => {
    setExporting(true);
    try {
      const name = await downloadFromApi(
        '/network/report',
        'uva-network-asset-report.xlsx'
      );
      onToast?.(`Report downloaded: ${name}`);
    } catch (err) {
      setViewError(describeError(err));
    } finally {
      setExporting(false);
    }
  };

  /* Anything derived from segment_register is stale after a write, and
     the new rows are easiest to see in the Segments list. */
  const afterWrite = (message, { keepImportOpen = false } = {}) => {
    setAddOpen(false);
    /* An import keeps its dialog open. Closing it on success threw away
       the "How the file was read" and "Where it was filed" panels the
       moment they appeared, so nobody ever saw them. */
    if (!keepImportOpen) setImportOpen(false);
    onToast?.(message);

    // The dashboard's tiles and charts are stale too.
    onDataChanged?.();

    setCache((c) => {
      const next = { ...c };
      delete next.assetsByCsc;
      delete next.areas;
      delete next.cscs;
      delete next.feeders;
      delete next.assets;
      return next;
    });
    setSearch('');
    setSegmentRows(undefined);
    setView('segments');
  };

  const rows = useMemo(() => {
    if (view === 'segments') return segmentRows;

    if (view === 'assets' && placeActive) {
      if (cache.assetsByCsc === undefined) return undefined;

      // Per unit, never mixed: poles and kilometres stay separate rows.
      const byType = new Map();
      for (const r of cache.assetsByCsc.filter(inPlace)) {
        const key = `${r.asset_type_id}-${r.unit_of_measure}`;
        const agg = byType.get(key) || {
          asset_type_id: r.asset_type_id,
          type_name: r.type_name,
          category_name: r.category_name,
          unit_of_measure: r.unit_of_measure,
          total_quantity: 0,
          placements: 0,
          cscs: new Set(),
          areas: new Set(),
        };
        agg.total_quantity += num(r.total_quantity);
        agg.placements += num(r.placements);
        agg.cscs.add(r.csc_id);
        agg.areas.add(r.area_id);
        byType.set(key, agg);
      }

      return Array.from(byType.values()).map(({ cscs, areas, ...rest }) => ({
        ...rest,
        csc_count: cscs.size,
        area_count: areas.size,
      }));
    }

    const source = config.endpoint ? cache[view] : cscSummaryRows;
    if (!source || !placeActive) return source;
    return source.filter(inPlace);
  }, [view, segmentRows, placeActive, cache, config.endpoint, cscSummaryRows, inPlace]);

  const summary = useMemo(() => {
    if (!rows || rows.length === 0) return null;

    if (view === 'transformers') {
      const tx = rows.reduce((s, r) => s + num(r.transformers), 0);
      return `${formatNumber(tx)} transformers across ${rows.length} CSCs`;
    }

    if (view === 'assets') {
      const counted = rows
        .filter((r) => r.unit_of_measure === 'nos')
        .reduce((s, r) => s + num(r.total_quantity), 0);
      const km = rows
        .filter((r) => r.unit_of_measure === 'km')
        .reduce((s, r) => s + num(r.total_quantity), 0);
      return `${formatNumber(counted)} items and ${formatNumber(km, 2)} km, over ${
        rows.length
      } asset types`;
    }

    const km = rows.reduce((s, r) => s + num(r.total_km ?? r.length_km), 0);

    if (view === 'segments') {
      const crossing = rows.filter((r) => num(r.csc_count) > 1).length;
      const added = rows.filter((r) => ENTERED_SOURCES.includes(r.source_file));
      const addedKm = added.reduce((s, r) => s + num(r.length_km), 0);

      return `${formatNumber(km, 3)} km across ${formatNumber(rows.length)} segments${
        crossing > 0 ? `, ${formatNumber(crossing)} crossing` : ''
      }${
        added.length > 0
          ? `, ${formatNumber(addedKm, 3)} km added here`
          : ''
      }`;
    }

    if (view === 'feeders') {
      const segs = rows.reduce((s, r) => s + num(r.segment_count), 0);
      return `${formatNumber(km, 2)} km across ${formatNumber(segs)} segments`;
    }

    const crossings = rows.reduce((s, r) => s + num(r.crossing_count), 0);
    const label = view === 'areas' ? 'areas' : 'CSCs';

    return `${formatNumber(km, 2)} km across ${rows.length} ${label}${
      crossings > 0 ? `, ${formatNumber(crossings)} crossing a boundary` : ''
    }`;
  }, [rows, view]);

  return (
    <>
      <div className="register-toolbar">
        {placeActive && profile && (
          <div className="register-tabs register-mode" role="tablist" aria-label="How to show it">
            {[
              ['profile', 'Profile'],
              ['table', 'Table'],
            ].map(([key, label]) => (
              <button
                key={key}
                type="button"
                role="tab"
                aria-selected={mode === key}
                className={`register-tab${mode === key ? ' is-active' : ''}`}
                onClick={() => setMode(key)}
              >
                {label}
              </button>
            ))}
          </div>
        )}

        {!showProfile && (
        <div className="register-tabs" role="tablist" aria-label="Register view">
          {Object.entries(VIEWS).map(([key, v]) => (
            <button
              key={key}
              type="button"
              role="tab"
              aria-selected={view === key}
              className={`register-tab${view === key ? ' is-active' : ''}`}
              onClick={() => setView(key)}
            >
              {v.label}
            </button>
          ))}
        </div>
        )}

        <div className="register-toolbar-right">
          {config.searchable && !showProfile && (
            <input
              type="search"
              className="register-search"
              placeholder="Find a segment ID or CSC"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              aria-label="Search segments"
            />
          )}

          {summary && !showProfile && <span className="register-summary">{summary}</span>}

          {placeActive && (
            <span className="register-place-chip" title="Change this with the place filter above">
              {placeLabel}
            </span>
          )}

          {/* A greyed button with only a tooltip reads as broken. Say why
              it is off, where it will actually be seen. */}
          {!mayWrite && (
            <span className="register-readonly" title={writeBlockedReason}>
              Read only &middot; {user?.role || 'not signed in'}
            </span>
          )}

          <button
            type="button"
            className="dash-btn-quiet dash-btn-sm"
            onClick={runExport}
            disabled={exporting}
            title="Download the asset report: province, then each area, then each CSC"
          >
            {exporting ? 'Building...' : 'Report'}
          </button>

          <button
            type="button"
            className="dash-btn-quiet dash-btn-sm"
            onClick={() => setImportOpen(true)}
            disabled={!mayWrite}
            title={mayWrite ? 'Load a sheet of segments' : writeBlockedReason}
          >
            Import
          </button>

          <button
            type="button"
            className="dash-btn-primary dash-btn-sm"
            onClick={openAdd}
            disabled={!mayWrite}
            title={mayWrite ? 'Record a length of HV line' : writeBlockedReason}
          >
            + HV Length
          </button>
        </div>
      </div>

      {!showProfile && viewError && <div className="register-error">{viewError}</div>}

      {showProfile ? (
        profile
      ) : loadingView && rows === undefined ? (
        <div className="chart-empty">Loading {config.label.toLowerCase()}...</div>
      ) : (
        <DataTable
          columns={config.columns}
          rows={rows}
          rowKey={ROW_KEYS[view]}
          initialSortKey={config.sort}
          footerLabel={placeActive ? `Total · ${placeLabel}` : config.footerLabel}
          emptyMessage={
            view === 'segments' && search
              ? `Nothing matches "${search}".`
              : placeActive
              ? `Nothing recorded for ${placeLabel}.`
              : config.empty
          }
          isRowMuted={
            view === 'transformers'
              ? (r) => num(r.transformers) === 0
              : view === 'assets'
              ? (r) => num(r.total_quantity) === 0
              : (r) => num(r.total_km ?? r.length_km) === 0
          }
        />
      )}

      <AddSegmentDialog
        open={addOpen}
        options={options}
        optionsError={optionsError}
        onRetryOptions={loadOptions}
        onClose={() => setAddOpen(false)}
        onSaved={afterWrite}
      />

      <ImportDialog
        open={importOpen}
        onClose={() => setImportOpen(false)}
        onImported={(message) => afterWrite(message, { keepImportOpen: true })}
      />
    </>
  );
};

export default NetworkRegister;
