\set ON_ERROR_STOP on
set search_path = public, private, extensions, pg_catalog;

-- Disposable multi-session proof that privacy deletion shares the existing
-- lifecycle lock order with M027 mutation/freeze and Fit evaluation start.
create extension if not exists dblink;

insert into auth.users (id, email) values
  ('a2910000-0000-4000-8000-000000000001',
   'phase029-mutate@test.invalid'),
  ('a2910000-0000-4000-8000-000000000002',
   'phase029-freeze@test.invalid'),
  ('a2910000-0000-4000-8000-000000000003',
   'phase029-evaluate@test.invalid');

do $fixture$
declare
  v_release record;
  v_case record;
  v_dimension public.fit_dimension;
begin
  select release.release_code, release.release_ordinal
  into strict v_release
  from public.taxonomy_releases release
  where release.status = 'VERIFIED' and release.retired_at is null
  order by release.release_ordinal desc
  limit 1;

  for v_case in
    select * from (values
      ('a2910000-0000-4000-8000-000000000001'::uuid,
       'a2910000-0000-4000-8000-000000000011'::uuid,
       'a2910000-0000-4000-8000-000000000021'::uuid,
       'a2910000-0000-4000-8000-000000000031'::uuid,
       'DRAFT'::public.fit_intent_set_status,
       true,
       'UNANSWERED'::public.fit_intent_product_dimension_state_v027),
      ('a2910000-0000-4000-8000-000000000002'::uuid,
       'a2910000-0000-4000-8000-000000000012'::uuid,
       'a2910000-0000-4000-8000-000000000022'::uuid,
       'a2910000-0000-4000-8000-000000000032'::uuid,
       'DRAFT'::public.fit_intent_set_status,
       true,
       'EXPLICIT_NOT_SUPPLIED'::public.fit_intent_product_dimension_state_v027),
      ('a2910000-0000-4000-8000-000000000003'::uuid,
       'a2910000-0000-4000-8000-000000000013'::uuid,
       'a2910000-0000-4000-8000-000000000023'::uuid,
       'a2910000-0000-4000-8000-000000000033'::uuid,
       'FROZEN'::public.fit_intent_set_status,
       false,
       'EXPLICIT_NOT_SUPPLIED'::public.fit_intent_product_dimension_state_v027)
    ) fixture(
      auth_user_id, student_id, profile_version_id, intent_set_id,
      intent_status, active_draft, disposition
    )
  loop
    perform public.create_student(v_case.student_id);
    insert into private.student_identities (auth_user_id, student_id)
    values (v_case.auth_user_id, v_case.student_id);
    insert into public.student_profile_versions (
      profile_version_id, student_id, version_number, status,
      snapshot_hash, frozen_at, product_managed, profile_revision
    ) values (
      v_case.profile_version_id, v_case.student_id, 1, 'FROZEN',
      repeat('a', 64), now(), true, 1
    );
    insert into public.fit_intent_sets (
      intent_set_id, profile_version_id, version_number, status,
      snapshot_hash, frozen_at
    ) values (
      v_case.intent_set_id, v_case.profile_version_id, 1,
      v_case.intent_status,
      case when v_case.intent_status = 'FROZEN'
        then repeat('b', 64) else null end,
      case when v_case.intent_status = 'FROZEN' then now() else null end
    );
    insert into private.fit_intent_product_states_v027 (
      intent_set_id, profile_version_id, intent_revision,
      taxonomy_release_code, taxonomy_release_ordinal, active_draft
    ) values (
      v_case.intent_set_id, v_case.profile_version_id, 0,
      v_release.release_code, v_release.release_ordinal,
      v_case.active_draft
    );
    foreach v_dimension in array enum_range(null::public.fit_dimension)
    loop
      insert into private.fit_intent_dimension_states_v027 (
        intent_set_id, profile_version_id, dimension, disposition
      ) values (
        v_case.intent_set_id, v_case.profile_version_id,
        v_dimension, v_case.disposition
      );
    end loop;
  end loop;
end;
$fixture$;

do $mutation_delete_race$
declare
  v_conn text := 'dbname=' || current_database();
  v_result text;
begin
  perform dblink_connect('p29_mutate', v_conn);
  perform dblink_connect('p29_delete_mutate', v_conn);
  perform dblink_exec('p29_mutate', 'begin');
  perform dblink_exec('p29_delete_mutate', 'begin');
  perform * from dblink('p29_mutate',
    $$select set_config(
      'request.jwt.claim.sub',
      'a2910000-0000-4000-8000-000000000001', true
    )$$) as configured(value text);
  perform dblink_exec('p29_mutate', 'set local role authenticated');
  perform dblink_send_query('p29_mutate',
    $$select public.mutate_fit_intent_draft_v027(
      'a2910000-0000-4000-8000-000000000031',
      'a2910000-0000-4000-8000-000000000101',0,
      'DIMENSION_MARK_NOT_SUPPLIED',
      '{"dimension":"ACADEMIC"}'::jsonb
    )::text$$);
  select result into v_result from dblink_get_result('p29_mutate')
    as result(result text);
  perform count(*) from dblink_get_result('p29_mutate')
    as result(result text);

  perform dblink_exec('p29_delete_mutate', 'set local role service_role');
  perform dblink_send_query('p29_delete_mutate',
    $$select public.delete_student_data(
      'a2910000-0000-4000-8000-000000000011','TEST_LIFECYCLE'
    )::text$$);
  perform pg_sleep(0.2);
  if dblink_is_busy('p29_delete_mutate') <> 1 then
    raise exception '029 deletion did not serialize behind M027 mutation';
  end if;
  perform dblink_exec('p29_mutate', 'commit');
  perform count(*) from dblink_get_result('p29_delete_mutate')
    as result(result text);
  perform count(*) from dblink_get_result('p29_delete_mutate')
    as result(result text);
  perform dblink_exec('p29_delete_mutate', 'commit');
  perform dblink_disconnect('p29_mutate');
  perform dblink_disconnect('p29_delete_mutate');

  if exists (
    select 1 from public.students
    where student_id = 'a2910000-0000-4000-8000-000000000011'
  ) or exists (
    select 1 from private.fit_intent_operations_v027
    where student_id = 'a2910000-0000-4000-8000-000000000011'
  ) then
    raise exception '029 mutation/delete race resurrected student state';
  end if;
