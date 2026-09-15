import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useLocation, useNavigate, useSearchParams } from 'react-router-dom';

import axiosClient from '../../api/axiosClient';
import DataTable from '../Dashboard/Components/DataTable';
import { toArray, num, pick, formatNumber, readUnits, readKva } from '../Dashboard/Components/data';
import NetworkRegister from '../Dashboard/Components/NetworkRegister';
import { downloadFromApi } from '../Dashboard/Components/fileTransfer';
import NotificationBell from '../Dashboard/Components/NotificationBell';

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
    if ((registerFocus || location.hash === '#register') && registerRef.current) {
      registerRef.current.scrollIntoView({ behavior: 'smooth', block: 'start' });
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

      {/* The answer, before the breakdown. */}
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

        <div className="summary-card accent-3">
          <span className="summary-label">CSCs</span>
          <span className="summary-value">{formatNumber(num(totals?.csc_count))}</span>
          <span className="summary-hint">Consumer service centres counted</span>
        </div>

        <div className="summary-card accent-4">
          <span className="summary-label">Areas</span>
          <span className="summary-value">{formatNumber(num(totals?.area_count))}</span>
          <span className="summary-hint">Operational areas counted</span>
        </div>

        <div className="summary-card accent-5">
          <span className="summary-label">Feeders</span>
          <span className="summary-value">{formatNumber(num(totals?.feeder_count))}</span>
          <span className="summary-hint">Feeders with recorded line</span>
        </div>
      </section>

      <section className="dashboard-card dashboard-table-card">
        <div className="card-header">
          <h2>
            {LEVELS.find((l) => l.key === level)?.label} breakdown
          </h2>
          <p>
            Length is the share inside each row, so a segment crossing a
            boundary is counted once in each place, for its own part only.
          </p>
        </div>

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
          />
        )}
      </section>

      <section
        className="dashboard-card dashboard-table-card hv-register"
        id="register"
        ref={registerRef}
      >
        <div className="card-header">
          <h2>Network Register</h2>
          <p>
            Every row at every level: transformers, areas, CSCs, feeders,
            segments and assets. Click a column heading to sort.
          </p>
        </div>

        {notice && <div className="dashboard-inline-notice">{notice}</div>}

        <NetworkRegister
          cscSummaryRows={cscSummaryRows}
          onToast={setNotice}
          focus={registerFocus}
          dataVersion={registerVersion}
          onDataChanged={() => {
            setRegisterVersion((v) => v + 1);
            load();
          }}
        />
      </section>
    </div>
  );
};

export default HvLength;
