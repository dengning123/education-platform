-- Phase 4B: authenticated, owner-scoped Eligibility v0.2 production assembly.
--
-- This additive capability does not change Eligibility truth semantics. It
-- assembles the exact frozen M013 inputs inside one database transaction,
-- invokes the frozen start/pin/seal/finalize primitives, and returns a bounded
-- projection. Browser and Next.js callers never receive authority-table access.

begin;

create table private.eligibility_assembly_operations_v026 (
  operation_id uuid primary key,
  profile_version_id uuid not null,
  program_version_id uuid not null
    references public.program_versions(program_version_id) on delete restrict,
  evaluation_id uuid not null unique
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  created_at timestamptz not null default now(),
  foreign key (evaluation_id, profile_version_id)
    references public.eligibility_evaluations(evaluation_id, profile_version_id)
    on delete cascade
);

revoke all on table private.eligibility_assembly_operations_v026
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor;

-- The M026 executor needs only ProgramVersion existence, in addition to the
-- catalog/profile authority already granted by M013. No external role gains
-- table access and no ProgramVersion write capability is added.
grant select, update on table public.program_versions
to foundation_evaluation_executor;
drop policy if exists program_versions_evaluation_executor_v026
on public.program_versions;
create policy program_versions_evaluation_executor_v026
on public.program_versions
for select to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor');
drop policy if exists program_versions_evaluation_executor_lock_v026
on public.program_versions;
create policy program_versions_evaluation_executor_lock_v026
on public.program_versions
for update to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (false);

