-- Run after Migration 029 and before Migration 030 on a disposable database.
create table private.phase030_upgrade_capture (
  capture_key text primary key,
  capture_value text not null
);

insert into private.phase030_upgrade_capture (capture_key, capture_value)
values
  (
    'legacy_rule_sets',
    coalesce((
      select md5(coalesce(jsonb_agg(to_jsonb(rule_set)
        order by rule_set.rule_set_id)::text, '[]'))
      from public.program_requirement_rule_sets rule_set
    ), md5('[]'))
  ),
  (
    'legacy_completed_evaluations',
    coalesce((
      select md5(coalesce(jsonb_agg(to_jsonb(evaluation)
        order by evaluation.evaluation_id)::text, '[]'))
      from public.eligibility_evaluations evaluation
      where evaluation.evaluation_state = 'COMPLETED'
    ), md5('[]'))
  );
