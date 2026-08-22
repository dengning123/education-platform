begin;

alter type public.fit_financial_period add value if not exists 'ACADEMIC_SEMESTER';
alter type public.fit_financial_period add value if not exists 'CREDIT';

commit;

begin;

alter table public.fit_evaluations
  add column financial_contract_version text;

alter table public.fit_evaluations
  add constraint fit_evaluations_financial_contract_version_v014
  check (
    financial_contract_version is null
    or financial_contract_version = 'FINANCIAL_BILLING_BASIS_V014'
  );

do $preflight$
declare
  v_count bigint;
  v_ids text;
begin
  select count(*), string_agg(e.evaluation_id::text, ', ' order by e.evaluation_id)
  into v_count, v_ids
  from public.fit_evaluations e
  where e.evaluation_state = 'BUILDING'
    and e.financial_contract_version is null
    and (
      e.candidate_input_fingerprint is not null
      or exists (
        select 1 from public.fit_manifest_items i
        where i.evaluation_id = e.evaluation_id
          and exists (
            select 1
            from public.fit_evaluation_methods em
            where em.evaluation_id = e.evaluation_id
              and em.method_id = i.method_id
              and em.dimension = 'FINANCIAL'
          )
      )
      or exists (
        select 1 from public.fit_financial_normalizations n
        where n.evaluation_id = e.evaluation_id
      )
      or exists (
        select 1 from public.fit_signals s
        where s.evaluation_id = e.evaluation_id
          and s.dimension = 'FINANCIAL'
      )
    );

  if v_count > 0 then
    raise exception using
      errcode = '55000',
      message = format(
        'Migration 014 found %s incomplete legacy Financial evaluation(s): %s',
        v_count,
        v_ids
      ),
      hint = 'Discard and rebuild these BUILDING evaluations through the authorized lifecycle before retrying Migration 014.';
  end if;
end
$preflight$;

create or replace function public.fit_financial_period_for_billing_basis(
  p_basis public.billing_basis
)
returns public.fit_financial_period
language plpgsql
immutable
strict
set search_path = pg_catalog, public
as $$
begin
  case p_basis
    when 'TOTAL_PROGRAM' then return 'PROGRAM_DURATION';
    when 'PER_YEAR' then return 'ACADEMIC_YEAR';
    when 'PER_SEMESTER' then return 'ACADEMIC_SEMESTER';
    when 'PER_CREDIT' then return 'CREDIT';
    when 'UNKNOWN' then return null;
  end case;

  raise exception using
    errcode = '22023',
    message = format('Unmapped billing_basis label: %s', p_basis::text);
end;
$$;

create or replace function public.fit_financial_facts_directly_comparable(
  p_source_currency text,
  p_source_period public.fit_financial_period,
  p_source_scope public.fit_financial_scope,
  p_source_basis public.fit_financial_basis,
  p_source_components text[],
  p_target_currency text,
  p_target_period public.fit_financial_period,
  p_target_scope public.fit_financial_scope,
  p_target_basis public.fit_financial_basis,
  p_target_components text[]
)
returns boolean
language sql
immutable
set search_path = pg_catalog, public
as $$
  select case
    when p_source_currency is null
      or p_source_period is null
      or p_source_scope is null
      or p_source_basis is null
      or p_source_components is null
      or cardinality(p_source_components) = 0
      or array_position(p_source_components, null) is not null
      or array_position(p_source_components, '') is not null
      or not public.fit_text_array_is_set(p_source_components)
      or p_target_currency is null
      or p_target_period is null
      or p_target_scope is null
      or p_target_basis is null
      or p_target_components is null
      or cardinality(p_target_components) = 0
      or array_position(p_target_components, null) is not null
      or array_position(p_target_components, '') is not null
      or not public.fit_text_array_is_set(p_target_components)
      then false
    else p_source_currency = p_target_currency
      and p_source_period = p_target_period
      and p_source_scope = p_target_scope
      and p_source_basis = p_target_basis
      and (select array_agg(x order by x) from unnest(p_source_components) x)
        = (select array_agg(x order by x) from unnest(p_target_components) x)
  end;
$$;

create table private.fit_financial_source_pins_v014 (
  source_pin_id uuid primary key default extensions.gen_random_uuid(),
  evaluation_id uuid not null references public.fit_evaluations(evaluation_id) on delete cascade,
  amount_manifest_item_id uuid not null,
  basis_manifest_item_id uuid not null,
  amount_observation_id uuid not null references public.field_observations(observation_id) on delete restrict,
  billing_basis_observation_id uuid not null references public.field_observations(observation_id) on delete restrict,
  cost_id uuid not null references public.program_costs(cost_id) on delete restrict,
  source_billing_basis public.billing_basis not null check (source_billing_basis <> 'UNKNOWN'),
  source_mapped_period public.fit_financial_period not null,
  amount_selection_selected_at timestamptz not null,
  basis_selection_selected_at timestamptz not null,
  amount_observation_payload_hash text not null check (amount_observation_payload_hash ~ '^[0-9a-f]{64}$'),
  basis_observation_payload_hash text not null check (basis_observation_payload_hash ~ '^[0-9a-f]{64}$'),
  amount_evidence_payload_hash text not null check (amount_evidence_payload_hash ~ '^[0-9a-f]{64}$'),
  basis_evidence_payload_hash text not null check (basis_evidence_payload_hash ~ '^[0-9a-f]{64}$'),
  amount_applicability_payload_hash text not null check (amount_applicability_payload_hash ~ '^[0-9a-f]{64}$'),
  basis_applicability_payload_hash text not null check (basis_applicability_payload_hash ~ '^[0-9a-f]{64}$'),
  cost_payload_hash text not null check (cost_payload_hash ~ '^[0-9a-f]{64}$'),
  pinned_at timestamptz not null default transaction_timestamp(),
  unique (evaluation_id, amount_manifest_item_id, basis_manifest_item_id),
  unique (evaluation_id, source_pin_id),
  check (amount_observation_id <> billing_basis_observation_id),
  foreign key (amount_manifest_item_id, evaluation_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id) on delete cascade,
  foreign key (basis_manifest_item_id, evaluation_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id) on delete cascade
);

alter table public.fit_financial_normalizations
  add column source_pin_id uuid;

alter table public.fit_financial_normalizations
  add constraint fit_financial_normalizations_source_pin_v014_fk
  foreign key (evaluation_id, source_pin_id)
  references private.fit_financial_source_pins_v014(evaluation_id, source_pin_id)
  on delete restrict;

create table public.fit_financial_normalization_reviews_v014 (
  financial_normalization_id uuid primary key
    references public.fit_financial_normalizations(financial_normalization_id) on delete cascade,
  evaluation_id uuid not null references public.fit_evaluations(evaluation_id) on delete cascade,
  status public.fit_definition_status not null default 'DRAFT',
  reviewed_by text,
  reviewed_at timestamptz,
  verification_evidence_id uuid references public.evidence_items(evidence_id) on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fit_financial_normalization_reviews_v014_state check (
    (status = 'DRAFT'
      and reviewed_by is null and reviewed_at is null
      and verification_evidence_id is null
      and retired_at is null and retirement_reason is null)
    or
    (status = 'VERIFIED'
      and nullif(btrim(reviewed_by), '') is not null
      and reviewed_at is not null and verification_evidence_id is not null
      and retired_at is null and retirement_reason is null)
    or
    (status = 'RETIRED'
      and nullif(btrim(reviewed_by), '') is not null
      and reviewed_at is not null and verification_evidence_id is not null
      and retired_at is not null
      and nullif(btrim(retirement_reason), '') is not null)
  ),
  unique (evaluation_id, financial_normalization_id)
);

create table public.fit_financial_conversion_factors_v014 (
  conversion_factor_id uuid primary key default extensions.gen_random_uuid(),
  financial_normalization_id uuid not null
    references public.fit_financial_normalizations(financial_normalization_id) on delete cascade,
  factor_ordinal smallint not null check (factor_ordinal > 0),
  factor_code text not null check (factor_code ~ '^[A-Z][A-Z0-9_]*$'),
  operation text not null check (operation in ('MULTIPLY','DIVIDE','ADD','SUBTRACT')),
  factor_value numeric not null,
  source_unit text not null check (nullif(btrim(source_unit), '') is not null),
  target_unit text not null check (nullif(btrim(target_unit), '') is not null),
  evidence_id uuid not null references public.evidence_items(evidence_id) on delete restrict,
  unique (financial_normalization_id, factor_ordinal)
);

create table public.fit_financial_conversion_inputs_v014 (
  conversion_input_id uuid primary key default extensions.gen_random_uuid(),
  financial_normalization_id uuid not null
    references public.fit_financial_normalizations(financial_normalization_id) on delete cascade,
  input_ordinal smallint not null check (input_ordinal > 0),
  input_role text not null check (input_role in (
    'SOURCE_AMOUNT','PROGRAM_DURATION','ACADEMIC_YEARS','SEMESTERS','CREDITS',
    'EXCHANGE_RATE','AVAILABLE_FUNDING','ROUNDING'
  )),
  numeric_value numeric,
  text_value text,
  unit text not null check (nullif(btrim(unit), '') is not null),
  source_observation_id uuid references public.field_observations(observation_id) on delete restrict,
  intent_declaration_id uuid references public.fit_intent_declarations(intent_declaration_id) on delete restrict,
  evidence_id uuid not null references public.evidence_items(evidence_id) on delete restrict,
  unique (financial_normalization_id, input_ordinal),
  check ((numeric_value is null) <> (text_value is null))
);

create unique index fit_financial_conversion_inputs_v014_role_key
on public.fit_financial_conversion_inputs_v014 (
  financial_normalization_id, input_role
);

create unique index fit_financial_conversion_factors_v014_code_key
on public.fit_financial_conversion_factors_v014 (
  financial_normalization_id, factor_code
);

create table private.fit_financial_normalization_verified_pins_v014 (
  financial_normalization_id uuid primary key
    references public.fit_financial_normalizations(financial_normalization_id) on delete cascade,
  evaluation_id uuid not null references public.fit_evaluations(evaluation_id) on delete cascade,
  method_payload_hash text not null check (method_payload_hash ~ '^[0-9a-f]{64}$'),
  method_evidence_payload_hash text not null check (method_evidence_payload_hash ~ '^[0-9a-f]{64}$'),
  normalization_review_evidence_hash text not null check (normalization_review_evidence_hash ~ '^[0-9a-f]{64}$'),
  typed_input_payload_hash text not null check (typed_input_payload_hash ~ '^[0-9a-f]{64}$'),
  typed_factor_payload_hash text not null check (typed_factor_payload_hash ~ '^[0-9a-f]{64}$'),
  legacy_json_hash text not null check (legacy_json_hash ~ '^[0-9a-f]{64}$'),
  target_constraint_payload_hash text not null check (target_constraint_payload_hash ~ '^[0-9a-f]{64}$'),
  verified_at timestamptz not null default transaction_timestamp(),
  unique (evaluation_id, financial_normalization_id)
);

create or replace function private.set_fit_financial_contract_v014()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  new.financial_contract_version := 'FINANCIAL_BILLING_BASIS_V014';
  return new;
end;
$$;

create trigger fit_evaluations_set_financial_contract_v014
before insert on public.fit_evaluations
for each row execute function private.set_fit_financial_contract_v014();

create or replace function private.guard_fit_financial_contract_v014()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if new.financial_contract_version is not distinct from old.financial_contract_version then
    return new;
  end if;
  if old.financial_contract_version is null
     and new.financial_contract_version = 'FINANCIAL_BILLING_BASIS_V014'
     and old.evaluation_state = 'BUILDING'
     and new.evaluation_state = 'BUILDING'
     and old.candidate_input_fingerprint is null
     and new.candidate_input_fingerprint is null
     and current_setting('app.fit_financial_v014_adopt', true) = 'on' then
    return new;
  end if;
  raise exception using errcode = '55000',
    message = 'Financial contract version is immutable outside authorized v014 adoption';
end;
$$;

create trigger fit_evaluations_guard_financial_contract_v014
before update on public.fit_evaluations
for each row execute function private.guard_fit_financial_contract_v014();

