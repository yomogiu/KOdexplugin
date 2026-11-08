'use strict';
const { createHash } = require('node:crypto');
const path = require('node:path');
const ID = /^[a-f0-9]{32}$/;
const KEY = /^[a-f0-9]{64}$/;
const PORT = 9444;
const MAX_RECORD = 512 * 1024;
const PAIRING_NAME = 'obsidian-companion.json';
const pairingsRoot = home => path.join(home, 'Library/Application Support/KOdex/companion-pairings');
function pairingFile(root, id) {
  check(typeof id === 'string' && ID.test(id), 'Invalid pairing destination identity');
  return path.join(root, id, PAIRING_NAME);
}
const digest = value => createHash('sha256').update(value).digest('hex');
function check(condition, message) { if (!condition) throw new Error(message); }
function keys(value, required, optional = []) {
  return value && typeof value === 'object' && !Array.isArray(value) &&
    required.every(k => Object.hasOwn(value, k)) && Object.keys(value).every(k => required.includes(k) || optional.includes(k));
}
function folder(value, maxLength = 240) {
  check(typeof value === 'string' && value.length <= maxLength && value !== '' &&
    !/[\\\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/.test(value) &&
    value.split('/').every(p => p && p !== '..' && !p.startsWith('.')), 'Choose an ordinary relative vault subfolder');
  return value;
}
function pairing(value) {
  check(keys(value, ['version', 'destinationId', 'token', 'port', 'enabled', 'vaultKey']) &&
    value.version === 1 && ID.test(value.destinationId) && KEY.test(value.token) && value.port === PORT &&
    typeof value.enabled === 'boolean' && (value.vaultKey === null || KEY.test(value.vaultKey)), 'Invalid companion pairing file');
  return value;
}
function record(value) {
  check(keys(value, ['version', 'id', 'destinationId', 'createdAt', 'title', 'source', 'messages']) &&
    value.version === 1 && ID.test(value.id) && ID.test(value.destinationId) &&
    typeof value.createdAt === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value.createdAt) && Number.isFinite(Date.parse(value.createdAt)) &&
    typeof value.title === 'string' && value.title.length <= 160 &&
    keys(value.source, ['kind'], ['documentId', 'conversationId']) &&
    ['sample', 'archive'].includes(value.source.kind) &&
    (value.source.kind !== 'archive' || (ID.test(value.source.documentId) && ID.test(value.source.conversationId))) &&
    Array.isArray(value.messages) && value.messages.length > 0 && value.messages.length <= 200 &&
    value.messages.every(m => keys(m, ['id', 'role', 'text'], ['submittedText']) && ID.test(m.id) &&
      ['user', 'assistant'].includes(m.role) && typeof m.text === 'string' && m.text.length <= 180000 &&
      (m.submittedText === undefined || (m.role === 'user' && typeof m.submittedText === 'string' && m.submittedText.length <= 16000))) &&
    Buffer.byteLength(JSON.stringify(value)) <= MAX_RECORD, 'Invalid or oversized export record');
  return value;
}
function literal(text) {
  // Untrusted model/book text stays literal: no remote images, HTML, URI
  // actions, vault transclusions, or YAML interpolation during rendering.
  const safe = text.replace(/[\x00-\x08\x0b-\x1f\x7f-\x9f]/g, '');
  const longest = Math.max(2, ...(safe.match(/`+/g) || []).map(s => s.length));
  const fence = '`'.repeat(longest + 1);
  return `${fence}text\n${safe}\n${fence}`;
}
function render(value) {
  record(value);
  const lines = ['---', `kodex_export_id: ${value.id}`, `kodex_destination_id: ${value.destinationId}`,
    `created: ${JSON.stringify(value.createdAt)}`, `title: ${JSON.stringify(value.title)}`,
    `source: ${value.source.kind}`];
  if (value.source.kind === 'archive') lines.push(`document_id: ${value.source.documentId}`, `conversation_id: ${value.source.conversationId}`);
  lines.push('---', '', '# KOdex reading conversation', '', literal(value.title), '');
  for (const message of value.messages) {
    lines.push(`## ${message.role === 'user' ? 'Your question' : 'Assistant answer'}`, '', literal(message.text), '', `^kodex-${message.id}`, '');
    if (message.submittedText && message.submittedText !== message.text) {
      lines.push('### Submitted context', '', literal(message.submittedText), '');
    }
  }
  return lines.join('\n');
}
module.exports = { ID, KEY, PORT, MAX_RECORD, PAIRING_NAME, pairingsRoot, pairingFile, digest, check, keys, folder, pairing, record, render };
