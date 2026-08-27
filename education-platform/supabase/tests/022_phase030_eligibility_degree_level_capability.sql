-- Run after Migration 030 Eligibility Degree-Level Capability.

begin;

do $test$
declare
  v_program_version_id uuid;
  v_evidence_id uuid;
  v_scope_id uuid;
  v_assertion_id uuid;
  v_observation_id uuid;
  v_degree_requirement_id uuid;
  v_rule_set_id constant uuid := 'a3000000-0000-4000-8000-000000000201';
  v_rule_node_id constant uuid := 'a3000000-0000-4000-8000-000000000202';
  v_auth_ids uuid[] := array[
    'a3000000-0000-4000-8000-000000000001'::uuid,
    'a3000000-0000-4000-8000-000000000002'::uuid,
    'a3000000-0000-4000-8000-000000000003'::uuid,
    'a3000000-0000-4000-8000-000000000004'::uuid,
    'a3000000-0000-4000-8000-000000000005'::uuid,
    'a3000000-0000-4000-8000-000000000006'::uuid,
    'a3000000-0000-4000-8000-000000000099'::uuid
  ];
  v_profiles uuid[] := array[]::uuid[];
  v_profile_id uuid;
  v_degree_id uuid;
  v_evidence_student_id uuid;
  v_revision bigint;
  v_result jsonb;
  v_replay jsonb;
  v_second jsonb;
  v_domain public.student_data_domain;
  v_case record;
  v_blocked boolean;
  v_before_hash text;
  v_after_hash text;
  v_matrix_hash text;
