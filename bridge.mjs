import { spawn } from 'node:child_process';
import { EventEmitter } from 'node:events';
import { createHash, timingSafeEqual } from 'node:crypto';
import { childEnvironment, assertSafePrompt } from './security.mjs';

export const MAX_TEXT = 16000;
const MAX_OUTPUT = 180000;
export const overrides = Object.freeze({
  'features.shell_tool': false, 'features.apps': false, web_search: 'disabled',
  project_doc_max_bytes: 0, 'skills.include_instructions': false, 'skills.bundled.enabled': false,
  'features.code_mode.enabled': false, 'features.memories': false,
  'analytics.enabled': false, 'otel.exporter': 'none', 'otel.trace_exporter': 'none',
  'otel.metrics_exporter': 'none', 'otel.log_user_prompt': false,
  'history.persistence': 'none', cli_auth_credentials_store: 'file',
  'shell_environment_policy.inherit': 'none',
  'features.browser_use': false, 'features.browser_use_external': false,
  'features.computer_use': false, 'features.code_mode_host': false,
  'features.view_image': false, 'features.workspace_dependencies': false,
  'features.skip_host_skill_discovery': true,
  'features.system_proxy_fallback': false, 'feedback.enabled': false,
  'memories.generate_memories': false, 'memories.use_memories': false,
});

export function authorized(header, token) {
  const digest = s => createHash('sha256').update(s).digest();
  return typeof header === 'string' && timingSafeEqual(digest(header), digest(`Bearer ${token}`));
}

export class AppServer extends EventEmitter {
  constructor({ codexHome, workspace, executable, sandboxFile, privateTmp, proxyUrl }) {
    super(); this.seq = 0; this.pending = new Map(); this.dead = false;
    if (!sandboxFile || !privateTmp || !proxyUrl || !executable || process.platform !== 'darwin') throw new Error('macOS process sandbox and restricted egress are required');
    const env = childEnvironment({ codexHome, privateTmp, proxyUrl });
    const runtimeConfig = { ...overrides, sqlite_home: privateTmp, log_dir: privateTmp };
    this.child = spawn('/usr/bin/sandbox-exec', ['-f', sandboxFile, executable, 'app-server', '--listen', 'stdio://',
      ...Object.entries(runtimeConfig).flatMap(([k,v]) => ['-c', `${k}=${JSON.stringify(v)}`])],
    { cwd: workspace, env, stdio: ['pipe', 'pipe', 'pipe'] });
    // Drain diagnostics without logging private paths, prompts, or tokens.
    this.child.stderr.on('data', () => {});
    this.child.stdin.on('error', () => this.fail());
    this.child.on('error', () => this.fail());
    this.child.on('exit', () => this.fail());
    let buffer = '';
    this.child.stdout.setEncoding('utf8');
    this.child.stdout.on('data', chunk => {
      buffer += chunk;
      if (buffer.length > 4 * 1024 * 1024) { this.close(); return; }
      let nl;
      while ((nl = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, nl); buffer = buffer.slice(nl + 1);
        try { this.receive(JSON.parse(line)); } catch { this.close(); return; }
      }
    });
  }
  fail() {
    if (this.dead) return;
    this.dead = true;
    for (const p of this.pending.values()) { clearTimeout(p.timer); p.reject(new Error('Codex connection closed')); }
    this.pending.clear(); this.emit('closed');
  }
  send(message) {
    if (this.dead) throw new Error('Codex connection closed');
    this.child.stdin.write(JSON.stringify(message) + '\n');
  }
  receive(message) {
    if (message.method && message.id !== undefined) {
      // Never approve or execute a server-initiated tool/approval request.
      this.send({ id: message.id, error: { code: -32601, message: 'This client does not grant permissions or execute tools' } });
      this.emit('blocked'); return;
    }
    if (message.id !== undefined) {
      const p = this.pending.get(message.id);
      if (!p) return;
      clearTimeout(p.timer); this.pending.delete(message.id);
      message.error ? p.reject(new Error('Codex rejected the request')) : p.resolve(message.result);
    } else if (message.method) this.emit('notification', message);
  }
  request(method, params = {}) {
    if (this.dead) return Promise.reject(new Error('Codex connection closed'));
    const id = ++this.seq;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id); reject(new Error('Codex request timed out; restart bridge before retrying'));
        this.close();
      }, 30000);
      this.pending.set(id, { resolve, reject, timer });
      try { this.send({ id, method, params }); }
      catch (e) { this.pending.delete(id); clearTimeout(timer); reject(e); }
    });
  }
  async initialize() {
    await this.request('initialize', { clientInfo: { name: 'kobo_codex_bridge', title: 'Kobo Codex', version: '0.2.0' } });
    this.send({ method: 'initialized', params: {} });
    const mcp = await this.request('mcpServerStatus/list', {});
    if (!Array.isArray(mcp.data) || mcp.data.length !== 0) { this.close(); throw new Error('Dedicated profile must not expose MCP servers'); }
  }
  close() { this.fail(); this.child.kill('SIGTERM'); }
}

