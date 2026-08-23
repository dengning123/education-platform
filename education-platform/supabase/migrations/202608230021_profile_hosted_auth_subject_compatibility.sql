-- Phase 4B: hosted Auth subject compatibility for the frozen Profile 019/020
-- capabilities. This migration changes only the execution boundary used to
-- derive the authenticated request subject. It does not change Profile
-- identity, ownership, DTO, mutation, revision, freeze, or fork semantics.

begin;

-- PostgREST installs verified JWT claims as transaction-local request
-- settings. Keep their extraction in one project-owned, no-argument bridge
-- rather than depending on a project executor receiving privileges inside the
-- Supabase-managed auth schema.
create or replace function private.profile_request_auth_subject_v021()
returns uuid
language sql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $function$
  select coalesce(
    nullif(pg_catalog.current_setting('request.jwt.claim.sub', true), ''),
    pg_catalog.jsonb_extract_path_text(
      nullif(
        pg_catalog.current_setting('request.jwt.claims', true),
        ''
      )::pg_catalog.jsonb,
      'sub'
    )
  )::pg_catalog.uuid
$function$;

-- Preserve the frozen v019 missing-subject behavior while replacing only the
-- inaccessible auth.uid() execution path.
create or replace function private.profile_require_auth_subject_v019()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_auth_user_id uuid;
begin
  v_auth_user_id := private.profile_request_auth_subject_v021();
  if v_auth_user_id is null then
    raise exception using errcode = '42501', message = 'PROFILE_AUTH_REQUIRED';
  end if;
  return v_auth_user_id;
end;
$function$;

-- Preserve the frozen v019 no-row behavior when no authenticated subject is
-- available. Ownership still resolves only through private.student_identities.
create or replace function private.profile_student_for_auth_v019()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  select identity.student_id
  from private.student_identities identity
  join public.students student using (student_id)
  where identity.auth_user_id = private.profile_request_auth_subject_v021()
    and student.privacy_state = 'ACTIVE'
$function$;

-- The standalone PostgreSQL test bootstrap made the v019 Auth grants
-- effective because its auth schema/function are installer-owned. Remove only
-- those custom-role grants when the installer is authorized to do so. On a
-- real Supabase stack they were never granted; the postconditions below are
-- authoritative and turn any ineffective warning into a hard failure.
do $remove_legacy_auth_grants$
declare
  v_executor oid := 'foundation_student_executor'::regrole::oid;
  v_uid oid := to_regprocedure('auth.uid()');
begin
  if pg_catalog.has_schema_privilege(
    'foundation_student_executor', 'auth', 'USAGE'
  ) then
    execute 'revoke usage on schema auth from foundation_student_executor';
  end if;

  if v_uid is not null and exists (
    select 1
    from pg_proc procedure
    cross join lateral aclexplode(
      coalesce(
        procedure.proacl,
        acldefault('f', procedure.proowner)
      )
    ) privilege
    where procedure.oid = v_uid
      and privilege.grantee = v_executor
      and privilege.privilege_type = 'EXECUTE'
  ) then
    execute 'revoke execute on function auth.uid() from foundation_student_executor';
  end if;
end;
$remove_legacy_auth_grants$;

grant create on schema private to foundation_student_executor;
alter function private.profile_request_auth_subject_v021()
  owner to foundation_student_executor;
revoke create on schema private from foundation_student_executor;

revoke all on function private.profile_request_auth_subject_v021()
  from public, anon, authenticated, service_role, authenticator,
       foundation_catalog_executor, foundation_student_executor,
       foundation_evaluation_executor;
grant execute on function private.profile_request_auth_subject_v021()
  to foundation_student_executor;

-- CREATE OR REPLACE retains the v019 ACLs, but converge them explicitly so a
-- partially drifted local database cannot pass this compatibility migration.
revoke all on function private.profile_require_auth_subject_v019()
  from public, anon, authenticated, service_role, authenticator,
       foundation_catalog_executor, foundation_student_executor,
       foundation_evaluation_executor;
revoke all on function private.profile_student_for_auth_v019()
  from public, anon, authenticated, service_role, authenticator,
       foundation_catalog_executor, foundation_student_executor,
       foundation_evaluation_executor;
grant execute on function private.profile_require_auth_subject_v019(),
  private.profile_student_for_auth_v019()
  to foundation_student_executor;

do $contracts$
declare
  v_function record;
begin
  for v_function in
    select namespace.nspname,
      procedure.proname,
      pg_get_function_identity_arguments(procedure.oid) as identity_arguments,
      procedure.proowner::regrole::text as owner_role,
      procedure.prosecdef,
      pg_get_functiondef(procedure.oid) as definition
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'private'
      and procedure.proname in (
        'profile_request_auth_subject_v021',
        'profile_require_auth_subject_v019',
        'profile_student_for_auth_v019'
      )
  loop
    insert into public.foundation_function_contracts (
      schema_name, function_name, identity_arguments, owner_role, prosecdef,
      search_path, allowed_caller_roles, body_digest
    ) values (
      v_function.nspname,
      v_function.proname,
      v_function.identity_arguments,
      v_function.owner_role,
      v_function.prosecdef,
      'pg_catalog, public, private, extensions',
      array['foundation_student_executor'],
      encode(
        extensions.digest(
          convert_to(v_function.definition, 'UTF8'),
          'sha256'
        ),
        'hex'
      )
    )
    on conflict (schema_name, function_name, identity_arguments) do update
      set owner_role = excluded.owner_role,
          prosecdef = excluded.prosecdef,
          search_path = excluded.search_path,
          allowed_caller_roles = excluded.allowed_caller_roles,
          body_digest = excluded.body_digest;
  end loop;
