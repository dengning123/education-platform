-- Runs after Migration 022. Application/Outcome remains planning-only under
-- a provisional future Migration 023 identity.

begin;

do $test$
declare
  v_owner_auth constant uuid := '96000000-0000-4000-8000-000000000001';
  v_other_auth constant uuid := '96000000-0000-4000-8000-000000000002';
  v_owner_student constant uuid := '96000000-0000-4000-8000-000000000011';
  v_other_student constant uuid := '96000000-0000-4000-8000-000000000012';
  v_owner_profile uuid;
  v_other_profile uuid;
  v_owner_evidence uuid;
  v_degree_id uuid;
  v_course_id uuid;
  v_retired_field_id uuid;
  v_active_field_id uuid;
  v_course_concept_id constant uuid := '96000000-0000-4000-8000-000000000021';
  v_arbitrary_concept_id constant uuid := '96000000-0000-4000-8000-000000000022';
  v_draft_concept_id constant uuid := '96000000-0000-4000-8000-000000000023';
  v_skill_concept_id uuid;
  v_assessment_concept_id uuid;
  v_career_concept_id uuid;
  v_result jsonb;
  v_explicit jsonb;
  v_other_result jsonb;
  v_keys text[];
  v_order text[];
  v_sorted text[];
  v_blocked boolean;
  v_function_oid oid;
