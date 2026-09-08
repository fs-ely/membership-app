import React, { useState, useEffect } from 'react';

const formatCountdown = (totalMs) => {
  const totalSeconds = Math.max(0, Math.floor(totalMs / 1000));
  const pad2 = (n) => String(n).padStart(2, '0');

  const weeks = Math.floor(totalSeconds / (7 * 24 * 60 * 60));
  const days = Math.floor((totalSeconds % (7 * 24 * 60 * 60)) / (24 * 60 * 60));
  const hours = Math.floor((totalSeconds % (24 * 60 * 60)) / (60 * 60));
  const minutes = Math.floor((totalSeconds % (60 * 60)) / 60);
  const seconds = totalSeconds % 60;

  const segments = [];
  if (weeks > 0) segments.push(`${weeks}w`);
  if (days > 0) segments.push(`${days}d`);
  if (hours > 0 || segments.length > 0) segments.push(`${pad2(hours)}h`);
  if (minutes > 0 || segments.length > 0) segments.push(`${pad2(minutes)}m`);
  segments.push(`${pad2(seconds)}s`);

  return segments.join(' : ');
};

const OtpHint = ({ otpCode, expiresAt }) => {
  const [remaining, setRemaining] = useState(() =>
    expiresAt ? new Date(expiresAt).getTime() - Date.now() : 0
  );

  useEffect(() => {
    if (!expiresAt) return;

    const update = () => setRemaining(new Date(expiresAt).getTime() - Date.now());
    update();
    const interval = setInterval(update, 1000);
    return () => clearInterval(interval);
  }, [expiresAt]);

  if (!otpCode || !expiresAt) return null;

  const expired = remaining <= 0;

  return (
    <div data-test="otp-hint" style={styles.hintBox}>
      <div style={styles.row}>
        <span style={styles.label}>For testing (OTP):</span>
        <strong data-test="otp-hint-code" style={styles.code}>{otpCode}</strong>
      </div>
      <div
        data-test="otp-validity-timer"
        style={expired ? styles.expired : styles.validity}
      >
        {expired ? 'OTP expired' : `Validity: ${formatCountdown(remaining)}`}
      </div>
    </div>
  );
};

const styles = {
  hintBox: {
    backgroundColor: '#fff8e1',
    border: '1px solid #f0c36d',
    borderRadius: '6px',
    padding: '10px 14px',
    marginBottom: '20px',
    textAlign: 'center',
  },
  row: {
    display: 'flex',
    justifyContent: 'center',
    alignItems: 'center',
    gap: '8px',
    marginBottom: '4px',
  },
  label: {
    color: '#8a6d3b',
    fontSize: '13px',
  },
  code: {
    fontSize: '20px',
    letterSpacing: '4px',
    color: '#5a4a1a',
  },
  validity: {
    color: '#8a6d3b',
    fontSize: '13px',
  },
  expired: {
    color: '#cc0000',
    fontSize: '13px',
    fontWeight: 'bold',
  },
};

export default OtpHint;