end;
$contracts$;

comment on function private.profile_request_auth_subject_v021() is
  'No-argument Profile subject bridge over PostgREST verified request JWT settings. Returns the same UUID/null subject shape as auth.uid() without requiring project-role access to the Supabase-managed auth schema.';

do $assert$
declare
  v_bridge oid := to_regprocedure(
    'private.profile_request_auth_subject_v021()'
  );
  v_require oid := to_regprocedure(
    'private.profile_require_auth_subject_v019()'
  );
  v_lookup oid := to_regprocedure(
    'private.profile_student_for_auth_v019()'
  );
  v_definition text;
begin
  if v_bridge is null or v_require is null or v_lookup is null then
    raise exception '021 assertion failed: subject function missing';
  end if;

  select pg_get_functiondef(v_bridge) into v_definition;
  if not exists (
    select 1
    from pg_proc procedure
    where procedure.oid = v_bridge
      and procedure.proowner::regrole::text = 'foundation_student_executor'
      and not procedure.prosecdef
      and procedure.provolatile = 's'
      and procedure.pronargs = 0
      and procedure.proconfig is not distinct from
        array['search_path=pg_catalog, public, private, extensions']::text[]
  ) or position('request.jwt.claim.sub' in v_definition) = 0
     or position('request.jwt.claims' in v_definition) = 0
     or position('auth.' in lower(v_definition)) <> 0 then
    raise exception '021 assertion failed: subject bridge contract';
  end if;

  if exists (
    select 1
    from pg_proc procedure
    where procedure.oid in (v_require, v_lookup)
      and (
        procedure.proowner::regrole::text <> 'foundation_student_executor'
        or not procedure.prosecdef
        or procedure.provolatile <> 's'
        or procedure.proconfig is distinct from
          array['search_path=pg_catalog, public, private, extensions']::text[]
        or position(
          'private.profile_request_auth_subject_v021()'
          in pg_get_functiondef(procedure.oid)
        ) = 0
        or position('auth.uid' in lower(pg_get_functiondef(procedure.oid))) <> 0
      )
  ) then
    raise exception '021 assertion failed: v019 subject helper convergence';
  end if;

  if not has_function_privilege(
    'foundation_student_executor', v_bridge, 'EXECUTE'
  ) or not has_function_privilege(
    'foundation_student_executor', v_require, 'EXECUTE'
  ) or not has_function_privilege(
    'foundation_student_executor', v_lookup, 'EXECUTE'
  ) or exists (
    select 1
    from information_schema.routine_privileges privilege
    where privilege.routine_schema = 'private'
      and privilege.routine_name in (
        'profile_request_auth_subject_v021',
        'profile_require_auth_subject_v019',
        'profile_student_for_auth_v019'
      )
      and privilege.privilege_type = 'EXECUTE'
      and privilege.grantee <> 'foundation_student_executor'
  ) then
    raise exception '021 assertion failed: subject helper ACL';
  end if;

  if has_schema_privilege(
    'foundation_student_executor', 'auth', 'USAGE'
  ) or has_schema_privilege(
    'foundation_student_executor', 'auth', 'CREATE'
  ) or has_table_privilege(
    'foundation_student_executor', 'auth.users',
    'SELECT,INSERT,UPDATE,DELETE'
  ) or pg_has_role(
    'foundation_student_executor', 'service_role', 'MEMBER'
  ) then
    raise exception '021 assertion failed: hosted Auth privilege expansion';
  end if;

  if not exists (
    select 1
    from public.foundation_function_contracts contract
    where contract.schema_name = 'private'
      and contract.function_name = 'profile_request_auth_subject_v021'
      and contract.identity_arguments = ''
      and contract.owner_role = 'foundation_student_executor'
      and not contract.prosecdef
      and contract.search_path =
        'pg_catalog, public, private, extensions'
      and contract.allowed_caller_roles =
        array['foundation_student_executor']
      and contract.body_digest ~ '^[a-f0-9]{64}$'
  ) or (
    select count(*)
    from public.foundation_function_contracts contract
    where contract.schema_name = 'private'
      and contract.function_name in (
        'profile_require_auth_subject_v019',
        'profile_student_for_auth_v019'
      )
      and contract.owner_role = 'foundation_student_executor'
      and contract.prosecdef
      and contract.search_path =
        'pg_catalog, public, private, extensions'
      and contract.allowed_caller_roles =
        array['foundation_student_executor']
      and contract.body_digest ~ '^[a-f0-9]{64}$'
  ) <> 2 then
    raise exception '021 assertion failed: function registry contract';
  end if;
end;
$assert$;

commit;
