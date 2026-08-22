begin;

-- Phase 3 production registration is additive. Migrations 001-015 remain the
-- frozen semantic and persistence authority. This migration registers one
-- reviewed implementation of that authority; it does not introduce a score,
-- weight, rank, probability, recommendation, Eligibility interpretation, or
-- Competitiveness model.
do $registration$
declare
  v_method record;
  v_reviewed_at constant timestamptz := timestamptz '2026-08-22 00:00:00+00';
begin
  insert into public.source_identities (
    source_identity_id, canonical_publisher, current_source_id, created_at
  ) values (
    '30000000-0000-0000-0000-000000000161',
    'Education Platform Phase 3 Review',
    '30000000-0000-0000-0000-000000000162',
    v_reviewed_at
  );

  insert into public.sources (
    source_id, source_identity_id, revision_number, publisher, title, url,
    reliability_tier, source_type, retrieval_content_hash, revision_reason,
    created_at, updated_at
  ) values (
    '30000000-0000-0000-0000-000000000162',
    '30000000-0000-0000-0000-000000000161',
    1,
    'Education Platform Phase 3 Review',
    'Fit Engine v0.1 production implementation review',
    'repository://education-platform/packages/fit-engine@e32a3ed849633a216e84dd23afae5bd60f261333c55e4c5a3c0841f6b795564e',
    'TIER_A_OFFICIAL',
    'INTERNAL_OFFICIAL_REVIEW',
    'e32a3ed849633a216e84dd23afae5bd60f261333c55e4c5a3c0841f6b795564e',
    'INITIAL',
    v_reviewed_at,
    v_reviewed_at
  );

  insert into public.evidence_items (
    evidence_id, source_id, excerpt, locator, cycle_context,
    retrieved_at, verified_at, content_hash, created_at
  ) values (
    '30000000-0000-0000-0000-000000000163',
    '30000000-0000-0000-0000-000000000162',
    'The pure Fit v0.1 engine, database resolver and persistence adapter, categorical API boundary, and cross-layer release gates were reviewed against the frozen Phase 3 contract.',
    'packages/fit-engine; packages/fit-engine-adapter; supabase/functions/fit-evaluate',
    'fit-v0.1-production',
    v_reviewed_at,
    v_reviewed_at,
    'e32a3ed849633a216e84dd23afae5bd60f261333c55e4c5a3c0841f6b795564e',
    v_reviewed_at
  );

  for v_method in
    select method_id
    from public.fit_dimension_methods
    where contract_release_id = '30000000-0000-0000-0000-000000000001'
      and status = 'DRAFT'
    order by dimension
  loop
    perform public.verify_fit_definition(
      'METHOD',
      v_method.method_id,
      'Phase 3 production review',
      '30000000-0000-0000-0000-000000000163'
    );
  end loop;

  if (
    select count(*)
    from public.fit_dimension_methods
    where contract_release_id = '30000000-0000-0000-0000-000000000001'
      and status = 'VERIFIED'
      and retired_at is null
      and verification_evidence_id =
        '30000000-0000-0000-0000-000000000163'
  ) <> 6 then
    raise exception using errcode = '23514',
      message = 'Production Fit registration requires exactly six reviewed methods';
  end if;

  insert into public.fit_evaluator_builds (
    evaluator_build_id, contract_release_id, evaluator_name,
    evaluator_version, build_hash, created_at
  ) values (
    '30000000-0000-0000-0000-000000000164',
    '30000000-0000-0000-0000-000000000001',
    'education-platform-fit-engine',
    '0.1.0',
    'e32a3ed849633a216e84dd23afae5bd60f261333c55e4c5a3c0841f6b795564e',
    v_reviewed_at
  );

  perform public.verify_fit_definition(
    'EVALUATOR_BUILD',
    '30000000-0000-0000-0000-000000000164',
    'Phase 3 production review',
    '30000000-0000-0000-0000-000000000163'
  );

  -- The lifecycle API above is the sole status-transition path. Review times
  -- intentionally record the database transaction that admitted the build;
  -- the fixed source, evidence, build identity, and build hash carry semantic
  -- replay identity without rewriting VERIFIED rows.
end;
$registration$;

