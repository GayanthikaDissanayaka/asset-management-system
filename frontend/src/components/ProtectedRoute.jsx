import React from 'react';
import { Navigate, useLocation } from 'react-router-dom';

/**
 * Convenience, not security. Anyone can set ceb_token in devtools and get
 * past this. The API must verify the token on every request and enforce
 * depot scope server-side.
 */
const ProtectedRoute = ({ children }) => {
  const location = useLocation();
  const token =
    localStorage.getItem('ceb_token') || sessionStorage.getItem('ceb_token');

  if (!token) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }

  return children;
};

export default ProtectedRoute;
