begin;

create type public.fit_manifest_item_type as enum (
  'FIT_INTENT_DECLARATION',
  'FIT_STUDENT_ACCESS_CONTEXT',
  'PHASE2_STUDENT_GOAL',
  'PHASE2_STUDENT_PREFERENCE',
  'PHASE2_STUDENT_COURSE',
  'PHASE2_STUDENT_COMPLETENESS',
  'PHASE2_STUDENT_MAPPING',
  'CATALOG_FIELD_OBSERVATION',
  'CATALOG_MAPPING',
  'TAXONOMY_CONCEPT',
  'FIT_CONTEXT_CLAIM_SELECTION',
  'FIT_CONTEXT_MAPPING',
  'FIT_FINANCIAL_NORMALIZATION'
);
create type public.fit_manifest_authority_role as enum (
  'AUTHORITATIVE',
  'LIMITING_CONTEXT'
);
create type public.fit_student_field_name as enum (
  'GOAL_TYPE',
  'CONCEPT_ID',
  'GOAL_TEXT',
  'PREFERENCE_TYPE',
  'VALUE',
  'COURSE_CODE',
  'COURSE_TITLE',
  'COURSE_STATUS',
  'TERM',
  'EDUCATION_CONTEXT_ID',
  'DOMAIN',
  'COMPLETENESS'
);

create table public.fit_evaluations (
  evaluation_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id) on delete cascade,
  profile_snapshot_hash text not null,
  intent_set_id uuid not null,
  intent_snapshot_hash text not null,
  program_version_id uuid not null
    references public.program_versions(program_version_id) on delete restrict,
  taxonomy_release_code text not null
    references public.taxonomy_releases(release_code) on delete restrict,
  contract_release_id uuid not null
    references public.fit_contract_releases(contract_release_id) on delete restrict,
  evaluator_build_id uuid not null
    references public.fit_evaluator_builds(evaluator_build_id)
    on delete restrict,
  evaluator_name text not null,
  evaluator_version text not null,
  evaluator_build_hash text not null,
  input_schema_version text not null default 'fit-v0.1',
  evaluation_state public.fit_evaluation_state not null default 'BUILDING',
  candidate_input_fingerprint text,
  decision_input_fingerprint text,
  result_fingerprint text,
  execution_id uuid not null default extensions.gen_random_uuid(),
  supersedes_evaluation_id uuid
    references public.fit_evaluations(evaluation_id) on delete set null,
  eligibility_context_evaluation_id uuid
    references public.eligibility_evaluations(evaluation_id) on delete set null,
  created_at timestamptz not null default now(),
  evaluation_as_of timestamptz not null default now(),
  evaluated_at timestamptz,
  finalized_by text,
  constraint fit_evaluations_identity check (
    btrim(evaluator_name) <> '' and btrim(evaluator_version) <> ''
    and input_schema_version = 'fit-v0.1'
  ),
  constraint fit_evaluations_hashes check (
    profile_snapshot_hash ~ '^[a-f0-9]{64}$'
    and intent_snapshot_hash ~ '^[a-f0-9]{64}$'
    and evaluator_build_hash ~ '^[a-f0-9]{64}$'
    and (candidate_input_fingerprint is null
      or candidate_input_fingerprint ~ '^[a-f0-9]{64}$')
    and (decision_input_fingerprint is null
      or decision_input_fingerprint ~ '^[a-f0-9]{64}$')
    and (result_fingerprint is null
      or result_fingerprint ~ '^[a-f0-9]{64}$')
  ),
  constraint fit_evaluations_completion check (
    (evaluation_state = 'BUILDING'
      and decision_input_fingerprint is null
      and result_fingerprint is null
      and evaluated_at is null
      and finalized_by is null)
    or
    (evaluation_state = 'COMPLETED'
      and candidate_input_fingerprint is not null
      and decision_input_fingerprint is not null
      and result_fingerprint is not null
      and evaluated_at is not null
      and nullif(btrim(finalized_by), '') is not null
    )
  ),
  constraint fit_evaluations_no_self_supersession check (
    supersedes_evaluation_id is null or supersedes_evaluation_id <> evaluation_id
  ),
  unique (evaluation_id, profile_version_id),
  foreign key (intent_set_id, profile_version_id)
    references public.fit_intent_sets(intent_set_id, profile_version_id)
    on delete cascade
);

create table public.fit_evaluation_methods (
  evaluation_id uuid not null
    references public.fit_evaluations(evaluation_id) on delete cascade,
  dimension public.fit_dimension not null,
  method_id uuid not null,
  contract_release_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (evaluation_id, dimension),
  unique (evaluation_id, method_id),
  unique (evaluation_id, dimension, method_id),
  foreign key (method_id, contract_release_id)
    references public.fit_dimension_methods(method_id, contract_release_id)
    on delete restrict
);

create table private.fit_evaluation_assembly_authorizations (
  evaluation_id uuid primary key
    references public.fit_evaluations(evaluation_id) on delete cascade,
  execution_id uuid not null,
  evaluator_build_id uuid not null
    references public.fit_evaluator_builds(evaluator_build_id)
    on delete restrict,
  evaluator_build_hash text not null,
  authorized_at timestamptz not null default now(),
  unique (evaluation_id, execution_id, evaluator_build_id),
  constraint fit_assembly_authorization_hash
    check (evaluator_build_hash ~ '^[a-f0-9]{64}$')
);
alter table private.fit_evaluation_assembly_authorizations
  enable row level security;
revoke all on private.fit_evaluation_assembly_authorizations
  from public, authenticated, service_role;

comment on column public.fit_evaluations.eligibility_context_evaluation_id is
  'Display-only adjacent Phase 2 context. Excluded from Fit manifests, signals, reasons, and decision fingerprints. ON DELETE SET NULL so Eligibility history can be retired without destroying Fit.';

create table public.fit_manifest_items (
  manifest_item_id uuid primary key default extensions.gen_random_uuid(),
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  method_id uuid not null,
  input_policy_id uuid not null,
  item_type public.fit_manifest_item_type not null,
  authority_role public.fit_manifest_authority_role not null,
  source_class_code text not null
    references public.fit_semantic_source_classes(source_class_code)
    on delete restrict,
  created_at timestamptz not null default now(),
  unique (manifest_item_id, evaluation_id),
  unique (manifest_item_id, evaluation_id, profile_version_id),
  unique (evaluation_id, manifest_item_id, item_type),
  foreign key (evaluation_id, profile_version_id)
    references public.fit_evaluations(evaluation_id, profile_version_id)
    on delete cascade,
  foreign key (method_id)
    references public.fit_dimension_methods(method_id) on delete restrict,
  foreign key (evaluation_id, method_id)
    references public.fit_evaluation_methods(evaluation_id, method_id)
    on delete cascade,
  foreign key (input_policy_id)
    references public.fit_method_input_policies(input_policy_id) on delete restrict
);