export class Chat {
  constructor(rpc, workspace, sensitiveValues = []) {
    this.rpc = rpc; this.workspace = workspace; this.threadId = null;
    this.sensitiveValues = sensitiveValues;
    this.ready = true;
    this.active = false; this.turnId = null; this.messages = []; this.requests = new Map(); this.notice = ''; this.parts = new Map();
    rpc.on('notification', m => this.notify(m));
    rpc.on('blocked', () => { this.notice = 'A tool or approval request was refused. This client cannot grant permissions.'; });
    rpc.on('closed', () => { this.active = false; this.notice = 'Codex disconnected. Restart the bridge.'; });
  }
  snapshot() { return { active: this.active, messages: this.messages, notice: this.notice }; }
  notify({ method, params: p }) {
    if (p?.threadId !== this.threadId) return;
    if (method === 'turn/started') this.turnId = p.turn.id;
    if (method === 'item/agentMessage/delta' && this.active) {
      const key = p.itemId || 'message';
      if (this.parts.size < 100 || this.parts.has(key)) this.parts.set(key, ((this.parts.get(key) || '') + p.delta).slice(0, MAX_OUTPUT));
      this.updateAnswer();
    }
    if (method === 'item/completed' && p.item?.type === 'agentMessage' && this.active) {
      if (this.parts.size < 100 || this.parts.has(p.item.id)) this.parts.set(p.item.id, p.item.text.slice(0, MAX_OUTPUT));
      this.updateAnswer();
    }
    if (method === 'turn/completed') {
      this.active = false; this.turnId = null;
      this.notice = p.turn.status === 'completed' ? '' : `Turn ${p.turn.status}.`;
    }
    if (method === 'error') this.notice = 'Codex reported an error. Check the computer-side login and account limits.';
  }
  updateAnswer() {
    const last = this.messages.at(-1);
    if (last?.role === 'assistant') last.text = [...this.parts.values()].join('\n\n').slice(0, MAX_OUTPUT);
  }
  async prompt(body) {
    if (!body || Object.keys(body).sort().join(',') !== 'requestId,text' ||
        typeof body.text !== 'string' || !body.text.trim() || body.text.length > MAX_TEXT ||
        typeof body.requestId !== 'string' || !/^[a-zA-Z0-9_-]{12,100}$/.test(body.requestId)) {
      throw Object.assign(new Error('Expected text and requestId only; prompt limit is 16000 characters'), { status: 400 });
    }
    assertSafePrompt(body.text, this.sensitiveValues);
    if (!this.ready) throw Object.assign(new Error('Codex sign-in on the computer is required before sending a prompt.'), { status: 503 });
    const previous = this.requests.get(body.requestId);
    if (previous) {
      if (previous.text !== body.text) throw Object.assign(new Error('Request ID already used for different text'), { status: 409 });
      if (previous.error) throw new Error(previous.error);
      return this.snapshot();
    }
    if (this.active) throw Object.assign(new Error('A reply is already in progress'), { status: 409 });
    if (this.rpc.dead) throw new Error('Codex disconnected');
    if (this.requests.size >= 1000) throw new Error('Session limit reached; restart bridge');
    this.active = true; this.requests.set(body.requestId, { text: body.text }); this.notice = ''; this.parts = new Map();
    try {
      if (!this.threadId) {
        const result = await this.rpc.request('thread/start', {
          cwd: this.workspace, sandbox: 'read-only', approvalPolicy: 'never', approvalsReviewer: 'user',
          ephemeral: true, config: overrides,
          baseInstructions: 'You are a text conversation companion. Answer only from the conversation. No tools or local files are available. Do not access files, execute code, or make network requests.',
          developerInstructions: 'Reply in readable plain text for a Kobo display. Do not include local environment details or perform actions.',
        });
        if (result.sandbox?.type !== 'readOnly' || result.sandbox?.networkAccess !== false || result.approvalPolicy !== 'never') {
          this.rpc.close(); throw new Error('Codex did not honor the required sandbox policy');
        }
        this.threadId = result.thread.id;
      }
      this.messages.push({ role: 'user', text: body.text }, { role: 'assistant', text: '' });
      this.messages = this.messages.slice(-12);
      const result = await this.rpc.request('turn/start', { threadId: this.threadId,
        input: [{ type: 'text', text: body.text }], approvalPolicy: 'never', approvalsReviewer: 'user',
        sandboxPolicy: { type: 'readOnly', networkAccess: false } });
      if (this.active) this.turnId = result.turn.id;
      return this.snapshot();
    } catch (e) { this.active = false; this.notice = 'Codex could not start the reply. Check sign-in on the computer.'; this.requests.get(body.requestId).error = this.notice; throw e; }
  }
  async stop() {
    if (this.active && !this.turnId) throw Object.assign(new Error('Turn is starting; retry Stop shortly'), { status: 409 });
    if (this.active) await this.rpc.request('turn/interrupt', { threadId: this.threadId, turnId: this.turnId });
    return this.snapshot();
  }
  async reset() {
    if (this.active) throw Object.assign(new Error('Stop the active turn first'), { status: 409 });
    this.active = true;
    try {
      if (this.threadId) await this.rpc.request('thread/unsubscribe', { threadId: this.threadId });
      this.threadId = null; this.messages = []; this.parts.clear(); this.requests.clear(); this.notice = '';
    } finally { this.active = false; }
    return this.snapshot();
  }
}

