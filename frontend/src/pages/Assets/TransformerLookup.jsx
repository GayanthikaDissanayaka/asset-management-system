import React, { useEffect, useRef, useState } from 'react';

import axiosClient from '../../api/axiosClient';
import { formatNumber } from '../Dashboard/Components/data';

/*
 * Find one transformer.
 *
 * "Name or ID" is five different things in this data and the person
 * holding a paper record does not know which one they have: the numeric
 * id, the old SIN, the new SIN, the serial number, or the substation it
 * serves. The API matches all five, so this box asks for none of them
 * in particular.
 *
 * It searches as you type, after a pause. Two characters is the floor —
 * one character matches most of 1,717 rows and the list would be noise.
 */

const MIN_QUERY = 2;
const DEBOUNCE_MS = 250;

const TransformerLookup = ({ onOpen }) => {
  const [query, setQuery] = useState('');
  const [rows, setRows] = useState(null);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState('');

  /* Every keystroke starts a request; without this the answer to "Bad"
     can land after the answer to "Badulla" and overwrite it. */
  const requestRef = useRef(0);

  useEffect(() => {
    const term = query.trim();

    if (term.length < MIN_QUERY) {
      setRows(null);
      setError('');
      setSearching(false);
      return undefined;
    }

    const ticket = ++requestRef.current;
    setSearching(true);

    const timer = setTimeout(() => {
      axiosClient
        .get('/network/transformers/search', { params: { q: term, limit: 25 } })
        .then(({ data }) => {
          if (ticket !== requestRef.current) return;
          setRows(data?.rows || []);
          setError('');
        })
        .catch((err) => {
          if (ticket !== requestRef.current) return;
          setRows([]);
          setError(
            err.response
              ? `The server returned ${err.response.status}.`
              : 'Could not reach the API. Check that Laravel is running on port 8000.'
          );
        })
        .finally(() => {
          if (ticket === requestRef.current) setSearching(false);
        });
    }, DEBOUNCE_MS);

    return () => clearTimeout(timer);
  }, [query]);

  return (
    <section className="dashboard-card ax-lookup">
      <div className="card-header">
        <h2>Find a transformer</h2>
        <p>
          Search by substation name, SIN number, serial number or record id.
          Any of them will do.
        </p>
      </div>

      <div className="ax-lookup-row">
        <input
          type="search"
          className="register-search ax-lookup-input"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="e.g. Capital City, UBB 141, T16U010030594 or 5"
          aria-label="Transformer name or number"
        />

        {query && (
          <button
            type="button"
            className="dash-btn-quiet dash-btn-sm"
            onClick={() => setQuery('')}
          >
            Clear
          </button>
        )}
      </div>

      {error && <div className="register-error">{error}</div>}

      {/* Four states, each said plainly: nothing typed, too little
          typed, searching, and no match. Silence on any of them reads
          as a broken search box. */}
      {!error && query.trim().length > 0 && query.trim().length < MIN_QUERY && (
        <p className="ax-lookup-hint">Type at least {MIN_QUERY} characters.</p>
      )}

      {!error && searching && rows === null && (
        <p className="ax-lookup-hint">Searching...</p>
      )}

      {!error && rows !== null && rows.length === 0 && !searching && (
        <p className="ax-lookup-hint">
          No transformer matches &ldquo;{query.trim()}&rdquo;.
        </p>
      )}

      {!error && rows !== null && rows.length > 0 && (
        <>
          <p className="ax-lookup-hint">
            {rows.length === 25
              ? 'First 25 matches. Narrow the search to see fewer.'
              : `${formatNumber(rows.length)} ${
                  rows.length === 1 ? 'match' : 'matches'
                }. Select one to see it in full.`}
          </p>

          <ul className="ax-hits">
            {rows.map((t) => (
              <li key={t.transformer_id}>
                <button
                  type="button"
                  className="ax-hit"
                  onClick={() => onOpen(t.transformer_id)}
                >
                  <span className="ax-hit-name">
                    {t.substation_name || 'Unnamed substation'}
                    {t.status !== 'ACTIVE' && (
                      <em className="ax-hit-flag">{t.status}</em>
                    )}
                  </span>

                  <span className="ax-hit-meta">
                    {[
                      t.new_sin_no || t.old_sin_no,
                      t.transformer_no ? `Serial ${t.transformer_no}` : null,
                      t.type_name,
                      t.capacity_kva ? `${formatNumber(t.capacity_kva)} kVA` : null,
                    ]
                      .filter(Boolean)
                      .join(' · ')}
                  </span>

                  <span className="ax-hit-place">
                    {t.csc_name} CSC · {t.area_name}
                  </span>
                </button>
              </li>
            ))}
          </ul>
        </>
      )}
    </section>
  );
};

export default TransformerLookup;
