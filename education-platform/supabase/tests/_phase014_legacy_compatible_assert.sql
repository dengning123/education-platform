begin;

do $assert_legacy$
declare
  v_empty uuid;
  v_completed uuid;
  v_blocked boolean;
  v_before record;
begin
  select evaluation_id into v_empty
  from public.phase014_compat_probe where case_code='EMPTY_BUILDING';
  select * into v_before
  from public.phase014_compat_probe where case_code='COMPLETED';
  v_completed:=v_before.evaluation_id;

  if (select financial_contract_version from public.fit_evaluations
      where evaluation_id=v_empty) is not null then
    raise exception 'empty legacy BUILDING evaluation was implicitly relabeled';
  end if;
  if not exists (
    select 1 from public.fit_evaluations e
    where e.evaluation_id=v_completed
      and e.evaluation_state='COMPLETED'
      and e.financial_contract_version is null
      and e.candidate_input_fingerprint=v_before.expected_candidate_input_fingerprint
      and e.decision_input_fingerprint=v_before.expected_decision_input_fingerprint
      and e.result_fingerprint=v_before.expected_result_fingerprint
      and e.evaluated_at='2026-08-20 00:00:00+00'
      and e.finalized_by='phase014-legacy-fixture'
  ) then
    raise exception 'completed legacy evaluation was relabeled or rewritten';
  end if;

  execute 'set local role service_role';
  perform public.adopt_fit_financial_contract_v014(v_empty);
  execute 'reset role';
  if (select financial_contract_version from public.fit_evaluations
      where evaluation_id=v_empty)<>'FINANCIAL_BILLING_BASIS_V014' then
    raise exception 'authorized empty legacy evaluation did not adopt v014';
  end if;

  v_blocked:=false;
  begin
    execute 'set local role service_role';
    perform public.adopt_fit_financial_contract_v014(v_empty);
    execute 'reset role';
  exception when object_not_in_prerequisite_state then
    v_blocked:=sqlerrm='Only an unsealed legacy BUILDING evaluation may adopt v014';
    execute 'reset role';
  end;
  if not v_blocked then raise exception 'already-adopted evaluation re-adopted'; end if;

  v_blocked:=false;
  begin
    execute 'set local role service_role';
    perform public.adopt_fit_financial_contract_v014(v_completed);
    execute 'reset role';
  exception when object_not_in_prerequisite_state then
    v_blocked:=sqlerrm='Only an unsealed legacy BUILDING evaluation may adopt v014';
    execute 'reset role';
  end;
  if not v_blocked then raise exception 'completed legacy evaluation adopted v014'; end if;

  v_blocked:=false;
  begin
    update public.fit_evaluations
    set financial_contract_version='FINANCIAL_BILLING_BASIS_V014'
    where evaluation_id=v_completed;
  exception when object_not_in_prerequisite_state then
    v_blocked:=true;
  end;
  if not v_blocked
     or (select financial_contract_version from public.fit_evaluations
         where evaluation_id=v_completed) is not null then
    raise exception 'completed legacy discriminator was directly mutated';
  end if;
end
$assert_legacy$;

rollback;
