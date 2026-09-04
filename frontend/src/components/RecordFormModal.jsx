import React, { useState, useEffect } from 'react';
import Modal from './Modal';
import { getCountries, getProvinces, getCities, getBarangays, createRecord, updateRecord } from '../services/api';

const RecordFormModal = ({ isOpen, onClose, record, onSaved }) => {
  const [formData, setFormData] = useState({
    first_name: '',
    last_name: '',
    email_address: '',
  });
  const [countries, setCountries] = useState([]);
  const [provinces, setProvinces] = useState([]);
  const [cities, setCities] = useState([]);
  const [barangays, setBarangays] = useState([]);
  const [selectedCountry, setSelectedCountry] = useState('');
  const [selectedProvince, setSelectedProvince] = useState('');
  const [selectedCity, setSelectedCity] = useState('');
  const [selectedBarangay, setSelectedBarangay] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [loadingLocations, setLoadingLocations] = useState(false);

  useEffect(() => {
    if (isOpen) {
      loadCountries();
      if (record) {
        setFormData({
          first_name: record.first_name,
          last_name: record.last_name,
          email_address: record.email_address,
        });
        if (record.location) {
          parseLocation(record.location);
        }
      } else {
        setFormData({ first_name: '', last_name: '', email_address: '' });
        setSelectedCountry('');
        setSelectedProvince('');
        setSelectedCity('');
        setSelectedBarangay('');
        setProvinces([]);
        setCities([]);
        setBarangays([]);
      }
      setError('');
    }
  }, [isOpen, record]);

  const loadCountries = async () => {
    try {
      const data = await getCountries();
      setCountries(data.countries);
    } catch (err) {
      console.error('Failed to load countries');
    }
  };

  const parseLocation = async (locationStr) => {
    const parts = locationStr.split(', ').map(s => s.trim());
    if (parts.length >= 1) {
      try {
        const data = await getCountries();
        const country = data.countries.find(c => parts.includes(c.name));
        if (country) {
          setSelectedCountry(country.id);
          const provData = await getProvinces(country.id);
          setProvinces(provData.provinces);
          if (parts.length >= 3) {
            const province = provData.provinces.find(p => parts.includes(p.name));
            if (province) {
              setSelectedProvince(province.id);
              const cityData = await getCities(province.id);
              setCities(cityData.cities);
              if (parts.length >= 2) {
                const city = cityData.cities.find(c => parts.includes(c.name));
                if (city) {
                  setSelectedCity(city.id);
                  const brgyData = await getBarangays(city.id);
                  setBarangays(brgyData.barangays);
                  const barangay = brgyData.barangays.find(b => parts.includes(b.name));
                  if (barangay) setSelectedBarangay(barangay.id);
                }
              }
            }
          }
        }
      } catch (err) {
        console.error('Failed to parse location');
      }
    }
  };

  const handleCountryChange = async (e) => {
    const countryId = e.target.value;
    setSelectedCountry(countryId);
    setSelectedProvince('');
    setSelectedCity('');
    setSelectedBarangay('');
    setCities([]);
    setBarangays([]);
    if (countryId) {
      setLoadingLocations(true);
      try {
        const data = await getProvinces(countryId);
        setProvinces(data.provinces);
      } catch (err) {
        setError('Failed to load provinces');
      } finally {
        setLoadingLocations(false);
      }
    } else {
      setProvinces([]);
    }
  };

  const handleProvinceChange = async (e) => {
    const provinceId = e.target.value;
    setSelectedProvince(provinceId);
    setSelectedCity('');
    setSelectedBarangay('');
    setBarangays([]);
    if (provinceId) {
      setLoadingLocations(true);
      try {
        const data = await getCities(provinceId);
        setCities(data.cities);
      } catch (err) {
        setError('Failed to load cities');
      } finally {
        setLoadingLocations(false);
      }
    } else {
      setCities([]);
    }
  };

  const handleCityChange = async (e) => {
    const cityId = e.target.value;
    setSelectedCity(cityId);
    setSelectedBarangay('');
    if (cityId) {
      setLoadingLocations(true);
      try {
        const data = await getBarangays(cityId);
        setBarangays(data.barangays);
      } catch (err) {
        setError('Failed to load barangays');
      } finally {
        setLoadingLocations(false);
      }
    } else {
      setBarangays([]);
    }
  };

  const buildLocationString = () => {
    const parts = [];
    if (selectedBarangay) {
      const brgy = barangays.find(b => b.id === Number(selectedBarangay) || String(b.id) === String(selectedBarangay));
      if (brgy) parts.push(brgy.name);
    }
    if (selectedCity) {
      const city = cities.find(c => c.id === selectedCity);
      if (city) parts.push(city.name);
    }
    if (selectedProvince) {
      const prov = provinces.find(p => p.id === selectedProvince);
      if (prov) parts.push(prov.name);
    }
    if (selectedCountry) {
      const country = countries.find(c => c.id === Number(selectedCountry));
      if (country) parts.push(country.name);
    }
    return parts.join(', ');
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const payload = {
        ...formData,
        location: buildLocationString() || null,
      };

      if (record) {
        await updateRecord(record.id, payload);
      } else {
        await createRecord(payload);
      }
      onSaved();
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to save record');
    } finally {
      setLoading(false);
    }
  };

  const isEdit = !!record;

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={isEdit ? 'Edit Record' : 'Create Record'}>
      {error && <div style={styles.error}>{error}</div>}
      <form onSubmit={handleSubmit}>
        <div style={styles.inputGroup}>
          <label style={styles.label}>First Name *</label>
          <input
            type="text"
            value={formData.first_name}
            onChange={(e) => setFormData({ ...formData, first_name: e.target.value })}
            style={styles.input}
            required
          />
        </div>
        <div style={styles.inputGroup}>
          <label style={styles.label}>Last Name *</label>
          <input
            type="text"
            value={formData.last_name}
            onChange={(e) => setFormData({ ...formData, last_name: e.target.value })}
            style={styles.input}
            required
          />
        </div>
        <div style={styles.inputGroup}>
          <label style={styles.label}>Email Address *</label>
          <input
            type="email"
            value={formData.email_address}
            onChange={(e) => setFormData({ ...formData, email_address: e.target.value })}
            style={styles.input}
            required
          />
        </div>

        <div style={styles.sectionTitle}>Location</div>

        <div style={styles.inputGroup}>
          <label style={styles.label}>Country</label>
          <select value={selectedCountry} onChange={handleCountryChange} style={styles.input}>
            <option value="">Select Country</option>
            {countries.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
        </div>

        <div style={styles.inputGroup}>
          <label style={styles.label}>Province</label>
          <select
            value={selectedProvince}
            onChange={handleProvinceChange}
            style={styles.input}
            disabled={!selectedCountry || loadingLocations}
          >
            <option value="">Select Province</option>
            {provinces.map((p) => (
              <option key={p.id} value={p.id}>{p.name}</option>
            ))}
          </select>
        </div>

        <div style={styles.inputGroup}>
          <label style={styles.label}>City / Municipality</label>
          <select
            value={selectedCity}
            onChange={handleCityChange}
            style={styles.input}
            disabled={!selectedProvince || loadingLocations}
          >
            <option value="">Select City</option>
            {cities.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
        </div>

        <div style={styles.inputGroup}>
          <label style={styles.label}>Barangay</label>
          <select
            value={selectedBarangay}
            onChange={(e) => setSelectedBarangay(e.target.value)}
            style={styles.input}
            disabled={!selectedCity || loadingLocations}
          >
            <option value="">Select Barangay</option>
            {barangays.map((b) => (
              <option key={b.id} value={b.id}>{b.name}</option>
            ))}
          </select>
        </div>

        <div style={styles.buttonGroup}>
          <button type="button" onClick={onClose} style={styles.cancelBtn}>Cancel</button>
          <button type="submit" style={styles.submitBtn} disabled={loading}>
            {loading ? 'Saving...' : (isEdit ? 'Update' : 'Create')}
          </button>
        </div>
      </form>
    </Modal>
  );
};

const styles = {
  inputGroup: {
    marginBottom: '16px',
  },
  label: {
    display: 'block',
    marginBottom: '5px',
    color: '#555',
    fontSize: '14px',
  },
  input: {
    width: '100%',
    padding: '10px',
    border: '1px solid #ddd',
    borderRadius: '4px',
    fontSize: '14px',
    boxSizing: 'border-box',
  },
  sectionTitle: {
    fontSize: '14px',
    fontWeight: 'bold',
    color: '#333',
    marginBottom: '12px',
    paddingBottom: '8px',
    borderBottom: '1px solid #eee',
  },
  buttonGroup: {
    display: 'flex',
    justifyContent: 'flex-end',
    gap: '10px',
    marginTop: '20px',
    paddingTop: '16px',
    borderTop: '1px solid #eee',
  },
  cancelBtn: {
    padding: '10px 20px',
    backgroundColor: '#6c757d',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '14px',
  },
  submitBtn: {
    padding: '10px 20px',
    backgroundColor: '#007bff',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer',
    fontSize: '14px',
  },
  error: {
    backgroundColor: '#ffe6e6',
    color: '#cc0000',
    padding: '10px',
    borderRadius: '4px',
    marginBottom: '16px',
  },
};

export default RecordFormModal;