comment on table public.fit_manifest_items is
  'Typed evidence envelope only. It is not a generic fact or feature warehouse.';

create table public.fit_manifest_intent_declarations (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  method_id uuid not null,
  intent_declaration_id uuid not null,
  intent_set_id uuid not null,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  foreign key (intent_declaration_id, intent_set_id, profile_version_id)
    references public.fit_intent_declarations(
      intent_declaration_id, intent_set_id, profile_version_id
    ) on delete cascade,
  unique (evaluation_id, method_id, intent_declaration_id),
  foreign key (method_id)
    references public.fit_dimension_methods(method_id) on delete restrict
);

create or replace function public.assign_fit_manifest_intent_method()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  select method_id into new.method_id
  from public.fit_manifest_items
  where manifest_item_id = new.manifest_item_id
    and evaluation_id = new.evaluation_id;
  if new.method_id is null then
    raise exception using errcode='23503',
      message='Intent manifest subtype requires its parent manifest item';
  end if;
  return new;
end;
$$;

create trigger fit_manifest_intent_assign_method
before insert on public.fit_manifest_intent_declarations
for each row execute function public.assign_fit_manifest_intent_method();

create table public.fit_manifest_student_access_contexts (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  access_context_id uuid not null
    references private.fit_student_access_contexts(access_context_id) on delete cascade,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  unique (evaluation_id, access_context_id, manifest_item_id)
);

create table public.fit_manifest_phase2_goals (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  student_goal_id uuid not null,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  foreign key (profile_version_id, student_goal_id)
    references public.student_goals(profile_version_id, student_goal_id) on delete cascade,
  unique (evaluation_id, student_goal_id, manifest_item_id)
);

create table public.fit_manifest_phase2_preferences (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  student_preference_id uuid not null,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  foreign key (profile_version_id, student_preference_id)
    references public.student_preferences(profile_version_id, student_preference_id)
    on delete cascade,
  unique (evaluation_id, student_preference_id, manifest_item_id)
);

create table public.fit_manifest_phase2_courses (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  student_course_id uuid not null,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  foreign key (profile_version_id, student_course_id)
    references public.student_courses(profile_version_id, student_course_id)
    on delete cascade,
  unique (evaluation_id, student_course_id, manifest_item_id)
);

create table public.fit_manifest_phase2_completeness (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  completeness_id uuid not null,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  foreign key (profile_version_id, completeness_id)
    references public.student_data_completeness(profile_version_id, completeness_id)
    on delete cascade,
  unique (evaluation_id, completeness_id, manifest_item_id)
);

create table public.fit_manifest_phase2_mappings (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  student_mapping_id uuid not null,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  foreign key (profile_version_id, student_mapping_id)
    references public.student_record_concept_mappings(
      profile_version_id, student_mapping_id
    ) on delete cascade,
  unique (evaluation_id, student_mapping_id, manifest_item_id)
);

create table public.fit_manifest_catalog_observations (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  field_observation_id uuid not null
    references public.field_observations(observation_id) on delete restrict,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  unique (evaluation_id, field_observation_id, manifest_item_id)
);

create table public.fit_manifest_catalog_mappings (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  catalog_mapping_id uuid not null
    references public.catalog_concept_mappings(mapping_id) on delete restrict,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  unique (evaluation_id, catalog_mapping_id, manifest_item_id)
);

create table public.fit_manifest_taxonomy_concepts (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  unique (evaluation_id, concept_id, manifest_item_id)
);

create table public.fit_manifest_context_claim_selections (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  context_claim_id uuid not null
    references public.fit_context_claims(context_claim_id) on delete restrict,
  context_selection_id uuid not null,
  context_observation_id uuid,
  knowledge_status public.knowledge_status not null,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  foreign key (context_selection_id, context_claim_id)
    references public.fit_context_claim_selection_history(
      context_selection_id, context_claim_id
    ) on delete restrict,
  foreign key (context_observation_id, context_claim_id)
    references public.fit_context_claim_observations(
      context_observation_id, context_claim_id
    ) on delete restrict,
  unique (evaluation_id, context_claim_id, manifest_item_id)
);

create table public.fit_manifest_context_mappings (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  context_mapping_id uuid not null
    references public.fit_context_concept_mappings(context_mapping_id) on delete restrict,
  mapping_status_at_pin public.mapping_status not null,
  mapping_reviewed_at_at_pin timestamptz not null,
  mapping_verification_evidence_id_at_pin uuid not null
    references public.evidence_items(evidence_id) on delete restrict,
  mapping_retired_at_at_pin timestamptz,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  unique (evaluation_id, context_mapping_id, manifest_item_id)
);

create or replace function public.pin_fit_context_mapping_authority()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  select
    mapping.mapping_status,
    mapping.reviewed_at,
    mapping.verification_evidence_id,
    mapping.retired_at
  into
    new.mapping_status_at_pin,
    new.mapping_reviewed_at_at_pin,
    new.mapping_verification_evidence_id_at_pin,
    new.mapping_retired_at_at_pin
  from public.fit_context_concept_mappings mapping
  where mapping.context_mapping_id = new.context_mapping_id;
  if new.mapping_status_at_pin <> 'VERIFIED'
     or new.mapping_retired_at_at_pin is not null then
    raise exception using errcode='55000',
      message='Only active VERIFIED context mappings may be pinned';
  end if;
  return new;
end;
$$;

create trigger fit_manifest_context_mappings_pin_authority
before insert on public.fit_manifest_context_mappings
for each row execute function public.pin_fit_context_mapping_authority();

create table public.fit_manifest_student_field_uses (
  manifest_item_id uuid not null,
  evaluation_id uuid not null,
  field_name public.fit_student_field_name not null,
  primary key (manifest_item_id, field_name),
  foreign key (manifest_item_id, evaluation_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id)
    on delete cascade
);

