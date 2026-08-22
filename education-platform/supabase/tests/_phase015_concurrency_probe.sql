\set ON_ERROR_STOP on
set search_path = public, private, extensions, pg_catalog;

-- Disposable multi-session probe. Prepare the database by running 006 with
-- phase014_commit_fixture=1, then applying Migration 015.

do $seal_races$
declare
  v_evaluation uuid;
  v_conn text;
  v_case text;
  v_sealed text;
begin
  select e.evaluation_id into strict v_evaluation
  from public.fit_evaluations e
  where e.profile_version_id = '61400000-0000-0000-0000-000000000002'
    and e.evaluator_build_id = '61400000-0000-0000-0000-000000000020'
    and e.financial_contract_version = 'FINANCIAL_BILLING_BASIS_V014'
    and e.replay_contract_version = 'FIT_REPLAY_SEAL_V015'
    and e.evaluation_state = 'BUILDING'
    and e.candidate_input_fingerprint is null;

  select case when rolsuper
    then 'dbname=' || current_database()
    else 'host=host.docker.internal port=54322 dbname=' || current_database()
      || ' user=postgres password=postgres'
    end into v_conn
  from pg_roles where rolname = current_user;

  foreach v_case in array array['EVALUATION_LOCK', 'NORMALIZATION_LOCK'] loop
    perform dblink_connect('phase015_seal_lock', v_conn);
    perform dblink_connect('phase015_seal_worker', v_conn);
    perform dblink_exec('phase015_seal_lock', 'begin');
    if v_case = 'EVALUATION_LOCK' then
      perform * from dblink(
        'phase015_seal_lock', format(
          'select 1 from public.fit_evaluations where evaluation_id=%L for update',
          v_evaluation
        )
      ) as locked(n integer);
    else
      perform * from dblink(
        'phase015_seal_lock', format(
          'select 1 from public.fit_financial_normalization_reviews_v014 where evaluation_id=%L order by financial_normalization_id limit 1 for update',
          v_evaluation
        )
      ) as locked(n integer);
    end if;

    perform dblink_exec('phase015_seal_worker', 'begin');
    perform dblink_exec(
      'phase015_seal_worker',
      'set local lock_timeout=''5s''; set local statement_timeout=''8s'''
    );
    if dblink_send_query(
      'phase015_seal_worker', format(
        'select public.seal_fit_evaluation_inputs(%L)::text', v_evaluation
      )
    ) <> 1 then
      raise exception 'could not dispatch v015 seal worker for %', v_case;
    end if;
    perform pg_sleep(0.25);
    if dblink_is_busy('phase015_seal_worker') <> 1 then
      raise exception 'v015 seal did not serialize behind %', v_case;
    end if;

    perform dblink_exec('phase015_seal_lock', 'rollback');
    select max(x) into v_sealed
    from dblink_get_result('phase015_seal_worker') as t(x text);
    perform count(*)
    from dblink_get_result('phase015_seal_worker') as t(x text);
    perform dblink_exec('phase015_seal_worker', 'rollback');
    perform dblink_disconnect('phase015_seal_lock');
    perform dblink_disconnect('phase015_seal_worker');

    if v_sealed !~ '^[0-9a-f]{64}$'
       or (select candidate_input_fingerprint
           from public.fit_evaluations
           where evaluation_id = v_evaluation) is not null
       or exists (
         select 1 from private.fit_evaluation_semantic_pins
         where evaluation_id = v_evaluation
       ) then
      raise exception 'rolled-back v015 seal changed durable state for %', v_case;
    end if;
  end loop;

  perform public.seal_fit_evaluation_inputs(v_evaluation);
  if not exists (
    select 1
    from public.fit_evaluations e
    join private.fit_evaluation_semantic_pins p using(evaluation_id)
    where e.evaluation_id = v_evaluation
      and e.evaluation_state = 'BUILDING'
      and e.candidate_input_fingerprint = p.decision_input_fingerprint
  ) then
    raise exception 'v015 concurrency fixture did not persist one valid seal';
  end if;
end;
$seal_races$;

do $finalization_races$
declare
  v_evaluation uuid;
  v_expected text;
  v_conn text;
  v_first text;
  v_second text;
