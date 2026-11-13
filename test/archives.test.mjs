import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtemp, rm, readdir, stat, readFile, writeFile, chmod, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DiskArchives, MemoryArchives } from '../archives.mjs';
import { ChatRegistry } from '../bridge.mjs';

const A = 'a'.repeat(32), B = 'b'.repeat(32);
class RPC extends EventEmitter {
  calls = []; sequence = 0;
  async request(method, params) {
    this.calls.push({ method, params });
    if (method === 'thread/start') return { thread: { id: 'thread-' + ++this.sequence }, sandbox: { type: 'readOnly', networkAccess: false }, approvalPolicy: 'never' };
    return { turn: { id: 'turn-' + this.sequence } };
  }
  answer(chat, text) {
    this.emit('notification', { method: 'item/completed', params: { threadId: chat.threadId, item: { id: 'answer', type: 'agentMessage', text } } });
    this.emit('notification', { method: 'turn/completed', params: { threadId: chat.threadId, turn: { status: 'completed' } } });
  }
}
const body = (text, requestId = 'archive-request-001') => ({ text, requestId });

test('document basename stays out of model input and survives archive/reopen with readable titles', async t => {
  const { store } = await disk(t);
  const rpc = new RPC(), chats = new ChatRegistry(rpc, '/empty', [], { archives: store });
  const documentName = 'The Book 中文.pdf';
  const request = { ...body('Selected passage text'), displayText: 'Explain this\n\nPassage: PDF physical page 3 (1-based)', documentName };
  await chats.prompt(request, A);
  assert.deepEqual(rpc.calls.find(c => c.method === 'turn/start').params.input, [{ type: 'text', text: request.text }]);
  rpc.answer(chats.chats.get(A), 'Answer');
  assert.match(chats.snapshot(A).messages[0].text, /Document: The Book 中文.pdf/);
  await assert.rejects(chats.prompt({ ...request, documentName: 'Another.pdf' }, A), /different text/);
  await chats.reset(A);
  const saved = (await chats.history(A)).archives[0];
  assert.equal(saved.title, `Explain this — ${documentName}`);
  assert.equal(saved.documentName, documentName);
  assert.equal((await store.load(A, saved.id)).documentName, documentName);
  await chats.reopen({ archiveId: saved.id }, A);
  await chats.prompt(body('Follow-up', 'follow-up-named-001'), A);rpc.answer(chats.chats.get(A), 'Another answer');
  await chats.reset(A);
  assert.equal((await chats.history(A)).archives[0].documentName, documentName);
});

