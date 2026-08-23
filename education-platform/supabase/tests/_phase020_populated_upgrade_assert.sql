\set ON_ERROR_STOP on

-- Run after Migration 020 on the paired populated Migration 019 fixture.

do $assert$
declare
  v_student constant uuid := '97000000-0000-0000-0000-000000000011';
  v_auth constant uuid := '97000000-0000-0000-0000-000000000001';
  v_source uuid;
  v_target uuid;
  v_source_degree uuid;
  v_target_degree uuid;
  v_source_hash text;
  v_after_hash text;
  v_result jsonb;
begin
  select profile_version_id into strict v_source
  from public.student_profile_versions
  where student_id = v_student and version_number = 1 and status = 'FROZEN';
  select student_degree_id into strict v_source_degree
  from public.student_degrees where profile_version_id = v_source;
  select encode(extensions.digest(convert_to(jsonb_build_object(
    'profile', (select to_jsonb(row_value) from public.student_profile_versions row_value where row_value.profile_version_id = v_source),
    'evidence', (select jsonb_agg(to_jsonb(row_value) order by row_value.student_evidence_id) from public.student_evidence_items row_value where row_value.profile_version_id = v_source),
    'degrees', (select jsonb_agg(to_jsonb(row_value) order by row_value.student_degree_id) from public.student_degrees row_value where row_value.profile_version_id = v_source),
    'completeness', (select jsonb_agg(to_jsonb(row_value) order by row_value.completeness_id) from public.student_data_completeness row_value where row_value.profile_version_id = v_source)
  )::text, 'UTF8'), 'sha256'), 'hex') into v_source_hash;

  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  execute 'set local role authenticated';
  v_result := public.fork_frozen_profile_to_draft_v020(
    v_source, '97000000-0000-0000-0000-000000000101'
  );
  execute 'reset role';
  v_target := (v_result ->> 'profileVersionId')::uuid;

  if (v_result ->> 'versionNumber')::integer <> 2
     or not exists (
       select 1 from public.student_profile_versions
       where profile_version_id = v_target
         and student_id = v_student
         and product_managed and status = 'DRAFT'
         and profile_revision = 0
     ) then
    raise exception '020 populated upgrade allocated an invalid target';
  end if;
  select student_degree_id into strict v_target_degree
  from public.student_degrees where profile_version_id = v_target;
  if v_target_degree = v_source_degree
     or (select count(*) from public.student_data_completeness
         where profile_version_id = v_target) <> 8
     or exists (
       select 1 from public.student_data_completeness
       where profile_version_id = v_target
         and education_context_id is not null
         and education_context_id <> v_target_degree
     )
     or (select metadata from public.student_evidence_items
         where profile_version_id = v_target) <> '{}'::jsonb then
    raise exception '020 populated upgrade did not remap the graph safely';
  end if;

  select encode(extensions.digest(convert_to(jsonb_build_object(
    'profile', (select to_jsonb(row_value) from public.student_profile_versions row_value where row_value.profile_version_id = v_source),
    'evidence', (select jsonb_agg(to_jsonb(row_value) order by row_value.student_evidence_id) from public.student_evidence_items row_value where row_value.profile_version_id = v_source),
    'degrees', (select jsonb_agg(to_jsonb(row_value) order by row_value.student_degree_id) from public.student_degrees row_value where row_value.profile_version_id = v_source),
    'completeness', (select jsonb_agg(to_jsonb(row_value) order by row_value.completeness_id) from public.student_data_completeness row_value where row_value.profile_version_id = v_source)
  )::text, 'UTF8'), 'sha256'), 'hex') into v_after_hash;
  if v_after_hash <> v_source_hash then
    raise exception '020 populated upgrade mutated the source graph';
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  execute 'reset role';
  if exists (
    select 1 from private.profile_capability_operations_v019
    where student_id = v_student
  ) or exists (
    select 1 from public.student_profile_versions where student_id = v_student
  ) then
    raise exception '020 populated-upgrade cleanup retained student state';
  end if;
  delete from auth.users where id = v_auth;
end;
$assert$;
