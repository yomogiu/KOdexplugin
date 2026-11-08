import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile, readdir, rm, stat, symlink, chmod, realpath, link, rename } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { connectDestination, inspectDestination, createReadingFolder, writeSample,
  saveSettings, loadSettings, discoverVaults, detectApp, validateApp, subfolder, validateSettings } from '../obsidian.mjs';
import { runSetup } from '../obsidian-setup.mjs';

async function fixture(t) {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'kodex-obsidian-')));
  t.after(() => rm(root, { recursive: true, force: true }));
  const privateRoot = join(root, '.private');
  await mkdir(privateRoot, { mode: 0o700 });
  await writeFile(join(privateRoot, 'bridge.json'), 'pairing stays unchanged', { mode: 0o600 });
  const vault = join(root, 'Notes ü'); await mkdir(vault);
  return { root, privateRoot, vault };
}

async function wizard(f, answers, overrides = {}) {
  const output = [];
  let index = 0;
  const settings = await runSetup({ privateRoot: f.privateRoot,
    ask: async prompt => {
      if (index >= answers.length) throw new Error('Missing scripted response: ' + prompt);
      return answers[index++];
    }, say: text => output.push(text), platform: 'darwin',
    detect: async () => null, discover: async () => ({ vaults: [], notice: 'Choose manually' }),
    pickFolder: async () => { throw new Error('Picker cancelled'); },
    pickApp: async () => { throw new Error('Picker cancelled'); },
    openManager: async () => { throw new Error('App unavailable'); }, ...overrides });
  assert.equal(index, answers.length, 'all intended workflow steps were exercised');
  assert.equal(await readFile(join(f.privateRoot, 'bridge.json'), 'utf8'), 'pairing stays unchanged');
  return { settings, output: output.join('\n') };
}

test('missing app: defer without creating a destination or touching pairing', async t => {
  const f = await fixture(t);
  const { settings, output } = await wizard(f, ['5', '0']);
  assert.equal(settings.state, 'deferred'); assert.equal(settings.destination, null);
  assert.match(output, /not detected/); assert.match(output, /https:\/\/obsidian.md\/download/);
  assert.deepEqual(await readdir(f.vault), []);
  assert.deepEqual(await loadSettings(f.privateRoot), settings);
  assert.equal((await stat(join(f.privateRoot, 'obsidian.json'))).mode & 0o777, 0o600);
});

test('Markdown destination connects without app, offers sample, and preserves user files', async t => {
  const f = await fixture(t);
  await writeFile(join(f.vault, 'My note.md'), 'user text');
  const { settings, output } = await wizard(f, ['3', f.vault, '', 'y', 'y', '0']);
  assert.equal(settings.state, 'connected'); assert.equal(settings.destination.kind, 'markdown');
  assert.equal(settings.destination.subfolder, 'Reading/KOdex');
  assert.match(output, /Sample saved/); assert.match(output, /not implemented yet/);
  assert.equal(await readFile(join(f.vault, 'My note.md'), 'utf8'), 'user text');
  assert.equal((await readdir(join(f.vault, 'Reading/KOdex'))).length, 1);
  assert.equal((await readdir(f.vault)).includes('.obsidian'), false);
});

test('multiple known vaults require explicit selection and never default to first', async t => {
  const f = await fixture(t); const other = join(f.root, 'Other'); await mkdir(other);
  const discovery = { vaults: [{ id: 'a'.repeat(16), name: 'First', path: other, available: true },
    { id: 'b'.repeat(16), name: 'Second', path: f.vault, available: true }], notice: null };
  const { settings } = await wizard(f, ['1', '2', '', 'y', 'n', '0'], { discover: async () => discovery });
  assert.equal(settings.destination.root, f.vault); assert.equal(settings.destination.registration, 'known');
  assert.deepEqual(await readdir(other), []); assert.deepEqual(await readdir(f.vault), []);
  const second = await wizard(f, ['1', '', other, '', 'n', '0'], { discover: async () => discovery });
  assert.equal(second.settings.destination.id, settings.destination.id, 'declining connection keeps existing settings');
});

