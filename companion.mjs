import { constants } from 'node:fs';
import { lstat, open, rename, unlink, mkdir } from 'node:fs/promises';
import { join, dirname, isAbsolute } from 'node:path';
import { homedir } from 'node:os';
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:http';
import { authorized } from './bridge.mjs';
import protocol from './obsidian-kodex/protocol.cjs';
const { ID, KEY, PORT, check, keys, digest, pairing, record } = protocol;
const PAIR = protocol.PAIRING_NAME, QUEUE = 'obsidian-exports.json', LOCATION = 'obsidian-companion-location.json';
const error = (status, message) => Object.assign(new Error(message), { status });

async function privateRoot(root) {
  const stat = await lstat(root);
  check(stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === process.getuid() && !(stat.mode & 0o077), 'Private bridge directory required');
}
export async function readPrivate(root, name, maxBytes = 8 * 1024 * 1024) {
  await privateRoot(root);
  const file = await open(join(root, name), constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await file.stat();
    check(stat.isFile() && stat.nlink === 1 && stat.uid === process.getuid() && !(stat.mode & 0o077) && stat.size <= maxBytes, 'Unsafe companion state');
    const buffer = Buffer.alloc(maxBytes + 1); let size = 0;
    while (size < buffer.length) {
      const result = await file.read(buffer, size, buffer.length - size, size);
      if (!result.bytesRead) break;
      size += result.bytesRead;
    }
    check(size <= maxBytes, 'Companion state is too large');
    try { return JSON.parse(buffer.subarray(0, size).toString('utf8')); }
    catch { throw new Error('Invalid companion state JSON; existing files were preserved'); }
  } finally { await file.close(); }
}
export async function writePrivate(root, name, value, { exclusive = false } = {}) {
  await privateRoot(root);
  const target = join(root, name), temp = target + '.tmp-' + randomBytes(8).toString('hex');
  let file;
  try {
    file = await open(exclusive ? target : temp, 'wx', 0o600);
    await file.writeFile(JSON.stringify(value) + '\n'); await file.sync(); await file.close(); file = null;
    if (!exclusive) await rename(temp, target);
    const directory = await open(root, 'r');
    try { await directory.sync(); } finally { await directory.close(); }
  } finally {
    await file?.close();
    if (!exclusive) await unlink(temp).catch(e => { if (e.code !== 'ENOENT') throw e; });
  }
}

export async function companionPairingDirectory(root) {
  try {
    const location = await readPrivate(root, LOCATION, 8192);
    check(keys(location, ['version', 'directory']) && location.version === 1 && typeof location.directory === 'string' &&
      isAbsolute(location.directory) && !/[\x00-\x1f\x7f-\x9f]/.test(location.directory), 'Invalid companion pairing location');
    return location.directory;
  } catch (e) { if (e.code !== 'ENOENT') throw e; return root; }
}

export async function migrateCompanionPairing(root, { pairingsRoot = protocol.pairingsRoot(homedir()) } = {}) {
  await privateRoot(root);
  const currentDirectory = await companionPairingDirectory(root);
  if (currentDirectory !== root) {
    const current = pairing(await readPrivate(currentDirectory, PAIR, 4096));
    // Recover an interruption after the pointer commit but before legacy cleanup.
    try {
      const legacy = pairing(await readPrivate(root, PAIR, 4096));
      check(JSON.stringify(legacy) === JSON.stringify(current), 'Legacy and relocated pairing differ; no files removed');
      await unlink(join(root, PAIR));
    } catch (e) { if (e.code !== 'ENOENT') throw e; }
    return join(currentDirectory, PAIR);
  }
  const config = pairing(await readPrivate(root, PAIR, 4096));
  await mkdir(pairingsRoot, { recursive: true, mode: 0o700 });
  await privateRoot(pairingsRoot);
  const target = protocol.pairingFile(pairingsRoot, config.destinationId), directory = dirname(target);
  await mkdir(directory, { mode: 0o700 }).catch(e => { if (e.code !== 'EEXIST') throw e; });
  await privateRoot(directory);
  try { await writePrivate(directory, PAIR, config, { exclusive: true }); }
  catch (e) {
    if (e.code !== 'EEXIST') throw e;
    const existing = pairing(await readPrivate(directory, PAIR, 4096));
    check(JSON.stringify(existing) === JSON.stringify(config), 'Relocated pairing conflicts with an existing file; no credential replaced');
  }
  // Commit the bridge's nonsecret pointer before removing the former credential.
  await writePrivate(root, LOCATION, { version: 1, directory });
  await unlink(join(root, PAIR));
  return target;
}

