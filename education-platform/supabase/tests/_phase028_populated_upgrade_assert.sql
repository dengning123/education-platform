-- Run immediately after Migration 028 on the paired disposable fixture.
do $assert$
begin
  if (select capture_value from private.phase028_upgrade_capture
      where capture_key = 'legacy_build') is distinct from (
    select md5(to_jsonb(build)::text)
    from public.fit_evaluator_builds build
    where build.evaluator_build_id =
      '30000000-0000-0000-0000-000000000164'::uuid
  ) then
    raise exception 'M028 populated upgrade changed the legacy evaluator build';
  end if;

  if (select capture_value from private.phase028_upgrade_capture
      where capture_key = 'completed_evaluations') is distinct from coalesce((
    select md5(coalesce(jsonb_agg(to_jsonb(evaluation)
      order by evaluation.evaluation_id)::text, '[]'))
    from public.fit_evaluations evaluation
    where evaluation.evaluation_state = 'COMPLETED'
  ), md5('[]')) then
    raise exception 'M028 populated upgrade changed an existing completed Fit evaluation';
  end if;

  if not exists (
    select 1 from public.fit_evaluator_builds build
    where build.evaluator_build_id =
      '30000000-0000-0000-0000-000000000284'::uuid
      and build.evaluator_version = '0.1.0-product-v027'
      and build.status = 'VERIFIED'
      and build.retired_at is null
  ) then
    raise exception 'M028 populated upgrade did not register the product build';
  end if;
end;
$assert$;

drop table private.phase028_upgrade_capture;

select 'PHASE028_POPULATED_UPGRADE_PASS';
