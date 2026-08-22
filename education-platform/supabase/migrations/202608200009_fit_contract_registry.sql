begin;

create type public.fit_dimension as enum (
  'ACADEMIC',
  'CAREER',
  'FINANCIAL',
  'GEOGRAPHIC_DELIVERY',
  'PERSONAL_PREFERENCE',
  'INTERNATIONAL_ACCESSIBILITY'
);
create type public.fit_assessment as enum (
  'STRONG_ALIGNMENT',
  'ALIGNMENT',
  'MIXED',
  'MISALIGNMENT',
  'UNKNOWN'
);
create type public.fit_confidence as enum ('HIGH', 'MEDIUM', 'LOW');
create type public.fit_coverage as enum (
  'SUFFICIENT',
  'PARTIAL',
  'INSUFFICIENT'
);
create type public.fit_inference_category as enum (
  'DETERMINISTIC',
  'REVIEWED_MAPPING',
  'RULE',
  'MODEL',
  'HYBRID'
);
create type public.fit_reason_direction as enum (
  'SUPPORTING',
  'CONTRADICTING',
  'LIMITING'
);
create type public.fit_importance as enum (
  'REQUIRED',
  'STRONGLY_PREFERRED',
  'PREFERRED',
  'NEUTRAL',
  'UNSPECIFIED'
);
create type public.fit_definition_status as enum (
  'DRAFT',
  'VERIFIED',
  'RETIRED'
);
create type public.fit_intent_origin as enum (
  'PHASE2_INTERPRETATION',
  'PHASE3_DECLARATION'
);
create type public.fit_importance_basis as enum (
  'STRUCTURED_STUDENT_DECLARATION',
  'NORMALIZED_STUDENT_LANGUAGE',
  'REVIEWED_INTERPRETATION'
);
create type public.fit_financial_constraint_semantics as enum (
  'HARD_TOTAL_COST_CEILING',
  'PREFERRED_TOTAL_COST',
  'HARD_TUITION_CEILING',
  'PREFERRED_TUITION',
  'AVAILABLE_FUNDING'
);
create type public.fit_reason_family as enum (
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
  'CONTEXT_APPLICABILITY_UNKNOWN',
  'DIRECTIONAL_SUPPORT',
  'DIRECTIONAL_CONTRADICTION',
  'REQUIRED_CONSTRAINT'
);
create type public.fit_input_availability as enum (
  'INCLUDED',
  'NOT_SUPPLIED',
  'INCOMPLETE',
  'UNKNOWN_SOURCE',
  'STALE_SOURCE',
  'SOURCE_CONFLICT',
  'INAPPLICABLE'
);
create type public.fit_evaluation_state as enum ('BUILDING', 'COMPLETED');
create type public.fit_input_policy_disposition as enum ('ALLOWED', 'FORBIDDEN');
create type public.fit_input_requirement as enum ('REQUIRED', 'OPTIONAL');
create type public.fit_claim_authority as enum (
  'OFFICIAL_REGULATORY',
  'OFFICIAL_INSTITUTIONAL',
  'REVIEWED_STRUCTURED',
  'APPLICABLE_OBSERVATIONAL',
  'MODEL_GENERATED'
);
create type public.fit_claim_workflow_status as enum (
  'PROPOSED',
  'VERIFIED',
  'REJECTED',
  'RETIRED'
);
create type public.fit_financial_scope as enum (
  'COMPONENT',
  'PARTIAL_TOTAL',
  'TOTAL_COST'
);
create type public.fit_financial_period as enum (
  'MONTH',
  'ACADEMIC_YEAR',
  'CALENDAR_YEAR',
  'PROGRAM_DURATION'
);
create type public.fit_financial_basis as enum (
  'GROSS',
  'NET_OF_VERIFIED_FUNDING'
);

create table public.fit_contract_releases (
  contract_release_id uuid primary key default extensions.gen_random_uuid(),
  release_code text not null unique,
  specification_version text not null,
  upstream_contract_version text not null,
  specification_digest text not null,
  status public.fit_definition_status not null default 'DRAFT',
  reviewed_by text,
  reviewed_at timestamptz,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  constraint fit_contract_releases_code_format
    check (release_code ~ '^fit-v[0-9]+\.[0-9]+$'),
  constraint fit_contract_releases_spec_version
    check (specification_version ~ '^v[0-9]+\.[0-9]+$'),
  constraint fit_contract_releases_upstream
    check (upstream_contract_version = 'phase2-eligibility-v0.1'),
  constraint fit_contract_releases_digest
    check (specification_digest ~ '^[a-f0-9]{64}$'),
  constraint fit_contract_releases_review_state
    check (
      (
        status = 'DRAFT'
        and reviewed_by is null
        and reviewed_at is null
        and retired_at is null
        and retirement_reason is null
      )
      or (
        status = 'VERIFIED'
        and nullif(btrim(reviewed_by), '') is not null
        and reviewed_at is not null
        and retired_at is null
        and retirement_reason is null
      )
      or (
        status = 'RETIRED'
        and nullif(btrim(reviewed_by), '') is not null
        and reviewed_at is not null
        and retired_at is not null
        and nullif(btrim(retirement_reason), '') is not null
      )
    )
);

