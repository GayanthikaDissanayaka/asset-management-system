import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import axiosClient from '../../api/axiosClient';

import SummaryCards from './Components/SummaryCards';
import DataTable from './Components/DataTable';
import AreaChart from './Components/AreaChart';
import AssetCategoryChart from './Components/AssetCategoryChart';
import TransformerPlaceChart from './Components/TransformerPlaceChart';
import PlaceProfile from './Components/PlaceProfile';
import TileDetailDialog from './Components/TileDetailDialog';
import NotificationBell from './Components/NotificationBell';
import PlaceFilter, {
  isPlaceSet,
  placeParams,
  describePlace,
  completePlace,
} from './Components/PlaceFilter';
import TransformerMixChart from './Components/TransformerMixChart';
import ApprovalsDialog from './Components/ApprovalsDialog';
import GlobalSearch from './Components/GlobalSearch';
import { toArray, num, pick, readUnits, readKva, readAreaName } from './Components/data';
import { useCurrentUser, canWriteNetwork } from './Components/session';
import ImportDialog from './Components/ImportDialog';

import edlMark from '../Auth/edl-mark.png';

import './Dashbord.css';

/* Small inline icon set so the sidebar doesn't need a new dependency.
   Each is 20x20, inherits color via currentColor, and stroke-based to
   match a typical nav icon weight. */
const Icon = {
  Assets: (props) => (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <rect x="3" y="3" width="7" height="7" rx="1.5" />
      <rect x="14" y="3" width="7" height="7" rx="1.5" />
      <rect x="3" y="14" width="7" height="7" rx="1.5" />
      <rect x="14" y="14" width="7" height="7" rx="1.5" />
    </svg>
  ),
  Length: (props) => (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="M4 19 19 4" />
      <path d="M4 19h4" />
      <path d="M4 19v-4" />
      <path d="M19 4h-4" />
      <path d="M19 4v4" />
    </svg>
  ),
  Reports: (props) => (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="M6 3h9l5 5v13a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z" />
      <path d="M9 13h6" />
      <path d="M9 17h6" />
      <path d="M9 9h2" />
    </svg>
  ),
  Import: (props) => (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="M12 3v12" />
      <path d="M7 10l5 5 5-5" />
      <path d="M5 21h14" />
    </svg>
  ),
  Approvals: (props) => (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="M9 12l2 2 4-4" />
      <circle cx="12" cy="12" r="9" />
    </svg>
  ),
  Logout: (props) => (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="M9 21H5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h4" />
      <path d="M16 17l5-5-5-5" />
      <path d="M21 12H9" />
    </svg>
  ),
  Refresh: (props) => (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" {...props}>
      <path d="M21 12a9 9 0 1 1-2.64-6.36" />
      <path d="M21 4v6h-6" />
    </svg>
  ),
};