export function handler(chat, token, { recognizer } = {}) {
  let windowStart = Date.now(), count = 0;
  return async (req, res) => {
    const reply = (status, data) => {
      if (res.destroyed) return;
      const payload = Buffer.from(JSON.stringify(data));
      res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': payload.length,
        'Cache-Control': 'no-store', 'Connection': 'close', 'X-Content-Type-Options': 'nosniff' });
      res.end(payload);
    };
    // No browser access, redirects, generic RPC forwarding, or public health endpoint.
    if (req.headers.origin || req.headers['sec-fetch-site'] || req.headers['forwarded'] ||
        Object.keys(req.headers).some(k => k.startsWith('x-forwarded-')) ||
        !authorized(req.headers.authorization, token)) { reply(401, { error: 'Unauthorized' }); return; }
    if (Date.now() - windowStart > 60000) { windowStart = Date.now(); count = 0; }
    if (++count > 180) { reply(429, { error: 'Too many requests' }); return; }
    try {
      if (req.method === 'GET' && req.url === '/v1/state') { reply(200, chat.snapshot()); return; }
      if (req.method === 'GET' && req.url === '/v1/recognize') {
        reply(recognizer ? 200 : 503, recognizer ? recognizer.state() : { error: 'Local recognizer is unavailable' }); return;
      }
      if (req.method !== 'POST' || !['/v1/prompt','/v1/stop','/v1/reset','/v1/recognize'].includes(req.url)) {
        reply(404, { error: 'Unknown endpoint' }); return;
      }
      if (req.headers['content-type'] !== 'application/json') { reply(415, { error: 'JSON required' }); return; }
      let size = 0, chunks = [];
      for await (const chunk of req) {
        size += chunk.length;
        if (size > (req.url === '/v1/recognize' ? 800000 : 70000)) { reply(413, { error: 'Request too large' }); return; }
        chunks.push(chunk);
      }
      let body;
      try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { throw Object.assign(new Error('Invalid JSON'), { status: 400 }); }
      if (req.url === '/v1/recognize') {
        if (!recognizer) { reply(503, { error: 'Local recognizer is unavailable' }); return; }
        reply(200, recognizer.start(body)); return;
      }
      if (req.url !== '/v1/prompt' && (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).length)) {
        throw Object.assign(new Error('Empty JSON object required'), { status: 400 });
      }
      const result = req.url === '/v1/prompt' ? await chat.prompt(body) : req.url === '/v1/stop' ? await chat.stop() : await chat.reset();
      reply(200, result);
    } catch (e) { reply(e.status || 503, { error: e.status ? e.message : 'Codex is unavailable. Check the computer-side sign-in and bridge.' }); }
  };
}