export async function configureCompanion(root, action = 'create', { pairingsRoot = protocol.pairingsRoot(homedir()) } = {}) {
  check(['create', 'rotate', 'revoke', 'migrate'].includes(action), 'Use create, rotate, revoke, or migrate');
  if (action === 'migrate') return migrateCompanionPairing(root, { pairingsRoot });
  let config;
  if (action === 'create') {
    await privateRoot(root);
    for (const name of [LOCATION, PAIR]) {
      try { await lstat(join(root, name)); throw Object.assign(new Error('Pairing already exists'), { code: 'EEXIST' }); }
      catch (e) { if (e.code !== 'ENOENT') throw e; }
    }
    config = pairing({ version: 1, destinationId: randomBytes(16).toString('hex'),
      token: randomBytes(32).toString('hex'), port: PORT, enabled: true, vaultKey: null });
    await mkdir(pairingsRoot, { recursive: true, mode: 0o700 }); await privateRoot(pairingsRoot);
    const directory = dirname(protocol.pairingFile(pairingsRoot, config.destinationId));
    await mkdir(directory, { mode: 0o700 });
    await writePrivate(directory, PAIR, config, { exclusive: true });
    await writePrivate(root, LOCATION, { version: 1, directory }, { exclusive: true });
    return join(directory, PAIR);
  } else {
    // Rotation/revocation automatically finishes legacy relocation first.
    const target = await migrateCompanionPairing(root, { pairingsRoot });
    config = pairing(await readPrivate(dirname(target), PAIR, 4096));
    config = { ...config, token: randomBytes(32).toString('hex'), enabled: action === 'rotate' };
    await writePrivate(dirname(target), PAIR, config);
    return target;
  }
}

export class Companion {
  constructor(root, archives, { maxPending = 64, maxEntries = 500, maxBytes = 8 * 1024 * 1024 } = {}) {
    Object.assign(this, { root, archives, maxPending, maxEntries, maxBytes }); this.serial = Promise.resolve();
  }
  mutate(action) {
    const result = this.serial.then(action); this.serial = result.catch(() => {}); return result;
  }
  async config() { return pairing(await readPrivate(await companionPairingDirectory(this.root), PAIR, 4096)); }
  async queue() {
    let data;
    try { data = await readPrivate(this.root, QUEUE); }
    catch (e) { if (e.code === 'ENOENT') return []; throw e; }
    check(keys(data, ['version', 'entries']) && data.version === 1 && Array.isArray(data.entries) && data.entries.length <= this.maxEntries, 'Invalid export queue');
    for (const entry of data.entries) {
      check(keys(entry, ['record', 'status']) && ['pending', 'delivered'].includes(entry.status), 'Invalid queue entry'); record(entry.record);
    }
    check(new Set(data.entries.map(e => e.record.id)).size === data.entries.length, 'Duplicate export identities');
    return data.entries;
  }
  async claim(vaultKey) {
    if (!KEY.test(vaultKey)) throw error(400, 'Invalid vault identity');
    return this.mutate(async () => {
      const config = await this.config();
      if (!config.enabled) throw error(403, 'Companion pairing is revoked');
      if (config.vaultKey && config.vaultKey !== vaultKey) throw error(409, 'This pairing belongs to another vault');
      if (!config.vaultKey) await writePrivate(await companionPairingDirectory(this.root), PAIR, { ...config, vaultKey });
      return { destinationId: config.destinationId };
    });
  }
  async enqueue({ kind, documentId, archiveId, requestId }) {
    return this.mutate(async () => {
      const config = await this.config();
      if (!config.enabled || !config.vaultKey) throw error(409, 'Pair an Obsidian vault first');
      const sourceKey = kind === 'archive' ? `${documentId}:${archiveId}` : requestId;
      const id = digest(`${config.destinationId}:${kind}:${sourceKey}`).slice(0, 32);
      const entries = await this.queue(), existing = entries.find(e => e.record.id === id);
      if (existing) return { id, status: existing.status };
      let title, messages, source;
      if (kind === 'archive') {
        if (!ID.test(documentId) || !ID.test(archiveId)) throw error(400, 'Invalid archive identity');
        const saved = await this.archives.load(documentId, archiveId);
        title = saved.title; source = { kind, documentId, conversationId: archiveId,
          ...(saved.documentName ? { documentName: saved.documentName } : {}) };
        messages = saved.messages.map((m, i) => ({ id: digest(`${documentId}:${archiveId}:${i}`).slice(0, 32), role: m.role, text: m.text,
          ...(m.wireText !== undefined ? { submittedText: m.wireText } : {}) }));
      } else {
        if (kind !== 'sample' || !ID.test(requestId)) throw error(400, 'Invalid sample request');
        title = 'KOdex connection sample'; source = { kind };
        messages = [{ id: digest(id + ':sample').slice(0, 32), role: 'assistant', text: 'Your Obsidian vault is connected to the Mac bridge. Reading questions still go directly through the bridge to Codex.' }];
      }
      const item = record({ version: 1, id, destinationId: config.destinationId, createdAt: new Date().toISOString(), title, source, messages });
      if (entries.length >= this.maxEntries || entries.filter(e => e.status === 'pending').length >= this.maxPending) throw error(409, 'Export queue is full; existing exports were retained');
      entries.push({ record: item, status: 'pending' });
      const payload = { version: 1, entries };
      // Reserve the small status expansion for future acknowledgments so a
      // full queue can always transition pending records to delivered.
      if (Buffer.byteLength(JSON.stringify(payload)) + 1 + entries.filter(e => e.status === 'pending').length * 2 > this.maxBytes) throw error(409, 'Export storage limit reached');
      await writePrivate(this.root, QUEUE, payload);
      return { id, status: 'pending' };
    });
  }
  async pending(destinationId) {
    const entries = await this.queue();
    const pending = entries.filter(e => e.status === 'pending' && e.record.destinationId === destinationId);
    return { pendingCount: pending.length, record: pending[0]?.record || null };
  }
  async ack(destinationId, id) {
    return this.mutate(async () => {
      const entries = await this.queue();
      const entry = entries.find(e => e.record.id === id && e.record.destinationId === destinationId);
      if (!entry) throw error(404, 'Export not found');
      if (entry.status !== 'delivered') {
        entry.status = 'delivered';
        await writePrivate(this.root, QUEUE, { version: 1, entries });
      }
      return { id, status: 'delivered' };
    });
  }
  async archiveList() {
    const entries = await this.archives.catalog();
    return entries.map(r => ({ documentId: r.documentId, archiveId: r.id, title: r.title, createdAt: r.createdAt, messageCount: r.messageCount,
      ...(r.documentName ? { documentName: r.documentName } : {}) }));
  }
}