create or replace function public.get_fit_student_access_context_v016(
  p_profile_version_id uuid,
  p_access_context_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_result jsonb;
begin
  select jsonb_build_object(
    'access_context_id', context.access_context_id,
    'citizenship_country_code', context.citizenship_country_code,
    'residence_country_code', context.residence_country_code,
    'jurisdiction_code', context.governing_jurisdiction_code,
    'current_status_code', context.current_status_code,
    'authorization_path_code', context.authorization_path_code,
    'target_path_code', context.target_path_code
  )
  into v_result
  from private.fit_student_access_contexts context
  join public.fit_intent_sets intent
    on intent.intent_set_id = context.intent_set_id
   and intent.profile_version_id = context.profile_version_id
  where context.access_context_id = p_access_context_id
    and context.profile_version_id = p_profile_version_id
    and intent.status = 'FROZEN';

  if v_result is null then
    raise exception using errcode = 'P0002',
      message = 'Frozen Fit student access context was not found';
  end if;
  return v_result;
end;
$function$;

create or replace function public.get_fit_evaluation_snapshot_v016(
  p_profile_version_id uuid,
  p_intent_set_id uuid,
  p_program_version_id uuid,
  p_taxonomy_release_code text,
  p_observation_ids uuid[],
  p_catalog_mapping_ids uuid[],
  p_student_course_ids uuid[],
  p_student_mapping_ids uuid[],
  p_taxonomy_concept_ids uuid[],
  p_context_claim_ids uuid[],
  p_context_mapping_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $snapshot$
declare
  v_result jsonb;
  v_release_id constant uuid :=
    '30000000-0000-0000-0000-000000000001';
begin
  if not exists (
    select 1
    from public.student_profile_versions profile
    join public.fit_intent_sets intent
      on intent.profile_version_id = profile.profile_version_id
    where profile.profile_version_id = p_profile_version_id
      and profile.status = 'FROZEN'
      and profile.snapshot_hash is not null
      and intent.intent_set_id = p_intent_set_id
      and intent.status = 'FROZEN'
      and intent.snapshot_hash is not null
  ) then
    raise exception using errcode = 'P0002',
      message = 'Matching frozen Fit profile and intent snapshots were not found';
  end if;
  if not exists (
    select 1 from public.program_versions
    where program_version_id = p_program_version_id
      and retired_at is null
  ) then
    raise exception using errcode = 'P0002',
      message = 'Active program version was not found';
  end if;
  if not exists (
    select 1 from public.taxonomy_releases
    where release_code = p_taxonomy_release_code
      and status = 'VERIFIED'
      and retired_at is null
      and published_at <= now()
  ) then
    raise exception using errcode = 'P0002',
      message = 'Active verified taxonomy release was not found';
  end if;

  select jsonb_build_object(
    'fit_contract_releases', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.contract_release_id)
      from public.fit_contract_releases row_value
      where row_value.contract_release_id = v_release_id
    ), '[]'::jsonb),
    'fit_evaluator_builds', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.evaluator_build_id)
      from public.fit_evaluator_builds row_value
      where row_value.contract_release_id = v_release_id
        and row_value.evaluator_name = 'education-platform-fit-engine'
        and row_value.evaluator_version = '0.1.0'
    ), '[]'::jsonb),
    'fit_dimension_methods', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.dimension)
      from public.fit_dimension_methods row_value
      where row_value.contract_release_id = v_release_id
    ), '[]'::jsonb),
    'fit_semantic_source_classes', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.source_class_code)
      from public.fit_semantic_source_classes row_value
    ), '[]'::jsonb),
    'fit_method_source_class_policies', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.method_id, row_value.source_class_code)
      from public.fit_method_source_class_policies row_value
      join public.fit_dimension_methods method using (method_id)
      where method.contract_release_id = v_release_id
    ), '[]'::jsonb),
    'fit_method_input_policies', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.method_id, row_value.input_policy_id)
      from public.fit_method_input_policies row_value
      join public.fit_dimension_methods method using (method_id)
      where method.contract_release_id = v_release_id
    ), '[]'::jsonb),
    'fit_method_program_field_policies', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.method_id, row_value.input_policy_id, row_value.record_type, row_value.field_name)
      from public.fit_method_program_field_policies row_value
      join public.fit_dimension_methods method using (method_id)
      where method.contract_release_id = v_release_id
    ), '[]'::jsonb),
    'fit_mapping_relation_definitions', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.relation_code)
      from public.fit_mapping_relation_definitions row_value
    ), '[]'::jsonb),
    'fit_method_mapping_relation_policies', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.method_id, row_value.relation_code)
      from public.fit_method_mapping_relation_policies row_value
      join public.fit_dimension_methods method using (method_id)
      where method.contract_release_id = v_release_id
    ), '[]'::jsonb),
    'fit_signal_types', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.method_id, row_value.signal_type_id)
      from public.fit_signal_types row_value
      join public.fit_dimension_methods method using (method_id)
      where method.contract_release_id = v_release_id
    ), '[]'::jsonb),
    'fit_reason_definitions', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.reason_definition_id)
      from public.fit_reason_definitions row_value
      where row_value.contract_release_id = v_release_id
    ), '[]'::jsonb),
    'fit_financial_normalization_methods', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.normalization_method_id)
      from public.fit_financial_normalization_methods row_value
      where row_value.contract_release_id = v_release_id
    ), '[]'::jsonb),
    'student_profile_versions', coalesce((
      select jsonb_agg(to_jsonb(row_value))
      from public.student_profile_versions row_value
      where row_value.profile_version_id = p_profile_version_id
    ), '[]'::jsonb),
    'fit_intent_sets', coalesce((
      select jsonb_agg(to_jsonb(row_value))
      from public.fit_intent_sets row_value
      where row_value.intent_set_id = p_intent_set_id
    ), '[]'::jsonb),
    'fit_intent_declarations', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.dimension, row_value.intent_declaration_id)
      from public.fit_intent_declarations row_value
      where row_value.intent_set_id = p_intent_set_id
    ), '[]'::jsonb),
    'fit_intent_taxonomy_targets', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.intent_declaration_id)
      from public.fit_intent_taxonomy_targets row_value
      where row_value.intent_set_id = p_intent_set_id
    ), '[]'::jsonb),
    'fit_intent_location_constraints', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.intent_declaration_id)
      from public.fit_intent_location_constraints row_value
      where row_value.intent_set_id = p_intent_set_id
    ), '[]'::jsonb),
    'fit_intent_delivery_constraints', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.intent_declaration_id)
      from public.fit_intent_delivery_constraints row_value
      where row_value.intent_set_id = p_intent_set_id
    ), '[]'::jsonb),
    'fit_intent_financial_constraints', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.intent_declaration_id)
      from public.fit_intent_financial_constraints row_value
      where row_value.intent_set_id = p_intent_set_id
    ), '[]'::jsonb),
    'fit_intent_duration_constraints', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.intent_declaration_id)
      from public.fit_intent_duration_constraints row_value
      where row_value.intent_set_id = p_intent_set_id
    ), '[]'::jsonb),
    'fit_intent_program_feature_constraints', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.intent_declaration_id)
      from public.fit_intent_program_feature_constraints row_value
      where row_value.intent_set_id = p_intent_set_id
    ), '[]'::jsonb),
    'student_goals', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.student_goal_id)
      from public.student_goals row_value
      where row_value.profile_version_id = p_profile_version_id
        and row_value.student_goal_id in (
          select source_student_goal_id
          from public.fit_intent_declarations
          where intent_set_id = p_intent_set_id
            and source_student_goal_id is not null
        )
    ), '[]'::jsonb),
    'student_preferences', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.student_preference_id)
      from public.student_preferences row_value
      where row_value.profile_version_id = p_profile_version_id
        and row_value.student_preference_id in (
          select source_student_preference_id
          from public.fit_intent_declarations
          where intent_set_id = p_intent_set_id
            and source_student_preference_id is not null
        )
    ), '[]'::jsonb),
    'student_courses', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.student_course_id)
      from public.student_courses row_value
      where row_value.profile_version_id = p_profile_version_id
        and row_value.student_course_id = any(coalesce(p_student_course_ids, '{}'::uuid[]))
    ), '[]'::jsonb),
    'student_record_concept_mappings', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.student_mapping_id)
      from public.student_record_concept_mappings row_value
      where row_value.profile_version_id = p_profile_version_id
        and row_value.student_mapping_id = any(coalesce(p_student_mapping_ids, '{}'::uuid[]))
    ), '[]'::jsonb),
    'program_courses', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.course_id)
      from public.program_courses row_value
      where row_value.program_version_id = p_program_version_id
        and row_value.retired_at is null
    ), '[]'::jsonb),
    'program_costs', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.cost_id)
      from public.program_costs row_value
      where row_value.program_version_id = p_program_version_id
        and row_value.retired_at is null
    ), '[]'::jsonb),
    'field_observations', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.observation_id)
      from public.field_observations row_value
      where row_value.observation_id = any(coalesce(p_observation_ids, '{}'::uuid[]))
    ), '[]'::jsonb),
    'canonical_field_selections', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.observation_id)
      from public.canonical_field_selections row_value
      where row_value.observation_id = any(coalesce(p_observation_ids, '{}'::uuid[]))
    ), '[]'::jsonb),
    'catalog_concept_mappings', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.mapping_id)
      from public.catalog_concept_mappings row_value
      where row_value.mapping_id = any(coalesce(p_catalog_mapping_ids, '{}'::uuid[]))
    ), '[]'::jsonb),
    'taxonomy_concepts', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.concept_id)
      from public.taxonomy_concepts row_value
      where row_value.concept_id = any(coalesce(p_taxonomy_concept_ids, '{}'::uuid[]))
    ), '[]'::jsonb),
    'taxonomy_releases', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.release_ordinal)
      from public.taxonomy_releases row_value
    ), '[]'::jsonb),
    'fit_context_claims', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.context_claim_id)
      from public.fit_context_claims row_value
      where row_value.context_claim_id = any(coalesce(p_context_claim_ids, '{}'::uuid[]))
         or row_value.context_claim_id in (
           select context_claim_id
           from public.fit_context_concept_mappings
           where context_mapping_id = any(coalesce(p_context_mapping_ids, '{}'::uuid[]))
         )
    ), '[]'::jsonb),
    'fit_context_claim_definitions', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.claim_definition_id)
      from public.fit_context_claim_definitions row_value
    ), '[]'::jsonb),
    'fit_context_claim_selections', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.context_claim_id)
      from public.fit_context_claim_selections row_value
      where row_value.context_claim_id = any(coalesce(p_context_claim_ids, '{}'::uuid[]))
         or row_value.context_claim_id in (
           select context_claim_id
           from public.fit_context_concept_mappings
           where context_mapping_id = any(coalesce(p_context_mapping_ids, '{}'::uuid[]))
         )
    ), '[]'::jsonb),
    'fit_context_claim_observations', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.context_observation_id)
      from public.fit_context_claim_observations row_value
      where row_value.context_observation_id in (
        select selection.context_observation_id
        from public.fit_context_claim_selections selection
        where (
          selection.context_claim_id = any(coalesce(p_context_claim_ids, '{}'::uuid[]))
          or selection.context_claim_id in (
            select context_claim_id
            from public.fit_context_concept_mappings
            where context_mapping_id = any(coalesce(p_context_mapping_ids, '{}'::uuid[]))
          )
        ) and selection.context_observation_id is not null
      )
    ), '[]'::jsonb),
    'fit_context_concept_mappings', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.context_mapping_id)
      from public.fit_context_concept_mappings row_value
      where row_value.context_mapping_id = any(coalesce(p_context_mapping_ids, '{}'::uuid[]))
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$snapshot$;