test('new reading folder is exclusive and registration/open failure does not undo configured folder', async t => {
  const f = await fixture(t);
  const { settings, output } = await wizard(f, ['2', f.root, 'Reading', 'y', '', 'y', 'n', 'y', '0'], {
    detect: async () => '/Applications/Obsidian.app',
  });
  assert.equal(settings.destination.registration, 'unverified'); assert.equal(settings.destination.subfolder, '');
  assert.match(output, /Open folder as vault/); assert.match(output, /destination is still configured/);
  assert.deepEqual((await readdir(join(f.root, 'Reading'))).sort(), ['Attachments', 'Books', 'Conversations', 'Welcome.md']);
  await assert.rejects(createReadingFolder(f.root, 'Reading'), { code: 'EEXIST' });
  assert.match(await readFile(join(f.root, 'Reading/Welcome.md'), 'utf8'), /not implemented/);
});

test('folder creation can be cancelled and collisions offer explicit connection', async t => {
  const f = await fixture(t);
  await wizard(f, ['2', f.root, 'Cancelled', 'n', '0']);
  await assert.rejects(stat(join(f.root, 'Cancelled')), { code: 'ENOENT' });
  const { output } = await wizard(f, ['2', f.root, 'Notes ü', 'y', '0']);
  assert.match(output, /already exists.*Connect existing/);
  assert.deepEqual(await readdir(f.vault), []);
});

test('cancelled picker, stale vault, and invalid subfolder keep setup recoverable', async t => {
  const f = await fixture(t);
  const stale = join(f.root, 'Missing');
  const { settings, output } = await wizard(f,
    ['3', '', '1', '1', '', '3', f.vault, '../escape', '0'], {
      discover: async () => ({ vaults: [{ name: 'Stale', path: stale, available: false }], notice: null }),
    });
  assert.equal(settings.destination, null); assert.match(output, /Picker cancelled/);
  assert.match(output, /unavailable/); assert.match(output, /parent traversal/);
  await assert.rejects(stat(stale), { code: 'ENOENT' });
});

test('disconnect retains settings identity and notes; missing destination status never recreates it', async t => {
  const f = await fixture(t);
  const connected = await connectDestination(null, { root: f.vault, kind: 'obsidian' });
  await saveSettings(f.privateRoot, connected);
  await rm(f.vault, { recursive: true });
  const { settings, output } = await wizard(f, ['7', 'n', '7', 'y', '0']);
  assert.equal(settings.state, 'disconnected'); assert.equal(settings.destination.id, connected.destination.id);
  assert.match(output, /Needs attention/); await assert.rejects(stat(f.vault), { code: 'ENOENT' });
});

test('destination identity is stable when reconnecting, changes for a different output', async t => {
  const f = await fixture(t);
  const first = await connectDestination(null, { root: f.vault, kind: 'markdown' });
  const same = await connectDestination(first, { root: f.vault, kind: 'markdown' });
  const changed = await connectDestination(first, { root: f.vault, folder: 'Other', kind: 'markdown' });
  assert.equal(same.destination.id, first.destination.id); assert.notEqual(changed.destination.id, first.destination.id);
});

test('discovery tolerates missing/corrupt registry and preserves multiple/stale entries without scanning', async t => {
  const f = await fixture(t);
  assert.deepEqual((await discoverVaults(f.root)).vaults, []);
  const registryRoot = join(f.root, 'Library/Application Support/obsidian'); await mkdir(registryRoot, { recursive: true });
  const registry = join(registryRoot, 'obsidian.json');
  await writeFile(registry, '{bad'); assert.match((await discoverVaults(f.root)).notice, /unavailable/);
  await writeFile(registry, JSON.stringify({ vaults: {
    ['a'.repeat(16)]: { path: f.vault }, ['b'.repeat(16)]: { path: join(f.root, 'Absent') },
    ['c'.repeat(16)]: { path: f.vault }, ['d'.repeat(16)]: { path: '../not-absolute' },
  } }));
  const result = await discoverVaults(f.root);
  assert.equal(result.vaults.length, 2); assert.equal(result.vaults[0].available, true);
  assert.equal(result.vaults[1].available, false);
  await writeFile(registry, ' '.repeat(1024 * 1024 + 1));
  assert.match((await discoverVaults(f.root)).notice, /unavailable/);
});

