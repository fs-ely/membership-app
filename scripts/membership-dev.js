const crypto = require('crypto');
const fs = require('fs');
const http = require('http');
const https = require('https');
const net = require('net');
const path = require('path');
const { spawn, spawnSync } = require('child_process');

const root = path.resolve(__dirname, '..');
const statePath = path.join(root, '.membership-dev-run.json');
const frontendTitle = (fs.readFileSync(path.join(root, 'frontend/public/index.html'), 'utf8').match(/<title>(.*?)<\/title>/i) || [])[1];
const tunnelHost = 'whooping-either-magnolia.ngrok-free.dev';
const tunnelUrl = `https://${tunnelHost}`;
const services = [
  { name: 'frontend', port: 3000, entry: path.join(root, 'frontend/scripts/start-with-ngrok-host.js') },
  { name: 'backend', port: 5000, entry: path.join(root, 'backend/src/server.js') },
];
const token = crypto.randomBytes(24).toString('hex');
const children = [];
let controlServer;
let stopping = false;
let stateCreated = false;

const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const normalize = (value) => String(value || '').replace(/\\/g, '/').toLowerCase();

function readState() {
  try { return JSON.parse(fs.readFileSync(statePath, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

function writeState(state) {
  fs.writeFileSync(statePath, JSON.stringify(state, null, 2));
}

function portFree(port) {
  return new Promise((resolve) => {
    const probe = net.createServer();
    probe.once('error', () => resolve(false));
    probe.listen(port, '0.0.0.0', () => probe.close(() => resolve(true)));
  });
}

function listenerPids(port) {
  if (process.platform === 'win32') {
    const result = spawnSync('netstat.exe', ['-ano', '-p', 'tcp'], { encoding: 'utf8', windowsHide: true });
    if (result.status !== 0) return [];
    const pids = new Set();
    for (const line of result.stdout.split(/\r?\n/)) {
      const match = line.match(new RegExp(`^\\s*TCP\\s+\\S+:${port}\\s+\\S+\\s+LISTENING\\s+(\\d+)\\s*$`, 'i'));
      if (match) pids.add(Number(match[1]));
    }
    return [...pids];
  }
  const result = spawnSync('lsof', ['-ti', `tcp:${port}`, '-sTCP:LISTEN'], { encoding: 'utf8' });
  return result.status === 0 ? [...new Set(result.stdout.trim().split(/\s+/).map(Number).filter(Boolean))] : [];
}

function processInfo(pid) {
  if (process.platform === 'win32') {
    const command = `$p=Get-CimInstance Win32_Process -Filter 'ProcessId = ${Number(pid)}' -ErrorAction SilentlyContinue; if($p){$p | Select-Object ProcessId,ParentProcessId,Name,ExecutablePath,CommandLine | ConvertTo-Json -Compress}`;
    const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], { encoding: 'utf8', windowsHide: true });
    let info = {};
    if (result.status === 0 && result.stdout.trim()) {
      try { info = JSON.parse(result.stdout.trim()); } catch (_) { /* use fallback below */ }
    }
    if (!info.Name || !info.ExecutablePath) {
      const fallback = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
        `Get-Process -Id ${Number(pid)} -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,Path | ConvertTo-Json -Compress`],
      { encoding: 'utf8', windowsHide: true });
      if (fallback.status === 0 && fallback.stdout.trim()) {
        try {
          const basic = JSON.parse(fallback.stdout.trim());
          info.Name ||= `${basic.ProcessName || 'unknown'}.exe`;
          info.ExecutablePath ||= basic.Path || '';
        } catch (_) { /* use tasklist below */ }
      }
    }
    if (!info.Name) {
      const fallback = spawnSync('tasklist.exe', ['/FI', `PID eq ${Number(pid)}`], { encoding: 'utf8', windowsHide: true });
      const line = (fallback.stdout || '').split(/\r?\n/).find((value) => value.includes(String(pid)));
      info.Name = line ? line.trim().split(/\s+/)[0] : 'unknown';
    }
    return { ProcessId: Number(pid), ...info, CommandLine: info.CommandLine || '' };
  }
  const result = spawnSync('ps', ['-p', String(pid), '-o', 'pid=,ppid=,comm=,args='], { encoding: 'utf8' });
  const line = result.stdout.trim();
  return { ProcessId: pid, Name: line.split(/\s+/)[2] || 'unknown', CommandLine: line };
}

