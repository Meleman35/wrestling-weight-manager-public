from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
guard="""begin;
-- Fail before any change if the existing deletion/merge schema has drifted.
do $$begin
 if private.scoped_deletion_schema_hash()<>'27d274de0c35fb69ae2ed5ff35a959b9b001de1ef865fad1a804b5ba8b39f57e'
 or not exists(select 1 from private.scoped_deletion_config where id and catalog_hash=private.scoped_deletion_schema_hash())
 then raise exception 'Creator offers needs a fresh schema compatibility review';end if;
end $$;
"""
content=guard+'\n'.join((root/('supabase/creator-offers'+s+'.sql')).read_text() for s in ['','-compatibility'])+'\ncommit;\n'
p=root/'supabase/migrations/20261001002730_creator_offer_controls_020107.sql'
if '--check' in sys.argv:
 assert p.read_text()==content,'Creator offers migration differs from reviewed sources'
 print('PASS Creator offers migration assembly')
else:p.write_text(content)
