import { constants } from 'node:fs';
import { access, lstat, mkdir, open, realpath, rename, unlink } from 'node:fs/promises';
import { basename, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { homedir } from 'node:os';
import { randomBytes } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const exec = promisify(execFile);
const ID = /^[a-f0-9]{32}$/;
const BUNDLE = 'md.obsidian';
export const DEFAULT_SUBFOLDER = 'Reading/KOdex';
const missing = e => e.code === 'ENOENT';
const UNSAFE_TEXT = /[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/;
const SETTINGS_LIMIT = 16384;

// Paths and OS error strings are untrusted terminal output. Keep intended line
// breaks but render escape/control and bidi formatting characters visibly.
export function terminalText(value) {
  return String(value).replace(/[\x00-\x08\x0b-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/g,
    c => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`);
}

async function privateDirectory(path) {
  const stat = await lstat(path);
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077)) {
    throw new Error('Settings need a private, user-owned .private folder');
  }
}

async function jsonFile(path, { privateFile = false, limit = 1024 * 1024 } = {}) {
  // O_NONBLOCK prevents a FIFO from hanging before fstat can reject it.
  const file = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW | constants.O_NONBLOCK);
  try {
    const stat = await file.stat();
    if (!stat.isFile() || stat.size > limit || (privateFile &&
        (stat.uid !== process.getuid() || (stat.mode & 0o077) || stat.nlink !== 1))) throw new Error('Unsafe or oversized configuration file');
    // Read at most limit + 1 bytes even if another process grows the file.
    const buffer = Buffer.alloc(limit + 1);
    const { bytesRead } = await file.read(buffer, 0, buffer.length, 0);
    if (bytesRead > limit) throw new Error('Oversized configuration file');
    try { return JSON.parse(buffer.subarray(0, bytesRead).toString('utf8')); }
    catch { throw new Error('Invalid JSON configuration; existing file was preserved'); }
  } finally { await file.close(); }
}

export function absolutePath(value) {
  if (typeof value !== 'string' || value.length > 4096 || !isAbsolute(value) || UNSAFE_TEXT.test(value)) {
    throw new Error('Choose an absolute local folder path');
  }
  return resolve(value);
}

export function subfolder(value) {
  if (typeof value !== 'string' || value.length > 240 || isAbsolute(value) ||
      (value.includes('\\') || UNSAFE_TEXT.test(value)) ||
      (value !== '' && value.split('/').some(p => !p || p === '.' || p === '..' || p.startsWith('.')))) {
    throw new Error('Use a relative subfolder without hidden folders or parent traversal');
  }
  return value;
}

async function directory(path) {
  const canonical = await realpath(absolutePath(path));
  absolutePath(canonical);
  if (!(await lstat(canonical)).isDirectory()) throw new Error('The selected path is not a folder');
  return canonical;
}

// No creation here: missing destinations stay missing during status checks.
export async function inspectDestination(path, folder = '', { requireCanonical = false } = {}) {
  const root = await directory(path);
  if (requireCanonical && root !== absolutePath(path)) throw new Error('Destination path changed or became a link; reconnect it explicitly');
  subfolder(folder);
  await access(root, constants.W_OK | constants.X_OK);
  let current = root;
  for (const part of folder ? folder.split('/') : []) {
    current = join(current, part);
    try {
      const stat = await lstat(current);
      if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Export subfolders must be ordinary directories, not links');
      await access(current, constants.W_OK | constants.X_OK);
    } catch (e) {
      if (!missing(e)) throw e;
      break;
    }
  }
  return { root, output: join(root, folder), availability: 'available' };
}

// Isolated adapter for Obsidian's undocumented, local discovery metadata.
// No directory scan, note reads, or writes to Obsidian's registry.
export async function discoverVaults(home = homedir()) {
  try {
    const data = await jsonFile(join(home, 'Library/Application Support/obsidian/obsidian.json'));
    if (!data?.vaults || typeof data.vaults !== 'object' || Array.isArray(data.vaults)) throw new Error('Invalid registry');
    const entries = Object.entries(data.vaults);
    if (entries.length > 200) throw new Error('Registry exceeds discovery limit');
    const vaults = [], seen = new Set();
    for (const [id, item] of entries) {
      if (!/^[a-f0-9]{16}$/.test(id) || typeof item?.path !== 'string') continue;
      try {
        const path = absolutePath(item.path);
        let canonical = path, available = true;
        try { canonical = await directory(path); } catch { available = false; }
        if (seen.has(canonical)) continue;
        seen.add(canonical);
        vaults.push({ id, path: canonical, name: basename(canonical), available });
      } catch { /* Malformed entry does not block manual selection. */ }
    }
    return { vaults, notice: null };
  } catch (e) {
    return { vaults: [], notice: missing(e) ? 'No known vaults found. Choose a folder manually.' : 'Vault discovery unavailable. Choose a folder manually.' };
  }
}

export async function validateApp(path, run = exec) {
  const app = await directory(path);
  const { stdout } = await run('/usr/bin/plutil', ['-extract', 'CFBundleIdentifier', 'raw', '-o', '-', join(app, 'Contents/Info.plist')], { timeout: 5000, maxBuffer: 8192 });
  if (stdout.trim() !== BUNDLE) throw new Error('Choose the Obsidian application');
  return app;
}

export async function detectApp({ home = homedir(), platform = process.platform, run = exec, preferredPath = null } = {}) {
  if (platform !== 'darwin') return null;
  if (preferredPath) {
    try { return await validateApp(preferredPath, run); } catch { /* Re-detect if moved or removed. */ }
  }
  // NSWorkspace checks Launch Services without starting Obsidian.
  try {
    const { stdout } = await run('/usr/bin/osascript', ['-l', 'JavaScript', '-e',
      'ObjC.import("AppKit"); var u = $.NSWorkspace.sharedWorkspace.URLForApplicationWithBundleIdentifier("md.obsidian"); u.isNil() ? "" : ObjC.unwrap(u.path);'], { timeout: 5000, maxBuffer: 8192 });
    if (stdout.trim()) return await validateApp(stdout.trim(), run);
  } catch { /* Conventional locations are a bounded fallback. */ }
  for (const path of ['/Applications/Obsidian.app', join(home, 'Applications/Obsidian.app')]) {
    try { return await validateApp(path, run); } catch { /* Manual Locate remains available. */ }
  }
  return null;
}

export async function chooseFolder(run = exec) {
  const { stdout } = await run('/usr/bin/osascript', ['-e', 'POSIX path of (choose folder with prompt "Choose the reading notes folder")'], { timeout: 120000, maxBuffer: 8192 });
  return absolutePath(stdout.trim());
}

export async function chooseApp(run = exec) {
  const { stdout } = await run('/usr/bin/osascript', ['-e', 'POSIX path of (choose file with prompt "Choose Obsidian.app" of type {"com.apple.application-bundle"})'], { timeout: 120000, maxBuffer: 8192 });
  return validateApp(stdout.trim(), run);
}

export async function openObsidian(appPath, run = exec) {
  const app = await validateApp(appPath, run);
  await run('/usr/bin/open', ['-a', app, 'obsidian://choose-vault'], { timeout: 5000 });
}

export async function createReadingFolder(parent, name) {
  if (typeof name !== 'string' || !name.trim() || name.length > 100 ||
      name.startsWith('.') || /[/:\\]/.test(name) || UNSAFE_TEXT.test(name)) throw new Error('Use a simple folder name without slashes or a leading dot');
  const path = join(await directory(parent), name);
  // Exclusive creation: an existing folder must be connected explicitly instead.
  await mkdir(path, { mode: 0o700 });
  try {
    for (const name of ['Books', 'Conversations', 'Attachments']) await mkdir(join(path, name), { mode: 0o700 });
    await exclusiveNote(join(path, 'Welcome.md'), '# Reading\n\nThis folder is ready for reading notes.\n\nIn Obsidian, use Manage Vaults → Open folder as vault and select this folder.\n\nKOdex export delivery is not implemented yet; configuring this destination does not export conversations.\n');
  } catch (e) {
    throw new Error(`Folder partly created at ${path}. Contents were preserved; inspect it and choose Connect existing folder to recover. ${e.message}`);
  }
  return path;
}

async function exclusiveNote(path, content) {
  const file = await open(path, 'wx', 0o600);
  try { await file.writeFile(content); await file.sync(); } finally { await file.close(); }
}

export async function writeSample(destination) {
  const { root } = await inspectDestination(destination.root, destination.subfolder, { requireCanonical: true });
  let output = root;
  // Refuse links in each component, including ones created since setup.
  for (const part of destination.subfolder ? destination.subfolder.split('/') : []) {
    output = join(output, part);
    try { await mkdir(output, { mode: 0o700 }); } catch (e) { if (e.code !== 'EEXIST') throw e; }
    const stat = await lstat(output);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('Unsafe sample destination');
    const rel = relative(root, await realpath(output));
    if (rel === '..' || rel.startsWith('..' + sep) || isAbsolute(rel)) throw new Error('Sample destination escaped selected folder');
  }
  const path = join(output, `KOdex sample-${randomBytes(8).toString('hex')}.md`);
  await exclusiveNote(path, '# KOdex sample\n\nThe Mac can write Markdown to this destination.\n\nThis is a setup sample, not an exported conversation. Export delivery is not implemented yet.\n');
  return path;
}

export function validateSettings(value) {
  const exactKeys = (record, keys) => record && typeof record === 'object' && !Array.isArray(record) &&
    Object.keys(record).length === keys.length && keys.every(key => Object.hasOwn(record, key));
  if (!exactKeys(value, ['version', 'state', 'appPath', 'destination']) || value.version !== 1 || !['deferred', 'connected', 'disconnected'].includes(value.state) ||
      (value.appPath !== null && typeof value.appPath !== 'string')) throw new Error('Invalid Obsidian settings; existing file was preserved');
  if (value.appPath !== null) absolutePath(value.appPath);
  if (value.destination !== null) {
    const d = value.destination;
    if (!exactKeys(d, ['id', 'root', 'subfolder', 'kind', 'registration']) || typeof d.id !== 'string' || !ID.test(d.id) || !['obsidian', 'markdown'].includes(d.kind) ||
        !['known', 'unverified'].includes(d.registration)) throw new Error('Invalid destination settings');
    absolutePath(d.root); subfolder(d.subfolder);
  }
  if (value.state === 'connected' && !value.destination) throw new Error('Connected destination is missing');
  if (value.state === 'deferred' && value.destination) throw new Error('Deferred settings cannot contain a destination');
  if (Buffer.byteLength(JSON.stringify(value, null, 2) + '\n') > SETTINGS_LIMIT) throw new Error('Settings exceed storage limit');
  return value;
}

export async function loadSettings(privateRoot) {
  await privateDirectory(privateRoot);
  try { return validateSettings(await jsonFile(join(privateRoot, 'obsidian.json'), { privateFile: true, limit: SETTINGS_LIMIT })); }
  catch (e) { if (missing(e)) return null; throw e; }
}

export async function saveSettings(privateRoot, settings) {
  validateSettings(settings);
  // Setup does not create or repair pairing, and never stores settings in a vault.
  await privateDirectory(privateRoot);
  const target = join(privateRoot, 'obsidian.json');
  const temporary = target + '.tmp-' + randomBytes(8).toString('hex');
  try {
    await exclusiveNote(temporary, JSON.stringify(settings, null, 2) + '\n');
    await rename(temporary, target);
    const dir = await open(privateRoot, 'r');
    try { await dir.sync(); } finally { await dir.close(); }
  } finally { await unlink(temporary).catch(e => { if (!missing(e)) throw e; }); }
}

export async function connectDestination(settings, { root, folder = DEFAULT_SUBFOLDER, kind, vaults = [] }) {
  if (!['obsidian', 'markdown'].includes(kind)) throw new Error('Choose a destination type');
  const checked = await inspectDestination(root, folder);
  const known = vaults.some(v => v.available && v.path === checked.root);
  const previous = settings?.destination;
  const same = previous && previous.root === checked.root && previous.subfolder === folder && previous.kind === kind;
  return validateSettings({ version: 1, state: 'connected', appPath: settings?.appPath ?? null,
    destination: { id: same ? previous.id : randomBytes(16).toString('hex'), root: checked.root,
      subfolder: folder, kind, registration: known ? 'known' : 'unverified' } });
}
