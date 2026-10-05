import {readFile} from 'node:fs/promises';

// Candidate assembly only. It does not approve a catalog, deploy SQL, or mutate
// historical migrations. Production still requires an exact live-source review.
const root=new URL('../',import.meta.url);
const schemas="('public','private','wm_billing')";
function definition(source,name){
 const marker='create function '+name+'(';
 const start=source.indexOf(marker),end=source.indexOf('$$;',start);
 if(start<0||end<0||source.indexOf(marker,start+1)!==-1)throw Error('Deletion source requires review: '+name);
 return source.slice(start,end+3).replace('create function ','create or replace function ');
}
export async function billingDeletionIntegrationSQL(){
 const service=await readFile(new URL('supabase/scoped-deletion-service.sql',root),'utf8');
 const media=await readFile(new URL('supabase/scoped-deletion-media.sql',root),'utf8');
 const parts=[];
 for(const [source,names] of [[service,['private.scoped_deletion_schema_hash','private.scoped_deletion_read']],
  [media,['private.scoped_deletion_media_inventory','private.scoped_deletion_seal_media']]]){
  for(const name of names){
   const text=definition(source,name);
   if(!text.includes("('public','private')"))throw Error('Deletion schema boundary requires review');
   parts.push(text.replaceAll("('public','private')",schemas));
  }
 }
 const boundary="elsif p_op='erase_records' and j.state='records' then\n";
 let worker=definition(service,'private.scoped_deletion_service');
 if(worker.split(boundary).length!==2)throw Error('Deletion ordering requires review');
 worker=worker.replace(boundary,boundary+
  '  -- Preserve paid team time while the sealed purchase evidence still exists.\n'+
  '  -- This runs in the same transaction, before the generic record erasure.\n'+
  '  perform wm_billing.prepare_deletion(j.id,p_lease);\n');
 parts.push(worker);
 parts.push(`do $$declare tab text;begin
  foreach tab in array array['team_bindings','intents','subscriptions','deliveries','family_coverage','notification_inbox','team_paid_remainders'] loop
   execute format('create trigger scoped_deletion_freeze before insert or update or delete on wm_billing.%I for each row execute function private.scoped_deletion_freeze()',tab);
  end loop;
 end $$;`);
 return parts.join('\n');
}