-- One authoritative identity registry covers both permitted and prohibited
-- semantic source classes. Methods authorize these identities independently.
create table public.fit_semantic_source_classes (
  source_class_code text primary key,
  owner_layer text not null,
  fit_permitted boolean not null,
  description text not null,
  created_at timestamptz not null default now(),
  constraint fit_source_class_code_format
    check (source_class_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint fit_source_class_owner
    check (owner_layer in ('PHASE1', 'PHASE2', 'PHASE3', 'PROHIBITED')),
  constraint fit_source_class_prohibited_owner
    check ((owner_layer = 'PROHIBITED') = (not fit_permitted)),
  constraint fit_source_class_description
    check (btrim(description) <> '')
);

create table public.fit_evaluator_builds (
  evaluator_build_id uuid primary key default extensions.gen_random_uuid(),
  contract_release_id uuid not null
    references public.fit_contract_releases(contract_release_id)
    on delete restrict,
  evaluator_name text not null,
  evaluator_version text not null,
  build_hash text not null,
  status public.fit_definition_status not null default 'DRAFT',
  reviewed_by text,
  reviewed_at timestamptz,
  verification_evidence_id uuid
    references public.evidence_items(evidence_id) on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  constraint fit_evaluator_builds_identity check (
    btrim(evaluator_name) <> ''
    and btrim(evaluator_version) <> ''
    and build_hash ~ '^[a-f0-9]{64}$'
  ),
  constraint fit_evaluator_builds_review_state check (
    (
      status = 'DRAFT'
      and reviewed_by is null
      and reviewed_at is null
      and verification_evidence_id is null
      and retired_at is null
      and retirement_reason is null
    )
    or (
      status = 'VERIFIED'
      and nullif(btrim(reviewed_by), '') is not null
      and reviewed_at is not null
      and verification_evidence_id is not null
      and retired_at is null
      and retirement_reason is null
    )
    or (
      status = 'RETIRED'
      and nullif(btrim(reviewed_by), '') is not null
      and reviewed_at is not null
      and verification_evidence_id is not null
      and retired_at is not null
      and nullif(btrim(retirement_reason), '') is not null
    )
  ),
  unique (contract_release_id, evaluator_name, evaluator_version, build_hash)
);

create unique index fit_contract_one_active_verified_idx
  on public.fit_contract_releases ((status))
  where status = 'VERIFIED';

create table public.fit_dimension_methods (
  method_id uuid primary key default extensions.gen_random_uuid(),
  contract_release_id uuid not null
    references public.fit_contract_releases(contract_release_id)
    on delete restrict,
  dimension public.fit_dimension not null,
  method_code text not null,
  method_version integer not null,
  status public.fit_definition_status not null default 'DRAFT',
  inference_category public.fit_inference_category not null,
  materiality_contract jsonb not null,
  permits_strong_alignment boolean not null default false,
  reviewed_by text,
  reviewed_at timestamptz,
  verification_evidence_id uuid
    references public.evidence_items(evidence_id) on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fit_dimension_methods_code_format
    check (method_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint fit_dimension_methods_version_positive
    check (method_version > 0),
  constraint fit_dimension_methods_materiality_object
    check (
      jsonb_typeof(materiality_contract) = 'object'
      and materiality_contract ? 'coreQuestion'
      and materiality_contract ? 'materialityRules'
      and jsonb_typeof(materiality_contract -> 'materialityRules') = 'array'
    ),
  constraint fit_dimension_methods_review_state
    check (
      (
        status = 'DRAFT'
        and reviewed_by is null
        and reviewed_at is null
        and verification_evidence_id is null
        and retired_at is null
        and retirement_reason is null
      )
      or (
        status = 'VERIFIED'
        and nullif(btrim(reviewed_by), '') is not null
        and reviewed_at is not null
        and verification_evidence_id is not null
        and retired_at is null
        and retirement_reason is null
      )
      or (
        status = 'RETIRED'
        and nullif(btrim(reviewed_by), '') is not null
        and reviewed_at is not null
        and verification_evidence_id is not null
        and retired_at is not null
        and nullif(btrim(retirement_reason), '') is not null
      )
    ),
  unique (
    contract_release_id,
    dimension,
    method_code,
    method_version
  ),
  unique (method_id, contract_release_id)
);

create unique index fit_dimension_one_active_verified_method_idx
  on public.fit_dimension_methods (contract_release_id, dimension)
  where status = 'VERIFIED';

create table public.fit_method_source_class_policies (
  method_id uuid not null
    references public.fit_dimension_methods(method_id) on delete restrict,
  source_class_code text not null
    references public.fit_semantic_source_classes(source_class_code)
    on delete restrict,
  disposition public.fit_input_policy_disposition not null,
  created_at timestamptz not null default now(),
  primary key (method_id, source_class_code)
);

create table public.fit_mapping_relation_definitions (
  relation_code text primary key,
  relation_domain text not null,
  description text not null,
  created_at timestamptz not null default now(),
  constraint fit_mapping_relation_code_format
    check (relation_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint fit_mapping_relation_domain
    check (relation_domain in ('CATALOG', 'STUDENT', 'FIT_CONTEXT')),
  constraint fit_mapping_relation_description
    check (btrim(description) <> '')
);

create table public.fit_method_mapping_relation_policies (
  method_id uuid not null
    references public.fit_dimension_methods(method_id) on delete restrict,
  relation_code text not null
    references public.fit_mapping_relation_definitions(relation_code)
    on delete restrict,
  allowed_assessments public.fit_assessment[] not null,
  permits_strong_alignment boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (method_id, relation_code),
  constraint fit_mapping_relation_policy_assessments check (
    cardinality(allowed_assessments) > 0
    and array_position(allowed_assessments, null) is null
    and (
      not permits_strong_alignment
      or 'STRONG_ALIGNMENT' = any(allowed_assessments)
    )
  )
);

create table public.fit_signal_types (
  signal_type_id uuid primary key default extensions.gen_random_uuid(),
  method_id uuid not null
    references public.fit_dimension_methods(method_id) on delete restrict,
  signal_code text not null,
  direction public.fit_reason_direction not null,
  material boolean not null,
  allowed_inference_categories public.fit_inference_category[] not null,
  permits_strong_alignment boolean not null default false,
  description text not null,
  created_at timestamptz not null default now(),
  unique (method_id, signal_code),
  unique (signal_type_id, method_id),
  constraint fit_signal_types_code_format
    check (signal_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint fit_signal_types_inference check (
    cardinality(allowed_inference_categories) > 0
    and array_position(allowed_inference_categories, null) is null
  ),
  constraint fit_signal_types_strong_shape check (
    not permits_strong_alignment
    or (material and direction = 'SUPPORTING')
  ),
  constraint fit_signal_types_description check (btrim(description) <> '')
);

create table public.fit_method_input_policies (
  input_policy_id uuid primary key default extensions.gen_random_uuid(),
  method_id uuid not null
    references public.fit_dimension_methods(method_id) on delete restrict,
  input_domain text not null,
  field_name text not null,
  disposition public.fit_input_policy_disposition not null,
  requirement public.fit_input_requirement not null,
  acceptable_authority public.fit_claim_authority,
  acceptable_claim_status public.fit_claim_workflow_status,
  permits_deterministic_use boolean not null,
  permits_model_use boolean not null,
  created_at timestamptz not null default now(),
  constraint fit_method_input_policies_domain_format
    check (input_domain ~ '^[A-Z][A-Z0-9_]*$'),
  constraint fit_method_input_policies_field_format
    check (field_name ~ '^[A-Z][A-Z0-9_]*$'),
  constraint fit_method_input_policies_forbidden_shape
    check (
      disposition = 'ALLOWED'
      or (
        requirement = 'OPTIONAL'
        and acceptable_authority is null
        and acceptable_claim_status is null
        and not permits_deterministic_use
        and not permits_model_use
      )
    ),
  constraint fit_method_input_policies_authority_state
    check (
      acceptable_authority is null
      or acceptable_claim_status is not null
    ),
  unique (method_id, input_domain, field_name)
);

create table public.fit_method_program_field_policies (
  method_id uuid not null
    references public.fit_dimension_methods(method_id) on delete restrict,
  input_policy_id uuid not null
    references public.fit_method_input_policies(input_policy_id)
    on delete restrict,
  record_type public.catalog_record_type not null,
  field_name text not null,
  created_at timestamptz not null default now(),
  primary key (method_id, input_policy_id, record_type, field_name),
  constraint fit_program_field_policy_name
    check (field_name ~ '^[a-z][a-z0-9_]*$')
);

create table public.fit_reason_definitions (
  reason_definition_id uuid primary key default extensions.gen_random_uuid(),
  contract_release_id uuid not null
    references public.fit_contract_releases(contract_release_id)
    on delete restrict,
  reason_code text not null,
  dimension public.fit_dimension,
  reason_family public.fit_reason_family not null,
  direction public.fit_reason_direction not null,
  allowed_assessments public.fit_assessment[] not null,
  description text not null,
  status public.fit_definition_status not null default 'DRAFT',
  reviewed_by text,
  reviewed_at timestamptz,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fit_reason_definitions_code_format
    check (reason_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint fit_reason_definitions_assessments
    check (
      cardinality(allowed_assessments) > 0
      and array_position(allowed_assessments, null) is null
    ),
  constraint fit_reason_definitions_description
    check (btrim(description) <> ''),
  constraint fit_reason_definitions_review_state
    check (
      (
        status = 'DRAFT'
        and reviewed_by is null
        and reviewed_at is null
        and retired_at is null
        and retirement_reason is null
      )
      or (
        status = 'VERIFIED'
        and nullif(btrim(reviewed_by), '') is not null
        and reviewed_at is not null
        and retired_at is null
        and retirement_reason is null
      )
      or (
        status = 'RETIRED'
        and nullif(btrim(reviewed_by), '') is not null
        and reviewed_at is not null
        and retired_at is not null
        and nullif(btrim(retirement_reason), '') is not null
      )
    ),
  unique (contract_release_id, reason_code)
);

create table public.fit_financial_normalization_methods (
  normalization_method_id uuid primary key default extensions.gen_random_uuid(),
  contract_release_id uuid not null
    references public.fit_contract_releases(contract_release_id)
    on delete restrict,
  method_code text not null,
  method_version integer not null,
  status public.fit_definition_status not null default 'DRAFT',
  source_scope public.fit_financial_scope not null,
  target_scope public.fit_financial_scope not null,
  source_period public.fit_financial_period not null,
  target_period public.fit_financial_period not null,
  source_basis public.fit_financial_basis not null,
  target_basis public.fit_financial_basis not null,
  source_currency char(3),
  target_currency char(3),
  normalization_contract jsonb not null,
  reviewed_by text,
  reviewed_at timestamptz,
  verification_evidence_id uuid
    references public.evidence_items(evidence_id) on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fit_financial_normalization_code_format
    check (method_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint fit_financial_normalization_version
    check (method_version > 0),
  constraint fit_financial_normalization_currency
    check (
      (source_currency is null or source_currency ~ '^[A-Z]{3}$')
      and (target_currency is null or target_currency ~ '^[A-Z]{3}$')
    ),
  constraint fit_financial_normalization_contract_object
    check (jsonb_typeof(normalization_contract) = 'object'),
  constraint fit_financial_normalization_review_state
    check (
      (
        status = 'DRAFT'
        and reviewed_by is null
        and reviewed_at is null
        and verification_evidence_id is null
        and retired_at is null
        and retirement_reason is null
      )
      or (
        status = 'VERIFIED'
        and nullif(btrim(reviewed_by), '') is not null
        and reviewed_at is not null
        and verification_evidence_id is not null
        and retired_at is null
        and retirement_reason is null
      )
      or (
        status = 'RETIRED'
        and nullif(btrim(reviewed_by), '') is not null
        and reviewed_at is not null
        and verification_evidence_id is not null
        and retired_at is not null
        and nullif(btrim(retirement_reason), '') is not null
      )
    ),
  unique (contract_release_id, method_code, method_version)
);

create index fit_methods_release_dimension_idx
  on public.fit_dimension_methods (contract_release_id, dimension, status);
create index fit_input_policies_method_idx
  on public.fit_method_input_policies (method_id, disposition);
create index fit_method_source_classes_method_idx
  on public.fit_method_source_class_policies (method_id, disposition);
create index fit_method_relations_method_idx
  on public.fit_method_mapping_relation_policies (method_id);
create index fit_signal_types_method_idx
  on public.fit_signal_types (method_id, direction, material);
create index fit_reasons_release_dimension_idx
  on public.fit_reason_definitions (
    contract_release_id,
    dimension,
    status
  );
create index fit_financial_methods_release_idx
  on public.fit_financial_normalization_methods (
    contract_release_id,
    status
  );

create trigger fit_dimension_methods_set_updated_at
before update on public.fit_dimension_methods
for each row execute function public.set_updated_at();
create trigger fit_reason_definitions_set_updated_at
before update on public.fit_reason_definitions
for each row execute function public.set_updated_at();
create trigger fit_financial_methods_set_updated_at
before update on public.fit_financial_normalization_methods
for each row execute function public.set_updated_at();

create or replace function public.guard_fit_static_semantic_registry()
returns trigger
language plpgsql
as $$
declare
  v_old jsonb;
  v_new jsonb;
begin
  if tg_op = 'DELETE' then
    raise exception using
      errcode = '55000',
      message = format('%s is append-only', tg_table_name);
  end if;
  v_old := to_jsonb(old);
  v_new := to_jsonb(new);
  if tg_table_name = 'fit_semantic_source_classes'
     and (
       v_new ->> 'source_class_code' is distinct from
         v_old ->> 'source_class_code'
       or v_new ->> 'owner_layer' is distinct from
         v_old ->> 'owner_layer'
       or v_new ->> 'fit_permitted' is distinct from
         v_old ->> 'fit_permitted'
       or v_new ->> 'description' is distinct from
         v_old ->> 'description'
     ) then
    raise exception using
      errcode = '55000',
      message = 'Semantic source class identity and meaning are immutable';
  elsif tg_table_name = 'fit_mapping_relation_definitions'
     and v_new is distinct from v_old then
    raise exception using
      errcode = '55000',
      message = 'Mapping relation identity and meaning are immutable';
  end if;
  return new;
end;
$$;

create trigger fit_semantic_source_classes_immutable
before update or delete on public.fit_semantic_source_classes
for each row execute function public.guard_fit_static_semantic_registry();
create trigger fit_mapping_relation_definitions_immutable
before update or delete on public.fit_mapping_relation_definitions
for each row execute function public.guard_fit_static_semantic_registry();

create or replace function public.guard_fit_registry_history()
returns trigger
language plpgsql
as $$
declare
  v_old jsonb;
  v_new jsonb;
begin
  if tg_op = 'DELETE' then
    raise exception '% definitions are historical and cannot be deleted',
      tg_table_name;
  end if;

  v_old := to_jsonb(old);
  v_new := to_jsonb(new);

  if tg_table_name = 'fit_contract_releases'
     and (
       v_new ->> 'release_code' is distinct from
         v_old ->> 'release_code'
       or v_new ->> 'specification_version' is distinct from
         v_old ->> 'specification_version'
       or v_new ->> 'upstream_contract_version' is distinct from
         v_old ->> 'upstream_contract_version'
       or v_new ->> 'specification_digest' is distinct from
         v_old ->> 'specification_digest'
     ) then
    raise exception 'Fit contract release identity is immutable';
  elsif tg_table_name = 'fit_dimension_methods'
     and (
       v_new ->> 'contract_release_id' is distinct from
         v_old ->> 'contract_release_id'
       or v_new ->> 'dimension' is distinct from
         v_old ->> 'dimension'
       or v_new ->> 'method_code' is distinct from
         v_old ->> 'method_code'
       or v_new ->> 'method_version' is distinct from
         v_old ->> 'method_version'
     ) then
    raise exception 'Fit dimension method identity is immutable';
  elsif tg_table_name = 'fit_reason_definitions'
     and (
       v_new ->> 'contract_release_id' is distinct from
         v_old ->> 'contract_release_id'
       or v_new ->> 'reason_code' is distinct from
         v_old ->> 'reason_code'
     ) then
    raise exception 'Fit reason identity is immutable';
  elsif tg_table_name = 'fit_financial_normalization_methods'
     and (
       v_new ->> 'contract_release_id' is distinct from
         v_old ->> 'contract_release_id'
       or v_new ->> 'method_code' is distinct from
         v_old ->> 'method_code'
       or v_new ->> 'method_version' is distinct from
         v_old ->> 'method_version'
     ) then
    raise exception 'Fit financial normalization identity is immutable';
  elsif tg_table_name = 'fit_evaluator_builds'
     and (
       v_new ->> 'contract_release_id' is distinct from
         v_old ->> 'contract_release_id'
       or v_new ->> 'evaluator_name' is distinct from
         v_old ->> 'evaluator_name'
       or v_new ->> 'evaluator_version' is distinct from
         v_old ->> 'evaluator_version'
       or v_new ->> 'build_hash' is distinct from
         v_old ->> 'build_hash'
     ) then
    raise exception 'Fit evaluator build identity is immutable';
  end if;

  if new.status is distinct from old.status
     and current_setting('app.fit_registry_controlled_write', true)
       is distinct from 'on' then
    raise exception 'Use controlled Fit registry verification or retirement';
  end if;

  if old.status in ('VERIFIED', 'RETIRED')
     and current_setting('app.fit_registry_controlled_write', true)
       is distinct from 'on'
     and (v_new - 'updated_at') is distinct from (v_old - 'updated_at') then
    raise exception 'Verified Fit definitions are append-only';
  end if;

  if old.status = 'RETIRED' then
    raise exception 'Retired Fit definitions are immutable';
  end if;
  return new;
end;
$$;

create trigger fit_contract_releases_history_guard
before update or delete on public.fit_contract_releases
for each row execute function public.guard_fit_registry_history();
create trigger fit_dimension_methods_history_guard
before update or delete on public.fit_dimension_methods
for each row execute function public.guard_fit_registry_history();
create trigger fit_reason_definitions_history_guard
before update or delete on public.fit_reason_definitions
for each row execute function public.guard_fit_registry_history();
create trigger fit_financial_methods_history_guard
before update or delete on public.fit_financial_normalization_methods
for each row execute function public.guard_fit_registry_history();
create trigger fit_evaluator_builds_history_guard
before update or delete on public.fit_evaluator_builds
for each row execute function public.guard_fit_registry_history();

create or replace function public.guard_fit_input_policy_history()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_method_id uuid;
  v_status public.fit_definition_status;
  v_old jsonb;
  v_new jsonb;
begin
  if tg_op = 'INSERT' then
    v_method_id := new.method_id;
  else
    v_method_id := old.method_id;
  end if;
  select status into v_status
  from public.fit_dimension_methods
  where method_id = v_method_id;

  if v_status in ('VERIFIED', 'RETIRED') then
    raise exception 'Input policies for verified Fit methods are append-only';
  end if;
  if tg_op = 'UPDATE' then
    v_old := to_jsonb(old);
    v_new := to_jsonb(new);
    if (
      v_new ->> 'method_id' is distinct from v_old ->> 'method_id'
      or (
        tg_table_name = 'fit_method_input_policies'
        and v_new ->> 'input_policy_id' is distinct from
          v_old ->> 'input_policy_id'
      )
      or (
        tg_table_name = 'fit_method_source_class_policies'
        and v_new ->> 'source_class_code' is distinct from
          v_old ->> 'source_class_code'
      )
      or (
        tg_table_name = 'fit_method_mapping_relation_policies'
        and v_new ->> 'relation_code' is distinct from
          v_old ->> 'relation_code'
      )
      or (
        tg_table_name = 'fit_signal_types'
        and v_new ->> 'signal_type_id' is distinct from
          v_old ->> 'signal_type_id'
      )
      or (
        tg_table_name = 'fit_method_program_field_policies'
        and (
          v_new ->> 'input_policy_id' is distinct from
            v_old ->> 'input_policy_id'
          or v_new ->> 'record_type' is distinct from
            v_old ->> 'record_type'
          or v_new ->> 'field_name' is distinct from
            v_old ->> 'field_name'
        )
      )
    ) then
      raise exception using
        errcode = '55000',
        message = format('%s identity is immutable', tg_table_name);
    end if;
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create trigger fit_method_input_policies_history_guard
before insert or update or delete on public.fit_method_input_policies
for each row execute function public.guard_fit_input_policy_history();
create trigger fit_method_source_classes_history_guard
before insert or update or delete on public.fit_method_source_class_policies
for each row execute function public.guard_fit_input_policy_history();
create trigger fit_method_mapping_relations_history_guard
before insert or update or delete on public.fit_method_mapping_relation_policies
for each row execute function public.guard_fit_input_policy_history();
create trigger fit_signal_types_history_guard
before insert or update or delete on public.fit_signal_types
for each row execute function public.guard_fit_input_policy_history();
create trigger fit_method_program_fields_history_guard
before insert or update or delete on public.fit_method_program_field_policies
for each row execute function public.guard_fit_input_policy_history();

create or replace function public.verify_fit_definition(
  p_registry text,
  p_definition_id uuid,
  p_reviewed_by text,
  p_verification_evidence_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_prior_setting text;
begin
  if nullif(btrim(p_reviewed_by), '') is null then
    raise exception 'Reviewer identity is required';
  end if;
  if p_registry in ('METHOD', 'FINANCIAL_NORMALIZATION', 'EVALUATOR_BUILD')
     and not exists (
       select 1
       from public.evidence_items
       where evidence_id = p_verification_evidence_id
     ) then
    raise exception 'Method verification requires existing review evidence';
  end if;

  v_prior_setting :=
    current_setting('app.fit_registry_controlled_write', true);
  perform set_config('app.fit_registry_controlled_write', 'on', true);

  case p_registry
    when 'CONTRACT_RELEASE' then
      if p_verification_evidence_id is not null then
        raise exception 'Contract release approval uses its specification digest';
      end if;
      update public.fit_contract_releases
      set status = 'VERIFIED',
          reviewed_by = p_reviewed_by,
          reviewed_at = now()
      where contract_release_id = p_definition_id
        and status = 'DRAFT';
    when 'METHOD' then
      if not exists (
        select 1
        from public.fit_dimension_methods method
        join public.fit_contract_releases release
          using (contract_release_id)
        where method.method_id = p_definition_id
          and method.status = 'DRAFT'
          and release.status = 'VERIFIED'
          and release.retired_at is null
      ) then
        raise exception using
          errcode = '23514',
          message = 'Method verification requires an active VERIFIED parent contract';
      end if;
      if (
        select count(*)
        from public.fit_method_source_class_policies
        where method_id = p_definition_id
      ) <> (
        select count(*) from public.fit_semantic_source_classes
      ) or exists (
        select 1
        from public.fit_method_source_class_policies policy
        join public.fit_semantic_source_classes source_class
          using (source_class_code)
        where policy.method_id = p_definition_id
          and (
            (policy.disposition = 'ALLOWED' and not source_class.fit_permitted)
            or (not source_class.fit_permitted
              and policy.disposition <> 'FORBIDDEN')
          )
      ) then
        raise exception using
          errcode = '23514',
          message = 'Method source-class policies are incomplete or inconsistent';
      end if;
      if not exists (
        select 1 from public.fit_method_input_policies
        where method_id = p_definition_id
          and disposition = 'ALLOWED'
          and requirement = 'REQUIRED'
      ) then
        raise exception using
          errcode = '23514',
          message = 'Method requires at least one ALLOWED required input policy';
      end if;
      if exists (
        select 1
        from public.fit_method_input_policies policy
        where policy.method_id = p_definition_id
          and policy.disposition = 'ALLOWED'
          and policy.input_domain in (
            'PROGRAM_COURSES', 'PROGRAM_COSTS', 'PROGRAM_VERSIONS'
          )
          and not exists (
            select 1
            from public.fit_method_program_field_policies field_policy
            where field_policy.method_id = policy.method_id
              and field_policy.input_policy_id = policy.input_policy_id
          )
      ) then
        raise exception using
          errcode = '23514',
          message = 'Program input policies require exact record/field allowlists';
      end if;
      if not exists (
        select 1 from public.fit_signal_types
        where method_id = p_definition_id
      ) or exists (
        select 1
        from public.fit_signal_types signal_type
        join public.fit_dimension_methods method using (method_id)
        where signal_type.method_id = p_definition_id
          and method.inference_category <> 'HYBRID'
          and exists (
            select 1
            from unnest(signal_type.allowed_inference_categories)
              inference_category
            where inference_category <> method.inference_category
          )
      ) then
        raise exception using
          errcode = '23514',
          message = 'Signal inference categories are incompatible with method inference';
      end if;
      if exists (
        select 1
        from public.fit_dimension_methods method
        where method.method_id = p_definition_id
          and (
            (
              method.permits_strong_alignment
              and (
                not method.materiality_contract ? 'strongAlignmentContract'
                or jsonb_typeof(
                  method.materiality_contract -> 'strongAlignmentContract'
                ) <> 'object'
                or method.materiality_contract #>>
                  '{strongAlignmentContract,qualificationMode}'
                  <> 'DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH'
                or method.materiality_contract #>
                  '{strongAlignmentContract,requiresAuthoritativeIntent}'
                  <> 'true'::jsonb
                or method.materiality_contract #>
                  '{strongAlignmentContract,requiresAuthoritativeProgramEvidence}'
                  <> 'true'::jsonb
                or method.materiality_contract #>
                  '{strongAlignmentContract,forbidsMaterialContradiction}'
                  <> 'true'::jsonb
                or method.materiality_contract #>
                  '{strongAlignmentContract,modelAlonePermitted}'
                  <> 'false'::jsonb
                or not exists (
                  select 1 from public.fit_signal_types signal_type
                  where signal_type.method_id = method.method_id
                    and signal_type.permits_strong_alignment
                )
              )
            )
            or (
              not method.permits_strong_alignment
              and exists (
                select 1 from public.fit_signal_types signal_type
                where signal_type.method_id = method.method_id
                  and signal_type.permits_strong_alignment
              )
            )
          )
      ) then
        raise exception using
          errcode = '23514',
          message = 'STRONG_ALIGNMENT method and signal configuration is inconsistent';
      end if;
      if exists (
        select 1
        from public.fit_method_mapping_relation_policies relation_policy
        where relation_policy.method_id = p_definition_id
          and (
            cardinality(relation_policy.allowed_assessments) = 0
            or (
              relation_policy.permits_strong_alignment
              and not 'STRONG_ALIGNMENT' =
                any(relation_policy.allowed_assessments)
            )
          )
      ) then
        raise exception using
          errcode = '23514',
          message = 'Mapping relation policy assessment authority is inconsistent';
      end if;
      update public.fit_dimension_methods
      set status = 'VERIFIED',
          reviewed_by = p_reviewed_by,
          reviewed_at = now(),
          verification_evidence_id = p_verification_evidence_id
      where method_id = p_definition_id
        and status = 'DRAFT';
    when 'REASON' then
      if p_verification_evidence_id is not null then
        raise exception 'Reason approval is governed by the contract release';
      end if;
      update public.fit_reason_definitions
      set status = 'VERIFIED',
          reviewed_by = p_reviewed_by,
          reviewed_at = now()
      where reason_definition_id = p_definition_id
        and status = 'DRAFT';
    when 'FINANCIAL_NORMALIZATION' then
      update public.fit_financial_normalization_methods
      set status = 'VERIFIED',
          reviewed_by = p_reviewed_by,
          reviewed_at = now(),
          verification_evidence_id = p_verification_evidence_id
      where normalization_method_id = p_definition_id
        and status = 'DRAFT';
    when 'EVALUATOR_BUILD' then
      update public.fit_evaluator_builds
      set status = 'VERIFIED',
          reviewed_by = p_reviewed_by,
          reviewed_at = now(),
          verification_evidence_id = p_verification_evidence_id
      where evaluator_build_id = p_definition_id
        and status = 'DRAFT';
    else
      raise exception 'Unknown Fit registry %', p_registry;
  end case;

  if not found then
    raise exception 'A draft % definition is required', p_registry;
  end if;
  perform set_config(
    'app.fit_registry_controlled_write',
    coalesce(v_prior_setting, ''),
    true
  );
end;
$$;

create or replace function public.retire_fit_definition(
  p_registry text,
  p_definition_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_prior_setting text;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Retirement reason is required';
  end if;
  v_prior_setting :=
    current_setting('app.fit_registry_controlled_write', true);
  perform set_config('app.fit_registry_controlled_write', 'on', true);

  case p_registry
    when 'CONTRACT_RELEASE' then
      update public.fit_contract_releases
      set status = 'RETIRED',
          retired_at = now(),
          retirement_reason = p_reason
      where contract_release_id = p_definition_id
        and status = 'VERIFIED';
    when 'METHOD' then
      update public.fit_dimension_methods
      set status = 'RETIRED',
          retired_at = now(),
          retirement_reason = p_reason
      where method_id = p_definition_id
        and status = 'VERIFIED';
    when 'REASON' then
      update public.fit_reason_definitions
      set status = 'RETIRED',
          retired_at = now(),
          retirement_reason = p_reason
      where reason_definition_id = p_definition_id
        and status = 'VERIFIED';
    when 'FINANCIAL_NORMALIZATION' then
      update public.fit_financial_normalization_methods
      set status = 'RETIRED',
          retired_at = now(),
          retirement_reason = p_reason
      where normalization_method_id = p_definition_id
        and status = 'VERIFIED';
    when 'EVALUATOR_BUILD' then
      update public.fit_evaluator_builds
      set status = 'RETIRED',
          retired_at = now(),
          retirement_reason = p_reason
      where evaluator_build_id = p_definition_id
        and status = 'VERIFIED';
    else
      raise exception 'Unknown Fit registry %', p_registry;
  end case;

  if not found then
    raise exception 'A verified % definition is required', p_registry;
  end if;
  perform set_config(
    'app.fit_registry_controlled_write',
    coalesce(v_prior_setting, ''),
    true
  );
end;
$$;

revoke all on function public.verify_fit_definition(
  text,
  uuid,
  text,
  uuid
) from public;
revoke all on function public.retire_fit_definition(
  text,
  uuid,
  text
) from public;
grant execute on function public.verify_fit_definition(
  text,
  uuid,
  text,
  uuid
) to service_role;
grant execute on function public.retire_fit_definition(
  text,
  uuid,
  text
) to service_role;

create trigger fit_contract_releases_audit
after insert or update or delete on public.fit_contract_releases
for each row execute function public.audit_phase2_change('contract_release_id');
create trigger fit_dimension_methods_audit
after insert or update or delete on public.fit_dimension_methods
for each row execute function public.audit_phase2_change('method_id');
create trigger fit_method_input_policies_audit
after insert or update or delete on public.fit_method_input_policies
for each row execute function public.audit_phase2_change('input_policy_id');
create trigger fit_reason_definitions_audit
after insert or update or delete on public.fit_reason_definitions
for each row execute function public.audit_phase2_change('reason_definition_id');
create trigger fit_financial_methods_audit
after insert or update or delete
on public.fit_financial_normalization_methods
for each row execute function public.audit_phase2_change(
  'normalization_method_id'
);
create trigger fit_evaluator_builds_audit
after insert or update or delete on public.fit_evaluator_builds
for each row execute function public.audit_phase2_change('evaluator_build_id');

alter table public.fit_contract_releases enable row level security;
alter table public.fit_semantic_source_classes enable row level security;
alter table public.fit_evaluator_builds enable row level security;
alter table public.fit_dimension_methods enable row level security;
alter table public.fit_method_source_class_policies enable row level security;
alter table public.fit_mapping_relation_definitions enable row level security;
alter table public.fit_method_mapping_relation_policies enable row level security;
alter table public.fit_signal_types enable row level security;
alter table public.fit_method_input_policies enable row level security;
alter table public.fit_method_program_field_policies enable row level security;
alter table public.fit_reason_definitions enable row level security;
alter table public.fit_financial_normalization_methods
  enable row level security;

create policy fit_contract_releases_public_read
  on public.fit_contract_releases for select to public
  using (status = 'VERIFIED' and retired_at is null);
create policy fit_semantic_source_classes_public_read
  on public.fit_semantic_source_classes for select to public using (true);
create policy fit_evaluator_builds_public_read
  on public.fit_evaluator_builds for select to public
  using (status = 'VERIFIED' and retired_at is null);
create policy fit_mapping_relation_definitions_public_read
  on public.fit_mapping_relation_definitions for select to public using (true);
create policy fit_dimension_methods_public_read
  on public.fit_dimension_methods for select to public
  using (
    status = 'VERIFIED'
    and retired_at is null
    and exists (
      select 1
      from public.fit_contract_releases release
      where release.contract_release_id =
        fit_dimension_methods.contract_release_id
        and release.status = 'VERIFIED'
        and release.retired_at is null
    )
  );
create policy fit_method_input_policies_public_read
  on public.fit_method_input_policies for select to public
  using (
    exists (
      select 1
      from public.fit_dimension_methods method
      join public.fit_contract_releases release
        using (contract_release_id)
      where method.method_id = fit_method_input_policies.method_id
        and method.status = 'VERIFIED'
        and method.retired_at is null
        and release.status = 'VERIFIED'
        and release.retired_at is null
    )
  );
create policy fit_method_program_fields_public_read
  on public.fit_method_program_field_policies for select to public
  using (
    exists (
      select 1 from public.fit_dimension_methods method
      where method.method_id =
        fit_method_program_field_policies.method_id
        and method.status = 'VERIFIED'
        and method.retired_at is null
    )
  );
create policy fit_method_source_classes_public_read
  on public.fit_method_source_class_policies for select to public
  using (
    exists (
      select 1 from public.fit_dimension_methods method
      where method.method_id = fit_method_source_class_policies.method_id
        and method.status = 'VERIFIED'
        and method.retired_at is null
    )
  );
create policy fit_method_mapping_relations_public_read
  on public.fit_method_mapping_relation_policies for select to public
  using (
    exists (
      select 1 from public.fit_dimension_methods method
      where method.method_id = fit_method_mapping_relation_policies.method_id
        and method.status = 'VERIFIED'
        and method.retired_at is null
    )
  );
create policy fit_signal_types_public_read
  on public.fit_signal_types for select to public
  using (
    exists (
      select 1 from public.fit_dimension_methods method
      where method.method_id = fit_signal_types.method_id
        and method.status = 'VERIFIED'
        and method.retired_at is null
    )
  );
create policy fit_reason_definitions_public_read
  on public.fit_reason_definitions for select to public
  using (
    status = 'VERIFIED'
    and retired_at is null
    and exists (
      select 1
      from public.fit_contract_releases release
      where release.contract_release_id =
        fit_reason_definitions.contract_release_id
        and release.status = 'VERIFIED'
        and release.retired_at is null
    )
  );
create policy fit_financial_normalization_methods_public_read
  on public.fit_financial_normalization_methods for select to public
  using (
    status = 'VERIFIED'
    and retired_at is null
    and exists (
      select 1
      from public.fit_contract_releases release
      where release.contract_release_id =
        fit_financial_normalization_methods.contract_release_id
        and release.status = 'VERIFIED'
        and release.retired_at is null
    )
  );

insert into public.fit_contract_releases (
  contract_release_id,
  release_code,
  specification_version,
  upstream_contract_version,
  specification_digest,
  status,
  reviewed_by,
  reviewed_at
) values (
  '30000000-0000-0000-0000-000000000001',
  'fit-v0.1',
  'v0.1',
  'phase2-eligibility-v0.1',
  '2f1076711a049b792efd3505df47d7baffd1a99ae42572d8bbad58cd5c2d7c29',
  'VERIFIED',
  'Phase 3 Fit semantic contract approval',
  timestamptz '2026-08-20 00:00:00+00'
);

insert into public.fit_semantic_source_classes (
  source_class_code, owner_layer, fit_permitted, description
) values
  ('PROGRAM_CANONICAL_FACT', 'PHASE1', true, 'Selected Phase 1 canonical program fact.'),
  ('STUDENT_RAW_INTENT', 'PHASE2', true, 'Explicit student goal or preference.'),
  ('STUDENT_RAW_ACADEMIC_HISTORY', 'PHASE2', true, 'Student course history used only as alignment context.'),
  ('STUDENT_RAW_ACCESS_CONTEXT', 'PHASE3', true, 'Authorized student access context owned by the Fit intent snapshot.'),
  ('TAXONOMY_MAPPING', 'PHASE2', true, 'Reviewed taxonomy relationship.'),
  ('FIT_CONTEXT_REGULATORY', 'PHASE3', true, 'Reviewed regulatory context not owned upstream.'),
  ('FIT_CONTEXT_CAREER', 'PHASE3', true, 'Reviewed career pathway context not owned upstream.'),
  ('FIT_CONTEXT_FINANCIAL', 'PHASE3', true, 'Reviewed financial context not owned upstream.'),
  ('FIT_CONTEXT_ACCESSIBILITY', 'PHASE3', true, 'Reviewed structural-access context not owned upstream.'),
  ('COMPETITIVENESS', 'PROHIBITED', false, 'Applicant competitiveness signal.'),
  ('ADMISSION_PROBABILITY', 'PROHIBITED', false, 'Admission likelihood or probability.'),
  ('PRESTIGE_RANKING', 'PROHIBITED', false, 'Prestige or ranking signal.'),
  ('ELIGIBILITY_DECISION', 'PROHIBITED', false, 'Phase 2 Eligibility decision or gap.'),
  ('RECOMMENDATION_OUTPUT', 'PROHIBITED', false, 'Recommendation or ranking output.'),
  ('GENERIC_STUDENT_CAPABILITY_SCORE', 'PROHIBITED', false, 'Generic preparation, strength, or capability score.');

insert into public.fit_dimension_methods (
  method_id,
  contract_release_id,
  dimension,
  method_code,
  method_version,
  status,
  inference_category,
  materiality_contract,
  permits_strong_alignment
) values
  (
    '30000000-0000-0000-0000-000000000101',
    '30000000-0000-0000-0000-000000000001',
    'ACADEMIC',
    'ACADEMIC_ALIGNMENT_V01',
    1,
    'DRAFT',
    'HYBRID',
    jsonb_build_object(
      'coreQuestion', 'Do curriculum and academic orientation align with explicit study goals?',
      'materialityRules', jsonb_build_array(
        'Missing explicit academic intent produces UNKNOWN.',
        'Reviewed curriculum mappings may support direction.',
        'A comparable REQUIRED contradiction takes precedence.'
      ),
      'strongAlignmentContract', jsonb_build_object(
        'qualificationMode',
          'DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH',
        'requiresAuthoritativeIntent', true,
        'requiresAuthoritativeProgramEvidence', true,
        'forbidsMaterialContradiction', true,
        'modelAlonePermitted', false
      )
    ),
    true
  ),
  (
    '30000000-0000-0000-0000-000000000102',
    '30000000-0000-0000-0000-000000000001',
    'CAREER',
    'CAREER_ALIGNMENT_V01',
    1,
    'DRAFT',
    'HYBRID',
    jsonb_build_object(
      'coreQuestion', 'Do program evidence and reviewed mappings align with explicit career goals?',
      'materialityRules', jsonb_build_array(
        'Program titles and model hypotheses are not authoritative outcomes.',
        'Observed outcomes require applicable population, geography, and period.',
        'Model evidence alone cannot produce STRONG_ALIGNMENT or HIGH confidence.'
      )
    ),
    false
  ),
  (
    '30000000-0000-0000-0000-000000000103',
    '30000000-0000-0000-0000-000000000001',
    'FINANCIAL',
    'FINANCIAL_ALIGNMENT_V01',
    1,
    'DRAFT',
    'DETERMINISTIC',
    jsonb_build_object(
      'coreQuestion', 'Do comparable known costs and funding align with explicit financial constraints?',
      'materialityRules', jsonb_build_array(
        'Currency, period, scope, components, and gross/net basis must be comparable.',
        'Required normalization must pin a VERIFIED method.',
        'Unknown financial quantities are never invented.'
      )
    ),
    false
  ),
  (
    '30000000-0000-0000-0000-000000000104',
    '30000000-0000-0000-0000-000000000001',
    'GEOGRAPHIC_DELIVERY',
    'GEOGRAPHIC_DELIVERY_ALIGNMENT_V01',
    1,
    'DRAFT',
    'HYBRID',
    jsonb_build_object(
      'coreQuestion', 'Do program location and delivery align with explicit geographic constraints?',
      'materialityRules', jsonb_build_array(
        'Preferences may not be inferred from demographics.',
        'Canonical location and delivery support deterministic comparison.',
        'International authorization remains outside this dimension.'
      )
    ),
    false
  ),
  (
    '30000000-0000-0000-0000-000000000105',
    '30000000-0000-0000-0000-000000000001',
    'PERSONAL_PREFERENCE',
    'PERSONAL_PREFERENCE_ALIGNMENT_V01',
    1,
    'DRAFT',
    'HYBRID',
    jsonb_build_object(
      'coreQuestion', 'Do observable program characteristics align with explicit personal preferences?',
      'materialityRules', jsonb_build_array(
        'Only explicit preferences and observable program characteristics are allowed.',
        'No personality or psychographic inference is permitted.',
        'Financial, geographic, career, and international factors retain separate ownership.'
      )
    ),
    false
  ),
  (
    '30000000-0000-0000-0000-000000000106',
    '30000000-0000-0000-0000-000000000001',
    'INTERNATIONAL_ACCESSIBILITY',
    'INTERNATIONAL_ACCESSIBILITY_V01',
    1,
    'DRAFT',
    'HYBRID',
    jsonb_build_object(
      'coreQuestion', 'Do current applicable structural facts support the international target path?',
      'materialityRules', jsonb_build_array(
        'Evidence must match jurisdiction, population, validity period, and path.',
        'STEM designation alone produces UNKNOWN.',
        'Model-only evidence cannot produce an authoritative directional assessment.'
      )
    ),
    false
  );

insert into public.fit_method_source_class_policies (
  method_id, source_class_code, disposition
)
select method_id, source_class_code,
  case
    when source_class_code = any(allowed_classes)
      then 'ALLOWED'::public.fit_input_policy_disposition
    else 'FORBIDDEN'::public.fit_input_policy_disposition
  end
from (
  values
    ('30000000-0000-0000-0000-000000000101'::uuid, array['PROGRAM_CANONICAL_FACT','STUDENT_RAW_INTENT','STUDENT_RAW_ACADEMIC_HISTORY','TAXONOMY_MAPPING']::text[]),
    ('30000000-0000-0000-0000-000000000102'::uuid, array['PROGRAM_CANONICAL_FACT','STUDENT_RAW_INTENT','TAXONOMY_MAPPING','FIT_CONTEXT_CAREER']::text[]),
    ('30000000-0000-0000-0000-000000000103'::uuid, array['PROGRAM_CANONICAL_FACT','STUDENT_RAW_INTENT','FIT_CONTEXT_FINANCIAL']::text[]),
    ('30000000-0000-0000-0000-000000000104'::uuid, array['PROGRAM_CANONICAL_FACT','STUDENT_RAW_INTENT']::text[]),
    ('30000000-0000-0000-0000-000000000105'::uuid, array['PROGRAM_CANONICAL_FACT','STUDENT_RAW_INTENT','TAXONOMY_MAPPING']::text[]),
    ('30000000-0000-0000-0000-000000000106'::uuid, array['PROGRAM_CANONICAL_FACT','STUDENT_RAW_INTENT','STUDENT_RAW_ACCESS_CONTEXT','TAXONOMY_MAPPING','FIT_CONTEXT_REGULATORY','FIT_CONTEXT_ACCESSIBILITY']::text[])
) method(method_id, allowed_classes)
cross join public.fit_semantic_source_classes;

insert into public.fit_mapping_relation_definitions (
  relation_code, relation_domain, description
) values
  ('FIELD_CLASSIFICATION', 'CATALOG', 'Catalog record is classified to a field.'),
  ('SUBFIELD_CLASSIFICATION', 'CATALOG', 'Catalog record is classified to a subfield.'),
  ('SUBJECT_CLASSIFICATION', 'CATALOG', 'Catalog record is classified to a subject.'),
  ('COURSE_EQUIVALENCY', 'CATALOG', 'Reviewed course-concept equivalency.'),
  ('SKILL_ASSOCIATION', 'CATALOG', 'Reviewed skill association.'),
  ('CAREER_ASSOCIATION', 'CATALOG', 'Reviewed career association; not causal preparation.'),
  ('INDUSTRY_ASSOCIATION', 'CATALOG', 'Reviewed industry association.'),
  ('STUDENT_COURSE_EQUIVALENCY', 'STUDENT', 'Reviewed student-course concept equivalency.'),
  ('PROGRAM_RELATED_TO_CAREER', 'FIT_CONTEXT', 'Program is contextually related to a career; not strong preparation.'),
  ('PROGRAM_ASSOCIATED_WITH_PATH', 'FIT_CONTEXT', 'Program is contextually associated with a path.'),
  ('CLAIM_APPLIES_TO_CONCEPT', 'FIT_CONTEXT', 'Context claim applies to a taxonomy concept.');

insert into public.fit_method_mapping_relation_policies (
  method_id, relation_code, allowed_assessments, permits_strong_alignment
) values
  ('30000000-0000-0000-0000-000000000101', 'FIELD_CLASSIFICATION', array['ALIGNMENT','MIXED','MISALIGNMENT','UNKNOWN']::public.fit_assessment[], false),
  ('30000000-0000-0000-0000-000000000101', 'SUBFIELD_CLASSIFICATION', array['ALIGNMENT','MIXED','MISALIGNMENT','UNKNOWN']::public.fit_assessment[], false),
  ('30000000-0000-0000-0000-000000000101', 'SUBJECT_CLASSIFICATION', array['ALIGNMENT','MIXED','MISALIGNMENT','UNKNOWN']::public.fit_assessment[], false),
  ('30000000-0000-0000-0000-000000000101', 'COURSE_EQUIVALENCY', array['ALIGNMENT','MIXED','MISALIGNMENT','UNKNOWN']::public.fit_assessment[], false),
  ('30000000-0000-0000-0000-000000000101', 'STUDENT_COURSE_EQUIVALENCY', array['ALIGNMENT','MIXED','UNKNOWN']::public.fit_assessment[], false),
  ('30000000-0000-0000-0000-000000000102', 'CAREER_ASSOCIATION', array['ALIGNMENT','MIXED','MISALIGNMENT','UNKNOWN']::public.fit_assessment[], false),
  ('30000000-0000-0000-0000-000000000102', 'INDUSTRY_ASSOCIATION', array['ALIGNMENT','MIXED','MISALIGNMENT','UNKNOWN']::public.fit_assessment[], false),
  ('30000000-0000-0000-0000-000000000102', 'PROGRAM_RELATED_TO_CAREER', array['ALIGNMENT','MIXED','UNKNOWN']::public.fit_assessment[], false),
  ('30000000-0000-0000-0000-000000000106', 'PROGRAM_ASSOCIATED_WITH_PATH', array['ALIGNMENT','MIXED','MISALIGNMENT','UNKNOWN']::public.fit_assessment[], false),
  ('30000000-0000-0000-0000-000000000106', 'CLAIM_APPLIES_TO_CONCEPT', array['ALIGNMENT','MIXED','MISALIGNMENT','UNKNOWN']::public.fit_assessment[], false);

insert into public.fit_signal_types (
  signal_type_id, method_id, signal_code, direction, material,
  allowed_inference_categories, permits_strong_alignment, description
)
select
  md5(method_id::text || ':' || signal_code)::uuid,
  method_id,
  signal_code,
  direction::public.fit_reason_direction,
  material,
  case
    when method_inference = 'DETERMINISTIC'
      then array['DETERMINISTIC']::public.fit_inference_category[]
    else inference_categories::public.fit_inference_category[]
  end,
  permits_strong,
  description
from (
  select method_id, inference_category as method_inference,
    signal_code, direction, material,
    inference_categories, permits_strong, description
  from public.fit_dimension_methods
  cross join (
    values
      ('MATERIAL_SUPPORT', 'SUPPORTING', true, array['DETERMINISTIC','REVIEWED_MAPPING','RULE','MODEL','HYBRID']::text[], false, 'Method-approved material positive evidence.'),
      ('MATERIAL_CONTRADICTION', 'CONTRADICTING', true, array['DETERMINISTIC','REVIEWED_MAPPING','RULE','MODEL','HYBRID']::text[], false, 'Method-approved material contradiction.'),
      ('NON_MATERIAL_SUPPORT', 'SUPPORTING', false, array['DETERMINISTIC','REVIEWED_MAPPING','RULE','MODEL','HYBRID']::text[], false, 'Relevant but non-material positive context.'),
      ('NON_MATERIAL_CONTRADICTION', 'CONTRADICTING', false, array['DETERMINISTIC','REVIEWED_MAPPING','RULE','MODEL','HYBRID']::text[], false, 'Relevant but non-material contradicting context.'),
      ('LIMITING_CONTEXT', 'LIMITING', false, array['DETERMINISTIC','REVIEWED_MAPPING','RULE','MODEL','HYBRID']::text[], false, 'Missing, conflicting, stale, or inapplicable input.')
  ) signal(signal_code, direction, material, inference_categories, permits_strong, description)
) seeded;

insert into public.fit_signal_types (
  signal_type_id, method_id, signal_code, direction, material,
  allowed_inference_categories, permits_strong_alignment, description
) values (
  md5(
    '30000000-0000-0000-0000-000000000101:'
    || 'DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH'
  )::uuid,
  '30000000-0000-0000-0000-000000000101',
  'DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH',
  'SUPPORTING',
  true,
  array[
    'DETERMINISTIC','REVIEWED_MAPPING','RULE','MODEL','HYBRID'
  ]::public.fit_inference_category[],
  true,
  'Direct authoritative curriculum match to explicit high-importance academic intent.'
);

insert into public.fit_method_input_policies (
  input_policy_id,
  method_id,
  input_domain,
  field_name,
  disposition,
  requirement,
  acceptable_authority,
  acceptable_claim_status,
  permits_deterministic_use,
  permits_model_use
)
select
  md5(method_id::text || ':' || input_domain || ':' || field_name)::uuid,
  method_id,
  input_domain,
  field_name,
  disposition::public.fit_input_policy_disposition,
  requirement::public.fit_input_requirement,
  authority::public.fit_claim_authority,
  workflow::public.fit_claim_workflow_status,
  deterministic_use,
  model_use
from (
  values
    ('30000000-0000-0000-0000-000000000101'::uuid, 'STUDENT_GOALS', 'ACADEMIC_INTENT', 'ALLOWED', 'REQUIRED', null, null, true, true),
    ('30000000-0000-0000-0000-000000000101'::uuid, 'PROGRAM_COURSES', 'CURRICULUM', 'ALLOWED', 'REQUIRED', 'OFFICIAL_INSTITUTIONAL', 'VERIFIED', true, true),
    ('30000000-0000-0000-0000-000000000102'::uuid, 'STUDENT_GOALS', 'CAREER_INTENT', 'ALLOWED', 'REQUIRED', null, null, true, true),
    ('30000000-0000-0000-0000-000000000102'::uuid, 'CATALOG_MAPPINGS', 'CAREER_MAPPING', 'ALLOWED', 'REQUIRED', 'REVIEWED_STRUCTURED', 'VERIFIED', true, true),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'STUDENT_PREFERENCES', 'BUDGET', 'ALLOWED', 'REQUIRED', null, null, true, false),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'PROGRAM_COSTS', 'COST_COMPONENTS', 'ALLOWED', 'REQUIRED', 'OFFICIAL_INSTITUTIONAL', 'VERIFIED', true, false),
    ('30000000-0000-0000-0000-000000000104'::uuid, 'STUDENT_PREFERENCES', 'GEOGRAPHIC_DELIVERY_INTENT', 'ALLOWED', 'REQUIRED', null, null, true, true),
    ('30000000-0000-0000-0000-000000000104'::uuid, 'PROGRAM_VERSIONS', 'LOCATION_DELIVERY', 'ALLOWED', 'REQUIRED', 'OFFICIAL_INSTITUTIONAL', 'VERIFIED', true, true),
    ('30000000-0000-0000-0000-000000000105'::uuid, 'STUDENT_PREFERENCES', 'PROGRAM_CHARACTERISTICS', 'ALLOWED', 'REQUIRED', null, null, true, true),
    ('30000000-0000-0000-0000-000000000105'::uuid, 'PROGRAM_VERSIONS', 'OBSERVABLE_CHARACTERISTICS', 'ALLOWED', 'REQUIRED', 'OFFICIAL_INSTITUTIONAL', 'VERIFIED', true, true),
    ('30000000-0000-0000-0000-000000000106'::uuid, 'STUDENT_GOALS', 'INTERNATIONAL_TARGET_PATH', 'ALLOWED', 'REQUIRED', null, null, true, true),
    ('30000000-0000-0000-0000-000000000106'::uuid, 'FIT_CONTEXT_CLAIMS', 'INTERNATIONAL_ACCESS_EVIDENCE', 'ALLOWED', 'REQUIRED', 'OFFICIAL_REGULATORY', 'VERIFIED', true, true)
) as policy(
  method_id,
  input_domain,
  field_name,
  disposition,
  requirement,
  authority,
  workflow,
  deterministic_use,
  model_use
);

-- Typed persistence domains used by the Phase 3 v0.1 evidence manifest.
-- These are deliberately narrow: no generic derived-feature or external-metric
-- domain is made ALLOWED.
insert into public.fit_method_input_policies (
  input_policy_id,
  method_id,
  input_domain,
  field_name,
  disposition,
  requirement,
  acceptable_authority,
  acceptable_claim_status,
  permits_deterministic_use,
  permits_model_use
)
select
  md5(method_id::text || ':' || input_domain || ':' || field_name)::uuid,
  method_id,
  input_domain,
  field_name,
  'ALLOWED'::public.fit_input_policy_disposition,
  requirement::public.fit_input_requirement,
  authority::public.fit_claim_authority,
  workflow::public.fit_claim_workflow_status,
  deterministic_use,
  model_use
from (
  values
    ('30000000-0000-0000-0000-000000000101'::uuid, 'FIT_INTENTS', 'DECLARED_ACADEMIC_INTENT', 'REQUIRED', null, null, true, true),
    ('30000000-0000-0000-0000-000000000101'::uuid, 'STUDENT_COURSES', 'ALIGNMENT_COURSE_CONTEXT', 'OPTIONAL', null, null, true, true),
    ('30000000-0000-0000-0000-000000000101'::uuid, 'STUDENT_COMPLETENESS', 'ACADEMIC_INPUT_AVAILABILITY', 'OPTIONAL', null, null, false, false),
    ('30000000-0000-0000-0000-000000000101'::uuid, 'STUDENT_MAPPINGS', 'REVIEWED_STUDENT_COURSE_MAPPING', 'OPTIONAL', 'REVIEWED_STRUCTURED', 'VERIFIED', true, true),
    ('30000000-0000-0000-0000-000000000101'::uuid, 'CATALOG_MAPPINGS', 'ACADEMIC_MAPPING', 'OPTIONAL', 'REVIEWED_STRUCTURED', 'VERIFIED', true, true),
    ('30000000-0000-0000-0000-000000000101'::uuid, 'TAXONOMY_CONCEPTS', 'ACADEMIC_CONCEPT', 'OPTIONAL', null, null, true, true),
    ('30000000-0000-0000-0000-000000000102'::uuid, 'FIT_INTENTS', 'DECLARED_CAREER_INTENT', 'REQUIRED', null, null, true, true),
    ('30000000-0000-0000-0000-000000000102'::uuid, 'PROGRAM_COURSES', 'CAREER_RELEVANT_CURRICULUM', 'OPTIONAL', 'OFFICIAL_INSTITUTIONAL', 'VERIFIED', true, true),
    ('30000000-0000-0000-0000-000000000102'::uuid, 'FIT_CONTEXT_CLAIMS', 'REVIEWED_CAREER_CONTEXT', 'OPTIONAL', 'REVIEWED_STRUCTURED', 'VERIFIED', true, true),
    ('30000000-0000-0000-0000-000000000102'::uuid, 'STUDENT_COMPLETENESS', 'CAREER_INPUT_AVAILABILITY', 'OPTIONAL', null, null, false, false),
    ('30000000-0000-0000-0000-000000000102'::uuid, 'TAXONOMY_CONCEPTS', 'CAREER_CONCEPT', 'OPTIONAL', null, null, true, true),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'FIT_INTENTS', 'DECLARED_FINANCIAL_INTENT', 'REQUIRED', null, null, true, false),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'STUDENT_COMPLETENESS', 'FINANCIAL_INPUT_AVAILABILITY', 'OPTIONAL', null, null, false, false),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'FINANCIAL_NORMALIZATIONS', 'COMPARABLE_FINANCIAL_ARTIFACT', 'OPTIONAL', 'REVIEWED_STRUCTURED', 'VERIFIED', true, false),
    ('30000000-0000-0000-0000-000000000104'::uuid, 'FIT_INTENTS', 'DECLARED_GEOGRAPHIC_DELIVERY_INTENT', 'REQUIRED', null, null, true, true),
    ('30000000-0000-0000-0000-000000000104'::uuid, 'STUDENT_COMPLETENESS', 'GEOGRAPHIC_DELIVERY_INPUT_AVAILABILITY', 'OPTIONAL', null, null, false, false),
    ('30000000-0000-0000-0000-000000000105'::uuid, 'FIT_INTENTS', 'DECLARED_PERSONAL_PREFERENCE_INTENT', 'REQUIRED', null, null, true, true),
    ('30000000-0000-0000-0000-000000000105'::uuid, 'STUDENT_COMPLETENESS', 'PERSONAL_PREFERENCE_INPUT_AVAILABILITY', 'OPTIONAL', null, null, false, false),
    ('30000000-0000-0000-0000-000000000106'::uuid, 'FIT_INTENTS', 'DECLARED_INTERNATIONAL_PATH_INTENT', 'REQUIRED', null, null, true, true),
    ('30000000-0000-0000-0000-000000000106'::uuid, 'FIT_ACCESS_CONTEXT', 'AUTHORIZED_STUDENT_ACCESS_CONTEXT', 'OPTIONAL', null, null, true, true),
    ('30000000-0000-0000-0000-000000000106'::uuid, 'STUDENT_COMPLETENESS', 'INTERNATIONAL_INPUT_AVAILABILITY', 'OPTIONAL', null, null, false, false),
    ('30000000-0000-0000-0000-000000000106'::uuid, 'PROGRAM_VERSIONS', 'INTERNATIONAL_PROGRAM_FACTS', 'OPTIONAL', 'OFFICIAL_INSTITUTIONAL', 'VERIFIED', true, true),
    ('30000000-0000-0000-0000-000000000106'::uuid, 'TAXONOMY_CONCEPTS', 'INTERNATIONAL_PATH_CONCEPT', 'OPTIONAL', null, null, true, true)
) as policy(
  method_id,
  input_domain,
  field_name,
  requirement,
  authority,
  workflow,
  deterministic_use,
  model_use
);

insert into public.fit_method_input_policies (
  input_policy_id,
  method_id,
  input_domain,
  field_name,
  disposition,
  requirement,
  permits_deterministic_use,
  permits_model_use
)
select
  md5(method.method_id::text || ':' || prohibited.input_domain || ':' ||
    prohibited.field_name)::uuid,
  method.method_id,
  prohibited.input_domain,
  prohibited.field_name,
  'FORBIDDEN',
  'OPTIONAL',
  false,
  false
from public.fit_dimension_methods method
cross join (
  values
    ('EXTERNAL_METRICS', 'PRESTIGE'),
    ('ELIGIBILITY_EVALUATIONS', 'ELIGIBILITY_CONTEXT'),
    ('STUDENT_DERIVED_FEATURE_VALUES', 'GENERIC_DERIVED_FEATURE')
) as prohibited(input_domain, field_name)
where method.contract_release_id =
  '30000000-0000-0000-0000-000000000001';

insert into public.fit_method_input_policies (
  input_policy_id,
  method_id,
  input_domain,
  field_name,
  disposition,
  requirement,
  permits_deterministic_use,
  permits_model_use
)
select
  md5(method.method_id::text || ':' || prohibited.input_domain || ':' ||
    prohibited.field_name)::uuid,
  method.method_id,
  prohibited.input_domain,
  prohibited.field_name,
  'FORBIDDEN',
  'OPTIONAL',
  false,
  false
from public.fit_dimension_methods method
cross join (
  values
    ('STUDENT_DEGREES', 'GPA_VALUE'),
    ('STUDENT_TEST_SCORES', 'GRE_SCORE'),
    ('STUDENT_TEST_SCORES', 'GMAT_SCORE')
) as prohibited(input_domain, field_name)
where method.method_id in (
  '30000000-0000-0000-0000-000000000101',
  '30000000-0000-0000-0000-000000000106'
);

insert into public.fit_method_program_field_policies (
  method_id, input_policy_id, record_type, field_name
)
select
  policy.method_id,
  policy.input_policy_id,
  allowed.record_type::public.catalog_record_type,
  allowed.catalog_field_name
from (
  values
    ('30000000-0000-0000-0000-000000000101'::uuid, 'PROGRAM_COURSES', 'CURRICULUM', 'PROGRAM_COURSE', 'course_name'),
    ('30000000-0000-0000-0000-000000000101'::uuid, 'PROGRAM_COURSES', 'CURRICULUM', 'PROGRAM_COURSE', 'official_description'),
    ('30000000-0000-0000-0000-000000000102'::uuid, 'PROGRAM_COURSES', 'CAREER_RELEVANT_CURRICULUM', 'PROGRAM_COURSE', 'course_name'),
    ('30000000-0000-0000-0000-000000000102'::uuid, 'PROGRAM_COURSES', 'CAREER_RELEVANT_CURRICULUM', 'PROGRAM_COURSE', 'official_description'),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'PROGRAM_COSTS', 'COST_COMPONENTS', 'PROGRAM_COST', 'tuition_amount'),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'PROGRAM_COSTS', 'COST_COMPONENTS', 'PROGRAM_COST', 'mandatory_fees'),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'PROGRAM_COSTS', 'COST_COMPONENTS', 'PROGRAM_COST', 'estimated_living_cost'),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'PROGRAM_COSTS', 'COST_COMPONENTS', 'PROGRAM_COST', 'estimated_total_cost'),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'PROGRAM_COSTS', 'COST_COMPONENTS', 'PROGRAM_COST', 'currency'),
    ('30000000-0000-0000-0000-000000000103'::uuid, 'PROGRAM_COSTS', 'COST_COMPONENTS', 'PROGRAM_COST', 'billing_basis'),
    ('30000000-0000-0000-0000-000000000104'::uuid, 'PROGRAM_VERSIONS', 'LOCATION_DELIVERY', 'PROGRAM_VERSION', 'delivery_mode'),
    ('30000000-0000-0000-0000-000000000105'::uuid, 'PROGRAM_VERSIONS', 'OBSERVABLE_CHARACTERISTICS', 'PROGRAM_VERSION', 'duration_months'),
    ('30000000-0000-0000-0000-000000000105'::uuid, 'PROGRAM_VERSIONS', 'OBSERVABLE_CHARACTERISTICS', 'PROGRAM_VERSION', 'full_time'),
    ('30000000-0000-0000-0000-000000000105'::uuid, 'PROGRAM_VERSIONS', 'OBSERVABLE_CHARACTERISTICS', 'PROGRAM_VERSION', 'capstone_required'),
    ('30000000-0000-0000-0000-000000000106'::uuid, 'PROGRAM_VERSIONS', 'INTERNATIONAL_PROGRAM_FACTS', 'PROGRAM_VERSION', 'stem_status')
) allowed(
  method_id, input_domain, policy_field_name, record_type, catalog_field_name
)
join public.fit_method_input_policies policy
  on policy.method_id = allowed.method_id
 and policy.input_domain = allowed.input_domain
 and policy.field_name = allowed.policy_field_name;

