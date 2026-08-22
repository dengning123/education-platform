begin;

\if :{?phase014_commit_fixture}
set local phase014.commit_fixture = 'on';
\else
set local phase014.commit_fixture = 'off';
\endif

create extension if not exists dblink with schema extensions;
set local search_path = public, extensions, pg_catalog;

do $test$
declare
  v_labels text[];
begin
  select array_agg(x::text order by enumsortorder) into v_labels
  from pg_enum e join pg_type t on t.oid=e.enumtypid
  cross join lateral (select e.enumlabel::public.billing_basis x) q
  where t.typname='billing_basis';
  if v_labels is distinct from array['TOTAL_PROGRAM','PER_YEAR','PER_SEMESTER','PER_CREDIT','UNKNOWN'] then
    raise exception 'billing_basis enum exhaustiveness failed: %',v_labels;
  end if;
  if public.fit_financial_period_for_billing_basis('TOTAL_PROGRAM')<>'PROGRAM_DURATION'
     or public.fit_financial_period_for_billing_basis('PER_YEAR')<>'ACADEMIC_YEAR'
     or public.fit_financial_period_for_billing_basis('PER_SEMESTER')<>'ACADEMIC_SEMESTER'
     or public.fit_financial_period_for_billing_basis('PER_CREDIT')<>'CREDIT'
     or public.fit_financial_period_for_billing_basis('UNKNOWN') is not null
     or public.fit_financial_period_for_billing_basis(null) is not null then
    raise exception 'closed billing-basis mapping failed';
  end if;
end;
$test$;

do $test$
declare
  s public.fit_financial_period;
  t public.fit_financial_period;
  expected boolean;
  actual boolean;
begin
  foreach s in array array['PROGRAM_DURATION','ACADEMIC_YEAR','ACADEMIC_SEMESTER','CREDIT']::public.fit_financial_period[] loop
    foreach t in array array['MONTH','ACADEMIC_YEAR','CALENDAR_YEAR','PROGRAM_DURATION','ACADEMIC_SEMESTER','CREDIT']::public.fit_financial_period[] loop
      expected := s=t;
      actual := public.fit_financial_facts_directly_comparable(
        'USD',s,'COMPONENT','GROSS',array['TUITION','MANDATORY_FEES'],
        'USD',t,'COMPONENT','GROSS',array['MANDATORY_FEES','TUITION']);
      if actual is distinct from expected then
        raise exception 'period matrix mismatch: % -> %, expected %, got %',s,t,expected,actual;
      end if;
    end loop;
  end loop;
  if public.fit_financial_facts_directly_comparable(
      'USD','ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'],
      'EUR','ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'])
     or public.fit_financial_facts_directly_comparable(
      'USD','ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'],
      'USD','ACADEMIC_YEAR','TOTAL_COST','GROSS',array['TUITION'])
     or public.fit_financial_facts_directly_comparable(
      'USD','ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'],
      'USD','ACADEMIC_YEAR','COMPONENT','NET_OF_VERIFIED_FUNDING',array['TUITION'])
     or public.fit_financial_facts_directly_comparable(
      'USD','ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'],
      'USD','ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION','MANDATORY_FEES'])
     or public.fit_financial_facts_directly_comparable(
      null,'ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'],
      'USD','ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'])
     or public.fit_financial_facts_directly_comparable(
      'USD','ACADEMIC_YEAR','COMPONENT','GROSS','{}',
      'USD','ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION']) then
    raise exception 'direct-comparability mismatch did not fail closed';
  end if;
end;
$test$;

do $test$
declare
  n integer;
  d text;
begin
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='fit_evaluations' and column_name='financial_contract_version')
     or to_regclass('private.fit_financial_source_pins_v014') is null
     or to_regclass('public.fit_financial_normalization_reviews_v014') is null
     or to_regclass('public.fit_financial_conversion_inputs_v014') is null
     or to_regclass('public.fit_financial_conversion_factors_v014') is null
     or to_regclass('private.fit_financial_normalization_verified_pins_v014') is null then
    raise exception 'v014 additive schema is incomplete';
  end if;
  select count(*) into n from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
  where ns.nspname in ('public','private') and c.relname in (
    'fit_financial_source_pins_v014','fit_financial_normalization_reviews_v014',
    'fit_financial_conversion_inputs_v014','fit_financial_conversion_factors_v014',
    'fit_financial_normalization_verified_pins_v014')
    and c.relrowsecurity and c.relforcerowsecurity
    and pg_get_userbyid(c.relowner)='foundation_evaluation_executor';
  if n<>5 then raise exception 'v014 owner/forced-RLS contract failed: %/5',n; end if;
  if has_schema_privilege('foundation_evaluation_executor','public','CREATE')
     or has_schema_privilege('foundation_evaluation_executor','private','CREATE') then
    raise exception 'evaluation executor retained schema CREATE';
  end if;
  if not has_table_privilege(
       'foundation_evaluation_executor','public.program_costs','UPDATE')
     or not exists (
       select 1 from pg_policies
       where schemaname='public' and tablename='program_costs'
         and policyname='program_costs_evaluation_executor_lock_v014'
         and cmd='UPDATE'
         and roles=array['foundation_evaluation_executor']::name[]
         and with_check='false'
     ) then
    raise exception 'program_costs lock-only permission contract is missing';
  end if;
  if not has_table_privilege(
       'foundation_evaluation_executor',
       'public.fit_financial_normalization_methods','UPDATE')
     or not has_table_privilege(
       'foundation_evaluation_executor',
       'public.fit_intent_financial_constraints','UPDATE')
     or not has_table_privilege(
       'foundation_evaluation_executor',
       'public.fit_intent_declarations','UPDATE')
     or (select pg_get_userbyid(proowner)
         from pg_proc where oid=
           'public.validate_fit_financial_normalization()'::regprocedure)
        <>'foundation_evaluation_executor'
     or (select count(*) from pg_policies
         where schemaname='public'
           and policyname in (
             'fit_financial_methods_evaluation_executor_lock_v014',
             'fit_intent_financial_constraints_evaluation_executor_lock_v014',
             'fit_intent_declarations_evaluation_executor_lock_v014'
           ) and cmd='UPDATE'
           and roles=array['foundation_evaluation_executor']::name[]
           and with_check='false')<>3 then
    raise exception 'Financial method/intent lock-only owner contract is missing';
  end if;
  if has_function_privilege('authenticated','public.pin_fit_financial_source_v014(uuid,uuid,uuid)','EXECUTE')
     or not has_function_privilege('service_role','public.pin_fit_financial_source_v014(uuid,uuid,uuid)','EXECUTE')
     or not has_function_privilege('foundation_catalog_executor','public.verify_fit_financial_normalization_v014(uuid,text,uuid)','EXECUTE')
     or has_function_privilege('service_role','public.verify_fit_financial_normalization_v014(uuid,text,uuid)','EXECUTE')
     or not has_function_privilege('foundation_evaluation_executor','public.fit_financial_period_for_billing_basis(public.billing_basis)','EXECUTE')
     or not has_function_privilege('foundation_evaluation_executor','public.fit_financial_facts_directly_comparable(text,public.fit_financial_period,public.fit_financial_scope,public.fit_financial_basis,text[],text,public.fit_financial_period,public.fit_financial_scope,public.fit_financial_basis,text[])','EXECUTE')
     or not has_function_privilege('foundation_evaluation_executor','private.validate_fit_financial_live_pins_v014(uuid)','EXECUTE')
     or has_function_privilege('service_role','private.validate_fit_financial_live_pins_v014(uuid)','EXECUTE') then
    raise exception 'v014 EXECUTE grant contract failed';
  end if;
  d:=pg_get_functiondef('public.compute_fit_decision_input_fingerprint(uuid)'::regprocedure);
  if d not like '%financialContractVersion%' or d not like '%financialSources%'
     or d not like '%financialNormalizations%' or d not like '%v_contract is null%' then
    raise exception 'v014 fingerprint discriminator/payload branch is missing';
  end if;
  d:=pg_get_functiondef('public.finalize_fit_evaluation(uuid)'::regprocedure);
  if d not like '%validate_fit_financial_finalization_v014%'
     or d not like '%financial_contract_version is null%' then
    raise exception 'legacy/v014 finalization branch is missing';
  end if;
  d:=pg_get_functiondef(
    'private.validate_fit_financial_finalization_v014(uuid)'::regprocedure
  );
  if d not like '%validate_fit_financial_live_pins_v014%' then
    raise exception 'v014 finalization does not recompute persisted live pins';
  end if;
end;
$test$;

do $test$
declare blocked boolean:=false;
begin
  begin
    execute 'set local role service_role';
    perform count(*) from public.fit_financial_conversion_inputs_v014;
    execute 'reset role';
  exception when insufficient_privilege then
    blocked:=true;
    execute 'reset role';
  end;
  if not blocked then raise exception 'service_role received forbidden direct typed-input table access'; end if;
end;
$test$;

-- Fixture-driven v014 behavior. Every row is transaction-local and uses a
-- dedicated UUID namespace so the test can run against a populated 013->014
-- upgrade without depending on incidental production identities.
create function pg_temp.accept_v014_cost_observation(
  p_field_name text,
  p_value jsonb
)
returns uuid
language plpgsql
as $fixture$
declare
  v_prior uuid;
  v_scope uuid;
  v_assertion uuid;
  v_observation uuid;
