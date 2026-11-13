import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import https from 'node:https';
import { Chat, ChatRegistry, handler } from '../bridge.mjs';

const A = 'a'.repeat(32), B = 'b'.repeat(32), C = 'c'.repeat(32);
const prompt = (text, requestId = 'shared-request-001') => ({ text, requestId });
class RPC extends EventEmitter {
  calls = []; threads = 0; turns = 0; dead = false;
  async request(method, params) {
    this.calls.push({ method, params });
    if (method === 'thread/start') return { thread: { id: `thread-${++this.threads}` }, sandbox: { type: 'readOnly', networkAccess: false }, approvalPolicy: 'never' };
    if (method === 'turn/start') return { turn: { id: `turn-${++this.turns}` } };
    return {};
  }
  close() { this.dead = true; this.emit('closed'); }
  answer(chat, text, status = 'completed') {
    this.emit('notification', { method: 'item/agentMessage/delta', params: { threadId: chat.threadId, itemId: 'answer', delta: text } });
    this.emit('notification', { method: 'turn/completed', params: { threadId: chat.threadId, turn: { status } } });
  }
}

test('documents have distinct threads, history, retry IDs, stop and reset; general chat stays separate', async () => {
  const rpc = new RPC(), registry = new ChatRegistry(rpc, '/empty');
  for (let i = 0; i < 10; i++) assert.deepEqual(registry.snapshot(A).messages, []);
  assert.equal(registry.chats.size, 0, 'reading empty state must not allocate model threads');
  await registry.prompt(prompt('Question from PDF A'), A);
  const a = registry.chats.get(A);
  await registry.prompt(prompt('Different question from PDF B'), B);
  const b = registry.chats.get(B);
  assert.equal(registry.snapshot().runningDocumentReplies, 2, 'operational probes see active document replies');
  assert.equal(registry.snapshot().active, false, 'general chat remains independent');
  assert.notEqual(a.threadId, b.threadId);
  assert.equal(rpc.listenerCount('notification'), 1, 'one event router, not one listener per document');
  rpc.emit('notification', { method: 'item/agentMessage/delta', params: { threadId: a.threadId, itemId: 'answer', delta: 'Only A can see this' } });
  assert.equal(a.parts.get('answer'), 'Only A can see this');
  assert.equal(b.messages.at(-1).text, '');
  assert.equal(registry.snapshot(A).messages.at(-1).text, '', 'still display completed answers only');
  await registry.stop(B);
  assert.equal(rpc.calls.at(-1).params.threadId, b.threadId);
  assert.equal(rpc.calls.at(-1).params.turnId, b.turnId);
  rpc.answer(b, 'B answer', 'interrupted');
  rpc.answer(a, ' — A finished');
  assert.equal(registry.snapshot().runningDocumentReplies, 0);
  const originalA = registry.snapshot(A), originalB = registry.snapshot(B);
  assert.equal(JSON.stringify(originalA).includes('PDF B'), false);
  assert.equal(JSON.stringify(originalB).includes('Only A'), false);
  await registry.prompt(prompt('Question from PDF A'), A);
  assert.deepEqual(registry.snapshot(A), originalA, 'retry after switching documents must resume the same chat');
  assert.equal(rpc.calls.filter(c => c.method === 'turn/start').length, 2);
  await registry.prompt(prompt('General chat, no document'));
  assert.equal(registry.snapshot().messages[0].text, 'General chat, no document');
  assert.deepEqual(registry.snapshot(A), originalA);
  const aThread = a.threadId;
  await registry.reset(A);
  assert.deepEqual(registry.snapshot(A), { documentId: A, active: false, messages: [], notice: '' });
  assert.deepEqual(registry.snapshot(B), originalB, 'reset only current document');
  assert.equal(rpc.calls.at(-1).method, 'thread/unsubscribe');
  assert.equal(rpc.calls.at(-1).params.threadId, aThread);
  await registry.prompt(prompt('Fresh A question', 'new-A-request-001'), A);
  assert.notEqual(registry.chats.get(A).threadId, aThread);
});

