\set ON_ERROR_STOP on
set search_path = public, private, extensions, pg_catalog;

-- Disposable committed fixture for multi-session visibility.
create extension if not exists dblink;
\set profile_version_id 'a3010000-0000-4000-8000-000000000021'
\i /workspace/apps/web/tests/real-local/profile-eligibility-fit.fixture.sql

insert into auth.users (id, email) values (
  'a3010000-0000-4000-8000-000000000001',
  'phase030-concurrency@test.invalid'
);
do $fixture$
declare
  v_student constant uuid := 'a3010000-0000-4000-8000-000000000011';
  v_domain public.student_data_domain;
begin
  perform public.create_student(v_student);
  insert into private.student_identities (auth_user_id, student_id) values (
    'a3010000-0000-4000-8000-000000000001', v_student
  );
  insert into public.student_profile_versions (
    profile_version_id, student_id, version_number, status,
    snapshot_hash, frozen_at, product_managed, profile_revision
  ) values (
    'a3010000-0000-4000-8000-000000000021', v_student, 1,
    'DRAFT', null, null, true, 0
  );
  foreach v_domain in array enum_range(null::public.student_data_domain)
  loop
    insert into public.student_data_completeness (
      profile_version_id, education_context_id, domain, completeness
    ) values (
      'a3010000-0000-4000-8000-000000000021', null,
      v_domain, 'COMPLETE'
    );
  end loop;
  perform set_config(
    'request.jwt.claim.sub',
    'a3010000-0000-4000-8000-000000000001', true
  );
  execute 'set local role authenticated';
  perform public.freeze_profile_draft_v019(
    'a3010000-0000-4000-8000-000000000021',
    'a3010000-0000-4000-8000-000000000031', 0
  );
  execute 'reset role';
end;
$fixture$;

do $race$
declare
  v_auth constant uuid := 'a3010000-0000-4000-8000-000000000001';
  v_profile constant uuid := 'a3010000-0000-4000-8000-000000000021';
  v_operation constant uuid := 'a3010000-0000-4000-8000-000000000101';
  v_program uuid;
  v_connection text := 'dbname=' || current_database();
  v_first text;
  v_second text;
begin
  select program_version_id into strict v_program
  from public.program_requirement_rule_sets
  where rule_set_id = '4b400000-0000-4000-8000-000000000030';
  perform dblink_connect('p30_first', v_connection);
  perform dblink_connect('p30_second', v_connection);
  perform dblink_exec('p30_first', 'begin');
  perform dblink_exec('p30_second', 'begin');
  perform * from dblink('p30_first', format(
    'select set_config(''request.jwt.claim.sub'',%L,true)', v_auth
  )) as configured(value text);
  perform * from dblink('p30_second', format(
    'select set_config(''request.jwt.claim.sub'',%L,true)', v_auth
  )) as configured(value text);
  perform dblink_exec('p30_first', 'set local role authenticated');
  perform dblink_exec('p30_second', 'set local role authenticated');
  perform dblink_send_query('p30_first', format(
    $$select public.assemble_eligibility_evaluation_v030(%L,%L,%L)::text$$,
    v_profile, v_program, v_operation
  ));
  perform pg_sleep(0.1);
  perform dblink_send_query('p30_second', format(
    $$select public.assemble_eligibility_evaluation_v030(%L,%L,%L)::text$$,
    v_profile, v_program, v_operation
  ));
  perform pg_sleep(0.2);
  if dblink_is_busy('p30_second') <> 1 then
    raise exception '030 concurrent exact replay did not serialize';
  end if;
  select result into v_first from dblink_get_result('p30_first')
    as result(result text);
  perform count(*) from dblink_get_result('p30_first') as result(result text);
  perform dblink_exec('p30_first', 'commit');
  select result into v_second from dblink_get_result('p30_second')
    as result(result text);
  perform count(*) from dblink_get_result('p30_second') as result(result text);
  perform dblink_exec('p30_second', 'commit');
  perform dblink_disconnect('p30_first');
  perform dblink_disconnect('p30_second');
  if v_first::jsonb is distinct from v_second::jsonb
     or (select count(*) from private.eligibility_degree_operations_v030
         where operation_id = v_operation) <> 1
     or (select count(*) from public.eligibility_evaluations
         where profile_version_id = v_profile
           and input_schema_version = 'eligibility-degree-v1') <> 1 then
    raise exception '030 concurrent exact replay duplicated or diverged';
  end if;
end;
$race$;

do $cleanup$
begin
  execute 'set local role service_role';
  perform public.delete_student_data(
    'a3010000-0000-4000-8000-000000000011', 'TEST_LIFECYCLE'
  );
  execute 'reset role';
  delete from auth.users
  where id = 'a3010000-0000-4000-8000-000000000001';
end;
$cleanup$;

select 'PHASE030_DEGREE_CONCURRENCY_PASS';
