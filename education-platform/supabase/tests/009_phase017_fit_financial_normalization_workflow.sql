-- PHASE 017 FINANCIAL NORMALIZATION WORKFLOW TEST.
-- Runs after migrations 001-017 and proves method registration, role separation,
-- bounded resume projection, and no widening of frozen runtime table grants.

begin;

set local search_path = public, private, extensions, pg_catalog;

do $test$
declare
  v_definition text;
begin
  if (
    select count(*)
    from public.fit_financial_normalization_methods
    where normalization_method_id in (
      '30000000-0000-0000-0000-000000000174',
      '30000000-0000-0000-0000-000000000175'
    )
      and contract_release_id='30000000-0000-0000-0000-000000000001'
      and method_version=1
      and source_scope='TOTAL_COST' and target_scope='TOTAL_COST'
      and source_period='ACADEMIC_YEAR' and target_period='PROGRAM_DURATION'
      and source_basis='GROSS'
      and status='VERIFIED' and retired_at is null
      and verification_evidence_id='30000000-0000-0000-0000-000000000173'
  ) <> 2 then
    raise exception 'Phase 017 production normalization methods are invalid';
  end if;
  if not exists (
    select 1 from public.fit_financial_normalization_methods
    where normalization_method_id='30000000-0000-0000-0000-000000000174'
      and target_basis='GROSS'
      and normalization_contract->>'formulaCode'='MULTIPLY_SOURCE_BY_ACADEMIC_YEARS'
      and normalization_contract->>'calculationContract'='FIT_FINANCIAL_NORMALIZATION_CALC_V017'
      and normalization_contract->'allowedRoundingRules'='["NONE"]'::jsonb
  ) or not exists (
    select 1 from public.fit_financial_normalization_methods
    where normalization_method_id='30000000-0000-0000-0000-000000000175'
      and target_basis='NET_OF_VERIFIED_FUNDING'
      and normalization_contract->>'formulaCode'='MULTIPLY_SOURCE_BY_ACADEMIC_YEARS_THEN_SUBTRACT_FUNDING'
  ) then
    raise exception 'Phase 017 method formulas or axes drifted';
  end if;

  if pg_get_userbyid((select proowner from pg_proc where oid=
       'public.prepare_fit_financial_normalization_v017(uuid,uuid,uuid,uuid,text,integer,uuid,numeric,text,uuid)'::regprocedure))
       <> 'foundation_evaluation_executor'
     or not has_function_privilege('service_role',
       'public.prepare_fit_financial_normalization_v017(uuid,uuid,uuid,uuid,text,integer,uuid,numeric,text,uuid)','EXECUTE')
     or has_function_privilege('authenticated',
       'public.prepare_fit_financial_normalization_v017(uuid,uuid,uuid,uuid,text,integer,uuid,numeric,text,uuid)','EXECUTE') then
    raise exception 'Phase 017 preparation boundary is invalid';
  end if;
  if not has_function_privilege('foundation_evaluation_executor',
       'public.pin_fit_financial_source_v014(uuid,uuid,uuid)','EXECUTE')
     or not has_function_privilege('foundation_evaluation_executor',
       'public.insert_fit_financial_conversion_input_v014(public.fit_financial_conversion_inputs_v014)','EXECUTE')
     or not has_function_privilege('foundation_evaluation_executor',
       'public.insert_fit_financial_conversion_factor_v014(public.fit_financial_conversion_factors_v014)','EXECUTE') then
    raise exception 'Phase 017 preparation owner cannot compose the frozen v014 primitives';
  end if;

  if pg_get_userbyid((select proowner from pg_proc where oid=
       'public.review_fit_financial_normalization_v017(uuid,uuid)'::regprocedure))
       <> 'foundation_catalog_executor'
     or not has_function_privilege('authenticated',
       'public.review_fit_financial_normalization_v017(uuid,uuid)','EXECUTE')
     or has_function_privilege('service_role',
       'public.review_fit_financial_normalization_v017(uuid,uuid)','EXECUTE')
     or has_function_privilege('anon',
       'public.review_fit_financial_normalization_v017(uuid,uuid)','EXECUTE') then
    raise exception 'Phase 017 independent reviewer boundary is invalid';
  end if;
  if not has_schema_privilege('foundation_catalog_executor','private','USAGE')
     or not has_function_privilege('foundation_catalog_executor',
       'private.fit_financial_normalization_review_subject_v017(uuid)','EXECUTE')
     or has_function_privilege('authenticated',
       'private.fit_financial_normalization_review_subject_v017(uuid)','EXECUTE') then
    raise exception 'Phase 017 reviewer owner cannot use the private subject boundary safely';
  end if;

  if pg_get_userbyid((select proowner from pg_proc where oid=
       'public.get_fit_financial_normalization_resume_snapshot_v017(uuid,uuid[])'::regprocedure))
       <> 'foundation_evaluation_executor'
     or not has_function_privilege('service_role',
       'public.get_fit_financial_normalization_resume_snapshot_v017(uuid,uuid[])','EXECUTE')
     or has_function_privilege('authenticated',
       'public.get_fit_financial_normalization_resume_snapshot_v017(uuid,uuid[])','EXECUTE') then
    raise exception 'Phase 017 resume snapshot boundary is invalid';
  end if;

  if has_table_privilege('service_role','public.fit_financial_normalization_reviews_v014','SELECT')
     or has_table_privilege('service_role','public.fit_financial_conversion_inputs_v014','SELECT')
     or has_table_privilege('service_role','public.fit_financial_conversion_factors_v014','SELECT')
     or has_table_privilege('authenticated','public.fit_financial_normalization_reviews_v014','UPDATE') then
    raise exception 'Phase 017 widened frozen Financial normalization table privileges';
  end if;

  if (
    select count(*)
    from public.foundation_function_contracts contract
    join pg_proc procedure
      on procedure.proname=contract.function_name
     and pg_get_function_identity_arguments(procedure.oid)=contract.identity_arguments
    join pg_namespace namespace
      on namespace.oid=procedure.pronamespace
     and namespace.nspname=contract.schema_name
    where (contract.schema_name,contract.function_name) in (
      ('public','prepare_fit_financial_normalization_v017'),
      ('private','fit_financial_normalization_review_subject_v017'),
      ('public','review_fit_financial_normalization_v017'),
      ('public','get_fit_financial_normalization_resume_snapshot_v017')
    )
      and contract.prosecdef
      and contract.body_digest=encode(extensions.digest(
        convert_to(pg_get_functiondef(procedure.oid),'UTF8'),'sha256'),'hex')
  ) <> 4 then
    raise exception 'Phase 017 functions are not contract-registered';
  end if;

  v_definition := pg_get_functiondef(
    'public.review_fit_financial_normalization_v017(uuid,uuid)'::regprocedure
  );
  if v_definition not like '%fit_normalization_reviewer%'
     or v_definition not like '%ownerAuthUserId%'
     or v_definition not like '%Independent review evidence must differ%'
     or v_definition like '%service_role%' then
    raise exception 'Phase 017 reviewer function lacks the closed independence checks';
  end if;
  v_definition := pg_get_functiondef(
    'public.get_fit_financial_normalization_resume_snapshot_v017(uuid,uuid[])'::regprocedure
  );
  if v_definition not like '%review.status = ''VERIFIED''%'
     or v_definition not like '%evaluation_state = ''BUILDING''%'
     or v_definition not like '%row_value.numeric_value::text%'
     or v_definition not like '%row_value.factor_value::text%'
     or v_definition like '%execute format%'
     or v_definition like '%auth.users%' then
    raise exception 'Phase 017 resume snapshot is not a static bounded projection';
  end if;
end;
$test$;

rollback;
