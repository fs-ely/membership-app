const pool = require('../config/db');

const getAllRecords = async (req, res) => {
  try {
    let result;
    if (req.user.role === 'admin') {
      result = await pool.query(
        `SELECT r.*, u.name as created_by_name 
         FROM records r 
         JOIN users u ON r.user_id = u.id 
         ORDER BY r.created_at DESC`
      );
    } else {
      result = await pool.query(
        `SELECT r.*, u.name as created_by_name 
         FROM records r 
         JOIN users u ON r.user_id = u.id 
         WHERE r.user_id = $1 
         ORDER BY r.created_at DESC`,
        [req.user.userId]
      );
    }
    res.json({ records: result.rows });
  } catch (error) {
    console.error('Get records error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

const getRecordById = async (req, res) => {
  try {
    const { id } = req.params;
    let result;

    if (req.user.role === 'admin') {
      result = await pool.query(
        `SELECT r.*, u.name as created_by_name 
         FROM records r 
         JOIN users u ON r.user_id = u.id 
         WHERE r.id = $1`,
        [id]
      );
    } else {
      result = await pool.query(
        `SELECT r.*, u.name as created_by_name 
         FROM records r 
         JOIN users u ON r.user_id = u.id 
         WHERE r.id = $1 AND r.user_id = $2`,
        [id, req.user.userId]
      );
    }

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }

    res.json({ record: result.rows[0] });
  } catch (error) {
    console.error('Get record error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

const createRecord = async (req, res) => {
  try {
    const { first_name, last_name, email_address, location } = req.body;

    if (!first_name || !last_name || !email_address) {
      return res.status(400).json({ error: 'First name, last name, and email address are required' });
    }

    const result = await pool.query(
      `INSERT INTO records (user_id, first_name, last_name, email_address, location) 
       VALUES ($1, $2, $3, $4, $5) 
       RETURNING *`,
      [req.user.userId, first_name, last_name, email_address, location || null]
    );

    res.status(201).json({
      message: 'Record created successfully',
      record: result.rows[0]
    });
  } catch (error) {
    console.error('Create record error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

const updateRecord = async (req, res) => {
  try {
    const { id } = req.params;
    const { first_name, last_name, email_address, location } = req.body;

    if (!first_name || !last_name || !email_address) {
      return res.status(400).json({ error: 'First name, last name, and email address are required' });
    }

    let result;
    if (req.user.role === 'admin') {
      result = await pool.query(
        `UPDATE records 
         SET first_name = $1, last_name = $2, email_address = $3, location = $4, updated_at = NOW() 
         WHERE id = $5 
         RETURNING *`,
        [first_name, last_name, email_address, location || null, id]
      );
    } else {
      result = await pool.query(
        `UPDATE records 
         SET first_name = $1, last_name = $2, email_address = $3, location = $4, updated_at = NOW() 
         WHERE id = $5 AND user_id = $6 
         RETURNING *`,
        [first_name, last_name, email_address, location || null, id, req.user.userId]
      );
    }

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }

    res.json({
      message: 'Record updated successfully',
      record: result.rows[0]
    });
  } catch (error) {
    console.error('Update record error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

const deleteRecord = async (req, res) => {
  try {
    const { id } = req.params;
    let result;

    if (req.user.role === 'admin') {
      result = await pool.query(
        'DELETE FROM records WHERE id = $1 RETURNING id',
        [id]
      );
    } else {
      result = await pool.query(
        'DELETE FROM records WHERE id = $1 AND user_id = $2 RETURNING id',
        [id, req.user.userId]
      );
    }

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }

    res.json({ message: 'Record deleted successfully' });
  } catch (error) {
    console.error('Delete record error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

module.exports = { getAllRecords, getRecordById, createRecord, updateRecord, deleteRecord };
