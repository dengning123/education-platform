\set ON_ERROR_STOP on
set search_path = public, private, extensions, pg_catalog;

-- Disposable multi-session probe. It commits fixtures so that dblink workers
-- can observe them, then deletes all student/Auth state. Run only on a
-- disposable local database.

create extension if not exists dblink;

insert into auth.users (id, email) values (
  '93000000-0000-0000-0000-000000000001',
  'phase019-concurrency@test.invalid'
);

do $bootstrap_and_create_races$
declare
  v_auth constant uuid := '93000000-0000-0000-0000-000000000001';
  v_conn text := 'dbname=' || current_database();
  v_first text;
  v_second text;
  v_profile uuid;
begin
  perform dblink_connect('p19_first', v_conn);
  perform dblink_connect('p19_second', v_conn);
  perform dblink_exec('p19_first', 'begin');
  perform dblink_exec('p19_second', 'begin');
  perform * from dblink(
    'p19_first', format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform * from dblink(
    'p19_second', format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform dblink_exec('p19_first', 'set local role authenticated');
  perform dblink_exec('p19_second', 'set local role authenticated');
  perform dblink_send_query(
    'p19_first', 'select public.bootstrap_profile_identity_v019()::text'
  );
  perform pg_sleep(0.1);
  perform dblink_send_query(
    'p19_second', 'select public.bootstrap_profile_identity_v019()::text'
  );
  perform pg_sleep(0.2);
  if dblink_is_busy('p19_second') <> 1 then
    raise exception 'Concurrent bootstrap did not serialize on Auth identity';
  end if;
  select result into v_first
  from dblink_get_result('p19_first') as result(result text);
  perform count(*) from dblink_get_result('p19_first') as result(result text);
  perform dblink_exec('p19_first', 'commit');
  select result into v_second
  from dblink_get_result('p19_second') as result(result text);
  perform count(*) from dblink_get_result('p19_second') as result(result text);
  perform dblink_exec('p19_second', 'commit');
  if v_first::jsonb is distinct from v_second::jsonb
     or (select count(*) from private.student_identities
         where auth_user_id = v_auth) <> 1 then
    raise exception 'Concurrent bootstrap did not converge';
  end if;

  perform dblink_exec('p19_first', 'begin');
  perform dblink_exec('p19_second', 'begin');
  perform * from dblink(
    'p19_first', format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform * from dblink(
    'p19_second', format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform dblink_exec('p19_first', 'set local role authenticated');
  perform dblink_exec('p19_second', 'set local role authenticated');
  perform dblink_send_query(
    'p19_first',
    $$select public.create_or_resume_profile_draft_v019(
      '93000000-0000-0000-0000-000000000011'
    )::text$$
  );
  perform pg_sleep(0.1);
  perform dblink_send_query(
    'p19_second',
    $$select public.create_or_resume_profile_draft_v019(
      '93000000-0000-0000-0000-000000000012'
    )::text$$
  );
  perform pg_sleep(0.2);
  if dblink_is_busy('p19_second') <> 1 then
    raise exception 'Concurrent draft creation did not serialize';
  end if;
  select result into v_first
  from dblink_get_result('p19_first') as result(result text);
  perform count(*) from dblink_get_result('p19_first') as result(result text);
  perform dblink_exec('p19_first', 'commit');
  select result into v_second
  from dblink_get_result('p19_second') as result(result text);
  perform count(*) from dblink_get_result('p19_second') as result(result text);
  perform dblink_exec('p19_second', 'commit');
  v_profile := (v_first::jsonb ->> 'profileVersionId')::uuid;
  if (v_second::jsonb ->> 'profileVersionId')::uuid <> v_profile
     or (select count(*) from public.student_profile_versions profile
         join private.student_identities identity using (student_id)
         where identity.auth_user_id = v_auth
           and profile.product_managed and profile.status = 'DRAFT') <> 1 then
    raise exception 'Concurrent create/resume produced multiple drafts';
  end if;
  perform dblink_disconnect('p19_first');
  perform dblink_disconnect('p19_second');
end;
$bootstrap_and_create_races$;

do $edit_race$
declare
  v_auth constant uuid := '93000000-0000-0000-0000-000000000001';
  v_conn text := 'dbname=' || current_database();
  v_profile uuid;
  v_first text;
  v_second_blocked boolean := false;
begin
  select profile.profile_version_id into strict v_profile
  from public.student_profile_versions profile
  join private.student_identities identity using (student_id)
  where identity.auth_user_id = v_auth
    and profile.product_managed and profile.status = 'DRAFT';
  perform dblink_connect('p19_edit_first', v_conn);
  perform dblink_connect('p19_edit_second', v_conn);
  perform dblink_exec('p19_edit_first', 'begin');
  perform dblink_exec('p19_edit_second', 'begin');
  perform * from dblink(
    'p19_edit_first', format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform * from dblink(
    'p19_edit_second', format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform dblink_exec('p19_edit_first', 'set local role authenticated');
  perform dblink_exec('p19_edit_second', 'set local role authenticated');
  perform dblink_send_query('p19_edit_first', format(
    $$select public.mutate_profile_draft_v019(
      %L,'93000000-0000-0000-0000-000000000021',0,'GOAL_CREATE',
      '{"goalType":"OTHER","goalText":"first","priority":1}'::jsonb
    )::text$$, v_profile
  ));
  perform pg_sleep(0.1);
  perform dblink_send_query('p19_edit_second', format(
    $$select public.mutate_profile_draft_v019(
      %L,'93000000-0000-0000-0000-000000000022',0,'GOAL_CREATE',
      '{"goalType":"OTHER","goalText":"second","priority":1}'::jsonb
    )::text$$, v_profile
  ));
  perform pg_sleep(0.2);
  if dblink_is_busy('p19_edit_second') <> 1 then
    raise exception 'Concurrent edits did not serialize';
  end if;
  select result into v_first
  from dblink_get_result('p19_edit_first') as result(result text);
  perform count(*)
  from dblink_get_result('p19_edit_first') as result(result text);
  perform dblink_exec('p19_edit_first', 'commit');
  begin
    perform count(*)
    from dblink_get_result('p19_edit_second') as result(result text);
  exception when others then
    v_second_blocked := sqlerrm like '%PROFILE_REVISION_CONFLICT%';
  end;
  perform count(*)
  from dblink_get_result('p19_edit_second') as result(result text);
  perform dblink_exec('p19_edit_second', 'rollback');
  perform dblink_disconnect('p19_edit_first');
  perform dblink_disconnect('p19_edit_second');
  if not v_second_blocked
     or (v_first::jsonb ->> 'revision')::bigint <> 1
     or (select profile_revision from public.student_profile_versions
         where profile_version_id = v_profile) <> 1
     or (select count(*) from public.student_goals
         where profile_version_id = v_profile) <> 1 then
    raise exception 'Concurrent edit lost an update or did not fail closed';
  end if;
end;
$edit_race$;

-- Complete all eight no-degree scopes in committed transactions.
do $complete_scopes$
declare
  v_auth constant uuid := '93000000-0000-0000-0000-000000000001';
  v_profile uuid;
  v_revision bigint := 1;
  v_domain public.student_data_domain;
begin
  select profile.profile_version_id into strict v_profile
  from public.student_profile_versions profile
  join private.student_identities identity using (student_id)
  where identity.auth_user_id = v_auth
    and profile.product_managed and profile.status = 'DRAFT';
  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  execute 'set local role authenticated';
  foreach v_domain in array array[
    'EDUCATION_HISTORY','TEST_HISTORY','EXPERIENCE_HISTORY','SKILL_HISTORY',
    'PREFERENCES','GOALS','COURSE_HISTORY','COURSE_MAPPING'
  ]::public.student_data_domain[]
  loop
    perform public.mutate_profile_draft_v019(
      v_profile, extensions.gen_random_uuid(), v_revision,
      'COMPLETENESS_UPSERT',
      jsonb_build_object('domain', v_domain, 'completeness', 'COMPLETE')
    );
    v_revision := v_revision + 1;
  end loop;
  execute 'reset role';
end;
$complete_scopes$;

do $freeze_edit_race$
declare
  v_auth constant uuid := '93000000-0000-0000-0000-000000000001';
  v_conn text := 'dbname=' || current_database();
  v_profile uuid;
  v_frozen text;
  v_edit_blocked boolean := false;
begin
  select profile.profile_version_id into strict v_profile
  from public.student_profile_versions profile
  join private.student_identities identity using (student_id)
  where identity.auth_user_id = v_auth
    and profile.product_managed and profile.status = 'DRAFT'
    and profile.profile_revision = 9;
  perform dblink_connect('p19_freezer', v_conn);
  perform dblink_connect('p19_late_editor', v_conn);
  perform dblink_exec('p19_freezer', 'begin');
  perform dblink_exec('p19_late_editor', 'begin');
  perform * from dblink(
    'p19_freezer', format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform * from dblink(
    'p19_late_editor', format('select set_config(''request.jwt.claim.sub'',%L,true)', v_auth)
  ) as configured(value text);
  perform dblink_exec('p19_freezer', 'set local role authenticated');
  perform dblink_exec('p19_late_editor', 'set local role authenticated');
  perform dblink_send_query('p19_freezer', format(
    $$select public.freeze_profile_draft_v019(
      %L,'93000000-0000-0000-0000-000000000031',9
    )::text$$, v_profile
  ));
  perform pg_sleep(0.1);
  perform dblink_send_query('p19_late_editor', format(
    $$select public.mutate_profile_draft_v019(
      %L,'93000000-0000-0000-0000-000000000032',9,'GOAL_CREATE',
      '{"goalType":"OTHER","goalText":"late","priority":1}'::jsonb
    )::text$$, v_profile
  ));
  perform pg_sleep(0.2);
  if dblink_is_busy('p19_late_editor') <> 1 then
    raise exception 'Edit did not serialize behind freeze';
  end if;
  select result into v_frozen
  from dblink_get_result('p19_freezer') as result(result text);
  perform count(*) from dblink_get_result('p19_freezer') as result(result text);
  perform dblink_exec('p19_freezer', 'commit');
  begin
    perform count(*)
    from dblink_get_result('p19_late_editor') as result(result text);
  exception when others then
    v_edit_blocked := sqlerrm like '%PROFILE_DRAFT_REQUIRED%';
  end;
  perform count(*)
  from dblink_get_result('p19_late_editor') as result(result text);
  perform dblink_exec('p19_late_editor', 'rollback');
  perform dblink_disconnect('p19_freezer');
  perform dblink_disconnect('p19_late_editor');
  if not v_edit_blocked
     or v_frozen::jsonb ->> 'status' <> 'FROZEN'
     or not exists (
       select 1 from public.student_profile_versions
       where profile_version_id = v_profile
         and status = 'FROZEN'
         and profile_revision = 10
         and snapshot_hash ~ '^[a-f0-9]{64}$'
     )
     or (select count(*) from public.student_goals
         where profile_version_id = v_profile) <> 1 then
    raise exception 'Concurrent freeze/edit did not fail closed';
  end if;
end;
$freeze_edit_race$;

do $cleanup$
declare
  v_auth constant uuid := '93000000-0000-0000-0000-000000000001';
  v_student uuid;
begin
  select student_id into strict v_student
  from private.student_identities where auth_user_id = v_auth;
  execute 'set local role service_role';
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  execute 'reset role';
  if exists (
    select 1 from private.profile_capability_operations_v019
    where student_id = v_student
  ) or exists (
    select 1 from public.student_profile_versions where student_id = v_student
  ) then
    raise exception 'Concurrency cleanup retained Profile state';
  end if;
  delete from auth.users where id = v_auth;
end;
$cleanup$;
