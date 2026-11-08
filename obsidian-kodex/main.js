'use strict';
const { Plugin, PluginSettingTab, Setting, Notice, Modal, FuzzySuggestModal, FileSystemAdapter } = require('obsidian');
const { homedir } = require('node:os');
const path = require('node:path');
const { randomBytes } = require('node:crypto');
const { Connection } = require('./core.cjs');

class PairModal extends Modal {
  constructor(plugin) { super(plugin.app); this.plugin = plugin; }
  onOpen() {
    let pairingFile = '', folder = this.plugin.connection.state?.folder || 'Reading/KOdex';
    this.contentEl.createEl('h2', { text: 'Connect this vault to KOdex' });
    this.contentEl.createEl('p', { text: 'On the Mac, run npm run pair:obsidian, then restart the bridge. Paste the Application Support pairing path below. For an older installation, run npm run pair:obsidian -- migrate. Documents access is not required.' });
    this.contentEl.createEl('p', { text: 'Notes imported here may be accessible to vault plugins, sync services, and backups. Questions continue through the Mac bridge even when Obsidian is closed.' });
    new Setting(this.contentEl).setName('Private pairing file').addText(t => t.setPlaceholder('…/Library/Application Support/KOdex/companion-pairings/…/obsidian-companion.json').onChange(v => { pairingFile = v.trim(); }));
    new Setting(this.contentEl).setName('Notes folder').addText(t => t.setValue(folder).onChange(v => { folder = v.trim(); }));
    new Setting(this.contentEl).addButton(b => b.setButtonText('Connect this vault').setCta().onClick(async () => {
      b.setDisabled(true);
      try { await this.plugin.connection.connect(pairingFile, folder); this.close(); this.plugin.updateStatus('Connected'); new Notice('KOdex connected. Use Send connection sample to test delivery.'); }
      catch (e) { new Notice(e.message); b.setDisabled(false); }
    }));
  }
  onClose() { this.contentEl.empty(); }
}
class ArchivePicker extends FuzzySuggestModal {
  constructor(plugin, items) { super(plugin.app); this.plugin = plugin; this.items = items; this.setPlaceholder('Choose a saved conversation to import'); }
  getItems() { return this.items; }
  getItemText(item) { return `${item.title} — ${item.createdAt.slice(0, 10)} (${item.messageCount} messages)`; }
  onChooseItem(item) {
    const modal = new Modal(this.app);
    modal.onOpen = () => {
      modal.contentEl.createEl('h2', { text: 'Import saved conversation?' });
      modal.contentEl.createEl('p', { text: item.title });
      modal.contentEl.createEl('p', { text: `Save ${item.messageCount} messages, including submitted passage context, to ${this.plugin.connection.state.folder}. Existing notes will be preserved.` });
      new Setting(modal.contentEl).addButton(b => b.setButtonText('Import conversation').setCta().onClick(async () => {
        b.setDisabled(true);
        try { await this.plugin.connection.call('/v1/export', { documentId: item.documentId, archiveId: item.archiveId }); modal.close(); await this.plugin.sync(true); }
        catch (e) { new Notice(e.message); b.setDisabled(false); }
      }));
    };
    modal.open();
  }
}
class CompanionSettings extends PluginSettingTab {
  constructor(plugin) { super(plugin.app, plugin); this.plugin = plugin; }
  display() {
    const el = this.containerEl; el.empty();
    const connection = this.plugin.connection;
    el.createEl('h2', { text: 'KOdex Companion' });
    el.createEl('p', { text: 'The Mac bridge handles Codex questions and keeps exports queued while Obsidian is closed. This plugin imports notes into this vault only.' });
    if (!connection) { el.createEl('p', { text: this.plugin.startupError || 'The companion currently supports macOS desktop only.' }); return; }
    el.createEl('p', { text: connection.state?.enabled ? `Connected destination: ${connection.state.destinationId}` : 'This vault is not connected.' });
    new Setting(el).setName('Pairing').addButton(b => b.setButtonText('Connect this vault').onClick(() => new PairModal(this.plugin).open()));
    if (!connection.state?.enabled) return;
    new Setting(el).setName('Notes folder').setDesc('New exports use this folder. Imports already started retain their original location.')
      .addText(t => t.setValue(connection.state.folder).onChange(v => { this.pendingFolder = v.trim(); }))
      .addButton(b => b.setButtonText('Save folder').onClick(async () => { try { await connection.setFolder(this.pendingFolder ?? connection.state.folder); new Notice('KOdex folder saved'); } catch (e) { new Notice(e.message); } }));
    new Setting(el).setName('Delivery').addButton(b => b.setButtonText('Receive queued notes').onClick(() => this.plugin.sync(true)))
      .addButton(b => b.setButtonText('Send connection sample').onClick(() => this.plugin.sample()));
    new Setting(el).setName('Saved conversations').addButton(b => b.setButtonText('Choose conversation to import').onClick(() => this.plugin.archives()));
    new Setting(el).setName('Disconnect').setDesc('Pauses receipt in this vault and retains notes. Revoke the pairing on the Mac to disable the bridge credential.')
      .addButton(b => b.setButtonText('Disconnect').onClick(async () => { try { await connection.disconnect(); this.plugin.updateStatus('Disconnected'); this.display(); } catch (e) { new Notice(e.message); } }));
  }
}
module.exports = class KOdexCompanion extends Plugin {
  async onload() {
    this.status = this.addStatusBarItem();
    this.addSettingTab(new CompanionSettings(this));
    if (process.platform !== 'darwin' || !(this.app.vault.adapter instanceof FileSystemAdapter)) { this.updateStatus('Mac desktop required'); return; }
    this.connection = new Connection({ vault: this.app.vault, vaultRoot: this.app.vault.adapter.getBasePath(),
      localRoot: path.join(homedir(), 'Library/Application Support/KOdex-Obsidian') });
    try { await this.connection.initialize(); }
    catch (e) { this.startupError = e.code === 'PAIRING_LOCATION' ? e.message : 'KOdex local settings could not be loaded. Existing notes and bridge exports were retained.'; this.updateStatus('Local settings need attention'); new Notice(this.startupError); this.connection = null; return; }
    this.addCommand({ id: 'connect', name: 'Connect this vault', callback: () => new PairModal(this).open() });
    this.addCommand({ id: 'receive', name: 'Receive queued notes', callback: () => this.sync(true) });
    this.addCommand({ id: 'sample', name: 'Send connection sample', callback: () => this.sample() });
    this.addCommand({ id: 'archives', name: 'Import a saved conversation', callback: () => this.archives() });
    this.addCommand({ id: 'open-last', name: 'Open last imported note', callback: () => { if (this.lastPath) void this.app.workspace.openLinkText(this.lastPath, '', true); else new Notice('No note has been imported in this session.'); } });
    this.registerInterval(setInterval(() => { void this.sync(false); }, 15000));
    this.app.workspace.onLayoutReady(() => { if (!this.stopped) void this.sync(false); });
    this.updateStatus(this.connection.state?.enabled ? 'Connected' : 'Not connected');
  }
  updateStatus(text) { this.status?.setText(`KOdex: ${text}`); }
  async sync(manual = false) {
    if (!this.connection?.state?.enabled || this.stopped) { if (manual) new Notice('Connect this vault to KOdex first.'); return; }
    try {
      const result = await this.connection.sync();
      if (this.stopped) return;
      if (result.lastPath) this.lastPath = result.lastPath;
      this.updateStatus('Connected');
      if (manual) new Notice(result.imported ? `KOdex imported ${result.imported} note(s).` : 'No queued notes.');
    } catch (e) { if (!this.stopped) { this.updateStatus('Waiting / needs attention'); if (manual) new Notice(e.message); } }
  }
  async sample() {
    try { await this.connection.call('/v1/sample', { requestId: randomBytes(16).toString('hex') }); await this.sync(true); }
    catch (e) { new Notice(e.message); }
  }
  async archives() {
    try {
      const result = await this.connection.call('/v1/archives');
      if (!result.archives.length) { new Notice('No saved conversations. Archive a book chat with New chat on the Kobo first.'); return; }
      new ArchivePicker(this, result.archives).open();
    } catch (e) { new Notice(e.message); }
  }
  onunload() { this.stopped = true; }
};
