-- Run after _phase022_populated_upgrade_fixture.sql and Migration 022.

begin;

do $test$
declare
  v_result jsonb;
begin
  if not exists (
    select 1
    from public.student_profile_versions profile
    where profile.profile_version_id =
        '96100000-0000-4000-8000-000000000021'
      and profile.student_id = '96100000-0000-4000-8000-000000000011'
      and profile.version_number = 1
      and profile.status = 'DRAFT'
      and profile.product_managed
      and profile.profile_revision = 3
  ) or (
    select count(*)
    from public.student_record_concept_mappings mapping
    where mapping.profile_version_id =
      '96100000-0000-4000-8000-000000000021'
  ) <> 1 then
    raise exception '022 populated upgrade changed the existing Profile graph';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    '96100000-0000-4000-8000-000000000001',
    true
  );
  execute 'set local role authenticated';
  v_result := public.get_profile_taxonomy_projection_v022(null);
  execute 'reset role';

  if v_result ->> 'schemaVersion' <>
       'PROFILE_TAXONOMY_PROJECTION_V022'
     or v_result ->> 'releaseCode' <> 'v0.1'
     or (v_result ->> 'releaseOrdinal')::bigint <> 1
     or jsonb_array_length(v_result -> 'concepts') <> 1 then
    raise exception '022 populated upgrade projection contract failed';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_result -> 'concepts') concept
    where concept ->> 'conceptKind' not in ('FIELD', 'SUBFIELD')
       or (concept ->> 'activeAtRelease')::boolean is not true
  ) then
    raise exception '022 populated upgrade projected an invalid concept';
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(
    '96100000-0000-4000-8000-000000000011',
    'TEST_LIFECYCLE'
  );
  execute 'reset role';
end;
$test$;

commit;
