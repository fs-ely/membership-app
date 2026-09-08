import React, { useState, useEffect } from 'react';

const ResendOtpButton = ({ onResend, cooldown = 30 }) => {
  const [cooldownLeft, setCooldownLeft] = useState(0);
  const [resending, setResending] = useState(false);

  useEffect(() => {
    if (cooldownLeft <= 0) return;
    const interval = setInterval(() => {
      setCooldownLeft((prev) => (prev > 0 ? prev - 1 : 0));
    }, 1000);
    return () => clearInterval(interval);
  }, [cooldownLeft]);

  const handleResend = async () => {
    if (resending) return;
    setResending(true);
    try {
      await onResend();
      setCooldownLeft(cooldown);
    } catch (e) {
      // Page-level handler already surfaced the error
    } finally {
      setResending(false);
    }
  };

  if (cooldownLeft > 0) {
    return (
      <p data-test="otp-resend-timer" style={styles.timer}>
        Resend OTP in {cooldownLeft}s
      </p>
    );
  }

  return (
    <button
      type="button"
      data-test="otp-resend-button"
      onClick={handleResend}
      style={styles.button}
      disabled={resending}
    >
      {resending ? 'Resending...' : 'Resend Code'}
    </button>
  );
};

const styles = {
  button: {
    display: 'inline-block',
    marginTop: '20px',
    padding: '8px 20px',
    backgroundColor: '#6c757d',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    fontSize: '14px',
    cursor: 'pointer',
  },
  timer: {
    marginTop: '20px',
    color: '#666',
    fontSize: '14px',
  },
};

export default ResendOtpButton;