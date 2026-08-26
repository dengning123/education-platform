\set ON_ERROR_STOP on
set search_path = public, private, extensions, pg_catalog;

-- Disposable multi-session race probe for the M027 active-draft and revision
-- contracts. Fixtures are committed for dblink visibility and deleted last.
create extension if not exists dblink;

insert into auth.users (id, email) values (
  'a2710000-0000-4000-8000-000000000001',
  'phase027-concurrency@test.invalid'
);

do $fixture$
declare
  v_student constant uuid := 'a2710000-0000-4000-8000-000000000011';
begin
  perform public.create_student(v_student);
  insert into private.student_identities (auth_user_id, student_id) values (
    'a2710000-0000-4000-8000-000000000001', v_student
  );
  insert into public.student_profile_versions (
    profile_version_id, student_id, version_number, status,
    snapshot_hash, frozen_at, product_managed, profile_revision
  ) values (
    'a2710000-0000-4000-8000-000000000021', v_student, 1,
    'FROZEN', repeat('a',64), now(), true, 1
  );
end;
$fixture$;

do $create_race$
declare
  v_auth constant uuid := 'a2710000-0000-4000-8000-000000000001';
  v_profile constant uuid := 'a2710000-0000-4000-8000-000000000021';
  v_conn text := 'dbname=' || current_database();
  v_first text;
  v_second text;
begin
  perform dblink_connect('p27_create_first', v_conn);
  perform dblink_connect('p27_create_second', v_conn);
  perform dblink_exec('p27_create_first', 'begin');
  perform dblink_exec('p27_create_second', 'begin');
  perform * from dblink('p27_create_first', format(
    'select set_config(''request.jwt.claim.sub'',%L,true)', v_auth
  )) as configured(value text);
  perform * from dblink('p27_create_second', format(
    'select set_config(''request.jwt.claim.sub'',%L,true)', v_auth
  )) as configured(value text);
  perform dblink_exec('p27_create_first', 'set local role authenticated');
  perform dblink_exec('p27_create_second', 'set local role authenticated');
  perform dblink_send_query('p27_create_first', format(
    $$select public.create_or_resume_fit_intent_draft_v027(
      %L,'a2710000-0000-4000-8000-000000000101'
    )::text$$, v_profile
  ));
  perform pg_sleep(0.1);
  perform dblink_send_query('p27_create_second', format(
    $$select public.create_or_resume_fit_intent_draft_v027(
      %L,'a2710000-0000-4000-8000-000000000102'
    )::text$$, v_profile
  ));
  perform pg_sleep(0.2);
  if dblink_is_busy('p27_create_second') <> 1 then
    raise exception '027 concurrent create did not serialize';
  end if;
  select result into v_first from dblink_get_result('p27_create_first')
    as result(result text);
  perform count(*) from dblink_get_result('p27_create_first')
    as result(result text);
  perform dblink_exec('p27_create_first', 'commit');
  select result into v_second from dblink_get_result('p27_create_second')
    as result(result text);
  perform count(*) from dblink_get_result('p27_create_second')
    as result(result text);
  perform dblink_exec('p27_create_second', 'commit');
  perform dblink_disconnect('p27_create_first');
  perform dblink_disconnect('p27_create_second');
  if (v_first::jsonb ->> 'intentSetId') is distinct from
       (v_second::jsonb ->> 'intentSetId')
     or (select count(*)
         from private.fit_intent_product_states_v027 state
         where state.profile_version_id = v_profile
           and state.active_draft) <> 1 then
    raise exception '027 concurrent create produced multiple drafts';
  end if;
end;
$create_race$;

do $mutation_race$
declare
  v_auth constant uuid := 'a2710000-0000-4000-8000-000000000001';
  v_conn text := 'dbname=' || current_database();
  v_intent uuid;
  v_first text;
  v_second_blocked boolean := false;
begin
  select state.intent_set_id into strict v_intent
  from private.fit_intent_product_states_v027 state
  where state.profile_version_id =
    'a2710000-0000-4000-8000-000000000021' and state.active_draft;
  perform dblink_connect('p27_edit_first', v_conn);
  perform dblink_connect('p27_edit_second', v_conn);
  perform dblink_exec('p27_edit_first', 'begin');
  perform dblink_exec('p27_edit_second', 'begin');
  perform * from dblink('p27_edit_first', format(
    'select set_config(''request.jwt.claim.sub'',%L,true)', v_auth
  )) as configured(value text);
  perform * from dblink('p27_edit_second', format(
    'select set_config(''request.jwt.claim.sub'',%L,true)', v_auth
  )) as configured(value text);
  perform dblink_exec('p27_edit_first', 'set local role authenticated');
  perform dblink_exec('p27_edit_second', 'set local role authenticated');
  perform dblink_send_query('p27_edit_first', format(
    $$select public.mutate_fit_intent_draft_v027(
      %L,'a2710000-0000-4000-8000-000000000111',0,
      'DIMENSION_MARK_NOT_SUPPLIED','{"dimension":"ACADEMIC"}'::jsonb
    )::text$$, v_intent
  ));
  perform pg_sleep(0.1);
  perform dblink_send_query('p27_edit_second', format(
    $$select public.mutate_fit_intent_draft_v027(
      %L,'a2710000-0000-4000-8000-000000000112',0,
      'DIMENSION_MARK_NOT_SUPPLIED','{"dimension":"CAREER"}'::jsonb
    )::text$$, v_intent
  ));
  perform pg_sleep(0.2);
  if dblink_is_busy('p27_edit_second') <> 1 then
    raise exception '027 concurrent mutation did not serialize';
  end if;
  select result into v_first from dblink_get_result('p27_edit_first')
    as result(result text);
  perform count(*) from dblink_get_result('p27_edit_first')
    as result(result text);
  perform dblink_exec('p27_edit_first', 'commit');
  begin
    perform count(*) from dblink_get_result('p27_edit_second')
      as result(result text);
  exception when others then
    v_second_blocked := sqlerrm like '%FIT_INTENT_REVISION_CONFLICT%';
  end;
  perform count(*) from dblink_get_result('p27_edit_second')
    as result(result text);
  perform dblink_exec('p27_edit_second', 'rollback');
  perform dblink_disconnect('p27_edit_first');
  perform dblink_disconnect('p27_edit_second');
  if not v_second_blocked
     or (v_first::jsonb ->> 'revision')::bigint <> 1
     or (select state.intent_revision
         from private.fit_intent_product_states_v027 state
         where state.intent_set_id = v_intent) <> 1 then
    raise exception '027 concurrent mutation did not fail closed';
  end if;
end;
$mutation_race$;

do $cleanup$
declare
  v_student constant uuid := 'a2710000-0000-4000-8000-000000000011';
begin
  execute 'set local role service_role';
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  execute 'reset role';
  delete from auth.users
  where id = 'a2710000-0000-4000-8000-000000000001';
end;
$cleanup$;

select 'PHASE027_CONCURRENCY_PASS';
