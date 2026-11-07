import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { mkdirSync, mkdtempSync, writeFileSync, rmSync, copyFileSync, chmodSync } from 'node:fs';
import { join } from 'node:path';
import { sandboxProfile } from './security.mjs';

export function validateInk(body) {
  const invalid = () => { throw Object.assign(new Error('Expected bounded pen strokes and canvas dimensions only'), { status: 400 }); };
  if (!body || Object.keys(body).sort().join(',') !== 'height,strokes,width' ||
      !Number.isInteger(body.width) || !Number.isInteger(body.height) ||
      body.width < 64 || body.width > 2048 || body.height < 64 || body.height > 2048 ||
      !Array.isArray(body.strokes) || !body.strokes.length || body.strokes.length > 1000) invalid();
  let count = 0;
  for (const stroke of body.strokes) {
    if (!Array.isArray(stroke) || !stroke.length) invalid();
    count += stroke.length;
    if (count > 20000) invalid();
    for (const point of stroke) {
      if (!Array.isArray(point) || point.length !== 2 || !point.every(Number.isFinite) ||
          point[0] < 0 || point[0] >= body.width || point[1] < 0 || point[1] >= body.height) invalid();
    }
  }
}

export class LocalRecognizer {
  constructor(binary) { this.binary = binary; this.job = null; this.child = null; this.expiry = null; }
  state() { return this.job || { status: 'idle' }; }
  start(ink) {
    validateInk(ink);
    if (this.child) throw Object.assign(new Error('Recognition is already running'), { status: 409 });
    clearTimeout(this.expiry);
    const job = this.job = { jobId: randomUUID(), status: 'running' };
    const runtime = mkdtempSync('/private/tmp/kobo-ocr-');
    mkdirSync(join(runtime, 'tmp'), { mode: 0o700 });
    const worker=join(runtime,'recognizer');
    copyFileSync(this.binary,worker);chmodSync(worker,0o700);
    const profile = join(runtime, 'ocr.sb');
    writeFileSync(profile, sandboxProfile({ codexHome: runtime, workspace: runtime,
      privateTmp: runtime, nativeBinary: worker, proxyPort: null }), { mode: 0o600 });
    let output = '', done = false;
    const child = this.child = spawn('/usr/bin/sandbox-exec', ['-f', profile, worker], {
      cwd: runtime, env: { PATH: '/usr/bin:/bin', TMPDIR: join(runtime, 'tmp') }, stdio: ['pipe','pipe','pipe'],
    });
    const finish = code => {
      if (done) return; done = true;
      clearTimeout(timeout); this.child = null;
      try {
        const result = JSON.parse(output);
        if (code !== 0 || typeof result.text !== 'string' || result.text.length > 16000 || !Number.isFinite(result.confidence)) throw new Error();
        Object.assign(job, { status: 'complete', text: result.text, confidence: result.confidence });
      } catch { Object.assign(job, { status: 'failed', error: 'Local handwriting recognition failed. Try clearer writing.' }); }
      rmSync(runtime, { recursive: true, force: true });
      this.expiry = setTimeout(() => { if (this.job === job) this.job = null; }, 5*60*1000); this.expiry.unref();
    };
    const timeout = setTimeout(() => { child.kill('SIGKILL'); finish(1); }, 30000);
    child.stdout.setEncoding('utf8');
    child.stdout.on('data', chunk => { output += chunk; if (Buffer.byteLength(output) > 100000) { child.kill('SIGKILL'); finish(1); } });
    child.stderr.on('data', () => {});
    child.stdin.on('error', () => {});
    child.once('error', () => finish(1)); child.once('exit', finish);
    child.stdin.end(JSON.stringify(ink));
    return { ...job };
  }
  close() { clearTimeout(this.expiry); if (this.child) this.child.kill('SIGKILL'); this.job = null; }
}
