import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';

/**
 * Plain entry point.
 *
 * NOTHING else is imported here on purpose. In the single-file setup the
 * styles live in pages/Auth/Auth.css (imported by Auth.jsx) and the toast
 * system lives inside Auth.jsx, so there is no theme file to load and no
 * provider to wrap.
 *
 * If you have a global stylesheet at src/index.css, uncomment the line
 * below. If that file does not exist, leave it commented out — importing
 * a missing stylesheet is what caused the last build error.
 */
// import './index.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
