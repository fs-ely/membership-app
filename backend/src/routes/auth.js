const express = require('express');
const router = express.Router();
const { register, login, verifyOTP, forgotPassword, resetPassword, getProfile } = require('../controllers/authController');
const authMiddleware = require('../middleware/auth');

// Public routes
router.post('/register', register);
router.post('/login', login);
router.post('/verify-otp', verifyOTP);
router.post('/forgot-password', forgotPassword);
router.post('/reset-password', resetPassword);

// Protected routes
router.get('/profile', authMiddleware, getProfile);

module.exports = router;
