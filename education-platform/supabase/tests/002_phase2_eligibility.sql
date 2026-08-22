begin;

do $test$
declare
  v_program_version_id uuid;
  v_prerequisite_id uuid;
  v_observation_id uuid;
  v_wrong_observation_id uuid;
  v_evidence_id uuid;
  v_course_concept_id uuid := '10000000-0000-0000-0000-000000000032';
  v_catalog_mapping_id uuid;
  v_rule_set_id uuid;
  v_invalid_rule_set_id uuid;
  v_root_id uuid;
  v_leaf_id uuid;
  v_auth_user_id uuid := extensions.gen_random_uuid();
  v_student_id uuid := extensions.gen_random_uuid();
  v_other_student_id uuid := extensions.gen_random_uuid();
  v_profile_id uuid := extensions.gen_random_uuid();
  v_other_profile_id uuid := extensions.gen_random_uuid();
  v_student_evidence_id uuid;
  v_other_evidence_id uuid;
  v_course_id uuid;
  v_second_course_id uuid;
  v_other_degree_id uuid;
  v_student_mapping_id uuid;
  v_second_student_mapping_id uuid;
  v_evaluation_id uuid;
  v_second_evaluation_id uuid;
  v_third_evaluation_id uuid;
  v_leaf_result_id uuid;
  v_third_leaf_result_id uuid;
  v_first_fingerprint text;
  v_second_fingerprint text;
  v_third_fingerprint text;
  v_snapshot_hash text;
  v_actual integer;
  v_blocked boolean;
