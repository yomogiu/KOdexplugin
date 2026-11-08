import { randomBytes } from 'node:crypto';
import { mkdir, lstat, readdir, open, rename, unlink } from 'node:fs/promises';
import { join } from 'node:path';

const ID = /^[a-f0-9]{32}$/;
const MAX_FILE = 3000000;
function checkId(id) {
  if (typeof id !== 'string' || !ID.test(id)) throw Object.assign(new Error('Invalid archive identity'), { status: 400 });
}
function checkRecord(record, documentId, id) {
  if (!record || record.version !== 1 || record.documentId !== documentId || record.id !== id ||
      typeof record.createdAt !== 'string' || !Number.isFinite(Date.parse(record.createdAt)) ||
      typeof record.title !== 'string' || record.title.length > 160 ||
      !Array.isArray(record.messages) || !record.messages.length || record.messages.length > 200 ||
      record.messages.some(m => !m || !['user', 'assistant'].includes(m.role) ||
        typeof m.text !== 'string' || m.text.length > 180000 ||
        (m.wireText !== undefined && (m.role !== 'user' || typeof m.wireText !== 'string' || m.wireText.length > 16000)))) {
    throw new Error('Invalid saved conversation; archive left unchanged');
  }
  return record;
}
function metadata({ id, createdAt, title, messages }) {
  return { id, createdAt, title, messageCount: messages.length };
}

// A memory implementation keeps registry unit tests independent of disk.
export class MemoryArchives {
  constructor({ maxPerDocument = 50, maxArchives = 500, maxBytes = 128 * 1024 * 1024 } = {}) {
    this.records = new Map();
    Object.assign(this, { maxPerDocument, maxArchives, maxBytes });
    this.queue = Promise.resolve();
  }
  serial(action) {
    const result = this.queue.then(action);
    this.queue = result.catch(() => {});
    return result;
  }
  async entries() { return [...this.records.values()]; }
  async catalog() {
    return (await this.entries()).map(r => ({ documentId: r.documentId, ...metadata(r) }));
  }
  async inventory() {
    return [...this.records.values()].map(r => ({ name: r.documentId + '-' + r.id + '.json', size: Buffer.byteLength(JSON.stringify(r)) }));
  }
  async write(record, payload) { this.records.set(record.documentId + '-' + record.id, JSON.parse(payload)); }
  async load(documentId, id) {
    checkId(documentId); checkId(id);
    const record = this.records.get(documentId + '-' + id);
    if (!record) throw Object.assign(new Error('Saved conversation not found for this document'), { status: 404 });
    return structuredClone(record);
  }
  async list(documentId) {
    checkId(documentId);
    return (await this.entries()).filter(r => r.documentId === documentId)
      .map(metadata).sort((a, b) => b.createdAt.localeCompare(a.createdAt) || b.id.localeCompare(a.id));
  }
  async save(documentId, messages) {
    checkId(documentId);
    if (!messages.length) return null;
    return this.serial(async () => {
      const firstQuestion = messages.find(m => m.role === 'user')?.text || 'Conversation';
      const title = [...firstQuestion.replace(/[\s\x00-\x1f\x7f]+/g, ' ').trim()].slice(0, 70).join('');
      const id = randomBytes(16).toString('hex');
      const record = checkRecord({ version: 1, documentId, id,
        createdAt: new Date().toISOString(), title, messages: structuredClone(messages) }, documentId, id);
      const payload = JSON.stringify(record);
      const size = Buffer.byteLength(payload);
      const files = await this.inventory();
      if (size > MAX_FILE || files.length >= this.maxArchives ||
          files.filter(f => f.name.startsWith(documentId + '-')).length >= this.maxPerDocument ||
          files.reduce((n, f) => n + f.size, 0) + size > this.maxBytes) {
        throw Object.assign(new Error('Archive storage limit reached. Current conversation was kept; manage saved archives on the Mac.'), { status: 409 });
      }
      await this.write(record, payload);
      return metadata(record);
    });
  }
}

// All filesystem work is async and happens only on archive/list/reopen, never
// on polling or streamed model updates. Paths derive solely from opaque IDs.
export class DiskArchives extends MemoryArchives {
  constructor(directory, options) { super(options); this.directory = directory; }
  async prepare() {
    await mkdir(this.directory, { mode: 0o700, recursive: true });
    const stat = await lstat(this.directory);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077)) {
      throw new Error('Archive directory must be private and owned by this user');
    }
  }
  async files() {
    await this.prepare();
    const result = [];
    for (const name of await readdir(this.directory)) {
      if (!/^[a-f0-9]{32}-[a-f0-9]{32}\.json$/.test(name)) continue;
      const stat = await lstat(join(this.directory, name));
      if (!stat.isFile() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077) || stat.size > MAX_FILE) {
        throw new Error('Unsafe saved conversation file; archive left unchanged');
      }
      result.push({ name, size: stat.size });
    }
    return result;
  }
  async inventory() { return this.files(); }
  async write(record, payload) {
    await this.prepare();
    const path = join(this.directory, record.documentId + '-' + record.id + '.json');
    const temporary = path + '.tmp-' + randomBytes(8).toString('hex');
    let file;
    try {
      file = await open(temporary, 'wx', 0o600);
      await file.writeFile(payload); await file.sync(); await file.close(); file = null;
      await rename(temporary, path);
      const directory = await open(this.directory, 'r');
      try { await directory.sync(); } finally { await directory.close(); }
    } finally {
      await file?.close();
      await unlink(temporary).catch(e => { if (e.code !== 'ENOENT') throw e; });
    }
  }
  async load(documentId, id) {
    checkId(documentId); checkId(id); await this.prepare();
    const path = join(this.directory, documentId + '-' + id + '.json');
    let file;
    try {
      // O_NOFOLLOW prevents substituting a symlink between checking and reading.
      const { constants } = await import('node:fs');
      file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
      const stat = await file.stat();
      if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o077) || stat.size > MAX_FILE) throw new Error('Unsafe saved conversation file');
      return checkRecord(JSON.parse(await file.readFile('utf8')), documentId, id);
    } catch (e) {
      if (e.code === 'ENOENT') throw Object.assign(new Error('Saved conversation not found for this document'), { status: 404 });
      throw e;
    } finally { await file?.close(); }
  }
  async entries(documentId) {
    const files = await this.files();
    const records = [];
    for (const { name } of files) {
      if (name.slice(0, 32) === documentId) records.push(await this.load(documentId, name.slice(33, 65)));
    }
    return records;
  }
  async catalog() {
    const result = [];
    for (const { name } of await this.files()) {
      const documentId = name.slice(0, 32);
      result.push({ documentId, ...metadata(await this.load(documentId, name.slice(33, 65))) });
    }
    return result;
  }
  async list(documentId) {
    checkId(documentId);
    return (await this.entries(documentId)).map(metadata)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt) || b.id.localeCompare(a.id));
  }
}