comment on table public.fit_manifest_student_field_uses is
  'Exact allowlisted Phase 2 fields supplied to a method; priority, GPA, grades, tests, experience, and skills cannot be represented.';

create table public.fit_financial_normalizations (
  financial_normalization_id uuid primary key default extensions.gen_random_uuid(),
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  field_observation_id uuid not null
    references public.field_observations(observation_id) on delete restrict,
  financial_constraint_id uuid not null
    references public.fit_intent_financial_constraints(intent_declaration_id)
    on delete cascade,
  intent_set_id uuid not null,
  normalization_method_id uuid not null
    references public.fit_financial_normalization_methods(normalization_method_id)
    on delete restrict,
  conversion_evidence_id uuid not null
    references public.evidence_items(evidence_id) on delete restrict,
  original_amount numeric(14,2) not null,
  original_currency char(3) not null,
  original_period public.fit_financial_period not null,
  original_scope public.fit_financial_scope not null,
  original_basis public.fit_financial_basis not null,
  original_components text[] not null,
  target_amount numeric(14,2) not null,
  target_currency char(3) not null,
  target_period public.fit_financial_period not null,
  target_scope public.fit_financial_scope not null,
  target_basis public.fit_financial_basis not null,
  target_components text[] not null,
  conversion_evidence jsonb not null,
  created_at timestamptz not null default now(),
  foreign key (evaluation_id, profile_version_id)
    references public.fit_evaluations(evaluation_id, profile_version_id)
    on delete cascade,
  constraint fit_financial_normalizations_amounts check (
    original_amount >= 0 and target_amount >= 0
  ),
  constraint fit_financial_normalizations_currencies check (
    original_currency ~ '^[A-Z]{3}$' and target_currency ~ '^[A-Z]{3}$'
  ),
  constraint fit_financial_normalizations_components check (
    cardinality(original_components) > 0
    and cardinality(target_components) > 0
    and array_position(original_components, null) is null
    and array_position(target_components, null) is null
    and array_position(original_components, '') is null
    and array_position(target_components, '') is null
    and public.fit_text_array_is_set(original_components)
    and public.fit_text_array_is_set(target_components)
  ),
  constraint fit_financial_normalizations_evidence check (
    jsonb_typeof(conversion_evidence) = 'object'
    and conversion_evidence <> '{}'::jsonb
  ),
  unique (evaluation_id, financial_normalization_id)
);

comment on table public.fit_financial_normalizations is
  'Evaluation-scoped derivation only; it never writes normalized values upstream.';

create table public.fit_manifest_financial_normalizations (
  manifest_item_id uuid primary key,
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  financial_normalization_id uuid not null,
  foreign key (manifest_item_id, evaluation_id, profile_version_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id, profile_version_id)
    on delete cascade,
  foreign key (evaluation_id, financial_normalization_id)
    references public.fit_financial_normalizations(
      evaluation_id, financial_normalization_id
    ) on delete cascade,
  unique (evaluation_id, financial_normalization_id, manifest_item_id)
);

create table public.fit_input_domain_states (
  input_state_id uuid primary key default extensions.gen_random_uuid(),
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  method_id uuid not null
    references public.fit_dimension_methods(method_id) on delete restrict,
  input_policy_id uuid not null
    references public.fit_method_input_policies(input_policy_id) on delete restrict,
  availability public.fit_input_availability not null,
  completeness_manifest_item_id uuid,
  provenance_manifest_item_id uuid,
  explanation text,
  created_at timestamptz not null default now(),
  foreign key (evaluation_id, profile_version_id)
    references public.fit_evaluations(evaluation_id, profile_version_id)
    on delete cascade,
  foreign key (completeness_manifest_item_id, evaluation_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id)
    on delete cascade,
  foreign key (provenance_manifest_item_id, evaluation_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id)
    on delete cascade,
  constraint fit_input_states_explanation check (
    availability = 'INCLUDED' or nullif(btrim(explanation), '') is not null
  ),
  constraint fit_input_states_provenance_required check (
    (availability = 'INCOMPLETE'
      and completeness_manifest_item_id is not null)
    or (availability in ('STALE_SOURCE', 'SOURCE_CONFLICT')
      and provenance_manifest_item_id is not null)
    or availability not in (
      'INCOMPLETE', 'STALE_SOURCE', 'SOURCE_CONFLICT'
    )
  ),
  unique (evaluation_id, method_id, input_policy_id),
  unique (input_state_id, evaluation_id)
);

comment on column public.fit_input_domain_states.completeness_manifest_item_id is
  'Optional pointer to the preserved Phase 2 completeness row; Fit does not reinterpret its value.';

create table public.fit_dimension_results (
  dimension_result_id uuid primary key default extensions.gen_random_uuid(),
  evaluation_id uuid not null
    references public.fit_evaluations(evaluation_id) on delete cascade,
  dimension public.fit_dimension not null,
  assessment public.fit_assessment not null,
  confidence public.fit_confidence not null,
  evidence_coverage public.fit_coverage not null,
  method_id uuid not null
    references public.fit_dimension_methods(method_id) on delete restrict,
  inference_category public.fit_inference_category not null,
  presentation_explanation text,
  created_at timestamptz not null default now(),
  constraint fit_dimension_results_explanation check (
    presentation_explanation is null or btrim(presentation_explanation) <> ''
  ),
  foreign key (evaluation_id, dimension, method_id)
    references public.fit_evaluation_methods(
      evaluation_id, dimension, method_id
    ) on delete cascade,
  unique (evaluation_id, dimension),
  unique (dimension_result_id, evaluation_id)
);

comment on column public.fit_dimension_results.presentation_explanation is
  'Non-authoritative short presentation text. Structured reasons and evidence govern semantics.';

