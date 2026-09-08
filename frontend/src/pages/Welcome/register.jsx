import React, { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import axiosClient from '../../api/axiosClient';
import Logo from '../../components/Logo';
import PowerGrid from '../../components/PowerGrid';
import { useToast } from '../../components/Toast';
import './Auth.css';

// Sri Lankan mobile and landline: 0712345678, or +94712345678.
const PHONE_RE = /^(?:\+94|0)(?:7\d{8}|(?:1[1-9]|2[1-9]|3[1-9]|4[1-9]|5[1-9]|6[1-9]|8[1-9]|9[1-9])\d{7})$/;

function passwordScore(pw) {
  let score = 0;
  if (pw.length >= 10) score += 1;
  if (pw.length >= 14) score += 1;
  if (/[a-z]/.test(pw) && /[A-Z]/.test(pw)) score += 1;
  if (/\d/.test(pw)) score += 1;
  if (/[^A-Za-z0-9]/.test(pw)) score += 1;
  return Math.min(score, 4);
}

const STRENGTH = [
  { label: 'Too weak', color: '#B3271A', width: '20%' },
  { label: 'Weak', color: '#D08C34', width: '40%' },
  { label: 'Fair', color: '#D0B334', width: '60%' },
  { label: 'Good', color: '#5C8F3E', width: '80%' },
  { label: 'Strong', color: '#2E7D57', width: '100%' },
];

const Register = () => {
  const navigate = useNavigate();
  const toast = useToast();

  const [form, setForm] = useState({
    fullName: '',
    email: '',
    phone: '',
    password: '',
    confirmPassword: '',
  });
  const [showPassword, setShowPassword] = useState(false);
  const [errors, setErrors] = useState({});
  const [shake, setShake] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const change = (e) => {
    setForm({ ...form, [e.target.name]: e.target.value });
    setErrors({ ...errors, [e.target.name]: '' });
  };

  const score = passwordScore(form.password);

  const failShake = () => {
    setShake(true);
    setTimeout(() => setShake(false), 520);
  };

  const validate = () => {
    const next = {};

    if (!form.fullName.trim()) {
      next.fullName = 'Enter your full name.';
    } else if (form.fullName.trim().length < 3) {
      next.fullName = 'Name looks too short.';
    }

    if (!form.email.trim()) {
      next.email = 'Enter your email address.';
    } else if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim())) {
      next.email = 'That does not look like a valid email address.';
    }

    const phone = form.phone.replace(/[\s-]/g, '');
    if (!phone) {
      next.phone = 'Enter your phone number.';
    } else if (!PHONE_RE.test(phone)) {
      next.phone = 'Enter a valid number, for example 0712345678.';
    }

    if (!form.password) {
      next.password = 'Choose a password.';
    } else if (form.password.length < 10) {
      next.password = 'Use at least 10 characters.';
    } else if (score < 2) {
      next.password = 'Mix upper and lower case, digits or symbols.';
    }

    if (form.confirmPassword !== form.password) {
      next.confirmPassword = 'Passwords do not match.';
    }

    setErrors(next);
    if (Object.keys(next).length > 0) {
      failShake();
      toast.warning('Check the form', 'Some fields still need attention.');
    }
    return Object.keys(next).length === 0;
  };

  const submit = async (e) => {
    e.preventDefault();
    if (!validate()) return;

    try {
      setSubmitting(true);

      const { data } = await axiosClient.post('/auth/register', {
        full_name: form.fullName.trim(),
        email: form.email.trim().toLowerCase(),
        phone: form.phone.replace(/[\s-]/g, ''),
        password: form.password,
      });

      const token = data.token || data.accessToken;

      if (token) {
        localStorage.setItem('ceb_token', token);
        if (data.user) localStorage.setItem('ceb_user', JSON.stringify(data.user));

        toast.success('Account created', 'Signing you in now.');
        setTimeout(() => navigate('/dashboard', { replace: true }), 600);
      } else {
        navigate('/login', {
          replace: true,
          state: { message: 'Account created. Please sign in.' },
        });
      }
    } catch (err) {
      const status = err.response?.status;
      failShake();

      if (status === 409) {
        setErrors({ email: 'An account with this email already exists.' });
        toast.error('Email already registered', 'Try signing in, or reset your password.');
      } else if (status === 422 && err.response?.data?.errors) {
        setErrors(err.response.data.errors);
        toast.error('Check the form', 'The server rejected some of these details.');
      } else if (!err.response) {
        toast.error('No response from the server', 'Check that the Laravel API is running on port 8000.');
      } else {
        toast.error('Could not create the account', err.response?.data?.message || 'Please try again.');
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
        <h2>Create your account</h2>
        <p>
          New accounts start with read access to dashboards and reports. An
          administrator assigns your role and depot before you can record or
          edit asset data.
        </p>
        <ul>
          <li>View province, area and depot totals</li>
          <li>Browse the asset and transformer register</li>
          <li>Request edit access from your administrator</li>
        </ul>
      </aside>

      <main className="auth-main">
        <div className={`auth-card anim-fade-up${shake ? ' anim-shake' : ''}`}>
          <Link to="/" className="auth-back">&larr; Back to home</Link>

          <h1>Create an account</h1>
          <p className="sub">It takes about a minute.</p>

          <form onSubmit={submit} noValidate>
            <div className="field">
              <label htmlFor="fullName">Full name</label>
              <input
                id="fullName"
                name="fullName"
                type="text"
                autoComplete="name"
                placeholder="K. Jayasekara"
                value={form.fullName}
                onChange={change}
                className={errors.fullName ? 'invalid' : ''}
              />
              {errors.fullName && <span className="field-error">{errors.fullName}</span>}
            </div>

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
              {errors.email ? (
                <span className="field-error">{errors.email}</span>
              ) : (
                <span className="hint">Used to sign in and to reset your password.</span>
              )}
            </div>

            <div className="field">
              <label htmlFor="phone">Phone number</label>
              <input
                id="phone"
                name="phone"
                type="tel"
                autoComplete="tel"
                placeholder="0712345678"
                value={form.phone}
                onChange={change}
                className={errors.phone ? 'invalid' : ''}
              />
              {errors.phone && <span className="field-error">{errors.phone}</span>}
            </div>

            <div className="field">
              <label htmlFor="password">Password</label>
              <div className="password-wrap">
                <input
                  id="password"
                  name="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="new-password"
                  placeholder="At least 10 characters"
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

              {form.password && (
                <>
                  <div className="strength">
                    <span
                      style={{
                        width: STRENGTH[score].width,
                        background: STRENGTH[score].color,
                      }}
                    />
                  </div>
                  <span className="hint">{STRENGTH[score].label}</span>
                </>
              )}
              {errors.password && <span className="field-error">{errors.password}</span>}
            </div>

            <div className="field">
              <label htmlFor="confirmPassword">Confirm password</label>
              <input
                id="confirmPassword"
                name="confirmPassword"
                type={showPassword ? 'text' : 'password'}
                autoComplete="new-password"
                placeholder="Type it again"
                value={form.confirmPassword}
                onChange={change}
                className={errors.confirmPassword ? 'invalid' : ''}
              />
              {errors.confirmPassword && (
                <span className="field-error">{errors.confirmPassword}</span>
              )}
            </div>

            <button
              type="submit"
              className={`auth-submit${submitting ? ' loading' : ''}`}
              disabled={submitting}
            >
              {submitting ? (<><span className="spin-dot" />Creating account</>) : 'Create account'}
            </button>
          </form>

          <p className="auth-alt">
            Already registered? <Link to="/login" className="auth-link">Sign in</Link>
          </p>
        </div>
      </main>
    </div>
  );
};

export default Register;