'use strict';
const fs = require('node:fs/promises');
const { constants } = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { randomBytes } = require('node:crypto');
const { homedir } = require('node:os');
const P = require('./protocol.cjs');

async function readJSON(file, limit = 4096) {
  const handle = await fs.open(file, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await handle.stat();
    P.check(stat.isFile() && stat.nlink === 1 && stat.uid === process.getuid() && !(stat.mode & 0o077) && stat.size <= limit, 'Pairing and local state must be private, regular user-owned files');
    const buffer = Buffer.alloc(limit + 1); let size = 0;
    while (size < buffer.length) {
      const result = await handle.read(buffer, size, buffer.length - size, size);
      if (!result.bytesRead) break;
      size += result.bytesRead;
    }
    P.check(size <= limit, 'Local state exceeds size limit');
    try { return JSON.parse(buffer.subarray(0, size).toString('utf8')); }
    catch { throw new Error('Invalid local pairing/state JSON'); }
  } finally { await handle.close(); }
}
async function privateDirectory(root, create = false) {
  if (create) await fs.mkdir(root, { recursive: true, mode: 0o700 });
  const stat = await fs.lstat(root);
  P.check(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === process.getuid() && !(stat.mode & 0o077), 'A private, user-owned local settings directory is required');
}
function contained(root, candidate) {
  const rel = path.relative(root, candidate);
  return rel === '' || (!rel.startsWith('..' + path.sep) && rel !== '..' && !path.isAbsolute(rel));
}
function localPath(value) {
  P.check(typeof value === 'string' && value.length <= 4096 && path.isAbsolute(value) && !/[\x00-\x1f\x7f-\x9f]/.test(value), 'Use an absolute local file path');
  return path.resolve(value);
}
function request(config, vaultKey, route, body, transport = http) {
  P.pairing(config); P.check(config.enabled, 'Pairing was revoked');
  return new Promise((resolve, reject) => {
    const payload = body === undefined ? null : JSON.stringify(body);
    const req = transport.request({ hostname: '127.0.0.1', port: config.port, path: route, method: payload === null ? 'GET' : 'POST',
      headers: { Authorization: `Bearer ${config.token}`, 'X-Kodex-Vault': vaultKey,
        ...(payload === null ? {} : { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }) } }, res => {
      let size = 0; const chunks = [];
      res.on('data', chunk => { size += chunk.length; if (size > 1024 * 1024) req.destroy(new Error('Bridge response too large')); else chunks.push(chunk); });
      res.on('error', () => reject(new Error('Bridge response interrupted')));
      res.on('end', () => {
        try {
          const value = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          if (res.statusCode !== 200) throw new Error('Bridge request failed. Check pairing, vault ownership, and queue status.');
          resolve(value);
        } catch { reject(new Error('Bridge rejected the request or returned invalid data. Check pairing and bridge status.')); }
      });
    });
    req.setTimeout(5000, () => req.destroy(new Error('Bridge unavailable')));
    req.on('error', () => reject(new Error('Mac bridge unavailable. Exports remain queued on the Mac.')));
    req.end(payload);
  });
}

