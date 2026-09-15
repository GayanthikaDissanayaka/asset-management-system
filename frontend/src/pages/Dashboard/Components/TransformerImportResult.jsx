import React from 'react';

import { formatNumber } from './data';

/*
 * The result of reading a transformer workbook.
 *
 * Shown twice: first as a PREVIEW, where nothing has been written and the
 * lists say exactly what would change, and again after "Apply", where the
 * same lists say what did. A transformer import changes records that
 * already exist, so the person importing sees every change -- field,
 * old value, new value -- before agreeing to it.
 */

const show = (v) => (v === null || v === undefined || v === '' ? 'blank' : String(v));

const TransformerImportResult = ({ result }) => {
  const c = result.counts || {};

  return (
    <div className="import-result">
      <div className={result.preview ? 'import-banner is-preview' : 'import-banner is-applied'}>
        <strong>{result.preview ? 'Preview — nothing written yet' : 'Applied'}</strong>
        <span>{result.message}</span>
      </div>

      <div className="import-tallies">
        <span className="import-tally is-good">
          <strong>{formatNumber(c.new || 0)}</strong> new
        </span>
        <span className="import-tally is-good">
          <strong>{formatNumber(c.updated || 0)}</strong> updated
        </span>
        <span className="import-tally">
          <strong>{formatNumber(c.unchanged || 0)}</strong> already match
        </span>
        <span className={`import-tally${c.errors ? ' is-bad' : ''}`}>
          <strong>{formatNumber(c.errors || 0)}</strong> errors
        </span>
      </div>

      <h4>What was read</h4>
      <ul className="import-list import-places">
        {(result.sheets || []).map((s) => (
          <li key={s.sheet} className="import-sheet">
            <span className="import-place-given">Sheet &ldquo;{s.sheet}&rdquo;</span>
            <span className="import-place-arrow" aria-hidden="true">→</span>
            <span className="import-place-to">{s.place || 'CSC per row'}</span>
            <span className="import-place-rows">
              {formatNumber(s.rows)} rows · {formatNumber(s.new)} new · {formatNumber(s.updated)} updated
            </span>
            <span className="import-sheet-note">
              Headings on row {s.header_row}: {s.used.map((u) => `${u.heading} → ${u.read_as}`).join(', ')}.
              {s.ignored?.length > 0 && ` Ignored: ${s.ignored.join(', ')}.`} {s.place_note}
            </span>
          </li>
        ))}
      </ul>

      {result.new?.length > 0 && (
        <>
          <h4>
            {result.preview ? 'Would be added' : 'Added'} ({formatNumber(c.new)})
          </h4>
          <ul className="import-list">
            {result.new.map((n) => (
              <li key={`${n.sheet}-${n.row}`}>
                <strong>{n.substation}</strong>
                {' — '}
                {[n.sin && `SIN ${n.sin}`, n.serial && `serial ${n.serial}`, n.capacity && `${formatNumber(n.capacity)} kVA`]
                  .filter(Boolean)
                  .join(' · ')}
                {' → '}
                {n.csc} CSC <em className="import-place-flag">from {n.place_from}</em>
              </li>
            ))}
          </ul>
          {c.new > result.new.length && (
            <p className="import-hint">and {formatNumber(c.new - result.new.length)} more.</p>
          )}
        </>
      )}

      {result.updates?.length > 0 && (
        <>
          <h4>
            {result.preview ? 'Would be updated' : 'Updated'} ({formatNumber(c.updated)})
          </h4>
          <ul className="import-list import-changes">
            {result.updates.map((u) => (
              <li key={`${u.sheet}-${u.row}`}>
                <span className="import-change-who">
                  <strong>{u.label}</strong> {u.name} · {u.csc}
                </span>
                {u.changes.map((ch) => (
                  <span key={ch.field} className="import-change">
                    {ch.field}: <del>{show(ch.from)}</del> → <ins>{show(ch.to)}</ins>
                  </span>
                ))}
              </li>
            ))}
          </ul>
          {c.updated > result.updates.length && (
            <p className="import-hint">and {formatNumber(c.updated - result.updates.length)} more.</p>
          )}
        </>
      )}

      {result.warnings?.length > 0 && (
        <>
          <h4>Worth a look</h4>
          <ul className="import-list">
            {result.warnings.slice(0, 15).map((w, i) => (
              <li key={`w-${i}`}>
                {w.sheet} row {w.row}: {w.message}
              </li>
            ))}
          </ul>
        </>
      )}

      {result.errors?.length > 0 && (
        <>
          <h4>Rows that could not be used</h4>
          <ul className="import-list is-bad">
            {result.errors.slice(0, 15).map((e, i) => (
              <li key={`e-${i}`}>
                {e.sheet} row {e.row}: {e.message}
              </li>
            ))}
          </ul>
          {result.errors.length > 15 && (
            <p className="import-hint">and {result.errors.length - 15} more.</p>
          )}
        </>
      )}
    </div>
  );
};

export default TransformerImportResult;
