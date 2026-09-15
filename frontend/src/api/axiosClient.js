import axios from 'axios';

/*
 * Where the API lives.
 *
 * The default is RELATIVE on purpose. Once the build is copied into
 * Laravel's public/ and served by Apache, the page and the API are the
 * same origin, so "/api" is correct whatever that origin turns out to
 * be -- ceb-uva.test, a LAN address, or a real domain later. Hardcoding
 * http://localhost:8000 meant the built app only worked on the machine
 * it was built on, and silently failed for everyone else with what
 * looks like a dead server.
 *
 * `npm start` is the exception: the dev server on :3000 has no API of
 * its own, so .env.development points this at the backend. See the
 * comments in that file.
 */
const axiosClient = axios.create({
  baseURL: process.env.REACT_APP_API_BASE_URL || '/api',
  withCredentials: true,
});

axiosClient.interceptors.request.use((config) => {
  const token =
    localStorage.getItem('ceb_token') || sessionStorage.getItem('ceb_token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

export default axiosClient;
