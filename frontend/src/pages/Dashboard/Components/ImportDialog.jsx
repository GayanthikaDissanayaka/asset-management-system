import React, { useEffect, useRef, useState } from 'react';

import { downloadFromApi, uploadSpreadsheet } from './fileTransfer';
import { describeWriteError } from './session';
import { formatNumber } from './data';

/**
 * Loading a spreadsheet of segments.
 *
 * The template is offered in two formats for a practical reason: reading
 * .xlsx needs PHP's zip extension, which is optional and off by default
 * in XAMPP. CSV needs nothing, so it always works. The server says which
 * applies, and that message is shown here rather than swallowed.
 *
 * The result panel reports three separate things, because they mean
 * different things to whoever is loading the file:
 *
 *   loaded    rows that became segments
 *   skipped   segment codes already in the register, left untouched
 *   errors    rows that could not be read, with the line number
 */
const ImportDialog = ({ open, onClose, onImported }) => {
  const [file, setFile] = useState(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');
  const inputRef = useRef(null);

  useEffect(() => {
    if (open) {
      setFile(null);
      setBusy(false);
      setResult(null);
      setError('');
    }
  }, [open]);

  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => {
      if (e.key === 'Escape' && !busy) onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose, busy]);

  const getTemplate = async (format) => {
    setError('');
    try {
      await downloadFromApi(
        `/network/import-template${format === 'csv' ? '?format=csv' : ''}`,
        `uva-segment-import-template.${format}`
      );
    } catch (err) {
      setError('Could not download the template.');
    }
  };

  const submit = async () => {
    if (!file) return;
    setBusy(true);
    setError('');
    setResult(null);

    try {
      const data = await uploadSpreadsheet(file);
      setResult(data);
      if (data.created > 0) onImported(data.message);
    } catch (err) {
      // A rejected file still carries a useful body, including the
      // "turn on the zip extension" case.
      const body = err.response?.data;
      if (body?.created !== undefined) {
        setResult(body);
      }
      setError(describeWriteError(err));
    } finally {
      setBusy(false);
    }
  };

  if (!open) return null;

  return (
    <div
      className="dialog-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget && !busy) onClose();
      }}
    >
      <div className="dialog dialog-narrow" role="dialog" aria-modal="true" aria-labelledby="import-title">
        <header className="dialog-head">
          <div>
            <h2 id="import-title">Import segments</h2>
            <p>Load a sheet of segments into the register.</p>
          </div>
          <button type="button" className="dialog-close" onClick={onClose} aria-label="Close">
            &times;
          </button>
        </header>

        <div className="dialog-body">
          <div className="dialog-section" style={{ marginTop: 0 }}>
            <div className="dialog-section-head">
              <h3>1. Start from the template</h3>
              <span className="dialog-section-note">
                It carries a column per asset type and the CSC codes to use
              </span>
            </div>

            <div className="import-actions">
              <button type="button" className="btn-quiet btn-sm" onClick={() => getTemplate('xlsx')}>
                Download .xlsx
              </button>
              <button type="button" className="btn-quiet btn-sm" onClick={() => getTemplate('csv')}>
                Download .csv
              </button>
            </div>

            <p className="import-hint">
              One row per CSC a segment runs through. A segment crossing a
              boundary repeats its code on each row, with the kilometres
              inside that CSC.
            </p>
          </div>

          <div className="dialog-section">
            <div className="dialog-section-head">
              <h3>2. Upload the filled sheet</h3>
            </div>

            <input
              ref={inputRef}
              type="file"
              accept=".xlsx,.xls,.csv"
              className="import-file"
              onChange={(e) => {
                setFile(e.target.files?.[0] || null);
                setResult(null);
                setError('');
              }}
            />

            {file && (
              <p className="import-hint">
                Selected <strong>{file.name}</strong> (
                {formatNumber(file.size / 1024, 1)} KB)
              </p>
            )}
          </div>

          {error && <div className="dialog-error">{error}</div>}

          {result && (
            <div className="import-result">
              <div className="import-tallies">
                <span className="import-tally is-good">
                  <strong>{formatNumber(result.created || 0)}</strong> loaded
                </span>
                <span className="import-tally">
                  <strong>{formatNumber(result.skipped?.length || 0)}</strong> skipped
                </span>
                <span className={`import-tally${result.errors?.length ? ' is-bad' : ''}`}>
                  <strong>{formatNumber(result.errors?.length || 0)}</strong> errors
                </span>
              </div>

              {result.skipped?.length > 0 && (
                <>
                  <h4>Already in the register</h4>
                  <ul className="import-list">
                    {result.skipped.slice(0, 12).map((s) => (
                      <li key={`${s.row}-${s.code}`}>
                        Row {s.row}: {s.code} — {s.message}
                      </li>
                    ))}
                  </ul>
                  {result.skipped.length > 12 && (
                    <p className="import-hint">
                      and {result.skipped.length - 12} more.
                    </p>
                  )}
                </>
              )}

              {result.errors?.length > 0 && (
                <>
                  <h4>Rows that could not be read</h4>
                  <ul className="import-list is-bad">
                    {result.errors.slice(0, 12).map((e, i) => (
                      <li key={`${e.row}-${i}`}>
                        Row {e.row}: {e.message}
                      </li>
                    ))}
                  </ul>
                  {result.errors.length > 12 && (
                    <p className="import-hint">and {result.errors.length - 12} more.</p>
                  )}
                </>
              )}
            </div>
          )}
        </div>

        <footer className="dialog-foot">
          <button type="button" className="btn-quiet" onClick={onClose} disabled={busy}>
            {result?.created > 0 ? 'Done' : 'Cancel'}
          </button>

          <div className="dialog-foot-right">
            <button
              type="button"
              className="btn-primary"
              onClick={submit}
              disabled={!file || busy}
            >
              {busy ? 'Loading...' : 'Load into register'}
            </button>
          </div>
        </footer>
      </div>
    </div>
  );
};

export default ImportDialog;
