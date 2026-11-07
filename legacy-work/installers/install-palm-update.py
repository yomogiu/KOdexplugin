from pathlib import Path
import os, hashlib, json
p=Path('outputs/kobo-codex');src=p/'kobocodex.koplugin';dst=Path('/Volumes/KOBOeReader/.adds/koreader/plugins/kobocodex.koplugin')
assert dst.is_dir(), 'Kobo must be connected and mounted'
hashfile=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
protected={n:hashfile(dst/n) for n in ['connection.json','transport.lua','_meta.lua']}
files=['main.lua','chatpanel.lua','inkpad.lua']
for n in files:
 data=(src/n).read_bytes()
 with (dst/n).open('wb') as f:
  f.write(data);f.flush();os.fsync(f.fileno())
 assert (dst/n).read_bytes()==data
 sidecar=dst/('._'+n)
 if sidecar.exists():sidecar.unlink()
assert all(hashfile(dst/n)==h for n,h in protected.items())
assert all(hashfile(dst/n)==hashfile(src/n) for n in files)
r=json.loads((p/'installation.json').read_text());r['version']='0.3.2';r['ui']='Pen controls above pad, palm touch suppression, bounded menus and full edge redraw';r['backupArchive']=Path('work/palm-layout-backup.txt').read_text().strip()
if not isinstance(r.get('sha256'),dict):r['sha256']={}
for n in files:r['sha256'][n]=hashfile(dst/n)
(p/'installation.json').write_text(json.dumps(r,indent=2)+'\n')
f=p/'TESTING.md';s=f.read_text().replace('UI 0.3.2 prepared; USB installation pending.', 'UI 0.3.2 installed and all three changed files hash-verified. Pairing, transport, and metadata unchanged.');f.write_text(s)
f=p/'HANDWRITING.md';s=f.read_text().replace('Prepared update: plugin version 0.3.2 for the installed KOReader v2026.07.1.\nThe Mac recognizer and encrypted recognition path are tested. Install the plugin\nupdate by USB, then eject and restart KOReader for the physical stylus/visual check.', 'Installed: plugin version 0.3.2 and KOReader v2026.07.1.\nThe Mac recognizer and encrypted recognition path are tested. Eject and restart\nKOReader for the physical stylus/visual check.');f.write_text(s)
print('Installed and verified version 0.3.2: all three UI files. Pairing and transport unchanged.')
