-- Phase 4B-1B.2B-4: bounded, release-aware Profile taxonomy options.
-- Additive over Migrations 001-022. Application/Outcome remains planning-only
-- under a provisional future Migration 024 identity.

begin;

create or replace function public.get_profile_taxonomy_options_v023(
  p_concept_kind text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_release_code text;
  v_release_ordinal bigint;
  v_option_count bigint;
  v_oversized boolean;
  v_max_options constant integer := 64;
  v_max_canonical_key_bytes constant integer := 128;
  v_max_display_name_bytes constant integer := 256;
begin
  if p_concept_kind is null
     or p_concept_kind not in ('ASSESSMENT', 'SKILL') then
    raise exception using errcode = '22023',
      message = 'PROFILE_TAXONOMY_KIND_NOT_ALLOWED';
  end if;

  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;

  select release.release_code, release.release_ordinal
  into v_release_code, v_release_ordinal
  from public.taxonomy_releases release
  where release.status = 'VERIFIED'
  order by release.release_ordinal desc, release.release_code collate "C" desc
  limit 1;

  if v_release_code is null or v_release_ordinal is null then
    raise exception using errcode = '55000',
      message = 'TAXONOMY_VERIFIED_RELEASE_NOT_FOUND';
  end if;

  if pg_catalog.octet_length(v_release_code) > 32 then
    raise exception using errcode = '54000',
      message = 'PROFILE_TAXONOMY_OPTION_VALUE_TOO_LONG';
  end if;

  select count(*),
    coalesce(bool_or(
      pg_catalog.octet_length(concept.canonical_key) >
        v_max_canonical_key_bytes
      or pg_catalog.octet_length(concept.display_name) >
        v_max_display_name_bytes
    ), false)
  into v_option_count, v_oversized
  from public.taxonomy_concepts concept
  where concept.concept_kind::text = p_concept_kind
    and concept.introduced_release_ordinal <= v_release_ordinal
    and (
      concept.retired_release_ordinal is null
      or concept.retired_release_ordinal > v_release_ordinal
    );

  if v_option_count > v_max_options then
    raise exception using errcode = '54000',
      message = 'PROFILE_TAXONOMY_OPTION_LIMIT_EXCEEDED';
  end if;
  if v_oversized then
    raise exception using errcode = '54000',
      message = 'PROFILE_TAXONOMY_OPTION_VALUE_TOO_LONG';
  end if;

  return jsonb_build_object(
    'schemaVersion', 'PROFILE_TAXONOMY_OPTIONS_V023',
    'releaseCode', v_release_code,
    'releaseOrdinal', v_release_ordinal,
    'conceptKind', p_concept_kind,
    'options', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'conceptId', concept.concept_id,
          'canonicalKey', concept.canonical_key,
          'displayName', concept.display_name
        )
        order by concept.canonical_key collate "C", concept.concept_id
      )
      from public.taxonomy_concepts concept
      where concept.concept_kind::text = p_concept_kind
        and concept.introduced_release_ordinal <= v_release_ordinal
        and (
          concept.retired_release_ordinal is null
          or concept.retired_release_ordinal > v_release_ordinal
        )
    ), '[]'::jsonb)
  );
end;
$function$;

grant create on schema public to foundation_student_executor;
alter function public.get_profile_taxonomy_options_v023(text)
  owner to foundation_student_executor;
revoke create on schema public from foundation_student_executor;

revoke all on function public.get_profile_taxonomy_options_v023(text)
  from public, anon, authenticated, service_role, authenticator,
       foundation_catalog_executor, foundation_student_executor,
       foundation_evaluation_executor;
grant execute on function public.get_profile_taxonomy_options_v023(text)
  to authenticated;

do $contracts$
declare
  v_function record;
begin
  select namespace.nspname,
    procedure.proname,
    pg_get_function_identity_arguments(procedure.oid) as identity_arguments,
    procedure.proowner::regrole::text as owner_role,
    procedure.prosecdef,
    pg_get_functiondef(procedure.oid) as definition
  into strict v_function
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'get_profile_taxonomy_options_v023';

  insert into public.foundation_function_contracts (
    schema_name, function_name, identity_arguments, owner_role, prosecdef,
    search_path, allowed_caller_roles, body_digest
  ) values (
    v_function.nspname, v_function.proname,
    v_function.identity_arguments, v_function.owner_role,
    v_function.prosecdef,
    'pg_catalog, public, private, extensions',
    array['authenticated'],
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
end;
$contracts$;

comment on function public.get_profile_taxonomy_options_v023(text) is
  'Lists at most 64 active ASSESSMENT or SKILL options from the highest VERIFIED taxonomy release for one trusted authenticated Profile subject.';

do $assert$
declare
  v_function_oid oid;
begin
  select procedure.oid
  into strict v_function_oid
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'get_profile_taxonomy_options_v023'
    and pg_get_function_identity_arguments(procedure.oid) =
      'p_concept_kind text';

  if not exists (
    select 1
    from pg_proc procedure
    where procedure.oid = v_function_oid
      and procedure.proowner::regrole::text = 'foundation_student_executor'
      and procedure.prosecdef
      and procedure.provolatile = 's'
      and procedure.pronargs = 1
      and procedure.pronargdefaults = 0
      and procedure.proconfig is not distinct from
        array['search_path=pg_catalog, public, private, extensions']::text[]
  ) then
    raise exception '023 assertion failed: options function contract';
  end if;

  if not has_function_privilege(
    'authenticated', v_function_oid, 'EXECUTE'
  ) or has_function_privilege(
    'anon', v_function_oid, 'EXECUTE'
  ) or has_function_privilege(
    'service_role', v_function_oid, 'EXECUTE'
  ) or has_function_privilege(
    'authenticator', v_function_oid, 'EXECUTE'
  ) or has_function_privilege(
    'foundation_catalog_executor', v_function_oid, 'EXECUTE'
  ) or has_function_privilege(
    'foundation_evaluation_executor', v_function_oid, 'EXECUTE'
  ) or exists (
    select 1
    from pg_proc procedure
    cross join lateral aclexplode(
      coalesce(
        procedure.proacl,
        acldefault('f', procedure.proowner)
      )
    ) privilege
    where procedure.oid = v_function_oid
      and privilege.grantee = 0
      and privilege.privilege_type = 'EXECUTE'
  ) then
    raise exception '023 assertion failed: options function ACL';
  end if;

  if has_table_privilege(
    'authenticated', 'public.taxonomy_releases', 'SELECT'
  ) or has_table_privilege(
    'authenticated', 'public.taxonomy_concepts', 'SELECT'
  ) or has_table_privilege(
    'authenticated', 'public.taxonomy_aliases', 'SELECT'
  ) or has_table_privilege(
    'authenticated', 'public.taxonomy_relationships', 'SELECT'
  ) then
    raise exception '023 assertion failed: direct taxonomy table access';
  end if;

  if not exists (
    select 1
    from public.foundation_function_contracts contract
    where contract.schema_name = 'public'
      and contract.function_name = 'get_profile_taxonomy_options_v023'
      and contract.identity_arguments = 'p_concept_kind text'
      and contract.owner_role = 'foundation_student_executor'
      and contract.prosecdef
      and contract.search_path =
        'pg_catalog, public, private, extensions'
      and contract.allowed_caller_roles = array['authenticated']
      and contract.body_digest ~ '^[a-f0-9]{64}$'
  ) then
    raise exception '023 assertion failed: function registry contract';
  end if;
end;
$assert$;

commit;