create table public.fit_signals (
  signal_id uuid primary key default extensions.gen_random_uuid(),
  evaluation_id uuid not null,
  dimension_result_id uuid not null,
  dimension public.fit_dimension not null,
  method_id uuid not null,
  signal_type_id uuid not null,
  direction public.fit_reason_direction not null,
  material boolean not null default false,
  inference_category public.fit_inference_category not null,
  model_version text,
  model_build_hash text,
  evidence_metadata jsonb not null default '{}'::jsonb,
  intent_declaration_id uuid,
  required_constraint_contradiction boolean not null default false,
  international_high_impact boolean not null default false,
  created_at timestamptz not null default now(),
  foreign key (dimension_result_id, evaluation_id)
    references public.fit_dimension_results(dimension_result_id, evaluation_id)
    on delete cascade,
  foreign key (signal_type_id, method_id)
    references public.fit_signal_types(signal_type_id, method_id)
    on delete restrict,
  foreign key (evaluation_id, method_id, intent_declaration_id)
    references public.fit_manifest_intent_declarations(
      evaluation_id, method_id, intent_declaration_id
    ) on delete cascade,
  constraint fit_signals_metadata check (jsonb_typeof(evidence_metadata) = 'object'),
  constraint fit_signals_model_hash check (
    (
      inference_category = 'MODEL'
      and nullif(btrim(model_version), '') is not null
      and model_build_hash ~ '^[a-f0-9]{64}$'
    )
    or (
      inference_category <> 'MODEL'
      and (model_build_hash is null
        or model_build_hash ~ '^[a-f0-9]{64}$')
    )
  ),
  constraint fit_signals_required_contradiction check (
    not required_constraint_contradiction
    or (material and direction = 'CONTRADICTING' and intent_declaration_id is not null)
  ),
  constraint fit_signals_high_impact_dimension check (
    not international_high_impact or dimension = 'INTERNATIONAL_ACCESSIBILITY'
  ),
  unique (signal_id, evaluation_id)
);

create table public.fit_signal_evidence (
  signal_id uuid not null,
  evaluation_id uuid not null,
  manifest_item_id uuid not null,
  primary key (signal_id, manifest_item_id),
  foreign key (signal_id, evaluation_id)
    references public.fit_signals(signal_id, evaluation_id) on delete cascade,
  foreign key (manifest_item_id, evaluation_id)
    references public.fit_manifest_items(manifest_item_id, evaluation_id)
    on delete cascade
);

create table public.fit_dimension_reasons (
  dimension_reason_id uuid primary key default extensions.gen_random_uuid(),
  dimension_result_id uuid not null,
  evaluation_id uuid not null,
  reason_definition_id uuid not null
    references public.fit_reason_definitions(reason_definition_id) on delete restrict,
  direction public.fit_reason_direction not null,
  signal_id uuid,
  input_state_id uuid,
  presentation_explanation text,
  created_at timestamptz not null default now(),
  foreign key (dimension_result_id, evaluation_id)
    references public.fit_dimension_results(dimension_result_id, evaluation_id)
    on delete cascade,
  foreign key (signal_id, evaluation_id)
    references public.fit_signals(signal_id, evaluation_id) on delete cascade,
  foreign key (input_state_id, evaluation_id)
    references public.fit_input_domain_states(input_state_id, evaluation_id)
    on delete cascade,
  constraint fit_dimension_reasons_source check (
    signal_id is not null or input_state_id is not null
  ),
  constraint fit_dimension_reasons_explanation check (
    presentation_explanation is null or btrim(presentation_explanation) <> ''
  )
);

comment on column public.fit_dimension_reasons.presentation_explanation is
  'Non-authoritative presentation text; the verified reason definition and exact links are authoritative.';

create index fit_evaluations_profile_idx
  on public.fit_evaluations(profile_version_id, created_at desc);
create index fit_evaluations_program_idx
  on public.fit_evaluations(program_version_id, created_at desc);
create index fit_manifest_evaluation_idx
  on public.fit_manifest_items(evaluation_id, method_id, item_type);
create index fit_input_states_evaluation_idx
  on public.fit_input_domain_states(evaluation_id, method_id);
create index fit_results_evaluation_idx
  on public.fit_dimension_results(evaluation_id, dimension);
create index fit_signals_result_idx
  on public.fit_signals(dimension_result_id, material, direction);
create index fit_signal_evidence_item_idx
  on public.fit_signal_evidence(manifest_item_id);
create index fit_reasons_result_idx
  on public.fit_dimension_reasons(dimension_result_id);

create or replace function public.validate_fit_evaluation_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.student_profile_versions%rowtype;
  v_intent public.fit_intent_sets%rowtype;
begin
  select * into v_profile from public.student_profile_versions
  where profile_version_id = new.profile_version_id;
  if v_profile.status is distinct from 'FROZEN'
     or v_profile.snapshot_hash is distinct from new.profile_snapshot_hash then
    raise exception 'Fit evaluation must pin the matching frozen profile snapshot';
  end if;
  select * into v_intent from public.fit_intent_sets
  where intent_set_id = new.intent_set_id
    and profile_version_id = new.profile_version_id;
  if v_intent.status is distinct from 'FROZEN'
     or v_intent.snapshot_hash is distinct from new.intent_snapshot_hash then
    raise exception 'Fit evaluation must pin the matching frozen intent snapshot';
  end if;
  if not exists (
    select 1 from public.fit_contract_releases r
    where r.contract_release_id = new.contract_release_id
      and r.release_code = new.input_schema_version
      and r.status = 'VERIFIED' and r.retired_at is null
  ) then
    raise exception 'Fit evaluation requires the active VERIFIED fit-v0.1 contract';
  end if;
  if not exists (
    select 1 from public.fit_evaluator_builds build
    where build.evaluator_build_id = new.evaluator_build_id
      and build.contract_release_id = new.contract_release_id
      and build.evaluator_name = new.evaluator_name
      and build.evaluator_version = new.evaluator_version
      and build.build_hash = new.evaluator_build_hash
      and build.status = 'VERIFIED'
      and build.retired_at is null
  ) then
    raise exception 'Fit evaluation requires an exact active VERIFIED evaluator build';
  end if;
  if new.supersedes_evaluation_id is not null and not exists (
    select 1 from public.fit_evaluations e
    where e.evaluation_id = new.supersedes_evaluation_id
      and e.profile_version_id = new.profile_version_id
      and e.program_version_id = new.program_version_id
      and e.evaluation_state = 'COMPLETED'
  ) then
    raise exception 'Superseded Fit evaluation must be completed for the same profile and program';
  end if;
  if new.eligibility_context_evaluation_id is not null and not exists (
    select 1
    from public.eligibility_evaluations ee
    join public.program_requirement_rule_sets rs using (rule_set_id)
    where ee.evaluation_id = new.eligibility_context_evaluation_id
      and ee.evaluation_state = 'COMPLETED'
      and ee.profile_version_id = new.profile_version_id
      and rs.program_version_id = new.program_version_id
  ) then
    raise exception 'Eligibility context must be completed for the same profile and program version';
  end if;
  return new;