create or replace function private.project_eligibility_assembly_v026(
  p_evaluation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_evaluation public.eligibility_evaluations%rowtype;
  v_program_version_id uuid;
  v_requirements jsonb := '[]'::jsonb;
  v_missing_codes jsonb;
  v_requirement record;
begin
  select * into v_evaluation
  from public.eligibility_evaluations evaluation
  where evaluation.evaluation_id = p_evaluation_id;
  select rule_set.program_version_id into v_program_version_id
  from public.program_requirement_rule_sets rule_set
  where rule_set.rule_set_id = v_evaluation.rule_set_id;

  if not found
     or v_evaluation.evaluation_state is distinct from 'COMPLETED'
     or v_evaluation.input_schema_version is distinct from 'eligibility-v0.2'
     or v_evaluation.input_fingerprint !~ '^[a-f0-9]{64}$'
     or v_evaluation.result_fingerprint !~ '^[a-f0-9]{64}$'
     or v_evaluation.outcome is null
     or v_evaluation.root_truth_value is null then
    raise exception using errcode = 'P0001', message = 'INTERNAL_ERROR';
  end if;

  if (select count(*) from public.eligibility_requirement_results
      where evaluation_id = p_evaluation_id) > 256 then
    raise exception using errcode = 'P0001', message = 'INTERNAL_ERROR';
  end if;

  for v_requirement in
    select result.rule_node_id,
      result.truth_value,
      result.reason_codes,
      result.explanation,
      result.supporting_fact_refs,
      result.missing_data
    from public.eligibility_requirement_results result
    where result.evaluation_id = p_evaluation_id
    order by result.rule_node_id
  loop
    if cardinality(v_requirement.reason_codes) > 256
       or exists (
         select 1 from unnest(v_requirement.reason_codes) code
         where code is null or code = '' or length(code) > 96
       )
       or length(v_requirement.explanation) > 2000
       or jsonb_typeof(v_requirement.supporting_fact_refs) is distinct from 'array'
       or jsonb_array_length(v_requirement.supporting_fact_refs) > 256
       or jsonb_typeof(v_requirement.missing_data) is distinct from 'array'
       or jsonb_array_length(v_requirement.missing_data) > 256
       or exists (
         select 1
         from jsonb_array_elements(v_requirement.missing_data) item
         where jsonb_typeof(item) is distinct from 'object'
            or (select array_agg(key order by key) from jsonb_object_keys(item) key)
               is distinct from array['code']::text[]
            or jsonb_typeof(item -> 'code') is distinct from 'string'
            or length(item ->> 'code') not between 1 and 96
       ) then
      raise exception using errcode = 'P0001', message = 'INTERNAL_ERROR';
    end if;

    select coalesce(jsonb_agg(item ->> 'code' order by ordinal), '[]'::jsonb)
    into v_missing_codes
    from jsonb_array_elements(v_requirement.missing_data)
      with ordinality as missing(item, ordinal);

    v_requirements := v_requirements || jsonb_build_array(jsonb_build_object(
      'id', v_requirement.rule_node_id,
      'truth', v_requirement.truth_value,
      'reasonCodes', to_jsonb(v_requirement.reason_codes),
      'explanation', v_requirement.explanation,
      'missingDataCodes', v_missing_codes,
      'supportingReferenceCount', jsonb_array_length(v_requirement.supporting_fact_refs)
    ));
  end loop;

  return jsonb_build_object(
    'schemaVersion', 'ELIGIBILITY_PRODUCTION_ASSEMBLY_V026',
    'evalId', v_evaluation.evaluation_id,
    'profileId', v_evaluation.profile_version_id,
    'programId', v_program_version_id,
    'status', v_evaluation.outcome,
    'rootTruth', v_evaluation.root_truth_value,
    'requirements', v_requirements,
    'inputFingerprint', v_evaluation.input_fingerprint,
    'resultFingerprint', v_evaluation.result_fingerprint
  );
end;
$function$;

create or replace function public.assemble_eligibility_evaluation_v026(
  p_profile_version_id uuid,
  p_program_version_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_auth_student_id uuid;
  v_profile public.student_profile_versions%rowtype;
  v_operation private.eligibility_assembly_operations_v026%rowtype;
  v_rule_set public.program_requirement_rule_sets%rowtype;
  v_rule_set_id uuid;
  v_rule_set_count integer;
  v_evaluation_id uuid;
  v_taxonomy_release_ordinal bigint;
  v_scope_id uuid;
  v_scope_kind public.eligibility_snapshot_scope_kind;
  v_has_degree boolean;
  v_source_id uuid;
  v_source_identity_id uuid;
  v_source_revision_number integer;
  v_retrieval_content_hash text;
  v_evidence_id uuid;
  v_applicability_assertion_id uuid;
  v_applicability_scope_id uuid;
  v_program_scope_key text;
  v_program_version_scope_key text;
  v_granularity_scope public.applicability_granularity_scope;
  v_population_scope_code public.applicability_population_scope;
  v_cycle_scope_code text;
  v_selection public.canonical_field_selections%rowtype;
  v_row record;
  v_error text;
  v_allowed_errors constant text[] := array[
    'AUTH_REQUIRED',
    'ACCESS_DENIED',
    'PROFILE_NOT_FOUND',
    'PROFILE_NOT_FROZEN',
    'PROGRAM_NOT_FOUND',
    'ELIGIBILITY_RULESET_NOT_FOUND',
    'ELIGIBILITY_RULESET_AMBIGUOUS',
    'ELIGIBILITY_INPUT_INVALID',
    'ELIGIBILITY_ASSEMBLY_CONFLICT',
    'REQUEST_TIMEOUT',
    'INTERNAL_ERROR'
  ];
begin
  if p_profile_version_id is null
     or p_program_version_id is null
     or p_operation_id is null then
    raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
  end if;

  -- A global operation lock makes exact retry and conflicting replay stable.
  perform pg_advisory_xact_lock(
    hashtextextended('eligibility-v026-operation:' || p_operation_id::text, 0)
  );

  select * into v_operation
  from private.eligibility_assembly_operations_v026 operation
  where operation.operation_id = p_operation_id
  for update;

  if found then
    if v_operation.profile_version_id is distinct from p_profile_version_id
       or v_operation.program_version_id is distinct from p_program_version_id then
      raise exception using errcode = 'P0001', message = 'ELIGIBILITY_ASSEMBLY_CONFLICT';
    end if;
    v_auth_student_id := private.profile_student_for_auth_v019();
    if v_auth_student_id is null or not exists (
      select 1
      from public.student_profile_versions profile
      where profile.profile_version_id = p_profile_version_id
        and profile.student_id = v_auth_student_id
    ) then
      raise exception using errcode = 'P0001', message = 'PROFILE_NOT_FOUND';
    end if;
    return private.project_eligibility_assembly_v026(v_operation.evaluation_id);
  end if;

  if private.profile_request_auth_subject_v021() is null then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;
  v_auth_student_id := private.profile_student_for_auth_v019();
  if v_auth_student_id is null then
    raise exception using errcode = 'P0001', message = 'PROFILE_NOT_FOUND';
  end if;

  select * into v_profile
  from public.student_profile_versions profile
  where profile.profile_version_id = p_profile_version_id
    and profile.student_id = v_auth_student_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'PROFILE_NOT_FOUND';
  end if;

  perform private.lock_student_lifecycle(v_auth_student_id);
  perform private.lock_student_owned_total_order(v_auth_student_id);
  select * into strict v_profile
  from public.student_profile_versions profile
  where profile.profile_version_id = p_profile_version_id
    and profile.student_id = v_auth_student_id
  for key share;
  if v_profile.status is distinct from 'FROZEN' then
    raise exception using errcode = 'P0001', message = 'PROFILE_NOT_FROZEN';
  end if;

  perform 1
  from public.program_versions version
  where version.program_version_id = p_program_version_id
  for key share;
  if not found then
    raise exception using errcode = 'P0001', message = 'PROGRAM_NOT_FOUND';
  end if;

  select count(*),
    (array_agg(rule_set.rule_set_id order by rule_set.rule_set_id))[1]
  into v_rule_set_count, v_rule_set_id
  from public.program_requirement_rule_sets rule_set
  where rule_set.program_version_id = p_program_version_id
    and rule_set.status = 'VERIFIED'
    and rule_set.engine_contract_version = 'eligibility-v0.2'
    and rule_set.rule_schema_version = 'phase2-v0.2';
  if v_rule_set_count = 0 then
    raise exception using errcode = 'P0001', message = 'ELIGIBILITY_RULESET_NOT_FOUND';
  elsif v_rule_set_count <> 1 then
    raise exception using errcode = 'P0001', message = 'ELIGIBILITY_RULESET_AMBIGUOUS';
  end if;
  select * into strict v_rule_set
  from public.program_requirement_rule_sets rule_set
  where rule_set.rule_set_id = v_rule_set_id
  for key share;
  if v_rule_set.program_version_id is distinct from p_program_version_id
     or v_rule_set.status is distinct from 'VERIFIED'
     or v_rule_set.engine_contract_version is distinct from 'eligibility-v0.2'
     or v_rule_set.rule_schema_version is distinct from 'phase2-v0.2' then
    raise exception using errcode = 'P0001', message = 'ELIGIBILITY_ASSEMBLY_CONFLICT';
  end if;

  -- Lock the mutable authority universe before starting any durable evaluation
  -- state. The table order is fixed and every row set is ordered by its stable
  -- identity. In particular, scope -> head matches the catalog review lock
  -- order, so an applicability head cannot advance between pin validation and
  -- seal/finalize.
  perform 1
  from public.taxonomy_releases release
  where release.release_code = v_rule_set.taxonomy_release_code
  order by release.release_code
  for key share;
  if not found or exists (
    select 1 from public.taxonomy_releases release
    where release.release_code = v_rule_set.taxonomy_release_code
      and release.status is distinct from 'VERIFIED'
  ) then
    raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
  end if;

  perform 1
  from public.program_requirement_nodes node
  where node.rule_set_id = v_rule_set.rule_set_id
  order by node.rule_node_id
  for key share;
  if not found then
    raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
  end if;

  perform 1
  from public.catalog_concept_mappings mapping
  where mapping.mapping_id in (
    select node_mapping.catalog_mapping_id
    from public.program_requirement_node_mappings node_mapping
    join public.program_requirement_nodes node
      on node.rule_node_id = node_mapping.rule_node_id
    where node.rule_set_id = v_rule_set.rule_set_id
  )
  order by mapping.mapping_id
  for key share;

  perform 1
  from public.field_observations observation
  where observation.observation_id in (
    select node_source.field_observation_id
    from public.program_requirement_node_sources node_source
    join public.program_requirement_nodes node
      on node.rule_node_id = node_source.rule_node_id
    where node.rule_set_id = v_rule_set.rule_set_id
  )
  order by observation.observation_id
  for key share;

  perform 1
  from public.canonical_field_selections selection
  where exists (
    select 1
    from public.program_requirement_node_sources node_source
    join public.program_requirement_nodes node
      on node.rule_node_id = node_source.rule_node_id
    join public.field_observations observation
      on observation.observation_id = node_source.field_observation_id
    where node.rule_set_id = v_rule_set.rule_set_id
      and selection.record_type = observation.record_type
      and selection.record_id = observation.record_id
      and selection.field_name = observation.field_name
  )
  order by selection.record_type, selection.record_id, selection.field_name
  for key share;

  perform 1
  from public.evidence_items evidence
  where evidence.evidence_id in (
    select observation.evidence_id
    from public.program_requirement_node_sources node_source
    join public.program_requirement_nodes node
      on node.rule_node_id = node_source.rule_node_id
    join public.field_observations observation
      on observation.observation_id = node_source.field_observation_id
    where node.rule_set_id = v_rule_set.rule_set_id
      and observation.evidence_id is not null
  )
  order by evidence.evidence_id
  for key share;

  perform 1
  from public.sources source
  where source.source_id in (
    select evidence.source_id
    from public.program_requirement_node_sources node_source
    join public.program_requirement_nodes node
      on node.rule_node_id = node_source.rule_node_id
    join public.field_observations observation
      on observation.observation_id = node_source.field_observation_id
    join public.evidence_items evidence
      on evidence.evidence_id = observation.evidence_id
    where node.rule_set_id = v_rule_set.rule_set_id
  )
  order by source.source_id
  for key share;

  perform 1
  from public.evidence_applicability_scopes scope
  where scope.scope_id in (
    select assertion.scope_id
    from public.program_requirement_node_sources node_source
    join public.program_requirement_nodes node
      on node.rule_node_id = node_source.rule_node_id
    join public.field_observation_applicability binding
      on binding.observation_id = node_source.field_observation_id
    join public.evidence_applicability_assertions assertion
      on assertion.assertion_id = binding.assertion_id
    where node.rule_set_id = v_rule_set.rule_set_id
      and assertion.scope_id is not null
  )
  order by scope.scope_id
  for key share;

  perform 1
  from public.evidence_applicability_heads head
  where head.scope_id in (
    select assertion.scope_id
    from public.program_requirement_node_sources node_source
    join public.program_requirement_nodes node
      on node.rule_node_id = node_source.rule_node_id
    join public.field_observation_applicability binding
      on binding.observation_id = node_source.field_observation_id
    join public.evidence_applicability_assertions assertion
      on assertion.assertion_id = binding.assertion_id
    where node.rule_set_id = v_rule_set.rule_set_id
      and assertion.scope_id is not null
  )
  order by head.scope_id
  for key share;

  perform 1
  from public.evidence_applicability_assertions assertion
  where assertion.assertion_id in (
    select binding.assertion_id
    from public.program_requirement_node_sources node_source
    join public.program_requirement_nodes node
      on node.rule_node_id = node_source.rule_node_id
    join public.field_observation_applicability binding
      on binding.observation_id = node_source.field_observation_id
    where node.rule_set_id = v_rule_set.rule_set_id
  )
  order by assertion.assertion_id
  for key share;

  perform 1
  from public.field_observation_applicability binding
  where binding.observation_id in (
    select node_source.field_observation_id
    from public.program_requirement_node_sources node_source
    join public.program_requirement_nodes node
      on node.rule_node_id = node_source.rule_node_id
    where node.rule_set_id = v_rule_set.rule_set_id
  )
  order by binding.observation_id
  for key share;

  perform 1
  from public.taxonomy_concepts concept
  where concept.concept_id in (
    select node.target_concept_id
    from public.program_requirement_nodes node
    where node.rule_set_id = v_rule_set.rule_set_id
      and node.target_concept_id is not null
    union
    select mapping.concept_id
    from public.program_requirement_node_mappings node_mapping
    join public.program_requirement_nodes node
      on node.rule_node_id = node_mapping.rule_node_id
    join public.catalog_concept_mappings mapping
      on mapping.mapping_id = node_mapping.catalog_mapping_id
    where node.rule_set_id = v_rule_set.rule_set_id
      and mapping.mapping_status in ('VERIFIED', 'PROPOSED')
  )
  order by concept.concept_id
  for key share;

  perform 1
  from public.requirement_group_projection_thresholds threshold
  where threshold.rule_set_id = v_rule_set.rule_set_id
  order by threshold.group_node_id, threshold.projection_kind
  for key share;

  if exists (
    select 1
    from public.program_requirement_node_sources node_source
    join public.program_requirement_nodes node
      on node.rule_node_id = node_source.rule_node_id
    join public.field_observations observation
      on observation.observation_id = node_source.field_observation_id
    left join public.canonical_field_selections selection
      on selection.record_type = observation.record_type
     and selection.record_id = observation.record_id
     and selection.field_name = observation.field_name
    left join public.field_observation_applicability binding
      on binding.observation_id = observation.observation_id
    left join public.evidence_applicability_assertions assertion
      on assertion.assertion_id = binding.assertion_id
    left join public.evidence_applicability_heads head
      on head.scope_id = assertion.scope_id
    where node.rule_set_id = v_rule_set.rule_set_id
      and (
        selection.observation_id is distinct from observation.observation_id
        or binding.assertion_id is null
        or assertion.assertion_id is null
        or assertion.applicability_status = 'LEGACY_UNASSERTED'
        or (
          assertion.scope_id is not null
          and (
            assertion.applicability_status is distinct from 'REVIEWED_APPLICABLE'
            or head.assertion_id is distinct from binding.assertion_id
          )
        )
      )
  ) then
    raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
  end if;

  v_evaluation_id := public.start_eligibility_evaluation_v02(
    p_profile_version_id,
    v_rule_set.rule_set_id,
    v_rule_set.taxonomy_release_code,
    'education-platform-eligibility-sql-v02',
    '0.2.0',
    '65f231e376246191f54a6f8e5a7b8d01810746b3c47e7ecef22f93f84d4a0f58'
  );
  select taxonomy_release_ordinal into v_taxonomy_release_ordinal
  from public.eligibility_evaluations evaluation
  where evaluation.evaluation_id = v_evaluation_id;

  insert into private.eligibility_assembly_operations_v026 (
    operation_id, profile_version_id, program_version_id, evaluation_id
  ) values (
    p_operation_id, p_profile_version_id, p_program_version_id, v_evaluation_id
  );

  perform public.insert_eligibility_rule_set_pin(jsonb_populate_record(
    null::public.eligibility_rule_set_pins,
    jsonb_build_object(
      'evaluation_id', v_evaluation_id,
      'rule_set_id', v_rule_set.rule_set_id,
      'program_version_id', v_rule_set.program_version_id,
      'rule_set_version', v_rule_set.rule_set_version,
      'taxonomy_release_code', v_rule_set.taxonomy_release_code,
      'taxonomy_release_ordinal', v_taxonomy_release_ordinal,
      'rule_schema_version', v_rule_set.rule_schema_version,
      'engine_contract_version', v_rule_set.engine_contract_version,
      'verification_evidence_id', v_rule_set.verification_evidence_id,
      'verified_by', v_rule_set.verified_by,
      'verified_at', v_rule_set.verified_at
    )
  ));

  for v_row in
    select node.*
    from public.program_requirement_nodes node
    where node.rule_set_id = v_rule_set.rule_set_id
    order by node.sort_order, node.rule_node_id
  loop
    perform public.insert_eligibility_rule_node_pin(jsonb_populate_record(
      null::public.eligibility_rule_node_pins,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'rule_node_id', v_row.rule_node_id,
        'parent_node_id', v_row.parent_node_id,
        'sort_order', v_row.sort_order,
        'node_kind', v_row.node_kind,
        'group_operator', v_row.group_operator,
        'minimum_children', v_row.minimum_children,
        'predicate_kind', v_row.predicate_kind,
        'requirement_strength', v_row.requirement_strength,
        'requirement_semantics', v_row.requirement_semantics,
        'target_concept_id', v_row.target_concept_id,
        'explanation_template', v_row.explanation_template
      )
    ));
  end loop;

  for v_row in
    select completeness.*
    from public.student_data_completeness completeness
    where completeness.profile_version_id = p_profile_version_id
    order by completeness.domain, completeness.education_context_id nulls first,
      completeness.completeness_id
  loop
    perform public.insert_eligibility_completeness_pin(jsonb_populate_record(
      null::public.eligibility_completeness_pins,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'completeness_id', v_row.completeness_id,
        'scope_id', null,
        'domain', v_row.domain,
        'completeness', v_row.completeness,
        'explanation', v_row.explanation
      )
    ));
    perform public.insert_eligibility_manifest_completeness(jsonb_populate_record(
      null::public.eligibility_manifest_completeness,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'profile_version_id', p_profile_version_id,
        'completeness_id', v_row.completeness_id
      )
    ));
  end loop;

  select exists (
    select 1 from public.student_degrees degree
    where degree.profile_version_id = p_profile_version_id
  ) into v_has_degree;

  for v_row in
    select completeness.*
    from public.student_data_completeness completeness
    where completeness.profile_version_id = p_profile_version_id
    order by completeness.domain, completeness.education_context_id nulls first,
      completeness.completeness_id
  loop
    if v_row.domain in ('COURSE_HISTORY', 'COURSE_MAPPING') then
      if v_row.education_context_id is null and v_has_degree then
        continue;
      end if;
      v_scope_kind := case when v_row.education_context_id is null
        then 'UNASSIGNED_CONTEXT'::public.eligibility_snapshot_scope_kind
        else 'EDUCATION_CONTEXT'::public.eligibility_snapshot_scope_kind end;
    else
      v_scope_kind := 'GLOBAL_PROFILE';
    end if;
    v_scope_id := extensions.gen_random_uuid();
    perform public.insert_eligibility_snapshot_scope(jsonb_populate_record(
      null::public.eligibility_snapshot_scopes,
      jsonb_build_object(
        'scope_id', v_scope_id,
        'evaluation_id', v_evaluation_id,
        'profile_version_id', p_profile_version_id,
        'scope_kind', v_scope_kind,
        'education_context_id', case when v_scope_kind = 'EDUCATION_CONTEXT'
          then v_row.education_context_id else null end,
        'domain', v_row.domain,
        'completeness_id', v_row.completeness_id,
        'completeness', v_row.completeness
      )
    ));
  end loop;

  for v_row in select unnest(array[
    'COURSE_HISTORY'::public.student_data_domain,
    'COURSE_MAPPING'::public.student_data_domain
  ]) as domain
  loop
    if not exists (
      select 1 from public.eligibility_snapshot_scopes scope
      where scope.evaluation_id = v_evaluation_id
        and scope.domain = v_row.domain
        and scope.education_context_id is null
    ) then
      v_scope_id := extensions.gen_random_uuid();
      perform public.insert_eligibility_snapshot_scope(jsonb_populate_record(
        null::public.eligibility_snapshot_scopes,
        jsonb_build_object(
          'scope_id', v_scope_id,
          'evaluation_id', v_evaluation_id,
          'profile_version_id', p_profile_version_id,
          'scope_kind', 'UNASSIGNED_CONTEXT',
          'education_context_id', null,
          'domain', v_row.domain,
          'completeness_id', null,
          'completeness', null
        )
      ));
    end if;
  end loop;

  for v_row in
    select degree.* from public.student_degrees degree
    where degree.profile_version_id = p_profile_version_id
    order by degree.student_degree_id
  loop
    perform public.insert_eligibility_manifest_degree(jsonb_populate_record(
      null::public.eligibility_manifest_degrees,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'profile_version_id', p_profile_version_id,
        'student_degree_id', v_row.student_degree_id
      )
    ));
    select scope.scope_id into v_scope_id
    from public.eligibility_snapshot_scopes scope
    where scope.evaluation_id = v_evaluation_id
      and scope.scope_kind = 'GLOBAL_PROFILE'
      and scope.domain = 'EDUCATION_HISTORY';
    if v_scope_id is null then
      raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
    end if;
    perform public.insert_eligibility_snapshot_degree(jsonb_populate_record(
      null::public.eligibility_snapshot_degrees,
      jsonb_build_object('scope_id', v_scope_id, 'student_degree_id', v_row.student_degree_id)
    ));
  end loop;

  for v_row in
    select course.* from public.student_courses course
    where course.profile_version_id = p_profile_version_id
    order by course.student_course_id
  loop
    perform public.insert_eligibility_manifest_course(jsonb_populate_record(
      null::public.eligibility_manifest_courses,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'profile_version_id', p_profile_version_id,
        'student_course_id', v_row.student_course_id
      )
    ));
    select scope.scope_id into v_scope_id
    from public.eligibility_snapshot_scopes scope
    where scope.evaluation_id = v_evaluation_id
      and scope.domain = 'COURSE_HISTORY'
      and scope.education_context_id is not distinct from v_row.student_degree_id;
    if v_scope_id is null then
      raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
    end if;
    perform public.insert_eligibility_snapshot_course(jsonb_populate_record(
      null::public.eligibility_snapshot_courses,
      jsonb_build_object('scope_id', v_scope_id, 'student_course_id', v_row.student_course_id)
    ));
  end loop;

  for v_row in
    select score.* from public.student_test_scores score
    where score.profile_version_id = p_profile_version_id
    order by score.student_test_score_id
  loop
    perform public.insert_eligibility_manifest_test_score(jsonb_populate_record(
      null::public.eligibility_manifest_test_scores,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'profile_version_id', p_profile_version_id,
        'student_test_score_id', v_row.student_test_score_id
      )
    ));
    select scope.scope_id into v_scope_id
    from public.eligibility_snapshot_scopes scope
    where scope.evaluation_id = v_evaluation_id
      and scope.scope_kind = 'GLOBAL_PROFILE'
      and scope.domain = 'TEST_HISTORY';
    if v_scope_id is null then
      raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
    end if;
    perform public.insert_eligibility_snapshot_test_score(jsonb_populate_record(
      null::public.eligibility_snapshot_test_scores,
      jsonb_build_object('scope_id', v_scope_id, 'student_test_score_id', v_row.student_test_score_id)
    ));
  end loop;

  for v_row in
    select evidence.* from public.student_evidence_items evidence
    where evidence.profile_version_id = p_profile_version_id
    order by evidence.student_evidence_id
  loop
    perform public.insert_eligibility_manifest_student_evidence(jsonb_populate_record(
      null::public.eligibility_manifest_student_evidence,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'profile_version_id', p_profile_version_id,
        'student_evidence_id', v_row.student_evidence_id
      )
    ));
  end loop;

  for v_row in
    select node_mapping.rule_node_id, mapping.*
    from public.program_requirement_node_mappings node_mapping
    join public.program_requirement_nodes node
      on node.rule_node_id = node_mapping.rule_node_id
    join public.catalog_concept_mappings mapping
      on mapping.mapping_id = node_mapping.catalog_mapping_id
    where node.rule_set_id = v_rule_set.rule_set_id
      and mapping.mapping_status in ('VERIFIED', 'PROPOSED')
    order by mapping.mapping_id, node_mapping.rule_node_id
  loop
    if not exists (
      select 1 from public.eligibility_catalog_mapping_pins pin
      where pin.evaluation_id = v_evaluation_id
        and pin.catalog_mapping_id = v_row.mapping_id
    ) then
      perform public.insert_eligibility_catalog_mapping_pin(jsonb_populate_record(
        null::public.eligibility_catalog_mapping_pins,
        jsonb_build_object(
          'evaluation_id', v_evaluation_id,
          'catalog_mapping_id', v_row.mapping_id,
          'record_type', v_row.record_type,
          'record_id', v_row.record_id,
          'concept_id', v_row.concept_id,
          'relation_at_pin', v_row.relation,
          'method', v_row.method,
          'confidence', v_row.confidence,
          'model_version', v_row.model_version,
          'verification_evidence_id', v_row.verification_evidence_id,
          'reviewed_by', v_row.reviewed_by,
          'reviewed_at', v_row.reviewed_at,
          'status_at_pin', v_row.mapping_status,
          'retired_at_pin', v_row.retired_at,
          'retirement_reason_at_pin', v_row.retirement_reason
        )
      ));
      perform public.insert_eligibility_manifest_catalog_mapping(jsonb_populate_record(
        null::public.eligibility_manifest_catalog_mappings,
        jsonb_build_object('evaluation_id', v_evaluation_id, 'catalog_mapping_id', v_row.mapping_id)
      ));
    end if;
    perform public.insert_eligibility_rule_node_mapping_pin(jsonb_populate_record(
      null::public.eligibility_rule_node_mapping_pins,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'rule_node_id', v_row.rule_node_id,
        'catalog_mapping_id', v_row.mapping_id
      )
    ));
  end loop;

  for v_row in
    select node_source.rule_node_id, observation.*
    from public.program_requirement_node_sources node_source
    join public.program_requirement_nodes node
      on node.rule_node_id = node_source.rule_node_id
    join public.field_observations observation
      on observation.observation_id = node_source.field_observation_id
    where node.rule_set_id = v_rule_set.rule_set_id
    order by observation.observation_id, node_source.rule_node_id
  loop
    select source.source_id, source.source_identity_id, source.revision_number,
      source.retrieval_content_hash, evidence.evidence_id
    into v_source_id, v_source_identity_id, v_source_revision_number,
      v_retrieval_content_hash, v_evidence_id
    from public.evidence_items evidence
    join public.sources source on source.source_id = evidence.source_id
    where evidence.evidence_id = v_row.evidence_id
    for key share of source;
    if not found then
      raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
    end if;

    select binding.assertion_id, assertion.scope_id,
      scope.program_scope_key, scope.program_version_scope_key,
      scope.granularity_scope, scope.population_scope_code, scope.cycle_scope_code
    into v_applicability_assertion_id, v_applicability_scope_id,
      v_program_scope_key, v_program_version_scope_key,
      v_granularity_scope, v_population_scope_code, v_cycle_scope_code
    from public.field_observation_applicability binding
    join public.evidence_applicability_assertions assertion
      on assertion.assertion_id = binding.assertion_id
    left join public.evidence_applicability_scopes scope
      on scope.scope_id = assertion.scope_id
    where binding.observation_id = v_row.observation_id;
    if not found then
      raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
    end if;

    if not exists (
      select 1 from public.eligibility_catalog_observation_pins pin
      where pin.evaluation_id = v_evaluation_id
        and pin.field_observation_id = v_row.observation_id
    ) then
      perform public.insert_eligibility_catalog_observation_pin(jsonb_populate_record(
        null::public.eligibility_catalog_observation_pins,
        jsonb_build_object(
          'evaluation_id', v_evaluation_id,
          'field_observation_id', v_row.observation_id,
          'source_id', v_source_id,
          'source_identity_id', v_source_identity_id,
          'source_revision_number', v_source_revision_number,
          'retrieval_content_hash', v_retrieval_content_hash,
          'evidence_id', v_evidence_id,
          'record_type', v_row.record_type,
          'record_id', v_row.record_id,
          'field_name', v_row.field_name,
          'canonical_value', v_row.observed_value,
          'knowledge_status', v_row.knowledge_status,
          'program_scope_key', v_program_scope_key,
          'program_version_scope_key', v_program_version_scope_key,
          'granularity_scope', v_granularity_scope,
          'population_scope_code', v_population_scope_code,
          'cycle_scope_code', v_cycle_scope_code
        )
      ));
      select selection.* into strict v_selection
      from public.canonical_field_selections selection
      where selection.record_type = v_row.record_type
        and selection.record_id = v_row.record_id
        and selection.field_name = v_row.field_name;
      perform public.insert_eligibility_catalog_selection_pin(jsonb_populate_record(
        null::public.eligibility_catalog_selection_pins,
        jsonb_build_object(
          'evaluation_id', v_evaluation_id,
          'record_type', v_row.record_type,
          'record_id', v_row.record_id,
          'field_name', v_row.field_name,
          'observation_id', v_selection.observation_id,
          'selected_at_pin', v_selection.selected_at,
          'selected_by_pin', v_selection.selected_by
        )
      ));
      perform public.insert_eligibility_manifest_catalog_source(jsonb_populate_record(
        null::public.eligibility_manifest_catalog_sources,
        jsonb_build_object('evaluation_id', v_evaluation_id, 'field_observation_id', v_row.observation_id)
      ));
    end if;
    perform public.insert_eligibility_rule_node_source_pin(jsonb_populate_record(
      null::public.eligibility_rule_node_source_pins,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'rule_node_id', v_row.rule_node_id,
        'field_observation_id', v_row.observation_id,
        'source_id', v_source_id,
        'applicability_assertion_id', v_applicability_assertion_id,
        'applicability_head_assertion_id_at_pin', v_applicability_assertion_id,
        'applicability_scope_id', v_applicability_scope_id,
        'knowledge_status_at_pin', v_row.knowledge_status
      )
    ));
  end loop;

  for v_row in
    select mapping.*, course.student_degree_id
    from private.eligibility_v02_required_student_mappings(v_evaluation_id) required
    join public.student_record_concept_mappings mapping
      on mapping.student_mapping_id = required.student_mapping_id
    join public.student_courses course
      on course.student_course_id = mapping.student_record_id
    order by mapping.student_mapping_id
  loop
    perform public.insert_eligibility_student_mapping_pin(jsonb_populate_record(
      null::public.eligibility_student_mapping_pins,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'student_mapping_id', v_row.student_mapping_id,
        'profile_version_id', p_profile_version_id,
        'record_type', v_row.record_type,
        'student_record_id', v_row.student_record_id,
        'concept_id', v_row.concept_id,
        'relation_at_pin', 'STUDENT_CONCEPT_ASSOCIATION',
        'method', v_row.method,
        'confidence', v_row.confidence,
        'model_version', v_row.model_version,
        'student_evidence_id', v_row.student_evidence_id,
        'reviewed_by', v_row.reviewed_by,
        'reviewed_at', v_row.reviewed_at,
        'status_at_pin', v_row.mapping_status,
        'retired_at_pin', v_row.retired_at,
        'retirement_reason_at_pin', v_row.retirement_reason
      )
    ));
    perform public.insert_eligibility_manifest_student_mapping(jsonb_populate_record(
      null::public.eligibility_manifest_student_mappings,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'profile_version_id', p_profile_version_id,
        'student_mapping_id', v_row.student_mapping_id
      )
    ));
    select scope.scope_id into v_scope_id
    from public.eligibility_snapshot_scopes scope
    where scope.evaluation_id = v_evaluation_id
      and scope.domain = 'COURSE_MAPPING'
      and scope.education_context_id is not distinct from v_row.student_degree_id;
    if v_scope_id is null then
      raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
    end if;
    perform public.insert_eligibility_snapshot_mapping_universe(jsonb_populate_record(
      null::public.eligibility_snapshot_mapping_universe,
      jsonb_build_object(
        'scope_id', v_scope_id,
        'student_mapping_id', v_row.student_mapping_id,
        'universe_role', case when v_row.mapping_status = 'VERIFIED'
          then 'AUTHORITATIVE' else 'LIMITING' end
      )
    ));
  end loop;

  for v_row in
    select distinct concept.concept_id, concept.canonical_key,
      concept.concept_kind, concept.introduced_release_ordinal,
      concept.retired_release_ordinal
    from public.taxonomy_concepts concept
    where concept.concept_id in (
      select pin.target_concept_id
      from public.eligibility_rule_node_pins pin
      where pin.evaluation_id = v_evaluation_id
        and pin.target_concept_id is not null
      union
      select pin.concept_id
      from public.eligibility_catalog_mapping_pins pin
      where pin.evaluation_id = v_evaluation_id
      union
      select pin.concept_id
      from public.eligibility_student_mapping_pins pin
      where pin.evaluation_id = v_evaluation_id
    )
    order by concept.concept_id
  loop
    perform public.insert_eligibility_taxonomy_concept_pin(jsonb_populate_record(
      null::public.eligibility_taxonomy_concept_pins,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'concept_id', v_row.concept_id,
        'canonical_key', v_row.canonical_key,
        'concept_kind', v_row.concept_kind,
        'introduced_release_ordinal', v_row.introduced_release_ordinal,
        'retired_release_ordinal', v_row.retired_release_ordinal
      )
    ));
    perform public.insert_eligibility_manifest_taxonomy_concept(jsonb_populate_record(
      null::public.eligibility_manifest_taxonomy_concepts,
      jsonb_build_object('evaluation_id', v_evaluation_id, 'concept_id', v_row.concept_id)
    ));
  end loop;

  for v_row in
    select threshold.*
    from public.requirement_group_projection_thresholds threshold
    where threshold.rule_set_id = v_rule_set.rule_set_id
    order by threshold.group_node_id, threshold.projection_kind
  loop
    perform public.insert_eligibility_projection_threshold_pin(jsonb_populate_record(
      null::public.eligibility_projection_threshold_pins,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'rule_set_id', v_rule_set.rule_set_id,
        'group_node_id', v_row.group_node_id,
        'projection_kind', v_row.projection_kind,
        'projected_minimum_children', v_row.projected_minimum_children,
        'projected_descendant_count', v_row.projected_descendant_count,
        'verification_evidence_id', v_row.verification_evidence_id,
        'verified_by', v_row.verified_by,
        'verified_at', v_row.verified_at,
        'created_at_source', v_row.created_at
      )
    ));
  end loop;

  perform public.seal_eligibility_evaluation_inputs_v02(v_evaluation_id);
  perform public.finalize_eligibility_evaluation_v02(v_evaluation_id);
  return private.project_eligibility_assembly_v026(v_evaluation_id);
