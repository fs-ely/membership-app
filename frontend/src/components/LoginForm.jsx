import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { login } from '../services/api';
import BrandHeader from './BrandHeader';

const LoginForm = () => {
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const data = await login(phone, password);
      // Navigate to OTP verification with userId and phone
      navigate('/verify-otp', { state: { userId: data.userId, phone: data.phone } });
    } catch (err) {
      setError(err.response?.data?.error || 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={styles.container}>
      <BrandHeader />
      <div style={styles.body}>
      <div style={styles.card}>
        <h2 style={styles.title}>Login</h2>
        {error && <div style={styles.error}>{error}</div>}
        <form onSubmit={handleSubmit}>
          <div style={styles.inputGroup}>
            <label style={styles.label}>Phone Number</label>
            <input
              type="tel"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="+1234567890"
              style={styles.input}
              required
            />
          </div>
          <div style={styles.inputGroup}>
            <label style={styles.label}>Password</label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter your password"
              style={styles.input}
              required
            />
          </div>
          <button type="submit" style={styles.button} disabled={loading}>
            {loading ? 'Sending OTP...' : 'Login'}
          </button>
        </form>
        <p style={styles.link}>
          Don't have an account? <Link to="/register">Register</Link>
          &nbsp;|&nbsp;
          <Link to="/forgot-password">Forgot password?</Link>
        </p>
      </div>
      <div style={styles.accountsBox}>
        <h3 style={styles.accountsTitle}>Default Seed Accounts</h3>
        <div style={styles.accountItem}>
          <strong>Admin</strong> — 09999999999 / Password@123
        </div>
        <div style={styles.accountItem}>
          <strong>Regular</strong> — 09111111111 / Password@123
        </div>
        <div style={styles.accountItem}>
          <strong>Regular</strong> — 09222222222 / Password@123
        </div>
      </div>
      </div>
    </div>
  );
};

const styles = {
  container: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    minHeight: '100vh',
    backgroundColor: '#f5f5f5',
  },
  body: {
    display: 'flex',
    flexDirection: 'column',
    justifyContent: 'center',
    alignItems: 'center',
    flexGrow: 1,
    width: '100%',
    padding: '40px 20px',
    boxSizing: 'border-box',
  },
  card: {
    backgroundColor: 'white',
    padding: '40px',
    borderRadius: '8px',
    boxShadow: '0 2px 10px rgba(0,0,0,0.1)',
    width: '100%',
    maxWidth: '400px',
  },
  title: {
    textAlign: 'center',
    marginBottom: '30px',
    color: '#333',
  },
  inputGroup: {
    marginBottom: '20px',
  },
  label: {
    display: 'block',
    marginBottom: '5px',
    color: '#555',
    fontSize: '14px',
  },
  input: {
    width: '100%',
    padding: '12px',
    border: '1px solid #ddd',
    borderRadius: '4px',
    fontSize: '16px',
    boxSizing: 'border-box',
  },
  button: {
    width: '100%',
    padding: '12px',
    backgroundColor: '#007bff',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    fontSize: '16px',
    cursor: 'pointer',
  },
  error: {
    backgroundColor: '#ffe6e6',
    color: '#cc0000',
    padding: '10px',
    borderRadius: '4px',
    marginBottom: '20px',
    textAlign: 'center',
  },
  link: {
    textAlign: 'center',
    marginTop: '20px',
    color: '#666',
  },
  accountsBox: {
    marginTop: '20px',
    width: '100%',
    maxWidth: '400px',
    backgroundColor: '#eef4ff',
    border: '1px solid #c9d8f5',
    borderRadius: '8px',
    padding: '16px',
  },
  accountsTitle: {
    margin: '0 0 12px 0',
    fontSize: '15px',
    color: '#333',
  },
  accountItem: {
    padding: '8px 0',
    borderBottom: '1px solid #d6e2f7',
    fontSize: '13px',
    color: '#444',
  },
};

export default LoginForm;
