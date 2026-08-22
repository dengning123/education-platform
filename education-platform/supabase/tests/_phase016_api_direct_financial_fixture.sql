-- Disposable-stack-only catalog fixture for the production adapter's direct
-- v014 Financial path. The isolated Supabase stack is destroyed after use.

begin;

set local search_path = public, private, extensions, pg_catalog;

set local role foundation_catalog_executor;
update public.program_costs
set estimated_total_cost = 75000,
    currency = 'USD',
    billing_basis = 'TOTAL_PROGRAM'
where cost_id = '00000000-0000-0000-0000-000000000404';
reset role;

do $fixture$
declare
  v_field text;
  v_value jsonb;
  v_prior uuid;
  v_scope uuid;
  v_assertion uuid;
  v_observation uuid;
begin
  for v_field, v_value in
    values
      ('estimated_total_cost'::text, to_jsonb(75000::numeric)),
      ('billing_basis'::text, to_jsonb('TOTAL_PROGRAM'::text))
  loop
    select observation_id into v_prior
    from public.canonical_field_selections
    where record_type = 'PROGRAM_COST'
      and record_id = '00000000-0000-0000-0000-000000000404'
      and field_name = v_field;
    v_scope := public.create_evidence_scope(
      '00000000-0000-0000-0000-000000000705',
      'PROGRAM_COST',
      '00000000-0000-0000-0000-000000000404',
      v_field,
      'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
    );
    v_assertion := public.review_evidence_applicability(
      v_scope,
      'REVIEWED_APPLICABLE',
      'phase016-api-test',
      'Disposable direct Financial API fixture.'
    );
    v_observation := public.create_field_observation(
      'PROGRAM_COST',
      '00000000-0000-0000-0000-000000000404',
      v_field,
      v_value,
      'KNOWN',
      '00000000-0000-0000-0000-000000000705',
      v_prior,
      'Disposable Phase 016 direct Financial API fixture.',
      v_assertion
    );
    perform public.accept_field_observation(
      v_observation,
      'phase016-api-test'
    );
  end loop;
end;
$fixture$;

commit;
