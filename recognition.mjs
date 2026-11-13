import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import * as fs from 'node:fs/promises';
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
  constructor(binary, { filesystem = fs, spawnWorker = spawn } = {}) {
    this.binary = binary; this.fs = filesystem; this.spawnWorker = spawnWorker;
    this.job = null; this.child = null; this.expiry = null;
    this.busy = false; this.closed = false; this.task = null;
  }
  state() { return this.job || { status: 'idle' }; }
  start(ink) {
    validateInk(ink);
    if (this.closed) throw Object.assign(new Error('Local recognizer is closed'), { status: 503 });
    if (this.busy) throw Object.assign(new Error('Recognition is already running'), { status: 409 });
    clearTimeout(this.expiry);
    // Reserve before the first await, including asynchronous setup and cleanup.
    this.busy = true;
    const job = this.job = { jobId: randomUUID(), status: 'running' };
    this.task = this.run(job, JSON.stringify(ink));
    return { ...job };
  }
  async run(job, input) {
    let runtime, result;
    try {
      runtime = await this.fs.mkdtemp('/private/tmp/kobo-ocr-');
      if (this.closed) return;
      await this.fs.mkdir(join(runtime, 'tmp'), { mode: 0o700 });
      const worker = join(runtime, 'recognizer');
      await this.fs.copyFile(this.binary, worker);
      await this.fs.chmod(worker, 0o700);
      const profile = join(runtime, 'ocr.sb');
      await this.fs.writeFile(profile, sandboxProfile({ codexHome: runtime, workspace: runtime,
        privateTmp: runtime, nativeBinary: worker, proxyPort: null }), { mode: 0o600 });
      if (this.closed) return;
      const child = this.child = this.spawnWorker('/usr/bin/sandbox-exec', ['-f', profile, worker], {
        cwd: runtime, env: { PATH: '/usr/bin:/bin', TMPDIR: join(runtime, 'tmp') }, stdio: ['pipe','pipe','pipe'],
      });
      result = await new Promise((resolve, reject) => {
        let output = '', failed = false;
        const abort = () => { failed = true; child.kill('SIGKILL'); };
        const timeout = setTimeout(abort, 30000);
        child.stdout.setEncoding('utf8');
        child.stdout.on('data', chunk => {
          if (failed) return;
          if (Buffer.byteLength(output) + Buffer.byteLength(chunk) > 100000) { abort(); return; }
          output += chunk;
        });
        child.stderr.on('data', () => {});
        child.stdin.on('error', () => {});
        child.once('error', () => { clearTimeout(timeout); reject(new Error('Worker failed')); });
        // Wait for stdio to close before parsing or removing the worker directory.
        child.once('close', code => {
          clearTimeout(timeout);
          try {
            const value = JSON.parse(output);
            if (failed || code !== 0 || typeof value.text !== 'string' || value.text.length > 16000 ||
                !Number.isFinite(value.confidence)) throw new Error();
            resolve(value);
          } catch { reject(new Error('Recognition failed')); }
        });
        child.stdin.end(input);
      });
    } catch {
      result = null;
    } finally {
      this.child = null;
      try { if (runtime) await this.fs.rm(runtime, { recursive: true, force: true }); }
      catch { result = null; }
      this.busy = false;
      if (!this.closed && this.job === job) {
        Object.assign(job, result ? { status: 'complete', text: result.text, confidence: result.confidence } :
          { status: 'failed', error: 'Local handwriting recognition failed. Try clearer writing.' });
        this.expiry = setTimeout(() => { if (this.job === job) this.job = null; }, 5*60*1000);
        this.expiry.unref();
      }
    }
  }
  close() {
    this.closed = true;
    clearTimeout(this.expiry);
    if (this.child) this.child.kill('SIGKILL');
    this.job = null;
    return this.task || Promise.resolve();
  }
}