test('scoped snapshots keep readable questions after client reopen while full quotes reach only that model thread', async () => {
  const rpc = new RPC(), registry = new ChatRegistry(rpc, '/empty');
  const body = { ...prompt('Question plus bounded selected quotation'), displayText: 'What does this mean?\n\nPassage: PDF physical page 12 (1-based)' };
  await registry.prompt(body, A);
  const turn = rpc.calls.find(c => c.method === 'turn/start');
  assert.deepEqual(turn.params.input, [{ type: 'text', text: body.text }]);
  assert.equal(JSON.stringify(turn.params).includes('displayText'), false);
  assert.equal(JSON.stringify(turn.params).includes(A), false, 'document identity is not model context');
  assert.equal(registry.snapshot(A).messages[0].text, body.displayText);
  await assert.rejects(registry.prompt({ ...body, displayText: 'Changed label' }, A), /different text/);
  assert.deepEqual(registry.snapshot(B).messages, []);
  rpc.answer(registry.chats.get(A), 'Answer A');
  rpc.close();
  assert.equal(registry.snapshot(A).active, false);
  assert.equal(registry.snapshot(A).messages.at(-1).text, 'Answer A');
  assert.equal(registry.snapshot(B).messages.length, 0);
});

test('limits reject new work without evicting another document; reset frees slots', async () => {
  const rpc = new RPC(), registry = new ChatRegistry(rpc, '/empty', [], { maxDocuments: 2, maxActive: 1, maxRequests: 10 });
  await registry.prompt(prompt('A'), A);
  await assert.rejects(registry.prompt(prompt('B'), B), /replies are still running/);
  assert.equal(registry.chats.has(B), false);
  await registry.prompt(prompt('A'), A);
  rpc.answer(registry.chats.get(A), 'Answer A');
  await registry.prompt(prompt('B'), B);
  rpc.answer(registry.chats.get(B), 'Answer B');
  await assert.rejects(registry.prompt(prompt('C'), C), /Document chat limit/);
  assert.equal(registry.snapshot(A).messages.at(-1).text, 'Answer A');
  await registry.reset(A);
  await registry.prompt(prompt('C'), C);
  assert.equal(registry.chats.size, 2);
  const small = new ChatRegistry(new RPC(), '/empty', [], { maxRequests: 1 });
  await small.prompt(prompt('A'), A);
  await assert.rejects(small.prompt(prompt('B'), B), /session limit/);
  await small.prompt(prompt('A'), A); // retry remains allowed
});

test('invalid identities, unexpected fields and sensitive text do not allocate chats or reach model RPC', async () => {
  const rpc = new RPC(), registry = new ChatRegistry(rpc, '/empty');
  for (const key of ['', 'A'.repeat(32), '../file', '/private/book.pdf', 'a'.repeat(31), 42, {}, []]) {
    await assert.rejects(registry.prompt(prompt('Question'), key), /Invalid document/);
  }
  for (const body of [{ ...prompt('Question'), path: '/book.pdf' }, { ...prompt('Question'), threadId: 'other' },
    { ...prompt('Question'), displayText: '' }, { ...prompt('Question'), displayText: 'x'.repeat(16001) },
    prompt('token=sk-secret-canary-000000000000000000000000000000'),
    { ...prompt('Question'), displayText: 'token=sk-secret-canary-000000000000000000000000000000' }]) {
    await assert.rejects(registry.prompt(body, A));
  }
  assert.equal(rpc.calls.length, 0); assert.equal(registry.chats.size, 0);
});

