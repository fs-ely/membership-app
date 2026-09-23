const bcrypt = require('bcrypt');
const fs = require('fs');
const path = require('path');
const jwt = require('jsonwebtoken');
const pool = require('../config/db');
const generateOTP = require('../utils/otpGenerator');
const { UPLOADS_DIR } = require('../utils/uploads');

const removeFile = (filename) => {
  if (!filename) return;
  const filePath = path.join(UPLOADS_DIR, path.basename(filename));
  fs.unlink(filePath, (err) => {
    if (err && err.code !== 'ENOENT') {
      console.error('Failed to remove file:', err);
    }
  });
};

// Register new user
const register = async (req, res) => {
  try {
    const { phone, password, name } = req.body;

    if (!phone || !password || !name) {
      return res.status(400).json({ error: 'Phone, password, and name are required' });
    }

    // Check if user exists
    const existingUser = await pool.query('SELECT id FROM users WHERE phone = $1', [phone]);
    if (existingUser.rows.length > 0) {
      return res.status(400).json({ error: 'User with this phone already exists' });
    }

    // Hash password
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(password, saltRounds);

    // Create user
    const result = await pool.query(
      'INSERT INTO users (phone, password, name) VALUES ($1, $2, $3) RETURNING id, phone, name',
      [phone, hashedPassword, name]
    );

    res.status(201).json({
      message: 'User registered successfully',
      user: result.rows[0]
    });
  } catch (error) {
    console.error('Register error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// Login - send OTP
const login = async (req, res) => {
  try {
    const { phone, password } = req.body;

    if (!phone || !password) {
      return res.status(400).json({ error: 'Phone and password are required' });
    }

    // Find user
    const result = await pool.query('SELECT * FROM users WHERE phone = $1', [phone]);
    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];
    const isAdmin = user.role === 'admin';

    // Lockout applies to non-admin users only
    if (!isAdmin) {
      const maxAttempts = parseInt(process.env.MAX_LOGIN_ATTEMPTS) || 3;
      const lockoutMinutes = parseInt(process.env.LOCKOUT_MINUTES) || 15;
      const lockoutUntil = user.lockout_until ? new Date(user.lockout_until) : null;

      // Account is currently locked
      if (lockoutUntil && lockoutUntil > new Date()) {
        const remainingMinutes = Math.ceil((lockoutUntil - new Date()) / 60000);
        return res.status(423).json({
          error: `Account locked. Try again in ${remainingMinutes} minute(s).`
        });
      }

      // Lockout expired - clear it
      if (lockoutUntil && lockoutUntil <= new Date()) {
        await pool.query(
          'UPDATE users SET failed_login_attempts = 0, lockout_until = NULL WHERE id = $1',
          [user.id]
        );
        user.failed_login_attempts = 0;
        user.lockout_until = null;
      }
    }

    // Verify password
    const validPassword = await bcrypt.compare(password, user.password);
    if (!validPassword) {
      // Lockout applies to non-admin users only
      if (!isAdmin) {
        const maxAttempts = parseInt(process.env.MAX_LOGIN_ATTEMPTS) || 3;
        const lockoutMinutes = parseInt(process.env.LOCKOUT_MINUTES) || 15;
        const newAttempts = (user.failed_login_attempts || 0) + 1;

        if (newAttempts >= maxAttempts) {
          const lockoutUntil = new Date(Date.now() + lockoutMinutes * 60 * 1000);
          await pool.query(
            'UPDATE users SET failed_login_attempts = 0, lockout_until = $1 WHERE id = $2',
            [lockoutUntil, user.id]
          );
          return res.status(423).json({
            error: `Account locked due to too many failed attempts. Try again in ${lockoutMinutes} minute(s).`
          });
        }

        await pool.query(
          'UPDATE users SET failed_login_attempts = $1 WHERE id = $2',
          [newAttempts, user.id]
        );

        const attemptsLeft = maxAttempts - newAttempts;
        return res.status(401).json({
          error: `Invalid credentials. ${attemptsLeft} attempt(s) remaining.`
        });
      }

      return res.status(401).json({ error: 'Invalid credentials' });
    }

    // Clear lockout on successful login (non-admin users)
    if (!isAdmin) {
      await pool.query(
        'UPDATE users SET failed_login_attempts = 0, lockout_until = NULL WHERE id = $1',
        [user.id]
      );
    }

    // Generate OTP
    const otp = generateOTP();
    const expiryMinutes = parseInt(process.env.OTP_EXPIRY_MINUTES) || 5;
    const expiresAt = new Date(Date.now() + expiryMinutes * 60 * 1000);

    // Invalidate previous unused OTPs for this user
    await pool.query(
      'UPDATE otps SET used = TRUE WHERE user_id = $1 AND used = FALSE',
      [user.id]
    );

    // Save OTP to database
    await pool.query(
      'INSERT INTO otps (user_id, otp_code, expires_at) VALUES ($1, $2, $3)',
      [user.id, otp, expiresAt]
    );

    // Log OTP to console (simulating SMS)
    console.log('\n========================================');
    console.log(`OTP for ${phone}: ${otp}`);
    console.log(`Expires at: ${expiresAt}`);
    console.log('========================================\n');

    res.json({
      message: 'OTP sent successfully',
      userId: user.id,
      phone: user.phone,
      otp,
      expiresAt: expiresAt.toISOString()
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// Verify OTP
const verifyOTP = async (req, res) => {
  try {
    const { userId, otp } = req.body;

    if (!userId || !otp) {
      return res.status(400).json({ error: 'User ID and OTP are required' });
    }

    // Find valid OTP
    const result = await pool.query(
      `SELECT * FROM otps 
       WHERE user_id = $1 AND otp_code = $2 AND used = FALSE AND expires_at > NOW()
       ORDER BY created_at DESC LIMIT 1`,
      [userId, otp]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid or expired OTP' });
    }

    // Mark OTP as used
    await pool.query('UPDATE otps SET used = TRUE WHERE id = $1', [result.rows[0].id]);

    // Get user
    const userResult = await pool.query('SELECT id, phone, name, role FROM users WHERE id = $1', [userId]);
    const user = userResult.rows[0];

    // Generate JWT
    const token = jwt.sign(
      { userId: user.id, phone: user.phone, role: user.role },
      process.env.JWT_SECRET,
      { expiresIn: '1h' }
    );

    // Store active session token (single session enforcement)
    await pool.query(
      'UPDATE users SET active_session_token = $1, active_session_created_at = NOW() WHERE id = $2',
      [token, user.id]
    );

    res.json({
      message: 'OTP verified successfully',
      token,
      user
    });
  } catch (error) {
    console.error('Verify OTP error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// Forgot password - send reset OTP
const forgotPassword = async (req, res) => {
  try {
    const { phone } = req.body;

    if (!phone) {
      return res.status(400).json({ error: 'Phone number is required' });
    }

    // Find user
    const result = await pool.query('SELECT id, phone FROM users WHERE phone = $1', [phone]);
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'No account found with this phone number' });
    }

    const user = result.rows[0];

    // Generate OTP
    const otp = generateOTP();
    const expiryMinutes = parseInt(process.env.OTP_EXPIRY_MINUTES) || 5;
    const expiresAt = new Date(Date.now() + expiryMinutes * 60 * 1000);

    // Invalidate previous unused OTPs for this user
    await pool.query(
      'UPDATE otps SET used = TRUE WHERE user_id = $1 AND used = FALSE',
      [user.id]
    );

    // Save OTP to database
    await pool.query(
      'INSERT INTO otps (user_id, otp_code, expires_at) VALUES ($1, $2, $3)',
      [user.id, otp, expiresAt]
    );

    // Log OTP to console (simulating SMS)
    console.log('\n========================================');
    console.log(`Password reset OTP for ${phone}: ${otp}`);
    console.log(`Expires at: ${expiresAt}`);
    console.log('========================================\n');

    res.json({
      message: 'Password reset OTP sent successfully',
      userId: user.id,
      phone: user.phone,
      otp,
      expiresAt: expiresAt.toISOString()
    });
  } catch (error) {
    console.error('Forgot password error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// Reset password - verify OTP and update password
const resetPassword = async (req, res) => {
  try {
    const { userId, otp, newPassword } = req.body;

    if (!userId || !otp || !newPassword) {
      return res.status(400).json({ error: 'User ID, OTP, and new password are required' });
    }

    if (newPassword.length < 6) {
      return res.status(400).json({ error: 'Password must be at least 6 characters' });
    }

    // Find valid OTP
    const result = await pool.query(
      `SELECT * FROM otps 
       WHERE user_id = $1 AND otp_code = $2 AND used = FALSE AND expires_at > NOW()
       ORDER BY created_at DESC LIMIT 1`,
      [userId, otp]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid or expired OTP' });
    }

    // Mark OTP as used
    await pool.query('UPDATE otps SET used = TRUE WHERE id = $1', [result.rows[0].id]);

    // Hash new password
    const saltRounds = 10;
    const hashedPassword = await bcrypt.hash(newPassword, saltRounds);

    // Update password, clear any lockout, and invalidate all sessions
    await pool.query(
      'UPDATE users SET password = $1, failed_login_attempts = 0, lockout_until = NULL, active_session_token = NULL, active_session_created_at = NULL WHERE id = $2',
      [hashedPassword, userId]
    );

    res.json({ message: 'Password reset successfully' });
  } catch (error) {
    console.error('Reset password error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// Get user profile (protected route)
const getProfile = async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, phone, name, role, profile_image, created_at, updated_at FROM users WHERE id = $1',
      [req.user.userId]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    res.json({ user: result.rows[0] });
  } catch (error) {
    console.error('Get profile error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// Update user profile (protected route)
const updateProfile = async (req, res) => {
  try {
    const { name, phone } = req.body;
    const profileImage = req.file ? req.file.filename : null;

    if (!name || !phone) {
      if (req.file) removeFile(req.file.filename);
      return res.status(400).json({ error: 'Name and phone are required' });
    }

    const existingResult = await pool.query(
      'SELECT phone, profile_image FROM users WHERE id = $1',
      [req.user.userId]
    );
    if (existingResult.rows.length === 0) {
      if (req.file) removeFile(req.file.filename);
      return res.status(404).json({ error: 'User not found' });
    }
    const existingUser = existingResult.rows[0];

    if (existingUser.phone !== phone) {
      const duplicate = await pool.query('SELECT id FROM users WHERE phone = $1', [phone]);
      if (duplicate.rows.length > 0) {
        if (req.file) removeFile(req.file.filename);
        return res.status(400).json({ error: 'User with this phone already exists' });
      }
    }

    const result = await pool.query(
      `UPDATE users 
       SET name = $1, phone = $2, profile_image = $3, updated_at = NOW() 
       WHERE id = $4 
       RETURNING id, phone, name, role, profile_image, created_at, updated_at`,
      [name, phone, profileImage || existingUser.profile_image, req.user.userId]
    );

    if (req.file && existingUser.profile_image) {
      removeFile(existingUser.profile_image);
    }

    res.json({
      message: 'Profile updated successfully',
      user: result.rows[0]
    });
  } catch (error) {
    if (req.file) removeFile(req.file.filename);
    console.error('Update profile error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// Logout - clear active session
const logout = async (req, res) => {
  try {
    await pool.query(
      'UPDATE users SET active_session_token = NULL, active_session_created_at = NULL WHERE id = $1',
      [req.user.userId]
    );

    res.json({ message: 'Logged out successfully' });
  } catch (error) {
    console.error('Logout error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// Resend OTP
const resendOTP = async (req, res) => {
  try {
    const { userId } = req.body;

    if (!userId) {
      return res.status(400).json({ error: 'User ID is required' });
    }

    const userResult = await pool.query('SELECT id, phone FROM users WHERE id = $1', [userId]);
    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'User not found' });
    }

    const user = userResult.rows[0];

    // Generate new OTP
    const otp = generateOTP();
    const expiryMinutes = parseInt(process.env.OTP_EXPIRY_MINUTES) || 5;
    const expiresAt = new Date(Date.now() + expiryMinutes * 60 * 1000);

    // Invalidate previous unused OTPs for this user
    await pool.query(
      'UPDATE otps SET used = TRUE WHERE user_id = $1 AND used = FALSE',
      [user.id]
    );

    // Save OTP to database
    await pool.query(
      'INSERT INTO otps (user_id, otp_code, expires_at) VALUES ($1, $2, $3)',
      [user.id, otp, expiresAt]
    );

    // Log OTP to console (simulating SMS)
    console.log('\n========================================');
    console.log(`Resent OTP for ${user.phone}: ${otp}`);
    console.log(`Expires at: ${expiresAt}`);
    console.log('========================================\n');

    res.json({
      message: 'OTP resent successfully',
      userId: user.id,
      phone: user.phone,
      otp,
      expiresAt: expiresAt.toISOString()
    });
  } catch (error) {
    console.error('Resend OTP error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

module.exports = { register, login, verifyOTP, forgotPassword, resetPassword, logout, resendOTP, getProfile, updateProfile };
