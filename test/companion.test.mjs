import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { mkdtemp, mkdir, writeFile, readFile, readdir, rm, stat, symlink, chmod, realpath } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { createRequire } from 'node:module';
import vm from 'node:vm';
import { configureCompanion, migrateCompanionPairing, Companion, companionHandler, startCompanion } from '../companion.mjs';
import { DiskArchives } from '../archives.mjs';
import core from '../obsidian-kodex/core.cjs';
import P from '../obsidian-kodex/protocol.cjs';

async function fixture(t, options = {}) {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'kodex-companion-')));
  t.after(() => rm(root, { force: true, recursive: true }));
  const privateRoot = join(root, '.private'); await mkdir(privateRoot, { mode: 0o700 });
  const pairingsRoot = join(root, 'Application Support/KOdex/companion-pairings');
  const pairingFile = await configureCompanion(privateRoot, 'create', { pairingsRoot });
  const archives = new DiskArchives(join(privateRoot, 'chat-archives'));
  const store = new Companion(privateRoot, archives, options);
  const server = http.createServer(companionHandler(store));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const port = server.address().port;
  const transport = { request: (options, callback) => http.request({ ...options, port }, callback) };
  const send = (config, key, route, body) => core.request(config, key, route, body, transport);
  const vaultRoot = join(root, 'Vault'); await mkdir(vaultRoot);
  const vault = new TestVault(vaultRoot);
  const localRoot = join(root, 'local-settings');
  const client = new core.Connection({ vault, vaultRoot, localRoot, pairingsRoot, send }); await client.initialize();
  return { root, privateRoot, pairingFile, pairingsRoot, archives, store, server, port, send, vaultRoot, vault, localRoot, client };
}
class TestVault {
  constructor(root) { this.root = root; this.files = new Map(); this.created = 0; }
  getAbstractFileByPath(path) { return this.files.get(path) || null; }
  async createFolder(path) { await mkdir(join(this.root, path)); this.files.set(path, { path }); }
  async create(path, text) {
    await writeFile(join(this.root, path), text, { flag: 'wx', mode: 0o600 });
    const file = { path, extension: 'md' }; this.files.set(path, file); this.created++; return file;
  }
  async read(file) { return readFile(join(this.root, file.path), 'utf8'); }
}

test('real HTTP pairing, sample queue, Vault API delivery and acknowledgment', async t => {
  const f = await fixture(t);
  await f.client.connect(f.pairingFile);
  assert.equal((await f.store.config()).vaultKey, P.digest(f.vaultRoot));
  await f.client.call('/v1/sample', { requestId: 'a'.repeat(32) });
  assert.equal((await f.client.call('/v1/status')).pendingCount, 1);
  const result = await f.client.sync(); assert.equal(result.imported, 1);
  assert.equal((await f.client.call('/v1/status')).pendingCount, 0);
  assert.match(await readFile(join(f.vaultRoot, result.lastPath), 'utf8'), /Your Obsidian vault is connected/);
  assert.equal(f.vault.created, 1);
  const local = await readFile(f.client.file, 'utf8');
  assert.equal(local.includes((await f.store.config()).token), false, 'credential remains only in the bridge pairing file');
  assert.equal((await stat(f.client.file)).mode & 0o777, 0o600);
});

test('explicit archive import preserves full context and stable source identities without model RPC', async t => {
  const f = await fixture(t); const doc = 'd'.repeat(32);
  const saved = await f.archives.save(doc, [{ role: 'user', text: 'Explain this', wireText: 'Selected passage: original book text' }, { role: 'assistant', text: 'An explanation' }]);
  await f.client.connect(f.pairingFile);
  const catalog = await f.client.call('/v1/archives');
  assert.equal(catalog.archives.length, 1); assert.equal(catalog.archives[0].archiveId, saved.id);
  assert.equal(JSON.stringify(catalog).includes('original book text'), false, 'catalog exposes metadata only');
  assert.equal((await f.store.queue()).length, 0, 'listing does not export');
  const body = { documentId: doc, archiveId: saved.id };
  const first = await f.client.call('/v1/export', body);
  const retry = await f.client.call('/v1/export', body); assert.equal(first.id, retry.id);
  const result = await f.client.sync();
  const text = await readFile(join(f.vaultRoot, result.lastPath), 'utf8');
  assert.match(text, /Explain this/); assert.match(text, /original book text/); assert.match(text, /Submitted context/);
  assert.match(text, new RegExp(`conversation_id: ${saved.id}`));
  assert.equal((await f.client.call('/v1/export', body)).status, 'delivered');
  assert.equal((await f.client.sync()).imported, 0);
});

