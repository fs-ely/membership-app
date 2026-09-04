const express = require('express');
const router = express.Router();
const {
  getCountries,
  getProvinces,
  getCities,
  getBarangays
} = require('../controllers/locationController');

router.get('/countries', getCountries);
router.get('/provinces/:countryId', getProvinces);
router.get('/cities/:provinceId', getCities);
router.get('/barangays/:cityId', getBarangays);

module.exports = router;
