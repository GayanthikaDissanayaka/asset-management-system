import React, { useEffect, useState } from 'react';
import { Link, useNavigate, useLocation } from 'react-router-dom';
import axiosClient from '../../api/axiosClient';
import Logo from '../../components/Logo';
import PowerGrid from '../../components/PowerGrid';
import { useToast } from '../../components/Toast';
import './Auth.css';

const Login = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const toast = useToast();

  const [form, setForm] = useState({ email: '', password: '' });
  const [remember, setRemember] = useState(true);
  const [showPassword, setShowPassword] = useState(false);
  const [errors, setErrors] = useState({});
  const [shake, setShake] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  // Message handed over from registration or a completed password reset.
  useEffect(() => {
    if (location.state?.message) {
      toast.success('All set', location.state.message);
      window.history.replaceState({}, '');
    }
    // Run once on mount only.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const change = (e) => {
    setForm({ ...form, [e.target.name]: e.target.value });
    setErrors({ ...errors, [e.target.name]: '' });
  };

  const failShake = () => {
    setShake(true);
    setTimeout(() => setShake(false), 520);
  };

  const validate = () => {
    const next = {};
    if (!form.email.trim()) {
      next.email = 'Enter your email address.';
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim())) {
      next.email = 'That does not look like a valid email address.';
    }
    if (!form.password) next.password = 'Enter your password.';
    setErrors(next);
    if (Object.keys(next).length > 0) failShake();
    return Object.keys(next).length === 0;
  };

  const submit = async (e) => {
    e.preventDefault();
    if (!validate()) return;

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
        'Signed in',
        data.user?.full_name ? `Welcome back, ${data.user.full_name}.` : 'Loading your dashboard.'
      );

      setTimeout(() => navigate('/dashboard', { replace: true }), 500);
    } catch (err) {
      const status = err.response?.status;
      failShake();

      if (status === 401 || status === 422) {
        toast.error('Sign in failed', 'That email and password combination is not recognised.');
      } else if (status === 423) {
        toast.warning(
          'Account locked',
          'Too many failed attempts. Try again in 15 minutes or reset your password.'
        );
      } else if (!err.response) {
        toast.error('No response from the server', 'Check that the Laravel API is running on port 8000.');
      } else {
        toast.error('Something went wrong', err.response?.data?.message || 'Please try again.');
      }
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="auth-shell">
      <aside className="auth-aside">
        <PowerGrid className="aside-grid-art" />
        <Logo size={52} showText variant="light" />
        <h2>Welcome back</h2>
        <p>
          Sign in to record assets, maintain the network and review depot
          totals across Uva Province.
        </p>
        <ul>
          <li>Depot, area and province rollups</li>
          <li>Transformer and asset register</li>
          <li>Network map and data quality worklist</li>
        </ul>
      </aside>

      <main className="auth-main">
        <div className={`auth-card anim-fade-up${shake ? ' anim-shake' : ''}`}>
          <Link to="/" className="auth-back">&larr; Back to home</Link>

          <h1>Sign in</h1>
          <p className="sub">Enter your credentials to continue.</p>

          <form onSubmit={submit} noValidate>
            <div className="field">
              <label htmlFor="email">Email address</label>
              <input
                id="email"
                name="email"
                type="email"
                autoComplete="email"
                placeholder="name@edl.lk"
                value={form.email}
                onChange={change}
                className={errors.email ? 'invalid' : ''}
              />
              {errors.email && <span className="field-error">{errors.email}</span>}
            </div>

            <div className="field">
              <label htmlFor="password">Password</label>
              <div className="password-wrap">
                <input
                  id="password"
                  name="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  placeholder="Your password"
                  value={form.password}
                  onChange={change}
                  className={errors.password ? 'invalid' : ''}
                />
                <button
                  type="button"
                  className="password-toggle"
                  onClick={() => setShowPassword(!showPassword)}
                >
                  {showPassword ? 'Hide' : 'Show'}
                </button>
              </div>
              {errors.password && <span className="field-error">{errors.password}</span>}
            </div>

            <div className="auth-row">
              <label>
                <input
                  type="checkbox"
                  checked={remember}
                  onChange={(e) => setRemember(e.target.checked)}
                />
                Keep me signed in
              </label>
              <Link to="/forgot-password" className="auth-link">Forgot password?</Link>
            </div>

            <button
              type="submit"
              className={`auth-submit${submitting ? ' loading' : ''}`}
              disabled={submitting}
            >
              {submitting ? (<><span className="spin-dot" />Signing in</>) : 'Sign in'}
            </button>
          </form>

          <p className="auth-alt">
            Don't have an account? <Link to="/register" className="auth-link">Create one</Link>
          </p>
        </div>
      </main>
    </div>
  );
};

export default Login;