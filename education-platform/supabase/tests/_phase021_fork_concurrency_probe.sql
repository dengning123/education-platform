\set ON_ERROR_STOP on
set search_path = public, private, extensions, pg_catalog;

-- Disposable multi-session probe. It commits fixtures so dblink workers can
-- observe them, then removes all Auth/student state through privacy deletion.

create extension if not exists dblink;

insert into auth.users (id, email) values (
  '96000000-0000-0000-0000-000000000001',
  'phase021-concurrency@test.invalid'
);
select public.create_student('96000000-0000-0000-0000-000000000011');
insert into private.student_identities (auth_user_id, student_id) values (
  '96000000-0000-0000-0000-000000000001',
  '96000000-0000-0000-0000-000000000011'
);

do $source_fixture$
declare
  v_profile uuid;
  v_domain public.student_data_domain;
begin
  v_profile := public.create_student_profile_version(
    '96000000-0000-0000-0000-000000000011', 1
  );
  foreach v_domain in array array[
    'EDUCATION_HISTORY','TEST_HISTORY','EXPERIENCE_HISTORY','SKILL_HISTORY',
    'PREFERENCES','GOALS','COURSE_HISTORY','COURSE_MAPPING'
  ]::public.student_data_domain[]
  loop
    insert into public.student_data_completeness (
      profile_version_id, domain, completeness
    ) values (v_profile, v_domain, 'COMPLETE');
  end loop;
  perform public.freeze_student_profile_version(v_profile);
end;
$source_fixture$;

do $same_operation_race$
declare
  v_auth constant uuid := '96000000-0000-0000-0000-000000000001';
  v_conn text := 'dbname=' || current_database();
  v_source uuid;
  v_first text;
  v_second text;