-- Match the frozen 014/015 non-super runner contract: ownership transfer
-- requires the target role to hold CREATE on the containing schema only for
-- the duration of this transaction.
grant create on schema public to foundation_evaluation_executor;

alter function public.get_fit_student_access_context_v016(uuid, uuid)
  owner to foundation_evaluation_executor;
alter function public.get_fit_evaluation_snapshot_v016(
  uuid, uuid, uuid, text, uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]
) owner to foundation_evaluation_executor;

revoke create on schema public from foundation_evaluation_executor;

revoke all on function public.get_fit_student_access_context_v016(uuid, uuid)
from public, anon, authenticated, service_role,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
revoke all on function public.get_fit_evaluation_snapshot_v016(
  uuid, uuid, uuid, text, uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]
) from public, anon, authenticated, service_role,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant execute on function public.get_fit_student_access_context_v016(uuid, uuid)
to service_role;
grant execute on function public.get_fit_evaluation_snapshot_v016(
  uuid, uuid, uuid, text, uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]
) to service_role;

do $contracts$
declare
  v_function record;
begin
  for v_function in
    select
      namespace.nspname,
      procedure.proname,
      pg_get_function_identity_arguments(procedure.oid) as identity_arguments,
      pg_get_functiondef(procedure.oid) as definition
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'get_fit_student_access_context_v016',
        'get_fit_evaluation_snapshot_v016'
      )
  loop
    insert into public.foundation_function_contracts (
      schema_name, function_name, identity_arguments, owner_role, prosecdef,
      search_path, allowed_caller_roles, body_digest
    ) values (
      v_function.nspname,
      v_function.proname,
      v_function.identity_arguments,
      'foundation_evaluation_executor',
      true,
      'pg_catalog, public, private, extensions',
      array['service_role'],
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

comment on function public.get_fit_student_access_context_v016(uuid, uuid) is
  'Service-only exact projection of one frozen Fit access-context row. It performs no inference and exposes no Eligibility or Competitiveness semantics.';

comment on function public.get_fit_evaluation_snapshot_v016(
  uuid, uuid, uuid, text, uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]
) is
  'Service-only bounded source projection for one frozen Fit request. It performs no scoring or inference and grants no runtime table access.';

commit;
