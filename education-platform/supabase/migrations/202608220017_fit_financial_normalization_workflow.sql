begin;

-- Additive production workflow for the frozen v014 Financial normalization
-- lifecycle. This migration does not replace or relax migrations 014/015.
-- It registers two closed methods, creates a service-only DRAFT assembler,
-- delegates review to a separately authorized signed-in reviewer, and exposes
-- a bounded service-only snapshot for resuming the same BUILDING evaluation.
do $registration$
declare
  v_reviewed_at constant timestamptz := timestamptz '2026-08-22 00:00:00+00';
begin
  insert into public.source_identities (
    source_identity_id, canonical_publisher, current_source_id, created_at
  ) values (
    '30000000-0000-0000-0000-000000000171',
    'Education Platform Phase 3 Review',
    '30000000-0000-0000-0000-000000000172',
    v_reviewed_at
  );

  insert into public.sources (
    source_id, source_identity_id, revision_number, publisher, title, url,
    reliability_tier, source_type, retrieval_content_hash, revision_reason,
    created_at, updated_at
  ) values (
    '30000000-0000-0000-0000-000000000172',
    '30000000-0000-0000-0000-000000000171',
    1,
    'Education Platform Phase 3 Review',
    'Fit Financial normalization workflow v0.1 review',
    'repository://education-platform/supabase/migrations/202608220017_fit_financial_normalization_workflow.sql',
    'TIER_A_OFFICIAL',
    'INTERNAL_OFFICIAL_REVIEW',
    'ce51007c3814ac8c44420becfc64a1e35b491bea51a6172433372402d5c96623',
    'INITIAL',
    v_reviewed_at,
    v_reviewed_at
  );

  insert into public.evidence_items (
    evidence_id, source_id, excerpt, locator, cycle_context,
    retrieved_at, verified_at, content_hash, created_at
  ) values (
    '30000000-0000-0000-0000-000000000173',
    '30000000-0000-0000-0000-000000000172',
    'The closed annual-to-program and annual-to-net-program method contracts and the separate DRAFT, reviewer verification, and resume boundaries were reviewed against frozen migrations 014 and 015.',
    'Migration 017 and Fit normalization Edge workflow',
    'fit-v0.1-production',
    v_reviewed_at,
    v_reviewed_at,
    'ce51007c3814ac8c44420becfc64a1e35b491bea51a6172433372402d5c96623',
    v_reviewed_at
  );

  insert into public.fit_financial_normalization_methods (
    normalization_method_id, contract_release_id, method_code, method_version,
    source_scope, target_scope, source_period, target_period,
    source_basis, target_basis, source_currency, target_currency,
    normalization_contract
  ) values
  (
    '30000000-0000-0000-0000-000000000174',
    '30000000-0000-0000-0000-000000000001',
    'ANNUAL_TO_PROGRAM', 1,
    'TOTAL_COST', 'TOTAL_COST', 'ACADEMIC_YEAR', 'PROGRAM_DURATION',
    'GROSS', 'GROSS', null, null,
    jsonb_build_object(
      'formulaCode', 'MULTIPLY_SOURCE_BY_ACADEMIC_YEARS',
      'calculationContract', 'FIT_FINANCIAL_NORMALIZATION_CALC_V017',
      'allowedRoundingRules', jsonb_build_array('NONE'),
      'requiredInputRoles', jsonb_build_array('SOURCE_AMOUNT','ACADEMIC_YEARS','ROUNDING'),
      'allowedInputRoles', jsonb_build_array('SOURCE_AMOUNT','ACADEMIC_YEARS','ROUNDING'),
      'requiredFactorCodes', jsonb_build_array('ACADEMIC_YEARS'),
      'allowedFactorCodes', jsonb_build_array('ACADEMIC_YEARS')
    )
  ),
  (
    '30000000-0000-0000-0000-000000000175',
    '30000000-0000-0000-0000-000000000001',
    'ANNUAL_TO_NET_PROGRAM', 1,
    'TOTAL_COST', 'TOTAL_COST', 'ACADEMIC_YEAR', 'PROGRAM_DURATION',
    'GROSS', 'NET_OF_VERIFIED_FUNDING', null, null,
    jsonb_build_object(
      'formulaCode', 'MULTIPLY_SOURCE_BY_ACADEMIC_YEARS_THEN_SUBTRACT_FUNDING',
      'calculationContract', 'FIT_FINANCIAL_NORMALIZATION_CALC_V017',
      'allowedRoundingRules', jsonb_build_array('NONE'),
      'requiredInputRoles', jsonb_build_array('SOURCE_AMOUNT','ACADEMIC_YEARS','AVAILABLE_FUNDING','ROUNDING'),
      'allowedInputRoles', jsonb_build_array('SOURCE_AMOUNT','ACADEMIC_YEARS','AVAILABLE_FUNDING','ROUNDING'),
      'requiredFactorCodes', jsonb_build_array('ACADEMIC_YEARS','AVAILABLE_FUNDING'),
      'allowedFactorCodes', jsonb_build_array('ACADEMIC_YEARS','AVAILABLE_FUNDING')
    )
  );

  perform public.verify_fit_definition(
    'FINANCIAL_NORMALIZATION',
    '30000000-0000-0000-0000-000000000174',
    'Phase 3 production review',
    '30000000-0000-0000-0000-000000000173'
  );
  perform public.verify_fit_definition(
    'FINANCIAL_NORMALIZATION',
    '30000000-0000-0000-0000-000000000175',
    'Phase 3 production review',
    '30000000-0000-0000-0000-000000000173'
  );
