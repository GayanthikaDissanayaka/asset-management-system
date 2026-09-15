import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useNavigate, useLocation, useSearchParams } from 'react-router-dom';
import axiosClient from '../../api/axiosClient';
import './auth.css';

// Imported so webpack fingerprints them and hands back a real URL. A raw
// filesystem path in `src` cannot work: the browser has no access to the disk.
import brandFull from './edl-logo.png';
import brandMark from './edl-mark.png';

let toastId = 1;

function useToasts(duration = 5000) {
  const [toasts, setToasts] = useState([]);
  const timers = useRef(new Map());

  const dismiss = useCallback((id) => {
    setToasts((cur) => cur.map((t) => (t.id === id ? { ...t, leaving: true } : t)));
    const t = setTimeout(() => {
      setToasts((cur) => cur.filter((x) => x.id !== id));
      timers.current.delete(id);
    }, 300);
    timers.current.set(`x-${id}`, t);
  }, []);

  const push = useCallback(
    (type, title, message) => {
      const id = toastId++;
      setToasts((cur) => [...cur, { id, type, title, message, life: duration }]);
      timers.current.set(id, setTimeout(() => dismiss(id), duration));
    },
    [duration, dismiss]
  );

  // Clear pending timers if the page unmounts before they fire.
  useEffect(() => {
    const map = timers.current;
    return () => {
      map.forEach(clearTimeout);
      map.clear();
    };
  }, []);

  return {
    toasts,
    dismiss,
    success: (t, m) => push('success', t, m),
    error: (t, m) => push('error', t, m),
    warning: (t, m) => push('warning', t, m),
    info: (t, m) => push('info', t, m),
  };
}

const TOAST_ICONS = { success: '\u2713', error: '!', warning: '!', info: 'i' };

function ToastStack({ toasts, onDismiss }) {
  return (
    <div className="toast-viewport" role="region" aria-live="polite" aria-label="Notifications">
      {toasts.map((t) => (
        <div
          key={t.id}
          className={`toast toast-${t.type}${t.leaving ? ' leaving' : ''}`}
          role={t.type === 'error' ? 'alert' : 'status'}
        >
          <span className="toast-icon" aria-hidden="true">{TOAST_ICONS[t.type]}</span>
          <div className="toast-body">
            {t.title && <p className="toast-title">{t.title}</p>}
            {t.message && <p className="toast-message">{t.message}</p>}
          </div>
          <button className="toast-close" onClick={() => onDismiss(t.id)} aria-label="Dismiss">
            &times;
          </button>
          <span className="toast-progress" />
        </div>
      ))}
    </div>
  );
}


/* =====================================================================
   LOGO — the EDL corporate mark

   The artwork is NOT recreated in code. It is a registered trademark, so
   the files are imported as assets from this folder:

       edl-logo.png   the full lockup with the company name, 400x198
       edl-mark.png   the roundel on its own, 192x192, for tight spaces

   Both are trimmed to the artwork. The originals (Background.jpeg and
   logo.jpeg) sat on a square 2048px canvas that was three quarters empty
   white, which forced the lockup to render tiny inside an oversized plate.

   `size` is the rendered height in CSS pixels. The lockup is 2.02:1, so
   its width is derived from that. Both files are roughly 4x the largest
   size used here, which keeps them sharp on high density screens.

   variant="full"  renders the complete lockup on a white plate
   variant="mark"  renders just the roundel, with text beside it
   ===================================================================== */

function Logo({ size = 44, showText = false, variant = 'mark' }) {
  if (variant === 'full') {
    return (
      <img
        src={brandFull}
        alt="Electricity Distribution Lanka (Pvt) Ltd"
        className="brand-full"
        width={Math.round(size * 2.02)}
        height={size}
      />
    );
  }

  return (
    <div className="brand-lockup">
      <img
        src={brandMark}
        alt="Electricity Distribution Lanka"
        width={size}
        height={size}
        className="brand-mark"
      />
      {showText && (
        <span className="brand-words">
          <span style={{ fontSize: size * 0.37 }}>Uva Province</span>
          <span style={{ fontSize: size * 0.24 }}>Network Asset Management</span>
        </span>
      )}
    </div>
  );
}


