import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';

import axiosClient from '../../../api/axiosClient';
import { formatNumber } from './data';

/*
 * One box that searches everything.
 *
 * Reads /api/search, which ranks across transformers, switchgear,
 * segments, CSCs, areas, feeders and the asset register from a single
 * index view. The person searching does not have to know which register
 * a thing lives in, which is the whole point: an engineer holding a SIN
 * number should not first have to decide whether it is a "transformer"
 * or an "asset".
 *
 * It sits inside the header bar rather than in a band of its own,
 * because the dashboard is deliberately one screen with no scrolling
 * and a new row would push the charts off it. The results overlay the
 * page instead of displacing it.
 *
 * NOT A PUBLIC SEARCH ENGINE. It reads the province operational record
 * and every request carries the signed-in user's token. The application
 * is marked noindex so none of it can be crawled.
 */

const MIN_QUERY = 2;
const DEBOUNCE_MS = 220;

/* What each kind is called, and where selecting one takes you.

   Everything lands on a page that can actually show the thing: a
   transformer opens its detail, a place filters the asset register, and
   a segment or feeder opens the dashboard register at the right tab
   with the code already searched. A result that navigated somewhere the
   reader then had to search again would be worse than no link. */
const KINDS = {
  area:        { label: 'Area',        accent: '#4A3AA7' },
  csc:         { label: 'CSC',         accent: '#A31D52' },
  feeder:      { label: 'Feeder',      accent: '#2A78D6' },
  transformer: { label: 'Transformer', accent: '#EDA100' },
  switchgear:  { label: 'Switchgear',  accent: '#1BAF7A' },
  asset:       { label: 'Asset',       accent: '#EB6834' },
  segment:     { label: 'Segment',     accent: '#6B5A62' },
};

function targetFor(row) {
  const code = encodeURIComponent(row.code || '');

  switch (row.kind) {
    case 'transformer':
      return `/assets?transformer=${row.entity_id}`;
    /* A place opens the DASHBOARD narrowed to it, so searching "Badulla"
       shows Badulla's tiles, charts and register together rather than
       one list of assets. */
    case 'csc':
      return `/dashboard?csc_id=${row.entity_id}`;
    case 'area':
      return `/dashboard?area_id=${row.area_id}`;
    case 'switchgear':
    case 'asset':
      return `/assets?${row.csc_id ? `csc_id=${row.csc_id}&` : ''}search=${code}`;
    case 'segment':
      return `/hv-length?register=segments&q=${code}`;
    case 'feeder':
      return `/hv-length?register=feeders&q=${code}`;
    default:
      return '/dashboard';
  }
}