test('reject unsafe output paths, symlink subfolders, configuration corruption and loose private modes', async t => {
  const f = await fixture(t);
  for (const value of ['../outside', '/absolute', '.obsidian', 'x//y', 'x/../y', 'x\\y']) assert.throws(() => subfolder(value));
  await symlink(f.root, join(f.vault, 'escape'));
  await assert.rejects(inspectDestination(f.vault, 'escape'), /not links/);
  await assert.rejects(writeSample({ root: f.vault, subfolder: 'escape' }), /not links/);
  const first = await connectDestination(null, { root: f.vault, kind: 'markdown' });
  await saveSettings(f.privateRoot, first);
  const config = join(f.privateRoot, 'obsidian.json'); await writeFile(config, '{bad');
  await assert.rejects(loadSettings(f.privateRoot));
  await assert.rejects(wizard(f, [])); assert.equal(await readFile(config, 'utf8'), '{bad');
  await writeFile(config, JSON.stringify(first)); await chmod(config, 0o644);
  await assert.rejects(loadSettings(f.privateRoot), /Unsafe/);
  await chmod(config, 0o600); await rm(config); await symlink(join(f.privateRoot, 'bridge.json'), config);
  await assert.rejects(loadSettings(f.privateRoot));
  await chmod(f.privateRoot, 0o755); await assert.rejects(saveSettings(f.privateRoot, first), /private/);
});

test('Mac discovery checks bundle identity without launching the app; custom location survives repeat setup', async t => {
  const f = await fixture(t);
  const app = join(f.root, 'Custom Obsidian.app'); await mkdir(app);
  const calls = [];
  const run = async (command, args) => {
    calls.push({ command, args });
    return { stdout: command.endsWith('plutil') ? 'md.obsidian\n' : app + '\n' };
  };
  assert.equal(await detectApp({ platform: 'darwin', run, home: f.root }), app);
  assert.equal(calls.some(c => c.command === '/usr/bin/open'), false);
  assert.equal(await detectApp({ platform: 'darwin', run, preferredPath: app }), app);
  await assert.rejects(validateApp(app, async () => ({ stdout: 'other.application' })), /Choose the Obsidian/);
  let preferred;
  await wizard(f, ['4', '0'], { pickApp: async () => app });
  const { settings } = await wizard(f, ['0'], { detect: async options => { preferred = options.preferredPath; return app; } });
  assert.equal(preferred, app); assert.equal(settings.appPath, app);
});

test('refresh can detect a newly installed app without switching destinations', async t => {
  const f = await fixture(t);
  const connected = await connectDestination(null, { root: f.vault, kind: 'markdown' });
  await saveSettings(f.privateRoot, connected);
  let count = 0;
  const { settings, output } = await wizard(f, ['9', '0'], {
    detect: async () => ++count === 1 ? null : '/Applications/Obsidian.app',
  });
  assert.match(output, /Obsidian detected/); assert.equal(settings.destination.id, connected.destination.id);
  assert.deepEqual((await loadSettings(f.privateRoot)).destination, connected.destination);
});

test('unwritable folders cannot be connected or receive a sample', async t => {
  if (process.getuid() === 0) return t.skip('root bypasses filesystem access checks');
  const f = await fixture(t);
  await chmod(f.vault, 0o500);
  try {
    await assert.rejects(connectDestination(null, { root: f.vault, kind: 'markdown' }));
    await assert.rejects(writeSample({ root: f.vault, subfolder: '' }));
  } finally { await chmod(f.vault, 0o700); }
  assert.deepEqual(await readdir(f.vault), []);
});

test('command rejects unattended invocation before changing private configuration', async t => {
  const f = await fixture(t);
  const result = spawnSync(process.execPath, [fileURLToPath(new URL('../obsidian-setup.mjs', import.meta.url))], {
    cwd: f.root, encoding: 'utf8', timeout: 5000,
  });
  assert.equal(result.status, 1); assert.match(result.stderr, /interactive terminal/);
  assert.deepEqual(await readdir(f.privateRoot), ['bridge.json']);
});

test('missing pairing folder has a setup instruction and is not created implicitly', async t => {
  const f = await fixture(t);
  const absent = join(f.root, 'No pairing');
  await assert.rejects(runSetup({ privateRoot: absent, ask: async () => '0' }), /Run bridge pairing setup first/);
  await assert.rejects(stat(absent), { code: 'ENOENT' });
});

