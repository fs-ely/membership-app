const bcrypt = require('bcrypt');
const pool = require('../src/config/db');
const createTables = require('../src/models/init');

const ADMIN_PASSWORD = 'Password@123';

const seedUsers = [
  { phone: '09999999999', password: ADMIN_PASSWORD, name: 'System Administrator', role: 'admin' },
  { phone: '09111111111', password: ADMIN_PASSWORD, name: 'Juan Dela Cruz', role: 'regular' },
  { phone: '09222222222', password: ADMIN_PASSWORD, name: 'Maria Santos', role: 'regular' }
];

const seedRecords = [
  { first_name: 'Andres', last_name: 'Bonifacio', email_address: 'andres.bonifacio@example.com', location: 'Philippines, Metro Manila, Manila' },
  { first_name: 'Jose', last_name: 'Rizal', email_address: 'jose.rizal@example.com', location: 'Philippines, Metro Manila, Makati' },
  { first_name: 'Gabriela', last_name: 'Silang', email_address: 'gabriela.silang@example.com', location: 'Philippines, Cebu, Cebu City' },
  { first_name: 'Lapu', last_name: 'Lapu', email_address: 'lapu.lapu@example.com', location: 'Philippines, Cebu, Lapu-Lapu' },
  { first_name: 'Melchora', last_name: 'Aquino', email_address: 'melchora.aquino@example.com', location: 'Philippines, Metro Manila, Quezon City' },
  { first_name: 'Antonio', last_name: 'Luna', email_address: 'antonio.luna@example.com', location: 'Philippines, La Union, San Fernando' }
];

const seed = async () => {
  await createTables();

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const hashedPassword = await bcrypt.hash(ADMIN_PASSWORD, 10);

    const seededUserIds = [];
    for (const user of seedUsers) {
      const result = await client.query(
        `INSERT INTO users (phone, password, name, role)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (phone) DO UPDATE
           SET password = EXCLUDED.password,
               name = EXCLUDED.name,
               role = EXCLUDED.role
         RETURNING id, phone, name, role`,
        [user.phone, hashedPassword, user.name, user.role]
      );
      seededUserIds.push(result.rows[0].id);
      console.log(`Upserted user: ${result.rows[0].phone} (${result.rows[0].name}, ${result.rows[0].role})`);
    }

    const adminId = seededUserIds[0];

    await client.query('DELETE FROM records');

    let inserted = 0;
    for (const record of seedRecords) {
      await client.query(
        `INSERT INTO records (user_id, first_name, last_name, email_address, location)
         VALUES ($1, $2, $3, $4, $5)`,
        [adminId, record.first_name, record.last_name, record.email_address, record.location]
      );
      inserted++;
    }

    await client.query('COMMIT');
    console.log(`Seeded ${inserted} records created by admin ${adminId}`);
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('Seed failed:', error);
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
};

seed().catch((error) => {
  console.error(error);
  process.exit(1);
});