begin
  perform set_config('statement_timeout', '30s', true);

  select procedure.oid
  into strict v_function_oid
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'get_profile_taxonomy_projection_v022'
    and pg_get_function_identity_arguments(procedure.oid) =
      'p_profile_version_id uuid';

  if exists (
    select 1
    from unnest(coalesce((select procedure.proargnames from pg_proc procedure
      where procedure.oid = v_function_oid), array[]::text[])) argument_name
    where argument_name in ('student_id', 'p_student_id', 'concept_ids', 'p_concept_ids')
  ) then
    raise exception '022 projection accepts caller-supplied ownership or concept enumeration';
  end if;

  if has_table_privilege('authenticated', 'public.taxonomy_releases', 'SELECT')
     or has_table_privilege('authenticated', 'public.taxonomy_concepts', 'SELECT')
     or has_table_privilege('authenticated', 'public.taxonomy_aliases', 'SELECT')
     or has_table_privilege('authenticated', 'public.taxonomy_relationships', 'SELECT') then
    raise exception '022 expanded direct authenticated taxonomy table access';
  end if;

  v_blocked := false;
  begin
    execute 'set local role anon';
    perform public.get_profile_taxonomy_projection_v022(null);
  exception when insufficient_privilege then
    v_blocked := true;
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception 'Anonymous taxonomy projection was not rejected';
  end if;

  select concept_id into strict v_retired_field_id
  from public.taxonomy_concepts
  where concept_kind in ('FIELD', 'SUBFIELD')
    and retired_release_ordinal is null
  order by canonical_key, concept_id
  limit 1;
  select concept_id into strict v_active_field_id
  from public.taxonomy_concepts
  where concept_kind in ('FIELD', 'SUBFIELD')
    and retired_release_ordinal is null
    and concept_id <> v_retired_field_id
  order by canonical_key, concept_id
  limit 1;
  select concept_id into strict v_skill_concept_id
  from public.taxonomy_concepts
  where concept_kind = 'SKILL' and retired_release_ordinal is null
  order by canonical_key, concept_id limit 1;
  select concept_id into strict v_assessment_concept_id
  from public.taxonomy_concepts
  where concept_kind = 'ASSESSMENT' and retired_release_ordinal is null
  order by canonical_key, concept_id limit 1;
  select concept_id into strict v_career_concept_id
  from public.taxonomy_concepts
  where concept_kind = 'CAREER' and retired_release_ordinal is null
  order by canonical_key, concept_id limit 1;

  execute 'set local role foundation_catalog_executor';
  perform public.create_taxonomy_release(
    'v0.2', '2026-08-23T00:00:00Z', 'Phase 022 verified-release fixture'
  );
  perform public.create_taxonomy_concept(jsonb_populate_record(
    null::public.taxonomy_concepts,
    jsonb_build_object(
      'concept_id', v_course_concept_id,
      'canonical_key', 'COURSE_CONCEPT.PHASE022_ACTIVE',
      'concept_kind', 'COURSE_CONCEPT',
      'display_name', 'Phase 022 Active Course Concept',
      'description', 'Must never cross the projection DTO.',
      'introduced_in_release', 'v0.2'
    )
  ));
  perform public.create_taxonomy_concept(jsonb_populate_record(
    null::public.taxonomy_concepts,
    jsonb_build_object(
      'concept_id', v_arbitrary_concept_id,
      'canonical_key', 'FIELD.PHASE022_UNREFERENCED',
      'concept_kind', 'FIELD',
      'display_name', 'Unreferenced Field',
      'description', 'Must not be enumerable.',
      'introduced_in_release', 'v0.2'
    )
  ));
  perform public.retire_taxonomy_concept(
    v_retired_field_id, 'v0.2', 'Phase 022 historical-label fixture'
  );
  perform public.verify_taxonomy_release('v0.2', 'PHASE022_TEST');

  perform public.create_taxonomy_release(
    'v0.3', '2026-08-24T00:00:00Z', 'Phase 022 DRAFT fixture'
  );
  perform public.create_taxonomy_concept(jsonb_populate_record(
    null::public.taxonomy_concepts,
    jsonb_build_object(
      'concept_id', v_draft_concept_id,
      'canonical_key', 'FIELD.PHASE022_DRAFT_ONLY',
      'concept_kind', 'FIELD',
      'display_name', 'Draft-only Field',
      'introduced_in_release', 'v0.3'
    )
  ));
  perform public.create_taxonomy_release(
    'v0.4', '2026-08-25T00:00:00Z', 'Phase 022 RETIRED fixture'
  );
  perform public.verify_taxonomy_release('v0.4', 'PHASE022_TEST');
  perform public.retire_taxonomy_release('v0.4', 'Phase 022 retired release fixture');
  execute 'reset role';

  insert into auth.users (id, email) values
    (v_owner_auth, 'phase022-owner@test.invalid'),
    (v_other_auth, 'phase022-other@test.invalid');
  perform public.create_student(v_owner_student);
  perform public.create_student(v_other_student);
  insert into private.student_identities (auth_user_id, student_id) values
    (v_owner_auth, v_owner_student),
    (v_other_auth, v_other_student);

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_owner_profile := (
    public.create_or_resume_profile_draft_v019(
      '96000000-0000-4000-8000-000000000101'
    ) ->> 'profileVersionId'
  )::uuid;
  execute 'reset role';

  insert into public.student_evidence_items (
    profile_version_id, evidence_type, locator
  ) values (
    v_owner_profile, 'SELF_REPORT', 'phase022-owner-source'
  ) returning student_evidence_id into v_owner_evidence;
  insert into public.student_degrees (
    profile_version_id, institution_name, degree_name, degree_level,
    degree_status, student_evidence_id
  ) values (
    v_owner_profile, 'Projection University', 'BSc Economics', 'BACHELORS',
    'COMPLETED', v_owner_evidence
  ) returning student_degree_id into v_degree_id;
  insert into public.student_courses (
    profile_version_id, student_degree_id, course_title, course_status,
    student_evidence_id
  ) values (
    v_owner_profile, v_degree_id, 'Projection Course', 'COMPLETED',
    v_owner_evidence
  ) returning student_course_id into v_course_id;

  insert into public.student_record_concept_mappings (
    profile_version_id, record_type, student_record_id, concept_id,
    mapping_status, method
  ) values
    (v_owner_profile, 'DEGREE', v_degree_id, v_retired_field_id, 'PROPOSED', 'HUMAN'),
    (v_owner_profile, 'DEGREE', v_degree_id, v_active_field_id, 'PROPOSED', 'HUMAN'),
    (v_owner_profile, 'COURSE', v_course_id, v_course_concept_id, 'PROPOSED', 'HUMAN');

  insert into public.student_test_scores (
    profile_version_id, assessment_concept_id, test_date, total_score,
    student_evidence_id
  ) values (
    v_owner_profile, v_assessment_concept_id, '2026-01-01', 100,
    v_owner_evidence
  );
  insert into public.student_skills (
    profile_version_id, skill_concept_id, proficiency_level,
    student_evidence_id
  ) values (
    v_owner_profile, v_skill_concept_id, 3, v_owner_evidence
  );
  insert into public.student_goals (
    profile_version_id, goal_type, concept_id, priority
  ) values (
    v_owner_profile, 'CAREER', v_career_concept_id, 1
  );

  perform set_config('request.jwt.claim.sub', v_other_auth::text, true);
  execute 'set local role authenticated';
  v_other_profile := (
    public.create_or_resume_profile_draft_v019(
      '96000000-0000-4000-8000-000000000102'
    ) ->> 'profileVersionId'
  )::uuid;
  v_other_result := public.get_profile_taxonomy_projection_v022(null);
  if v_other_result ->> 'schemaVersion' <>
       'PROFILE_TAXONOMY_PROJECTION_V022'
     or jsonb_array_length(v_other_result -> 'concepts') <> 0 then
    raise exception 'Null projection escaped the current owner DRAFT';
  end if;

  v_blocked := false;
  begin
    perform public.get_profile_taxonomy_projection_v022(v_owner_profile);
  exception when no_data_found then
    v_blocked := sqlerrm = 'PROFILE_NOT_FOUND';
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception 'Unrelated authenticated user projected an owner Profile';
  end if;

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_result := public.get_profile_taxonomy_projection_v022(null);
  v_explicit := public.get_profile_taxonomy_projection_v022(v_owner_profile);
  execute 'reset role';

  if v_result is distinct from v_explicit then
    raise exception 'Null and explicit owner projection diverged';
  end if;
  if v_result ->> 'schemaVersion' <>
       'PROFILE_TAXONOMY_PROJECTION_V022'
     or v_result ->> 'releaseCode' <> 'v0.2'
     or (v_result ->> 'releaseOrdinal')::bigint <> (
       select release_ordinal from public.taxonomy_releases
       where release_code = 'v0.2'
     ) then
    raise exception 'Highest VERIFIED release selection is incorrect';
  end if;
  if jsonb_array_length(v_result -> 'concepts') <> 3 then
    raise exception 'Projection returned unreferenced or disallowed concepts';
  end if;

  select array_agg(key order by key) into v_keys
  from jsonb_object_keys(v_result) key;
  if v_keys is distinct from array[
    'concepts', 'releaseCode', 'releaseOrdinal', 'schemaVersion'
  ]::text[] then
    raise exception 'Projection top-level DTO keys are not closed';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(v_result -> 'concepts') concept,
         lateral (
           select array_agg(key order by key) as keys
           from jsonb_object_keys(concept) key
         ) shape
    where shape.keys is distinct from array[
      'activeAtRelease', 'canonicalKey', 'conceptId', 'conceptKind',
      'displayName'
    ]::text[]
  ) then
    raise exception 'Projection concept DTO keys are not closed';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(v_result -> 'concepts') concept
    where concept ?| array[
      'description', 'aliases', 'relationships', 'reviewedBy', 'studentId',
      'authUserId'
    ]
  ) then
    raise exception 'Projection leaked catalog, review, or ownership fields';
  end if;

  select array_agg(concept ->> 'canonicalKey') into v_order
  from jsonb_array_elements(v_result -> 'concepts') concept;
  select array_agg(value order by value) into v_sorted
  from unnest(v_order) value;
  if v_order is distinct from v_sorted then
    raise exception 'Projection ordering is not deterministic';
  end if;

  if not exists (
    select 1 from jsonb_array_elements(v_result -> 'concepts') concept
    where (concept ->> 'conceptId')::uuid = v_retired_field_id
      and (concept ->> 'activeAtRelease')::boolean is false
  ) or not exists (
    select 1 from jsonb_array_elements(v_result -> 'concepts') concept
    where (concept ->> 'conceptId')::uuid = v_active_field_id
      and (concept ->> 'activeAtRelease')::boolean is true
  ) or not exists (
    select 1 from jsonb_array_elements(v_result -> 'concepts') concept
    where (concept ->> 'conceptId')::uuid = v_course_concept_id
      and concept ->> 'canonicalKey' = 'COURSE_CONCEPT.PHASE022_ACTIVE'
      and concept ->> 'conceptKind' = 'COURSE_CONCEPT'
      and concept ->> 'displayName' = 'Phase 022 Active Course Concept'
      and (concept ->> 'activeAtRelease')::boolean is true
  ) then
    raise exception 'Active/historical interval or canonical projection is incorrect';
  end if;

  if exists (
    select 1 from jsonb_array_elements(v_result -> 'concepts') concept
    where (concept ->> 'conceptId')::uuid in (
      v_arbitrary_concept_id, v_draft_concept_id, v_skill_concept_id,
      v_assessment_concept_id, v_career_concept_id
    )
       or concept ->> 'conceptKind' not in (
         'FIELD', 'SUBFIELD', 'COURSE_CONCEPT'
       )
  ) then
    raise exception 'Projection enabled enumeration or a disallowed concept kind';
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(v_owner_student, 'TEST_LIFECYCLE');
  perform public.delete_student_data(v_other_student, 'TEST_LIFECYCLE');
  execute 'reset role';

  if exists (
    select 1 from public.student_profile_versions
    where profile_version_id in (v_owner_profile, v_other_profile)
  ) or exists (
    select 1 from private.student_identities
    where student_id in (v_owner_student, v_other_student)
  ) then
    raise exception 'Privacy deletion retained Profile state after projection use';
  end if;
end;
$test$;

rollback;