end;
$$;

create or replace function public.pin_fit_evaluation_methods()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.fit_evaluation_methods (
    evaluation_id, dimension, method_id, contract_release_id
  )
  select
    new.evaluation_id, method.dimension, method.method_id,
    method.contract_release_id
  from public.fit_dimension_methods method
  where method.contract_release_id = new.contract_release_id
    and method.status = 'VERIFIED'
    and method.retired_at is null;

  if (
    select count(*) from public.fit_evaluation_methods
    where evaluation_id = new.evaluation_id
  ) <> 6 then
    raise exception 'Fit evaluation requires exactly six active VERIFIED dimension methods';
  end if;
  return new;
end;
$$;

create or replace function public.guard_fit_evaluation_methods()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE'
     and current_setting('app.student_privacy_delete', true) = 'on' then
    return old;
  end if;
  raise exception using errcode='55000',
    message='Pinned Fit evaluation methods are immutable';
end;
$$;

create or replace function public.guard_fit_evaluation_row()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE'
     and current_setting('app.student_privacy_delete', true) = 'on' then
    return old;
  end if;
  if tg_op = 'UPDATE'
     and current_setting('app.fit_evaluation_controlled_write', true) = 'on'
     and old.evaluation_state = 'BUILDING'
     and new.evaluation_state in ('BUILDING', 'COMPLETED') then
    return new;
  end if;
  raise exception 'Fit evaluations are immutable and finalize through finalize_fit_evaluation()';
end;
$$;

create or replace function public.guard_fit_evaluation_assembly()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row jsonb;
  v_evaluation_id uuid;
  v_state public.fit_evaluation_state;
  v_candidate_fingerprint text;
begin
  if tg_op = 'DELETE'
     and current_setting('app.student_privacy_delete', true) = 'on' then
    return old;
  end if;
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_evaluation_id := (v_row ->> 'evaluation_id')::uuid;
  select evaluation_state, candidate_input_fingerprint
  into v_state, v_candidate_fingerprint
  from public.fit_evaluations
  where evaluation_id = v_evaluation_id
  for share;
  if v_state is distinct from 'BUILDING' then
    raise exception 'Fit evaluation assembly is allowed only while BUILDING';
  end if;
  if tg_table_name in (
    'fit_manifest_items',
    'fit_manifest_intent_declarations',
    'fit_manifest_student_access_contexts',
    'fit_manifest_phase2_goals',
    'fit_manifest_phase2_preferences',
    'fit_manifest_phase2_courses',
    'fit_manifest_phase2_completeness',
    'fit_manifest_phase2_mappings',
    'fit_manifest_catalog_observations',
    'fit_manifest_catalog_mappings',
    'fit_manifest_taxonomy_concepts',
    'fit_manifest_context_claim_selections',
    'fit_manifest_context_mappings',
    'fit_manifest_student_field_uses',
    'fit_financial_normalizations',
    'fit_manifest_financial_normalizations',
    'fit_input_domain_states'
  ) and v_candidate_fingerprint is not null then
    raise exception 'Fit decision inputs are immutable after candidate input sealing';
  end if;
  if not exists (
    select 1
    from private.fit_evaluation_assembly_authorizations authz
    join public.fit_evaluations evaluation
      on evaluation.evaluation_id = authz.evaluation_id
    where authz.evaluation_id = v_evaluation_id
      and authz.execution_id = evaluation.execution_id
      and authz.evaluator_build_id =
        evaluation.evaluator_build_id
      and authz.evaluator_build_hash =
        evaluation.evaluator_build_hash
  ) then
    raise exception using errcode='42501',
      message='No durable assembly authorization exists for this evaluation execution';
  end if;
  return coalesce(new, old);
end;
$$;

create or replace function public.validate_fit_financial_normalization()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eval public.fit_evaluations%rowtype;
  v_method public.fit_financial_normalization_methods%rowtype;
  v_observation public.field_observations%rowtype;
  v_program_cost public.program_costs%rowtype;
  v_constraint public.fit_intent_financial_constraints%rowtype;
