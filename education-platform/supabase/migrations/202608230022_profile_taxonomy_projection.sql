-- Phase 4B-1B.2B-3: owner-scoped, release-aware Profile taxonomy labels.
-- Additive over Migrations 001-021. Application/Outcome remains planning-only
-- under a provisional future Migration 023 identity.

begin;

create or replace function public.get_profile_taxonomy_projection_v022(
  p_profile_version_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_profile_id uuid;
  v_release_code text;
  v_release_ordinal bigint;
begin
  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;

  if p_profile_version_id is null then
    select profile.profile_version_id
    into v_profile_id
    from public.student_profile_versions profile
    where profile.student_id = v_student_id
      and profile.product_managed
      and profile.status = 'DRAFT'
    order by profile.version_number desc
    limit 1;
  else
    select profile.profile_version_id
    into v_profile_id
    from public.student_profile_versions profile
    where profile.profile_version_id = p_profile_version_id
      and profile.student_id = v_student_id;
  end if;

  if v_profile_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;

  select release.release_code, release.release_ordinal
  into v_release_code, v_release_ordinal
  from public.taxonomy_releases release
  where release.status = 'VERIFIED'
  order by release.release_ordinal desc, release.release_code desc
  limit 1;

  if v_release_code is null or v_release_ordinal is null then
    raise exception using errcode = '55000',
      message = 'TAXONOMY_VERIFIED_RELEASE_NOT_FOUND';
  end if;

  return jsonb_build_object(
    'schemaVersion', 'PROFILE_TAXONOMY_PROJECTION_V022',
    'releaseCode', v_release_code,
    'releaseOrdinal', v_release_ordinal,
    'concepts', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'conceptId', projected.concept_id,
          'canonicalKey', projected.canonical_key,
          'conceptKind', projected.concept_kind,
          'displayName', projected.display_name,
          'activeAtRelease',
            projected.introduced_release_ordinal <= v_release_ordinal
            and (
              projected.retired_release_ordinal is null
              or projected.retired_release_ordinal > v_release_ordinal
            )
        )
        order by projected.canonical_key, projected.concept_id
      )
      from (
        select distinct
          concept.concept_id,
          concept.canonical_key,
          concept.concept_kind,
          concept.display_name,
          concept.introduced_release_ordinal,
          concept.retired_release_ordinal
        from public.student_record_concept_mappings mapping
        join public.taxonomy_concepts concept
          on concept.concept_id = mapping.concept_id
        where mapping.profile_version_id = v_profile_id
          and concept.concept_kind in ('FIELD', 'SUBFIELD', 'COURSE_CONCEPT')
      ) projected
    ), '[]'::jsonb)
  );
end;
$function$;

grant create on schema public to foundation_student_executor;
alter function public.get_profile_taxonomy_projection_v022(uuid)
  owner to foundation_student_executor;
revoke create on schema public from foundation_student_executor;

revoke all on function public.get_profile_taxonomy_projection_v022(uuid)
  from public, anon, authenticated, service_role, authenticator,
       foundation_catalog_executor, foundation_student_executor,
       foundation_evaluation_executor;
grant execute on function public.get_profile_taxonomy_projection_v022(uuid)
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
    and procedure.proname = 'get_profile_taxonomy_projection_v022';

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
      extensions.digest(convert_to(v_function.definition, 'UTF8'), 'sha256'),
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

comment on function public.get_profile_taxonomy_projection_v022(uuid) is
  'Projects labels only for FIELD, SUBFIELD, and COURSE_CONCEPT IDs referenced by one authenticated owner Profile, pinned to the highest VERIFIED taxonomy release.';

do $assert$
declare
  v_function_oid oid;
begin
  select procedure.oid
  into strict v_function_oid
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'get_profile_taxonomy_projection_v022'
    and pg_get_function_identity_arguments(procedure.oid) =
      'p_profile_version_id uuid';

  if not exists (
    select 1
    from pg_proc procedure
    where procedure.oid = v_function_oid
      and procedure.proowner::regrole::text = 'foundation_student_executor'
      and procedure.prosecdef
      and procedure.provolatile = 's'
      and procedure.pronargdefaults = 1
      and procedure.proconfig is not distinct from
        array['search_path=pg_catalog, public, private, extensions']::text[]
  ) then
    raise exception '022 assertion failed: projection function contract';
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
  ) then
    raise exception '022 assertion failed: projection function ACL';
  end if;

  if not exists (
    select 1
    from public.foundation_function_contracts contract
    where contract.schema_name = 'public'
      and contract.function_name = 'get_profile_taxonomy_projection_v022'
      and contract.identity_arguments = 'p_profile_version_id uuid'
      and contract.owner_role = 'foundation_student_executor'
      and contract.prosecdef
      and contract.search_path =
        'pg_catalog, public, private, extensions'
      and contract.allowed_caller_roles = array['authenticated']
      and contract.body_digest ~ '^[a-f0-9]{64}$'
  ) then
    raise exception '022 assertion failed: function registry contract';
  end if;
end;
$assert$;

commit;
