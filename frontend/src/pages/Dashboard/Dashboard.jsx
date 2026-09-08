import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import axiosClient from '../../api/axiosClient';

import SummaryCards from './Components/SummaryCards';
import AreaChart from './Components/AreaChart';
import CscChart from './Components/CscChart';
import TransformerMixChart from './Components/TransformerMixChart';
import NetworkRegister from './Components/NetworkRegister';
import { toArray, num, pick, readUnits, readKva } from './Components/data';

import edlMark from '../Auth/edl-mark.png';

import './Dashbord.css';

/*
 * Everything on this page comes from MySQL views in ceb_uva_ams, served
 * by DashboardController.
 *
 *   transformer-area-totals    v_transformer_totals_by_area
 *   transformer-depot-totals   v_transformer_totals_by_csc
 *   transformer-capacity-mix   v_transformer_capacity_mix
 *   depot-summary              v_depot_dashboard
 *
 * The dashboard leads with transformers rather than the general asset
 * register because that is where the province's data actually is: 1,711
 * units across all five areas, against an asset register still piloted
 * in two depots. The asset register also mixes units of measure in one
 * column, so its totals cannot be summed without filtering first.
 */
const Dashboard = () => {
  const navigate = useNavigate();

  const [areaTotals, setAreaTotals] = useState([]);
  const [depotTotals, setDepotTotals] = useState([]);
  const [capacityMix, setCapacityMix] = useState([]);
  const [depotSummary, setDepotSummary] = useState([]);

  // `loading` is the first paint only. A later refresh sets `refreshing`
  // instead, so the dashboard dims in place rather than collapsing to a
  // spinner and throwing the layout away.
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');

  const loadDashboardData = useCallback(async (isRefresh = false) => {
    try {
      if (isRefresh) setRefreshing(true);
      setError('');

      const [areaRes, depotRes, mixRes, summaryRes] = await Promise.all([
        axiosClient.get('/dashboard/transformer-area-totals'),
        axiosClient.get('/dashboard/transformer-depot-totals'),
        axiosClient.get('/dashboard/transformer-capacity-mix'),
        axiosClient.get('/dashboard/depot-summary'),
      ]);

      setAreaTotals(areaRes.data || []);
      setDepotTotals(depotRes.data || []);
      setCapacityMix(mixRes.data || []);
      setDepotSummary(summaryRes.data || []);
      setLoaded(true);
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

  // Confirmation of a save, cleared on its own so it never becomes part
  // of the furniture.
  useEffect(() => {
    if (!notice) return undefined;
    const t = setTimeout(() => setNotice(''), 5000);
    return () => clearTimeout(t);
  }, [notice]);

  /* v_depot_dashboard shaped for the register's Transformers view. Done
     here so NetworkRegister stays a presentation component. */
  const cscSummaryRows = useMemo(
    () =>
      toArray(depotSummary).map((r) => ({
        id: pick(r, 'csc_id', 'cscId') ?? pick(r, 'csc_code', 'cscCode'),
        code: pick(r, 'csc_code', 'cscCode') || '',
        name: pick(r, 'csc_name', 'cscName', 'depot_name') || 'Unknown',
        area: pick(r, 'area_name', 'areaName') || '',
        transformers: readUnits(r),
        kva: readKva(r),
        networkKm: num(pick(r, 'network_km', 'networkKm')),
      })),
    [depotSummary]
  );

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
            className="refresh-button"
            onClick={() => loadDashboardData(true)}
            disabled={refreshing}
          >
            {refreshing ? 'Refreshing...' : '↻ Refresh'}
          </button>
        </div>

      </header>


      {/* ================= HEADLINE FIGURES ================= */}

      <SummaryCards areaTotals={areaTotals} cscSummary={depotSummary} />


      {/* ================= CHARTS ================= */}

      <div className="dashboard-charts">

        <section className="dashboard-card">
          <div className="card-header">
            <h2>Transformers by Area</h2>
            <p>Units recorded in each operational area</p>
          </div>

          <AreaChart data={areaTotals} />
        </section>


        <section className="dashboard-card">
          <div className="card-header">
            <h2>Transformers by CSC</h2>
            <p>Top eight consumer service centres</p>
          </div>

          <CscChart data={depotTotals} />
        </section>


        <section className="dashboard-card">
          <div className="card-header">
            <h2>Fleet Mix</h2>
            <p>Share of units by transformer type</p>
          </div>

          <TransformerMixChart data={capacityMix} />
        </section>

      </div>


      {/* ================= DEPOT TABLE ================= */}

      <section className="dashboard-card dashboard-table-card">
        <div className="card-header">
          <h2>Network Register</h2>
          <p>
            Line length at every level. Each total states how many segments
            it came from. Click a column heading to sort.
          </p>
        </div>

        <NetworkRegister cscSummaryRows={cscSummaryRows} onToast={setNotice} />
      </section>

    </div>
  );
};

export default Dashboard;