create or replace function public.adopt_fit_financial_contract_v014(p_evaluation_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_prior_adopt text;
  v_prior_write text;
begin
  perform 1 from public.fit_evaluations e
  where e.evaluation_id = p_evaluation_id
    and e.evaluation_state = 'BUILDING'
    and e.financial_contract_version is null
    and e.candidate_input_fingerprint is null
  for update;
  if not found then
    raise exception using errcode = '55000', message = 'Only an unsealed legacy BUILDING evaluation may adopt v014';
  end if;
  if not exists (
    select 1 from private.fit_evaluation_assembly_authorizations a
    join public.fit_evaluations e using (evaluation_id)
    where a.evaluation_id = p_evaluation_id
      and a.execution_id = e.execution_id
      and a.evaluator_build_id = e.evaluator_build_id
      and a.evaluator_build_hash = e.evaluator_build_hash
  ) then
    raise exception using errcode = '42501', message = 'No durable assembly authorization exists for this evaluation execution';
  end if;
  if exists (select 1 from public.fit_manifest_items where evaluation_id = p_evaluation_id)
     or exists (select 1 from public.fit_financial_normalizations where evaluation_id = p_evaluation_id)
     or exists (select 1 from public.fit_signals where evaluation_id = p_evaluation_id) then
    raise exception using errcode = '55000', message = 'Legacy evaluation with Fit child rows cannot adopt v014';
  end if;
  v_prior_adopt := current_setting('app.fit_financial_v014_adopt', true);
  v_prior_write := current_setting('app.fit_evaluation_controlled_write', true);
  perform set_config('app.fit_financial_v014_adopt', 'on', true);
  perform set_config('app.fit_evaluation_controlled_write', 'on', true);
  update public.fit_evaluations
  set financial_contract_version = 'FINANCIAL_BILLING_BASIS_V014'
  where evaluation_id = p_evaluation_id;
  perform set_config('app.fit_financial_v014_adopt', coalesce(v_prior_adopt, ''), true);
  perform set_config('app.fit_evaluation_controlled_write', coalesce(v_prior_write, ''), true);
end;
$$;

create or replace function private.create_fit_financial_review_v014()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if exists (
    select 1 from public.fit_evaluations e
    where e.evaluation_id = new.evaluation_id
      and e.financial_contract_version = 'FINANCIAL_BILLING_BASIS_V014'
  ) then
    perform set_config('app.fit_financial_v014_review_insert', 'on', true);
    insert into public.fit_financial_normalization_reviews_v014 (
      financial_normalization_id, evaluation_id
    ) values (new.financial_normalization_id, new.evaluation_id);
    perform set_config('app.fit_financial_v014_review_insert', '', true);
  end if;
  return new;
end;
$$;

create or replace function private.guard_fit_financial_review_insert_v014()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if current_setting('app.fit_financial_v014_review_insert', true) = 'on'
     and new.status = 'DRAFT' then
    return new;
  end if;
  raise exception using errcode = '55000', message = 'Financial normalization review rows are created only by the normalization trigger';
end;
$$;

create trigger fit_financial_normalizations_create_review_v014
after insert on public.fit_financial_normalizations
for each row execute function private.create_fit_financial_review_v014();

create trigger fit_financial_reviews_no_direct_insert_v014
before insert on public.fit_financial_normalization_reviews_v014
for each row execute function private.guard_fit_financial_review_insert_v014();

create or replace function private.require_fit_financial_v014_assembly(
  p_financial_normalization_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_evaluation_id uuid;
begin
  select n.evaluation_id into v_evaluation_id
  from public.fit_financial_normalizations n
  join public.fit_evaluations e using (evaluation_id)
  join public.fit_financial_normalization_reviews_v014 r
    using (financial_normalization_id, evaluation_id)
  where n.financial_normalization_id = p_financial_normalization_id
    and e.financial_contract_version = 'FINANCIAL_BILLING_BASIS_V014'
    and e.evaluation_state = 'BUILDING'
    and e.candidate_input_fingerprint is null
    and r.status = 'DRAFT'
  for update of e, n, r;
  if v_evaluation_id is null then
    raise exception using errcode = '55000',
      message = 'Typed Financial inputs require an unsealed v014 BUILDING evaluation and DRAFT normalization';
  end if;
  if not exists (
    select 1 from private.fit_evaluation_assembly_authorizations a
    join public.fit_evaluations e using (evaluation_id)
    where a.evaluation_id = v_evaluation_id
      and a.execution_id = e.execution_id
      and a.evaluator_build_id = e.evaluator_build_id
      and a.evaluator_build_hash = e.evaluator_build_hash
  ) then
    raise exception using errcode = '42501',
      message = 'No durable assembly authorization exists for this evaluation execution';
  end if;
  return v_evaluation_id;
end;
$$;

create or replace function public.pin_fit_financial_source_v014(
  p_evaluation_id uuid,
  p_amount_manifest_item_id uuid,
  p_basis_manifest_item_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_eval public.fit_evaluations%rowtype;
  v_amount public.field_observations%rowtype;
  v_basis public.field_observations%rowtype;
  v_amount_selection public.canonical_field_selections%rowtype;
  v_basis_selection public.canonical_field_selections%rowtype;
  v_cost public.program_costs%rowtype;
  v_amount_evidence public.evidence_items%rowtype;
  v_basis_evidence public.evidence_items%rowtype;
  v_amount_link public.field_observation_applicability%rowtype;
  v_basis_link public.field_observation_applicability%rowtype;
  v_amount_assertion public.evidence_applicability_assertions%rowtype;
  v_basis_assertion public.evidence_applicability_assertions%rowtype;
  v_amount_head public.evidence_applicability_heads%rowtype;
  v_basis_head public.evidence_applicability_heads%rowtype;
  v_amount_numeric numeric;
  v_live_amount numeric;
  v_basis_value public.billing_basis;
  v_pin_id uuid;
begin
  select * into v_eval from public.fit_evaluations
  where evaluation_id = p_evaluation_id for update;
  if not found or v_eval.evaluation_state <> 'BUILDING'
     or v_eval.candidate_input_fingerprint is not null
     or v_eval.financial_contract_version <> 'FINANCIAL_BILLING_BASIS_V014' then
    raise exception using errcode='55000', message='Source pin requires an unsealed v014 BUILDING evaluation';
  end if;
  if not exists (
    select 1 from private.fit_evaluation_assembly_authorizations a
    where a.evaluation_id=p_evaluation_id and a.execution_id=v_eval.execution_id
      and a.evaluator_build_id=v_eval.evaluator_build_id
      and a.evaluator_build_hash=v_eval.evaluator_build_hash
  ) then
    raise exception using errcode='42501', message='No durable assembly authorization exists for this evaluation execution';
  end if;
  if p_amount_manifest_item_id = p_basis_manifest_item_id then
    raise exception using errcode='23514', message='Amount and billing-basis manifest items must be distinct';
  end if;
  if not exists (
    select 1 from public.fit_manifest_items i
    join public.fit_evaluation_methods em
      on em.evaluation_id=i.evaluation_id and em.method_id=i.method_id
    where i.manifest_item_id in (p_amount_manifest_item_id,p_basis_manifest_item_id)
      and i.evaluation_id=p_evaluation_id
      and i.profile_version_id=v_eval.profile_version_id
      and i.item_type='CATALOG_FIELD_OBSERVATION'
      and em.dimension='FINANCIAL'
    group by i.evaluation_id having count(*)=2
  ) then
    raise exception using errcode='23514', message='Both source observations must be distinct Financial catalog manifest items';
  end if;
  select o.* into v_amount
  from public.fit_manifest_catalog_observations m
  join public.field_observations o on o.observation_id=m.field_observation_id
  where m.manifest_item_id=p_amount_manifest_item_id and m.evaluation_id=p_evaluation_id;
  select o.* into v_basis
  from public.fit_manifest_catalog_observations m
  join public.field_observations o on o.observation_id=m.field_observation_id
  where m.manifest_item_id=p_basis_manifest_item_id and m.evaluation_id=p_evaluation_id;
  if v_amount.observation_id is null or v_basis.observation_id is null
     or v_amount.observation_id=v_basis.observation_id
     or v_amount.record_type<>'PROGRAM_COST' or v_basis.record_type<>'PROGRAM_COST'
     or v_amount.record_id<>v_basis.record_id
     or v_amount.field_name not in ('tuition_amount','mandatory_fees','estimated_living_cost','estimated_total_cost')
     or v_basis.field_name<>'billing_basis'
     or v_amount.knowledge_status<>'KNOWN' or v_basis.knowledge_status<>'KNOWN'
     or jsonb_typeof(v_amount.observed_value)<>'number'
     or jsonb_typeof(v_basis.observed_value)<>'string'
     or v_amount.evidence_id is null or v_basis.evidence_id is null then
    raise exception using errcode='23514', message='Source pin requires distinct selected KNOWN amount and billing_basis observations on one PROGRAM_COST';
  end if;
  select * into v_cost from public.program_costs
  where cost_id=v_amount.record_id for update;
  if not found or v_cost.retired_at is not null
     or v_cost.program_version_id<>v_eval.program_version_id then
    raise exception using errcode='23514', message='Source PROGRAM_COST must be active and match the evaluation program version';
  end if;
  v_amount_numeric := (v_amount.observed_value #>> '{}')::numeric;
  v_live_amount := case v_amount.field_name
    when 'tuition_amount' then v_cost.tuition_amount
    when 'mandatory_fees' then v_cost.mandatory_fees
    when 'estimated_living_cost' then v_cost.estimated_living_cost
    when 'estimated_total_cost' then v_cost.estimated_total_cost end;
  v_basis_value := (v_basis.observed_value #>> '{}')::public.billing_basis;
  if v_live_amount is distinct from v_amount_numeric
     or v_cost.billing_basis is null or v_cost.billing_basis='UNKNOWN'
     or v_basis_value is distinct from v_cost.billing_basis
     or public.fit_financial_period_for_billing_basis(v_basis_value) is null then
    raise exception using errcode='23514', message='Observed amount and billing basis must exactly match the live typed cost row';
  end if;
  select * into v_amount_selection from public.canonical_field_selections
  where record_type='PROGRAM_COST' and record_id=v_cost.cost_id
    and field_name=v_amount.field_name and observation_id=v_amount.observation_id for update;
  select * into v_basis_selection from public.canonical_field_selections
  where record_type='PROGRAM_COST' and record_id=v_cost.cost_id
    and field_name='billing_basis' and observation_id=v_basis.observation_id for update;
  if v_amount_selection.observation_id is null or v_basis_selection.observation_id is null then
    raise exception using errcode='23514', message='Both observations must be the current exact canonical selections';
  end if;
  select * into v_amount_link from public.field_observation_applicability where observation_id=v_amount.observation_id for update;
  select * into v_basis_link from public.field_observation_applicability where observation_id=v_basis.observation_id for update;
  select * into v_amount_assertion from public.evidence_applicability_assertions where assertion_id=v_amount_link.assertion_id for update;
  select * into v_basis_assertion from public.evidence_applicability_assertions where assertion_id=v_basis_link.assertion_id for update;
  select * into v_amount_head from public.evidence_applicability_heads where scope_id=v_amount_assertion.scope_id for update;
  select * into v_basis_head from public.evidence_applicability_heads where scope_id=v_basis_assertion.scope_id for update;
  if v_amount_assertion.applicability_status<>'REVIEWED_APPLICABLE'
     or v_basis_assertion.applicability_status<>'REVIEWED_APPLICABLE'
     or v_amount_head.assertion_id<>v_amount_assertion.assertion_id
     or v_basis_head.assertion_id<>v_basis_assertion.assertion_id then
    raise exception using errcode='23514', message='Both observations require current REVIEWED_APPLICABLE evidence assertions';
  end if;
  select * into v_amount_evidence from public.evidence_items where evidence_id=v_amount.evidence_id for update;
  select * into v_basis_evidence from public.evidence_items where evidence_id=v_basis.evidence_id for update;
  insert into private.fit_financial_source_pins_v014 (
    evaluation_id,amount_manifest_item_id,basis_manifest_item_id,
    amount_observation_id,billing_basis_observation_id,cost_id,
    source_billing_basis,source_mapped_period,
    amount_selection_selected_at,basis_selection_selected_at,
    amount_observation_payload_hash,basis_observation_payload_hash,
    amount_evidence_payload_hash,basis_evidence_payload_hash,
    amount_applicability_payload_hash,basis_applicability_payload_hash,cost_payload_hash
  ) values (
    p_evaluation_id,p_amount_manifest_item_id,p_basis_manifest_item_id,
    v_amount.observation_id,v_basis.observation_id,v_cost.cost_id,
    v_basis_value,public.fit_financial_period_for_billing_basis(v_basis_value),
    v_amount_selection.selected_at,v_basis_selection.selected_at,
    encode(extensions.digest(convert_to(to_jsonb(v_amount)::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(to_jsonb(v_basis)::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(to_jsonb(v_amount_evidence)::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(to_jsonb(v_basis_evidence)::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(jsonb_build_object('link',to_jsonb(v_amount_link),'head',to_jsonb(v_amount_head),'assertion',to_jsonb(v_amount_assertion))::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(jsonb_build_object('link',to_jsonb(v_basis_link),'head',to_jsonb(v_basis_head),'assertion',to_jsonb(v_basis_assertion))::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(to_jsonb(v_cost)::text,'UTF8'),'sha256'),'hex')
  ) returning source_pin_id into v_pin_id;
  return v_pin_id;
end;
$$;

create or replace function public.insert_fit_financial_conversion_input_v014(
  p_row public.fit_financial_conversion_inputs_v014
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_id uuid;
begin
  perform private.require_fit_financial_v014_assembly(p_row.financial_normalization_id);
  v_id := coalesce(p_row.conversion_input_id, extensions.gen_random_uuid());
  insert into public.fit_financial_conversion_inputs_v014 (
    conversion_input_id,financial_normalization_id,input_ordinal,input_role,
    numeric_value,text_value,unit,source_observation_id,
    intent_declaration_id,evidence_id
  ) values (
    v_id,p_row.financial_normalization_id,p_row.input_ordinal,p_row.input_role,
    p_row.numeric_value,p_row.text_value,p_row.unit,p_row.source_observation_id,
    p_row.intent_declaration_id,p_row.evidence_id
  );
  return v_id;
end;
$$;

create or replace function public.insert_fit_financial_conversion_factor_v014(
  p_row public.fit_financial_conversion_factors_v014
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_id uuid;
begin
  perform private.require_fit_financial_v014_assembly(p_row.financial_normalization_id);
  v_id := coalesce(p_row.conversion_factor_id, extensions.gen_random_uuid());
  insert into public.fit_financial_conversion_factors_v014 (
    conversion_factor_id,financial_normalization_id,factor_ordinal,
    factor_code,operation,factor_value,source_unit,target_unit,evidence_id
  ) values (
    v_id,p_row.financial_normalization_id,p_row.factor_ordinal,
    p_row.factor_code,p_row.operation,p_row.factor_value,
    p_row.source_unit,p_row.target_unit,p_row.evidence_id
  );
  return v_id;
end;
$$;

create or replace function private.guard_fit_financial_typed_rows_v014()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if tg_op = 'INSERT' then return new; end if;
  raise exception using errcode = '55000',
    message = 'Typed Financial conversion rows are append-only';
end;
$$;

create trigger fit_financial_inputs_append_only_v014
before update or delete on public.fit_financial_conversion_inputs_v014
for each row execute function private.guard_fit_financial_typed_rows_v014();
create trigger fit_financial_factors_append_only_v014
before update or delete on public.fit_financial_conversion_factors_v014
for each row execute function private.guard_fit_financial_typed_rows_v014();

create or replace function private.fit_financial_typed_input_payload_hash_v014(
  p_financial_normalization_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $$
  select encode(extensions.digest(convert_to(coalesce((select jsonb_agg(
    (to_jsonb(i)
      - 'conversion_input_id' - 'financial_normalization_id'
      - 'source_observation_id' - 'intent_declaration_id' - 'evidence_id')
    || jsonb_build_object(
      'sourceObservationHash',case when o.observation_id is null then null else
        encode(extensions.digest(convert_to(to_jsonb(o)::text,'UTF8'),'sha256'),'hex') end,
      'intentDeclarationHash',case when d.intent_declaration_id is null then null else
        encode(extensions.digest(convert_to(to_jsonb(d)::text,'UTF8'),'sha256'),'hex') end,
      'intentFinancialConstraintHash',case when c.intent_declaration_id is null then null else
        encode(extensions.digest(convert_to(to_jsonb(c)::text,'UTF8'),'sha256'),'hex') end,
      'evidenceHash',encode(extensions.digest(convert_to(to_jsonb(ie)::text,'UTF8'),'sha256'),'hex')
    ) order by i.input_ordinal
  ) from public.fit_financial_conversion_inputs_v014 i
    join public.evidence_items ie on ie.evidence_id=i.evidence_id
    left join public.field_observations o
      on o.observation_id=i.source_observation_id
    left join public.fit_intent_declarations d
      on d.intent_declaration_id=i.intent_declaration_id
    left join public.fit_intent_financial_constraints c
      on c.intent_declaration_id=i.intent_declaration_id
    where i.financial_normalization_id=p_financial_normalization_id
  ),'[]')::text,'UTF8'),'sha256'),'hex');
$$;

create or replace function private.fit_financial_typed_factor_payload_hash_v014(
  p_financial_normalization_id uuid
)
returns text
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $$
  select encode(extensions.digest(convert_to(coalesce((select jsonb_agg(
    (to_jsonb(f)
      - 'conversion_factor_id' - 'financial_normalization_id' - 'evidence_id')
    || jsonb_build_object(
      'evidenceHash',encode(extensions.digest(convert_to(to_jsonb(fe)::text,'UTF8'),'sha256'),'hex')
    ) order by f.factor_ordinal
  ) from public.fit_financial_conversion_factors_v014 f
    join public.evidence_items fe on fe.evidence_id=f.evidence_id
    where f.financial_normalization_id=p_financial_normalization_id
  ),'[]')::text,'UTF8'),'sha256'),'hex');
$$;

create or replace function private.guard_fit_financial_normalization_update_v014()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
begin
  if exists (
    select 1
    from public.fit_evaluations e
    join public.fit_financial_normalization_reviews_v014 r
      on r.evaluation_id=e.evaluation_id
    where e.evaluation_id=old.evaluation_id
      and e.financial_contract_version='FINANCIAL_BILLING_BASIS_V014'
      and r.financial_normalization_id=old.financial_normalization_id
      and r.status in ('VERIFIED','RETIRED')
  ) then
    raise exception using errcode='55000',
      message='VERIFIED Financial normalization payloads are immutable';
  end if;
  return coalesce(new,old);
end;
$$;

create trigger a_fit_financial_normalizations_verified_immutable_v014
before update or delete on public.fit_financial_normalizations
for each row execute function private.guard_fit_financial_normalization_update_v014();

create or replace function private.guard_fit_financial_review_update_v014()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if current_setting('app.fit_financial_v014_review_update', true)
       is distinct from 'on' then
    raise exception using errcode = '55000',
      message = 'Financial normalization lifecycle changes require an authorized entry point';
  end if;
  if old.status = 'DRAFT' and new.status = 'VERIFIED' then return new; end if;
  if old.status = 'VERIFIED' and new.status = 'RETIRED'
     and (to_jsonb(new) - 'status' - 'retired_at' - 'retirement_reason' - 'updated_at')
       is not distinct from
         (to_jsonb(old) - 'status' - 'retired_at' - 'retirement_reason' - 'updated_at') then
    return new;
  end if;
  raise exception using errcode = '55000',
    message = 'Only DRAFT to VERIFIED to RETIRED is permitted';
end;
$$;

create trigger fit_financial_reviews_lifecycle_v014
before update or delete on public.fit_financial_normalization_reviews_v014
for each row execute function private.guard_fit_financial_review_update_v014();

create or replace function public.verify_fit_financial_normalization_v014(
  p_financial_normalization_id uuid,
  p_reviewed_by text,
  p_verification_evidence_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_n public.fit_financial_normalizations%rowtype;
  v_m public.fit_financial_normalization_methods%rowtype;
  v_evaluation_id uuid;
  v_roles text[];
  v_factors text[];
  v_required_roles text[];
  v_allowed_roles text[];
  v_required_factors text[];
  v_allowed_factors text[];
  v_source_input public.fit_financial_conversion_inputs_v014%rowtype;
  v_rounding_input public.fit_financial_conversion_inputs_v014%rowtype;
  v_years_input public.fit_financial_conversion_inputs_v014%rowtype;
  v_years_factor public.fit_financial_conversion_factors_v014%rowtype;
  v_funding_input public.fit_financial_conversion_inputs_v014%rowtype;
  v_funding_factor public.fit_financial_conversion_factors_v014%rowtype;
  v_funding_constraint public.fit_intent_financial_constraints%rowtype;
  v_funding_count bigint;
  v_formula_code text;
begin
  if nullif(btrim(p_reviewed_by), '') is null then
    raise exception using errcode = '22023', message = 'reviewed_by is required';
  end if;
  select n.* into v_n from public.fit_financial_normalizations n
  where n.financial_normalization_id = p_financial_normalization_id for update;
  if not found then raise exception using errcode = '22023', message = 'Financial normalization not found'; end if;
  v_evaluation_id := v_n.evaluation_id;
  perform 1 from public.fit_evaluations e
  where e.evaluation_id = v_evaluation_id
    and e.financial_contract_version = 'FINANCIAL_BILLING_BASIS_V014'
  for update;
  select m.* into v_m from public.fit_financial_normalization_methods m
  where m.normalization_method_id = v_n.normalization_method_id for update;
  if v_m.status <> 'VERIFIED' or v_m.retired_at is not null then
    raise exception using errcode = '55000', message = 'Normalization method must be active VERIFIED';
  end if;
  if not exists (select 1 from public.evidence_items where evidence_id = p_verification_evidence_id for update) then
    raise exception using errcode = '22023', message = 'Verification evidence not found';
  end if;
  select coalesce(array_agg(input_role order by input_role), '{}') into v_roles
  from public.fit_financial_conversion_inputs_v014 where financial_normalization_id = p_financial_normalization_id;
  select coalesce(array_agg(factor_code order by factor_code), '{}') into v_factors
  from public.fit_financial_conversion_factors_v014 where financial_normalization_id = p_financial_normalization_id;
  select coalesce(array_agg(value order by value), '{}') into v_required_roles
  from jsonb_array_elements_text(v_m.normalization_contract -> 'requiredInputRoles') value;
  select coalesce(array_agg(value order by value), '{}') into v_allowed_roles
  from jsonb_array_elements_text(v_m.normalization_contract -> 'allowedInputRoles') value;
  select coalesce(array_agg(value order by value), '{}') into v_required_factors
  from jsonb_array_elements_text(v_m.normalization_contract -> 'requiredFactorCodes') value;
  select coalesce(array_agg(value order by value), '{}') into v_allowed_factors
  from jsonb_array_elements_text(v_m.normalization_contract -> 'allowedFactorCodes') value;
  if jsonb_typeof(v_m.normalization_contract -> 'requiredInputRoles') <> 'array'
     or jsonb_typeof(v_m.normalization_contract -> 'allowedInputRoles') <> 'array'
     or jsonb_typeof(v_m.normalization_contract -> 'requiredFactorCodes') <> 'array'
     or jsonb_typeof(v_m.normalization_contract -> 'allowedFactorCodes') <> 'array'
     or nullif(v_m.normalization_contract ->> 'formulaCode', '') is null
     or not v_roles @> v_required_roles or not v_roles <@ v_allowed_roles
     or not v_factors @> v_required_factors or not v_factors <@ v_allowed_factors then
    raise exception using errcode = '23514', message = 'Typed rows do not satisfy the closed normalization contract';
  end if;
  if (select count(*) from public.fit_financial_conversion_inputs_v014
      where financial_normalization_id = p_financial_normalization_id and input_role = 'SOURCE_AMOUNT') <> 1
     or (select count(*) from public.fit_financial_conversion_inputs_v014
      where financial_normalization_id = p_financial_normalization_id and input_role = 'ROUNDING'
        and text_value in ('NONE','HALF_UP','HALF_EVEN','FLOOR','CEILING') and unit = 'RULE') <> 1 then
    raise exception using errcode = '23514', message = 'SOURCE_AMOUNT and valid ROUNDING are required exactly once';
  end if;
  select * into v_source_input
  from public.fit_financial_conversion_inputs_v014
  where financial_normalization_id=p_financial_normalization_id
    and input_role='SOURCE_AMOUNT';
  if v_source_input.numeric_value is distinct from v_n.original_amount
     or v_source_input.text_value is not null
     or btrim(v_source_input.unit) is distinct from btrim(v_n.original_currency::text)
     or v_source_input.source_observation_id is distinct from v_n.field_observation_id
     or v_source_input.intent_declaration_id is not null then
    raise exception using errcode='23514',
      message='SOURCE_AMOUNT must exactly match the pinned normalization amount, currency, and observation';
  end if;
  select * into v_rounding_input
  from public.fit_financial_conversion_inputs_v014
  where financial_normalization_id=p_financial_normalization_id
    and input_role='ROUNDING';
  if v_rounding_input.numeric_value is not null
     or v_rounding_input.text_value not in (
       'NONE','HALF_UP','HALF_EVEN','FLOOR','CEILING'
     )
     or v_rounding_input.unit<>'RULE'
     or v_rounding_input.source_observation_id is not null
     or v_rounding_input.intent_declaration_id is not null then
    raise exception using errcode='23514',
      message='ROUNDING must be one closed rule with no observation or intent reference';
  end if;
  select count(*) into v_funding_count
  from public.fit_financial_conversion_inputs_v014
  where financial_normalization_id=p_financial_normalization_id
    and input_role='AVAILABLE_FUNDING';
  if v_n.target_basis='NET_OF_VERIFIED_FUNDING' then
    if v_funding_count<>1 then
      raise exception using errcode='23514',
        message='NET_OF_VERIFIED_FUNDING requires exactly one typed AVAILABLE_FUNDING input';
    end if;
    select * into v_funding_input
    from public.fit_financial_conversion_inputs_v014
    where financial_normalization_id=p_financial_normalization_id
      and input_role='AVAILABLE_FUNDING';
    select * into v_funding_constraint
    from public.fit_intent_financial_constraints c
    where c.intent_declaration_id=v_funding_input.intent_declaration_id
      and c.intent_set_id=v_n.intent_set_id
      and c.profile_version_id=v_n.profile_version_id;
    if not found
       or v_funding_constraint.constraint_semantics<>'AVAILABLE_FUNDING'
       or v_funding_input.numeric_value is distinct from v_funding_constraint.amount
       or v_funding_input.text_value is not null
       or btrim(v_funding_input.unit) is distinct from
          btrim(v_funding_constraint.currency::text)
       or v_funding_input.source_observation_id is not null
       or v_funding_input.intent_declaration_id is null
       or v_funding_input.intent_declaration_id=v_n.financial_constraint_id
       or v_funding_constraint.financial_period is distinct from v_n.target_period
       or v_funding_constraint.financial_scope is distinct from v_n.target_scope
       or (select array_agg(x order by x)
           from unnest(v_funding_constraint.components) x) is distinct from
          (select array_agg(x order by x) from unnest(v_n.target_components) x) then
      raise exception using errcode='23514',
        message='AVAILABLE_FUNDING must exactly reference a separate matching frozen funding declaration';
    end if;
  elsif v_funding_count<>0 then
    raise exception using errcode='23514',
      message='Gross Financial normalization forbids AVAILABLE_FUNDING';
  end if;
  v_formula_code:=v_m.normalization_contract->>'formulaCode';
  if v_formula_code in (
    'MULTIPLY_SOURCE_BY_ACADEMIC_YEARS',
    'MULTIPLY_SOURCE_BY_ACADEMIC_YEARS_THEN_SUBTRACT_FUNDING'
  ) then
    select * into v_years_input
    from public.fit_financial_conversion_inputs_v014
    where financial_normalization_id=p_financial_normalization_id
      and input_role='ACADEMIC_YEARS';
    select * into v_years_factor
    from public.fit_financial_conversion_factors_v014
    where financial_normalization_id=p_financial_normalization_id
      and factor_code='ACADEMIC_YEARS';
    if v_years_input.numeric_value is null
       or v_years_input.numeric_value<=0
       or v_years_input.text_value is not null
       or v_years_input.unit<>'ACADEMIC_YEAR'
       or v_years_input.source_observation_id is not null
       or v_years_input.intent_declaration_id is not null
       or v_years_factor.operation<>'MULTIPLY'
       or v_years_factor.factor_value is distinct from v_years_input.numeric_value
       or v_years_factor.source_unit is distinct from
          btrim(v_n.original_currency::text)||'_PER_'||v_n.original_period::text
       or v_years_factor.target_unit is distinct from
          btrim(v_n.target_currency::text)||'_PER_'||v_n.target_period::text then
      raise exception using errcode='23514',
        message='MULTIPLY_SOURCE_BY_ACADEMIC_YEARS requires one positive matching years input and exact multiply factor units';
    end if;
    if v_formula_code=
       'MULTIPLY_SOURCE_BY_ACADEMIC_YEARS_THEN_SUBTRACT_FUNDING' then
      if v_n.target_basis<>'NET_OF_VERIFIED_FUNDING' then
        raise exception using errcode='23514',
          message='Funding subtraction formula requires NET_OF_VERIFIED_FUNDING target basis';
      end if;
      select * into v_funding_factor
      from public.fit_financial_conversion_factors_v014
      where financial_normalization_id=p_financial_normalization_id
        and factor_code='AVAILABLE_FUNDING';
      if v_funding_factor.operation<>'SUBTRACT'
         or v_funding_factor.factor_value is distinct from
            v_funding_input.numeric_value
         or btrim(v_funding_factor.source_unit) is distinct from
            btrim(v_n.target_currency::text)
         or btrim(v_funding_factor.target_unit) is distinct from
            btrim(v_n.target_currency::text) then
        raise exception using errcode='23514',
          message='Funding subtraction formula requires one exact SUBTRACT factor';
      end if;
    elsif v_n.target_basis='NET_OF_VERIFIED_FUNDING' then
      raise exception using errcode='23514',
        message='Annualization-only formula cannot produce NET_OF_VERIFIED_FUNDING';
    end if;
  else
    raise exception using errcode='23514',
      message='Unsupported Financial normalization formulaCode';
  end if;
  perform set_config('app.fit_financial_v014_review_update', 'on', true);
  update public.fit_financial_normalization_reviews_v014
  set status = 'VERIFIED', reviewed_by = p_reviewed_by,
      reviewed_at = transaction_timestamp(), verification_evidence_id = p_verification_evidence_id,
      updated_at = transaction_timestamp()
  where financial_normalization_id = p_financial_normalization_id and status = 'DRAFT';
  if not found then raise exception using errcode = '55000', message = 'A DRAFT normalization review is required'; end if;
  insert into private.fit_financial_normalization_verified_pins_v014 (
    financial_normalization_id, evaluation_id, method_payload_hash,
    method_evidence_payload_hash, normalization_review_evidence_hash,
    typed_input_payload_hash, typed_factor_payload_hash, legacy_json_hash,
    target_constraint_payload_hash
  ) values (
    p_financial_normalization_id, v_evaluation_id,
    encode(extensions.digest(convert_to(to_jsonb(v_m)::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(to_jsonb((select e from public.evidence_items e where e.evidence_id=v_m.verification_evidence_id))::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(to_jsonb((select e from public.evidence_items e where e.evidence_id=p_verification_evidence_id))::text,'UTF8'),'sha256'),'hex'),
    private.fit_financial_typed_input_payload_hash_v014(
      p_financial_normalization_id
    ),
    private.fit_financial_typed_factor_payload_hash_v014(
      p_financial_normalization_id
    ),
    encode(extensions.digest(convert_to(v_n.conversion_evidence::text,'UTF8'),'sha256'),'hex'),
    encode(extensions.digest(convert_to(to_jsonb((select c from public.fit_intent_financial_constraints c where c.intent_declaration_id=v_n.financial_constraint_id))::text,'UTF8'),'sha256'),'hex')
  );
  perform set_config('app.fit_financial_v014_review_update', '', true);
end;
$$;

create or replace function public.retire_fit_financial_normalization_v014(
  p_financial_normalization_id uuid, p_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if nullif(btrim(p_reason), '') is null then raise exception using errcode='22023', message='Retirement reason is required'; end if;
  perform 1 from public.fit_financial_normalizations n
  join public.fit_evaluations e using (evaluation_id)
  where n.financial_normalization_id = p_financial_normalization_id
    and e.evaluation_state = 'BUILDING' for update of e, n;
  if not found then raise exception using errcode='55000', message='Only a BUILDING normalization may be retired'; end if;
  perform set_config('app.fit_financial_v014_review_update', 'on', true);
  update public.fit_financial_normalization_reviews_v014
  set status='RETIRED', retired_at=transaction_timestamp(), retirement_reason=p_reason,
      updated_at=transaction_timestamp()
  where financial_normalization_id=p_financial_normalization_id and status='VERIFIED';
  if not found then raise exception using errcode='55000', message='A VERIFIED normalization is required'; end if;
  perform set_config('app.fit_financial_v014_review_update', '', true);
end;
$$;

create or replace function public.validate_fit_financial_normalization()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_eval public.fit_evaluations%rowtype;
  v_method public.fit_financial_normalization_methods%rowtype;
  v_observation public.field_observations%rowtype;
  v_program_cost public.program_costs%rowtype;
  v_constraint public.fit_intent_financial_constraints%rowtype;
  v_pin private.fit_financial_source_pins_v014%rowtype;
  v_expected_scope public.fit_financial_scope;
  v_expected_components text[];
begin
  select * into v_eval from public.fit_evaluations
  where evaluation_id = new.evaluation_id for update;

  if v_eval.financial_contract_version = 'FINANCIAL_BILLING_BASIS_V014' then
    if v_eval.evaluation_state <> 'BUILDING'
       or v_eval.candidate_input_fingerprint is not null then
      raise exception using errcode='55000',
        message='v014 normalization insertion requires an unsealed BUILDING evaluation';
    end if;
    if not exists (
      select 1 from private.fit_evaluation_assembly_authorizations a
      where a.evaluation_id=v_eval.evaluation_id
        and a.execution_id=v_eval.execution_id
        and a.evaluator_build_id=v_eval.evaluator_build_id
        and a.evaluator_build_hash=v_eval.evaluator_build_hash
    ) then
      raise exception using errcode='42501',
        message='No durable assembly authorization exists for this evaluation execution';
    end if;
    if new.source_pin_id is null then
      raise exception using errcode='23514',
        message='v014 normalization requires an evaluation-scoped source pin';
    end if;
    select * into v_pin from private.fit_financial_source_pins_v014
    where evaluation_id=new.evaluation_id and source_pin_id=new.source_pin_id
    for update;
    if not found or v_pin.amount_observation_id<>new.field_observation_id then
      raise exception using errcode='23514',
        message='Normalization source pin must match its evaluation and amount observation';
    end if;
    select * into v_observation from public.field_observations
    where observation_id=v_pin.amount_observation_id for update;
    select * into v_program_cost from public.program_costs
    where cost_id=v_pin.cost_id for update;
    if v_observation.record_type<>'PROGRAM_COST'
       or v_observation.record_id<>v_program_cost.cost_id
       or v_observation.knowledge_status<>'KNOWN'
       or jsonb_typeof(v_observation.observed_value)<>'number'
       or v_program_cost.retired_at is not null
       or v_program_cost.program_version_id<>v_eval.program_version_id then
      raise exception using errcode='23514', message='Pinned v014 source is no longer admissible';
    end if;
    v_expected_scope := case v_observation.field_name
      when 'estimated_total_cost' then 'TOTAL_COST'::public.fit_financial_scope
      else 'COMPONENT'::public.fit_financial_scope end;
    v_expected_components := array[case v_observation.field_name
      when 'tuition_amount' then 'TUITION'
      when 'mandatory_fees' then 'MANDATORY_FEES'
      when 'estimated_living_cost' then 'LIVING_COST'
      when 'estimated_total_cost' then 'TOTAL_COST' end]::text[];
    if v_expected_components[1] is null
       or new.original_amount is distinct from (v_observation.observed_value #>> '{}')::numeric
       or new.original_currency is distinct from v_program_cost.currency
       or new.original_period is distinct from v_pin.source_mapped_period
       or new.original_scope is distinct from v_expected_scope
       or new.original_basis<>'GROSS'
       or new.original_components is distinct from v_expected_components then
      raise exception using errcode='23514',
        message='v014 normalization original tuple must be exactly derived from its pinned source';
    end if;
    select * into v_constraint from public.fit_intent_financial_constraints c
    where c.intent_declaration_id=new.financial_constraint_id
      and c.intent_set_id=v_eval.intent_set_id
      and c.profile_version_id=new.profile_version_id
    for update;
    if not found or v_constraint.constraint_semantics='AVAILABLE_FUNDING' then
      raise exception using errcode='23514',
        message='Normalization target must be a frozen cost ceiling or preference, never AVAILABLE_FUNDING';
    end if;
    if new.intent_set_id<>v_eval.intent_set_id
       or new.profile_version_id<>v_eval.profile_version_id
       or new.target_amount is distinct from v_constraint.amount
       or new.target_currency is distinct from v_constraint.currency
       or new.target_period is distinct from v_constraint.financial_period
       or new.target_scope is distinct from v_constraint.financial_scope
       or new.target_basis is distinct from v_constraint.financial_basis
       or (select array_agg(x order by x) from unnest(new.target_components) x)
          is distinct from
          (select array_agg(x order by x) from unnest(v_constraint.components) x) then
      raise exception using errcode='23514',
        message='v014 normalization target tuple must exactly match the frozen target declaration';
    end if;
    select * into v_method from public.fit_financial_normalization_methods
    where normalization_method_id=new.normalization_method_id for update;
    if v_method.status<>'VERIFIED' or v_method.retired_at is not null
       or v_method.contract_release_id<>v_eval.contract_release_id
       or v_method.source_scope<>new.original_scope
       or v_method.target_scope<>new.target_scope
       or v_method.source_period<>new.original_period
       or v_method.target_period<>new.target_period
       or v_method.source_basis<>new.original_basis
       or v_method.target_basis<>new.target_basis
       or (v_method.source_currency is not null and v_method.source_currency<>new.original_currency)
       or (v_method.target_currency is not null and v_method.target_currency<>new.target_currency) then
      raise exception using errcode='23514',
        message='v014 normalization must exactly satisfy an active VERIFIED release-matched method';
    end if;
    return new;
  end if;

  if v_eval.financial_contract_version is not null then
    raise exception using errcode='55000', message='Unknown Financial contract version';
  end if;
  if new.source_pin_id is not null then
    raise exception using errcode='23514', message='Legacy normalization cannot reference a v014 source pin';
  end if;
  select * into v_method from public.fit_financial_normalization_methods
  where normalization_method_id = new.normalization_method_id;
  if v_method.status is distinct from 'VERIFIED'
     or v_method.retired_at is not null
     or v_method.contract_release_id <> v_eval.contract_release_id
     or v_method.source_scope <> new.original_scope
     or v_method.target_scope <> new.target_scope
     or v_method.source_period <> new.original_period
     or v_method.target_period <> new.target_period
     or v_method.source_basis <> new.original_basis
     or v_method.target_basis <> new.target_basis
     or (v_method.source_currency is not null and v_method.source_currency <> new.original_currency)
     or (v_method.target_currency is not null and v_method.target_currency <> new.target_currency) then
    raise exception 'Financial normalization must exactly satisfy a VERIFIED method';
  end if;
  select * into v_observation from public.field_observations
  where observation_id = new.field_observation_id;
  if v_observation.knowledge_status <> 'KNOWN'
     or jsonb_typeof(v_observation.observed_value) is distinct from 'number'
     or (jsonb_typeof(v_observation.observed_value)='number'
       and (v_observation.observed_value #>> '{}')::numeric is distinct from new.original_amount)
     or not exists (select 1 from public.canonical_field_selections c where c.observation_id=v_observation.observation_id)
     or public.catalog_record_program_version(v_observation.record_type,v_observation.record_id)
        is distinct from v_eval.program_version_id then
    raise exception 'Financial normalization requires a selected KNOWN numeric program amount equal to original_amount';
  end if;
  if v_observation.record_type<>'PROGRAM_COST' or v_observation.field_name not in
    ('tuition_amount','mandatory_fees','estimated_living_cost','estimated_total_cost') then
    raise exception using errcode='23514', message='Financial normalization requires an approved Phase 1 program-cost amount field';
  end if;
  select * into v_program_cost from public.program_costs where cost_id=v_observation.record_id;
  if v_program_cost.currency is distinct from new.original_currency
     or new.original_period<>'ACADEMIC_YEAR' or new.original_basis<>'GROSS'
     or new.original_scope is distinct from (case v_observation.field_name
       when 'estimated_total_cost' then 'TOTAL_COST'::public.fit_financial_scope
       else 'COMPONENT'::public.fit_financial_scope end)
     or new.original_components<>array[case v_observation.field_name
       when 'tuition_amount' then 'TUITION' when 'mandatory_fees' then 'MANDATORY_FEES'
       when 'estimated_living_cost' then 'LIVING_COST' when 'estimated_total_cost' then 'TOTAL_COST' end]::text[] then
    raise exception using errcode='23514', message='Financial normalization original metadata must match the selected Phase 1 cost fact';
  end if;
  select * into v_constraint from public.fit_intent_financial_constraints c
  where c.intent_declaration_id=new.financial_constraint_id
    and c.intent_set_id=v_eval.intent_set_id and c.profile_version_id=new.profile_version_id;
  if not found then raise exception 'Financial normalization constraint is outside the frozen evaluation intent'; end if;
  if new.target_currency is distinct from v_constraint.currency
     or new.target_period is distinct from v_constraint.financial_period
     or new.target_scope is distinct from v_constraint.financial_scope
     or new.target_basis is distinct from v_constraint.financial_basis
     or (select array_agg(x order by x) from unnest(new.target_components) x)
       is distinct from (select array_agg(x order by x) from unnest(v_constraint.components) x) then
    raise exception using errcode='23514', message='Financial normalization target metadata must match the frozen student constraint';
  end if;
  return new;
end;
$$;

create or replace function private.fit_financial_source_payload_v014(
  p_source_pin_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $$
  select jsonb_build_object(
    'contract', 'FINANCIAL_BILLING_BASIS_V014',
    'profileVersionId', e.profile_version_id,
    'intentSetId', e.intent_set_id,
    'programVersionId', e.program_version_id,
    'contractReleaseId', e.contract_release_id,
    'amountObservationHash', p.amount_observation_payload_hash,
    'basisObservationHash', p.basis_observation_payload_hash,
    'amountSelectionHash', encode(extensions.digest(convert_to(to_jsonb(sa)::text,'UTF8'),'sha256'),'hex'),
    'basisSelectionHash', encode(extensions.digest(convert_to(to_jsonb(sb)::text,'UTF8'),'sha256'),'hex'),
    'amountApplicabilityHash', p.amount_applicability_payload_hash,
    'basisApplicabilityHash', p.basis_applicability_payload_hash,
    'amountEvidenceHash', p.amount_evidence_payload_hash,
    'basisEvidenceHash', p.basis_evidence_payload_hash,
    'costHash', p.cost_payload_hash,
    'sourceBillingBasis', p.source_billing_basis,
    'sourceAmount', (oa.observed_value #>> '{}')::numeric,
    'sourceCurrency', c.currency,
    'sourcePeriod', p.source_mapped_period,
    'sourceScope', case oa.field_name when 'estimated_total_cost'
      then 'TOTAL_COST'::public.fit_financial_scope
      else 'COMPONENT'::public.fit_financial_scope end,
    'sourceBasis', 'GROSS'::public.fit_financial_basis,
    'sourceComponents', to_jsonb(array[case oa.field_name
      when 'tuition_amount' then 'TUITION'
      when 'mandatory_fees' then 'MANDATORY_FEES'
      when 'estimated_living_cost' then 'LIVING_COST'
      when 'estimated_total_cost' then 'TOTAL_COST' end]::text[])
  )
  from private.fit_financial_source_pins_v014 p
  join public.fit_evaluations e on e.evaluation_id=p.evaluation_id
  join public.field_observations oa on oa.observation_id=p.amount_observation_id
  join public.program_costs c on c.cost_id=p.cost_id
  join public.canonical_field_selections sa
    on sa.record_type='PROGRAM_COST' and sa.record_id=p.cost_id
   and sa.field_name=oa.field_name and sa.observation_id=p.amount_observation_id
  join public.canonical_field_selections sb
    on sb.record_type='PROGRAM_COST' and sb.record_id=p.cost_id
   and sb.field_name='billing_basis'
   and sb.observation_id=p.billing_basis_observation_id
  where p.source_pin_id=p_source_pin_id;
$$;

create or replace function private.fit_financial_normalization_payload_v014(
  p_financial_normalization_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $$
  select jsonb_build_object(
    'contract', 'FINANCIAL_BILLING_BASIS_V014',
    'profileVersionId', e.profile_version_id,
    'intentSetId', e.intent_set_id,
    'programVersionId', e.program_version_id,
    'contractReleaseId', e.contract_release_id,
    'amountObservationHash', p.amount_observation_payload_hash,
    'basisObservationHash', p.basis_observation_payload_hash,
    'amountSelectionHash', encode(extensions.digest(convert_to(to_jsonb(sa)::text,'UTF8'),'sha256'),'hex'),
    'basisSelectionHash', encode(extensions.digest(convert_to(to_jsonb(sb)::text,'UTF8'),'sha256'),'hex'),
    'amountApplicabilityHash', p.amount_applicability_payload_hash,
    'basisApplicabilityHash', p.basis_applicability_payload_hash,
    'amountEvidenceHash', p.amount_evidence_payload_hash,
    'basisEvidenceHash', p.basis_evidence_payload_hash,
    'costHash', p.cost_payload_hash,
    'sourceBillingBasis', p.source_billing_basis,
    'sourceAmount', n.original_amount,
    'sourceCurrency', n.original_currency,
    'sourcePeriod', n.original_period,
    'sourceScope', n.original_scope,
    'sourceBasis', n.original_basis,
    'sourceComponents', (select jsonb_agg(x order by x) from unnest(n.original_components) x),
    'targetConstraintHash', vp.target_constraint_payload_hash,
    'targetAmount', n.target_amount,
    'targetCurrency', n.target_currency,
    'targetPeriod', n.target_period,
    'targetScope', n.target_scope,
    'targetBasis', n.target_basis,
    'targetComponents', (select jsonb_agg(x order by x) from unnest(n.target_components) x),
    'methodCode', m.method_code,
    'methodVersion', m.method_version,
    'methodContractHash', vp.method_payload_hash,
    'methodVerificationEvidenceHash', vp.method_evidence_payload_hash,
    'normalizationReviewEvidenceHash', vp.normalization_review_evidence_hash,
    'conversionInputsHash', vp.typed_input_payload_hash,
    'conversionFactorsHash', vp.typed_factor_payload_hash,
    'legacyConversionJsonHash', vp.legacy_json_hash
  )
  from public.fit_financial_normalizations n
  join public.fit_evaluations e on e.evaluation_id=n.evaluation_id
  join private.fit_financial_source_pins_v014 p
    on p.evaluation_id=n.evaluation_id and p.source_pin_id=n.source_pin_id
  join public.field_observations oa on oa.observation_id=p.amount_observation_id
  join public.canonical_field_selections sa
    on sa.record_type='PROGRAM_COST' and sa.record_id=p.cost_id
   and sa.field_name=oa.field_name and sa.observation_id=p.amount_observation_id
  join public.canonical_field_selections sb
    on sb.record_type='PROGRAM_COST' and sb.record_id=p.cost_id
   and sb.field_name='billing_basis'
   and sb.observation_id=p.billing_basis_observation_id
  join public.fit_financial_normalization_methods m
    on m.normalization_method_id=n.normalization_method_id
  join public.fit_financial_normalization_reviews_v014 r
    on r.financial_normalization_id=n.financial_normalization_id
   and r.evaluation_id=n.evaluation_id and r.status='VERIFIED'
  join private.fit_financial_normalization_verified_pins_v014 vp
    on vp.financial_normalization_id=n.financial_normalization_id
   and vp.evaluation_id=n.evaluation_id
  where n.financial_normalization_id=p_financial_normalization_id;
$$;

create or replace function private.fit_financial_payload_collections_v014(
  p_evaluation_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_all_sources bigint;
  v_referenced_sources bigint;
  v_all_normalizations bigint;
  v_referenced_normalizations bigint;
  v_duplicate_sources bigint;
  v_duplicate_normalizations bigint;
  v_sources jsonb;
  v_normalizations jsonb;
begin
  if not exists (
    select 1 from public.fit_evaluations e
    where e.evaluation_id=p_evaluation_id
      and e.financial_contract_version='FINANCIAL_BILLING_BASIS_V014'
  ) then
    raise exception using errcode='55000', message='Financial v014 payload requires a v014 evaluation';
  end if;

  select count(*) into v_all_sources
  from private.fit_financial_source_pins_v014 p
  where p.evaluation_id=p_evaluation_id;
  select count(distinct p.source_pin_id) into v_referenced_sources
  from private.fit_financial_source_pins_v014 p
  where p.evaluation_id=p_evaluation_id
    and exists (
      select 1 from public.fit_signals s
      where s.evaluation_id=p_evaluation_id and s.dimension='FINANCIAL'
        and exists (select 1 from public.fit_signal_evidence se where se.signal_id=s.signal_id and se.manifest_item_id=p.amount_manifest_item_id)
        and exists (select 1 from public.fit_signal_evidence se where se.signal_id=s.signal_id and se.manifest_item_id=p.basis_manifest_item_id)
    );
  if v_all_sources<>v_referenced_sources then
    raise exception using errcode='23514', message='Financial source pins must equal the exact same-signal referenced set';
  end if;

  select count(*) into v_all_normalizations
  from public.fit_financial_normalizations n where n.evaluation_id=p_evaluation_id;
  select count(distinct n.financial_normalization_id) into v_referenced_normalizations
  from public.fit_financial_normalizations n
  join public.fit_manifest_financial_normalizations mn
    on mn.evaluation_id=n.evaluation_id
   and mn.financial_normalization_id=n.financial_normalization_id
  where n.evaluation_id=p_evaluation_id
    and exists (
      select 1 from public.fit_signal_evidence se
      join public.fit_signals s using(signal_id,evaluation_id)
      where se.evaluation_id=p_evaluation_id and se.manifest_item_id=mn.manifest_item_id
        and s.dimension='FINANCIAL'
    );
  if v_all_normalizations<>v_referenced_normalizations then
    raise exception using errcode='23514', message='Financial normalizations must equal the exact signal-referenced set';
  end if;

  with payloads as (
    select private.fit_financial_source_payload_v014(p.source_pin_id) payload
    from private.fit_financial_source_pins_v014 p where p.evaluation_id=p_evaluation_id
  ), hashes as (
    select encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex') h
    from payloads
  ) select count(*)-count(distinct h) into v_duplicate_sources from hashes;
  if v_duplicate_sources<>0 then
    raise exception using errcode='23514', message='Duplicate Financial source semantic hashes are forbidden';
  end if;

  with payloads as (
    select private.fit_financial_normalization_payload_v014(n.financial_normalization_id) payload
    from public.fit_financial_normalizations n where n.evaluation_id=p_evaluation_id
  ), hashes as (
    select encode(extensions.digest(convert_to(payload::text,'UTF8'),'sha256'),'hex') h
    from payloads
  ) select count(*)-count(distinct h) into v_duplicate_normalizations from hashes;
  if v_duplicate_normalizations<>0 then
    raise exception using errcode='23514', message='Duplicate Financial normalization semantic hashes are forbidden';
  end if;

  select coalesce(jsonb_agg(x.payload order by x.semantic_hash),'[]'::jsonb) into v_sources
  from (
    select private.fit_financial_source_payload_v014(p.source_pin_id) payload,
      encode(extensions.digest(convert_to(private.fit_financial_source_payload_v014(p.source_pin_id)::text,'UTF8'),'sha256'),'hex') semantic_hash
    from private.fit_financial_source_pins_v014 p where p.evaluation_id=p_evaluation_id
  ) x;
  select coalesce(jsonb_agg(x.payload order by x.semantic_hash),'[]'::jsonb) into v_normalizations
  from (
    select private.fit_financial_normalization_payload_v014(n.financial_normalization_id) payload,
      encode(extensions.digest(convert_to(private.fit_financial_normalization_payload_v014(n.financial_normalization_id)::text,'UTF8'),'sha256'),'hex') semantic_hash
    from public.fit_financial_normalizations n where n.evaluation_id=p_evaluation_id
  ) x;
  return jsonb_build_object('financialSources',v_sources,'financialNormalizations',v_normalizations);
end;
$$;


create or replace function private.fit_decision_input_payload_v011(p_evaluation_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $$
  select jsonb_build_object(
          'profileVersionId', evaluation.profile_version_id,
          'profileSnapshotHash', evaluation.profile_snapshot_hash,
          'intentSetId', evaluation.intent_set_id,
          'intentSnapshotHash', evaluation.intent_snapshot_hash,
          'programVersionId', evaluation.program_version_id,
          'taxonomyRelease', evaluation.taxonomy_release_code,
          'contractReleaseId', evaluation.contract_release_id,
          'evaluatorBuildId', evaluation.evaluator_build_id,
          'evaluationMethods', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'dimension', method.dimension,
                'methodId', method.method_id
              )
              order by method.dimension
            )
            from public.fit_evaluation_methods method
            where method.evaluation_id = evaluation.evaluation_id
          ), '[]'::jsonb),
          'manifestItems', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'type', item.item_type,
                'authorityRole', item.authority_role,
                'sourceClass', item.source_class_code,
                'methodId', item.method_id,
                'policyId', item.input_policy_id,
                'sourceId', coalesce(
                  intent.intent_declaration_id,
                  access.access_context_id,
                  goal.student_goal_id,
                  preference.student_preference_id,
                  course.student_course_id,
                  completeness.completeness_id,
                  student_mapping.student_mapping_id,
                  observation.field_observation_id,
                  catalog_mapping.catalog_mapping_id,
                  concept.concept_id,
                  context_selection.context_selection_id,
                  context_mapping.context_mapping_id,
                  normalization.financial_normalization_id
                ),
                'contextObservationId',
                  context_selection.context_observation_id,
                'knowledgeStatus', context_selection.knowledge_status,
                'contextObservationWorkflowStatusAtSelection',
                  selection_history.observation_workflow_status_at_selection,
                'contextMappingStatusAtPin',
                  context_mapping.mapping_status_at_pin,
                'contextMappingReviewedAtPin',
                  context_mapping.mapping_reviewed_at_at_pin,
                'contextMappingEvidenceAtPin',
                  context_mapping.mapping_verification_evidence_id_at_pin,
                'fields', coalesce((
                  select jsonb_agg(field_use.field_name order by field_use.field_name)
                  from public.fit_manifest_student_field_uses field_use
                  where field_use.manifest_item_id = item.manifest_item_id
                ), '[]'::jsonb)
              )
              order by
                item.item_type, item.method_id, item.input_policy_id,
                item.authority_role, item.source_class_code,
                coalesce(
                  intent.intent_declaration_id,
                  access.access_context_id,
                  goal.student_goal_id,
                  preference.student_preference_id,
                  course.student_course_id,
                  completeness.completeness_id,
                  student_mapping.student_mapping_id,
                  observation.field_observation_id,
                  catalog_mapping.catalog_mapping_id,
                  concept.concept_id,
                  context_selection.context_selection_id,
                  context_mapping.context_mapping_id,
                  normalization.financial_normalization_id
                ) nulls first
            )
            from public.fit_manifest_items item
            left join public.fit_manifest_intent_declarations intent using(manifest_item_id)
            left join public.fit_manifest_student_access_contexts access using(manifest_item_id)
            left join public.fit_manifest_phase2_goals goal using(manifest_item_id)
            left join public.fit_manifest_phase2_preferences preference using(manifest_item_id)
            left join public.fit_manifest_phase2_courses course using(manifest_item_id)
            left join public.fit_manifest_phase2_completeness completeness using(manifest_item_id)
            left join public.fit_manifest_phase2_mappings student_mapping using(manifest_item_id)
            left join public.fit_manifest_catalog_observations observation using(manifest_item_id)
            left join public.fit_manifest_catalog_mappings catalog_mapping using(manifest_item_id)
            left join public.fit_manifest_taxonomy_concepts concept using(manifest_item_id)
            left join public.fit_manifest_context_claim_selections context_selection using(manifest_item_id)
            left join public.fit_context_claim_selection_history
              selection_history
              on selection_history.context_selection_id =
                context_selection.context_selection_id
             and selection_history.context_claim_id =
                context_selection.context_claim_id
            left join public.fit_manifest_context_mappings context_mapping using(manifest_item_id)
            left join public.fit_manifest_financial_normalizations normalization using(manifest_item_id)
            where item.evaluation_id = evaluation.evaluation_id
          ), '[]'::jsonb),
          'inputStates', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'methodId', state.method_id,
                'policyId', state.input_policy_id,
                'availability', state.availability,
                'completenessItemId', state.completeness_manifest_item_id,
                'provenanceItemId', state.provenance_manifest_item_id
              )
              order by state.method_id, state.input_policy_id
            )
            from public.fit_input_domain_states state
            where state.evaluation_id = evaluation.evaluation_id
          ), '[]'::jsonb),
          'normalizations', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', normalization.financial_normalization_id,
                'fieldObservationId', normalization.field_observation_id,
                'financialConstraintId',
                  normalization.financial_constraint_id,
                'intentSetId', normalization.intent_set_id,
                'methodId', normalization.normalization_method_id,
                'evidenceId', normalization.conversion_evidence_id,
                'originalAmount', normalization.original_amount,
                'originalCurrency', normalization.original_currency,
                'originalPeriod', normalization.original_period,
                'originalScope', normalization.original_scope,
                'originalBasis', normalization.original_basis,
                'originalComponents', (
                  select jsonb_agg(component order by component)
                  from unnest(normalization.original_components) component
                ),
                'targetAmount', normalization.target_amount,
                'targetCurrency', normalization.target_currency,
                'targetPeriod', normalization.target_period,
                'targetScope', normalization.target_scope,
                'targetBasis', normalization.target_basis,
                'targetComponents', (
                  select jsonb_agg(component order by component)
                  from unnest(normalization.target_components) component
                ),
                'conversionEvidence', normalization.conversion_evidence
              )
              order by normalization.financial_normalization_id
            )
            from public.fit_financial_normalizations normalization
            where normalization.evaluation_id = evaluation.evaluation_id
          ), '[]'::jsonb)
        )
  from public.fit_evaluations evaluation
  where evaluation.evaluation_id = p_evaluation_id;
$$;

create or replace function public.compute_fit_decision_input_fingerprint(p_evaluation_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_contract text;
  v_payload jsonb;
  v_financial jsonb;
begin
  select financial_contract_version into v_contract
  from public.fit_evaluations where evaluation_id=p_evaluation_id;
  if not found then return null; end if;
  v_payload := private.fit_decision_input_payload_v011(p_evaluation_id);
  if v_contract is null then
    return encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
  end if;
  if v_contract<>'FINANCIAL_BILLING_BASIS_V014' then
    raise exception using errcode='55000', message='Unknown Financial contract version';
  end if;
  v_financial := private.fit_financial_payload_collections_v014(p_evaluation_id);
  v_payload := jsonb_set(
    v_payload - 'normalizations',
    '{manifestItems}',
    coalesce((select jsonb_agg(item order by item::text)
      from jsonb_array_elements(v_payload->'manifestItems') item
      where item->>'type'<>'FIT_FINANCIAL_NORMALIZATION'),'[]'::jsonb)
  ) || jsonb_build_object(
    'financialContractVersion',v_contract,
    'financialSources',v_financial->'financialSources',
    'financialNormalizations',v_financial->'financialNormalizations'
  );
  return encode(extensions.digest(convert_to(v_payload::text,'UTF8'),'sha256'),'hex');
end;
$$;

create or replace function private.validate_fit_financial_live_pins_v014(
  p_evaluation_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  p private.fit_financial_source_pins_v014%rowtype;
  n public.fit_financial_normalizations%rowtype;
  vp private.fit_financial_normalization_verified_pins_v014%rowtype;
  v_eval public.fit_evaluations%rowtype;
  v_amount public.field_observations%rowtype;
  v_basis public.field_observations%rowtype;
  v_amount_selection public.canonical_field_selections%rowtype;
  v_basis_selection public.canonical_field_selections%rowtype;
  v_cost public.program_costs%rowtype;
  v_amount_evidence public.evidence_items%rowtype;
  v_basis_evidence public.evidence_items%rowtype;
  v_amount_link public.field_observation_applicability%rowtype;
  v_basis_link public.field_observation_applicability%rowtype;
  v_amount_assertion public.evidence_applicability_assertions%rowtype;
  v_basis_assertion public.evidence_applicability_assertions%rowtype;
  v_amount_head public.evidence_applicability_heads%rowtype;
  v_basis_head public.evidence_applicability_heads%rowtype;
  v_method public.fit_financial_normalization_methods%rowtype;
  v_review public.fit_financial_normalization_reviews_v014%rowtype;
  v_method_evidence public.evidence_items%rowtype;
  v_review_evidence public.evidence_items%rowtype;
  v_constraint public.fit_intent_financial_constraints%rowtype;
  v_live_amount numeric;
  v_live_basis public.billing_basis;
  v_normalization_count bigint;
  v_verified_pin_count bigint;
begin
  select * into v_eval
  from public.fit_evaluations e
  where e.evaluation_id=p_evaluation_id
    and e.evaluation_state='BUILDING'
    and e.financial_contract_version='FINANCIAL_BILLING_BASIS_V014'
  for update;
  if not found then
    raise exception using errcode='55000',
      message='Financial live-pin validation requires a BUILDING v014 evaluation';
  end if;

  -- Acquire every source and evaluation row in the global v014 lock order.
  perform 1 from public.fit_evaluation_methods em
  where em.evaluation_id=p_evaluation_id
  order by em.method_id for update;
  perform 1 from public.fit_intent_sets s
  where s.intent_set_id=v_eval.intent_set_id for update;
  perform 1 from public.fit_intent_declarations d
  where d.intent_set_id=v_eval.intent_set_id
  order by d.intent_declaration_id for update;
  perform 1 from public.fit_intent_financial_constraints c
  where c.intent_set_id=v_eval.intent_set_id
  order by c.intent_declaration_id for update;
  perform 1 from public.program_costs c
  where exists (
    select 1 from private.fit_financial_source_pins_v014 sp
    where sp.evaluation_id=p_evaluation_id and sp.cost_id=c.cost_id
  ) order by c.cost_id for update;
  perform 1 from public.canonical_field_selections s
  where s.record_type='PROGRAM_COST'
    and exists (
      select 1
      from private.fit_financial_source_pins_v014 sp
      join public.field_observations o
        on o.observation_id=sp.amount_observation_id
      where sp.evaluation_id=p_evaluation_id
        and sp.cost_id=s.record_id
        and s.field_name in (o.field_name,'billing_basis')
    )
  order by s.record_id,s.field_name for update;
  perform 1 from public.field_observations o
  where exists (
    select 1 from private.fit_financial_source_pins_v014 sp
    where sp.evaluation_id=p_evaluation_id
      and o.observation_id in (
        sp.amount_observation_id,sp.billing_basis_observation_id
      )
  ) order by o.observation_id for update;
  perform 1 from public.field_observation_applicability l
  where exists (
    select 1 from private.fit_financial_source_pins_v014 sp
    where sp.evaluation_id=p_evaluation_id
      and l.observation_id in (
        sp.amount_observation_id,sp.billing_basis_observation_id
      )
  ) order by l.observation_id for update;
  perform 1 from public.evidence_applicability_heads h
  where exists (
    select 1
    from public.evidence_applicability_assertions a
    join public.field_observation_applicability l
      on l.assertion_id=a.assertion_id
    join private.fit_financial_source_pins_v014 sp
      on l.observation_id in (
        sp.amount_observation_id,sp.billing_basis_observation_id
      )
    where sp.evaluation_id=p_evaluation_id and h.scope_id=a.scope_id
  ) order by h.scope_id for update;
  perform 1 from public.evidence_applicability_assertions a
  where exists (
    select 1
    from public.field_observation_applicability l
    join private.fit_financial_source_pins_v014 sp
      on l.observation_id in (
        sp.amount_observation_id,sp.billing_basis_observation_id
      )
    where sp.evaluation_id=p_evaluation_id
      and a.assertion_id=l.assertion_id
  ) order by a.assertion_id for update;
  perform 1 from public.evidence_items e
  where exists (
      select 1
      from public.field_observations o
      join private.fit_financial_source_pins_v014 sp
        on o.observation_id in (
          sp.amount_observation_id,sp.billing_basis_observation_id
        )
      where sp.evaluation_id=p_evaluation_id and o.evidence_id=e.evidence_id
    )
    or exists (
      select 1
      from public.fit_financial_normalizations fn
      join public.fit_financial_normalization_methods m
        using(normalization_method_id)
      where fn.evaluation_id=p_evaluation_id
        and m.verification_evidence_id=e.evidence_id
    )
    or exists (
      select 1
      from public.fit_financial_normalization_reviews_v014 r
      where r.evaluation_id=p_evaluation_id
        and r.verification_evidence_id=e.evidence_id
    )
    or exists (
      select 1
      from public.fit_financial_conversion_inputs_v014 i
      join public.fit_financial_normalizations fn
        using(financial_normalization_id)
      where fn.evaluation_id=p_evaluation_id and i.evidence_id=e.evidence_id
    )
    or exists (
      select 1
      from public.fit_financial_conversion_factors_v014 f
      join public.fit_financial_normalizations fn
        using(financial_normalization_id)
      where fn.evaluation_id=p_evaluation_id and f.evidence_id=e.evidence_id
    )
  order by e.evidence_id for update;
  perform 1 from public.fit_financial_normalization_methods m
  where exists (
    select 1 from public.fit_financial_normalizations fn
    where fn.evaluation_id=p_evaluation_id
      and fn.normalization_method_id=m.normalization_method_id
  ) order by m.normalization_method_id for update;
  perform 1 from public.fit_financial_normalizations fn
  where fn.evaluation_id=p_evaluation_id
  order by fn.financial_normalization_id for update;
  perform 1 from public.fit_financial_normalization_reviews_v014 r
  where r.evaluation_id=p_evaluation_id
  order by r.financial_normalization_id for update;
  perform 1 from public.fit_financial_conversion_inputs_v014 i
  where exists (
    select 1 from public.fit_financial_normalizations fn
    where fn.evaluation_id=p_evaluation_id
      and fn.financial_normalization_id=i.financial_normalization_id
  ) order by i.financial_normalization_id,i.input_ordinal for update;
  perform 1 from public.fit_financial_conversion_factors_v014 f
  where exists (
    select 1 from public.fit_financial_normalizations fn
    where fn.evaluation_id=p_evaluation_id
      and fn.financial_normalization_id=f.financial_normalization_id
  ) order by f.financial_normalization_id,f.factor_ordinal for update;
  perform 1 from public.fit_manifest_items mi
  where mi.evaluation_id=p_evaluation_id
  order by mi.manifest_item_id for update;
  perform 1 from public.fit_signal_evidence se
  where se.evaluation_id=p_evaluation_id
  order by se.signal_id,se.manifest_item_id for update;
  perform 1 from private.fit_financial_source_pins_v014 sp
  where sp.evaluation_id=p_evaluation_id
  order by sp.source_pin_id for update;
  perform 1 from private.fit_financial_normalization_verified_pins_v014 x
  where x.evaluation_id=p_evaluation_id
  order by x.financial_normalization_id for update;

  for p in
    select * from private.fit_financial_source_pins_v014 sp
    where sp.evaluation_id=p_evaluation_id
    order by sp.source_pin_id
  loop
    v_amount:=null; v_basis:=null; v_cost:=null;
    v_amount_selection:=null; v_basis_selection:=null;
    v_amount_link:=null; v_basis_link:=null;
    v_amount_assertion:=null; v_basis_assertion:=null;
    v_amount_head:=null; v_basis_head:=null;
    v_amount_evidence:=null; v_basis_evidence:=null;
    select * into v_amount from public.field_observations
      where observation_id=p.amount_observation_id;
    select * into v_basis from public.field_observations
      where observation_id=p.billing_basis_observation_id;
    select * into v_cost from public.program_costs where cost_id=p.cost_id;
    select * into v_amount_selection from public.canonical_field_selections
      where record_type='PROGRAM_COST' and record_id=p.cost_id
        and field_name=v_amount.field_name
        and observation_id=p.amount_observation_id;
    select * into v_basis_selection from public.canonical_field_selections
      where record_type='PROGRAM_COST' and record_id=p.cost_id
        and field_name='billing_basis'
        and observation_id=p.billing_basis_observation_id;
    select * into v_amount_link from public.field_observation_applicability
      where observation_id=p.amount_observation_id;
    select * into v_basis_link from public.field_observation_applicability
      where observation_id=p.billing_basis_observation_id;
    select * into v_amount_assertion
      from public.evidence_applicability_assertions
      where assertion_id=v_amount_link.assertion_id;
    select * into v_basis_assertion
      from public.evidence_applicability_assertions
      where assertion_id=v_basis_link.assertion_id;
    select * into v_amount_head from public.evidence_applicability_heads
      where scope_id=v_amount_assertion.scope_id;
    select * into v_basis_head from public.evidence_applicability_heads
      where scope_id=v_basis_assertion.scope_id;
    select * into v_amount_evidence from public.evidence_items
      where evidence_id=v_amount.evidence_id;
    select * into v_basis_evidence from public.evidence_items
      where evidence_id=v_basis.evidence_id;

    if v_amount.observation_id is null or v_basis.observation_id is null
       or v_cost.cost_id is null
       or v_amount_selection.observation_id is null
       or v_basis_selection.observation_id is null
       or v_amount_selection.selected_at is distinct from
          p.amount_selection_selected_at
       or v_basis_selection.selected_at is distinct from
          p.basis_selection_selected_at
       or v_amount_assertion.applicability_status is distinct from
          'REVIEWED_APPLICABLE'
       or v_basis_assertion.applicability_status is distinct from
          'REVIEWED_APPLICABLE'
       or v_amount_head.assertion_id is distinct from
          v_amount_assertion.assertion_id
       or v_basis_head.assertion_id is distinct from
          v_basis_assertion.assertion_id
       or encode(extensions.digest(convert_to(to_jsonb(v_amount)::text,'UTF8'),'sha256'),'hex')
          is distinct from p.amount_observation_payload_hash
       or encode(extensions.digest(convert_to(to_jsonb(v_basis)::text,'UTF8'),'sha256'),'hex')
          is distinct from p.basis_observation_payload_hash
       or encode(extensions.digest(convert_to(to_jsonb(v_amount_evidence)::text,'UTF8'),'sha256'),'hex')
          is distinct from p.amount_evidence_payload_hash
       or encode(extensions.digest(convert_to(to_jsonb(v_basis_evidence)::text,'UTF8'),'sha256'),'hex')
          is distinct from p.basis_evidence_payload_hash
       or encode(extensions.digest(convert_to(jsonb_build_object(
            'link',to_jsonb(v_amount_link),'head',to_jsonb(v_amount_head),
            'assertion',to_jsonb(v_amount_assertion))::text,'UTF8'),'sha256'),'hex')
          is distinct from p.amount_applicability_payload_hash
       or encode(extensions.digest(convert_to(jsonb_build_object(
            'link',to_jsonb(v_basis_link),'head',to_jsonb(v_basis_head),
            'assertion',to_jsonb(v_basis_assertion))::text,'UTF8'),'sha256'),'hex')
          is distinct from p.basis_applicability_payload_hash
       or encode(extensions.digest(convert_to(to_jsonb(v_cost)::text,'UTF8'),'sha256'),'hex')
          is distinct from p.cost_payload_hash then
      raise exception using errcode='23514',
        message='Financial source authority no longer matches its persisted v014 live pins';
    end if;

    v_live_amount:=case v_amount.field_name
      when 'tuition_amount' then v_cost.tuition_amount
      when 'mandatory_fees' then v_cost.mandatory_fees
      when 'estimated_living_cost' then v_cost.estimated_living_cost
      when 'estimated_total_cost' then v_cost.estimated_total_cost end;
    v_live_basis:=(v_basis.observed_value #>> '{}')::public.billing_basis;
    if v_amount.record_type<>'PROGRAM_COST'
       or v_basis.record_type<>'PROGRAM_COST'
       or v_amount.record_id<>p.cost_id or v_basis.record_id<>p.cost_id
       or v_amount.knowledge_status<>'KNOWN'
       or v_basis.knowledge_status<>'KNOWN'
       or (v_amount.observed_value #>> '{}')::numeric
          is distinct from v_live_amount
       or v_live_basis is distinct from v_cost.billing_basis
       or v_live_basis is distinct from p.source_billing_basis
       or public.fit_financial_period_for_billing_basis(v_live_basis)
          is distinct from p.source_mapped_period
       or v_cost.retired_at is not null
       or v_cost.program_version_id<>v_eval.program_version_id
       or not exists (
         select 1 from public.fit_manifest_catalog_observations mo
         where mo.manifest_item_id=p.amount_manifest_item_id
           and mo.evaluation_id=p_evaluation_id
           and mo.field_observation_id=p.amount_observation_id
       )
       or not exists (
         select 1 from public.fit_manifest_catalog_observations mo
         where mo.manifest_item_id=p.basis_manifest_item_id
           and mo.evaluation_id=p_evaluation_id
           and mo.field_observation_id=p.billing_basis_observation_id
       ) then
      raise exception using errcode='23514',
        message='Financial source tuple is no longer admissible under its v014 live pins';
    end if;
  end loop;

  select count(*) into v_normalization_count
  from public.fit_financial_normalizations fn
  where fn.evaluation_id=p_evaluation_id;
  select count(*) into v_verified_pin_count
  from private.fit_financial_normalization_verified_pins_v014 x
  where x.evaluation_id=p_evaluation_id;
  if v_normalization_count<>v_verified_pin_count then
    raise exception using errcode='23514',
      message='Every v014 normalization requires exactly one persisted verified pin';
  end if;

  for n in
    select * from public.fit_financial_normalizations fn
    where fn.evaluation_id=p_evaluation_id
    order by fn.financial_normalization_id
  loop
    v_method:=null; v_review:=null; vp:=null;
    v_method_evidence:=null; v_review_evidence:=null; v_constraint:=null;
    select * into vp
    from private.fit_financial_normalization_verified_pins_v014 x
    where x.evaluation_id=p_evaluation_id
      and x.financial_normalization_id=n.financial_normalization_id;
    select * into v_method
    from public.fit_financial_normalization_methods m
    where m.normalization_method_id=n.normalization_method_id;
    select * into v_review
    from public.fit_financial_normalization_reviews_v014 r
    where r.evaluation_id=p_evaluation_id
      and r.financial_normalization_id=n.financial_normalization_id;
    select * into v_method_evidence from public.evidence_items e
      where e.evidence_id=v_method.verification_evidence_id;
    select * into v_review_evidence from public.evidence_items e
      where e.evidence_id=v_review.verification_evidence_id;
    select * into v_constraint
    from public.fit_intent_financial_constraints c
    where c.intent_declaration_id=n.financial_constraint_id;

    if vp.financial_normalization_id is null
       or v_method.status is distinct from 'VERIFIED'
       or v_method.retired_at is not null
       or v_review.status is distinct from 'VERIFIED'
       or v_review.reviewed_at is distinct from vp.verified_at
       or v_review.updated_at is distinct from vp.verified_at
       or encode(extensions.digest(convert_to(to_jsonb(v_method)::text,'UTF8'),'sha256'),'hex')
          is distinct from vp.method_payload_hash
       or encode(extensions.digest(convert_to(to_jsonb(v_method_evidence)::text,'UTF8'),'sha256'),'hex')
          is distinct from vp.method_evidence_payload_hash
       or encode(extensions.digest(convert_to(to_jsonb(v_review_evidence)::text,'UTF8'),'sha256'),'hex')
          is distinct from vp.normalization_review_evidence_hash
       or private.fit_financial_typed_input_payload_hash_v014(
            n.financial_normalization_id
          ) is distinct from vp.typed_input_payload_hash
       or private.fit_financial_typed_factor_payload_hash_v014(
            n.financial_normalization_id
          ) is distinct from vp.typed_factor_payload_hash
       or encode(extensions.digest(convert_to(n.conversion_evidence::text,'UTF8'),'sha256'),'hex')
          is distinct from vp.legacy_json_hash
       or encode(extensions.digest(convert_to(to_jsonb(v_constraint)::text,'UTF8'),'sha256'),'hex')
          is distinct from vp.target_constraint_payload_hash then
      raise exception using errcode='23514',
        message='Financial normalization no longer matches its persisted v014 verified pins';
    end if;
  end loop;
end;
$$;

create or replace function private.validate_fit_financial_finalization_v014(
  p_evaluation_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  s record;
  n record;
  v_direct integer;
  v_normalized integer;
  v_collections jsonb;
begin
  perform 1 from public.fit_evaluations e
  where e.evaluation_id=p_evaluation_id
    and e.financial_contract_version='FINANCIAL_BILLING_BASIS_V014'
    and e.evaluation_state='BUILDING' for update;
  if not found then raise exception using errcode='55000', message='Financial v014 finalization requires a BUILDING v014 evaluation'; end if;

  perform private.validate_fit_financial_live_pins_v014(p_evaluation_id);
  v_collections := private.fit_financial_payload_collections_v014(p_evaluation_id);
  for n in
    select fn.*, r.status review_status, m.status method_status, m.retired_at method_retired_at,
      vp.*, c.constraint_semantics
    from public.fit_financial_normalizations fn
    join public.fit_financial_normalization_reviews_v014 r using(financial_normalization_id,evaluation_id)
    join public.fit_financial_normalization_methods m using(normalization_method_id)
    join private.fit_financial_normalization_verified_pins_v014 vp using(financial_normalization_id,evaluation_id)
    join public.fit_intent_financial_constraints c on c.intent_declaration_id=fn.financial_constraint_id
    where fn.evaluation_id=p_evaluation_id
    order by fn.financial_normalization_id
  loop
    if n.review_status<>'VERIFIED' or n.method_status<>'VERIFIED' or n.method_retired_at is not null
       or n.constraint_semantics='AVAILABLE_FUNDING'
       or private.fit_financial_normalization_payload_v014(n.financial_normalization_id) is null then
      raise exception using errcode='23514', message='Every referenced v014 normalization must remain active VERIFIED and fully serializable';
    end if;
  end loop;

  for s in
    select sig.signal_id, sig.intent_declaration_id
    from public.fit_signals sig
    join public.fit_dimension_results r using(dimension_result_id,evaluation_id)
    where sig.evaluation_id=p_evaluation_id and sig.dimension='FINANCIAL'
      and sig.material and sig.direction in ('SUPPORTING','CONTRADICTING')
      and sig.inference_category='DETERMINISTIC' and r.assessment<>'UNKNOWN'
    order by sig.signal_id
  loop
    select count(*) into v_direct
    from private.fit_financial_source_pins_v014 p
    join public.field_observations o on o.observation_id=p.amount_observation_id
    join public.program_costs pc on pc.cost_id=p.cost_id
    join public.fit_intent_financial_constraints c on c.intent_declaration_id=s.intent_declaration_id
    where p.evaluation_id=p_evaluation_id and c.constraint_semantics<>'AVAILABLE_FUNDING'
      and exists(select 1 from public.fit_signal_evidence se where se.signal_id=s.signal_id and se.manifest_item_id=p.amount_manifest_item_id)
      and exists(select 1 from public.fit_signal_evidence se where se.signal_id=s.signal_id and se.manifest_item_id=p.basis_manifest_item_id)
      and exists(select 1 from public.fit_signal_evidence se join public.fit_manifest_intent_declarations mi using(manifest_item_id)
        where se.signal_id=s.signal_id and mi.intent_declaration_id=c.intent_declaration_id)
      and not exists(select 1 from public.fit_signal_evidence se join public.fit_manifest_financial_normalizations mn using(manifest_item_id)
        where se.signal_id=s.signal_id)
      and not exists(
        select 1 from public.fit_signal_evidence se
        join public.fit_manifest_intent_declarations mi using(manifest_item_id)
        join public.fit_intent_financial_constraints fc
          on fc.intent_declaration_id=mi.intent_declaration_id
        where se.signal_id=s.signal_id
          and fc.constraint_semantics='AVAILABLE_FUNDING'
      )
      and public.fit_financial_facts_directly_comparable(
        pc.currency,p.source_mapped_period,
        case o.field_name when 'estimated_total_cost' then 'TOTAL_COST'::public.fit_financial_scope else 'COMPONENT'::public.fit_financial_scope end,
        'GROSS',array[case o.field_name when 'tuition_amount' then 'TUITION' when 'mandatory_fees' then 'MANDATORY_FEES'
          when 'estimated_living_cost' then 'LIVING_COST' when 'estimated_total_cost' then 'TOTAL_COST' end]::text[],
        c.currency,c.financial_period,c.financial_scope,c.financial_basis,c.components);

    select count(*) into v_normalized
    from public.fit_financial_normalizations fn
    join private.fit_financial_source_pins_v014 p on p.source_pin_id=fn.source_pin_id and p.evaluation_id=fn.evaluation_id
    join public.field_observations o on o.observation_id=p.amount_observation_id
    join public.program_costs pc on pc.cost_id=p.cost_id
    join public.fit_financial_normalization_reviews_v014 r
      on r.financial_normalization_id=fn.financial_normalization_id
     and r.evaluation_id=fn.evaluation_id
    join public.fit_manifest_financial_normalizations mn
      on mn.financial_normalization_id=fn.financial_normalization_id
     and mn.evaluation_id=fn.evaluation_id
    where fn.evaluation_id=p_evaluation_id and fn.financial_constraint_id=s.intent_declaration_id and r.status='VERIFIED'
      and exists(select 1 from public.fit_signal_evidence se where se.signal_id=s.signal_id and se.manifest_item_id=mn.manifest_item_id)
      and exists(select 1 from public.fit_signal_evidence se where se.signal_id=s.signal_id and se.manifest_item_id=p.amount_manifest_item_id)
      and exists(select 1 from public.fit_signal_evidence se where se.signal_id=s.signal_id and se.manifest_item_id=p.basis_manifest_item_id)
      and (
        (fn.target_basis<>'NET_OF_VERIFIED_FUNDING' and not exists(
          select 1 from public.fit_signal_evidence se
          join public.fit_manifest_intent_declarations mi using(manifest_item_id)
          join public.fit_intent_financial_constraints fc
            on fc.intent_declaration_id=mi.intent_declaration_id
          where se.signal_id=s.signal_id
            and fc.constraint_semantics='AVAILABLE_FUNDING'
        ))
        or
        (fn.target_basis='NET_OF_VERIFIED_FUNDING' and 1=(
          select count(*) from public.fit_signal_evidence se
          join public.fit_manifest_intent_declarations mi using(manifest_item_id)
          join public.fit_intent_financial_constraints fc
            on fc.intent_declaration_id=mi.intent_declaration_id
          join public.fit_financial_conversion_inputs_v014 fi
            on fi.financial_normalization_id=fn.financial_normalization_id
           and fi.input_role='AVAILABLE_FUNDING'
           and fi.intent_declaration_id=fc.intent_declaration_id
          where se.signal_id=s.signal_id
            and fc.constraint_semantics='AVAILABLE_FUNDING'
        ) and 1=(
          select count(*) from public.fit_signal_evidence se
          join public.fit_manifest_intent_declarations mi using(manifest_item_id)
          join public.fit_intent_financial_constraints fc
            on fc.intent_declaration_id=mi.intent_declaration_id
          where se.signal_id=s.signal_id
            and fc.constraint_semantics='AVAILABLE_FUNDING'
        ))
      )
      and not public.fit_financial_facts_directly_comparable(
        pc.currency,p.source_mapped_period,
        case o.field_name when 'estimated_total_cost' then 'TOTAL_COST'::public.fit_financial_scope else 'COMPONENT'::public.fit_financial_scope end,
        'GROSS',array[case o.field_name when 'tuition_amount' then 'TUITION' when 'mandatory_fees' then 'MANDATORY_FEES'
          when 'estimated_living_cost' then 'LIVING_COST' when 'estimated_total_cost' then 'TOTAL_COST' end]::text[],
        fn.target_currency,fn.target_period,fn.target_scope,fn.target_basis,fn.target_components);
    if v_direct+v_normalized<>1 then
      raise exception using errcode='23514', message='Each directional deterministic Financial signal requires exactly one direct or normalized witness';
    end if;
  end loop;
end;
$$;


create or replace function public.finalize_fit_evaluation(p_evaluation_id uuid)
returns text
language plpgsql
security definer
set search_path = public, private, extensions, pg_temp
as $$
declare
  v_eval public.fit_evaluations%rowtype;
  v_invalid integer;
  v_fingerprint text;
  v_result_fingerprint text;
  v_prior text;
begin
  select * into v_eval from public.fit_evaluations
  where evaluation_id = p_evaluation_id for update;
  if not found or v_eval.evaluation_state <> 'BUILDING' then
    raise exception 'A BUILDING Fit evaluation is required';
  end if;
  if v_eval.candidate_input_fingerprint is null then
    raise exception 'Fit decision inputs must be sealed before finalization';
  end if;

  if not exists (
    select 1 from public.student_profile_versions p
    where p.profile_version_id = v_eval.profile_version_id
      and p.status = 'FROZEN'
      and p.snapshot_hash = v_eval.profile_snapshot_hash
  ) or not exists (
    select 1 from public.fit_intent_sets s
    where s.intent_set_id = v_eval.intent_set_id
      and s.profile_version_id = v_eval.profile_version_id
      and s.status = 'FROZEN'
      and s.snapshot_hash = v_eval.intent_snapshot_hash
  ) then
    raise exception 'Frozen evaluation sources no longer match their pins';
  end if;

  select count(*) into v_invalid
  from public.fit_dimension_results r
  where r.evaluation_id = p_evaluation_id;
  if v_invalid <> 6 or exists (
    select d.dimension
    from unnest(enum_range(null::public.fit_dimension)) d(dimension)
    except
    select r.dimension from public.fit_dimension_results r
    where r.evaluation_id = p_evaluation_id
  ) then
    raise exception 'Exactly one result for each of the six Fit dimensions is required';
  end if;

  -- Every item has exactly one subtype, matching its declared type.
  select count(*) into v_invalid
  from public.fit_manifest_items i
  cross join lateral (
    select
      (select count(*) from public.fit_manifest_intent_declarations x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_student_access_contexts x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_phase2_goals x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_phase2_preferences x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_phase2_courses x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_phase2_completeness x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_phase2_mappings x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_catalog_observations x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_catalog_mappings x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_taxonomy_concepts x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_context_claim_selections x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_context_mappings x where x.manifest_item_id=i.manifest_item_id)
      +(select count(*) from public.fit_manifest_financial_normalizations x where x.manifest_item_id=i.manifest_item_id)
      as child_count,
      case i.item_type
        when 'FIT_INTENT_DECLARATION' then exists(select 1 from public.fit_manifest_intent_declarations x where x.manifest_item_id=i.manifest_item_id)
        when 'FIT_STUDENT_ACCESS_CONTEXT' then exists(select 1 from public.fit_manifest_student_access_contexts x where x.manifest_item_id=i.manifest_item_id)
        when 'PHASE2_STUDENT_GOAL' then exists(select 1 from public.fit_manifest_phase2_goals x where x.manifest_item_id=i.manifest_item_id)
        when 'PHASE2_STUDENT_PREFERENCE' then exists(select 1 from public.fit_manifest_phase2_preferences x where x.manifest_item_id=i.manifest_item_id)
        when 'PHASE2_STUDENT_COURSE' then exists(select 1 from public.fit_manifest_phase2_courses x where x.manifest_item_id=i.manifest_item_id)
        when 'PHASE2_STUDENT_COMPLETENESS' then exists(select 1 from public.fit_manifest_phase2_completeness x where x.manifest_item_id=i.manifest_item_id)
        when 'PHASE2_STUDENT_MAPPING' then exists(select 1 from public.fit_manifest_phase2_mappings x where x.manifest_item_id=i.manifest_item_id)
        when 'CATALOG_FIELD_OBSERVATION' then exists(select 1 from public.fit_manifest_catalog_observations x where x.manifest_item_id=i.manifest_item_id)
        when 'CATALOG_MAPPING' then exists(select 1 from public.fit_manifest_catalog_mappings x where x.manifest_item_id=i.manifest_item_id)
        when 'TAXONOMY_CONCEPT' then exists(select 1 from public.fit_manifest_taxonomy_concepts x where x.manifest_item_id=i.manifest_item_id)
        when 'FIT_CONTEXT_CLAIM_SELECTION' then exists(select 1 from public.fit_manifest_context_claim_selections x where x.manifest_item_id=i.manifest_item_id)
        when 'FIT_CONTEXT_MAPPING' then exists(select 1 from public.fit_manifest_context_mappings x where x.manifest_item_id=i.manifest_item_id)
        when 'FIT_FINANCIAL_NORMALIZATION' then exists(select 1 from public.fit_manifest_financial_normalizations x where x.manifest_item_id=i.manifest_item_id)
      end as type_matches
  ) typed
  where i.evaluation_id = p_evaluation_id
    and (typed.child_count <> 1 or not typed.type_matches);
  if v_invalid > 0 then
    raise exception 'Every manifest item requires exactly one matching typed subtype';
  end if;
  if exists (
    select 1
    from (
      select
        item.method_id,
        item.item_type,
        coalesce(
          intent.intent_declaration_id,
          access.access_context_id,
          goal.student_goal_id,
          preference.student_preference_id,
          course.student_course_id,
          completeness.completeness_id,
          student_mapping.student_mapping_id,
          observation.field_observation_id,
          catalog_mapping.catalog_mapping_id,
          concept.concept_id,
          context_selection.context_selection_id,
          context_mapping.context_mapping_id,
          normalization.financial_normalization_id
        ) source_id
      from public.fit_manifest_items item
      left join public.fit_manifest_intent_declarations intent using(manifest_item_id)
      left join public.fit_manifest_student_access_contexts access using(manifest_item_id)
      left join public.fit_manifest_phase2_goals goal using(manifest_item_id)
      left join public.fit_manifest_phase2_preferences preference using(manifest_item_id)
      left join public.fit_manifest_phase2_courses course using(manifest_item_id)
      left join public.fit_manifest_phase2_completeness completeness using(manifest_item_id)
      left join public.fit_manifest_phase2_mappings student_mapping using(manifest_item_id)
      left join public.fit_manifest_catalog_observations observation using(manifest_item_id)
      left join public.fit_manifest_catalog_mappings catalog_mapping using(manifest_item_id)
      left join public.fit_manifest_taxonomy_concepts concept using(manifest_item_id)
      left join public.fit_manifest_context_claim_selections context_selection using(manifest_item_id)
      left join public.fit_manifest_context_mappings context_mapping using(manifest_item_id)
      left join public.fit_manifest_financial_normalizations normalization using(manifest_item_id)
      where item.evaluation_id = p_evaluation_id
    ) source
    group by method_id, item_type, source_id
    having count(*) > 1
  ) then
    raise exception using errcode='23505',
      message='A source may appear at most once per evaluation method and manifest type';
  end if;

  -- Method/policy ownership and student-field hard allowlists.
  if exists (
    select 1
    from public.fit_manifest_items i
    join public.fit_dimension_methods m on m.method_id=i.method_id
    join public.fit_method_input_policies p on p.input_policy_id=i.input_policy_id
    where i.evaluation_id=p_evaluation_id
      and (m.contract_release_id <> v_eval.contract_release_id
        or m.status <> 'VERIFIED' or m.retired_at is not null
        or p.method_id <> i.method_id or p.disposition <> 'ALLOWED')
  ) or exists (
    select 1
    from public.fit_input_domain_states s
    join public.fit_dimension_methods m on m.method_id=s.method_id
    join public.fit_method_input_policies p on p.input_policy_id=s.input_policy_id
    where s.evaluation_id=p_evaluation_id
      and (m.contract_release_id <> v_eval.contract_release_id
        or m.status <> 'VERIFIED' or m.retired_at is not null
        or p.method_id <> s.method_id or p.disposition <> 'ALLOWED')
  ) then
    raise exception 'Manifest items and input states require an ALLOWED policy of a VERIFIED evaluation method';
  end if;
  if exists (
    select 1
    from public.fit_manifest_items item
    join public.fit_semantic_source_classes source_class
      using (source_class_code)
    left join public.fit_method_source_class_policies source_policy
      on source_policy.method_id = item.method_id
     and source_policy.source_class_code = item.source_class_code
    where item.evaluation_id = p_evaluation_id
      and (
        not source_class.fit_permitted
        or source_policy.disposition is distinct from 'ALLOWED'
      )
  ) then
    raise exception 'Manifest semantic source class is prohibited or unauthorized for its dimension method';
  end if;
  if exists (
    select 1
    from public.fit_manifest_items item
    left join public.fit_manifest_context_claim_selections selection
      using(manifest_item_id)
    left join public.fit_context_claims claim
      on claim.context_claim_id = selection.context_claim_id
    left join public.fit_manifest_context_mappings context_mapping
      using(manifest_item_id)
    left join public.fit_context_concept_mappings mapping
      on mapping.context_mapping_id = context_mapping.context_mapping_id
    left join public.fit_context_claims mapped_claim
      on mapped_claim.context_claim_id = mapping.context_claim_id
    left join public.fit_context_claim_definitions definition
      on definition.claim_definition_id =
        coalesce(claim.claim_definition_id, mapped_claim.claim_definition_id)
     and definition.definition_version =
        coalesce(claim.definition_version, mapped_claim.definition_version)
    where item.evaluation_id = p_evaluation_id
      and item.source_class_code is distinct from case item.item_type
        when 'FIT_INTENT_DECLARATION' then 'STUDENT_RAW_INTENT'
        when 'FIT_STUDENT_ACCESS_CONTEXT' then 'STUDENT_RAW_ACCESS_CONTEXT'
        when 'PHASE2_STUDENT_GOAL' then 'STUDENT_RAW_INTENT'
        when 'PHASE2_STUDENT_PREFERENCE' then 'STUDENT_RAW_INTENT'
        when 'PHASE2_STUDENT_COURSE' then 'STUDENT_RAW_ACADEMIC_HISTORY'
        when 'PHASE2_STUDENT_MAPPING' then 'TAXONOMY_MAPPING'
        when 'CATALOG_FIELD_OBSERVATION' then 'PROGRAM_CANONICAL_FACT'
        when 'CATALOG_MAPPING' then 'TAXONOMY_MAPPING'
        when 'TAXONOMY_CONCEPT' then 'TAXONOMY_MAPPING'
        when 'FIT_CONTEXT_CLAIM_SELECTION'
          then definition.semantic_source_class_code
        when 'FIT_CONTEXT_MAPPING'
          then definition.semantic_source_class_code
        when 'FIT_FINANCIAL_NORMALIZATION' then 'FIT_CONTEXT_FINANCIAL'
        when 'PHASE2_STUDENT_COMPLETENESS' then item.source_class_code
      end
  ) then
    raise exception 'Manifest wrapper semantic source class does not match its authoritative underlying source';
  end if;
  if exists (
    select 1
    from public.fit_manifest_items i
    join public.fit_method_input_policies p
      on p.input_policy_id=i.input_policy_id
    left join public.fit_manifest_catalog_observations mo
      using(manifest_item_id)
    left join public.field_observations o
      on o.observation_id=mo.field_observation_id
    where i.evaluation_id=p_evaluation_id
      and p.input_domain is distinct from case i.item_type
        when 'FIT_INTENT_DECLARATION' then 'FIT_INTENTS'
        when 'FIT_STUDENT_ACCESS_CONTEXT' then 'FIT_ACCESS_CONTEXT'
        when 'PHASE2_STUDENT_GOAL' then 'STUDENT_GOALS'
        when 'PHASE2_STUDENT_PREFERENCE' then 'STUDENT_PREFERENCES'
        when 'PHASE2_STUDENT_COURSE' then 'STUDENT_COURSES'
        when 'PHASE2_STUDENT_COMPLETENESS' then 'STUDENT_COMPLETENESS'
        when 'PHASE2_STUDENT_MAPPING' then 'STUDENT_MAPPINGS'
        when 'CATALOG_FIELD_OBSERVATION' then case o.record_type
          when 'PROGRAM_COURSE' then 'PROGRAM_COURSES'
          when 'PROGRAM_COST' then 'PROGRAM_COSTS'
          when 'PROGRAM' then 'PROGRAM_VERSIONS'
          when 'PROGRAM_VERSION' then 'PROGRAM_VERSIONS'
          else null
        end
        when 'CATALOG_MAPPING' then 'CATALOG_MAPPINGS'
        when 'TAXONOMY_CONCEPT' then 'TAXONOMY_CONCEPTS'
        when 'FIT_CONTEXT_CLAIM_SELECTION' then 'FIT_CONTEXT_CLAIMS'
        when 'FIT_CONTEXT_MAPPING' then 'FIT_CONTEXT_CLAIMS'
        when 'FIT_FINANCIAL_NORMALIZATION' then 'FINANCIAL_NORMALIZATIONS'
      end
  ) then
    raise exception 'Manifest item type/source is incompatible with its input-policy domain';
  end if;
  if exists (
    select 1
    from public.fit_dimension_results r
    join public.fit_method_input_policies p on p.method_id=r.method_id
    where r.evaluation_id=p_evaluation_id
      and p.disposition='ALLOWED'
      and not exists (
        select 1 from public.fit_input_domain_states s
        where s.evaluation_id=r.evaluation_id
          and s.method_id=r.method_id
          and s.input_policy_id=p.input_policy_id
      )
  ) or exists (
    select 1
    from public.fit_input_domain_states s
    where s.evaluation_id=p_evaluation_id
      and (
        (s.availability='INCLUDED') is distinct from exists (
          select 1 from public.fit_manifest_items i
          where i.evaluation_id=s.evaluation_id
            and i.method_id=s.method_id
            and i.input_policy_id=s.input_policy_id
        )
      )
  ) then
    raise exception 'Every ALLOWED method requirement needs an exact availability state consistent with its supplied items';
  end if;
  if exists (
    select 1
    from public.fit_dimension_results r
    join public.fit_method_input_policies p
      on p.method_id=r.method_id
     and p.disposition='ALLOWED'
     and p.requirement='REQUIRED'
    join public.fit_input_domain_states s
      on s.evaluation_id=r.evaluation_id
     and s.method_id=r.method_id
     and s.input_policy_id=p.input_policy_id
    where r.evaluation_id=p_evaluation_id
      and s.availability<>'INCLUDED'
      and r.assessment<>'UNKNOWN'
  ) then
    raise exception 'A non-INCLUDED REQUIRED method input forces UNKNOWN';
  end if;
  if exists (
    select 1 from public.fit_manifest_items i
    left join public.fit_manifest_student_field_uses f
      on f.manifest_item_id=i.manifest_item_id
    where i.evaluation_id=p_evaluation_id
      and (
        (i.item_type='PHASE2_STUDENT_GOAL'
          and (f.field_name is null or f.field_name not in ('GOAL_TYPE','CONCEPT_ID','GOAL_TEXT')))
        or (i.item_type='PHASE2_STUDENT_PREFERENCE'
          and (f.field_name is null or f.field_name not in ('PREFERENCE_TYPE','VALUE')))
        or (i.item_type='PHASE2_STUDENT_COURSE'
          and (f.field_name is null or f.field_name not in ('COURSE_CODE','COURSE_TITLE','COURSE_STATUS','TERM')))
        or (i.item_type='PHASE2_STUDENT_COMPLETENESS'
          and (f.field_name is null or f.field_name not in ('EDUCATION_CONTEXT_ID','DOMAIN','COMPLETENESS')))
        or (i.item_type not in (
          'PHASE2_STUDENT_GOAL','PHASE2_STUDENT_PREFERENCE',
          'PHASE2_STUDENT_COURSE','PHASE2_STUDENT_COMPLETENESS'
        ) and f.field_name is not null)
      )
  ) then
    raise exception 'Phase 2 student field uses violate the Fit v0.1 hard allowlist';
  end if;
  if exists (
    select 1
    from public.fit_input_domain_states s
    join public.fit_manifest_items i
      on i.manifest_item_id=s.completeness_manifest_item_id
    where s.evaluation_id=p_evaluation_id
      and (i.item_type<>'PHASE2_STUDENT_COMPLETENESS'
        or i.method_id<>s.method_id
        or i.input_policy_id<>s.input_policy_id)
  ) then
    raise exception 'Input-state completeness references must use the same method requirement and a completeness item';
  end if;
  if exists (
    select 1
    from public.fit_input_domain_states state
    join public.fit_manifest_items item
      on item.manifest_item_id = state.provenance_manifest_item_id
    where state.evaluation_id = p_evaluation_id
      and (
        item.evaluation_id <> state.evaluation_id
        or item.method_id <> state.method_id
        or item.input_policy_id <> state.input_policy_id
      )
  ) then
    raise exception 'Input-state provenance must use the same evaluation method requirement';
  end if;

  -- Exact source scope and current authority.
  if exists (
    select 1
    from public.fit_manifest_intent_declarations x
    join public.fit_intent_declarations d using(intent_declaration_id)
    join public.fit_manifest_items i using(manifest_item_id)
    join public.fit_dimension_methods m
      on m.method_id = i.method_id
    where x.evaluation_id=p_evaluation_id
      and (x.intent_set_id<>v_eval.intent_set_id or d.dimension<>m.dimension)
  ) or exists (
    select 1 from public.fit_manifest_student_access_contexts x
    join private.fit_student_access_contexts c using(access_context_id)
    where x.evaluation_id=p_evaluation_id
      and (c.profile_version_id<>v_eval.profile_version_id
        or c.intent_set_id<>v_eval.intent_set_id)
  ) or exists (
    select 1
    from public.fit_manifest_phase2_mappings x
    join public.student_record_concept_mappings m using(student_mapping_id)
    join public.fit_manifest_items i using(manifest_item_id)
    where x.evaluation_id=p_evaluation_id
      and i.authority_role='AUTHORITATIVE'
      and (m.mapping_status<>'VERIFIED' or m.retired_at is not null)
  ) or exists (
    select 1
    from public.fit_manifest_catalog_mappings x
    join public.catalog_concept_mappings m
      on m.mapping_id=x.catalog_mapping_id
    join public.fit_manifest_items i using(manifest_item_id)
    where x.evaluation_id=p_evaluation_id
      and (
        public.catalog_record_program_version(m.record_type,m.record_id)
          is distinct from v_eval.program_version_id
        and not (
          m.record_type='PROGRAM' and exists (
            select 1 from public.program_versions pv
            where pv.program_version_id=v_eval.program_version_id
              and pv.program_id=m.record_id
          )
        )
        or (i.authority_role='AUTHORITATIVE'
          and (m.mapping_status<>'VERIFIED' or m.retired_at is not null))
      )
  ) then
    raise exception 'Manifest student, intent, or mapping scope/authority is invalid';
  end if;
  if exists (
    select i.method_id,m.concept_id
    from public.fit_manifest_phase2_mappings x
    join public.fit_manifest_items i using(manifest_item_id)
    join public.student_record_concept_mappings m using(student_mapping_id)
    where x.evaluation_id=p_evaluation_id
    union all
    select i.method_id,m.concept_id
    from public.fit_manifest_catalog_mappings x
    join public.fit_manifest_items i using(manifest_item_id)
    join public.catalog_concept_mappings m
      on m.mapping_id=x.catalog_mapping_id
    where x.evaluation_id=p_evaluation_id
    union all
    select i.method_id,m.concept_id
    from public.fit_manifest_context_mappings x
    join public.fit_manifest_items i using(manifest_item_id)
    join public.fit_context_concept_mappings m using(context_mapping_id)
    where x.evaluation_id=p_evaluation_id
    except
    select i.method_id,x.concept_id
    from public.fit_manifest_taxonomy_concepts x
    join public.fit_manifest_items i using(manifest_item_id)
    where x.evaluation_id=p_evaluation_id
  ) then
    raise exception 'Every supplied mapping concept requires a taxonomy manifest item for the same method';
  end if;
  if exists (
    select item.method_id, mapping.relation::text
    from public.fit_manifest_catalog_mappings manifest_mapping
    join public.fit_manifest_items item using(manifest_item_id)
    join public.catalog_concept_mappings mapping
      on mapping.mapping_id = manifest_mapping.catalog_mapping_id
    where manifest_mapping.evaluation_id = p_evaluation_id
    union all
    select item.method_id, 'STUDENT_COURSE_EQUIVALENCY'
    from public.fit_manifest_phase2_mappings manifest_mapping
    join public.fit_manifest_items item using(manifest_item_id)
    where manifest_mapping.evaluation_id = p_evaluation_id
    union all
    select item.method_id, mapping.relation_code
    from public.fit_manifest_context_mappings manifest_mapping
    join public.fit_manifest_items item using(manifest_item_id)
    join public.fit_context_concept_mappings mapping
      using(context_mapping_id)
    where manifest_mapping.evaluation_id = p_evaluation_id
    except
    select policy.method_id, policy.relation_code
    from public.fit_method_mapping_relation_policies policy
  ) then
    raise exception 'Mapping relation semantics are not authorized by the owning Fit method';
  end if;
  if exists (
    select 1
    from public.fit_signal_evidence evidence
    join public.fit_signals signal using(signal_id, evaluation_id)
    join public.fit_dimension_results result
      on result.dimension_result_id = signal.dimension_result_id
    join public.fit_manifest_items item using(manifest_item_id)
    left join public.fit_manifest_catalog_mappings catalog_manifest
      using(manifest_item_id)
    left join public.catalog_concept_mappings catalog_mapping
      on catalog_mapping.mapping_id = catalog_manifest.catalog_mapping_id
    left join public.fit_manifest_phase2_mappings student_manifest
      using(manifest_item_id)
    left join public.fit_manifest_context_mappings context_manifest
      using(manifest_item_id)
    left join public.fit_context_concept_mappings context_mapping
      on context_mapping.context_mapping_id =
        context_manifest.context_mapping_id
    left join public.fit_method_mapping_relation_policies policy
      on policy.method_id = item.method_id
     and policy.relation_code = coalesce(
       catalog_mapping.relation::text,
       case when student_manifest.student_mapping_id is not null
         then 'STUDENT_COURSE_EQUIVALENCY' end,
       context_mapping.relation_code
     )
    where evidence.evaluation_id = p_evaluation_id
      and coalesce(
        catalog_manifest.catalog_mapping_id,
        student_manifest.student_mapping_id,
        context_manifest.context_mapping_id
      ) is not null
      and (
        policy.method_id is null
        or not result.assessment = any(policy.allowed_assessments)
        or (
          result.assessment = 'STRONG_ALIGNMENT'
          and not policy.permits_strong_alignment
        )
      )
  ) then
    raise exception using errcode='42501',
      message='Mapping relation policy does not authorize this result assessment';
  end if;
  if exists (
    select 1
    from public.fit_manifest_catalog_observations x
    join public.field_observations o on o.observation_id=x.field_observation_id
    join public.fit_manifest_items i using(manifest_item_id)
    where x.evaluation_id=p_evaluation_id
      and (
        public.catalog_record_program_version(o.record_type,o.record_id)
          is distinct from v_eval.program_version_id
        and not (
          o.record_type='PROGRAM' and exists (
            select 1 from public.program_versions pv
            where pv.program_version_id=v_eval.program_version_id
              and pv.program_id=o.record_id
          )
        )
        or (
          i.authority_role='AUTHORITATIVE'
          and (o.knowledge_status<>'KNOWN' or not exists (
            select 1 from public.canonical_field_selections c
            where c.observation_id=o.observation_id
              and c.record_type=o.record_type
              and c.record_id=o.record_id
              and c.field_name=o.field_name
          ))
        )
      )
  ) then
    raise exception 'Catalog observations must belong to the target version; authoritative observations must be selected and KNOWN';
  end if;
  if exists (
    select 1
    from public.fit_manifest_catalog_observations manifest
    join public.fit_manifest_items item using(manifest_item_id)
    join public.field_observations observation
      on observation.observation_id = manifest.field_observation_id
    where manifest.evaluation_id = p_evaluation_id
      and not exists (
        select 1
        from public.fit_method_program_field_policies field_policy
        where field_policy.method_id = item.method_id
          and field_policy.input_policy_id = item.input_policy_id
          and field_policy.record_type = observation.record_type
          and field_policy.field_name = observation.field_name
      )
  ) then
    raise exception using errcode='42501',
      message='Program field observation is not explicitly allowlisted for its method policy';
  end if;
  if exists (
    select 1
    from public.fit_manifest_taxonomy_concepts x
    join public.taxonomy_concepts c using(concept_id)
    join public.taxonomy_releases introduced
      on introduced.release_code=c.introduced_in_release
    join public.taxonomy_releases pinned
      on pinned.release_code=v_eval.taxonomy_release_code
    left join public.taxonomy_releases retired
      on retired.release_code=c.retired_in_release
    where x.evaluation_id=p_evaluation_id
      and (introduced.published_at>pinned.published_at
        or retired.published_at<=pinned.published_at)
  ) then
    raise exception 'Taxonomy concepts must be active in the pinned release';
  end if;
  if exists (
    select 1
    from public.fit_manifest_context_claim_selections x
    join public.fit_context_claim_selection_history s
      on s.context_selection_id = x.context_selection_id
     and s.context_claim_id = x.context_claim_id
    join public.fit_context_claims c
      on c.context_claim_id = x.context_claim_id
    join public.fit_manifest_items i using(manifest_item_id)
    left join public.fit_context_claim_observations o
      on o.context_observation_id=x.context_observation_id
     and o.context_claim_id=x.context_claim_id
    where x.evaluation_id=p_evaluation_id
      and (x.knowledge_status<>s.knowledge_status
        or x.context_observation_id is distinct from s.context_observation_id
        or (c.program_version_id is not null
          and c.program_version_id<>v_eval.program_version_id)
        or (x.knowledge_status in ('SOURCE_CONFLICT','STALE')
          and i.authority_role<>'LIMITING_CONTEXT')
        or (i.authority_role='AUTHORITATIVE'
          and (x.knowledge_status<>'KNOWN' or x.context_observation_id is null
            or s.observation_workflow_status_at_selection
              is distinct from 'VERIFIED'
            or s.observation_reviewed_at_at_selection is null)))
  ) or exists (
    select 1
    from public.fit_manifest_context_mappings x
    join public.fit_context_concept_mappings m using(context_mapping_id)
    join public.fit_context_claims c using(context_claim_id)
    join public.fit_manifest_items i using(manifest_item_id)
    where x.evaluation_id=p_evaluation_id
      and i.authority_role='AUTHORITATIVE'
      and (x.mapping_status_at_pin<>'VERIFIED'
        or x.mapping_retired_at_at_pin is not null
        or x.mapping_reviewed_at_at_pin is null
        or x.mapping_verification_evidence_id_at_pin is null
        or (c.program_version_id is not null
          and c.program_version_id<>v_eval.program_version_id)
        or not exists (
          select 1
          from public.fit_manifest_context_claim_selections selected
          join public.fit_manifest_items selected_item
            using (manifest_item_id)
          join public.fit_context_claim_selection_history history
            on history.context_selection_id =
              selected.context_selection_id
           and history.context_claim_id = selected.context_claim_id
          where selected.evaluation_id = x.evaluation_id
            and selected.context_claim_id = m.context_claim_id
            and selected_item.method_id = i.method_id
            and history.knowledge_status = 'KNOWN'
            and history.observation_workflow_status_at_selection =
              'VERIFIED'
        ))
  ) then
    raise exception 'Context selections/mappings do not satisfy pinned scoped authority';
  end if;
  if exists (
    select n.financial_normalization_id
    from public.fit_financial_normalizations n
    where n.evaluation_id=p_evaluation_id
    except
    select m.financial_normalization_id
    from public.fit_manifest_financial_normalizations m
    where m.evaluation_id=p_evaluation_id
  ) then
    raise exception 'Every evaluation-scoped financial normalization requires its manifest subtype';
  end if;

  -- Results, signals, evidence, and reasons must remain within the owning method.
  if exists (
    select 1
    from public.fit_dimension_results r
    join public.fit_dimension_methods m using(method_id)
    where r.evaluation_id=p_evaluation_id
      and (m.status<>'VERIFIED' or m.retired_at is not null
        or m.contract_release_id<>v_eval.contract_release_id
        or m.dimension<>r.dimension
        or (m.inference_category<>'HYBRID'
          and m.inference_category<>r.inference_category))
  ) or exists (
    select 1
    from public.fit_signals s
    join public.fit_dimension_results r
      on r.dimension_result_id=s.dimension_result_id
    where s.evaluation_id=p_evaluation_id and s.dimension<>r.dimension
  ) or exists (
    select 1
    from public.fit_signals s
    join public.fit_dimension_results r
      on r.dimension_result_id=s.dimension_result_id
    join public.fit_manifest_intent_declarations d
      on d.evaluation_id=s.evaluation_id
     and d.intent_declaration_id=s.intent_declaration_id
    join public.fit_manifest_items i using(manifest_item_id)
    where s.evaluation_id=p_evaluation_id
      and i.method_id<>r.method_id
  ) or exists (
    select 1
    from public.fit_signal_evidence se
    join public.fit_signals s using(signal_id,evaluation_id)
    join public.fit_dimension_results r
      on r.dimension_result_id=s.dimension_result_id
    join public.fit_manifest_items i
      on i.manifest_item_id=se.manifest_item_id
    where se.evaluation_id=p_evaluation_id
      and (i.evaluation_id<>se.evaluation_id or i.method_id<>r.method_id)
  ) then
    raise exception 'Result methods or signal evidence do not match their owning dimension method';
  end if;
  if exists (
    select 1
    from public.fit_signals signal
    join public.fit_dimension_results result
      on result.dimension_result_id = signal.dimension_result_id
     and result.evaluation_id = signal.evaluation_id
    join public.fit_signal_types signal_type
      on signal_type.signal_type_id = signal.signal_type_id
     and signal_type.method_id = signal.method_id
    where signal.evaluation_id = p_evaluation_id
      and (
        signal.method_id <> result.method_id
        or signal.direction <> signal_type.direction
        or signal.material <> signal_type.material
        or not signal.inference_category =
          any(signal_type.allowed_inference_categories)
      )
  ) then
    raise exception 'Signal direction, materiality, inference category, and method must come from its registered signal type';
  end if;
  if exists (
    select 1
    from public.fit_signals signal
    join public.fit_dimension_results result
      on result.dimension_result_id = signal.dimension_result_id
    left join public.fit_intent_declarations intent
      on intent.intent_declaration_id = signal.intent_declaration_id
     and intent.intent_set_id = v_eval.intent_set_id
     and intent.profile_version_id = v_eval.profile_version_id
    where signal.evaluation_id = p_evaluation_id
      and signal.intent_declaration_id is not null
      and (
        intent.intent_declaration_id is null
        or intent.dimension <> result.dimension
        or not exists (
          select 1
          from public.fit_manifest_intent_declarations manifest_intent
          join public.fit_manifest_items item using(manifest_item_id)
          where manifest_intent.evaluation_id = signal.evaluation_id
            and manifest_intent.intent_declaration_id =
              signal.intent_declaration_id
            and item.method_id = signal.method_id
        )
      )
  ) then
    raise exception using errcode='23503',
      message='Signal intent must be in the frozen intent set, own the dimension, and be manifested by the same method';
  end if;
  if exists (
    select 1
    from public.fit_signal_evidence se
    join public.fit_signals s using(signal_id,evaluation_id)
    join public.fit_manifest_items i using(manifest_item_id)
    join public.fit_method_input_policies p
      on p.input_policy_id=i.input_policy_id
    where se.evaluation_id=p_evaluation_id
      and (
        (s.inference_category='MODEL' and not p.permits_model_use)
        or (s.inference_category='DETERMINISTIC'
          and not p.permits_deterministic_use)
      )
  ) or exists (
    select 1
    from public.fit_signal_evidence se
    join public.fit_manifest_items i using(manifest_item_id)
    join public.fit_method_input_policies p
      on p.input_policy_id=i.input_policy_id
    join public.fit_manifest_context_claim_selections selection
      using(manifest_item_id)
    left join public.fit_context_claim_observations observation
      on observation.context_observation_id=
        selection.context_observation_id
     and observation.context_claim_id=selection.context_claim_id
    where se.evaluation_id=p_evaluation_id
      and (
        (p.acceptable_authority is not null
          and observation.authority is distinct from
            p.acceptable_authority)
        or (p.acceptable_claim_status is not null
          and observation.workflow_status is distinct from
            p.acceptable_claim_status)
      )
  ) then
    raise exception 'Signal evidence violates method policy permissions or exact context authority/status';
  end if;
  if exists (
    select 1 from public.fit_signals s
    where s.evaluation_id=p_evaluation_id and s.material
      and not exists (
        select 1 from public.fit_signal_evidence se
        where se.signal_id=s.signal_id
      )
  ) then
    raise exception 'Every material signal requires exact evidence';
  end if;
  if exists (
    select 1
    from public.fit_signals s
    where s.evaluation_id=p_evaluation_id
      and s.material
      and s.direction in ('SUPPORTING','CONTRADICTING')
      and (
        s.intent_declaration_id is null
        or not exists (
          select 1
          from public.fit_signal_evidence intent_evidence
          join public.fit_manifest_intent_declarations manifest_intent
            using(manifest_item_id)
          where intent_evidence.signal_id = s.signal_id
            and manifest_intent.intent_declaration_id =
              s.intent_declaration_id
        )
        or not exists (
          select 1
          from public.fit_signal_evidence se
          join public.fit_manifest_items i using(manifest_item_id)
          where se.signal_id=s.signal_id
            and se.evaluation_id=s.evaluation_id
            and i.authority_role='AUTHORITATIVE'
            and i.item_type in (
              'CATALOG_FIELD_OBSERVATION',
              'CATALOG_MAPPING',
              'FIT_CONTEXT_CLAIM_SELECTION',
              'FIT_CONTEXT_MAPPING',
              'FIT_FINANCIAL_NORMALIZATION'
            )
        )
      )
  ) then
    raise exception 'Every material directional signal requires exact manifested intent evidence and AUTHORITATIVE evidence';
  end if;
  if exists (
    select 1
    from public.fit_signal_evidence se
    join public.fit_signals s using(signal_id,evaluation_id)
    join public.fit_manifest_items i using(manifest_item_id)
    left join public.fit_manifest_context_claim_selections cs using(manifest_item_id)
    where se.evaluation_id=p_evaluation_id
      and cs.knowledge_status in ('SOURCE_CONFLICT','STALE')
      and (s.direction<>'LIMITING' or s.material)
  ) then
    raise exception 'Conflicting or stale context may be limiting only, never directional';
  end if;
  if exists (
    select 1
    from public.fit_dimension_reasons dr
    join public.fit_dimension_results r
      on r.dimension_result_id=dr.dimension_result_id
    join public.fit_reason_definitions d
      on d.reason_definition_id=dr.reason_definition_id
    left join public.fit_signals s on s.signal_id=dr.signal_id
    left join public.fit_input_domain_states st on st.input_state_id=dr.input_state_id
    where dr.evaluation_id=p_evaluation_id
      and (d.status<>'VERIFIED' or d.retired_at is not null
        or d.contract_release_id<>v_eval.contract_release_id
        or (d.dimension is not null and d.dimension<>r.dimension)
        or d.direction<>dr.direction
        or not r.assessment=any(d.allowed_assessments)
        or (s.signal_id is not null
          and (s.evaluation_id<>dr.evaluation_id or s.dimension<>r.dimension
            or s.direction<>dr.direction))
        or (st.input_state_id is not null
          and (st.evaluation_id<>dr.evaluation_id or st.method_id<>r.method_id)))
  ) or exists (
    select 1 from public.fit_dimension_results r
    where r.evaluation_id=p_evaluation_id
      and not exists (
        select 1 from public.fit_dimension_reasons dr
        where dr.dimension_result_id=r.dimension_result_id
      )
  ) then
    raise exception 'Every result requires valid verified structured reasons';
  end if;

  -- Approved categorical semantics.
  if exists (
    select 1 from public.fit_dimension_results r
    where r.evaluation_id=p_evaluation_id and r.assessment='MIXED'
      and (not exists (
        select 1 from public.fit_signals s
        where s.dimension_result_id=r.dimension_result_id and s.material
          and s.direction='SUPPORTING'
      ) or not exists (
        select 1 from public.fit_signals s
        where s.dimension_result_id=r.dimension_result_id and s.material
          and s.direction='CONTRADICTING'
      ))
  ) then
    raise exception 'MIXED requires material supporting and contradicting signals';
  end if;
  if exists (
    select 1 from public.fit_dimension_results r
    where r.evaluation_id=p_evaluation_id and r.assessment='ALIGNMENT'
      and (
        not exists (
          select 1 from public.fit_signals s
          where s.dimension_result_id=r.dimension_result_id
            and s.material and s.direction='SUPPORTING'
        )
        or exists (
          select 1 from public.fit_signals s
          where s.dimension_result_id=r.dimension_result_id
            and s.material and s.direction='CONTRADICTING'
        )
      )
  ) then
    raise exception 'ALIGNMENT requires material support and no material contradiction';
  end if;
  if exists (
    select 1 from public.fit_dimension_results r
    where r.evaluation_id=p_evaluation_id and r.assessment='MISALIGNMENT'
      and not exists (
        select 1 from public.fit_signals s
        where s.dimension_result_id=r.dimension_result_id and s.material
          and s.direction='CONTRADICTING'
      )
  ) then
    raise exception 'MISALIGNMENT requires a method-valid material contradiction';
  end if;
  if exists (
    select 1 from public.fit_dimension_results r
    where r.evaluation_id=p_evaluation_id and r.assessment='MISALIGNMENT'
      and exists (
        select 1 from public.fit_signals support
        where support.dimension_result_id=r.dimension_result_id
          and support.material and support.direction='SUPPORTING'
      )
      and not exists (
        select 1
        from public.fit_signals contradiction
        join public.fit_intent_declarations intent
          on intent.intent_declaration_id =
            contradiction.intent_declaration_id
        where contradiction.dimension_result_id=r.dimension_result_id
          and contradiction.material
          and contradiction.direction='CONTRADICTING'
          and contradiction.required_constraint_contradiction
          and intent.importance='REQUIRED'
      )
  ) then
    raise exception 'Ordinary material support and contradiction require MIXED, not MISALIGNMENT';
  end if;
  if exists (
    select 1
    from public.fit_signals s
    join public.fit_intent_declarations d
      on d.intent_declaration_id=s.intent_declaration_id
    join public.fit_dimension_results r
      on r.dimension_result_id=s.dimension_result_id
    where s.evaluation_id=p_evaluation_id
      and (
        (s.required_constraint_contradiction
          and (d.importance<>'REQUIRED'
            or r.assessment<>'MISALIGNMENT'
            or s.inference_category<>'DETERMINISTIC'
            or not exists (
              select 1
              from public.fit_signal_evidence evidence
              join public.fit_manifest_intent_declarations intent_manifest
                using(manifest_item_id)
              where evidence.signal_id = s.signal_id
                and intent_manifest.intent_declaration_id =
                  s.intent_declaration_id
            )
            or not (
              exists (
                select 1
                from public.fit_signal_evidence evidence
                join public.fit_manifest_items item using(manifest_item_id)
                join public.fit_manifest_catalog_observations manifest
                  using(manifest_item_id)
                join public.field_observations observation
                  on observation.observation_id =
                    manifest.field_observation_id
                left join public.fit_intent_delivery_constraints delivery
                  on delivery.intent_declaration_id =
                    s.intent_declaration_id
                left join public.fit_intent_duration_constraints duration
                  on duration.intent_declaration_id =
                    s.intent_declaration_id
                where evidence.signal_id = s.signal_id
                  and item.authority_role = 'AUTHORITATIVE'
                  and observation.knowledge_status = 'KNOWN'
                  and (
                    (
                      d.semantic_type = 'DELIVERY_CONSTRAINT'
                      and observation.record_type = 'PROGRAM_VERSION'
                      and observation.field_name = 'delivery_mode'
                      and observation.observed_value #>> '{}' <>
                        delivery.delivery_mode::text
                    )
                    or (
                      d.semantic_type = 'DURATION_CONSTRAINT'
                      and observation.record_type = 'PROGRAM_VERSION'
                      and observation.field_name = 'duration_months'
                      and jsonb_typeof(observation.observed_value) =
                        'number'
                      and (
                        (
                          duration.minimum_months is not null
                          and (observation.observed_value #>> '{}')::numeric
                            < duration.minimum_months
                        )
                        or (
                          duration.maximum_months is not null
                          and (observation.observed_value #>> '{}')::numeric
                            > duration.maximum_months
                        )
                      )
                    )
                  )
              )
              or exists (
                select 1
                from public.fit_signal_evidence evidence
                join public.fit_manifest_financial_normalizations manifest
                  using(manifest_item_id)
                where evidence.signal_id = s.signal_id
                  and d.semantic_type = 'FINANCIAL_CONSTRAINT'
              )
            )))
        or (s.material and s.direction='CONTRADICTING'
          and d.importance='REQUIRED'
          and (not s.required_constraint_contradiction
            or r.assessment<>'MISALIGNMENT'))
      )
  ) then
    raise exception 'Required contradictions must be deterministic, directly comparable, reference REQUIRED intent, and force MISALIGNMENT';
  end if;
  if exists (
    select 1
    from public.fit_dimension_results r
    join public.fit_dimension_methods m using(method_id)
    where r.evaluation_id=p_evaluation_id and r.assessment='STRONG_ALIGNMENT'
      and (not m.permits_strong_alignment
        or exists (
          select 1 from public.fit_signals s
          where s.dimension_result_id=r.dimension_result_id
            and s.material and s.direction='CONTRADICTING'
        )
        or not exists (
          select 1
          from public.fit_signals signal
          join public.fit_signal_types signal_type
            on signal_type.signal_type_id = signal.signal_type_id
           and signal_type.method_id = signal.method_id
          join public.fit_intent_declarations intent
            on intent.intent_declaration_id =
              signal.intent_declaration_id
          where signal.dimension_result_id = r.dimension_result_id
            and signal.material
            and signal.direction = 'SUPPORTING'
            and signal.inference_category <> 'MODEL'
            and signal_type.permits_strong_alignment
            and intent.importance in (
              'REQUIRED', 'STRONGLY_PREFERRED'
            )
            and exists (
              select 1
              from public.fit_signal_evidence evidence
              join public.fit_manifest_items item using(manifest_item_id)
              where evidence.signal_id = signal.signal_id
                and item.authority_role = 'AUTHORITATIVE'
                and item.item_type =
                  'CATALOG_FIELD_OBSERVATION'
            )
        ))
  ) then
    raise exception 'STRONG_ALIGNMENT requires method permission, qualifying non-model positive evidence, and no material contradiction';
  end if;
  if exists (
    select 1
    from public.fit_dimension_results result
    where result.evaluation_id=p_evaluation_id
      and result.evidence_coverage='INSUFFICIENT'
      and result.assessment<>'UNKNOWN'
  ) then
    raise exception 'INSUFFICIENT evidence coverage permits only UNKNOWN';
  end if;
  if exists (
    select 1
    from public.fit_dimension_results result
    where result.evaluation_id=p_evaluation_id
      and result.assessment<>'UNKNOWN'
      and result.confidence='HIGH'
      and exists (
        select 1 from public.fit_signals signal
        where signal.dimension_result_id=result.dimension_result_id
          and signal.material
          and signal.direction in ('SUPPORTING','CONTRADICTING')
      )
      and not exists (
        select 1 from public.fit_signals signal
        where signal.dimension_result_id=result.dimension_result_id
          and signal.material
          and signal.direction in ('SUPPORTING','CONTRADICTING')
          and signal.inference_category<>'MODEL'
      )
  ) then
    raise exception 'Model-only directional evidence cannot receive HIGH confidence';
  end if;
  if exists (
    select 1 from public.fit_dimension_results r
    where r.evaluation_id=p_evaluation_id and r.assessment='UNKNOWN'
      and not exists (
        select 1
        from public.fit_dimension_reasons reason
        join public.fit_reason_definitions definition
          on definition.reason_definition_id = reason.reason_definition_id
        where reason.dimension_result_id = r.dimension_result_id
          and reason.direction = 'LIMITING'
          and definition.reason_family in (
            'STUDENT_INPUT_NOT_SUPPLIED',
            'STUDENT_INPUT_INCOMPLETE',
            'PROGRAM_FACT_UNKNOWN',
            'SOURCE_CONFLICT',
            'STALE_SOURCE',
            'NO_AUTHORITATIVE_MAPPING',
            'EVIDENCE_INSUFFICIENT',
            'METHOD_UNSUPPORTED',
            'METHOD_LIMITATION',
            'INPUT_INAPPLICABLE',
            'INTENT_UNSPECIFIED',
            'INTENT_CONFLICT',
            'CONTEXT_APPLICABILITY_UNKNOWN'
          )
      )
  ) then
    raise exception 'UNKNOWN requires at least one normalized limiting reason family';
  end if;
  if exists (
    select 1
    from public.fit_dimension_results result
    join public.fit_dimension_reasons reason
      on reason.dimension_result_id = result.dimension_result_id
    left join public.fit_signals signal
      on signal.signal_id = reason.signal_id
    left join public.fit_input_domain_states state
      on state.input_state_id = reason.input_state_id
    where result.evaluation_id = p_evaluation_id
      and result.assessment = 'UNKNOWN'
      and reason.direction = 'LIMITING'
      and not (
        (
          state.input_state_id is not null
          and state.availability <> 'INCLUDED'
        )
        or (
          signal.signal_id is not null
          and signal.direction = 'LIMITING'
          and exists (
            select 1
            from public.fit_signal_evidence evidence
            where evidence.signal_id = signal.signal_id
          )
        )
      )
  ) then
    raise exception using errcode='23514',
      message='UNKNOWN limiting reasons require exact unavailable-input or limiting-signal provenance';
  end if;
  if exists (
    select 1 from public.fit_signals s
    where s.evaluation_id=p_evaluation_id
      and s.international_high_impact and s.direction<>'LIMITING'
      and (
        s.inference_category='MODEL'
        or not exists (
          select 1
          from public.fit_signal_evidence se_claim
          join public.fit_manifest_items claim_item
            on claim_item.manifest_item_id=se_claim.manifest_item_id
          join public.fit_manifest_context_claim_selections selection
            on selection.manifest_item_id=claim_item.manifest_item_id
          join public.fit_context_claims claim
            on claim.context_claim_id=selection.context_claim_id
          join public.fit_context_claim_observations observation
            on observation.context_observation_id=
              selection.context_observation_id
           and observation.context_claim_id=selection.context_claim_id
          join public.fit_context_claim_selection_history selection_history
            on selection_history.context_selection_id =
              selection.context_selection_id
           and selection_history.context_claim_id =
              selection.context_claim_id
          where se_claim.signal_id=s.signal_id
            and se_claim.evaluation_id=s.evaluation_id
            and claim_item.authority_role='AUTHORITATIVE'
            and selection.knowledge_status='KNOWN'
            and selection_history.observation_workflow_status_at_selection =
              'VERIFIED'
            and observation.authority <> 'MODEL_GENERATED'
            and claim.valid_from<=v_eval.evaluation_as_of::date
            and (claim.valid_to is null
              or claim.valid_to>=v_eval.evaluation_as_of::date)
            and (claim.program_version_id is null
              or claim.program_version_id=v_eval.program_version_id)
            and exists (
              select 1
              from public.fit_signal_evidence se_access
              join public.fit_manifest_items access_item
                on access_item.manifest_item_id=
                  se_access.manifest_item_id
              join public.fit_manifest_student_access_contexts manifest_access
                on manifest_access.manifest_item_id=
                  access_item.manifest_item_id
              join private.fit_student_access_contexts access
                using(access_context_id)
              where se_access.signal_id=s.signal_id
                and se_access.evaluation_id=s.evaluation_id
                and access_item.authority_role='AUTHORITATIVE'
                and (
                  claim.jurisdiction_code is null
                  or claim.jurisdiction_code=
                    access.governing_jurisdiction_code
                )
                and (
                  claim.path_code is null
                  or claim.path_code=access.target_path_code
                  or claim.path_code=access.authorization_path_code
                )
                and (
                  claim.geography_code is null
                  or lower(claim.geography_code) =
                    lower(access.residence_country_code)
                  or lower(claim.geography_code) =
                    lower(access.citizenship_country_code)
                )
            )
        )
      )
  ) then
    raise exception 'High-impact international direction requires matching authoritative student access and current VERIFIED claim evidence and cannot be model-only';
  end if;
  if v_eval.financial_contract_version = 'FINANCIAL_BILLING_BASIS_V014' then
    perform private.validate_fit_financial_finalization_v014(p_evaluation_id);
  elsif v_eval.financial_contract_version is null then
    if exists (
      select 1
      from public.fit_dimension_results r
      where r.evaluation_id=p_evaluation_id
        and r.dimension='FINANCIAL'
        and r.assessment<>'UNKNOWN'
        and r.inference_category='DETERMINISTIC'
        and not exists (
          select 1
          from public.fit_signals s
          join public.fit_signal_evidence se using(signal_id,evaluation_id)
          join public.fit_manifest_items i using(manifest_item_id)
          where s.dimension_result_id=r.dimension_result_id
            and i.item_type='FIT_FINANCIAL_NORMALIZATION'
        )
        and not exists (
          select 1
          from public.fit_signals signal
          join public.fit_signal_evidence intent_evidence
            on intent_evidence.signal_id = signal.signal_id
          join public.fit_manifest_items intent_item
            on intent_item.manifest_item_id =
              intent_evidence.manifest_item_id
           and intent_item.item_type = 'FIT_INTENT_DECLARATION'
           and intent_item.authority_role = 'AUTHORITATIVE'
          join public.fit_manifest_intent_declarations intent_manifest
            on intent_manifest.manifest_item_id =
              intent_item.manifest_item_id
          join public.fit_intent_financial_constraints constraint_value
            on constraint_value.intent_declaration_id =
              intent_manifest.intent_declaration_id
          join public.fit_signal_evidence program_evidence
            on program_evidence.signal_id = signal.signal_id
          join public.fit_manifest_items program_item
            on program_item.manifest_item_id =
              program_evidence.manifest_item_id
           and program_item.item_type =
             'CATALOG_FIELD_OBSERVATION'
           and program_item.authority_role = 'AUTHORITATIVE'
          join public.fit_manifest_catalog_observations program_manifest
            on program_manifest.manifest_item_id =
              program_item.manifest_item_id
          join public.field_observations observation
            on observation.observation_id =
              program_manifest.field_observation_id
          join public.program_costs program_cost
            on observation.record_type = 'PROGRAM_COST'
           and program_cost.cost_id = observation.record_id
          where signal.dimension_result_id = r.dimension_result_id
            and signal.material
            and signal.direction in ('SUPPORTING','CONTRADICTING')
            and observation.field_name in (
              'tuition_amount', 'mandatory_fees',
              'estimated_living_cost', 'estimated_total_cost'
            )
            and constraint_value.currency = program_cost.currency
            and constraint_value.financial_period = 'ACADEMIC_YEAR'
            and constraint_value.financial_basis = 'GROSS'
            and constraint_value.financial_scope = case
              when observation.field_name = 'estimated_total_cost'
                then 'TOTAL_COST'::public.fit_financial_scope
              else 'COMPONENT'::public.fit_financial_scope
            end
            and (
              select array_agg(component order by component)
              from unnest(constraint_value.components) component
            ) = array[
              case observation.field_name
                when 'tuition_amount' then 'TUITION'
                when 'mandatory_fees' then 'MANDATORY_FEES'
                when 'estimated_living_cost' then 'LIVING_COST'
                when 'estimated_total_cost' then 'TOTAL_COST'
              end
            ]::text[]
        )
    ) then
      raise exception 'Directional deterministic Financial Fit requires direct comparable facts or a VERIFIED normalization artifact';
    end if;
  else
    raise exception using errcode='55000', message='Unknown Financial contract version';
  end if;

  v_fingerprint :=
    public.compute_fit_decision_input_fingerprint(p_evaluation_id);
  if v_fingerprint is distinct from v_eval.candidate_input_fingerprint then
    raise exception 'Decision inputs changed after evaluator candidate sealing';
  end if;
  v_result_fingerprint :=
    public.compute_fit_result_fingerprint(p_evaluation_id);
  v_prior := current_setting('app.fit_evaluation_controlled_write',true);
  perform set_config('app.fit_evaluation_controlled_write','on',true);
  update public.fit_evaluations
  set evaluation_state='COMPLETED',
      decision_input_fingerprint=v_fingerprint,
      result_fingerprint=v_result_fingerprint,
      evaluated_at=now(),
      finalized_by=coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        session_user::text
      )
  where evaluation_id=p_evaluation_id;
  perform set_config('app.fit_evaluation_controlled_write',coalesce(v_prior,''),true);
  return v_fingerprint;
end;
$$;

create policy fit_financial_reviews_owner_v014
on public.fit_financial_normalization_reviews_v014
for all to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (current_user = 'foundation_evaluation_executor');

create policy fit_financial_inputs_owner_v014
on public.fit_financial_conversion_inputs_v014
for all to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (current_user = 'foundation_evaluation_executor');

create policy fit_financial_factors_owner_v014
on public.fit_financial_conversion_factors_v014
for all to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (current_user = 'foundation_evaluation_executor');

create policy fit_financial_source_pins_owner_v014
on private.fit_financial_source_pins_v014
for all to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (current_user = 'foundation_evaluation_executor');

create policy fit_financial_verified_pins_owner_v014
on private.fit_financial_normalization_verified_pins_v014
for all to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (current_user = 'foundation_evaluation_executor');

-- SELECT ... FOR UPDATE requires UPDATE privilege and an UPDATE-visible RLS
-- policy even though the pin function never mutates the canonical cost row.
-- WITH CHECK false preserves the existing catalog-writer boundary.
create policy program_costs_evaluation_executor_lock_v014
on public.program_costs
for update to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (false);

create policy fit_financial_methods_evaluation_executor_lock_v014
on public.fit_financial_normalization_methods
for update to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (false);

create policy fit_intent_financial_constraints_evaluation_executor_lock_v014
on public.fit_intent_financial_constraints
for update to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (false);

create policy fit_intent_declarations_evaluation_executor_lock_v014
on public.fit_intent_declarations
for update to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (false);

grant update on public.program_costs,
  public.fit_financial_normalization_methods,
  public.fit_intent_financial_constraints,
  public.fit_intent_declarations
to foundation_evaluation_executor;

grant create on schema public, private to foundation_evaluation_executor;

alter table private.fit_financial_source_pins_v014 owner to foundation_evaluation_executor;
alter table public.fit_financial_normalization_reviews_v014 owner to foundation_evaluation_executor;
alter table public.fit_financial_conversion_factors_v014 owner to foundation_evaluation_executor;
alter table public.fit_financial_conversion_inputs_v014 owner to foundation_evaluation_executor;
alter table private.fit_financial_normalization_verified_pins_v014 owner to foundation_evaluation_executor;
alter function private.set_fit_financial_contract_v014() owner to foundation_evaluation_executor;
alter function private.guard_fit_financial_contract_v014() owner to foundation_evaluation_executor;
alter function public.adopt_fit_financial_contract_v014(uuid) owner to foundation_evaluation_executor;
alter function private.create_fit_financial_review_v014() owner to foundation_evaluation_executor;
alter function private.guard_fit_financial_review_insert_v014() owner to foundation_evaluation_executor;
alter function private.require_fit_financial_v014_assembly(uuid) owner to foundation_evaluation_executor;
alter function public.pin_fit_financial_source_v014(uuid,uuid,uuid) owner to foundation_evaluation_executor;
alter function public.insert_fit_financial_conversion_input_v014(public.fit_financial_conversion_inputs_v014) owner to foundation_evaluation_executor;
alter function public.insert_fit_financial_conversion_factor_v014(public.fit_financial_conversion_factors_v014) owner to foundation_evaluation_executor;
alter function private.guard_fit_financial_typed_rows_v014() owner to foundation_evaluation_executor;
alter function private.fit_financial_typed_input_payload_hash_v014(uuid) owner to foundation_evaluation_executor;
alter function private.fit_financial_typed_factor_payload_hash_v014(uuid) owner to foundation_evaluation_executor;
alter function private.guard_fit_financial_normalization_update_v014() owner to foundation_evaluation_executor;
alter function private.guard_fit_financial_review_update_v014() owner to foundation_evaluation_executor;
alter function public.verify_fit_financial_normalization_v014(uuid,text,uuid) owner to foundation_evaluation_executor;
alter function public.retire_fit_financial_normalization_v014(uuid,text) owner to foundation_evaluation_executor;
alter function public.validate_fit_financial_normalization() owner to foundation_evaluation_executor;
alter function private.fit_financial_source_payload_v014(uuid) owner to foundation_evaluation_executor;
alter function private.fit_financial_normalization_payload_v014(uuid) owner to foundation_evaluation_executor;
alter function private.fit_financial_payload_collections_v014(uuid) owner to foundation_evaluation_executor;
alter function private.fit_decision_input_payload_v011(uuid) owner to foundation_evaluation_executor;
alter function public.compute_fit_decision_input_fingerprint(uuid) owner to foundation_evaluation_executor;
alter function private.validate_fit_financial_live_pins_v014(uuid) owner to foundation_evaluation_executor;
alter function private.validate_fit_financial_finalization_v014(uuid) owner to foundation_evaluation_executor;
alter function public.finalize_fit_evaluation(uuid) owner to foundation_evaluation_executor;

alter table private.fit_financial_source_pins_v014 enable row level security;
alter table private.fit_financial_source_pins_v014 force row level security;
alter table public.fit_financial_normalization_reviews_v014 enable row level security;
alter table public.fit_financial_normalization_reviews_v014 force row level security;
alter table public.fit_financial_conversion_factors_v014 enable row level security;
alter table public.fit_financial_conversion_factors_v014 force row level security;
alter table public.fit_financial_conversion_inputs_v014 enable row level security;
alter table public.fit_financial_conversion_inputs_v014 force row level security;
alter table private.fit_financial_normalization_verified_pins_v014 enable row level security;
alter table private.fit_financial_normalization_verified_pins_v014 force row level security;

revoke all on private.fit_financial_source_pins_v014 from public, anon, authenticated, service_role;
revoke all on public.fit_financial_normalization_reviews_v014 from public, anon, authenticated, service_role;
revoke all on public.fit_financial_conversion_factors_v014 from public, anon, authenticated, service_role;
revoke all on public.fit_financial_conversion_inputs_v014 from public, anon, authenticated, service_role;
revoke all on private.fit_financial_normalization_verified_pins_v014 from public, anon, authenticated, service_role;

grant select on public.fit_financial_normalization_reviews_v014,
  public.fit_financial_conversion_factors_v014,
  public.fit_financial_conversion_inputs_v014
to foundation_catalog_executor;

grant select, insert, update on public.fit_financial_normalization_reviews_v014
to foundation_evaluation_executor;
grant select, insert on public.fit_financial_conversion_factors_v014,
  public.fit_financial_conversion_inputs_v014
to foundation_evaluation_executor;
grant select, insert on private.fit_financial_source_pins_v014
to foundation_evaluation_executor;
grant select, insert, update on private.fit_financial_normalization_verified_pins_v014
to foundation_evaluation_executor;

revoke create on schema public, private from foundation_evaluation_executor;

revoke all on function public.fit_financial_period_for_billing_basis(public.billing_basis)
from public, anon, authenticated, service_role, foundation_catalog_executor, foundation_evaluation_executor;
revoke all on function public.fit_financial_facts_directly_comparable(
  text, public.fit_financial_period, public.fit_financial_scope,
  public.fit_financial_basis, text[], text, public.fit_financial_period,
  public.fit_financial_scope, public.fit_financial_basis, text[]
) from public, anon, authenticated, service_role, foundation_catalog_executor, foundation_evaluation_executor;
grant execute on function public.fit_financial_period_for_billing_basis(public.billing_basis)
to foundation_evaluation_executor;
grant execute on function public.fit_financial_facts_directly_comparable(
  text, public.fit_financial_period, public.fit_financial_scope,
  public.fit_financial_basis, text[], text, public.fit_financial_period,
  public.fit_financial_scope, public.fit_financial_basis, text[]
) to foundation_evaluation_executor;

revoke all on function public.adopt_fit_financial_contract_v014(uuid)
from public, anon, authenticated, service_role, foundation_catalog_executor, foundation_evaluation_executor;
grant execute on function public.adopt_fit_financial_contract_v014(uuid) to service_role;
revoke all on function public.insert_fit_financial_conversion_input_v014(public.fit_financial_conversion_inputs_v014),
  public.pin_fit_financial_source_v014(uuid,uuid,uuid),
  public.insert_fit_financial_conversion_factor_v014(public.fit_financial_conversion_factors_v014),
  public.verify_fit_financial_normalization_v014(uuid,text,uuid),
  public.retire_fit_financial_normalization_v014(uuid,text)
from public, anon, authenticated, service_role, foundation_catalog_executor, foundation_evaluation_executor;
grant execute on function public.insert_fit_financial_conversion_input_v014(public.fit_financial_conversion_inputs_v014),
  public.insert_fit_financial_conversion_factor_v014(public.fit_financial_conversion_factors_v014),
  public.pin_fit_financial_source_v014(uuid,uuid,uuid)
to service_role;
grant execute on function public.verify_fit_financial_normalization_v014(uuid,text,uuid),
  public.retire_fit_financial_normalization_v014(uuid,text)
to foundation_catalog_executor;

revoke all on function
  private.fit_financial_typed_input_payload_hash_v014(uuid),
  private.fit_financial_typed_factor_payload_hash_v014(uuid),
  private.validate_fit_financial_live_pins_v014(uuid)
from public, anon, authenticated, service_role,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant execute on function
  private.fit_financial_typed_input_payload_hash_v014(uuid),
  private.fit_financial_typed_factor_payload_hash_v014(uuid),
  private.validate_fit_financial_live_pins_v014(uuid)
to foundation_evaluation_executor;

commit;
