import { useEffect, useState } from 'react';

import axiosClient from '../../../api/axiosClient';

/* =====================================================================
   Who is signed in, and what they are allowed to do.

   The token and the user are written at sign-in by the auth screens,
   into localStorage when "keep me signed in" was ticked and into
   sessionStorage otherwise, so both are checked here.

   This is for the INTERFACE only — deciding whether to offer a button.
   It is not a security boundary. The server checks the same roles on
   every write, and a viewer who reached the endpoint another way still
   gets a 403. Never treat this as the gate.
   ===================================================================== */

/** Roles allowed to record network data. Mirrors the API's route gate. */
export const WRITE_ROLES = ['ADMIN', 'AREA_ENGINEER', 'ENGINEER'];

const STORAGE_KEY = 'ceb_user';

export function currentUser() {
  try {
    const raw =
      localStorage.getItem(STORAGE_KEY) || sessionStorage.getItem(STORAGE_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    // Private windows and cleared site data both land here.
    return null;
  }
}

/** Keeps the stored copy in step, in whichever store it already lives. */
function persistUser(user) {
  try {
    const store = localStorage.getItem(STORAGE_KEY) ? localStorage : sessionStorage;
    store.setItem(STORAGE_KEY, JSON.stringify(user));
  } catch {
    // Nothing to do; the in-memory copy is still correct for this session.
  }
}

/**
 * The signed-in user, starting from the stored copy and then confirmed
 * against the server.
 *
 * The stored copy is written once at sign-in and never changes after
 * that, so an administrator who widens someone's role would otherwise
 * have to tell them to sign out and back in before the buttons appeared.
 * Re-reading /auth/me on mount removes that trap: the role is whatever
 * the database says by the next page load.
 */
export function useCurrentUser() {
  const [user, setUser] = useState(currentUser);

  useEffect(() => {
    let cancelled = false;

    axiosClient
      .get('/auth/me')
      .then(({ data }) => {
        if (cancelled || !data) return;
        setUser(data);
        persistUser(data);
      })
      .catch(() => {
        // Offline, or the token has expired. The stored copy still says
        // who they were, and every write is checked server-side anyway.
      });

    return () => {
      cancelled = true;
    };
  }, []);

  return user;
}

export function canWriteNetwork(user) {
  return Boolean(user && WRITE_ROLES.includes(user.role));
}

/**
 * Turns a failed write into something worth reading.
 *
 * 401 and 403 mean different things and need different advice: one is
 * "sign in again", the other is "you are signed in but not permitted".
 */
export function describeWriteError(err, fallback) {
  const status = err.response?.status;

  if (status === 401) {
    return 'Your session has ended. Sign in again to record data.';
  }

  if (status === 403) {
    return (
      err.response?.data?.message ||
      'Your role does not allow recording network data. An administrator can widen your access.'
    );
  }

  return (
    err.response?.data?.message ||
    (err.response
      ? `The server returned ${status}.`
      : fallback ||
        'Could not reach the API. Check that Laravel is running on port 8000.')
  );
}
