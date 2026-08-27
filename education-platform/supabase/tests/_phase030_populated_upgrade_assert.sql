-- Run immediately after Migration 030 on the paired disposable fixture.
do $assert$
begin
  if (select capture_value from private.phase030_upgrade_capture
      where capture_key = 'legacy_rule_sets') is distinct from (
    select md5(coalesce(jsonb_agg(to_jsonb(rule_set)
      order by rule_set.rule_set_id)::text, '[]'))
    from public.program_requirement_rule_sets rule_set
  ) then
    raise exception 'M030 populated upgrade changed a legacy requirement rule set';
  end if;
  if (select capture_value from private.phase030_upgrade_capture
      where capture_key = 'legacy_completed_evaluations') is distinct from (
    select md5(coalesce(jsonb_agg(to_jsonb(evaluation)
      order by evaluation.evaluation_id)::text, '[]'))
    from public.eligibility_evaluations evaluation
    where evaluation.evaluation_state = 'COMPLETED'
  ) then
    raise exception 'M030 populated upgrade changed a completed legacy Eligibility evaluation';
  end if;
  if not exists (
    select 1 from public.eligibility_evaluator_builds_v030 build
    where build.evaluator_build_id = '03003030-0303-4030-8030-030030030030'
      and build.input_schema_version = 'eligibility-degree-v1'
      and build.status = 'VERIFIED'
  ) then
    raise exception 'M030 populated upgrade did not register the degree evaluator build';
  end if;
end;
$assert$;

drop table private.phase030_upgrade_capture;

select 'PHASE030_POPULATED_UPGRADE_PASS';
