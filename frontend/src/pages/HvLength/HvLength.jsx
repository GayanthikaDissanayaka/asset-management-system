import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom';

import axiosClient from '../../api/axiosClient';
import DataTable from '../Dashboard/Components/DataTable';
import { toArray, num, pick, formatNumber, readUnits, readKva } from '../Dashboard/Components/data';
import NetworkRegister from '../Dashboard/Components/NetworkRegister';
import { downloadFromApi } from '../Dashboard/Components/fileTransfer';
import NotificationBell from '../Dashboard/Components/NotificationBell';
import { useCurrentUser, canWriteNetwork } from '../Dashboard/Components/session';

import edlMark from '../Auth/edl-mark.png';

import '../Dashboard/Dashbord.css';
import './hv-length.css';

/*
 * HV line length, at whichever level you ask for.
 *
 * Everything comes from /network/hv-length, which reads the CSC share
 * view rather than the register directly. That matters: a segment
 * crossing a boundary contributes only its own portion to each CSC and
 * each area, so province, area and CSC totals all reconcile to the same
 * 3,441.31 km instead of drifting apart as the grouping changes.
 *
 * The filters narrow one query rather than switching between different
 * ones, so a number never changes meaning depending on what is selected.
 */

const LEVELS = [
  { key: 'province', label: 'Province' },
  { key: 'area', label: 'Area' },
  { key: 'csc', label: 'CSC' },
  { key: 'feeder', label: 'Feeder' },
];

const COLUMNS = {
  province: [
    { key: 'group_name', label: 'Province' },
    { key: 'csc_count', label: 'CSCs', numeric: true },
    { key: 'feeder_count', label: 'Feeders', numeric: true },
    { key: 'segment_count', label: 'Segments', numeric: true },
    { key: 'total_km', label: 'HV length km', numeric: true, decimals: 3, total: 'sum', share: true },
    { key: 'mean_km', label: 'Mean km', numeric: true, decimals: 3 },
    { key: 'longest_km', label: 'Longest km', numeric: true, decimals: 3 },
  ],
  area: [
    { key: 'group_name', label: 'Area', render: (r) => nameCell(r) },
    { key: 'csc_count', label: 'CSCs', numeric: true },
    { key: 'feeder_count', label: 'Feeders', numeric: true },
    { key: 'segment_count', label: 'Segments', numeric: true },
    { key: 'crossing_count', label: 'Crossing', numeric: true },
    { key: 'total_km', label: 'HV length km', numeric: true, decimals: 3, total: 'sum', share: true },
    { key: 'mean_km', label: 'Mean km', numeric: true, decimals: 3 },
  ],
  csc: [
    { key: 'group_name', label: 'CSC', render: (r) => nameCell(r) },
    { key: 'feeder_count', label: 'Feeders', numeric: true },
    { key: 'segment_count', label: 'Segments', numeric: true },
    { key: 'crossing_count', label: 'Crossing', numeric: true },
    { key: 'total_km', label: 'HV length km', numeric: true, decimals: 3, total: 'sum', share: true },
    { key: 'mean_km', label: 'Mean km', numeric: true, decimals: 3 },
    { key: 'longest_km', label: 'Longest km', numeric: true, decimals: 3 },
  ],
  feeder: [
    { key: 'group_name', label: 'Feeder', render: (r) => nameCell(r) },
    { key: 'csc_count', label: 'CSCs crossed', numeric: true },
    { key: 'segment_count', label: 'Segments', numeric: true },
    { key: 'total_km', label: 'HV length km', numeric: true, decimals: 3, total: 'sum', share: true },
    { key: 'mean_km', label: 'Mean km', numeric: true, decimals: 3 },
  ],
};

function nameCell(row) {
  return (
    <>
      <span className="depot-name">{row.group_name || 'Unassigned'}</span>
      {row.group_code && row.group_code !== row.group_name && (
        <span className="depot-code">{row.group_code}</span>
      )}
    </>
  );
}

const EMPTY_FILTERS = { provinceId: '', areaId: '', cscId: '', voltage: '' };

