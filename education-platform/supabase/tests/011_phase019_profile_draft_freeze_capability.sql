-- Runs after migrations 001-019. All fixtures roll back.

begin;

do $test$
declare
  v_owner_auth uuid := '91000000-0000-0000-0000-000000000001';
  v_other_auth uuid := '91000000-0000-0000-0000-000000000002';
  v_student_id uuid;
  v_profile_id uuid;
  v_other_profile_id uuid;
  v_revision bigint := 0;
  v_result jsonb;
  v_replay jsonb;
  v_document jsonb;
  v_readiness jsonb;
  v_operation_id uuid;
  v_evidence_id uuid;
  v_extra_evidence_id uuid;
  v_degree_id uuid;
  v_course_id uuid;
  v_test_id uuid;
  v_experience_id uuid;
  v_skill_id uuid;
  v_goal_id uuid;
  v_preference_id uuid;
  v_temp_id uuid;
  v_assessment_concept_id uuid;
  v_skill_concept_id uuid;
  v_second_skill_concept_id uuid;
  v_goal_concept_id uuid;
  v_blocked boolean;
  v_count integer;
  v_sqlstate text;
begin
  perform set_config('statement_timeout', '20s', true);

  -- Migration identity, additive columns, and exact browser surface.
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'student_profile_versions'
      and column_name = 'profile_revision'
  ) or not exists (
    select 1 from pg_class relation
    join pg_namespace namespace on namespace.oid = relation.relnamespace
    where namespace.nspname = 'private'
      and relation.relname = 'profile_capability_operations_v019'
      and relation.relrowsecurity
  ) then
    raise exception '019 capability DDL is incomplete';
  end if;
  if exists (
    select 1 from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname like '%\_v019' escape '\'
      and pg_get_function_identity_arguments(procedure.oid) ~ 'student_id'
  ) then
    raise exception 'Browser Profile RPC accepts caller-supplied student_id';
  end if;
  if has_table_privilege(
    'authenticated', 'public.student_profile_versions', 'INSERT,UPDATE,DELETE'
  ) or has_table_privilege(
    'authenticated', 'public.student_degrees', 'INSERT,UPDATE,DELETE'
  ) or has_table_privilege(
    'authenticated', 'private.profile_capability_operations_v019',
    'SELECT,INSERT,UPDATE,DELETE'
  ) then
    raise exception 'Authenticated retains direct Profile DML';
  end if;

  -- Anonymous has no capability EXECUTE.
  v_blocked := false;
  begin
    execute 'set local role anon';
    perform public.bootstrap_profile_identity_v019();
  exception when insufficient_privilege then
    v_blocked := true;
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception 'Anonymous bootstrap was not rejected';
  end if;

  insert into auth.users (id, email) values
    (v_owner_auth, 'phase019-owner@test.invalid'),
    (v_other_auth, 'phase019-other@test.invalid');

  -- First/repeated bootstrap and one private binding.
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_result := public.bootstrap_profile_identity_v019();
  if v_result ->> 'accountState' <> 'ACTIVE'
     or (v_result ->> 'hasCurrentDraft')::boolean then
    raise exception 'First bootstrap returned an invalid account DTO';
  end if;
  v_replay := public.bootstrap_profile_identity_v019();
  if v_replay is distinct from v_result then
    raise exception 'Repeated bootstrap changed logical account state';
  end if;
  v_operation_id := extensions.gen_random_uuid();
  v_result := public.create_or_resume_profile_draft_v019(v_operation_id);
  v_profile_id := (v_result ->> 'profileVersionId')::uuid;
  if (v_result ->> 'versionNumber')::integer <> 1
     or (v_result ->> 'revision')::bigint <> 0
     or v_result ->> 'status' <> 'DRAFT' then
    raise exception 'First draft allocation is invalid';
  end if;
  v_replay := public.create_or_resume_profile_draft_v019(v_operation_id);
  if v_replay is distinct from v_result then
    raise exception 'Create/resume exact replay changed result';
  end if;
  v_replay := public.create_or_resume_profile_draft_v019(extensions.gen_random_uuid());
  if (v_replay ->> 'profileVersionId')::uuid <> v_profile_id then
    raise exception 'Create/resume did not resume the current product draft';
  end if;
  execute 'reset role';

  select identity.student_id into v_student_id
  from private.student_identities identity
  where identity.auth_user_id = v_owner_auth;
  if v_student_id is null or (
    select count(*) from private.student_identities
    where auth_user_id = v_owner_auth
  ) <> 1 or (
    select count(*) from public.student_profile_versions
    where student_id = v_student_id and product_managed and status = 'DRAFT'
  ) <> 1 then
    raise exception 'Bootstrap/draft uniqueness failed';
  end if;

  -- Unrelated authenticated user gets a distinct binding and non-enumerating
  -- failures for the owner's profile.
  perform set_config('request.jwt.claim.sub', v_other_auth::text, true);
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();
  v_result := public.create_or_resume_profile_draft_v019(extensions.gen_random_uuid());
  v_other_profile_id := (v_result ->> 'profileVersionId')::uuid;
  if v_other_profile_id = v_profile_id then
    raise exception 'Two Auth users acquired one Profile identity';
  end if;
  v_blocked := false;
  begin
    perform public.get_profile_document_v019(v_profile_id);
  exception when no_data_found then
    v_blocked := sqlerrm = 'PROFILE_NOT_FOUND';
  end;
  if not v_blocked then
    raise exception 'Unrelated user enumerated the owner Profile';
  end if;
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), 0,
      'GOAL_CREATE',
      jsonb_build_object('goalType', 'CAREER', 'goalText', 'blocked', 'priority', 1)
    );
  exception when no_data_found then
    v_blocked := sqlerrm = 'PROFILE_NOT_FOUND';
  end;
  if not v_blocked then
    raise exception 'Unrelated user mutated the owner Profile';
  end if;
  execute 'reset role';

  select concept_id into v_assessment_concept_id
  from public.taxonomy_concepts
  where concept_kind = 'ASSESSMENT' and retired_in_release is null
  order by concept_id limit 1;
  select concept_id into v_skill_concept_id
  from public.taxonomy_concepts
  where concept_kind = 'SKILL' and retired_in_release is null
  order by concept_id limit 1;
  select concept_id into v_second_skill_concept_id
  from public.taxonomy_concepts
  where concept_kind = 'SKILL' and retired_in_release is null
    and concept_id <> v_skill_concept_id
  order by concept_id limit 1;
  select concept_id into v_goal_concept_id
  from public.taxonomy_concepts
  where concept_kind = 'CAREER' and retired_in_release is null
  order by concept_id limit 1;

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';

  -- COMPLETE is never inferred from populated records; a fresh draft is not
  -- ready and the authoritative freeze path rejects it.
  v_readiness := public.get_profile_readiness_v019(v_profile_id);
  if (v_readiness ->> 'freezeReady')::boolean
     or (v_readiness ->> 'requiredScopeCount')::integer <> 8
     or jsonb_array_length(v_readiness -> 'missingDeclarations') <> 8 then
    raise exception 'Fresh readiness does not mirror the no-degree 012 scope law';
  end if;
  v_blocked := false;
  begin
    perform public.freeze_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), v_revision
    );
  exception when others then
    v_blocked := sqlerrm like '%Every required profile and education context%';
  end;
  if not v_blocked or (
    public.get_profile_document_v019(v_profile_id) ->> 'revision'
  )::bigint <> v_revision then
    raise exception 'Failed freeze did not roll back atomically';
  end if;

  -- Evidence CREATE plus real operation replay/conflict semantics.
  v_operation_id := extensions.gen_random_uuid();
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, v_operation_id, v_revision, 'EVIDENCE_CREATE',
    jsonb_build_object('evidenceType', 'SELF_REPORT')
  );
  v_evidence_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  if (v_result ->> 'revision')::bigint <> v_revision then
    raise exception 'Evidence create did not advance revision';
  end if;
  v_replay := public.mutate_profile_draft_v019(
    v_profile_id, v_operation_id, 0, 'EVIDENCE_CREATE',
    jsonb_build_object('evidenceType', 'SELF_REPORT')
  );
  if v_replay is distinct from v_result or jsonb_array_length(
    public.get_profile_document_v019(v_profile_id) -> 'evidenceItems'
  ) <> 1 then
    raise exception 'Exact operation replay duplicated evidence';
  end if;
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile_id, v_operation_id, 0, 'EVIDENCE_CREATE',
      jsonb_build_object('evidenceType', 'TRANSCRIPT')
    );
  exception when unique_violation then
    v_blocked := sqlerrm = 'PROFILE_OPERATION_CONFLICT';
  end;
  if not v_blocked then
    raise exception 'operationId accepted a different payload';
  end if;

  -- Unknown keys, arbitrary metadata, reviewer fields, arbitrary preference
  -- extensions, and unknown test sections fail before revision changes.
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), v_revision,
      'EVIDENCE_CREATE',
      jsonb_build_object('evidenceType', 'SELF_REPORT', 'metadata', jsonb_build_object('x', 1))
    );
  exception when invalid_parameter_value then
    v_blocked := sqlerrm = 'PROFILE_UNKNOWN_FIELD';
  end;
  if not v_blocked then raise exception 'Arbitrary evidence metadata was accepted'; end if;
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), v_revision,
      'DEGREE_CREATE',
      jsonb_build_object(
        'institutionName', 'Example', 'degreeName', 'BS',
        'degreeLevel', 'BACHELORS', 'degreeStatus', 'COMPLETED',
        'evidenceId', v_evidence_id, 'reviewedBy', 'student'
      )
    );
  exception when invalid_parameter_value then
    v_blocked := sqlerrm = 'PROFILE_UNKNOWN_FIELD';
  end;
  if not v_blocked then raise exception 'Reviewer field was student-editable'; end if;
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), v_revision,
      'PREFERENCE_CREATE',
      jsonb_build_object(
        'preferenceType', 'BUDGET', 'priority', 1,
        'value', jsonb_build_object('currencyCode', 'USD', 'maximumAmount', 1, 'extra', true)
      )
    );
  exception when invalid_parameter_value then
    v_blocked := sqlerrm = 'PROFILE_UNKNOWN_FIELD';
  end;
  if not v_blocked then raise exception 'Arbitrary preference extension was accepted'; end if;

  -- Cross-profile evidence ID attack fails closed.
  execute 'reset role';
  select evidence.student_evidence_id into v_extra_evidence_id
  from public.student_evidence_items evidence
  where evidence.profile_version_id = v_other_profile_id
  limit 1;
  if v_extra_evidence_id is null then
    insert into public.student_evidence_items (
      profile_version_id, evidence_type
    ) values (v_other_profile_id, 'SELF_REPORT')
    returning student_evidence_id into v_extra_evidence_id;
  end if;
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), v_revision,
      'DEGREE_CREATE',
      jsonb_build_object(
        'institutionName', 'Other', 'degreeName', 'BS',
        'degreeLevel', 'BACHELORS', 'degreeStatus', 'COMPLETED',
        'evidenceId', v_extra_evidence_id
      )
    );
  exception when no_data_found then
    v_blocked := sqlerrm = 'PROFILE_CHILD_NOT_FOUND';
  end;
  if not v_blocked then raise exception 'Cross-profile evidence ID was accepted'; end if;

  -- Primary records: CREATE and UPDATE for every browser-editable resource.
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'EVIDENCE_UPDATE',
    jsonb_build_object('evidenceId', v_evidence_id, 'evidenceType', 'SELF_REPORT',
      'locator', 'student-entry')
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'DEGREE_CREATE',
    jsonb_build_object(
      'institutionName', 'Example University', 'degreeName', 'BSc Economics',
      'degreeLevel', 'BACHELORS', 'degreeStatus', 'COMPLETED',
      'countryCode', 'US', 'gpaValue', 3.8, 'gpaScale', 4,
      'evidenceId', v_evidence_id
    )
  );
  v_degree_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'DEGREE_UPDATE',
    jsonb_build_object(
      'degreeId', v_degree_id, 'institutionName', 'Example University',
      'degreeName', 'BSc Quantitative Economics', 'degreeLevel', 'BACHELORS',
      'degreeStatus', 'COMPLETED', 'countryCode', 'US',
      'gpaValue', 3.9, 'gpaScale', 4, 'evidenceId', v_evidence_id
    )
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'COURSE_CREATE',
    jsonb_build_object(
      'degreeId', v_degree_id, 'courseCode', 'MATH-201',
      'courseTitle', 'Calculus II', 'courseStatus', 'COMPLETED',
      'credits', 4, 'gradeValue', 4, 'gradeScale', 4,
      'evidenceId', v_evidence_id
    )
  );
  v_course_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'COURSE_UPDATE',
    jsonb_build_object(
      'courseId', v_course_id, 'degreeId', v_degree_id,
      'courseCode', 'MATH-201', 'courseTitle', 'Calculus II',
      'courseStatus', 'COMPLETED', 'term', 'Fall', 'credits', 4,
      'gradeValue', 4, 'gradeScale', 4, 'evidenceId', v_evidence_id
    )
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'TEST_SCORE_CREATE',
    jsonb_build_object(
      'assessmentConceptId', v_assessment_concept_id, 'testDate', '2026-01-01',
      'totalScore', 330, 'sectionScores', jsonb_build_object('quantitative', 170),
      'evidenceId', v_evidence_id
    )
  );
  v_test_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'TEST_SCORE_UPDATE',
    jsonb_build_object(
      'testScoreId', v_test_id, 'assessmentConceptId', v_assessment_concept_id,
      'testDate', '2026-01-01', 'totalScore', 331,
      'sectionScores', jsonb_build_object('quantitative', 170, 'verbal', 161),
      'evidenceId', v_evidence_id
    )
  );
  v_revision := v_revision + 1;

  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), v_revision,
      'TEST_SCORE_UPDATE',
      jsonb_build_object(
        'testScoreId', v_test_id, 'assessmentConceptId', v_assessment_concept_id,
        'testDate', '2026-01-01', 'sectionScores', jsonb_build_object('secret', 1),
        'evidenceId', v_evidence_id
      )
    );
  exception when invalid_parameter_value then
    v_blocked := sqlerrm = 'PROFILE_UNKNOWN_SECTION_SCORE';
  end;
  if not v_blocked then raise exception 'Unknown test section was accepted'; end if;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'EXPERIENCE_CREATE',
    jsonb_build_object(
      'experienceType', 'RESEARCH', 'organizationName', 'Example Lab',
      'roleTitle', 'Research Assistant', 'hoursPerWeek', 10,
      'evidenceId', v_evidence_id
    )
  );
  v_experience_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'EXPERIENCE_UPDATE',
    jsonb_build_object(
      'experienceId', v_experience_id, 'experienceType', 'RESEARCH',
      'organizationName', 'Example Lab', 'roleTitle', 'Senior Research Assistant',
      'hoursPerWeek', 12, 'description', 'Quantitative research',
      'evidenceId', v_evidence_id
    )
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'SKILL_CREATE',
    jsonb_build_object(
      'skillConceptId', v_skill_concept_id, 'proficiencyLevel', 4,
      'yearsExperience', 2, 'evidenceId', v_evidence_id
    )
  );
  v_skill_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'SKILL_UPDATE',
    jsonb_build_object(
      'skillId', v_skill_id, 'skillConceptId', v_skill_concept_id,
      'proficiencyLevel', 5, 'yearsExperience', 3,
      'evidenceId', v_evidence_id
    )
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision,
    'EXPERIENCE_SKILL_LINK',
    jsonb_build_object('experienceId', v_experience_id, 'skillId', v_skill_id)
  );
  v_revision := v_revision + 1;
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision,
    'EXPERIENCE_SKILL_UNLINK',
    jsonb_build_object('experienceId', v_experience_id, 'skillId', v_skill_id)
  );
  v_revision := v_revision + 1;
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision,
    'EXPERIENCE_SKILL_LINK',
    jsonb_build_object('experienceId', v_experience_id, 'skillId', v_skill_id)
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'GOAL_CREATE',
    jsonb_build_object(
      'goalType', 'CAREER', 'conceptId', v_goal_concept_id,
      'goalText', 'Quantitative economist', 'priority', 1
    )
  );
  v_goal_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'GOAL_UPDATE',
    jsonb_build_object(
      'goalId', v_goal_id, 'goalType', 'CAREER',
      'conceptId', v_goal_concept_id, 'goalText', 'Applied economist',
      'priority', 2
    )
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'PREFERENCE_CREATE',
    jsonb_build_object(
      'preferenceType', 'BUDGET', 'priority', 1,
      'value', jsonb_build_object('currencyCode', 'USD', 'maximumAmount', 100000)
    )
  );
  v_preference_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'PREFERENCE_UPDATE',
    jsonb_build_object(
      'preferenceId', v_preference_id, 'preferenceType', 'BUDGET',
      'priority', 2,
      'value', jsonb_build_object('currencyCode', 'USD', 'maximumAmount', 90000)
    )
  );
  v_revision := v_revision + 1;

  -- Every DELETE command receives a valid disposable resource.
  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'EVIDENCE_CREATE',
    jsonb_build_object('evidenceType', 'SELF_REPORT')
  );
  v_extra_evidence_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'EVIDENCE_DELETE',
    jsonb_build_object('evidenceId', v_extra_evidence_id)
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'DEGREE_CREATE',
    jsonb_build_object(
      'institutionName', 'Delete University', 'degreeName', 'Delete Degree',
      'degreeLevel', 'BACHELORS', 'degreeStatus', 'WITHDRAWN',
      'evidenceId', v_evidence_id
    )
  );
  v_temp_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'DEGREE_DELETE',
    jsonb_build_object('degreeId', v_temp_id)
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'COURSE_CREATE',
    jsonb_build_object('courseTitle', 'Delete Course', 'courseStatus', 'WITHDRAWN',
      'evidenceId', v_evidence_id)
  );
  v_temp_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'COURSE_DELETE',
    jsonb_build_object('courseId', v_temp_id)
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'TEST_SCORE_CREATE',
    jsonb_build_object('assessmentConceptId', v_assessment_concept_id,
      'testDate', '2026-02-01', 'totalScore', 1, 'evidenceId', v_evidence_id)
  );
  v_temp_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'TEST_SCORE_DELETE',
    jsonb_build_object('testScoreId', v_temp_id)
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'EXPERIENCE_CREATE',
    jsonb_build_object('experienceType', 'OTHER', 'roleTitle', 'Delete Experience',
      'evidenceId', v_evidence_id)
  );
  v_temp_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'EXPERIENCE_DELETE',
    jsonb_build_object('experienceId', v_temp_id)
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'SKILL_CREATE',
    jsonb_build_object('skillConceptId', v_second_skill_concept_id,
      'evidenceId', v_evidence_id)
  );
  v_temp_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'SKILL_DELETE',
    jsonb_build_object('skillId', v_temp_id)
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'GOAL_CREATE',
    jsonb_build_object('goalType', 'OTHER', 'goalText', 'Delete goal', 'priority', 5)
  );
  v_temp_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'GOAL_DELETE',
    jsonb_build_object('goalId', v_temp_id)
  );
  v_revision := v_revision + 1;

  v_result := public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'PREFERENCE_CREATE',
    jsonb_build_object('preferenceType', 'DELIVERY_MODE', 'priority', 5,
      'value', jsonb_build_object('modes', jsonb_build_array('ONLINE')))
  );
  v_temp_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(
    v_profile_id, extensions.gen_random_uuid(), v_revision, 'PREFERENCE_DELETE',
    jsonb_build_object('preferenceId', v_temp_id)
  );
  v_revision := v_revision + 1;

  -- Stale revision fails without a lost update.
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), v_revision - 1,
      'GOAL_CREATE',
      jsonb_build_object('goalType', 'OTHER', 'goalText', 'stale', 'priority', 1)
    );
  exception when serialization_failure then
    v_blocked := sqlerrm = 'PROFILE_REVISION_CONFLICT';
  end;
  if not v_blocked then raise exception 'Stale revision was accepted'; end if;

  -- Exact Migration 012 scope law: six globals plus two per degree. PARTIAL
  -- and UNKNOWN are explicit declarations with explanations and remain
  -- freeze-eligible; COMPLETE is never inferred.
  perform public.mutate_profile_draft_v019(v_profile_id, extensions.gen_random_uuid(), v_revision,
    'COMPLETENESS_UPSERT', jsonb_build_object('domain','EDUCATION_HISTORY','completeness','COMPLETE'));
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(v_profile_id, extensions.gen_random_uuid(), v_revision,
    'COMPLETENESS_UPSERT', jsonb_build_object('domain','TEST_HISTORY','completeness','PARTIAL','explanation','One score pending'));
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(v_profile_id, extensions.gen_random_uuid(), v_revision,
    'COMPLETENESS_UPSERT', jsonb_build_object('domain','EXPERIENCE_HISTORY','completeness','UNKNOWN','explanation','History not fully known'));
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(v_profile_id, extensions.gen_random_uuid(), v_revision,
    'COMPLETENESS_UPSERT', jsonb_build_object('domain','SKILL_HISTORY','completeness','COMPLETE'));
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(v_profile_id, extensions.gen_random_uuid(), v_revision,
    'COMPLETENESS_UPSERT', jsonb_build_object('domain','PREFERENCES','completeness','COMPLETE'));
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(v_profile_id, extensions.gen_random_uuid(), v_revision,
    'COMPLETENESS_UPSERT', jsonb_build_object('domain','GOALS','completeness','COMPLETE'));
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(v_profile_id, extensions.gen_random_uuid(), v_revision,
    'COMPLETENESS_UPSERT', jsonb_build_object('educationContextId',v_degree_id,'domain','COURSE_HISTORY','completeness','COMPLETE'));
  v_revision := v_revision + 1;
  perform public.mutate_profile_draft_v019(v_profile_id, extensions.gen_random_uuid(), v_revision,
    'COMPLETENESS_UPSERT', jsonb_build_object('educationContextId',v_degree_id,'domain','COURSE_MAPPING','completeness','PARTIAL','explanation','Mapping review pending'));
  v_revision := v_revision + 1;

  v_readiness := public.get_profile_readiness_v019(v_profile_id);
  if not (v_readiness ->> 'freezeReady')::boolean
     or (v_readiness ->> 'requiredScopeCount')::integer <> 8
     or (v_readiness ->> 'declaredRequiredScopeCount')::integer <> 8
     or jsonb_array_length(v_readiness -> 'missingDeclarations') <> 0 then
    raise exception 'Readiness does not match the 012 required-scope law';
  end if;
  perform public.mutate_profile_draft_v019(v_profile_id, extensions.gen_random_uuid(), v_revision,
    'COMPLETENESS_DELETE', jsonb_build_object('educationContextId',v_degree_id,'domain','COURSE_MAPPING'));
  v_revision := v_revision + 1;
  if (public.get_profile_readiness_v019(v_profile_id) ->> 'freezeReady')::boolean then
    raise exception 'Deleting a declaration did not reopen readiness';
  end if;
  perform public.mutate_profile_draft_v019(v_profile_id, extensions.gen_random_uuid(), v_revision,
    'COMPLETENESS_UPSERT', jsonb_build_object('educationContextId',v_degree_id,'domain','COURSE_MAPPING','completeness','UNKNOWN','explanation','Mapping status unknown'));
  v_revision := v_revision + 1;

  v_document := public.get_profile_document_v019(v_profile_id);
  if v_document ->> 'schemaVersion' <> 'PROFILE_DOCUMENT_V019'
     or v_document ? 'studentId' or v_document ? 'authUserId'
     or jsonb_array_length(v_document -> 'degrees') <> 1
     or jsonb_array_length(v_document -> 'courses') <> 1
     or jsonb_array_length(v_document -> 'testScores') <> 1
     or jsonb_array_length(v_document -> 'experiences') <> 1
     or jsonb_array_length(v_document -> 'skills') <> 1
     or jsonb_array_length(v_document -> 'goals') <> 1
     or jsonb_array_length(v_document -> 'preferences') <> 1 then
    raise exception 'Closed Profile document has an invalid schema or content';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_document -> 'mappings') mapping
    where mapping ?| array[
      'method', 'confidence', 'modelVersion', 'reviewedBy', 'reviewedAt',
      'supersedesMappingId', 'retiredAt', 'retirementReason'
    ]
  ) then
    raise exception 'Profile DTO exposed reviewer identity/control fields';
  end if;
  if pg_get_functiondef(
       'private.profile_document_v019(uuid)'::regprocedure
     ) like any (array[
       '%''method''%', '%''confidence''%', '%''modelVersion''%',
       '%''reviewedBy''%', '%''reviewedAt''%', '%''retirementReason''%'
     ]) then
    raise exception 'Profile document definition includes internal mapping control fields';
  end if;

  -- Atomic freeze advances revision once, delegates to the frozen 012 law,
  -- and exact operation replay returns the same prior logical result.
  v_operation_id := extensions.gen_random_uuid();
  v_result := public.freeze_profile_draft_v019(
    v_profile_id, v_operation_id, v_revision
  );
  v_revision := v_revision + 1;
  if v_result ->> 'status' <> 'FROZEN'
     or (v_result ->> 'revision')::bigint <> v_revision
     or (v_result #>> '{document,snapshotHash}') !~ '^[a-f0-9]{64}$' then
    raise exception 'Atomic freeze result is invalid';
  end if;
  v_replay := public.freeze_profile_draft_v019(
    v_profile_id, v_operation_id, v_revision - 1
  );
  if v_replay is distinct from v_result then
    raise exception 'Freeze retry did not replay the prior logical result';
  end if;
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), v_revision,
      'GOAL_CREATE',
      jsonb_build_object('goalType','OTHER','goalText','late','priority',1)
    );
  exception when object_not_in_prerequisite_state then
    v_blocked := sqlerrm = 'PROFILE_DRAFT_REQUIRED';
  end;
  if not v_blocked then raise exception 'Late browser child write was accepted'; end if;
  execute 'reset role';

  -- Frozen root/children remain immutable even through the trusted executor.
  v_blocked := false;
  begin
    execute 'set local role foundation_student_executor';
    insert into public.student_goals (
      profile_version_id, goal_type, goal_text, priority
    ) values (v_profile_id, 'OTHER', 'late trusted write', 1);
  exception when others then
    v_blocked := sqlerrm like '%Frozen profile versions are immutable%';
  end;
  execute 'reset role';
  if not v_blocked then raise exception 'Frozen child trigger did not reject a late write'; end if;

  -- Browser direct table DML remains denied.
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    update public.student_profile_versions
    set profile_revision = profile_revision + 1
    where profile_version_id = v_profile_id;
  exception when insufficient_privilege then
    v_blocked := true;
  end;
  execute 'reset role';
  if not v_blocked then raise exception 'Authenticated direct table update was accepted'; end if;

  -- All capability/idempotency state is student-linked and is removed by the
  -- existing privacy lifecycle without replacing its frozen public API.
  select count(*) into v_count
  from private.profile_capability_operations_v019
  where student_id = v_student_id;
  if v_count = 0 then raise exception 'Idempotency witness was not persisted'; end if;
  execute 'set local role service_role';
  perform public.delete_student_data(v_student_id, 'TEST_LIFECYCLE');
  execute 'reset role';
  if exists (
    select 1 from private.profile_capability_operations_v019
    where student_id = v_student_id
  ) or exists (
    select 1 from public.student_profile_versions
    where student_id = v_student_id
  ) or exists (
    select 1 from private.student_identities
    where student_id = v_student_id
  ) then
    raise exception 'Privacy deletion retained Profile capability state';
  end if;
end;
$test$;

rollback;