begin
  select observation_id into v_prior
  from public.canonical_field_selections
  where record_type='PROGRAM_COST'
    and record_id='00000000-0000-0000-0000-000000000404'
    and field_name=p_field_name;
  v_scope := public.create_evidence_scope(
    '00000000-0000-0000-0000-000000000705',
    'PROGRAM_COST','00000000-0000-0000-0000-000000000404',p_field_name,
    'UNSPECIFIED','UNSPECIFIED','UNSPECIFIED'
  );
  v_assertion := public.review_evidence_applicability(
    v_scope,'REVIEWED_APPLICABLE','phase014-test','v014 behavior fixture'
  );
  v_observation := public.create_field_observation(
    'PROGRAM_COST','00000000-0000-0000-0000-000000000404',p_field_name,
    p_value,'KNOWN','00000000-0000-0000-0000-000000000705',v_prior,
    'Migration 014 transaction-local behavior fixture.',v_assertion
  );
  perform public.accept_field_observation(v_observation,'phase014-test');
  return v_observation;
end;
$fixture$;

create function pg_temp.create_v014_normalization_fixture(
  p_evaluation uuid,
  p_amount_observation uuid,
  p_source_pin uuid,
  p_method uuid default '61400000-0000-0000-0000-000000000021'
)
returns uuid
language plpgsql
as $fixture$
declare v_normalization uuid;
begin
  insert into public.fit_financial_normalizations (
    evaluation_id,profile_version_id,field_observation_id,
    financial_constraint_id,intent_set_id,normalization_method_id,
    conversion_evidence_id,original_amount,original_currency,
    original_period,original_scope,original_basis,original_components,
    target_amount,target_currency,target_period,target_scope,target_basis,
    target_components,conversion_evidence,source_pin_id
  ) values (
    p_evaluation,'61400000-0000-0000-0000-000000000002',
    p_amount_observation,'61400000-0000-0000-0000-000000000011',
    '61400000-0000-0000-0000-000000000010',
    p_method,
    '00000000-0000-0000-0000-000000000705',60000,'USD',
    'ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'],
    90000,'USD','PROGRAM_DURATION','COMPONENT','GROSS',array['TUITION'],
    '{"formula":"fixture"}',p_source_pin
  ) returning financial_normalization_id into v_normalization;
  return v_normalization;
end;
$fixture$;

create function pg_temp.create_v014_net_normalization_fixture(
  p_evaluation uuid,
  p_amount_observation uuid,
  p_source_pin uuid
)
returns uuid
language plpgsql
as $fixture$
declare v_normalization uuid;
begin
  insert into public.fit_financial_normalizations (
    evaluation_id,profile_version_id,field_observation_id,
    financial_constraint_id,intent_set_id,normalization_method_id,
    conversion_evidence_id,original_amount,original_currency,
    original_period,original_scope,original_basis,original_components,
    target_amount,target_currency,target_period,target_scope,target_basis,
    target_components,conversion_evidence,source_pin_id
  ) values (
    p_evaluation,'61400000-0000-0000-0000-000000000002',
    p_amount_observation,'61400000-0000-0000-0000-000000000013',
    '61400000-0000-0000-0000-000000000010',
    '61400000-0000-0000-0000-000000000022',
    '00000000-0000-0000-0000-000000000705',60000,'USD',
    'ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'],
    90000,'USD','PROGRAM_DURATION','COMPONENT','NET_OF_VERIFIED_FUNDING',
    array['TUITION'],'{"formula":"fixture-net"}',p_source_pin
  ) returning financial_normalization_id into v_normalization;
  return v_normalization;
end;
$fixture$;

do $test$
declare
  v_method record;
  v_policy record;
  v_amount_observation uuid;
  v_basis_observation uuid;
  v_evaluation uuid;
  v_amount_item uuid;
  v_basis_item uuid;
  v_duplicate_amount_item uuid;
  v_duplicate_basis_item uuid;
  v_budget_item uuid;
  v_intent_item uuid;
  v_net_intent_item uuid;
  v_funding_intent_item uuid;
  v_normalization_item uuid;
  v_net_normalization_item uuid;
  v_duplicate_normalization_item uuid;
  v_result uuid;
  v_signal uuid;
  v_net_signal uuid;
  v_source_pin uuid;
  v_duplicate_source_pin uuid;
  v_normalization uuid := '61400000-0000-0000-0000-000000000050';
  v_net_normalization uuid := '61400000-0000-0000-0000-000000000052';
  v_duplicate_normalization uuid := '61400000-0000-0000-0000-000000000051';
  v_blocked boolean;
  v_payload jsonb;
  v_fingerprint text;
  v_finalized text;
  v_state uuid;
  v_inserted_state uuid;
  v_other_result uuid;
  v_scope uuid;
  v_assertion uuid;
  v_attack_observation uuid;
  v_attack_item uuid;
  v_attack_status public.knowledge_status;
  v_conn text;
  v_attack_case text;
  v_attack_normalization uuid;
  v_typed_failures text[] := '{}';
  v_funding_case text;
  v_funding_failures text[] := '{}';
  v_live_pin_case text;
  v_live_pin_failures text[] := '{}';
  v_mutated_payload jsonb;
