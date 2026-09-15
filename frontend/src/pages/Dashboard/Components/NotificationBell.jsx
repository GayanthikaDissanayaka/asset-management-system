import React, { useCallback, useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';

import axiosClient from '../../../api/axiosClient';
import { useCurrentUser } from './session';

/*
 * Access requests, announced.
 *
 * Before this an administrator only learned that somebody had registered
 * by happening to open the Approvals dialog, so new staff waited for
 * access nobody knew they had asked for.
 *
 * Three signals, from loudest to quietest:
 *
 *   POP-UP  a card in the corner the first time a request is seen, with
 *           Review and Later. Shown once per request per session, so it
 *           announces rather than nags.
 *
 *   BADGE   the number of requests still waiting, on the bell, for as
 *           long as they wait -- "Later" does not make it go away,
 *           because the request has not gone away.
 *
 *   TITLE   "(2) CEB Uva Province ..." in the browser tab, so a request
 *           is visible even from another tab.
 *
 * Polls every 20 seconds and whenever the window regains focus. The rows
 * live in the notifications table (written by AdminNotifier on
 * registration), so they survive a refresh and are closed for every
 * administrator the moment any one of them decides the request.
 *
 * Administrators only. Nobody else receives these yet.
 */

const POLL_MS = 20000;
const SHOWN_KEY = 'ceb_notifications_shown';

const readShown = () => {
  try {
    return JSON.parse(sessionStorage.getItem(SHOWN_KEY) || '[]');
  } catch {
    return [];
  }
};

const rememberShown = (id) => {
  try {
    const next = [...readShown(), id].slice(-50);
    sessionStorage.setItem(SHOWN_KEY, JSON.stringify(next));
  } catch {
    // Private windows refuse storage; the pop-up may repeat after a
    // refresh, which is the safer failure.
  }
};

function timeAgo(stamp) {
  if (!stamp) return '';
  const then = new Date(String(stamp).replace(' ', 'T')).getTime();
  if (Number.isNaN(then)) return '';
  const minutes = Math.round((Date.now() - then) / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours} h ago`;
  return `${Math.round(hours / 24)} d ago`;
}

const BellIcon = () => (
  <svg viewBox="0 0 24 24" width="17" height="17" aria-hidden="true" focusable="false">
    <path
      fill="currentColor"
      d="M12 22a2.5 2.5 0 0 0 2.45-2h-4.9A2.5 2.5 0 0 0 12 22Zm7-6V11a7 7 0 0 0-5.5-6.84V3.5a1.5 1.5 0 0 0-3 0v.66A7 7 0 0 0 5 11v5l-1.7 1.7A1 1 0 0 0 4 19.4h16a1 1 0 0 0 .7-1.7L19 16Z"
    />
  </svg>
);

const NotificationBell = ({ onReview, onCount, refreshKey = 0 }) => {
  const navigate = useNavigate();
  const user = useCurrentUser();
  const isAdmin = user?.role === 'ADMIN';

  const [data, setData] = useState(null);
  const [open, setOpen] = useState(false);
  const [popup, setPopup] = useState(null);

  const boxRef = useRef(null);
  const baseTitle = useRef(document.title.replace(/^\(\d+\)\s*/, ''));

  const load = useCallback(async () => {
    try {
      const { data: body } = await axiosClient.get('/notifications');
      setData(body);
    } catch {
      // Keep the last answer. A dropped poll should not blank the badge.
    }
  }, []);

  useEffect(() => {
    if (!isAdmin) return undefined;

    load();
    const timer = setInterval(load, POLL_MS);
    const onFocus = () => load();
    window.addEventListener('focus', onFocus);

    return () => {
      clearInterval(timer);
      window.removeEventListener('focus', onFocus);
    };
  }, [isAdmin, load, refreshKey]);

  // Put the tab title back when the page that owns the bell goes away.
  useEffect(() => {
    const title = baseTitle.current;
    return () => {
      document.title = title;
    };
  }, []);

  const pending = data?.pending_requests || 0;
  const unread = data?.unread_count || 0;
  const items = data?.items || [];

  useEffect(() => {
    if (!data) return;

    onCount?.(pending);
    document.title = pending > 0 ? `(${pending}) ${baseTitle.current}` : baseTitle.current;

    const shown = readShown();
    const fresh = items.find(
      (n) => n.status === 'OPEN' && !n.read_at && !shown.includes(n.notification_id)
    );

    if (fresh) {
      rememberShown(fresh.notification_id);
      setPopup(fresh);
    }
    // `items` and `pending` both derive from `data`.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [data, onCount]);

  useEffect(() => {
    if (!open) return undefined;
    const onDown = (e) => {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener('mousedown', onDown);
    return () => document.removeEventListener('mousedown', onDown);
  }, [open]);

  const markRead = async (id) => {
    try {
      await axiosClient.post(`/notifications/${id}/read`);
    } catch {
      // Not worth interrupting anyone over; the next poll corrects it.
    }
    load();
  };

  const markAllRead = async () => {
    try {
      await axiosClient.post('/notifications/read-all');
    } catch {
      /* the next poll corrects it */
    }
    load();
  };

  const review = (note) => {
    if (note?.notification_id && !note.read_at) markRead(note.notification_id);
    setPopup(null);
    setOpen(false);

    if (onReview) onReview(note);
    else navigate(note?.link || '/dashboard?approvals=open');
  };

  if (!isAdmin) return null;

  const firstOpen = items.find((n) => n.status === 'OPEN');

  return (
    <div className="nb" ref={boxRef}>
      <button
        type="button"
        className={`nb-bell${pending > 0 ? ' has-count' : ''}`}
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
        aria-label={
          pending > 0
            ? `${pending} access request${pending === 1 ? '' : 's'} waiting`
            : 'Notifications'
        }
        title={
          pending > 0
            ? `${pending} access request${pending === 1 ? '' : 's'} waiting for a decision`
            : 'No requests waiting'
        }
      >
        <BellIcon />
        {pending > 0 && <span className="nb-count">{pending}</span>}
      </button>

      {open && (
        <div className="nb-panel" role="dialog" aria-label="Notifications">
          <div className="nb-head">
            <strong>Notifications</strong>
            {unread > 0 && (
              <button type="button" className="link-button" onClick={markAllRead}>
                Mark all read
              </button>
            )}
          </div>

          {items.length === 0 ? (
            <p className="nb-empty">Nothing yet. New access requests appear here.</p>
          ) : (
            <ul className="nb-list">
              {items.slice(0, 8).map((n) => (
                <li key={n.notification_id}>
                  <button
                    type="button"
                    className={`nb-item${n.read_at ? '' : ' is-unread'}${
                      n.status === 'RESOLVED' ? ' is-resolved' : ''
                    }`}
                    onClick={() => review(n)}
                  >
                    <span className="nb-item-title">{n.title}</span>
                    {n.body && <span className="nb-item-body">{n.body}</span>}
                    <span className="nb-item-meta">
                      {n.status === 'RESOLVED'
                        ? `Handled${n.resolution ? ` · ${n.resolution}` : ''}`
                        : 'Waiting for a decision'}
                      {' · '}
                      {timeAgo(n.created_at)}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}

          {pending > 0 && (
            <button
              type="button"
              className="dash-btn-primary dash-btn-sm nb-review"
              onClick={() => review(firstOpen)}
            >
              Review {pending} waiting request{pending === 1 ? '' : 's'}
            </button>
          )}
        </div>
      )}

      {popup && (
        <div className="nb-popup" role="alert">
          <span className="nb-popup-icon" aria-hidden="true">
            <BellIcon />
          </span>

          <div className="nb-popup-text">
            <strong>New access request</strong>
            <span>
              {popup.title.replace(/^Access request from\s*/, '')}
              {popup.body ? ` — ${popup.body}` : ''}
            </span>
          </div>

          <div className="nb-popup-actions">
            <button
              type="button"
              className="dash-btn-primary dash-btn-sm"
              onClick={() => review(popup)}
            >
              Review
            </button>
            <button
              type="button"
              className="dash-btn-quiet dash-btn-sm"
              onClick={() => {
                markRead(popup.notification_id);
                setPopup(null);
              }}
            >
              Later
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

export default NotificationBell;
