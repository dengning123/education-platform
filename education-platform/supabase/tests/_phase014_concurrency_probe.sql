\set ON_ERROR_STOP on
set search_path = public, extensions, pg_catalog;

-- Disposable multi-session probe. The fixture is committed only when 006 is
-- invoked with -v phase014_commit_fixture=1; the containing database is then
-- discarded after this file finishes.

do $seal_race$
declare
  v_evaluation uuid;
  v_conn text;
  v_sealed text;
begin
  select e.evaluation_id into strict v_evaluation
  from public.fit_evaluations e
  where e.profile_version_id='61400000-0000-0000-0000-000000000002'
    and e.evaluator_build_id='61400000-0000-0000-0000-000000000020'
    and e.financial_contract_version='FINANCIAL_BILLING_BASIS_V014'
    and e.evaluation_state='BUILDING'
    and e.candidate_input_fingerprint is null;
  if (select count(*) from public.fit_financial_normalizations n
      where n.evaluation_id=v_evaluation)<>2
     or exists (
       select 1 from public.fit_financial_normalization_reviews_v014 r
       where r.evaluation_id=v_evaluation and r.status<>'VERIFIED'
     ) then
    raise exception 'committed v014 concurrency fixture is incomplete';
  end if;

  select case when rolsuper
    then 'dbname='||current_database()
    else 'host=host.docker.internal port=54322 dbname='||current_database()
      ||' user=postgres password=postgres'
    end into v_conn
  from pg_roles where rolname=current_user;
  perform dblink_connect('phase014_seal_lock',v_conn);
  perform dblink_connect('phase014_seal_worker',v_conn);
  perform dblink_exec('phase014_seal_lock','begin');
  perform * from dblink(
    'phase014_seal_lock',format(
      'select 1 from public.fit_evaluations where evaluation_id=%L for update',
      v_evaluation
    )
  ) as locked(n integer);
  perform dblink_exec('phase014_seal_worker','begin');
  perform dblink_exec(
    'phase014_seal_worker','set local lock_timeout=''5s'''
  );
  perform dblink_exec(
    'phase014_seal_worker','set local statement_timeout=''8s'''
  );
  if dblink_send_query(
      'phase014_seal_worker',format(
        'select public.seal_fit_evaluation_inputs(%L)::text',v_evaluation
      ))<>1 then
    raise exception 'could not dispatch concurrent seal worker';
  end if;
  perform pg_sleep(0.2);
  if dblink_is_busy('phase014_seal_worker')<>1 then
    raise exception 'seal did not serialize on the evaluation row lock';
  end if;
  perform dblink_exec('phase014_seal_lock','rollback');
  select max(x) into v_sealed
  from dblink_get_result('phase014_seal_worker') as t(x text);
  perform count(*)
  from dblink_get_result('phase014_seal_worker') as t(x text);
  perform dblink_exec('phase014_seal_worker','rollback');
  perform dblink_disconnect('phase014_seal_lock');
  perform dblink_disconnect('phase014_seal_worker');
  if v_sealed !~ '^[0-9a-f]{64}$'
     or (select candidate_input_fingerprint from public.fit_evaluations
         where evaluation_id=v_evaluation) is not null then
    raise exception 'rolled-back concurrent seal produced an invalid result';
  end if;

  -- Persist one valid seal only after the blocked worker rolled back. All
  -- following races use this committed candidate and roll back their effects.
  perform public.seal_fit_evaluation_inputs(v_evaluation);
end;
$seal_race$;

do $finalization_races$
declare
  v_evaluation uuid;
  v_expected text;
  v_conn text;
  v_case text;
  v_worker_query text;
  v_finalized text;
  v_worker_result text;