test('real HTTPS routes enforce document isolation, scoped empty reset, auth, and old-bridge fail-closed behavior', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'kodex-document-https-'));
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', join(dir, 'key'), '-out', join(dir, 'cert'), '-days', '1', '-subj', '/CN=localhost'], { stdio: 'ignore' });
  const rpc = new RPC(), registry = new ChatRegistry(rpc, '/empty');
  const server = https.createServer({ key: readFileSync(join(dir, 'key')), cert: readFileSync(join(dir, 'cert')) }, handler(registry, 'test-token'));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => { server.closeAllConnections(); server.close(); rmSync(dir, { recursive: true, force: true }); });
  const request = (path, method = 'GET', body, auth = 'test-token', revision) => new Promise((resolve, reject) => {
    const req = https.request({ hostname: '127.0.0.1', port: server.address().port, servername: 'localhost', ca: readFileSync(join(dir, 'cert')),
      path, method, headers: { authorization: `Bearer ${auth}`, 'content-type': 'application/json', ...(revision ? { 'x-kodex-revision': revision } : {}) } }, res => {
      let data = ''; res.on('data', part => data += part); res.on('end', () => resolve({ status: res.statusCode, body: JSON.parse(data) }));
    }); req.on('error', reject); req.end(body === undefined ? undefined : JSON.stringify(body));
  });
  const path = (id, operation) => `/v1/documents/${id}/${operation}`;
  assert.equal((await request(path(A, 'state'), 'GET', undefined, 'bad')).status, 401);
  assert.deepEqual((await request(path(A, 'state'))).body, { documentId: A, active: false, messages: [], notice: '' });
  assert.equal((await request(path(A, 'prompt'), 'POST', prompt('PDF A question'))).status, 200);
  assert.equal((await request(path(B, 'state'))).body.messages.length, 0);
  assert.equal((await request('/v1/state')).body.messages.length, 0);
  assert.equal((await request(path(B, 'reset'), 'POST', {})).status, 200);
  assert.equal((await request(path(A, 'reset'), 'POST', {})).status, 409);
  rpc.answer(registry.chats.get(A), 'A answer');
  assert.equal((await request(path(A, 'state'))).body.messages.at(-1).text, 'A answer');
  const full = (await request(path(A, 'state'), 'GET', undefined, 'test-token', '0')).body;
  const compact = (await request(path(A, 'state'), 'GET', undefined, 'test-token', full.revision)).body;
  assert.equal(compact.messages, undefined);
  assert.equal(compact.active, false);
  assert.equal(compact.revision, full.revision);
  assert.deepEqual((await request(path(B, 'state'), 'GET', undefined, 'test-token', full.revision)).body.messages, []);
  assert.equal((await request(path(A, 'reset'), 'POST', { documentId: B })).status, 400);
  assert.equal((await request(path(A, 'reset'), 'POST', {})).status, 200);
  const history = await request(path(A, 'history'));
  assert.equal(history.status, 200); assert.equal(history.body.documentId, A);
  const archiveId = history.body.archives[0].id;
  assert.equal((await request(path(B, 'history'))).body.archives.length, 0);
  assert.equal((await request(path(A, 'history'), 'GET', undefined, 'bad')).status, 401);
  assert.equal((await request(path(B, 'reopen'), 'POST', { archiveId })).status, 404);
  assert.equal((await request(path(A, 'reopen'), 'POST', { archiveId, path: 'book' })).status, 400);
  assert.equal((await request('/v1/reopen', 'POST', { archiveId })).status, 404);
  assert.equal((await request(path(A, 'reopen'), 'POST', { archiveId })).body.messages.at(-1).text, 'A answer');

  assert.equal((await request(path(A, 'recognize'))).status, 404);
  assert.equal((await request(`/v1/documents/${'g'.repeat(32)}/state`)).status, 404);
  assert.equal((await request(`/v1/documents/${A}/state?path=book`)).status, 404);
  assert.equal((await request(path(A, 'prompt'), 'POST', { ...prompt('X'), path: 'book' })).status, 400);
  // A previous single-chat bridge must reject scoped URLs, not silently send
  // this question into its shared conversation.
  const old = new Chat(new RPC(), '/empty');
  const oldHandler = handler(old, 'test-token');
  let status;
  await oldHandler({ method: 'POST', url: path(A, 'prompt'), headers: { authorization: 'Bearer test-token' } },
    { destroyed: false, writeHead: code => { status = code; }, end: () => {} });
  assert.equal(status, 404); assert.equal(old.messages.length, 0);
});