class Connection {
  constructor({ vault, vaultRoot, localRoot, pairingsRoot = P.pairingsRoot(homedir()), send = request }) {
    Object.assign(this, { vault, vaultRoot, localRoot, pairingsRoot, send }); this.state = null; this.busy = false;
  }
  async initialize() {
    this.vaultRoot = await fs.realpath(this.vaultRoot);
    this.vaultKey = P.digest(this.vaultRoot);
    await privateDirectory(this.localRoot, true);
    this.file = path.join(this.localRoot, `${this.vaultKey}.json`);
    try {
      const state = await readJSON(this.file, 256 * 1024);
      P.check(P.keys(state, ['version', 'enabled', 'pairingFile', 'destinationId', 'folder', 'receipts']) && state.version === 1 && typeof state.enabled === 'boolean' &&
        P.ID.test(state.destinationId) && state.receipts && typeof state.receipts === 'object' && !Array.isArray(state.receipts) && Object.keys(state.receipts).length <= 500, 'Invalid local connection state');
      localPath(state.pairingFile); P.folder(state.folder);
      for (const [id, receipt] of Object.entries(state.receipts)) {
        P.check(P.ID.test(id) && P.keys(receipt, ['path', 'hash', 'stage']) && P.KEY.test(receipt.hash) &&
          ['planned', 'written'].includes(receipt.stage) && typeof receipt.path === 'string' && receipt.path.endsWith('.md'), 'Invalid delivery receipt');
        P.folder(receipt.path, 512);
      }
      this.state = state;
    } catch (e) { if (e.code !== 'ENOENT') throw e; }
    if (this.state) {
      const relocated = P.pairingFile(this.pairingsRoot, this.state.destinationId);
      if (path.resolve(this.state.pairingFile) !== path.resolve(relocated)) {
        // Never inspect or resolve the legacy Documents path from Obsidian.
        // Only the Mac migration command may read the old credential.
        try {
          const config = await this.credentials(relocated);
          P.check(config.destinationId === this.state.destinationId && (!config.vaultKey || config.vaultKey === this.vaultKey), 'Pairing identity mismatch');
          await this.save({ ...this.state, pairingFile: relocated });
        } catch {
          throw Object.assign(new Error('Move the companion pairing on the Mac with npm run pair:obsidian -- migrate, then reload this plugin. No Documents access is needed.'), { code: 'PAIRING_LOCATION' });
        }
      }
    }
  }
  async save(next) {
    const payload = JSON.stringify(next);
    P.check(Buffer.byteLength(payload) <= 256 * 1024, 'Local delivery history is full');
    await privateDirectory(this.localRoot);
    const temp = this.file + '.tmp-' + randomBytes(8).toString('hex'); let file;
    try {
      file = await fs.open(temp, 'wx', 0o600); await file.writeFile(payload); await file.sync(); await file.close(); file = null;
      await fs.rename(temp, this.file);
      const dir = await fs.open(this.localRoot, 'r'); try { await dir.sync(); } finally { await dir.close(); }
      this.state = next;
    } finally { await file?.close(); await fs.unlink(temp).catch(e => { if (e.code !== 'ENOENT') throw e; }); }
  }
  async credentials(pairingFile = this.state?.pairingFile) {
    const requested = localPath(pairingFile), root = localPath(this.pairingsRoot);
    P.check(!contained(this.vaultRoot, requested), 'Keep the private pairing file outside the vault');
    const id = path.basename(path.dirname(requested));
    P.check(P.ID.test(id) && requested === P.pairingFile(root, id), 'Use the companion pairing in KOdex Application Support; Documents paths are not accessed');
    // Check each app-owned directory without following links to protected folders.
    await privateDirectory(root); await privateDirectory(path.dirname(requested));
    const config = P.pairing(await readJSON(requested));
    P.check(config.destinationId === id, 'Pairing file does not match its destination directory');
    return config;
  }
  async connect(pairingFile, folder = 'Reading/KOdex') {
    P.folder(folder); pairingFile = localPath(pairingFile);
    const config = await this.credentials(pairingFile);
    P.check(!this.busy, 'Wait for the current import to finish');
    if (this.state?.enabled && this.state.destinationId !== config.destinationId) throw new Error('Disconnect the current destination before pairing a different bridge');
    const result = await this.send(config, this.vaultKey, '/v1/claim', {});
    P.check(result.destinationId === config.destinationId, 'Bridge identity mismatch');
    await this.save({ version: 1, enabled: true, pairingFile, destinationId: config.destinationId, folder, receipts: this.state?.receipts || {} });
  }
  async disconnect() {
    P.check(!this.busy, 'Wait for the current import to finish');
    // Local disconnect pauses delivery. Bridge revocation is a separate Mac command.
    if (this.state) await this.save({ ...this.state, enabled: false });
  }
  async call(route, body) {
    P.check(this.state?.enabled, 'Connect this vault first');
    const config = await this.credentials();
    P.check(config.destinationId === this.state.destinationId, 'Pairing destination changed; reconnect explicitly');
    return this.send(config, this.vaultKey, route, body);
  }
  async setFolder(folder) {
    P.check(this.state?.enabled && !this.busy, 'Connect first and wait for pending imports'); P.folder(folder);
    await this.save({ ...this.state, folder });
  }
  async safeFolder(folder) {
    P.folder(folder);
    const rootStat = await fs.lstat(this.vaultRoot);
    P.check(rootStat.isDirectory() && !rootStat.isSymbolicLink() && await fs.realpath(this.vaultRoot) === this.vaultRoot, 'Vault location changed; reconnect it explicitly');
    let current = this.vaultRoot;
    // Normal symlink checks for local power users; not a hostile directory-swap sandbox.
    for (const component of folder.split('/')) {
      current = path.join(current, component);
      try {
        const stat = await fs.lstat(current);
        P.check(stat.isDirectory() && !stat.isSymbolicLink(), 'Destination contains a link or a non-folder');
      } catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
    let rel = '';
    for (const component of folder.split('/')) {
      rel = rel ? rel + '/' + component : component;
      if (!this.vault.getAbstractFileByPath(rel)) await this.vault.createFolder(rel);
    }
  }
  async deliver(item) {
    P.record(item); P.check(item.destinationId === this.state.destinationId, 'Export belongs to another destination');
    const markdown = P.render(item), hash = P.digest(markdown);
    let receipt = this.state.receipts[item.id];
    if (!receipt) {
      P.check(Object.keys(this.state.receipts).length < 500, 'Local delivery history is full');
      receipt = { path: `${this.state.folder}/${item.createdAt.slice(0, 10)} - KOdex - ${item.id}.md`, hash, stage: 'planned' };
      await this.save({ ...this.state, receipts: { ...this.state.receipts, [item.id]: receipt } });
    }
    P.check(receipt.hash === hash, 'Export content changed unexpectedly');
    if (receipt.stage !== 'written') {
      await this.safeFolder(receipt.path.slice(0, receipt.path.lastIndexOf('/')));
      const target = path.join(this.vaultRoot, receipt.path);
      let existing = false;
      try { const stat = await fs.lstat(target); P.check(stat.isFile() && !stat.isSymbolicLink(), 'Export filename is occupied'); existing = true; }
      catch (e) { if (e.code !== 'ENOENT') throw e; }
      const file = this.vault.getAbstractFileByPath(receipt.path);
      if (existing || file) {
        P.check(file && typeof file.extension === 'string', 'Export filename is occupied');
        P.check(P.digest(await this.vault.read(file)) === hash, 'An existing or edited note occupies this export filename; it was preserved');
      } else await this.vault.create(receipt.path, markdown);
      receipt = { ...receipt, stage: 'written' };
      await this.save({ ...this.state, receipts: { ...this.state.receipts, [item.id]: receipt } });
    }
    await this.call('/v1/ack', { id: item.id });
    return receipt.path;
  }
  async sync() {
    if (this.busy || !this.state?.enabled) return { imported: 0 };
    this.busy = true; let imported = 0, lastPath = null;
    try {
      for (let i = 0; i < 64; i++) {
        const pending = await this.call('/v1/pending');
        if (!pending.record) break;
        lastPath = await this.deliver(pending.record); imported++;
      }
      return { imported, lastPath };
    } finally { this.busy = false; }
  }
}
module.exports = { Connection, request, readJSON };
