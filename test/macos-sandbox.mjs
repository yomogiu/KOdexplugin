import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync,spawn} from 'node:child_process';
import net from 'node:net';
import {sandboxProfile} from '../security.mjs';
const root=mkdtempSync('/private/tmp/kobo-sandbox-audit-');
const noNetwork=process.argv.includes('--no-network');
const codexHome=join(root,'home'),workspace=join(root,'workspace'),privateTmp=join(root,'tmp');
for(const p of [codexHome,workspace,privateTmp])mkdirSync(p,{mode:0o700});
const allowed=join(workspace,'allowed.txt'),outside=join(root,'synthetic-secret.txt');
writeFileSync(allowed,'public synthetic fixture');writeFileSync(outside,'SYNTHETIC-NOT-A-REAL-SECRET');
const binary=join(root,'probe');
execFileSync('/usr/bin/cc',['-O2','-o',binary,fileURLToPath(new URL('./probe.c',import.meta.url))]);
const proxy=net.createServer(s=>s.end()),trap=net.createServer(s=>s.end());
for(const s of [proxy,trap])await new Promise(r=>s.listen(0,'127.0.0.1',r));
const profile=join(root,'sandbox.sb');
writeFileSync(profile,sandboxProfile({codexHome,workspace,privateTmp,nativeBinary:binary,proxyPort:noNetwork?null:proxy.address().port}));
try {
 const child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,allowed,outside,String(proxy.address().port),String(trap.address().port)],{env:{PATH:'/usr/bin:/bin'},stdio:['ignore','pipe','pipe']});
 let output='',err='';child.stdout.on('data',b=>output+=b);child.stderr.on('data',b=>err+=b);
 const code=await new Promise(r=>child.on('exit',r));
 if(code!==0&&!noNetwork)throw new Error(`Sandbox verification failed (${code}): ${output} ${err}`);
 const result=JSON.parse(output);
 if(result.proxyReachable!==!noNetwork)throw new Error('Proxy access rule failed');
 if(Object.entries(result).some(([k,v])=>k!=='proxyReachable'&&v!==true))throw new Error('A sandbox check failed');
 console.log(JSON.stringify(result));
}finally{proxy.close();trap.close();rmSync(root,{recursive:true,force:true});}
