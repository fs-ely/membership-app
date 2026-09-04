const locations = require('../data/locations.json');

const getCountries = (req, res) => {
  res.json({ countries: locations.countries });
};

const getProvinces = (req, res) => {
  const { countryId } = req.params;
  const provinces = locations.provinces.filter(p => p.countryId === Number(countryId));
  res.json({ provinces });
};

const getCities = (req, res) => {
  const { provinceId } = req.params;
  const cities = locations.cities.filter(c => c.provinceId === provinceId);
  res.json({ cities });
};

const getBarangays = (req, res) => {
  const { cityId } = req.params;
  const barangays = locations.barangays.filter(b => b.cityId === cityId);
  res.json({ barangays });
};

module.exports = { getCountries, getProvinces, getCities, getBarangays };