const HvLength = () => {
  const navigate = useNavigate();

  const [level, setLevel] = useState('area');

  /* One panel at a time. The breakdown and the full register were two
     tall cards stacked, so the page was mostly scrolling past the one
     you were not reading. */
  const [panel, setPanel] = useState('breakdown');

  /* Bumped by the header button; NetworkRegister opens its own dialog
     when this changes, so the dialog and its options loading stay in
     one place. */
  const [addSignal, setAddSignal] = useState(0);

  const user = useCurrentUser();
  const mayWrite = canWriteNetwork(user);
  const [filters, setFilters] = useState(EMPTY_FILTERS);
  const [options, setOptions] = useState({ provinces: [], areas: [], cscs: [] });
  const [voltages, setVoltages] = useState([]);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [exporting, setExporting] = useState(false);

  /* ------------------------------------------------ the full register
     Moved here from the dashboard, whose bottom card now describes a
     place instead. Every row, every level, with Report, Import and
     + HV Length. */
  const location = useLocation();
  const [searchParams] = useSearchParams();
  const registerRef = useRef(null);
  const [depotSummary, setDepotSummary] = useState([]);
  const [lineByCsc, setLineByCsc] = useState([]);
  const [registerVersion, setRegisterVersion] = useState(0);
  const [notice, setNotice] = useState('');

  useEffect(() => {
    Promise.all([
      axiosClient.get('/dashboard/depot-summary'),
      axiosClient.get('/network/length/by-csc'),
    ])
      .then(([depots, lengths]) => {
        setDepotSummary(depots.data || []);
        setLineByCsc(lengths.data || []);
      })
      .catch(() => {
        /* The register's own tabs still load; only Transformers needs these. */
      });
  }, [registerVersion]);

  useEffect(() => {
    if (!notice) return undefined;
    const t = setTimeout(() => setNotice(''), 6000);
    return () => clearTimeout(t);
  }, [notice]);

  const cscSummaryRows = useMemo(() => {
    const km = new Map(toArray(lineByCsc).map((r) => [String(r.csc_id), r.total_km]));
    return toArray(depotSummary).map((r) => ({
      id: pick(r, 'csc_id'),
      code: pick(r, 'csc_code') || '',
      name: pick(r, 'csc_name') || 'Unknown',
      area: pick(r, 'area_name') || '',
      transformers: readUnits(r),
      kva: readKva(r),
      networkKm: num(km.get(String(pick(r, 'csc_id')))),
      csc_id: pick(r, 'csc_id'),
      area_id: pick(r, 'area_id'),
      province_id: pick(r, 'province_id'),
    }));
  }, [depotSummary, lineByCsc]);

  /* A search result for a segment or feeder opens this page on the
     register, at the right tab, with the code already searched. */
  const registerFocus = useMemo(() => {
    const view = searchParams.get('register');
    const q = searchParams.get('q');
    return view || q ? { view, search: q || '' } : null;
  }, [searchParams]);

  useEffect(() => {
    if (registerFocus || location.hash === '#register') {
      // The register is a tab now, so arriving from a search result or
      // from the dashboard's "Full register" link has to select it —
      // scrolling to a panel that is not showing lands on nothing.
      setPanel('register');
      registerRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  }, [registerFocus, location.hash]);

  useEffect(() => {
    Promise.all([
      axiosClient.get('/network/form-options'),
      axiosClient.get('/network/voltage-levels'),
    ])
      .then(([opts, volts]) => {
        setOptions({
          provinces: opts.data?.provinces || [],
          areas: opts.data?.areas || [],
          cscs: opts.data?.cscs || [],
        });
        setVoltages(volts.data || []);
      })
      .catch(() => {
        /* The filters simply stay empty; the table still loads. */
      });
  }, []);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const { data: body } = await axiosClient.get('/network/hv-length', {
        params: {
          level,
          province_id: filters.provinceId || undefined,
          area_id: filters.areaId || undefined,
          csc_id: filters.cscId || undefined,
          voltage: filters.voltage || undefined,
        },
      });
      setData(body);
    } catch (err) {
      setError(
        err.response
          ? `The server returned ${err.response.status}.`
          : 'Could not reach the API. Check that Laravel is running on port 8000.'
      );
      setData(null);
    } finally {
      setLoading(false);
    }
  }, [level, filters]);

  useEffect(() => {
    load();
  }, [load]);

  /* Only CSCs in the chosen area, so the two filters cannot contradict
     each other and return nothing. */
  const cscChoices = useMemo(
    () =>
      options.cscs.filter(
        (c) => !filters.areaId || String(c.area_id) === String(filters.areaId)
      ),
    [options.cscs, filters.areaId]
  );

  const setFilter = (name, value) =>
    setFilters((f) => {
      const next = { ...f, [name]: value };
      if (name === 'provinceId') {
        next.areaId = '';
        next.cscId = '';
      }
      if (name === 'areaId') next.cscId = '';
      return next;
    });

  const totals = data?.totals;
  const filtered =
    Boolean(filters.provinceId || filters.areaId || filters.cscId || filters.voltage);

  /*
   * A row is a place, so selecting it goes into that place and drops the
   * grouping one level: the province table opens its areas, an area opens
   * its CSCs, a CSC opens its feeders. Feeder is the bottom — there is
   * nothing below a feeder to group by — so those rows are not clickable.
   *
   * This is the same movement as the filters above, done by pointing at
   * what you want instead of finding it in a dropdown.
   */
  const drillInto = (row) => {
    if (level === 'province') {
      setFilters((f) => ({ ...f, provinceId: String(row.group_id), areaId: '', cscId: '' }));
      setLevel('area');
      return;
    }
    if (level === 'area') {
      setFilters((f) => ({ ...f, areaId: String(row.group_id), cscId: '' }));
      setLevel('csc');
      return;
    }
    if (level === 'csc') {
      setFilters((f) => ({ ...f, cscId: String(row.group_id) }));
      setLevel('feeder');
    }
  };

  const goBack = () => {
    if (window.history.state?.idx > 0) navigate(-1);
    else navigate('/dashboard');
  };

  const runExport = async () => {
    setExporting(true);
    try {
      await downloadFromApi('/network/report', 'uva-network-asset-report.xlsx');
    } catch {
      setError('Could not build the report.');
    } finally {
      setExporting(false);
    }
  };

  return (
    <div className="dashboard-page hv-page">

      <header className="dashboard-header">
        <div className="dashboard-identity">
          <button type="button" className="dashboard-back" onClick={goBack}>
            &larr; Back
          </button>

          <img src={edlMark} alt="" className="dashboard-logo" width={32} height={32} />

          <div className="dashboard-titles">
            <h1>HV Length</h1>
            <p>CEB Uva Province &middot; province, area, CSC and feeder</p>
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

          {/* The one thing people come to this page to DO. It used to sit
              in the register's own toolbar at the very bottom, so adding
              a length meant scrolling past every table first. */}
          <button
            type="button"
            className="ax-add-button"
            onClick={() => {
              // Show the register too: what you just added appears there.
              setPanel('register');
              setAddSignal((n) => n + 1);
            }}
            disabled={!mayWrite}
            title={
              mayWrite
                ? 'Record a length of HV line'
                : 'Your role does not allow recording line. An administrator can widen your access.'
            }
          >
            + HV Length
          </button>

          <button
            className="refresh-button"
            onClick={load}
            disabled={loading}
          >
            {loading ? 'Loading...' : '↻ Refresh'}
          </button>
        </div>
      </header>

      {/* One filter row above everything it scopes, so every figure on
          the page is answering the same question. */}
      <section className="hv-filters">
        <div className="hv-filter">
          <span>Group by</span>
          <div className="register-tabs" role="tablist" aria-label="Grouping level">
            {LEVELS.map((l) => (
              <button
                key={l.key}
                type="button"
                role="tab"
                aria-selected={level === l.key}
                className={`register-tab${level === l.key ? ' is-active' : ''}`}
                onClick={() => setLevel(l.key)}
              >
                {l.label}
              </button>
            ))}
          </div>
        </div>

        <label className="hv-filter">
          <span>Province</span>
          <select
            value={filters.provinceId}
            onChange={(e) => setFilter('provinceId', e.target.value)}
          >
            <option value="">All provinces</option>
            {options.provinces.map((p) => (
              <option key={p.province_id} value={p.province_id}>
                {p.province_name}
              </option>
            ))}
          </select>
        </label>

        <label className="hv-filter">
          <span>Area</span>
          <select
            value={filters.areaId}
            onChange={(e) => setFilter('areaId', e.target.value)}
          >
            <option value="">All areas</option>
            {options.areas
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

        <label className="hv-filter">
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

        <label className="hv-filter">
          <span>Voltage</span>
          <select
            value={filters.voltage}
            onChange={(e) => setFilter('voltage', e.target.value)}
          >
            <option value="">All levels</option>
            {voltages.map((v) => (
              <option key={v} value={v}>{v}</option>
            ))}
          </select>
        </label>

        <div className="hv-filter hv-filter-actions">
          <button
            type="button"
            className="dash-btn-quiet dash-btn-sm"
            onClick={() => setFilters(EMPTY_FILTERS)}
            disabled={!filtered}
          >
            Clear filters
          </button>

          <button
            type="button"
            className="dash-btn-quiet dash-btn-sm"
            onClick={runExport}
            disabled={exporting}
          >
            {exporting ? 'Building...' : 'Report'}
          </button>
        </div>
      </section>

      {/* The answer, before the breakdown. The three tiles that name a
          level regroup the table below to it, so the summary is also the
          way into the detail. */}
      <section className="summary-cards hv-totals">
        <div className="summary-card accent-1">
          <span className="summary-label">HV Length</span>
          <span className="summary-value">
            {formatNumber(num(totals?.total_km), 2)} km
          </span>
          <span className="summary-hint">
            {filtered ? 'Matching the filters above' : 'Whole province'}
          </span>
        </div>

        <div className="summary-card accent-2">
          <span className="summary-label">Segments</span>
          <span className="summary-value">
            {formatNumber(num(totals?.distinct_segments))}
          </span>
          <span className="summary-hint">
            {num(totals?.crossing_count) > 0
              ? `${formatNumber(num(totals.crossing_count))} cross a CSC boundary`
              : 'None cross a boundary'}
          </span>
        </div>

        {[
          { key: 'csc', accent: 'accent-3', label: 'CSCs', value: totals?.csc_count, hint: 'Consumer service centres counted' },
          { key: 'area', accent: 'accent-4', label: 'Areas', value: totals?.area_count, hint: 'Operational areas counted' },
          { key: 'feeder', accent: 'accent-5', label: 'Feeders', value: totals?.feeder_count, hint: 'Feeders with recorded line' },
        ].map((tile) => (
          <button
            type="button"
            key={tile.key}
            className={`summary-card is-clickable ${tile.accent}${
              level === tile.key ? ' is-current' : ''
            }`}
            onClick={() => setLevel(tile.key)}
            title={`Group the table below by ${tile.label.toLowerCase()}`}
          >
            <span className="summary-label">
              {tile.label}
              <span className="summary-more" aria-hidden="true">
                {level === tile.key ? 'Shown below' : 'Group by →'}
              </span>
            </span>
            <span className="summary-value">{formatNumber(num(tile.value))}</span>
            <span className="summary-hint">{tile.hint}</span>
          </button>
        ))}
      </section>

      {/* ONE panel, not two stacked cards. The breakdown and the full
          register answer different questions and you are only ever
          asking one of them, so only one is on screen. */}
      <section
        className="dashboard-card dashboard-table-card hv-panel"
        id="register"
        ref={registerRef}
      >
        <div className="register-toolbar hv-panel-bar">
          <div className="register-tabs" role="tablist" aria-label="What to show">
            {[
              { key: 'breakdown', label: `${LEVELS.find((l) => l.key === level)?.label} breakdown` },
              { key: 'register', label: 'Network Register' },
            ].map((p) => (
              <button
                key={p.key}
                type="button"
                role="tab"
                aria-selected={panel === p.key}
                className={`register-tab${panel === p.key ? ' is-active' : ''}`}
                onClick={() => setPanel(p.key)}
              >
                {p.label}
              </button>
            ))}
          </div>

          <span className="register-summary hv-panel-hint">
            {panel === 'breakdown'
              ? `Share inside each row${level !== 'feeder' ? ' · select a row to open it' : ''}`
              : 'Every row at every level · click a heading to sort'}
          </span>
        </div>

        {notice && <div className="dashboard-inline-notice">{notice}</div>}

        {panel === 'breakdown' ? (
          <>
            {error && <div className="register-error">{error}</div>}

            {loading && !data ? (
              <div className="chart-empty">Loading HV length...</div>
            ) : (
              <DataTable
                columns={COLUMNS[level]}
                rows={data?.rows || []}
                rowKey={(r) => `${level}-${r.group_id}`}
                initialSortKey="total_km"
                footerLabel="Total"
                emptyMessage="Nothing matches these filters."
                isRowMuted={(r) => num(r.total_km) === 0}
                onRowClick={level === 'feeder' ? undefined : drillInto}
                rowTitle={
                  level === 'feeder'
                    ? undefined
                    : (r) => `Open ${r.group_name || 'this place'}`
                }
                maxHeight={360}
              />
            )}
          </>
        ) : null}

        {/* Kept mounted and hidden rather than unmounted, for two
            reasons: the header's "+ HV Length" needs it there to open
            its dialog, and switching tabs would otherwise throw away
            whatever was typed in the register's search box. */}
        <div hidden={panel !== 'register'}>
          <NetworkRegister
            openAddSignal={addSignal}
            cscSummaryRows={cscSummaryRows}
            onToast={setNotice}
            focus={registerFocus}
            dataVersion={registerVersion}
            onDataChanged={() => {
              setRegisterVersion((v) => v + 1);
              load();
            }}
          />
        </div>
      </section>
    </div>
  );
};

export default HvLength;
