import React, { useState, useEffect } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { verifyOTP, resendOTP } from '../services/api';
import { useAuth } from '../context/AuthContext';
import BrandHeader from './BrandHeader';
import OtpHint from './OtpHint';
import ResendOtpButton from './ResendOtpButton';

const OTPVerification = () => {
  const [otp, setOtp] = useState(['', '', '', '', '', '']);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const location = useLocation();
  const navigate = useNavigate();
  const { loginUser } = useAuth();

  const { userId, phone, otp: initialOtp, expiresAt: initialExpiresAt } = location.state || {};
  const [otpCode, setOtpCode] = useState(initialOtp);
  const [expiresAt, setExpiresAt] = useState(initialExpiresAt);

  useEffect(() => {
    if (!userId || !phone) {
      navigate('/login');
    }
  }, [userId, phone, navigate]);

  const handleChange = (index, value) => {
    if (value.length > 1) return;
    
    const newOtp = [...otp];
    newOtp[index] = value;
    setOtp(newOtp);

    // Auto-focus next input
    if (value && index < 5) {
      document.getElementById(`otp-${index + 1}`)?.focus();
    }
  };

  const handleKeyDown = (index, e) => {
    if (e.key === 'Backspace' && !otp[index] && index > 0) {
      document.getElementById(`otp-${index - 1}`)?.focus();
    }
  };

  const handlePaste = (e) => {
    e.preventDefault();
    const pastedData = e.clipboardData.getData('text').slice(0, 6);
    const newOtp = pastedData.split('').concat(Array(6).fill('')).slice(0, 6);
    setOtp(newOtp);
    document.getElementById(`otp-${Math.min(pastedData.length, 5)}`)?.focus();
  };

  const handleResend = async () => {
    setError('');
    try {
      const data = await resendOTP(userId);
      setOtpCode(data.otp);
      setExpiresAt(data.expiresAt);
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to resend OTP');
      throw err;
    }
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    const otpString = otp.join('');
    if (otpString.length !== 6) {
      setError('Please enter complete OTP');
      setLoading(false);
      return;
    }

    try {
      const data = await verifyOTP(userId, otpString);
      loginUser(data.token, data.user);
      navigate('/dashboard');
    } catch (err) {
      setError(err.response?.data?.error || 'OTP verification failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={styles.container}>
      <BrandHeader />
      <div style={styles.body}>
      <div style={styles.card}>
        <h2 data-test="otp-title" style={styles.title}>Verify OTP</h2>
        <p style={styles.subtitle}>
          Enter the 6-digit code sent to <strong>{phone}</strong>
        </p>
        <OtpHint otpCode={otpCode} expiresAt={expiresAt} />
        {error && <div data-test="otp-error-message" style={styles.error}>{error}</div>}
        <form data-test="otp-form" onSubmit={handleSubmit}>
          <div style={styles.otpContainer}>
            {otp.map((digit, index) => (
              <input
                key={index}
                id={`otp-${index}`}
                data-test={`otp-digit-input-${index}`}
                type="text"
                inputMode="numeric"
                maxLength={1}
                value={digit}
                onChange={(e) => handleChange(index, e.target.value)}
                onKeyDown={(e) => handleKeyDown(index, e)}
                onPaste={handlePaste}
                style={styles.otpInput}
              />
            ))}
          </div>
          <button type="submit" data-test="otp-verify-button" style={styles.button} disabled={loading}>
            {loading ? 'Verifying...' : 'Verify OTP'}
          </button>
        </form>
        <ResendOtpButton onResend={handleResend} />
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
    textAlign: 'center',
  },
  title: {
    marginBottom: '10px',
    color: '#333',
  },
  subtitle: {
    color: '#666',
    marginBottom: '20px',
  },
  otpContainer: {
    display: 'flex',
    justifyContent: 'center',
    gap: '10px',
    marginBottom: '30px',
  },
  otpInput: {
    width: '50px',
    height: '50px',
    textAlign: 'center',
    fontSize: '24px',
    border: '2px solid #ddd',
    borderRadius: '8px',
    outline: 'none',
  },
  button: {
    width: '100%',
    padding: '12px',
    backgroundColor: '#28a745',
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
  },
};

export default OTPVerification;
