import React from 'react';
import { useNavigate } from 'react-router-dom';
import Logo from '../../components/Logo';
import PowerGrid from '../../components/PowerGrid';
import './Auth.css';

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

const STATS = [
  { num: '17', cap: 'Consumer service centres' },
  { num: '5', cap: 'Operational areas' },
  { num: '1,717', cap: 'Transformers registered' },
  { num: '39', cap: 'Asset types tracked' },
];

const Welcome = () => {
  const navigate = useNavigate();

  return (
    <div className="welcome-page">
      <nav className="welcome-nav anim-fade-in">
        <Logo size={40} showText variant="light" />
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
        <PowerGrid className="hero-grid-art" />

        <div>
          <span className="welcome-badge anim-fade-up">
            <span className="live-dot" />
            Uva Province &middot; Asset Management
          </span>

          <h1 className="anim-fade-up delay-1">
            The distribution network, <em>counted once</em>.
          </h1>

          <p className="lede anim-fade-up delay-2">
            One authoritative register across five areas and seventeen consumer
            service centres. Depot, area and province totals that reconcile,
            because an asset sitting on a depot boundary belongs to exactly one
            of them.
          </p>

          <div className="welcome-actions anim-fade-up delay-3">
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
            <div key={s.cap} className={`welcome-stat anim-fade-up delay-${i + 3}`}>
              <span className="num">{s.num}</span>
              <span className="cap">{s.cap}</span>
            </div>
          ))}
        </div>
      </section>

      <section className="welcome-features">
        {FEATURES.map((f, i) => (
          <div key={f.title} className={`welcome-feature anim-fade-up delay-${i + 1}`}>
            <div className="feature-icon" aria-hidden="true">{f.icon}</div>
            <h3>{f.title}</h3>
            <p>{f.body}</p>
          </div>
        ))}
      </section>

      <footer className="welcome-footer">
        <span>
          Electricity Distribution Lanka (Pvt) Ltd &middot; Uva Provincial Office
        </span>
        <span>Internal system. Authorised users only.</span>
      </footer>
    </div>
  );
};

export default Welcome;