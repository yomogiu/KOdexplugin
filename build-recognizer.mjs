import { execFileSync } from 'node:child_process';
import { mkdirSync, chmodSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { privateDirectory } from './security.mjs';
process.umask(0o077);
const root=privateDirectory(resolve('.private'));
const cache=join(root,'swift-cache');mkdirSync(cache,{recursive:true,mode:0o700});
const output=join(root,'ocr-worker');
execFileSync('/usr/bin/swiftc',['-O','-module-cache-path',cache,fileURLToPath(new URL('./ocr/Recognizer.swift',import.meta.url)),
  '-o',output,'-framework','Foundation','-framework','CoreGraphics','-framework','Vision'],{stdio:'inherit'});
chmodSync(output,0o700);
console.log('Built the Mac-local recognizer. No cloud OCR provider or extra model is used.');