begin
  -- Build only the frozen student/intent and verified registry state needed by
  -- the v014 source/normalization APIs.
  insert into public.students (student_id)
  values ('61400000-0000-0000-0000-000000000001');
  insert into public.student_profile_versions (
    profile_version_id,student_id,version_number
  ) values (
    '61400000-0000-0000-0000-000000000002',
    '61400000-0000-0000-0000-000000000001',1
  );
  insert into public.student_evidence_items (
    student_evidence_id,profile_version_id,evidence_type,content_hash
  ) values (
    '61400000-0000-0000-0000-000000000003',
    '61400000-0000-0000-0000-000000000002','SELF_REPORT',repeat('6',64)
  );
  insert into public.student_preferences (
    student_preference_id,profile_version_id,preference_type,value,priority
  ) values (
    '61400000-0000-0000-0000-000000000004',
    '61400000-0000-0000-0000-000000000002','BUDGET',
    '{"amount":90000,"currency":"USD","period":"PROGRAM_DURATION"}',5
  );
  insert into public.student_data_completeness (
    profile_version_id,domain,completeness
  ) select '61400000-0000-0000-0000-000000000002',domain,'COMPLETE'
    from unnest(enum_range(null::public.student_data_domain)) domain;
  perform public.freeze_student_profile_version(
    '61400000-0000-0000-0000-000000000002'
  );

  insert into public.fit_intent_sets (
    intent_set_id,profile_version_id,version_number
  ) values (
    '61400000-0000-0000-0000-000000000010',
    '61400000-0000-0000-0000-000000000002',1
  );
  insert into public.fit_intent_declarations (
    intent_declaration_id,intent_set_id,profile_version_id,origin,dimension,
    semantic_type,importance,importance_basis,importance_evidence_id,
    interpretation_method,interpretation_method_version,
    interpretation_provenance,student_evidence_id
  ) values
    ('61400000-0000-0000-0000-000000000011',
     '61400000-0000-0000-0000-000000000010',
     '61400000-0000-0000-0000-000000000002','PHASE3_DECLARATION','FINANCIAL',
     'FINANCIAL_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION',
     '61400000-0000-0000-0000-000000000003','HUMAN','1',
     'Program-duration tuition preference.','61400000-0000-0000-0000-000000000003'),
    ('61400000-0000-0000-0000-000000000012',
     '61400000-0000-0000-0000-000000000010',
     '61400000-0000-0000-0000-000000000002','PHASE3_DECLARATION','FINANCIAL',
     'FINANCIAL_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION',
     '61400000-0000-0000-0000-000000000003','HUMAN','1',
     'Available funding kept separate from cost.','61400000-0000-0000-0000-000000000003'),
    ('61400000-0000-0000-0000-000000000013',
     '61400000-0000-0000-0000-000000000010',
     '61400000-0000-0000-0000-000000000002','PHASE3_DECLARATION','FINANCIAL',
     'FINANCIAL_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION',
     '61400000-0000-0000-0000-000000000003','HUMAN','1',
     'Net tuition preference remains distinct from available funding.',
     '61400000-0000-0000-0000-000000000003'),
    ('61400000-0000-0000-0000-000000000014',
     '61400000-0000-0000-0000-000000000010',
     '61400000-0000-0000-0000-000000000002','PHASE3_DECLARATION','FINANCIAL',
     'FINANCIAL_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION',
     '61400000-0000-0000-0000-000000000003','HUMAN','1',
     'Alternative funding must not be silently combined.',
     '61400000-0000-0000-0000-000000000003');
  insert into public.fit_intent_financial_constraints values
    ('61400000-0000-0000-0000-000000000011',
     '61400000-0000-0000-0000-000000000010',
     '61400000-0000-0000-0000-000000000002',90000,'PREFERRED_TUITION',
     'USD','COMPONENT','PROGRAM_DURATION','GROSS',array['TUITION']),
    ('61400000-0000-0000-0000-000000000012',
     '61400000-0000-0000-0000-000000000010',
     '61400000-0000-0000-0000-000000000002',20000,'AVAILABLE_FUNDING',
     'USD','COMPONENT','PROGRAM_DURATION','GROSS',array['TUITION']),
    ('61400000-0000-0000-0000-000000000013',
     '61400000-0000-0000-0000-000000000010',
     '61400000-0000-0000-0000-000000000002',90000,'PREFERRED_TUITION',
     'USD','COMPONENT','PROGRAM_DURATION','NET_OF_VERIFIED_FUNDING',
     array['TUITION']),
    ('61400000-0000-0000-0000-000000000014',
     '61400000-0000-0000-0000-000000000010',
     '61400000-0000-0000-0000-000000000002',10000,'AVAILABLE_FUNDING',
     'USD','COMPONENT','PROGRAM_DURATION','GROSS',
     array['TUITION']);
  if public.freeze_fit_intent_set(
      '61400000-0000-0000-0000-000000000010')='VALIDATION_FAILED' then
    raise exception 'v014 Financial intent fixture did not freeze';
  end if;

  insert into public.fit_evaluator_builds (
    evaluator_build_id,contract_release_id,evaluator_name,
    evaluator_version,build_hash
  ) values (
    '61400000-0000-0000-0000-000000000020',
    '30000000-0000-0000-0000-000000000001',
    'phase014-behavior-test','0.14.0',repeat('d',64)
  );
  perform public.verify_fit_definition(
    'EVALUATOR_BUILD','61400000-0000-0000-0000-000000000020',
    'phase014-reviewer','00000000-0000-0000-0000-000000000705'
  );
  for v_method in
    select method_id from public.fit_dimension_methods
    where contract_release_id='30000000-0000-0000-0000-000000000001'
      and status='DRAFT'
  loop
    perform public.verify_fit_definition(
      'METHOD',v_method.method_id,'phase014-reviewer',
      '00000000-0000-0000-0000-000000000705'
    );
  end loop;

  insert into public.fit_financial_normalization_methods (
    normalization_method_id,contract_release_id,method_code,method_version,
    source_scope,target_scope,source_period,target_period,
    source_basis,target_basis,source_currency,target_currency,
    normalization_contract
  ) values (
    '61400000-0000-0000-0000-000000000021',
    '30000000-0000-0000-0000-000000000001','ANNUAL_TO_PROGRAM',1,
    'COMPONENT','COMPONENT','ACADEMIC_YEAR','PROGRAM_DURATION',
    'GROSS','GROSS','USD','USD',
    jsonb_build_object(
      'formulaCode','MULTIPLY_SOURCE_BY_ACADEMIC_YEARS',
      'requiredInputRoles',jsonb_build_array('SOURCE_AMOUNT','ACADEMIC_YEARS','ROUNDING'),
      'allowedInputRoles',jsonb_build_array('SOURCE_AMOUNT','ACADEMIC_YEARS','ROUNDING'),
      'requiredFactorCodes',jsonb_build_array('ACADEMIC_YEARS'),
      'allowedFactorCodes',jsonb_build_array('ACADEMIC_YEARS')
    )
  );
  perform public.verify_fit_definition(
    'FINANCIAL_NORMALIZATION','61400000-0000-0000-0000-000000000021',
    'phase014-reviewer','00000000-0000-0000-0000-000000000705'
  );
  insert into public.fit_financial_normalization_methods (
    normalization_method_id,contract_release_id,method_code,method_version,
    source_scope,target_scope,source_period,target_period,
    source_basis,target_basis,source_currency,target_currency,
    normalization_contract
  ) values (
    '61400000-0000-0000-0000-000000000022',
    '30000000-0000-0000-0000-000000000001','ANNUAL_TO_NET_PROGRAM',1,
    'COMPONENT','COMPONENT','ACADEMIC_YEAR','PROGRAM_DURATION',
    'GROSS','NET_OF_VERIFIED_FUNDING','USD','USD',
    jsonb_build_object(
      'formulaCode','MULTIPLY_SOURCE_BY_ACADEMIC_YEARS_THEN_SUBTRACT_FUNDING',
      'requiredInputRoles',jsonb_build_array(
        'SOURCE_AMOUNT','ACADEMIC_YEARS','AVAILABLE_FUNDING','ROUNDING'),
      'allowedInputRoles',jsonb_build_array(
        'SOURCE_AMOUNT','ACADEMIC_YEARS','AVAILABLE_FUNDING','ROUNDING'),
      'requiredFactorCodes',jsonb_build_array('ACADEMIC_YEARS','AVAILABLE_FUNDING'),
      'allowedFactorCodes',jsonb_build_array('ACADEMIC_YEARS','AVAILABLE_FUNDING')
    )
  );
  perform public.verify_fit_definition(
    'FINANCIAL_NORMALIZATION','61400000-0000-0000-0000-000000000022',
    'phase014-reviewer','00000000-0000-0000-0000-000000000705'
  );
  insert into public.fit_financial_normalization_methods (
    normalization_method_id,contract_release_id,method_code,method_version,
    source_scope,target_scope,source_period,target_period,
    source_basis,target_basis,source_currency,target_currency,
    normalization_contract
  ) values (
    '61400000-0000-0000-0000-000000000023',
    '30000000-0000-0000-0000-000000000001','UNSUPPORTED_FORMULA',1,
    'COMPONENT','COMPONENT','ACADEMIC_YEAR','PROGRAM_DURATION',
    'GROSS','GROSS','USD','USD',
    jsonb_build_object(
      'formulaCode','UNIMPLEMENTED_FREE_FORM_FORMULA',
      'requiredInputRoles',jsonb_build_array('SOURCE_AMOUNT','ACADEMIC_YEARS','ROUNDING'),
      'allowedInputRoles',jsonb_build_array('SOURCE_AMOUNT','ACADEMIC_YEARS','ROUNDING'),
      'requiredFactorCodes',jsonb_build_array('ACADEMIC_YEARS'),
      'allowedFactorCodes',jsonb_build_array('ACADEMIC_YEARS')
    )
  );
  perform public.verify_fit_definition(
    'FINANCIAL_NORMALIZATION','61400000-0000-0000-0000-000000000023',
    'phase014-reviewer','00000000-0000-0000-0000-000000000705'
  );

  v_amount_observation := pg_temp.accept_v014_cost_observation(
    'tuition_amount',to_jsonb(60000::numeric)
  );
  perform pg_temp.accept_v014_cost_observation('currency',to_jsonb('USD'::text));
  v_basis_observation := pg_temp.accept_v014_cost_observation(
    'billing_basis',to_jsonb('PER_YEAR'::text)
  );

  v_evaluation := public.start_fit_evaluation(
    '61400000-0000-0000-0000-000000000002',
    '61400000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000401','v0.1',
    '30000000-0000-0000-0000-000000000001',
    '61400000-0000-0000-0000-000000000020'
  );
  perform public.authorize_fit_evaluation_assembly(
    v_evaluation,repeat('d',64)
  );
  if (select financial_contract_version from public.fit_evaluations
      where evaluation_id=v_evaluation)<>'FINANCIAL_BILLING_BASIS_V014' then
    raise exception 'new evaluation did not receive the v014 discriminator';
  end if;
  v_blocked:=false;
  begin
    update public.fit_evaluations set financial_contract_version=null
    where evaluation_id=v_evaluation;
  exception when object_not_in_prerequisite_state then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'v014 discriminator remained caller-mutable'; end if;

  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    v_evaluation,'61400000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000103',
    '6f33306a-4e4f-bcb6-509a-e18b82539bb4',
    'CATALOG_FIELD_OBSERVATION','AUTHORITATIVE'
  ) returning manifest_item_id into v_amount_item;
  insert into public.fit_manifest_catalog_observations values (
    v_amount_item,v_evaluation,'61400000-0000-0000-0000-000000000002',
    v_amount_observation
  );
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    v_evaluation,'61400000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000103',
    '6f33306a-4e4f-bcb6-509a-e18b82539bb4',
    'CATALOG_FIELD_OBSERVATION','AUTHORITATIVE'
  ) returning manifest_item_id into v_basis_item;
  insert into public.fit_manifest_catalog_observations values (
    v_basis_item,v_evaluation,'61400000-0000-0000-0000-000000000002',
    v_basis_observation
  );

  foreach v_attack_status in array
    array['STALE','SOURCE_CONFLICT']::public.knowledge_status[]
  loop
    begin
      v_scope:=public.create_evidence_scope(
        '00000000-0000-0000-0000-000000000705','PROGRAM_COST',
        '00000000-0000-0000-0000-000000000404','tuition_amount',
        'UNSPECIFIED','UNSPECIFIED','UNSPECIFIED'
      );
      v_assertion:=public.review_evidence_applicability(
        v_scope,'REVIEWED_APPLICABLE','phase014-test','adversarial source state'
      );
      v_attack_observation:=public.create_field_observation(
        'PROGRAM_COST','00000000-0000-0000-0000-000000000404',
        'tuition_amount',to_jsonb(60000::numeric),v_attack_status,
        '00000000-0000-0000-0000-000000000705',v_amount_observation,
        'v014 stale/conflict source attack.',v_assertion
      );
      perform public.select_field_observation(v_attack_observation,'phase014-test');
      insert into public.fit_manifest_items (
        evaluation_id,profile_version_id,method_id,input_policy_id,
        item_type,authority_role
      ) values (
        v_evaluation,'61400000-0000-0000-0000-000000000002',
        '30000000-0000-0000-0000-000000000103',
        '6f33306a-4e4f-bcb6-509a-e18b82539bb4',
        'CATALOG_FIELD_OBSERVATION','AUTHORITATIVE'
      ) returning manifest_item_id into v_attack_item;
      insert into public.fit_manifest_catalog_observations (
        manifest_item_id,evaluation_id,profile_version_id,field_observation_id
      ) values (
        v_attack_item,v_evaluation,
        '61400000-0000-0000-0000-000000000002',v_attack_observation
      );
      v_blocked:=false;
      begin
        perform public.pin_fit_financial_source_v014(
          v_evaluation,v_attack_item,v_basis_item
        );
      exception when check_violation then v_blocked:=true;
      end;
      if not v_blocked then
        raise exception 'source pin accepted % amount evidence',v_attack_status;
      end if;
      raise exception using errcode='P7781',message='rollback source-state attack';
    exception when sqlstate 'P7781' then null;
    end;
  end loop;

  begin
    v_scope:=public.create_evidence_scope(
      '00000000-0000-0000-0000-000000000705','PROGRAM_COST',
      '00000000-0000-0000-0000-000000000404','tuition_amount',
      'UNSPECIFIED','UNSPECIFIED','UNSPECIFIED'
    );
    perform public.review_evidence_applicability(
      v_scope,'REVIEWED_INAPPLICABLE','phase014-test','adversarial applicability change'
    );
    v_blocked:=false;
    begin
      perform public.pin_fit_financial_source_v014(
        v_evaluation,v_amount_item,v_basis_item
      );
    exception when check_violation then v_blocked:=true;
    end;
    if not v_blocked then
      raise exception 'source pin accepted an inapplicable current evidence head';
    end if;
    raise exception using errcode='P7782',message='rollback applicability attack';
  exception when sqlstate 'P7782' then null;
  end;

  v_source_pin := public.pin_fit_financial_source_v014(
    v_evaluation,v_amount_item,v_basis_item
  );
  select case when rolsuper
    then 'dbname=' || current_database()
    else 'host=host.docker.internal port=54322 dbname=' || current_database()
      || ' user=postgres password=postgres'
    end into v_conn
  from pg_roles where rolname=current_user;
  perform dblink_connect('phase014_cost_lock',v_conn);
  v_blocked:=false;
  begin
    perform 1 from dblink('phase014_cost_lock',format(
      'select 1 from public.program_costs where cost_id=%L for update nowait',
      '00000000-0000-0000-0000-000000000404'
    )) as locked(n int);
  exception when lock_not_available then v_blocked:=true;
  end;
  perform dblink_disconnect('phase014_cost_lock');
  if not v_blocked then
    raise exception 'source pin did not retain its canonical cost row lock';
  end if;
  v_payload := private.fit_financial_source_payload_v014(v_source_pin);
  if v_payload is null or v_payload ? 'sourcePinId'
     or v_payload->>'sourceBillingBasis'<>'PER_YEAR'
     or v_payload->>'sourcePeriod'<>'ACADEMIC_YEAR' then
    raise exception 'source pin payload is missing semantics or leaks incidental identity: %',v_payload;
  end if;
  v_blocked:=false;
  begin
    perform private.fit_financial_payload_collections_v014(v_evaluation);
  exception when check_violation then v_blocked:=true;
  end;
  if not v_blocked then
    raise exception 'unreferenced source pin was silently omitted from fingerprint collections';
  end if;

  -- Closed typed-contract matrix. Every case runs in its own subtransaction
  -- and is rolled back, so an erroneously accepted verification can be
  -- reported without contaminating the positive normalization fixture.
  foreach v_attack_case in array array[
    'MISSING_ROLE','EXTRA_ROLE','MISSING_FACTOR','EXTRA_FACTOR',
    'DUPLICATE_ORDINAL','DUPLICATE_ROLE','SOURCE_AMOUNT_VALUE',
    'SOURCE_AMOUNT_OBSERVATION','SOURCE_AMOUNT_UNIT','SOURCE_AMOUNT_TYPE',
    'SOURCE_AMOUNT_INTENT','YEARS_VALUE','YEARS_TYPE','YEARS_UNIT',
    'YEARS_OBSERVATION','YEARS_INTENT','ROUNDING_VALUE','ROUNDING_UNIT',
    'ROUNDING_OBSERVATION','ROUNDING_INTENT','FACTOR_OPERATION',
    'FACTOR_VALUE','FACTOR_UNITS'
  ] loop
    begin
      v_attack_normalization:=pg_temp.create_v014_normalization_fixture(
        v_evaluation,v_amount_observation,v_source_pin
      );
      perform public.insert_fit_financial_conversion_input_v014(row(
        null,v_attack_normalization,1,'SOURCE_AMOUNT',
        case when v_attack_case='SOURCE_AMOUNT_TYPE' then null::numeric
             when v_attack_case='SOURCE_AMOUNT_VALUE' then 59999::numeric
             else 60000::numeric end,
        case when v_attack_case='SOURCE_AMOUNT_TYPE' then '60000'::text
             else null::text end,
        case when v_attack_case='SOURCE_AMOUNT_UNIT' then 'EUR' else 'USD' end,
        case when v_attack_case='SOURCE_AMOUNT_OBSERVATION'
             then v_basis_observation else v_amount_observation end,
        case when v_attack_case='SOURCE_AMOUNT_INTENT'
             then '61400000-0000-0000-0000-000000000011'::uuid else null end,
        '00000000-0000-0000-0000-000000000705'
      )::public.fit_financial_conversion_inputs_v014);
      if v_attack_case<>'MISSING_ROLE' then
        perform public.insert_fit_financial_conversion_input_v014(row(
          null,v_attack_normalization,2,'ACADEMIC_YEARS',
          case when v_attack_case='YEARS_TYPE' then null::numeric
               when v_attack_case='YEARS_VALUE' then 0::numeric else 2::numeric end,
          case when v_attack_case='YEARS_TYPE' then '2'::text else null::text end,
          case when v_attack_case='YEARS_UNIT' then 'SEMESTER'
               else 'ACADEMIC_YEAR' end,
          case when v_attack_case='YEARS_OBSERVATION'
               then v_amount_observation else null end,
          case when v_attack_case='YEARS_INTENT'
               then '61400000-0000-0000-0000-000000000011'::uuid else null end,
          '00000000-0000-0000-0000-000000000705'
        )::public.fit_financial_conversion_inputs_v014);
      end if;
      perform public.insert_fit_financial_conversion_input_v014(row(
        null,v_attack_normalization,3,'ROUNDING',null,
        case when v_attack_case='ROUNDING_VALUE' then 'BANKERS' else 'NONE' end,
        case when v_attack_case='ROUNDING_UNIT' then 'TEXT' else 'RULE' end,
        case when v_attack_case='ROUNDING_OBSERVATION'
             then v_amount_observation else null end,
        case when v_attack_case='ROUNDING_INTENT'
             then '61400000-0000-0000-0000-000000000011'::uuid else null end,
        '00000000-0000-0000-0000-000000000705'
      )::public.fit_financial_conversion_inputs_v014);
      if v_attack_case='EXTRA_ROLE' then
        perform public.insert_fit_financial_conversion_input_v014(row(
          null,v_attack_normalization,4,'PROGRAM_DURATION',2,null,'ACADEMIC_YEAR',
          null,null,'00000000-0000-0000-0000-000000000705'
        )::public.fit_financial_conversion_inputs_v014);
      end if;
      if v_attack_case<>'MISSING_FACTOR' then
        perform public.insert_fit_financial_conversion_factor_v014(row(
          null,v_attack_normalization,1,'ACADEMIC_YEARS',
          case when v_attack_case='FACTOR_OPERATION' then 'DIVIDE' else 'MULTIPLY' end,
          case when v_attack_case='FACTOR_VALUE' then 3 else 2 end,
          case when v_attack_case='FACTOR_UNITS' then 'BAD_SOURCE'
               else 'USD_PER_ACADEMIC_YEAR' end,
          case when v_attack_case='FACTOR_UNITS' then 'BAD_TARGET'
               else 'USD_PER_PROGRAM_DURATION' end,
          '00000000-0000-0000-0000-000000000705'
        )::public.fit_financial_conversion_factors_v014);
      end if;
      if v_attack_case='EXTRA_FACTOR' then
        perform public.insert_fit_financial_conversion_factor_v014(row(
          null,v_attack_normalization,2,'EXTRA','ADD',1,'USD','USD',
          '00000000-0000-0000-0000-000000000705'
        )::public.fit_financial_conversion_factors_v014);
      end if;

      v_blocked:=false;
      if v_attack_case='DUPLICATE_ORDINAL' then
        begin
          perform public.insert_fit_financial_conversion_input_v014(row(
            null,v_attack_normalization,1,'SEMESTERS',2,null,'SEMESTER',
            null,null,'00000000-0000-0000-0000-000000000705'
          )::public.fit_financial_conversion_inputs_v014);
        exception when unique_violation then v_blocked:=true;
        end;
      elsif v_attack_case='DUPLICATE_ROLE' then
        begin
          perform public.insert_fit_financial_conversion_input_v014(row(
            null,v_attack_normalization,4,'SOURCE_AMOUNT',60000,null,'USD',
            v_amount_observation,null,'00000000-0000-0000-0000-000000000705'
          )::public.fit_financial_conversion_inputs_v014);
        exception when unique_violation then v_blocked:=true;
        end;
      else
        begin
          perform public.verify_fit_financial_normalization_v014(
            v_attack_normalization,'phase014-adversarial-reviewer',
            '00000000-0000-0000-0000-000000000705'
          );
        exception when check_violation then v_blocked:=true;
        end;
      end if;
      if not v_blocked then
        v_typed_failures:=array_append(v_typed_failures,v_attack_case);
      end if;
      raise exception using errcode='P7790',message='rollback typed attack';
    exception when sqlstate 'P7790' then null;
    end;
  end loop;
  if cardinality(v_typed_failures)>0 then
    raise exception 'typed normalization attacks were accepted: %',v_typed_failures;
  end if;

  begin
    v_attack_normalization:=pg_temp.create_v014_normalization_fixture(
      v_evaluation,v_amount_observation,v_source_pin,
      '61400000-0000-0000-0000-000000000023'
    );
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_attack_normalization,1,'SOURCE_AMOUNT',60000,null,'USD',
      v_amount_observation,null,'00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_inputs_v014);
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_attack_normalization,2,'ACADEMIC_YEARS',2,null,'ACADEMIC_YEAR',
      null,null,'00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_inputs_v014);
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_attack_normalization,3,'ROUNDING',null,'NONE','RULE',
      null,null,'00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_inputs_v014);
    perform public.insert_fit_financial_conversion_factor_v014(row(
      null,v_attack_normalization,1,'ACADEMIC_YEARS','MULTIPLY',2,
      'USD_PER_ACADEMIC_YEAR','USD_PER_PROGRAM_DURATION',
      '00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_factors_v014);
    v_blocked:=false;
    begin
      perform public.verify_fit_financial_normalization_v014(
        v_attack_normalization,'phase014-unsupported-formula-reviewer',
        '00000000-0000-0000-0000-000000000705'
      );
    exception when check_violation then
      v_blocked:=sqlerrm='Unsupported Financial normalization formulaCode';
    end;
    if not v_blocked then
      raise exception 'unsupported formulaCode authorized a normalization';
    end if;
    raise exception using errcode='P7792',message='rollback formula attack';
  exception when sqlstate 'P7792' then null;
  end;

  foreach v_funding_case in array array[
    'MISSING_INPUT','WRONG_VALUE','WRONG_UNIT','WRONG_INTENT',
    'FUNDING_OBSERVATION','MISSING_FACTOR','FACTOR_OPERATION',
    'FACTOR_VALUE','FACTOR_UNITS'
  ] loop
    begin
      v_attack_normalization:=pg_temp.create_v014_net_normalization_fixture(
        v_evaluation,v_amount_observation,v_source_pin
      );
      perform public.insert_fit_financial_conversion_input_v014(row(
        null,v_attack_normalization,1,'SOURCE_AMOUNT',60000,null,'USD',
        v_amount_observation,null,'00000000-0000-0000-0000-000000000705'
      )::public.fit_financial_conversion_inputs_v014);
      perform public.insert_fit_financial_conversion_input_v014(row(
        null,v_attack_normalization,2,'ACADEMIC_YEARS',2,null,'ACADEMIC_YEAR',
        null,null,'00000000-0000-0000-0000-000000000705'
      )::public.fit_financial_conversion_inputs_v014);
      if v_funding_case<>'MISSING_INPUT' then
        perform public.insert_fit_financial_conversion_input_v014(row(
          null,v_attack_normalization,3,'AVAILABLE_FUNDING',
          case when v_funding_case='WRONG_VALUE' then 19999 else 20000 end,
          null,case when v_funding_case='WRONG_UNIT' then 'EUR' else 'USD' end,
          case when v_funding_case='FUNDING_OBSERVATION'
               then v_amount_observation else null end,
          case when v_funding_case='WRONG_INTENT'
               then '61400000-0000-0000-0000-000000000013'::uuid
               else '61400000-0000-0000-0000-000000000012'::uuid end,
          '00000000-0000-0000-0000-000000000705'
        )::public.fit_financial_conversion_inputs_v014);
      end if;
      perform public.insert_fit_financial_conversion_input_v014(row(
        null,v_attack_normalization,4,'ROUNDING',null,'NONE','RULE',
        null,null,'00000000-0000-0000-0000-000000000705'
      )::public.fit_financial_conversion_inputs_v014);
      perform public.insert_fit_financial_conversion_factor_v014(row(
        null,v_attack_normalization,1,'ACADEMIC_YEARS','MULTIPLY',2,
        'USD_PER_ACADEMIC_YEAR','USD_PER_PROGRAM_DURATION',
        '00000000-0000-0000-0000-000000000705'
      )::public.fit_financial_conversion_factors_v014);
      if v_funding_case<>'MISSING_FACTOR' then
        perform public.insert_fit_financial_conversion_factor_v014(row(
          null,v_attack_normalization,2,'AVAILABLE_FUNDING',
          case when v_funding_case='FACTOR_OPERATION' then 'ADD' else 'SUBTRACT' end,
          case when v_funding_case='FACTOR_VALUE' then 19999 else 20000 end,
          case when v_funding_case='FACTOR_UNITS' then 'EUR' else 'USD' end,
          case when v_funding_case='FACTOR_UNITS' then 'EUR' else 'USD' end,
          '00000000-0000-0000-0000-000000000705'
        )::public.fit_financial_conversion_factors_v014);
      end if;
      v_blocked:=false;
      begin
        perform public.verify_fit_financial_normalization_v014(
          v_attack_normalization,'phase014-funding-adversarial-reviewer',
          '00000000-0000-0000-0000-000000000705'
        );
      exception when check_violation then v_blocked:=true;
      end;
      if not v_blocked then
        v_funding_failures:=array_append(v_funding_failures,v_funding_case);
      end if;
      raise exception using errcode='P7793',message='rollback funding attack';
    exception when sqlstate 'P7793' then null;
    end;
  end loop;
  if cardinality(v_funding_failures)>0 then
    raise exception 'funding normalization attacks were accepted: %',v_funding_failures;
  end if;

  -- AVAILABLE_FUNDING is not a normalization target and cannot masquerade as
  -- a cost ceiling merely because its numeric/currency tuple looks compatible.
  v_blocked:=false;
  begin
    insert into public.fit_financial_normalizations (
      evaluation_id,profile_version_id,field_observation_id,
      financial_constraint_id,intent_set_id,normalization_method_id,
      conversion_evidence_id,original_amount,original_currency,
      original_period,original_scope,original_basis,original_components,
      target_amount,target_currency,target_period,target_scope,target_basis,
      target_components,conversion_evidence,source_pin_id
    ) values (
      v_evaluation,'61400000-0000-0000-0000-000000000002',v_amount_observation,
      '61400000-0000-0000-0000-000000000012',
      '61400000-0000-0000-0000-000000000010',
      '61400000-0000-0000-0000-000000000021',
      '00000000-0000-0000-0000-000000000705',60000,'USD',
      'ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'],
      20000,'USD','PROGRAM_DURATION','COMPONENT','GROSS',array['TUITION'],
      '{"formula":"fixture"}',v_source_pin
    );
  exception when check_violation then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'AVAILABLE_FUNDING became a cost normalization target'; end if;

  insert into public.fit_financial_normalizations (
    financial_normalization_id,evaluation_id,profile_version_id,
    field_observation_id,financial_constraint_id,intent_set_id,
    normalization_method_id,conversion_evidence_id,
    original_amount,original_currency,original_period,original_scope,
    original_basis,original_components,target_amount,target_currency,
    target_period,target_scope,target_basis,target_components,
    conversion_evidence,source_pin_id
  ) values (
    v_normalization,v_evaluation,'61400000-0000-0000-0000-000000000002',
    v_amount_observation,'61400000-0000-0000-0000-000000000011',
    '61400000-0000-0000-0000-000000000010',
    '61400000-0000-0000-0000-000000000021',
    '00000000-0000-0000-0000-000000000705',
    60000,'USD','ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'],
    90000,'USD','PROGRAM_DURATION','COMPONENT','GROSS',array['TUITION'],
    '{"formula":"fixture"}',v_source_pin
  );
  if (select status from public.fit_financial_normalization_reviews_v014
      where financial_normalization_id=v_normalization)<>'DRAFT' then
    raise exception 'normalization did not start in DRAFT';
  end if;
  v_blocked:=false;
  begin
    update public.fit_financial_normalization_reviews_v014
    set status='VERIFIED',reviewed_by='bypass',reviewed_at=now(),
        verification_evidence_id='00000000-0000-0000-0000-000000000705'
    where financial_normalization_id=v_normalization;
  exception when object_not_in_prerequisite_state then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'normalization review bypassed its lifecycle API'; end if;

  perform public.insert_fit_financial_conversion_input_v014(row(
    null,v_normalization,1,'SOURCE_AMOUNT',60000,null,'USD',
    v_amount_observation,null,'00000000-0000-0000-0000-000000000705'
  )::public.fit_financial_conversion_inputs_v014);
  perform public.insert_fit_financial_conversion_input_v014(row(
    null,v_normalization,2,'ACADEMIC_YEARS',2,null,'ACADEMIC_YEAR',
    null,null,'00000000-0000-0000-0000-000000000705'
  )::public.fit_financial_conversion_inputs_v014);
  perform public.insert_fit_financial_conversion_input_v014(row(
    null,v_normalization,3,'ROUNDING',null,'NONE','RULE',
    null,null,'00000000-0000-0000-0000-000000000705'
  )::public.fit_financial_conversion_inputs_v014);
  perform public.insert_fit_financial_conversion_factor_v014(row(
    null,v_normalization,1,'ACADEMIC_YEARS','MULTIPLY',2,
    'USD_PER_ACADEMIC_YEAR','USD_PER_PROGRAM_DURATION',
    '00000000-0000-0000-0000-000000000705'
  )::public.fit_financial_conversion_factors_v014);
  perform public.verify_fit_financial_normalization_v014(
    v_normalization,'phase014-reviewer',
    '00000000-0000-0000-0000-000000000705'
  );
  if not exists (
    select 1 from public.fit_financial_normalization_reviews_v014 r
    join private.fit_financial_normalization_verified_pins_v014 p
      using(financial_normalization_id,evaluation_id)
    where r.financial_normalization_id=v_normalization and r.status='VERIFIED'
  ) then raise exception 'normalization verification did not persist its semantic pins'; end if;
  v_payload := private.fit_financial_normalization_payload_v014(v_normalization);
  if v_payload is null or v_payload ? 'financialNormalizationId'
     or v_payload->>'methodCode'<>'ANNUAL_TO_PROGRAM' then
    raise exception 'verified normalization payload is incomplete or identity-dependent: %',v_payload;
  end if;

  -- A valid semantic mutation must change the normalization identity even
  -- though every generated graph ID remains excluded from the payload.
  begin
    v_attack_normalization:=pg_temp.create_v014_normalization_fixture(
      v_evaluation,v_amount_observation,v_source_pin
    );
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_attack_normalization,1,'SOURCE_AMOUNT',60000,null,'USD',
      v_amount_observation,null,'00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_inputs_v014);
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_attack_normalization,2,'ACADEMIC_YEARS',3,null,'ACADEMIC_YEAR',
      null,null,'00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_inputs_v014);
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_attack_normalization,3,'ROUNDING',null,'NONE','RULE',
      null,null,'00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_inputs_v014);
    perform public.insert_fit_financial_conversion_factor_v014(row(
      null,v_attack_normalization,1,'ACADEMIC_YEARS','MULTIPLY',3,
      'USD_PER_ACADEMIC_YEAR','USD_PER_PROGRAM_DURATION',
      '00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_factors_v014);
    perform public.verify_fit_financial_normalization_v014(
      v_attack_normalization,'phase014-semantic-mutation-reviewer',
      '00000000-0000-0000-0000-000000000705'
    );
    v_mutated_payload:=private.fit_financial_normalization_payload_v014(
      v_attack_normalization
    );
    if v_mutated_payload is null
       or v_mutated_payload=v_payload
       or v_mutated_payload->>'conversionInputsHash'
          =v_payload->>'conversionInputsHash'
       or v_mutated_payload->>'conversionFactorsHash'
          =v_payload->>'conversionFactorsHash' then
      raise exception 'semantic typed-row mutation did not change normalization identity';
    end if;
    raise exception using errcode='P7791',message='rollback semantic mutation';
  exception when sqlstate 'P7791' then null;
  end;

  v_net_normalization:=pg_temp.create_v014_net_normalization_fixture(
    v_evaluation,v_amount_observation,v_source_pin
  );
  perform public.insert_fit_financial_conversion_input_v014(row(
    null,v_net_normalization,1,'SOURCE_AMOUNT',60000,null,'USD',
    v_amount_observation,null,'00000000-0000-0000-0000-000000000705'
  )::public.fit_financial_conversion_inputs_v014);
  perform public.insert_fit_financial_conversion_input_v014(row(
    null,v_net_normalization,2,'ACADEMIC_YEARS',2,null,'ACADEMIC_YEAR',
    null,null,'00000000-0000-0000-0000-000000000705'
  )::public.fit_financial_conversion_inputs_v014);
  perform public.insert_fit_financial_conversion_input_v014(row(
    null,v_net_normalization,3,'AVAILABLE_FUNDING',20000,null,'USD',
    null,'61400000-0000-0000-0000-000000000012',
    '00000000-0000-0000-0000-000000000705'
  )::public.fit_financial_conversion_inputs_v014);
  perform public.insert_fit_financial_conversion_input_v014(row(
    null,v_net_normalization,4,'ROUNDING',null,'NONE','RULE',
    null,null,'00000000-0000-0000-0000-000000000705'
  )::public.fit_financial_conversion_inputs_v014);
  perform public.insert_fit_financial_conversion_factor_v014(row(
    null,v_net_normalization,1,'ACADEMIC_YEARS','MULTIPLY',2,
    'USD_PER_ACADEMIC_YEAR','USD_PER_PROGRAM_DURATION',
    '00000000-0000-0000-0000-000000000705'
  )::public.fit_financial_conversion_factors_v014);
  perform public.insert_fit_financial_conversion_factor_v014(row(
    null,v_net_normalization,2,'AVAILABLE_FUNDING','SUBTRACT',20000,
    'USD','USD','00000000-0000-0000-0000-000000000705'
  )::public.fit_financial_conversion_factors_v014);
  perform public.verify_fit_financial_normalization_v014(
    v_net_normalization,'phase014-net-reviewer',
    '00000000-0000-0000-0000-000000000705'
  );
  if private.fit_financial_normalization_payload_v014(v_net_normalization) is null then
    raise exception 'valid NET_OF_VERIFIED_FUNDING normalization was not serializable';
  end if;

  -- Build the exact same-signal witness required by v014 finalization: amount
  -- + basis + frozen intent + one VERIFIED normalization.
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    v_evaluation,'61400000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000103',
    'bd4b1c93-9f2e-3b5a-8074-840d4761342a',
    'FIT_INTENT_DECLARATION','AUTHORITATIVE'
  ) returning manifest_item_id into v_intent_item;
  insert into public.fit_manifest_intent_declarations (
    manifest_item_id,evaluation_id,profile_version_id,
    intent_declaration_id,intent_set_id
  ) values (
    v_intent_item,v_evaluation,'61400000-0000-0000-0000-000000000002',
    '61400000-0000-0000-0000-000000000011',
    '61400000-0000-0000-0000-000000000010'
  );
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    v_evaluation,'61400000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000103',
    'bd4b1c93-9f2e-3b5a-8074-840d4761342a',
    'FIT_INTENT_DECLARATION','AUTHORITATIVE'
  ) returning manifest_item_id into v_net_intent_item;
  insert into public.fit_manifest_intent_declarations (
    manifest_item_id,evaluation_id,profile_version_id,
    intent_declaration_id,intent_set_id
  ) values (
    v_net_intent_item,v_evaluation,'61400000-0000-0000-0000-000000000002',
    '61400000-0000-0000-0000-000000000013',
    '61400000-0000-0000-0000-000000000010'
  );
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    v_evaluation,'61400000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000103',
    'bd4b1c93-9f2e-3b5a-8074-840d4761342a',
    'FIT_INTENT_DECLARATION','AUTHORITATIVE'
  ) returning manifest_item_id into v_funding_intent_item;
  insert into public.fit_manifest_intent_declarations (
    manifest_item_id,evaluation_id,profile_version_id,
    intent_declaration_id,intent_set_id
  ) values (
    v_funding_intent_item,v_evaluation,
    '61400000-0000-0000-0000-000000000002',
    '61400000-0000-0000-0000-000000000012',
    '61400000-0000-0000-0000-000000000010'
  );
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    v_evaluation,'61400000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000103',
    'e4036723-22c5-6da2-d278-4de5458ad45d',
    'FIT_FINANCIAL_NORMALIZATION','AUTHORITATIVE'
  ) returning manifest_item_id into v_normalization_item;
  insert into public.fit_manifest_financial_normalizations (
    manifest_item_id,evaluation_id,profile_version_id,
    financial_normalization_id
  ) values (
    v_normalization_item,v_evaluation,
    '61400000-0000-0000-0000-000000000002',v_normalization
  );
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    v_evaluation,'61400000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000103',
    'e4036723-22c5-6da2-d278-4de5458ad45d',
    'FIT_FINANCIAL_NORMALIZATION','AUTHORITATIVE'
  ) returning manifest_item_id into v_net_normalization_item;
  insert into public.fit_manifest_financial_normalizations (
    manifest_item_id,evaluation_id,profile_version_id,
    financial_normalization_id
  ) values (
    v_net_normalization_item,v_evaluation,
    '61400000-0000-0000-0000-000000000002',v_net_normalization
  );
  insert into public.fit_dimension_results (
    evaluation_id,dimension,assessment,confidence,evidence_coverage,
    method_id,inference_category,presentation_explanation
  ) values (
    v_evaluation,'FINANCIAL','ALIGNMENT','HIGH','SUFFICIENT',
    '30000000-0000-0000-0000-000000000103','DETERMINISTIC',
    'Verified normalization supports the frozen tuition preference.'
  ) returning dimension_result_id into v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,evidence_metadata,
    intent_declaration_id
  ) values (
    v_evaluation,v_result,'FINANCIAL',
    '30000000-0000-0000-0000-000000000103',
    'd577f332-57fd-dafe-1844-cb5883d3983e','SUPPORTING',true,
    'DETERMINISTIC','{}','61400000-0000-0000-0000-000000000011'
  ) returning signal_id into v_signal;
  insert into public.fit_signal_evidence values
    (v_signal,v_evaluation,v_amount_item),
    (v_signal,v_evaluation,v_basis_item),
    (v_signal,v_evaluation,v_intent_item),
    (v_signal,v_evaluation,v_normalization_item);
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,direction,
    signal_id,presentation_explanation
  ) values (
    v_result,v_evaluation,'30000000-0000-0000-0000-000000000203',
    'SUPPORTING',v_signal,'Verified normalized tuition evidence supports alignment.'
  );

  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,evidence_metadata,
    intent_declaration_id
  ) values (
    v_evaluation,v_result,'FINANCIAL',
    '30000000-0000-0000-0000-000000000103',
    'd577f332-57fd-dafe-1844-cb5883d3983e','SUPPORTING',true,
    'DETERMINISTIC','{}','61400000-0000-0000-0000-000000000013'
  ) returning signal_id into v_net_signal;
  insert into public.fit_signal_evidence values
    (v_net_signal,v_evaluation,v_amount_item),
    (v_net_signal,v_evaluation,v_basis_item),
    (v_net_signal,v_evaluation,v_net_intent_item),
    (v_net_signal,v_evaluation,v_net_normalization_item);

  v_blocked:=false;
  begin
    perform private.validate_fit_financial_finalization_v014(v_evaluation);
  exception when check_violation then v_blocked:=true;
  end;
  if not v_blocked then
    raise exception 'NET_OF_VERIFIED_FUNDING signal accepted without same-signal funding evidence';
  end if;

  insert into public.fit_signal_evidence values
    (v_net_signal,v_evaluation,v_funding_intent_item);
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,direction,
    signal_id,presentation_explanation
  ) values (
    v_result,v_evaluation,'30000000-0000-0000-0000-000000000203',
    'SUPPORTING',v_net_signal,
    'Verified funding is subtracted only in the net-cost normalization.'
  );

  -- Funding is limiting context for a NET witness only. It cannot be attached
  -- to a GROSS witness, and a NET witness cannot carry two funding manifests.
  begin
    insert into public.fit_signal_evidence values
      (v_signal,v_evaluation,v_funding_intent_item);
    v_blocked:=false;
    begin
      perform private.validate_fit_financial_finalization_v014(v_evaluation);
    exception when check_violation then v_blocked:=true;
    end;
    if not v_blocked then
      raise exception 'GROSS Financial signal accepted same-signal funding evidence';
    end if;
    raise exception using errcode='P7792',message='rollback gross funding attack';
  exception when sqlstate 'P7792' then null;
  end;

  begin
    insert into public.fit_manifest_items (
      evaluation_id,profile_version_id,method_id,input_policy_id,
      item_type,authority_role
    ) values (
      v_evaluation,'61400000-0000-0000-0000-000000000002',
      '30000000-0000-0000-0000-000000000103',
      'bd4b1c93-9f2e-3b5a-8074-840d4761342a',
      'FIT_INTENT_DECLARATION','AUTHORITATIVE'
    ) returning manifest_item_id into v_attack_item;
    insert into public.fit_manifest_intent_declarations (
      manifest_item_id,evaluation_id,profile_version_id,
      intent_declaration_id,intent_set_id
    ) values (
      v_attack_item,v_evaluation,'61400000-0000-0000-0000-000000000002',
      '61400000-0000-0000-0000-000000000014',
      '61400000-0000-0000-0000-000000000010'
    );
    insert into public.fit_signal_evidence values
      (v_net_signal,v_evaluation,v_attack_item);
    v_blocked:=false;
    begin
      perform private.validate_fit_financial_finalization_v014(v_evaluation);
    exception when check_violation then v_blocked:=true;
    end;
    if not v_blocked then
      raise exception 'NET Financial signal accepted an extra mismatched funding declaration';
    end if;
    raise exception using errcode='P7793',message='rollback duplicate funding attack';
  exception when sqlstate 'P7793' then null;
  end;

  perform private.validate_fit_financial_finalization_v014(v_evaluation);

  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    v_evaluation,'61400000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000103',
    '94646dff-73a0-0db4-be99-363a5f0b1a28',
    'PHASE2_STUDENT_PREFERENCE','LIMITING_CONTEXT'
  ) returning manifest_item_id into v_budget_item;
  insert into public.fit_manifest_phase2_preferences (
    manifest_item_id,evaluation_id,profile_version_id,student_preference_id
  ) values (
    v_budget_item,v_evaluation,'61400000-0000-0000-0000-000000000002',
    '61400000-0000-0000-0000-000000000004'
  );
  insert into public.fit_manifest_student_field_uses values
    (v_budget_item,v_evaluation,'PREFERENCE_TYPE'),
    (v_budget_item,v_evaluation,'VALUE');
  insert into public.fit_signal_evidence values
    (v_signal,v_evaluation,v_budget_item);

  -- A second manifest/source-pin UUID graph over the same authoritative
  -- observations has the same semantic source identity and must be rejected
  -- as a duplicate before it can influence ordering or the fingerprint.
  begin
    insert into public.fit_manifest_items (
      evaluation_id,profile_version_id,method_id,input_policy_id,
      item_type,authority_role
    ) values (
      v_evaluation,'61400000-0000-0000-0000-000000000002',
      '30000000-0000-0000-0000-000000000103',
      '6f33306a-4e4f-bcb6-509a-e18b82539bb4',
      'CATALOG_FIELD_OBSERVATION','AUTHORITATIVE'
    ) returning manifest_item_id into v_duplicate_amount_item;
    insert into public.fit_manifest_catalog_observations values (
      v_duplicate_amount_item,v_evaluation,
      '61400000-0000-0000-0000-000000000002',v_amount_observation
    );
    insert into public.fit_manifest_items (
      evaluation_id,profile_version_id,method_id,input_policy_id,
      item_type,authority_role
    ) values (
      v_evaluation,'61400000-0000-0000-0000-000000000002',
      '30000000-0000-0000-0000-000000000103',
      '6f33306a-4e4f-bcb6-509a-e18b82539bb4',
      'CATALOG_FIELD_OBSERVATION','AUTHORITATIVE'
    ) returning manifest_item_id into v_duplicate_basis_item;
    insert into public.fit_manifest_catalog_observations values (
      v_duplicate_basis_item,v_evaluation,
      '61400000-0000-0000-0000-000000000002',v_basis_observation
    );
    v_duplicate_source_pin := public.pin_fit_financial_source_v014(
      v_evaluation,v_duplicate_amount_item,v_duplicate_basis_item
    );
    insert into public.fit_signal_evidence values
      (v_signal,v_evaluation,v_duplicate_amount_item),
      (v_signal,v_evaluation,v_duplicate_basis_item);
    v_blocked:=false;
    begin
      perform private.fit_financial_payload_collections_v014(v_evaluation);
    exception when check_violation then
      if sqlerrm='Duplicate Financial source semantic hashes are forbidden' then
        v_blocked:=true;
      else
        raise;
      end if;
    end;
    if not v_blocked then
      raise exception 'equivalent source UUID graphs did not collide semantically';
    end if;
    raise exception using errcode='P7784',message='rollback duplicate source attack';
  exception when sqlstate 'P7784' then null;
  end;

  -- Conversion input/factor UUIDs and the normalization UUID are audit-only.
  -- Recreating identical semantics with fresh generated IDs must therefore
  -- collide with the first normalization's semantic identity.
  begin
    insert into public.fit_financial_normalizations (
      financial_normalization_id,evaluation_id,profile_version_id,
      field_observation_id,financial_constraint_id,intent_set_id,
      normalization_method_id,conversion_evidence_id,
      original_amount,original_currency,original_period,original_scope,
      original_basis,original_components,target_amount,target_currency,
      target_period,target_scope,target_basis,target_components,
      conversion_evidence,source_pin_id
    ) values (
      v_duplicate_normalization,v_evaluation,
      '61400000-0000-0000-0000-000000000002',v_amount_observation,
      '61400000-0000-0000-0000-000000000011',
      '61400000-0000-0000-0000-000000000010',
      '61400000-0000-0000-0000-000000000021',
      '00000000-0000-0000-0000-000000000705',
      60000,'USD','ACADEMIC_YEAR','COMPONENT','GROSS',array['TUITION'],
      90000,'USD','PROGRAM_DURATION','COMPONENT','GROSS',array['TUITION'],
      '{"formula":"fixture"}',v_source_pin
    );
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_duplicate_normalization,1,'SOURCE_AMOUNT',60000,null,'USD',
      v_amount_observation,null,'00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_inputs_v014);
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_duplicate_normalization,2,'ACADEMIC_YEARS',2,null,'ACADEMIC_YEAR',
      null,null,'00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_inputs_v014);
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_duplicate_normalization,3,'ROUNDING',null,'NONE','RULE',
      null,null,'00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_inputs_v014);
    perform public.insert_fit_financial_conversion_factor_v014(row(
      null,v_duplicate_normalization,1,'ACADEMIC_YEARS','MULTIPLY',2,
      'USD_PER_ACADEMIC_YEAR','USD_PER_PROGRAM_DURATION',
      '00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_factors_v014);
    perform public.verify_fit_financial_normalization_v014(
      v_duplicate_normalization,'phase014-reviewer',
      '00000000-0000-0000-0000-000000000705'
    );
    insert into public.fit_manifest_items (
      evaluation_id,profile_version_id,method_id,input_policy_id,
      item_type,authority_role
    ) values (
      v_evaluation,'61400000-0000-0000-0000-000000000002',
      '30000000-0000-0000-0000-000000000103',
      'e4036723-22c5-6da2-d278-4de5458ad45d',
      'FIT_FINANCIAL_NORMALIZATION','AUTHORITATIVE'
    ) returning manifest_item_id into v_duplicate_normalization_item;
    insert into public.fit_manifest_financial_normalizations (
      manifest_item_id,evaluation_id,profile_version_id,
      financial_normalization_id
    ) values (
      v_duplicate_normalization_item,v_evaluation,
      '61400000-0000-0000-0000-000000000002',v_duplicate_normalization
    );
    insert into public.fit_signal_evidence values
      (v_signal,v_evaluation,v_duplicate_normalization_item);
    v_blocked:=false;
    begin
      perform private.fit_financial_payload_collections_v014(v_evaluation);
    exception when check_violation then
      if sqlerrm='Duplicate Financial normalization semantic hashes are forbidden' then
        v_blocked:=true;
      else
        raise;
      end if;
    end;
    if not v_blocked then
      raise exception 'equivalent normalization/input/factor UUID graphs did not collide semantically';
    end if;
    raise exception using errcode='P7785',message='rollback duplicate normalization attack';
  exception when sqlstate 'P7785' then null;
  end;

  -- Complete the six-dimensional input-state/result contract. The five
  -- non-Financial dimensions are explicitly UNKNOWN with limiting states;
  -- Financial alone has the verified directional witness above.
  for v_method in
    select * from public.fit_dimension_methods
    where contract_release_id='30000000-0000-0000-0000-000000000001'
    order by dimension
  loop
    v_state:=null;
    for v_policy in
      select * from public.fit_method_input_policies
      where method_id=v_method.method_id and disposition='ALLOWED'
      order by input_policy_id
    loop
      insert into public.fit_input_domain_states (
        evaluation_id,profile_version_id,method_id,input_policy_id,
        availability,explanation
      ) values (
        v_evaluation,'61400000-0000-0000-0000-000000000002',
        v_method.method_id,v_policy.input_policy_id,
        case when v_method.dimension='FINANCIAL' and v_policy.input_policy_id in (
          '6f33306a-4e4f-bcb6-509a-e18b82539bb4',
          'bd4b1c93-9f2e-3b5a-8074-840d4761342a',
          'e4036723-22c5-6da2-d278-4de5458ad45d',
          '94646dff-73a0-0db4-be99-363a5f0b1a28'
        ) then 'INCLUDED'::public.fit_input_availability
        else 'NOT_SUPPLIED'::public.fit_input_availability end,
        case when v_method.dimension='FINANCIAL' and v_policy.input_policy_id in (
          '6f33306a-4e4f-bcb6-509a-e18b82539bb4',
          'bd4b1c93-9f2e-3b5a-8074-840d4761342a',
          'e4036723-22c5-6da2-d278-4de5458ad45d',
          '94646dff-73a0-0db4-be99-363a5f0b1a28'
        ) then null else 'Not supplied in the isolated v014 finalization fixture.' end
      ) returning input_state_id into v_inserted_state;
      if v_state is null and not (
        v_method.dimension='FINANCIAL' and v_policy.input_policy_id in (
          '6f33306a-4e4f-bcb6-509a-e18b82539bb4',
          'bd4b1c93-9f2e-3b5a-8074-840d4761342a',
          'e4036723-22c5-6da2-d278-4de5458ad45d',
          '94646dff-73a0-0db4-be99-363a5f0b1a28'
        )
      ) then v_state:=v_inserted_state; end if;
    end loop;
    if v_method.dimension<>'FINANCIAL' then
      insert into public.fit_dimension_results (
        evaluation_id,dimension,assessment,confidence,evidence_coverage,
        method_id,inference_category,presentation_explanation
      ) values (
        v_evaluation,v_method.dimension,'UNKNOWN','LOW','INSUFFICIENT',
        v_method.method_id,v_method.inference_category,
        'Insufficient approved inputs in the isolated v014 fixture.'
      ) returning dimension_result_id into v_other_result;
      insert into public.fit_dimension_reasons (
        dimension_result_id,evaluation_id,reason_definition_id,direction,
        input_state_id,presentation_explanation
      ) values (
        v_other_result,v_evaluation,
        '30000000-0000-0000-0000-000000000202','LIMITING',v_state,
        'Required approved input was unavailable.'
      );
    end if;
  end loop;

  v_fingerprint := public.compute_fit_decision_input_fingerprint(v_evaluation);
  if v_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'v014 semantic fingerprint was not produced: %',v_fingerprint;
  end if;
  perform private.validate_fit_financial_finalization_v014(v_evaluation);

  -- Simulate privileged physical drift after sealing. Ordinary writes are
  -- already blocked by lifecycle/immutability triggers; finalization must
  -- still recompute every persisted pin instead of trusting stored hashes.
  -- Supabase's README `postgres` role intentionally is not superuser; the same
  -- file is also executed as disposable supabase_admin for this attack block.
  if (select rolsuper from pg_roles where rolname=current_user) then
    foreach v_live_pin_case in array array[
      'SOURCE_COST','METHOD','FUNDING_CONSTRAINT',
      'EVIDENCE','TYPED_INPUT','TYPED_FACTOR'
    ] loop
      begin
        perform public.seal_fit_evaluation_inputs(v_evaluation);
        perform set_config('session_replication_role','replica',true);
        case v_live_pin_case
        when 'SOURCE_COST' then
          update public.program_costs set tuition_amount=60001
          where cost_id=(
            select cost_id from private.fit_financial_source_pins_v014
            where source_pin_id=v_source_pin
          );
        when 'METHOD' then
          update public.fit_financial_normalization_methods
          set normalization_contract=jsonb_set(
            normalization_contract,'{formulaCode}','"TAMPERED"'::jsonb
          )
          where normalization_method_id=
            '61400000-0000-0000-0000-000000000021';
        when 'FUNDING_CONSTRAINT' then
          update public.fit_intent_financial_constraints set amount=20001
          where intent_declaration_id=
            '61400000-0000-0000-0000-000000000012';
        when 'EVIDENCE' then
          update public.evidence_items set content_hash=repeat('e',64)
          where evidence_id='00000000-0000-0000-0000-000000000705';
        when 'TYPED_INPUT' then
          update public.fit_financial_conversion_inputs_v014
          set numeric_value=3
          where financial_normalization_id=v_normalization
            and input_role='ACADEMIC_YEARS';
        when 'TYPED_FACTOR' then
          update public.fit_financial_conversion_factors_v014
          set factor_value=3
          where financial_normalization_id=v_normalization
            and factor_code='ACADEMIC_YEARS';
        end case;
        perform set_config('session_replication_role','origin',true);
        v_blocked:=false;
        begin
          perform public.finalize_fit_evaluation(v_evaluation);
        exception when check_violation then v_blocked:=true;
        end;
        if not v_blocked then
          v_live_pin_failures:=array_append(
            v_live_pin_failures,v_live_pin_case
          );
        end if;
        raise exception using errcode='P7794',
          message='rollback live-pin mutation attack';
      exception when sqlstate 'P7794' then null;
      end;
    end loop;
    if cardinality(v_live_pin_failures)<>0 then
      raise exception 'post-seal live-pin mutation attacks were accepted: %',
        v_live_pin_failures;
    end if;
  end if;

  begin
    perform public.seal_fit_evaluation_inputs(v_evaluation);
    perform pg_temp.accept_v014_cost_observation(
      'tuition_amount',to_jsonb(65000::numeric)
    );
    v_blocked:=false;
    begin
      perform public.finalize_fit_evaluation(v_evaluation);
    exception when others then
      if sqlstate='P0001' and sqlerrm=
        'Catalog observations must belong to the target version; authoritative observations must be selected and KNOWN' then
        v_blocked:=true;
      else
        raise;
      end if;
    end;
    if not v_blocked then
      raise exception 'public finalizer accepted a post-seal catalog/selection change';
    end if;
    raise exception using errcode='P7783',message='rollback post-seal replay attack';
  exception when sqlstate 'P7783' then null;
  end;

  -- Exercise the public seal/finalize entry points, then deliberately roll the
  -- successful probe back to BUILDING so lifecycle retirement can be tested.
  begin
    perform public.seal_fit_evaluation_inputs(v_evaluation);
    v_finalized:=public.finalize_fit_evaluation(v_evaluation);
    if v_finalized is distinct from v_fingerprint
       or (select evaluation_state from public.fit_evaluations
           where evaluation_id=v_evaluation)<>'COMPLETED' then
      raise exception 'public v014 finalization did not persist the sealed fingerprint';
    end if;
    raise exception using errcode='P7777',message='rollback successful finalization probe';
  exception when sqlstate 'P7777' then null;
  end;
  if (select evaluation_state from public.fit_evaluations
      where evaluation_id=v_evaluation)<>'BUILDING'
     or (select candidate_input_fingerprint from public.fit_evaluations
         where evaluation_id=v_evaluation) is not null then
    raise exception 'finalization probe subtransaction did not restore BUILDING state';
  end if;

  v_blocked:=false;
  begin
    update public.fit_financial_conversion_inputs_v014 set numeric_value=3
    where financial_normalization_id=v_normalization and input_role='ACADEMIC_YEARS';
  exception when object_not_in_prerequisite_state then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'verified typed conversion input remained mutable'; end if;
  v_blocked:=false;
  begin
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_normalization,4,'AVAILABLE_FUNDING',20000,null,'USD',
      null,'61400000-0000-0000-0000-000000000012',
      '00000000-0000-0000-0000-000000000705'
    )::public.fit_financial_conversion_inputs_v014);
  exception when object_not_in_prerequisite_state then v_blocked:=true;
  end;
  if not v_blocked then raise exception 'VERIFIED normalization accepted a post-review funding input'; end if;
  v_blocked:=false;
  begin
    update public.fit_financial_normalizations set target_amount=90001
    where financial_normalization_id=v_normalization;
  exception when object_not_in_prerequisite_state then v_blocked:=true;
  end;
  if not v_blocked then
    raise exception 'VERIFIED normalization payload remained mutable';
  end if;

  if current_setting('phase014.commit_fixture',true)<>'on' then
    perform public.retire_fit_financial_normalization_v014(
      v_normalization,'fixture retirement'
    );
    if (select status from public.fit_financial_normalization_reviews_v014
        where financial_normalization_id=v_normalization)<>'RETIRED'
       or private.fit_financial_normalization_payload_v014(v_normalization) is not null then
      raise exception 'retired normalization remained replay-admissible';
    end if;
    v_blocked:=false;
    begin
      perform private.validate_fit_financial_finalization_v014(v_evaluation);
    exception when check_violation then v_blocked:=true;
    end;
    if not v_blocked then
      raise exception 'finalization accepted a retired normalization witness';
    end if;
  end if;
end;
$test$;

\if :{?phase014_commit_fixture}
commit;
\else
rollback;
\endif
