from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
guard="""begin;
-- Fail before any change if the existing deletion/merge schema has drifted.
do $$begin
 if private.scoped_deletion_schema_hash()<>'77511a6731a00bdd44ab3767a9581c873cb8e69f97f54cbbb51547f8276568d0'
 or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
 then raise exception 'Practice plans needs a fresh schema compatibility review';end if;
end $$;
"""
content=guard+'\n'.join((root/('supabase/practice-plans'+s+'.sql')).read_text() for s in ['','-compatibility'])+'\ncommit;\n'
p=root/'supabase/migrations/20261001010602_practice_plans_020109.sql'
if '--check' in sys.argv:
 assert p.read_text()==content,'Practice plans migration differs from reviewed sources'
 print('PASS Practice plans migration assembly')
else:p.write_text(content)
