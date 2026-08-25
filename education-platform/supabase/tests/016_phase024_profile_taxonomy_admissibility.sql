-- Runs after Migration 024. All synthetic assessment authority is test-only
-- and rolls back. No real assessment definition is asserted by this file.

begin;

do $test$
declare
  v_auth constant uuid := '96400000-0000-4000-8000-000000000001';
  v_other_auth constant uuid := '96400000-0000-4000-8000-000000000002';
  v_student constant uuid := '96400000-0000-4000-8000-000000000011';
  v_other_student constant uuid := '96400000-0000-4000-8000-000000000012';
  v_assessment uuid;
  v_unsupported_assessment uuid;
  v_skill uuid;
  v_wrong_kind uuid;
  v_source_identity uuid;
  v_source uuid;
  v_catalog_evidence uuid;
  v_definition uuid;
  v_draft_definition uuid;
  v_overlap_definition uuid;
  v_profile uuid;
  v_fork uuid;
  v_student_evidence uuid;
  v_test_id uuid;
  v_skill_id uuid;
  v_copied_test_id uuid;
  v_copied_skill_id uuid;
  v_copied_evidence uuid;
  v_revision bigint := 0;
  v_result jsonb;
  v_projection jsonb;
  v_before_hash text;
  v_after_hash text;
  v_blocked boolean;
  v_manifest text;
  v_domain public.student_data_domain;
  v_role public.profile_assessment_evidence_role_v024;
