-- Run after _phase024_populated_upgrade_fixture.sql and Migration 024.

begin;

do $test$
declare
  v_document jsonb;
  v_hash text;
begin
  if not exists (
    select 1 from public.student_test_scores score
    where score.student_test_score_id =
        '96410000-0000-4000-8000-000000000041'
      and score.assessment_definition_id is null
      and score.taxonomy_release_ordinal_at_selection is null
      and score.taxonomy_reference_origin is null
  ) or not exists (
    select 1 from public.student_skills skill
    where skill.student_skill_id =
        '96410000-0000-4000-8000-000000000051'
      and skill.taxonomy_release_ordinal_at_selection is null
      and skill.taxonomy_reference_origin is null
  ) then
    raise exception '024 populated legacy rows were reinterpreted';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    '96410000-0000-4000-8000-000000000001', true
  );
  execute 'set local role authenticated';
  v_document := public.get_profile_document_v019(
    '96410000-0000-4000-8000-000000000021'
  );
  execute 'reset role';
  v_hash := encode(extensions.digest(
    convert_to(v_document::text, 'UTF8'), 'sha256'
  ), 'hex');
  if v_hash is distinct from (
    select expected.profile_document_hash
    from private.phase024_populated_upgrade_expected expected
    where expected.profile_version_id =
      '96410000-0000-4000-8000-000000000021'
  ) then
    raise exception '024 changed the frozen Profile document identity';
  end if;

  if exists (
    select 1 from public.profile_assessment_definitions_v024
  ) then
    raise exception '024 populated upgrade seeded assessment authority';
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(
    '96410000-0000-4000-8000-000000000011', 'TEST_LIFECYCLE'
  );
  execute 'reset role';
  delete from auth.users
  where id = '96410000-0000-4000-8000-000000000001';
end;
$test$;

drop table private.phase024_populated_upgrade_expected;

commit;