function get(url, headers = {}, timeout = 1800) {
  return new Promise((resolve, reject) => {
    const transport = url.startsWith('https:') ? https : http;
    const request = transport.get(url, { headers, timeout }, (response) => {
      const chunks = [];
      response.on('data', (chunk) => chunks.push(chunk));
      response.on('end', () => resolve({
        status: response.statusCode,
        headers: response.headers,
        body: Buffer.concat(chunks).toString('utf8'),
      }));
    });
    request.on('timeout', () => request.destroy(new Error('request timed out')));
    request.on('error', reject);
  });
}

async function hasMembershipSignature(port) {
  try {
    if (port === 3000) {
      const response = await get('http://127.0.0.1:3000/');
      return response.status === 200 && frontendTitle && response.body.includes(`<title>${frontendTitle}</title>`);
    }
    const [health, locations] = await Promise.all([
      get('http://127.0.0.1:5000/api/health'),
      get('http://127.0.0.1:5000/api/locations/countries'),
    ]);
    const healthBody = JSON.parse(health.body);
    const locationBody = JSON.parse(locations.body);
    return health.status === 200 && healthBody.status === 'OK' &&
      locations.status === 200 && Array.isArray(locationBody.countries);
  } catch (_) {
    return false;
  }
}

function elevatedKillCommand(pid) {
  return `taskkill.exe /PID ${pid} /T /F`;
}

async function terminatePid(pid, label) {
  if (process.platform === 'win32') {
    const result = spawnSync('taskkill.exe', ['/PID', String(pid), '/T', '/F'], { encoding: 'utf8', windowsHide: true });
    if (result.status !== 0) {
      const detail = `${result.stderr || result.stdout || ''}`.trim().replace(/\s+/g, ' ');
      throw new Error(`Windows could not stop ${label} PID ${pid}${detail ? `: ${detail}` : ''}. In an elevated PowerShell window run: ${elevatedKillCommand(pid)}`);
    }
  } else {
    try { process.kill(pid, 'SIGTERM'); } catch (error) { if (error.code !== 'ESRCH') throw error; }
  }
}

async function cleanPort(port) {
  if (await portFree(port)) return;
  const pids = listenerPids(port);
  if (!pids.length) throw new Error(`Port ${port} is occupied, but its listener PID could not be determined.`);
  for (const pid of pids) {
    const info = processInfo(pid);
    const processText = normalize(`${info.ExecutablePath || ''} ${info.CommandLine || ''}`);
    const projectMatch = processText.includes(normalize(root));
    const appMatch = await hasMembershipSignature(port);
    const membership = projectMatch || appMatch;
    const description = `${info.Name || 'process'} PID ${pid}${info.ParentProcessId ? ` (parent PID ${info.ParentProcessId})` : ''}${info.ExecutablePath ? ` [${info.ExecutablePath}]` : ''}${info.CommandLine ? ` (${info.CommandLine})` : ''}`;
    if (!membership) {
      throw new Error(`Port ${port} is occupied by ${description}; it was not identified as Membership, so it was left running.`);
    }
    console.log(`Stopping stale Membership ${port === 3000 ? 'frontend' : 'backend'}: ${description}`);
    await terminatePid(pid, 'stale Membership listener');
  }
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline && !(await portFree(port))) await delay(200);
  if (!(await portFree(port))) throw new Error(`Membership port ${port} is still occupied after cleanup.`);
}