insert into public.fit_reason_definitions (
  reason_definition_id,
  contract_release_id,
  reason_code,
  dimension,
  reason_family,
  direction,
  allowed_assessments,
  description,
  status,
  reviewed_by,
  reviewed_at
) values
  (
    '30000000-0000-0000-0000-000000000201',
    '30000000-0000-0000-0000-000000000001',
    'STUDENT_PREFERENCE_UNSPECIFIED',
    null,
    'INTENT_UNSPECIFIED',
    'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'Required student intent is unspecified; no direction may be inferred.',
    'VERIFIED',
    'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000202',
    '30000000-0000-0000-0000-000000000001',
    'REQUIRED_INPUT_UNAVAILABLE',
    null,
    'STUDENT_INPUT_NOT_SUPPLIED',
    'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'A required method input is missing, unusable, or not supplied.',
    'VERIFIED',
    'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000203',
    '30000000-0000-0000-0000-000000000001',
    'MATERIAL_EVIDENCE_SUPPORTS_ALIGNMENT',
    null,
    'DIRECTIONAL_SUPPORT',
    'SUPPORTING',
    array['STRONG_ALIGNMENT', 'ALIGNMENT', 'MIXED']::public.fit_assessment[],
    'Known applicable material evidence supports the explicit intent.',
    'VERIFIED',
    'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000204',
    '30000000-0000-0000-0000-000000000001',
    'MATERIAL_EVIDENCE_CONTRADICTS_INTENT',
    null,
    'DIRECTIONAL_CONTRADICTION',
    'CONTRADICTING',
    array['MIXED', 'MISALIGNMENT']::public.fit_assessment[],
    'Known applicable material evidence contradicts explicit student intent.',
    'VERIFIED',
    'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000205',
    '30000000-0000-0000-0000-000000000001',
    'REQUIRED_CONSTRAINT_CONTRADICTED',
    null,
    'REQUIRED_CONSTRAINT',
    'CONTRADICTING',
    array['MISALIGNMENT']::public.fit_assessment[],
    'A comparable known fact contradicts a student-declared REQUIRED constraint.',
    'VERIFIED',
    'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000206',
    '30000000-0000-0000-0000-000000000001',
    'MODEL_INFERENCE_LIMITATION',
    null,
    'METHOD_LIMITATION',
    'LIMITING',
    array['ALIGNMENT', 'MIXED', 'MISALIGNMENT', 'UNKNOWN']::public.fit_assessment[],
    'Model inference is subordinate to authoritative facts and reviewed mappings.',
    'VERIFIED',
    'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000207',
    '30000000-0000-0000-0000-000000000001',
    'SOURCE_CONFLICT',
    null,
    'SOURCE_CONFLICT',
    'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'Material source claims conflict and cannot support a defensible direction.',
    'VERIFIED',
    'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000208',
    '30000000-0000-0000-0000-000000000001',
    'FINANCIAL_INPUTS_INCOMPARABLE',
    'FINANCIAL',
    'EVIDENCE_INSUFFICIENT',
    'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'Currency, period, component scope, or gross/net basis is not comparable.',
    'VERIFIED',
    'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000209',
    '30000000-0000-0000-0000-000000000001',
    'INTERNATIONAL_EVIDENCE_INAPPLICABLE',
    'INTERNATIONAL_ACCESSIBILITY',
    'CONTEXT_APPLICABILITY_UNKNOWN',
    'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'Evidence does not match jurisdiction, population, validity period, or target path.',
    'VERIFIED',
    'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000210',
    '30000000-0000-0000-0000-000000000001',
    'STUDENT_INPUT_INCOMPLETE', null, 'STUDENT_INPUT_INCOMPLETE', 'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'Student input exists but upstream completeness is partial or unknown.',
    'VERIFIED', 'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000211',
    '30000000-0000-0000-0000-000000000001',
    'PROGRAM_FACT_UNKNOWN', null, 'PROGRAM_FACT_UNKNOWN', 'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'A Phase 1-owned program fact is unknown and may not be copied into Fit.',
    'VERIFIED', 'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000212',
    '30000000-0000-0000-0000-000000000001',
    'STALE_SOURCE', null, 'STALE_SOURCE', 'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'Required evidence is stale at the evaluation as-of time.',
    'VERIFIED', 'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000213',
    '30000000-0000-0000-0000-000000000001',
    'NO_AUTHORITATIVE_MAPPING', null, 'NO_AUTHORITATIVE_MAPPING', 'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'No active VERIFIED mapping with method-authorized relation semantics exists.',
    'VERIFIED', 'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000214',
    '30000000-0000-0000-0000-000000000001',
    'EVIDENCE_INSUFFICIENT', null, 'EVIDENCE_INSUFFICIENT', 'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'Available applicable evidence is insufficient for a direction.',
    'VERIFIED', 'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000215',
    '30000000-0000-0000-0000-000000000001',
    'METHOD_UNSUPPORTED', null, 'METHOD_UNSUPPORTED', 'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'The pinned method does not support the requested comparison.',
    'VERIFIED', 'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000216',
    '30000000-0000-0000-0000-000000000001',
    'INPUT_INAPPLICABLE', null, 'INPUT_INAPPLICABLE', 'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'A method input is genuinely inapplicable; this is not misalignment.',
    'VERIFIED', 'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  ),
  (
    '30000000-0000-0000-0000-000000000217',
    '30000000-0000-0000-0000-000000000001',
    'INTENT_CONFLICT', null, 'INTENT_CONFLICT', 'LIMITING',
    array['UNKNOWN']::public.fit_assessment[],
    'Mutually incompatible REQUIRED student constraints prevent valid Fit interpretation.',
    'VERIFIED', 'Phase 3 Fit semantic contract approval',
    timestamptz '2026-08-20 00:00:00+00'
  );

commit;