begin
  select e.evaluation_id, e.candidate_input_fingerprint
  into strict v_evaluation, v_expected
  from public.fit_evaluations e
  where e.profile_version_id = '61400000-0000-0000-0000-000000000002'
    and e.replay_contract_version = 'FIT_REPLAY_SEAL_V015'
    and e.evaluation_state = 'BUILDING'
    and e.candidate_input_fingerprint is not null;

  select case when rolsuper
    then 'dbname=' || current_database()
    else 'host=host.docker.internal port=54322 dbname=' || current_database()
      || ' user=postgres password=postgres'
    end into v_conn
  from pg_roles where rolname = current_user;

  -- Finalization after seal must not read or wait for mutable normalization
  -- authority. Only the immutable pin and evaluation-owned output hash remain.
  perform dblink_connect('phase015_live_lock', v_conn);
  perform dblink_connect('phase015_pin_finalizer', v_conn);
  perform dblink_exec('phase015_live_lock', 'begin');
  perform * from dblink(
    'phase015_live_lock', format(
      'select 1 from public.fit_financial_normalization_reviews_v014 where evaluation_id=%L order by financial_normalization_id limit 1 for update',
      v_evaluation
    )
  ) as locked(n integer);
  perform dblink_exec('phase015_pin_finalizer', 'begin');
  perform dblink_exec(
    'phase015_pin_finalizer',
    'set local lock_timeout=''5s''; set local statement_timeout=''8s'''
  );
  if dblink_send_query(
    'phase015_pin_finalizer', format(
      'select public.finalize_fit_evaluation(%L)::text', v_evaluation
    )
  ) <> 1 then
    raise exception 'could not dispatch pin-only finalizer';
  end if;
  perform pg_sleep(0.25);
  if dblink_is_busy('phase015_pin_finalizer') <> 0 then
    raise exception 'v015 finalizer waited on mutable live normalization authority';
  end if;
  select max(x) into v_first
  from dblink_get_result('phase015_pin_finalizer') as t(x text);
  perform count(*)
  from dblink_get_result('phase015_pin_finalizer') as t(x text);
  perform dblink_exec('phase015_pin_finalizer', 'rollback');
  perform dblink_exec('phase015_live_lock', 'rollback');
  perform dblink_disconnect('phase015_pin_finalizer');
  perform dblink_disconnect('phase015_live_lock');
  if v_first is distinct from v_expected then
    raise exception 'pin-only finalizer returned the wrong fingerprint';
  end if;

  -- Two finalizers serialize only on the evaluation row. The first worker is
  -- rolled back, allowing the second to replay the identical sealed pin.
  perform dblink_connect('phase015_eval_lock', v_conn);
  perform dblink_connect('phase015_first_finalizer', v_conn);
  perform dblink_connect('phase015_second_finalizer', v_conn);
  perform dblink_exec('phase015_eval_lock', 'begin');
  perform * from dblink(
    'phase015_eval_lock', format(
      'select 1 from public.fit_evaluations where evaluation_id=%L for update',
      v_evaluation
    )
  ) as locked(n integer);
  perform dblink_exec('phase015_first_finalizer', 'begin');
  perform dblink_exec('phase015_second_finalizer', 'begin');
  perform dblink_exec(
    'phase015_first_finalizer',
    'set local lock_timeout=''5s''; set local statement_timeout=''8s'''
  );
  perform dblink_exec(
    'phase015_second_finalizer',
    'set local lock_timeout=''5s''; set local statement_timeout=''8s'''
  );
  perform dblink_send_query(
    'phase015_first_finalizer', format(
      'select public.finalize_fit_evaluation(%L)::text', v_evaluation
    )
  );
  perform pg_sleep(0.15);
  if dblink_is_busy('phase015_first_finalizer') <> 1 then
    raise exception 'first v015 finalizer did not enter the evaluation lock queue';
  end if;
  perform dblink_send_query(
    'phase015_second_finalizer', format(
      'select public.finalize_fit_evaluation(%L)::text', v_evaluation
    )
  );
  perform pg_sleep(0.25);
  if dblink_is_busy('phase015_first_finalizer') <> 1
     or dblink_is_busy('phase015_second_finalizer') <> 1 then
    raise exception 'v015 finalizers did not serialize on the evaluation row';
  end if;

  perform dblink_exec('phase015_eval_lock', 'rollback');
  select max(x) into v_first
  from dblink_get_result('phase015_first_finalizer') as t(x text);
  perform count(*)
  from dblink_get_result('phase015_first_finalizer') as t(x text);
  if dblink_is_busy('phase015_second_finalizer') <> 1 then
    raise exception 'second v015 finalizer bypassed the first worker row lock';
  end if;
  perform dblink_exec('phase015_first_finalizer', 'rollback');
  select max(x) into v_second
  from dblink_get_result('phase015_second_finalizer') as t(x text);
  perform count(*)
  from dblink_get_result('phase015_second_finalizer') as t(x text);
  perform dblink_exec('phase015_second_finalizer', 'rollback');
  perform dblink_disconnect('phase015_eval_lock');
  perform dblink_disconnect('phase015_first_finalizer');
  perform dblink_disconnect('phase015_second_finalizer');

  if v_first is distinct from v_expected
     or v_second is distinct from v_expected
     or not exists (
       select 1 from public.fit_evaluations
       where evaluation_id = v_evaluation
         and evaluation_state = 'BUILDING'
         and candidate_input_fingerprint = v_expected
         and decision_input_fingerprint is null
         and result_fingerprint is null
     ) then
    raise exception 'rolled-back v015 finalizers diverged or changed state';
  end if;
end;
$finalization_races$;
