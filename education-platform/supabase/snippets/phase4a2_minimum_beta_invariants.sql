begin read only;

-- This pack returns exactly one fixed check code and one aggregate count per
-- invariant. It never returns row identifiers, timestamps, evidence, result
-- values, financial values, or free text.

-- PHASE4A2_COUNT_QUERY_BEGIN
with invariant_counts as (
  select
    'FIT_STALE_BUILDING_GT_15M'::text as check_code,
    count(*)::bigint as violation_count
  from public.fit_evaluations as evaluation
  where evaluation.evaluation_state = 'BUILDING'
    and evaluation.created_at < statement_timestamp() - interval '15 minutes'

  union all

  select
    'ELIGIBILITY_STALE_BUILDING_GT_15M'::text,
    count(*)::bigint
  from public.eligibility_evaluations as evaluation
  where evaluation.evaluation_state = 'BUILDING'
    and evaluation.created_at < statement_timestamp() - interval '15 minutes'

  union all

  select
    'FIT_COMPLETED_FINGERPRINT_INVARIANT'::text,
    count(*)::bigint
  from public.fit_evaluations as evaluation
  where evaluation.evaluation_state = 'COMPLETED'
    and (
      evaluation.candidate_input_fingerprint is null
      or evaluation.candidate_input_fingerprint !~ '^[a-f0-9]{64}$'
      or evaluation.decision_input_fingerprint is null
      or evaluation.decision_input_fingerprint !~ '^[a-f0-9]{64}$'
      or evaluation.result_fingerprint is null
      or evaluation.result_fingerprint !~ '^[a-f0-9]{64}$'
      or (
        evaluation.replay_contract_version = 'FIT_REPLAY_SEAL_V015'
        and not exists (
          select 1
          from private.fit_evaluation_semantic_pins as pin
          where pin.evaluation_id = evaluation.evaluation_id
            and pin.replay_contract_version = evaluation.replay_contract_version
            and pin.decision_input_fingerprint = evaluation.decision_input_fingerprint
            and pin.result_fingerprint = evaluation.result_fingerprint
            and pin.semantic_fingerprint ~ '^[a-f0-9]{64}$'
        )
      )
    )

  union all

  select
    'ELIGIBILITY_COMPLETED_FINGERPRINT_INVARIANT'::text,
    count(*)::bigint
  from public.eligibility_evaluations as evaluation
  where evaluation.evaluation_state = 'COMPLETED'
    and (
      evaluation.input_fingerprint is null
      or evaluation.input_fingerprint !~ '^[a-f0-9]{64}$'
      or (
        evaluation.input_schema_version = 'eligibility-v0.1'
        and evaluation.result_fingerprint is not null
      )
      or (
        evaluation.input_schema_version = 'eligibility-v0.2'
        and (
          evaluation.result_fingerprint is null
          or evaluation.result_fingerprint !~ '^[a-f0-9]{64}$'
          or evaluation.inputs_sealed_at is null
        )
      )
      or evaluation.input_schema_version not in ('eligibility-v0.1', 'eligibility-v0.2')
    )

  union all

  select
    'FINANCIAL_DRAFT_GT_72H'::text,
    count(*)::bigint
  from public.fit_financial_normalization_reviews_v014 as review
  where review.status = 'DRAFT'
    and review.created_at < statement_timestamp() - interval '72 hours'

  union all

  select
    'VERIFIED_FINANCIAL_GRAPH_INVARIANT'::text,
    count(*)::bigint
  from public.fit_financial_normalization_reviews_v014 as review
  join public.fit_financial_normalizations as normalization
    on normalization.financial_normalization_id = review.financial_normalization_id
  where review.status = 'VERIFIED'
    and (
      review.evaluation_id <> normalization.evaluation_id
      or normalization.source_pin_id is null
      or not exists (
        select 1
        from private.fit_financial_source_pins_v014 as source_pin
        where source_pin.evaluation_id = normalization.evaluation_id
          and source_pin.source_pin_id = normalization.source_pin_id
      )
      or not exists (
        select 1
        from private.fit_financial_normalization_verified_pins_v014 as verified_pin
        where verified_pin.evaluation_id = normalization.evaluation_id
          and verified_pin.financial_normalization_id = normalization.financial_normalization_id
          and verified_pin.method_payload_hash ~ '^[a-f0-9]{64}$'
          and verified_pin.method_evidence_payload_hash ~ '^[a-f0-9]{64}$'
          and verified_pin.normalization_review_evidence_hash ~ '^[a-f0-9]{64}$'
          and verified_pin.typed_input_payload_hash ~ '^[a-f0-9]{64}$'
          and verified_pin.typed_factor_payload_hash ~ '^[a-f0-9]{64}$'
          and verified_pin.legacy_json_hash ~ '^[a-f0-9]{64}$'
          and verified_pin.target_constraint_payload_hash ~ '^[a-f0-9]{64}$'
      )
      or not exists (
        select 1
        from public.fit_financial_normalization_methods as method
        where method.normalization_method_id = normalization.normalization_method_id
          and method.status = 'VERIFIED'
          and method.retired_at is null
          and jsonb_typeof(method.normalization_contract -> 'requiredInputRoles') = 'array'
          and jsonb_typeof(method.normalization_contract -> 'allowedInputRoles') = 'array'
          and jsonb_typeof(method.normalization_contract -> 'requiredFactorCodes') = 'array'
          and jsonb_typeof(method.normalization_contract -> 'allowedFactorCodes') = 'array'
          and not exists (
            select jsonb_array_elements_text(
              method.normalization_contract -> 'requiredInputRoles'
            )
            except
            select input.input_role
            from public.fit_financial_conversion_inputs_v014 as input
            where input.financial_normalization_id = normalization.financial_normalization_id
          )
          and not exists (
            select input.input_role
            from public.fit_financial_conversion_inputs_v014 as input
            where input.financial_normalization_id = normalization.financial_normalization_id
            except
            select jsonb_array_elements_text(
              method.normalization_contract -> 'allowedInputRoles'
            )
          )
          and not exists (
            select jsonb_array_elements_text(
              method.normalization_contract -> 'requiredFactorCodes'
            )
            except
            select factor.factor_code
            from public.fit_financial_conversion_factors_v014 as factor
            where factor.financial_normalization_id = normalization.financial_normalization_id
          )
          and not exists (
            select factor.factor_code
            from public.fit_financial_conversion_factors_v014 as factor
            where factor.financial_normalization_id = normalization.financial_normalization_id
            except
            select jsonb_array_elements_text(
              method.normalization_contract -> 'allowedFactorCodes'
            )
          )
      )
    )
)
select invariant.check_code, invariant.violation_count
from invariant_counts as invariant
order by invariant.check_code;
-- PHASE4A2_COUNT_QUERY_END

rollback;
