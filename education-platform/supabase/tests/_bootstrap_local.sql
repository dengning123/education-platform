-- Local/non-Supabase bootstrap for migrations 005+ that reference auth.users
-- and hosted roles. Not a production migration.

begin;
do $roles$
declare r text;
begin
  foreach r in array array['anon','authenticated','service_role','authenticator']
  loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I nologin nosuperuser nocreatedb nocreaterole nobypassrls', r);
    end if;
  end loop;
  -- Hosted-style BYPASSRLS for service_role as used by SQL tests.
  execute 'alter role service_role bypassrls';
  execute 'alter role service_role login';
end;
$roles$;
create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key,
  email text
);
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;
commit;
