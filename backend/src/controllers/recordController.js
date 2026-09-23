const fs = require('fs');
const path = require('path');
const pool = require('../config/db');
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

const getAllRecords = async (req, res) => {
  try {
    const { search, searchBy, user_ids } = req.query;
    const hasSearch = search && search.trim() !== '';
    const searchTerm = hasSearch ? `%${search.trim()}%` : null;
    const isAdmin = req.user.role === 'admin';
    const searchByName = searchBy === 'name';

    const conditions = [];
    const params = [];

    if (!isAdmin) {
      const userResult = await pool.query('SELECT name FROM users WHERE id = $1', [req.user.userId]);
      const userName = userResult.rows[0] ? userResult.rows[0].name : null;
      params.push(userName);
      conditions.push(`u.name = $${params.length}`);
    }

    if (isAdmin && user_ids) {
      const ids = user_ids.split(',').map((s) => s.trim()).filter(Boolean).map(Number).filter(Number.isInteger);
      if (ids.length > 0) {
        params.push(ids);
        conditions.push(`r.user_id = ANY($${params.length}::int[])`);
      }
    }

    if (hasSearch) {
      params.push(searchTerm);
      const idx = params.length;
      const searchCondition = searchByName
        ? `(r.first_name ILIKE $${idx} OR r.last_name ILIKE $${idx} OR CONCAT(r.first_name, ' ', r.last_name) ILIKE $${idx})`
        : `r.email_address ILIKE $${idx}`;
      conditions.push(searchCondition);
    }

    const whereClause = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const result = await pool.query(
      `SELECT r.*, u.name as created_by_name 
       FROM records r 
       JOIN users u ON r.user_id = u.id 
       ${whereClause} 
       ORDER BY r.created_at DESC`,
      params
    );

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
    const profileImage = req.file ? req.file.filename : null;

    if (!first_name || !last_name || !email_address) {
      return res.status(400).json({ error: 'First name, last name, and email address are required' });
    }

    const result = await pool.query(
      `INSERT INTO records (user_id, first_name, last_name, email_address, location, profile_image) 
       VALUES ($1, $2, $3, $4, $5, $6) 
       RETURNING *`,
      [req.user.userId, first_name, last_name, email_address, location || null, profileImage]
    );

    res.status(201).json({
      message: 'Record created successfully',
      record: result.rows[0]
    });
  } catch (error) {
    if (req.file) removeFile(req.file.filename);
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

    const existingResult = await pool.query(
      'SELECT profile_image FROM records WHERE id = $1' + (req.user.role === 'admin' ? '' : ' AND user_id = $2'),
      req.user.role === 'admin' ? [id] : [id, req.user.userId]
    );
    if (existingResult.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }

    const profileImage = existingResult.rows[0].profile_image;

    let result;
    if (req.user.role === 'admin') {
      result = await pool.query(
        `UPDATE records 
         SET first_name = $1, last_name = $2, email_address = $3, location = $4, profile_image = $5, updated_at = NOW() 
         WHERE id = $6 
         RETURNING *`,
        [first_name, last_name, email_address, location || null, profileImage, id]
      );
    } else {
      result = await pool.query(
        `UPDATE records 
         SET first_name = $1, last_name = $2, email_address = $3, location = $4, profile_image = $5, updated_at = NOW() 
         WHERE id = $6 AND user_id = $7 
         RETURNING *`,
        [first_name, last_name, email_address, location || null, profileImage, id, req.user.userId]
      );
    }

    if (result.rows.length === 0) {
      if (req.file) removeFile(req.file.filename);
      return res.status(404).json({ error: 'Record not found' });
    }

    res.json({
      message: 'Record updated successfully',
      record: result.rows[0]
    });
  } catch (error) {
    if (req.file) removeFile(req.file.filename);
    console.error('Update record error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

const deleteRecord = async (req, res) => {
  try {
    const { id } = req.params;
    let result;
    let existing;

    if (req.user.role === 'admin') {
      existing = await pool.query(
        'SELECT profile_image FROM records WHERE id = $1',
        [id]
      );
    } else {
      existing = await pool.query(
        'SELECT profile_image FROM records WHERE id = $1 AND user_id = $2',
        [id, req.user.userId]
      );
    }

    if (existing.rows.length === 0) {
      return res.status(404).json({ error: 'Record not found' });
    }

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

    removeFile(existing.rows[0].profile_image);

    res.json({ message: 'Record deleted successfully' });
  } catch (error) {
    console.error('Delete record error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

module.exports = { getAllRecords, getRecordById, createRecord, updateRecord, deleteRecord };