test('bridge and client restart recover queued work; an ack failure preserves edited notes on retry', async t => {
  const f = await fixture(t); await f.client.connect(f.pairingFile);
  await f.client.call('/v1/sample', { requestId: 'b'.repeat(32) });
  assert.equal((await new Companion(f.privateRoot, f.archives).pending(f.client.state.destinationId)).pendingCount, 1);
  const realSend = f.client.send;
  f.client.send = (config, key, route, body) => route === '/v1/ack' ? Promise.reject(new Error('Simulated lost ack')) : realSend(config, key, route, body);
  await assert.rejects(f.client.sync(), /lost ack/);
  const receipt = Object.values(f.client.state.receipts)[0]; assert.equal(receipt.stage, 'written');
  await writeFile(join(f.vaultRoot, receipt.path), 'My edits');
  const restarted = new core.Connection({ vault: f.vault, vaultRoot: f.vaultRoot, localRoot: f.localRoot, pairingsRoot: f.pairingsRoot, send: realSend });
  await restarted.initialize(); await restarted.sync();
  assert.equal(await readFile(join(f.vaultRoot, receipt.path), 'utf8'), 'My edits');
  assert.equal(f.vault.created, 1); assert.equal((await restarted.call('/v1/status')).pendingCount, 0);
});

test('crash between note creation and receipt completion reconciles by content without duplicate creation', async t => {
  const f = await fixture(t); await f.client.connect(f.pairingFile);
  await f.client.call('/v1/sample', { requestId: 'c'.repeat(32) });
  const save = f.client.save.bind(f.client);
  f.client.save = next => Object.values(next.receipts).some(r => r.stage === 'written') ? Promise.reject(new Error('Simulated ledger failure')) : save(next);
  await assert.rejects(f.client.sync(), /ledger failure/); assert.equal(f.vault.created, 1);
  const restarted = new core.Connection({ vault: f.vault, vaultRoot: f.vaultRoot, localRoot: f.localRoot, pairingsRoot: f.pairingsRoot, send: f.send });
  await restarted.initialize(); await restarted.sync(); assert.equal(f.vault.created, 1);
});

test('another vault cannot claim the same pairing; rotation keeps identity and revocation stops delivery', async t => {
  const f = await fixture(t); await f.client.connect(f.pairingFile);
  const config = await f.store.config();
  await assert.rejects(f.send(config, 'f'.repeat(64), '/v1/claim', {}), /Bridge rejected/);
  await assert.rejects(f.send(config, 'f'.repeat(64), '/v1/pending'), /Bridge rejected/);
  await configureCompanion(f.privateRoot, 'rotate');
  assert.equal((await f.store.config()).destinationId, config.destinationId);
  await assert.rejects(f.send(config, f.client.vaultKey, '/v1/status'), /Bridge rejected/);
  await f.client.call('/v1/sample', { requestId: 'e'.repeat(32) });
  await configureCompanion(f.privateRoot, 'revoke');
  await assert.rejects(f.client.sync(), /revoked/);
  assert.equal((await f.store.pending(config.destinationId)).pendingCount, 1);
});

test('no-clobber conflicts and unsafe subfolders retain queued work', async t => {
  const f = await fixture(t); await f.client.connect(f.pairingFile);
  const result = await f.client.call('/v1/sample', { requestId: '1'.repeat(32) });
  const pending = await f.client.call('/v1/pending');
  const filename = `Reading/KOdex/${pending.record.createdAt.slice(0, 10)} - KOdex - ${result.id}.md`;
  await f.client.safeFolder('Reading/KOdex'); await f.vault.create(filename, 'Existing user note');
  await assert.rejects(f.client.sync(), /preserved/);
  assert.equal(await readFile(join(f.vaultRoot, filename), 'utf8'), 'Existing user note');
  assert.equal((await f.client.call('/v1/status')).pendingCount, 1);
  const outside = join(f.root, 'Outside'); await mkdir(outside);
  await symlink(outside, join(f.vaultRoot, 'Linked'));
  await assert.rejects(f.client.safeFolder('Linked/Notes'), /link/);
  assert.deepEqual(await readdir(outside), []);
  await assert.rejects(f.client.setFolder('../escape'));
});

