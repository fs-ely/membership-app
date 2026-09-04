import axios from 'axios';

const API_URL = 'http://localhost:5000/api/auth';
const BASE_URL = 'http://localhost:5000/api';

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

export const getProfile = async () => {
  const response = await api.get('/profile');
  return response.data;
};

// Records
export const getRecords = async () => {
  const token = localStorage.getItem('token');
  const response = await axios.get(`${BASE_URL}/records`, {
    headers: { Authorization: `Bearer ${token}` },
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
