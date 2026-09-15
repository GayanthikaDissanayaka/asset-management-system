import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';

import axiosClient from '../../api/axiosClient';
import { formatNumber } from '../Dashboard/Components/data';
import { downloadFromApi } from '../Dashboard/Components/fileTransfer';
import NotificationBell from '../Dashboard/Components/NotificationBell';
import {
  useCurrentUser,
  canWriteNetwork,
  describeWriteError,
} from '../Dashboard/Components/session';

import edlMark from '../Auth/edl-mark.png';

import '../Dashboard/Dashbord.css';
import './reports.css';

/*
 * Reports.
 *
 * Two different things, deliberately kept apart:
 *
 *   DOWNLOAD  builds the file and hands it to the browser. Nothing is
 *             kept. Right for "let me look at this now".
 *
 *   SAVE      builds the same file and writes it into the project's
 *             reports/ folder, stamped with the date and time. Right for
 *             "what did the register say at the end of last month" --
 *             a question the live register cannot answer, because it has
 *             moved on since. That answer has to have been written down
 *             at the time.
 *
 * Both go through the same builder on the server, so a saved file and a
 * downloaded one can never disagree.
 */

const REPORTS = [
  {
    key: 'report',
    label: 'Full report',
    note: 'The written province / area / CSC document, with every data sheet behind it.',
  },
  {
    key: 'assets-used',
    label: 'Assets used — every entry',
    note: 'The usage log: what was recorded, where it went, when, and by whom.',
  },
  {
    key: 'assets-used-by-csc',
    label: 'Assets used — by CSC',
    note: 'The same log totalled per CSC and asset type.',
  },
  {
    key: 'asset-types',
    label: 'Asset catalogue',
    note: 'Every category and type from asset_categories and asset_types, with what is held.',
  },
  {
    key: 'asset-by-csc',
    label: 'Assets held, by CSC',
    note: 'What each CSC currently holds, per asset type.',
  },
  {
    key: 'segments',
    label: 'Segments',
    note: 'Every segment in the working register with its length and CSC.',
  },
  {
    key: 'areas',
    label: 'Line length by area',
    note: 'HV length per area, each area credited only with the line inside it.',
  },
  {
    key: 'cscs',
    label: 'Line length by CSC',
    note: 'HV length per consumer service centre.',
  },
  {
    key: 'feeders',
    label: 'Line length by feeder',
    note: 'HV length per feeder.',
  },
];

