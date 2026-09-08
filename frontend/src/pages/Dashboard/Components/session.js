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

export function currentUser() {
  try {
    const raw =
      localStorage.getItem('ceb_user') || sessionStorage.getItem('ceb_user');
    return raw ? JSON.parse(raw) : null;
  } catch {
    // Private windows and cleared site data both land here.
    return null;
  }
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