begin
  select count(*) into v_actual
  from public.program_requirement_rule_sets;
  if v_actual <> 0 then
    raise exception 'Production migrations must not force an unverified NYU rule set';
  end if;

  select program_version_id into v_program_version_id
  from public.program_versions
  where program_id = '00000000-0000-0000-0000-000000000301';

  select p.course_id, c.observation_id, o.evidence_id
  into v_prerequisite_id, v_observation_id, v_evidence_id
  from public.program_courses p
  join public.canonical_field_selections c
    on c.record_type = 'PROGRAM_COURSE'
   and c.record_id = p.course_id
   and c.field_name = 'course_name'
  join public.field_observations o
    on o.observation_id = c.observation_id
  where p.program_version_id = v_program_version_id
    and p.retired_at is null
  order by p.created_at
  limit 1;

  if v_prerequisite_id is null or v_observation_id is null then
    raise exception 'Phase 2 fixture requires an accepted NYU course observation';
  end if;

  select count(*) into v_actual
  from public.taxonomy_concepts
  where canonical_key = 'COURSE_CONCEPT.CALCULUS_II'
    and introduced_in_release = 'v0.1'
    and retired_in_release is null;
  if v_actual <> 1 then
    raise exception 'Stable taxonomy key seed is missing';
  end if;

  v_blocked := false;
  begin
    update public.taxonomy_concepts
    set canonical_key = 'COURSE_CONCEPT.CALCULUS_II_CHANGED'
    where concept_id = v_course_concept_id;
  exception when others then
    if sqlerrm like '%semantic identity is immutable%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Taxonomy canonical key was mutable';
  end if;

  v_blocked := false;
  begin
    insert into public.catalog_concept_mappings (
      record_type,
      record_id,
      concept_id,
      relation,
      mapping_status,
      method,
      confidence,
      model_version,
      verification_evidence_id
    ) values (
      'PROGRAM_COURSE',
      v_prerequisite_id,
      v_course_concept_id,
      'COURSE_EQUIVALENCY',
      'VERIFIED',
      'MODEL',
      1,
      'test-model',
      v_evidence_id
    );
  exception when sqlstate '55000' then
    if sqlerrm like '%cannot be inserted%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'A model mapping self-verified without reviewer authority';
  end if;

  v_blocked := false;
  begin
    insert into public.catalog_concept_mappings (
      record_type,
      record_id,
      concept_id,
      relation,
      mapping_status,
      method,
      reviewed_by,
      reviewed_at
    ) values (
      'PROGRAM_COURSE',
      v_prerequisite_id,
      v_course_concept_id,
      'COURSE_EQUIVALENCY',
      'VERIFIED',
      'HUMAN',
      'reviewer-without-evidence',
      now()
    );
  exception when sqlstate '55000' then
    if sqlerrm like '%cannot be inserted%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'A verified mapping was accepted without evidence';
  end if;

  insert into public.catalog_concept_mappings (
    record_type,
    record_id,
    concept_id,
    relation,
    mapping_status,
    method,
    confidence,
    model_version
  ) values (
    'PROGRAM_COURSE',
    v_prerequisite_id,
    v_course_concept_id,
    'COURSE_EQUIVALENCY',
    'PROPOSED',
    'MODEL',
    1,
    'test-model'
  ) returning mapping_id into v_catalog_mapping_id;

  insert into public.program_requirement_rule_sets (
    program_version_id,
    rule_set_version,
    taxonomy_release_code
  ) values (
    v_program_version_id,
    1,
    'v0.1'
  ) returning rule_set_id into v_rule_set_id;

  insert into public.program_requirement_nodes (
    rule_set_id,
    parent_node_id,
    sort_order,
    node_kind,
    group_operator,
    explanation_template
  ) values (
    v_rule_set_id,
    null,
    0,
    'GROUP',
    'ALL',
    'All ordinary requirements must be satisfied.'
  ) returning rule_node_id into v_root_id;

  insert into public.program_requirement_nodes (
    rule_set_id,
    parent_node_id,
    sort_order,
    node_kind,
    predicate_kind,
    requirement_strength,
    requirement_semantics,
    target_concept_id,
    explanation_template
  ) values (
    v_rule_set_id,
    v_root_id,
    0,
    'PREDICATE',
    'HAS_COURSE_CONCEPT',
    'HARD',
    'ORDINARY',
    v_course_concept_id,
    'The accepted prerequisite requires this reviewed course concept.'
  ) returning rule_node_id into v_leaf_id;

  insert into public.program_requirement_node_sources (
    rule_node_id,
    field_observation_id
  ) values (v_leaf_id, v_observation_id);
  insert into public.program_requirement_node_mappings (
    rule_node_id,
    catalog_mapping_id
  ) values (v_leaf_id, v_catalog_mapping_id);

  v_blocked := false;
  begin
    perform public.verify_program_requirement_rule_set(
      v_rule_set_id,
      'phase2-test-reviewer',
      v_evidence_id
    );
  exception when others then
    if sqlerrm like '%reviewed catalog mapping%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Rule verification accepted an unreviewed mapping';
  end if;

  perform public.review_catalog_concept_mapping(
    v_catalog_mapping_id,
    'VERIFIED',
    'phase2-test-reviewer',
    v_evidence_id
  );

  v_blocked := false;
  begin
    update public.catalog_concept_mappings
    set mapping_status = 'PROPOSED'
    where mapping_id = v_catalog_mapping_id;
  exception when others then
    if sqlerrm like '%only transition to RETIRED%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Verified mapping history was reversible';
  end if;

  perform public.verify_program_requirement_rule_set(
    v_rule_set_id,
    'phase2-test-reviewer',
    v_evidence_id
  );

  v_blocked := false;
  begin
    update public.program_requirement_nodes
    set explanation_template = 'Mutated verified interpretation'
    where rule_node_id = v_leaf_id;
  exception when others then
    if sqlerrm like '%immutable%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Verified rule content was mutable';
  end if;

  v_blocked := false;
  begin
    update public.program_requirement_rule_sets
    set status = 'RETIRED',
        retired_at = now(),
        retirement_reason = 'Direct bypass attempt'
    where rule_set_id = v_rule_set_id;
  exception when others then
    if sqlerrm like '%retire_program_requirement_rule_set%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Direct rule-set status mutation bypassed control';
  end if;

  insert into public.program_requirement_rule_sets (
    program_version_id,
    rule_set_version,
    taxonomy_release_code
  ) values (
    v_program_version_id,
    2,
    'v0.1'
  ) returning rule_set_id into v_invalid_rule_set_id;

  insert into public.program_requirement_nodes (
    rule_set_id,
    parent_node_id,
    node_kind,
    group_operator,
    minimum_children,
    explanation_template
  ) values (
    v_invalid_rule_set_id,
    null,
    'GROUP',
    'AT_LEAST',
    2,
    'Invalid test tree'
  ) returning rule_node_id into v_root_id;

  v_blocked := false;
  begin
    insert into public.program_requirement_nodes (
      rule_set_id,
      parent_node_id,
      node_kind,
      predicate_kind,
      requirement_strength,
      requirement_semantics,
      target_concept_id,
      explanation_template
    ) values (
      v_invalid_rule_set_id,
      (
        select rule_node_id
        from public.program_requirement_nodes
        where rule_set_id = v_rule_set_id
          and parent_node_id is null
      ),
      'PREDICATE',
      'HAS_COURSE_CONCEPT',
      'HARD',
      'ORDINARY',
      v_course_concept_id,
      'Cross-rule-set child attack'
    );
    set constraints all immediate;
  exception when foreign_key_violation then
    v_blocked := true;
  end;
  set constraints all deferred;
  if not v_blocked then
    raise exception 'Child referenced a parent from another rule set';
  end if;

  insert into public.program_requirement_nodes (
    rule_set_id,
    parent_node_id,
    node_kind,
    predicate_kind,
    requirement_strength,
    requirement_semantics,
    target_concept_id,
    explanation_template
  ) values (
    v_invalid_rule_set_id,
    v_root_id,
    'PREDICATE',
    'HAS_COURSE_CONCEPT',
    'HARD',
    'ORDINARY',
    v_course_concept_id,
    'Only child'
  ) returning rule_node_id into v_leaf_id;
  insert into public.program_requirement_node_sources values (
    v_leaf_id,
    v_observation_id
  );
  insert into public.program_requirement_node_mappings values (
    v_leaf_id,
    v_catalog_mapping_id
  );

  v_blocked := false;
  begin
    perform public.verify_program_requirement_rule_set(
      v_invalid_rule_set_id,
      'phase2-test-reviewer',
      v_evidence_id
    );
  exception when others then
    if sqlerrm like '%AT_LEAST cardinality%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Invalid AT_LEAST tree became verified';
  end if;

  select observation_id into v_wrong_observation_id
  from public.canonical_field_selections
  where record_type = 'PROGRAM'
    and record_id = '00000000-0000-0000-0000-000000000301'
    and field_name = 'cip_code';
  insert into public.program_requirement_rule_sets (
    program_version_id,
    rule_set_version,
    taxonomy_release_code
  ) values (
    v_program_version_id,
    3,
    'v0.1'
  ) returning rule_set_id into v_invalid_rule_set_id;
  insert into public.program_requirement_nodes (
    rule_set_id,
    node_kind,
    group_operator,
    explanation_template
  ) values (
    v_invalid_rule_set_id,
    'GROUP',
    'ALL',
    'Cross-program source attack root'
  ) returning rule_node_id into v_root_id;
  insert into public.program_requirement_nodes (
    rule_set_id,
    parent_node_id,
    node_kind,
    predicate_kind,
    requirement_strength,
    requirement_semantics,
    target_concept_id,
    explanation_template
  ) values (
    v_invalid_rule_set_id,
    v_root_id,
    'PREDICATE',
    'HAS_COURSE_CONCEPT',
    'HARD',
    'ORDINARY',
    v_course_concept_id,
    'Source must belong to the rule-set program version'
  ) returning rule_node_id into v_leaf_id;
  insert into public.program_requirement_node_sources
  values (v_leaf_id, v_wrong_observation_id);
  insert into public.program_requirement_node_mappings
  values (v_leaf_id, v_catalog_mapping_id);
  v_blocked := false;
  begin
    perform public.verify_program_requirement_rule_set(
      v_invalid_rule_set_id,
      'phase2-test-reviewer',
      v_evidence_id
    );
  exception when others then
    if sqlerrm like '%currently selected KNOWN source observation for this program version%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Rule verification accepted a source outside its program version';
  end if;

  insert into public.students (student_id) values (v_student_id);
  insert into public.students (student_id) values (v_other_student_id);
  insert into auth.users (id) values (v_auth_user_id);
  insert into private.student_identities (auth_user_id, student_id)
  values (v_auth_user_id, v_student_id);
  insert into public.student_profile_versions (
    profile_version_id,
    student_id,
    version_number
  ) values (v_profile_id, v_student_id, 1);
  insert into public.student_profile_versions (
    profile_version_id,
    student_id,
    version_number
  ) values (v_other_profile_id, v_other_student_id, 1);

  insert into public.student_evidence_items (
    profile_version_id,
    evidence_type
  ) values (
    v_profile_id,
    'TRANSCRIPT'
  ) returning student_evidence_id into v_student_evidence_id;
  insert into public.student_evidence_items (
    profile_version_id,
    evidence_type
  ) values (
    v_other_profile_id,
    'TRANSCRIPT'
  ) returning student_evidence_id into v_other_evidence_id;

  insert into public.student_degrees (
    profile_version_id,
    institution_name,
    degree_name,
    degree_level,
    degree_status,
    student_evidence_id
  ) values (
    v_other_profile_id,
    'Other University',
    'Bachelor of Science',
    'BACHELORS',
    'COMPLETED',
    v_other_evidence_id
  ) returning student_degree_id into v_other_degree_id;

  v_blocked := false;
  begin
    insert into public.student_courses (
      profile_version_id,
      student_degree_id,
      course_title,
      course_status,
      student_evidence_id
    ) values (
      v_profile_id,
      v_other_degree_id,
      'Cross-student course',
      'COMPLETED',
      v_student_evidence_id
    );
  exception when foreign_key_violation then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Composite ownership FK allowed a cross-profile degree';
  end if;

  insert into public.student_data_completeness (
    profile_version_id,
    education_context_id,
    domain,
    completeness
  )
  select v_other_profile_id, null, domain, 'COMPLETE'
  from unnest(enum_range(null::public.student_data_domain)) as value(domain);

  v_blocked := false;
  begin
    perform public.freeze_student_profile_version(v_other_profile_id);
  exception when others then
    if sqlerrm like '%education context requires explicit completeness%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Global completeness incorrectly covered an education context';
  end if;

  insert into public.student_data_completeness (
    profile_version_id,
    education_context_id,
    domain,
    completeness
  ) values
    (v_other_profile_id, v_other_degree_id, 'COURSE_HISTORY', 'COMPLETE'),
    (v_other_profile_id, v_other_degree_id, 'COURSE_MAPPING', 'COMPLETE');
  perform public.freeze_student_profile_version(v_other_profile_id);

  insert into public.student_courses (
    profile_version_id,
    course_code,
    course_title,
    course_status,
    student_evidence_id
  ) values (
    v_profile_id,
    'MATH-102',
    'Calculus II',
    'COMPLETED',
    v_student_evidence_id
  ) returning student_course_id into v_course_id;

  insert into public.student_courses (
    profile_version_id,
    course_code,
    course_title,
    course_status,
    student_evidence_id
  ) values (
    v_profile_id,
    'MATH-202',
    'Advanced Calculus',
    'COMPLETED',
    v_student_evidence_id
  ) returning student_course_id into v_second_course_id;

  v_blocked := false;
  begin
    insert into public.student_record_concept_mappings (
      profile_version_id,
      record_type,
      student_record_id,
      concept_id,
      mapping_status,
      method,
      model_version,
      reviewed_by,
      reviewed_at
    ) values (
      v_profile_id,
      'COURSE',
      v_course_id,
      v_course_concept_id,
      'VERIFIED',
      'MODEL',
      'test-model',
      'human-reviewer',
      now()
    );
  exception when sqlstate '55000' then
    if sqlerrm like '%cannot be inserted%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Student mapping became VERIFIED without evidence';
  end if;

  insert into public.student_record_concept_mappings (
    profile_version_id,
    record_type,
    student_record_id,
    concept_id,
    mapping_status,
    method,
    confidence,
    model_version,
    student_evidence_id
  ) values (
    v_profile_id,
    'COURSE',
    v_course_id,
    v_course_concept_id,
    'PROPOSED',
    'MODEL',
    0,
    'test-model',
    v_student_evidence_id
  ) returning student_mapping_id into v_student_mapping_id;
  perform public.review_student_record_concept_mapping(
    v_student_mapping_id, 'VERIFIED', 'human-reviewer', v_student_evidence_id
  );

  insert into public.student_record_concept_mappings (
    profile_version_id,
    record_type,
    student_record_id,
    concept_id,
    mapping_status,
    method,
    confidence,
    student_evidence_id
  ) values (
    v_profile_id,
    'COURSE',
    v_second_course_id,
    v_course_concept_id,
    'PROPOSED',
    'HUMAN',
    0,
    v_student_evidence_id
  ) returning student_mapping_id into v_second_student_mapping_id;
  perform public.review_student_record_concept_mapping(
    v_second_student_mapping_id, 'VERIFIED', 'human-reviewer', v_student_evidence_id
  );

  insert into public.student_data_completeness (
    profile_version_id,
    education_context_id,
    domain,
    completeness
  )
  select v_profile_id, null, domain, 'COMPLETE'
  from unnest(enum_range(null::public.student_data_domain)) as value(domain);

  perform public.freeze_student_profile_version(v_profile_id);
  select snapshot_hash into v_snapshot_hash
  from public.student_profile_versions
  where profile_version_id = v_profile_id;

  select rule_node_id into v_root_id
  from public.program_requirement_nodes
  where rule_set_id = v_rule_set_id and parent_node_id is null;
  select rule_node_id into v_leaf_id
  from public.program_requirement_nodes
  where rule_set_id = v_rule_set_id and node_kind = 'PREDICATE';

  insert into public.eligibility_evaluations (
    profile_version_id,
    rule_set_id,
    taxonomy_release_code,
    evaluator_name,
    evaluator_version,
    evaluator_build_hash,
    input_schema_version,
    profile_snapshot_hash
  ) values (
    v_profile_id,
    v_rule_set_id,
    'v0.1',
    'pure-ts-eligibility',
    '0.1.0',
    repeat('c', 64),
    'eligibility-v0.1',
    v_snapshot_hash
  ) returning evaluation_id into v_evaluation_id;

  insert into public.eligibility_manifest_courses
  values (v_evaluation_id, v_profile_id, v_course_id);
  insert into public.eligibility_manifest_student_mappings
  values (v_evaluation_id, v_profile_id, v_student_mapping_id);
  insert into public.eligibility_manifest_completeness
  select v_evaluation_id, v_profile_id, completeness_id
  from public.student_data_completeness
  where profile_version_id = v_profile_id;
  insert into public.eligibility_manifest_student_evidence
  values (v_evaluation_id, v_profile_id, v_student_evidence_id);
  insert into public.eligibility_manifest_catalog_sources
  values (v_evaluation_id, v_observation_id);
  insert into public.eligibility_manifest_catalog_mappings
  values (v_evaluation_id, v_catalog_mapping_id);
  insert into public.eligibility_manifest_taxonomy_concepts
  values (v_evaluation_id, v_course_concept_id);

  insert into public.eligibility_requirement_results (
    evaluation_id,
    rule_node_id,
    truth_value,
    reason_codes,
    explanation,
    supporting_fact_refs
  ) values (
    v_evaluation_id,
    v_leaf_id,
    'SATISFIED',
    array['VERIFIED_COURSE_MATCH'],
    'Verified completed equivalency.',
    jsonb_build_array(v_course_id, v_student_mapping_id)
  ) returning requirement_result_id into v_leaf_result_id;
  insert into public.eligibility_requirement_results (
    evaluation_id,
    rule_node_id,
    truth_value,
    reason_codes,
    explanation
  ) values (
    v_evaluation_id,
    v_root_id,
    'SATISFIED',
    array['GROUP_SATISFIED'],
    'All hard ordinary requirements are satisfied.'
  );
  insert into public.eligibility_course_matches (
    requirement_result_id,
    evaluation_id,
    catalog_mapping_id,
    student_mapping_id,
    student_course_id,
    student_evidence_id
  ) values (
    v_leaf_result_id,
    v_evaluation_id,
    v_catalog_mapping_id,
    v_student_mapping_id,
    v_course_id,
    v_student_evidence_id
  );

  perform public.seal_eligibility_evaluation_inputs(v_evaluation_id);
  v_first_fingerprint := public.finalize_eligibility_evaluation(
    v_evaluation_id,
    'ELIGIBLE'
  );
  if v_first_fingerprint !~ '^[a-f0-9]{64}$' then
    raise exception 'Finalized manifest fingerprint is invalid';
  end if;

  v_blocked := false;
  begin
    update public.eligibility_evaluations
    set evaluator_version = 'mutated'
    where evaluation_id = v_evaluation_id;
  exception when others then
    if sqlerrm like '%append-only%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Completed evaluation was mutable';
  end if;

  insert into public.eligibility_evaluations (
    profile_version_id,
    rule_set_id,
    taxonomy_release_code,
    evaluator_name,
    evaluator_version,
    evaluator_build_hash,
    input_schema_version,
    profile_snapshot_hash
  ) values (
    v_profile_id,
    v_rule_set_id,
    'v0.1',
    'pure-ts-eligibility',
    '0.1.0',
    repeat('c', 64),
    'eligibility-v0.1',
    v_snapshot_hash
  ) returning evaluation_id into v_second_evaluation_id;
  insert into public.eligibility_manifest_courses
  values (v_second_evaluation_id, v_profile_id, v_second_course_id);
  insert into public.eligibility_manifest_student_mappings
  values (
    v_second_evaluation_id,
    v_profile_id,
    v_second_student_mapping_id
  );
  insert into public.eligibility_manifest_completeness
  select v_second_evaluation_id, v_profile_id, completeness_id
  from public.student_data_completeness
  where profile_version_id = v_profile_id;
  insert into public.eligibility_manifest_student_evidence
  values (v_second_evaluation_id, v_profile_id, v_student_evidence_id);
  insert into public.eligibility_manifest_catalog_sources
  values (v_second_evaluation_id, v_observation_id);
  insert into public.eligibility_manifest_catalog_mappings
  values (v_second_evaluation_id, v_catalog_mapping_id);
  insert into public.eligibility_manifest_taxonomy_concepts
  values (v_second_evaluation_id, v_course_concept_id);
  insert into public.eligibility_requirement_results (
    evaluation_id,
    rule_node_id,
    truth_value,
    reason_codes,
    explanation
  ) values
    (
      v_second_evaluation_id,
      v_leaf_id,
      'SATISFIED',
      array['VERIFIED_COURSE_MATCH'],
      'The alternative exact mapping satisfies the same concept.'
    )
  returning requirement_result_id into v_leaf_result_id;
  insert into public.eligibility_requirement_results (
    evaluation_id,
    rule_node_id,
    truth_value,
    reason_codes,
    explanation
  ) values (
    v_second_evaluation_id,
    v_root_id,
    'SATISFIED',
    array['GROUP_SATISFIED'],
    'All hard ordinary requirements are satisfied.'
  );
  insert into public.eligibility_course_matches (
    requirement_result_id,
    evaluation_id,
    catalog_mapping_id,
    student_mapping_id,
    student_course_id,
    student_evidence_id
  ) values (
    v_leaf_result_id,
    v_second_evaluation_id,
    v_catalog_mapping_id,
    v_second_student_mapping_id,
    v_second_course_id,
    v_student_evidence_id
  );
  perform public.seal_eligibility_evaluation_inputs(v_second_evaluation_id);
  v_second_fingerprint := public.finalize_eligibility_evaluation(
    v_second_evaluation_id,
    'ELIGIBLE'
  );
  if v_second_fingerprint = v_first_fingerprint then
    raise exception 'Changing an exact mapping ID did not change the fingerprint';
  end if;

  insert into public.eligibility_evaluations (
    profile_version_id,
    rule_set_id,
    taxonomy_release_code,
    evaluator_name,
    evaluator_version,
    evaluator_build_hash,
    input_schema_version,
    profile_snapshot_hash
  ) values (
    v_profile_id,
    v_rule_set_id,
    'v0.1',
    'pure-ts-eligibility',
    '0.1.0',
    repeat('c', 64),
    'eligibility-v0.1',
    v_snapshot_hash
  ) returning evaluation_id into v_third_evaluation_id;
  insert into public.eligibility_manifest_taxonomy_concepts
  values (v_third_evaluation_id, v_course_concept_id);
  insert into public.eligibility_manifest_catalog_mappings
  values (v_third_evaluation_id, v_catalog_mapping_id);
  insert into public.eligibility_manifest_catalog_sources
  values (v_third_evaluation_id, v_observation_id);
  insert into public.eligibility_manifest_student_evidence
  values (v_third_evaluation_id, v_profile_id, v_student_evidence_id);
  insert into public.eligibility_manifest_completeness
  select v_third_evaluation_id, v_profile_id, completeness_id
  from public.student_data_completeness
  where profile_version_id = v_profile_id
  order by completeness_id desc;
  insert into public.eligibility_manifest_student_mappings
  values (v_third_evaluation_id, v_profile_id, v_student_mapping_id);
  insert into public.eligibility_manifest_courses
  values (v_third_evaluation_id, v_profile_id, v_course_id);
  insert into public.eligibility_requirement_results (
    evaluation_id,
    rule_node_id,
    truth_value,
    reason_codes,
    explanation
  ) values (
    v_third_evaluation_id,
    v_leaf_id,
    'SATISFIED',
    array['VERIFIED_COURSE_MATCH'],
    'Verified completed equivalency.'
  ) returning requirement_result_id into v_third_leaf_result_id;
  insert into public.eligibility_requirement_results (
    evaluation_id,
    rule_node_id,
    truth_value,
    reason_codes,
    explanation
  ) values (
    v_third_evaluation_id,
    v_root_id,
    'SATISFIED',
    array['GROUP_SATISFIED'],
    'All hard ordinary requirements are satisfied.'
  );
  insert into public.eligibility_course_matches (
    requirement_result_id,
    evaluation_id,
    catalog_mapping_id,
    student_mapping_id,
    student_course_id,
    student_evidence_id
  ) values (
    v_third_leaf_result_id,
    v_third_evaluation_id,
    v_catalog_mapping_id,
    v_student_mapping_id,
    v_course_id,
    v_student_evidence_id
  );
  perform public.seal_eligibility_evaluation_inputs(v_third_evaluation_id);
  v_third_fingerprint := public.finalize_eligibility_evaluation(
    v_third_evaluation_id,
    'ELIGIBLE'
  );
  if v_third_fingerprint <> v_first_fingerprint then
    raise exception 'Manifest insertion order changed the canonical fingerprint';
  end if;

  perform public.retire_catalog_concept_mapping(
    v_catalog_mapping_id,
    'Superseded equivalency interpretation'
  );
  select count(*) into v_actual
  from public.eligibility_evaluations
  where profile_version_id = v_profile_id
    and evaluation_state = 'COMPLETED';
  if v_actual <> 3 then
    raise exception 'Mapping retirement damaged historical evaluations';
  end if;
  select count(*) into v_actual
  from public.program_requirement_rule_sets
  where rule_set_id = v_rule_set_id
    and status = 'VERIFIED';
  if v_actual <> 1 then
    raise exception 'Mapping retirement silently mutated the verified rule tree';
  end if;
  insert into public.program_requirement_rule_sets (
    program_version_id,
    rule_set_version,
    taxonomy_release_code
  ) values (
    v_program_version_id,
    4,
    'v0.1'
  ) returning rule_set_id into v_invalid_rule_set_id;
  insert into public.program_requirement_nodes (
    rule_set_id,
    node_kind,
    group_operator,
    explanation_template
  ) values (
    v_invalid_rule_set_id,
    'GROUP',
    'ALL',
    'Retired mapping attack root'
  ) returning rule_node_id into v_root_id;
  insert into public.program_requirement_nodes (
    rule_set_id,
    parent_node_id,
    node_kind,
    predicate_kind,
    requirement_strength,
    requirement_semantics,
    target_concept_id,
    explanation_template
  ) values (
    v_invalid_rule_set_id,
    v_root_id,
    'PREDICATE',
    'HAS_COURSE_CONCEPT',
    'HARD',
    'ORDINARY',
    v_course_concept_id,
    'A retired mapping is not review authority'
  ) returning rule_node_id into v_leaf_id;
  insert into public.program_requirement_node_sources
  values (v_leaf_id, v_observation_id);
  insert into public.program_requirement_node_mappings
  values (v_leaf_id, v_catalog_mapping_id);
  v_blocked := false;
  begin
    perform public.verify_program_requirement_rule_set(
      v_invalid_rule_set_id,
      'phase2-test-reviewer',
      v_evidence_id
    );
  exception when others then
    if sqlerrm like '%reviewed catalog mapping%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'A retired mapping was used to verify a new rule set';
  end if;

  v_blocked := false;
  begin
    insert into public.eligibility_evaluations (
      profile_version_id,
      rule_set_id,
      taxonomy_release_code,
      evaluator_name,
      evaluator_version,
      evaluator_build_hash,
      input_schema_version,
      profile_snapshot_hash
    ) values (
      v_profile_id,
      v_rule_set_id,
      'v0.1',
      'pure-ts-eligibility',
      '0.1.0',
      repeat('c', 64),
      'eligibility-v0.1',
      v_snapshot_hash
    );
  exception when others then
    if sqlerrm like '%stale sources or mappings%' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'A retired mapping was reused for a new evaluation';
  end if;

  select count(*) into v_actual
  from pg_class
  where relnamespace = 'public'::regnamespace
    and relname in (
      'students',
      'student_evidence_items',
      'student_record_concept_mappings',
      'eligibility_evaluations'
    )
    and relrowsecurity;
  if v_actual <> 4 then
    raise exception 'Student or eligibility tables are missing RLS';
  end if;

  execute 'grant select on public.students, public.eligibility_evaluations to authenticated';
  perform set_config(
    'request.jwt.claim.sub',
    extensions.gen_random_uuid()::text,
    true
  );
  execute 'set local role authenticated';
  select count(*) into v_actual from public.students;
  if v_actual <> 0 then
    raise exception 'RLS exposed a student to an unrelated authenticated user';
  end if;
  select count(*) into v_actual from public.eligibility_evaluations;
  if v_actual <> 0 then
    raise exception 'RLS exposed an evaluation to an unrelated authenticated user';
  end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub', v_auth_user_id::text, true);
  execute 'set local role authenticated';
  select count(*) into v_actual
  from public.students
  where student_id = v_student_id;
  if v_actual <> 1 then
    raise exception 'RLS denied the owning user access to the anonymous student';
  end if;
  select count(*) into v_actual
  from public.eligibility_evaluations
  where profile_version_id = v_profile_id;
  if v_actual <> 3 then
    raise exception 'RLS denied the owner access to historical evaluations';
  end if;
  execute 'reset role';

  perform public.delete_student_data(
    v_student_id,
    'Phase 2 privacy lifecycle test'
  );
  select count(*) into v_actual
  from public.eligibility_evaluations
  where profile_version_id = v_profile_id;
  if v_actual <> 0 then
    raise exception 'Privacy deletion retained replayable evaluations';
  end if;
  select count(*) into v_actual
  from public.student_deletion_tombstones
  where reason_code = 'TEST_LIFECYCLE'
    and request_class = 'TEST'
    and legacy_deletion_reason = 'MIGRATED_TO_REASON_CODE';
  if v_actual <> 1 then
    raise exception 'Minimal non-PII deletion tombstone was not created';
  end if;
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'student_deletion_tombstones'
      and column_name in (
        'student_id',
        'auth_user_id',
        'content_hash',
        'document_hash'
      )
  ) then
    raise exception 'Deletion tombstone retains linkable student data';
  end if;
end;
$test$;

rollback;