/* =====================================================================
   SHARED FORM HELPERS
   ===================================================================== */

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Sri Lankan mobile and landline: 0712345678 or +94712345678.
const PHONE_RE =
  /^(?:\+94|0)(?:7\d{8}|(?:1[1-9]|2[1-9]|3[1-9]|4[1-9]|5[1-9]|6[1-9]|8[1-9]|9[1-9])\d{7})$/;

function passwordScore(pw) {
  let s = 0;
  if (pw.length >= 10) s += 1;
  if (pw.length >= 14) s += 1;
  if (/[a-z]/.test(pw) && /[A-Z]/.test(pw)) s += 1;
  if (/\d/.test(pw)) s += 1;
  if (/[^A-Za-z0-9]/.test(pw)) s += 1;
  return Math.min(s, 4);
}

const STRENGTH = [
  { label: 'Too weak', color: '#B3271A', width: '20%' },
  { label: 'Weak', color: '#D08C34', width: '40%' },
  { label: 'Fair', color: '#D0B334', width: '60%' },
  { label: 'Good', color: '#5C8F3E', width: '80%' },
  { label: 'Strong', color: '#2E7D57', width: '100%' },
];

function AuthAside({ title, body, points }) {
  return (
    <aside className="auth-aside">
      <Logo size={48} variant="full" />
      <h2>{title}</h2>
      <p>{body}</p>
      <ul>{points.map((p) => <li key={p}>{p}</li>)}</ul>
    </aside>
  );
}

function SubmitButton({ loading, idle, busy }) {
  return (
    <button type="submit" className={`auth-submit${loading ? ' loading' : ''}`} disabled={loading}>
      {loading ? (<><span className="spin-dot" />{busy}</>) : idle}
    </button>
  );
}

function PasswordStrength({ value }) {
  if (!value) return null;
  const s = passwordScore(value);
  return (
    <>
      <div className="strength">
        <span style={{ width: STRENGTH[s].width, background: STRENGTH[s].color }} />
      </div>
      <span className="hint">{STRENGTH[s].label}</span>
    </>
  );
}

/** Turns an axios failure into a toast, consistently across every page. */
function reportError(err, toast, fallbackTitle) {
  if (!err.response) {
    toast.error(
      'No response from the server',
      'Check that the Laravel API is running on port 8000.'
    );
  } else {
    toast.error(fallbackTitle, err.response?.data?.message || 'Please try again.');
  }
}


/* =====================================================================
   1. WELCOME
   ===================================================================== */

const STATS = [
  { num: '17', cap: 'Consumer service centres' },
  { num: '5', cap: 'Operational areas' },
  { num: '1,717', cap: 'Transformers registered' },
  { num: '39', cap: 'Asset types tracked' },
];

const FEATURES = [
  {
    icon: '\u2696\uFE0F',
    title: 'Totals that reconcile',
    body: 'Province equals the sum of areas, which equals the sum of all seventeen depots. A switch on a boundary belongs to one depot and appears once.',
  },
  {
    icon: '\u26A1',
    title: 'The network as a graph',
    body: 'Points and spans rather than a flat list, so a line crossing a depot boundary is split at the boundary and each half has a single owner.',
  },
  {
    icon: '\uD83D\uDD52',
    title: 'Nothing lost at handover',
    body: 'Every change is attributed and timestamped. An incoming officer can see who last touched any asset and when.',
  },
  {
    icon: '\uD83D\uDD0D',
    title: 'Data quality in the open',
    body: 'Missing SIN numbers, uncounted substations and orphaned nodes appear as a worklist rather than staying hidden.',
  },
];

