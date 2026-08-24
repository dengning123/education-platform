-- Run after _phase023_populated_upgrade_fixture.sql and Migration 023.

begin;

do $test$
declare
  v_result jsonb;
begin
  perform set_config(
    'request.jwt.claim.sub',
    '96300000-0000-4000-8000-000000000001',
    true
  );
  execute 'set local role authenticated';
  v_result := public.get_profile_taxonomy_options_v023('ASSESSMENT');
  execute 'reset role';

  if v_result ->> 'schemaVersion' <>
       'PROFILE_TAXONOMY_OPTIONS_V023'
     or v_result ->> 'releaseCode' <> 'v0.1'
     or (v_result ->> 'releaseOrdinal')::bigint <> 1
     or v_result ->> 'conceptKind' <> 'ASSESSMENT'
     or jsonb_array_length(v_result -> 'options') <> 4 then
    raise exception '023 populated upgrade returned invalid options: %',
      v_result;
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(
    '96300000-0000-4000-8000-000000000011',
    'TEST_LIFECYCLE'
  );
  execute 'reset role';

  delete from auth.users
  where id = '96300000-0000-4000-8000-000000000001';
end;
$test$;

commit;
