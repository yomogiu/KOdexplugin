from pathlib import Path, PurePosixPath
import tarfile, zipfile, hashlib, datetime, os, stat, json, subprocess, time
cwd=Path.cwd();device=Path('/Volumes/KOBOeReader');target=device/'.adds/koreader';source=cwd/'outputs/kobo-codex';package=cwd/'work/handwriting/koreader-kobo-v2026.07.1.zip'
assert target.is_dir(),'Connect the Kobo and tap Connect before installing'
assert (device/'.kobo/version').read_text().startswith('N605'),'This update was prepared for Kobo Elipsa 2E'
assert (device/'.kobo/version').read_text().split(',')[2].startswith('4.'),'This package is for Kobo firmware 4.x'
version=(target/'git-rev').read_text().strip()
assert version in {'v2025.04','v2026.07.1'},'Unreviewed KOReader version; inspect before proceeding'
assert hashlib.sha256(package.read_bytes()).hexdigest()=='0f36a62ce73b12516f969e4ad7862cc06920afb03c7bd4db29a0d990bdd84b2f'
protected=[target/n for n in ['settings.reader.lua','history.lua','defaults.custom.lua']]
protected.append(target/'plugins/kobocodex.koplugin/connection.json')
original={p:hashlib.sha256(p.read_bytes()).hexdigest() for p in protected if p.is_file()}
prepared=json.loads((cwd/'work/handwriting/prepared-backup.json').read_text())
backup=Path(prepared['archive'])
assert backup.is_file() and prepared['version']==version and time.time()-prepared['created_epoch']<3600,'A fresh verified backup is required'
for path,digest in original.items():assert prepared['protected'][str(path.relative_to(target))]==digest,'State changed since backup'
with open(backup,'rb') as f:assert hashlib.file_digest(f,'sha256').hexdigest()==prepared['sha256'],'Backup checksum mismatch'
# Extract only the verified application folder, retaining launchers and user state.
count=0
with zipfile.ZipFile(package) as z:
 for info in z.infolist():
  parts=PurePosixPath(info.filename).parts
  if not parts or parts[0]!='koreader':continue
  assert '..' not in parts and not info.filename.startswith('/')
  assert not stat.S_ISLNK(info.external_attr>>16),'Unexpected symbolic link in official package'
  relative=Path(*parts[1:])
  assert str(relative) not in {'settings.reader.lua','history.lua','defaults.custom.lua'}
  out=target/relative
  if info.is_dir():out.mkdir(parents=True,exist_ok=True);continue
  out.parent.mkdir(parents=True,exist_ok=True)
  temp=out.with_name('.codex-update-'+out.name+'.part');assert not temp.exists()
  payload=z.read(info)
  with open(temp,'xb') as f:f.write(payload);f.flush();os.fsync(f.fileno())
  os.replace(temp,out)
  assert hashlib.sha256(out.read_bytes()).digest()==hashlib.sha256(payload).digest()
  count+=1
plugin=target/'plugins/kobocodex.koplugin';plugin.mkdir(exist_ok=True)
for name in ['main.lua','chatpanel.lua','inkpad.lua','transport.lua','_meta.lua']:
 payload=(source/'kobocodex.koplugin'/name).read_bytes()
 with open(plugin/name,'wb') as f:f.write(payload);f.flush();os.fsync(f.fileno())
 assert (plugin/name).read_bytes()==payload
 subprocess.run(['/usr/bin/xattr','-c',str(plugin/name)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 sidecar=plugin/('._'+name)
 if sidecar.exists():sidecar.unlink()
for path,digest in original.items():assert hashlib.sha256(path.read_bytes()).hexdigest()==digest,'User state was modified unexpectedly'
assert (target/'git-rev').read_text().strip()=='v2026.07.1'
record=json.loads((source/'installation.json').read_text())
record.update(koreader='v2026.07.1',ui='persistent composer with local handwriting',handwriting=True,backupArchive=backup.name,verifiedCoreFiles=count,verified_files=6)
record['sha256']={n:hashlib.sha256((plugin/n).read_bytes()).hexdigest() for n in ['main.lua','chatpanel.lua','inkpad.lua','transport.lua','_meta.lua']}
(source/'installation.json').write_text(json.dumps(record,indent=2))
print(json.dumps({'koreader':'v2026.07.1','verifiedCoreFiles':count,'verifiedPluginFiles':5,'userStateAndPairingPreserved':True,'backup':backup.name}))
