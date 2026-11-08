import { readFileSync, mkdirSync, mkdtempSync, writeFileSync, rmSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createServer } from 'node:https';
import { AppServer, ChatRegistry, handler } from './bridge.mjs';
import { DiskArchives } from './archives.mjs';
import { privateFile, privateDirectory, sandboxProfile, resolveNativeBinary, validateBind } from './security.mjs';
import { createEgress } from './egress.mjs';
import { hostname } from 'node:os';
import { LocalRecognizer } from './recognition.mjs';
import { startCompanion } from './companion.mjs';

process.umask(0o077);
if (process.versions.node.split('.')[0] !== '22' || process.env.NODE_OPTIONS || process.env.SSLKEYLOGFILE ||
    process.execArgv.some(arg => /--(?:tls-keylog|inspect|require|import|report)/.test(arg))) {
  throw new Error('Use the Node 22 launcher without debugging, preload, key logging, or diagnostic flags');
}
const root = privateDirectory(resolve('.private'));
const config = JSON.parse(readFileSync(privateFile(join(root, 'bridge.json'))));
validateBind(config);
privateFile(join(root, 'server.key')); privateFile(join(root, 'codex-home/config.toml'));
const codexHome = privateDirectory(join(root, 'codex-home'));
const archives = new DiskArchives(join(root, 'chat-archives'));
await archives.prepare();
const executable = resolveNativeBinary(config.codexBinary || process.env.CODEX_BIN);
// A generic temporary workspace avoids putting account names or project paths
// in the model's environment context. It contains no user documents.
const runtime = mkdtempSync('/private/tmp/kobo-codex-');
const workspace = join(runtime, 'workspace'), privateTmp = join(runtime, 'tmp');
mkdirSync(workspace, { mode: 0o700 }); mkdirSync(privateTmp, { mode: 0o700 });
const egress = await createEgress();
const sandboxFile = join(runtime, 'codex.sb');
writeFileSync(sandboxFile, sandboxProfile({ codexHome, workspace, privateTmp, nativeBinary: executable, proxyPort: egress.port }), { mode: 0o600 });
const rpc = new AppServer({ codexHome, workspace, executable, sandboxFile, privateTmp, proxyUrl: egress.proxyUrl });
try { await rpc.initialize(); } catch {
  rpc.close(); egress.close(); rmSync(runtime, { recursive: true, force: true });
  throw new Error('Restricted Codex startup failed. No unrestricted fallback is permitted.');
}
const chat = new ChatRegistry(rpc, workspace, [config.token, config.host, hostname(), root], { archives });
const ocrBinary = join(root, 'ocr-worker');
if (existsSync(ocrBinary)) privateFile(ocrBinary);
const recognizer = existsSync(ocrBinary) ? new LocalRecognizer(ocrBinary) : undefined;
const account = await rpc.request('account/read', { refreshToken: false });
chat.ready = Boolean(account.account);
if (!chat.ready) chat.notice = 'Sign in to the separate Codex profile on the computer, then restart the bridge.';
const server = createServer({ key: readFileSync(join(root, 'server.key')), cert: readFileSync(join(root, 'server.crt')),
  minVersion: 'TLSv1.2', ciphers: 'ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384',
  honorCipherOrder: true, requestTimeout: 10000, headersTimeout: 10000, maxHeaderSize: 8192 }, handler(chat, config.token, { recognizer }));
server.maxConnections = 8;
server.setTimeout(35000, socket => socket.destroy());
server.on('tlsClientError', () => {});
let companion;
try {
  companion = await startCompanion(root, archives);
  companion?.on('error', () => { console.error('Obsidian companion listener stopped; reading chat remains available.'); companion.close(); });
} catch { console.error('Obsidian companion unavailable; reading chat remains available.'); }
let closing = false;
function close() {
  if (closing) return; closing = true;
  rpc.close(); egress.close(); recognizer?.close(); server.closeAllConnections(); server.close();
  companion?.closeAllConnections(); companion?.close();
  rmSync(runtime, { recursive: true, force: true });
}
server.on('error', () => { console.error('Bridge listener failed.'); close(); process.exitCode = 1; });
rpc.on('closed', () => { if (!closing) { console.error('Codex disconnected; stopping bridge.'); close(); } });
server.listen(config.port, config.host, () => console.log(`Restricted Kobo bridge listening over TLS on port ${config.port}.`));
process.on('SIGINT', close); process.on('SIGTERM', close);
