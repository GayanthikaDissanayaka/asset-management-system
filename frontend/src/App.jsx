import React from 'react';
import { BrowserRouter, Routes, Route, Navigate, Link } from 'react-router-dom';

// All five auth screens come from ONE file.
import {
  Welcome,
  Login,
  Register,
  ForgotPassword,
  ResetPassword,
} from './pages/Auth/auth';

import Dashboard from './pages/Dashboard/Dashboard';
import HvLength from './pages/HvLength/HvLength';
import AssetsPage from './pages/Assets/AssetsPage';
import ReportsPage from './pages/Reports/ReportsPage';
import ProtectedRoute from './components/ProtectedRoute';

// Styles for the status pages below. Auth.jsx imports this too; importing
// the same stylesheet twice is harmless, webpack includes it once.
import './pages/Auth/auth.css';

/* =====================================================================
   STATUS PAGES
   Defined here rather than in their own files, so there are no extra
   imports to resolve. Move them out later if they grow.
   ===================================================================== */

function StatusPage({ code, title, message, actionTo, actionLabel }) {
  return (
    <div className="auth-main" style={{ minHeight: '100vh' }}>
      <div className="auth-card anim-fade-up" style={{ textAlign: 'center' }}>
        <div
          style={{
            fontSize: 64,
            fontWeight: 700,
            lineHeight: 1,
            color: 'var(--brand-amber)',
            marginBottom: 12,
          }}
        >
          {code}
        </div>
        <h1>{title}</h1>
        <p className="sub">{message}</p>
        <Link to={actionTo}>
          <button className="auth-submit">{actionLabel}</button>
        </Link>
      </div>
    </div>
  );
}

const NotFound = () => (
  <StatusPage
    code="404"
    title="Page not found"
    message="That address does not match anything in this system."
    actionTo="/"
    actionLabel="Back to home"
  />
);

const Unauthorized = () => (
  <StatusPage
    code="401"
    title="Not signed in"
    message="Your session has ended. Sign in again to continue."
    actionTo="/login"
    actionLabel="Sign in"
  />
);

const Forbidden = () => (
  <StatusPage
    code="403"
    title="No access to this depot"
    message="Your role does not permit this. An administrator can widen your scope."
    actionTo="/dashboard"
    actionLabel="Back to dashboard"
  />
);

const ServerError = () => (
  <StatusPage
    code="500"
    title="Something broke on the server"
    message="The request could not be completed. Try again, or contact IT if it persists."
    actionTo="/"
    actionLabel="Back to home"
  />
);

const App = () => (
  <BrowserRouter>
    <Routes>
      {/* ---------- public ---------- */}
      <Route path="/" element={<Welcome />} />
      <Route path="/login" element={<Login />} />
      <Route path="/register" element={<Register />} />
      <Route path="/forgot-password" element={<ForgotPassword />} />
      <Route path="/reset-password" element={<ResetPassword />} />

      {/* ---------- protected ---------- */}
      <Route
        path="/dashboard"
        element={
          <ProtectedRoute>
            <Dashboard />
          </ProtectedRoute>
        }
      />

      <Route
        path="/hv-length"
        element={
          <ProtectedRoute>
            <HvLength />
          </ProtectedRoute>
        }
      />

      <Route
        path="/assets"
        element={
          <ProtectedRoute>
            <AssetsPage />
          </ProtectedRoute>
        }
      />

      <Route
        path="/reports"
        element={
          <ProtectedRoute>
            <ReportsPage />
          </ProtectedRoute>
        }
      />

      {/* ---------- status ---------- */}
      <Route path="/unauthorized" element={<Unauthorized />} />
      <Route path="/forbidden" element={<Forbidden />} />
      <Route path="/server-error" element={<ServerError />} />

      {/* ---------- fallback ---------- */}
      <Route path="*" element={<NotFound />} />
    </Routes>
  </BrowserRouter>
);

export default App;