begin
  select * into v_eval from public.fit_evaluations
  where evaluation_id = new.evaluation_id;
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
     or (v_method.source_currency is not null
       and v_method.source_currency <> new.original_currency)
     or (v_method.target_currency is not null
       and v_method.target_currency <> new.target_currency) then
    raise exception 'Financial normalization must exactly satisfy a VERIFIED method';
  end if;
  select * into v_observation from public.field_observations
  where observation_id = new.field_observation_id;
  if v_observation.knowledge_status <> 'KNOWN'
     or jsonb_typeof(v_observation.observed_value) is distinct from 'number'
     or (
       jsonb_typeof(v_observation.observed_value) = 'number'
       and (v_observation.observed_value #>> '{}')::numeric
         is distinct from new.original_amount
     )
     or not exists (
       select 1 from public.canonical_field_selections c
       where c.observation_id = v_observation.observation_id
     )
     or (
       public.catalog_record_program_version(
         v_observation.record_type, v_observation.record_id
       ) is distinct from v_eval.program_version_id
       and not (
         v_observation.record_type = 'PROGRAM'
         and exists (
           select 1 from public.program_versions pv
           where pv.program_version_id = v_eval.program_version_id
             and pv.program_id = v_observation.record_id
         )
       )
     ) then
    raise exception 'Financial normalization requires a selected KNOWN numeric program amount equal to original_amount';
  end if;
  if v_observation.record_type <> 'PROGRAM_COST'
     or v_observation.field_name not in (
       'tuition_amount', 'mandatory_fees',
       'estimated_living_cost', 'estimated_total_cost'
     ) then
    raise exception using errcode='23514',
      message='Financial normalization requires an approved Phase 1 program-cost amount field';
  end if;
  select * into v_program_cost
  from public.program_costs
  where cost_id = v_observation.record_id;
  if v_program_cost.currency is distinct from new.original_currency
     or new.original_period <> 'ACADEMIC_YEAR'
     or new.original_basis <> 'GROSS'
     or new.original_scope is distinct from (case v_observation.field_name
       when 'estimated_total_cost' then 'TOTAL_COST'::public.fit_financial_scope
       else 'COMPONENT'::public.fit_financial_scope
     end)
     or new.original_components <> array[
       case v_observation.field_name
         when 'tuition_amount' then 'TUITION'
         when 'mandatory_fees' then 'MANDATORY_FEES'
         when 'estimated_living_cost' then 'LIVING_COST'
         when 'estimated_total_cost' then 'TOTAL_COST'
       end
     ]::text[] then
    raise exception using errcode='23514',
      message='Financial normalization original metadata must match the selected Phase 1 cost fact';
  end if;
  select * into v_constraint
  from public.fit_intent_financial_constraints c
  where c.intent_declaration_id = new.financial_constraint_id
    and c.intent_set_id = v_eval.intent_set_id
    and c.profile_version_id = new.profile_version_id;
  if not found then
    raise exception 'Financial normalization constraint is outside the frozen evaluation intent';
  end if;
  if new.target_currency is distinct from v_constraint.currency
     or new.target_period is distinct from v_constraint.financial_period
     or new.target_scope is distinct from v_constraint.financial_scope
     or new.target_basis is distinct from v_constraint.financial_basis
     or (
       select array_agg(component order by component)
       from unnest(new.target_components) component
     ) is distinct from (
       select array_agg(component order by component)
       from unnest(v_constraint.components) component
     ) then
    raise exception using errcode='23514',
      message='Financial normalization target metadata must match the frozen student constraint';
  end if;
  return new;
end;
$$;

create or replace function public.assign_fit_manifest_source_class()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dimension public.fit_dimension;
  v_expected text;
begin
  select dimension into v_dimension
  from public.fit_dimension_methods
  where method_id = new.method_id;
  v_expected := case new.item_type
    when 'FIT_INTENT_DECLARATION' then 'STUDENT_RAW_INTENT'
    when 'FIT_STUDENT_ACCESS_CONTEXT' then 'STUDENT_RAW_ACCESS_CONTEXT'
    when 'PHASE2_STUDENT_GOAL' then 'STUDENT_RAW_INTENT'
    when 'PHASE2_STUDENT_PREFERENCE' then 'STUDENT_RAW_INTENT'
    when 'PHASE2_STUDENT_COURSE' then 'STUDENT_RAW_ACADEMIC_HISTORY'
    when 'PHASE2_STUDENT_COMPLETENESS' then case v_dimension
      when 'ACADEMIC' then 'STUDENT_RAW_ACADEMIC_HISTORY'
      when 'INTERNATIONAL_ACCESSIBILITY' then 'STUDENT_RAW_ACCESS_CONTEXT'
      else 'STUDENT_RAW_INTENT'
    end
    when 'PHASE2_STUDENT_MAPPING' then 'TAXONOMY_MAPPING'
    when 'CATALOG_FIELD_OBSERVATION' then 'PROGRAM_CANONICAL_FACT'
    when 'CATALOG_MAPPING' then 'TAXONOMY_MAPPING'
    when 'TAXONOMY_CONCEPT' then 'TAXONOMY_MAPPING'
    when 'FIT_CONTEXT_CLAIM_SELECTION' then new.source_class_code
    when 'FIT_CONTEXT_MAPPING' then new.source_class_code
    when 'FIT_FINANCIAL_NORMALIZATION' then 'FIT_CONTEXT_FINANCIAL'
  end;
  if v_expected is null then
    raise exception 'Manifest item type has no approved semantic source class for its method';
  end if;
  if new.source_class_code is not null
     and new.source_class_code <> v_expected then
    raise exception 'Manifest semantic source class cannot override its underlying source';
  end if;
  new.source_class_code := v_expected;
  return new;
end;
$$;

create or replace function public.validate_fit_signal()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_result public.fit_dimension_results%rowtype;
  v_signal_type public.fit_signal_types%rowtype;
begin
  select * into v_result
  from public.fit_dimension_results
  where dimension_result_id = new.dimension_result_id
    and evaluation_id = new.evaluation_id;
  select * into v_signal_type
  from public.fit_signal_types
  where signal_type_id = new.signal_type_id
    and method_id = new.method_id;
  if v_result.dimension_result_id is null
     or v_signal_type.signal_type_id is null
     or v_result.dimension <> new.dimension
     or v_result.method_id <> new.method_id
     or v_signal_type.direction <> new.direction
     or v_signal_type.material <> new.material
     or not new.inference_category =
       any(v_signal_type.allowed_inference_categories) then
    raise exception 'Signal method, direction, materiality, and inference must match its result and registered signal type';
  end if;
  return new;
end;
$$;

create or replace function public.compute_fit_decision_input_fingerprint(
  p_evaluation_id uuid
)
returns text
language sql
stable
security definer
set search_path = public, private, extensions, pg_temp
as $$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
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
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  )
  from public.fit_evaluations evaluation
  where evaluation.evaluation_id = p_evaluation_id;
$$;

create or replace function public.compute_fit_result_fingerprint(
  p_evaluation_id uuid
)
returns text
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'decisionInputFingerprint', (
            select candidate_input_fingerprint
            from public.fit_evaluations
            where evaluation_id = p_evaluation_id
          ),
          'results', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'dimension', result.dimension,
                'assessment', result.assessment,
                'confidence', result.confidence,
                'coverage', result.evidence_coverage,
                'methodId', result.method_id,
                'inferenceCategory', result.inference_category
              )
              order by result.dimension
            )
            from public.fit_dimension_results result
            where result.evaluation_id = p_evaluation_id
          ), '[]'::jsonb),
          'signals', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'dimension', signal.dimension,
                'methodId', signal.method_id,
                'signalTypeId', signal.signal_type_id,
                'direction', signal.direction,
                'material', signal.material,
                'inferenceCategory', signal.inference_category,
                'modelVersion', signal.model_version,
                'modelBuildHash', signal.model_build_hash,
                'intentId', signal.intent_declaration_id,
                'requiredContradiction',
                  signal.required_constraint_contradiction,
                'internationalHighImpact',
                  signal.international_high_impact,
                'evidence', coalesce((
                  select jsonb_agg(
                    evidence.manifest_item_id
                    order by evidence.manifest_item_id
                  )
                  from public.fit_signal_evidence evidence
                  where evidence.signal_id = signal.signal_id
                ), '[]'::jsonb)
              )
              order by
                signal.dimension, signal.signal_type_id,
                signal.inference_category, signal.intent_declaration_id
                nulls first
            )
            from public.fit_signals signal
            where signal.evaluation_id = p_evaluation_id
          ), '[]'::jsonb),
          'reasons', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'dimension', result.dimension,
                'definitionId', reason.reason_definition_id,
                'direction', reason.direction,
                'signalTypeId', signal.signal_type_id,
                'inputPolicyId', state.input_policy_id
              )
              order by
                result.dimension, reason.reason_definition_id,
                signal.signal_type_id nulls first,
                state.input_policy_id nulls first
            )
            from public.fit_dimension_reasons reason
            join public.fit_dimension_results result
              on result.dimension_result_id = reason.dimension_result_id
            left join public.fit_signals signal
              on signal.signal_id = reason.signal_id
            left join public.fit_input_domain_states state
              on state.input_state_id = reason.input_state_id
            where reason.evaluation_id = p_evaluation_id
          ), '[]'::jsonb)
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
$$;

