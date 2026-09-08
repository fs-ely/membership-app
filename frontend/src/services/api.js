import axios from 'axios';
import { toast } from 'react-toastify';

const API_URL = 'http://localhost:5000/api/auth';
const BASE_URL = 'http://localhost:5000/api';

export const UPLOADS_URL = 'http://localhost:5000/uploads';

const api = axios.create({
  baseURL: API_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

const locationApi = axios.create({
  baseURL: BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

api.interceptors.request.use((config) => {
  const token = localStorage.getItem('token');
  if (token) {
    config.headers.Authorization = `Bearer ${token}`;
  }
  return config;
});

// Global response interceptor for session invalidation
api.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 403 && error.response?.data?.code === 'SESSION_INVALIDATED') {
      localStorage.removeItem('token');
      toast.error('Your account has been logged in from another device. You have been logged out.', {
        position: 'top-right',
        autoClose: 5000,
        toastId: 'session-invalidated',
      });
      setTimeout(() => {
        window.location.href = '/login';
      }, 1500);
    }
    return Promise.reject(error);
  }
);

// Also intercept raw axios calls for session invalidation
axios.interceptors.response.use(
  (response) => response,
  (error) => {
    if (error.response?.status === 403 && error.response?.data?.code === 'SESSION_INVALIDATED') {
      localStorage.removeItem('token');
      toast.error('Your account has been logged in from another device. You have been logged out.', {
        position: 'top-right',
        autoClose: 5000,
        toastId: 'session-invalidated',
      });
      setTimeout(() => {
        window.location.href = '/login';
      }, 1500);
    }
    return Promise.reject(error);
  }
);

// Auth
export const register = async (phone, password, name) => {
  const response = await api.post('/register', { phone, password, name });
  return response.data;
};

export const login = async (phone, password) => {
  const response = await api.post('/login', { phone, password });
  return response.data;
};

export const verifyOTP = async (userId, otp) => {
  const response = await api.post('/verify-otp', { userId, otp });
  return response.data;
};

export const resendOTP = async (userId) => {
  const response = await api.post('/resend-otp', { userId });
  return response.data;
};

export const forgotPassword = async (phone) => {
  const response = await api.post('/forgot-password', { phone });
  return response.data;
};

export const resetPassword = async (userId, otp, newPassword) => {
  const response = await api.post('/reset-password', { userId, otp, newPassword });
  return response.data;
};

export const getProfile = async () => {
  const response = await api.get('/profile');
  return response.data;
};

export const updateProfile = async (data) => {
  const token = localStorage.getItem('token');
  const response = await axios.put(`${BASE_URL}/auth/profile`, data, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return response.data;
};

export const logoutApi = async () => {
  const response = await api.post('/logout');
  return response.data;
};

// Records
export const getRecords = async (search, searchBy, userIds) => {
  const token = localStorage.getItem('token');
  const params = {};
  if (search) params.search = search;
  if (searchBy) params.searchBy = searchBy;
  if (userIds && userIds.length > 0) params.user_ids = userIds.join(',');
  const response = await axios.get(`${BASE_URL}/records`, {
    headers: { Authorization: `Bearer ${token}` },
    params,
  });
  return response.data;
};

export const getRecord = async (id) => {
  const token = localStorage.getItem('token');
  const response = await axios.get(`${BASE_URL}/records/${id}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return response.data;
};

// Users (admin only)
export const getUsers = async () => {
  const token = localStorage.getItem('token');
  const response = await axios.get(`${BASE_URL}/users`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return response.data;
};

export const createRecord = async (data) => {
  const token = localStorage.getItem('token');
  const response = await axios.post(`${BASE_URL}/records`, data, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return response.data;
};

export const updateRecord = async (id, data) => {
  const token = localStorage.getItem('token');
  const response = await axios.put(`${BASE_URL}/records/${id}`, data, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return response.data;
};

export const deleteRecord = async (id) => {
  const token = localStorage.getItem('token');
  const response = await axios.delete(`${BASE_URL}/records/${id}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  return response.data;
};

// Locations
export const getCountries = async () => {
  const response = await locationApi.get('/locations/countries');
  return response.data;
};

export const getProvinces = async (countryId) => {
  const response = await locationApi.get(`/locations/provinces/${countryId}`);
  return response.data;
};

export const getCities = async (provinceId) => {
  const response = await locationApi.get(`/locations/cities/${provinceId}`);
  return response.data;
};

export const getBarangays = async (cityId) => {
  const response = await locationApi.get(`/locations/barangays/${cityId}`);
  return response.data;
};

export default api;
