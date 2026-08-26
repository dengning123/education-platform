-- Run after Migration 026 Eligibility production assembly capability.

begin;

do $test$
declare
  v_owner_auth constant uuid := 'a2600000-0000-4000-8000-000000000001';
  v_other_auth constant uuid := 'a2600000-0000-4000-8000-000000000002';
  v_profile_id uuid;
  v_other_profile_id uuid;
  v_program_version_id uuid;
  v_course_id uuid;
  v_prior_observation_id uuid;
  v_catalog_evidence_id uuid;
  v_scope_id uuid;
  v_assertion_id uuid;
  v_observation_id uuid;
  v_operation_id uuid := 'a2600000-0000-4000-8000-000000000101';
  v_rule_set_id uuid := 'a2600000-0000-4000-8000-000000000201';
  v_rule_node_id uuid := 'a2600000-0000-4000-8000-000000000202';
  v_duplicate_rule_set_id constant uuid :=
    'a2600000-0000-4000-8000-000000000203';
  v_revision bigint := 0;
  v_result jsonb;
  v_replay jsonb;
  v_blocked boolean;
  v_failure_operation_id uuid;
  v_evaluation_count bigint;
  v_domain public.student_data_domain;
  v_student_id uuid;
  v_other_student_id uuid;
  v_rule_set_snapshot public.program_requirement_rule_sets%rowtype;
  v_taxonomy_snapshot public.taxonomy_releases%rowtype;