end;
$mutation_delete_race$;

do $freeze_delete_race$
declare
  v_conn text := 'dbname=' || current_database();
begin
  perform dblink_connect('p29_freeze', v_conn);
  perform dblink_connect('p29_delete_freeze', v_conn);
  perform dblink_exec('p29_freeze', 'begin');
  perform dblink_exec('p29_delete_freeze', 'begin');
  perform * from dblink('p29_freeze',
    $$select set_config(
      'request.jwt.claim.sub',
      'a2910000-0000-4000-8000-000000000002', true
    )$$) as configured(value text);
  perform dblink_exec('p29_freeze', 'set local role authenticated');
  perform dblink_send_query('p29_freeze',
    $$select public.freeze_fit_intent_draft_v027(
      'a2910000-0000-4000-8000-000000000032',
      'a2910000-0000-4000-8000-000000000102',0
    )::text$$);
  perform count(*) from dblink_get_result('p29_freeze')
    as result(result text);
  perform count(*) from dblink_get_result('p29_freeze')
    as result(result text);

  perform dblink_exec('p29_delete_freeze', 'set local role service_role');
  perform dblink_send_query('p29_delete_freeze',
    $$select public.delete_student_data(
      'a2910000-0000-4000-8000-000000000012','TEST_LIFECYCLE'
    )::text$$);
  perform pg_sleep(0.2);
  if dblink_is_busy('p29_delete_freeze') <> 1 then
    raise exception '029 deletion did not serialize behind M027 freeze';
  end if;
  perform dblink_exec('p29_freeze', 'commit');
  perform count(*) from dblink_get_result('p29_delete_freeze')
    as result(result text);
  perform count(*) from dblink_get_result('p29_delete_freeze')
    as result(result text);
  perform dblink_exec('p29_delete_freeze', 'commit');
  perform dblink_disconnect('p29_freeze');
  perform dblink_disconnect('p29_delete_freeze');

  if exists (
    select 1 from public.students
    where student_id = 'a2910000-0000-4000-8000-000000000012'
  ) or exists (
    select 1 from public.fit_intent_sets
    where intent_set_id = 'a2910000-0000-4000-8000-000000000032'
  ) then
    raise exception '029 freeze/delete race resurrected student state';
  end if;
end;
$freeze_delete_race$;

do $evaluation_delete_race$
declare
  v_conn text := 'dbname=' || current_database();
  v_program uuid;
  v_taxonomy text;
begin
  select version.program_version_id into strict v_program
  from public.program_versions version
  order by version.program_version_id limit 1;
  select state.taxonomy_release_code into strict v_taxonomy
  from private.fit_intent_product_states_v027 state
  where state.intent_set_id =
    'a2910000-0000-4000-8000-000000000033';

  perform dblink_connect('p29_evaluate', v_conn);
  perform dblink_connect('p29_delete_evaluate', v_conn);
  perform dblink_exec('p29_evaluate', 'begin');
  perform dblink_exec('p29_delete_evaluate', 'begin');
  perform dblink_exec('p29_evaluate', 'set local role service_role');
  perform dblink_send_query('p29_evaluate', format(
    $$select public.start_fit_evaluation(
      'a2910000-0000-4000-8000-000000000023',
      'a2910000-0000-4000-8000-000000000033',
      %L,%L,
      '30000000-0000-0000-0000-000000000001',
      '30000000-0000-0000-0000-000000000164'
    )::text$$, v_program, v_taxonomy
  ));
  perform count(*) from dblink_get_result('p29_evaluate')
    as result(result text);
  perform count(*) from dblink_get_result('p29_evaluate')
    as result(result text);

  perform dblink_exec('p29_delete_evaluate', 'set local role service_role');
  perform dblink_send_query('p29_delete_evaluate',
    $$select public.delete_student_data(
      'a2910000-0000-4000-8000-000000000013','TEST_LIFECYCLE'
    )::text$$);
  perform pg_sleep(0.2);
  if dblink_is_busy('p29_delete_evaluate') <> 1 then
    raise exception '029 deletion did not serialize behind Fit evaluation';
  end if;
  perform dblink_exec('p29_evaluate', 'commit');
  perform count(*) from dblink_get_result('p29_delete_evaluate')
    as result(result text);
  perform count(*) from dblink_get_result('p29_delete_evaluate')
    as result(result text);
  perform dblink_exec('p29_delete_evaluate', 'commit');
  perform dblink_disconnect('p29_evaluate');
  perform dblink_disconnect('p29_delete_evaluate');

  if exists (
    select 1 from public.students
    where student_id = 'a2910000-0000-4000-8000-000000000013'
  ) or exists (
    select 1 from public.fit_evaluations
    where profile_version_id =
      'a2910000-0000-4000-8000-000000000023'
  ) then
    raise exception '029 evaluation/delete race left or resurrected state';
  end if;
end;
$evaluation_delete_race$;

delete from auth.users where id in (
  'a2910000-0000-4000-8000-000000000001',
  'a2910000-0000-4000-8000-000000000002',
  'a2910000-0000-4000-8000-000000000003'
);

select 'PHASE029_PRIVACY_CONCURRENCY_PASS';
