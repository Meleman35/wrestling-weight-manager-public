'use strict';
// Synthetic Auth/application fixtures plus actual draft migrations and recorder guards.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');
const read = p => fs.readFileSync(path.join(root, p), 'utf8');
const migration = name => read('supabase/migrations/' + name);
function before(source, marker) { const at=source.indexOf(marker); assert(at>0, 'Fixture boundary exists'); return source.slice(0,at); }
function existingFunction(source, signature) {
  const at=source.indexOf('CREATE OR REPLACE FUNCTION '+signature); assert(at>=0, 'Existing function found: '+signature);
  const begin=source.indexOf('$function$',at), end=source.indexOf('$function$',begin+10);
  assert(begin>at && end>begin, 'Existing function has complete dollar delimiters');
  return source.slice(at,end+10)+';';
}
async function setup(db) {
    await db.exec(`
      create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create schema private;
      create table auth.users(id uuid primary key, banned_until timestamptz, deleted_at timestamptz);
      create table auth.sessions(id uuid primary key,user_id uuid references auth.users on delete cascade,not_after timestamptz);
      create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
      create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
      grant usage on schema auth,public to anon,authenticated,service_role;
      create table public.teams(id uuid primary key);
      create table public.athletes(id uuid primary key);
      create table public.team_memberships(id uuid primary key,team_id uuid references public.teams,user_id uuid references auth.users on delete cascade);
      create table public.communication_threads(id uuid primary key);
      create table public.athlete_guardians(id uuid primary key,athlete_id uuid references public.athletes on delete cascade,guardian_user_id uuid references auth.users on delete set null);
      create table public.guardian_invitations(id uuid primary key);
      create table private.wrestling_profiles(id uuid primary key);
      create table private.team_logins(id uuid primary key,user_id uuid,kind text,active boolean,state text,revision integer,parent_id uuid,permissions jsonb);
      create table private.team_login_sessions(session_id uuid,login_id uuid,revision integer,device_id uuid);
      create table private.team_login_devices(id uuid,parent_id uuid,credential_session_id uuid,current_session_id uuid,revision integer);
    `);
    await db.exec(before(migration('20260929114400_parent_browser_approval.sql'),'create function private.parent_browser_verification_valid'));
    await db.exec(before(migration('20260929123507_quiet_conversation_reviewers.sql'),'create function private.conversation_review_admin'));
    await db.exec(migration('20260929052714_account_deletion_intake_draft.sql'));
    await db.exec(migration('20260929190649_account_deletion_fulfillment_draft.sql'));
    await db.exec(existingFunction(read('tests/team-recorder-login-existing.sql'),'private.managed_login_access_ok()'));
    const recorderSQL = migration('20260927180754_team_recorder_login_02066.sql');
    await db.exec(existingFunction(recorderSQL,'private.enforce_team_login_request()'));
    await db.exec(existingFunction(recorderSQL,'private.managed_resource_allowed(p_resource text)'));
    // Public wrapper logic verified by read-only production inspection September 29.
    await db.exec(`create function public.enforce_team_login_request() returns void language plpgsql set search_path='' as $$
      begin if (select auth.uid()) is null then return; end if; perform private.enforce_team_login_request(); end $$;
      revoke all on function private.enforce_team_login_request(),private.managed_login_access_ok(),private.managed_resource_allowed(text) from public,anon;
      grant execute on function private.enforce_team_login_request() to authenticated;
      select set_config('pgrst.db_pre_request','public.enforce_team_login_request',false);
    `);
}
module.exports = {setup};