begin
  select e.evaluation_id,e.candidate_input_fingerprint
  into strict v_evaluation,v_expected
  from public.fit_evaluations e
  where e.profile_version_id='61400000-0000-0000-0000-000000000002'
    and e.evaluator_build_id='61400000-0000-0000-0000-000000000020'
    and e.financial_contract_version='FINANCIAL_BILLING_BASIS_V014'
    and e.evaluation_state='BUILDING'
    and e.candidate_input_fingerprint is not null;
  select case when rolsuper
    then 'dbname='||current_database()
    else 'host=host.docker.internal port=54322 dbname='||current_database()
      ||' user=postgres password=postgres'
    end into v_conn
  from pg_roles where rolname=current_user;

  foreach v_case in array array[
    'METHOD_RETIREMENT','NORMALIZATION_RETIREMENT',
    'SELECTION_REPLACEMENT','SECOND_FINALIZER'
  ] loop
    perform dblink_connect('phase014_late_lock',v_conn);
    perform dblink_connect('phase014_finalizer',v_conn);
    perform dblink_connect('phase014_competitor',v_conn);
    perform dblink_exec('phase014_late_lock','begin');
    perform * from dblink(
      'phase014_late_lock',format(
        'select 1 from public.fit_manifest_items where evaluation_id=%L order by manifest_item_id limit 1 for update',
        v_evaluation
      )
    ) as locked(n integer);

    perform dblink_exec('phase014_finalizer','begin');
    perform dblink_exec(
      'phase014_finalizer','set local lock_timeout=''5s'''
    );
    perform dblink_exec(
      'phase014_finalizer','set local statement_timeout=''8s'''
    );
    if dblink_send_query(
        'phase014_finalizer',format(
          'select public.finalize_fit_evaluation(%L)::text',v_evaluation
        ))<>1 then
      raise exception 'could not dispatch finalizer for %',v_case;
    end if;
    perform pg_sleep(0.25);
    if dblink_is_busy('phase014_finalizer')<>1 then
      raise exception 'finalizer did not reach the late manifest lock for %',v_case;
    end if;

    v_worker_query:=case v_case
      when 'METHOD_RETIREMENT' then
        $$select 'RETIRED'::text
          from public.retire_fit_definition(
            'FINANCIAL_NORMALIZATION',
            '61400000-0000-0000-0000-000000000021',
            'phase014 concurrent method retirement probe'
          )$$
      when 'NORMALIZATION_RETIREMENT' then
        $$select 'RETIRED'::text
          from public.retire_fit_financial_normalization_v014(
            '61400000-0000-0000-0000-000000000050',
            'phase014 concurrent normalization retirement probe'
          )$$
      when 'SELECTION_REPLACEMENT' then
        $$with prior as (
            select observation_id
            from public.canonical_field_selections
            where record_type='PROGRAM_COST'
              and record_id='00000000-0000-0000-0000-000000000404'
              and field_name='tuition_amount'
          ), scope_row as (
            select public.create_evidence_scope(
              '00000000-0000-0000-0000-000000000705','PROGRAM_COST',
              '00000000-0000-0000-0000-000000000404','tuition_amount',
              'UNSPECIFIED','UNSPECIFIED','UNSPECIFIED'
            ) scope_id
          ), assertion_row as (
            select public.review_evidence_applicability(
              scope_id,'REVIEWED_APPLICABLE','phase014-concurrency',
              'concurrent canonical replacement probe'
            ) assertion_id from scope_row
          ), observation_row as (
            select public.create_field_observation(
              'PROGRAM_COST','00000000-0000-0000-0000-000000000404',
              'tuition_amount',to_jsonb(60000::numeric),'KNOWN',
              '00000000-0000-0000-0000-000000000705',prior.observation_id,
              'phase014 concurrent selection replacement',
              assertion_row.assertion_id
            ) observation_id
            from prior cross join assertion_row
          ), accepted as (
            select public.accept_field_observation(
              observation_id,'phase014-concurrency'
            ) accepted from observation_row
          )
          select observation_id::text
          from observation_row cross join accepted$$
      when 'SECOND_FINALIZER' then format(
        'select public.finalize_fit_evaluation(%L)::text',v_evaluation
      )
    end;
    perform dblink_exec('phase014_competitor','begin');
    perform dblink_exec(
      'phase014_competitor','set local lock_timeout=''5s'''
    );
    perform dblink_exec(
      'phase014_competitor','set local statement_timeout=''8s'''
    );
    if dblink_send_query('phase014_competitor',v_worker_query)<>1 then
      raise exception 'could not dispatch competitor for %',v_case;
    end if;
    perform pg_sleep(0.25);
    if dblink_is_busy('phase014_competitor')<>1 then
      raise exception 'concurrent % did not serialize behind finalization',v_case;
    end if;

    perform dblink_exec('phase014_late_lock','rollback');
    select max(x) into v_finalized
    from dblink_get_result('phase014_finalizer') as t(x text);
    perform count(*)
    from dblink_get_result('phase014_finalizer') as t(x text);
    if v_finalized is distinct from v_expected then
      raise exception 'finalizer returned the wrong fingerprint for %',v_case;
    end if;
    perform dblink_exec('phase014_finalizer','rollback');
    select max(x) into v_worker_result
    from dblink_get_result('phase014_competitor') as t(x text);
    perform count(*)
    from dblink_get_result('phase014_competitor') as t(x text);
    perform dblink_exec('phase014_competitor','rollback');

    if v_case in ('METHOD_RETIREMENT','NORMALIZATION_RETIREMENT')
       and v_worker_result<>'RETIRED' then
      raise exception 'retirement competitor did not finish after serialization: %/%',
        v_case,v_worker_result;
    elsif v_case='SELECTION_REPLACEMENT'
       and v_worker_result !~ '^[0-9a-f-]{36}$' then
      raise exception 'selection competitor returned an invalid observation: %',
        v_worker_result;
    elsif v_case='SECOND_FINALIZER'
       and v_worker_result is distinct from v_expected then
      raise exception 'second finalizer did not replay the same sealed snapshot';
    end if;

    perform dblink_disconnect('phase014_late_lock');
    perform dblink_disconnect('phase014_finalizer');
    perform dblink_disconnect('phase014_competitor');
    if not exists (
      select 1 from public.fit_evaluations e
      where e.evaluation_id=v_evaluation
        and e.evaluation_state='BUILDING'
        and e.candidate_input_fingerprint=v_expected
        and e.decision_input_fingerprint is null
        and e.result_fingerprint is null
    ) then
      raise exception 'rolled-back concurrency race changed evaluation state: %',
        v_case;
    end if;
  end loop;
end;
$finalization_races$;
