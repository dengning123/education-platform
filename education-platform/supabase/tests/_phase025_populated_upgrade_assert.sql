-- Run after the Phase 025 populated fixture and Migration 025.

begin;

do $assert$
declare
  v_result jsonb;
  v_hash text;
begin
  select encode(extensions.digest(convert_to(coalesce(jsonb_agg(
    to_jsonb(profile) order by profile.version_number
  )::text, '[]'), 'UTF8'), 'sha256'), 'hex')
  into v_hash
  from public.student_profile_versions profile
  where profile.student_id = '96520000-0000-4000-8000-000000000011';

  if v_hash is distinct from (
    select expected.profile_rows_hash
    from private.phase025_populated_upgrade_expected expected
    where expected.student_id = '96520000-0000-4000-8000-000000000011'
  ) or (select count(*) from private.profile_capability_operations_v019 operation
        where operation.student_id =
          '96520000-0000-4000-8000-000000000011') <> (
    select expected.operation_count
    from private.phase025_populated_upgrade_expected expected
    where expected.student_id = '96520000-0000-4000-8000-000000000011'
  ) then
    raise exception '025 populated upgrade changed Profile state';
  end if;

  perform set_config(
    'request.jwt.claim.sub',
    '96520000-0000-4000-8000-000000000001', true
  );
  execute 'set local role authenticated';
  v_result := public.get_latest_frozen_profile_v025();
  execute 'reset role';
  if (v_result ->> 'profileVersionId')::uuid <>
       '96520000-0000-4000-8000-000000000022'::uuid
     or (v_result ->> 'versionNumber')::integer <> 2 then
    raise exception '025 populated latest-FROZEN selection failed';
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(
    '96520000-0000-4000-8000-000000000011', 'TEST_LIFECYCLE'
  );
  execute 'reset role';
  delete from auth.users
  where id = '96520000-0000-4000-8000-000000000001';
end;
$assert$;

drop table private.phase025_populated_upgrade_expected;

commit;
