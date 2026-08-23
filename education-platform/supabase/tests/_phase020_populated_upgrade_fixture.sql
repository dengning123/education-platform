\set ON_ERROR_STOP on

-- Run after Migration 019 and before Migration 020 on a disposable database.
-- Commits a populated historical FROZEN graph.

begin;
insert into auth.users (id, email) values (
  '97000000-0000-0000-0000-000000000001',
  'phase020-upgrade@test.invalid'
);
select public.create_student('97000000-0000-0000-0000-000000000011');
insert into private.student_identities (auth_user_id, student_id) values (
  '97000000-0000-0000-0000-000000000001',
  '97000000-0000-0000-0000-000000000011'
);

do $fixture$
declare
  v_profile uuid;
  v_evidence uuid;
  v_degree uuid;
  v_domain public.student_data_domain;
begin
  v_profile := public.create_student_profile_version(
    '97000000-0000-0000-0000-000000000011', 1
  );
  insert into public.student_evidence_items (
    profile_version_id, evidence_type, locator, metadata
  ) values (
    v_profile, 'SELF_REPORT', 'upgrade-source',
    jsonb_build_object('legacyControl', true)
  ) returning student_evidence_id into v_evidence;
  insert into public.student_degrees (
    profile_version_id, institution_name, degree_name,
    degree_level, degree_status, student_evidence_id
  ) values (
    v_profile, 'Upgrade University', 'BSc Economics',
    'BACHELORS', 'COMPLETED', v_evidence
  ) returning student_degree_id into v_degree;
  foreach v_domain in array array[
    'EDUCATION_HISTORY','TEST_HISTORY','EXPERIENCE_HISTORY','SKILL_HISTORY',
    'PREFERENCES','GOALS'
  ]::public.student_data_domain[]
  loop
    insert into public.student_data_completeness (
      profile_version_id, domain, completeness
    ) values (v_profile, v_domain, 'COMPLETE');
  end loop;
  foreach v_domain in array array[
    'COURSE_HISTORY','COURSE_MAPPING'
  ]::public.student_data_domain[]
  loop
    insert into public.student_data_completeness (
      profile_version_id, education_context_id, domain, completeness
    ) values (v_profile, v_degree, v_domain, 'COMPLETE');
  end loop;
  perform public.freeze_student_profile_version(v_profile);
end;
$fixture$;
commit;
