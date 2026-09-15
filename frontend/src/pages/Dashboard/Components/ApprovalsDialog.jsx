import React, { useCallback, useEffect, useMemo, useState } from 'react';

import axiosClient from '../../../api/axiosClient';
import { describeWriteError } from './session';

/**
 * Account approval, for administrators.
 *
 * This is the other half of self-registration. A new account arrives as a
 * Viewer with no scope, which is what puts it in the pending queue; here
 * an administrator gives it a role and says which area or CSC that role
 * applies to. Those go together, so they are one action rather than
 * three separate edits.
 *
 * Roles that name a place have that place required: an Area Engineer
 * without an area, or a Depot Engineer without a CSC, would hold a role
 * pointing at nothing. The server enforces it too; this only saves a
 * round trip.
 *
 * Nothing here needs the person to sign in again. A token carries no role
 * of its own — the role is read from the user on every request — so a
 * grant takes effect on their next page load.
 */

/** Which scope each role must be given, mirroring the API's rules. */
const SCOPE_NEEDED = {
  AREA_ENGINEER: 'area',
  ENGINEER: 'csc',
  TECHNICIAN: 'csc',
};

const ApprovalsDialog = ({ open, onClose, onChanged }) => {
  const [pending, setPending] = useState(null);
  const [roles, setRoles] = useState([]);
  const [areas, setAreas] = useState([]);
  const [cscs, setCscs] = useState([]);
  const [drafts, setDrafts] = useState({});
  const [busyId, setBusyId] = useState(null);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setError('');
    try {
      const [queue, grantable, options] = await Promise.all([
        axiosClient.get('/admin/pending-users'),
        axiosClient.get('/admin/grantable-roles'),
        axiosClient.get('/auth/registration-options'),
      ]);

      setPending(queue.data || []);
      setRoles(grantable.data || []);
      setAreas(options.data?.areas || []);
      setCscs(options.data?.cscs || []);

      // Start each row from what the applicant asked for.
      const seeded = {};
      for (const u of queue.data || []) {
        seeded[u.user_id] = {
          roleCode: u.requested_role_code || 'VIEWER',
          areaId: u.area_id ? String(u.area_id) : '',
          cscId: u.csc_id ? String(u.csc_id) : '',
        };
      }
      setDrafts(seeded);
    } catch (err) {
      setPending([]);
      setError(describeWriteError(err));
    }
  }, []);

  useEffect(() => {
    if (open) load();
  }, [open, load]);

  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => {
      if (e.key === 'Escape' && !busyId) onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose, busyId]);

  const cscsByArea = useMemo(() => {
    const map = new Map();
    for (const c of cscs) {
      const key = String(c.area_id);
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(c);
    }
    return map;
  }, [cscs]);

  const setDraft = (userId, patch) => {
    setDrafts((d) => {
      const next = { ...(d[userId] || {}), ...patch };
      // A CSC belongs to an area, so switching area clears the CSC.
      if (patch.areaId !== undefined) next.cscId = '';
      return { ...d, [userId]: next };
    });
    setError('');
  };

  const approve = async (user) => {
    const draft = drafts[user.user_id] || {};
    const needs = SCOPE_NEEDED[draft.roleCode];

    if (needs === 'area' && !draft.areaId) {
      setError(`${user.full_name}: an Area Engineer needs an area.`);
      return;
    }
    if (needs === 'csc' && !draft.cscId) {
      setError(`${user.full_name}: that role needs a CSC.`);
      return;
    }

    setBusyId(user.user_id);
    setError('');
    try {
      const { data } = await axiosClient.post(
        `/admin/users/${user.user_id}/approve`,
        {
          role_code: draft.roleCode,
          area_id: draft.areaId ? Number(draft.areaId) : null,
          csc_id: draft.cscId ? Number(draft.cscId) : null,
        }
      );
      setPending((list) => list.filter((u) => u.user_id !== user.user_id));
      onChanged?.(data.message);
    } catch (err) {
      setError(describeWriteError(err));
    } finally {
      setBusyId(null);
    }
  };

  const decline = async (user) => {
    setBusyId(user.user_id);
    setError('');
    try {
      const { data } = await axiosClient.post(`/admin/users/${user.user_id}/decline`);
      setPending((list) => list.filter((u) => u.user_id !== user.user_id));
      onChanged?.(data.message);
    } catch (err) {
      setError(describeWriteError(err));
    } finally {
      setBusyId(null);
    }
  };

  if (!open) return null;

  return (
    <div
      className="dialog-backdrop"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget && !busyId) onClose();
      }}
    >
      <div className="dialog" role="dialog" aria-modal="true" aria-labelledby="approvals-title">
        <header className="dialog-head">
          <div>
            <h2 id="approvals-title">Account requests</h2>
            <p>Give a role, and say which area or CSC it covers.</p>
          </div>
          <button type="button" className="dialog-close" onClick={onClose} aria-label="Close">
            &times;
          </button>
        </header>

        <div className="dialog-body">
          {error && <div className="dialog-error">{error}</div>}

          {pending === null && <div className="dialog-notice">Loading requests...</div>}

          {pending !== null && pending.length === 0 && (
            <div className="dialog-notice">
              No requests waiting. New sign-ups appear here.
            </div>
          )}

          {(pending || []).map((u) => {
            const draft = drafts[u.user_id] || {};
            const needs = SCOPE_NEEDED[draft.roleCode];
            const areaCscs = cscsByArea.get(String(draft.areaId)) || [];
            const busy = busyId === u.user_id;

            return (
              <div className="approval-row" key={u.user_id}>
                <div className="approval-who">
                  <strong>{u.full_name}</strong>
                  <span>{u.email}</span>
                  {u.designation && <span>{u.designation}</span>}
                  {u.requested_role_name && (
                    <span className="approval-asked">
                      asked for {u.requested_role_name}
                    </span>
                  )}
                </div>

                <div className="approval-grant">
                  <label className="field">
                    <span>Role</span>
                    <select
                      value={draft.roleCode || 'VIEWER'}
                      onChange={(e) => setDraft(u.user_id, { roleCode: e.target.value })}
                      disabled={busy}
                    >
                      {roles.map((r) => (
                        <option key={r.role_id} value={r.role_code}>{r.role_name}</option>
                      ))}
                    </select>
                  </label>

                  <label className="field">
                    <span>Area {needs === 'area' ? '*' : ''}</span>
                    <select
                      value={draft.areaId || ''}
                      onChange={(e) => setDraft(u.user_id, { areaId: e.target.value })}
                      disabled={busy}
                    >
                      <option value="">Province-wide</option>
                      {areas.map((a) => (
                        <option key={a.area_id} value={a.area_id}>{a.area_name}</option>
                      ))}
                    </select>
                  </label>

                  <label className="field">
                    <span>CSC {needs === 'csc' ? '*' : ''}</span>
                    <select
                      value={draft.cscId || ''}
                      onChange={(e) => setDraft(u.user_id, { cscId: e.target.value })}
                      disabled={busy || !draft.areaId}
                    >
                      <option value="">
                        {draft.areaId ? 'Whole area' : 'Choose an area first'}
                      </option>
                      {areaCscs.map((c) => (
                        <option key={c.csc_id} value={c.csc_id}>{c.csc_name}</option>
                      ))}
                    </select>
                  </label>
                </div>

                <div className="approval-actions">
                  <button
                    type="button"
                    className="dash-btn-primary dash-btn-sm"
                    onClick={() => approve(u)}
                    disabled={busy}
                  >
                    {busy ? 'Saving...' : 'Grant access'}
                  </button>
                  <button
                    type="button"
                    className="dash-btn-quiet dash-btn-sm"
                    onClick={() => decline(u)}
                    disabled={busy}
                  >
                    Decline
                  </button>
                </div>
              </div>
            );
          })}
        </div>

        <footer className="dialog-foot">
          <button type="button" className="dash-btn-quiet" onClick={onClose} disabled={Boolean(busyId)}>
            Close
          </button>
          <div className="dialog-foot-right">
            <button type="button" className="dash-btn-quiet" onClick={load} disabled={Boolean(busyId)}>
              Refresh list
            </button>
          </div>
        </footer>
      </div>
    </div>
  );
};

export default ApprovalsDialog;
