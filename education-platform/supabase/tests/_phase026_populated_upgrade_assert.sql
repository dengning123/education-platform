do $assert$
declare
  v_row public.eligibility_evaluations%rowtype;
begin
  select * into strict v_row
  from public.eligibility_evaluations
  where evaluation_id = 'a2610000-0000-4000-8000-000000000031';

  if v_row.profile_version_id <>
       'a2610000-0000-4000-8000-000000000011'::uuid
     or v_row.rule_set_id <>
       'a2610000-0000-4000-8000-000000000021'::uuid
     or v_row.evaluator_name <> 'phase026-upgrade-probe'
     or v_row.evaluator_version <> '0.1.0'
     or v_row.evaluator_build_hash <> repeat('b', 64)
     or v_row.input_schema_version <> 'eligibility-v0.1'
     or v_row.profile_snapshot_hash <> repeat('a', 64)
     or v_row.input_fingerprint <> repeat('c', 64)
     or v_row.evaluation_state <> 'COMPLETED'
     or v_row.outcome <> 'ELIGIBLE'
     or v_row.root_truth_value <> 'SATISFIED'
     or v_row.result_fingerprint is not null then
    raise exception '026 populated upgrade rewrote historical Eligibility identity';
  end if;

  if to_regclass('private.eligibility_assembly_operations_v026') is null
     or to_regprocedure(
       'public.assemble_eligibility_evaluation_v026(uuid,uuid,uuid)'
     ) is null
     or exists (
       select 1 from private.eligibility_assembly_operations_v026
     ) then
    raise exception '026 populated upgrade did not remain additive and empty';
  end if;

  raise notice 'Migration 026 populated 025->026 upgrade: PASS';
end;
$assert$;