exception
  when query_canceled then
    raise exception using errcode = 'P0001', message = 'REQUEST_TIMEOUT';
  when others then
    v_error := sqlerrm;
    if v_error = any(v_allowed_errors) then
      raise exception using errcode = 'P0001', message = v_error;
    end if;
    raise exception using errcode = 'P0001', message = 'INTERNAL_ERROR';
end;
$function$;

grant create on schema public to foundation_evaluation_executor;
grant create on schema private to foundation_evaluation_executor;
alter function public.assemble_eligibility_evaluation_v026(uuid, uuid, uuid)
  owner to foundation_evaluation_executor;
alter function private.project_eligibility_assembly_v026(uuid)
  owner to foundation_evaluation_executor;
alter table private.eligibility_assembly_operations_v026
  owner to foundation_evaluation_executor;
revoke create on schema public from foundation_evaluation_executor;
revoke create on schema private from foundation_evaluation_executor;

grant execute on function private.profile_student_for_auth_v019()
to foundation_evaluation_executor;
grant execute on function private.profile_request_auth_subject_v021()
to foundation_evaluation_executor;

revoke all on function private.project_eligibility_assembly_v026(uuid)
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor;
revoke all on function public.assemble_eligibility_evaluation_v026(uuid, uuid, uuid)
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant execute on function public.assemble_eligibility_evaluation_v026(uuid, uuid, uuid)
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
  and procedure.proname = 'assemble_eligibility_evaluation_v026'
