import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { spawn } from 'node:child_process';
import { privateFile, privateDirectory, resolveNativeBinary, sandboxProfile, childEnvironment } from './security.mjs';
import { createEgress } from './egress.mjs';
import { overrides } from './bridge.mjs';

process.umask(0o077);
if (process.versions.node.split('.')[0] !== '22' || process.env.NODE_OPTIONS || process.env.SSLKEYLOGFILE) throw new Error('Use the Node 22 sign-in launcher without extra runtime flags');
const root = privateDirectory(resolve('.private'));
const config = JSON.parse(readFileSync(privateFile(join(root, 'bridge.json'))));
const codexHome = privateDirectory(join(root, 'codex-home'));
const executable = resolveNativeBinary(config.codexBinary);
const runtime = mkdtempSync('/private/tmp/kobo-login-');
const workspace = join(runtime, 'workspace'), privateTmp = join(runtime, 'tmp');
mkdirSync(workspace, { mode: 0o700 }); mkdirSync(privateTmp, { mode: 0o700 });
const egress = await createEgress();
const profile = join(runtime, 'login.sb');
writeFileSync(profile, sandboxProfile({ codexHome, workspace, privateTmp, nativeBinary: executable, proxyPort: egress.port }));
const settings = { ...overrides, log_dir: privateTmp, sqlite_home: privateTmp };
const child = spawn('/usr/bin/sandbox-exec', ['-f', profile, executable,
  ...Object.entries(settings).flatMap(([k,v]) => ['-c', `${k}=${JSON.stringify(v)}`]), 'login', '--device-auth'],
{ cwd: workspace, env: childEnvironment({ codexHome, privateTmp, proxyUrl: egress.proxyUrl }), stdio: 'inherit' });
const cleanup = () => { egress.close(); rmSync(runtime, { recursive: true, force: true }); };
child.on('error', () => { cleanup(); process.exitCode = 1; });
child.on('exit', code => { cleanup(); process.exitCode = code || 0; });
process.on('SIGINT', () => child.kill('SIGTERM'));
process.on('SIGTERM', () => child.kill('SIGTERM'));
