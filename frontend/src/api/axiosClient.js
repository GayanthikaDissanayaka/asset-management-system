import axios from 'axios';

const axiosClient = axios.create({
  baseURL: process.env.REACT_APP_API_BASE_URL || 'http://localhost:8000/api',
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