on conflict (schema_name, function_name, identity_arguments) do update
set owner_role = excluded.owner_role,
    prosecdef = excluded.prosecdef,
    search_path = excluded.search_path,
    allowed_caller_roles = excluded.allowed_caller_roles,
    body_digest = excluded.body_digest;

comment on function public.assemble_eligibility_evaluation_v026(uuid, uuid, uuid) is
  'Authenticated owner-only atomic Eligibility v0.2 assembly using frozen M013 semantics and a closed bounded result.';

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
    and procedure.proname = 'assemble_eligibility_evaluation_v026';

  if v_function.owner_role <> 'foundation_evaluation_executor'
     or not v_function.prosecdef
     or v_function.provolatile <> 'v'
     or v_function.proconfig is distinct from
       array['search_path=pg_catalog, public, private, extensions']::text[]
     or v_function.identity_arguments <>
       'p_profile_version_id uuid, p_program_version_id uuid, p_operation_id uuid'
     or v_function.return_type <> 'jsonb' then
    raise exception '026 assertion failed: assembly function contract';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.assemble_eligibility_evaluation_v026(uuid,uuid,uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.assemble_eligibility_evaluation_v026(uuid,uuid,uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'service_role',
    'public.assemble_eligibility_evaluation_v026(uuid,uuid,uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'authenticator',
    'public.assemble_eligibility_evaluation_v026(uuid,uuid,uuid)',
    'EXECUTE'
  ) then
    raise exception '026 assertion failed: assembly external ACL';
  end if;

  if has_schema_privilege('foundation_evaluation_executor', 'auth', 'USAGE')
     or has_table_privilege('foundation_evaluation_executor', 'auth.users', 'SELECT')
     or has_table_privilege('service_role', 'public.program_requirement_rule_sets', 'SELECT')
     or has_table_privilege('service_role', 'public.student_profile_versions', 'SELECT')
     or has_table_privilege('service_role', 'public.eligibility_evaluations', 'SELECT')
     or not has_table_privilege(
       'foundation_evaluation_executor', 'public.program_versions', 'SELECT'
     )
     or has_table_privilege(
       'foundation_evaluation_executor', 'public.program_versions',
       'INSERT,DELETE'
     )
     or pg_has_role('foundation_evaluation_executor', 'service_role', 'MEMBER') then
    raise exception '026 assertion failed: executor/service-role authority widened';
  end if;

  if has_schema_privilege('foundation_evaluation_executor', 'public', 'CREATE')
     or has_schema_privilege('foundation_evaluation_executor', 'private', 'CREATE') then
    raise exception '026 assertion failed: temporary schema CREATE not revoked';
  end if;

  if not exists (
    select 1 from public.foundation_function_contracts contract
    where contract.schema_name = 'public'
      and contract.function_name = 'assemble_eligibility_evaluation_v026'
      and contract.identity_arguments =
        'p_profile_version_id uuid, p_program_version_id uuid, p_operation_id uuid'
      and contract.owner_role = 'foundation_evaluation_executor'
      and contract.prosecdef
      and contract.search_path = 'pg_catalog, public, private, extensions'
      and contract.allowed_caller_roles = array['authenticated']
      and contract.body_digest ~ '^[a-f0-9]{64}$'
  ) then
    raise exception '026 assertion failed: function registry';
  end if;
end;
$assert$;

commit;
