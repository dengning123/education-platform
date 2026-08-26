-- Run after Migration 027 and before Migration 028 on a disposable database.
create table private.phase028_upgrade_capture (
  capture_key text primary key,
  capture_value text not null
);

insert into private.phase028_upgrade_capture (capture_key, capture_value)
values
  (
    'legacy_build',
    coalesce((
      select md5(to_jsonb(build)::text)
      from public.fit_evaluator_builds build
      where build.evaluator_build_id =
        '30000000-0000-0000-0000-000000000164'::uuid
    ), 'MISSING')
  ),
  (
    'completed_evaluations',
    coalesce((
      select md5(coalesce(jsonb_agg(to_jsonb(evaluation)
        order by evaluation.evaluation_id)::text, '[]'))
      from public.fit_evaluations evaluation
      where evaluation.evaluation_state = 'COMPLETED'
    ), md5('[]'))
  );
