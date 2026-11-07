import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn, execFileSync } from 'node:child_process';
import net from 'node:net';
import https from 'node:https';
import assert from 'node:assert/strict';

const modules = resolve(process.argv[2]), configPath = resolve('.private/connection.json');
const config = JSON.parse(readFileSync(configPath));
const here = fileURLToPath(new URL('.', import.meta.url));
const captured = [], sockets = new Set();
const relay = net.createServer(client => {
  const upstream = net.connect(config.port, config.host);
  for (const socket of [client,upstream]) {
    sockets.add(socket); socket.on('close', () => sockets.delete(socket)); socket.on('error', () => {});
    socket.on('data', data => captured.push(data));
  }
  client.on('close', () => upstream.destroy()); upstream.on('close', () => client.destroy());
  client.pipe(upstream); upstream.pipe(client);
});
await new Promise(r => relay.listen(0, '127.0.0.1', r));
async function lua(port, mode) {
  return new Promise((fulfill, reject) => {
    const child = spawn('luajit', [join(here,'live-lua.lua'),modules,configPath,join(here,'../kobocodex.koplugin/transport.lua'),String(port),...(mode?[mode]:[]),...(mode==='recognize'?[resolve(process.argv[3])]:[])], { stdio:['ignore','pipe','pipe'] });
    let output='',error=''; child.stdout.on('data',b=>output+=b); child.stderr.on('data',b=>error+=b);
    const timer=setTimeout(()=>{child.kill();reject(new Error('Live Lua test timed out'));},20000);
    child.on('exit',code=>{clearTimeout(timer);code===0?fulfill(output.trim()):reject(new Error(`Lua transport failed: ${error}`));});
  });
}
const temporary = mkdtempSync('/private/tmp/kobo-fake-cert-');
let fake;
try {
  console.log(await lua(relay.address().port));
  if(process.argv[3])console.log(await lua(relay.address().port,'recognize'));
  const wire = Buffer.concat(captured);
  for(const marker of [config.token,'KOBO_SYNTHETIC_WIRE_CANARY_948213','Authorization: Bearer','GET /v1/state','POST /v1/prompt','POST /v1/recognize','"strokes"']) {
    assert.equal(wire.includes(Buffer.from(marker)), false, 'Plaintext application data found in TLS wire capture');
  }
  execFileSync('openssl',['req','-x509','-newkey','rsa:2048','-nodes','-days','1','-keyout',join(temporary,'key'),'-out',join(temporary,'cert'),'-subj','/CN=synthetic-wrong-server'],{stdio:'ignore'});
  let requests = 0, applicationBytes = 0;
  fake = https.createServer({key:readFileSync(join(temporary,'key')),cert:readFileSync(join(temporary,'cert')),minVersion:'TLSv1.2'},(_,res)=>{requests++;res.end('{}');});
  fake.on('secureConnection',s=>s.on('data',b=>applicationBytes+=b.length));
  fake.on('tlsClientError',()=>{});
  await new Promise(r=>fake.listen(0,'127.0.0.1',r));
  console.log(await lua(fake.address().port,'wrong-server'));
  assert.equal(requests,0); assert.equal(applicationBytes,0);
  const plaintext = await new Promise(resolve=>{
    const socket=net.connect(config.port,config.host);let data='';
    socket.setTimeout(1000,()=>socket.destroy()); socket.on('connect',()=>socket.write('GET /v1/state HTTP/1.1\r\nHost: synthetic-audit\r\nConnection: close\r\n\r\n'));
    socket.on('data',b=>data+=b);socket.on('error',()=>{});socket.on('close',()=>resolve(data));
  });
  assert.equal(plaintext.includes('messages'),false);assert.equal(plaintext.includes(config.token),false);
  console.log(JSON.stringify({wireBytes:wire.length,plaintextTokenOrPromptFound:false,wrongServerReceivedApplicationBytes:applicationBytes,plaintextHTTPExposedState:false}));
} finally {
  for (const socket of sockets) socket.destroy(); relay.close(); if(fake)fake.close();
  rmSync(temporary,{recursive:true,force:true});
}