const Dashboard = () => {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();

  const [areaTotals, setAreaTotals] = useState([]);
  const [capacityMix, setCapacityMix] = useState([]);
  const [depotSummary, setDepotSummary] = useState([]);
  const [lineLengths, setLineLengths] = useState([]);
  const [assetCategories, setAssetCategories] = useState([]);
  const [lineByCsc, setLineByCsc] = useState([]);
  const [placeOptions, setPlaceOptions] = useState(null);

  const [place, setPlace] = useState(() => ({
    provinceId: searchParams.get('province_id') || '',
    areaId: searchParams.get('area_id') || '',
    cscId: searchParams.get('csc_id') || '',
  }));

  const [dataVersion, setDataVersion] = useState(0);
  const [quietTick, setQuietTick] = useState(0);

  const [pendingCount, setPendingCount] = useState(0);
  const [bellKey, setBellKey] = useState(0);

  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const [welcome, setWelcome] = useState(null);
  const [approvalsOpen, setApprovalsOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);

  const [tileOpen, setTileOpen] = useState(null);

  /* The one panel below the tiles. Overview first — the shape of the
     province in three charts — with everything else a tab away rather
     than further down the page. */
  const [mainTab, setMainTab] = useState('overview');

  /* Within Overview, the three panels read either as charts or as the
     tables they are drawn from. Charts first, because the first thing
     anyone wants from a dashboard is the shape; the table is one click
     away for whoever needs the figures themselves. */
  const [panelView, setPanelView] = useState('charts');

  /* The sidebar collapses to a compact rail under 1180px and to an
     off-canvas drawer under 820px; this tracks whether the drawer is
     open on small screens. */
  const [navOpen, setNavOpen] = useState(false);

  const currentUser = useCurrentUser();
  const isAdmin = currentUser?.role === 'ADMIN';
  const mayWrite = canWriteNetwork(currentUser);

  const loadDashboardData = useCallback(async (mode = false) => {
    try {
      if (mode === true) setRefreshing(true);
      setError('');

      /*
       * ONE request, not five.
       *
       * Promise.all looks parallel and is, in the browser. The dev
       * backend is not: `php artisan serve` is PHP's built-in server
       * and handles one request at a time, so five "parallel" calls
       * became five Laravel boots in a row while the page sat empty.
       * /dashboard/bootstrap returns all five datasets from one boot.
       */
      const { data } = await axiosClient.get('/dashboard/bootstrap');

      setAreaTotals(data.area_totals || []);
      setCapacityMix(data.capacity_mix || []);
      setDepotSummary(data.depot_summary || []);
      setLineLengths(data.length_by_area || []);
      setLineByCsc(data.length_by_csc || []);
      setLoaded(true);

      if (mode !== 'quiet') setDataVersion((v) => v + 1);
    } catch (err) {
      console.error('Dashboard API Error:', err);

      if (err.response) {
        console.error('Status:', err.response.status);
        console.error('Response:', err.response.data);
      }

      setError(
        err.response?.data?.message ||
          (err.response
            ? `The server returned ${err.response.status}.`
            : 'Could not reach the API. Check that Laravel is running on port 8000.')
      );
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    loadDashboardData(false);
  }, [loadDashboardData]);

  useEffect(() => {
    const quiet = () => {
      if (document.visibilityState !== 'visible') return;
      loadDashboardData('quiet');
      setQuietTick((t) => t + 1);
    };

    const timer = setInterval(quiet, 60000);
    window.addEventListener('focus', quiet);

    return () => {
      clearInterval(timer);
      window.removeEventListener('focus', quiet);
    };
  }, [loadDashboardData]);

  const onDataChanged = useCallback(() => {
    loadDashboardData(true);
  }, [loadDashboardData]);

  useEffect(() => {
    axiosClient
      .get('/network/form-options')
      .then(({ data }) => setPlaceOptions(data))
      .catch(() => setPlaceOptions({ provinces: [], areas: [], cscs: [] }));
  }, []);

  useEffect(() => {
    let cancelled = false;

    axiosClient
      .get('/network/assets/catalog', {
        params: placeParams({
          provinceId: place.provinceId,
          areaId: place.areaId,
          cscId: place.cscId,
        }),
      })
      .then(({ data }) => {
        if (!cancelled) setAssetCategories(data || []);
      })
      .catch(() => {
        if (!cancelled) setAssetCategories([]);
      });

    return () => {
      cancelled = true;
    };
  }, [place.provinceId, place.areaId, place.cscId, dataVersion, quietTick]);

  useEffect(() => {
    const fromUrl = {
      provinceId: searchParams.get('province_id') || '',
      areaId: searchParams.get('area_id') || '',
      cscId: searchParams.get('csc_id') || '',
    };
    if (isPlaceSet(fromUrl)) setPlace(fromUrl);

    if (searchParams.get('approvals') === 'open' && isAdmin) setApprovalsOpen(true);
  }, [searchParams, isAdmin]);

  const changePlace = useCallback(
    (next) => {
      setPlace(next);
      const params = {};
      if (next.provinceId) params.province_id = next.provinceId;
      if (next.areaId) params.area_id = next.areaId;
      if (next.cscId) params.csc_id = next.cscId;
      setSearchParams(params, { replace: true });
    },
    [setSearchParams]
  );

  useEffect(() => {
    if (!notice) return undefined;
    const t = setTimeout(() => setNotice(''), 5000);
    return () => clearTimeout(t);
  }, [notice]);

  useEffect(() => {
    let greeting = null;

    try {
      const raw = sessionStorage.getItem('ceb_welcome');
      if (raw) {
        greeting = JSON.parse(raw);
        sessionStorage.removeItem('ceb_welcome');
      }
    } catch {
      // Private windows and cleared site data both land here.
    }

    if (greeting && Date.now() - (greeting.at || 0) < 60_000) {
      setWelcome(greeting.name || '');
    }
  }, []);

  useEffect(() => {
    if (welcome === null) return undefined;
    const t = setTimeout(() => setWelcome(null), 9000);
    return () => clearTimeout(t);
  }, [welcome]);

  // Close the mobile nav drawer whenever the viewport grows back past
  // the breakpoint, so it never gets stuck open on rotate/resize.
  useEffect(() => {
    const onResize = () => {
      if (window.innerWidth > 820) setNavOpen(false);
    };
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  const placeActive = isPlaceSet(place);
  const scopeLabel = placeActive ? describePlace(place, placeOptions) : '';

  const profilePlace = useMemo(() => {
    const chosen = completePlace(place, placeOptions);
    if (isPlaceSet(chosen)) return chosen;
    const first = placeOptions?.provinces?.[0];
    return first ? { provinceId: String(first.province_id), areaId: '', cscId: '' } : chosen;
  }, [place, placeOptions]);

  const areaById = useMemo(
    () => new Map((placeOptions?.areas || []).map((a) => [String(a.area_id), a])),
    [placeOptions]
  );
  const cscById = useMemo(
    () => new Map((placeOptions?.cscs || []).map((c) => [String(c.csc_id), c])),
    [placeOptions]
  );

  const matchPlace = useCallback(
    (r) => {
      if (!placeActive) return true;

      const csc = pick(r, 'csc_id');
      const hasCsc = csc !== undefined && csc !== null;
      const areaId = pick(r, 'area_id') ?? (hasCsc ? cscById.get(String(csc))?.area_id : undefined);
      const hasArea = areaId !== undefined && areaId !== null;
      const provinceId =
        pick(r, 'province_id') ?? (hasArea ? areaById.get(String(areaId))?.province_id : undefined);

      if (place.cscId) return hasCsc && String(csc) === String(place.cscId);
      if (place.areaId) return hasArea && String(areaId) === String(place.areaId);
      return (
        provinceId !== undefined &&
        provinceId !== null &&
        String(provinceId) === String(place.provinceId)
      );
    },
    [placeActive, place.cscId, place.areaId, place.provinceId, cscById, areaById]
  );

  const shownDepotSummary = useMemo(
    () => toArray(depotSummary).filter(matchPlace),
    [depotSummary, matchPlace]
  );
  const shownMix = useMemo(
    () => toArray(capacityMix).filter(matchPlace),
    [capacityMix, matchPlace]
  );
  const shownAreaTotals = useMemo(
    () => toArray(areaTotals).filter(matchPlace),
    [areaTotals, matchPlace]
  );
  const shownLengths = useMemo(() => {
    if (place.cscId) {
      return toArray(lineByCsc).filter((r) => String(r.csc_id) === String(place.cscId));
    }
    return toArray(lineLengths).filter(matchPlace);
  }, [place.cscId, lineByCsc, lineLengths, matchPlace]);

  const focusAreaId =
    place.areaId ||
    (place.cscId ? String(cscById.get(String(place.cscId))?.area_id ?? '') : '');
  const focusAreaName = focusAreaId ? areaById.get(String(focusAreaId))?.area_name : '';

  const areaCscRows = useMemo(() => {
    if (!focusAreaId) return [];
    return toArray(depotSummary)
      .filter((r) => String(pick(r, 'area_id')) === String(focusAreaId))
      .map((r) => ({
        key: pick(r, 'csc_id'),
        label: pick(r, 'csc_name') || 'Unknown',
        value: readUnits(r),
      }));
  }, [depotSummary, focusAreaId]);

  /* ------------------------------------------- the panels, as tables
     The same numbers the three charts draw. Built here rather than
     inside the chart components so the table and the chart can never
     disagree: one set of rows, two ways of reading it. */

  const placeTableRows = useMemo(() => {
    if (focusAreaId) {
      return areaCscRows.map((r) => ({
        key: `csc-${r.key}`,
        id: r.key,
        name: r.label,
        units: r.value,
      }));
    }

    return toArray(shownAreaTotals).map((r) => ({
      key: `area-${pick(r, 'area_id')}`,
      id: pick(r, 'area_id'),
      name: readAreaName(r),
      units: readUnits(r),
      kva: readKva(r),
    }));
  }, [focusAreaId, areaCscRows, shownAreaTotals]);

  const categoryTableRows = useMemo(
    () =>
      toArray(assetCategories).map((cat) => ({
        key: `cat-${cat.category_id}`,
        name: cat.category_name,
        counted: num(
          (cat.by_unit || []).find((u) => u.unit_of_measure === 'nos')?.quantity
        ),
        km: num(
          (cat.by_unit || []).find((u) => u.unit_of_measure === 'km')?.quantity
        ),
        records: num(cat.records),
      })),
    [assetCategories]
  );

  const typeTableRows = useMemo(() => {
    const m = new Map();
    for (const r of toArray(shownMix)) {
      const type = pick(r, 'transformer_type') || 'Unspecified';
      const cur = m.get(type) || { units: 0, kva: 0 };
      cur.units += num(pick(r, 'unit_count', 'transformer_units'));
      cur.kva += num(pick(r, 'installed_kva'));
      m.set(type, cur);
    }
    return Array.from(m, ([name, v]) => ({
      key: `t-${name}`,
      name,
      units: v.units,
      kva: v.kva,
    })).filter((r) => r.units > 0);
  }, [shownMix]);

  /* A CSC has no places inside it, so that tab is absent there rather
     than present and empty. If the tab in hand is one this place does
     not offer — you were looking at CSCs and then opened one — Overview
     stands in. */
  const profileLevel = profilePlace.cscId
    ? 'csc'
    : profilePlace.areaId
    ? 'area'
    : 'province';

  const mainTabs = useMemo(
    () =>
      [
        { key: 'overview', label: 'Overview' },
        profileLevel !== 'csc' && {
          key: 'places',
          label: profileLevel === 'province' ? 'Areas' : 'CSCs',
        },
        { key: 'feeders', label: 'Feeders' },
        { key: 'assets', label: 'Assets held' },
        { key: 'segments', label: 'Segments' },
      ].filter(Boolean),
    [profileLevel]
  );

  useEffect(() => {
    if (!mainTabs.some((t) => t.key === mainTab)) setMainTab('overview');
  }, [mainTabs, mainTab]);

  const goBack = () => {
    if (window.history.state?.idx > 0) {
      navigate(-1);
    } else {
      navigate('/');
    }
  };

  const handleLogout = async () => {
    try {
      await axiosClient.post('/auth/logout');
    } catch {
      // The UI still logs the user out even if the API call fails.
    }

    localStorage.removeItem('ceb_token');
    localStorage.removeItem('ceb_user');
    sessionStorage.removeItem('ceb_token');
    sessionStorage.removeItem('ceb_user');

    navigate('/', { replace: true });
  };

  if (loading) {
    return (
      <div className="dashboard-page dashboard-page-centred">
        <div className="dashboard-loading">
          <div className="loading-spinner" />
          <p>Loading dashboard...</p>
        </div>
      </div>
    );
  }

  if (error && !loaded) {
    return (
      <div className="dashboard-page dashboard-page-centred">
        <div className="dashboard-error">
          <h3>Unable to load dashboard</h3>
          <p>{error}</p>

          <div className="dashboard-error-actions">
            <button onClick={() => loadDashboardData(true)}>Try Again</button>
            <button type="button" className="dashboard-error-back" onClick={goBack}>
              &larr; Back
            </button>
          </div>
        </div>
      </div>
    );
  }

  const navItems = [
    { key: 'assets', label: 'Assets', icon: Icon.Assets, onClick: () => navigate('/assets'), title: 'Every asset the province holds, and one transformer in detail' },
    { key: 'length', label: 'HV Length', icon: Icon.Length, onClick: () => navigate('/hv-length'), title: 'HV length by province, area, CSC and feeder' },
    { key: 'reports', label: 'Reports', icon: Icon.Reports, onClick: () => navigate('/reports'), title: 'Build a report, download it, or keep a dated copy in the project' },
    {
      key: 'import',
      label: 'Import',
      icon: Icon.Import,
      onClick: () => setImportOpen(true),
      disabled: !mayWrite,
      title: mayWrite
        ? 'Load a spreadsheet of segments'
        : 'Your role cannot load data. An administrator can widen your access.',
    },
  ];

  if (isAdmin) {
    navItems.push({
      key: 'approvals',
      label: 'Approvals',
      icon: Icon.Approvals,
      onClick: () => setApprovalsOpen(true),
      badge: pendingCount > 0 ? pendingCount : null,
      title:
        pendingCount > 0
          ? `${pendingCount} access request${pendingCount === 1 ? '' : 's'} waiting`
          : 'Give a signed-up user their role and depot',
    });
  }

  return (
    <div className={`dashboard-page${refreshing ? ' is-refreshing' : ''}`}>
      {/* ================= HEADER ================= */}
      <header className="dashboard-header">
        <div className="dashboard-identity">
          <button
            type="button"
            className="dashboard-back"
            onClick={goBack}
          >
            &larr; Back
          </button>

          {/* Mobile-only nav toggle for the sidebar drawer. */}
          <button
            type="button"
            className="dashboard-nav-toggle"
            onClick={() => setNavOpen((o) => !o)}
            aria-label="Toggle menu"
            aria-expanded={navOpen}
          >
            <span />
            <span />
            <span />
          </button>

          <img
            src={edlMark}
            alt=""
            className="dashboard-logo"
            width={32}
            height={32}
          />

          <div className="dashboard-titles">
            <h1>Dashboard</h1>
            <p>CEB Uva Province &middot; Network Asset Management</p>
          </div>
        </div>

        {/* Search and refresh sit together, since refreshing is the
            other thing someone reaches for right after searching. */}
        <div className="dashboard-header-tools">
          <GlobalSearch />

          <button
            className="refresh-button refresh-button-header"
            onClick={() => loadDashboardData(true)}
            disabled={refreshing}
            title="Refresh dashboard data"
          >
            <Icon.Refresh className={refreshing ? 'is-spinning' : ''} />
            <span>{refreshing ? 'Refreshing...' : 'Refresh'}</span>
          </button>

          <div className="dashboard-notify-box">
            <NotificationBell
              onReview={() => setApprovalsOpen(true)}
              onCount={setPendingCount}
              refreshKey={bellKey}
            />
          </div>
        </div>
      </header>

      {navOpen && (
        <div className="dashboard-nav-scrim" onClick={() => setNavOpen(false)} />
      )}

      <div className="dashboard-shell">
        <aside className={`dashboard-sidebar${navOpen ? ' is-open' : ''}`}>
          {(notice || error) && (
            <div className="sidebar-status">
              {notice && (
                <span className="dashboard-inline-notice" role="status">
                  {notice}
                </span>
              )}
              {error && (
                <span className="dashboard-inline-error" role="status">
                  Refresh failed
                </span>
              )}
            </div>
          )}

          <nav className="sidebar-nav" aria-label="Dashboard sections">
            {navItems.map((item) => {
              const ItemIcon = item.icon;
              return (
                <button
                  key={item.key}
                  type="button"
                  className="sidebar-nav-item"
                  onClick={() => {
                    item.onClick();
                    setNavOpen(false);
                  }}
                  disabled={item.disabled}
                  title={item.title}
                >
                  <span className="sidebar-nav-icon">
                    <ItemIcon />
                  </span>
                  <span className="sidebar-nav-label">{item.label}</span>
                  {item.badge ? (
                    <span className="sidebar-nav-badge">{item.badge}</span>
                  ) : null}
                </button>
              );
            })}
          </nav>

          <div className="sidebar-footer">
            <button
              type="button"
              className="sidebar-nav-item sidebar-logout"
              onClick={handleLogout}
              title="Log out"
            >
              <span className="sidebar-nav-icon">
                <Icon.Logout />
              </span>
              <span className="sidebar-nav-label">Log out</span>
            </button>
          </div>
        </aside>

        <div className="dashboard-main">
          <div className="dashboard-subbar">
            <PlaceFilter
              options={placeOptions}
              value={completePlace(place, placeOptions)}
              onChange={changePlace}
            />

            <span className="dashboard-scope" aria-live="polite">
              {placeActive ? (
                <>
                  Showing <strong>{scopeLabel}</strong>
                </>
              ) : (
                'Showing the whole province'
              )}
            </span>

            {welcome !== null && (
              <div className="dashboard-welcome dashboard-welcome-inline" role="status">
                <span className="dashboard-welcome-text">
                  Welcome to the CEB Asset Management System
                  {welcome ? (
                    <>
                      , <strong>{welcome}</strong>.
                    </>
                  ) : (
                    '.'
                  )}
                </span>

                <button
                  type="button"
                  className="dashboard-welcome-close"
                  onClick={() => setWelcome(null)}
                  aria-label="Dismiss"
                >
                  &times;
                </button>
              </div>
            )}
          </div>

          <SummaryCards
            cscSummary={shownDepotSummary}
            lineLengths={shownLengths}
            scopeLabel={scopeLabel}
            onOpen={setTileOpen}
          />

          {/* ONE panel below the tiles, not a row of charts and then a
              second card of tables. Between them they made the dashboard
              something you scrolled through rather than looked at, and
              only ever one of them was the thing being asked about. */}
          <section className="dashboard-card dashboard-panel">
            <div className="register-toolbar">
              <div className="register-tabs" role="tablist" aria-label="Dashboard detail">
                {mainTabs.map((t) => (
                  <button
                    key={t.key}
                    type="button"
                    role="tab"
                    aria-selected={mainTab === t.key}
                    className={`register-tab${mainTab === t.key ? ' is-active' : ''}`}
                    onClick={() => setMainTab(t.key)}
                  >
                    {t.label}
                  </button>
                ))}
              </div>

              <div className="register-toolbar-right">
                {mainTab === 'overview' && (
                  <div className="register-tabs" role="tablist" aria-label="How to show the overview">
                    {[
                      { key: 'charts', label: 'Charts' },
                      { key: 'tables', label: 'Tables' },
                    ].map((option) => (
                      <button
                        key={option.key}
                        type="button"
                        role="tab"
                        aria-selected={panelView === option.key}
                        className={`register-tab${panelView === option.key ? ' is-active' : ''}`}
                        onClick={() => setPanelView(option.key)}
                      >
                        {option.label}
                      </button>
                    ))}
                  </div>
                )}

                <button
                  type="button"
                  className="dash-btn-quiet dash-btn-sm"
                  onClick={() => navigate('/hv-length#register')}
                  title="Every row of the register, with Report, Import and + HV Length"
                >
                  Full register &rarr;
                </button>
              </div>
            </div>

            {mainTab !== 'overview' ? (
              <PlaceProfile
                place={profilePlace}
                placeOptions={placeOptions}
                depotSummary={depotSummary}
                lineLengths={lineLengths}
                lineByCsc={lineByCsc}
                assetCategories={assetCategories}
                dataVersion={dataVersion}
                onPickPlace={changePlace}
                tab={mainTab}
              />
            ) : (
              <div className={`dashboard-charts${panelView === 'tables' ? ' is-tables' : ''}`}>
                <section className="dashboard-panel-cell">
                  {focusAreaId ? (
                    <>
                      <div className="card-header">
                        <h2>Transformers by CSC</h2>
                        <p>
                          CSCs in {focusAreaName || 'this'} area
                          {place.cscId ? ' — the chosen CSC highlighted' : ''}
                        </p>
                      </div>

                      {panelView === 'charts' ? (
                        <TransformerPlaceChart
                          rows={areaCscRows}
                          highlightKey={place.cscId}
                          emptyMessage="No transformers recorded in this area."
                          onPick={(cscId) =>
                            changePlace(
                              completePlace({ provinceId: '', areaId: '', cscId: String(cscId) }, placeOptions)
                            )
                          }
                        />
                      ) : (
                        <DataTable
                          columns={[
                            { key: 'name', label: 'CSC' },
                            { key: 'units', label: 'Transformers', numeric: true, total: 'sum', share: true },
                          ]}
                          rows={placeTableRows}
                          rowKey={(r) => r.key}
                          initialSortKey="units"
                          footerLabel="Total"
                          emptyMessage="No transformers recorded in this area."
                          dense
                          maxHeight={178}
                          isRowActive={(r) => String(r.id) === String(place.cscId)}
                          isRowMuted={(r) => r.units === 0}
                          onRowClick={(r) =>
                            changePlace(
                              completePlace({ provinceId: '', areaId: '', cscId: String(r.id) }, placeOptions)
                            )
                          }
                          rowTitle={(r) => `Open ${r.name}`}
                        />
                      )}
                    </>
                  ) : (
                    <>
                      <div className="card-header">
                        <h2>Transformers by Area</h2>
                        <p>Units recorded in each operational area</p>
                      </div>

                      {panelView === 'charts' ? (
                        <AreaChart
                          data={shownAreaTotals}
                          onPick={(areaId) =>
                            changePlace(
                              completePlace({ provinceId: '', areaId: String(areaId), cscId: '' }, placeOptions)
                            )
                          }
                        />
                      ) : (
                        <DataTable
                          columns={[
                            { key: 'name', label: 'Area' },
                            { key: 'units', label: 'Transformers', numeric: true, total: 'sum', share: true },
                            { key: 'kva', label: 'kVA', numeric: true, total: 'sum' },
                          ]}
                          rows={placeTableRows}
                          rowKey={(r) => r.key}
                          initialSortKey="units"
                          footerLabel="Total"
                          emptyMessage="No transformers recorded."
                          dense
                          maxHeight={178}
                          isRowMuted={(r) => r.units === 0}
                          onRowClick={(r) =>
                            changePlace(
                              completePlace({ provinceId: '', areaId: String(r.id), cscId: '' }, placeOptions)
                            )
                          }
                          rowTitle={(r) => `Open ${r.name}`}
                        />
                      )}
                    </>
                  )}
                </section>

                <section className="dashboard-panel-cell">
                  <div className="card-header">
                    <h2>Assets by Category</h2>
                    <p>
                      {placeActive
                        ? `Counted items in ${scopeLabel}`
                        : 'Counted items; conductor and line are km, on the Assets page'}
                    </p>
                  </div>

                  {panelView === 'charts' ? (
                    <AssetCategoryChart data={assetCategories} />
                  ) : (
                    <DataTable
                      columns={[
                        { key: 'name', label: 'Main asset' },
                        { key: 'counted', label: 'Counted nos', numeric: true, total: 'sum' },
                        { key: 'km', label: 'Line km', numeric: true, decimals: 2, total: 'sum' },
                        { key: 'records', label: 'Records', numeric: true, total: 'sum' },
                      ]}
                      rows={categoryTableRows}
                      rowKey={(r) => r.key}
                      initialSortKey="counted"
                      footerLabel="Total"
                      emptyMessage="No assets recorded here."
                      dense
                      maxHeight={178}
                      isRowMuted={(r) => r.records === 0}
                      onRowClick={() => navigate('/assets')}
                      rowTitle={() => 'Open the Assets page'}
                    />
                  )}
                </section>

                <section className="dashboard-panel-cell">
                  <div className="card-header">
                    <h2>Transformer Types</h2>
                    <p>
                      {placeActive
                        ? `Transformer types in ${scopeLabel}`
                        : 'How the units split between distribution, bulk and generation'}
                    </p>
                  </div>

                  {panelView === 'charts' ? (
                    <TransformerMixChart data={shownMix} />
                  ) : (
                    <DataTable
                      columns={[
                        { key: 'name', label: 'Type' },
                        { key: 'units', label: 'Units', numeric: true, total: 'sum', share: true },
                        { key: 'kva', label: 'Installed kVA', numeric: true, total: 'sum' },
                      ]}
                      rows={typeTableRows}
                      rowKey={(r) => r.key}
                      initialSortKey="units"
                      footerLabel="All types"
                      emptyMessage="No transformers recorded here."
                      dense
                      maxHeight={178}
                    />
                  )}
                </section>
              </div>
            )}
          </section>
        </div>
      </div>

      <ApprovalsDialog
        open={approvalsOpen}
        onClose={() => {
          setApprovalsOpen(false);
          if (searchParams.get('approvals')) {
            const next = new URLSearchParams(searchParams);
            next.delete('approvals');
            setSearchParams(next, { replace: true });
          }
        }}
        onChanged={(message) => {
          setNotice(message);
          setBellKey((k) => k + 1);
        }}
      />

      <TileDetailDialog
        kind={tileOpen}
        onClose={() => setTileOpen(null)}
        scopeLabel={scopeLabel}
        place={completePlace(place, placeOptions)}
        placeOptions={placeOptions}
        depotRows={shownDepotSummary}
        mixRows={shownMix}
        lineLengths={lineLengths}
        lineByCsc={lineByCsc}
        onPickPlace={changePlace}
      />

      <ImportDialog
        open={importOpen}
        onClose={() => setImportOpen(false)}
        onImported={(message) => {
          setNotice(message);
          onDataChanged();
        }}
      />
    </div>
  );
};

export default Dashboard;