const prettyBytes = (n) => {
  if (!n) return '0 KB';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(0)} KB`;
  return `${(n / 1024 / 1024).toFixed(1)} MB`;
};

const ReportsPage = () => {
  const navigate = useNavigate();
  const user = useCurrentUser();
  const mayWrite = canWriteNetwork(user);

  const [choice, setChoice] = useState('report');
  const [label, setLabel] = useState('');

  const [saved, setSaved] = useState(null);
  const [folder, setFolder] = useState('');

  const [busy, setBusy] = useState('');
  const [notice, setNotice] = useState('');
  const [error, setError] = useState('');

  const selected = useMemo(
    () => REPORTS.find((r) => r.key === choice),
    [choice]
  );

  const loadSaved = useCallback(async () => {
    try {
      const { data } = await axiosClient.get('/network/reports/saved');
      setSaved(data.files || []);
      setFolder(data.folder || '');
    } catch (err) {
      setError(
        err.response
          ? `Could not read the reports folder (${err.response.status}).`
          : 'Could not reach the API.'
      );
      setSaved([]);
    }
  }, []);

  useEffect(() => {
    loadSaved();
  }, [loadSaved]);

  // Notices clear themselves so they never become part of the furniture.
  useEffect(() => {
    if (!notice) return undefined;
    const t = setTimeout(() => setNotice(''), 7000);
    return () => clearTimeout(t);
  }, [notice]);

  const path = (key) =>
    key === 'report' ? '/network/report' : `/network/export?view=${key}`;

  const runDownload = async () => {
    setBusy('download');
    setError('');
    try {
      const name = await downloadFromApi(path(choice), `uva-${choice}.xlsx`);
      setNotice(`Downloaded ${name}.`);
    } catch (err) {
      setError(describeWriteError(err, 'Could not build that report.'));
    } finally {
      setBusy('');
    }
  };

  const runSave = async () => {
    setBusy('save');
    setError('');
    try {
      const { data } = await axiosClient.post('/network/reports/save', {
        view: choice,
        label: label.trim() || null,
      });
      setNotice(data.message);
      setLabel('');
      // The list is the proof it was written, so refresh it rather than
      // asking the reader to take the message on trust.
      loadSaved();
    } catch (err) {
      setError(describeWriteError(err, 'Could not save that report.'));
    } finally {
      setBusy('');
    }
  };

  const fetchSaved = async (file) => {
    setError('');
    try {
      await downloadFromApi(
        `/network/reports/download?file=${encodeURIComponent(file)}`,
        file
      );
    } catch {
      setError(`Could not download ${file}.`);
    }
  };

  const goBack = () => {
    if (window.history.state?.idx > 0) navigate(-1);
    else navigate('/dashboard');
  };

  return (
    <div className="dashboard-page rp-page">
      <header className="dashboard-header">
        <div className="dashboard-identity">
          <button type="button" className="dashboard-back" onClick={goBack}>
            &larr; Back
          </button>

          <img src={edlMark} alt="" className="dashboard-logo" width={32} height={32} />

          <div className="dashboard-titles">
            <h1>Reports</h1>
            <p>CEB Uva Province &middot; build, download and keep a dated copy</p>
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
            onClick={() => navigate('/assets')}
          >
            Assets
          </button>
          <button
            type="button"
            className="approvals-button"
            onClick={() => navigate('/hv-length')}
          >
            HV Length
          </button>
          <button className="refresh-button" onClick={loadSaved}>
            ↻ Refresh
          </button>
        </div>
      </header>

      {notice && <div className="dashboard-welcome rp-notice" role="status">{notice}</div>}
      {error && <div className="register-error">{error}</div>}

      <section className="dashboard-card">
        <div className="card-header">
          <h2>Build a report</h2>
          <p>
            Every report reads the live register, so it is correct at the moment
            you build it.
          </p>
        </div>

        <div className="rp-builder">
          <label className="rp-field rp-field-wide">
            <span>Report</span>
            <select value={choice} onChange={(e) => setChoice(e.target.value)}>
              {REPORTS.map((r) => (
                <option key={r.key} value={r.key}>
                  {r.label}
                </option>
              ))}
            </select>
          </label>

          <label className="rp-field rp-field-wide">
            <span>Label (optional)</span>
            <input
              type="text"
              value={label}
              maxLength={60}
              placeholder="e.g. September review — added to the filename"
              onChange={(e) => setLabel(e.target.value)}
            />
          </label>

          <div className="rp-actions">
            <button
              type="button"
              className="dash-btn-quiet"
              onClick={runDownload}
              disabled={busy !== ''}
            >
              {busy === 'download' ? 'Building...' : '↓ Download'}
            </button>

            <button
              type="button"
              className="dash-btn-primary"
              onClick={runSave}
              disabled={busy !== '' || !mayWrite}
              title={
                mayWrite
                  ? 'Writes a dated copy into the project reports/ folder'
                  : 'Your role does not allow writing to the server. An administrator can widen your access.'
              }
            >
              {busy === 'save' ? 'Saving...' : 'Save to project folder'}
            </button>
          </div>
        </div>

        {selected && <p className="rp-note">{selected.note}</p>}
      </section>

      <section className="dashboard-card dashboard-table-card">
        <div className="card-header">
          <h2>Kept in the project</h2>
          <p>
            Saved reports are written to <code>{folder || 'reports/'}</code> and
            appear in the editor beside the rest of the project. Each one is a
            snapshot of the register at the time it was built — the live
            register cannot answer what it said last month.
          </p>
        </div>

        {saved === null ? (
          <div className="chart-empty">Reading the reports folder...</div>
        ) : saved.length === 0 ? (
          <div className="chart-empty">
            Nothing saved yet. Build a report above and choose &ldquo;Save to
            project folder&rdquo;.
          </div>
        ) : (
          <div className="depot-table-wrapper">
            <table className="depot-table">
              <thead>
                <tr>
                  <th>File</th>
                  <th>Saved</th>
                  <th className="numeric">Size</th>
                  <th className="numeric">Open</th>
                </tr>
              </thead>
              <tbody>
                {saved.map((f) => (
                  <tr key={f.file}>
                    <td>
                      <span className="depot-name">{f.file}</span>
                    </td>
                    <td>{f.saved_at}</td>
                    <td className="numeric">{prettyBytes(f.bytes)}</td>
                    <td className="numeric">
                      <button
                        type="button"
                        className="dash-btn-quiet dash-btn-sm"
                        onClick={() => fetchSaved(f.file)}
                      >
                        Download
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr>
                  <td>
                    {formatNumber(saved.length)}{' '}
                    {saved.length === 1 ? 'report' : 'reports'}
                  </td>
                  <td />
                  <td className="numeric strong">
                    {prettyBytes(saved.reduce((s, f) => s + (f.bytes || 0), 0))}
                  </td>
                  <td />
                </tr>
              </tfoot>
            </table>
          </div>
        )}
      </section>
    </div>
  );
};

export default ReportsPage;