create or replace function public.authorize_fit_evaluation_assembly(
  p_evaluation_id uuid,
  p_evaluator_build_hash text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.fit_evaluations evaluation
    join public.fit_evaluator_builds build
      on build.evaluator_build_id = evaluation.evaluator_build_id
    where evaluation.evaluation_id = p_evaluation_id
      and evaluation.evaluation_state = 'BUILDING'
      and evaluation.evaluator_build_hash = p_evaluator_build_hash
      and build.status = 'VERIFIED'
      and build.retired_at is null
  ) then
    raise exception 'Assembly authorization requires a BUILDING evaluation with its active VERIFIED evaluator build';
  end if;
  insert into private.fit_evaluation_assembly_authorizations (
    evaluation_id, execution_id, evaluator_build_id,
    evaluator_build_hash
  )
  select
    evaluation_id, execution_id, evaluator_build_id,
    evaluator_build_hash
  from public.fit_evaluations
  where evaluation_id = p_evaluation_id
  on conflict (evaluation_id) do update
  set execution_id = excluded.execution_id,
      evaluator_build_id = excluded.evaluator_build_id,
      evaluator_build_hash = excluded.evaluator_build_hash,
      authorized_at = now();
end;
$$;

create or replace function public.start_fit_evaluation(
  p_profile_version_id uuid,
  p_intent_set_id uuid,
  p_program_version_id uuid,
  p_taxonomy_release_code text,
  p_contract_release_id uuid,
  p_evaluator_build_id uuid,
  p_supersedes_evaluation_id uuid default null,
  p_eligibility_context_evaluation_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile_hash text;
  v_intent_hash text;
  v_build public.fit_evaluator_builds%rowtype;
  v_evaluation_id uuid;
begin
  select snapshot_hash into v_profile_hash
  from public.student_profile_versions
  where profile_version_id = p_profile_version_id
    and status = 'FROZEN';
  select snapshot_hash into v_intent_hash
  from public.fit_intent_sets
  where intent_set_id = p_intent_set_id
    and profile_version_id = p_profile_version_id
    and status = 'FROZEN';
  select * into v_build
  from public.fit_evaluator_builds
  where evaluator_build_id = p_evaluator_build_id
    and contract_release_id = p_contract_release_id
    and status = 'VERIFIED'
    and retired_at is null;
  if v_profile_hash is null or v_intent_hash is null or not found then
    raise exception 'Fit evaluation start requires frozen inputs and an active VERIFIED evaluator build';
  end if;
  insert into public.fit_evaluations (
    profile_version_id, profile_snapshot_hash,
    intent_set_id, intent_snapshot_hash,
    program_version_id, taxonomy_release_code, contract_release_id,
    evaluator_build_id, evaluator_name, evaluator_version,
    evaluator_build_hash, supersedes_evaluation_id,
    eligibility_context_evaluation_id
  ) values (
    p_profile_version_id, v_profile_hash,
    p_intent_set_id, v_intent_hash,
    p_program_version_id, p_taxonomy_release_code, p_contract_release_id,
    p_evaluator_build_id, v_build.evaluator_name, v_build.evaluator_version,
    v_build.build_hash, p_supersedes_evaluation_id,
    p_eligibility_context_evaluation_id
  ) returning evaluation_id into v_evaluation_id;
  return v_evaluation_id;
end;
$$;

create or replace function public.seal_fit_evaluation_inputs(
  p_evaluation_id uuid
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_fingerprint text;
  v_prior text;
begin
  if not exists (
    select 1 from public.fit_evaluations
    where evaluation_id = p_evaluation_id
      and evaluation_state = 'BUILDING'
      and candidate_input_fingerprint is null
  ) then
    raise exception 'An unsealed BUILDING Fit evaluation is required';
  end if;
  v_fingerprint :=
    public.compute_fit_decision_input_fingerprint(p_evaluation_id);
  v_prior :=
    current_setting('app.fit_evaluation_controlled_write', true);
  perform set_config('app.fit_evaluation_controlled_write', 'on', true);
  update public.fit_evaluations
  set candidate_input_fingerprint = v_fingerprint
  where evaluation_id = p_evaluation_id;
  delete from private.fit_evaluation_assembly_authorizations
  where evaluation_id = p_evaluation_id;
  perform set_config(
    'app.fit_evaluation_controlled_write', coalesce(v_prior, ''), true
  );
  return v_fingerprint;
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

create trigger fit_evaluations_validate
before insert on public.fit_evaluations
for each row execute function public.validate_fit_evaluation_insert();
create trigger fit_evaluations_pin_methods
after insert on public.fit_evaluations
for each row execute function public.pin_fit_evaluation_methods();
create trigger fit_evaluation_methods_immutable
before update or delete on public.fit_evaluation_methods
for each row execute function public.guard_fit_evaluation_methods();
create trigger fit_evaluations_guard
before update or delete on public.fit_evaluations
for each row execute function public.guard_fit_evaluation_row();
create trigger fit_financial_normalizations_validate
before insert or update on public.fit_financial_normalizations
for each row execute function public.validate_fit_financial_normalization();
create trigger fit_manifest_items_assign_source_class
before insert or update on public.fit_manifest_items
for each row execute function public.assign_fit_manifest_source_class();
create trigger fit_signals_validate
before insert or update on public.fit_signals
for each row execute function public.validate_fit_signal();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fit_manifest_items',
    'fit_manifest_intent_declarations',
    'fit_manifest_student_access_contexts',
    'fit_manifest_phase2_goals',
    'fit_manifest_phase2_preferences',
    'fit_manifest_phase2_courses',
    'fit_manifest_phase2_completeness',
    'fit_manifest_phase2_mappings',
    'fit_manifest_catalog_observations',
    'fit_manifest_catalog_mappings',
    'fit_manifest_taxonomy_concepts',
    'fit_manifest_context_claim_selections',
    'fit_manifest_context_mappings',
    'fit_manifest_student_field_uses',
    'fit_financial_normalizations',
    'fit_manifest_financial_normalizations',
    'fit_input_domain_states',
    'fit_dimension_results',
    'fit_signals',
    'fit_signal_evidence',
    'fit_dimension_reasons'
  ]
  loop
    execute format(
      'create trigger %I before insert or update or delete on public.%I
       for each row execute function public.guard_fit_evaluation_assembly()',
      v_table||'_assembly_guard',v_table
    );
  end loop;
end;
$$;

revoke all on function public.validate_fit_evaluation_insert() from public;
revoke all on function public.pin_fit_evaluation_methods() from public;
revoke all on function public.guard_fit_evaluation_methods() from public;
revoke all on function public.guard_fit_evaluation_row() from public;
revoke all on function public.guard_fit_evaluation_assembly() from public;
revoke all on function public.validate_fit_financial_normalization() from public;
revoke all on function public.validate_fit_signal() from public;
revoke all on function public.assign_fit_manifest_source_class() from public;
revoke all on function public.assign_fit_manifest_intent_method() from public;
revoke all on function public.pin_fit_context_mapping_authority() from public;
revoke all on function public.finalize_fit_evaluation(uuid) from public;
revoke all on function public.compute_fit_decision_input_fingerprint(uuid)
  from public;
revoke all on function public.compute_fit_result_fingerprint(uuid)
  from public;
revoke all on function public.authorize_fit_evaluation_assembly(uuid, text)
  from public;
revoke all on function public.start_fit_evaluation(
  uuid, uuid, uuid, text, uuid, uuid, uuid, uuid
) from public;
revoke all on function public.seal_fit_evaluation_inputs(uuid) from public;
grant execute on function public.validate_fit_evaluation_insert() to service_role;
grant execute on function public.guard_fit_evaluation_row() to service_role;
grant execute on function public.guard_fit_evaluation_assembly() to service_role;
grant execute on function public.validate_fit_financial_normalization()
  to service_role;
grant execute on function public.validate_fit_signal() to service_role;
grant execute on function public.assign_fit_manifest_source_class()
  to service_role;
grant execute on function public.finalize_fit_evaluation(uuid) to service_role;
grant execute on function public.compute_fit_decision_input_fingerprint(uuid)
  to service_role;
grant execute on function public.compute_fit_result_fingerprint(uuid)
  to service_role;
grant execute on function public.authorize_fit_evaluation_assembly(uuid, text)
  to service_role;
grant execute on function public.start_fit_evaluation(
  uuid, uuid, uuid, text, uuid, uuid, uuid, uuid
) to service_role;
grant execute on function public.seal_fit_evaluation_inputs(uuid)
  to service_role;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fit_evaluations',
    'fit_evaluation_methods',
    'fit_manifest_items',
    'fit_manifest_intent_declarations',
    'fit_manifest_student_access_contexts',
    'fit_manifest_phase2_goals',
    'fit_manifest_phase2_preferences',
    'fit_manifest_phase2_courses',
    'fit_manifest_phase2_completeness',
    'fit_manifest_phase2_mappings',
    'fit_manifest_catalog_observations',
    'fit_manifest_catalog_mappings',
    'fit_manifest_taxonomy_concepts',
    'fit_manifest_context_claim_selections',
    'fit_manifest_context_mappings',
    'fit_manifest_student_field_uses',
    'fit_financial_normalizations',
    'fit_manifest_financial_normalizations',
    'fit_input_domain_states',
    'fit_dimension_results',
    'fit_signals',
    'fit_signal_evidence',
    'fit_dimension_reasons'
  ]
  loop
    execute format('alter table public.%I enable row level security',v_table);
  end loop;