test('document metadata rejects paths and unsafe names before allocating a conversation', async () => {
  const rpc = new RPC(), chats = new ChatRegistry(rpc, '/empty');
  for (const documentName of ['', '.', '..', '/private/Book.pdf', 'C:\\Book.pdf', 'Bad\nname.pdf', 'a'.repeat(241), 'bad\u202ename.pdf']) {
    await assert.rejects(chats.prompt({ ...body('Question'), documentName }, A));
  }
  await assert.rejects(chats.prompt({ ...body('Question'), documentName: 'Book.pdf' }), /requires a book/);
  assert.equal(rpc.calls.length, 0);assert.equal(chats.chats.size, 0);
});
async function disk(t, options) {
  const root = await mkdtemp(join(tmpdir(), 'kodex-archives-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const directory = join(root, 'archives');
  return { root, directory, store: new DiskArchives(directory, options) };
}

test('New chat archives per PDF, survives restart, reopens with bounded model context, and saves displaced chat', async t => {
  const { directory, store } = await disk(t);
  const rpc = new RPC(), chats = new ChatRegistry(rpc, '/empty', [], { archives: store });
  await chats.reset(A); assert.deepEqual((await chats.history(A)).archives, [], 'empty New chat creates no archive');
  await chats.prompt({ ...body('Question with QUOTED BOOK CONTEXT'), displayText: 'Explain this passage — page 12' }, A);
  rpc.answer(chats.chats.get(A), 'The explanation');
  const oldThread = chats.chats.get(A).threadId;
  await chats.prompt(body('Unrelated B question'), B); rpc.answer(chats.chats.get(B), 'B answer');
  const unchangedB = chats.snapshot(B);
  await chats.reset(A);
  assert.deepEqual(chats.snapshot(A).messages, []);
  assert.deepEqual(chats.snapshot(B), unchangedB);
  const history = await chats.history(A);
  assert.equal(history.archives.length, 1);
  assert.equal(history.archives[0].title, 'Explain this passage — page 12');
  assert.equal(JSON.stringify(history).includes('QUOTED BOOK CONTEXT'), false, 'list is metadata only');
  assert.equal((await chats.history(B)).archives.length, 0);
  const id = history.archives[0].id;
  assert.equal((await stat(directory)).mode & 0o777, 0o700);
  const files = await readdir(directory); assert.equal(files.length, 1);
  assert.equal((await stat(join(directory, files[0]))).mode & 0o777, 0o600);
  assert.equal((await store.load(A, id)).messages[0].wireText, 'Question with QUOTED BOOK CONTEXT');
  await assert.rejects(store.load(B, id), /not found/);
  const second = new ChatRegistry(new RPC(), '/empty', [], { archives: new DiskArchives(directory) });
  assert.equal((await second.history(A)).archives.length, 1, 'disk history survives a new registry/store');
  await second.reopen({ archiveId: id }, A);
  assert.equal(second.snapshot(A).messages.at(-1).text, 'The explanation');
  assert.equal(JSON.stringify(second.snapshot(A)).includes('wireText'), false);
  assert.equal(second.rpc.calls.length, 0, 'opening saved text does not call the model');
  await second.reopen({ archiveId: id }, A);
  assert.equal((await second.history(A)).archives.length, 1, 'retrying reopen does not duplicate archive');
  await second.prompt(body('Follow-up', 'follow-up-request-001'), A);
  const start = second.rpc.calls.find(c => c.method === 'turn/start');
  assert.match(start.params.input[0].text, /QUOTED BOOK CONTEXT/);
  assert.equal(start.params.input[1].text, 'Follow-up');
  assert.equal(start.params.sandboxPolicy.networkAccess, false);
  second.rpc.answer(second.chats.get(A), 'Follow-up answer');
  await second.reopen({ archiveId: id }, A);
  assert.equal((await second.history(A)).archives.length, 2, 'current chat saved before switching back');
  assert.equal(second.snapshot(A).messages.at(-1).text, 'The explanation');
  assert.notEqual(second.chats.get(A).threadId, oldThread);
});

test('archives retain older exchanges beyond the lightweight 12-message snapshot', async t => {
  const { store } = await disk(t);
  const rpc = new RPC(), registry = new ChatRegistry(rpc, '/empty', [], { archives: store });
  for (let i = 0; i < 8; i++) {
    await registry.prompt(body('Question ' + i, 'request-for-turn-' + i), A);
    rpc.answer(registry.chats.get(A), 'Answer ' + i);
  }
  assert.equal(registry.snapshot(A).messages.length, 12);
  await registry.reset(A);
  const id = (await registry.history(A)).archives[0].id;
  const saved = await store.load(A, id);
  assert.equal(saved.messages.length, 16); assert.equal(saved.messages[0].text, 'Question 0');
  await registry.reopen({ archiveId: id }, A);
  assert.equal(registry.snapshot(A).messages.length, 12);
  await registry.prompt(body('More', 'request-after-reopen'), A);
  assert.match(rpc.calls.at(-1).params.input[0].text, /Question 0/);
});

test('write failure and storage limits keep the current conversation; active and concurrent changes are rejected', async t => {
  const { store } = await disk(t, { maxPerDocument: 1 });
  const rpc = new RPC(), registry = new ChatRegistry(rpc, '/empty', [], { archives: store });
  await registry.prompt(body('First'), A);
  await assert.rejects(registry.reset(A), /Stop/);
  rpc.answer(registry.chats.get(A), 'First answer');
  await registry.reset(A);
  await registry.prompt(body('Second'), A); rpc.answer(registry.chats.get(A), 'Second answer');
  const current = registry.snapshot(A);
  await assert.rejects(registry.reset(A), /storage limit/);
  const archiveId = (await registry.history(A)).archives[0].id;
  await assert.rejects(registry.reopen({ archiveId }, A), /storage limit/);
  assert.deepEqual(registry.snapshot(A), current, 'archive failure never clears current');
  registry.archives = { save: async () => { throw new Error('Simulated disk failure'); } };
  const beforeFailure = rpc.calls.length;
  await assert.rejects(registry.reset(A), /archive storage is unavailable/);
  assert.deepEqual(registry.snapshot(A), current); assert.equal(rpc.calls.length, beforeFailure);
  let release;
  const waiting = new Promise(resolve => { release = resolve; });
  registry.archives = { save: () => waiting };
  const saving = registry.reset(A);
  assert.equal(registry.snapshot().pendingConversationChanges, 1);
  await assert.rejects(registry.prompt(body('Racing prompt'), A), /saved or reopened/);
  await assert.rejects(registry.reset(A), /changing conversations/);
  release(); await saving;
  const limited = new MemoryArchives({ maxBytes: 1 });
  await assert.rejects(limited.save(A, [{ role: 'user', text: 'too large' }]), /storage limit/);
});

test('private archive files reject traversal, symlinks, loose modes, corruption and mismatched identities', async t => {
  const { root, directory, store } = await disk(t);
  const metadata = await store.save(A, [{ role: 'user', text: 'Question' }, { role: 'assistant', text: 'Answer' }]);
  const target = join(directory, A + '-' + metadata.id + '.json');
  const original = await readFile(target);
  for (const id of ['../file', 'A'.repeat(32), '', 42]) await assert.rejects(store.load(A, id), /Invalid archive/);
  await chmod(target, 0o644); await assert.rejects(store.load(A, metadata.id), /Unsafe/);
  await chmod(target, 0o600);
  await writeFile(target, '{}'); await assert.rejects(store.load(A, metadata.id), /Invalid saved/);
  const wrong = JSON.parse(original); wrong.documentId = B;
  await writeFile(target, JSON.stringify(wrong)); await assert.rejects(store.load(A, metadata.id), /Invalid saved/);
  await rm(target); const outside = join(root, 'outside'); await writeFile(outside, original, { mode: 0o600 });
  await symlink(outside, target); await assert.rejects(store.load(A, metadata.id));
  await assert.rejects(store.list(A), /Unsafe/);
  await rm(target); await rm(directory, { recursive: true }); await symlink(root, directory);
  await assert.rejects(store.prepare(), /private/);
});

test('restored context stays bounded and is rechecked by the existing outbound secret guard', async () => {
  const store = new MemoryArchives();
  const meta = await store.save(A, [{ role: 'user', text: 'Safe question' }, { role: 'assistant', text: 'x'.repeat(80000) }]);
  const rpc = new RPC(), registry = new ChatRegistry(rpc, '/empty', [], { archives: store });
  await registry.reopen({ archiveId: meta.id }, A);
  await registry.prompt(body('Follow-up'), A);
  assert(rpc.calls.at(-1).params.input[0].text.length < 64200);
  rpc.answer(registry.chats.get(A), 'Done');
  const unsafe = await store.save(B, [{ role: 'user', text: '192.168.1.7' }]);
  await registry.reopen({ archiveId: unsafe.id }, B);
  const before = rpc.calls.length;
  await assert.rejects(registry.prompt(body('Follow-up'), B), /Prompt blocked/);
  assert.equal(rpc.calls.length, before);
  for (const value of [null, {}, { archiveId: '../file' }, { archiveId: meta.id, path: 'anything' }]) {
    await assert.rejects(registry.reopen(value, A));
  }
});


test('history bounds reject the next prompt before losing archivable messages', async () => {
  const rpc = new RPC(), registry = new ChatRegistry(rpc, '/empty');
  await registry.prompt(body('Original'), A); rpc.answer(registry.chats.get(A), 'Answer');
  const chat = registry.chats.get(A);
  chat.transcript = Array.from({ length: 200 }, (_, i) => ({ role: i % 2 ? 'assistant' : 'user', text: 'Message ' + i }));
  const before = rpc.calls.length;
  await assert.rejects(registry.prompt(body('One more', 'over-history-limit'), A), /history limit/);
  assert.equal(rpc.calls.length, before);
  await registry.reset(A);
  const saved = (await registry.history(A)).archives[0];
  assert.equal(saved.messageCount, 200);
});

test('disk listing extracts metadata without collecting transcript entries', async t => {
  const dir = await mkdtemp(join(tmpdir(), 'kodex-list-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const archives = new DiskArchives(dir);
  const saved = await archives.save(A, [{ role: 'user', text: 'Question' }, { role: 'assistant', text: 'x'.repeat(180000) }]);
  await archives.save(B, [{ role: 'user', text: 'Other document' }]);
  archives.entries = () => { throw new Error('Must not retain full transcripts'); };
  assert.deepEqual(await archives.list(A), [saved]);
});
