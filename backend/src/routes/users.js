const express = require('express');
const router = express.Router();
const { getAllUsers } = require('../controllers/userController');
const authMiddleware = require('../middleware/auth');
const authorizeRole = require('../middleware/role');

router.get('/', authMiddleware, authorizeRole('admin'), getAllUsers);

module.exports = router;