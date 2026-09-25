-- Release after local authorization/privacy tests, browser/database integration,
-- and separate PostgreSQL transactions verified duplicate, substitution, close,
-- rollback/retry, and distinct-seat races. All temporary fixtures were removed.
create or replace function private.vote039_released() returns boolean language sql stable set search_path='' as $$select true;$$;
revoke all on function private.vote039_released() from public,anon,authenticated;
