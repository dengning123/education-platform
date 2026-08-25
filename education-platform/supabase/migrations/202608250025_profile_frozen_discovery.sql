-- Phase 4B: owner-scoped latest FROZEN Profile discovery.
--
-- This additive capability closes only the post-login lifecycle gap. It does
-- not change Profile document, freeze, fork, taxonomy, Eligibility, Fit, or
-- Financial semantics and it creates no student-linked durable state.

begin;

create or replace function public.get_latest_frozen_profile_v025()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_result jsonb;
begin
  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;

  select jsonb_build_object(
    'schemaVersion', 'PROFILE_FROZEN_DISCOVERY_V025',
    'profileVersionId', profile.profile_version_id,
    'versionNumber', profile.version_number,
    'status', 'FROZEN',
    'frozenAt', profile.frozen_at
  )
  into v_result
  from public.student_profile_versions profile
  where profile.student_id = v_student_id
    and profile.status = 'FROZEN'
  order by profile.version_number desc
  limit 1;

  if v_result is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  return v_result;
end;
$function$;

grant create on schema public to foundation_student_executor;
alter function public.get_latest_frozen_profile_v025()
  owner to foundation_student_executor;
revoke create on schema public from foundation_student_executor;

revoke all on function public.get_latest_frozen_profile_v025()
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant execute on function public.get_latest_frozen_profile_v025()
to authenticated;

insert into public.foundation_function_contracts (
  schema_name, function_name, identity_arguments, owner_role, prosecdef,
  search_path, allowed_caller_roles, body_digest
)
select namespace.nspname,
  procedure.proname,
  pg_get_function_identity_arguments(procedure.oid),
  procedure.proowner::regrole::text,
  procedure.prosecdef,
  'pg_catalog, public, private, extensions',
  array['authenticated']::text[],
  encode(extensions.digest(
    convert_to(pg_get_functiondef(procedure.oid), 'UTF8'), 'sha256'
  ), 'hex')
from pg_proc procedure
join pg_namespace namespace on namespace.oid = procedure.pronamespace
where namespace.nspname = 'public'
  and procedure.proname = 'get_latest_frozen_profile_v025'
on conflict (schema_name, function_name, identity_arguments) do update
set owner_role = excluded.owner_role,
    prosecdef = excluded.prosecdef,
    search_path = excluded.search_path,
    allowed_caller_roles = excluded.allowed_caller_roles,
    body_digest = excluded.body_digest;

comment on function public.get_latest_frozen_profile_v025() is
  'Owner-only, bounded latest-FROZEN Profile discovery. Returns lifecycle metadata only and creates no student state.';

do $assert$
declare
  v_function record;
begin
  select procedure.proowner::regrole::text as owner_role,
    procedure.prosecdef,
    procedure.provolatile,
    procedure.proconfig,
    pg_get_function_identity_arguments(procedure.oid) as identity_arguments,
    procedure.prorettype::regtype::text as return_type
  into strict v_function
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'get_latest_frozen_profile_v025';

  if v_function.owner_role <> 'foundation_student_executor'
     or not v_function.prosecdef
     or v_function.provolatile <> 's'
     or v_function.proconfig is distinct from
       array['search_path=pg_catalog, public, private, extensions']::text[]
     or v_function.identity_arguments <> ''
     or v_function.return_type <> 'jsonb' then
    raise exception '025 assertion failed: discovery function contract';
  end if;

  if not has_function_privilege(
    'authenticated', 'public.get_latest_frozen_profile_v025()', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.get_latest_frozen_profile_v025()', 'EXECUTE'
  ) or has_function_privilege(
    'service_role', 'public.get_latest_frozen_profile_v025()', 'EXECUTE'
  ) or has_function_privilege(
    'authenticator', 'public.get_latest_frozen_profile_v025()', 'EXECUTE'
  ) then
    raise exception '025 assertion failed: discovery function ACL';
  end if;

  if exists (
    select 1
    from information_schema.routine_privileges privilege
    where privilege.routine_schema = 'public'
      and privilege.routine_name = 'get_latest_frozen_profile_v025'
      and privilege.privilege_type = 'EXECUTE'
      and privilege.grantee not in (
        'authenticated', 'foundation_student_executor'
      )
  ) then
    raise exception '025 assertion failed: external discovery EXECUTE';
  end if;

  if not exists (
    select 1
    from public.foundation_function_contracts contract
    where contract.schema_name = 'public'
      and contract.function_name = 'get_latest_frozen_profile_v025'
      and contract.identity_arguments = ''
      and contract.owner_role = 'foundation_student_executor'
      and contract.prosecdef
      and contract.search_path =
        'pg_catalog, public, private, extensions'
      and contract.allowed_caller_roles = array['authenticated']
      and contract.body_digest ~ '^[a-f0-9]{64}$'
  ) then
    raise exception '025 assertion failed: discovery function registry';
  end if;

  if has_schema_privilege(
    'foundation_student_executor', 'auth', 'USAGE'
  ) or has_table_privilege(
    'foundation_student_executor', 'auth.users', 'SELECT'
  ) or pg_has_role(
    'foundation_student_executor', 'service_role', 'MEMBER'
  ) then
    raise exception '025 assertion failed: hosted Auth capability widened';
  end if;
end;
$assert$;

commit;