begin
  select profile_version_id into strict v_source
  from public.student_profile_versions
  where student_id = '96000000-0000-0000-0000-000000000011'
    and version_number = 1 and status = 'FROZEN';

  perform dblink_connect('p21_same_first', v_conn);
  perform dblink_connect('p21_same_second', v_conn);
  perform dblink_exec('p21_same_first', 'begin');
  perform dblink_exec('p21_same_second', 'begin');
  perform * from dblink(
    'p21_same_first',
    format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform * from dblink(
    'p21_same_second',
    format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform dblink_exec('p21_same_first', 'set local role authenticated');
  perform dblink_exec('p21_same_second', 'set local role authenticated');

  perform dblink_send_query('p21_same_first', format(
    $$select public.fork_frozen_profile_to_draft_v021(
      %L,'96000000-0000-0000-0000-000000000101'
    )::text$$, v_source
  ));
  perform pg_sleep(0.1);
  perform dblink_send_query('p21_same_second', format(
    $$select public.fork_frozen_profile_to_draft_v021(
      %L,'96000000-0000-0000-0000-000000000101'
    )::text$$, v_source
  ));
  perform pg_sleep(0.2);
  if dblink_is_busy('p21_same_second') <> 1 then
    raise exception 'Concurrent exact replay did not serialize';
  end if;

  select result into v_first
  from dblink_get_result('p21_same_first') as result(result text);
  perform count(*)
  from dblink_get_result('p21_same_first') as result(result text);
  perform dblink_exec('p21_same_first', 'commit');
  select result into v_second
  from dblink_get_result('p21_same_second') as result(result text);
  perform count(*)
  from dblink_get_result('p21_same_second') as result(result text);
  perform dblink_exec('p21_same_second', 'commit');
  perform dblink_disconnect('p21_same_first');
  perform dblink_disconnect('p21_same_second');

  if v_first::jsonb is distinct from v_second::jsonb
     or (select count(*) from public.student_profile_versions
         where student_id = '96000000-0000-0000-0000-000000000011'
           and product_managed and status = 'DRAFT') <> 1
     or (select count(*) from private.profile_capability_operations_v019
         where student_id = '96000000-0000-0000-0000-000000000011'
           and operation_kind = 'FORK_FROZEN') <> 1 then
    raise exception 'Concurrent exact fork did not converge';
  end if;
end;
$same_operation_race$;

-- Freeze the converged draft so a second independent fork race starts with no
-- active product-managed DRAFT.
do $freeze_first_fork$
declare
  v_profile uuid;
begin
  select profile_version_id into strict v_profile
  from public.student_profile_versions
  where student_id = '96000000-0000-0000-0000-000000000011'
    and product_managed and status = 'DRAFT';
  perform set_config(
    'request.jwt.claim.sub',
    '96000000-0000-0000-0000-000000000001',
    true
  );
  execute 'set local role authenticated';
  perform public.freeze_profile_draft_v019(
    v_profile, '96000000-0000-0000-0000-000000000111', 0
  );
  execute 'reset role';
end;
$freeze_first_fork$;

do $different_operation_race$
declare
  v_auth constant uuid := '96000000-0000-0000-0000-000000000001';
  v_conn text := 'dbname=' || current_database();
  v_source uuid;
  v_first text;
  v_second_blocked boolean := false;
begin
  select profile_version_id into strict v_source
  from public.student_profile_versions
  where student_id = '96000000-0000-0000-0000-000000000011'
    and product_managed and status = 'FROZEN'
  order by version_number desc limit 1;

  perform dblink_connect('p21_diff_first', v_conn);
  perform dblink_connect('p21_diff_second', v_conn);
  perform dblink_exec('p21_diff_first', 'begin');
  perform dblink_exec('p21_diff_second', 'begin');
  perform * from dblink(
    'p21_diff_first',
    format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform * from dblink(
    'p21_diff_second',
    format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform dblink_exec('p21_diff_first', 'set local role authenticated');
  perform dblink_exec('p21_diff_second', 'set local role authenticated');

  perform dblink_send_query('p21_diff_first', format(
    $$select public.fork_frozen_profile_to_draft_v021(
      %L,'96000000-0000-0000-0000-000000000201'
    )::text$$, v_source
  ));
  perform pg_sleep(0.1);
  perform dblink_send_query('p21_diff_second', format(
    $$select public.fork_frozen_profile_to_draft_v021(
      %L,'96000000-0000-0000-0000-000000000202'
    )::text$$, v_source
  ));
  perform pg_sleep(0.2);
  if dblink_is_busy('p21_diff_second') <> 1 then
    raise exception 'Concurrent independent forks did not serialize';
  end if;

  select result into v_first
  from dblink_get_result('p21_diff_first') as result(result text);
  perform count(*)
  from dblink_get_result('p21_diff_first') as result(result text);
  perform dblink_exec('p21_diff_first', 'commit');
  begin
    perform count(*)
    from dblink_get_result('p21_diff_second') as result(result text);
  exception when others then
    v_second_blocked := sqlerrm like '%PROFILE_ACTIVE_DRAFT_EXISTS%';
  end;
  perform count(*)
  from dblink_get_result('p21_diff_second') as result(result text);
  perform dblink_exec('p21_diff_second', 'rollback');
  perform dblink_disconnect('p21_diff_first');
  perform dblink_disconnect('p21_diff_second');

  if not v_second_blocked
     or v_first::jsonb ->> 'status' <> 'DRAFT'
     or (select count(*) from public.student_profile_versions
         where student_id = '96000000-0000-0000-0000-000000000011'
           and product_managed and status = 'DRAFT') <> 1
     or (select count(*) from private.profile_capability_operations_v019
         where student_id = '96000000-0000-0000-0000-000000000011'
           and operation_kind = 'FORK_FROZEN') <> 2 then
    raise exception 'Concurrent independent fork policy failed';
  end if;
end;
$different_operation_race$;

do $cleanup$
begin
  execute 'set local role service_role';
  perform public.delete_student_data(
    '96000000-0000-0000-0000-000000000011', 'TEST_LIFECYCLE'
  );
  execute 'reset role';
  if exists (
    select 1 from private.profile_capability_operations_v019
    where student_id = '96000000-0000-0000-0000-000000000011'
  ) or exists (
    select 1 from public.student_profile_versions
    where student_id = '96000000-0000-0000-0000-000000000011'
  ) then
    raise exception 'Phase 021 concurrency cleanup retained fork state';
  end if;
  delete from auth.users
  where id = '96000000-0000-0000-0000-000000000001';
end;
$cleanup$;
