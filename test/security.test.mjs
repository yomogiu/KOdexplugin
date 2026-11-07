import test from 'node:test';
import assert from 'node:assert/strict';
import net from 'node:net';
import { mkdtempSync, writeFileSync, chmodSync, symlinkSync, rmSync } from 'node:fs';
import { createEgress } from '../egress.mjs';
import { publicAddress, childEnvironment, validateBind, privateFile, assertSafePrompt } from '../security.mjs';

test('egress rejects private, loopback, link-local, reserved and mapped addresses', () => {
  for (const ip of ['0.0.0.0','10.0.0.1','100.64.0.1','127.0.0.1','169.254.169.254','172.16.0.1',
    '192.168.0.1','192.0.2.1','198.18.0.1','198.51.100.1','203.0.113.1','224.0.0.1','255.255.255.255',
    '::','::1','2::','fc00::1','fe80::1','ff02::1','::ffff:127.0.0.1','64:ff9b::7f00:1','2001:db8::1','2002:a00:1::']) {
    assert.equal(publicAddress(ip), false, ip);
  }
  for (const ip of ['1.1.1.1','8.8.8.8','172.32.0.1','2606:4700:4700::1111']) assert.equal(publicAddress(ip), true, ip);
});
test('outbound guard rejects credentials and local identifying data without echoing it', () => {
  for (const text of ['sk-proj-'+'a'.repeat(32),'-----BEGIN OPENSSH PRIVATE KEY-----',
    'password=syntheticpassword123','Authorization: Bearer syntheticlongtoken123',
    'My router is 192.168.0.1','http://169.254.169.254/','host.example.local',
    '/Users/private-person/.ssh/id_ed25519','http://[fd00::1234]/','my-bridge-secret']) {
    let error; try { assertSafePrompt(text,['my-bridge-secret']); } catch(e) {error=e;}
    assert(error, 'Sensitive fixture was not blocked');
    assert.equal(error.message.includes(text),false);
  }
  assertSafePrompt('Explain how TLS protects my Kobo conversation.');
});
test('child environment excludes host secrets, custom CAs, key logs, user names and inherited proxies', () => {
  const saved = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = 'SYNTHETIC-CANARY';
  try {
    const env = childEnvironment({ codexHome: '/isolated', privateTmp: '/temporary', proxyUrl: 'http://local-proxy' });
    for (const k of ['OPENAI_API_KEY','AWS_SECRET_ACCESS_KEY','HOME','USER','NODE_OPTIONS','SSH_AUTH_SOCK','SSLKEYLOGFILE','CODEX_CA_CERTIFICATE','NODE_EXTRA_CA_CERTS']) assert.equal(env[k], undefined);
    assert.equal(JSON.stringify(env).includes('SYNTHETIC-CANARY'), false);
    assert.equal(env.HTTPS_PROXY, 'http://local-proxy'); assert.equal(env.NO_PROXY, '');
  } finally { if (saved === undefined) delete process.env.OPENAI_API_KEY; else process.env.OPENAI_API_KEY = saved; }
});
test('listener cannot bind a wildcard or public interface', () => {
  for (const host of ['0.0.0.0','::','8.8.8.8','example.com','169.254.1.2']) assert.throws(() => validateBind({ host, port: 9443, token: 'a'.repeat(64) }));
  for (const host of ['127.0.0.1','192.168.50.10','10.0.0.5','172.16.0.1']) validateBind({ host, port: 9443, token: 'a'.repeat(64) });
});
test('private secrets cannot be read through symlinks or loose file permissions', () => {
  const dir = mkdtempSync('/private/tmp/kobo-file-audit-');
  try {
    const file = `${dir}/secret`, link = `${dir}/link`;
    writeFileSync(file, 'SYNTHETIC', { mode: 0o600 }); privateFile(file);
    chmodSync(file, 0o644); assert.throws(() => privateFile(file));
    chmodSync(file, 0o600); symlinkSync(file, link); assert.throws(() => privateFile(link));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});
function raw(port, text) {
  return new Promise((resolve,reject) => {
    const socket = net.connect({ host: '127.0.0.1', port }); let result = '';
    socket.setTimeout(2000, () => { socket.destroy(); reject(new Error('Proxy test timeout')); });
    socket.on('connect', () => socket.write(text)); socket.on('data', b => result += b);
    socket.on('end', () => resolve(result)); socket.on('error', reject);
  });
}
test('proxy refuses unauthenticated, arbitrary-host, plaintext, port and authority attacks', async () => {
  let lookedUp = 0;
  const proxy = await createEgress({ lookup: async () => { lookedUp++; return []; } });
  const url = new URL(proxy.proxyUrl);
  const auth = 'Basic ' + Buffer.from(`${url.username}:${url.password}`).toString('base64');
  try {
    for (const authority of ['evil.invalid:443','127.0.0.1:443','192.168.0.1:80','chatgpt.com:80',
      'chatgpt.com.evil.invalid:443','chatgpt.com.:443','user@chatgpt.com:443']) {
      const response = await raw(proxy.port, `CONNECT ${authority} HTTP/1.1\r\nHost: ${authority}\r\nProxy-Authorization: ${auth}\r\n\r\n`);
      assert.match(response, /^HTTP\/1.1 403/);
    }
    assert.match(await raw(proxy.port, 'CONNECT chatgpt.com:443 HTTP/1.1\r\nHost: chatgpt.com:443\r\n\r\n'), /^HTTP\/1.1 403/);
    assert.match(await raw(proxy.port, `GET http://chatgpt.com/ HTTP/1.1\r\nHost: chatgpt.com\r\nProxy-Authorization: ${auth}\r\nConnection: close\r\n\r\n`), /^HTTP\/1.1 403/);
    assert.equal(lookedUp, 0);
  } finally { proxy.close(); }
});
test('proxy blocks DNS rebinding to LAN and mixed public/private responses', async () => {
  for (const addresses of [['127.0.0.1'],['192.168.0.1'],['::ffff:127.0.0.1'],['1.1.1.1','10.0.0.1']]) {
    let connected = false;
    const proxy = await createEgress({ lookup: async () => addresses.map(address => ({ address, family: net.isIP(address) })), connect: () => { connected = true; throw new Error('Must not connect'); } });
    const url = new URL(proxy.proxyUrl), auth = 'Basic ' + Buffer.from(`${url.username}:${url.password}`).toString('base64');
    try {
      assert.match(await raw(proxy.port, `CONNECT chatgpt.com:443 HTTP/1.1\r\nHost: chatgpt.com:443\r\nProxy-Authorization: ${auth}\r\n\r\n`), /^HTTP\/1.1 403/);
      assert.equal(connected, false);
    } finally { proxy.close(); }
  }
});
