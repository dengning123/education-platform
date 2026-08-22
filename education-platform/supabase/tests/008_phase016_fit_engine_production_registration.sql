-- PHASE 016 FIT ENGINE V0.1 PRODUCTION REGISTRATION TEST.
-- Runs after Migrations 001-016 and proves the additive registration and
-- service-only private-context projection without changing frozen semantics.

begin;

set local search_path = public, private, extensions, pg_catalog;

do $test$
declare
  v_hash constant text :=
    'e32a3ed849633a216e84dd23afae5bd60f261333c55e4c5a3c0841f6b795564e';
  v_definition text;
begin
  if (
    select count(*)
    from public.fit_evaluator_builds
    where evaluator_build_id = '30000000-0000-0000-0000-000000000164'
      and contract_release_id = '30000000-0000-0000-0000-000000000001'
      and evaluator_name = 'education-platform-fit-engine'
      and evaluator_version = '0.1.0'
      and build_hash = v_hash
      and status = 'VERIFIED'
      and verification_evidence_id =
        '30000000-0000-0000-0000-000000000163'
      and retired_at is null
  ) <> 1 then
    raise exception 'Phase 016 production evaluator registration is invalid';
  end if;

  if (
    select count(*)
    from public.fit_dimension_methods
    where contract_release_id = '30000000-0000-0000-0000-000000000001'
      and status = 'VERIFIED'
      and verification_evidence_id =
        '30000000-0000-0000-0000-000000000163'
      and retired_at is null
  ) <> 6 or exists (
    select 1
    from public.fit_dimension_methods
    where contract_release_id = '30000000-0000-0000-0000-000000000001'
      and status = 'DRAFT'
      and retired_at is null
  ) then
    raise exception 'Phase 016 requires exactly six active reviewed methods';
  end if;

  if not exists (
    select 1
    from public.sources source
    join public.evidence_items evidence using (source_id)
    where source.source_id = '30000000-0000-0000-0000-000000000162'
      and evidence.evidence_id = '30000000-0000-0000-0000-000000000163'
      and source.retrieval_content_hash = v_hash
      and evidence.content_hash = v_hash
  ) then
    raise exception 'Phase 016 review evidence is not content-addressed';
  end if;

  if pg_get_userbyid(
       (select proowner
        from pg_proc
        where oid =
          'public.get_fit_student_access_context_v016(uuid,uuid)'::regprocedure)
     ) <> 'foundation_evaluation_executor'
     or not has_function_privilege(
       'service_role',
       'public.get_fit_student_access_context_v016(uuid,uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.get_fit_student_access_context_v016(uuid,uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.get_fit_student_access_context_v016(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'Phase 016 access-context RPC privilege boundary is invalid';
  end if;

  if pg_get_userbyid(
       (select proowner
        from pg_proc
        where oid =
          'public.get_fit_evaluation_snapshot_v016(uuid,uuid,uuid,text,uuid[],uuid[],uuid[],uuid[],uuid[],uuid[],uuid[])'::regprocedure)
     ) <> 'foundation_evaluation_executor'
     or not has_function_privilege(
       'service_role',
       'public.get_fit_evaluation_snapshot_v016(uuid,uuid,uuid,text,uuid[],uuid[],uuid[],uuid[],uuid[],uuid[],uuid[])',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.get_fit_evaluation_snapshot_v016(uuid,uuid,uuid,text,uuid[],uuid[],uuid[],uuid[],uuid[],uuid[],uuid[])',
       'EXECUTE'
     )
     or has_function_privilege(
       'anon',
       'public.get_fit_evaluation_snapshot_v016(uuid,uuid,uuid,text,uuid[],uuid[],uuid[],uuid[],uuid[],uuid[],uuid[])',
       'EXECUTE'
     ) then
    raise exception 'Phase 016 bounded snapshot RPC privilege boundary is invalid';
  end if;

  if has_table_privilege('service_role', 'public.fit_contract_releases', 'SELECT')
     or has_table_privilege('service_role', 'public.student_profile_versions', 'SELECT')
     or has_table_privilege('service_role', 'public.fit_manifest_items', 'INSERT') then
    raise exception 'Phase 016 widened frozen service-role table privileges';
  end if;

  if (
    select count(*)
    from public.foundation_function_contracts contract
    join pg_proc procedure
      on procedure.proname = contract.function_name
     and pg_get_function_identity_arguments(procedure.oid) =
       contract.identity_arguments
    join pg_namespace namespace
      on namespace.oid = procedure.pronamespace
     and namespace.nspname = contract.schema_name
    where contract.schema_name = 'public'
      and contract.function_name in (
        'get_fit_student_access_context_v016',
        'get_fit_evaluation_snapshot_v016'
      )
      and contract.owner_role = 'foundation_evaluation_executor'
      and contract.prosecdef
      and contract.allowed_caller_roles = array['service_role']
      and contract.body_digest = encode(
        extensions.digest(
          convert_to(pg_get_functiondef(procedure.oid), 'UTF8'),
          'sha256'
        ),
        'hex'
      )
  ) <> 2 then
    raise exception 'Phase 016 executor functions are not contract-registered';
  end if;

  v_definition := pg_get_functiondef(
    'public.get_fit_student_access_context_v016(uuid,uuid)'::regprocedure
  );
  if v_definition not like '%intent.status = ''FROZEN''%'
     or v_definition not like '%context.profile_version_id = p_profile_version_id%'
     or v_definition like '%eligibility%'
     or v_definition like '%competitiveness%'
     or v_definition like '%score%'
     or v_definition like '%weight%'
     or v_definition like '%rank%'
     or v_definition like '%probability%' then
    raise exception 'Phase 016 access-context RPC exceeds its exact projection';
  end if;

  v_definition := pg_get_functiondef(
    'public.get_fit_evaluation_snapshot_v016(uuid,uuid,uuid,text,uuid[],uuid[],uuid[],uuid[],uuid[],uuid[],uuid[])'::regprocedure
  );
  if v_definition not like '%profile.status = ''FROZEN''%'
     or v_definition not like '%intent.status = ''FROZEN''%'
     or v_definition not like '%program_version_id = p_program_version_id%'
     or v_definition not like '%row_value.observation_id = any(coalesce%'
     or v_definition like '%EXECUTE format%'
     or v_definition like '%service_role%'
     or v_definition like '%current_user_owns_profile%' then
    raise exception 'Phase 016 source snapshot is not a static bounded projection';
  end if;
end;
$test$;

rollback;
