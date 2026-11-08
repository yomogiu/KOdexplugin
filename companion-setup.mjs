import { resolve } from 'node:path';
import { configureCompanion } from './companion.mjs';
import { terminalText } from './obsidian.mjs';

if (process.versions.node.split('.')[0] !== '22') throw new Error('Use Node 22');
try {
  const action = process.argv[2] || 'create';
  const path = await configureCompanion(resolve('.private'), action);
  console.log(terminalText(action === 'revoke' ? 'Companion pairing revoked. Pending exports remain on the Mac.' : action === 'migrate' ?
    `Companion pairing is in Application Support:\n${path}\nFor an upgrade from the earlier bridge, archive working chats and restart the bridge once. Reload the updated Obsidian plugin; it will update its saved path without reading Documents.` :
    `Companion pairing ready. Restart the Mac bridge if its companion service is not running.\nIn the Obsidian plugin, select Connect and enter this private pairing file path:\n${path}\nDo not copy this file into your vault. Credentials are separate from the Kobo pairing.`));
} catch (e) { console.error(terminalText(`Companion setup failed: ${e.code === 'EEXIST' ? 'Pairing already exists. Use rotate to renew it, or revoke to disable it.' : e.message}`)); process.exitCode = 1; }
