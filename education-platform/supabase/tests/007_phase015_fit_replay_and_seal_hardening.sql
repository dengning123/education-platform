-- PHASE 015 FIT REPLAY AND SEAL HARDENING TEST.
-- Behavior mode runs after the committed 006 fixture and Migration 015.

begin;

set local search_path = public, private, extensions, pg_catalog;

do $test$
declare
  v_definition text;
  v_count integer;
begin
  if not exists (
       select 1 from information_schema.columns
       where table_schema = 'public'
         and table_name = 'fit_evaluations'
         and column_name = 'replay_contract_version'
     )
     or to_regclass('private.fit_evaluation_semantic_pins') is null
     or to_regprocedure(
       'public.finalize_fit_evaluation_v014_validator(uuid)'
     ) is null
     or to_regprocedure(
       'public.seal_fit_evaluation_inputs_v014(uuid)'
     ) is null then
    raise exception 'Phase 015 additive schema/API is incomplete';
  end if;

  select count(*) into v_count
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'private'
    and c.relname = 'fit_evaluation_semantic_pins'
    and c.relrowsecurity
    and c.relforcerowsecurity
    and pg_get_userbyid(c.relowner) = 'foundation_evaluation_executor';
  if v_count <> 1 then
    raise exception 'Phase 015 pin owner/forced-RLS contract is missing';
  end if;

  if not exists (
       select 1 from pg_policies
       where schemaname = 'private'
         and tablename = 'fit_evaluation_semantic_pins'
         and policyname = 'fit_evaluation_semantic_pins_executor_v015'
         and cmd = 'ALL'
         and roles = array['foundation_evaluation_executor']::name[]
     ) then
    raise exception 'Phase 015 executor pin policy is missing';
  end if;

  if not exists (
       select 1
       from pg_constraint c
       join pg_class t on t.oid = c.conrelid
       join pg_namespace n on n.oid = t.relnamespace
       where n.nspname = 'public'
         and t.relname = 'fit_financial_conversion_inputs_v014'
         and c.conname =
           'fit_financial_conversion_inputs_v014_intent_declaration_id_fkey'
         and c.contype = 'f'
         and c.confdeltype = 'c'
     ) then
    raise exception 'Phase 015 privacy cascade edge is missing';
  end if;

  v_definition := pg_get_functiondef(
    'public.compute_fit_decision_input_fingerprint(uuid)'::regprocedure
  );
  if v_definition not like '%financialContractVersion%'
     or v_definition not like '%financialSources%'
     or v_definition not like '%financialNormalizations%'
     or v_definition not like '%v_contract is null%' then
    raise exception 'Phase 015 replaced or weakened the frozen 014 fingerprint';
  end if;

  v_definition := pg_get_functiondef(
    'public.finalize_fit_evaluation_v014_validator(uuid)'::regprocedure
  );
  if v_definition not like '%validate_fit_financial_finalization_v014%'
     or v_definition not like '%financial_contract_version is null%' then
    raise exception 'Phase 015 did not preserve the complete 014 validator';
  end if;

  v_definition := pg_get_functiondef(
    'public.seal_fit_evaluation_inputs(uuid)'::regprocedure
  );
  if v_definition not like '%finalize_fit_evaluation_v014_validator%'
     or v_definition not like '%fit_v015_decision_input_payload%'
     or v_definition not like '%fit_evaluation_semantic_pins%' then
    raise exception 'Phase 015 seal does not validate and pin the 014 payload';
  end if;

  v_definition := pg_get_functiondef(
    'public.finalize_fit_evaluation(uuid)'::regprocedure
  );
  if v_definition not like '%Sealed Fit result changed after input sealing%'
     or v_definition like '%validate_fit_financial_live_pins_v014%'
     or v_definition like '%canonical_field_selections%'
     or v_definition like '%evidence_applicability_heads%' then
    raise exception 'Phase 015 finalizer reads live authority or omits output drift validation';
  end if;

  if not has_function_privilege(
       'service_role', 'public.seal_fit_evaluation_inputs(uuid)', 'EXECUTE'
     )
     or not has_function_privilege(
       'service_role', 'public.finalize_fit_evaluation(uuid)', 'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'public.finalize_fit_evaluation_v014_validator(uuid)', 'EXECUTE'
     )
     or has_function_privilege(
       'authenticated', 'public.finalize_fit_evaluation(uuid)', 'EXECUTE'
     ) then
    raise exception 'Phase 015 EXECUTE grant boundary is incorrect';
  end if;
end;
$test$;

\if :{?phase015_behavior_fixture}
do $test$
declare
  v_evaluation uuid;
  v_new_evaluation uuid;
  v_normalization uuid;
  v_student uuid;
  v_input_fingerprint text;
  v_finalized text;
  v_blocked boolean;
  v_is_superuser boolean;
