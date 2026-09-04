const express = require('express');
const router = express.Router();
const {
  getAllRecords,
  getRecordById,
  createRecord,
  updateRecord,
  deleteRecord
} = require('../controllers/recordController');
const authMiddleware = require('../middleware/auth');

router.get('/', authMiddleware, getAllRecords);
router.get('/:id', authMiddleware, getRecordById);
router.post('/', authMiddleware, createRecord);
router.put('/:id', authMiddleware, updateRecord);
router.delete('/:id', authMiddleware, deleteRecord);

module.exports = router;
