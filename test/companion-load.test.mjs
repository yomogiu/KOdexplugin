import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire, isBuiltin } from 'node:module';
import vm from 'node:vm';
import { buildCompanion } from '../build-companion.mjs';

test('installable main.js loads and initializes without resolving any relative source modules', async t => {
  const root = await mkdtemp(join(tmpdir(), 'kodex-load-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const folder = join(root, 'plugin');
  await buildCompanion(folder);
  assert.deepEqual((await readdir(folder)).sort(), ['LICENSE', 'README.md', 'main.js', 'manifest.json']);
  const source = await readFile(join(folder, 'main.js'), 'utf8');
  const externalRequests = [], nodeRequire = createRequire(import.meta.url);
  class Plugin {
    constructor(app) { this.app = app; this.commands = []; this.intervals = []; }
    addStatusBarItem() { return { setText: text => { this.statusText = text; } }; }
    addSettingTab(tab) { this.settings = tab; }
    addCommand(command) { this.commands.push(command); }
    registerInterval(timer) { this.intervals.push(timer); }
  }
  class FileSystemAdapter {
    getBasePath() { return join(root, 'vault'); }
  }
  class PluginSettingTab { constructor(app, plugin) { this.app = app; this.plugin = plugin; } }
  const api = { Plugin, FileSystemAdapter, PluginSettingTab, Modal: class {}, FuzzySuggestModal: class {}, Setting: class {}, Notice: class {} };
  const output = { exports: {} };
  const context = { module: output, exports: output.exports, Buffer, console, process,
    setInterval: (callback, milliseconds) => ({ callback, milliseconds }),
    require: name => {
      externalRequests.push(name);
      if (name === 'obsidian') return api;
      if (name === 'node:os') return { homedir: () => join(root, 'home') };
      // Model Obsidian's loader: only host APIs and builtins, no plugin-relative
      // module resolution. The previous package failed this boundary.
      if (!isBuiltin(name)) throw new Error('Unbundled dependency: ' + name);
      return nodeRequire(name);
    },
  };
  const unbundled = await readFile(new URL('../obsidian-kodex/main.js', import.meta.url), 'utf8');
  assert.throws(() => vm.runInNewContext(unbundled, { ...context, module: { exports: {} } }), /Unbundled dependency/);
  externalRequests.length = 0;
  vm.runInNewContext(source, context, { filename: 'plugin:kodex-companion' });
  assert.equal(typeof output.exports, 'function');
  assert.equal(externalRequests.some(name => name.startsWith('.')), false);
  await mkdir(join(root, 'vault'));
  const app = { vault: { adapter: new FileSystemAdapter() }, workspace: { onLayoutReady: callback => callback() } };
  const instance = new output.exports(app);
  await instance.onload();
  if (process.platform === 'darwin') {
    assert.equal(instance.commands.length, 5);
    assert.equal(instance.statusText, 'KOdex: Not connected');
    assert.equal(instance.intervals.length, 1);
  }
  instance.onunload();
});
