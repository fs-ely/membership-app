const express = require('express');
const router = express.Router();
const { register, login, verifyOTP, getProfile } = require('../controllers/authController');
const authMiddleware = require('../middleware/auth');

// Public routes
router.post('/register', register);
router.post('/login', login);
router.post('/verify-otp', verifyOTP);

// Protected routes
router.get('/profile', authMiddleware, getProfile);

module.exports = router;
