"""Materialize the CLI-created review migration from its reviewed source."""
from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
source=(root/'supabase/practice-plan-review.sql').read_text()
target=root/'supabase/migrations/20261006032752_practice_plan_review_and_athlete_view.sql'
if '--check' in sys.argv:
    assert target.read_text()==source,'Practice review migration differs from reviewed source'
    print('PASS Practice review migration assembly')
else:
    target.write_text(source)
