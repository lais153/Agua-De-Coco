import fs from 'node:fs';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const config='dist/server/wrangler.json';
if(!fs.existsSync(config))throw new Error('Execute pnpm build antes de preparar o banco local.');
const markers='.wrangler/state/realeza-migrations';
fs.mkdirSync(markers,{recursive:true});
for(const file of fs.readdirSync('drizzle').filter(f=>f.endsWith('.sql')).sort()){
  const marker=path.join(markers,file+'.applied');
  if(fs.existsSync(marker))continue;
  const result=spawnSync(process.execPath,['--import','./scripts/sites-env.mjs','./node_modules/wrangler/bin/wrangler.js','d1','execute','DB','--local','--config',config,'--persist-to','.wrangler/state','--file',path.join('drizzle',file)],{stdio:'inherit'});
  if(result.error)throw result.error;
  if(result.status!==0)process.exit(result.status||1);
  fs.writeFileSync(marker,new Date().toISOString());
}
console.log('Banco de teste preparado. Execute pnpm dev.');