end;
$registration$;

create or replace function public.prepare_fit_financial_normalization_v017(
  p_evaluation_id uuid,
  p_amount_observation_id uuid,
  p_billing_basis_observation_id uuid,
  p_financial_constraint_id uuid,
  p_normalization_method_code text,
  p_normalization_method_version integer,
  p_conversion_evidence_id uuid,
  p_academic_years numeric,
  p_rounding text,
  p_funding_intent_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $prepare$
declare
  v_evaluation public.fit_evaluations%rowtype;
  v_amount public.field_observations%rowtype;
  v_basis public.field_observations%rowtype;
  v_cost public.program_costs%rowtype;
  v_constraint public.fit_intent_financial_constraints%rowtype;
  v_funding public.fit_intent_financial_constraints%rowtype;
  v_method public.fit_financial_normalization_methods%rowtype;
  v_financial_method_id constant uuid := '30000000-0000-0000-0000-000000000103';
  v_program_cost_policy_id uuid;
  v_amount_manifest_id uuid := extensions.gen_random_uuid();
  v_basis_manifest_id uuid := extensions.gen_random_uuid();
  v_source_pin_id uuid;
  v_normalization_id uuid := extensions.gen_random_uuid();
  v_original_amount numeric;
  v_original_scope public.fit_financial_scope;
  v_original_components text[];
  v_formula_code text;
begin
  if p_normalization_method_code not in ('ANNUAL_TO_PROGRAM','ANNUAL_TO_NET_PROGRAM')
     or p_normalization_method_version <> 1 then
    raise exception using errcode='22023', message='Unsupported production Financial normalization method';
  end if;
  if p_academic_years is null or p_academic_years <= 0 then
    raise exception using errcode='22023', message='academic_years must be positive';
  end if;
  if p_rounding <> 'NONE' then
    raise exception using errcode='22023', message='The v017 calculation contract permits only exact no-rounding arithmetic';
  end if;

  select * into v_evaluation
  from public.fit_evaluations
  where evaluation_id = p_evaluation_id
  for update;
  if not found or v_evaluation.evaluation_state <> 'BUILDING'
     or v_evaluation.candidate_input_fingerprint is not null
     or v_evaluation.financial_contract_version <> 'FINANCIAL_BILLING_BASIS_V014' then
    raise exception using errcode='55000', message='Normalization preparation requires an unsealed v014 BUILDING evaluation';
  end if;
  if not exists (
    select 1 from private.fit_evaluation_assembly_authorizations assembly
    where assembly.evaluation_id = v_evaluation.evaluation_id
      and assembly.execution_id = v_evaluation.execution_id
      and assembly.evaluator_build_id = v_evaluation.evaluator_build_id
      and assembly.evaluator_build_hash = v_evaluation.evaluator_build_hash
  ) then
    raise exception using errcode='42501', message='No durable assembly authorization exists for this evaluation execution';
  end if;
  if exists (
    select 1 from public.fit_financial_normalizations normalization
    where normalization.evaluation_id = p_evaluation_id
      and normalization.financial_constraint_id = p_financial_constraint_id
  ) then
    raise exception using errcode='23505', message='Only one Financial normalization draft is allowed per evaluation constraint';
  end if;

  select * into v_amount from public.field_observations
  where observation_id = p_amount_observation_id;
  select * into v_basis from public.field_observations
  where observation_id = p_billing_basis_observation_id;
  if v_amount.observation_id is null or v_basis.observation_id is null
     or v_amount.record_type <> 'PROGRAM_COST' or v_basis.record_type <> 'PROGRAM_COST'
     or v_amount.record_id <> v_basis.record_id
     or v_amount.field_name not in ('tuition_amount','mandatory_fees','estimated_living_cost','estimated_total_cost')
     or v_basis.field_name <> 'billing_basis' then
    raise exception using errcode='23514', message='Normalization source must be one exact program-cost amount and billing-basis pair';
  end if;
  select * into v_cost from public.program_costs where cost_id = v_amount.record_id;
  select * into v_constraint from public.fit_intent_financial_constraints
  where intent_declaration_id = p_financial_constraint_id
    and intent_set_id = v_evaluation.intent_set_id
    and profile_version_id = v_evaluation.profile_version_id;
  if not found or v_constraint.constraint_semantics = 'AVAILABLE_FUNDING' then
    raise exception using errcode='23514', message='Normalization target must be a frozen cost ceiling or preference';
  end if;
  if v_cost.currency is null or v_cost.currency is distinct from v_constraint.currency then
    raise exception using errcode='23514', message='The v017 calculation contract does not authorize currency conversion';
  end if;
  select * into v_method from public.fit_financial_normalization_methods
  where contract_release_id = v_evaluation.contract_release_id
    and method_code = p_normalization_method_code
    and method_version = p_normalization_method_version
    and status = 'VERIFIED' and retired_at is null;
  if not found then
    raise exception using errcode='23514', message='Active reviewed production normalization method was not found';
  end if;
  v_formula_code := v_method.normalization_contract ->> 'formulaCode';
  if (v_formula_code = 'MULTIPLY_SOURCE_BY_ACADEMIC_YEARS_THEN_SUBTRACT_FUNDING') <> (p_funding_intent_id is not null) then
    raise exception using errcode='23514', message='Net normalization requires exactly one funding intent; gross normalization forbids it';
  end if;
  if p_funding_intent_id is not null then
    select * into v_funding from public.fit_intent_financial_constraints
    where intent_declaration_id = p_funding_intent_id
      and intent_set_id = v_evaluation.intent_set_id
      and profile_version_id = v_evaluation.profile_version_id
      and constraint_semantics = 'AVAILABLE_FUNDING';
    if not found then raise exception using errcode='23514', message='Frozen AVAILABLE_FUNDING intent was not found'; end if;
    if v_funding.currency is distinct from v_constraint.currency then
      raise exception using errcode='23514', message='Funding and normalized target currencies must match exactly';
    end if;
  end if;
  if not exists (select 1 from public.evidence_items where evidence_id = p_conversion_evidence_id) then
    raise exception using errcode='22023', message='Conversion evidence was not found';
  end if;

  select policy.input_policy_id into strict v_program_cost_policy_id
  from public.fit_method_input_policies policy
  where policy.method_id = v_financial_method_id
    and policy.input_domain = 'PROGRAM_COSTS'
    and policy.field_name = 'COST_COMPONENTS'
    and policy.disposition = 'ALLOWED';

  insert into public.fit_manifest_items (
    manifest_item_id,evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role,source_class_code
  ) values
  (v_amount_manifest_id,p_evaluation_id,v_evaluation.profile_version_id,v_financial_method_id,v_program_cost_policy_id,
   'CATALOG_FIELD_OBSERVATION','AUTHORITATIVE','PROGRAM_CANONICAL_FACT'),
  (v_basis_manifest_id,p_evaluation_id,v_evaluation.profile_version_id,v_financial_method_id,v_program_cost_policy_id,
   'CATALOG_FIELD_OBSERVATION','AUTHORITATIVE','PROGRAM_CANONICAL_FACT');
  insert into public.fit_manifest_catalog_observations (
    manifest_item_id,evaluation_id,profile_version_id,field_observation_id
  ) values
  (v_amount_manifest_id,p_evaluation_id,v_evaluation.profile_version_id,p_amount_observation_id),
  (v_basis_manifest_id,p_evaluation_id,v_evaluation.profile_version_id,p_billing_basis_observation_id);

  v_source_pin_id := public.pin_fit_financial_source_v014(
    p_evaluation_id,v_amount_manifest_id,v_basis_manifest_id
  );
  v_original_amount := (v_amount.observed_value #>> '{}')::numeric;
  v_original_scope := case when v_amount.field_name='estimated_total_cost' then 'TOTAL_COST'::public.fit_financial_scope else 'COMPONENT'::public.fit_financial_scope end;
  v_original_components := array[case v_amount.field_name
    when 'tuition_amount' then 'TUITION'
    when 'mandatory_fees' then 'MANDATORY_FEES'
    when 'estimated_living_cost' then 'LIVING_COST'
    when 'estimated_total_cost' then 'TOTAL_COST' end]::text[];

  insert into public.fit_financial_normalizations (
    financial_normalization_id,evaluation_id,profile_version_id,
    field_observation_id,financial_constraint_id,intent_set_id,
    normalization_method_id,conversion_evidence_id,
    original_amount,original_currency,original_period,original_scope,
    original_basis,original_components,target_amount,target_currency,
    target_period,target_scope,target_basis,target_components,
    conversion_evidence,source_pin_id
  ) values (
    v_normalization_id,p_evaluation_id,v_evaluation.profile_version_id,
    p_amount_observation_id,p_financial_constraint_id,v_evaluation.intent_set_id,
    v_method.normalization_method_id,p_conversion_evidence_id,
    v_original_amount,v_cost.currency,
    public.fit_financial_period_for_billing_basis(v_cost.billing_basis),
    v_original_scope,'GROSS',v_original_components,
    v_constraint.amount,v_constraint.currency,v_constraint.financial_period,
    v_constraint.financial_scope,v_constraint.financial_basis,v_constraint.components,
    jsonb_build_object(
      'workflow','FIT_FINANCIAL_NORMALIZATION_V017',
      'calculationContract','FIT_FINANCIAL_NORMALIZATION_CALC_V017',
      'formulaCode',v_formula_code,
      'academicYears',p_academic_years,
      'rounding',p_rounding,
      'fundingIntentId',p_funding_intent_id
    ),
    v_source_pin_id
  );

  perform public.insert_fit_financial_conversion_input_v014(row(
    null,v_normalization_id,1,'SOURCE_AMOUNT',v_original_amount,null,
    btrim(v_cost.currency::text),p_amount_observation_id,null,p_conversion_evidence_id
  )::public.fit_financial_conversion_inputs_v014);
  perform public.insert_fit_financial_conversion_input_v014(row(
    null,v_normalization_id,2,'ACADEMIC_YEARS',p_academic_years,null,
    'ACADEMIC_YEAR',null,null,p_conversion_evidence_id
  )::public.fit_financial_conversion_inputs_v014);
  if p_funding_intent_id is not null then
    perform public.insert_fit_financial_conversion_input_v014(row(
      null,v_normalization_id,3,'AVAILABLE_FUNDING',v_funding.amount,null,
      btrim(v_funding.currency::text),null,p_funding_intent_id,p_conversion_evidence_id
    )::public.fit_financial_conversion_inputs_v014);
  end if;
  perform public.insert_fit_financial_conversion_input_v014(row(
    null,v_normalization_id,case when p_funding_intent_id is null then 3 else 4 end,
    'ROUNDING',null,p_rounding,'RULE',null,null,p_conversion_evidence_id
  )::public.fit_financial_conversion_inputs_v014);

  perform public.insert_fit_financial_conversion_factor_v014(row(
    null,v_normalization_id,1,'ACADEMIC_YEARS','MULTIPLY',p_academic_years,
    btrim(v_cost.currency::text)||'_PER_'||public.fit_financial_period_for_billing_basis(v_cost.billing_basis)::text,
    btrim(v_constraint.currency::text)||'_PER_'||v_constraint.financial_period::text,
    p_conversion_evidence_id
  )::public.fit_financial_conversion_factors_v014);
  if p_funding_intent_id is not null then
    perform public.insert_fit_financial_conversion_factor_v014(row(
      null,v_normalization_id,2,'AVAILABLE_FUNDING','SUBTRACT',v_funding.amount,
      btrim(v_constraint.currency::text),btrim(v_constraint.currency::text),p_conversion_evidence_id
    )::public.fit_financial_conversion_factors_v014);
  end if;

  return jsonb_build_object(
    'evaluationId',p_evaluation_id,
    'normalizationId',v_normalization_id,
    'reviewState','DRAFT'
  );
end;
$prepare$;

create or replace function private.fit_financial_normalization_review_subject_v017(
  p_financial_normalization_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $subject$
  select jsonb_build_object(
    'evaluationId', normalization.evaluation_id,
    'profileVersionId', normalization.profile_version_id,
    'ownerAuthUserId', identity.auth_user_id,
    'conversionEvidenceId', normalization.conversion_evidence_id
  )
  from public.fit_financial_normalizations normalization
  join public.student_profile_versions profile
    on profile.profile_version_id = normalization.profile_version_id
  join private.student_identities identity using (student_id)
  where normalization.financial_normalization_id = p_financial_normalization_id;
$subject$;

create or replace function public.review_fit_financial_normalization_v017(
  p_financial_normalization_id uuid,
  p_verification_evidence_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $review$
declare
  v_claims jsonb;
  v_reviewer_id uuid;
  v_subject jsonb;
begin
  v_claims := nullif(current_setting('request.jwt.claims',true),'')::jsonb;
  v_reviewer_id := nullif(v_claims ->> 'sub','')::uuid;
  if v_reviewer_id is null
     or lower(coalesce(v_claims #>> '{app_metadata,fit_normalization_reviewer}','false')) <> 'true' then
    raise exception using errcode='42501', message='An independently authorized Financial normalization reviewer is required';
  end if;
  v_subject := private.fit_financial_normalization_review_subject_v017(p_financial_normalization_id);
  if v_subject is null then raise exception using errcode='22023', message='Financial normalization was not found'; end if;
  if (v_subject ->> 'ownerAuthUserId')::uuid = v_reviewer_id then
    raise exception using errcode='42501', message='A student cannot review their own Financial normalization';
  end if;
  if (v_subject ->> 'conversionEvidenceId')::uuid = p_verification_evidence_id then
    raise exception using errcode='23514', message='Independent review evidence must differ from conversion evidence';
  end if;
  perform public.verify_fit_financial_normalization_v014(
    p_financial_normalization_id,
    v_reviewer_id::text,
    p_verification_evidence_id
  );
  return jsonb_build_object(
    'evaluationId',v_subject ->> 'evaluationId',
    'normalizationId',p_financial_normalization_id,
    'reviewState','VERIFIED',
    'reviewedBy',v_reviewer_id
  );
end;
$review$;

create or replace function public.get_fit_financial_normalization_resume_snapshot_v017(
  p_evaluation_id uuid,
  p_financial_normalization_ids uuid[]
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private
as $snapshot$
declare
  v_result jsonb;
begin
  if p_financial_normalization_ids is null
     or cardinality(p_financial_normalization_ids) = 0
     or cardinality(p_financial_normalization_ids) <> (
       select count(distinct value) from unnest(p_financial_normalization_ids) value
     ) then
    raise exception using errcode='22023', message='Resume requires a nonempty unique normalization set';
  end if;
  if (
    select count(*)
    from public.fit_financial_normalizations normalization
    join public.fit_financial_normalization_reviews_v014 review
      using (financial_normalization_id,evaluation_id)
    where normalization.evaluation_id = p_evaluation_id
      and normalization.financial_normalization_id = any(p_financial_normalization_ids)
      and review.status = 'VERIFIED'
      and review.retired_at is null
  ) <> cardinality(p_financial_normalization_ids) then
    raise exception using errcode='55000', message='Every resumed Financial normalization must be active VERIFIED and evaluation-scoped';
  end if;

  select jsonb_build_object(
    'fit_evaluations', coalesce((
      select jsonb_agg(to_jsonb(row_value)) from public.fit_evaluations row_value
      where row_value.evaluation_id = p_evaluation_id
        and row_value.evaluation_state = 'BUILDING'
        and row_value.candidate_input_fingerprint is null
    ),'[]'::jsonb),
    'fit_financial_normalizations', coalesce((
      select jsonb_agg(
        to_jsonb(row_value) || jsonb_build_object(
          'original_amount',row_value.original_amount::text,
          'target_amount',row_value.target_amount::text
        ) order by row_value.financial_normalization_id
      )
      from public.fit_financial_normalizations row_value
      where row_value.evaluation_id = p_evaluation_id
        and row_value.financial_normalization_id = any(p_financial_normalization_ids)
    ),'[]'::jsonb),
    'fit_financial_normalization_reviews_v014', coalesce((
      select jsonb_agg(to_jsonb(row_value) order by row_value.financial_normalization_id)
      from public.fit_financial_normalization_reviews_v014 row_value
      where row_value.evaluation_id = p_evaluation_id
        and row_value.financial_normalization_id = any(p_financial_normalization_ids)
    ),'[]'::jsonb),
    'fit_financial_conversion_inputs_v014', coalesce((
      select jsonb_agg(
        to_jsonb(row_value) || jsonb_build_object(
          'numeric_value',case when row_value.numeric_value is null then null else row_value.numeric_value::text end
        ) order by row_value.financial_normalization_id,row_value.input_ordinal
      )
      from public.fit_financial_conversion_inputs_v014 row_value
      where row_value.financial_normalization_id = any(p_financial_normalization_ids)
    ),'[]'::jsonb),
    'fit_financial_conversion_factors_v014', coalesce((
      select jsonb_agg(
        to_jsonb(row_value) || jsonb_build_object('factor_value',row_value.factor_value::text)
        order by row_value.financial_normalization_id,row_value.factor_ordinal
      )
      from public.fit_financial_conversion_factors_v014 row_value
      where row_value.financial_normalization_id = any(p_financial_normalization_ids)
    ),'[]'::jsonb),
    'fit_financial_source_pins_v014', coalesce((
      select jsonb_agg(to_jsonb(pin) order by pin.source_pin_id)
      from private.fit_financial_source_pins_v014 pin
      where pin.evaluation_id = p_evaluation_id
        and pin.source_pin_id in (
          select normalization.source_pin_id
          from public.fit_financial_normalizations normalization
          where normalization.financial_normalization_id = any(p_financial_normalization_ids)
        )
    ),'[]'::jsonb)
  ) into v_result;
  if jsonb_array_length(v_result -> 'fit_evaluations') <> 1 then
    raise exception using errcode='55000', message='Resume requires exactly one unsealed BUILDING evaluation';
  end if;
  return v_result;
end;
$snapshot$;

grant create on schema public, private to foundation_evaluation_executor;
grant create on schema public to foundation_catalog_executor;

alter function public.prepare_fit_financial_normalization_v017(
  uuid,uuid,uuid,uuid,text,integer,uuid,numeric,text,uuid
) owner to foundation_evaluation_executor;
alter function private.fit_financial_normalization_review_subject_v017(uuid)
  owner to foundation_evaluation_executor;
alter function public.review_fit_financial_normalization_v017(uuid,uuid)
  owner to foundation_catalog_executor;
alter function public.get_fit_financial_normalization_resume_snapshot_v017(uuid,uuid[])
  owner to foundation_evaluation_executor;

revoke create on schema public, private from foundation_evaluation_executor;
revoke create on schema public from foundation_catalog_executor;

revoke all on function public.prepare_fit_financial_normalization_v017(
  uuid,uuid,uuid,uuid,text,integer,uuid,numeric,text,uuid
) from public,anon,authenticated,service_role,foundation_catalog_executor,foundation_student_executor,foundation_evaluation_executor;
grant execute on function public.prepare_fit_financial_normalization_v017(
  uuid,uuid,uuid,uuid,text,integer,uuid,numeric,text,uuid
) to service_role;

-- The v017 service-only orchestrator runs as the non-login evaluation
-- executor. Permit only that trusted owner to compose the frozen v014
-- primitives; their direct external service_role grants remain unchanged.
grant execute on function public.pin_fit_financial_source_v014(uuid,uuid,uuid),
  public.insert_fit_financial_conversion_input_v014(public.fit_financial_conversion_inputs_v014),
  public.insert_fit_financial_conversion_factor_v014(public.fit_financial_conversion_factors_v014)
to foundation_evaluation_executor;

revoke all on function private.fit_financial_normalization_review_subject_v017(uuid)
from public,anon,authenticated,service_role,foundation_catalog_executor,foundation_student_executor,foundation_evaluation_executor;
grant execute on function private.fit_financial_normalization_review_subject_v017(uuid)
to foundation_catalog_executor;
grant usage on schema private to foundation_catalog_executor;

revoke all on function public.review_fit_financial_normalization_v017(uuid,uuid)
from public,anon,authenticated,service_role,foundation_catalog_executor,foundation_student_executor,foundation_evaluation_executor;
grant execute on function public.review_fit_financial_normalization_v017(uuid,uuid)
to authenticated;

revoke all on function public.get_fit_financial_normalization_resume_snapshot_v017(uuid,uuid[])
from public,anon,authenticated,service_role,foundation_catalog_executor,foundation_student_executor,foundation_evaluation_executor;
grant execute on function public.get_fit_financial_normalization_resume_snapshot_v017(uuid,uuid[])
to service_role;

do $contracts$
declare
  v_function record;
  v_allowed text[];
begin
  for v_function in
    select namespace.nspname, procedure.proname,
      pg_get_function_identity_arguments(procedure.oid) as identity_arguments,
      procedure.proowner::regrole::text as owner_role,
      pg_get_functiondef(procedure.oid) as definition
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid=procedure.pronamespace
    where (namespace.nspname,procedure.proname) in (
      ('public','prepare_fit_financial_normalization_v017'),
      ('private','fit_financial_normalization_review_subject_v017'),
      ('public','review_fit_financial_normalization_v017'),
      ('public','get_fit_financial_normalization_resume_snapshot_v017')
    )
  loop
    v_allowed := case v_function.proname
      when 'review_fit_financial_normalization_v017' then array['authenticated']
      when 'fit_financial_normalization_review_subject_v017' then array['foundation_catalog_executor']
      else array['service_role'] end;
    insert into public.foundation_function_contracts (
      schema_name,function_name,identity_arguments,owner_role,prosecdef,
      search_path,allowed_caller_roles,body_digest
    ) values (
      v_function.nspname,v_function.proname,v_function.identity_arguments,
      v_function.owner_role,true,
      case when v_function.proname='fit_financial_normalization_review_subject_v017'
        then 'pg_catalog, public, private'
        else 'pg_catalog, public, private, extensions' end,
      v_allowed,
      encode(extensions.digest(convert_to(v_function.definition,'UTF8'),'sha256'),'hex')
    );
  end loop;
end;
$contracts$;

comment on function public.review_fit_financial_normalization_v017(uuid,uuid) is
  'Authenticated reviewer-only bridge to the frozen v014 DRAFT-to-VERIFIED lifecycle. Reviewer identity is derived from signed JWT claims and may not own the evaluated profile.';

commit;
