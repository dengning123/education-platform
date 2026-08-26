-- Run immediately after Migration 029 on the paired disposable fixture.
do $assert$
declare
  v_capture private.phase029_upgrade_capture%rowtype;
  v_after_fingerprint text;
begin
  select * into strict v_capture from private.phase029_upgrade_capture;
  select md5(jsonb_build_object(
    'intent', (select to_jsonb(intent) from public.fit_intent_sets intent
      where intent.intent_set_id = v_capture.intent_set_id),
    'product', (select to_jsonb(state)
      from private.fit_intent_product_states_v027 state
      where state.intent_set_id = v_capture.intent_set_id),
    'dimensions', (select jsonb_agg(to_jsonb(state) order by state.dimension)
      from private.fit_intent_dimension_states_v027 state
      where state.intent_set_id = v_capture.intent_set_id),
    'declarations', (select jsonb_agg(to_jsonb(declaration)
      order by declaration.intent_declaration_id)
      from public.fit_intent_declarations declaration
      where declaration.intent_set_id = v_capture.intent_set_id),
    'operations', (select jsonb_agg(to_jsonb(operation)
      order by operation.operation_id)
      from private.fit_intent_operations_v027 operation
      where operation.student_id = v_capture.student_id)
  )::text) into v_after_fingerprint;

  if v_after_fingerprint is distinct from v_capture.graph_fingerprint then
    raise exception 'M029 populated upgrade changed existing M027 state';
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(v_capture.student_id, 'TEST_LIFECYCLE');
  execute 'reset role';

  if exists (
    select 1 from public.students where student_id = v_capture.student_id
  ) or exists (
    select 1 from public.student_profile_versions
    where profile_version_id = v_capture.profile_version_id
  ) or exists (
    select 1 from public.fit_intent_sets
    where intent_set_id = v_capture.intent_set_id
  ) or exists (
    select 1 from public.fit_intent_declarations
    where intent_set_id = v_capture.intent_set_id
  ) or exists (
    select 1 from private.fit_intent_product_states_v027
    where intent_set_id = v_capture.intent_set_id
  ) or exists (
    select 1 from private.fit_intent_dimension_states_v027
    where intent_set_id = v_capture.intent_set_id
  ) or exists (
    select 1 from private.fit_intent_student_assertions_v027
    where intent_set_id = v_capture.intent_set_id
  ) or exists (
    select 1 from private.fit_intent_operations_v027
    where student_id = v_capture.student_id
  ) then
    raise exception 'M029 populated privacy deletion left student state';
  end if;

  if (select count(*) from public.taxonomy_concepts) <>
       v_capture.taxonomy_count
     or (select count(*) from public.program_versions) <>
       v_capture.program_count
     or (select count(*) from public.sources) <>
       v_capture.source_count then
    raise exception 'M029 populated privacy deletion changed global state';
  end if;

  delete from auth.users where id = v_capture.auth_user_id;
end;
$assert$;

drop table private.phase029_upgrade_capture;

select 'PHASE029_POPULATED_UPGRADE_PASS';
