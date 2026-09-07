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
const { upload } = require('../utils/uploads');

router.get('/', authMiddleware, getAllRecords);
router.get('/:id', authMiddleware, getRecordById);
router.post('/', authMiddleware, upload.single('profile_image'), createRecord);
router.put('/:id', authMiddleware, upload.single('profile_image'), updateRecord);
router.delete('/:id', authMiddleware, deleteRecord);

module.exports = router;
