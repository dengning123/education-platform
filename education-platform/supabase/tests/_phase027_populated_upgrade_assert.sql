-- Run immediately after Migration 027 on the populated fixture.
do $assert$
declare
  v_student constant uuid := 'a2720000-0000-4000-8000-000000000001';
  v_intent constant uuid := 'a2720000-0000-4000-8000-000000000003';
begin
  if not exists (
    select 1 from public.fit_intent_declarations declaration
    where declaration.intent_set_id = v_intent
      and declaration.student_evidence_id =
        'a2720000-0000-4000-8000-000000000004'
      and declaration.student_assertion_id is null
      and declaration.interpretation_provenance = 'SELF_REPORTED'
  ) or not exists (
    select 1 from private.fit_student_access_contexts context
    where context.intent_set_id = v_intent
      and context.student_evidence_id =
        'a2720000-0000-4000-8000-000000000004'
      and context.student_assertion_id is null
  ) or exists (
    select 1 from private.fit_intent_product_states_v027 state
    where state.intent_set_id = v_intent
  ) then
    raise exception '027 populated upgrade changed legacy Fit intent semantics';
  end if;
  execute 'set local role service_role';
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  execute 'reset role';
end;
$assert$;

select 'PHASE027_POPULATED_UPGRADE_PASS';