export function Welcome() {
  const navigate = useNavigate();

  return (
    <div className="welcome-page">
      <nav className="welcome-nav ">
        <Logo size={42} showText variant="mark" />
        <div className="welcome-nav-actions">
          <button className="btn btn-ghost btn-sm" onClick={() => navigate('/login')}>
            Sign in
          </button>
          <button className="btn btn-primary btn-sm" onClick={() => navigate('/register')}>
            Register
          </button>
        </div>
      </nav>

      <section className="welcome-hero">

        <div>
          <span className="welcome-badge ">
            <span className="live-dot" />
            Uva Province &middot; Asset Management
          </span>

          <h1 className="">
            The distribution network, <em>counted once</em>.
          </h1>

          <p className="lede">
            One authoritative register across five areas and seventeen consumer
            service centres. Depot, area and province totals that reconcile,
            because an asset sitting on a depot boundary belongs to exactly one
            of them.
          </p>

          <div className="welcome-actions">
            <button className="btn btn-primary" onClick={() => navigate('/login')}>
              Sign in to continue
            </button>
            <button className="btn btn-ghost" onClick={() => navigate('/register')}>
              Create an account
            </button>
          </div>
        </div>

        <div className="welcome-stats">
          {STATS.map((s, i) => (
            <div key={s.cap} className={`welcome-stat`}>
              <span className="num">{s.num}</span>
              <span className="cap">{s.cap}</span>
            </div>
          ))}
        </div>
      </section>

      <section className="welcome-features">
        {FEATURES.map((f, i) => (
          <div key={f.title} className={`welcome-feature`}>
            <div className="feature-icon" aria-hidden="true">{f.icon}</div>
            <h3>{f.title}</h3>
            <p>{f.body}</p>
          </div>
        ))}
      </section>

      <footer className="welcome-footer">
        <span>Electricity Distribution Lanka (Pvt) Ltd &middot; Uva Provincial Office</span>
        <span>Internal system. Authorised users only.</span>
      </footer>
    </div>
  );
}


/* =====================================================================
   2. LOGIN
   ===================================================================== */