begin
  if to_regprocedure(
    'public.assemble_eligibility_evaluation_v030(uuid,uuid,uuid)'
  ) is null then
    raise exception '030 assembly capability is missing';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.assemble_eligibility_evaluation_v030(uuid,uuid,uuid)', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.assemble_eligibility_evaluation_v030(uuid,uuid,uuid)', 'EXECUTE'
  ) or has_function_privilege(
    'service_role', 'public.assemble_eligibility_evaluation_v030(uuid,uuid,uuid)', 'EXECUTE'
  ) then
    raise exception '030 external assembly ACL is not closed';
  end if;
  if has_table_privilege(
    'authenticated', 'public.program_degree_requirements_v030', 'SELECT'
  ) or has_table_privilege(
    'authenticated', 'public.eligibility_degree_matches_v030', 'SELECT'
  ) or has_table_privilege(
    'service_role', 'private.eligibility_degree_operations_v030', 'SELECT'
  ) or has_schema_privilege('foundation_evaluation_executor', 'auth', 'USAGE')
     or has_table_privilege('foundation_evaluation_executor', 'auth.users', 'SELECT') then
    raise exception '030 authority escaped its controlled boundary';
  end if;
  if exists (
    select 1 from pg_enum item
    join pg_type type on type.oid = item.enumtypid
    join pg_namespace namespace on namespace.oid = type.typnamespace
    where namespace.nspname = 'public'
      and type.typname = 'requirement_predicate_kind'
      and item.enumlabel = 'HAS_ASSESSMENT_TOTAL_AT_LEAST'
  ) then
    raise exception '030 introduced the prohibited assessment threshold leaf';
  end if;
  select contract.matrix_hash into strict v_matrix_hash
  from public.degree_level_qualification_contracts_v030 contract
  where contract.contract_code = 'DEGREE_LEVEL_QUALIFICATION_V1';
  if v_matrix_hash is distinct from encode(extensions.digest(convert_to(
    'DEGREE_LEVEL_QUALIFICATION_V1|BACHELORS>BACHELORS|BACHELORS>MASTERS|BACHELORS>DOCTORAL|MASTERS>MASTERS|MASTERS>DOCTORAL|DOCTORAL>DOCTORAL',
    'UTF8'
  ), 'sha256'), 'hex')
     or (select count(*) from public.degree_level_qualification_relations_v030) <> 6
     or exists (
       select 1 from public.degree_level_qualification_relations_v030 relation
       where relation.required_degree_level in ('CERTIFICATE', 'OTHER')
          or relation.student_degree_level in ('CERTIFICATE', 'OTHER')
     ) then
    raise exception '030 qualification matrix is not the exact V1 contract';
  end if;

  select version.program_version_id into strict v_program_version_id
  from public.program_versions version
  where version.program_id = '00000000-0000-0000-0000-000000000301'
  order by version.created_at
  limit 1;
  select evidence.evidence_id into strict v_evidence_id
  from public.evidence_items evidence
  join public.sources source on source.source_id = evidence.source_id
  where source.reliability_tier = 'TIER_A_OFFICIAL'
  order by evidence.created_at
  limit 1;

  execute 'set local role foundation_catalog_executor';
  v_scope_id := public.create_evidence_scope(
    v_evidence_id, 'PROGRAM_VERSION', v_program_version_id,
    'degree_requirement_level_v030',
    'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
  );
  v_assertion_id := public.review_evidence_applicability(
    v_scope_id, 'REVIEWED_APPLICABLE', 'phase030-reviewer',
    'M030 degree authority fixture'
  );
  v_observation_id := public.create_field_observation(
    'PROGRAM_VERSION', v_program_version_id,
    'degree_requirement_level_v030', to_jsonb('BACHELORS'::text),
    'KNOWN', v_evidence_id, null,
    'M030 typed BACHELORS requirement fixture', v_assertion_id
  );
  perform public.select_field_observation(v_observation_id, 'phase030-reviewer');
  v_degree_requirement_id := public.create_program_degree_requirement_v030(
    'PROGRAM:NYU_MSQE:DEGREE_LEVEL', 1, v_program_version_id,
    (select upper(admission_cycle) from public.program_versions
     where program_version_id = v_program_version_id),
    'BACHELORS', v_observation_id
  );
  perform public.verify_program_degree_requirement_v030(
    v_degree_requirement_id, 'phase030-reviewer'
  );
  perform public.create_requirement_rule_set(jsonb_populate_record(
    null::public.program_requirement_rule_sets,
    jsonb_build_object(
      'rule_set_id', v_rule_set_id,
      'program_version_id', v_program_version_id,
      'rule_set_version', 3001,
      'taxonomy_release_code', 'v0.1',
      'rule_schema_version', 'phase2-degree-v1',
      'engine_contract_version', 'eligibility-degree-v1'
    )
  ));
  perform public.insert_requirement_node(jsonb_populate_record(
    null::public.program_requirement_nodes,
    jsonb_build_object(
      'rule_node_id', v_rule_node_id,
      'rule_set_id', v_rule_set_id,
      'sort_order', 0,
      'node_kind', 'PREDICATE',
      'predicate_kind', 'HAS_DEGREE_LEVEL',
      'requirement_strength', 'HARD',
      'requirement_semantics', 'ORDINARY',
      'target_concept_id', null,
      'explanation_template', 'The program requires the stated completed degree level.'
    )
  ));
  perform public.insert_requirement_node_source(jsonb_populate_record(
    null::public.program_requirement_node_sources,
    jsonb_build_object(
      'rule_node_id', v_rule_node_id,
      'field_observation_id', v_observation_id
    )
  ));
  perform public.insert_program_degree_predicate_v030(
    v_rule_node_id, v_degree_requirement_id
  );
  perform public.verify_program_requirement_rule_set_degree_v030(
    v_rule_set_id, 'phase030-reviewer', v_evidence_id
  );
  execute 'reset role';

  insert into auth.users (id, email)
  select auth_id, 'phase030-' || ordinal::text || '@test.invalid'
  from unnest(v_auth_ids) with ordinality as input(auth_id, ordinal);

  for v_case in
    select * from (values
      (1, 'BACHELORS'::public.degree_level, 'COMPLETED'::public.degree_status),
      (2, 'MASTERS'::public.degree_level, 'COMPLETED'::public.degree_status),
      (3, 'CERTIFICATE'::public.degree_level, 'COMPLETED'::public.degree_status),
      (4, 'BACHELORS'::public.degree_level, 'IN_PROGRESS'::public.degree_status),
      (5, 'OTHER'::public.degree_level, 'COMPLETED'::public.degree_status),
      (6, null::public.degree_level, null::public.degree_status)
    ) as cases(case_id, degree_level, degree_status)
  loop
    perform set_config('request.jwt.claim.sub', v_auth_ids[v_case.case_id]::text, true);
    execute 'set local role authenticated';
    perform public.bootstrap_profile_identity_v019();
    v_result := public.create_or_resume_profile_draft_v019(
      extensions.gen_random_uuid()
    );
    v_profile_id := (v_result ->> 'profileVersionId')::uuid;
    v_revision := 0;
    v_degree_id := null;
    if v_case.degree_level is not null then
      v_result := public.mutate_profile_draft_v019(
        v_profile_id, extensions.gen_random_uuid(), v_revision,
        'EVIDENCE_CREATE', jsonb_build_object('evidenceType', 'SELF_REPORT')
      );
      v_evidence_student_id := (v_result ->> 'resourceId')::uuid;
      v_revision := v_revision + 1;
      v_result := public.mutate_profile_draft_v019(
        v_profile_id, extensions.gen_random_uuid(), v_revision,
        'DEGREE_CREATE', jsonb_build_object(
          'institutionName', 'M030 Test University',
          'degreeName', 'M030 Test Degree',
          'degreeLevel', v_case.degree_level,
          'degreeStatus', v_case.degree_status,
          'evidenceId', v_evidence_student_id
        )
      );
      v_degree_id := (v_result ->> 'resourceId')::uuid;
      v_revision := v_revision + 1;
    end if;
    foreach v_domain in array enum_range(null::public.student_data_domain)
    loop
      perform public.mutate_profile_draft_v019(
        v_profile_id, extensions.gen_random_uuid(), v_revision,
        'COMPLETENESS_UPSERT', jsonb_build_object(
          'educationContextId', case
            when v_domain in ('COURSE_HISTORY', 'COURSE_MAPPING')
              then v_degree_id
            else null
          end,
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
    v_profiles := array_append(v_profiles, v_profile_id);
  end loop;

  for v_case in
    select * from (values
      (1, 'ELIGIBLE', 'SATISFIED', 'DEGREE_LEVEL_MATCHED'),
      (2, 'ELIGIBLE', 'SATISFIED', 'DEGREE_LEVEL_MATCHED'),
      (3, 'NOT_ELIGIBLE', 'NOT_SATISFIED', 'DEGREE_LEVEL_NOT_FOUND'),
      (4, 'UNKNOWN', 'UNKNOWN', 'DEGREE_STATUS_UNRESOLVED'),
      (5, 'UNKNOWN', 'UNKNOWN', 'DEGREE_EQUIVALENCY_UNRESOLVED'),
      (6, 'NOT_ELIGIBLE', 'NOT_SATISFIED', 'DEGREE_LEVEL_NOT_FOUND')
    ) as cases(case_id, expected_status, expected_truth, expected_reason)
  loop
    select snapshot_hash into strict v_before_hash
    from public.student_profile_versions
    where profile_version_id = v_profiles[v_case.case_id];
    perform set_config('request.jwt.claim.sub', v_auth_ids[v_case.case_id]::text, true);
    execute 'set local role authenticated';
    v_result := public.assemble_eligibility_evaluation_v030(
      v_profiles[v_case.case_id], v_program_version_id,
      ('a3000000-0000-4000-8000-' || lpad((100 + v_case.case_id)::text, 12, '0'))::uuid
    );
    v_replay := public.assemble_eligibility_evaluation_v030(
      v_profiles[v_case.case_id], v_program_version_id,
      ('a3000000-0000-4000-8000-' || lpad((100 + v_case.case_id)::text, 12, '0'))::uuid
    );
    if v_replay is distinct from v_result
       or v_result ->> 'schemaVersion' <> 'ELIGIBILITY_PRODUCTION_ASSEMBLY_V026'
       or v_result ->> 'status' <> v_case.expected_status
       or v_result ->> 'rootTruth' <> v_case.expected_truth
       or (v_result #>> '{requirements,0,reasonCodes,0}') <> v_case.expected_reason
       or (v_result ->> 'inputFingerprint') !~ '^[a-f0-9]{64}$'
       or (v_result ->> 'resultFingerprint') !~ '^[a-f0-9]{64}$' then
      raise exception '030 case % result or replay mismatch: %', v_case.case_id, v_result;
    end if;
    execute 'reset role';
    select snapshot_hash into strict v_after_hash
    from public.student_profile_versions
    where profile_version_id = v_profiles[v_case.case_id];
    if v_after_hash is distinct from v_before_hash then
      raise exception '030 assembly changed the frozen source profile';
    end if;
    if v_case.expected_truth = 'SATISFIED'
       and (select count(*) from public.eligibility_degree_matches_v030
            where evaluation_id = (v_result ->> 'evalId')::uuid) <> 1 then
      raise exception '030 positive result lacks exact degree match';
    end if;
    if v_case.expected_truth = 'NOT_SATISFIED'
       and (select count(*) from public.eligibility_degree_negative_proofs_v030
            where evaluation_id = (v_result ->> 'evalId')::uuid
              and proof_version = 'eligibility-degree-v1-neg1') <> 1 then
      raise exception '030 negative result lacks exact completeness proof';
    end if;
    if v_case.expected_truth = 'UNKNOWN'
       and ((select count(*) from public.eligibility_degree_matches_v030
             where evaluation_id = (v_result ->> 'evalId')::uuid) <> 0
            or (select count(*) from public.eligibility_degree_negative_proofs_v030
                where evaluation_id = (v_result ->> 'evalId')::uuid) <> 0) then
      raise exception '030 UNKNOWN result created positive or negative proof';
    end if;
  end loop;

  -- A different operation over identical frozen inputs naturally creates a
  -- new row but preserves both semantic fingerprints.
  perform set_config('request.jwt.claim.sub', v_auth_ids[1]::text, true);
  execute 'set local role authenticated';
  v_result := public.assemble_eligibility_evaluation_v030(
    v_profiles[1], v_program_version_id,
    'a3000000-0000-4000-8000-000000000101'
  );
  v_second := public.assemble_eligibility_evaluation_v030(
    v_profiles[1], v_program_version_id,
    'a3000000-0000-4000-8000-000000000701'
  );
  if v_second ->> 'evalId' = v_result ->> 'evalId'
     or v_second ->> 'inputFingerprint' is distinct from v_result ->> 'inputFingerprint'
     or v_second ->> 'resultFingerprint' is distinct from v_result ->> 'resultFingerprint' then
    raise exception '030 deterministic fingerprint replay contract failed';
  end if;
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v030(
      v_profiles[2], v_program_version_id,
      'a3000000-0000-4000-8000-000000000101'
    );
  exception when others then
    v_blocked := sqlerrm = 'ELIGIBILITY_ASSEMBLY_CONFLICT';
  end;
  if not v_blocked then
    raise exception '030 conflicting operation replay did not fail closed';
  end if;
  execute 'reset role';

  -- Unrelated and anonymous callers cannot use an owner's profile.
  perform set_config('request.jwt.claim.sub', v_auth_ids[7]::text, true);
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v030(
      v_profiles[1], v_program_version_id,
      'a3000000-0000-4000-8000-000000000801'
    );
  exception when others then
    v_blocked := sqlerrm = 'PROFILE_NOT_FOUND';
  end;
  if not v_blocked then raise exception '030 unrelated user crossed ownership'; end if;
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.assemble_eligibility_evaluation_v030(
      v_profiles[1], v_program_version_id,
      'a3000000-0000-4000-8000-000000000802'
    );
  exception when others then
    v_blocked := sqlerrm = 'AUTH_REQUIRED';
  end;
  if not v_blocked then raise exception '030 anonymous subject was accepted'; end if;
  execute 'reset role';

  if not exists (
    select 1 from public.eligibility_evaluations evaluation
    where evaluation.input_schema_version = 'eligibility-degree-v1'
      and evaluation.result_semantics_version = 'eligibility-v0.2'
      and evaluation.canonicalization_version = 'eligibility-degree-v1-c14n1'
      and evaluation.contract_release_code = 'phase2-degree-v1'
  ) or exists (
    select 1 from public.eligibility_rule_node_pins pin
    where pin.evaluation_id in (
      select evaluation_id from public.eligibility_evaluations
      where input_schema_version = 'eligibility-degree-v1'
    ) and pin.predicate_kind is distinct from 'HAS_DEGREE_LEVEL'
  ) then
    raise exception '030 version gate or degree-only input surface drifted';
  end if;

  -- The existing transaction-bound privacy lifecycle cascades through every
  -- evaluation-owned M030 input, result, proof, and operation row.
  select profile.student_id into strict v_degree_id
  from public.student_profile_versions profile
  where profile.profile_version_id = v_profiles[6];
  execute 'set local role service_role';
  perform public.delete_student_data(v_degree_id, 'TEST_LIFECYCLE');
  execute 'reset role';
  if exists (
    select 1 from public.eligibility_evaluations evaluation
    where evaluation.profile_version_id = v_profiles[6]
  ) or exists (
    select 1 from private.eligibility_degree_operations_v030 operation
    where operation.profile_version_id = v_profiles[6]
  ) or exists (
    select 1 from public.eligibility_degree_requirement_pins_v030 pin
    join public.eligibility_evaluations evaluation using (evaluation_id)
    where evaluation.profile_version_id = v_profiles[6]
  ) then
    raise exception '030 privacy deletion left evaluation-linked residue';
  end if;
end;
$test$;

rollback;

select 'PHASE030_ELIGIBILITY_DEGREE_LEVEL_PASS' as result;
