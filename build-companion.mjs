import { createRequire } from 'node:module';
import { mkdir, copyFile, rm } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = import.meta.dirname;
const pluginRequire = createRequire(new URL('./obsidian-kodex/package.json', import.meta.url));

export async function buildCompanion(destination) {
  const { build } = pluginRequire('esbuild');
  await mkdir(destination, { recursive: true, mode: 0o700 });
  await build({
    entryPoints: [join(root, 'obsidian-kodex/main.js')],
    outfile: join(destination, 'main.js'),
    bundle: true, platform: 'node', format: 'cjs', target: 'es2020',
    external: ['obsidian', 'electron'], sourcemap: false, minify: false,
    banner: { js: '// KOdex Companion. Bundled from the source in obsidian-kodex/.' },
    logLevel: 'silent',
  });
  for (const name of ['manifest.json', 'README.md']) {
    await copyFile(join(root, 'obsidian-kodex', name), join(destination, name));
  }
  await copyFile(join(root, 'LICENSE'), join(destination, 'LICENSE'));
  // These belonged to the unbundled preview, not to the installable artifact.
  for (const name of ['core.cjs', 'protocol.cjs', 'package.json']) await rm(join(destination, name), { force: true });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const destination = join(root, 'outputs/obsidian-install/kodex-companion');
  await buildCompanion(destination);
  console.log(`Installable companion folder: ${destination}`);
}