export function Login() {
  const navigate = useNavigate();
  const location = useLocation();
  const toast = useToasts();

  const [form, setForm] = useState({ email: '', password: '' });
  const [remember, setRemember] = useState(true);
  const [showPassword, setShowPassword] = useState(false);
  const [errors, setErrors] = useState({});
  const [submitting, setSubmitting] = useState(false);

  // Message handed over from registration or a completed reset.
  useEffect(() => {
    if (location.state?.message) {
      toast.success('All set', location.state.message);
      window.history.replaceState({}, '');
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const change = (e) => {
    setForm({ ...form, [e.target.name]: e.target.value });
    setErrors({ ...errors, [e.target.name]: '' });
  };

  const submit = async (e) => {
    e.preventDefault();

    const next = {};
    if (!form.email.trim()) next.email = 'Enter your email address.';
    else if (!EMAIL_RE.test(form.email.trim())) next.email = 'That does not look like a valid email address.';
    if (!form.password) next.password = 'Enter your password.';
    setErrors(next);
    if (Object.keys(next).length) return;

    try {
      setSubmitting(true);
      const { data } = await axiosClient.post('/auth/login', {
        email: form.email.trim().toLowerCase(),
        password: form.password,
      });

      const token = data.token || data.accessToken;
      if (!token) throw new Error('The server did not return a token.');

      const store = remember ? localStorage : sessionStorage;
      store.setItem('ceb_token', token);
      if (data.user) store.setItem('ceb_user', JSON.stringify(data.user));

      toast.success(
        'Welcome to the CEB Asset Management System',
        data.user?.full_name
          ? `Signed in as ${data.user.full_name}.`
          : 'Loading your dashboard.'
      );

      /* The same greeting is handed to the dashboard to show on arrival.
         This toast is only on screen for half a second before the page
         navigates away, which is not long enough to read a welcome --
         and a message nobody can read is not a welcome. sessionStorage
         rather than router state so it survives the redirect and a
         refresh, and is read once and cleared. */
      try {
        sessionStorage.setItem(
          'ceb_welcome',
          JSON.stringify({
            name: data.user?.full_name || '',
            at: Date.now(),
          })
        );
      } catch {
        // Private windows refuse storage; the dashboard simply opens
        // without a greeting, which is not worth failing the sign-in for.
      }

      setTimeout(() => navigate('/dashboard', { replace: true }), 500);
    } catch (err) {
      const status = err.response?.status;
      if (status === 401 || status === 422) {
        toast.error('Sign in failed', 'That email and password combination is not recognised.');
      } else if (status === 423) {
        toast.warning('Account locked', 'Too many failed attempts. Try again in 15 minutes.');
      } else {
        reportError(err, toast, 'Something went wrong');
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="auth-shell">
      <ToastStack toasts={toast.toasts} onDismiss={toast.dismiss} />

      <AuthAside
        title="Welcome back"
        body="Sign in to record assets, maintain the network and review depot totals across Uva Province."
        points={[
          'Depot, area and province rollups',
          'Transformer and asset register',
          'Network map and data quality worklist',
        ]}
      />

      <main className="auth-main">
        <div className="auth-card">
          <Link to="/" className="auth-back">&larr; Back to home</Link>
          <h1>Sign in</h1>
          <p className="sub">Enter your credentials to continue.</p>

          <form onSubmit={submit} noValidate>
            <div className="field">
              <label htmlFor="email">Email address</label>
              <input id="email" name="email" type="email" autoComplete="email"
                     placeholder="name@edl.lk" value={form.email} onChange={change}
                     className={errors.email ? 'invalid' : ''} />
              {errors.email && <span className="field-error">{errors.email}</span>}
            </div>

            <div className="field">
              <label htmlFor="password">Password</label>
              <div className="password-wrap">
                <input id="password" name="password"
                       type={showPassword ? 'text' : 'password'}
                       autoComplete="current-password" placeholder="Your password"
                       value={form.password} onChange={change}
                       className={errors.password ? 'invalid' : ''} />
                <button type="button" className="password-toggle"
                        onClick={() => setShowPassword(!showPassword)}>
                  {showPassword ? 'Hide' : 'Show'}
                </button>
              </div>
              {errors.password && <span className="field-error">{errors.password}</span>}
            </div>

            <div className="auth-row">
              <label>
                <input type="checkbox" checked={remember}
                       onChange={(e) => setRemember(e.target.checked)} />
                Keep me signed in
              </label>
              <Link to="/forgot-password" className="auth-link">Forgot password?</Link>
            </div>

            <SubmitButton loading={submitting} idle="Sign in" busy="Signing in" />
          </form>

          <p className="auth-alt">
            Don't have an account? <Link to="/register" className="auth-link">Create one</Link>
          </p>
        </div>
      </main>
    </div>
  );
}


/* =====================================================================
   3. REGISTER
   ===================================================================== */

export function Register() {
  const navigate = useNavigate();
  const toast = useToasts();

  const [form, setForm] = useState({
    fullName: '', designation: '',
    email: '', phone: '',
    areaId: '', requestedRole: '',
    password: '', confirmPassword: '',
  });
  const [options, setOptions] = useState(null);
  const [showPassword, setShowPassword] = useState(false);
  const [errors, setErrors] = useState({});
  const [submitting, setSubmitting] = useState(false);

  /* Areas, CSCs and the roles that may be asked for. A failure here is
     not fatal: those three fields are optional, and the account can still
     be created without them. */
  useEffect(() => {
    let cancelled = false;
    axiosClient
      .get('/auth/registration-options')
      .then(({ data }) => { if (!cancelled) setOptions(data); })
      .catch(() => { if (!cancelled) setOptions({ areas: [], cscs: [], roles: [] }); });
    return () => { cancelled = true; };
  }, []);

  const areas = options?.areas || [];
  const roles = options?.roles || [];

  const change = (e) => {
    const { name, value } = e.target;
    setForm((f) => ({ ...f, [name]: value }));
    setErrors((prev) => ({ ...prev, [name]: '' }));
  };

  const submit = async (e) => {
    e.preventDefault();

    const next = {};
    if (!form.fullName.trim()) next.fullName = 'Enter your full name.';
    else if (form.fullName.trim().length < 3) next.fullName = 'Name looks too short.';

    if (!form.email.trim()) next.email = 'Enter your email address.';
    else if (!EMAIL_RE.test(form.email.trim())) next.email = 'That does not look like a valid email address.';

    const phone = form.phone.replace(/[\s-]/g, '');
    if (!phone) next.phone = 'Enter your phone number.';
    else if (!PHONE_RE.test(phone)) next.phone = 'Enter a valid number, for example 0712345678.';

    if (!form.password) next.password = 'Choose a password.';
    else if (form.password.length < 10) next.password = 'Use at least 10 characters.';
    else if (passwordScore(form.password) < 2) next.password = 'Mix upper and lower case, digits or symbols.';

    if (form.confirmPassword !== form.password) next.confirmPassword = 'Passwords do not match.';

    setErrors(next);
    if (Object.keys(next).length) {
      toast.warning('Check the form', 'Some fields still need attention.');
      return;
    }

    try {
      setSubmitting(true);
      const { data } = await axiosClient.post('/auth/register', {
        full_name: form.fullName.trim(),
        email: form.email.trim().toLowerCase(),
        phone,
        password: form.password,
        designation: form.designation.trim() || null,
        area_id: form.areaId ? Number(form.areaId) : null,
        requested_role: form.requestedRole || null,
      });

      const token = data.token || data.accessToken;
      if (token) {
        localStorage.setItem('ceb_token', token);
        if (data.user) localStorage.setItem('ceb_user', JSON.stringify(data.user));
        toast.success('Request sent', data.message || 'Signing you in now.');
        setTimeout(() => navigate('/dashboard', { replace: true }), 900);
      } else {
        navigate('/login', {
          replace: true,
          state: { message: data.message || 'Account created. Please sign in.' },
        });
      }
    } catch (err) {
      const status = err.response?.status;
      const fieldErrors = err.response?.data?.errors;

      if (status === 409) {
        setErrors({ email: 'An account with this email already exists.' });
        toast.error('Email already registered', 'Try signing in, or reset your password.');
      } else if (status === 422 && fieldErrors) {
        setErrors(fieldErrors);
        toast.error('Check the form', 'The server rejected some of these details.');
      } else {
        reportError(err, toast, 'Could not create the account');
      }
    } finally {
      setSubmitting(false);
    }
  };

  const chosenRole = roles.find((r) => r.role_code === form.requestedRole);

  return (
    <div className="auth-shell">
      <ToastStack toasts={toast.toasts} onDismiss={toast.dismiss} />

      <AuthAside
        title="Request an account"
        body="Tell us who you are and where you work. Every new account starts read-only, and an administrator assigns your role and depot before you can record or edit asset data."
        points={[
          'Read access to dashboards and reports straight away',
          'Your request goes to an administrator for approval',
          'Editing opens once your role and depot are assigned',
        ]}
      />

      <main className="auth-main">
        {/* Compact so the whole request fits one screen without scrolling:
            every field is paired, and the hints sit in placeholders. */}
        <div className="auth-card auth-card-wide auth-card-compact">
          <Link to="/" className="auth-back">&larr; Back to home</Link>
          <h1>Request an account</h1>
          <p className="sub">Read-only until an administrator assigns your role.</p>

          <form onSubmit={submit} noValidate>

            <fieldset className="form-section">
              <legend>Who you are</legend>

              <div className="field-row">
                <div className="field">
                  <label htmlFor="fullName">Full name *</label>
                  <input id="fullName" name="fullName" type="text" autoComplete="name"
                         placeholder="K. Jayasekara" value={form.fullName} onChange={change}
                         className={errors.fullName ? 'invalid' : ''} />
                  {errors.fullName && <span className="field-error">{errors.fullName}</span>}
                </div>

                <div className="field">
                  <label htmlFor="designation">Designation</label>
                  <input id="designation" name="designation" type="text"
                         placeholder="Electrical Superintendent" value={form.designation}
                         onChange={change} />
                </div>
              </div>

              <div className="field-row">
                <div className="field">
                  <label htmlFor="reg-email">Email address *</label>
                  <input id="reg-email" name="email" type="email" autoComplete="email"
                         placeholder="name@edl.lk" value={form.email} onChange={change}
                         className={errors.email ? 'invalid' : ''} />
                  {errors.email && <span className="field-error">{errors.email}</span>}
                </div>

                <div className="field">
                  <label htmlFor="phone">Phone number *</label>
                  <input id="phone" name="phone" type="tel" autoComplete="tel"
                         placeholder="0712345678" value={form.phone} onChange={change}
                         className={errors.phone ? 'invalid' : ''} />
                  {errors.phone && <span className="field-error">{errors.phone}</span>}
                </div>
              </div>
            </fieldset>

            <fieldset className="form-section">
              <legend>Where you work</legend>

              <div className="field-row">
                <div className="field">
                  <label htmlFor="areaId">Area</label>
                  <select id="areaId" name="areaId" value={form.areaId} onChange={change}
                          className={errors.areaId ? 'invalid' : ''}>
                    <option value="">Not sure yet</option>
                    {areas.map((a) => (
                      <option key={a.area_id} value={a.area_id}>
                        {a.area_name} ({a.area_code})
                      </option>
                    ))}
                  </select>
                  {errors.areaId && <span className="field-error">{errors.areaId}</span>}
                </div>

                <div className="field">
                  <label htmlFor="requestedRole">Access you need</label>
                  <select id="requestedRole" name="requestedRole"
                          value={form.requestedRole} onChange={change}>
                    <option value="">Read only is fine</option>
                    {roles.map((r) => (
                      <option key={r.role_id} value={r.role_code}>{r.role_name}</option>
                    ))}
                  </select>
                </div>
              </div>

              {chosenRole && <span className="hint">{chosenRole.description}</span>}
            </fieldset>

            <fieldset className="form-section">
              <legend>Choose a password</legend>

              <div className="field-row">
                <div className="field">
                  <label htmlFor="reg-password">Password *</label>
                  <div className="password-wrap">
                    <input id="reg-password" name="password"
                           type={showPassword ? 'text' : 'password'}
                           autoComplete="new-password" placeholder="At least 10 characters"
                           value={form.password} onChange={change}
                           className={errors.password ? 'invalid' : ''} />
                    <button type="button" className="password-toggle"
                            onClick={() => setShowPassword(!showPassword)}>
                      {showPassword ? 'Hide' : 'Show'}
                    </button>
                  </div>
                  <PasswordStrength value={form.password} />
                  {errors.password && <span className="field-error">{errors.password}</span>}
                </div>

                <div className="field">
                  <label htmlFor="confirmPassword">Confirm password *</label>
                  <input id="confirmPassword" name="confirmPassword"
                         type={showPassword ? 'text' : 'password'}
                         autoComplete="new-password" placeholder="Type it again"
                         value={form.confirmPassword} onChange={change}
                         className={errors.confirmPassword ? 'invalid' : ''} />
                  {errors.confirmPassword && (
                    <span className="field-error">{errors.confirmPassword}</span>
                  )}
                </div>
              </div>
            </fieldset>

            <SubmitButton loading={submitting} idle="Send request" busy="Sending request" />
          </form>

          <p className="auth-alt">
            Already registered? <Link to="/login" className="auth-link">Sign in</Link>
          </p>
        </div>
      </main>
    </div>
  );
}




/* =====================================================================
   4. FORGOT PASSWORD
   The success screen shows whether or not the email exists. Saying "no
   such account" would let anyone test which addresses are registered.
   The API must behave the same way and always return 200.
   ===================================================================== */

export function ForgotPassword() {
  const toast = useToasts();
  const [email, setEmail] = useState('');
  const [error, setError] = useState('');
  const [sent, setSent] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const submit = async (e) => {
    e.preventDefault();

    if (!email.trim()) { setError('Enter your email address.'); return; }
    if (!EMAIL_RE.test(email.trim())) {
      setError('That does not look like a valid email address.');
      return;
    }

    try {
      setSubmitting(true);
      setError('');
      await axiosClient.post('/auth/forgot-password', {
        email: email.trim().toLowerCase(),
      });
      setSent(true);
      toast.success('Email sent', 'Check your inbox for the reset link.');
    } catch (err) {
      // A 404 would leak which emails are registered, so only real server
      // failures are surfaced.
      if (err.response && err.response.status < 500) {
        setSent(true);
        toast.success('Email sent', 'Check your inbox for the reset link.');
      } else {
        reportError(err, toast, 'Could not send the reset link');
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="auth-shell">
      <ToastStack toasts={toast.toasts} onDismiss={toast.dismiss} />

      <AuthAside
        title="Reset your password"
        body="We'll email you a link to set a new password. The link works once and expires after one hour."
        points={[
          "Check your spam folder if it doesn't arrive",
          'The link can only be used a single time',
          'Your old password stays active until you set a new one',
        ]}
      />

      <main className="auth-main">
        <div className="auth-card">
          <Link to="/login" className="auth-back">&larr; Back to sign in</Link>

          {sent ? (
            <>
              <h1>Check your email</h1>
              <p className="sub">
                If an account exists for <strong>{email.trim().toLowerCase()}</strong>,
                a reset link is on its way.
              </p>
              <div className="alert alert-success">
                The link expires in one hour and can be used once. If it doesn't
                arrive within a few minutes, check your spam folder.
              </div>
              <button className="auth-submit"
                      onClick={() => { setSent(false); setEmail(''); }}>
                Send to a different address
              </button>
              <p className="auth-alt">
                <Link to="/login" className="auth-link">Return to sign in</Link>
              </p>
            </>
          ) : (
            <>
              <h1>Forgot password</h1>
              <p className="sub">
                Enter the email address on your account and we'll send a reset link.
              </p>

              <form onSubmit={submit} noValidate>
                <div className="field">
                  <label htmlFor="fp-email">Email address</label>
                  <input id="fp-email" name="email" type="email" autoComplete="email"
                         placeholder="name@edl.lk" value={email}
                         onChange={(e) => { setEmail(e.target.value); setError(''); }}
                         className={error ? 'invalid' : ''} />
                  {error && <span className="field-error">{error}</span>}
                </div>

                <SubmitButton loading={submitting} idle="Send reset link" busy="Sending" />
              </form>

              <p className="auth-alt">
                Remembered it? <Link to="/login" className="auth-link">Sign in</Link>
              </p>
            </>
          )}
        </div>
      </main>
    </div>
  );
}


/* =====================================================================
   5. RESET PASSWORD
   Reached from the emailed link: /reset-password?token=abc123
   ===================================================================== */

export function ResetPassword() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token') || '';
  const toast = useToasts();

  const [form, setForm] = useState({ password: '', confirmPassword: '' });
  const [showPassword, setShowPassword] = useState(false);
  const [errors, setErrors] = useState({});
  const [submitting, setSubmitting] = useState(false);

  const change = (e) => {
    setForm({ ...form, [e.target.name]: e.target.value });
    setErrors({ ...errors, [e.target.name]: '' });
  };

  const submit = async (e) => {
    e.preventDefault();

    const next = {};
    if (!form.password) next.password = 'Choose a new password.';
    else if (form.password.length < 10) next.password = 'Use at least 10 characters.';
    else if (passwordScore(form.password) < 2) next.password = 'Mix upper and lower case, digits or symbols.';
    if (form.confirmPassword !== form.password) next.confirmPassword = 'Passwords do not match.';

    setErrors(next);
    if (Object.keys(next).length) return;

    try {
      setSubmitting(true);
      await axiosClient.post('/auth/reset-password', { token, password: form.password });
      navigate('/login', {
        replace: true,
        state: { message: 'Password updated. Please sign in.' },
      });
    } catch (err) {
      const status = err.response?.status;
      if (status === 400 || status === 410) {
        toast.error('Link expired', 'This reset link has expired or has already been used.');
      } else {
        reportError(err, toast, 'Could not reset the password');
      }
    } finally {
      setSubmitting(false);
    }
  };

  // Some email clients truncate long links.
  if (!token) {
    return (
      <div className="auth-shell">
        <AuthAside
          title="Reset link problem"
          body="The link is missing its token. Request a fresh one."
          points={['Open the link directly from the email', 'Avoid copying it by hand']}
        />
        <main className="auth-main">
          <div className="auth-card">
            <h1>Invalid reset link</h1>
            <p className="sub">This link has no reset token.</p>
            <div className="alert alert-error">
              Request a new link and open it directly from the email rather than
              copying it by hand.
            </div>
            <Link to="/forgot-password">
              <button className="auth-submit">Request a new link</button>
            </Link>
          </div>
        </main>
      </div>
    );
  }

  return (
    <div className="auth-shell">
      <ToastStack toasts={toast.toasts} onDismiss={toast.dismiss} />

      <AuthAside
        title="Set a new password"
        body="Choose something you haven't used elsewhere. Once saved, this reset link stops working."
        points={['At least 10 characters', 'Mix cases, digits or symbols', 'Not reused from another site']}
      />

      <main className="auth-main">
        <div className="auth-card">
          <h1>New password</h1>
          <p className="sub">Enter it twice so we know it's right.</p>

          <form onSubmit={submit} noValidate>
            <div className="field">
              <label htmlFor="rp-password">New password</label>
              <div className="password-wrap">
                <input id="rp-password" name="password"
                       type={showPassword ? 'text' : 'password'}
                       autoComplete="new-password" placeholder="At least 10 characters"
                       value={form.password} onChange={change}
                       className={errors.password ? 'invalid' : ''} />
                <button type="button" className="password-toggle"
                        onClick={() => setShowPassword(!showPassword)}>
                  {showPassword ? 'Hide' : 'Show'}
                </button>
              </div>
              <PasswordStrength value={form.password} />
              {errors.password && <span className="field-error">{errors.password}</span>}
            </div>

            <div className="field">
              <label htmlFor="rp-confirm">Confirm new password</label>
              <input id="rp-confirm" name="confirmPassword"
                     type={showPassword ? 'text' : 'password'}
                     autoComplete="new-password" placeholder="Type it again"
                     value={form.confirmPassword} onChange={change}
                     className={errors.confirmPassword ? 'invalid' : ''} />
              {errors.confirmPassword && (
                <span className="field-error">{errors.confirmPassword}</span>
              )}
            </div>

            <SubmitButton loading={submitting} idle="Save new password" busy="Saving" />
          </form>

          <p className="auth-alt">
            <Link to="/login" className="auth-link">Return to sign in</Link>
          </p>
        </div>
      </main>
    </div>
  );
}

/* Default export is the landing page, so `import Welcome from './Auth'`
   also works if you prefer that style. */
export default Welcome;