async function tunnelList() {
  try {
    const response = await get('http://127.0.0.1:4040/api/tunnels', {}, 1000);
    if (response.status !== 200) return null;
    const result = JSON.parse(response.body);
    return Array.isArray(result.tunnels) ? result.tunnels : null;
  } catch (_) { return null; }
}

function isMembershipTunnel(tunnel) {
  const target = normalize(tunnel?.config?.addr).replace(/\/$/, '');
  return tunnel?.public_url === tunnelUrl && (target === 'http://localhost:3000' || target === 'http://127.0.0.1:3000');
}

async function cleanStaleTunnel() {
  const tunnels = await tunnelList();
  if (tunnels === null) {
    if (process.platform === 'win32') {
      const result = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command',
        `Get-CimInstance Win32_Process -Filter \"Name = 'ngrok.exe'\" -ErrorAction SilentlyContinue | Select-Object ProcessId,Name,ExecutablePath,CommandLine | ConvertTo-Json -Compress`], { encoding: 'utf8', windowsHide: true });
      let processes = [];
      if (result.status === 0 && result.stdout.trim()) {
        try { const parsed = JSON.parse(result.stdout.trim()); processes = Array.isArray(parsed) ? parsed : [parsed]; } catch (_) { /* no usable details */ }
      }
      const matching = processes.filter((process) => normalize(process.CommandLine).includes(normalize(tunnelHost)));
      const uninspectable = processes.filter((process) => !process.CommandLine);
      if (uninspectable.length) {
        throw new Error(`Could not inspect ngrok command line for PID ${uninspectable[0].ProcessId}; leaving it untouched.`);
      }
      for (const process of matching) {
        console.log(`Stopping stale Membership ngrok tunnel: ${process.Name} PID ${process.ProcessId}`);
        await terminatePid(process.ProcessId, 'stale Membership ngrok tunnel');
      }
    }
    return;
  }
  const matching = tunnels.filter(isMembershipTunnel);
  if (!matching.length) return;
  const unrelated = tunnels.filter((tunnel) => !isMembershipTunnel(tunnel));
  if (unrelated.length) {
    throw new Error('The ngrok agent has the Membership tunnel and other tunnels. It was left running to preserve the unrelated tunnel(s). Stop the Membership endpoint through that agent before restarting.');
  }
  const pids = listenerPids(4040);
  if (!pids.length) throw new Error('Membership ngrok tunnel is active, but the agent PID on port 4040 could not be determined.');
  for (const pid of pids) {
    const info = processInfo(pid);
    const processText = normalize(`${info.Name || ''} ${info.ExecutablePath || ''} ${info.CommandLine || ''}`);
    if (!processText.includes('ngrok')) throw new Error(`The confirmed Membership tunnel’s inspector port 4040 is owned by ${info.Name || 'an unknown process'} PID ${pid}; not terminating an unidentified process.`);
    console.log(`Stopping Membership ngrok tunnel: ${info.Name || 'agent'} PID ${pid}`);
    await terminatePid(pid, 'Membership ngrok agent');
  }
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline && await tunnelList()) await delay(200);
  if (await tunnelList()) throw new Error('Membership ngrok tunnel is still active after cleanup.');
}

async function freeRequiredPorts() {
  const failures = [];
  for (const port of [3000, 5000]) {
    try { await cleanPort(port); } catch (error) { failures.push(error.message); }
  }
  for (const port of [3000, 5000]) {
    if (!(await portFree(port)) && !failures.some((message) => message.includes(`port ${port}`) || message.includes(`Port ${port}`))) {
      failures.push(`Membership port ${port} remains occupied.`);
    }
  }
  if (failures.length) throw new Error(failures.join('\n'));
}