test('pairing files inside the vault and loose credentials are refused', async t => {
  const f = await fixture(t);
  const copied = join(f.vaultRoot, 'pairing.json');
  await writeFile(copied, await readFile(f.pairingFile), { mode: 0o600 });
  await assert.rejects(f.client.connect(copied), /outside the vault/);
  await chmod(f.pairingFile, 0o644); await assert.rejects(f.client.connect(f.pairingFile), /private/);
});

test('queue limits reject new work without losing previous exports; disconnect pauses local receipt', async t => {
  const f = await fixture(t, { maxPending: 1 }); await f.client.connect(f.pairingFile);
  const first = await f.client.call('/v1/sample', { requestId: '2'.repeat(32) });
  await assert.rejects(f.client.call('/v1/sample', { requestId: '3'.repeat(32) }), /Bridge rejected/);
  assert.equal((await f.store.queue()).length, 1);
  await f.client.disconnect(); assert.equal((await f.client.sync()).imported, 0);
  assert.equal((await f.store.pending((await f.store.config()).destinationId)).record.id, first.id);
  await f.client.connect(f.pairingFile); await f.client.sync(); assert.equal(f.vault.created, 1);
});

test('browser-origin traffic and unexpected JSON are denied', async t => {
  const f = await fixture(t); await f.client.connect(f.pairingFile); const config = await f.store.config();
  const status = await new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port: f.port, path: '/v1/pending', headers: {
      Origin: 'https://example.com', Authorization: `Bearer ${config.token}`, 'X-Kodex-Vault': f.client.vaultKey,
    } }, res => { res.resume(); resolve(res.statusCode); }); req.on('error', reject); req.end();
  });
  assert.equal(status, 401);
  await assert.rejects(f.client.call('/v1/sample', { requestId: '4'.repeat(32), path: '/outside' }));
  await assert.rejects(f.client.call('/v1/prompt', { text: 'No model access here' }));
});

