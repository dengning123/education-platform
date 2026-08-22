-- Disposable-stack-only catalog fixture for the reviewed v017 Financial
-- normalization workflow. The isolated Supabase stack is destroyed after use.

\if :{?annual_amount}
\else
\set annual_amount 45000
\endif

begin;

set local search_path = public, private, extensions, pg_catalog;

select set_config('app.phase017_annual_amount', :'annual_amount', true);

set local role foundation_catalog_executor;
update public.program_costs
set estimated_total_cost = :'annual_amount'::numeric,
    currency = 'USD',
    billing_basis = 'PER_YEAR'
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
  v_annual_amount numeric := current_setting('app.phase017_annual_amount')::numeric;
begin
  for v_field, v_value in
    values
      ('estimated_total_cost'::text, to_jsonb(v_annual_amount)),
      ('billing_basis'::text, to_jsonb('PER_YEAR'::text))
  loop
    select observation_id into v_prior
    from public.canonical_field_selections
    where record_type='PROGRAM_COST'
      and record_id='00000000-0000-0000-0000-000000000404'
      and field_name=v_field;
    v_scope := public.create_evidence_scope(
      '00000000-0000-0000-0000-000000000705',
      'PROGRAM_COST','00000000-0000-0000-0000-000000000404',v_field,
      'UNSPECIFIED','UNSPECIFIED','UNSPECIFIED'
    );
    v_assertion := public.review_evidence_applicability(
      v_scope,'REVIEWED_APPLICABLE','phase017-api-test',
      'Disposable reviewed Financial normalization API fixture.'
    );
    v_observation := public.create_field_observation(
      'PROGRAM_COST','00000000-0000-0000-0000-000000000404',v_field,
      v_value,'KNOWN','00000000-0000-0000-0000-000000000705',v_prior,
      'Disposable Phase 017 reviewed Financial normalization fixture.',
      v_assertion
    );
    perform public.accept_field_observation(v_observation,'phase017-api-test');
  end loop;
end;
$fixture$;

commit;