const GlobalSearch = () => {
  const navigate = useNavigate();

  const [query, setQuery] = useState('');
  const [data, setData] = useState(null);
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [active, setActive] = useState(0);

  const boxRef = useRef(null);
  const inputRef = useRef(null);

  /* Every keystroke starts a request. Without a ticket the answer to
     "bad" can land after the answer to "badulla" and replace it. */
  const ticketRef = useRef(0);

  useEffect(() => {
    const term = query.trim();

    if (term.length < MIN_QUERY) {
      setData(null);
      setError('');
      setBusy(false);
      return undefined;
    }

    const ticket = ++ticketRef.current;
    setBusy(true);

    const timer = setTimeout(() => {
      axiosClient
        .get('/search', { params: { q: term, limit: 12 } })
        .then(({ data: body }) => {
          if (ticket !== ticketRef.current) return;
          setData(body);
          setError('');
          setActive(0);
          setOpen(true);
        })
        .catch((err) => {
          if (ticket !== ticketRef.current) return;
          setData(null);
          setError(
            err.response
              ? `Search failed (${err.response.status}).`
              : 'Could not reach the API.'
          );
          setOpen(true);
        })
        .finally(() => {
          if (ticket === ticketRef.current) setBusy(false);
        });
    }, DEBOUNCE_MS);

    return () => clearTimeout(timer);
  }, [query]);

  // Clicking anywhere else puts the panel away, the way a suggestion
  // list is expected to behave.
  useEffect(() => {
    const onDown = (e) => {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, []);

  const results = useMemo(() => data?.results || [], [data]);

  const choose = useCallback(
    (row) => {
      if (!row) return;
      setOpen(false);
      setQuery('');
      setData(null);
      inputRef.current?.blur();
      navigate(targetFor(row));
    },
    [navigate]
  );

  const onKeyDown = (e) => {
    if (e.key === 'Escape') {
      setOpen(false);
      inputRef.current?.blur();
      return;
    }

    if (!open || results.length === 0) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setActive((i) => (i + 1) % results.length);
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setActive((i) => (i - 1 + results.length) % results.length);
    } else if (e.key === 'Enter') {
      e.preventDefault();
      choose(results[active]);
    }
  };

  /* How many matched beyond what is listed. The endpoint caps each kind
     so one crowded kind cannot hide the others, which means the list is
     often a small part of the total — saying so is the difference
     between "that is everything" and "narrow your search". */
  const hidden = Math.max(0, (data?.total || 0) - results.length);

  return (
    <div className="gs" ref={boxRef}>
      <div className="gs-field">
        <span className="gs-icon" aria-hidden="true">⌕</span>

        <input
          ref={inputRef}
          type="search"
          className="gs-input"
          value={query}
          placeholder="Search transformers, switchgear, segments, CSCs..."
          aria-label="Search the province"
          aria-expanded={open}
          aria-controls="gs-results"
          aria-activedescendant={
            open && results[active] ? `gs-hit-${active}` : undefined
          }
          aria-autocomplete="list"
          role="combobox"
          autoComplete="off"
          onChange={(e) => setQuery(e.target.value)}
          onFocus={() => data && setOpen(true)}
          onKeyDown={onKeyDown}
        />

        {busy && <span className="gs-busy" aria-hidden="true" />}
      </div>

      {open && (
        <div className="gs-panel" id="gs-results" role="listbox">
          {error && <div className="gs-message gs-error">{error}</div>}

          {!error && results.length === 0 && !busy && (
            <div className="gs-message">
              Nothing matches &ldquo;{query.trim()}&rdquo;.
            </div>
          )}

          {!error && results.length > 0 && (
            <>
              <ul className="gs-list">
                {results.map((row, i) => {
                  const kind = KINDS[row.kind] || { label: row.kind, accent: '#6B5A62' };

                  return (
                    <li key={`${row.kind}-${row.entity_id}`}>
                      <button
                        type="button"
                        role="option"
                        id={`gs-hit-${i}`}
                        aria-selected={i === active}
                        className={`gs-hit${i === active ? ' is-active' : ''}`}
                        /* Pointer move, not enter: moving through the
                           list to reach the one below should not keep
                           snatching the highlight back. */
                        onMouseMove={() => setActive(i)}
                        onClick={() => choose(row)}
                      >
                        <span
                          className="gs-kind"
                          style={{ '--gs-accent': kind.accent }}
                        >
                          {kind.label}
                        </span>

                        <span className="gs-body">
                          <span className="gs-title">
                            {row.title || row.code}
                            {row.status && row.status !== 'ACTIVE' && (
                              <em className="gs-flag">{row.status}</em>
                            )}
                          </span>
                          <span className="gs-sub">
                            {[row.code, row.subtitle].filter(Boolean).join(' · ')}
                          </span>
                        </span>

                        <span className="gs-place">{row.place}</span>
                      </button>
                    </li>
                  );
                })}
              </ul>

              <div className="gs-foot">
                {hidden > 0
                  ? `Showing ${results.length} of ${formatNumber(data.total)} matches. Type more to narrow it.`
                  : `${formatNumber(data.total)} ${
                      data.total === 1 ? 'match' : 'matches'
                    }.`}
                <span className="gs-hint">↑↓ to move · Enter to open</span>
              </div>
            </>
          )}
        </div>
      )}
    </div>
  );
};

export default GlobalSearch;