test('persisted destination replaced by a symlink cannot redirect a sample write', async t => {
  const f = await fixture(t);
  const settings = await connectDestination(null, { root: f.vault, kind: 'markdown' });
  const elsewhere = join(f.root, 'Elsewhere'); await mkdir(elsewhere);
  await rename(f.vault, join(f.root, 'Original vault'));
  await symlink(elsewhere, f.vault);
  await assert.rejects(writeSample(settings.destination), /Destination path changed/);
  assert.deepEqual(await readdir(elsewhere), []);
  // A user can still explicitly reconnect an alias; its canonical target is saved.
  const repaired = await connectDestination(settings, { root: f.vault, kind: 'markdown' });
  assert.equal(repaired.destination.root, elsewhere);
  assert.notEqual(repaired.destination.id, settings.destination.id);
});

test('terminal output escapes controls in discovered names and OS errors', async t => {
  const f = await fixture(t);
  const escape = '\x1b]52;c;clipboard-payload\x07';
  const { output } = await wizard(f, ['1', '1', '', 'n', '3', '', '0'], {
    discover: async () => ({ vaults: [{ name: escape + '\u202e', path: f.vault, available: true }], notice: null }),
    pickFolder: async () => { throw new Error(escape); },
  });
  assert.equal(output.includes('\x1b'), false); assert.equal(output.includes('\x07'), false);
  assert.equal(output.includes('\u202e'), false); assert.match(output, /\\u001b/);
  for (const value of ['unsafe\x1b', 'unsafe\u009b', 'unsafe\u202e']) assert.throws(() => subfolder(value));
});

test('settings require an exact schema and a private directory on reads as well as writes', async t => {
  const f = await fixture(t);
  const settings = await connectDestination(null, { root: f.vault, kind: 'markdown' });
  assert.throws(() => validateSettings({ ...settings, unexpected: 'unintended private data' }));
  assert.throws(() => validateSettings({ ...settings, destination: { ...settings.destination, unexpected: true } }));
  assert.throws(() => validateSettings({ ...settings, destination: { ...settings.destination, root: '/' + 'x'.repeat(5000) } }));
  await saveSettings(f.privateRoot, settings);
  await chmod(f.privateRoot, 0o755);
  await assert.rejects(loadSettings(f.privateRoot), /private/);
  await chmod(f.privateRoot, 0o700);
  const alias = join(f.root, 'Private alias'); await symlink(f.privateRoot, alias);
  await assert.rejects(loadSettings(alias), /private/);
  const config = join(f.privateRoot, 'obsidian.json');
  await link(config, join(f.root, 'Hardlink to settings'));
  await assert.rejects(loadSettings(f.privateRoot), /Unsafe/);
});

test('FIFO config and discovery metadata are rejected without blocking setup', async t => {
  if (process.platform === 'win32') return t.skip('POSIX FIFO test');
  const f = await fixture(t);
  const registry = join(f.root, 'Library/Application Support/obsidian');
  await mkdir(registry, { recursive: true });
  const pipes = [join(f.privateRoot, 'obsidian.json'), join(registry, 'obsidian.json')];
  for (const path of pipes) {
    const made = spawnSync('/usr/bin/mkfifo', ['-m', '600', path], { encoding: 'utf8' });
    assert.equal(made.status, 0, made.stderr);
  }
  // A child timeout makes this regression safe even if a blocking open returns.
  const result = spawnSync(process.execPath, ['--input-type=module', '-e',
    'import { loadSettings, discoverVaults } from "./obsidian.mjs"; let rejected = false; try { await loadSettings(process.argv[1]); } catch { rejected = true; } const discovery = await discoverVaults(process.argv[2]); console.log(JSON.stringify({rejected, notice: discovery.notice}));',
    f.privateRoot, f.root], { cwd: fileURLToPath(new URL('..', import.meta.url)), encoding: 'utf8', timeout: 3000 });
  assert.equal(result.error, undefined); assert.equal(result.status, 0, result.stderr);
  const output = JSON.parse(result.stdout);
  assert.equal(output.rejected, true); assert.match(output.notice, /unavailable/);
});
