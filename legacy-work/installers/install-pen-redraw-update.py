from pathlib import Path
import os,hashlib,json,tarfile,datetime
root=Path('outputs/kobo-codex');src=root/'kobocodex.koplugin'
volume=Path('/Volumes/KOBOeReader');dst=volume/'.adds/koreader/plugins/kobocodex.koplugin'
assert dst.is_dir(), 'Kobo must be mounted'
assert (volume/'.adds/koreader/git-rev').read_text().strip()=='v2026.07.1'
version=json.loads((root/'package.json').read_text())['version'];assert version=='0.3.4'
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
protected={n:sha(dst/n) for n in ['connection.json','transport.lua','inkpad.lua','_meta.lua','main.lua']}
backups=Path('outputs/kobo-backups');backups.mkdir(exist_ok=True);os.chmod(backups,0o700)
backup=backups/('kobocodex-before-pen-redraw-'+datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'.tar.gz')
fd=os.open(backup,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'wb') as f:
 with tarfile.open(fileobj=f,mode='w:gz') as t:t.add(dst,arcname='kobocodex.koplugin')
with tarfile.open(backup,'r:gz') as t:
 for n in ['chatpanel.lua',*protected]:assert t.extractfile('kobocodex.koplugin/'+n).read()==(dst/n).read_bytes()
for n in ['chatpanel.lua']:
 with (dst/n).open('wb') as f:f.write((src/n).read_bytes());f.flush();os.fsync(f.fileno())
 assert sha(dst/n)==sha(src/n)
 sidecar=dst/('._'+n)
 if sidecar.exists():sidecar.unlink()
assert all(sha(dst/n)==h for n,h in protected.items())
r=json.loads((root/'installation.json').read_text());r['version']=version;r['ui']='Deferred Pen-mode transition and post-frame follow-up redraw';r['backupArchive']=str(backup.resolve())
for n in ['chatpanel.lua']:r.setdefault('sha256',{})[n]=sha(dst/n)
(root/'installation.json').write_text(json.dumps(r,indent=2)+'\n')
f=root/'TESTING.md';f.write_text(f.read_text().replace('UI 0.3.4 prepared, not installed.', 'UI 0.3.4 installed: chatpanel source hash-verified; pairing, transport, pen module, and metadata unchanged.'))
f=root/'HANDWRITING.md';f.write_text(f.read_text().replace('Prepared update: plugin version 0.3.4 for the installed KOReader v2026.07.1.', 'Installed: plugin version 0.3.4 and KOReader v2026.07.1.'))
print('Backed up plugin and installed version 0.3.4; changed UI file verified. Pairing, transport and pen module unchanged.')
