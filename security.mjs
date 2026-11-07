import { isIP } from 'node:net';
import { createHash, timingSafeEqual } from 'node:crypto';
import { lstatSync, realpathSync, existsSync, openSync, readSync, closeSync } from 'node:fs';
import { isAbsolute, join, dirname } from 'node:path';
import { createRequire } from 'node:module';

export const UPSTREAM_HOSTS = new Set(['chatgpt.com', 'auth.openai.com', 'api.openai.com']);
export function publicAddress(address) {
  if (isIP(address) === 4) {
    const [a,b,c] = address.split('.').map(Number);
    return !(a === 0 || a === 10 || a === 127 || a >= 224 ||
      (a === 100 && b >= 64 && b <= 127) || (a === 169 && b === 254) ||
      (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) ||
      (a === 192 && b === 0) || (a === 192 && b === 0 && c === 2) ||
      (a === 198 && (b === 18 || b === 19 || (b === 51 && c === 100))) ||
      (a === 203 && b === 0 && c === 113));
  }
  if (isIP(address) === 6) {
    // Only global unicast; excludes loopback, ULA, link-local, IPv4-mapped,
    // multicast and NAT64. Also exclude documentation and transition ranges.
    const s = address.toLowerCase();
    return /^[23][0-9a-f]{3}:/.test(s) &&
      !/^2001:(0*:|db8:|0?2:|1[0-9a-f]:|2[0-9a-f]:)/.test(s) && !s.startsWith('2002:');
  }
  return false;
}
export function resolveNativeBinary(candidate) {
  if (!candidate) candidate = (process.env.PATH || '').split(':').map(p => join(p, 'codex')).find(existsSync);
  if (!candidate) throw new Error('Codex executable not found');
  let path = realpathSync(candidate);
  if (path.endsWith('.js')) {
    const pkg = createRequire(path).resolve('@openai/codex-darwin-arm64/package.json');
    path = realpathSync(join(dirname(pkg), 'vendor/aarch64-apple-darwin/bin/codex'));
  }
  const fd = openSync(path, 'r'), header = Buffer.alloc(4);
  try { readSync(fd, header, 0, 4, 0); } finally { closeSync(fd); }
  if (!['cffaedfe','feedfacf','cefaedfe','feedface','cafebabe','bebafeca'].includes(header.toString('hex'))) throw new Error('A native macOS Codex executable is required');
  return path;
}
export function equalSecret(actual, expected) {
  if (typeof actual !== 'string') return false;
  const hash = s => createHash('sha256').update(s).digest();
  return timingSafeEqual(hash(actual), hash(expected));
}
export function assertSafePrompt(text, sensitiveValues = []) {
  const credential = /-----BEGIN (?:[A-Z ]+ )?PRIVATE KEY-----|\bsk-(?:proj-|svcacct-)?[a-zA-Z0-9_-]{16,}|\b(?:gh[pousr]_[a-zA-Z0-9_]{20,}|github_pat_[a-zA-Z0-9_]{20,}|(?:AKIA|ASIA)[A-Z0-9]{16})\b|\beyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9_-]{10,}\b/;
  const assignment = /\b(?:authorization\s*:\s*bearer|(?:api[_-]?key|secret|password|access[_-]?token|refresh[_-]?token)\s*[:=])\s*["']?[a-zA-Z0-9_+\/=.-]{8,}/i;
  const localInfo = /\b[\w.-]+\.local\b|\/Users\/[^\s/]+|\/home\/[^\s/]+|\b(?:f[cd][0-9a-f]{2}|fe80):[0-9a-f:]+|::1\b/i;
  const privateIPs = (text.match(/\b(?:\d{1,3}\.){3}\d{1,3}\b/g) || []).some(ip => isIP(ip) && !publicAddress(ip));
  if (credential.test(text) || assignment.test(text) || localInfo.test(text) || privateIPs ||
      sensitiveValues.some(value => value && text.includes(value))) {
    throw Object.assign(new Error('Prompt blocked: remove credentials, private paths, or private-network information before sending.'), { status: 400 });
  }
}
export function privateFile(path) {
  const s = lstatSync(path);
  if (!s.isFile() || s.isSymbolicLink() || (s.mode & 0o077) || s.uid !== process.getuid()) {
    throw new Error('Private files must be owned by this user, regular files, and mode 0600');
  }
  return path;
}
export function privateDirectory(path) {
  const s = lstatSync(path);
  if (!s.isDirectory() || s.isSymbolicLink() || (s.mode & 0o077) || s.uid !== process.getuid()) {
    throw new Error('Private directories must be owned by this user and mode 0700');
  }
  return realpathSync(path);
}
export function childEnvironment({ codexHome, privateTmp, proxyUrl }) {
  return {
    PATH: '/usr/bin:/bin', CODEX_HOME: codexHome, TMPDIR: privateTmp,
    HTTPS_PROXY: proxyUrl, HTTP_PROXY: proxyUrl, ALL_PROXY: proxyUrl,
    https_proxy: proxyUrl, http_proxy: proxyUrl, all_proxy: proxyUrl,
    NO_PROXY: '', no_proxy: '', RUST_LOG: 'off',
    SSL_CERT_FILE: '/private/etc/ssl/cert.pem',
  };
}
function quoted(path) {
  if (!isAbsolute(path) || /["\\\n\r]/.test(path)) throw new Error('Unsupported sandbox path');
  return JSON.stringify(path);
}
export function sandboxProfile({ codexHome, workspace, privateTmp, nativeBinary, proxyPort }) {
  if (proxyPort !== null && (!Number.isInteger(proxyPort) || proxyPort < 1 || proxyPort > 65535)) throw new Error('Invalid proxy port');
  const literal = p => `(literal ${quoted(p)})`;
  const subpath = p => `(subpath ${quoted(p)})`;
  return `(version 1)
(allow default)
(deny file-read* file-write* network* process-exec process-fork process-info*)
(allow file-read-metadata)
(allow process-info* (target self))
(allow file-read*
 ${literal('/')}
 ${subpath('/System')} ${subpath('/usr/lib')} ${subpath('/usr/share')}
 ${subpath('/private/etc/ssl')} ${subpath('/private/etc/zoneinfo')}
 ${literal('/private/etc/localtime')} ${literal('/dev/random')} ${literal('/dev/urandom')}
 ${literal('/dev/zero')} ${literal('/dev/null')}
 ${literal(nativeBinary)} ${subpath(codexHome)} ${subpath(workspace)} ${subpath(privateTmp)})
(allow file-write* ${subpath(codexHome)} ${subpath(privateTmp)} ${literal('/dev/null')})
(allow process-exec ${literal(nativeBinary)})
${proxyPort === null ? '' : `(allow network-outbound (remote tcp "localhost:${proxyPort}"))`}
`;
}
export function validateBind(config) {
  if (isIP(config.host) !== 4 || config.host === '0.0.0.0' || publicAddress(config.host) ||
      !(config.host.startsWith('192.168.') || config.host.startsWith('10.') ||
        (config.host.startsWith('172.') && +config.host.split('.')[1] >= 16 && +config.host.split('.')[1] <= 31) ||
        config.host === '127.0.0.1')) throw new Error('Bind only a specific RFC1918 LAN IPv4 address or loopback');
  if (!Number.isInteger(config.port) || config.port < 1024 || config.port > 65535) throw new Error('Invalid bridge port');
  if (!/^[0-9a-f]{64}$/.test(config.token)) throw new Error('Invalid device token');
}
