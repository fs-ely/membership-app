const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function commandExists(command, args) {
  const result = spawnSync(command, args, { stdio: 'ignore', windowsHide: true });
  return !result.error && result.status === 0;
}

if (commandExists('psql', ['--version'])) {
  console.log('PostgreSQL is installed.');
  process.exit(0);
}

if (process.platform === 'win32') {
  const installRoot = path.join(process.env.ProgramFiles || 'C:\\Program Files', 'PostgreSQL');
  if (fs.existsSync(installRoot) && fs.readdirSync(installRoot).some((version) =>
    fs.existsSync(path.join(installRoot, version, 'bin', 'psql.exe')))) {
    console.log('PostgreSQL is installed (psql is not on PATH).');
    process.exit(0);
  }
}

if (process.platform !== 'win32') {
  console.error('PostgreSQL was not found. Install PostgreSQL 14 or newer with your operating system package manager, then run make setup again.');
  process.exit(1);
}

if (!commandExists('winget', ['--version'])) {
  console.error('PostgreSQL was not found, and winget is unavailable. Install PostgreSQL 14 or newer, then run make setup again.');
  process.exit(1);
}

console.log('Installing PostgreSQL 18 for local development. The Windows installer uses the default postgres password.');
const result = spawnSync('winget', [
  'install', '--id', 'PostgreSQL.PostgreSQL.18', '--exact',
  '--accept-package-agreements', '--accept-source-agreements',
], { stdio: 'inherit', windowsHide: false });

if (result.error || result.status !== 0) {
  console.error(`PostgreSQL installation failed${result.error ? `: ${result.error.message}` : ` (exit ${result.status})`}.`);
  process.exit(result.status || 1);
}

console.log('PostgreSQL installation finished. The next setup step will check backend/.env and connect to the server.');
