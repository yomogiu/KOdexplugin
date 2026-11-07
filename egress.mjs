import http from 'node:http';
import net from 'node:net';
import dns from 'node:dns/promises';
import { randomBytes } from 'node:crypto';
import { UPSTREAM_HOSTS, publicAddress, equalSecret } from './security.mjs';

// Only an authenticated loopback CONNECT tunnel is permitted. TLS, including
// the OpenAI authentication header and request bodies, stays end-to-end.
// There is no TLS interception, URL/body logging, or upstream proxy chaining.
export async function createEgress({ lookup = dns.lookup, connect = net.connect } = {}) {
  const token = randomBytes(32).toString('hex');
  const authorization = `Basic ${Buffer.from(`kobo:${token}`).toString('base64')}`;
  const sockets = new Set();
  const counts = { allowed: 0, denied: 0, failed: 0 };
  const deny = (socket, status = 403) => {
    counts.denied++;
    socket.end(`HTTP/1.1 ${status} Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n`);
  };
  const server = http.createServer({ requestTimeout: 5000, headersTimeout: 5000, maxHeaderSize: 4096 }, (_, res) => {
    counts.denied++; res.writeHead(403, { 'Content-Length': '0', 'Connection': 'close' }); res.end();
  });
  server.maxConnections = 16;
  server.on('connection', socket => { sockets.add(socket); socket.on('close', () => sockets.delete(socket)); socket.on('error', () => {}); socket.setTimeout(120000, () => socket.destroy()); });
  server.on('clientError', (_, socket) => socket.destroy());
  server.on('connect', async (req, client, head) => {
    if (!equalSecret(req.headers['proxy-authorization'], authorization) ||
        !/^[a-z0-9.-]+:443$/.test(req.url) || req.headers.origin) { deny(client); return; }
    const host = req.url.slice(0, -4);
    if (!UPSTREAM_HOSTS.has(host)) { deny(client); return; }
    try {
      const records = await Promise.race([
        lookup(host, { all: true, verbatim: true }),
        new Promise((_, reject) => { const timer = setTimeout(() => reject(new Error('DNS timeout')), 5000); timer.unref(); }),
      ]);
      if (!records.length || records.some(r => !publicAddress(r.address))) { deny(client); return; }
      if (client.destroyed) return;
      // Connect to the checked IP itself, never resolve the hostname twice.
      const address = records.find(r => r.family === 4) || records[0];
      const upstream = connect({ host: address.address, family: address.family, port: 443 });
      sockets.add(upstream);
      upstream.setTimeout(120000, () => upstream.destroy());
      upstream.on('close', () => { sockets.delete(upstream); client.destroy(); });
      client.on('close', () => upstream.destroy());
      upstream.once('error', () => { counts.failed++; client.destroy(); });
      upstream.once('connect', () => {
        counts.allowed++;
        client.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        if (head.length) upstream.write(head);
        upstream.pipe(client); client.pipe(upstream);
      });
    } catch { counts.failed++; if (!client.destroyed) client.end('HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'); }
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  return {
    port: server.address().port,
    proxyUrl: `http://kobo:${token}@127.0.0.1:${server.address().port}`,
    counts,
    close() { for (const socket of sockets) socket.destroy(); server.close(); },
  };
}
