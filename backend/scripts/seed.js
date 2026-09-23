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
  { created_by: 'System Administrator', first_name: 'Andres', last_name: 'Bonifacio', email_address: 'andres.bonifacio@example.com', location: 'Barangay 1, Manila, Metro Manila, Philippines' },
  { created_by: 'System Administrator', first_name: 'Jose', last_name: 'Rizal', email_address: 'jose.rizal@example.com', location: 'Bel-Air, Makati City, Metro Manila, Philippines' },
  { created_by: 'Maria Santos', first_name: 'Gabriela', last_name: 'Silang', email_address: 'gabriela.silang@example.com', location: 'Lahug, Cebu City, Cebu, Philippines' },
  { created_by: 'Juan Dela Cruz', first_name: 'Lapu', last_name: 'Lapu', email_address: 'lapu.lapu@example.com', location: 'Pusok, Lapu-Lapu City, Cebu, Philippines' },
  { created_by: 'System Administrator', first_name: 'Melchora', last_name: 'Aquino', email_address: 'melchora.aquino@example.com', location: 'Aurora, Quezon City, Metro Manila, Philippines' },
  { created_by: 'Juan Dela Cruz', first_name: 'Antonio', last_name: 'Luna', email_address: 'antonio.luna@example.com', location: 'Bangbangolan, San Fernando City, La Union, Philippines' },
  { created_by: 'Maria Santos', first_name: 'Josefa', last_name: 'Llanes Escoda', email_address: 'josefa.escola@example.com', location: 'Barangay 100, Manila, Metro Manila, Philippines' },
  { created_by: 'Juan Dela Cruz', first_name: 'Emilio', last_name: 'Jacinto', email_address: 'emilio.jacinto@example.com', location: 'Lewin, Lumban, Laguna, Philippines' },
  { created_by: 'Maria Santos', first_name: 'Gregoria', last_name: 'de Jesus', email_address: 'gregoria.dejesus@example.com', location: 'Barangay 1, Caloocan City, Metro Manila, Philippines' },
  { created_by: 'System Administrator', first_name: 'Apolinario', last_name: 'Mabini', email_address: 'apolinario.mabini@example.com', location: 'Ambulong, Tanauan City, Batangas, Philippines' }
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
        `INSERT INTO users (phone, password, name, role, failed_login_attempts, lockout_until)
         VALUES ($1, $2, $3, $4, 0, NULL)
         ON CONFLICT (phone) DO UPDATE
           SET password = EXCLUDED.password,
               name = EXCLUDED.name,
               role = EXCLUDED.role,
               failed_login_attempts = EXCLUDED.failed_login_attempts,
               lockout_until = EXCLUDED.lockout_until
         RETURNING id, phone, name, role`,
        [user.phone, hashedPassword, user.name, user.role]
      );
      seededUserIds.push(result.rows[0].id);
      console.log(`Upserted user: ${result.rows[0].phone} (${result.rows[0].name}, ${result.rows[0].role})`);
    }

    await client.query('DELETE FROM otps');
    await client.query('DELETE FROM records');

    const seedPhones = seedUsers.map((user) => user.phone);
    await client.query('DELETE FROM users WHERE phone NOT IN ($1, $2, $3)', seedPhones);

    let inserted = 0;
    for (const record of seedRecords) {
      const ownerId = seededUserIds[seedUsers.findIndex((user) => user.name === record.created_by)];
      await client.query(
        `INSERT INTO records (user_id, first_name, last_name, email_address, location)
         VALUES ($1, $2, $3, $4, $5)`,
        [ownerId, record.first_name, record.last_name, record.email_address, record.location]
      );
      inserted++;
    }

    await client.query('COMMIT');
    console.log(`Seeded ${inserted} records created by seeded users`);
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