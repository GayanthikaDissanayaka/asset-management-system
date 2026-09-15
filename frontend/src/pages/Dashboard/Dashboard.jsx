import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import axiosClient from '../../api/axiosClient';

import SummaryCards from './Components/SummaryCards';
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
import { toArray, pick, readUnits } from './Components/data';
import { useCurrentUser, canWriteNetwork } from './Components/session';
import ImportDialog from './Components/ImportDialog';

import edlMark from '../Auth/edl-mark.png';

import './Dashbord.css';

/*
 * Everything on this page comes from MySQL views in ceb_uva_ams, served
 * by DashboardController.
 *
 *   transformer-area-totals    v_transformer_totals_by_area
 *   transformer-capacity-mix   v_transformer_capacity_mix
 *   depot-summary              v_depot_dashboard
 *   network/length/by-area     v_line_length_by_area
 *   network/assets/catalog     v_asset_register
 *   network/length/by-csc      v_line_length_by_csc
 *   network/form-options       provinces, areas and CSCs for the place filter
 *
 * The dashboard leads with transformers because they are the province's
 * largest single register, but it no longer ONLY shows transformers.
 * It used to chart transformer counts twice -- by area and by CSC --
 * which was the same measure at two levels, while the switchgear, poles,
 * substations and plant went unmentioned. The second card now shows
 * those instead; the per-CSC transformer figures are still in the
 * register table below and on the Assets page.
 *
 * UNITS ARE NEVER MIXED anywhere on this page. asset_types counts
 * switchgear in `nos` and measures conductor in `km`, and no tile or bar
 * here adds the two together.
 */
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

  /* The place the whole dashboard is narrowed to. Read from the address
     bar, so a search result, a bookmark or a shared link opens straight
     onto that area or CSC. */
  const [place, setPlace] = useState(() => ({
    provinceId: searchParams.get('province_id') || '',
    areaId: searchParams.get('area_id') || '',
    cscId: searchParams.get('csc_id') || '',
  }));

  /* Bumped whenever the data may have changed, so the register drops its
     cached tabs and the asset chart re-reads. */
  const [dataVersion, setDataVersion] = useState(0);
  const [quietTick, setQuietTick] = useState(0);

  /* Waiting access requests, reported by the bell, shown on Approvals. */
  const [pendingCount, setPendingCount] = useState(0);
  const [bellKey, setBellKey] = useState(0);

  // `loading` is the first paint only. A later refresh sets `refreshing`
  // instead, so the dashboard dims in place rather than collapsing to a
  // spinner and throwing the layout away.
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  /* null = no greeting to show. A signed-in name, or '' when the server
     did not send one, both mean "greet them". */
  const [welcome, setWelcome] = useState(null);
  const [approvalsOpen, setApprovalsOpen] = useState(false);
  const [importOpen, setImportOpen] = useState(false);

  /* Which headline tile's breakdown is open, if any. */
  const [tileOpen, setTileOpen] = useState(null);

  /* Account approval is the administrator's job and nobody else's, so the
     button only exists for them. The API enforces the same rule. */
  const currentUser = useCurrentUser();
  const isAdmin = currentUser?.role === 'ADMIN';

  /* Loading a spreadsheet writes to the register, so it takes the same
     roles as any other write. The API checks this too. */
  const mayWrite = canWriteNetwork(currentUser);

  /* `mode`: true for a visible refresh that dims the page, 'quiet' for
     the background poll that should not flicker anything. */
  const loadDashboardData = useCallback(async (mode = false) => {
    try {
      if (mode === true) setRefreshing(true);
      setError('');

      const [areaRes, mixRes, summaryRes, lengthRes, cscLengthRes] = await Promise.all([
        axiosClient.get('/dashboard/transformer-area-totals'),
        axiosClient.get('/dashboard/transformer-capacity-mix'),
        axiosClient.get('/dashboard/depot-summary'),

        /* The province's real HV line length, from the working segment
           register. The headline tile used to read network_km off
           v_depot_dashboard, which is the ASSET register's line and is
           piloted in two CSCs -- so the front page announced 16.3 km
           while the HV Length page said 3,441.31 km. Two answers to
           "how much line" on one system, and the front page carried
           the wrong one. */
        axiosClient.get('/network/length/by-area'),

        // Line per CSC, so the HV tile can narrow to a single CSC.
        axiosClient.get('/network/length/by-csc'),
      ]);

      setAreaTotals(areaRes.data || []);
      setCapacityMix(mixRes.data || []);
      setDepotSummary(summaryRes.data || []);
      setLineLengths(lengthRes.data || []);
      setLineByCsc(cscLengthRes.data || []);
      setLoaded(true);

      // A visible refresh re-reads the register too; the quiet poll
      // leaves it alone so its table does not blink every minute.
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

  /*
   * Keeping the charts current.
   *
   * Anything added through this dashboard refreshes it straight away
   * (onDataChanged, below). This covers the rest: data added on another
   * page, in another tab, or by someone else. Every minute while the tab
   * is visible, and whenever the window regains focus.
   */
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

  // Areas and CSCs for the place filter.
  useEffect(() => {
    axiosClient
      .get('/network/form-options')
      .then(({ data }) => setPlaceOptions(data))
      .catch(() => setPlaceOptions({ provinces: [], areas: [], cscs: [] }));
  }, []);

  /* What the place holds by kind of asset. Asked of the server with the
     place, because the catalogue is built from 3,000-odd records and is
     not worth sending whole to be filtered here. */
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

  /* The address bar can change without a reload -- choosing an area in
     the search box while already on the dashboard -- so follow it. */
  useEffect(() => {
    const fromUrl = {
      provinceId: searchParams.get('province_id') || '',
      areaId: searchParams.get('area_id') || '',
      cscId: searchParams.get('csc_id') || '',
    };
    if (isPlaceSet(fromUrl)) setPlace(fromUrl);

    // A notification's Review link from another page.
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

  // Confirmation of a save, cleared on its own so it never becomes part
  // of the furniture.
  useEffect(() => {
    if (!notice) return undefined;
    const t = setTimeout(() => setNotice(''), 5000);
    return () => clearTimeout(t);
  }, [notice]);

  /*
   * The greeting after signing in.
   *
   * Written by the sign-in screen, read here once and removed. It is
   * shown on the dashboard rather than on the auth page because that
   * page navigates away half a second after the toast appears, which is
   * not long enough to read anything.
   *
   * Read once and cleared, so it greets a sign-in and not every later
   * visit to the dashboard.
   */
  useEffect(() => {
    let greeting = null;

    try {
      const raw = sessionStorage.getItem('ceb_welcome');
      if (raw) {
        greeting = JSON.parse(raw);
        sessionStorage.removeItem('ceb_welcome');
      }
    } catch {
      // Private windows and cleared site data both land here; the
      // dashboard simply opens without a greeting.
    }

    // Ignore a stale flag: a tab left open for an hour should not
    // welcome somebody who signed in long ago.
    if (greeting && Date.now() - (greeting.at || 0) < 60_000) {
      setWelcome(greeting.name || '');
    }
  }, []);

  useEffect(() => {
    if (welcome === null) return undefined;
    const t = setTimeout(() => setWelcome(null), 9000);
    return () => clearTimeout(t);
  }, [welcome]);

  /*
   * Everything on the page, narrowed to the chosen place.
   *
   * Filtered here from per-CSC rows rather than fetched again per place:
   * v_depot_dashboard, v_transformer_capacity_mix and
   * v_line_length_by_csc all carry the CSC, area and province, and each
   * reconciles with the province figures (1,711 units, 312,230 kVA,
   * 3,441.31 km), so a narrowed tile is exactly the share of the whole.
   */
  const placeActive = isPlaceSet(place);
  const scopeLabel = placeActive ? describePlace(place, placeOptions) : '';

  /* The place the bottom card describes. With nothing chosen it is the
     whole province, so the dashboard opens on its areas. A future second
     province would make this the first one listed. */
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

  /* The area in focus -- chosen directly, or the area of a chosen CSC. */
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

  /*
   * Sign-in replaces /login in the history stack, so the entry behind the
   * dashboard is normally the welcome page. React Router records its own
   * position on window.history.state.idx: anything above 0 means there is
   * an in-app entry to return to. When there is not (the dashboard was
   * opened directly, or from a bookmark) going back would leave the app
   * entirely, so fall back to the welcome page instead.
   */
  const goBack = () => {
    if (window.history.state?.idx > 0) {
      navigate(-1);
    } else {
      navigate('/');
    }
  };

  // First paint only.
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

  // A failure with nothing already on screen. If a refresh fails after a
  // good load, the badge in the header carries it instead.
  if (error && !loaded) {
    return (
      <div className="dashboard-page dashboard-page-centred">
        <div className="dashboard-error">
          <h3>Unable to load dashboard</h3>

          <p>{error}</p>

          <div className="dashboard-error-actions">
            <button onClick={() => loadDashboardData(true)}>Try Again</button>

            <button
              type="button"
              className="dashboard-error-back"
              onClick={goBack}
            >
              &larr; Back
            </button>
          </div>
        </div>
      </div>
    );
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

        {/* One box over every register. It sits in the header bar rather
            than in a row of its own so the dashboard keeps fitting one
            screen; the results overlay the page instead. */}
        <GlobalSearch />

        <div className="dashboard-actions">
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

          <button
            type="button"
            className="approvals-button"
            onClick={() => navigate('/assets')}
            title="Every asset the province holds, and one transformer in detail"
          >
            Assets
          </button>

          <button
            type="button"
            className="approvals-button"
            onClick={() => navigate('/hv-length')}
            title="HV length by province, area, CSC and feeder"
          >
            HV Length
          </button>

          <button
            type="button"
            className="approvals-button"
            onClick={() => navigate('/reports')}
            title="Build a report, download it, or keep a dated copy in the project"
          >
            Reports
          </button>

          {/* Import from the top bar as well as from the register card,
              so loading a file does not mean scrolling to find it. */}
          <button
            type="button"
            className="approvals-button"
            onClick={() => setImportOpen(true)}
            disabled={!mayWrite}
            title={
              mayWrite
                ? 'Load a spreadsheet of segments'
                : 'Your role cannot load data. An administrator can widen your access.'
            }
          >
            &uarr; Import
          </button>

          {/* Access requests announce themselves: a badge, a pop-up the
              first time one arrives, and the count in the tab title.
              Administrators only. */}
          <NotificationBell
            onReview={() => setApprovalsOpen(true)}
            onCount={setPendingCount}
            refreshKey={bellKey}
          />

          {isAdmin && (
            <button
              type="button"
              className="approvals-button"
              onClick={() => setApprovalsOpen(true)}
              title={
                pendingCount > 0
                  ? `${pendingCount} access request${pendingCount === 1 ? '' : 's'} waiting`
                  : 'Give a signed-up user their role and depot'
              }
            >
              Approvals
              {pendingCount > 0 && <span className="approvals-count">{pendingCount}</span>}
            </button>
          )}

          <button
            className="refresh-button"
            onClick={() => loadDashboardData(true)}
            disabled={refreshing}
          >
            {refreshing ? 'Refreshing...' : '↻ Refresh'}
          </button>
        </div>

      </header>

      {/* The place filter, with the sign-in greeting beside it.

          One row, always present. The page is a fixed grid with a row per
          band, so a strip that came and went -- as the greeting used to --
          pushed the register off the bottom of the screen for as long as
          it showed. */}
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


      {/* ================= HEADLINE FIGURES ================= */}

      <SummaryCards
        cscSummary={shownDepotSummary}
        lineLengths={shownLengths}
        scopeLabel={scopeLabel}
        onOpen={setTileOpen}
      />


      {/* ================= CHARTS ================= */}

      <div className="dashboard-charts">

        <section className="dashboard-card">
          {/* Narrowed to an area, a chart of areas would be one bar, so
              it steps down to the CSCs inside that area instead. */}
          {focusAreaId ? (
            <>
              <div className="card-header">
                <h2>Transformers by CSC</h2>
                <p>
                  CSCs in {focusAreaName || 'this'} area
                  {place.cscId ? ' — the chosen CSC highlighted' : ''}
                </p>
              </div>

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
            </>
          ) : (
            <>
              <div className="card-header">
                <h2>Transformers by Area</h2>
                <p>Units recorded in each operational area</p>
              </div>

              <AreaChart
                data={shownAreaTotals}
                onPick={(areaId) =>
                  changePlace(
                    completePlace({ provinceId: '', areaId: String(areaId), cscId: '' }, placeOptions)
                  )
                }
              />
            </>
          )}
        </section>


        <section className="dashboard-card">
          <div className="card-header">
            <h2>Assets by Category</h2>
            <p>
              {placeActive
                ? `Counted items in ${scopeLabel}`
                : 'Counted items; conductor and line are km, on the Assets page'}
            </p>
          </div>

          <AssetCategoryChart data={assetCategories} />
        </section>


        <section className="dashboard-card">
          <div className="card-header">
            {/* Was "Fleet Mix", which is jargon: it reads as a measure
                rather than as a breakdown, and says nothing about what
                is being mixed. */}
            <h2>Transformer Types</h2>
            <p>
              {placeActive
                ? `Transformer types in ${scopeLabel}`
                : 'How the units split between distribution, bulk and generation'}
            </p>
          </div>

          <TransformerMixChart data={shownMix} />
        </section>

      </div>


      {/* ================= AT A GLANCE ================= */}

      {/* The place in view, described: the province when nothing is
          chosen, otherwise the chosen area or CSC. This replaced the
          register table, which now lives on the HV Length page with its
          Report, Import and + HV Length buttons. */}
      <section className="dashboard-card dashboard-table-card">
        <div className="card-header card-header-row">
          <div>
            <h2>At a glance</h2>
            <p>
              {placeActive
                ? `Everything recorded for ${scopeLabel}. Select a card to open the place inside it.`
                : 'The whole province. Select an area to open it, or choose a place above.'}
            </p>
          </div>

          <button
            type="button"
            className="dash-btn-quiet dash-btn-sm"
            onClick={() => navigate('/hv-length#register')}
            title="Every row of the register, with Report, Import and + HV Length"
          >
            Full register table &rarr;
          </button>
        </div>

        <PlaceProfile
          place={profilePlace}
          placeOptions={placeOptions}
          depotSummary={depotSummary}
          lineLengths={lineLengths}
          lineByCsc={lineByCsc}
          assetCategories={assetCategories}
          dataVersion={dataVersion}
          onPickPlace={changePlace}
        />
      </section>

      <ApprovalsDialog
        open={approvalsOpen}
        onClose={() => {
          setApprovalsOpen(false);
          // Drop ?approvals=open so a refresh does not reopen it.
          if (searchParams.get('approvals')) {
            const next = new URLSearchParams(searchParams);
            next.delete('approvals');
            setSearchParams(next, { replace: true });
          }
        }}
        onChanged={(message) => {
          setNotice(message);
          // The request is decided; the badge should drop now, not at
          // the next poll.
          setBellKey((k) => k + 1);
        }}
      />

      {/* The top bar's import. The dialog stays open on success so its
          "How the file was read" and "Where it was filed" panels can be
          read; the tiles, charts and register refresh behind it. */}
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
