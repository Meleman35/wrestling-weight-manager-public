-- Review candidate, not a deployed migration. Include in scoped-deletion catalog
-- and schema fingerprint before enabling writes. Keep outside the public API.
create table private.athlete_membership_identifiers (
 profile_id uuid primary key references public.athlete_profiles(id) on delete cascade,
 usaw_id text not null default '',
 aau_number text not null default '',
 verification text not null default 'unverified' check (verification='unverified'),
 updated_at timestamptz not null default clock_timestamp(),
 check (usaw_id='' or usaw_id ~ '^[A-Za-z0-9][A-Za-z0-9 -]{0,63}$'),
 check (aau_number='' or aau_number ~ '^[A-Za-z0-9][A-Za-z0-9 -]{0,63}$')
);
alter table private.athlete_membership_identifiers enable row level security;
revoke all on private.athlete_membership_identifiers from public,anon,authenticated;
