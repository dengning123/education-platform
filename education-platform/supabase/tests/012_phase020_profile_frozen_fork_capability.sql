-- Runs after Migration 020 as test identity 012. Test identity 013 belongs to
-- Migration 021 Hosted Auth Subject Compatibility Repair, and test identity
-- 014 belongs to Migration 022 Profile Taxonomy Projection. Application/Outcome
-- remains planning-only under a provisional future Migration 023 identity.

begin;

create or replace function pg_temp.phase020_profile_graph(p_profile_id uuid)
returns jsonb
language sql
stable
as $function$
  select jsonb_build_object(
    'profile', (select to_jsonb(row_value) from public.student_profile_versions row_value
      where row_value.profile_version_id = p_profile_id),
    'completeness', coalesce((select jsonb_agg(to_jsonb(row_value) order by row_value.completeness_id)
      from public.student_data_completeness row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb),
    'evidence', coalesce((select jsonb_agg(to_jsonb(row_value) order by row_value.student_evidence_id)
      from public.student_evidence_items row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb),
    'degrees', coalesce((select jsonb_agg(to_jsonb(row_value) order by row_value.student_degree_id)
      from public.student_degrees row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb),
    'courses', coalesce((select jsonb_agg(to_jsonb(row_value) order by row_value.student_course_id)
      from public.student_courses row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb),
    'tests', coalesce((select jsonb_agg(to_jsonb(row_value) order by row_value.student_test_score_id)
      from public.student_test_scores row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb),
    'experiences', coalesce((select jsonb_agg(to_jsonb(row_value) order by row_value.student_experience_id)
      from public.student_experiences row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb),
    'skills', coalesce((select jsonb_agg(to_jsonb(row_value) order by row_value.student_skill_id)
      from public.student_skills row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb),
    'experienceSkills', coalesce((select jsonb_agg(to_jsonb(row_value)
      order by row_value.student_experience_id, row_value.student_skill_id)
      from public.student_experience_skills row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb),
    'goals', coalesce((select jsonb_agg(to_jsonb(row_value) order by row_value.student_goal_id)
      from public.student_goals row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb),
    'preferences', coalesce((select jsonb_agg(to_jsonb(row_value) order by row_value.student_preference_id)
      from public.student_preferences row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb),
    'mappings', coalesce((select jsonb_agg(to_jsonb(row_value) order by row_value.student_mapping_id)
      from public.student_record_concept_mappings row_value where row_value.profile_version_id = p_profile_id), '[]'::jsonb)
  )
$function$;

do $test$
declare
  v_owner_auth constant uuid := '95000000-0000-0000-0000-000000000001';
  v_other_auth constant uuid := '95000000-0000-0000-0000-000000000002';
  v_owner_student constant uuid := '95000000-0000-0000-0000-000000000011';
  v_other_student constant uuid := '95000000-0000-0000-0000-000000000012';
  v_source_id uuid;
  v_second_source_id uuid;
  v_nonfrozen_source_id uuid;
  v_other_source_id uuid;
  v_new_profile_id uuid;
  v_evidence_id uuid;
  v_degree_id uuid;
  v_course_id uuid;
  v_test_id uuid;
  v_experience_id uuid;
  v_skill_id uuid;
  v_goal_id uuid;
  v_new_goal_id uuid;
  v_preference_id uuid;
  v_retired_mapping_id uuid;
  v_verified_mapping_id uuid;
  v_new_retired_mapping_id uuid;
  v_new_active_mapping_id uuid;
  v_new_degree_id uuid;
  v_new_course_id uuid;
  v_new_evidence_id uuid;
  v_assessment_concept_id uuid;
  v_skill_concept_id uuid;
  v_field_concept_id uuid;
  v_career_concept_id uuid;
  v_operation_id uuid := '95000000-0000-0000-0000-000000000101';
  v_result jsonb;
  v_replay jsonb;
  v_source_before jsonb;
  v_source_after jsonb;
  v_blocked boolean;
  v_domain public.student_data_domain;
  v_count integer;
begin
  perform set_config('statement_timeout', '30s', true);

  if not exists (
    select 1 from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'fork_frozen_profile_to_draft_v020'
      and procedure.proowner::regrole::text = 'foundation_student_executor'
      and procedure.prosecdef
      and procedure.proconfig is not distinct from
        array['search_path=pg_catalog, public, private, extensions']::text[]
  ) then
    raise exception '020 fork function contract is absent';
  end if;
  if exists (
    select 1 from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'fork_frozen_profile_to_draft_v020'
      and pg_get_function_identity_arguments(procedure.oid) like '%student_id%'
  ) then
    raise exception '020 fork accepts caller-supplied student ownership';
  end if;
  if has_table_privilege(
    'authenticated', 'public.student_profile_versions', 'INSERT,UPDATE,DELETE'
  ) or has_table_privilege(
    'authenticated', 'private.profile_capability_operations_v019',
    'SELECT,INSERT,UPDATE,DELETE'
  ) then
    raise exception '020 introduced direct authenticated DML';
  end if;

  v_blocked := false;
  begin
    execute 'set local role anon';
    perform public.fork_frozen_profile_to_draft_v020(
      extensions.gen_random_uuid(), extensions.gen_random_uuid()
    );
  exception when insufficient_privilege then
    v_blocked := true;
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception 'Anonymous fork was not rejected';
  end if;

  insert into auth.users (id, email) values
    (v_owner_auth, 'phase020-owner@test.invalid'),
    (v_other_auth, 'phase020-other@test.invalid');
  perform public.create_student(v_owner_student);
  perform public.create_student(v_other_student);
  insert into private.student_identities (auth_user_id, student_id) values
    (v_owner_auth, v_owner_student),
    (v_other_auth, v_other_student);

  select concept_id into strict v_assessment_concept_id
  from public.taxonomy_concepts
  where concept_kind = 'ASSESSMENT' and retired_in_release is null
  order by concept_id limit 1;
  select concept_id into strict v_skill_concept_id
  from public.taxonomy_concepts
  where concept_kind = 'SKILL' and retired_in_release is null
  order by concept_id limit 1;
  select concept_id into strict v_field_concept_id
  from public.taxonomy_concepts
  where concept_kind in ('FIELD', 'SUBFIELD') and retired_in_release is null
  order by concept_id limit 1;
  select concept_id into strict v_career_concept_id
  from public.taxonomy_concepts
  where concept_kind = 'CAREER' and retired_in_release is null
  order by concept_id limit 1;

  v_source_id := public.create_student_profile_version(v_owner_student, 1);
  insert into public.student_evidence_items (
    profile_version_id, evidence_type, locator, content_hash,
    observed_at, metadata
  ) values (
    v_source_id, 'SELF_REPORT', 'source-locator', repeat('a', 64),
    '2026-01-01T00:00:00Z',
    jsonb_build_object('reviewedBy', 'source-reviewer', 'control', true)
  ) returning student_evidence_id into v_evidence_id;

  insert into public.student_degrees (
    profile_version_id, institution_name, degree_name, degree_level,
    degree_status, start_date, completion_date, country_code,
    gpa_value, gpa_scale, student_evidence_id
  ) values (
    v_source_id, 'Fork University', 'BSc Economics', 'BACHELORS',
    'COMPLETED', '2021-09-01', '2025-05-01', 'US', 3.8, 4,
    v_evidence_id
  ) returning student_degree_id into v_degree_id;

  insert into public.student_courses (
    profile_version_id, student_degree_id, course_code, course_title,
    course_status, term, completion_date, credits, grade_value,
    grade_scale, grade_text, student_evidence_id
  ) values (
    v_source_id, v_degree_id, 'MATH-201', 'Calculus II', 'COMPLETED',
    'Fall 2023', '2023-12-15', 4, 4, 4, 'A', v_evidence_id
  ) returning student_course_id into v_course_id;

  insert into public.student_test_scores (
    profile_version_id, assessment_concept_id, test_date, total_score,
    section_scores, student_evidence_id
  ) values (
    v_source_id, v_assessment_concept_id, '2025-10-01', 330,
    jsonb_build_object('quantitative', 170, 'verbal', 160), v_evidence_id
  ) returning student_test_score_id into v_test_id;

  insert into public.student_experiences (
    profile_version_id, experience_type, organization_name, role_title,
    start_date, end_date, hours_per_week, description, student_evidence_id
  ) values (
    v_source_id, 'RESEARCH', 'Fork Lab', 'Research Assistant',
    '2024-01-01', '2025-01-01', 10, 'Quantitative research', v_evidence_id
  ) returning student_experience_id into v_experience_id;

  insert into public.student_skills (
    profile_version_id, skill_concept_id, proficiency_level,
    years_experience, student_evidence_id
  ) values (
    v_source_id, v_skill_concept_id, 4, 2, v_evidence_id
  ) returning student_skill_id into v_skill_id;

  insert into public.student_experience_skills (
    profile_version_id, student_experience_id, student_skill_id
  ) values (v_source_id, v_experience_id, v_skill_id);

  insert into public.student_goals (
    profile_version_id, goal_type, concept_id, goal_text, priority
  ) values (
    v_source_id, 'CAREER', v_career_concept_id,
    'Quantitative economist', 1
  ) returning student_goal_id into v_goal_id;

  insert into public.student_preferences (
    profile_version_id, preference_type, value, priority
  ) values (
    v_source_id, 'BUDGET',
    jsonb_build_object('currencyCode', 'USD', 'maximumAmount', 90000), 1
  ) returning student_preference_id into v_preference_id;

  foreach v_domain in array array[
    'EDUCATION_HISTORY','TEST_HISTORY','EXPERIENCE_HISTORY','SKILL_HISTORY',
    'PREFERENCES','GOALS'
  ]::public.student_data_domain[]
  loop
    insert into public.student_data_completeness (
      profile_version_id, education_context_id, domain, completeness
    ) values (v_source_id, null, v_domain, 'COMPLETE');
  end loop;
  foreach v_domain in array array[
    'COURSE_HISTORY','COURSE_MAPPING'
  ]::public.student_data_domain[]
  loop
    insert into public.student_data_completeness (
      profile_version_id, education_context_id, domain, completeness
    ) values (v_source_id, v_degree_id, v_domain, 'COMPLETE');
  end loop;

  insert into public.student_record_concept_mappings (
    profile_version_id, record_type, student_record_id, concept_id,
    mapping_status, method, confidence, student_evidence_id
  ) values (
    v_source_id, 'DEGREE', v_degree_id, v_field_concept_id,
    'PROPOSED', 'HUMAN', 0.9, v_evidence_id
  ) returning student_mapping_id into v_retired_mapping_id;
  perform public.review_student_record_concept_mapping(
    v_retired_mapping_id, 'VERIFIED', 'source-reviewer', v_evidence_id
  );
  perform public.retire_student_record_concept_mapping(
    v_retired_mapping_id, 'superseded source mapping'
  );

  insert into public.student_record_concept_mappings (
    profile_version_id, record_type, student_record_id, concept_id,
    mapping_status, method, confidence, student_evidence_id,
    supersedes_mapping_id
  ) values (
    v_source_id, 'DEGREE', v_degree_id, v_field_concept_id,
    'PROPOSED', 'HUMAN', 0.95, v_evidence_id,
    v_retired_mapping_id
  ) returning student_mapping_id into v_verified_mapping_id;
  perform public.review_student_record_concept_mapping(
    v_verified_mapping_id, 'VERIFIED', 'source-reviewer', v_evidence_id
  );

  perform public.freeze_student_profile_version(v_source_id);

  -- A second owner source is used only for conflicting operation replay.
  v_second_source_id := public.create_student_profile_version(v_owner_student, 2);
  foreach v_domain in array array[
    'EDUCATION_HISTORY','TEST_HISTORY','EXPERIENCE_HISTORY','SKILL_HISTORY',
    'PREFERENCES','GOALS','COURSE_HISTORY','COURSE_MAPPING'
  ]::public.student_data_domain[]
  loop
    insert into public.student_data_completeness (
      profile_version_id, domain, completeness
    ) values (v_second_source_id, v_domain, 'COMPLETE');
  end loop;
  perform public.freeze_student_profile_version(v_second_source_id);

  -- Non-product historical DRAFTs do not consume the active product slot.
  v_nonfrozen_source_id := public.create_student_profile_version(v_owner_student, 3);

  v_other_source_id := public.create_student_profile_version(v_other_student, 1);
  foreach v_domain in array array[
    'EDUCATION_HISTORY','TEST_HISTORY','EXPERIENCE_HISTORY','SKILL_HISTORY',
    'PREFERENCES','GOALS','COURSE_HISTORY','COURSE_MAPPING'
  ]::public.student_data_domain[]
  loop
    insert into public.student_data_completeness (
      profile_version_id, domain, completeness
    ) values (v_other_source_id, v_domain, 'COMPLETE');
  end loop;
  perform public.freeze_student_profile_version(v_other_source_id);

  v_source_before := pg_temp.phase020_profile_graph(v_source_id);

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';

  v_blocked := false;
  begin
    perform public.fork_frozen_profile_to_draft_v020(
      v_nonfrozen_source_id, extensions.gen_random_uuid()
    );
  exception when object_not_in_prerequisite_state then
    v_blocked := sqlerrm = 'PROFILE_FROZEN_REQUIRED';
  end;
  if not v_blocked then
    raise exception 'Non-FROZEN owner source was accepted';
  end if;

  v_blocked := false;
  begin
    perform public.fork_frozen_profile_to_draft_v020(
      v_other_source_id, extensions.gen_random_uuid()
    );
  exception when no_data_found then
    v_blocked := sqlerrm = 'PROFILE_NOT_FOUND';
  end;
  if not v_blocked then
    raise exception 'Cross-student source attack was accepted';
  end if;

  v_result := public.fork_frozen_profile_to_draft_v020(
    v_source_id, v_operation_id
  );
  v_new_profile_id := (v_result ->> 'profileVersionId')::uuid;
  if v_result ->> 'schemaVersion' <> 'PROFILE_OPERATION_RESULT_V020'
     or v_result ->> 'operation' <> 'FORK_FROZEN'
     or (v_result ->> 'sourceProfileVersionId')::uuid <> v_source_id
     or (v_result ->> 'versionNumber')::integer <> 4
     or v_result ->> 'status' <> 'DRAFT'
     or (v_result ->> 'revision')::bigint <> 0 then
    raise exception 'Owner fork result is invalid';
  end if;

  v_replay := public.fork_frozen_profile_to_draft_v020(
    v_source_id, v_operation_id
  );
  if v_replay is distinct from v_result then
    raise exception 'Exact fork replay changed its result';
  end if;

  v_blocked := false;
  begin
    perform public.fork_frozen_profile_to_draft_v020(
      v_second_source_id, v_operation_id
    );
  exception when unique_violation then
    v_blocked := sqlerrm = 'PROFILE_OPERATION_CONFLICT';
  end;
  if not v_blocked then
    raise exception 'Conflicting source replay was accepted';
  end if;

  v_blocked := false;
  begin
    perform public.fork_frozen_profile_to_draft_v020(
      v_second_source_id, extensions.gen_random_uuid()
    );
  exception when object_not_in_prerequisite_state then
    v_blocked := sqlerrm = 'PROFILE_ACTIVE_DRAFT_EXISTS';
  end;
  if not v_blocked then
    raise exception 'Existing active product draft did not produce stable conflict';
  end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub', v_other_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.fork_frozen_profile_to_draft_v020(
      v_source_id, extensions.gen_random_uuid()
    );
  exception when no_data_found then
    v_blocked := sqlerrm = 'PROFILE_NOT_FOUND';
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception 'Unrelated authenticated user forked the owner source';
  end if;

  if not exists (
    select 1 from public.student_profile_versions profile
    where profile.profile_version_id = v_new_profile_id
      and profile.student_id = v_owner_student
      and profile.version_number = 4
      and profile.product_managed
      and profile.status = 'DRAFT'
      and profile.profile_revision = 0
      and profile.snapshot_hash is null
      and profile.frozen_at is null
  ) or (
    select count(*) from public.student_profile_versions profile
    where profile.student_id = v_owner_student
      and profile.product_managed and profile.status = 'DRAFT'
  ) <> 1 then
    raise exception 'Fork root/revision/single-active-draft contract failed';
  end if;

  -- Row counts are exact for every required graph family.
  if (select count(*) from public.student_data_completeness where profile_version_id = v_new_profile_id) <> 8
     or (select count(*) from public.student_evidence_items where profile_version_id = v_new_profile_id) <> 1
     or (select count(*) from public.student_degrees where profile_version_id = v_new_profile_id) <> 1
     or (select count(*) from public.student_courses where profile_version_id = v_new_profile_id) <> 1
     or (select count(*) from public.student_test_scores where profile_version_id = v_new_profile_id) <> 1
     or (select count(*) from public.student_experiences where profile_version_id = v_new_profile_id) <> 1
     or (select count(*) from public.student_skills where profile_version_id = v_new_profile_id) <> 1
     or (select count(*) from public.student_experience_skills where profile_version_id = v_new_profile_id) <> 1
     or (select count(*) from public.student_goals where profile_version_id = v_new_profile_id) <> 1
     or (select count(*) from public.student_preferences where profile_version_id = v_new_profile_id) <> 1
     or (select count(*) from public.student_record_concept_mappings where profile_version_id = v_new_profile_id) <> 2 then
    raise exception 'Fork did not deep-copy every graph family';
  end if;

  select student_evidence_id into strict v_new_evidence_id
  from public.student_evidence_items where profile_version_id = v_new_profile_id;
  select student_degree_id into strict v_new_degree_id
  from public.student_degrees where profile_version_id = v_new_profile_id;
  select student_course_id into strict v_new_course_id
  from public.student_courses where profile_version_id = v_new_profile_id;
  select student_mapping_id into strict v_new_retired_mapping_id
  from public.student_record_concept_mappings
  where profile_version_id = v_new_profile_id and mapping_status = 'RETIRED';
  select student_mapping_id into strict v_new_active_mapping_id
  from public.student_record_concept_mappings
  where profile_version_id = v_new_profile_id and mapping_status = 'PROPOSED';

  if v_new_profile_id = v_source_id
     or v_new_evidence_id = v_evidence_id
     or v_new_degree_id = v_degree_id
     or v_new_course_id = v_course_id
     or v_new_retired_mapping_id = v_retired_mapping_id
     or v_new_active_mapping_id = v_verified_mapping_id then
    raise exception 'Fork reused a source entity identifier';
  end if;

  if (select metadata from public.student_evidence_items
      where student_evidence_id = v_new_evidence_id) <> '{}'::jsonb
     or (select student_evidence_id from public.student_degrees
         where student_degree_id = v_new_degree_id) <> v_new_evidence_id
     or (select student_degree_id from public.student_courses
         where student_course_id = v_new_course_id) <> v_new_degree_id
     or (select student_evidence_id from public.student_courses
         where student_course_id = v_new_course_id) <> v_new_evidence_id
     or exists (
       select 1 from public.student_data_completeness completeness
       where completeness.profile_version_id = v_new_profile_id
         and completeness.education_context_id is not null
         and completeness.education_context_id <> v_new_degree_id
     )
     or not exists (
       select 1 from public.student_experience_skills link
       join public.student_experiences experience
         on experience.student_experience_id = link.student_experience_id
        and experience.profile_version_id = link.profile_version_id
       join public.student_skills skill
         on skill.student_skill_id = link.student_skill_id
        and skill.profile_version_id = link.profile_version_id
       where link.profile_version_id = v_new_profile_id
     ) then
    raise exception 'Fork did not remap evidence/context/relation identifiers';
  end if;

  if not exists (
    select 1
    from public.student_record_concept_mappings active_mapping
    join public.student_record_concept_mappings retired_mapping
      on retired_mapping.student_mapping_id = active_mapping.supersedes_mapping_id
     and retired_mapping.profile_version_id = active_mapping.profile_version_id
    where active_mapping.student_mapping_id = v_new_active_mapping_id
      and active_mapping.profile_version_id = v_new_profile_id
      and active_mapping.student_record_id = v_new_degree_id
      and active_mapping.student_evidence_id = v_new_evidence_id
      and active_mapping.mapping_status = 'PROPOSED'
      and active_mapping.reviewed_by is null
      and active_mapping.reviewed_at is null
      and active_mapping.retired_at is null
      and active_mapping.retirement_reason is null
      and retired_mapping.student_mapping_id = v_new_retired_mapping_id
      and retired_mapping.student_record_id = v_new_degree_id
      and retired_mapping.student_evidence_id = v_new_evidence_id
      and retired_mapping.mapping_status = 'RETIRED'
      and retired_mapping.reviewed_by = 'PROFILE_FORK_V020'
      and retired_mapping.reviewed_at is not null
      and retired_mapping.retired_at is not null
  ) then
    raise exception 'Mapping authority/history was not safely remapped';
  end if;

  -- No target-owned FK may point back into the source graph.
  if exists (
    select 1 from public.student_data_completeness target
    where target.profile_version_id = v_new_profile_id
      and target.education_context_id = v_degree_id
    union all
    select 1 from public.student_courses target
    where target.profile_version_id = v_new_profile_id
      and (target.student_degree_id = v_degree_id
        or target.student_evidence_id = v_evidence_id)
    union all
    select 1 from public.student_experience_skills target
    where target.profile_version_id = v_new_profile_id
      and (target.student_experience_id = v_experience_id
        or target.student_skill_id = v_skill_id)
    union all
    select 1 from public.student_record_concept_mappings target
    where target.profile_version_id = v_new_profile_id
      and (target.student_record_id in (v_degree_id, v_course_id)
        or target.student_evidence_id = v_evidence_id
        or target.supersedes_mapping_id in (
          v_retired_mapping_id, v_verified_mapping_id
        ))
  ) then
    raise exception 'New draft retained an old-child identifier';
  end if;

  -- Existing v019 mutation is the only edit authority and starts from
  -- revision zero on the forked draft.
  select student_goal_id into strict v_new_goal_id
  from public.student_goals
  where profile_version_id = v_new_profile_id;
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_result := public.mutate_profile_draft_v019(
    v_new_profile_id, extensions.gen_random_uuid(), 0, 'GOAL_UPDATE',
    jsonb_build_object(
      'goalId', v_new_goal_id,
      'goalType', 'CAREER', 'conceptId', v_career_concept_id,
      'goalText', 'Edited fork goal', 'priority', 2
    )
  );
  if (v_result ->> 'revision')::bigint <> 1 then
    raise exception 'Forked draft did not use the v019 revision contract';
  end if;
  v_replay := public.fork_frozen_profile_to_draft_v020(
    v_source_id, v_operation_id
  );
  execute 'reset role';
  if (v_replay ->> 'profileVersionId')::uuid <> v_new_profile_id
     or (v_replay ->> 'revision')::bigint <> 0 then
    raise exception 'Fork replay did not preserve the original operation result';
  end if;

  v_source_after := pg_temp.phase020_profile_graph(v_source_id);
  if v_source_after is distinct from v_source_before then
    raise exception 'Fork or target edit mutated the FROZEN source graph';
  end if;

  select count(*) into v_count
  from private.profile_capability_operations_v019
  where student_id = v_owner_student and operation_kind = 'FORK_FROZEN';
  if v_count <> 1 then
    raise exception 'Fork idempotency state is missing or duplicated';
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(v_owner_student, 'TEST_LIFECYCLE');
  perform public.delete_student_data(v_other_student, 'TEST_LIFECYCLE');
  execute 'reset role';

  if exists (
    select 1 from private.profile_capability_operations_v019
    where student_id in (v_owner_student, v_other_student)
  ) or exists (
    select 1 from public.student_profile_versions
    where student_id in (v_owner_student, v_other_student)
  ) or exists (
    select 1 from private.student_identities
    where student_id in (v_owner_student, v_other_student)
  ) then
    raise exception 'Privacy deletion retained fork-created state';
  end if;
end;
$test$;

rollback;