export function companionHandler(store) {
  let windowStart = Date.now(), count = 0;
  return async (req, res) => {
    const reply = (status, value) => {
      const body = Buffer.from(JSON.stringify(value));
      if (res.destroyed) return;
      res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': body.length,
        'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Connection': 'close' }); res.end(body);
    };
    try {
      if (!['127.0.0.1', '::ffff:127.0.0.1'].includes(req.socket.remoteAddress) || req.headers.origin || req.headers['sec-fetch-site'] ||
          req.headers.forwarded || Object.keys(req.headers).some(k => k.startsWith('x-forwarded-')) ||
          !/^127\.0\.0\.1:\d+$/.test(req.headers.host || '')) throw error(401, 'Unauthorized');
      const config = await store.config();
      if (!config.enabled || !authorized(req.headers.authorization, config.token)) throw error(401, 'Unauthorized');
      if (Date.now() - windowStart > 60000) { windowStart = Date.now(); count = 0; }
      if (++count > 240) throw error(429, 'Too many requests');
      const vaultKey = req.headers['x-kodex-vault'];
      if (!KEY.test(vaultKey || '')) throw error(401, 'Vault identity required');
      if (req.url !== '/v1/claim' && config.vaultKey !== vaultKey) throw error(403, 'Vault is not paired');
      if (req.method === 'GET' && req.url === '/v1/status') {
        const pending = await store.pending(config.destinationId);
        reply(200, { version: 1, destinationId: config.destinationId, pendingCount: pending.pendingCount }); return;
      }
      if (req.method === 'GET' && req.url === '/v1/pending') { reply(200, await store.pending(config.destinationId)); return; }
      if (req.method === 'GET' && req.url === '/v1/archives') { reply(200, { archives: await store.archiveList() }); return; }
      if (req.method !== 'POST' || !['/v1/claim', '/v1/sample', '/v1/export', '/v1/ack'].includes(req.url)) throw error(404, 'Unknown endpoint');
      if (req.headers['content-type'] !== 'application/json') throw error(415, 'JSON required');
      let size = 0; const chunks = [];
      for await (const chunk of req) {
        size += chunk.length; if (size > 4096) throw error(413, 'Request too large'); chunks.push(chunk);
      }
      let body; try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); } catch { throw error(400, 'Invalid JSON'); }
      if (req.url === '/v1/claim' && keys(body, [])) { reply(200, await store.claim(vaultKey)); return; }
      if (req.url === '/v1/sample' && keys(body, ['requestId']) && ID.test(body.requestId)) { reply(200, await store.enqueue({ kind: 'sample', requestId: body.requestId })); return; }
      if (req.url === '/v1/export' && keys(body, ['documentId', 'archiveId']) && ID.test(body.documentId) && ID.test(body.archiveId)) {
        reply(200, await store.enqueue({ kind: 'archive', ...body })); return;
      }
      if (req.url === '/v1/ack' && keys(body, ['id']) && ID.test(body.id)) { reply(200, await store.ack(config.destinationId, body.id)); return; }
      throw error(400, 'Unexpected request fields');
    } catch (e) { reply(e.status || 503, { error: e.status ? e.message : 'Companion storage unavailable; existing exports were retained' }); }
  };
}

export async function startCompanion(root, archives, { port = PORT } = {}) {
  const store = new Companion(root, archives);
  try { await store.config(); } catch (e) { if (e.code === 'ENOENT') return null; throw e; }
  const server = createServer({ requestTimeout: 10000, headersTimeout: 10000, maxHeaderSize: 4096 }, companionHandler(store));
  server.maxConnections = 4; server.setTimeout(10000);
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', resolve); });
  return server;
}