begin
  if to_regprocedure(
    'public.assemble_eligibility_evaluation_v026(uuid,uuid,uuid)'
  ) is null then
    raise exception '026 assembly capability is missing';
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
  ) then
    raise exception '026 external function ACL is not closed';
  end if;
  if has_table_privilege(
    'authenticated', 'private.eligibility_assembly_operations_v026',
    'SELECT,INSERT,UPDATE,DELETE'
  ) or has_table_privilege(
    'service_role', 'private.eligibility_assembly_operations_v026',
    'SELECT,INSERT,UPDATE,DELETE'
  ) or has_table_privilege(
    'service_role', 'public.program_requirement_rule_sets', 'SELECT'
  ) or has_table_privilege(
    'service_role', 'public.student_profile_versions', 'SELECT'
  ) then
    raise exception '026 table authority escaped its executor boundary';
  end if;

  insert into auth.users (id, email) values
    (v_owner_auth, 'phase026-owner@test.invalid'),
    (v_other_auth, 'phase026-other@test.invalid');

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();
  v_result := public.create_or_resume_profile_draft_v019(
    extensions.gen_random_uuid()
  );
  v_profile_id := (v_result ->> 'profileVersionId')::uuid;
  perform public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision,
    'EVIDENCE_CREATE', jsonb_build_object('evidenceType', 'SELF_REPORT')
  );
  v_revision := v_revision + 1;
  foreach v_domain in array enum_range(null::public.student_data_domain)
  loop
    perform public.mutate_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), v_revision,
      'COMPLETENESS_UPSERT', jsonb_build_object(
        'educationContextId', null,
        'domain', v_domain,
        'completeness', 'COMPLETE',
        'explanation', null
      )
    );
    v_revision := v_revision + 1;
  end loop;
  perform public.freeze_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision
  );
  execute 'reset role';

  select version.program_version_id, course.course_id,
    selection.observation_id, observation.evidence_id
  into strict v_program_version_id, v_course_id,
    v_prior_observation_id, v_catalog_evidence_id
  from public.program_versions version
  join public.program_courses course
    on course.program_version_id = version.program_version_id
   and course.retired_at is null
  join public.canonical_field_selections selection
    on selection.record_type = 'PROGRAM_COURSE'
   and selection.record_id = course.course_id
   and selection.field_name = 'course_name'
  join public.field_observations observation
    on observation.observation_id = selection.observation_id
  where version.program_id = '00000000-0000-0000-0000-000000000301'
  order by course.created_at
  limit 1;

  execute 'set local role foundation_catalog_executor';
  v_scope_id := public.create_evidence_scope(
    v_catalog_evidence_id, 'PROGRAM_COURSE', v_course_id, 'course_name',
    'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
  );
  v_assertion_id := public.review_evidence_applicability(
    v_scope_id, 'REVIEWED_APPLICABLE', 'phase026-test-reviewer',
    'Migration 026 local behavior fixture'
  );
  v_observation_id := public.create_field_observation(
    'PROGRAM_COURSE', v_course_id, 'course_name',
    (select observed_value from public.field_observations
     where observation_id = v_prior_observation_id),
    'KNOWN', v_catalog_evidence_id, v_prior_observation_id,
    'Migration 026 local-only headed source fixture.', v_assertion_id
  );
  perform public.select_field_observation(
    v_observation_id, 'phase026-test-reviewer'
  );
  perform public.create_requirement_rule_set(jsonb_populate_record(
    null::public.program_requirement_rule_sets,
    jsonb_build_object(
      'rule_set_id', v_rule_set_id,
      'program_version_id', v_program_version_id,
      'rule_set_version', 2601,
      'taxonomy_release_code', 'v0.1',
      'rule_schema_version', 'phase2-v0.2',
      'engine_contract_version', 'eligibility-v0.2'
    )
  ));
  perform public.insert_requirement_node(jsonb_populate_record(
    null::public.program_requirement_nodes,
    jsonb_build_object(
      'rule_node_id', v_rule_node_id,
      'rule_set_id', v_rule_set_id,
      'sort_order', 0,
      'node_kind', 'PREDICATE',
      'predicate_kind', 'HAS_TEST',
      'requirement_strength', 'HARD',
      'requirement_semantics', 'ORDINARY',
      'target_concept_id',
        '10000000-0000-0000-0000-000000000071'::uuid,
      'explanation_template', 'The program requires the verified assessment.'
    )
  ));
  perform public.insert_requirement_node_source(jsonb_populate_record(
    null::public.program_requirement_node_sources,
    jsonb_build_object(
      'rule_node_id', v_rule_node_id,
      'field_observation_id', v_observation_id
    )
  ));
  perform public.verify_program_requirement_rule_set(
    v_rule_set_id, 'phase026-test-reviewer', v_catalog_evidence_id
  );
  execute 'reset role';

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_result := public.assemble_eligibility_evaluation_v026(
    v_profile_id, v_program_version_id, v_operation_id
  );
  if (select array_agg(key order by key) from jsonb_object_keys(v_result) key)
       is distinct from array[
         'evalId', 'inputFingerprint', 'profileId', 'programId',
         'requirements', 'resultFingerprint', 'rootTruth', 'schemaVersion',
         'status'
       ]::text[]
     or v_result ->> 'schemaVersion' <>
       'ELIGIBILITY_PRODUCTION_ASSEMBLY_V026'
     or (v_result ->> 'profileId')::uuid <> v_profile_id
     or (v_result ->> 'programId')::uuid <> v_program_version_id
     or v_result ->> 'status' <> 'NOT_ELIGIBLE'
     or v_result ->> 'rootTruth' <> 'NOT_SATISFIED'
     or (v_result ->> 'inputFingerprint') !~ '^[a-f0-9]{64}$'
     or (v_result ->> 'resultFingerprint') !~ '^[a-f0-9]{64}$'
     or jsonb_array_length(v_result -> 'requirements') <> 1 then
    raise exception '026 closed Eligibility result is invalid';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_result -> 'requirements') item
    where (select array_agg(key order by key) from jsonb_object_keys(item) key)
      is distinct from array[
        'explanation', 'id', 'missingDataCodes', 'reasonCodes',
        'supportingReferenceCount', 'truth'
      ]::text[]
  ) then
    raise exception '026 requirement projection is not closed';
  end if;

  v_replay := public.assemble_eligibility_evaluation_v026(
    v_profile_id, v_program_version_id, v_operation_id
  );
  if v_replay is distinct from v_result then
    raise exception '026 exact operation replay was not idempotent';
  end if;
  execute 'reset role';
  if (select count(*) from private.eligibility_assembly_operations_v026
      where operation_id = v_operation_id) <> 1
     or (select count(*) from public.eligibility_evaluations
         where evaluation_id = (v_result ->> 'evalId')::uuid) <> 1 then
    raise exception '026 exact replay created duplicate durable state';
  end if;

  if not exists (
       select 1 from public.eligibility_evaluations evaluation
       where evaluation.evaluation_id = (v_result ->> 'evalId')::uuid
         and evaluation.evaluation_state = 'COMPLETED'
         and evaluation.inputs_sealed_at is not null
         and evaluation.input_fingerprint = v_result ->> 'inputFingerprint'
         and evaluation.result_fingerprint = v_result ->> 'resultFingerprint'
     )
     or (select count(*) from public.eligibility_rule_set_pins
         where evaluation_id = (v_result ->> 'evalId')::uuid) <> 1
     or (select count(*) from public.eligibility_rule_node_pins
         where evaluation_id = (v_result ->> 'evalId')::uuid) <> 1
     or (select count(*) from public.eligibility_rule_node_source_pins
         where evaluation_id = (v_result ->> 'evalId')::uuid) <> 1
     or (select count(*) from public.eligibility_catalog_observation_pins
         where evaluation_id = (v_result ->> 'evalId')::uuid) <> 1
     or (select count(*) from public.eligibility_catalog_selection_pins
         where evaluation_id = (v_result ->> 'evalId')::uuid
           and observation_id = v_observation_id) <> 1
     or (select count(*) from public.eligibility_taxonomy_concept_pins
         where evaluation_id = (v_result ->> 'evalId')::uuid
           and concept_id = '10000000-0000-0000-0000-000000000071'::uuid) <> 1
     or (select count(*) from public.eligibility_completeness_pins
         where evaluation_id = (v_result ->> 'evalId')::uuid) <>
        (select count(*) from public.student_data_completeness
         where profile_version_id = v_profile_id)
     or (select count(*) from public.eligibility_manifest_completeness
         where evaluation_id = (v_result ->> 'evalId')::uuid) <>
        (select count(*) from public.student_data_completeness
         where profile_version_id = v_profile_id)
     or (select count(*) from public.eligibility_snapshot_scopes
         where evaluation_id = (v_result ->> 'evalId')::uuid) <>
        (select count(*) from public.student_data_completeness
         where profile_version_id = v_profile_id)
     or (select count(*) from public.eligibility_manifest_student_evidence
         where evaluation_id = (v_result ->> 'evalId')::uuid) <> 1
     or (select count(*) from public.eligibility_rule_node_mapping_pins
         where evaluation_id = (v_result ->> 'evalId')::uuid) <> 0
     or (select count(*) from public.eligibility_catalog_mapping_pins
         where evaluation_id = (v_result ->> 'evalId')::uuid) <> 0
     or (select count(*) from public.eligibility_student_mapping_pins
         where evaluation_id = (v_result ->> 'evalId')::uuid) <> 0 then
    raise exception '026 did not assemble the exact frozen Eligibility pin universe';
  end if;
  if not exists (
    select 1
    from public.eligibility_rule_node_source_pins pin
    join public.field_observation_applicability binding
      on binding.observation_id = pin.field_observation_id
    join public.evidence_applicability_heads head
      on head.scope_id = pin.applicability_scope_id
    where pin.evaluation_id = (v_result ->> 'evalId')::uuid
      and pin.applicability_assertion_id = binding.assertion_id
      and pin.applicability_head_assertion_id_at_pin = head.assertion_id
      and pin.applicability_assertion_id = head.assertion_id
  ) then
    raise exception '026 source/applicability authority was not pinned exactly';
  end if;

  select * into strict v_rule_set_snapshot
  from public.program_requirement_rule_sets
  where rule_set_id = v_rule_set_id;
  select * into strict v_taxonomy_snapshot
  from public.taxonomy_releases
  where release_code = v_rule_set_snapshot.taxonomy_release_code;

  -- RETIRED means there is no eligible v0.2 rule set. The failed statement must
  -- not retain either the operation identity or a BUILDING evaluation.
  execute 'set local session_replication_role = replica';
  update public.program_requirement_rule_sets
  set status = 'RETIRED', retired_at = clock_timestamp(),
      retirement_reason = 'phase026 no-rule probe'
  where rule_set_id = v_rule_set_id;
  execute 'set local session_replication_role = origin';
  v_failure_operation_id := 'a2600000-0000-4000-8000-000000000301';
  select count(*) into v_evaluation_count
  from public.eligibility_evaluations where profile_version_id = v_profile_id;
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_profile_id, v_program_version_id, v_failure_operation_id
    );
  exception when others then
    v_blocked := sqlerrm = 'ELIGIBILITY_RULESET_NOT_FOUND';
  end;
  execute 'reset role';
  if not v_blocked
     or exists (select 1 from private.eligibility_assembly_operations_v026
                where operation_id = v_failure_operation_id)
     or (select count(*) from public.eligibility_evaluations
         where profile_version_id = v_profile_id) <> v_evaluation_count then
    raise exception '026 no-rule resolution did not fail atomically';
  end if;

  -- A DRAFT rule set and a VERIFIED rule set for the wrong engine contract are
  -- both ineligible and must converge on the same non-enumerating result.
  execute 'set local session_replication_role = replica';
  update public.program_requirement_rule_sets
  set status = 'DRAFT', verification_evidence_id = null,
      verified_by = null, verified_at = null,
      retired_at = null, retirement_reason = null
  where rule_set_id = v_rule_set_id;
  execute 'set local session_replication_role = origin';
  v_failure_operation_id := 'a2600000-0000-4000-8000-000000000302';
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_profile_id, v_program_version_id, v_failure_operation_id
    );
  exception when others then
    v_blocked := sqlerrm = 'ELIGIBILITY_RULESET_NOT_FOUND';
  end;
  execute 'reset role';
  if not v_blocked
     or exists (select 1 from private.eligibility_assembly_operations_v026
                where operation_id = v_failure_operation_id) then
    raise exception '026 accepted or persisted an unverified rule set';
  end if;

  execute 'set local session_replication_role = replica';
  update public.program_requirement_rule_sets
  set status = 'VERIFIED',
      verification_evidence_id = v_rule_set_snapshot.verification_evidence_id,
      verified_by = v_rule_set_snapshot.verified_by,
      verified_at = v_rule_set_snapshot.verified_at,
      rule_schema_version = 'phase2-v0.1',
      engine_contract_version = 'eligibility-v0.1'
  where rule_set_id = v_rule_set_id;
  execute 'set local session_replication_role = origin';
  v_failure_operation_id := 'a2600000-0000-4000-8000-000000000303';
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_profile_id, v_program_version_id, v_failure_operation_id
    );
  exception when others then
    v_blocked := sqlerrm = 'ELIGIBILITY_RULESET_NOT_FOUND';
  end;
  execute 'reset role';
  if not v_blocked
     or exists (select 1 from private.eligibility_assembly_operations_v026
                where operation_id = v_failure_operation_id) then
    raise exception '026 accepted or persisted the wrong rule contract';
  end if;

  execute 'set local session_replication_role = replica';
  update public.program_requirement_rule_sets
  set rule_schema_version = v_rule_set_snapshot.rule_schema_version,
      engine_contract_version = v_rule_set_snapshot.engine_contract_version
  where rule_set_id = v_rule_set_id;
  drop index public.program_requirement_one_verified_idx;
  insert into public.program_requirement_rule_sets (
    rule_set_id, program_version_id, rule_set_version,
    taxonomy_release_code, rule_schema_version, engine_contract_version,
    status, verification_evidence_id, verified_by, verified_at,
    retired_at, retirement_reason
  ) select
    v_duplicate_rule_set_id, program_version_id, rule_set_version + 1,
    taxonomy_release_code, rule_schema_version, engine_contract_version,
    status, verification_evidence_id, verified_by, verified_at,
    retired_at, retirement_reason
  from public.program_requirement_rule_sets where rule_set_id = v_rule_set_id;
  execute 'set local session_replication_role = origin';
  v_failure_operation_id := 'a2600000-0000-4000-8000-000000000304';
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_profile_id, v_program_version_id, v_failure_operation_id
    );
  exception when others then
    v_blocked := sqlerrm = 'ELIGIBILITY_RULESET_AMBIGUOUS';
  end;
  execute 'reset role';
  if not v_blocked
     or exists (select 1 from private.eligibility_assembly_operations_v026
                where operation_id = v_failure_operation_id) then
    raise exception '026 ambiguous rule resolution did not fail atomically';
  end if;
  execute 'set local session_replication_role = replica';
  delete from public.program_requirement_rule_sets
  where rule_set_id = v_duplicate_rule_set_id;
  create unique index program_requirement_one_verified_idx
    on public.program_requirement_rule_sets (program_version_id)
    where status = 'VERIFIED';
  execute 'set local session_replication_role = origin';

  -- Canonical selection drift is rejected by the frozen M013 pin/seal law and
  -- rolls the entire assembly statement back.
  execute 'set local session_replication_role = replica';
  update public.canonical_field_selections
  set observation_id = v_prior_observation_id
  where record_type = 'PROGRAM_COURSE'
    and record_id = v_course_id
    and field_name = 'course_name';
  execute 'set local session_replication_role = origin';
  v_failure_operation_id := 'a2600000-0000-4000-8000-000000000305';
  select count(*) into v_evaluation_count
  from public.eligibility_evaluations where profile_version_id = v_profile_id;
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_profile_id, v_program_version_id, v_failure_operation_id
    );
  exception when others then
    v_blocked := sqlerrm = 'ELIGIBILITY_INPUT_INVALID';
  end;
  execute 'reset role';
  if not v_blocked
     or exists (select 1 from private.eligibility_assembly_operations_v026
                where operation_id = v_failure_operation_id)
     or (select count(*) from public.eligibility_evaluations
         where profile_version_id = v_profile_id) <> v_evaluation_count then
    raise exception '026 canonical-head drift left partial evaluation state';
  end if;
  execute 'set local session_replication_role = replica';
  update public.canonical_field_selections
  set observation_id = v_observation_id
  where record_type = 'PROGRAM_COURSE'
    and record_id = v_course_id
    and field_name = 'course_name';
  execute 'set local session_replication_role = origin';

  -- A taxonomy release that is no longer VERIFIED is not assembly authority.
  execute 'set local session_replication_role = replica';
  update public.taxonomy_releases
  set status = 'DRAFT', verified_by = null, verified_at = null
  where release_code = v_rule_set_snapshot.taxonomy_release_code;
  execute 'set local session_replication_role = origin';
  v_failure_operation_id := 'a2600000-0000-4000-8000-000000000306';
  select count(*) into v_evaluation_count
  from public.eligibility_evaluations where profile_version_id = v_profile_id;
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_profile_id, v_program_version_id, v_failure_operation_id
    );
  exception when others then
    v_blocked := sqlerrm = 'ELIGIBILITY_INPUT_INVALID';
  end;
  execute 'reset role';
  if not v_blocked
     or exists (select 1 from private.eligibility_assembly_operations_v026
                where operation_id = v_failure_operation_id)
     or (select count(*) from public.eligibility_evaluations
         where profile_version_id = v_profile_id) <> v_evaluation_count then
    raise exception '026 taxonomy-status drift left partial evaluation state';
  end if;
  execute 'set local session_replication_role = replica';
  update public.taxonomy_releases
  set status = v_taxonomy_snapshot.status,
      verified_by = v_taxonomy_snapshot.verified_by,
      verified_at = v_taxonomy_snapshot.verified_at
  where release_code = v_rule_set_snapshot.taxonomy_release_code;
  execute 'set local session_replication_role = origin';

  -- Advancing the applicability head invalidates the observation binding. M013
  -- must reject it and the M026 statement must retain no partial state.
  execute 'set local role foundation_catalog_executor';
  perform public.review_evidence_applicability(
    v_scope_id, 'REVIEWED_INAPPLICABLE', 'phase026-applicability-drift',
    'Migration 026 headed applicability rollback probe'
  );
  execute 'reset role';
  v_failure_operation_id := 'a2600000-0000-4000-8000-000000000307';
  select count(*) into v_evaluation_count
  from public.eligibility_evaluations where profile_version_id = v_profile_id;
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_profile_id, v_program_version_id, v_failure_operation_id
    );
  exception when others then
    v_blocked := sqlerrm = 'ELIGIBILITY_INPUT_INVALID';
  end;
  execute 'reset role';
  if not v_blocked
     or exists (select 1 from private.eligibility_assembly_operations_v026
                where operation_id = v_failure_operation_id)
     or (select count(*) from public.eligibility_evaluations
         where profile_version_id = v_profile_id) <> v_evaluation_count then
    raise exception '026 applicability-head drift left partial evaluation state';
  end if;

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';

  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_profile_id, extensions.gen_random_uuid(), v_operation_id
    );
  exception when others then
    v_blocked := sqlerrm = 'ELIGIBILITY_ASSEMBLY_CONFLICT';
  end;
  if not v_blocked then
    raise exception '026 conflicting operation replay did not fail closed';
  end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub', v_other_auth::text, true);
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();
  v_other_profile_id := (
    public.create_or_resume_profile_draft_v019(extensions.gen_random_uuid())
    ->> 'profileVersionId'
  )::uuid;
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_profile_id, v_program_version_id, extensions.gen_random_uuid()
    );
  exception when others then
    v_blocked := sqlerrm = 'PROFILE_NOT_FOUND';
  end;
  if not v_blocked then
    raise exception '026 unrelated user enumerated the owner Profile';
  end if;
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_other_profile_id, v_program_version_id, extensions.gen_random_uuid()
    );
  exception when others then
    v_blocked := sqlerrm = 'PROFILE_NOT_FROZEN';
  end;
  if not v_blocked then
    raise exception '026 accepted a DRAFT Profile';
  end if;
  execute 'reset role';

  select student_id into strict v_student_id
  from private.student_identities where auth_user_id = v_owner_auth;
  select student_id into strict v_other_student_id
  from private.student_identities where auth_user_id = v_other_auth;

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v026(
      v_profile_id, extensions.gen_random_uuid(), extensions.gen_random_uuid()
    );
  exception when others then
    v_blocked := sqlerrm = 'PROGRAM_NOT_FOUND';
  end;
  if not v_blocked then
    raise exception '026 missing Program did not fail closed';
  end if;
  execute 'reset role';
  perform public.delete_student_data(v_student_id, 'PHASE026_PRIVACY_TEST');

  if exists (
    select 1 from private.eligibility_assembly_operations_v026
    where operation_id = v_operation_id
  ) or exists (
    select 1 from public.eligibility_evaluations
    where evaluation_id = (v_result ->> 'evalId')::uuid
  ) then
    raise exception '026 privacy deletion retained assembly state';
  end if;

  perform set_config('request.jwt.claim.sub', v_other_auth::text, true);
  perform public.delete_student_data(v_other_student_id, 'PHASE026_PRIVACY_TEST');
  delete from auth.users where id in (v_owner_auth, v_other_auth);

  if pg_get_functiondef(
       'public.assemble_eligibility_evaluation_v026(uuid,uuid,uuid)'::regprocedure
     ) !~ 'start_eligibility_evaluation_v02'
     or pg_get_functiondef(
       'public.assemble_eligibility_evaluation_v026(uuid,uuid,uuid)'::regprocedure
     ) !~ 'seal_eligibility_evaluation_inputs_v02'
     or pg_get_functiondef(
       'public.assemble_eligibility_evaluation_v026(uuid,uuid,uuid)'::regprocedure
     ) !~ 'finalize_eligibility_evaluation_v02' then
    raise exception '026 does not compose the frozen M013 primitives';
  end if;

  raise notice '018 phase 026 production assembly behavior/security/privacy passed';
end;
$test$;

rollback;
