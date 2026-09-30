const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { Client } = require('../backend/node_modules/pg');

const backendDir = path.resolve(__dirname, '..', 'backend');
const envPath = path.join(backendDir, '.env');
const examplePath = path.join(backendDir, '.env.example');

function readEnv(file) {
  return Object.fromEntries(fs.readFileSync(file, 'utf8').split(/\r?\n/)
    .map((line) => line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/))
    .filter(Boolean)
    .map((match) => [match[1], match[2].replace(/^(['"])(.*)\1$/, '$2')]));
}

function fail(message) {
  console.error(`Database setup failed: ${message}`);
  process.exit(1);
}

async function main() {
  if (!fs.existsSync(envPath)) {
    const example = fs.readFileSync(examplePath, 'utf8');
    const configured = example
      .replace(/^DB_USER=.*$/m, 'DB_USER=postgres')
      .replace(/^DB_PASSWORD=.*$/m, 'DB_PASSWORD=postgres')
      .replace(/^JWT_SECRET=.*$/m, `JWT_SECRET=${crypto.randomBytes(32).toString('hex')}`);
    fs.writeFileSync(envPath, configured);
    console.log('Created backend/.env from backend/.env.example.');
  }

  const env = readEnv(envPath);
  const required = ['DB_HOST', 'DB_PORT', 'DB_NAME', 'DB_USER', 'DB_PASSWORD'];
  const missing = required.filter((key) => !env[key] || /^your_.*(user|password)$/i.test(env[key]));
  if (missing.length) {
    fail(`set valid ${missing.join(', ')} values in backend/.env, then run make setup again.`);
  }
  if (!/^[A-Za-z_][A-Za-z0-9_$]*$/.test(env.DB_NAME)) {
    fail('DB_NAME must contain only letters, numbers, underscores, or dollar signs and cannot start with a number.');
  }

  const client = new Client({
    host: env.DB_HOST,
    port: Number(env.DB_PORT),
    database: 'postgres',
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    connectionTimeoutMillis: 5000,
  });

  try {
    await client.connect();
    const result = await client.query('SELECT 1 FROM pg_database WHERE datname = $1', [env.DB_NAME]);
    if (result.rowCount === 0) {
      await client.query(`CREATE DATABASE "${env.DB_NAME}"`);
      console.log(`Created PostgreSQL database "${env.DB_NAME}".`);
    } else {
      console.log(`PostgreSQL database "${env.DB_NAME}" already exists.`);
    }
  } catch (error) {
    fail(`${error.message}. Make sure PostgreSQL is installed and running, and backend/.env has valid credentials with permission to create databases.`);
  } finally {
    await client.end().catch(() => {});
  }
}

main();
