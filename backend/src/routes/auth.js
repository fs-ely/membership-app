const express = require('express');
const router = express.Router();
const { register, login, verifyOTP, forgotPassword, resetPassword, logout, getProfile, updateProfile } = require('../controllers/authController');
const authMiddleware = require('../middleware/auth');
const { upload } = require('../utils/uploads');

// Public routes
router.post('/register', register);
router.post('/login', login);
router.post('/verify-otp', verifyOTP);
router.post('/forgot-password', forgotPassword);
router.post('/reset-password', resetPassword);

// Protected routes
router.post('/logout', authMiddleware, logout);
router.get('/profile', authMiddleware, getProfile);
router.put('/profile', authMiddleware, upload.single('profile_image'), updateProfile);

module.exports = router;