begin
  select evaluation_id into strict v_evaluation
  from public.fit_evaluations
  where profile_version_id = '61400000-0000-0000-0000-000000000002'
    and evaluation_state = 'BUILDING'
    and candidate_input_fingerprint is null
  order by created_at desc
  limit 1;

  if (select replay_contract_version from public.fit_evaluations
      where evaluation_id = v_evaluation)
       <> 'FIT_REPLAY_SEAL_V015' then
    raise exception 'Migration 015 did not adopt the committed unsealed 006 fixture';
  end if;

  v_new_evaluation := public.start_fit_evaluation(
    '61400000-0000-0000-0000-000000000002',
    '61400000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000401',
    'v0.1',
    '30000000-0000-0000-0000-000000000001',
    '61400000-0000-0000-0000-000000000020'
  );
  if (select replay_contract_version from public.fit_evaluations
      where evaluation_id = v_new_evaluation)
       <> 'FIT_REPLAY_SEAL_V015' then
    raise exception 'New Fit evaluation did not receive the v015 discriminator';
  end if;

  v_input_fingerprint :=
    public.seal_fit_evaluation_inputs(v_evaluation);
  if not exists (
       select 1
       from private.fit_evaluation_semantic_pins p
       join public.fit_evaluations e using(evaluation_id)
       where p.evaluation_id = v_evaluation
         and p.replay_contract_version = 'FIT_REPLAY_SEAL_V015'
         and p.decision_input_fingerprint = v_input_fingerprint
         and p.decision_input_fingerprint = e.candidate_input_fingerprint
         and encode(
           extensions.digest(
             convert_to(p.semantic_envelope::text, 'UTF8'), 'sha256'
           ),
           'hex'
         ) = p.semantic_fingerprint
     ) then
    raise exception 'Phase 015 seal did not persist a self-consistent semantic pin';
  end if;

  v_blocked := false;
  begin
    update private.fit_evaluation_semantic_pins
    set result_fingerprint = repeat('a', 64)
    where evaluation_id = v_evaluation;
  exception when object_not_in_prerequisite_state then
    v_blocked := sqlerrm = 'Sealed Fit semantic pins are immutable';
  end;
  if not v_blocked then
    raise exception 'Phase 015 semantic pin remained directly mutable';
  end if;

  v_blocked := false;
  begin
    execute 'set local role service_role';
    perform count(*) from private.fit_evaluation_semantic_pins;
    execute 'reset role';
  exception when insufficient_privilege then
    v_blocked := true;
    execute 'reset role';
  end;
  if not v_blocked then
    raise exception 'service_role received forbidden direct semantic-pin access';
  end if;

  select rolsuper into v_is_superuser
  from pg_roles where rolname = current_user;
  if v_is_superuser then
    begin
      perform set_config('session_replication_role', 'replica', true);
      update private.fit_evaluation_semantic_pins
      set semantic_envelope = jsonb_set(
        semantic_envelope,
        '{decisionInputFingerprint}',
        to_jsonb(repeat('a', 64))
      )
      where evaluation_id = v_evaluation;
      perform set_config('session_replication_role', 'origin', true);

      v_blocked := false;
      begin
        perform public.finalize_fit_evaluation(v_evaluation);
      exception when object_not_in_prerequisite_state then
        v_blocked := sqlerrm in (
          'Sealed Fit semantic pin is missing or inconsistent',
          'Sealed Fit semantic pin is corrupt'
        );
      end;
      if not v_blocked then
        raise exception 'Phase 015 finalizer accepted physical semantic-pin tampering';
      end if;
      raise exception using
        errcode = 'P5415', message = 'rollback v015 semantic-pin tamper';
    exception when sqlstate 'P5415' then
      perform set_config('session_replication_role', 'origin', true);
    end;

    begin
      perform set_config('session_replication_role', 'replica', true);
      update public.fit_dimension_results
      set confidence = case confidence
        when 'HIGH' then 'LOW'::public.fit_confidence
        else 'HIGH'::public.fit_confidence
      end
      where evaluation_id = v_evaluation
        and dimension = 'ACADEMIC';
      perform set_config('session_replication_role', 'origin', true);

      v_blocked := false;
      begin
        perform public.finalize_fit_evaluation(v_evaluation);
      exception when object_not_in_prerequisite_state then
        v_blocked :=
          sqlerrm = 'Sealed Fit result changed after input sealing';
      end;
      if not v_blocked then
        raise exception 'Phase 015 finalizer accepted physical output tampering';
      end if;
      raise exception using
        errcode = 'P5515', message = 'rollback v015 output tamper';
    exception when sqlstate 'P5515' then
      perform set_config('session_replication_role', 'origin', true);
    end;
  end if;

  select n.financial_normalization_id into strict v_normalization
  from public.fit_financial_normalizations n
  join public.fit_financial_normalization_reviews_v014 r
    using(financial_normalization_id)
  where n.evaluation_id = v_evaluation
    and r.status = 'VERIFIED'
  order by n.financial_normalization_id
  limit 1;
  perform public.retire_fit_financial_normalization_v014(
    v_normalization, 'Phase 015 post-seal replay test'
  );

  v_finalized := public.finalize_fit_evaluation(v_evaluation);
  if v_finalized is distinct from v_input_fingerprint
     or not exists (
       select 1
       from public.fit_evaluations e
       join private.fit_evaluation_semantic_pins p using(evaluation_id)
       where e.evaluation_id = v_evaluation
         and e.evaluation_state = 'COMPLETED'
         and e.decision_input_fingerprint = p.decision_input_fingerprint
         and e.result_fingerprint = p.result_fingerprint
     ) then
    raise exception 'Phase 015 pinned finalization did not complete deterministically';
  end if;

  select p.student_id into strict v_student
  from public.student_profile_versions p
  where p.profile_version_id = '61400000-0000-0000-0000-000000000002';
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  if exists (
       select 1 from private.fit_evaluation_semantic_pins
       where evaluation_id = v_evaluation
     )
     or exists (
       select 1 from public.fit_evaluations
       where evaluation_id in (v_evaluation, v_new_evaluation)
     )
     or exists (
       select 1 from public.fit_financial_normalizations
       where evaluation_id = v_evaluation
     )
     or exists (
       select 1 from public.fit_financial_normalization_reviews_v014
       where evaluation_id = v_evaluation
     )
     or exists (
       select 1 from private.fit_financial_source_pins_v014
       where evaluation_id = v_evaluation
     )
     or exists (
       select 1 from private.fit_financial_normalization_verified_pins_v014
       where evaluation_id = v_evaluation
     ) then
    raise exception 'Privacy deletion retained v014/v015 Financial evaluation state';
  end if;
end;
$test$;
\endif

rollback;
