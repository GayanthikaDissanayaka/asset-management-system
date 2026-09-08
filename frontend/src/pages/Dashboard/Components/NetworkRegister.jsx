import React, { useCallback, useEffect, useMemo, useState } from 'react';

import axiosClient from '../../../api/axiosClient';
import DataTable from './DataTable';
import AddSegmentDialog from './AddSegmentDialog';
import ImportDialog from './ImportDialog';
import { downloadFromApi } from './fileTransfer';
import { currentUser, canWriteNetwork } from './session';
import { num, formatNumber } from './data';

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
      { key: 'networkKm', label: 'Network km', numeric: true, decimals: 2, total: 'sum' },
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

const NetworkRegister = ({ cscSummaryRows, onToast }) => {
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

  /* Read once per mount. Hiding the buttons is a courtesy, not the gate:
     the API checks the same roles on every write. */
  const user = useMemo(() => currentUser(), []);
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

  /* Segments are fetched with the search term rather than cached, and the
     keystrokes are debounced so typing does not fire a request per
     letter. */
  const loadSegments = useCallback(async (term) => {
    setViewError('');
    setLoadingView(true);
    try {
      const { data } = await axiosClient.get('/network/segments', {
        params: { limit: 500, search: term || undefined },
      });
      setSegmentRows(data || []);
    } catch (err) {
      console.error('Failed to load segments:', err);
      setViewError(describeError(err));
      setSegmentRows([]);
    } finally {
      setLoadingView(false);
    }
  }, []);

  useEffect(() => {
    if (view !== 'segments') return undefined;
    const timer = setTimeout(() => loadSegments(search.trim()), search ? 350 : 0);
    return () => clearTimeout(timer);
  }, [view, search, loadSegments]);

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
  const afterWrite = (message) => {
    setAddOpen(false);
    setImportOpen(false);
    onToast?.(message);

    setCache((c) => {
      const next = { ...c };
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

  const rows =
    view === 'segments'
      ? segmentRows
      : config.endpoint
      ? cache[view]
      : cscSummaryRows;

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
      const entered = rows.filter((r) => ENTERED_SOURCES.includes(r.source_file)).length;
      return `${formatNumber(km, 3)} km across ${formatNumber(rows.length)} segments${
        crossing > 0 ? `, ${formatNumber(crossing)} crossing` : ''
      }${entered > 0 ? `, ${formatNumber(entered)} added here` : ''}`;
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

        <div className="register-toolbar-right">
          {config.searchable && (
            <input
              type="search"
              className="register-search"
              placeholder="Find a segment ID or CSC"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              aria-label="Search segments"
            />
          )}

          {summary && <span className="register-summary">{summary}</span>}

          <button
            type="button"
            className="btn-quiet btn-sm"
            onClick={runExport}
            disabled={exporting}
            title="Download the asset report: province, then each area, then each CSC"
          >
            {exporting ? 'Building...' : 'Report'}
          </button>

          <button
            type="button"
            className="btn-quiet btn-sm"
            onClick={() => setImportOpen(true)}
            disabled={!mayWrite}
            title={mayWrite ? 'Load a sheet of segments' : writeBlockedReason}
          >
            Import
          </button>

          <button
            type="button"
            className="btn-primary btn-sm"
            onClick={openAdd}
            disabled={!mayWrite}
            title={mayWrite ? 'Record a new segment' : writeBlockedReason}
          >
            + Add segment
          </button>
        </div>
      </div>

      {viewError && <div className="register-error">{viewError}</div>}

      {loadingView && rows === undefined ? (
        <div className="chart-empty">Loading {config.label.toLowerCase()}...</div>
      ) : (
        <DataTable
          columns={config.columns}
          rows={rows}
          rowKey={ROW_KEYS[view]}
          initialSortKey={config.sort}
          footerLabel={config.footerLabel}
          emptyMessage={
            view === 'segments' && search
              ? `Nothing matches "${search}".`
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
        onImported={afterWrite}
      />
    </>
  );
};

export default NetworkRegister;
