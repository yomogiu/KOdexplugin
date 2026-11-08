import { createInterface } from 'node:readline/promises';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';
import { lstat } from 'node:fs/promises';
import {
  DEFAULT_SUBFOLDER, loadSettings, saveSettings, detectApp, discoverVaults,
  chooseFolder, chooseApp, openObsidian, createReadingFolder,
  connectDestination, inspectDestination, writeSample, terminalText,
} from './obsidian.mjs';

// Inject prompts and OS actions for unattended workflow tests. This setup never
// starts the bridge, changes pairing, installs software, or reads vault notes.
export async function runSetup({ privateRoot, ask, say = console.log, platform = process.platform,
  discover = discoverVaults, detect = detectApp, pickFolder = chooseFolder,
  pickApp = chooseApp, openManager = openObsidian } = {}) {
  const stat = await lstat(privateRoot).catch(e => {
    if (e.code === 'ENOENT') throw new Error('Run bridge pairing setup first; no .private folder was found');
    throw e;
  });
  if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o077)) {
    throw new Error('Run bridge setup first; .private must be a private, user-owned folder');
  }
  let settings = await loadSettings(privateRoot) || { version: 1, state: 'deferred', appPath: null, destination: null };
  const output = say;
  say = value => output(terminalText(value));
  // Re-detect on every run; persisted app availability is not authoritative.
  const appPath = await detect({ preferredPath: settings.appPath });
  settings = { ...settings, appPath };
  let discovery = await discover();
  const yes = async prompt => (await ask(prompt + ' [y/N] ')).trim().toLowerCase() === 'y';
  const folder = async prompt => {
    const path = (await ask(prompt + ' (absolute path, blank for Mac folder picker): ')).trim();
    if (path) return path;
    if (platform !== 'darwin') throw new Error('Enter an absolute folder path on this platform');
    return pickFolder();
  };
  const registrationHelp = async destination => {
    if (destination.kind !== 'obsidian' || destination.registration === 'known') return;
    say(`Folder ready: ${destination.root}\nVault registration is unverified. In Obsidian, choose Manage Vaults → Open folder as vault and select this folder.`);
    if (settings.appPath && await yes('Open the Obsidian vault manager now?')) {
      try { await openManager(settings.appPath); }
      catch { say('Could not open Obsidian. The destination is still configured; open the folder as a vault manually.'); }
    }
  };

  say('KOdex Markdown folder setup\nThis configures a folder only. Direct folder export is not implemented yet. Use the Obsidian companion for archived-conversation imports.');
  say(appPath ? `Obsidian detected: ${appPath}` : 'Obsidian was not detected. Markdown folders work without it.');
  if (discovery.notice) say(discovery.notice);
  while (true) {
    if (settings.destination) {
      const d = settings.destination;
      say(`\n${settings.state === 'connected' ? 'Connected' : 'Disconnected'}: ${d.root}\nExport subfolder: ${d.subfolder || '(vault/folder root)'}\nType: ${d.kind}; vault registration: ${d.registration}`);
      try { await inspectDestination(d.root, d.subfolder, { requireCanonical: true }); say('Destination available (write access checked).'); }
      catch { say('Needs attention: destination missing, not writable, or has an unsafe subfolder. Reconnect its location to repair it.'); }
    }
    say('\n1 Connect existing vault\n2 Create a reading vault folder\n3 Choose a Markdown folder\n4 Locate Obsidian\n5 Get Obsidian\n6 Write a sample note\n7 Disconnect\n8 Open vault manager / registration help\n9 Refresh app and vault discovery\n0 Set up later / Exit');
    const action = (await ask('Choose: ')).trim();
    try {
      if (action === '0') {
        // Exit never disconnects or replaces an existing destination.
        if (!settings.destination) await saveSettings(privateRoot, settings);
        say('Setup closed. Reading and chat remain available.'); return settings;
      }
      if (action === '4') {
        if (platform !== 'darwin') throw new Error('App selection is available on the Mac');
        settings = { ...settings, appPath: await pickApp() };
        await saveSettings(privateRoot, settings);
        say(`Obsidian selected: ${settings.appPath}`); continue;
      }
      if (action === '5') {
        say('Download Obsidian from https://obsidian.md/download and run it once, then return to setup. No software was installed.'); continue;
      }
      if (action === '9') {
        settings = { ...settings, appPath: await detect({ preferredPath: settings.appPath }) };
        discovery = await discover();
        say(settings.appPath ? `Obsidian detected: ${settings.appPath}` : 'Obsidian was not detected. Use Locate Obsidian or choose a Markdown folder.');
        if (discovery.notice) say(discovery.notice);
        // Refresh never silently switches the connected destination.
        continue;
      }
      if (action === '7') {
        if (settings.state !== 'connected') { say('No destination is connected.'); continue; }
        if (await yes('Disconnect this destination? Existing notes will be retained.')) {
          settings = { ...settings, state: 'disconnected' };
          await saveSettings(privateRoot, settings);
          say('Disconnected. Existing notes were retained.');
        }
        continue;
      }
      if (action === '8') {
        if (!settings.destination) throw new Error('Choose a destination first');
        if (settings.destination.registration !== 'known') await registrationHelp(settings.destination);
        else if (settings.appPath && await yes('Open the Obsidian vault manager?')) await openManager(settings.appPath);
        else say('Open Manage Vaults in Obsidian to inspect the selected vault.');
        continue;
      }
      if (action === '6') {
        if (settings.state !== 'connected') throw new Error('Connect a destination first');
        if (await yes('Create a sample Markdown note in the configured destination?')) {
          say(`Sample saved: ${await writeSample(settings.destination)}`);
        }
        continue;
      }
      if (!['1', '2', '3'].includes(action)) { say('Choose one of the listed numbers.'); continue; }
      let root, exportFolder = DEFAULT_SUBFOLDER;
      const kind = action === '3' ? 'markdown' : 'obsidian';
      if (action === '2') {
        const parent = await folder('Parent folder');
        const name = (await ask('New folder name [Reading]: ')).trim() || 'Reading';
        say(`Create a new folder named ${JSON.stringify(name)} inside ${parent}, containing Books/, Conversations/, Attachments/, and Welcome.md.`);
        if (!await yes('Create this folder?')) continue;
        try { root = await createReadingFolder(parent, name); }
        catch (e) {
          if (e.code === 'EEXIST') say('That folder already exists. Choose Connect existing vault or Choose a Markdown folder to connect it.');
          else throw e;
          continue;
        }
        say(`Folder ready: ${root}`);
        exportFolder = '';
      } else if (action === '1') {
        discovery.vaults.forEach((v, i) => say(`${i + 1}: ${v.name} — ${v.path}${v.available ? '' : ' (unavailable)'}`));
        if (discovery.vaults.length) {
          const selection = (await ask('Vault number, or Enter to choose another folder: ')).trim();
          if (selection) {
            if (!/^[1-9][0-9]*$/.test(selection) || !discovery.vaults[Number(selection) - 1]) throw new Error('Choose a listed vault number');
            root = discovery.vaults[Number(selection) - 1].path;
          }
        }
        root ||= await folder('Existing vault folder');
      } else root = await folder('Markdown destination folder');
      const selectedFolder = await ask(`Export subfolder [${exportFolder || '(root)'}]; enter / for root: `);
      exportFolder = selectedFolder.trim() === '/' ? '' : selectedFolder.trim() || exportFolder;
      const candidate = await connectDestination(settings, { root, folder: exportFolder, kind, vaults: discovery.vaults });
      say(`Save destination: ${candidate.destination.root}\nExport subfolder: ${exportFolder || '(root)'}\nVault registration: ${candidate.destination.registration}`);
      say('Notes saved here may be accessible to Obsidian plugins and this folder’s sync or backup services.');
      if (!await yes('Connect this destination?')) { say('Destination settings were not changed. Any new reading folder was retained.'); continue; }
      // Validate with an actual exclusive write only when the user requests it.
      if (await yes('Write a sample note now?')) say(`Sample saved: ${await writeSample(candidate.destination)}`);
      await saveSettings(privateRoot, candidate);
      settings = candidate;
      say('Destination configured. Direct folder export is not implemented yet. Use the Obsidian companion for archived-conversation imports.');
      await registrationHelp(settings.destination);
    } catch (e) {
      say(`Setup action could not finish: ${e.message}\nExisting notes and pairing were retained. You can retry or exit.`);
    }
  }
}

async function main() {
  if (process.versions.node.split('.')[0] !== '22') throw new Error('Use Node 22 for setup');
  if (!process.stdin.isTTY || !process.stdout.isTTY) throw new Error('Run npm run setup:obsidian in an interactive terminal on the Mac');
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try { await runSetup({ privateRoot: resolve('.private'), ask: prompt => rl.question(prompt) }); }
  finally { rl.close(); }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  main().catch(e => { console.error(terminalText(`Obsidian setup stopped: ${e.message}`)); process.exitCode = 1; });
}
