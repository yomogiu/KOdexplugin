import { mkdirSync, writeFileSync, existsSync, chmodSync, readFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { randomBytes, X509Certificate } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { resolveNativeBinary, validateBind } from './security.mjs';

// No network, shell interpolation, or access to the user's existing Codex auth.
const host = process.argv[2];
if (process.versions.node.split('.')[0] !== '22') throw new Error('Use the tested Node.js 22 runtime for setup');
if (!host || host === '0.0.0.0' || !/^[a-zA-Z0-9][a-zA-Z0-9.-]{0,252}$/.test(host)) {
  throw new Error('Usage: node setup.mjs COMPUTER_LAN_IP_OR_HOSTNAME');
}
const root = resolve('.private');
const codexBinary = resolveNativeBinary(process.env.CODEX_BIN);
validateBind({ host, port: 9443, token: 'a'.repeat(64) });
if (existsSync(root)) throw new Error('.private already exists; refusing to overwrite pairing or credentials.');
mkdirSync(root, { mode: 0o700 });
for (const dir of ['codex-home', 'workspace']) mkdirSync(join(root, dir), { mode: 0o700 });
const key = join(root, 'server.key');
const cert = join(root, 'server.crt');
execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:3072', '-nodes', '-sha256',
  '-days', '365', '-keyout', key, '-out', cert, '-subj', '/CN=Kobo Codex bridge'], { stdio: 'ignore' });
chmodSync(key, 0o600);
const fingerprint = new X509Certificate(readFileSync(cert)).fingerprint256.replaceAll(':', '').toLowerCase();
const token = randomBytes(32).toString('hex');
writeFileSync(join(root, 'bridge.json'), JSON.stringify({ host, port: 9443, token, codexBinary, nodeBinary: process.execPath }, null, 2), { mode: 0o600 });
writeFileSync(join(root, 'connection.json'), JSON.stringify({ host, port: 9443, token, fingerprint }, null, 2), { mode: 0o600 });
writeFileSync(join(root, 'codex-home', 'config.toml'), `# Dedicated chat-only profile. Do not add MCP servers or plugins here.
sandbox_mode = "read-only"
approval_policy = "never"
web_search = "disabled"
project_doc_max_bytes = 0
[features]
shell_tool = false
apps = false
[skills]
include_instructions = false
[skills.bundled]
enabled = false
`, { mode: 0o600 });
console.log('Created .private (contains secrets; do not share it).');
console.log('Sign into the separate profile:');
console.log(`CODEX_HOME="${join(root, 'codex-home')}" codex login`);
console.log('Then: npm start');
console.log('Copy .private/connection.json by USB into plugins/kobocodex.koplugin/.');
