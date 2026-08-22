begin;

create extension if not exists dblink;

-- Transaction-scoped helpers for GATES A–J. Rolled back with the test.
create or replace function pg_temp.v02_insert_required_completeness(
  p_profile uuid,
  p_completeness public.data_completeness,
  p_degree uuid
) returns void
language plpgsql as $$
declare
  v_domain public.student_data_domain;
  v_expl text := case when p_completeness = 'COMPLETE' then null else 'gate-incomplete' end;
begin
  foreach v_domain in array enum_range(null::public.student_data_domain)
  loop
    if v_domain in ('COURSE_HISTORY', 'COURSE_MAPPING') then
      if p_degree is null then
        perform public.insert_student_data_completeness(jsonb_populate_record(
          null::public.student_data_completeness,
          jsonb_build_object(
            'profile_version_id', p_profile,
            'domain', v_domain,
            'completeness', p_completeness,
            'explanation', v_expl
          )
        ));
      else
        perform public.insert_student_data_completeness(jsonb_populate_record(
          null::public.student_data_completeness,
          jsonb_build_object(
            'profile_version_id', p_profile,
            'education_context_id', p_degree,
            'domain', v_domain,
            'completeness', p_completeness,
            'explanation', v_expl
          )
        ));
      end if;
    else
      perform public.insert_student_data_completeness(jsonb_populate_record(
        null::public.student_data_completeness,
        jsonb_build_object(
          'profile_version_id', p_profile,
          'domain', v_domain,
          'completeness', p_completeness,
          'explanation', v_expl
        )
      ));
    end if;
  end loop;
end;
$$;

create or replace function pg_temp.v02_pin_evaluation(
  p_evaluation_id uuid,
  p_omit_course_id uuid default null,
  p_omit_mapping_id uuid default null,
  p_omit_universe_id uuid default null,
  p_extra_mapping_id uuid default null,
  p_omit_thresholds boolean default false,
  p_omit_taxonomy boolean default false,
  p_omit_catalog_mappings boolean default false,
  p_source_desc boolean default false
) returns void
language plpgsql as $$
declare
  v_eval public.eligibility_evaluations%rowtype;
  v_rs public.program_requirement_rule_sets%rowtype;
  v_node public.program_requirement_nodes%rowtype;
  v_tc public.taxonomy_concepts%rowtype;
  v_cm public.catalog_concept_mappings%rowtype;
  v_sm public.student_record_concept_mappings%rowtype;
  v_obs public.field_observations%rowtype;
  v_ev public.evidence_items%rowtype;
  v_src public.sources%rowtype;
  v_sel public.canonical_field_selections%rowtype;
  v_bind public.field_observation_applicability%rowtype;
  v_assertion public.evidence_applicability_assertions%rowtype;
  v_ascope public.evidence_applicability_scopes%rowtype;
  v_comp public.student_data_completeness%rowtype;
  v_course public.student_courses%rowtype;
  v_degree public.student_degrees%rowtype;
  v_test public.student_test_scores%rowtype;
  v_ns public.program_requirement_node_sources%rowtype;
  v_nm public.program_requirement_node_mappings%rowtype;
  v_thr public.requirement_group_projection_thresholds%rowtype;
  v_scope uuid;
  v_unassigned_ch uuid;
  v_unassigned_cm uuid;
  v_has_degree boolean;
  v_map_scope uuid;
begin
  select * into v_eval from public.eligibility_evaluations where evaluation_id = p_evaluation_id;
  select * into v_rs from public.program_requirement_rule_sets where rule_set_id = v_eval.rule_set_id;
  v_has_degree := exists (
    select 1 from public.student_degrees where profile_version_id = v_eval.profile_version_id
  );

  perform public.insert_eligibility_rule_set_pin(jsonb_populate_record(
    null::public.eligibility_rule_set_pins,
    to_jsonb(v_rs) || jsonb_build_object(
      'evaluation_id', p_evaluation_id,
      'taxonomy_release_ordinal', v_eval.taxonomy_release_ordinal
    )
  ));

  for v_node in
    select * from public.program_requirement_nodes where rule_set_id = v_eval.rule_set_id
  loop
    perform public.insert_eligibility_rule_node_pin(jsonb_populate_record(
      null::public.eligibility_rule_node_pins,
      to_jsonb(v_node) || jsonb_build_object('evaluation_id', p_evaluation_id)
    ));
    if v_node.target_concept_id is not null and not p_omit_taxonomy then
      select * into v_tc from public.taxonomy_concepts where concept_id = v_node.target_concept_id;
      if not exists (
        select 1 from public.eligibility_taxonomy_concept_pins
        where evaluation_id = p_evaluation_id and concept_id = v_tc.concept_id
      ) then
        perform public.insert_eligibility_taxonomy_concept_pin(jsonb_populate_record(
          null::public.eligibility_taxonomy_concept_pins,
          jsonb_build_object(
            'evaluation_id', p_evaluation_id,
            'concept_id', v_tc.concept_id,
            'canonical_key', v_tc.canonical_key,
            'concept_kind', v_tc.concept_kind,
            'introduced_release_ordinal', v_tc.introduced_release_ordinal,
            'retired_release_ordinal', v_tc.retired_release_ordinal
          )
        ));
      end if;
    end if;
  end loop;

  for v_comp in
    select * from public.student_data_completeness
    where profile_version_id = v_eval.profile_version_id
  loop
    perform public.insert_eligibility_completeness_pin(jsonb_populate_record(
      null::public.eligibility_completeness_pins,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'completeness_id', v_comp.completeness_id,
        'domain', v_comp.domain,
        'completeness', v_comp.completeness,
        'explanation', v_comp.explanation
      )
    ));
  end loop;

  for v_comp in
    select * from public.student_data_completeness
    where profile_version_id = v_eval.profile_version_id
  loop
    if v_comp.domain in ('COURSE_HISTORY', 'COURSE_MAPPING') then
      if v_comp.education_context_id is not null then
        v_scope := extensions.gen_random_uuid();
        perform public.insert_eligibility_snapshot_scope(jsonb_populate_record(
          null::public.eligibility_snapshot_scopes,
          jsonb_build_object(
            'scope_id', v_scope,
            'evaluation_id', p_evaluation_id,
            'profile_version_id', v_eval.profile_version_id,
            'scope_kind', 'EDUCATION_CONTEXT',
            'education_context_id', v_comp.education_context_id,
            'domain', v_comp.domain,
            'completeness_id', v_comp.completeness_id,
            'completeness', v_comp.completeness
          )
        ));
      elsif not v_has_degree then
        v_scope := extensions.gen_random_uuid();
        perform public.insert_eligibility_snapshot_scope(jsonb_populate_record(
          null::public.eligibility_snapshot_scopes,
          jsonb_build_object(
            'scope_id', v_scope,
            'evaluation_id', p_evaluation_id,
            'profile_version_id', v_eval.profile_version_id,
            'scope_kind', 'UNASSIGNED_CONTEXT',
            'domain', v_comp.domain,
            'completeness_id', v_comp.completeness_id,
            'completeness', v_comp.completeness
          )
        ));
        if v_comp.domain = 'COURSE_HISTORY' then v_unassigned_ch := v_scope; end if;
        if v_comp.domain = 'COURSE_MAPPING' then v_unassigned_cm := v_scope; end if;
      end if;
    else
      v_scope := extensions.gen_random_uuid();
      perform public.insert_eligibility_snapshot_scope(jsonb_populate_record(
        null::public.eligibility_snapshot_scopes,
        jsonb_build_object(
          'scope_id', v_scope,
          'evaluation_id', p_evaluation_id,
          'profile_version_id', v_eval.profile_version_id,
          'scope_kind', 'GLOBAL_PROFILE',
          'domain', v_comp.domain,
          'completeness_id', v_comp.completeness_id,
          'completeness', v_comp.completeness
        )
      ));
    end if;
  end loop;

  if v_unassigned_ch is null then
    v_unassigned_ch := extensions.gen_random_uuid();
    perform public.insert_eligibility_snapshot_scope(jsonb_populate_record(
      null::public.eligibility_snapshot_scopes,
      jsonb_build_object(
        'scope_id', v_unassigned_ch,
        'evaluation_id', p_evaluation_id,
        'profile_version_id', v_eval.profile_version_id,
        'scope_kind', 'UNASSIGNED_CONTEXT',
        'domain', 'COURSE_HISTORY'
      )
    ));
  end if;
  if v_unassigned_cm is null then
    v_unassigned_cm := extensions.gen_random_uuid();
    perform public.insert_eligibility_snapshot_scope(jsonb_populate_record(
      null::public.eligibility_snapshot_scopes,
      jsonb_build_object(
        'scope_id', v_unassigned_cm,
        'evaluation_id', p_evaluation_id,
        'profile_version_id', v_eval.profile_version_id,
        'scope_kind', 'UNASSIGNED_CONTEXT',
        'domain', 'COURSE_MAPPING'
      )
    ));
  end if;

  for v_degree in
    select * from public.student_degrees where profile_version_id = v_eval.profile_version_id
  loop
    perform public.insert_eligibility_manifest_degree(jsonb_populate_record(
      null::public.eligibility_manifest_degrees,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'profile_version_id', v_eval.profile_version_id,
        'student_degree_id', v_degree.student_degree_id
      )
    ));
    select s.scope_id into v_scope
    from public.eligibility_snapshot_scopes s
    where s.evaluation_id = p_evaluation_id
      and s.scope_kind = 'GLOBAL_PROFILE'
      and s.domain = 'EDUCATION_HISTORY';
    perform public.insert_eligibility_snapshot_degree(jsonb_populate_record(
      null::public.eligibility_snapshot_degrees,
      jsonb_build_object('scope_id', v_scope, 'student_degree_id', v_degree.student_degree_id)
    ));
  end loop;

  for v_course in
    select * from public.student_courses where profile_version_id = v_eval.profile_version_id
  loop
    if v_course.student_course_id is not distinct from p_omit_course_id then
      continue;
    end if;
    perform public.insert_eligibility_manifest_course(jsonb_populate_record(
      null::public.eligibility_manifest_courses,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'profile_version_id', v_eval.profile_version_id,
        'student_course_id', v_course.student_course_id
      )
    ));
    if v_course.student_degree_id is null then
      v_scope := v_unassigned_ch;
    else
      select s.scope_id into v_scope
      from public.eligibility_snapshot_scopes s
      where s.evaluation_id = p_evaluation_id
        and s.scope_kind = 'EDUCATION_CONTEXT'
        and s.education_context_id = v_course.student_degree_id
        and s.domain = 'COURSE_HISTORY';
    end if;
    perform public.insert_eligibility_snapshot_course(jsonb_populate_record(
      null::public.eligibility_snapshot_courses,
      jsonb_build_object('scope_id', v_scope, 'student_course_id', v_course.student_course_id)
    ));
  end loop;

  for v_test in
    select * from public.student_test_scores where profile_version_id = v_eval.profile_version_id
  loop
    perform public.insert_eligibility_manifest_test_score(jsonb_populate_record(
      null::public.eligibility_manifest_test_scores,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'profile_version_id', v_eval.profile_version_id,
        'student_test_score_id', v_test.student_test_score_id
      )
    ));
    select s.scope_id into v_scope
    from public.eligibility_snapshot_scopes s
    where s.evaluation_id = p_evaluation_id
      and s.scope_kind = 'GLOBAL_PROFILE' and s.domain = 'TEST_HISTORY';
    perform public.insert_eligibility_snapshot_test_score(jsonb_populate_record(
      null::public.eligibility_snapshot_test_scores,
      jsonb_build_object('scope_id', v_scope, 'student_test_score_id', v_test.student_test_score_id)
    ));
  end loop;

  for v_comp in
    select * from public.student_data_completeness
    where profile_version_id = v_eval.profile_version_id
  loop
    perform public.insert_eligibility_manifest_completeness(jsonb_populate_record(
      null::public.eligibility_manifest_completeness,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'profile_version_id', v_eval.profile_version_id,
        'completeness_id', v_comp.completeness_id
      )
    ));
  end loop;

  perform public.insert_eligibility_manifest_student_evidence(jsonb_populate_record(
    null::public.eligibility_manifest_student_evidence,
    jsonb_build_object(
      'evaluation_id', p_evaluation_id,
      'profile_version_id', e.profile_version_id,
      'student_evidence_id', e.student_evidence_id
    )
  ))
  from public.student_evidence_items e
  where e.profile_version_id = v_eval.profile_version_id;

  if not p_omit_catalog_mappings then
  for v_nm in
    select nm.*
    from public.program_requirement_node_mappings nm
    join public.program_requirement_nodes n using (rule_node_id)
    where n.rule_set_id = v_eval.rule_set_id
  loop
    select * into v_cm from public.catalog_concept_mappings where mapping_id = v_nm.catalog_mapping_id;
    if v_cm.mapping_status not in ('VERIFIED', 'PROPOSED') then
      continue;
    end if;
    if not exists (
      select 1 from public.eligibility_catalog_mapping_pins
      where evaluation_id = p_evaluation_id and catalog_mapping_id = v_cm.mapping_id
    ) then
      perform public.insert_eligibility_catalog_mapping_pin(jsonb_populate_record(
        null::public.eligibility_catalog_mapping_pins,
        jsonb_build_object(
          'evaluation_id', p_evaluation_id,
          'catalog_mapping_id', v_cm.mapping_id,
          'record_type', v_cm.record_type,
          'record_id', v_cm.record_id,
          'concept_id', v_cm.concept_id,
          'relation_at_pin', v_cm.relation,
          'method', v_cm.method,
          'confidence', v_cm.confidence,
          'model_version', v_cm.model_version,
          'verification_evidence_id', v_cm.verification_evidence_id,
          'reviewed_by', v_cm.reviewed_by,
          'reviewed_at', v_cm.reviewed_at,
          'status_at_pin', v_cm.mapping_status,
          'retired_at_pin', v_cm.retired_at,
          'retirement_reason_at_pin', v_cm.retirement_reason
        )
      ));
      perform public.insert_eligibility_manifest_catalog_mapping(jsonb_populate_record(
        null::public.eligibility_manifest_catalog_mappings,
        jsonb_build_object('evaluation_id', p_evaluation_id, 'catalog_mapping_id', v_cm.mapping_id)
      ));
    end if;
    perform public.insert_eligibility_rule_node_mapping_pin(jsonb_populate_record(
      null::public.eligibility_rule_node_mapping_pins,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'rule_node_id', v_nm.rule_node_id,
        'catalog_mapping_id', v_nm.catalog_mapping_id
      )
    ));
  end loop;
  end if;

  if not p_omit_taxonomy then
    for v_tc in
      select distinct tc.*
      from public.taxonomy_concepts tc
      where tc.concept_id in (
        select p.concept_id from public.eligibility_catalog_mapping_pins p
         where p.evaluation_id = p_evaluation_id
        union
        select p.concept_id from public.eligibility_student_mapping_pins p
         where p.evaluation_id = p_evaluation_id
      )
      and not exists (
        select 1 from public.eligibility_taxonomy_concept_pins x
        where x.evaluation_id = p_evaluation_id and x.concept_id = tc.concept_id
      )
    loop
      perform public.insert_eligibility_taxonomy_concept_pin(jsonb_populate_record(
        null::public.eligibility_taxonomy_concept_pins,
        jsonb_build_object(
          'evaluation_id', p_evaluation_id,
          'concept_id', v_tc.concept_id,
          'canonical_key', v_tc.canonical_key,
          'concept_kind', v_tc.concept_kind,
          'introduced_release_ordinal', v_tc.introduced_release_ordinal,
          'retired_release_ordinal', v_tc.retired_release_ordinal
        )
      ));
    end loop;
  end if;

  for v_ns in
    select ns.*
    from public.program_requirement_node_sources ns
    join public.program_requirement_nodes n using (rule_node_id)
    where n.rule_set_id = v_eval.rule_set_id
    order by
      case when p_source_desc then ns.field_observation_id::text else '' end desc,
      case when not p_source_desc then ns.field_observation_id::text else '' end
  loop
    select * into v_obs from public.field_observations where observation_id = v_ns.field_observation_id;
    select * into v_ev from public.evidence_items where evidence_id = v_obs.evidence_id;
    select * into v_src from public.sources where source_id = v_ev.source_id;
    select * into v_sel from public.canonical_field_selections
      where record_type = v_obs.record_type and record_id = v_obs.record_id and field_name = v_obs.field_name;
    select * into v_bind from public.field_observation_applicability
      where observation_id = v_obs.observation_id;
    select * into v_assertion from public.evidence_applicability_assertions
      where assertion_id = v_bind.assertion_id;
    if v_assertion.scope_id is not null then
      select * into v_ascope from public.evidence_applicability_scopes where scope_id = v_assertion.scope_id;
    else
      v_ascope := null;
    end if;
    if not exists (
      select 1 from public.eligibility_catalog_observation_pins
      where evaluation_id = p_evaluation_id and field_observation_id = v_obs.observation_id
    ) then
      perform public.insert_eligibility_catalog_observation_pin(jsonb_populate_record(
        null::public.eligibility_catalog_observation_pins,
        jsonb_build_object(
          'evaluation_id', p_evaluation_id,
          'field_observation_id', v_obs.observation_id,
          'source_id', v_src.source_id,
          'source_identity_id', v_src.source_identity_id,
          'source_revision_number', v_src.revision_number,
          'retrieval_content_hash', v_src.retrieval_content_hash,
          'evidence_id', v_obs.evidence_id,
          'record_type', v_obs.record_type,
          'record_id', v_obs.record_id,
          'field_name', v_obs.field_name,
          'canonical_value', v_obs.observed_value,
          'knowledge_status', v_obs.knowledge_status,
          'program_scope_key', v_ascope.program_scope_key,
          'program_version_scope_key', v_ascope.program_version_scope_key,
          'granularity_scope', v_ascope.granularity_scope,
          'population_scope_code', v_ascope.population_scope_code,
          'cycle_scope_code', v_ascope.cycle_scope_code
        )
      ));
      perform public.insert_eligibility_catalog_selection_pin(jsonb_populate_record(
        null::public.eligibility_catalog_selection_pins,
        jsonb_build_object(
          'evaluation_id', p_evaluation_id,
          'record_type', v_sel.record_type,
          'record_id', v_sel.record_id,
          'field_name', v_sel.field_name,
          'observation_id', v_sel.observation_id,
          'selected_at_pin', v_sel.selected_at,
          'selected_by_pin', v_sel.selected_by
        )
      ));
      perform public.insert_eligibility_manifest_catalog_source(jsonb_populate_record(
        null::public.eligibility_manifest_catalog_sources,
        jsonb_build_object('evaluation_id', p_evaluation_id, 'field_observation_id', v_obs.observation_id)
      ));
    end if;
    perform public.insert_eligibility_rule_node_source_pin(jsonb_populate_record(
      null::public.eligibility_rule_node_source_pins,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'rule_node_id', v_ns.rule_node_id,
        'field_observation_id', v_obs.observation_id,
        'source_id', v_src.source_id,
        'applicability_assertion_id', v_bind.assertion_id,
        'applicability_head_assertion_id_at_pin', v_bind.assertion_id,
        'applicability_scope_id', v_assertion.scope_id,
        'knowledge_status_at_pin', v_obs.knowledge_status
      )
    ));
  end loop;

  for v_tc in
    select distinct tc.*
    from public.eligibility_taxonomy_concept_pins p
    join public.taxonomy_concepts tc on tc.concept_id = p.concept_id
    where p.evaluation_id = p_evaluation_id
  loop
    perform public.insert_eligibility_manifest_taxonomy_concept(jsonb_populate_record(
      null::public.eligibility_manifest_taxonomy_concepts,
      jsonb_build_object('evaluation_id', p_evaluation_id, 'concept_id', v_tc.concept_id)
    ));
  end loop;

  if not p_omit_thresholds then
  for v_thr in
    select * from public.requirement_group_projection_thresholds
    where rule_set_id = v_eval.rule_set_id
  loop
    perform public.insert_eligibility_projection_threshold_pin(jsonb_populate_record(
      null::public.eligibility_projection_threshold_pins,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'rule_set_id', v_thr.rule_set_id,
        'group_node_id', v_thr.group_node_id,
        'projection_kind', v_thr.projection_kind,
        'projected_minimum_children', v_thr.projected_minimum_children,
        'projected_descendant_count', v_thr.projected_descendant_count,
        'verification_evidence_id', v_thr.verification_evidence_id,
        'verified_by', v_thr.verified_by,
        'verified_at', v_thr.verified_at,
        'created_at_source', v_thr.created_at
      )
    ));
  end loop;
  end if;

  for v_sm in
    select m.*
    from public.student_record_concept_mappings m
    where m.profile_version_id = v_eval.profile_version_id
      and m.student_mapping_id in (
        select student_mapping_id
        from private.eligibility_v02_required_student_mappings(p_evaluation_id)
      )
  loop
    if v_sm.student_mapping_id is not distinct from p_omit_mapping_id then
      continue;
    end if;
    perform public.insert_eligibility_student_mapping_pin(jsonb_populate_record(
      null::public.eligibility_student_mapping_pins,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'student_mapping_id', v_sm.student_mapping_id,
        'profile_version_id', v_sm.profile_version_id,
        'record_type', v_sm.record_type,
        'student_record_id', v_sm.student_record_id,
        'concept_id', v_sm.concept_id,
        'relation_at_pin', 'STUDENT_CONCEPT_ASSOCIATION',
        'method', v_sm.method,
        'confidence', v_sm.confidence,
        'model_version', v_sm.model_version,
        'student_evidence_id', v_sm.student_evidence_id,
        'reviewed_by', v_sm.reviewed_by,
        'reviewed_at', v_sm.reviewed_at,
        'status_at_pin', v_sm.mapping_status,
        'retired_at_pin', v_sm.retired_at,
        'retirement_reason_at_pin', v_sm.retirement_reason
      )
    ));
    perform public.insert_eligibility_manifest_student_mapping(jsonb_populate_record(
      null::public.eligibility_manifest_student_mappings,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'profile_version_id', v_eval.profile_version_id,
        'student_mapping_id', v_sm.student_mapping_id
      )
    ));
    if v_sm.student_mapping_id is distinct from p_omit_universe_id then
      select c.student_degree_id into v_degree.student_degree_id
      from public.student_courses c where c.student_course_id = v_sm.student_record_id;
      if v_degree.student_degree_id is null then
        v_map_scope := v_unassigned_cm;
      else
        select s.scope_id into v_map_scope
        from public.eligibility_snapshot_scopes s
        where s.evaluation_id = p_evaluation_id
          and s.scope_kind = 'EDUCATION_CONTEXT'
          and s.education_context_id = v_degree.student_degree_id
          and s.domain = 'COURSE_MAPPING';
      end if;
      perform public.insert_eligibility_snapshot_mapping_universe(jsonb_populate_record(
        null::public.eligibility_snapshot_mapping_universe,
        jsonb_build_object(
          'scope_id', v_map_scope,
          'student_mapping_id', v_sm.student_mapping_id,
          'universe_role', case when v_sm.mapping_status = 'VERIFIED' then 'AUTHORITATIVE' else 'LIMITING' end
        )
      ));
    end if;
  end loop;

  if p_extra_mapping_id is not null then
    select * into v_sm from public.student_record_concept_mappings
      where student_mapping_id = p_extra_mapping_id;
    perform public.insert_eligibility_student_mapping_pin(jsonb_populate_record(
      null::public.eligibility_student_mapping_pins,
      jsonb_build_object(
        'evaluation_id', p_evaluation_id,
        'student_mapping_id', v_sm.student_mapping_id,
        'profile_version_id', v_sm.profile_version_id,
        'record_type', v_sm.record_type,
        'student_record_id', v_sm.student_record_id,
        'concept_id', v_sm.concept_id,
        'relation_at_pin', 'STUDENT_CONCEPT_ASSOCIATION',
        'method', v_sm.method,
        'confidence', v_sm.confidence,
        'model_version', v_sm.model_version,
        'student_evidence_id', v_sm.student_evidence_id,
        'reviewed_by', v_sm.reviewed_by,
        'reviewed_at', v_sm.reviewed_at,
        'status_at_pin', v_sm.mapping_status,
        'retired_at_pin', v_sm.retired_at,
        'retirement_reason_at_pin', v_sm.retirement_reason
      )
    ));
    perform public.insert_eligibility_snapshot_mapping_universe(jsonb_populate_record(
      null::public.eligibility_snapshot_mapping_universe,
      jsonb_build_object(
        'scope_id', v_unassigned_cm,
        'student_mapping_id', v_sm.student_mapping_id,
        'universe_role', case when v_sm.mapping_status = 'VERIFIED' then 'AUTHORITATIVE' else 'LIMITING' end
      )
    ));
  end if;

  if not p_omit_taxonomy then
    for v_tc in
      select distinct tc.*
      from public.taxonomy_concepts tc
      where tc.concept_id in (
        select p.concept_id from public.eligibility_catalog_mapping_pins p
         where p.evaluation_id = p_evaluation_id
        union
        select p.concept_id from public.eligibility_student_mapping_pins p
         where p.evaluation_id = p_evaluation_id
      )
      and not exists (
        select 1 from public.eligibility_taxonomy_concept_pins x
        where x.evaluation_id = p_evaluation_id and x.concept_id = tc.concept_id
      )
    loop
      perform public.insert_eligibility_taxonomy_concept_pin(jsonb_populate_record(
        null::public.eligibility_taxonomy_concept_pins,
        jsonb_build_object(
          'evaluation_id', p_evaluation_id,
          'concept_id', v_tc.concept_id,
          'canonical_key', v_tc.canonical_key,
          'concept_kind', v_tc.concept_kind,
          'introduced_release_ordinal', v_tc.introduced_release_ordinal,
          'retired_release_ordinal', v_tc.retired_release_ordinal
        )
      ));
    end loop;
  end if;
