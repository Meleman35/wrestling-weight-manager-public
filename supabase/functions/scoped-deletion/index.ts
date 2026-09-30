import {createClient} from 'npm:@supabase/supabase-js@2.100.1';
import {createDeletionHandler} from './handler.mjs';
const url=Deno.env.get('SUPABASE_URL')!;
const key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const anon=Deno.env.get('SUPABASE_ANON_KEY')!;
const options={auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}};
const admin=createClient(url,key,options);
Deno.serve(createDeletionHandler({admin,
 caller:(Authorization:string)=>createClient(url,anon,{...options,global:{headers:{Authorization}}}),
 waitUntil:(task:Promise<unknown>)=>EdgeRuntime.waitUntil(task)
}));
