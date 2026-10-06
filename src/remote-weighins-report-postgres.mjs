// Privileged, server-only canonical report reader. Invoke only through the
// reporting service's live assignment checks. One SQL statement supplies the
// roster, accepted weights, totals, page and revision from one MVCC snapshot.
const query=`with candidates as materialized (
 select r.club_id,r.athlete_id,t.name as club_name,a.first_name,a.last_name,
  coalesce(m.usaw_id,'') as usaw_id,coalesce(m.aau_number,'') as aau_number,
  s.submission_id,s.receipt_id,s.received_at,s.record,
  case when s.submission_id is null then 'missing'
   when s.received_at>=w.closes_at then 'late' else 'submitted' end as status
 from remote_reporting.roster r
 join remote_reporting.windows w on w.program_id=r.program_id and w.id=r.window_id
 join public.teams t on t.id=r.club_id::uuid
 join public.athletes a on a.id=r.athlete_id::uuid and a.organization_id=t.organization_id
 left join private.athlete_membership_identifiers m on m.profile_id=a.profile_id
 left join lateral (
  select s.* from remote_reporting.submissions s
  where s.program_id=r.program_id and s.window_id=r.window_id
   and s.club_id=r.club_id and s.athlete_id=r.athlete_id
   and (s.record->>'capturedAt')::timestamptz+interval '240 hours'>statement_timestamp()
   and exists(select 1 from remote_reporting.evidence e where e.id=s.evidence_id
     and e.verified and not e.revoked and e.expires_at>statement_timestamp())
  order by (s.record->>'weight')::numeric,(s.record->>'capturedAt'),s.submission_id limit 1
 ) s on true
 where r.program_id=$1 and r.window_id=$2 and ($3::text is null or r.club_id=$3)
  and r.active and r.remote_consent and w.active
  and exists(select 1 from remote_reporting.club_enrollments ce where ce.program_id=r.program_id and ce.club_id=r.club_id and ce.active)
  and exists(select 1 from public.roster_memberships rm join public.seasons season on season.id=rm.season_id
   where rm.athlete_id=a.id and rm.active and season.active and season.team_id=t.id)
 order by r.club_id,r.athlete_id limit 20001
), projected as materialized (
 select *,jsonb_build_object('clubId',club_id,'athleteId',athlete_id,'clubName',club_name,
  'athleteName',trim(concat_ws(' ',first_name,last_name)),'firstName',coalesce(first_name,''),'lastName',coalesce(last_name,''),
  'usawId',usaw_id,'aauNumber',aau_number,'status',status,
  'submission',case when submission_id is null then null else jsonb_build_object(
   'submissionId',submission_id,'receiptId',receipt_id,'weight',(record->>'weight')::numeric,'unit',record->>'unit',
   'capturedAt',to_char((record->>'capturedAt')::timestamptz at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
   'receivedAt',to_char(received_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')) end) as row
 from candidates
), totals as (
 select count(*)::int as expected,count(*) filter(where status='submitted')::int as submitted,
  count(*) filter(where status='late')::int as late,count(*) filter(where status='missing')::int as missing from projected
), filtered as materialized (
 select *,row_number() over(order by club_name collate "C",club_id,
  trim(concat_ws(' ',first_name,last_name)) collate "C",athlete_id) as position
 from projected where $4::text is null or status=$4
), summary as (
 select count(*)::int as total,encode(sha256(convert_to(jsonb_build_object(
  'programId',$1::text,'windowId',$2::text,'clubId',$3::text,'status',$4::text,
  'counts',(select row_to_json(totals) from totals),
  'rows',coalesce(jsonb_agg(row order by position),'[]'::jsonb))::text,'UTF8')),'hex') as revision from filtered
)
select summary.*,row_to_json(totals) as counts,
 coalesce((select jsonb_agg(row order by position) from filtered where position>$5 and position<=$5+$6),'[]'::jsonb) as rows
from summary cross join totals`;

export function createCanonicalRemoteReportReader({db}) {
 if(typeof db?.query!=='function')throw Error('Trusted report database required');
 return async ({programId,windowId,clubId=null,status=null,offset=0,limit=100,revision=null})=>{
  if(![programId,windowId].every(x=>typeof x==='string'&&/^[A-Za-z0-9_-]{1,160}$/.test(x))||
   (clubId!==null&&(typeof clubId!=='string'||!/^[0-9a-f-]{36}$/.test(clubId)))||
   !(status===null||['submitted','late','missing'].includes(status))||!Number.isInteger(offset)||offset<0||offset>20000||!Number.isInteger(limit)||limit<1||limit>500)throw Error('Invalid report query');
  const result=(await db.query(query,[programId,windowId,clubId,status,offset,limit])).rows[0];
  if(!result||result.counts.expected>20000)throw Error('Report capacity exceeded; select one club');
  if(revision!==null&&revision!==result.revision)throw Error('Report changed; refresh and export again');
  return {...result,nextOffset:offset+result.rows.length<result.total?offset+result.rows.length:null};
 };
}