test('Markdown renderer contains remote embeds, HTML, and fence-breaking text as literals', () => {
  const item = { version: 1, id: 'a'.repeat(32), destinationId: 'b'.repeat(32), createdAt: '2026-11-08T00:00:00.000Z',
    title: 'title\nwith properties: true', source: { kind: 'sample' }, messages: [{ id: 'c'.repeat(32), role: 'assistant',
      text: '```\n![](https://tracker.example/pixel)\n![[Private note]]\n<script>alert(1)</script>\n```' }] };
  const rendered = P.render(item);
  assert.match(rendered, /````text\n```/); assert.match(rendered, /title: "title\\nwith properties: true"/);
  assert.throws(() => P.render({ ...item, createdAt: '2026/11/08' }));
});

test('companion listener is optional and port collisions are reported independently', async t => {
  const f = await fixture(t);
  const unconfigured = join(f.root, 'Unconfigured'); await mkdir(unconfigured, { mode: 0o700 });
  assert.equal(await startCompanion(unconfigured, f.archives, { port: 0 }), null);
  await assert.rejects(startCompanion(f.privateRoot, f.archives, { port: f.port }), { code: 'EADDRINUSE' });
  const optional = await startCompanion(f.privateRoot, f.archives, { port: 0 });
  assert.equal(optional.address().address, '127.0.0.1');
  await new Promise(resolve => optional.close(resolve));
});

test('disconnect and folder change retain recovery receipts for already written notes', async t => {
  const f = await fixture(t); await f.client.connect(f.pairingFile);
  await f.client.call('/v1/sample', { requestId: '5'.repeat(32) });
  const realSend = f.client.send;
  f.client.send = (config, key, route, body) => route === '/v1/ack' ? Promise.reject(new Error('Lost ack')) : realSend(config, key, route, body);
  await assert.rejects(f.client.sync(), /Lost ack/);
  const original = Object.values(f.client.state.receipts)[0].path;
  await f.client.disconnect();
  const restarted = new core.Connection({ vault: f.vault, vaultRoot: f.vaultRoot, localRoot: f.localRoot, pairingsRoot: f.pairingsRoot, send: realSend });
  await restarted.initialize(); assert.equal(restarted.state.enabled, false);
  await restarted.connect(f.pairingFile, 'Another folder');
  const result = await restarted.sync(); assert.equal(result.lastPath, original); assert.equal(f.vault.created, 1);
});

test('legacy migration moves the only credential, preserves identity and queue, and supports rotation', async t => {
  const f = await fixture(t); await f.client.connect(f.pairingFile);
  await f.client.call('/v1/sample', { requestId: '6'.repeat(32) });
  const config = await f.store.config();
  const beforeQueue = await readFile(join(f.privateRoot, 'obsidian-exports.json'));
  // Simulate the prior release, including a duplicate at the target from an
  // interrupted relocation. Migration must reconcile it without token changes.
  await writeFile(join(f.privateRoot, 'obsidian-companion.json'), JSON.stringify(config), { mode: 0o600 });
  await rm(join(f.privateRoot, 'obsidian-companion-location.json'));
  const relocated = await migrateCompanionPairing(f.privateRoot, { pairingsRoot: f.pairingsRoot });
  assert.equal(relocated, f.pairingFile);
  assert.deepEqual(await f.store.config(), config);
  await assert.rejects(stat(join(f.privateRoot, 'obsidian-companion.json')), { code: 'ENOENT' });
  assert.deepEqual(await readFile(join(f.privateRoot, 'obsidian-exports.json')), beforeQueue);
  assert.equal((await stat(relocated)).mode & 0o777, 0o600);
  assert.equal((await stat(f.pairingsRoot)).mode & 0o777, 0o700);
  assert.equal(await migrateCompanionPairing(f.privateRoot, { pairingsRoot: f.pairingsRoot }), relocated);
  await configureCompanion(f.privateRoot, 'rotate');
  assert.notEqual((await f.store.config()).token, config.token);
  assert.equal((await f.store.config()).destinationId, config.destinationId);
  assert.equal((await f.client.call('/v1/status')).pendingCount, 1);
  await configureCompanion(f.privateRoot, 'revoke');
  await assert.rejects(f.client.call('/v1/status'), /revoked/);
});

test('migration refuses conflicting target credentials and retains the original', async t => {
  const f = await fixture(t); const config = await f.store.config();
  await writeFile(join(f.privateRoot, 'obsidian-companion.json'), JSON.stringify({ ...config, token: 'f'.repeat(64) }), { mode: 0o600 });
  await rm(join(f.privateRoot, 'obsidian-companion-location.json'));
  await assert.rejects(migrateCompanionPairing(f.privateRoot, { pairingsRoot: f.pairingsRoot }), /conflicts/);
  assert.equal(JSON.parse(await readFile(join(f.privateRoot, 'obsidian-companion.json'), 'utf8')).token, 'f'.repeat(64));
  await assert.rejects(stat(join(f.privateRoot, 'obsidian-companion-location.json')), { code: 'ENOENT' });
});

test('plugin migrates saved connection without any filesystem access to its old Documents path', async t => {
  const f = await fixture(t); await f.client.connect(f.pairingFile);
  const legacyRoot = join(f.root, 'Documents');
  const receipt = { path: 'Reading/KOdex/existing.md', hash: 'a'.repeat(64), stage: 'written' };
  const receipts = { ['e'.repeat(32)]: receipt };
  await f.client.save({ ...f.client.state, pairingFile: join(legacyRoot, 'bridge/.private/obsidian-companion.json'), receipts });
  const nodeRequire = createRequire(import.meta.url), touched = [];
  const filesystem = nodeRequire('node:fs/promises');
  const guarded = new Proxy(filesystem, { get(target, key) {
    if (!['open', 'realpath', 'lstat', 'readFile'].includes(key)) return target[key];
    return (...args) => {
      if (String(args[0]).startsWith(legacyRoot)) { touched.push(key); throw new Error('Documents must not be accessed'); }
      return target[key](...args);
    };
  } });
  const module = { exports: {} };
  const source = await readFile(new URL('../obsidian-kodex/core.cjs', import.meta.url), 'utf8');
  vm.runInNewContext(source, { module, Buffer, process, require: name => name === 'node:fs/promises' ? guarded : name === './protocol.cjs' ? P : nodeRequire(name) });
  const upgraded = new module.exports.Connection({ vault: f.vault, vaultRoot: f.vaultRoot, localRoot: f.localRoot, pairingsRoot: f.pairingsRoot, send: f.send });
  await upgraded.initialize();
  assert.equal(upgraded.state.pairingFile, f.pairingFile);
  assert.deepEqual(JSON.parse(JSON.stringify(upgraded.state.receipts)), receipts);
  await upgraded.call('/v1/status');
  await assert.rejects(upgraded.credentials(join(legacyRoot, 'pairing.json')), /Documents paths are not accessed/);
  assert.deepEqual(touched, []);
  assert.equal((await upgraded.call('/v1/status')).destinationId, f.client.state.destinationId);
});
