from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
guard="""begin;
-- Fail before any change if the existing deletion/merge schema has drifted.
do $$begin
 if private.scoped_deletion_schema_hash()<>'4edb6748d4f52b32daeb62498f2fb3152b6bc5caa1ac1618b7e89e77c850d587'
 or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
 then raise exception 'Athlete Health needs a fresh schema compatibility review';end if;
end $$;
"""
content=guard+'\n'.join((root/('supabase/athlete-health'+s+'.sql')).read_text() for s in ['-roles','','-compatibility'])+'\ncommit;\n'
p=root/'supabase/migrations/20260930233008_team_trainer_athlete_health_020106.sql'
if '--check' in sys.argv:
 assert p.read_text()==content,'Athlete Health migration differs from reviewed sources'
 print('PASS Athlete Health migration assembly')
else:p.write_text(content)