end;
$$;

create policy fit_evaluations_owner_read on public.fit_evaluations
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy fit_evaluations_service_write on public.fit_evaluations
  for all to service_role using (true) with check (true);

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fit_manifest_items',
    'fit_manifest_intent_declarations',
    'fit_manifest_student_access_contexts',
    'fit_manifest_phase2_goals',
    'fit_manifest_phase2_preferences',
    'fit_manifest_phase2_courses',
    'fit_manifest_phase2_completeness',
    'fit_manifest_phase2_mappings',
    'fit_manifest_catalog_observations',
    'fit_manifest_catalog_mappings',
    'fit_manifest_taxonomy_concepts',
    'fit_manifest_context_claim_selections',
    'fit_manifest_context_mappings',
    'fit_manifest_student_field_uses',
    'fit_financial_normalizations',
    'fit_manifest_financial_normalizations',
    'fit_input_domain_states',
    'fit_dimension_results',
    'fit_signals',
    'fit_signal_evidence',
    'fit_dimension_reasons'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated
       using (exists (
         select 1 from public.fit_evaluations e
         where e.evaluation_id=%I.evaluation_id
           and public.current_user_owns_profile(e.profile_version_id)
       ))',
      v_table||'_owner_read',v_table,v_table
    );
    execute format(
      'create policy %I on public.%I for all to service_role
       using (true) with check (true)',
      v_table||'_service_write',v_table
    );
    execute format(
      'grant select on public.%I to authenticated',
      v_table
    );
    execute format(
      'grant select, insert, update, delete on public.%I to service_role',
      v_table
    );
  end loop;
end;
$$;

grant select on public.fit_evaluations to authenticated, service_role;
grant select on public.fit_evaluation_methods to authenticated, service_role;
revoke insert, update, delete on public.fit_evaluations
  from authenticated, service_role;
revoke insert, update, delete on public.fit_evaluation_methods
  from authenticated, service_role;

create policy fit_evaluation_methods_owner_read
  on public.fit_evaluation_methods for select to authenticated
  using (
    exists (
      select 1 from public.fit_evaluations evaluation
      where evaluation.evaluation_id =
        fit_evaluation_methods.evaluation_id
        and public.current_user_owns_profile(
          evaluation.profile_version_id
        )
    )
  );
create policy fit_evaluation_methods_service_read
  on public.fit_evaluation_methods for select to service_role
  using (true);

-- Fit evaluation rows deliberately have no global audit trigger: private inputs
-- and derived output must disappear completely during student privacy deletion.

commit;
