const pool = require('../config/db');

const getAllUsers = async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, name, phone, role, created_at FROM users ORDER BY name ASC`
    );
    res.json({ users: result.rows });
  } catch (error) {
    console.error('Get users error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

module.exports = { getAllUsers };