async function waitFor(check, label, timeout = 60000) {
  const deadline = Date.now() + timeout;
  let lastError;
  while (Date.now() < deadline) {
    try { if (await check()) return; } catch (error) { lastError = error; }
    await delay(350);
  }
  throw new Error(`Timed out waiting for ${label}${lastError ? `: ${lastError.message}` : ''}`);
}

function fetchCountries(base, headers = {}) {
  return get(`${base}/api/locations/countries`, headers, 6000).then((response) => {
    if (response.status !== 200) throw new Error(`countries endpoint returned HTTP ${response.status}`);
    const data = JSON.parse(response.body);
    if (!Array.isArray(data.countries)) throw new Error('countries endpoint returned an unexpected payload');
    return response;
  });
}

async function verifyUploadProxy(base, headers = {}) {
  const files = fs.readdirSync(path.join(root, 'backend/uploads')).filter((name) => !name.startsWith('.'));
  if (files.length) {
    const file = files[0].split('/').map(encodeURIComponent).join('/');
    const response = await get(`${base}/uploads/${file}`, headers, 6000);
    if (response.status !== 200 || !String(response.headers['content-type'] || '').startsWith('image/')) {
      throw new Error(`/uploads did not return an image (HTTP ${response.status})`);
    }
    return `served existing upload (${response.status})`;
  }
  const probe = `__membership_proxy_probe_${crypto.randomBytes(6).toString('hex')}.png`;
  const response = await get(`${base}/uploads/${probe}`, { ...headers, Accept: 'image/png' }, 6000);
  if (response.status !== 404 || !response.headers['x-powered-by']) {
    throw new Error(`/uploads probe did not reach the backend (HTTP ${response.status})`);
  }
  return 'backend upload route reached (no saved image available for read-only check)';
}

async function verifyLocal() {
  const page = await get('http://127.0.0.1:3000/', { Host: tunnelHost }, 6000);
  if (page.status !== 200 || !frontendTitle || !page.body.includes(`<title>${frontendTitle}</title>`) || page.body.includes('Invalid Host header')) {
    throw new Error(`Membership frontend host check failed (HTTP ${page.status}).`);
  }
  const health = await get('http://127.0.0.1:5000/api/health', {}, 6000);
  if (health.status !== 200 || JSON.parse(health.body).status !== 'OK') {
    throw new Error(`Membership backend health check failed (HTTP ${health.status}).`);
  }
  await fetchCountries('http://127.0.0.1:3000');
  const uploadResult = await verifyUploadProxy('http://127.0.0.1:3000');
  console.log(`Local checks passed: frontend, backend health, /api proxy, ${uploadResult}.`);
}

async function verifyPublic() {
  const headers = { 'ngrok-skip-browser-warning': '1', Accept: 'text/html,application/json' };
  const page = await get(tunnelUrl, headers, 15000);
  if (page.status !== 200 || !frontendTitle || !page.body.includes(`<title>${frontendTitle}</title>`) || page.body.includes('Invalid Host header')) {
    throw new Error(`Public Membership page check failed (HTTP ${page.status}).`);
  }
  await fetchCountries(tunnelUrl, { ...headers, Accept: 'application/json' });
  const uploadResult = await verifyUploadProxy(tunnelUrl, headers);
  console.log(`Public ngrok checks passed: page, /api proxy, ${uploadResult}.`);
}

function requestControl(state, action) {
  return new Promise((resolve, reject) => {
    const request = http.request({
      host: '127.0.0.1', port: state.controlPort, path: `/${action}`,
      method: action === 'stop' ? 'POST' : 'GET',
      headers: { Authorization: `Bearer ${state.token}` }, timeout: 2500,
    }, (response) => {
      let body = '';
      response.setEncoding('utf8');
      response.on('data', (chunk) => { body += chunk; });
      response.on('end', () => response.statusCode === 200 ? resolve(body) : reject(new Error(body)));
    });
    request.on('timeout', () => request.destroy(new Error('Membership supervisor timeout.')));
    request.on('error', reject);
    request.end();
  });
}

