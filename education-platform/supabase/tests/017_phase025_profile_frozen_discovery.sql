-- Run after Migration 025 Profile latest-FROZEN discovery.

begin;

do $test$
declare
  v_owner_auth constant uuid := '96510000-0000-4000-8000-000000000001';
  v_owner_student constant uuid := '96510000-0000-4000-8000-000000000011';
  v_other_auth constant uuid := '96510000-0000-4000-8000-000000000002';
  v_other_student constant uuid := '96510000-0000-4000-8000-000000000012';
  v_latest_profile constant uuid := '96510000-0000-4000-8000-000000000023';
  v_result jsonb;
  v_before_profiles bigint;
  v_before_operations bigint;
  v_blocked boolean;
begin
  if to_regprocedure('public.get_latest_frozen_profile_v025()') is null then
    raise exception '025 discovery capability is missing';
  end if;
  if not has_function_privilege(
    'authenticated', 'public.get_latest_frozen_profile_v025()', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.get_latest_frozen_profile_v025()', 'EXECUTE'
  ) or has_function_privilege(
    'service_role', 'public.get_latest_frozen_profile_v025()', 'EXECUTE'
  ) then
    raise exception '025 discovery ACL is not closed';
  end if;
  if has_table_privilege(
    'authenticated', 'public.student_profile_versions',
    'INSERT,UPDATE,DELETE'
  ) then
    raise exception '025 expanded direct Profile DML';
  end if;

  insert into auth.users (id, email) values
    (v_owner_auth, 'phase025-owner@test.invalid'),
    (v_other_auth, 'phase025-other@test.invalid');
  perform public.create_student(v_owner_student);
  perform public.create_student(v_other_student);
  insert into private.student_identities (auth_user_id, student_id) values
    (v_owner_auth, v_owner_student),
    (v_other_auth, v_other_student);

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.get_latest_frozen_profile_v025();
  exception when no_data_found then
    v_blocked := sqlerrm = 'PROFILE_NOT_FOUND';
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception '025 no-FROZEN contract did not fail closed';
  end if;

  insert into public.student_profile_versions (
    profile_version_id, student_id, version_number, status,
    snapshot_hash, frozen_at, product_managed, profile_revision
  ) values
    ('96510000-0000-4000-8000-000000000021', v_owner_student, 1,
     'FROZEN', repeat('a', 64), '2026-08-20T00:00:00Z', true, 4),
    (v_latest_profile, v_owner_student, 3,
     'FROZEN', repeat('b', 64), '2026-08-22T00:00:00Z', true, 9),
    ('96510000-0000-4000-8000-000000000024', v_owner_student, 4,
     'DRAFT', null, null, false, 0),
    ('96510000-0000-4000-8000-000000000025', v_other_student, 9,
     'FROZEN', repeat('c', 64), '2026-08-24T00:00:00Z', true, 2);

  select count(*) into v_before_profiles
  from public.student_profile_versions
  where student_id = v_owner_student;
  select count(*) into v_before_operations
  from private.profile_capability_operations_v019
  where student_id = v_owner_student;

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_result := public.get_latest_frozen_profile_v025();
  execute 'reset role';

  if (select array_agg(key order by key) from jsonb_object_keys(v_result) key)
       is distinct from array[
         'frozenAt', 'profileVersionId', 'schemaVersion', 'status',
         'versionNumber'
       ]::text[]
     or v_result ->> 'schemaVersion' <> 'PROFILE_FROZEN_DISCOVERY_V025'
     or (v_result ->> 'profileVersionId')::uuid <> v_latest_profile
     or (v_result ->> 'versionNumber')::integer <> 3
     or v_result ->> 'status' <> 'FROZEN'
     or (v_result ->> 'frozenAt')::timestamptz <>
       '2026-08-22T00:00:00Z'::timestamptz then
    raise exception '025 latest-FROZEN DTO/order contract failed';
  end if;
  if v_result ?| array[
    'studentId', 'authUserId', 'snapshotHash', 'reviewedBy', 'children',
    'metadata'
  ] then
    raise exception '025 discovery leaked an excluded field';
  end if;
  if (select count(*) from public.student_profile_versions
      where student_id = v_owner_student) <> v_before_profiles
     or (select count(*) from private.profile_capability_operations_v019
         where student_id = v_owner_student) <> v_before_operations then
    raise exception '025 discovery created student-linked durable state';
  end if;

  perform set_config('request.jwt.claim.sub', v_other_auth::text, true);
  execute 'set local role authenticated';
  v_result := public.get_latest_frozen_profile_v025();
  execute 'reset role';
  if (v_result ->> 'profileVersionId')::uuid = v_latest_profile
     or (v_result ->> 'profileVersionId')::uuid <>
       '96510000-0000-4000-8000-000000000025'::uuid then
    raise exception '025 unrelated subject enumerated owner frozen state';
  end if;

  v_blocked := false;
  begin
    execute 'set local role anon';
    perform public.get_latest_frozen_profile_v025();
  exception when insufficient_privilege then
    v_blocked := true;
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception '025 anonymous discovery was accepted';
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(v_owner_student, 'TEST_LIFECYCLE');
  perform public.delete_student_data(v_other_student, 'TEST_LIFECYCLE');
  execute 'reset role';
  delete from auth.users where id in (v_owner_auth, v_other_auth);

  if exists (
    select 1 from public.student_profile_versions
    where student_id in (v_owner_student, v_other_student)
  ) or exists (
    select 1 from private.profile_capability_operations_v019
    where student_id in (v_owner_student, v_other_student)
  ) or exists (
    select 1 from private.student_identities
    where student_id in (v_owner_student, v_other_student)
  ) then
    raise exception '025 privacy deletion retained Profile lifecycle state';
  end if;
end;
$test$;

rollback;