begin
  perform set_config('statement_timeout', '30s', true);

  if exists (
    select 1 from public.profile_assessment_definitions_v024
  ) then
    raise exception '024 production migration seeded a real assessment definition';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'student_test_scores'
      and column_name = 'assessment_definition_id'
      and is_nullable = 'YES'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'student_skills'
      and column_name = 'taxonomy_release_ordinal_at_selection'
      and is_nullable = 'YES'
  ) then
    raise exception '024 additive legacy-null pins are absent';
  end if;

  if has_table_privilege(
    'authenticated', 'public.profile_assessment_definitions_v024',
    'SELECT,INSERT,UPDATE,DELETE'
  ) or has_table_privilege(
    'authenticated', 'public.student_test_scores', 'INSERT,UPDATE,DELETE'
  ) or has_function_privilege(
    'anon', 'public.get_profile_assessment_definitions_v024()', 'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.get_profile_assessment_definitions_v024()', 'EXECUTE'
  ) then
    raise exception '024 external ACL boundary drifted';
  end if;

  if exists (
    select 1
    from unnest(array[
      'foundation_catalog_executor', 'foundation_student_executor',
      'anon', 'authenticated', 'authenticator', 'service_role'
    ]::text[]) role_name
    cross join unnest(array['public', 'private']::text[]) schema_name
    where has_schema_privilege(role_name, schema_name, 'CREATE')
  ) or exists (
    select 1
    from pg_namespace namespace
    cross join lateral aclexplode(coalesce(
      namespace.nspacl, acldefault('n', namespace.nspowner)
    )) privilege
    where namespace.nspname in ('public', 'private')
      and privilege.grantee = 0
      and privilege.privilege_type = 'CREATE'
  ) then
    raise exception '024 temporary schema CREATE privilege survived';
  end if;

  if not has_schema_privilege(
    'foundation_catalog_executor', 'public', 'USAGE'
  ) or not has_schema_privilege(
    'foundation_catalog_executor', 'private', 'USAGE'
  ) or not has_schema_privilege(
    'foundation_student_executor', 'public', 'USAGE'
  ) or not has_schema_privilege(
    'foundation_student_executor', 'private', 'USAGE'
  ) then
    raise exception '024 required executor schema USAGE drifted';
  end if;

  if exists (
    select 1
    from (values
      ('public', 'profile_assessment_definitions_v024',
        'foundation_catalog_executor'),
      ('public', 'profile_assessment_score_shapes_v024',
        'foundation_catalog_executor'),
      ('public', 'profile_assessment_sections_v024',
        'foundation_catalog_executor'),
      ('public', 'profile_assessment_definition_evidence_v024',
        'foundation_catalog_executor'),
      ('private', 'profile_fork_context_v024',
        'foundation_student_executor')
    ) expected(schema_name, object_name, owner_role)
    left join pg_namespace namespace
      on namespace.nspname = expected.schema_name
    left join pg_class relation
      on relation.relnamespace = namespace.oid
      and relation.relname = expected.object_name
    where relation.oid is null
      or pg_get_userbyid(relation.relowner) <> expected.owner_role
  ) then
    raise exception '024 exact table owner contract drifted';
  end if;

  if exists (
    select 1
    from (values
      ('private.profile_require_verified_active_concept_v024(uuid,public.taxonomy_concept_kind)',
        'foundation_student_executor'),
      ('private.profile_assessment_definition_guard_v024()',
        'foundation_catalog_executor'),
      ('private.profile_assessment_child_guard_v024()',
        'foundation_catalog_executor'),
      ('public.create_profile_assessment_definition_v024(uuid,bigint,text,text,date,date,numeric,numeric,numeric,smallint,uuid)',
        'foundation_catalog_executor'),
      ('public.add_profile_assessment_score_shape_v024(uuid,public.profile_assessment_score_shape_v024)',
        'foundation_catalog_executor'),
      ('public.add_profile_assessment_section_v024(uuid,text,text,numeric,numeric,numeric,smallint,boolean,smallint)',
        'foundation_catalog_executor'),
      ('public.add_profile_assessment_evidence_v024(uuid,public.profile_assessment_evidence_role_v024,uuid)',
        'foundation_catalog_executor'),
      ('public.verify_profile_assessment_definition_v024(uuid,text)',
        'foundation_catalog_executor'),
      ('public.retire_profile_assessment_definition_v024(uuid,text)',
        'foundation_catalog_executor'),
      ('private.profile_validate_section_scores_v019(jsonb)',
        'foundation_student_executor'),
      ('private.profile_resolve_assessment_definition_v024(uuid,date,bigint)',
        'foundation_student_executor'),
      ('private.profile_validate_assessment_score_v024(uuid,numeric,jsonb)',
        'foundation_student_executor'),
      ('public.validate_student_taxonomy_kind()',
        'foundation_student_executor'),
      ('private.profile_fork_v020_impl_v024(uuid,uuid)',
        'foundation_student_executor'),
      ('public.fork_frozen_profile_to_draft_v020(uuid,uuid)',
        'foundation_student_executor'),
      ('public.get_profile_taxonomy_projection_v024(uuid)',
        'foundation_student_executor'),
      ('public.get_profile_assessment_definitions_v024()',
        'foundation_student_executor')
    ) expected(function_identity, owner_role)
    left join pg_proc procedure
      on procedure.oid = to_regprocedure(expected.function_identity)
    where procedure.oid is null
      or pg_get_userbyid(procedure.proowner) <> expected.owner_role
      or not procedure.prosecdef
      or procedure.proconfig is distinct from array[
        'search_path=pg_catalog, public, private, extensions'
      ]::text[]
  ) then
    raise exception '024 exact function owner/security contract drifted';
  end if;

  select concept_id into strict v_assessment
  from public.taxonomy_concepts
  where canonical_key = 'ASSESSMENT.GRE';
  select concept_id into strict v_unsupported_assessment
  from public.taxonomy_concepts
  where canonical_key = 'ASSESSMENT.GMAT';
  select concept_id into strict v_skill
  from public.taxonomy_concepts
  where canonical_key = 'SKILL.PYTHON';
  select concept_id into strict v_wrong_kind
  from public.taxonomy_concepts
  where concept_kind = 'FIELD'
  order by canonical_key collate "C" limit 1;

  execute 'set local role foundation_catalog_executor';
  v_source_identity := public.create_source_identity(
    'Phase 024 Synthetic Authority',
    'Synthetic assessment definition evidence',
    'https://test.invalid/phase024-assessment-authority',
    'TIER_A_OFFICIAL', 'TEST_FIXTURE', repeat('a', 64),
    'Phase 024 Synthetic Authority'
  );
  select identity.current_source_id into strict v_source
  from public.source_identities identity
  where identity.source_identity_id = v_source_identity;
  insert into public.evidence_items (
    source_id, excerpt, locator, cycle_context,
    retrieved_at, verified_at, content_hash
  ) values (
    v_source, 'Synthetic fixture only.', 'fixture', 'PHASE024_TEST',
    now(), now(), repeat('b', 64)
  ) returning evidence_id into v_catalog_evidence;

  v_definition := public.create_profile_assessment_definition_v024(
    v_assessment, 1::bigint, 'SYNTHETIC_FORMAT', 'v0.1',
    '2000-01-01'::date, '2026-12-31'::date,
    0, 1000, 1, 0::smallint, null
  );
  foreach v_role in array enum_range(
    null::public.profile_assessment_evidence_role_v024
  ) loop
    perform public.add_profile_assessment_evidence_v024(
      v_definition, v_role, v_catalog_evidence
    );
  end loop;
  perform public.add_profile_assessment_score_shape_v024(
    v_definition, 'TOTAL_ONLY'
  );
  perform public.add_profile_assessment_score_shape_v024(
    v_definition, 'SECTIONS_ONLY_COMPLETE'
  );
  perform public.add_profile_assessment_score_shape_v024(
    v_definition, 'SECTIONS_ONLY_PARTIAL'
  );
  perform public.add_profile_assessment_score_shape_v024(
    v_definition, 'TOTAL_AND_COMPLETE_SECTIONS'
  );
  perform public.add_profile_assessment_score_shape_v024(
    v_definition, 'TOTAL_AND_PARTIAL_SECTIONS'
  );
  perform public.add_profile_assessment_section_v024(
    v_definition, 'quantitative', 'Synthetic Quantitative',
    0, 500, 1, 0::smallint, true, 1::smallint
  );
  perform public.add_profile_assessment_section_v024(
    v_definition, 'verbal', 'Synthetic Verbal',
    0, 500, 1, 0::smallint, true, 2::smallint
  );
  v_manifest := public.verify_profile_assessment_definition_v024(
    v_definition, 'PHASE024_TEST'
  );
  if v_manifest !~ '^[a-f0-9]{64}$' then
    raise exception '024 verified manifest is not SHA-256';
  end if;

  -- DRAFT definitions are unusable, and missing evidence cannot be verified.
  v_draft_definition := public.create_profile_assessment_definition_v024(
    v_unsupported_assessment, 1::bigint, 'SYNTHETIC_DRAFT', 'v0.1',
    '2000-01-01'::date, null, 0, 100, 1, 0::smallint, null
  );
  perform public.add_profile_assessment_score_shape_v024(
    v_draft_definition, 'TOTAL_ONLY'
  );
  v_blocked := false;
  begin
    perform public.verify_profile_assessment_definition_v024(
      v_draft_definition, 'PHASE024_TEST'
    );
  exception when object_not_in_prerequisite_state then
    v_blocked := sqlerrm = 'PROFILE_ASSESSMENT_EVIDENCE_INCOMPLETE';
  end;
  if not v_blocked then
    raise exception '024 verified an evidence-incomplete definition';
  end if;

  -- Same-format overlapping VERIFIED intervals fail closed.
  v_overlap_definition := public.create_profile_assessment_definition_v024(
    v_assessment, 2::bigint, 'SYNTHETIC_FORMAT', 'v0.1',
    '2026-01-01'::date, '2027-12-31'::date,
    0, 1000, 1, 0::smallint, v_definition
  );
  foreach v_role in array enum_range(
    null::public.profile_assessment_evidence_role_v024
  ) loop
    perform public.add_profile_assessment_evidence_v024(
      v_overlap_definition, v_role, v_catalog_evidence
    );
  end loop;
  perform public.add_profile_assessment_score_shape_v024(
    v_overlap_definition, 'TOTAL_ONLY'
  );
  v_blocked := false;
  begin
    perform public.verify_profile_assessment_definition_v024(
      v_overlap_definition, 'PHASE024_TEST'
    );
  exception when object_not_in_prerequisite_state then
    v_blocked := sqlerrm = 'PROFILE_ASSESSMENT_DEFINITION_AMBIGUOUS';
  end;
  if not v_blocked then
    raise exception '024 accepted overlapping VERIFIED definitions';
  end if;

  v_blocked := false;
  begin
    update public.profile_assessment_definitions_v024
    set total_max = 999 where assessment_definition_id = v_definition;
  exception when object_not_in_prerequisite_state then
    v_blocked := sqlerrm = 'PROFILE_ASSESSMENT_DEFINITION_IMMUTABLE';
  end;
  if not v_blocked then
    raise exception '024 mutated a VERIFIED definition';
  end if;
  execute 'reset role';

  insert into auth.users (id, email) values
    (v_auth, 'phase024-owner@test.invalid'),
    (v_other_auth, 'phase024-other@test.invalid');
  perform public.create_student(v_student);
  perform public.create_student(v_other_student);
  insert into private.student_identities (auth_user_id, student_id) values
    (v_auth, v_student), (v_other_auth, v_other_student);

  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  execute 'set local role authenticated';
  v_result := public.get_profile_assessment_definitions_v024();
  if v_result ->> 'schemaVersion' <>
       'PROFILE_ASSESSMENT_DEFINITIONS_V024'
     or jsonb_array_length(v_result -> 'definitions') <> 1
     or v_result::text ~ '(evidence|manifest|verifiedBy|retirement)' then
    raise exception '024 bounded assessment definition DTO drifted: %',
      v_result;
  end if;
  v_result := public.create_or_resume_profile_draft_v019(
    extensions.gen_random_uuid()
  );
  v_profile := (v_result ->> 'profileVersionId')::uuid;
  v_result := public.mutate_profile_draft_v019(
    v_profile, extensions.gen_random_uuid(), v_revision,
    'EVIDENCE_CREATE', jsonb_build_object('evidenceType', 'SELF_REPORT')
  );
  v_student_evidence := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;

  -- Definition-backed total + partial sections is accepted and pinned.
  v_result := public.mutate_profile_draft_v019(
    v_profile, extensions.gen_random_uuid(), v_revision,
    'TEST_SCORE_CREATE', jsonb_build_object(
      'assessmentConceptId', v_assessment,
      'testDate', '2026-01-01', 'totalScore', 700,
      'sectionScores', jsonb_build_object('quantitative', 350),
      'evidenceId', v_student_evidence
    )
  );
  v_test_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  execute 'reset role';
  if not exists (
    select 1 from public.student_test_scores score
    where score.student_test_score_id = v_test_id
      and score.assessment_definition_id = v_definition
      and score.taxonomy_release_ordinal_at_selection = 1
      and score.taxonomy_reference_origin = 'NEW_SELECTION'
  ) then
    raise exception '024 did not persist server-resolved test pins';
  end if;
  execute 'set local role authenticated';

  -- Replacement update and exact operation replay retain the same definition.
  v_result := public.mutate_profile_draft_v019(
    v_profile, '96400000-0000-4000-8000-000000000090', v_revision,
    'TEST_SCORE_UPDATE', jsonb_build_object(
      'testScoreId', v_test_id, 'assessmentConceptId', v_assessment,
      'testDate', '2026-01-01', 'totalScore', 701,
      'sectionScores', jsonb_build_object(
        'quantitative', 350, 'verbal', 351
      ), 'evidenceId', v_student_evidence
    )
  );
  v_revision := v_revision + 1;
  if public.mutate_profile_draft_v019(
    v_profile, '96400000-0000-4000-8000-000000000090', v_revision - 1,
    'TEST_SCORE_UPDATE', jsonb_build_object(
      'testScoreId', v_test_id, 'assessmentConceptId', v_assessment,
      'testDate', '2026-01-01', 'totalScore', 701,
      'sectionScores', jsonb_build_object(
        'quantitative', 350, 'verbal', 351
      ), 'evidenceId', v_student_evidence
    )
  ) is distinct from v_result then
    raise exception '024 exact replay changed the mutation result';
  end if;

  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile, '96400000-0000-4000-8000-000000000090', v_revision,
      'TEST_SCORE_UPDATE', jsonb_build_object(
        'testScoreId', v_test_id, 'assessmentConceptId', v_assessment,
        'testDate', '2026-01-01', 'totalScore', 702,
        'sectionScores', jsonb_build_object('quantitative', 350),
        'evidenceId', v_student_evidence
      )
    );
  exception when unique_violation then
    v_blocked := sqlerrm = 'PROFILE_OPERATION_CONFLICT';
  end;
  if not v_blocked then
    raise exception '024 conflicting operation replay was accepted';
  end if;

  -- Empty, unknown section, range, and unsupported definition all fail.
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile, extensions.gen_random_uuid(), v_revision,
      'TEST_SCORE_CREATE', jsonb_build_object(
        'assessmentConceptId', v_assessment, 'testDate', '2026-01-01',
        'sectionScores', jsonb_build_object(),
        'evidenceId', v_student_evidence
      )
    );
  exception when invalid_parameter_value then
    v_blocked := sqlerrm = 'PROFILE_ASSESSMENT_SCORE_INVALID';
  end;
  if not v_blocked then raise exception '024 accepted an empty score'; end if;

  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile, extensions.gen_random_uuid(), v_revision,
      'TEST_SCORE_CREATE', jsonb_build_object(
        'assessmentConceptId', v_assessment, 'testDate', '2026-01-01',
        'sectionScores', jsonb_build_object('wrongSection', 1),
        'evidenceId', v_student_evidence
      )
    );
  exception when invalid_parameter_value then
    v_blocked := sqlerrm = 'PROFILE_ASSESSMENT_SECTION_INVALID';
  end;
  if not v_blocked then raise exception '024 accepted an unknown section'; end if;

  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile, extensions.gen_random_uuid(), v_revision,
      'TEST_SCORE_CREATE', jsonb_build_object(
        'assessmentConceptId', v_assessment, 'testDate', '2026-01-01',
        'totalScore', 1001, 'sectionScores', jsonb_build_object(),
        'evidenceId', v_student_evidence
      )
    );
  exception when invalid_parameter_value then
    v_blocked := sqlerrm = 'PROFILE_ASSESSMENT_SCORE_INVALID';
  end;
  if not v_blocked then raise exception '024 accepted an out-of-range total'; end if;

  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile, extensions.gen_random_uuid(), v_revision,
      'TEST_SCORE_CREATE', jsonb_build_object(
        'assessmentConceptId', v_unsupported_assessment,
        'testDate', '2026-01-01', 'totalScore', 50,
        'sectionScores', jsonb_build_object(),
        'evidenceId', v_student_evidence
      )
    );
  exception when object_not_in_prerequisite_state then
    v_blocked := sqlerrm = 'PROFILE_ASSESSMENT_UNSUPPORTED';
  end;
  if not v_blocked then raise exception '024 used a DRAFT definition'; end if;

  v_result := public.mutate_profile_draft_v019(
    v_profile, extensions.gen_random_uuid(), v_revision,
    'SKILL_CREATE', jsonb_build_object(
      'skillConceptId', v_skill, 'proficiencyLevel', 4,
      'yearsExperience', 2, 'evidenceId', v_student_evidence
    )
  );
  v_skill_id := (v_result ->> 'resourceId')::uuid;
  v_revision := v_revision + 1;
  execute 'reset role';
  if not exists (
    select 1 from public.student_skills skill
    where skill.student_skill_id = v_skill_id
      and skill.taxonomy_release_ordinal_at_selection = 1
      and skill.taxonomy_reference_origin = 'NEW_SELECTION'
      and skill.proficiency_level = 4 and skill.years_experience = 2
  ) then
    raise exception '024 skill self-report pin/values drifted';
  end if;
  execute 'set local role authenticated';

  -- Wrong-kind and unknown concept attacks fail in the shared validator.
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_profile, extensions.gen_random_uuid(), v_revision,
      'SKILL_CREATE', jsonb_build_object(
        'skillConceptId', v_wrong_kind, 'evidenceId', v_student_evidence
      )
    );
  exception when invalid_parameter_value then
    v_blocked := sqlerrm = 'PROFILE_TAXONOMY_KIND_MISMATCH';
  end;
  if not v_blocked then raise exception '024 accepted a wrong-kind skill'; end if;
  execute 'reset role';

  -- A populated-upgrade legacy row has no definition/release pin and must
  -- remain legacy through fork; it is never reinterpreted by Migration 024.
  perform set_config('session_replication_role', 'replica', true);
  insert into public.student_test_scores (
    profile_version_id, assessment_concept_id, test_date, total_score,
    section_scores, student_evidence_id
  ) values (
    v_profile, v_unsupported_assessment, '2025-01-01', 50,
    '{}'::jsonb, v_student_evidence
  );
  perform set_config('session_replication_role', 'origin', true);

  -- Explicit completeness makes the source safely freezable.
  foreach v_domain in array enum_range(null::public.student_data_domain) loop
    if v_domain in (
      'EDUCATION_HISTORY', 'TEST_HISTORY', 'COURSE_HISTORY',
      'COURSE_MAPPING', 'EXPERIENCE_HISTORY', 'SKILL_HISTORY',
      'PREFERENCES', 'GOALS'
    ) then
      insert into public.student_data_completeness (
        profile_version_id, domain, completeness
      ) values (v_profile, v_domain, 'COMPLETE');
    end if;
  end loop;
  execute 'set local role foundation_student_executor';
  perform public.freeze_student_profile_version(v_profile);
  execute 'reset role';

  select encode(extensions.digest(convert_to(jsonb_build_object(
    'tests', coalesce((
      select jsonb_agg(to_jsonb(score) order by score.student_test_score_id)
      from public.student_test_scores score
      where score.profile_version_id = v_profile
    ), '[]'::jsonb),
    'skills', coalesce((
      select jsonb_agg(to_jsonb(skill) order by skill.student_skill_id)
      from public.student_skills skill
      where skill.profile_version_id = v_profile
    ), '[]'::jsonb)
  )::text, 'UTF8'), 'sha256'), 'hex')
  into v_before_hash;

  -- Retire the referenced assessment/skill at the next VERIFIED release.
  execute 'set local role foundation_catalog_executor';
  perform public.create_taxonomy_release(
    'v9.8', '2026-08-30T00:00:00Z', 'Phase 024 retirement fixture'
  );
  perform public.retire_taxonomy_concept(
    v_assessment, 'v9.8', 'Phase 024 historical assessment fixture'
  );
  perform public.retire_taxonomy_concept(
    v_skill, 'v9.8', 'Phase 024 historical skill fixture'
  );
  perform public.verify_taxonomy_release('v9.8', 'PHASE024_TEST');
  execute 'reset role';

  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  execute 'set local role authenticated';
  v_result := public.fork_frozen_profile_to_draft_v020(
    v_profile, extensions.gen_random_uuid()
  );
  v_fork := (v_result ->> 'profileVersionId')::uuid;
  v_projection := public.get_profile_taxonomy_projection_v024(v_fork);
  if not exists (
    select 1 from jsonb_array_elements(v_projection -> 'concepts') concept
    where (concept ->> 'conceptId')::uuid in (v_assessment, v_skill)
      and (concept ->> 'activeAtRelease')::boolean = false
  ) or (
    select count(*) from jsonb_array_elements(v_projection -> 'concepts') concept
    where (concept ->> 'conceptId')::uuid in (v_assessment, v_skill)
      and (concept ->> 'activeAtRelease')::boolean = false
  ) <> 2 then
    raise exception '024 historical projection did not mark both concepts inactive';
  end if;
  execute 'reset role';

  if not exists (
    select 1 from public.student_test_scores copied
    join public.student_test_scores source
      on source.profile_version_id = v_profile
      and copied.assessment_concept_id = source.assessment_concept_id
      and copied.assessment_definition_id = source.assessment_definition_id
      and copied.taxonomy_release_ordinal_at_selection =
        source.taxonomy_release_ordinal_at_selection
    where copied.profile_version_id = v_fork
      and copied.taxonomy_reference_origin = 'HISTORICAL_FORK'
  ) or not exists (
    select 1 from public.student_skills copied
    join public.student_skills source
      on source.profile_version_id = v_profile
      and copied.skill_concept_id = source.skill_concept_id
      and copied.taxonomy_release_ordinal_at_selection =
        source.taxonomy_release_ordinal_at_selection
    where copied.profile_version_id = v_fork
      and copied.taxonomy_reference_origin = 'HISTORICAL_FORK'
  ) then
    raise exception '024 trusted fork did not preserve historical pins';
  end if;
  if not exists (
    select 1 from public.student_test_scores copied
    where copied.profile_version_id = v_fork
      and copied.assessment_concept_id = v_unsupported_assessment
      and copied.assessment_definition_id is null
      and copied.taxonomy_release_ordinal_at_selection is null
      and copied.taxonomy_reference_origin is null
  ) then
    raise exception '024 legacy NULL-definition row was reinterpreted';
  end if;

  select encode(extensions.digest(convert_to(jsonb_build_object(
    'tests', coalesce((
      select jsonb_agg(to_jsonb(score) order by score.student_test_score_id)
      from public.student_test_scores score
      where score.profile_version_id = v_profile
    ), '[]'::jsonb),
    'skills', coalesce((
      select jsonb_agg(to_jsonb(skill) order by skill.student_skill_id)
      from public.student_skills skill
      where skill.profile_version_id = v_profile
    ), '[]'::jsonb)
  )::text, 'UTF8'), 'sha256'), 'hex')
  into v_after_hash;
  if v_after_hash is distinct from v_before_hash then
    raise exception '024 fork changed the FROZEN source graph';
  end if;

  select score.student_test_score_id, score.student_evidence_id
  into strict v_copied_test_id, v_copied_evidence
  from public.student_test_scores score
  where score.profile_version_id = v_fork
    and score.assessment_concept_id = v_assessment;
  select skill.student_skill_id into strict v_copied_skill_id
  from public.student_skills skill
  where skill.profile_version_id = v_fork
    and skill.skill_concept_id = v_skill;

  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_fork, extensions.gen_random_uuid(), 0, 'TEST_SCORE_UPDATE',
      jsonb_build_object(
        'testScoreId', v_copied_test_id,
        'assessmentConceptId', v_assessment, 'testDate', '2026-01-01',
        'totalScore', 702, 'sectionScores', jsonb_build_object(),
        'evidenceId', v_copied_evidence
      )
    );
  exception when object_not_in_prerequisite_state then
    v_blocked := sqlerrm = 'PROFILE_TAXONOMY_CONCEPT_INACTIVE';
  end;
  if not v_blocked then
    raise exception '024 changed a copied inactive assessment';
  end if;
  v_blocked := false;
  begin
    perform public.mutate_profile_draft_v019(
      v_fork, extensions.gen_random_uuid(), 0, 'SKILL_UPDATE',
      jsonb_build_object(
        'skillId', v_copied_skill_id, 'skillConceptId', v_skill,
        'proficiencyLevel', 5, 'yearsExperience', 3,
        'evidenceId', v_copied_evidence
      )
    );
  exception when object_not_in_prerequisite_state then
    v_blocked := sqlerrm = 'PROFILE_TAXONOMY_CONCEPT_INACTIVE';
  end;
  if not v_blocked then raise exception '024 changed a copied inactive skill'; end if;
  perform public.mutate_profile_draft_v019(
    v_fork, extensions.gen_random_uuid(), 0, 'TEST_SCORE_DELETE',
    jsonb_build_object('testScoreId', v_copied_test_id)
  );
  perform public.mutate_profile_draft_v019(
    v_fork, extensions.gen_random_uuid(), 1, 'SKILL_DELETE',
    jsonb_build_object('skillId', v_copied_skill_id)
  );
  execute 'reset role';
  if not exists (
    select 1 from public.student_test_scores
    where profile_version_id = v_profile
      and assessment_concept_id = v_assessment
  ) or not exists (
    select 1 from public.student_skills
    where profile_version_id = v_profile and skill_concept_id = v_skill
  ) then
    raise exception '024 historical delete changed the FROZEN source';
  end if;

  -- Unrelated owner cannot project the fork.
  perform set_config('request.jwt.claim.sub', v_other_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.get_profile_taxonomy_projection_v024(v_fork);
  exception when no_data_found then
    v_blocked := sqlerrm = 'PROFILE_NOT_FOUND';
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception '024 unrelated user projected another Profile';
  end if;

  -- Student privacy deletion removes pins/fork state but retains catalog data.
  execute 'set local role foundation_student_executor';
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  execute 'reset role';
  if exists (
    select 1 from public.student_test_scores
    where profile_version_id in (v_profile, v_fork)
  ) or exists (
    select 1 from public.student_skills
    where profile_version_id in (v_profile, v_fork)
  ) or not exists (
    select 1 from public.profile_assessment_definitions_v024
    where assessment_definition_id = v_definition
  ) or not exists (
    select 1 from public.profile_assessment_definition_evidence_v024
    where assessment_definition_id = v_definition
  ) then
    raise exception '024 privacy closure/global catalog retention failed';
  end if;
end;
$test$;

rollback;