function startChild(name, executable, args, options = {}) {
  const child = spawn(executable, args, {
    cwd: options.cwd || root,
    env: { ...process.env, ...options.env },
    stdio: 'inherit', windowsHide: true,
  });
  child.membershipName = name;
  children.push(child);
  child.once('error', (error) => {
    console.error(`Membership ${name} failed to start: ${error.message}`);
    void shutdown(1);
  });
  child.once('exit', (code, signal) => {
    if (!stopping) {
      console.error(`Membership ${name} exited${signal ? ` after ${signal}` : ` with code ${code}`}.`);
      void shutdown(code || 1);
    }
  });
  return new Promise((resolve, reject) => {
    child.once('spawn', () => resolve(child));
    child.once('error', reject);
  });
}

async function stopChild(child) {
  if (!child.pid || child.exitCode !== null || child.signalCode !== null) return;
  if (process.platform === 'win32') {
    const result = spawnSync('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { encoding: 'utf8', windowsHide: true });
    if (result.status !== 0 && child.exitCode === null && child.signalCode === null) {
      throw new Error(`Could not stop Membership ${child.membershipName} PID ${child.pid}. In elevated PowerShell run: ${elevatedKillCommand(child.pid)}`);
    }
  } else {
    child.kill('SIGTERM');
  }
  await Promise.race([new Promise((resolve) => child.once('exit', resolve)), delay(5000)]);
  if (child.exitCode === null && child.signalCode === null) {
    throw new Error(`Membership ${child.membershipName} PID ${child.pid} did not exit after the stop request.`);
  }
}

function elevatedKillCommand(pid) {
  return process.platform === 'win32' ? `taskkill.exe /PID ${pid} /T /F` : `kill -TERM ${pid}`;
}

async function removeStateIfOwned() {
  const current = readState();
  if (current?.token === token) {
    try { fs.unlinkSync(statePath); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}

async function shutdown(code = 0) {
  if (stopping) return;
  stopping = true;
  console.log('\nStopping Membership frontend and backend...');
  const results = await Promise.allSettled([...children].reverse().map(stopChild));
  const failures = results.filter((result) => result.status === 'rejected').map((result) => result.reason.message);
  try { await freeRequiredPorts(); } catch (error) { failures.push(error.message); }
  if (failures.length) {
    console.error(`Membership stop incomplete:\n- ${failures.join('\n- ')}`);
    const current = readState();
    if (current?.token === token) writeState({ ...current, lastError: failures.join('; ') });
    if (controlServer) controlServer.close();
    process.exit(1);
  }
  await removeStateIfOwned();
  if (controlServer) controlServer.close();
  console.log('Membership stopped. Ports 3000/5000 are free.');
  process.exit(code);
}

async function cleanupBeforeStart() {
  await freeRequiredPorts();
  if (!(await portFree(3000)) || !(await portFree(5000))) {
    throw new Error('Membership ports 3000 and 5000 must both be free before startup.');
  }
}

async function beginRun() {
  const existing = readState();
  if (existing) {
    try {
      await requestControl(existing, 'status');
      throw new Error('Membership is already running. Use make restart to replace its services.');
    } catch (error) {
      if (error.message.includes('already running')) throw error;
      try { process.kill(existing.runnerPid, 0); throw new Error('Membership supervisor state exists but its control service is unavailable.'); }
      catch (processError) { if (processError.code !== 'ESRCH') throw processError; }
      fs.unlinkSync(statePath);
    }
  }
  let fd;
  try {
    fd = fs.openSync(statePath, 'wx');
    stateCreated = true;
    fs.writeFileSync(fd, JSON.stringify({ runnerPid: process.pid, token, controlPort: null, children: [] }));
    fs.closeSync(fd);
  } catch (error) {
    if (fd !== undefined) fs.closeSync(fd);
    if (error.code === 'EEXIST') throw new Error('Membership startup is already in progress. Use make stop before retrying.');
    throw error;
  }
  controlServer = http.createServer((request, response) => {
    if (request.headers.authorization !== `Bearer ${token}`) return response.writeHead(403).end('Forbidden');
    if (request.url === '/status' && request.method === 'GET') return response.writeHead(200).end('running');
    if (request.url === '/stop' && request.method === 'POST') {
      response.writeHead(200).end('stopping');
      setImmediate(() => void shutdown(0));
      return;
    }
    response.writeHead(404).end('Not found');
  });
  await new Promise((resolve, reject) => {
    controlServer.once('error', reject);
    controlServer.listen(0, '127.0.0.1', resolve);
  });
  writeState({ runnerPid: process.pid, token, controlPort: controlServer.address().port, children: [] });
  await cleanupBeforeStart();
  process.once('SIGINT', () => void shutdown(130));
  process.once('SIGTERM', () => void shutdown(143));

  const backend = await startChild('backend', process.execPath, [services[1].entry], {
    cwd: path.join(root, 'backend'), env: { PORT: '5000' },
  });
  const frontend = await startChild('frontend', process.execPath, [services[0].entry], {
    cwd: path.join(root, 'frontend'), env: { HOST: '0.0.0.0', PORT: '3000', CI: 'true', BROWSER: 'none' },
  });
  writeState({ ...readState(), children: [backend.pid, frontend.pid] });

  await waitFor(async () => {
    const health = await get('http://127.0.0.1:5000/api/health');
    return health.status === 200 && JSON.parse(health.body).status === 'OK';
  }, 'Membership backend health endpoint');
  await waitFor(async () => {
    const page = await get('http://127.0.0.1:3000/', { Host: tunnelHost });
    return page.status === 200 && page.body.includes(`<title>${frontendTitle}</title>`) && !page.body.includes('Invalid Host header');
  }, 'Membership frontend host allowlist');
  await verifyLocal();

  console.log('Membership ready: http://localhost:3000, http://localhost:5000');
  console.log('Stop all Membership services with Ctrl+C or make stop.');
}

async function stopRun() {
  const state = readState();
  if (state) {
    try { await requestControl(state, 'stop'); }
    catch (error) {
      if (error.code !== 'ECONNREFUSED' && error.code !== 'ECONNRESET') throw error;
      try { process.kill(state.runnerPid, 0); throw new Error('Membership supervisor is alive but unreachable; refusing to claim stop succeeded.'); }
      catch (probeError) { if (probeError.code !== 'ESRCH') throw probeError; }
    }
    const deadline = Date.now() + 15000;
    while (Date.now() < deadline) {
      const current = readState();
      if (!current && await portFree(3000) && await portFree(5000)) break;
      if (current?.lastError) throw new Error(`Membership stop failed: ${current.lastError}`);
      await delay(250);
    }
    if (readState()) throw new Error('Membership supervisor did not complete stop; its process state remains active.');
  }
  await freeRequiredPorts();
  if (!(await portFree(3000)) || !(await portFree(5000))) throw new Error('Stop failed: Membership port 3000 or 5000 remains occupied.');
  console.log('Membership stopped. Ports 3000/5000 are free.');
}

async function main() {
  const command = process.argv[2] || 'run';
  if (command === 'stop') return stopRun();
  if (command === 'restart') {
    await stopRun();
    if (!(await portFree(3000)) || !(await portFree(5000))) throw new Error('Restart cancelled because a required Membership port is occupied.');
    return beginRun();
  }
  if (command === 'run') return beginRun();
  throw new Error(`Unknown Membership command: ${command}`);
}

main().catch(async (error) => {
  console.error(error.message);
  if (children.length) {
    await shutdown(1);
    return;
  }
  if (stateCreated) {
    await removeStateIfOwned().catch(() => {});
    if (controlServer) controlServer.close();
  }
  process.exitCode = 1;
});
