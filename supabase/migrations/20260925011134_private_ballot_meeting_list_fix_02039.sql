-- Resolve the table alias independently of the PL/pgSQL meeting record.
create or replace function private.vote039_meeting(q jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare o uuid=nullif(q->>'organization_id','')::uuid; m private.organization_meetings%rowtype; out jsonb; request uuid=nullif(q->>'request_id','')::uuid; receipt private.organization_meeting_requests%rowtype; demo jsonb; i integer;
begin
 if auth.uid() is null or not private.ops_personal() or not private.managed_login_access_ok() then raise sqlstate '42501' using message='Use your personal account.';end if;
 if q->>'action'='meeting_delete_test' then
  if not private.ops_admin(o) then raise sqlstate '42501' using message='Organization administrator required to delete a test meeting.';end if;
  if request is null or q->>'confirm_delete' is distinct from 'DELETE' then raise exception 'Type DELETE to delete this test meeting and its test ballots.';end if;
  perform 1 from public.organizations where id=o for update;
  select * into receipt from private.organization_meeting_requests where organization_id=o and actor_id=auth.uid() and request_id=request;
  if found then if receipt.fingerprint<>md5(q::text) then raise exception 'Request ID already used for different content.';end if;return receipt.result;end if;
  select * into m from private.organization_meetings where id=nullif(q->>'id','')::uuid and organization_id=o for update;
  if not found or not m.is_test then raise exception 'Only a test meeting can be deleted here.';end if;
  if q->>'revision' is null or (q->>'revision')::int<>m.revision then raise sqlstate '40001' using message='Meeting changed. Reload before deleting.';end if;
  delete from private.organization_secret_requests where organization_id=o and result->>'id' in(select id::text from private.organization_secret_rounds where meeting_id=m.id);
  delete from private.organization_secret_delegations where round_id in(select id from private.organization_secret_rounds where meeting_id=m.id);
  delete from private.organization_secret_participants where round_id in(select id from private.organization_secret_rounds where meeting_id=m.id);
  delete from private.organization_secret_totals where round_id in(select id from private.organization_secret_rounds where meeting_id=m.id);
  delete from private.organization_secret_rounds where meeting_id=m.id;
  delete from private.organization_meeting_requests where organization_id=o and result->>'id'=m.id::text;
  delete from private.organization_meetings where id=m.id;
  out:=jsonb_build_object('id',m.id,'deleted',true);
  insert into private.organization_meeting_requests(organization_id,actor_id,request_id,fingerprint,result) values(o,auth.uid(),request,md5(q::text),out);
  insert into private.ops_audit(organization_id,actor_id,action,record_id,detail) values(o,auth.uid(),'meeting_delete_test',m.id,'{"is_test":true}');
  return out;
 end if;
 if q->>'action' in ('meeting_adjourn','meeting_cancel') then
  perform 1 from public.organizations where id=o for update;
  select * into m from private.organization_meetings where organization_id=o and id=nullif(q->>'id','')::uuid;
  if m.id is null or not private.meeting038_editor(m) then raise exception 'Meeting editor access required.' using errcode='42501';end if;
  if exists(select 1 from private.organization_secret_rounds where organization_id=o and meeting_id=m.id and status='open') then raise exception 'Close or cancel every open ballot before adjourning this meeting.';end if;
 end if;
 out:=private.meeting038_request(q);
 if q->>'action'='meeting_create' and q->>'is_test'='true' then
  select * into m from private.organization_meetings where id=(out->>'id')::uuid and created_by=auth.uid() for update;
  if m.id is not null and not m.is_test then
   demo:='[]';for i in 1..3 loop demo:=demo||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'kind','affiliate','name','Demo club '||i||' (test only)','delegate','','present',true,'eligible',true));end loop;
   update private.organization_meetings set is_test=true,workspace=jsonb_set(workspace,'{roll}',workspace->'roll'||demo) where id=m.id;
   insert into private.organization_meeting_attendance(meeting_id,participant_kind,participant_id,display_name,present)
    select m.id,'affiliate',(a->>'id')::uuid,a->>'name',true from jsonb_array_elements(demo) a;
  end if;
 elsif q->>'action'='meeting_list' then
  out:=out||'{"voting_enabled":true}'::jsonb;
  out:=jsonb_set(out,'{meetings}',coalesce((select jsonb_agg(a||jsonb_build_object('is_test',listed.is_test)) from jsonb_array_elements(out->'meetings') a join private.organization_meetings listed on listed.id=(a->>'id')::uuid),'[]'));
 end if;
 return out;
end $$;