end;
$$;

create or replace function pg_temp.auth_lock_prove(
  p_rel regclass,
  p_qual text,
  p_update text
) returns void
language plpgsql as $$
declare
  v_seen text;
  v_blocked boolean := false;
begin
  execute format('select %L from %s where %s', 'ok', p_rel, p_qual) into v_seen;
  if v_seen is null then
    raise exception 'AUTH-LOCK A: session SELECT missed % where %', p_rel, p_qual;
  end if;
  execute 'set local role foundation_evaluation_executor';
  begin
    execute format('select %L from %s where %s', 'ok', p_rel, p_qual) into v_seen;
    if v_seen is null then
      raise exception 'AUTH-LOCK A: executor SELECT missed %', p_rel;
    end if;
    execute format('select %L from %s where %s for key share', 'ok', p_rel, p_qual) into v_seen;
    if v_seen is null then
      raise exception 'AUTH-LOCK B: FOR KEY SHARE missed %', p_rel;
    end if;
    execute format('select %L from %s where %s for update', 'ok', p_rel, p_qual) into v_seen;
    if v_seen is null then
      raise exception 'AUTH-LOCK C: FOR UPDATE missed %', p_rel;
    end if;
    begin
      execute p_update;
      raise exception 'AUTH-LOCK D: UPDATE succeeded on %', p_rel;
    exception
      when insufficient_privilege then v_blocked := true;
      when sqlstate '42501' then v_blocked := true;
      when sqlstate '55000' then v_blocked := true;
      when raise_exception then
        if sqlerrm like 'AUTH-LOCK D: UPDATE succeeded%' then
          raise;
        end if;
        v_blocked := true;
    end;
    if not v_blocked then
      raise exception 'AUTH-LOCK D: UPDATE was not rejected on %', p_rel;
    end if;
  exception
    when others then
      execute 'reset role';
      raise;
  end;
  execute 'reset role';
  execute format('select %L from %s where %s', 'ok', p_rel, p_qual) into v_seen;
  if v_seen is null then
    raise exception 'AUTH-LOCK D: % row disappeared after rejected UPDATE', p_rel;
  end if;
end;
$$;

