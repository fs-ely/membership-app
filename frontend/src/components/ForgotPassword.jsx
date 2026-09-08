import React, { useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { forgotPassword, resetPassword, resendOTP } from '../services/api';
import BrandHeader from './BrandHeader';
import OtpHint from './OtpHint';
import ResendOtpButton from './ResendOtpButton';

const ForgotPassword = () => {
  const [step, setStep] = useState(1);
  const [phone, setPhone] = useState('');
  const [userId, setUserId] = useState(null);
  const [otpCode, setOtpCode] = useState(null);
  const [expiresAt, setExpiresAt] = useState(null);
  const [otp, setOtp] = useState(['', '', '', '', '', '']);
  const [newPassword, setNewPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const navigate = useNavigate();

  const handleSendOtp = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const data = await forgotPassword(phone);
      setUserId(data.userId);
      setOtpCode(data.otp);
      setExpiresAt(data.expiresAt);
      setStep(2);
    } catch (err) {
      setError(err.response?.data?.error || 'Failed to send OTP');
    } finally {
      setLoading(false);
    }
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

  const handleOtpChange = (index, value) => {
    if (value.length > 1) return;

    const newOtp = [...otp];
    newOtp[index] = value;
    setOtp(newOtp);

    if (value && index < 5) {
      document.getElementById(`fp-otp-${index + 1}`)?.focus();
    }
  };

  const handleOtpKeyDown = (index, e) => {
    if (e.key === 'Backspace' && !otp[index] && index > 0) {
      document.getElementById(`fp-otp-${index - 1}`)?.focus();
    }
  };

  const handleOtpPaste = (e) => {
    e.preventDefault();
    const pastedData = e.clipboardData.getData('text').slice(0, 6);
    const newOtp = pastedData.split('').concat(Array(6).fill('')).slice(0, 6);
    setOtp(newOtp);
    document.getElementById(`fp-otp-${Math.min(pastedData.length, 5)}`)?.focus();
  };

  const handleResetPassword = async (e) => {
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
      await resetPassword(userId, otpString, newPassword);
      navigate('/login');
    } catch (err) {
      setError(err.response?.data?.error || 'Password reset failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={styles.container}>
      <BrandHeader />
      <div style={styles.body}>
        <div style={styles.card}>
          <h2 data-test="forgot-password-title" style={styles.title}>Forgot Password</h2>
          {step === 1 ? (
            <>
              <p style={styles.subtitle}>
                Enter your registered phone number to receive a password reset code.
              </p>
              {error && <div data-test="forgot-password-error-message" style={styles.error}>{error}</div>}
              <form data-test="forgot-password-send-form" onSubmit={handleSendOtp}>
                <div style={styles.inputGroup}>
                  <label style={styles.label}>Phone Number</label>
                  <input
                    type="tel"
                    data-test="forgot-password-phone-input"
                    value={phone}
                    onChange={(e) => setPhone(e.target.value)}
                    placeholder="+1234567890"
                    style={styles.input}
                    required
                  />
                </div>
                <button type="submit" data-test="forgot-password-send-button" style={styles.button} disabled={loading}>
                  {loading ? 'Sending OTP...' : 'Send OTP'}
                </button>
              </form>
            </>
          ) : (
            <>
              <p style={styles.subtitle}>
                Enter the 6-digit code and your new password.
              </p>
              <OtpHint otpCode={otpCode} expiresAt={expiresAt} />
              {error && <div data-test="forgot-password-error-message" style={styles.error}>{error}</div>}
              <form data-test="forgot-password-reset-form" onSubmit={handleResetPassword}>
                <div style={styles.otpContainer}>
                  {otp.map((digit, index) => (
                    <input
                      key={index}
                      id={`fp-otp-${index}`}
                      data-test={`forgot-password-otp-input-${index}`}
                      type="text"
                      inputMode="numeric"
                      maxLength={1}
                      value={digit}
                      onChange={(e) => handleOtpChange(index, e.target.value)}
                      onKeyDown={(e) => handleOtpKeyDown(index, e)}
                      onPaste={handleOtpPaste}
                      style={styles.otpInput}
                    />
                  ))}
                </div>
                <div style={styles.inputGroup}>
                  <label style={styles.label}>New Password</label>
                  <input
                    type="password"
                    data-test="forgot-password-new-password-input"
                    value={newPassword}
                    onChange={(e) => setNewPassword(e.target.value)}
                    placeholder="Enter a new password"
                    style={styles.input}
                    required
                    minLength={6}
                  />
                </div>
                <button type="submit" data-test="forgot-password-reset-button" style={styles.button} disabled={loading}>
                  {loading ? 'Resetting...' : 'Reset Password'}
                </button>
              </form>
              <ResendOtpButton onResend={handleResend} />
            </>
          )}
          <p style={styles.link}>
            <Link data-test="forgot-password-back-link" to="/login">Back to Login</Link>
          </p>
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
    fontSize: '14px',
  },
  inputGroup: {
    marginBottom: '20px',
    textAlign: 'left',
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
  link: {
    textAlign: 'center',
    marginTop: '20px',
    color: '#666',
  },
};

export default ForgotPassword;