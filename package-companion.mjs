import { mkdir, mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { buildCompanion } from './build-companion.mjs';

const root = import.meta.dirname;
const releases = join(root, '.local/releases');
await mkdir(releases, { recursive: true, mode: 0o700 });
const staging = await mkdtemp(join(releases, 'companion-build-'));
const archive = join(releases, 'kodex-companion.zip');
try {
  const destination = join(staging, 'kodex-companion');
  await buildCompanion(destination);
  await rm(archive, { force: true });
  await promisify(execFile)('/usr/bin/ditto', ['-c', '-k', '--norsrc', '--noextattr', '--noacl', '--keepParent', destination, archive]);
} finally { await rm(staging, { force: true, recursive: true }); }
console.log(`Companion package: ${archive}`);