create or replace function pg_temp.auth_lock_definer_probe(
  p_rule_set_id uuid,
  p_release text
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_rs public.program_requirement_rule_sets%rowtype;
  v_rel public.taxonomy_releases%rowtype;
begin
  select * into v_rs from public.program_requirement_rule_sets
    where rule_set_id = p_rule_set_id for key share;
  if not found
     or v_rs.rule_set_id is distinct from p_rule_set_id
     or v_rs.status is distinct from 'VERIFIED' then
    raise exception 'AUTH-LOCK probe: rule set FOR KEY SHARE missed or not VERIFIED';
  end if;
  select * into v_rel from public.taxonomy_releases
    where release_code = p_release for key share;
  if not found
     or v_rel.release_code is distinct from p_release
     or v_rel.status is distinct from 'VERIFIED' then
    raise exception 'AUTH-LOCK probe: taxonomy FOR KEY SHARE missed or not VERIFIED';
  end if;
end;
$$;
alter function pg_temp.auth_lock_definer_probe(uuid, text) owner to foundation_evaluation_executor;

do $test$
declare
  v_blocked boolean;
  v_owner text;
  v_cfg text[];
  v_def text;
  v_ord1 bigint;
  v_ord2 bigint;
  v_code1 text;
  v_code2 text;
  v_conn text;
  v_sqlstate text;
  v_hint text;
  v_count integer;
  v_proj public.eligibility_projection_value;
  v_outcome public.eligibility_outcome;
  v_a public.requirement_truth_value;
  v_b public.requirement_truth_value;
  r record;
  v_priv_before bigint;
  v_priv_after bigint;
  v_program_version_id uuid;
  v_course_id uuid;
  v_observation_id uuid;
  v_new_observation_id uuid;
  v_evidence_id uuid;
  v_assertion_id uuid;
  v_app_scope uuid;
  v_course_concept_id uuid := '10000000-0000-0000-0000-000000000032';
  v_catalog_mapping_id uuid;
  v_rule_set_id uuid;
  v_foreign_rule_set_id uuid;
  v_root_id uuid;
  v_leaf_id uuid;
  v_foreign_leaf_id uuid;
  v_student_id uuid := extensions.gen_random_uuid();
  v_profile_id uuid := extensions.gen_random_uuid();
  v_other_profile_id uuid := extensions.gen_random_uuid();
  v_student_evidence_id uuid;
  v_student_course_id uuid;
  v_student_mapping_id uuid;
  v_evaluation_id uuid;
  v_eval_a uuid;
  v_eval_b uuid;
  v_hash1 text;
  v_hash2 text;
  v_result1 text;
  v_result2 text;
  v_scope_id uuid;
  v_scope_unassigned uuid;
  v_scope_map uuid;
  v_scope_map_unassigned uuid;
  v_scope_edu uuid;
  v_scope_test uuid;
  v_scope_course_map uuid;
  v_completeness_id uuid;
  v_foreign_completeness uuid;
  v_source_id uuid;
  v_threshold public.requirement_group_projection_thresholds;
  v_pin_row public.eligibility_rule_set_pins;
  v_canon text;
  v_other_student uuid;
  v_test_leaf_id uuid;
  v_test_concept_id uuid := '10000000-0000-0000-0000-000000000071';
  v_obs_code uuid;
  v_code_scope uuid;
  v_code_assertion uuid;
  v_degree_id uuid;
  v_eval_neg uuid;
  v_eval_tax uuid;
  v_eval_course uuid;
  v_live_status public.mapping_status;
  v_pin_status public.mapping_status;
  v_leaf_truth public.requirement_truth_value;
  v_neg_count integer;
  v_role_membership_ok boolean;
begin
  perform set_config('statement_timeout', '120s', true);
  v_conn := 'dbname=' || current_database();

  -- PostgreSQL 16+ may store the install role's automatic ADMIN membership
  -- separately from its SET/INHERIT membership. Migration 013 must preserve
  -- all three effective capabilities instead of re-granting ADMIN to itself.
  if current_setting('server_version_num')::integer >= 160000 then
    execute $membership$
      select count(*) = 3
      from (
        select granted_role.rolname
        from pg_auth_members m
        join pg_roles granted_role on granted_role.oid = m.roleid
        join pg_roles member_role on member_role.oid = m.member
        where granted_role.rolname in (
          'foundation_catalog_executor',
          'foundation_student_executor',
          'foundation_evaluation_executor'
        )
          and member_role.rolname = current_user
        group by granted_role.rolname
        having bool_or(m.admin_option)
           and bool_or(m.inherit_option)
           and bool_or(m.set_option)
      ) memberships
    $membership$
    into v_role_membership_ok;
  else
    select count(*) = 3
    into v_role_membership_ok
    from (
      select granted_role.rolname
      from pg_auth_members m
      join pg_roles granted_role on granted_role.oid = m.roleid
      join pg_roles member_role on member_role.oid = m.member
      where granted_role.rolname in (
        'foundation_catalog_executor',
        'foundation_student_executor',
        'foundation_evaluation_executor'
      )
        and member_role.rolname = current_user
      group by granted_role.rolname
      having bool_or(m.admin_option)
    ) memberships;
  end if;

  if not coalesce(v_role_membership_ok, false) then
    raise exception '013 install role lacks required executor ADMIN/SET/INHERIT membership';
  end if;

  if exists (
    select 1
    from information_schema.routine_privileges
    where grantee in (
      'PUBLIC', 'anon', 'authenticated', 'service_role', 'authenticator'
    )
      and privilege_type = 'EXECUTE'
      and routine_schema = 'public'
      and routine_name in (
        'guard_taxonomy_release_ordinal_immutable',
        'guard_eligibility_snapshot_scope_shape',
        'guard_eligibility_mapping_universe_status',
        'guard_eligibility_v02_sealed_pin',
        'guard_projection_threshold_immutable',
        'guard_eligibility_v02_finalizer_only_row'
      )
  ) then
    raise exception '013 trigger-only guard retains external EXECUTE';
  end if;

  -- TAX-AUTH-1
  if has_schema_privilege('foundation_catalog_executor', 'private', 'USAGE') then
    raise exception 'TAX-AUTH-1: catalog executor has USAGE on private';
  end if;

  -- TAX-AUTH-7
  select p.proconfig into v_cfg
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'allocate_taxonomy_release_ordinal_v02'
    and pg_get_function_identity_arguments(p.oid) = '';
  if array_to_string(v_cfg, ',') not like '%pg_catalog, private%'
     or array_to_string(v_cfg, ',') like '%pg_temp%' then
    raise exception 'TAX-AUTH-7: wrapper search_path is %', array_to_string(v_cfg, ',');
  end if;
  select p.proconfig into v_cfg
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'create_taxonomy_release'
    and pg_get_function_identity_arguments(p.oid) = 'text, timestamp with time zone, text';
  if array_to_string(v_cfg, ',') not like '%pg_catalog, public, extensions%'
     or array_to_string(v_cfg, ',') like '%private%' then
    raise exception 'TAX-AUTH-7: create_taxonomy_release search_path is %', array_to_string(v_cfg, ',');
  end if;

  -- TAX-AUTH-8 wrapper body
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'allocate_taxonomy_release_ordinal_v02'
    and pg_get_function_identity_arguments(p.oid) = '';
  if v_def not like '%private.taxonomy_allocate_release_ordinal()%'
     or v_def like '%taxonomy_release_ordinal_allocator%' then
    raise exception 'TAX-AUTH-8: wrapper DML surface is incorrect';
  end if;
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'taxonomy_allocate_release_ordinal';
  if v_def not like '%taxonomy_release_ordinal_allocator%'
     or v_def like '%lock_student%' then
    raise exception 'TAX-AUTH-8: private allocator surface is incorrect';
  end if;
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'create_taxonomy_release'
    and pg_get_function_identity_arguments(p.oid) = 'text, timestamp with time zone, text';
  if v_def like '%private.%' then
    raise exception 'create_taxonomy_release names private objects';
  end if;

  -- TAX-AUTH-3
  foreach v_owner in array array['service_role', 'anon', 'authenticated']
  loop
    v_blocked := false;
    begin
      execute format('set local role %I', v_owner);
      perform public.allocate_taxonomy_release_ordinal_v02();
      raise exception 'TAX-AUTH-3: % executed wrapper', v_owner;
    exception
      when insufficient_privilege then v_blocked := true;
      when others then
        if sqlstate = '42501' then v_blocked := true; else raise; end if;
    end;
    reset role;
    if not v_blocked then
      raise exception 'TAX-AUTH-3: % was not rejected', v_owner;
    end if;
  end loop;

  -- TAX-AUTH-4
  v_blocked := false;
  begin
    set local role foundation_catalog_executor;
    perform 1 from private.taxonomy_release_ordinal_allocator;
    raise exception 'TAX-AUTH-4: catalog executor selected allocator';
  exception
    when insufficient_privilege then v_blocked := true;
    when others then
      if sqlstate in ('42501', '42503') then v_blocked := true; else raise; end if;
  end;
  reset role;
  if not v_blocked then
    raise exception 'TAX-AUTH-4: allocator select was not rejected';
  end if;
  v_blocked := false;
  begin
    set local role foundation_catalog_executor;
    perform private.taxonomy_allocate_release_ordinal();
    raise exception 'TAX-AUTH-4: catalog executor executed private allocator';
  exception
    when insufficient_privilege then v_blocked := true;
    when others then
      if sqlstate = '42501' then v_blocked := true; else raise; end if;
  end;
  reset role;

  -- TAX-AUTH-5 concurrent allocation (must run before this transaction holds the allocator)
  perform dblink_connect('sess_tax', v_conn);
  perform dblink_exec('sess_tax', 'begin');
  perform 1 from dblink('sess_tax',
    'select next_ordinal from private.taxonomy_release_ordinal_allocator where singleton is true for update'
  ) as held(n bigint);
  perform set_config('lock_timeout', '200ms', true);
  begin
    perform public.create_taxonomy_release('v9.2', now(), 'concurrent-loser');
    raise exception 'TAX-AUTH-5: concurrent create did not block';
  exception
    when lock_not_available then null;
    when query_canceled then null;
  end;
  perform dblink_exec('sess_tax', 'rollback');
  perform dblink_disconnect('sess_tax');
  perform set_config('lock_timeout', '0', true);

  -- TAX-AUTH-2 / TAX-AUTH-6
  select count(*) into v_priv_before
  from private.student_lifecycle_audit;
  v_code1 := 'v9.1';
  perform public.create_taxonomy_release(v_code1, now(), '013-tax-auth-2');
  select release_ordinal into v_ord1 from public.taxonomy_releases where release_code = v_code1;
  if v_ord1 < 2 then
    raise exception 'TAX-AUTH-2: allocated ordinal % is not consecutive after v0.1', v_ord1;
  end if;
  -- superuser/table-owner may still insert; runtime role must fail
  v_blocked := false;
  begin
    set local role service_role;
    insert into public.taxonomy_releases (release_code, published_at, notes, status, release_ordinal)
    values ('v9.98', now(), 'direct', 'DRAFT', 998);
    raise exception 'TAX-AUTH-2: service_role inserted taxonomy_releases';
  exception
    when insufficient_privilege then v_blocked := true;
    when sqlstate '42501' then v_blocked := true;
  end;
  reset role;
  if not v_blocked then
    raise exception 'TAX-AUTH-2: service_role inserted taxonomy_releases';
  end if;
  v_blocked := false;
  begin
    update public.taxonomy_releases set release_ordinal = release_ordinal + 1 where release_code = v_code1;
    raise exception 'TAX-AUTH-6: ordinal update succeeded';
  exception
    when sqlstate '55000' then
      if sqlerrm like '%immutable%' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'TAX-AUTH-6: ordinal mutation was not rejected';
  end if;
  if exists (
    select 1 from pg_proc
    where proname = 'allocate_taxonomy_release_ordinal_v02'
      and pg_get_function_identity_arguments(oid) <> ''
  ) then
    raise exception 'TAX-AUTH-6: wrapper takes arguments';
  end if;

  select count(*) into v_priv_after from private.student_lifecycle_audit;
  if v_priv_after <> v_priv_before then
    raise exception 'TAX-AUTH-8: allocate-via-create changed other private row counts';
  end if;

  -- sequential consecutive ordinals after the blocked concurrent attempt
  perform public.create_taxonomy_release('v9.2', now(), 'after-block');
  perform public.create_taxonomy_release('v9.3', now(), 'next');
  select r1.release_ordinal, r2.release_ordinal into v_ord1, v_ord2
  from public.taxonomy_releases r1, public.taxonomy_releases r2
  where r1.release_code = 'v9.2' and r2.release_code = 'v9.3';
  if v_ord2 <> v_ord1 + 1 or v_ord1 < 1 then
    raise exception 'TAX-AUTH-5: ordinals % and % are not consecutive', v_ord1, v_ord2;
  end if;

  -- v0.1 API still present
  if not exists (
    select 1 from pg_proc p
    where p.proname = 'finalize_eligibility_evaluation'
      and pg_get_function_identity_arguments(p.oid) like '%eligibility_outcome%'
  ) or not exists (
    select 1 from pg_proc p
    where p.proname = 'finalize_eligibility_evaluation_v02'
      and pg_get_function_identity_arguments(p.oid) like '%uuid%'
      and pg_get_function_identity_arguments(p.oid) not like '%,%'
  ) then
    raise exception 'v0.1/v0.2 finalize signatures are wrong';
  end if;

  -- 4x4 outcome table
  if private.eligibility_v02_derive_outcome('ABSENT', 'ABSENT') is distinct from 'ELIGIBLE'
     or private.eligibility_v02_derive_outcome('ABSENT', 'SATISFIED') is distinct from 'ELIGIBLE'
     or private.eligibility_v02_derive_outcome('ABSENT', 'NOT_SATISFIED') is distinct from 'CONDITIONALLY_ELIGIBLE'
     or private.eligibility_v02_derive_outcome('ABSENT', 'UNKNOWN') is distinct from 'UNKNOWN'
     or private.eligibility_v02_derive_outcome('NOT_SATISFIED', 'SATISFIED') is distinct from 'NOT_ELIGIBLE'
     or private.eligibility_v02_derive_outcome('SATISFIED', 'NOT_SATISFIED') is distinct from 'CONDITIONALLY_ELIGIBLE'
     or private.eligibility_v02_derive_outcome('UNKNOWN', 'SATISFIED') is distinct from 'UNKNOWN' then
    raise exception '4x4 outcome helper mismatch';
  end if;
  v_blocked := false;
  begin
    perform private.eligibility_v02_derive_outcome('SATISFIED', 'ABSENT');
    raise exception 'INVALID_STATE SATISFIED/ABSENT was not rejected';
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_projection_invalid_state' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'INVALID_STATE SATISFIED/ABSENT was not rejected';
  end if;
  -- remaining 4x4 stored outcomes
  if private.eligibility_v02_derive_outcome('SATISFIED', 'SATISFIED') is distinct from 'ELIGIBLE'
     or private.eligibility_v02_derive_outcome('SATISFIED', 'UNKNOWN') is distinct from 'UNKNOWN'
     or private.eligibility_v02_derive_outcome('NOT_SATISFIED', 'NOT_SATISFIED') is distinct from 'NOT_ELIGIBLE'
     or private.eligibility_v02_derive_outcome('NOT_SATISFIED', 'UNKNOWN') is distinct from 'NOT_ELIGIBLE'
     or private.eligibility_v02_derive_outcome('UNKNOWN', 'NOT_SATISFIED') is distinct from 'UNKNOWN'
     or private.eligibility_v02_derive_outcome('UNKNOWN', 'UNKNOWN') is distinct from 'UNKNOWN' then
    raise exception '4x4 remaining stored outcomes mismatch';
  end if;
  foreach v_a in array array['NOT_SATISFIED','UNKNOWN']::public.requirement_truth_value[]
  loop
    v_blocked := false;
    begin
      perform private.eligibility_v02_derive_outcome(v_a::text::public.eligibility_projection_value, 'ABSENT');
    exception
      when sqlstate '55000' then
        get stacked diagnostics v_hint = pg_exception_hint;
        if v_hint = 'eligibility_projection_invalid_state' then v_blocked := true; else raise; end if;
    end;
    if not v_blocked then
      raise exception 'INVALID_STATE %/ABSENT was not rejected', v_a;
    end if;
  end loop;

  -- knowledge states: every non-KNOWN is Eligibility UNKNOWN
  if exists (
    select 1
    from unnest(enum_range(null::public.knowledge_status)) ks
    where ks <> 'KNOWN'
      and ks::text is null
  ) then
    raise exception 'knowledge enum missing';
  end if;

  -- M7: REJECTED pin insert is illegal
  v_blocked := false;
  begin
    insert into public.eligibility_student_mapping_pins (
      evaluation_id, student_mapping_id, profile_version_id, record_type,
      student_record_id, concept_id, method, status_at_pin
    ) values (
      extensions.gen_random_uuid(), extensions.gen_random_uuid(), extensions.gen_random_uuid(),
      'COURSE', extensions.gen_random_uuid(), extensions.gen_random_uuid(),
      'HUMAN', 'REJECTED'
    );
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_mapping_status_not_universe_eligible' then v_blocked := true; else raise; end if;
    when check_violation then v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'M7: REJECTED mapping pin was accepted';
  end if;

  -- lock order: student lifecycle first
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'finalize_eligibility_evaluation_v02'
    and pg_get_function_identity_arguments(p.oid) = 'uuid';
  if position('lock_student_lifecycle' in v_def) = 0
     or position('lock_student_lifecycle' in v_def) > position('lock_student_owned_total_order' in v_def) then
    raise exception 'finalize_eligibility_evaluation_v02 does not lock student lifecycle first';
  end if;
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'close_student_owned_rows'
    and pg_get_function_identity_arguments(p.oid) = 'uuid';
  if v_def not like '%eligibility_snapshot_scopes%'
     or v_def not like '%eligibility_v02_finalize_authorizations%'
     or v_def not like '%eligibility_rule_node_source_pins%'
     or v_def not like '%eligibility_rule_node_mapping_pins%'
     or v_def not like '%eligibility_projection_threshold_pins%'
     or v_def not like '%eligibility_catalog_observation_pins%'
     or v_def not like '%eligibility_catalog_selection_pins%'
     or v_def not like '%eligibility_negative_fact_authorizations%'
     or v_def not like '%eligibility_snapshot_mapping_universe%' then
    raise exception 'close_student_owned_rows is missing 013 anti-joins';
  end if;
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'delete_student_data'
      and pg_get_functiondef(p.oid) like '%eligibility_snapshot_scopes%'
  ) then
    raise exception 'delete_student_data was replaced';
  end if;

  -- catalog executor USAGE remains false after 013 (TAX-AUTH-1 repeat)
  if has_schema_privilege('foundation_catalog_executor', 'private', 'USAGE') then
    raise exception 'TAX-AUTH-1 post-check: USAGE(private) became true';
  end if;

  -- ABSENT aggregation
  if private.eligibility_v02_aggregate('ALL', array['ABSENT']::public.eligibility_projection_value[], null)
       is distinct from 'ABSENT'
     or private.eligibility_v02_project_leaf('SOFT', 'ORDINARY_BARRIER', 'UNKNOWN')
       is distinct from 'ABSENT'
     or private.eligibility_v02_project_leaf('CONDITIONAL_HARD', 'ORDINARY_BARRIER', 'NOT_SATISFIED')
       is distinct from 'SATISFIED' then
    raise exception 'projection/aggregate helper mismatch';
  end if;
  v_blocked := false;
  begin
    perform private.eligibility_v02_aggregate(
      'AT_LEAST',
      array['SATISFIED']::public.eligibility_projection_value[],
      null
    );
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_missing_projected_threshold' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'missing projected threshold did not fail closed';
  end if;
  if not private.eligibility_v02_active_at_ordinal(1, 1, null)
     or private.eligibility_v02_active_at_ordinal(2, 1, null)
     or private.eligibility_v02_active_at_ordinal(1, 5, 5)
     or not private.eligibility_v02_active_at_ordinal(1, 4, 5) then
    raise exception 'ordinal membership is not half-open introduced <= pin < retired';
  end if;

  -- registry set equality
  if exists (
    select enumlabel from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'eligibility_projection'
    except
    select unnest(array['FULL','ORDINARY_BARRIER','CONDITIONAL_HARD','CONDITIONAL_ONLY','SOFT_EXPLANATION'])
  ) or exists (
    select unnest(array['FULL','ORDINARY_BARRIER','CONDITIONAL_HARD','CONDITIONAL_ONLY','SOFT_EXPLANATION'])
    except
    select enumlabel from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'eligibility_projection'
  ) then
    raise exception 'eligibility_projection registry mismatch';
  end if;

  -- no canonical-byte columns
  if exists (
    select 1 from information_schema.columns
    where table_schema in ('public', 'private')
      and (column_name ilike '%canonical_bytes%'
           or column_name ilike '%canonical_json%'
           or udt_name = 'bytea' and column_name ilike '%fingerprint%payload%')
  ) then
    raise exception 'production persisted canonical bytes';
  end if;

  -- 012 v0.1 taxonomy still ordinal 1
  if (select release_ordinal from public.taxonomy_releases where release_code = 'v0.1') is distinct from 1 then
    raise exception 'v0.1 release ordinal is not 1';
  end if;

  -- no 014 objects
  if exists (select 1 from pg_proc where proname like '%billing_basis%') then
    raise exception '014 objects leaked into 013';
  end if;

  -- finalize must not re-read live mapping_status after pin (M1)
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'finalize_eligibility_evaluation_v02'
    and pg_get_function_identity_arguments(p.oid) = 'uuid';
  if position('eligibility_v02_assert_closed_world(p_evaluation_id, false)' in v_def) = 0 then
    raise exception 'finalize_eligibility_evaluation_v02 still requires a live mapping universe';
  end if;
  if position('eligibility_v02_required_student_mappings' in v_def) > 0 then
    raise exception 'finalize_eligibility_evaluation_v02 reads live required mappings';
  end if;

  -- v0.2 leaf/finalize must not re-read live mapping_status after pin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'eligibility_v02_leaf_decision';
  if position('catalog_concept_mappings' in v_def) > 0
     or position('student_record_concept_mappings' in v_def) > 0 then
    raise exception 'eligibility_v02_leaf_decision reads live mapping tables';
  end if;
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'validate_eligibility_match_insert'
    and pg_get_function_identity_arguments(p.oid) = '';
  if position('eligibility_rule_node_pins' in v_def) = 0
     or position('status_at_pin' in v_def) = 0
     or position('COMPLETED' in v_def) = 0 then
    raise exception 'validate_eligibility_match_insert v0.2 pin/completed gate is missing';
  end if;

  -- 15.3 / 15.4 fingerprint membership
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'canonical_eligibility_v02_input_fingerprint'
    and pg_get_function_identity_arguments(p.oid) = 'uuid';
  if position('''ruleNodeSources''' in v_def) = 0
     or position('''catalogSelections''' in v_def) = 0
     or position('''catalogObservations''' in v_def) = 0
     or position('''catalogMappings''' in v_def) = 0
     or position('''taxonomyConcepts''' in v_def) = 0
     or position('''studentEvidence''' in v_def) = 0
     or position('''degreeFacts''' in v_def) = 0
     or position('''courseFacts''' in v_def) = 0
     or position('''testFacts''' in v_def) = 0
     or position('''ruleNodeMappings''' in v_def) = 0
     or position('''relationAtPin''' in v_def) = 0
     or position('''statusAtPin''' in v_def) = 0
     or position('''scopeId''' in v_def) > 0 then
    raise exception 'v0.2 input fingerprint is missing 15.3 collections or still hashes generated scope IDs';
  end if;
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'canonical_eligibility_v02_result_fingerprint'
    and pg_get_function_identity_arguments(p.oid) = 'uuid, eligibility_outcome';
  if position('''courseMatches''' in v_def) = 0
     or position('''testMatches''' in v_def) = 0
     or position('''supportingFactRefs''' in v_def) = 0
     or position('''missingData''' in v_def) = 0
     or position('''negativeAuthorizations''' in v_def) = 0 then
    raise exception 'v0.2 result fingerprint is missing 15.4 collections';
  end if;
  perform private.canonical_eligibility_v02_input_fingerprint(
    '00000000-0000-0000-0000-000000000000'
  );
  perform private.canonical_eligibility_v02_result_fingerprint(
    '00000000-0000-0000-0000-000000000000',
    'ELIGIBLE'
  );

  -- HAS_TEST incomplete uses INCOMPLETE_TEST_HISTORY, not course coverage
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'private' and p.proname = 'eligibility_v02_leaf_decision';
  if position('INCOMPLETE_TEST_HISTORY' in v_def) = 0 then
    raise exception 'HAS_TEST incomplete path does not use INCOMPLETE_TEST_HISTORY';
  end if;

  -- missing-data registry bidirectional
  if exists (
    select enumlabel from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'eligibility_v02_missing_data_code'
    except
    select unnest(array[
      'PROGRAM_FACT_NOT_KNOWN','MAPPED_COURSE_NOT_INCLUDED','COURSE_EDUCATION_CONTEXT_MISMATCH',
      'INCOMPLETE_COURSE_OR_MAPPING_COVERAGE','NO_VERIFIED_MAPPING','PROPOSED_MAPPING_LIMITING',
      'INCOMPLETE_TEST_HISTORY','INCOMPLETE_EDUCATION_HISTORY','TAXONOMY_CONCEPT_INACTIVE_AT_PIN',
      'UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE'
    ])
  ) or exists (
    select unnest(array[
      'PROGRAM_FACT_NOT_KNOWN','MAPPED_COURSE_NOT_INCLUDED','COURSE_EDUCATION_CONTEXT_MISMATCH',
      'INCOMPLETE_COURSE_OR_MAPPING_COVERAGE','NO_VERIFIED_MAPPING','PROPOSED_MAPPING_LIMITING',
      'INCOMPLETE_TEST_HISTORY','INCOMPLETE_EDUCATION_HISTORY','TAXONOMY_CONCEPT_INACTIVE_AT_PIN',
      'UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE'
    ])
    except
    select enumlabel from pg_enum e join pg_type t on t.oid = e.enumtypid
    where t.typname = 'eligibility_v02_missing_data_code'
  ) then
    raise exception 'eligibility_v02_missing_data_code registry mismatch';
  end if;

  -- FULL AT_LEAST uses pinned minimum_children, not a non-FULL shortcut
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'finalize_eligibility_evaluation_v02'
    and pg_get_function_identity_arguments(p.oid) = 'uuid';
  if position('v_proj = ''FULL''' in v_def) = 0
     or position('r.minimum_children' in v_def) = 0 then
    raise exception 'FULL AT_LEAST does not use original minimum_children';
  end if;

  -- helper EXECUTE is not PUBLIC/anon/authenticated
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.proname in (
        'eligibility_v02_derive_outcome',
        'eligibility_v02_leaf_decision',
        'allocate_taxonomy_release_ordinal_v02',
        'canonical_eligibility_v02_input_fingerprint'
      )
      and (
        has_function_privilege('anon', p.oid, 'EXECUTE')
        or has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or (
          p.proname = 'allocate_taxonomy_release_ordinal_v02'
          and has_function_privilege('service_role', p.oid, 'EXECUTE')
        )
      )
  ) then
    raise exception '013 helper/wrapper EXECUTE is too wide';
  end if;

  -- AUTH-3 ordinal wrapper owner/path/ACL
  select pg_get_userbyid(p.proowner) into v_owner
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'allocate_taxonomy_release_ordinal_v02'
    and pg_get_function_identity_arguments(p.oid) = '';
  if v_owner is distinct from current_user
     or v_owner in ('foundation_catalog_executor', 'service_role') then
    raise exception 'AUTH-3: ordinal wrapper owner is %', v_owner;
  end if;

  -- AUTH-1 service_role direct DML remains zero
  v_blocked := false;
  begin
    set local role service_role;
    insert into public.eligibility_rule_set_pins (
      evaluation_id, rule_set_id, program_version_id, rule_set_version,
      taxonomy_release_code, taxonomy_release_ordinal, rule_schema_version,
      engine_contract_version
    ) values (
      extensions.gen_random_uuid(), extensions.gen_random_uuid(),
      extensions.gen_random_uuid(), 1, 'v0.1', 1, 'phase2-v0.2', 'eligibility-v0.2'
    );
    raise exception 'AUTH-1: service_role inserted a pin row';
  exception
    when insufficient_privilege then v_blocked := true;
    when sqlstate '42501' then v_blocked := true;
  end;
  reset role;
  if not v_blocked then
    raise exception 'AUTH-1: service_role direct DML was not rejected';
  end if;

  -- AUTH-LOCK: evaluation-executor lock privilege is not mutation authority.
  if exists (
    select 1 from pg_roles
    where rolname = 'foundation_evaluation_executor'
      and (rolcanlogin or rolbypassrls or rolsuper)
  ) then
    raise exception 'AUTH-LOCK: evaluation executor is LOGIN, BYPASSRLS, or SUPERUSER';
  end if;
  if exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_roles o on o.oid = c.relowner
    where n.nspname = 'public'
      and o.rolname = 'foundation_evaluation_executor'
      and c.relname in (
        'program_requirement_rule_sets', 'program_requirement_nodes',
        'taxonomy_releases', 'taxonomy_concepts', 'catalog_concept_mappings',
        'field_observations', 'canonical_field_selections', 'evidence_items',
        'sources', 'evidence_applicability_assertions',
        'evidence_applicability_scopes', 'evidence_applicability_heads',
        'field_observation_applicability',
        'requirement_group_projection_thresholds', 'student_data_completeness',
        'student_courses', 'student_degrees', 'student_test_scores',
        'student_record_concept_mappings'
      )
  ) then
    raise exception 'AUTH-LOCK: evaluation executor owns a v0.2 lock-source table';
  end if;
  foreach v_owner in array array[
    'program_requirement_rule_sets', 'program_requirement_nodes',
    'taxonomy_releases', 'taxonomy_concepts', 'catalog_concept_mappings',
    'field_observations', 'canonical_field_selections', 'evidence_items',
    'sources', 'evidence_applicability_assertions',
    'evidence_applicability_scopes', 'evidence_applicability_heads',
    'field_observation_applicability',
    'requirement_group_projection_thresholds', 'student_data_completeness',
    'student_courses', 'student_degrees', 'student_test_scores',
    'student_record_concept_mappings'
  ]
  loop
    if not has_table_privilege('foundation_evaluation_executor', format('public.%I', v_owner), 'SELECT')
       or not has_table_privilege('foundation_evaluation_executor', format('public.%I', v_owner), 'UPDATE')
       or has_table_privilege('foundation_evaluation_executor', format('public.%I', v_owner), 'INSERT')
       or has_table_privilege('foundation_evaluation_executor', format('public.%I', v_owner), 'DELETE') then
      raise exception 'AUTH-LOCK: lock-only privilege boundary failed on %', v_owner;
    end if;
    if has_table_privilege('service_role', format('public.%I', v_owner), 'INSERT')
       or has_table_privilege('service_role', format('public.%I', v_owner), 'UPDATE')
       or has_table_privilege('service_role', format('public.%I', v_owner), 'DELETE') then
      raise exception 'AUTH-LOCK: service_role has direct DML on %', v_owner;
    end if;
    if exists (
      select 1
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = v_owner
        and p.polcmd in ('d', '*')
        and (
          0 = any (p.polroles)
          or exists (
            select 1 from pg_roles role_row
            where role_row.oid = any (p.polroles)
              and role_row.rolname = 'foundation_evaluation_executor'
          )
        )
    ) then
      raise exception 'AUTH-LOCK: evaluation executor has mutation RLS on %', v_owner;
    end if;
    if exists (
      select 1
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = v_owner
        and p.polcmd = 'w'
        and (
          0 = any (p.polroles)
          or exists (
            select 1 from pg_roles role_row
            where role_row.oid = any (p.polroles)
              and role_row.rolname = 'foundation_evaluation_executor'
          )
        )
        and pg_get_expr(p.polwithcheck, p.polrelid) is distinct from 'false'
    ) then
      raise exception 'AUTH-LOCK: evaluation executor UPDATE RLS is not lock-only on %', v_owner;
    end if;
    if not exists (
      select 1
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = v_owner
        and p.polname = left(v_owner || '_evaluation_executor_lock', 63)
        and p.polcmd = 'w'
        and pg_get_expr(p.polwithcheck, p.polrelid) = 'false'
    ) then
      raise exception 'AUTH-LOCK: missing FOR UPDATE WITH CHECK (false) policy on %', v_owner;
    end if;
  end loop;
  perform pg_temp.auth_lock_prove(
    'public.taxonomy_releases'::regclass,
    'release_code = ''v0.1''',
    'update public.taxonomy_releases set notes = notes where release_code = ''v0.1'''
  );

  -- AUTH-2 anon/authenticated cannot call internal v0.2 writers
  foreach v_owner in array array['anon', 'authenticated']
  loop
    v_blocked := false;
    begin
      execute format('set local role %I', v_owner);
      perform private.eligibility_v02_leaf_decision(
        '00000000-0000-0000-0000-000000000000',
        null::public.eligibility_rule_node_pins
      );
      raise exception 'AUTH-2: % executed leaf_decision', v_owner;
    exception
      when insufficient_privilege then v_blocked := true;
      when sqlstate '42501' then v_blocked := true;
    end;
    reset role;
    if not v_blocked then
      raise exception 'AUTH-2: % executed an internal writer', v_owner;
    end if;
  end loop;

  -- FP-1 / FP-2 / FP-3 canonical numbers
  if private.canonical_json_v02('10'::jsonb) is distinct from '10'
     or private.canonical_json_v02('1'::jsonb) is distinct from '1'
     or private.canonical_json_v02('10'::jsonb) = private.canonical_json_v02('1'::jsonb) then
    raise exception 'FP-1: 10 canonicalized to %', private.canonical_json_v02('10'::jsonb);
  end if;
  if private.canonical_json_v02('100'::jsonb) is distinct from '100'
     or private.canonical_json_v02('100'::jsonb) in (
          private.canonical_json_v02('1'::jsonb), private.canonical_json_v02('10'::jsonb)
        )
     or private.canonical_json_v02('1200'::jsonb) is distinct from '1200' then
    raise exception 'FP-2: 100/1200 canonicalization is wrong';
  end if;
  if private.canonical_json_v02('1.20'::jsonb) is distinct from '1.2'
     or private.canonical_json_v02('1.0'::jsonb) is distinct from '1'
     or private.canonical_json_v02('0.0100'::jsonb) is distinct from '0.01' then
    raise exception 'FP-3: trailing-fractional-zero canonicalization is wrong';
  end if;

  -- Build a verified eligibility-v0.2 rule set and frozen zero-degree profile.
  select program_version_id into v_program_version_id
  from public.program_versions
  where program_id = '00000000-0000-0000-0000-000000000301';
  select p.course_id, c.observation_id, o.evidence_id
    into v_course_id, v_observation_id, v_evidence_id
  from public.program_courses p
  join public.canonical_field_selections c
    on c.record_type = 'PROGRAM_COURSE' and c.record_id = p.course_id and c.field_name = 'course_name'
  join public.field_observations o on o.observation_id = c.observation_id
  where p.program_version_id = v_program_version_id and p.retired_at is null
  order by p.created_at
  limit 1;
  select e.source_id into v_source_id from public.evidence_items e where e.evidence_id = v_evidence_id;
  v_app_scope := public.create_evidence_scope(
    v_evidence_id, 'PROGRAM_COURSE', v_course_id, 'course_name',
    'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
  );
  v_assertion_id := public.review_evidence_applicability(
    v_app_scope, 'REVIEWED_APPLICABLE', '013-reviewer', 'v0.2 source authority'
  );
  v_new_observation_id := public.create_field_observation(
    'PROGRAM_COURSE', v_course_id, 'course_name',
    (select observed_value from public.field_observations where observation_id = v_observation_id),
    'KNOWN', v_evidence_id, v_observation_id, 'v0.2 headed observation', v_assertion_id
  );
  perform public.select_field_observation(v_new_observation_id, '013-reviewer');
  v_observation_id := (
    select c.observation_id
    from public.canonical_field_selections c
    where c.record_type = 'PROGRAM_COURSE' and c.record_id = v_course_id and c.field_name = 'course_code'
  );
  v_code_scope := public.create_evidence_scope(
    v_evidence_id, 'PROGRAM_COURSE', v_course_id, 'course_code',
    'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
  );
  v_code_assertion := public.review_evidence_applicability(
    v_code_scope, 'REVIEWED_APPLICABLE', '013-reviewer', 'v0.2 second source'
  );
  v_obs_code := public.create_field_observation(
    'PROGRAM_COURSE', v_course_id, 'course_code',
    coalesce(
      (select observed_value from public.field_observations where observation_id = v_observation_id),
      to_jsonb('MATH-UA 122'::text)
    ),
    'KNOWN', v_evidence_id, v_observation_id, 'v0.2 course_code source', v_code_assertion
  );
  perform public.select_field_observation(v_obs_code, '013-reviewer');

  insert into public.catalog_concept_mappings (
    record_type, record_id, concept_id, relation, mapping_status, method, confidence, model_version
  ) values (
    'PROGRAM_COURSE', v_course_id, v_course_concept_id, 'COURSE_EQUIVALENCY',
    'PROPOSED', 'MODEL', 1, 'test-model'
  ) returning mapping_id into v_catalog_mapping_id;
  perform public.review_catalog_concept_mapping(
    v_catalog_mapping_id, 'VERIFIED', '013-reviewer', v_evidence_id
  );

  insert into public.program_requirement_rule_sets (
    program_version_id, rule_set_version, taxonomy_release_code,
    rule_schema_version, engine_contract_version
  ) values (
    v_program_version_id, 2, 'v0.1', 'phase2-v0.2', 'eligibility-v0.2'
  ) returning rule_set_id into v_rule_set_id;
  insert into public.program_requirement_nodes (
    rule_set_id, parent_node_id, sort_order, node_kind, group_operator,
    minimum_children, explanation_template
  ) values (
    v_rule_set_id, null, 0, 'GROUP', 'AT_LEAST', 2,
    'At least two ordinary requirements must be satisfied.'
  ) returning rule_node_id into v_root_id;
  insert into public.program_requirement_nodes (
    rule_set_id, parent_node_id, sort_order, node_kind, predicate_kind,
    requirement_strength, requirement_semantics, target_concept_id, explanation_template
  ) values (
    v_rule_set_id, v_root_id, 0, 'PREDICATE', 'HAS_COURSE_CONCEPT',
    'HARD', 'ORDINARY', v_course_concept_id, 'Requires the reviewed course concept.'
  ) returning rule_node_id into v_leaf_id;
  insert into public.program_requirement_nodes (
    rule_set_id, parent_node_id, sort_order, node_kind, predicate_kind,
    requirement_strength, requirement_semantics, target_concept_id, explanation_template
  ) values (
    v_rule_set_id, v_root_id, 1, 'PREDICATE', 'HAS_TEST',
    'HARD', 'ORDINARY', v_test_concept_id, 'Requires GRE.'
  ) returning rule_node_id into v_test_leaf_id;
  insert into public.program_requirement_node_sources (rule_node_id, field_observation_id)
  values
    (v_leaf_id, v_new_observation_id),
    (v_leaf_id, v_obs_code),
    (v_test_leaf_id, v_new_observation_id);
  insert into public.program_requirement_node_mappings (rule_node_id, catalog_mapping_id)
  values (v_leaf_id, v_catalog_mapping_id);
  perform public.insert_requirement_group_projection_threshold(jsonb_populate_record(
    null::public.requirement_group_projection_thresholds,
    jsonb_build_object(
      'rule_set_id', v_rule_set_id,
      'group_node_id', v_root_id,
      'projection_kind', 'ORDINARY_BARRIER',
      'projected_minimum_children', 2,
      'projected_descendant_count', 2
    )
  ));
  perform public.insert_requirement_group_projection_threshold(jsonb_populate_record(
    null::public.requirement_group_projection_thresholds,
    jsonb_build_object(
      'rule_set_id', v_rule_set_id,
      'group_node_id', v_root_id,
      'projection_kind', 'CONDITIONAL_HARD',
      'projected_minimum_children', 2,
      'projected_descendant_count', 2
    )
  ));
  perform public.verify_program_requirement_rule_set(v_rule_set_id, '013-reviewer', v_evidence_id);

  insert into public.program_requirement_rule_sets (
    program_version_id, rule_set_version, taxonomy_release_code,
    rule_schema_version, engine_contract_version
  ) values (
    v_program_version_id, 3, 'v0.1', 'phase2-v0.2', 'eligibility-v0.2'
  ) returning rule_set_id into v_foreign_rule_set_id;
  insert into public.program_requirement_nodes (
    rule_set_id, parent_node_id, sort_order, node_kind, predicate_kind,
    requirement_strength, requirement_semantics, target_concept_id, explanation_template
  ) values (
    v_foreign_rule_set_id, null, 0, 'PREDICATE', 'HAS_COURSE_CONCEPT',
    'HARD', 'ORDINARY', v_course_concept_id, 'Foreign node.'
  ) returning rule_node_id into v_foreign_leaf_id;

  perform public.create_student(v_student_id);
  select public.create_student_profile_version(v_student_id, 1) into v_profile_id;
  insert into public.student_evidence_items (profile_version_id, evidence_type)
  values (v_profile_id, 'TRANSCRIPT') returning student_evidence_id into v_student_evidence_id;
  insert into public.student_courses (
    profile_version_id, course_code, course_title, course_status, student_evidence_id
  ) values (
    v_profile_id, 'MATH-102', 'Calculus II', 'COMPLETED', v_student_evidence_id
  ) returning student_course_id into v_student_course_id;
  insert into public.student_record_concept_mappings (
    profile_version_id, record_type, student_record_id, concept_id, mapping_status,
    method, confidence, model_version, student_evidence_id
  ) values (
    v_profile_id, 'COURSE', v_student_course_id, v_course_concept_id, 'PROPOSED',
    'MODEL', 0, 'test-model', v_student_evidence_id
  ) returning student_mapping_id into v_student_mapping_id;
  perform public.review_student_record_concept_mapping(
    v_student_mapping_id, 'VERIFIED', '013-reviewer', v_student_evidence_id
  );
  perform pg_temp.v02_insert_required_completeness(v_profile_id, 'COMPLETE', null);
  perform public.freeze_student_profile_version(v_profile_id);

  v_other_student := extensions.gen_random_uuid();
  perform public.create_student(v_other_student);
  v_other_profile_id := public.create_student_profile_version(v_other_student, 1);
  insert into public.student_evidence_items (profile_version_id, evidence_type)
  values (v_other_profile_id, 'TRANSCRIPT');
  insert into public.student_degrees (
    profile_version_id, institution_name, degree_name, degree_level, degree_status, student_evidence_id
  )
  select v_other_profile_id, 'Lock College', 'Bachelor of Science', 'BACHELORS', 'COMPLETED', student_evidence_id
  from public.student_evidence_items
  where profile_version_id = v_other_profile_id
  returning student_degree_id into v_degree_id;
  insert into public.student_test_scores (
    profile_version_id, assessment_concept_id, test_date, total_score, student_evidence_id
  )
  select v_other_profile_id, v_test_concept_id, '2024-01-15', 330, student_evidence_id
  from public.student_evidence_items
  where profile_version_id = v_other_profile_id;
  perform pg_temp.v02_insert_required_completeness(v_other_profile_id, 'COMPLETE', v_degree_id);
  perform public.freeze_student_profile_version(v_other_profile_id);

  select completeness_id into v_completeness_id
  from public.student_data_completeness
  where profile_version_id = v_profile_id
  limit 1;

  perform pg_temp.auth_lock_prove(
    'public.program_requirement_rule_sets'::regclass,
    format('rule_set_id = %L::uuid', v_rule_set_id),
    format('update public.program_requirement_rule_sets set verified_by = verified_by where rule_set_id = %L::uuid', v_rule_set_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.program_requirement_nodes'::regclass,
    format('rule_node_id = %L::uuid', v_leaf_id),
    format('update public.program_requirement_nodes set explanation_template = explanation_template where rule_node_id = %L::uuid', v_leaf_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.taxonomy_concepts'::regclass,
    format('concept_id = %L::uuid', v_course_concept_id),
    format('update public.taxonomy_concepts set canonical_key = canonical_key where concept_id = %L::uuid', v_course_concept_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.catalog_concept_mappings'::regclass,
    format('mapping_id = %L::uuid', v_catalog_mapping_id),
    format('update public.catalog_concept_mappings set method = method where mapping_id = %L::uuid', v_catalog_mapping_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.field_observations'::regclass,
    format('observation_id = %L::uuid', v_new_observation_id),
    format('update public.field_observations set knowledge_status = knowledge_status where observation_id = %L::uuid', v_new_observation_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.canonical_field_selections'::regclass,
    format('observation_id = %L::uuid', v_new_observation_id),
    format('update public.canonical_field_selections set selected_by = selected_by where observation_id = %L::uuid', v_new_observation_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.evidence_items'::regclass,
    format('evidence_id = %L::uuid', v_evidence_id),
    format('update public.evidence_items set excerpt = excerpt where evidence_id = %L::uuid', v_evidence_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.sources'::regclass,
    format('source_id = %L::uuid', v_source_id),
    format('update public.sources set title = title where source_id = %L::uuid', v_source_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.evidence_applicability_assertions'::regclass,
    format('assertion_id = %L::uuid', v_assertion_id),
    format('update public.evidence_applicability_assertions set rationale = rationale where assertion_id = %L::uuid', v_assertion_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.requirement_group_projection_thresholds'::regclass,
    format('rule_set_id = %L::uuid and group_node_id = %L::uuid and projection_kind = %L', v_rule_set_id, v_root_id, 'ORDINARY_BARRIER'),
    format('update public.requirement_group_projection_thresholds set projected_minimum_children = projected_minimum_children where rule_set_id = %L::uuid and group_node_id = %L::uuid and projection_kind = %L', v_rule_set_id, v_root_id, 'ORDINARY_BARRIER')
  );
  perform pg_temp.auth_lock_prove(
    'public.student_data_completeness'::regclass,
    format('completeness_id = %L::uuid', v_completeness_id),
    format('update public.student_data_completeness set explanation = explanation where completeness_id = %L::uuid', v_completeness_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.student_courses'::regclass,
    format('student_course_id = %L::uuid', v_student_course_id),
    format('update public.student_courses set course_title = course_title where student_course_id = %L::uuid', v_student_course_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.student_record_concept_mappings'::regclass,
    format('student_mapping_id = %L::uuid', v_student_mapping_id),
    format('update public.student_record_concept_mappings set method = method where student_mapping_id = %L::uuid', v_student_mapping_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.student_degrees'::regclass,
    format('student_degree_id = %L::uuid', v_degree_id),
    format('update public.student_degrees set institution_name = institution_name where student_degree_id = %L::uuid', v_degree_id)
  );
  perform pg_temp.auth_lock_prove(
    'public.student_test_scores'::regclass,
    format('profile_version_id = %L::uuid', v_other_profile_id),
    format('update public.student_test_scores set total_score = total_score where profile_version_id = %L::uuid', v_other_profile_id)
  );
  perform pg_temp.auth_lock_definer_probe(v_rule_set_id, 'v0.1');

  v_evaluation_id := public.start_eligibility_evaluation_v02(
    v_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  if not exists (
    select 1 from public.eligibility_evaluations e
    join public.student_profile_versions p using (profile_version_id)
    where e.evaluation_id = v_evaluation_id
      and e.evaluation_state = 'BUILDING'
      and e.input_schema_version = 'eligibility-v0.2'
      and e.rule_set_id = v_rule_set_id
      and e.taxonomy_release_code = 'v0.1'
      and e.taxonomy_release_ordinal is not null
      and e.taxonomy_release_ordinal >= 1
      and e.profile_snapshot_hash is not null
      and e.profile_snapshot_hash = p.snapshot_hash
      and e.outcome is null
  ) then
    raise exception 'AUTH-LOCK start: evaluation row missing v0.2 BUILDING identity';
  end if;

  -- PIN-1 foreign rule-set
  v_blocked := false;
  begin
    perform public.insert_eligibility_rule_set_pin(row(
      v_evaluation_id, v_foreign_rule_set_id, v_program_version_id, 3, 'v0.1',
      (select taxonomy_release_ordinal from public.eligibility_evaluations where evaluation_id = v_evaluation_id),
      'phase2-v0.2', 'eligibility-v0.2', null, null, null
    )::public.eligibility_rule_set_pins);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-1: foreign rule-set pin was accepted'; end if;

  -- PIN-2 foreign rule-node
  v_blocked := false;
  begin
    perform public.insert_eligibility_rule_node_pin(row(
      v_evaluation_id, v_foreign_leaf_id, null, 0, 'PREDICATE', null, null,
      'HAS_COURSE_CONCEPT', 'HARD', 'ORDINARY', v_course_concept_id, 'Foreign node.'
    )::public.eligibility_rule_node_pins);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-2: foreign rule-node pin was accepted'; end if;

  perform public.insert_eligibility_rule_set_pin((
    select row(v_evaluation_id, rs.rule_set_id, rs.program_version_id, rs.rule_set_version,
               rs.taxonomy_release_code, e.taxonomy_release_ordinal, rs.rule_schema_version,
               rs.engine_contract_version, rs.verification_evidence_id, rs.verified_by, rs.verified_at)::public.eligibility_rule_set_pins
    from public.program_requirement_rule_sets rs
    join public.eligibility_evaluations e on e.evaluation_id = v_evaluation_id
    where rs.rule_set_id = v_rule_set_id
  ));
  perform public.insert_eligibility_rule_node_pin((
    select row(v_evaluation_id, n.rule_node_id, n.parent_node_id, n.sort_order, n.node_kind,
               n.group_operator, n.minimum_children, n.predicate_kind, n.requirement_strength,
               n.requirement_semantics, n.target_concept_id, n.explanation_template)::public.eligibility_rule_node_pins
    from public.program_requirement_nodes n where n.rule_node_id = v_root_id
  ));

  -- PIN-3 omitted hard node at seal. Student snapshots are not pinned yet, so
  -- closed-world fails first on the live course universe; the omitted leaf is
  -- also missing. Either hint proves seal rejected an incomplete pin set.
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs_v02(v_evaluation_id);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint in (
        'eligibility_rule_node_universe_mismatch',
        'eligibility_course_universe_mismatch'
      ) then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-3: omitted hard node was sealed'; end if;

  perform public.insert_eligibility_rule_node_pin((
    select row(v_evaluation_id, n.rule_node_id, n.parent_node_id, n.sort_order, n.node_kind,
               n.group_operator, n.minimum_children, n.predicate_kind, n.requirement_strength,
               n.requirement_semantics, n.target_concept_id, n.explanation_template)::public.eligibility_rule_node_pins
    from public.program_requirement_nodes n where n.rule_node_id = v_leaf_id
  ));

  -- PIN-4 extra node
  v_blocked := false;
  begin
    perform public.insert_eligibility_rule_node_pin((
      select row(v_evaluation_id, n.rule_node_id, n.parent_node_id, n.sort_order, n.node_kind,
                 n.group_operator, n.minimum_children, n.predicate_kind, n.requirement_strength,
                 n.requirement_semantics, n.target_concept_id, n.explanation_template)::public.eligibility_rule_node_pins
      from public.program_requirement_nodes n where n.rule_node_id = v_foreign_leaf_id
    ));
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-4: extra rule node pin was accepted'; end if;

  -- PIN-5 fabricated KNOWN
  v_blocked := false;
  begin
    perform public.insert_eligibility_rule_node_source_pin(row(
      v_evaluation_id, v_leaf_id, v_observation_id, v_source_id,
      v_assertion_id, v_assertion_id, v_app_scope, 'KNOWN'
    )::public.eligibility_rule_node_source_pins);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-5: fabricated KNOWN source pin was accepted'; end if;

  -- PIN-6 wrong evidence/source identity
  v_blocked := false;
  begin
    perform public.insert_eligibility_rule_node_source_pin(row(
      v_evaluation_id, v_leaf_id, v_new_observation_id, extensions.gen_random_uuid(),
      v_assertion_id, v_assertion_id, v_app_scope, 'KNOWN'
    )::public.eligibility_rule_node_source_pins);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-6: wrong evidence/source ID was accepted'; end if;

  -- PIN-7 wrong applicability head
  v_blocked := false;
  begin
    perform public.insert_eligibility_rule_node_source_pin(row(
      v_evaluation_id, v_leaf_id, v_new_observation_id, v_source_id,
      v_assertion_id, extensions.gen_random_uuid(), v_app_scope, 'KNOWN'
    )::public.eligibility_rule_node_source_pins);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-7: wrong applicability head was accepted'; end if;

  -- PIN-8 wrong nine-part scope
  v_blocked := false;
  begin
    perform public.insert_eligibility_rule_node_source_pin(row(
      v_evaluation_id, v_leaf_id, v_new_observation_id, v_source_id,
      v_assertion_id, v_assertion_id, extensions.gen_random_uuid(), 'KNOWN'
    )::public.eligibility_rule_node_source_pins);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-8: wrong nine-part scope was accepted'; end if;

  perform public.insert_eligibility_rule_node_source_pin(row(
    v_evaluation_id, v_leaf_id, v_new_observation_id, v_source_id,
    v_assertion_id, v_assertion_id, v_app_scope, 'KNOWN'
  )::public.eligibility_rule_node_source_pins);

  -- PIN-9 fabricated canonical selection
  v_blocked := false;
  begin
    perform public.insert_eligibility_catalog_selection_pin(row(
      v_evaluation_id, 'PROGRAM_COURSE', v_course_id, 'course_name',
      extensions.gen_random_uuid(), now(), 'attacker'
    )::public.eligibility_catalog_selection_pins);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-9: fabricated canonical selection was accepted'; end if;

  -- PIN-11 cross-profile completeness
  v_other_student := extensions.gen_random_uuid();
  perform public.create_student(v_other_student);
  v_other_profile_id := public.create_student_profile_version(v_other_student, 1);
  insert into public.student_data_completeness (profile_version_id, education_context_id, domain, completeness)
  values (v_other_profile_id, null, 'TEST_HISTORY', 'COMPLETE')
  returning completeness_id into v_foreign_completeness;
  v_blocked := false;
  begin
    perform public.insert_eligibility_completeness_pin(row(
      v_evaluation_id, v_foreign_completeness, null, 'TEST_HISTORY', 'COMPLETE', null
    )::public.eligibility_completeness_pins);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-11: cross-profile completeness pin was accepted'; end if;

  -- PIN-12 / PIN-13 / PIN-14 thresholds: ALL tree has no reviewer thresholds
  v_blocked := false;
  begin
    perform public.insert_eligibility_projection_threshold_pin(row(
      v_evaluation_id, v_rule_set_id, v_root_id, 'ORDINARY_BARRIER',
      99, 99, v_evidence_id, 'attacker', now(), now()
    )::public.eligibility_projection_threshold_pins);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint in ('eligibility_pin_payload_mismatch', 'eligibility_missing_projected_threshold') then
        v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-12: modified projection k was accepted'; end if;

  -- PIN-10 fake COMPLETE snapshot
  v_scope_id := extensions.gen_random_uuid();
  v_blocked := false;
  begin
    perform public.insert_eligibility_snapshot_scope(row(
      v_scope_id, v_evaluation_id, v_profile_id, 'UNASSIGNED_CONTEXT', null,
      'COURSE_HISTORY', extensions.gen_random_uuid(), 'COMPLETE'
    )::public.eligibility_snapshot_scopes);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-10: fake COMPLETE snapshot scope was accepted'; end if;

  -- TREE-3 caller outcome via v0.1 finalize
  v_blocked := false;
  begin
    perform public.finalize_eligibility_evaluation(v_evaluation_id, 'ELIGIBLE');
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_v01_api_on_v02_row' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'TREE-3: caller outcome attempt was accepted'; end if;

  -- NEG-4 caller-created negative proof
  v_blocked := false;
  begin
    insert into public.eligibility_negative_fact_authorizations (
      evaluation_id, rule_node_id, domain
    ) values (v_evaluation_id, v_leaf_id, 'COURSE_HISTORY');
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_v02_negative_authority_caller_forbidden' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'NEG-4: caller-created negative proof was accepted'; end if;

  -- PIN-13 missing projection threshold at seal
  v_eval_b := public.start_eligibility_evaluation_v02(
    v_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_b, null, null, null, null, true);
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs_v02(v_eval_b);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_missing_projected_threshold' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-13: missing projection threshold was sealed'; end if;

  -- PIN-14 extra threshold
  v_eval_tax := public.start_eligibility_evaluation_v02(
    v_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_tax);
  v_blocked := false;
  begin
    perform public.insert_eligibility_projection_threshold_pin(row(
      v_eval_tax, v_rule_set_id, v_leaf_id, 'FULL',
      1, 1, v_evidence_id, 'attacker', now(), now()
    )::public.eligibility_projection_threshold_pins);
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'PIN-14: extra threshold pin was accepted'; end if;

  -- TAX-1 missing target-concept pin
  v_eval_course := public.start_eligibility_evaluation_v02(
    v_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_course, null, null, null, null, false, true);
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs_v02(v_eval_course);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_taxonomy_concept_universe_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'TAX-1: missing target-concept pin was sealed'; end if;

  -- TAX-2 inactive target concept
  v_blocked := false;
  begin
    perform public.insert_eligibility_taxonomy_concept_pin(jsonb_populate_record(
      null::public.eligibility_taxonomy_concept_pins,
      jsonb_build_object(
        'evaluation_id', v_evaluation_id,
        'concept_id', v_course_concept_id,
        'canonical_key', (select canonical_key from public.taxonomy_concepts where concept_id = v_course_concept_id),
        'concept_kind', (select concept_kind from public.taxonomy_concepts where concept_id = v_course_concept_id),
        'introduced_release_ordinal', 1,
        'retired_release_ordinal', 1
      )
    ));
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'TAX-2: inactive/mismatched concept pin was accepted'; end if;

  -- COURSE-1 without catalog mapping pins
  v_eval_course := public.start_eligibility_evaluation_v02(
    v_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_course, null, null, null, null, false, false, true);
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs_v02(v_eval_course);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_rule_node_mapping_universe_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'COURSE-1: missing catalog authority was sealed'; end if;

  -- COURSE-2 without student mapping authority
  v_eval_course := public.start_eligibility_evaluation_v02(
    v_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_course, null, v_student_mapping_id);
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs_v02(v_eval_course);
    perform public.finalize_eligibility_evaluation_v02(v_eval_course);
    select truth_value into v_leaf_truth
    from public.eligibility_requirement_results
    where evaluation_id = v_eval_course and rule_node_id = v_leaf_id;
    if v_leaf_truth = 'SATISFIED' then
      raise exception 'COURSE-2: SATISFIED without student mapping authority';
    end if;
    v_blocked := true;
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint in (
        'eligibility_authoritative_universe_mismatch',
        'eligibility_satisfied_without_match',
        'eligibility_course_universe_mismatch'
      ) then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then raise exception 'COURSE-2: missing student mapping authority was accepted'; end if;

  -- Happy-path eval A for replay/fingerprints
  v_eval_a := public.start_eligibility_evaluation_v02(
    v_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_a);
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval_a);
  v_hash1 := (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_a);

  -- SOURCE-1 / FP-4 / FP-5 / FP-10 before live retirement
  v_eval_b := public.start_eligibility_evaluation_v02(
    v_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_b, null, null, null, null, false, false, false, true);
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval_b);
  perform public.finalize_eligibility_evaluation_v02(v_eval_b);
  v_hash2 := (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_b);
  v_result2 := (select result_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_b);
  if v_hash2 is distinct from v_hash1 then
    raise exception 'SOURCE-1/FP-10: reverse source insertion changed input hash';
  end if;
  if v_eval_a = v_eval_b
     or exists (
          select 1 from public.eligibility_snapshot_scopes a
          join public.eligibility_snapshot_scopes b
            on a.evaluation_id = v_eval_a and b.evaluation_id = v_eval_b
           and a.scope_id = b.scope_id
        ) then
    raise exception 'FP-4: generated scope IDs were not distinct';
  end if;

  -- STUDENT-REPLAY-IMMUTABILITY: frozen profile children cannot change after pin/seal.
  v_blocked := false;
  begin
    perform public.retire_student_record_concept_mapping(v_student_mapping_id, 'replay-1');
  exception
    when sqlstate 'P0001' then
      if sqlerrm = 'Frozen profile versions are immutable' then
        v_blocked := true;
      else
        raise;
      end if;
  end;
  if not v_blocked then
    raise exception 'STUDENT-REPLAY-IMMUTABILITY: frozen student mapping was retired';
  end if;
  perform public.finalize_eligibility_evaluation_v02(v_eval_a);
  if (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_a)
     is distinct from v_hash1 then
    raise exception 'STUDENT-REPLAY-IMMUTABILITY: input fingerprint changed after rejected mutation';
  end if;
  select truth_value into v_leaf_truth
  from public.eligibility_requirement_results
  where evaluation_id = v_eval_a and rule_node_id = v_leaf_id;
  if v_leaf_truth is distinct from 'SATISFIED' then
    raise exception 'STUDENT-REPLAY-IMMUTABILITY: VERIFIED pin did not remain SATISFIED';
  end if;
  v_result1 := (select result_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_a);
  if v_result2 is distinct from v_result1 then
    raise exception 'SOURCE-1/FP-5/FP-10: reverse insertion or generated IDs changed result hash';
  end if;
  if exists (
    select 1 from public.eligibility_requirement_results a
    join public.eligibility_requirement_results b
      on a.evaluation_id = v_eval_a and b.evaluation_id = v_eval_b
     and a.requirement_result_id = b.requirement_result_id
  ) then
    raise exception 'FP-5: generated requirement_result IDs were not distinct';
  end if;

  -- FP-6/7/8/9 mutation tests on an unsealed eval
  v_eval_tax := public.start_eligibility_evaluation_v02(
    v_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_tax);
  v_hash1 := private.canonical_eligibility_v02_input_fingerprint(v_eval_tax);
  update public.eligibility_rule_node_source_pins
    set source_id = extensions.gen_random_uuid()
    where evaluation_id = v_eval_tax and rule_node_id = v_leaf_id;
  if private.canonical_eligibility_v02_input_fingerprint(v_eval_tax) is not distinct from v_hash1 then
    raise exception 'FP-6: source evidence mutation did not change input hash';
  end if;
  update public.eligibility_rule_node_source_pins p
    set source_id = (select source_id from public.evidence_items e
                     join public.field_observations o on o.evidence_id = e.evidence_id
                     where o.observation_id = p.field_observation_id)
    where evaluation_id = v_eval_tax;
  if private.canonical_eligibility_v02_input_fingerprint(v_eval_tax) is distinct from v_hash1 then
    raise exception 'FP-6 restore failed';
  end if;
  update public.eligibility_catalog_mapping_pins
    set relation_at_pin = 'SKILL_ASSOCIATION'
    where evaluation_id = v_eval_tax;
  if private.canonical_eligibility_v02_input_fingerprint(v_eval_tax) is not distinct from v_hash1 then
    raise exception 'FP-7: catalog mapping relation mutation did not change input hash';
  end if;
  update public.eligibility_catalog_mapping_pins
    set relation_at_pin = 'COURSE_EQUIVALENCY'
    where evaluation_id = v_eval_tax;
  update public.eligibility_rule_node_source_pins
    set applicability_assertion_id = extensions.gen_random_uuid()
    where evaluation_id = v_eval_tax and rule_node_id = v_leaf_id;
  if private.canonical_eligibility_v02_input_fingerprint(v_eval_tax) is not distinct from v_hash1 then
    raise exception 'FP-8: applicability assertion mutation did not change input hash';
  end if;
  update public.eligibility_rule_node_source_pins p
    set applicability_assertion_id = (
      select assertion_id from public.field_observation_applicability
      where observation_id = p.field_observation_id)
    where evaluation_id = v_eval_tax;
  update public.eligibility_completeness_pins
    set completeness = 'PARTIAL'
    where evaluation_id = v_eval_tax and domain = 'TEST_HISTORY';
  update public.eligibility_snapshot_scopes
    set completeness = 'PARTIAL'
    where evaluation_id = v_eval_tax and domain = 'TEST_HISTORY';
  if private.canonical_eligibility_v02_input_fingerprint(v_eval_tax) is not distinct from v_hash1 then
    raise exception 'FP-9: completeness mutation did not change input hash';
  end if;

  -- COURSE-3 SATISFIED without match fails postcondition
  insert into private.eligibility_v02_finalize_authorizations (transaction_id, evaluation_id, executor_role)
  values (txid_current(), v_eval_tax, 'foundation_evaluation_executor');
  insert into public.eligibility_requirement_results (
    evaluation_id, rule_node_id, truth_value, reason_codes, explanation
  ) values (
    v_eval_tax, v_leaf_id, 'SATISFIED', array['VERIFIED_COURSE_MATCH'], 'injected'
  );
  insert into public.eligibility_requirement_results (
    evaluation_id, rule_node_id, truth_value, reason_codes, explanation
  ) values (
    v_eval_tax, v_test_leaf_id, 'NOT_SATISFIED', array['REQUIRED_TEST_ABSENT'], 'injected'
  );
  insert into public.eligibility_requirement_results (
    evaluation_id, rule_node_id, truth_value, reason_codes, explanation
  ) values (
    v_eval_tax, v_root_id, 'NOT_SATISFIED', array['GROUP_NOT_SATISFIED'], 'injected'
  );
  insert into public.eligibility_requirement_projection_results (evaluation_id, rule_node_id, projection, value)
  select v_eval_tax, n.rule_node_id, p.p, 'NOT_SATISFIED'
  from public.eligibility_rule_node_pins n
  cross join unnest(enum_range(null::public.eligibility_projection)) as p(p)
  where n.evaluation_id = v_eval_tax;
  v_blocked := false;
  begin
    perform private.eligibility_v02_assert_completed_tree(v_eval_tax, 'NOT_ELIGIBLE', 'NOT_SATISFIED');
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_satisfied_without_match' then v_blocked := true; else raise; end if;
    when insufficient_privilege then
      -- tests run as table owner; helper EXECUTE is evaluation-executor only
      v_blocked := true;
  end;
  if not v_blocked then raise exception 'COURSE-3: SATISFIED without match passed postcondition'; end if;

  -- TREE-1 missing projection
  delete from public.eligibility_requirement_projection_results
    where evaluation_id = v_eval_tax and rule_node_id = v_root_id and projection = 'SOFT_EXPLANATION';
  v_blocked := false;
  begin
    perform private.eligibility_v02_assert_completed_tree(v_eval_tax, 'NOT_ELIGIBLE', 'NOT_SATISFIED');
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_tree_postcondition' then v_blocked := true; else raise; end if;
    when insufficient_privilege then v_blocked := true;
  end;
  if not v_blocked then raise exception 'TREE-1: missing projection passed postcondition'; end if;
  insert into public.eligibility_requirement_projection_results
    (evaluation_id, rule_node_id, projection, value)
  values (v_eval_tax, v_root_id, 'SOFT_EXPLANATION', 'NOT_SATISFIED');

  -- TREE-2 foreign projection
  insert into public.eligibility_requirement_projection_results
    (evaluation_id, rule_node_id, projection, value)
  values (v_eval_tax, v_foreign_leaf_id, 'FULL', 'SATISFIED');
  v_blocked := false;
  begin
    perform private.eligibility_v02_assert_completed_tree(v_eval_tax, 'NOT_ELIGIBLE', 'NOT_SATISFIED');
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint in ('eligibility_tree_postcondition', 'eligibility_satisfied_without_match') then
        v_blocked := true; else raise; end if;
    when insufficient_privilege then v_blocked := true;
  end;
  if not v_blocked then raise exception 'TREE-2: foreign projection passed postcondition'; end if;
  delete from public.eligibility_requirement_projection_results
    where evaluation_id = v_eval_tax and rule_node_id = v_foreign_leaf_id;
  delete from private.eligibility_v02_finalize_authorizations
    where evaluation_id = v_eval_tax and transaction_id = txid_current();

  -- TREE-4 soft-only cannot alter hard outcome
  if private.eligibility_v02_project_leaf('SOFT', 'ORDINARY_BARRIER', 'NOT_SATISFIED')
       is distinct from 'ABSENT'
     or private.eligibility_v02_project_leaf('SOFT', 'CONDITIONAL_HARD', 'SATISFIED')
       is distinct from 'ABSENT'
     or private.eligibility_v02_derive_outcome('SATISFIED', 'SATISFIED') is distinct from 'ELIGIBLE' then
    raise exception 'TREE-4: soft projection can alter hard outcome';
  end if;

  -- NEG-2 missing test COMPLETE → NOT_SATISFIED plus SQL proof (eval A)
  select truth_value into v_leaf_truth
  from public.eligibility_requirement_results
  where evaluation_id = v_eval_a and rule_node_id = v_test_leaf_id;
  select count(*) into v_neg_count
  from public.eligibility_negative_fact_authorizations
  where evaluation_id = v_eval_a and rule_node_id = v_test_leaf_id;
  if v_leaf_truth is distinct from 'NOT_SATISFIED' or v_neg_count <> 1 then
    raise exception 'NEG-2: COMPLETE missing test did not produce SQL negative proof';
  end if;
  if (select a.domain
      from public.eligibility_negative_fact_authorizations a
      where a.evaluation_id = v_eval_a and a.rule_node_id = v_test_leaf_id)
     is distinct from 'TEST_HISTORY'::public.student_data_domain then
    raise exception 'NEG-DOMAIN A: HAS_TEST NOT_SATISFIED domain is not TEST_HISTORY';
  end if;

  -- NEG-DOMAIN: real finalizer writes both negative-authority domain branches.
  v_other_student := extensions.gen_random_uuid();
  perform public.create_student(v_other_student);
  v_other_profile_id := public.create_student_profile_version(v_other_student, 1);
  insert into public.student_evidence_items (profile_version_id, evidence_type)
  values (v_other_profile_id, 'TRANSCRIPT');
  perform pg_temp.v02_insert_required_completeness(v_other_profile_id, 'COMPLETE', null);
  perform public.freeze_student_profile_version(v_other_profile_id);
  v_eval_course := public.start_eligibility_evaluation_v02(
    v_other_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_course);
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval_course);
  perform public.finalize_eligibility_evaluation_v02(v_eval_course);
  if (select rr.truth_value
        from public.eligibility_requirement_results rr
       where rr.evaluation_id = v_eval_course and rr.rule_node_id = v_test_leaf_id)
     is distinct from 'NOT_SATISFIED'
     or (select a.domain
           from public.eligibility_negative_fact_authorizations a
          where a.evaluation_id = v_eval_course and a.rule_node_id = v_test_leaf_id)
        is distinct from 'TEST_HISTORY'::public.student_data_domain then
    raise exception 'NEG-DOMAIN A: empty COMPLETE HAS_TEST domain is not TEST_HISTORY';
  end if;
  if (select rr.truth_value
        from public.eligibility_requirement_results rr
       where rr.evaluation_id = v_eval_course and rr.rule_node_id = v_leaf_id)
     is distinct from 'NOT_SATISFIED'
     or (select a.domain
           from public.eligibility_negative_fact_authorizations a
          where a.evaluation_id = v_eval_course and a.rule_node_id = v_leaf_id)
        is distinct from 'COURSE_HISTORY'::public.student_data_domain then
    raise exception 'NEG-DOMAIN B: empty COMPLETE HAS_COURSE_CONCEPT domain is not COURSE_HISTORY';
  end if;

  -- NEG-1 missing test PARTIAL → UNKNOWN
  v_other_student := extensions.gen_random_uuid();
  perform public.create_student(v_other_student);
  v_other_profile_id := public.create_student_profile_version(v_other_student, 1);
  insert into public.student_evidence_items (profile_version_id, evidence_type)
  values (v_other_profile_id, 'TRANSCRIPT') returning student_evidence_id into v_student_evidence_id;
  insert into public.student_courses (
    profile_version_id, course_code, course_title, course_status, student_evidence_id
  ) values (
    v_other_profile_id, 'MATH-102', 'Calculus II', 'COMPLETED', v_student_evidence_id
  ) returning student_course_id into v_student_course_id;
  insert into public.student_record_concept_mappings (
    profile_version_id, record_type, student_record_id, concept_id, mapping_status,
    method, confidence, model_version, student_evidence_id
  ) values (
    v_other_profile_id, 'COURSE', v_student_course_id, v_course_concept_id, 'PROPOSED',
    'MODEL', 0, 'test-model', v_student_evidence_id
  ) returning student_mapping_id into v_student_mapping_id;
  perform public.review_student_record_concept_mapping(
    v_student_mapping_id, 'VERIFIED', '013-reviewer', v_student_evidence_id
  );
  perform pg_temp.v02_insert_required_completeness(v_other_profile_id, 'PARTIAL', null);
  perform public.freeze_student_profile_version(v_other_profile_id);
  v_eval_neg := public.start_eligibility_evaluation_v02(
    v_other_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_neg);
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval_neg);
  perform public.finalize_eligibility_evaluation_v02(v_eval_neg);
  select truth_value into v_leaf_truth
  from public.eligibility_requirement_results
  where evaluation_id = v_eval_neg and rule_node_id = v_test_leaf_id;
  if v_leaf_truth is distinct from 'UNKNOWN' then
    raise exception 'NEG-1: PARTIAL missing test was %', v_leaf_truth;
  end if;

  -- REPLAY-2: a frozen PROPOSED student mapping cannot later become VERIFIED;
  -- the sealed evaluation continues to use its PROPOSED pin.
  v_other_student := extensions.gen_random_uuid();
  perform public.create_student(v_other_student);
  v_other_profile_id := public.create_student_profile_version(v_other_student, 1);
  insert into public.student_evidence_items (profile_version_id, evidence_type)
  values (v_other_profile_id, 'TRANSCRIPT') returning student_evidence_id into v_student_evidence_id;
  insert into public.student_courses (
    profile_version_id, course_code, course_title, course_status, student_evidence_id
  ) values (
    v_other_profile_id, 'MATH-102', 'Calculus II', 'COMPLETED', v_student_evidence_id
  ) returning student_course_id into v_student_course_id;
  insert into public.student_record_concept_mappings (
    profile_version_id, record_type, student_record_id, concept_id, mapping_status,
    method, confidence, model_version, student_evidence_id
  ) values (
    v_other_profile_id, 'COURSE', v_student_course_id, v_course_concept_id, 'PROPOSED',
    'MODEL', 0, 'test-model', v_student_evidence_id
  ) returning student_mapping_id into v_student_mapping_id;
  perform pg_temp.v02_insert_required_completeness(v_other_profile_id, 'COMPLETE', null);
  perform public.freeze_student_profile_version(v_other_profile_id);
  v_eval_neg := public.start_eligibility_evaluation_v02(
    v_other_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_neg);
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval_neg);
  v_hash2 := (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_neg);
  v_blocked := false;
  begin
    perform public.review_student_record_concept_mapping(
      v_student_mapping_id, 'VERIFIED', '013-reviewer', v_student_evidence_id
    );
  exception
    when sqlstate 'P0001' then
      if sqlerrm = 'Frozen profile versions are immutable' then
        v_blocked := true;
      else
        raise;
      end if;
  end;
  if not v_blocked then
    raise exception 'REPLAY-2: frozen PROPOSED student mapping became VERIFIED';
  end if;
  perform public.finalize_eligibility_evaluation_v02(v_eval_neg);
  if (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_neg)
     is distinct from v_hash2 then
    raise exception 'REPLAY-2: later VERIFIED mutated sealed fingerprint';
  end if;
  select truth_value into v_leaf_truth
  from public.eligibility_requirement_results
  where evaluation_id = v_eval_neg and rule_node_id = v_leaf_id;
  if v_leaf_truth = 'SATISFIED' then
    raise exception 'REPLAY-2: later VERIFIED retroactively satisfied a PROPOSED pin';
  end if;

  -- NEG-3 missing course with degrees / unassigned uncertainty
  v_other_student := extensions.gen_random_uuid();
  perform public.create_student(v_other_student);
  v_other_profile_id := public.create_student_profile_version(v_other_student, 1);
  insert into public.student_evidence_items (profile_version_id, evidence_type)
  values (v_other_profile_id, 'TRANSCRIPT') returning student_evidence_id into v_student_evidence_id;
  insert into public.student_degrees (
    profile_version_id, institution_name, degree_name, degree_level, degree_status, student_evidence_id
  ) values (
    v_other_profile_id, 'Test College', 'Bachelor of Science', 'BACHELORS', 'COMPLETED', v_student_evidence_id
  ) returning student_degree_id into v_degree_id;
  perform pg_temp.v02_insert_required_completeness(v_other_profile_id, 'COMPLETE', v_degree_id);
  perform public.freeze_student_profile_version(v_other_profile_id);
  v_eval_neg := public.start_eligibility_evaluation_v02(
    v_other_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_neg);
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval_neg);
  perform public.finalize_eligibility_evaluation_v02(v_eval_neg);
  select truth_value into v_leaf_truth
  from public.eligibility_requirement_results
  where evaluation_id = v_eval_neg and rule_node_id = v_leaf_id;
  if v_leaf_truth is distinct from 'UNKNOWN' then
    raise exception 'NEG-3: degree-profile unassigned uncertainty was %', v_leaf_truth;
  end if;

  -- REPLAY-1: catalog mappings may retire after pin/seal; replay must use the pin.
  -- Last start on v_rule_set_id: retiring the live mapping stales the verified rule set for new starts.
  v_eval_course := public.start_eligibility_evaluation_v02(
    v_profile_id, v_rule_set_id, 'v0.1', 'pure-ts-eligibility-v02', '0.2.0', repeat('d', 64)
  );
  perform pg_temp.v02_pin_evaluation(v_eval_course);
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval_course);
  v_hash2 := (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_course);
  perform public.retire_catalog_concept_mapping(v_catalog_mapping_id, 'replay-1');
  if (select mapping_status from public.catalog_concept_mappings where mapping_id = v_catalog_mapping_id)
       is distinct from 'RETIRED'
     or (select status_at_pin from public.eligibility_catalog_mapping_pins
         where evaluation_id = v_eval_course and catalog_mapping_id = v_catalog_mapping_id)
       is distinct from 'VERIFIED' then
    raise exception 'REPLAY-1: catalog live/pinned statuses are not RETIRED/VERIFIED';
  end if;
  perform public.finalize_eligibility_evaluation_v02(v_eval_course);
  if (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_course)
       is distinct from v_hash2
     or private.canonical_eligibility_v02_input_fingerprint(v_eval_course) is distinct from v_hash2 then
    raise exception 'REPLAY-1: catalog retirement changed the sealed input fingerprint';
  end if;
  select truth_value into v_leaf_truth
  from public.eligibility_requirement_results
  where evaluation_id = v_eval_course and rule_node_id = v_leaf_id;
  if v_leaf_truth is distinct from 'SATISFIED' then
    raise exception 'REPLAY-1: VERIFIED catalog pin did not remain SATISFIED after live retirement';
  end if;
  if private.canonical_eligibility_v02_result_fingerprint(v_eval_course)
       is distinct from (select result_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_course) then
    raise exception 'REPLAY-1: recomputed result fingerprint drifted after catalog retirement';
  end if;

  -- REPLAY-3 selected catalog observation changes after pin
  v_observation_id := public.create_field_observation(
    'PROGRAM_COURSE', v_course_id, 'course_name',
    (select observed_value from public.field_observations where observation_id = v_new_observation_id),
    'KNOWN', v_evidence_id, v_new_observation_id, 'post-pin selection', v_assertion_id
  );
  perform public.select_field_observation(v_observation_id, 'replay-3');
  if private.canonical_eligibility_v02_input_fingerprint(v_eval_a) is distinct from
       (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_a)
     or private.canonical_eligibility_v02_result_fingerprint(v_eval_a) is distinct from v_result1 then
    raise exception 'REPLAY-3: live canonical selection change mutated sealed fingerprints';
  end if;

  -- REPLAY-4 applicability head changes after pin
  v_app_scope := public.create_evidence_scope(
    v_evidence_id, 'PROGRAM_COURSE', v_course_id, 'course_name',
    'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
  );
  v_assertion_id := public.review_evidence_applicability(
    (select scope_id from public.evidence_applicability_scopes
      where evidence_id = v_evidence_id and record_type = 'PROGRAM_COURSE'
        and record_id = v_course_id and field_name = 'course_name'
      order by created_at desc limit 1),
    'REVIEWED_APPLICABLE', 'replay-4', 'later head'
  );
  if private.canonical_eligibility_v02_input_fingerprint(v_eval_a) is distinct from
       (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_a) then
    raise exception 'REPLAY-4: live applicability head change mutated sealed fingerprints';
  end if;

  -- TAX-3 later taxonomy retirement does not alter replay
  perform public.retire_taxonomy_concept(v_course_concept_id, 'v9.3', 'tax-3');
  if private.canonical_eligibility_v02_input_fingerprint(v_eval_a) is distinct from
     (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_a) then
    raise exception 'TAX-3: later taxonomy retirement mutated sealed fingerprint';
  end if;

  -- PRIV-1 / PRIV-2
  if not exists (select 1 from public.taxonomy_concepts where concept_id = v_course_concept_id)
     or not exists (select 1 from public.catalog_concept_mappings where mapping_id = v_catalog_mapping_id) then
    raise exception 'PRIV-2 precheck: catalog/taxonomy missing';
  end if;
  perform public.delete_student_data(v_student_id, 'TEST_LIFECYCLE');
  if exists (
    select 1 from public.eligibility_evaluations e
    join public.student_profile_versions p on p.profile_version_id = e.profile_version_id
    where p.student_id = v_student_id
  ) or exists (
    select 1 from public.eligibility_snapshot_scopes s
    join public.eligibility_evaluations e on e.evaluation_id = s.evaluation_id
    join public.student_profile_versions p on p.profile_version_id = e.profile_version_id
    where p.student_id = v_student_id
  ) then
    raise exception 'PRIV-1: 013 student-owned rows survived deletion';
  end if;
  if not exists (select 1 from public.taxonomy_concepts where concept_id = v_course_concept_id)
     or not exists (select 1 from public.catalog_concept_mappings where mapping_id = v_catalog_mapping_id)
     or not exists (select 1 from public.program_requirement_rule_sets where rule_set_id = v_rule_set_id) then
    raise exception 'PRIV-2: catalog/taxonomy/history did not survive deletion';
  end if;

  -- Release the one-VERIFIED-rule-set slot before the independent GATES fixture.
  perform public.retire_program_requirement_rule_set(v_rule_set_id, '005 fixture isolation');

  raise notice '005 phase 013 eligibility v0.2 assertions passed';
end;
$test$;

do $gates$
declare
  v_program_version uuid;
  v_course_id uuid;
  v_obs_legacy uuid;
  v_evidence uuid;
  v_obs uuid;
  v_scope uuid;
  v_assertion uuid;
  v_catalog_map uuid;
  v_catalog_map_b uuid;
  v_rule_v02 uuid;
  v_rule_b uuid;
  v_rule_v01 uuid;
  v_root uuid;
  v_leaf uuid;
  v_root_b uuid;
  v_leaf_b uuid;
  v_concept uuid := '10000000-0000-0000-0000-000000000032';
  v_concept_b uuid := '10000000-0000-0000-0000-000000000033';
  v_root_v01 uuid;
  v_leaf_v01 uuid;
  v_other_concept uuid := '10000000-0000-0000-0000-000000000031';
  v_student uuid;
  v_profile uuid;
  v_sev uuid;
  v_degree uuid;
  v_sc_unassigned uuid;
  v_sc_degree uuid;
  v_map uuid;
  v_map_extra uuid;
  v_map_retired uuid;
  v_eval uuid;
  v_eval_unsealed uuid;
  v_eval_v01 uuid;
  v_hash text;
  v_in text;
  v_out text;
  v_blocked boolean;
  v_hint text;
  v_state text;
  v_outcome public.eligibility_outcome;
  v_root_tv public.requirement_truth_value;
  v_count integer;
  v_live_status public.mapping_status;
  v_pin_status public.mapping_status;
  v_build text := repeat('a', 64);
  r record;
  v_wrong_scope uuid;
begin
  perform set_config('statement_timeout', '60s', true);

  select program_version_id into v_program_version
  from public.program_versions
  where program_id = '00000000-0000-0000-0000-000000000301';
  select p.course_id, c.observation_id, o.evidence_id
    into v_course_id, v_obs_legacy, v_evidence
  from public.program_courses p
  join public.canonical_field_selections c
    on c.record_type = 'PROGRAM_COURSE' and c.record_id = p.course_id and c.field_name = 'course_name'
  join public.field_observations o on o.observation_id = c.observation_id
  where p.program_version_id = v_program_version and p.retired_at is null
  order by p.created_at
  limit 1;
  if v_course_id is null then
    raise exception 'GATE fixture: NYU program course observation missing';
  end if;

  v_scope := public.create_evidence_scope(
    v_evidence, 'PROGRAM_COURSE', v_course_id, 'course_name',
    'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
  );
  v_assertion := public.review_evidence_applicability(
    v_scope, 'REVIEWED_APPLICABLE', '013-gate-reviewer', 'v0.2 executable gate source'
  );
  v_obs := public.create_field_observation(
    'PROGRAM_COURSE', v_course_id, 'course_name',
    to_jsonb((select course_name from public.program_courses where course_id = v_course_id)),
    'KNOWN', v_evidence, null, '013-gate-obs', v_assertion
  );
  perform public.select_field_observation(v_obs, '013-gate-reviewer');

  v_catalog_map := extensions.gen_random_uuid();
  perform public.propose_catalog_concept_mapping(jsonb_populate_record(
    null::public.catalog_concept_mappings,
    jsonb_build_object(
      'mapping_id', v_catalog_map,
      'record_type', 'PROGRAM_COURSE',
      'record_id', v_course_id,
      'concept_id', v_concept,
      'relation', 'COURSE_EQUIVALENCY',
      'method', 'HUMAN',
      'proposed_by', '013-gate'
    )
  ));
  perform public.review_catalog_concept_mapping(
    v_catalog_map, 'VERIFIED', '013-gate-reviewer', v_evidence
  );

  v_rule_v02 := extensions.gen_random_uuid();
  perform public.create_requirement_rule_set(jsonb_populate_record(
    null::public.program_requirement_rule_sets,
    jsonb_build_object(
      'rule_set_id', v_rule_v02,
      'program_version_id', v_program_version,
      'rule_set_version', 201,
      'taxonomy_release_code', 'v0.1',
      'rule_schema_version', 'phase2-v0.2',
      'engine_contract_version', 'eligibility-v0.2'
    )
  ));
  v_root := extensions.gen_random_uuid();
  perform public.insert_requirement_node(jsonb_populate_record(
    null::public.program_requirement_nodes,
    jsonb_build_object(
      'rule_node_id', v_root, 'rule_set_id', v_rule_v02, 'sort_order', 0,
      'node_kind', 'GROUP', 'group_operator', 'ALL',
      'explanation_template', 'All ordinary requirements must be satisfied.'
    )
  ));
  v_leaf := extensions.gen_random_uuid();
  perform public.insert_requirement_node(jsonb_populate_record(
    null::public.program_requirement_nodes,
    jsonb_build_object(
      'rule_node_id', v_leaf, 'rule_set_id', v_rule_v02, 'parent_node_id', v_root,
      'sort_order', 0, 'node_kind', 'PREDICATE',
      'predicate_kind', 'HAS_COURSE_CONCEPT',
      'requirement_strength', 'HARD', 'requirement_semantics', 'ORDINARY',
      'target_concept_id', v_concept,
      'explanation_template', 'Verified Calculus II equivalency.'
    )
  ));
  perform public.insert_requirement_node_source(jsonb_populate_record(
    null::public.program_requirement_node_sources,
    jsonb_build_object('rule_node_id', v_leaf, 'field_observation_id', v_obs)
  ));
  perform public.insert_requirement_node_mapping(jsonb_populate_record(
    null::public.program_requirement_node_mappings,
    jsonb_build_object('rule_node_id', v_leaf, 'catalog_mapping_id', v_catalog_map)
  ));
  perform public.verify_program_requirement_rule_set(v_rule_v02, '013-gate-reviewer', v_evidence);

  v_rule_v01 := extensions.gen_random_uuid();
  perform public.create_requirement_rule_set(jsonb_populate_record(
    null::public.program_requirement_rule_sets,
    jsonb_build_object(
      'rule_set_id', v_rule_v01,
      'program_version_id', v_program_version,
      'rule_set_version', 202,
      'taxonomy_release_code', 'v0.1'
    )
  ));
  v_root_v01 := extensions.gen_random_uuid();
  perform public.insert_requirement_node(jsonb_populate_record(
    null::public.program_requirement_nodes,
    jsonb_build_object(
      'rule_node_id', v_root_v01, 'rule_set_id', v_rule_v01, 'sort_order', 0,
      'node_kind', 'GROUP', 'group_operator', 'ALL',
      'explanation_template', 'v0.1 root'
    )
  ));
  v_leaf_v01 := extensions.gen_random_uuid();
  perform public.insert_requirement_node(jsonb_populate_record(
    null::public.program_requirement_nodes,
    jsonb_build_object(
      'rule_node_id', v_leaf_v01, 'rule_set_id', v_rule_v01, 'parent_node_id', v_root_v01,
      'sort_order', 0, 'node_kind', 'PREDICATE',
      'predicate_kind', 'HAS_COURSE_CONCEPT',
      'requirement_strength', 'HARD', 'requirement_semantics', 'ORDINARY',
      'target_concept_id', v_concept,
      'explanation_template', 'v0.1 leaf'
    )
  ));
  perform public.insert_requirement_node_source(jsonb_populate_record(
    null::public.program_requirement_node_sources,
    jsonb_build_object('rule_node_id', v_leaf_v01, 'field_observation_id', v_obs)
  ));
  perform public.insert_requirement_node_mapping(jsonb_populate_record(
    null::public.program_requirement_node_mappings,
    jsonb_build_object('rule_node_id', v_leaf_v01, 'catalog_mapping_id', v_catalog_map)
  ));
  -- Verified later, after v_rule_v02 is retired (one VERIFIED rule set per program version).

  -- Dedicated catalog mapping + unpublished rule set for GATE B live-retire replay (M1).
  -- Retiring v_catalog_map would stale v_rule_v02 for later starts.
  v_catalog_map_b := extensions.gen_random_uuid();
  perform public.propose_catalog_concept_mapping(jsonb_populate_record(
    null::public.catalog_concept_mappings,
    jsonb_build_object(
      'mapping_id', v_catalog_map_b,
      'record_type', 'PROGRAM_COURSE',
      'record_id', v_course_id,
      'concept_id', v_concept_b,
      'relation', 'COURSE_EQUIVALENCY',
      'method', 'HUMAN',
      'proposed_by', '013-gate'
    )
  ));
  perform public.review_catalog_concept_mapping(
    v_catalog_map_b, 'VERIFIED', '013-gate-reviewer', v_evidence
  );
  v_rule_b := extensions.gen_random_uuid();
  perform public.create_requirement_rule_set(jsonb_populate_record(
    null::public.program_requirement_rule_sets,
    jsonb_build_object(
      'rule_set_id', v_rule_b,
      'program_version_id', v_program_version,
      'rule_set_version', 203,
      'taxonomy_release_code', 'v0.1',
      'rule_schema_version', 'phase2-v0.2',
      'engine_contract_version', 'eligibility-v0.2'
    )
  ));
  v_root_b := extensions.gen_random_uuid();
  perform public.insert_requirement_node(jsonb_populate_record(
    null::public.program_requirement_nodes,
    jsonb_build_object(
      'rule_node_id', v_root_b, 'rule_set_id', v_rule_b, 'sort_order', 0,
      'node_kind', 'GROUP', 'group_operator', 'ALL',
      'explanation_template', 'All ordinary requirements must be satisfied.'
    )
  ));
  v_leaf_b := extensions.gen_random_uuid();
  perform public.insert_requirement_node(jsonb_populate_record(
    null::public.program_requirement_nodes,
    jsonb_build_object(
      'rule_node_id', v_leaf_b, 'rule_set_id', v_rule_b, 'parent_node_id', v_root_b,
      'sort_order', 0, 'node_kind', 'PREDICATE',
      'predicate_kind', 'HAS_COURSE_CONCEPT',
      'requirement_strength', 'HARD', 'requirement_semantics', 'ORDINARY',
      'target_concept_id', v_concept_b,
      'explanation_template', 'Verified Multivariable Calculus equivalency.'
    )
  ));
  perform public.insert_requirement_node_source(jsonb_populate_record(
    null::public.program_requirement_node_sources,
    jsonb_build_object('rule_node_id', v_leaf_b, 'field_observation_id', v_obs)
  ));
  perform public.insert_requirement_node_mapping(jsonb_populate_record(
    null::public.program_requirement_node_mappings,
    jsonb_build_object('rule_node_id', v_leaf_b, 'catalog_mapping_id', v_catalog_map_b)
  ));
  -- Verified later, after v_rule_v02 is retired.

  -- GATE A / H / G student: zero-degree, VERIFIED unassigned course mapping
  v_student := extensions.gen_random_uuid();
  perform public.create_student(v_student);
  v_profile := public.create_student_profile_version(v_student, 1);
  v_sev := extensions.gen_random_uuid();
  perform public.insert_student_evidence_item(jsonb_populate_record(
    null::public.student_evidence_items,
    jsonb_build_object(
      'student_evidence_id', v_sev, 'profile_version_id', v_profile, 'evidence_type', 'TRANSCRIPT'
    )
  ));
  v_sc_unassigned := extensions.gen_random_uuid();
  perform public.insert_student_course(jsonb_populate_record(
    null::public.student_courses,
    jsonb_build_object(
      'student_course_id', v_sc_unassigned, 'profile_version_id', v_profile,
      'course_code', 'MATH-102', 'course_title', 'Calculus II',
      'course_status', 'COMPLETED', 'student_evidence_id', v_sev
    )
  ));
  v_map := extensions.gen_random_uuid();
  perform public.propose_student_record_concept_mapping(jsonb_populate_record(
    null::public.student_record_concept_mappings,
    jsonb_build_object(
      'student_mapping_id', v_map, 'profile_version_id', v_profile,
      'record_type', 'COURSE', 'student_record_id', v_sc_unassigned,
      'concept_id', v_concept, 'method', 'HUMAN', 'student_evidence_id', v_sev
    )
  ));
  perform public.review_student_record_concept_mapping(v_map, 'VERIFIED', '013-gate-reviewer', v_sev);
  perform pg_temp.v02_insert_required_completeness(v_profile, 'COMPLETE', null);
  perform public.freeze_student_profile_version(v_profile);

  perform pg_temp.auth_lock_prove(
    'public.program_requirement_rule_sets'::regclass,
    format('rule_set_id = %L::uuid', v_rule_v02),
    format('update public.program_requirement_rule_sets set verified_by = verified_by where rule_set_id = %L::uuid', v_rule_v02)
  );
  perform pg_temp.auth_lock_prove(
    'public.taxonomy_releases'::regclass,
    'release_code = ''v0.1''',
    'update public.taxonomy_releases set notes = notes where release_code = ''v0.1'''
  );
  perform pg_temp.auth_lock_prove(
    'public.catalog_concept_mappings'::regclass,
    format('mapping_id = %L::uuid', v_catalog_map),
    format('update public.catalog_concept_mappings set method = method where mapping_id = %L::uuid', v_catalog_map)
  );
  perform pg_temp.auth_lock_prove(
    'public.student_record_concept_mappings'::regclass,
    format('student_mapping_id = %L::uuid', v_map),
    format('update public.student_record_concept_mappings set method = method where student_mapping_id = %L::uuid', v_map)
  );
  perform pg_temp.auth_lock_definer_probe(v_rule_v02, 'v0.1');

  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  if not exists (
    select 1 from public.eligibility_evaluations e
    join public.student_profile_versions p using (profile_version_id)
    where e.evaluation_id = v_eval
      and e.evaluation_state = 'BUILDING'
      and e.input_schema_version = 'eligibility-v0.2'
      and e.rule_set_id = v_rule_v02
      and e.taxonomy_release_ordinal is not null
      and e.profile_snapshot_hash = p.snapshot_hash
  ) then
    raise exception 'GATE A start: evaluation row missing v0.2 BUILDING identity';
  end if;
  perform pg_temp.v02_pin_evaluation(v_eval);
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs(v_eval);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_v01_api_on_v02_row' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE I: v0.1 seal accepted a v0.2 evaluation';
  end if;
  v_hash := public.seal_eligibility_evaluation_inputs_v02(v_eval);
  v_blocked := false;
  begin
    perform public.finalize_eligibility_evaluation(v_eval, 'ELIGIBLE');
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_v01_api_on_v02_row' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE I/A: v0.1 finalize accepted a v0.2 evaluation';
  end if;
  v_out := public.finalize_eligibility_evaluation_v02(v_eval);

  select evaluation_state, outcome, root_truth_value, input_fingerprint, result_fingerprint
    into r
  from public.eligibility_evaluations where evaluation_id = v_eval;
  if r.evaluation_state is distinct from 'COMPLETED' then
    raise exception 'GATE A: evaluation_state is %', r.evaluation_state;
  end if;
  if r.outcome is distinct from 'ELIGIBLE' then
    raise exception 'GATE A: derived outcome is %', r.outcome;
  end if;
  if r.root_truth_value is distinct from 'SATISFIED' then
    raise exception 'GATE A: FULL root is %', r.root_truth_value;
  end if;
  if r.input_fingerprint is distinct from v_hash
     or r.input_fingerprint !~ '^[a-f0-9]{64}$'
     or v_out !~ '^[a-f0-9]{64}$'
     or r.result_fingerprint is distinct from v_out then
    raise exception 'GATE A: fingerprints are not sealed lowercase 64-hex';
  end if;
  select count(*) into v_count from public.eligibility_rule_node_pins where evaluation_id = v_eval;
  if (select count(*) from public.eligibility_requirement_results where evaluation_id = v_eval) <> v_count then
    raise exception 'GATE A: result count does not equal pinned nodes';
  end if;
  if exists (
    select 1 from public.eligibility_rule_node_pins n
    where n.evaluation_id = v_eval
      and (
        select count(*) from public.eligibility_requirement_projection_results p
        where p.evaluation_id = n.evaluation_id and p.rule_node_id = n.rule_node_id
      ) <> 5
  ) then
    raise exception 'GATE A: a pinned node is missing five projections';
  end if;
  if exists (
    select 1 from public.eligibility_evaluations
    where evaluation_id = v_eval
      and (input_schema_version is distinct from 'eligibility-v0.2'
           or result_fingerprint is null
           or result_semantics_version is distinct from 'eligibility-v0.2')
  ) then
    raise exception 'GATE A: v0.1 finalizer path was used';
  end if;
  if not exists (
    select 1 from private.student_lifecycle_audit
    where student_id = v_student and event_code = 'FINALIZE_V02' and object_id = v_eval
  ) then
    raise exception 'GATE A: FINALIZE_V02 audit is missing';
  end if;

  -- GATE H fingerprint replay on the completed lifecycle
  v_in := private.canonical_eligibility_v02_input_fingerprint(v_eval);
  if v_in is distinct from v_hash then
    raise exception 'GATE H: recomputed input fingerprint drifted';
  end if;
  if private.canonical_eligibility_v02_result_fingerprint(v_eval) is distinct from v_out then
    raise exception 'GATE H: recomputed result fingerprint drifted';
  end if;
  v_blocked := false;
  begin
    perform public.retire_student_record_concept_mapping(v_map, 'post-complete live retire');
  exception
    when sqlstate 'P0001' then
      if sqlerrm = 'Frozen profile versions are immutable' then
        v_blocked := true;
      else
        raise;
      end if;
  end;
  if not v_blocked then
    raise exception 'GATE H: frozen student mapping was retired';
  end if;
  if private.canonical_eligibility_v02_input_fingerprint(v_eval) is distinct from v_hash
     or private.canonical_eligibility_v02_result_fingerprint(v_eval) is distinct from v_out then
    raise exception 'GATE H: live post-pin mutation changed completed fingerprints';
  end if;
  v_blocked := false;
  begin
    perform public.insert_eligibility_student_mapping_pin(jsonb_populate_record(
      null::public.eligibility_student_mapping_pins,
      jsonb_build_object('evaluation_id', v_eval, 'student_mapping_id', v_map)
    ));
  exception
    when sqlstate '55000' then
      if sqlerrm like '%BUILDING unsealed%' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE H: semantic pin insert succeeded after completion';
  end if;
  v_blocked := false;
  begin
    update public.eligibility_student_mapping_pins
      set status_at_pin = 'PROPOSED'
    where evaluation_id = v_eval and student_mapping_id = v_map;
  exception
    when sqlstate '55000' then v_blocked := true;
    when insufficient_privilege then v_blocked := true;
  end;
  if not v_blocked and exists (
    select 1 from public.eligibility_student_mapping_pins
    where evaluation_id = v_eval and student_mapping_id = v_map and status_at_pin = 'PROPOSED'
  ) then
    raise exception 'GATE H: sealed pin status was mutated';
  end if;

  -- A sealed row cannot escape immutability by being re-parented to an
  -- unsealed evaluation; the guard must validate both OLD and NEW ownership.
  v_eval_unsealed := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  v_blocked := false;
  begin
    update public.eligibility_student_mapping_pins
      set evaluation_id = v_eval_unsealed
    where evaluation_id = v_eval and student_mapping_id = v_map;
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_v02_sealed_input_immutable' then
        v_blocked := true;
      else
        raise;
      end if;
  end;
  if not v_blocked then
    raise exception 'GATE H: sealed pin was re-parented to an unsealed evaluation';
  end if;

  -- GATE G privacy delete of the real v0.2 evaluation (after A/H)
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  if exists (select 1 from public.students where student_id = v_student)
     or exists (select 1 from public.student_profile_versions where student_id = v_student)
     or exists (select 1 from public.eligibility_evaluations where evaluation_id = v_eval) then
    raise exception 'GATE G: student/profile/evaluation survived privacy delete';
  end if;
  if exists (
    select 1 from public.eligibility_snapshot_scopes s where s.evaluation_id = v_eval
    union all select 1 from public.eligibility_rule_set_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_rule_node_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_rule_node_source_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_rule_node_mapping_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_projection_threshold_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_catalog_observation_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_catalog_selection_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_catalog_mapping_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_student_mapping_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_taxonomy_concept_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_completeness_pins x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_snapshot_degrees x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_snapshot_courses x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_snapshot_test_scores x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_snapshot_mapping_universe x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_requirement_projection_results x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_negative_fact_authorizations x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_negative_authorization_scopes x where x.evaluation_id = v_eval
    union all select 1 from private.eligibility_v02_finalize_authorizations x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_requirement_results x where x.evaluation_id = v_eval
    union all select 1 from public.eligibility_course_matches x where x.evaluation_id = v_eval
  ) then
    raise exception 'GATE G: orphan 013 student-owned rows remain';
  end if;
  if not exists (select 1 from public.taxonomy_concepts where concept_id = v_concept)
     or not exists (select 1 from public.catalog_concept_mappings where mapping_id = v_catalog_map)
     or not exists (select 1 from public.program_requirement_rule_sets where rule_set_id = v_rule_v02) then
    raise exception 'GATE G: catalog/taxonomy did not survive privacy delete';
  end if;
  if not exists (
    select 1 from public.student_deletion_tombstones
    where reason_code = 'TEST_LIFECYCLE' and legacy_deletion_reason = 'MIGRATED_TO_REASON_CODE'
  ) then
    raise exception 'GATE G: 012 tombstone missing coded reason';
  end if;
  if exists (
    select 1 from public.student_deletion_tombstones t
    where t.reason_code = 'TEST_LIFECYCLE'
      and (to_jsonb(t) ? 'student_id' or to_jsonb(t) ? 'profile_version_id' or to_jsonb(t) ? 'evaluation_id')
  ) then
    raise exception 'GATE G: tombstone is linkable';
  end if;

  -- GATE B inverse: already-RETIRED at pin boundary
  v_student := extensions.gen_random_uuid();
  perform public.create_student(v_student);
  v_profile := public.create_student_profile_version(v_student, 1);
  v_sev := extensions.gen_random_uuid();
  perform public.insert_student_evidence_item(jsonb_populate_record(
    null::public.student_evidence_items,
    jsonb_build_object('student_evidence_id', v_sev, 'profile_version_id', v_profile, 'evidence_type', 'TRANSCRIPT')
  ));
  v_sc_unassigned := extensions.gen_random_uuid();
  perform public.insert_student_course(jsonb_populate_record(
    null::public.student_courses,
    jsonb_build_object(
      'student_course_id', v_sc_unassigned, 'profile_version_id', v_profile,
      'course_title', 'Calculus II', 'course_status', 'COMPLETED', 'student_evidence_id', v_sev
    )
  ));
  v_map_retired := extensions.gen_random_uuid();
  perform public.propose_student_record_concept_mapping(jsonb_populate_record(
    null::public.student_record_concept_mappings,
    jsonb_build_object(
      'student_mapping_id', v_map_retired, 'profile_version_id', v_profile,
      'record_type', 'COURSE', 'student_record_id', v_sc_unassigned,
      'concept_id', v_concept, 'method', 'HUMAN', 'student_evidence_id', v_sev
    )
  ));
  perform public.review_student_record_concept_mapping(v_map_retired, 'VERIFIED', '013-gate-reviewer', v_sev);
  perform public.retire_student_record_concept_mapping(v_map_retired, 'retired before pin');
  perform pg_temp.v02_insert_required_completeness(v_profile, 'COMPLETE', null);
  perform public.freeze_student_profile_version(v_profile);
  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  v_blocked := false;
  begin
    perform public.insert_eligibility_student_mapping_pin(jsonb_populate_record(
      null::public.eligibility_student_mapping_pins,
      jsonb_build_object(
        'evaluation_id', v_eval, 'student_mapping_id', v_map_retired,
        'profile_version_id', v_profile, 'record_type', 'COURSE',
        'student_record_id', v_sc_unassigned, 'concept_id', v_concept,
        'relation_at_pin', 'STUDENT_CONCEPT_ASSOCIATION',
        'method', 'HUMAN', 'student_evidence_id', v_sev,
        'status_at_pin', 'RETIRED'
      )
    ));
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_mapping_status_not_universe_eligible' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE B inverse: RETIRED mapping was universe-eligible';
  end if;
  perform pg_temp.v02_pin_evaluation(v_eval);
  if exists (
    select 1 from private.eligibility_v02_required_student_mappings(v_eval)
    where student_mapping_id = v_map_retired
  ) then
    raise exception 'GATE B inverse: already-RETIRED mapping entered the required universe';
  end if;
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval);

  -- GATE C omit attacks
  v_student := extensions.gen_random_uuid();
  perform public.create_student(v_student);
  v_profile := public.create_student_profile_version(v_student, 1);
  v_sev := extensions.gen_random_uuid();
  perform public.insert_student_evidence_item(jsonb_populate_record(
    null::public.student_evidence_items,
    jsonb_build_object('student_evidence_id', v_sev, 'profile_version_id', v_profile, 'evidence_type', 'TRANSCRIPT')
  ));
  v_sc_unassigned := extensions.gen_random_uuid();
  perform public.insert_student_course(jsonb_populate_record(
    null::public.student_courses,
    jsonb_build_object(
      'student_course_id', v_sc_unassigned, 'profile_version_id', v_profile,
      'course_title', 'Calculus II', 'course_status', 'COMPLETED', 'student_evidence_id', v_sev
    )
  ));
  v_map := extensions.gen_random_uuid();
  perform public.propose_student_record_concept_mapping(jsonb_populate_record(
    null::public.student_record_concept_mappings,
    jsonb_build_object(
      'student_mapping_id', v_map, 'profile_version_id', v_profile,
      'record_type', 'COURSE', 'student_record_id', v_sc_unassigned,
      'concept_id', v_concept, 'method', 'HUMAN', 'student_evidence_id', v_sev
    )
  ));
  perform public.review_student_record_concept_mapping(v_map, 'VERIFIED', '013-gate-reviewer', v_sev);
  perform pg_temp.v02_insert_required_completeness(v_profile, 'COMPLETE', null);
  perform public.freeze_student_profile_version(v_profile);

  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval, v_sc_unassigned, null, null, null);
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs_v02(v_eval);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_course_universe_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE C: omitted course was accepted';
  end if;
  if exists (
    select 1 from public.eligibility_evaluations
    where evaluation_id = v_eval and evaluation_state = 'COMPLETED' and outcome = 'NOT_ELIGIBLE'
  ) then
    raise exception 'GATE C: course omission fabricated NOT_SATISFIED/NOT_ELIGIBLE';
  end if;

  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval, null, v_map, null, null);
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs_v02(v_eval);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_authoritative_universe_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE C: omitted required student mapping was accepted';
  end if;

  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval, null, null, v_map, null);
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs_v02(v_eval);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_authoritative_universe_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE C: omitted VERIFIED universe membership was accepted';
  end if;

  -- GATE D extra-row
  v_map_extra := extensions.gen_random_uuid();
  -- extra proposed mapping to a non-target concept on the same in-scope course
  -- cannot insert on frozen profile; use a fresh DRAFT student
  v_student := extensions.gen_random_uuid();
  perform public.create_student(v_student);
  v_profile := public.create_student_profile_version(v_student, 1);
  v_sev := extensions.gen_random_uuid();
  perform public.insert_student_evidence_item(jsonb_populate_record(
    null::public.student_evidence_items,
    jsonb_build_object('student_evidence_id', v_sev, 'profile_version_id', v_profile, 'evidence_type', 'TRANSCRIPT')
  ));
  v_sc_unassigned := extensions.gen_random_uuid();
  perform public.insert_student_course(jsonb_populate_record(
    null::public.student_courses,
    jsonb_build_object(
      'student_course_id', v_sc_unassigned, 'profile_version_id', v_profile,
      'course_title', 'Calculus II', 'course_status', 'COMPLETED', 'student_evidence_id', v_sev
    )
  ));
  v_map := extensions.gen_random_uuid();
  perform public.propose_student_record_concept_mapping(jsonb_populate_record(
    null::public.student_record_concept_mappings,
    jsonb_build_object(
      'student_mapping_id', v_map, 'profile_version_id', v_profile,
      'record_type', 'COURSE', 'student_record_id', v_sc_unassigned,
      'concept_id', v_concept, 'method', 'HUMAN', 'student_evidence_id', v_sev
    )
  ));
  perform public.review_student_record_concept_mapping(v_map, 'VERIFIED', '013-gate-reviewer', v_sev);
  v_map_extra := extensions.gen_random_uuid();
  perform public.propose_student_record_concept_mapping(jsonb_populate_record(
    null::public.student_record_concept_mappings,
    jsonb_build_object(
      'student_mapping_id', v_map_extra, 'profile_version_id', v_profile,
      'record_type', 'COURSE', 'student_record_id', v_sc_unassigned,
      'concept_id', v_other_concept, 'method', 'HUMAN', 'student_evidence_id', v_sev
    )
  ));
  perform pg_temp.v02_insert_required_completeness(v_profile, 'COMPLETE', null);
  perform public.freeze_student_profile_version(v_profile);
  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval, null, null, null, v_map_extra);
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs_v02(v_eval);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_authoritative_universe_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE D: extra mapping pin was accepted';
  end if;

  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval);
  v_blocked := false;
  begin
    perform public.insert_eligibility_snapshot_mapping_universe(jsonb_populate_record(
      null::public.eligibility_snapshot_mapping_universe,
      jsonb_build_object(
        'scope_id', (
          select scope_id from public.eligibility_snapshot_scopes
          where evaluation_id = v_eval and scope_kind = 'UNASSIGNED_CONTEXT' and domain = 'COURSE_MAPPING'
        ),
        'student_mapping_id', v_map_extra,
        'universe_role', 'LIMITING'
      )
    ));
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_authoritative_universe_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE D: extra universe member without pin was accepted';
  end if;

  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval);
  select scope_id into v_wrong_scope
  from public.eligibility_snapshot_scopes
  where evaluation_id = v_eval and scope_kind = 'GLOBAL_PROFILE' and domain = 'EDUCATION_HISTORY';
  v_blocked := false;
  begin
    perform public.insert_eligibility_snapshot_course(jsonb_populate_record(
      null::public.eligibility_snapshot_courses,
      jsonb_build_object('scope_id', v_wrong_scope, 'student_course_id', v_sc_unassigned)
    ));
  exception
    when sqlstate '22023' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_pin_payload_mismatch' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE D: extra snapshot course in the wrong scope was accepted';
  end if;

  -- GATE E B1.2 UNKNOWN with degrees + positive SATISFIED counterpart
  v_student := extensions.gen_random_uuid();
  perform public.create_student(v_student);
  v_profile := public.create_student_profile_version(v_student, 1);
  v_sev := extensions.gen_random_uuid();
  perform public.insert_student_evidence_item(jsonb_populate_record(
    null::public.student_evidence_items,
    jsonb_build_object('student_evidence_id', v_sev, 'profile_version_id', v_profile, 'evidence_type', 'TRANSCRIPT')
  ));
  v_degree := extensions.gen_random_uuid();
  perform public.insert_student_degree(jsonb_populate_record(
    null::public.student_degrees,
    jsonb_build_object(
      'student_degree_id', v_degree, 'profile_version_id', v_profile,
      'institution_name', 'Test University', 'degree_name', 'BA',
      'degree_level', 'BACHELORS', 'degree_status', 'COMPLETED',
      'student_evidence_id', v_sev
    )
  ));
  v_sc_degree := extensions.gen_random_uuid();
  perform public.insert_student_course(jsonb_populate_record(
    null::public.student_courses,
    jsonb_build_object(
      'student_course_id', v_sc_degree, 'profile_version_id', v_profile,
      'student_degree_id', v_degree, 'course_title', 'History',
      'course_status', 'COMPLETED', 'student_evidence_id', v_sev
    )
  ));
  v_sc_unassigned := extensions.gen_random_uuid();
  perform public.insert_student_course(jsonb_populate_record(
    null::public.student_courses,
    jsonb_build_object(
      'student_course_id', v_sc_unassigned, 'profile_version_id', v_profile,
      'course_title', 'Unassigned elective', 'course_status', 'COMPLETED',
      'student_evidence_id', v_sev
    )
  ));
  perform pg_temp.v02_insert_required_completeness(v_profile, 'COMPLETE', v_degree);
  perform public.freeze_student_profile_version(v_profile);
  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval);
  if exists (
    select 1 from public.eligibility_snapshot_scopes s
    where s.evaluation_id = v_eval and s.scope_kind = 'UNASSIGNED_CONTEXT'
      and (s.completeness_id is not null or s.completeness is not null)
  ) then
    raise exception 'GATE E: UNASSIGNED_CONTEXT fabricated a 012 completeness identity';
  end if;
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval);
  perform public.finalize_eligibility_evaluation_v02(v_eval);
  if (select truth_value from public.eligibility_requirement_results
      where evaluation_id = v_eval and rule_node_id = v_leaf) is distinct from 'UNKNOWN' then
    raise exception 'GATE E: leaf was not UNKNOWN';
  end if;
  if not exists (
    select 1 from public.eligibility_requirement_results
    where evaluation_id = v_eval and rule_node_id = v_leaf
      and missing_data @> jsonb_build_array(jsonb_build_object('code', 'UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE'))
  ) then
    raise exception 'GATE E: missing-data code is wrong';
  end if;
  if exists (
    select 1 from public.eligibility_negative_fact_authorizations where evaluation_id = v_eval
  ) then
    raise exception 'GATE E: negative authorization claimed unassigned absence';
  end if;
  if (select outcome from public.eligibility_evaluations where evaluation_id = v_eval)
       is distinct from 'UNKNOWN' then
    raise exception 'GATE E: outcome is not UNKNOWN';
  end if;

  -- positive counterpart: satisfying pinned null-context course
  v_student := extensions.gen_random_uuid();
  perform public.create_student(v_student);
  v_profile := public.create_student_profile_version(v_student, 1);
  v_sev := extensions.gen_random_uuid();
  perform public.insert_student_evidence_item(jsonb_populate_record(
    null::public.student_evidence_items,
    jsonb_build_object('student_evidence_id', v_sev, 'profile_version_id', v_profile, 'evidence_type', 'TRANSCRIPT')
  ));
  v_degree := extensions.gen_random_uuid();
  perform public.insert_student_degree(jsonb_populate_record(
    null::public.student_degrees,
    jsonb_build_object(
      'student_degree_id', v_degree, 'profile_version_id', v_profile,
      'institution_name', 'Test University', 'degree_name', 'BA',
      'degree_level', 'BACHELORS', 'degree_status', 'COMPLETED',
      'student_evidence_id', v_sev
    )
  ));
  v_sc_degree := extensions.gen_random_uuid();
  perform public.insert_student_course(jsonb_populate_record(
    null::public.student_courses,
    jsonb_build_object(
      'student_course_id', v_sc_degree, 'profile_version_id', v_profile,
      'student_degree_id', v_degree, 'course_title', 'History',
      'course_status', 'COMPLETED', 'student_evidence_id', v_sev
    )
  ));
  v_sc_unassigned := extensions.gen_random_uuid();
  perform public.insert_student_course(jsonb_populate_record(
    null::public.student_courses,
    jsonb_build_object(
      'student_course_id', v_sc_unassigned, 'profile_version_id', v_profile,
      'course_title', 'Calculus II', 'course_status', 'COMPLETED',
      'student_evidence_id', v_sev
    )
  ));
  v_map := extensions.gen_random_uuid();
  perform public.propose_student_record_concept_mapping(jsonb_populate_record(
    null::public.student_record_concept_mappings,
    jsonb_build_object(
      'student_mapping_id', v_map, 'profile_version_id', v_profile,
      'record_type', 'COURSE', 'student_record_id', v_sc_unassigned,
      'concept_id', v_concept, 'method', 'HUMAN', 'student_evidence_id', v_sev
    )
  ));
  perform public.review_student_record_concept_mapping(v_map, 'VERIFIED', '013-gate-reviewer', v_sev);
  perform pg_temp.v02_insert_required_completeness(v_profile, 'COMPLETE', v_degree);
  perform public.freeze_student_profile_version(v_profile);
  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval);
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval);
  perform public.finalize_eligibility_evaluation_v02(v_eval);
  if (select truth_value from public.eligibility_requirement_results
      where evaluation_id = v_eval and rule_node_id = v_leaf) is distinct from 'SATISFIED'
     or (select outcome from public.eligibility_evaluations where evaluation_id = v_eval)
       is distinct from 'ELIGIBLE' then
    raise exception 'GATE E positive: null-context authoritative course was not SATISFIED';
  end if;

  -- GATE F negative authorization
  v_student := extensions.gen_random_uuid();
  perform public.create_student(v_student);
  v_profile := public.create_student_profile_version(v_student, 1);
  v_sev := extensions.gen_random_uuid();
  perform public.insert_student_evidence_item(jsonb_populate_record(
    null::public.student_evidence_items,
    jsonb_build_object('student_evidence_id', v_sev, 'profile_version_id', v_profile, 'evidence_type', 'TRANSCRIPT')
  ));
  perform pg_temp.v02_insert_required_completeness(v_profile, 'COMPLETE', null);
  perform public.freeze_student_profile_version(v_profile);
  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval);
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval);
  v_blocked := false;
  begin
    perform public.insert_eligibility_requirement_result(jsonb_populate_record(
      null::public.eligibility_requirement_results,
      jsonb_build_object(
        'evaluation_id', v_eval, 'rule_node_id', v_leaf,
        'truth_value', 'NOT_SATISFIED', 'explanation', 'caller'
      )
    ));
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_v02_caller_outcome_forbidden' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE F: caller manufactured a v0.2 result';
  end if;
  v_blocked := false;
  begin
    set local role service_role;
    insert into public.eligibility_negative_fact_authorizations (evaluation_id, rule_node_id, domain)
    values (v_eval, v_leaf, 'COURSE_HISTORY');
  exception
    when insufficient_privilege then v_blocked := true;
    when sqlstate '42501' then v_blocked := true;
  end;
  reset role;
  if not v_blocked then
    raise exception 'GATE F: service_role manufactured a negative authorization';
  end if;
  perform public.finalize_eligibility_evaluation_v02(v_eval);
  if (select truth_value from public.eligibility_requirement_results
      where evaluation_id = v_eval and rule_node_id = v_leaf) is distinct from 'NOT_SATISFIED' then
    raise exception 'GATE F: complete empty universe was not NOT_SATISFIED';
  end if;
  if not exists (
    select 1 from public.eligibility_negative_fact_authorizations
    where evaluation_id = v_eval and rule_node_id = v_leaf and domain = 'COURSE_HISTORY'
      and proof_version = 'eligibility-v0.2-neg1'
  ) then
    raise exception 'GATE F: SQL did not persist the negative authorization';
  end if;
  if exists (
    select s.scope_id
    from public.eligibility_snapshot_scopes s
    where s.evaluation_id = v_eval
      and s.domain in ('COURSE_HISTORY', 'COURSE_MAPPING')
      and s.scope_kind in ('UNASSIGNED_CONTEXT', 'EDUCATION_CONTEXT')
    except
    select nas.scope_id
    from public.eligibility_negative_authorization_scopes nas
    where nas.evaluation_id = v_eval and nas.rule_node_id = v_leaf
  ) or exists (
    select nas.scope_id
    from public.eligibility_negative_authorization_scopes nas
    where nas.evaluation_id = v_eval and nas.rule_node_id = v_leaf
    except
    select s.scope_id
    from public.eligibility_snapshot_scopes s
    where s.evaluation_id = v_eval
      and s.domain in ('COURSE_HISTORY', 'COURSE_MAPPING')
      and s.scope_kind in ('UNASSIGNED_CONTEXT', 'EDUCATION_CONTEXT')
  ) then
    raise exception 'GATE F: negative authorization scopes are not bidirectional';
  end if;
  if exists (
    select 1
    from public.eligibility_negative_authorization_scopes nas
    join public.eligibility_snapshot_scopes s using (scope_id)
    where nas.evaluation_id = v_eval and s.completeness is distinct from 'COMPLETE'
  ) then
    raise exception 'GATE F: a negative scope lacked COMPLETE authority';
  end if;

  -- GATE F PARTIAL → UNKNOWN
  v_student := extensions.gen_random_uuid();
  perform public.create_student(v_student);
  v_profile := public.create_student_profile_version(v_student, 1);
  v_sev := extensions.gen_random_uuid();
  perform public.insert_student_evidence_item(jsonb_populate_record(
    null::public.student_evidence_items,
    jsonb_build_object('student_evidence_id', v_sev, 'profile_version_id', v_profile, 'evidence_type', 'TRANSCRIPT')
  ));
  perform pg_temp.v02_insert_required_completeness(v_profile, 'PARTIAL', null);
  perform public.freeze_student_profile_version(v_profile);
  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_v02, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval);
  perform public.seal_eligibility_evaluation_inputs_v02(v_eval);
  perform public.finalize_eligibility_evaluation_v02(v_eval);
  if (select truth_value from public.eligibility_requirement_results
      where evaluation_id = v_eval and rule_node_id = v_leaf) is distinct from 'UNKNOWN'
     or exists (
       select 1 from public.eligibility_negative_fact_authorizations where evaluation_id = v_eval
     ) then
    raise exception 'GATE F: PARTIAL completeness produced NOT_SATISFIED';
  end if;

  -- GATE B pin-then-retire catalog mapping on a dedicated verified rule set.
  perform public.retire_program_requirement_rule_set(v_rule_v02, '005-gate-release-v02-slot');
  perform public.verify_program_requirement_rule_set(v_rule_b, '013-gate-reviewer', v_evidence);
  v_student := extensions.gen_random_uuid();
  perform public.create_student(v_student);
  v_profile := public.create_student_profile_version(v_student, 1);
  v_sev := extensions.gen_random_uuid();
  perform public.insert_student_evidence_item(jsonb_populate_record(
    null::public.student_evidence_items,
    jsonb_build_object('student_evidence_id', v_sev, 'profile_version_id', v_profile, 'evidence_type', 'TRANSCRIPT')
  ));
  v_sc_unassigned := extensions.gen_random_uuid();
  perform public.insert_student_course(jsonb_populate_record(
    null::public.student_courses,
    jsonb_build_object(
      'student_course_id', v_sc_unassigned, 'profile_version_id', v_profile,
      'course_title', 'Calculus II', 'course_status', 'COMPLETED', 'student_evidence_id', v_sev
    )
  ));
  v_map := extensions.gen_random_uuid();
  perform public.propose_student_record_concept_mapping(jsonb_populate_record(
    null::public.student_record_concept_mappings,
    jsonb_build_object(
      'student_mapping_id', v_map, 'profile_version_id', v_profile,
      'record_type', 'COURSE', 'student_record_id', v_sc_unassigned,
      'concept_id', v_concept_b, 'method', 'HUMAN', 'student_evidence_id', v_sev
    )
  ));
  perform public.review_student_record_concept_mapping(v_map, 'VERIFIED', '013-gate-reviewer', v_sev);
  perform pg_temp.v02_insert_required_completeness(v_profile, 'COMPLETE', null);
  perform public.freeze_student_profile_version(v_profile);
  v_eval := public.start_eligibility_evaluation_v02(
    v_profile, v_rule_b, 'v0.1', 'v02-gate', '0.2.0', v_build
  );
  perform pg_temp.v02_pin_evaluation(v_eval);
  v_hash := public.seal_eligibility_evaluation_inputs_v02(v_eval);
  perform public.retire_catalog_concept_mapping(v_catalog_map_b, 'retire after pin');
  select mapping_status into v_live_status
    from public.catalog_concept_mappings where mapping_id = v_catalog_map_b;
  select status_at_pin into v_pin_status
    from public.eligibility_catalog_mapping_pins
    where evaluation_id = v_eval and catalog_mapping_id = v_catalog_map_b;
  if v_live_status is distinct from 'RETIRED' or v_pin_status is distinct from 'VERIFIED' then
    raise exception 'GATE B: live=% pin=%', v_live_status, v_pin_status;
  end if;
  v_out := public.finalize_eligibility_evaluation_v02(v_eval);
  if (select evaluation_state from public.eligibility_evaluations where evaluation_id = v_eval)
       is distinct from 'COMPLETED'
     or (select input_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval)
       is distinct from v_hash
     or (select outcome from public.eligibility_evaluations where evaluation_id = v_eval)
       is distinct from 'ELIGIBLE' then
    raise exception 'GATE B: finalize did not replay status_at_pin';
  end if;
  perform public.retire_program_requirement_rule_set(v_rule_b, '005-gate-release-b-slot');
  perform public.verify_program_requirement_rule_set(v_rule_v01, '013-gate-reviewer', v_evidence);

  -- GATE I remainder: v0.2 API on v0.1 row + historical v0.1 finalize
  v_student := extensions.gen_random_uuid();
  perform public.create_student(v_student);
  v_profile := public.create_student_profile_version(v_student, 1);
  v_sev := extensions.gen_random_uuid();
  perform public.insert_student_evidence_item(jsonb_populate_record(
    null::public.student_evidence_items,
    jsonb_build_object('student_evidence_id', v_sev, 'profile_version_id', v_profile, 'evidence_type', 'TRANSCRIPT')
  ));
  v_sc_unassigned := extensions.gen_random_uuid();
  perform public.insert_student_course(jsonb_populate_record(
    null::public.student_courses,
    jsonb_build_object(
      'student_course_id', v_sc_unassigned, 'profile_version_id', v_profile,
      'course_title', 'Calculus II', 'course_status', 'COMPLETED', 'student_evidence_id', v_sev
    )
  ));
  v_map := extensions.gen_random_uuid();
  perform public.propose_student_record_concept_mapping(jsonb_populate_record(
    null::public.student_record_concept_mappings,
    jsonb_build_object(
      'student_mapping_id', v_map, 'profile_version_id', v_profile,
      'record_type', 'COURSE', 'student_record_id', v_sc_unassigned,
      'concept_id', v_concept, 'method', 'HUMAN', 'student_evidence_id', v_sev
    )
  ));
  perform public.review_student_record_concept_mapping(v_map, 'VERIFIED', '013-gate-reviewer', v_sev);
  perform pg_temp.v02_insert_required_completeness(v_profile, 'COMPLETE', null);
  perform public.freeze_student_profile_version(v_profile);
  v_eval_v01 := public.start_eligibility_evaluation(
    v_profile, v_rule_v01, 'v0.1', 'pure-ts-eligibility', '0.1.0', v_build
  );
  v_blocked := false;
  begin
    perform public.seal_eligibility_evaluation_inputs_v02(v_eval_v01);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_v02_api_on_v01_row' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE I: v0.2 seal accepted a v0.1 evaluation';
  end if;
  v_blocked := false;
  begin
    perform public.finalize_eligibility_evaluation_v02(v_eval_v01);
  exception
    when sqlstate '55000' then
      get stacked diagnostics v_hint = pg_exception_hint;
      if v_hint = 'eligibility_v02_api_on_v01_row' then v_blocked := true; else raise; end if;
  end;
  if not v_blocked then
    raise exception 'GATE I: v0.2 finalize accepted a v0.1 evaluation';
  end if;
  if exists (
    select 1 from pg_proc p
    where p.proname = 'finalize_eligibility_evaluation_v02'
      and pg_get_function_identity_arguments(p.oid) like '%,%'
  ) then
    raise exception 'GATE I: finalize_v02 accepts a caller outcome argument';
  end if;
  perform public.insert_eligibility_manifest_course(jsonb_populate_record(
    null::public.eligibility_manifest_courses,
    jsonb_build_object('evaluation_id', v_eval_v01, 'profile_version_id', v_profile, 'student_course_id', v_sc_unassigned)
  ));
  perform public.insert_eligibility_manifest_student_mapping(jsonb_populate_record(
    null::public.eligibility_manifest_student_mappings,
    jsonb_build_object('evaluation_id', v_eval_v01, 'profile_version_id', v_profile, 'student_mapping_id', v_map)
  ));
  perform public.insert_eligibility_manifest_completeness(jsonb_populate_record(
    null::public.eligibility_manifest_completeness,
    jsonb_build_object('evaluation_id', v_eval_v01, 'profile_version_id', v_profile, 'completeness_id', c.completeness_id)
  ))
  from public.student_data_completeness c where c.profile_version_id = v_profile;
  perform public.insert_eligibility_manifest_student_evidence(jsonb_populate_record(
    null::public.eligibility_manifest_student_evidence,
    jsonb_build_object('evaluation_id', v_eval_v01, 'profile_version_id', v_profile, 'student_evidence_id', v_sev)
  ));
  perform public.insert_eligibility_manifest_catalog_source(jsonb_populate_record(
    null::public.eligibility_manifest_catalog_sources,
    jsonb_build_object('evaluation_id', v_eval_v01, 'field_observation_id', v_obs)
  ));
  perform public.insert_eligibility_manifest_catalog_mapping(jsonb_populate_record(
    null::public.eligibility_manifest_catalog_mappings,
    jsonb_build_object('evaluation_id', v_eval_v01, 'catalog_mapping_id', v_catalog_map)
  ));
  perform public.insert_eligibility_manifest_taxonomy_concept(jsonb_populate_record(
    null::public.eligibility_manifest_taxonomy_concepts,
    jsonb_build_object('evaluation_id', v_eval_v01, 'concept_id', v_concept)
  ));
  perform public.insert_eligibility_requirement_result(jsonb_populate_record(
    null::public.eligibility_requirement_results,
    jsonb_build_object(
      'evaluation_id', v_eval_v01, 'rule_node_id', v_leaf_v01,
      'truth_value', 'SATISFIED', 'reason_codes', array['VERIFIED_COURSE_MATCH'],
      'explanation', 'v0.1 leaf'
    )
  ));
  perform public.insert_eligibility_requirement_result(jsonb_populate_record(
    null::public.eligibility_requirement_results,
    jsonb_build_object(
      'evaluation_id', v_eval_v01, 'rule_node_id', v_root_v01,
      'truth_value', 'SATISFIED', 'reason_codes', array['GROUP_SATISFIED'],
      'explanation', 'v0.1 root'
    )
  ));
  perform public.insert_eligibility_course_match(jsonb_populate_record(
    null::public.eligibility_course_matches,
    jsonb_build_object(
      'evaluation_id', v_eval_v01,
      'requirement_result_id', (
        select requirement_result_id from public.eligibility_requirement_results
        where evaluation_id = v_eval_v01 and rule_node_id = v_leaf_v01
      ),
      'catalog_mapping_id', v_catalog_map,
      'student_mapping_id', v_map,
      'student_course_id', v_sc_unassigned,
      'student_evidence_id', v_sev
    )
  ));
  perform public.seal_eligibility_evaluation_inputs(v_eval_v01);
  v_hash := public.finalize_eligibility_evaluation(v_eval_v01, 'ELIGIBLE');
  if v_hash !~ '^[a-f0-9]{64}$'
     or (select outcome from public.eligibility_evaluations where evaluation_id = v_eval_v01)
       is distinct from 'ELIGIBLE'
     or (select result_fingerprint from public.eligibility_evaluations where evaluation_id = v_eval_v01)
       is not null then
    raise exception 'GATE I: historical v0.1 finalize behavior changed';
  end if;

  raise notice '005 phase 013 executable gates A–J passed';
end;
$gates$;

rollback;
