import {readFile,writeFile} from 'node:fs/promises';
const root=new URL('../',import.meta.url);
const migration=new URL('supabase/migrations/20260930060258_scoped_deletion_worker.sql',root);
const marker='-- BEGIN GENERATED SCOPED SERVICE';
const base=(await readFile(migration,'utf8')).split(marker)[0].trimEnd();
const parts=[];
for(const name of ['service','media','guards'])parts.push(await readFile(new URL('supabase/scoped-deletion-'+name+'.sql',root),'utf8'));
await writeFile(migration,base+'\n'+marker+'\n'+parts.join('\n')+'\ncommit;\n');
