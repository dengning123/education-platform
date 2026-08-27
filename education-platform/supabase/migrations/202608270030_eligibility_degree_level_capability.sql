-- Phase 4B: Eligibility HAS_DEGREE_LEVEL degree-only capability.
--
-- This additive migration introduces a separately versioned Eligibility input
-- contract.  It reuses the frozen M013 truth/projection/aggregation laws but
-- does not reinterpret any M013/M026 rule, input, result, or fingerprint.

begin;

do $preflight$
begin
  if exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'assemble_eligibility_evaluation_v030'
  ) then
    raise exception using errcode = '55000',
      message = '030 preflight failed: degree capability already exists';
  end if;
  if not exists (
    select 1
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname = 'assemble_eligibility_evaluation_v026'
  ) then
    raise exception using errcode = '55000',
      message = '030 preflight failed: M026 production assembly is required';
  end if;
  if exists (
    select 1 from pg_enum item
    join pg_type type on type.oid = item.enumtypid
    join pg_namespace namespace on namespace.oid = type.typnamespace
    where namespace.nspname = 'public'
      and type.typname = 'requirement_predicate_kind'
      and item.enumlabel = 'HAS_DEGREE_LEVEL'
  ) then
    raise exception using errcode = '55000',
      message = '030 preflight failed: HAS_DEGREE_LEVEL already exists';
  end if;
end;
$preflight$;

-- PostgreSQL 15 cannot use a newly-added enum value in objects created in the
-- transaction that added it.  The repository runner contract therefore uses
-- this deliberate single-file/two-transaction boundary.
alter type public.requirement_predicate_kind add value 'HAS_DEGREE_LEVEL';

commit;

begin;

create type public.degree_requirement_status_v030 as enum (
  'DRAFT', 'VERIFIED', 'RETIRED'
);
create type public.degree_qualification_contract_status_v030 as enum (
  'DRAFT', 'VERIFIED', 'RETIRED'
);
create type public.eligibility_degree_reason_code_v030 as enum (
  'DEGREE_LEVEL_MATCHED',
  'DEGREE_LEVEL_NOT_FOUND',
  'EDUCATION_HISTORY_INCOMPLETE',
  'DEGREE_STATUS_UNRESOLVED',
  'DEGREE_LEVEL_UNRESOLVED',
  'DEGREE_EQUIVALENCY_UNRESOLVED'
);
create type public.eligibility_degree_execution_mode_v030 as enum (
  'DEGREE', 'LEGACY'
);

alter table public.program_versions
  add column degree_requirement_level_v030 public.degree_level;

alter table public.program_requirement_rule_sets
  drop constraint program_rule_sets_supported_contract;
alter table public.program_requirement_rule_sets
  add constraint program_rule_sets_supported_contract check (
    (
      rule_schema_version = 'phase2-v0.1'
      and engine_contract_version = 'eligibility-v0.1'
    ) or (
      rule_schema_version = 'phase2-v0.2'
      and engine_contract_version = 'eligibility-v0.2'
    ) or (
      rule_schema_version = 'phase2-degree-v1'
      and engine_contract_version = 'eligibility-degree-v1'
    )
  );

drop index public.program_requirement_one_verified_idx;
create unique index program_requirement_one_verified_idx
  on public.program_requirement_rule_sets (
    program_version_id,
    engine_contract_version
  )
  where status = 'VERIFIED';

alter table public.eligibility_evaluations
  drop constraint eligibility_evaluations_version_gate;
alter table public.eligibility_evaluations
  add constraint eligibility_evaluations_version_gate check (
    (
      input_schema_version = 'eligibility-v0.1'
      and result_semantics_version is null
      and canonicalization_version is null
      and contract_release_code is null
      and taxonomy_release_ordinal is null
      and result_fingerprint is null
      and (
        (evaluation_state = 'BUILDING' and input_fingerprint is null
         and outcome is null and root_truth_value is null and evaluated_at is null)
        or
        (evaluation_state = 'COMPLETED' and input_fingerprint is not null
         and outcome is not null and root_truth_value is not null and evaluated_at is not null)
      )
    ) or (
      input_schema_version = 'eligibility-v0.2'
      and result_semantics_version = 'eligibility-v0.2'
      and canonicalization_version = 'eligibility-v0.2-c14n1'
      and contract_release_code = 'phase2-v0.2'
      and taxonomy_release_ordinal >= 1
      and (
        (evaluation_state = 'BUILDING' and inputs_sealed_at is null
         and input_fingerprint is null and result_fingerprint is null
         and outcome is null and root_truth_value is null and evaluated_at is null)
        or
        (evaluation_state = 'BUILDING' and inputs_sealed_at is not null
         and input_fingerprint ~ '^[a-f0-9]{64}$' and result_fingerprint is null
         and outcome is null and root_truth_value is null and evaluated_at is null)
        or
        (evaluation_state = 'COMPLETED' and inputs_sealed_at is not null
         and input_fingerprint ~ '^[a-f0-9]{64}$'
         and result_fingerprint ~ '^[a-f0-9]{64}$'
         and outcome is not null and root_truth_value is not null and evaluated_at is not null)
      )
    ) or (
      input_schema_version = 'eligibility-degree-v1'
      and result_semantics_version = 'eligibility-v0.2'
      and canonicalization_version = 'eligibility-degree-v1-c14n1'
      and contract_release_code = 'phase2-degree-v1'
      and taxonomy_release_ordinal >= 1
      and (
        (evaluation_state = 'BUILDING' and inputs_sealed_at is null
         and input_fingerprint is null and result_fingerprint is null
         and outcome is null and root_truth_value is null and evaluated_at is null)
        or
        (evaluation_state = 'BUILDING' and inputs_sealed_at is not null
         and input_fingerprint ~ '^[a-f0-9]{64}$' and result_fingerprint is null
         and outcome is null and root_truth_value is null and evaluated_at is null)
        or
        (evaluation_state = 'COMPLETED' and inputs_sealed_at is not null
         and input_fingerprint ~ '^[a-f0-9]{64}$'
         and result_fingerprint ~ '^[a-f0-9]{64}$'
         and outcome is not null and root_truth_value is not null and evaluated_at is not null)
      )
    )
  );

create table public.program_degree_requirements_v030 (
  degree_requirement_id uuid primary key default extensions.gen_random_uuid(),
  semantic_identity text not null,
  semantic_version integer not null,
  program_version_id uuid not null
    references public.program_versions(program_version_id) on delete restrict,
  cycle_identity text not null,
  required_degree_level public.degree_level not null,
  selected_observation_id uuid not null
    references public.field_observations(observation_id) on delete restrict,
  status public.degree_requirement_status_v030 not null default 'DRAFT',
  verified_by text,
  verified_at timestamptz,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  check (semantic_identity ~ '^[A-Z0-9][A-Z0-9._:-]{0,127}$'),
  check (semantic_version > 0),
  check (cycle_identity ~ '^[A-Z0-9][A-Z0-9._:-]{0,63}$'),
  check (required_degree_level in ('BACHELORS', 'MASTERS', 'DOCTORAL')),
  check (
    (status = 'DRAFT' and verified_by is null and verified_at is null)
    or
    (status in ('VERIFIED', 'RETIRED')
      and nullif(btrim(verified_by), '') is not null and verified_at is not null)
  ),
  check ((status = 'RETIRED') = (retired_at is not null and retirement_reason is not null)),
  unique (semantic_identity, semantic_version),
  unique (degree_requirement_id, program_version_id)
);
create unique index program_degree_requirements_v030_verified_idx
  on public.program_degree_requirements_v030(program_version_id, semantic_identity)
  where status = 'VERIFIED';

create table public.program_degree_requirement_predicates_v030 (
  rule_node_id uuid primary key
    references public.program_requirement_nodes(rule_node_id) on delete restrict,
  rule_set_id uuid not null,
  degree_requirement_id uuid not null,
  program_version_id uuid not null,
  created_at timestamptz not null default now(),
  foreign key (rule_set_id, rule_node_id)
    references public.program_requirement_nodes(rule_set_id, rule_node_id)
    on delete restrict,
  foreign key (degree_requirement_id, program_version_id)
    references public.program_degree_requirements_v030(
      degree_requirement_id, program_version_id
    ) on delete restrict,
  unique (rule_set_id, degree_requirement_id)
);

create table public.degree_level_qualification_contracts_v030 (
  contract_code text primary key,
  contract_version integer not null,
  semantic_identity text not null unique,
  matrix_hash text not null,
  status public.degree_qualification_contract_status_v030 not null,
  verified_by text not null,
  verified_at timestamptz not null,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  check (contract_code = 'DEGREE_LEVEL_QUALIFICATION_V1'),
  check (contract_version = 1),
  check (semantic_identity = 'DEGREE_LEVEL_QUALIFICATION_V1'),
  check (matrix_hash ~ '^[a-f0-9]{64}$'),
  check (status in ('VERIFIED', 'RETIRED')),
  check ((status = 'RETIRED') = (retired_at is not null and retirement_reason is not null))
);
create table public.degree_level_qualification_relations_v030 (
  contract_code text not null
    references public.degree_level_qualification_contracts_v030(contract_code)
    on delete restrict,
  required_degree_level public.degree_level not null,
  student_degree_level public.degree_level not null,
  qualifies boolean not null,
  primary key (contract_code, required_degree_level, student_degree_level),
  check (qualifies),
  check (required_degree_level in ('BACHELORS', 'MASTERS', 'DOCTORAL')),
  check (student_degree_level in ('BACHELORS', 'MASTERS', 'DOCTORAL'))
);

insert into public.degree_level_qualification_contracts_v030 (
  contract_code, contract_version, semantic_identity, matrix_hash,
  status, verified_by, verified_at
) values (
  'DEGREE_LEVEL_QUALIFICATION_V1',
  1,
  'DEGREE_LEVEL_QUALIFICATION_V1',
  encode(extensions.digest(convert_to(
    'DEGREE_LEVEL_QUALIFICATION_V1|BACHELORS>BACHELORS|BACHELORS>MASTERS|BACHELORS>DOCTORAL|MASTERS>MASTERS|MASTERS>DOCTORAL|DOCTORAL>DOCTORAL',
    'UTF8'
  ), 'sha256'), 'hex'),
  'VERIFIED',
  'migration-030',
  transaction_timestamp()
);
insert into public.degree_level_qualification_relations_v030 (
  contract_code, required_degree_level, student_degree_level, qualifies
) values
  ('DEGREE_LEVEL_QUALIFICATION_V1', 'BACHELORS', 'BACHELORS', true),
  ('DEGREE_LEVEL_QUALIFICATION_V1', 'BACHELORS', 'MASTERS', true),
  ('DEGREE_LEVEL_QUALIFICATION_V1', 'BACHELORS', 'DOCTORAL', true),
  ('DEGREE_LEVEL_QUALIFICATION_V1', 'MASTERS', 'MASTERS', true),
  ('DEGREE_LEVEL_QUALIFICATION_V1', 'MASTERS', 'DOCTORAL', true),
  ('DEGREE_LEVEL_QUALIFICATION_V1', 'DOCTORAL', 'DOCTORAL', true);

create table public.eligibility_evaluator_builds_v030 (
  evaluator_build_id uuid primary key,
  evaluator_name text not null,
  evaluator_version text not null,
  evaluator_build_hash text not null,
  input_schema_version text not null,
  result_semantics_version text not null,
  canonicalization_version text not null,
  contract_release_code text not null,
  qualification_contract_code text not null
    references public.degree_level_qualification_contracts_v030(contract_code)
    on delete restrict,
  status public.taxonomy_release_status not null,
  registered_at timestamptz not null default now(),
  check (evaluator_build_id = '03003030-0303-4030-8030-030030030030'::uuid),
  check (evaluator_name = 'education-platform-eligibility-degree-sql'),
  check (evaluator_version = '1.0.0'),
  check (evaluator_build_hash ~ '^[a-f0-9]{64}$'),
  check (input_schema_version = 'eligibility-degree-v1'),
  check (result_semantics_version = 'eligibility-v0.2'),
  check (canonicalization_version = 'eligibility-degree-v1-c14n1'),
  check (contract_release_code = 'phase2-degree-v1'),
  check (qualification_contract_code = 'DEGREE_LEVEL_QUALIFICATION_V1'),
  check (status = 'VERIFIED')
);
insert into public.eligibility_evaluator_builds_v030 (
  evaluator_build_id, evaluator_name, evaluator_version,
  evaluator_build_hash, input_schema_version, result_semantics_version,
  canonicalization_version, contract_release_code,
  qualification_contract_code, status
) values (
  '03003030-0303-4030-8030-030030030030',
  'education-platform-eligibility-degree-sql',
  '1.0.0',
  encode(extensions.digest(convert_to(
    'M030|HAS_DEGREE_LEVEL|DEGREE_LEVEL_QUALIFICATION_V1|eligibility-degree-v1|eligibility-v0.2|eligibility-degree-v1-c14n1',
    'UTF8'
  ), 'sha256'), 'hex'),
  'eligibility-degree-v1',
  'eligibility-v0.2',
  'eligibility-degree-v1-c14n1',
  'phase2-degree-v1',
  'DEGREE_LEVEL_QUALIFICATION_V1',
  'VERIFIED'
);

create table public.eligibility_degree_requirement_pins_v030 (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  rule_node_id uuid not null,
  degree_requirement_id uuid not null,
  semantic_identity text not null,
  semantic_version integer not null,
  program_version_id uuid not null,
  cycle_identity text not null,
  required_degree_level public.degree_level not null,
  selected_observation_id uuid not null,
  verified_by text not null,
  verified_at timestamptz not null,
  primary key (evaluation_id, rule_node_id),
  unique (evaluation_id, degree_requirement_id),
  foreign key (evaluation_id, rule_node_id)
    references public.eligibility_rule_node_pins(evaluation_id, rule_node_id)
    on delete cascade,
  check (required_degree_level in ('BACHELORS', 'MASTERS', 'DOCTORAL'))
);
create table public.eligibility_degree_qualification_pins_v030 (
  evaluation_id uuid primary key
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  contract_code text not null,
  contract_version integer not null,
  semantic_identity text not null,
  matrix_hash text not null,
  verified_by text not null,
  verified_at timestamptz not null,
  check (contract_code = 'DEGREE_LEVEL_QUALIFICATION_V1'),
  check (contract_version = 1),
  check (matrix_hash ~ '^[a-f0-9]{64}$')
);
create table public.eligibility_degree_qualification_relation_pins_v030 (
  evaluation_id uuid not null,
  contract_code text not null,
  required_degree_level public.degree_level not null,
  student_degree_level public.degree_level not null,
  qualifies boolean not null,
  primary key (evaluation_id, required_degree_level, student_degree_level),
  foreign key (evaluation_id)
    references public.eligibility_degree_qualification_pins_v030(evaluation_id)
    on delete cascade,
  check (qualifies)
);
create table public.eligibility_degree_snapshot_pins_v030 (
  evaluation_id uuid not null,
  student_degree_id uuid not null,
  degree_level public.degree_level not null,
  degree_status public.degree_status not null,
  student_evidence_id uuid not null,
  primary key (evaluation_id, student_degree_id),
  foreign key (evaluation_id, student_degree_id)
    references public.eligibility_manifest_degrees(evaluation_id, student_degree_id)
    on delete cascade
);
create table public.eligibility_degree_matches_v030 (
  degree_match_id uuid primary key default extensions.gen_random_uuid(),
  evaluation_id uuid not null,
  requirement_result_id uuid not null,
  rule_node_id uuid not null,
  degree_requirement_id uuid not null,
  student_degree_id uuid not null,
  student_evidence_id uuid not null,
  contract_code text not null,
  created_at timestamptz not null default now(),
  foreign key (requirement_result_id, evaluation_id)
    references public.eligibility_requirement_results(requirement_result_id, evaluation_id)
    on delete cascade,
  foreign key (evaluation_id, rule_node_id)
    references public.eligibility_degree_requirement_pins_v030(evaluation_id, rule_node_id)
    on delete cascade,
  foreign key (evaluation_id, student_degree_id)
    references public.eligibility_degree_snapshot_pins_v030(evaluation_id, student_degree_id)
    on delete cascade,
  unique (evaluation_id, rule_node_id, student_degree_id)
);
create table public.eligibility_degree_negative_proofs_v030 (
  evaluation_id uuid not null,
  rule_node_id uuid not null,
  scope_id uuid not null,
  completeness_id uuid not null,
  proof_version text not null,
  created_at timestamptz not null default now(),
  primary key (evaluation_id, rule_node_id),
  foreign key (evaluation_id, rule_node_id)
    references public.eligibility_degree_requirement_pins_v030(evaluation_id, rule_node_id)
    on delete cascade,
  foreign key (scope_id)
    references public.eligibility_snapshot_scopes(scope_id) on delete cascade,
  foreign key (evaluation_id, completeness_id)
    references public.eligibility_completeness_pins(evaluation_id, completeness_id)
    on delete cascade,
  check (proof_version = 'eligibility-degree-v1-neg1')
);
create table private.eligibility_degree_operations_v030 (
  operation_id uuid primary key,
  profile_version_id uuid not null,
  program_version_id uuid not null
    references public.program_versions(program_version_id) on delete restrict,
  execution_mode public.eligibility_degree_execution_mode_v030 not null,
  evaluation_id uuid not null unique
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  created_at timestamptz not null default now(),
  foreign key (evaluation_id, profile_version_id)
    references public.eligibility_evaluations(evaluation_id, profile_version_id)
    on delete cascade
);

create or replace function public.guard_program_degree_requirement_v030()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000',
      message = 'Degree requirement authority is append-only';
  end if;
  if old.status in ('VERIFIED', 'RETIRED') then
    if new.degree_requirement_id is distinct from old.degree_requirement_id
       or new.semantic_identity is distinct from old.semantic_identity
       or new.semantic_version is distinct from old.semantic_version
       or new.program_version_id is distinct from old.program_version_id
       or new.cycle_identity is distinct from old.cycle_identity
       or new.required_degree_level is distinct from old.required_degree_level
       or new.selected_observation_id is distinct from old.selected_observation_id
       or new.verified_by is distinct from old.verified_by
       or new.verified_at is distinct from old.verified_at then
      raise exception using errcode = '55000',
        message = 'Verified degree requirement semantics are immutable';
    end if;
  end if;
  if old.status = 'RETIRED' then
    raise exception using errcode = '55000',
      message = 'Retired degree requirement is immutable';
  end if;
  if old.status = 'VERIFIED' and new.status <> 'RETIRED' then
    raise exception using errcode = '55000',
      message = 'Verified degree requirement may only retire';
  end if;
  if old.status = 'DRAFT' and new.status not in ('DRAFT', 'VERIFIED') then
    raise exception using errcode = '55000',
      message = 'Invalid degree requirement lifecycle transition';
  end if;
  return new;
end;
$function$;
create trigger program_degree_requirements_v030_guard
before update or delete on public.program_degree_requirements_v030
for each row execute function public.guard_program_degree_requirement_v030();

create or replace function public.guard_degree_qualification_v030()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $function$
begin
  raise exception using errcode = '55000',
    message = 'DEGREE_LEVEL_QUALIFICATION_V1 is immutable';
end;
$function$;
create trigger degree_qualification_contract_v030_guard
before insert or update or delete on public.degree_level_qualification_contracts_v030
for each row execute function public.guard_degree_qualification_v030();
create trigger degree_qualification_relations_v030_guard
before insert or update or delete on public.degree_level_qualification_relations_v030
for each row execute function public.guard_degree_qualification_v030();
create trigger eligibility_evaluator_builds_v030_guard
before insert or update or delete on public.eligibility_evaluator_builds_v030
for each row execute function public.guard_degree_qualification_v030();

create or replace function private.lock_eligibility_evaluator_build_v030()
returns public.eligibility_evaluator_builds_v030
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private
as $function$
declare
  v_build public.eligibility_evaluator_builds_v030%rowtype;
begin
  select * into strict v_build
  from public.eligibility_evaluator_builds_v030 build
  where build.evaluator_build_id = '03003030-0303-4030-8030-030030030030'
    and build.status = 'VERIFIED'
  for key share;
  return v_build;
end;
$function$;

create or replace function public.create_program_degree_requirement_v030(
  p_semantic_identity text,
  p_semantic_version integer,
  p_program_version_id uuid,
  p_cycle_identity text,
  p_required_degree_level public.degree_level,
  p_selected_observation_id uuid
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $function$
declare
  v_id uuid;
begin
  if current_user is distinct from 'foundation_catalog_executor' then
    raise exception using errcode = '42501', message = 'Catalog executor required';
  end if;
  insert into public.program_degree_requirements_v030 (
    semantic_identity, semantic_version, program_version_id, cycle_identity,
    required_degree_level, selected_observation_id
  ) values (
    upper(btrim(p_semantic_identity)), p_semantic_version,
    p_program_version_id, upper(btrim(p_cycle_identity)),
    p_required_degree_level, p_selected_observation_id
  ) returning degree_requirement_id into v_id;
  return v_id;
end;
$function$;

create or replace function public.verify_program_degree_requirement_v030(
  p_degree_requirement_id uuid,
  p_verified_by text
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $function$
declare
  v_requirement public.program_degree_requirements_v030%rowtype;
  v_observation public.field_observations%rowtype;
  v_cycle text;
begin
  if current_user is distinct from 'foundation_catalog_executor' then
    raise exception using errcode = '42501', message = 'Catalog executor required';
  end if;
  if nullif(btrim(p_verified_by), '') is null then
    raise exception using errcode = '22023', message = 'Verifier identity is required';
  end if;
  select * into v_requirement
  from public.program_degree_requirements_v030 requirement
  where requirement.degree_requirement_id = p_degree_requirement_id
  for update;
  if not found or v_requirement.status is distinct from 'DRAFT' then
    raise exception using errcode = '55000', message = 'A DRAFT degree requirement is required';
  end if;
  select admission_cycle into v_cycle
  from public.program_versions version
  where version.program_version_id = v_requirement.program_version_id
  for key share;
  if upper(v_cycle) is distinct from v_requirement.cycle_identity then
    raise exception using errcode = '55000', message = 'Degree requirement cycle is not the ProgramVersion cycle';
  end if;
  select * into v_observation
  from public.field_observations observation
  where observation.observation_id = v_requirement.selected_observation_id
  for key share;
  if not found
     or v_observation.record_type is distinct from 'PROGRAM_VERSION'
     or v_observation.record_id is distinct from v_requirement.program_version_id
     or v_observation.field_name is distinct from 'degree_requirement_level_v030'
     or v_observation.knowledge_status is distinct from 'KNOWN'
     or v_observation.observed_value is distinct from to_jsonb(v_requirement.required_degree_level::text)
     or v_observation.evidence_id is null then
    raise exception using errcode = '55000', message = 'Degree requirement observation is not exact KNOWN authority';
  end if;
  if not exists (
    select 1
    from public.canonical_field_selections selection
    where selection.record_type = v_observation.record_type
      and selection.record_id = v_observation.record_id
      and selection.field_name = v_observation.field_name
      and selection.observation_id = v_observation.observation_id
  ) then
    raise exception using errcode = '55000', message = 'Degree requirement observation is not canonical';
  end if;
  if not exists (
    select 1
    from public.evidence_items evidence
    join public.sources source on source.source_id = evidence.source_id
    join public.field_observation_applicability binding
      on binding.observation_id = v_observation.observation_id
    join public.evidence_applicability_assertions assertion
      on assertion.assertion_id = binding.assertion_id
    join public.evidence_applicability_heads head
      on head.scope_id = assertion.scope_id
     and head.assertion_id = assertion.assertion_id
    join public.evidence_applicability_scopes scope
      on scope.scope_id = assertion.scope_id
    where evidence.evidence_id = v_observation.evidence_id
      and source.reliability_tier = 'TIER_A_OFFICIAL'
      and source.source_identity_id is not null
      and source.revision_number > 0
      and source.retrieval_content_hash ~ '^[a-f0-9]{64}$'
      and assertion.applicability_status = 'REVIEWED_APPLICABLE'
      and scope.evidence_id = evidence.evidence_id
      and scope.record_type = 'PROGRAM_VERSION'
      and scope.record_id = v_requirement.program_version_id
      and scope.field_name = 'degree_requirement_level_v030'
      and scope.resolved_program_version_id = v_requirement.program_version_id
      and scope.granularity_scope = 'UNSPECIFIED'
      and scope.population_scope_code = 'UNSPECIFIED'
      and scope.cycle_scope_code = 'UNSPECIFIED'
  ) then
    raise exception using errcode = '55000',
      message = 'Degree requirement needs current Tier-A reviewed applicability authority';
  end if;
  if not exists (
    select 1 from public.program_versions version
    where version.program_version_id = v_requirement.program_version_id
      and version.degree_requirement_level_v030 = v_requirement.required_degree_level
  ) then
    raise exception using errcode = '55000', message = 'Canonical ProgramVersion degree level does not match';
  end if;
  update public.program_degree_requirements_v030
  set status = 'VERIFIED', verified_by = btrim(p_verified_by), verified_at = now()
  where degree_requirement_id = p_degree_requirement_id;
end;
$function$;

create or replace function public.retire_program_degree_requirement_v030(
  p_degree_requirement_id uuid,
  p_reason text
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
begin
  if current_user is distinct from 'foundation_catalog_executor' then
    raise exception using errcode = '42501', message = 'Catalog executor required';
  end if;
  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = '22023', message = 'Retirement reason is required';
  end if;
  update public.program_degree_requirements_v030
  set status = 'RETIRED', retired_at = now(), retirement_reason = btrim(p_reason)
  where degree_requirement_id = p_degree_requirement_id and status = 'VERIFIED';
  if not found then
    raise exception using errcode = '55000', message = 'A VERIFIED degree requirement is required';
  end if;
end;
$function$;

create or replace function public.insert_program_degree_predicate_v030(
  p_rule_node_id uuid,
  p_degree_requirement_id uuid
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_node public.program_requirement_nodes%rowtype;
  v_rule_set public.program_requirement_rule_sets%rowtype;
  v_requirement public.program_degree_requirements_v030%rowtype;
begin
  if current_user is distinct from 'foundation_catalog_executor' then
    raise exception using errcode = '42501', message = 'Catalog executor required';
  end if;
  select * into v_node from public.program_requirement_nodes
  where rule_node_id = p_rule_node_id for update;
  select * into v_rule_set from public.program_requirement_rule_sets
  where rule_set_id = v_node.rule_set_id for update;
  select * into v_requirement from public.program_degree_requirements_v030
  where degree_requirement_id = p_degree_requirement_id for key share;
  if v_rule_set.status is distinct from 'DRAFT'
     or v_rule_set.rule_schema_version is distinct from 'phase2-degree-v1'
     or v_rule_set.engine_contract_version is distinct from 'eligibility-degree-v1'
     or v_node.node_kind is distinct from 'PREDICATE'
     or v_node.predicate_kind is distinct from 'HAS_DEGREE_LEVEL'
     or v_node.requirement_strength is distinct from 'HARD'
     or v_node.requirement_semantics is distinct from 'ORDINARY'
     or v_node.target_concept_id is not null
     or v_requirement.status is distinct from 'VERIFIED'
     or v_requirement.program_version_id is distinct from v_rule_set.program_version_id then
    raise exception using errcode = '55000', message = 'Invalid degree predicate binding';
  end if;
  insert into public.program_degree_requirement_predicates_v030 (
    rule_node_id, rule_set_id, degree_requirement_id, program_version_id
  ) values (
    v_node.rule_node_id, v_node.rule_set_id,
    v_requirement.degree_requirement_id, v_requirement.program_version_id
  );
end;
$function$;

create or replace function public.verify_program_requirement_rule_set_degree_v030(
  p_rule_set_id uuid,
  p_verified_by text,
  p_verification_evidence_id uuid
) returns void
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_rule_set public.program_requirement_rule_sets%rowtype;
  v_root uuid;
  v_total integer;
  v_reachable integer;
  v_group record;
  v_children integer;
begin
  if current_user is distinct from 'foundation_catalog_executor' then
    raise exception using errcode = '42501', message = 'Catalog executor required';
  end if;
  if nullif(btrim(p_verified_by), '') is null
     or not exists (select 1 from public.evidence_items where evidence_id = p_verification_evidence_id) then
    raise exception using errcode = '22023', message = 'Verifier and evidence are required';
  end if;
  select * into v_rule_set from public.program_requirement_rule_sets
  where rule_set_id = p_rule_set_id for update;
  if not found or v_rule_set.status is distinct from 'DRAFT'
     or v_rule_set.rule_schema_version is distinct from 'phase2-degree-v1'
     or v_rule_set.engine_contract_version is distinct from 'eligibility-degree-v1' then
    raise exception using errcode = '55000', message = 'A DRAFT degree-v1 rule set is required';
  end if;
  select rule_node_id into v_root from public.program_requirement_nodes
  where rule_set_id = p_rule_set_id and parent_node_id is null;
  select count(*) into v_total from public.program_requirement_nodes
  where rule_set_id = p_rule_set_id;
  with recursive reachable(rule_node_id, path) as (
    select v_root, array[v_root]
    union all
    select child.rule_node_id, parent.path || child.rule_node_id
    from reachable parent
    join public.program_requirement_nodes child
      on child.parent_node_id = parent.rule_node_id
     and child.rule_set_id = p_rule_set_id
    where not child.rule_node_id = any(parent.path)
  )
  select count(distinct rule_node_id) into v_reachable from reachable;
  if v_root is null or v_total < 1 or v_reachable is distinct from v_total then
    raise exception using errcode = '55000', message = 'Degree rule tree must be complete and acyclic';
  end if;
  if exists (
    select 1
    from public.program_requirement_nodes node
    where node.rule_set_id = p_rule_set_id
      and (
        (node.node_kind = 'PREDICATE' and (
          node.predicate_kind is distinct from 'HAS_DEGREE_LEVEL'
          or node.requirement_strength is distinct from 'HARD'
          or node.requirement_semantics is distinct from 'ORDINARY'
          or node.target_concept_id is not null
          or exists (select 1 from public.program_requirement_nodes child
                     where child.parent_node_id = node.rule_node_id)
          or not exists (
            select 1
            from public.program_degree_requirement_predicates_v030 binding
            join public.program_degree_requirements_v030 requirement
              on requirement.degree_requirement_id = binding.degree_requirement_id
            where binding.rule_node_id = node.rule_node_id
              and binding.rule_set_id = p_rule_set_id
              and requirement.status = 'VERIFIED'
              and requirement.program_version_id = v_rule_set.program_version_id
          )
          or not exists (
            select 1 from public.program_requirement_node_sources source
            join public.program_degree_requirement_predicates_v030 binding
              on binding.rule_node_id = source.rule_node_id
            join public.program_degree_requirements_v030 requirement
              on requirement.degree_requirement_id = binding.degree_requirement_id
            where source.rule_node_id = node.rule_node_id
              and source.field_observation_id = requirement.selected_observation_id
          )
        ))
        or
        (node.node_kind = 'GROUP' and not exists (
          select 1 from public.program_requirement_nodes child
          where child.parent_node_id = node.rule_node_id
        ))
      )
  ) then
    raise exception using errcode = '55000', message = 'Degree rule set has invalid node or authority shape';
  end if;
  for v_group in
    select node.rule_node_id, node.group_operator, node.minimum_children
    from public.program_requirement_nodes node
    where node.rule_set_id = p_rule_set_id and node.node_kind = 'GROUP'
  loop
    select count(*) into v_children from public.program_requirement_nodes child
    where child.parent_node_id = v_group.rule_node_id;
    if v_group.group_operator = 'AT_LEAST'
       and (v_group.minimum_children is null or v_group.minimum_children > v_children) then
      raise exception using errcode = '55000', message = 'Invalid degree AT_LEAST cardinality';
    end if;
    if v_group.group_operator = 'AT_LEAST' then
      insert into public.requirement_group_projection_thresholds (
        rule_set_id, group_node_id, projection_kind,
        projected_minimum_children, projected_descendant_count,
        verification_evidence_id, verified_by, verified_at
      ) values
        (p_rule_set_id, v_group.rule_node_id, 'FULL',
          v_group.minimum_children, v_children,
          p_verification_evidence_id, btrim(p_verified_by), now()),
        (p_rule_set_id, v_group.rule_node_id, 'ORDINARY_BARRIER',
          v_group.minimum_children, v_children,
          p_verification_evidence_id, btrim(p_verified_by), now()),
        (p_rule_set_id, v_group.rule_node_id, 'CONDITIONAL_HARD',
          v_group.minimum_children, v_children,
          p_verification_evidence_id, btrim(p_verified_by), now());
    end if;
  end loop;
  update public.program_requirement_rule_sets
  set status = 'VERIFIED', verification_evidence_id = p_verification_evidence_id,
      verified_by = btrim(p_verified_by), verified_at = now()
  where rule_set_id = p_rule_set_id;
end;
$function$;

do $sealed_pin_triggers$
declare
  v_table text;
begin
  foreach v_table in array array[
    'eligibility_degree_requirement_pins_v030',
    'eligibility_degree_qualification_pins_v030',
    'eligibility_degree_qualification_relation_pins_v030',
    'eligibility_degree_snapshot_pins_v030'
  ] loop
    execute format(
      'create trigger %I before insert or update or delete on public.%I '
      || 'for each row execute function public.guard_eligibility_v02_sealed_pin()',
      left(v_table || '_sealed_guard', 63), v_table
    );
  end loop;
end;
$sealed_pin_triggers$;

create or replace function private.canonical_eligibility_degree_input_v030(
  p_evaluation_id uuid
) returns text
language plpgsql
stable
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_evaluation public.eligibility_evaluations%rowtype;
  v_student_id uuid;
  v_object jsonb;
begin
  select * into strict v_evaluation
  from public.eligibility_evaluations evaluation
  where evaluation.evaluation_id = p_evaluation_id;
  select profile.student_id into strict v_student_id
  from public.student_profile_versions profile
  where profile.profile_version_id = v_evaluation.profile_version_id;
  v_object := jsonb_build_object(
    'contract', jsonb_build_object(
      'inputSchemaVersion', v_evaluation.input_schema_version,
      'resultSemanticsVersion', v_evaluation.result_semantics_version,
      'canonicalizationVersion', v_evaluation.canonicalization_version,
      'contractReleaseCode', v_evaluation.contract_release_code,
      'evaluatorName', v_evaluation.evaluator_name,
      'evaluatorVersion', v_evaluation.evaluator_version,
      'evaluatorBuildHash', v_evaluation.evaluator_build_hash
    ),
    'profile', jsonb_build_object(
      'studentId', v_student_id,
      'profileVersionId', v_evaluation.profile_version_id,
      'profileSnapshotHash', v_evaluation.profile_snapshot_hash
    ),
    'ruleSet', (
      select to_jsonb(pin) - 'evaluation_id' - 'verified_at'
      from public.eligibility_rule_set_pins pin
      where pin.evaluation_id = p_evaluation_id
    ),
    'nodes', coalesce((
      select jsonb_agg(to_jsonb(pin) - 'evaluation_id' order by pin.rule_node_id)
      from public.eligibility_rule_node_pins pin
      where pin.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'sources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', source_pin.rule_node_id,
        'fieldObservationId', source_pin.field_observation_id,
        'sourceIdentityId', observation_pin.source_identity_id,
        'sourceRevisionNumber', observation_pin.source_revision_number,
        'retrievalContentHash', observation_pin.retrieval_content_hash,
        'canonicalValue', observation_pin.canonical_value,
        'knowledgeStatus', observation_pin.knowledge_status,
        'applicabilityAssertionId', source_pin.applicability_assertion_id,
        'applicabilityScopeId', source_pin.applicability_scope_id
      ) order by source_pin.rule_node_id, source_pin.field_observation_id)
      from public.eligibility_rule_node_source_pins source_pin
      join public.eligibility_catalog_observation_pins observation_pin
        on observation_pin.evaluation_id = source_pin.evaluation_id
       and observation_pin.field_observation_id = source_pin.field_observation_id
      where source_pin.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'degreeRequirements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', pin.rule_node_id,
        'degreeRequirementId', pin.degree_requirement_id,
        'semanticIdentity', pin.semantic_identity,
        'semanticVersion', pin.semantic_version,
        'programVersionId', pin.program_version_id,
        'cycleIdentity', pin.cycle_identity,
        'requiredDegreeLevel', pin.required_degree_level,
        'selectedObservationId', pin.selected_observation_id
      ) order by pin.rule_node_id)
      from public.eligibility_degree_requirement_pins_v030 pin
      where pin.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'qualification', jsonb_build_object(
      'contract', (
        select jsonb_build_object(
          'contractCode', pin.contract_code,
          'contractVersion', pin.contract_version,
          'semanticIdentity', pin.semantic_identity,
          'matrixHash', pin.matrix_hash
        )
        from public.eligibility_degree_qualification_pins_v030 pin
        where pin.evaluation_id = p_evaluation_id
      ),
      'relations', coalesce((
        select jsonb_agg(jsonb_build_object(
          'requiredDegreeLevel', relation.required_degree_level,
          'studentDegreeLevel', relation.student_degree_level,
          'qualifies', relation.qualifies
        ) order by relation.required_degree_level, relation.student_degree_level)
        from public.eligibility_degree_qualification_relation_pins_v030 relation
        where relation.evaluation_id = p_evaluation_id
      ), '[]'::jsonb)
    ),
    'educationHistoryCompleteness', (
      select jsonb_build_object(
        'completenessId', pin.completeness_id,
        'domain', pin.domain,
        'completeness', pin.completeness,
        'scopeKind', scope.scope_kind
      )
      from public.eligibility_completeness_pins pin
      join public.eligibility_snapshot_scopes scope
        on scope.scope_id = pin.scope_id
      where pin.evaluation_id = p_evaluation_id
        and pin.domain = 'EDUCATION_HISTORY'
    ),
    'degrees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'studentDegreeId', pin.student_degree_id,
        'degreeLevel', pin.degree_level,
        'degreeStatus', pin.degree_status,
        'studentEvidenceId', pin.student_evidence_id
      ) order by pin.student_degree_id)
      from public.eligibility_degree_snapshot_pins_v030 pin
      where pin.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'projectionThresholds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'groupNodeId', pin.group_node_id,
        'projectionKind', pin.projection_kind,
        'projectedMinimumChildren', pin.projected_minimum_children,
        'projectedDescendantCount', pin.projected_descendant_count
      ) order by pin.group_node_id, pin.projection_kind)
      from public.eligibility_projection_threshold_pins pin
      where pin.evaluation_id = p_evaluation_id
    ), '[]'::jsonb)
  );
  return encode(extensions.digest(
    convert_to(private.canonical_json_v02(v_object), 'UTF8'), 'sha256'
  ), 'hex');
end;
$function$;

create or replace function private.assert_eligibility_degree_closed_world_v030(
  p_evaluation_id uuid
) returns void
language plpgsql
stable
set search_path = pg_catalog, public, private
as $function$
declare
  v_evaluation public.eligibility_evaluations%rowtype;
  v_profile_version_id uuid;
begin
  select * into strict v_evaluation
  from public.eligibility_evaluations evaluation
  where evaluation.evaluation_id = p_evaluation_id;
  v_profile_version_id := v_evaluation.profile_version_id;
  if v_evaluation.input_schema_version is distinct from 'eligibility-degree-v1'
     or (select count(*) from public.eligibility_rule_set_pins
         where evaluation_id = p_evaluation_id) <> 1
     or exists (
       select 1 from public.eligibility_rule_set_pins pin
       where pin.evaluation_id = p_evaluation_id
         and (pin.rule_schema_version is distinct from 'phase2-degree-v1'
              or pin.engine_contract_version is distinct from 'eligibility-degree-v1')
     ) then
    raise exception using errcode = '55000', message = 'Degree evaluation rule-set pin is incomplete';
  end if;
  if (select count(*) from public.eligibility_rule_node_pins
      where evaluation_id = p_evaluation_id) is distinct from
     (select count(*) from public.program_requirement_nodes
      where rule_set_id = v_evaluation.rule_set_id)
     or exists (
       select 1 from public.eligibility_rule_node_pins pin
       where pin.evaluation_id = p_evaluation_id
         and pin.node_kind = 'PREDICATE'
         and pin.predicate_kind is distinct from 'HAS_DEGREE_LEVEL'
     ) then
    raise exception using errcode = '55000', message = 'Degree evaluation node universe is incomplete';
  end if;
  if (select count(*) from public.eligibility_degree_requirement_pins_v030
      where evaluation_id = p_evaluation_id) is distinct from
     (select count(*) from public.eligibility_rule_node_pins
      where evaluation_id = p_evaluation_id and node_kind = 'PREDICATE') then
    raise exception using errcode = '55000', message = 'Degree requirement pins are incomplete';
  end if;
  if (select count(*) from public.eligibility_degree_qualification_pins_v030
      where evaluation_id = p_evaluation_id) <> 1
     or (select count(*) from public.eligibility_degree_qualification_relation_pins_v030
         where evaluation_id = p_evaluation_id) <> 6 then
    raise exception using errcode = '55000', message = 'Degree qualification matrix pin is incomplete';
  end if;
  if exists (
    (select required_degree_level, student_degree_level, qualifies
     from public.eligibility_degree_qualification_relation_pins_v030
     where evaluation_id = p_evaluation_id
     except
     select required_degree_level, student_degree_level, qualifies
     from public.degree_level_qualification_relations_v030
     where contract_code = 'DEGREE_LEVEL_QUALIFICATION_V1')
    union all
    (select required_degree_level, student_degree_level, qualifies
     from public.degree_level_qualification_relations_v030
     where contract_code = 'DEGREE_LEVEL_QUALIFICATION_V1'
     except
     select required_degree_level, student_degree_level, qualifies
     from public.eligibility_degree_qualification_relation_pins_v030
     where evaluation_id = p_evaluation_id)
  ) then
    raise exception using errcode = '55000', message = 'Degree qualification matrix pin drifted';
  end if;
  if (select count(*) from public.eligibility_completeness_pins
      where evaluation_id = p_evaluation_id and domain = 'EDUCATION_HISTORY') <> 1
     or exists (
       select 1
       from public.eligibility_completeness_pins pin
       join public.eligibility_snapshot_scopes scope on scope.scope_id = pin.scope_id
       where pin.evaluation_id = p_evaluation_id
         and (pin.domain is distinct from 'EDUCATION_HISTORY'
              or scope.scope_kind is distinct from 'GLOBAL_PROFILE'
              or scope.education_context_id is not null
              or scope.completeness_id is distinct from pin.completeness_id
              or scope.completeness is distinct from pin.completeness)
     ) then
    raise exception using errcode = '55000', message = 'EDUCATION_HISTORY completeness witness is invalid';
  end if;
  if exists (
    (select degree.student_degree_id, degree.degree_level, degree.degree_status, degree.student_evidence_id
     from public.student_degrees degree
     where degree.profile_version_id = v_profile_version_id
     except
     select pin.student_degree_id, pin.degree_level, pin.degree_status, pin.student_evidence_id
     from public.eligibility_degree_snapshot_pins_v030 pin
     where pin.evaluation_id = p_evaluation_id)
    union all
    (select pin.student_degree_id, pin.degree_level, pin.degree_status, pin.student_evidence_id
     from public.eligibility_degree_snapshot_pins_v030 pin
     where pin.evaluation_id = p_evaluation_id
     except
     select degree.student_degree_id, degree.degree_level, degree.degree_status, degree.student_evidence_id
     from public.student_degrees degree
     where degree.profile_version_id = v_profile_version_id)
  ) then
    raise exception using errcode = '55000', message = 'Frozen degree snapshot is not closed-world';
  end if;
  if (select count(*) from public.eligibility_manifest_degrees
      where evaluation_id = p_evaluation_id) is distinct from
     (select count(*) from public.eligibility_degree_snapshot_pins_v030
      where evaluation_id = p_evaluation_id)
     or (select count(*) from public.eligibility_manifest_student_evidence
         where evaluation_id = p_evaluation_id) is distinct from
        (select count(distinct student_evidence_id)
         from public.eligibility_degree_snapshot_pins_v030
         where evaluation_id = p_evaluation_id)
     or exists (select 1 from public.eligibility_manifest_courses where evaluation_id = p_evaluation_id)
     or exists (select 1 from public.eligibility_manifest_test_scores where evaluation_id = p_evaluation_id)
     or exists (select 1 from public.eligibility_manifest_student_mappings where evaluation_id = p_evaluation_id)
     or exists (select 1 from public.eligibility_manifest_catalog_mappings where evaluation_id = p_evaluation_id)
     or exists (select 1 from public.eligibility_manifest_taxonomy_concepts where evaluation_id = p_evaluation_id) then
    raise exception using errcode = '55000', message = 'Degree manifest contains missing or incidental inputs';
  end if;
end;
$function$;

create or replace function private.canonical_eligibility_degree_result_v030(
  p_evaluation_id uuid,
  p_outcome public.eligibility_outcome
) returns text
language plpgsql
stable
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_object jsonb;
begin
  v_object := jsonb_build_object(
    'inputFingerprint', (
      select input_fingerprint from public.eligibility_evaluations
      where evaluation_id = p_evaluation_id
    ),
    'outcome', p_outcome,
    'results', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', result.rule_node_id,
        'truthValue', result.truth_value,
        'reasonCodes', result.reason_codes,
        'missingData', result.missing_data,
        'supportingFactRefs', result.supporting_fact_refs
      ) order by result.rule_node_id)
      from public.eligibility_requirement_results result
      where result.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'projections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', result.rule_node_id,
        'projection', result.projection,
        'value', result.value
      ) order by result.rule_node_id, result.projection)
      from public.eligibility_requirement_projection_results result
      where result.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'degreeMatches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', match.rule_node_id,
        'degreeRequirementId', match.degree_requirement_id,
        'studentDegreeId', match.student_degree_id,
        'studentEvidenceId', match.student_evidence_id,
        'contractCode', match.contract_code
      ) order by match.rule_node_id, match.student_degree_id)
      from public.eligibility_degree_matches_v030 match
      where match.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'negativeProofs', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', proof.rule_node_id,
        'completenessId', proof.completeness_id,
        'proofVersion', proof.proof_version
      ) order by proof.rule_node_id)
      from public.eligibility_degree_negative_proofs_v030 proof
      where proof.evaluation_id = p_evaluation_id
    ), '[]'::jsonb)
  );
  return encode(extensions.digest(
    convert_to(private.canonical_json_v02(v_object), 'UTF8'), 'sha256'
  ), 'hex');
end;
$function$;

create or replace function public.guard_eligibility_degree_finalizer_v030()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private
as $function$
begin
  if not exists (
    select 1
    from private.eligibility_v02_finalize_authorizations authz
    where authz.transaction_id = txid_current()
      and authz.evaluation_id = new.evaluation_id
      and authz.executor_role = 'foundation_evaluation_executor'
  ) then
    raise exception using errcode = '55000',
      message = 'Degree result support rows are finalizer-only';
  end if;
  return new;
end;
$function$;
create trigger eligibility_degree_matches_v030_finalizer
before insert on public.eligibility_degree_matches_v030
for each row execute function public.guard_eligibility_degree_finalizer_v030();
create trigger eligibility_degree_negative_v030_finalizer
before insert on public.eligibility_degree_negative_proofs_v030
for each row execute function public.guard_eligibility_degree_finalizer_v030();

create or replace function private.finalize_eligibility_degree_v030(
  p_evaluation_id uuid
) returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_evaluation public.eligibility_evaluations%rowtype;
  v_student_id uuid;
  v_node public.eligibility_rule_node_pins%rowtype;
  v_truth public.requirement_truth_value;
  v_class public.eligibility_v02_leaf_class;
  v_projection public.eligibility_projection;
  v_projection_value public.eligibility_projection_value;
  v_children public.eligibility_projection_value[];
  v_threshold integer;
  v_progress boolean;
  v_result_id uuid;
  v_required_level public.degree_level;
  v_completeness public.data_completeness;
  v_completeness_id uuid;
  v_scope_id uuid;
  v_reason public.eligibility_degree_reason_code_v030;
  v_missing jsonb;
  v_support jsonb;
  v_root_truth public.requirement_truth_value;
  v_ordinary public.eligibility_projection_value;
  v_conditional public.eligibility_projection_value;
  v_outcome public.eligibility_outcome;
  v_input_hash text;
  v_result_hash text;
  v_match record;
begin
  select * into strict v_evaluation
  from public.eligibility_evaluations evaluation
  where evaluation.evaluation_id = p_evaluation_id
  for update;
  select profile.student_id into strict v_student_id
  from public.student_profile_versions profile
  where profile.profile_version_id = v_evaluation.profile_version_id;
  perform private.lock_student_lifecycle(v_student_id);
  perform private.lock_student_owned_total_order(v_student_id);
  if v_evaluation.evaluation_state is distinct from 'BUILDING'
     or v_evaluation.inputs_sealed_at is null
     or v_evaluation.input_schema_version is distinct from 'eligibility-degree-v1' then
    raise exception using errcode = '55000', message = 'A sealed BUILDING degree-v1 evaluation is required';
  end if;
  perform private.assert_eligibility_degree_closed_world_v030(p_evaluation_id);
  v_input_hash := private.canonical_eligibility_degree_input_v030(p_evaluation_id);
  if v_input_hash is distinct from v_evaluation.input_fingerprint then
    raise exception using errcode = '55000', message = 'Degree input fingerprint drifted';
  end if;
  insert into private.eligibility_v02_finalize_authorizations (
    transaction_id, evaluation_id, executor_role
  ) values (
    txid_current(), p_evaluation_id, 'foundation_evaluation_executor'
  );
  select pin.completeness, pin.completeness_id, pin.scope_id
    into strict v_completeness, v_completeness_id, v_scope_id
  from public.eligibility_completeness_pins pin
  where pin.evaluation_id = p_evaluation_id
    and pin.domain = 'EDUCATION_HISTORY';

  for v_node in
    select * from public.eligibility_rule_node_pins pin
    where pin.evaluation_id = p_evaluation_id and pin.node_kind = 'PREDICATE'
    order by pin.rule_node_id
  loop
    select pin.required_degree_level into strict v_required_level
    from public.eligibility_degree_requirement_pins_v030 pin
    where pin.evaluation_id = p_evaluation_id
      and pin.rule_node_id = v_node.rule_node_id;
    if exists (
      select 1
      from public.eligibility_degree_snapshot_pins_v030 degree
      join public.eligibility_degree_qualification_relation_pins_v030 relation
        on relation.evaluation_id = degree.evaluation_id
       and relation.required_degree_level = v_required_level
       and relation.student_degree_level = degree.degree_level
       and relation.qualifies
      where degree.evaluation_id = p_evaluation_id
        and degree.degree_status = 'COMPLETED'
    ) then
      v_truth := 'SATISFIED';
      v_reason := 'DEGREE_LEVEL_MATCHED';
      v_missing := '[]'::jsonb;
      v_support := jsonb_build_array(jsonb_build_object(
        'kind', 'DEGREE_LEVEL_QUALIFICATION',
        'contractCode', 'DEGREE_LEVEL_QUALIFICATION_V1',
        'requiredDegreeLevel', v_required_level
      ));
    elsif exists (
      select 1 from public.eligibility_degree_snapshot_pins_v030 degree
      where degree.evaluation_id = p_evaluation_id
        and degree.degree_status = 'IN_PROGRESS'
    ) then
      v_truth := 'UNKNOWN';
      v_reason := 'DEGREE_STATUS_UNRESOLVED';
      v_missing := jsonb_build_array(jsonb_build_object('code', v_reason));
      v_support := '[]'::jsonb;
    elsif exists (
      select 1 from public.eligibility_degree_snapshot_pins_v030 degree
      where degree.evaluation_id = p_evaluation_id
        and degree.degree_level = 'OTHER'
    ) then
      v_truth := 'UNKNOWN';
      v_reason := 'DEGREE_EQUIVALENCY_UNRESOLVED';
      v_missing := jsonb_build_array(
        jsonb_build_object('code', 'DEGREE_LEVEL_UNRESOLVED'),
        jsonb_build_object('code', 'DEGREE_EQUIVALENCY_UNRESOLVED')
      );
      v_support := '[]'::jsonb;
    elsif v_completeness = 'COMPLETE' then
      v_truth := 'NOT_SATISFIED';
      v_reason := 'DEGREE_LEVEL_NOT_FOUND';
      v_missing := '[]'::jsonb;
      v_support := '[]'::jsonb;
    else
      v_truth := 'UNKNOWN';
      v_reason := 'EDUCATION_HISTORY_INCOMPLETE';
      v_missing := jsonb_build_array(jsonb_build_object('code', v_reason));
      v_support := '[]'::jsonb;
    end if;
    insert into public.eligibility_requirement_results (
      evaluation_id, rule_node_id, truth_value, reason_codes,
      explanation, supporting_fact_refs, missing_data
    ) values (
      p_evaluation_id, v_node.rule_node_id, v_truth, array[v_reason::text],
      v_node.explanation_template, v_support, v_missing
    ) returning requirement_result_id into v_result_id;
    v_class := private.eligibility_v02_leaf_class(
      v_node.requirement_strength, v_node.requirement_semantics
    );
    foreach v_projection in array enum_range(null::public.eligibility_projection)
    loop
      insert into public.eligibility_requirement_projection_results (
        evaluation_id, rule_node_id, projection, value
      ) values (
        p_evaluation_id, v_node.rule_node_id, v_projection,
        private.eligibility_v02_project_leaf(v_class, v_projection, v_truth)
      );
    end loop;
    if v_truth = 'SATISFIED' then
      for v_match in
        select degree.student_degree_id, degree.student_evidence_id,
          requirement.degree_requirement_id
        from public.eligibility_degree_snapshot_pins_v030 degree
        join public.eligibility_degree_qualification_relation_pins_v030 relation
          on relation.evaluation_id = degree.evaluation_id
         and relation.required_degree_level = v_required_level
         and relation.student_degree_level = degree.degree_level
         and relation.qualifies
        join public.eligibility_degree_requirement_pins_v030 requirement
          on requirement.evaluation_id = degree.evaluation_id
         and requirement.rule_node_id = v_node.rule_node_id
        where degree.evaluation_id = p_evaluation_id
          and degree.degree_status = 'COMPLETED'
        order by degree.student_degree_id
      loop
        insert into public.eligibility_degree_matches_v030 (
          evaluation_id, requirement_result_id, rule_node_id,
          degree_requirement_id, student_degree_id, student_evidence_id,
          contract_code
        ) values (
          p_evaluation_id, v_result_id, v_node.rule_node_id,
          v_match.degree_requirement_id, v_match.student_degree_id,
          v_match.student_evidence_id, 'DEGREE_LEVEL_QUALIFICATION_V1'
        );
      end loop;
    elsif v_truth = 'NOT_SATISFIED' then
      insert into public.eligibility_degree_negative_proofs_v030 (
        evaluation_id, rule_node_id, scope_id, completeness_id, proof_version
      ) values (
        p_evaluation_id, v_node.rule_node_id, v_scope_id,
        v_completeness_id, 'eligibility-degree-v1-neg1'
      );
    end if;
  end loop;

  loop
    v_progress := false;
    for v_node in
      select node.*
      from public.eligibility_rule_node_pins node
      where node.evaluation_id = p_evaluation_id
        and node.node_kind = 'GROUP'
        and not exists (
          select 1 from public.eligibility_requirement_results result
          where result.evaluation_id = p_evaluation_id
            and result.rule_node_id = node.rule_node_id
        )
        and not exists (
          select 1 from public.eligibility_rule_node_pins child
          where child.evaluation_id = p_evaluation_id
            and child.parent_node_id = node.rule_node_id
            and not exists (
              select 1 from public.eligibility_requirement_results result
              where result.evaluation_id = p_evaluation_id
                and result.rule_node_id = child.rule_node_id
            )
        )
      order by node.rule_node_id
    loop
      v_progress := true;
      foreach v_projection in array enum_range(null::public.eligibility_projection)
      loop
        select coalesce(array_agg(result.value order by child.sort_order), '{}')
          into v_children
        from public.eligibility_rule_node_pins child
        join public.eligibility_requirement_projection_results result
          on result.evaluation_id = child.evaluation_id
         and result.rule_node_id = child.rule_node_id
         and result.projection = v_projection
        where child.evaluation_id = p_evaluation_id
          and child.parent_node_id = v_node.rule_node_id;
        v_threshold := null;
        if v_node.group_operator = 'AT_LEAST'
           and exists (select 1 from unnest(v_children) item where item is distinct from 'ABSENT') then
          if v_projection = 'FULL' then
            v_threshold := v_node.minimum_children;
          else
            select pin.projected_minimum_children into v_threshold
            from public.eligibility_projection_threshold_pins pin
            where pin.evaluation_id = p_evaluation_id
              and pin.group_node_id = v_node.rule_node_id
              and pin.projection_kind = v_projection;
          end if;
        end if;
        v_projection_value := private.eligibility_v02_aggregate(
          v_node.group_operator, v_children, v_threshold
        );
        insert into public.eligibility_requirement_projection_results (
          evaluation_id, rule_node_id, projection, value
        ) values (
          p_evaluation_id, v_node.rule_node_id, v_projection, v_projection_value
        );
        if v_projection = 'FULL' then
          insert into public.eligibility_requirement_results (
            evaluation_id, rule_node_id, truth_value, reason_codes,
            explanation, missing_data
          ) values (
            p_evaluation_id, v_node.rule_node_id,
            case when v_projection_value = 'ABSENT' then 'UNKNOWN'
                 else v_projection_value::text::public.requirement_truth_value end,
            array[case when v_projection_value = 'SATISFIED' then 'GROUP_SATISFIED'
                       when v_projection_value = 'NOT_SATISFIED' then 'GROUP_NOT_SATISFIED'
                       else 'GROUP_UNKNOWN' end],
            v_node.explanation_template,
            case when v_projection_value in ('UNKNOWN', 'ABSENT')
                 then jsonb_build_array(jsonb_build_object('code', 'EDUCATION_HISTORY_INCOMPLETE'))
                 else '[]'::jsonb end
          );
        end if;
      end loop;
    end loop;
    exit when not v_progress;
  end loop;
  if exists (
    select 1 from public.eligibility_rule_node_pins node
    where node.evaluation_id = p_evaluation_id
      and not exists (
        select 1 from public.eligibility_requirement_results result
        where result.evaluation_id = p_evaluation_id
          and result.rule_node_id = node.rule_node_id
      )
  ) then
    raise exception using errcode = '55000', message = 'Degree result tree did not close';
  end if;
  select projection.value into strict v_ordinary
  from public.eligibility_requirement_projection_results projection
  join public.eligibility_rule_node_pins root
    on root.evaluation_id = projection.evaluation_id
   and root.rule_node_id = projection.rule_node_id
  where projection.evaluation_id = p_evaluation_id
    and root.parent_node_id is null
    and projection.projection = 'ORDINARY_BARRIER';
  select projection.value into strict v_conditional
  from public.eligibility_requirement_projection_results projection
  join public.eligibility_rule_node_pins root
    on root.evaluation_id = projection.evaluation_id
   and root.rule_node_id = projection.rule_node_id
  where projection.evaluation_id = p_evaluation_id
    and root.parent_node_id is null
    and projection.projection = 'CONDITIONAL_HARD';
  select result.truth_value into strict v_root_truth
  from public.eligibility_requirement_results result
  join public.eligibility_rule_node_pins root
    on root.evaluation_id = result.evaluation_id
   and root.rule_node_id = result.rule_node_id
  where result.evaluation_id = p_evaluation_id
    and root.parent_node_id is null;
  v_outcome := private.eligibility_v02_derive_outcome(v_ordinary, v_conditional);
  if exists (
    select 1 from public.eligibility_requirement_results result
    join public.eligibility_rule_node_pins node
      on node.evaluation_id = result.evaluation_id
     and node.rule_node_id = result.rule_node_id
    where result.evaluation_id = p_evaluation_id
      and node.node_kind = 'PREDICATE'
      and (
        (result.truth_value = 'SATISFIED' and not exists (
          select 1 from public.eligibility_degree_matches_v030 match
          where match.evaluation_id = result.evaluation_id
            and match.rule_node_id = result.rule_node_id
        ))
        or
        (result.truth_value = 'NOT_SATISFIED' and not exists (
          select 1 from public.eligibility_degree_negative_proofs_v030 proof
          where proof.evaluation_id = result.evaluation_id
            and proof.rule_node_id = result.rule_node_id
        ))
      )
  ) then
    raise exception using errcode = '55000', message = 'Degree positive/negative proof closure failed';
  end if;
  v_result_hash := private.canonical_eligibility_degree_result_v030(
    p_evaluation_id, v_outcome
  );
  update public.eligibility_evaluations
  set evaluation_state = 'COMPLETED', outcome = v_outcome,
      root_truth_value = v_root_truth, evaluated_at = now(),
      result_fingerprint = v_result_hash
  where evaluation_id = p_evaluation_id and evaluation_state = 'BUILDING';
  delete from private.eligibility_v02_finalize_authorizations
  where transaction_id = txid_current() and evaluation_id = p_evaluation_id;
  perform private.write_student_lifecycle_audit(
    v_student_id, 'eligibility_evaluations', p_evaluation_id, 'FINALIZE_DEGREE_V030'
  );
  return v_result_hash;
end;
$function$;

create or replace function private.project_eligibility_assembly_v030(
  p_evaluation_id uuid
) returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_evaluation public.eligibility_evaluations%rowtype;
  v_program_version_id uuid;
  v_requirements jsonb := '[]'::jsonb;
  v_requirement record;
  v_missing_codes jsonb;
begin
  select * into strict v_evaluation
  from public.eligibility_evaluations evaluation
  where evaluation.evaluation_id = p_evaluation_id;
  select rule_set.program_version_id into strict v_program_version_id
  from public.program_requirement_rule_sets rule_set
  where rule_set.rule_set_id = v_evaluation.rule_set_id;
  if v_evaluation.evaluation_state is distinct from 'COMPLETED'
     or v_evaluation.input_fingerprint !~ '^[a-f0-9]{64}$'
     or v_evaluation.result_fingerprint !~ '^[a-f0-9]{64}$'
     or v_evaluation.outcome is null or v_evaluation.root_truth_value is null then
    raise exception using errcode = 'P0001', message = 'INTERNAL_ERROR';
  end if;
  for v_requirement in
    select result.rule_node_id, result.truth_value, result.reason_codes,
      result.explanation, result.supporting_fact_refs, result.missing_data
    from public.eligibility_requirement_results result
    where result.evaluation_id = p_evaluation_id
    order by result.rule_node_id
  loop
    if cardinality(v_requirement.reason_codes) > 256
       or length(v_requirement.explanation) > 2000
       or jsonb_typeof(v_requirement.supporting_fact_refs) is distinct from 'array'
       or jsonb_array_length(v_requirement.supporting_fact_refs) > 256
       or jsonb_typeof(v_requirement.missing_data) is distinct from 'array'
       or jsonb_array_length(v_requirement.missing_data) > 256 then
      raise exception using errcode = 'P0001', message = 'INTERNAL_ERROR';
    end if;
    select coalesce(jsonb_agg(item ->> 'code' order by ordinal), '[]'::jsonb)
      into v_missing_codes
    from jsonb_array_elements(v_requirement.missing_data)
      with ordinality as missing(item, ordinal);
    v_requirements := v_requirements || jsonb_build_array(jsonb_build_object(
      'id', v_requirement.rule_node_id,
      'truth', v_requirement.truth_value,
      'reasonCodes', to_jsonb(v_requirement.reason_codes),
      'explanation', v_requirement.explanation,
      'missingDataCodes', v_missing_codes,
      'supportingReferenceCount', jsonb_array_length(v_requirement.supporting_fact_refs)
    ));
  end loop;
  return jsonb_build_object(
    'schemaVersion', 'ELIGIBILITY_PRODUCTION_ASSEMBLY_V026',
    'evalId', v_evaluation.evaluation_id,
    'profileId', v_evaluation.profile_version_id,
    'programId', v_program_version_id,
    'status', v_evaluation.outcome,
    'rootTruth', v_evaluation.root_truth_value,
    'requirements', v_requirements,
    'inputFingerprint', v_evaluation.input_fingerprint,
    'resultFingerprint', v_evaluation.result_fingerprint
  );
end;
$function$;

create or replace function public.assemble_eligibility_evaluation_v030(
  p_profile_version_id uuid,
  p_program_version_id uuid,
  p_operation_id uuid
) returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_profile public.student_profile_versions%rowtype;
  v_operation private.eligibility_degree_operations_v030%rowtype;
  v_legacy_operation private.eligibility_assembly_operations_v026%rowtype;
  v_rule_set public.program_requirement_rule_sets%rowtype;
  v_degree_rule_count integer;
  v_evaluation_id uuid;
  v_taxonomy_ordinal bigint;
  v_build public.eligibility_evaluator_builds_v030%rowtype;
  v_scope_id uuid;
  v_completeness public.student_data_completeness%rowtype;
  v_selection public.canonical_field_selections%rowtype;
  v_row record;
  v_source_id uuid;
  v_source_identity_id uuid;
  v_source_revision integer;
  v_source_hash text;
  v_evidence_id uuid;
  v_assertion_id uuid;
  v_scope_key uuid;
  v_program_scope_key text;
  v_program_version_scope_key text;
  v_granularity public.applicability_granularity_scope;
  v_population public.applicability_population_scope;
  v_cycle_scope text;
  v_input_hash text;
  v_legacy_result jsonb;
  v_error text;
  v_allowed_errors constant text[] := array[
    'AUTH_REQUIRED', 'ACCESS_DENIED', 'PROFILE_NOT_FOUND',
    'PROFILE_NOT_FROZEN', 'PROGRAM_NOT_FOUND',
    'ELIGIBILITY_RULESET_NOT_FOUND', 'ELIGIBILITY_RULESET_AMBIGUOUS',
    'ELIGIBILITY_INPUT_INVALID', 'ELIGIBILITY_ASSEMBLY_CONFLICT',
    'REQUEST_TIMEOUT', 'INTERNAL_ERROR'
  ];
begin
  if p_profile_version_id is null or p_program_version_id is null
     or p_operation_id is null then
    raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('eligibility-v030-operation:' || p_operation_id::text, 0)
  );
  select * into v_operation
  from private.eligibility_degree_operations_v030 operation
  where operation.operation_id = p_operation_id
  for update;
  if found then
    if v_operation.profile_version_id is distinct from p_profile_version_id
       or v_operation.program_version_id is distinct from p_program_version_id then
      raise exception using errcode = 'P0001', message = 'ELIGIBILITY_ASSEMBLY_CONFLICT';
    end if;
    v_student_id := private.profile_student_for_auth_v019();
    if v_student_id is null or not exists (
      select 1 from public.student_profile_versions profile
      where profile.profile_version_id = p_profile_version_id
        and profile.student_id = v_student_id
    ) then
      raise exception using errcode = 'P0001', message = 'PROFILE_NOT_FOUND';
    end if;
    if v_operation.execution_mode = 'LEGACY' then
      return private.project_eligibility_assembly_v026(v_operation.evaluation_id);
    end if;
    return private.project_eligibility_assembly_v030(v_operation.evaluation_id);
  end if;
  if private.profile_request_auth_subject_v021() is null then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;
  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0001', message = 'PROFILE_NOT_FOUND';
  end if;
  select * into v_profile
  from public.student_profile_versions profile
  where profile.profile_version_id = p_profile_version_id
    and profile.student_id = v_student_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'PROFILE_NOT_FOUND';
  end if;
  perform private.lock_student_lifecycle(v_student_id);
  perform private.lock_student_owned_total_order(v_student_id);
  select * into strict v_profile
  from public.student_profile_versions profile
  where profile.profile_version_id = p_profile_version_id
    and profile.student_id = v_student_id
  for key share;
  if v_profile.status is distinct from 'FROZEN' then
    raise exception using errcode = 'P0001', message = 'PROFILE_NOT_FROZEN';
  end if;
  perform 1 from public.program_versions version
  where version.program_version_id = p_program_version_id
  for key share;
  if not found then
    raise exception using errcode = 'P0001', message = 'PROGRAM_NOT_FOUND';
  end if;
  select count(*) into v_degree_rule_count
  from public.program_requirement_rule_sets rule_set
  where rule_set.program_version_id = p_program_version_id
    and rule_set.status = 'VERIFIED'
    and rule_set.rule_schema_version = 'phase2-degree-v1'
    and rule_set.engine_contract_version = 'eligibility-degree-v1';
  if v_degree_rule_count > 1 then
    raise exception using errcode = 'P0001', message = 'ELIGIBILITY_RULESET_AMBIGUOUS';
  end if;
  if v_degree_rule_count = 0 then
    select * into v_legacy_operation
    from private.eligibility_assembly_operations_v026 operation
    where operation.operation_id = p_operation_id
    for update;
    if found then
      if v_legacy_operation.profile_version_id is distinct from p_profile_version_id
         or v_legacy_operation.program_version_id is distinct from p_program_version_id then
        raise exception using errcode = 'P0001', message = 'ELIGIBILITY_ASSEMBLY_CONFLICT';
      end if;
      v_legacy_result := private.project_eligibility_assembly_v026(
        v_legacy_operation.evaluation_id
      );
    else
      v_legacy_result := public.assemble_eligibility_evaluation_v026(
        p_profile_version_id, p_program_version_id, p_operation_id
      );
    end if;
    insert into private.eligibility_degree_operations_v030 (
      operation_id, profile_version_id, program_version_id,
      execution_mode, evaluation_id
    ) values (
      p_operation_id, p_profile_version_id, p_program_version_id,
      'LEGACY', (v_legacy_result ->> 'evalId')::uuid
    );
    return v_legacy_result;
  end if;
  select * into strict v_rule_set
  from public.program_requirement_rule_sets rule_set
  where rule_set.program_version_id = p_program_version_id
    and rule_set.status = 'VERIFIED'
    and rule_set.rule_schema_version = 'phase2-degree-v1'
    and rule_set.engine_contract_version = 'eligibility-degree-v1'
  for key share;
  select release.release_ordinal into strict v_taxonomy_ordinal
  from public.taxonomy_releases release
  where release.release_code = v_rule_set.taxonomy_release_code
    and release.status = 'VERIFIED'
  for key share;
  select * into strict v_build
  from private.lock_eligibility_evaluator_build_v030();
  select * into v_completeness
  from public.student_data_completeness completeness
  where completeness.profile_version_id = p_profile_version_id
    and completeness.domain = 'EDUCATION_HISTORY'
    and completeness.education_context_id is null
  for key share;
  if not found then
    raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
  end if;
  insert into public.eligibility_evaluations (
    profile_version_id, rule_set_id, taxonomy_release_code,
    evaluator_name, evaluator_version, evaluator_build_hash,
    input_schema_version, profile_snapshot_hash,
    result_semantics_version, canonicalization_version,
    contract_release_code, taxonomy_release_ordinal
  ) values (
    p_profile_version_id, v_rule_set.rule_set_id,
    v_rule_set.taxonomy_release_code, v_build.evaluator_name,
    v_build.evaluator_version, v_build.evaluator_build_hash,
    v_build.input_schema_version, v_profile.snapshot_hash,
    v_build.result_semantics_version, v_build.canonicalization_version,
    v_build.contract_release_code, v_taxonomy_ordinal
  ) returning evaluation_id into v_evaluation_id;
  insert into private.eligibility_degree_operations_v030 (
    operation_id, profile_version_id, program_version_id,
    execution_mode, evaluation_id
  ) values (
    p_operation_id, p_profile_version_id, p_program_version_id,
    'DEGREE', v_evaluation_id
  );
  insert into public.eligibility_rule_set_pins (
    evaluation_id, rule_set_id, program_version_id, rule_set_version,
    taxonomy_release_code, taxonomy_release_ordinal,
    rule_schema_version, engine_contract_version,
    verification_evidence_id, verified_by, verified_at
  ) values (
    v_evaluation_id, v_rule_set.rule_set_id, v_rule_set.program_version_id,
    v_rule_set.rule_set_version, v_rule_set.taxonomy_release_code,
    v_taxonomy_ordinal, v_rule_set.rule_schema_version,
    v_rule_set.engine_contract_version, v_rule_set.verification_evidence_id,
    v_rule_set.verified_by, v_rule_set.verified_at
  );
  insert into public.eligibility_rule_node_pins (
    evaluation_id, rule_node_id, parent_node_id, sort_order, node_kind,
    group_operator, minimum_children, predicate_kind, requirement_strength,
    requirement_semantics, target_concept_id, explanation_template
  )
  select v_evaluation_id, node.rule_node_id, node.parent_node_id,
    node.sort_order, node.node_kind, node.group_operator, node.minimum_children,
    node.predicate_kind, node.requirement_strength,
    node.requirement_semantics, node.target_concept_id,
    node.explanation_template
  from public.program_requirement_nodes node
  where node.rule_set_id = v_rule_set.rule_set_id
  order by node.rule_node_id;
  insert into public.eligibility_degree_requirement_pins_v030 (
    evaluation_id, rule_node_id, degree_requirement_id, semantic_identity,
    semantic_version, program_version_id, cycle_identity,
    required_degree_level, selected_observation_id, verified_by, verified_at
  )
  select v_evaluation_id, binding.rule_node_id,
    requirement.degree_requirement_id, requirement.semantic_identity,
    requirement.semantic_version, requirement.program_version_id,
    requirement.cycle_identity, requirement.required_degree_level,
    requirement.selected_observation_id, requirement.verified_by,
    requirement.verified_at
  from public.program_degree_requirement_predicates_v030 binding
  join public.program_degree_requirements_v030 requirement
    on requirement.degree_requirement_id = binding.degree_requirement_id
  where binding.rule_set_id = v_rule_set.rule_set_id
    and requirement.status = 'VERIFIED'
  order by binding.rule_node_id;
  insert into public.eligibility_degree_qualification_pins_v030 (
    evaluation_id, contract_code, contract_version, semantic_identity,
    matrix_hash, verified_by, verified_at
  )
  select v_evaluation_id, contract.contract_code, contract.contract_version,
    contract.semantic_identity, contract.matrix_hash,
    contract.verified_by, contract.verified_at
  from public.degree_level_qualification_contracts_v030 contract
  where contract.contract_code = v_build.qualification_contract_code
    and contract.status = 'VERIFIED';
  insert into public.eligibility_degree_qualification_relation_pins_v030 (
    evaluation_id, contract_code, required_degree_level,
    student_degree_level, qualifies
  )
  select v_evaluation_id, relation.contract_code,
    relation.required_degree_level, relation.student_degree_level,
    relation.qualifies
  from public.degree_level_qualification_relations_v030 relation
  where relation.contract_code = v_build.qualification_contract_code
  order by relation.required_degree_level, relation.student_degree_level;
  v_scope_id := extensions.gen_random_uuid();
  insert into public.eligibility_snapshot_scopes (
    scope_id, evaluation_id, profile_version_id, scope_kind,
    education_context_id, domain, completeness_id, completeness
  ) values (
    v_scope_id, v_evaluation_id, p_profile_version_id, 'GLOBAL_PROFILE',
    null, 'EDUCATION_HISTORY', v_completeness.completeness_id,
    v_completeness.completeness
  );
  insert into public.eligibility_completeness_pins (
    evaluation_id, completeness_id, scope_id, domain,
    completeness, explanation
  ) values (
    v_evaluation_id, v_completeness.completeness_id, v_scope_id,
    v_completeness.domain, v_completeness.completeness,
    v_completeness.explanation
  );
  insert into public.eligibility_manifest_completeness (
    evaluation_id, profile_version_id, completeness_id
  ) values (
    v_evaluation_id, p_profile_version_id, v_completeness.completeness_id
  );
  for v_row in
    select degree.* from public.student_degrees degree
    where degree.profile_version_id = p_profile_version_id
    order by degree.student_degree_id
  loop
    insert into public.eligibility_manifest_degrees (
      evaluation_id, profile_version_id, student_degree_id
    ) values (
      v_evaluation_id, p_profile_version_id, v_row.student_degree_id
    );
    insert into public.eligibility_snapshot_degrees (
      scope_id, student_degree_id, evaluation_id
    ) values (
      v_scope_id, v_row.student_degree_id, v_evaluation_id
    );
    insert into public.eligibility_manifest_student_evidence (
      evaluation_id, profile_version_id, student_evidence_id
    ) values (
      v_evaluation_id, p_profile_version_id, v_row.student_evidence_id
    ) on conflict do nothing;
    insert into public.eligibility_degree_snapshot_pins_v030 (
      evaluation_id, student_degree_id, degree_level,
      degree_status, student_evidence_id
    ) values (
      v_evaluation_id, v_row.student_degree_id, v_row.degree_level,
      v_row.degree_status, v_row.student_evidence_id
    );
  end loop;
  for v_row in
    select source_binding.rule_node_id, observation.*
    from public.program_requirement_node_sources source_binding
    join public.program_requirement_nodes node
      on node.rule_node_id = source_binding.rule_node_id
    join public.field_observations observation
      on observation.observation_id = source_binding.field_observation_id
    where node.rule_set_id = v_rule_set.rule_set_id
    order by observation.observation_id, source_binding.rule_node_id
  loop
    select source.source_id, source.source_identity_id,
      source.revision_number, source.retrieval_content_hash,
      evidence.evidence_id
      into strict v_source_id, v_source_identity_id,
        v_source_revision, v_source_hash, v_evidence_id
    from public.evidence_items evidence
    join public.sources source on source.source_id = evidence.source_id
    where evidence.evidence_id = v_row.evidence_id
    for key share of source;
    select binding.assertion_id, assertion.scope_id,
      scope.program_scope_key, scope.program_version_scope_key,
      scope.granularity_scope, scope.population_scope_code,
      scope.cycle_scope_code
      into strict v_assertion_id, v_scope_key,
        v_program_scope_key, v_program_version_scope_key,
        v_granularity, v_population, v_cycle_scope
    from public.field_observation_applicability binding
    join public.evidence_applicability_assertions assertion
      on assertion.assertion_id = binding.assertion_id
    join public.evidence_applicability_heads head
      on head.scope_id = assertion.scope_id
     and head.assertion_id = assertion.assertion_id
    join public.evidence_applicability_scopes scope
      on scope.scope_id = assertion.scope_id
    where binding.observation_id = v_row.observation_id
      and assertion.applicability_status = 'REVIEWED_APPLICABLE';
    if not exists (
      select 1 from public.eligibility_catalog_observation_pins pin
      where pin.evaluation_id = v_evaluation_id
        and pin.field_observation_id = v_row.observation_id
    ) then
      insert into public.eligibility_catalog_observation_pins (
        evaluation_id, field_observation_id, source_id,
        source_identity_id, source_revision_number,
        retrieval_content_hash, evidence_id, record_type, record_id,
        field_name, canonical_value, knowledge_status,
        program_scope_key, program_version_scope_key,
        granularity_scope, population_scope_code, cycle_scope_code
      ) values (
        v_evaluation_id, v_row.observation_id, v_source_id,
        v_source_identity_id, v_source_revision, v_source_hash,
        v_evidence_id, v_row.record_type, v_row.record_id,
        v_row.field_name, v_row.observed_value, v_row.knowledge_status,
        v_program_scope_key, v_program_version_scope_key,
        v_granularity, v_population, v_cycle_scope
      );
      select * into strict v_selection
      from public.canonical_field_selections selection
      where selection.record_type = v_row.record_type
        and selection.record_id = v_row.record_id
        and selection.field_name = v_row.field_name;
      if v_selection.observation_id is distinct from v_row.observation_id then
        raise exception using errcode = 'P0001', message = 'ELIGIBILITY_INPUT_INVALID';
      end if;
      insert into public.eligibility_catalog_selection_pins (
        evaluation_id, record_type, record_id, field_name,
        observation_id, selected_at_pin, selected_by_pin
      ) values (
        v_evaluation_id, v_selection.record_type, v_selection.record_id,
        v_selection.field_name, v_selection.observation_id,
        v_selection.selected_at, v_selection.selected_by
      );
      insert into public.eligibility_manifest_catalog_sources (
        evaluation_id, field_observation_id
      ) values (v_evaluation_id, v_row.observation_id);
    end if;
    insert into public.eligibility_rule_node_source_pins (
      evaluation_id, rule_node_id, field_observation_id, source_id,
      applicability_assertion_id, applicability_head_assertion_id_at_pin,
      applicability_scope_id, knowledge_status_at_pin
    ) values (
      v_evaluation_id, v_row.rule_node_id, v_row.observation_id,
      v_source_id, v_assertion_id, v_assertion_id, v_scope_key,
      v_row.knowledge_status
    );
  end loop;
  insert into public.eligibility_projection_threshold_pins (
    evaluation_id, rule_set_id, group_node_id, projection_kind,
    projected_minimum_children, projected_descendant_count,
    verification_evidence_id, verified_by, verified_at,
    created_at_source
  )
  select v_evaluation_id, threshold.rule_set_id, threshold.group_node_id,
    threshold.projection_kind, threshold.projected_minimum_children,
    threshold.projected_descendant_count,
    threshold.verification_evidence_id, threshold.verified_by,
    threshold.verified_at, threshold.created_at
  from public.requirement_group_projection_thresholds threshold
  where threshold.rule_set_id = v_rule_set.rule_set_id
  order by threshold.group_node_id, threshold.projection_kind;
  perform private.assert_eligibility_degree_closed_world_v030(v_evaluation_id);
  v_input_hash := private.canonical_eligibility_degree_input_v030(v_evaluation_id);
  update public.eligibility_evaluations
  set inputs_sealed_at = now(), input_fingerprint = v_input_hash
  where evaluation_id = v_evaluation_id and evaluation_state = 'BUILDING'
    and inputs_sealed_at is null;
  perform private.finalize_eligibility_degree_v030(v_evaluation_id);
  return private.project_eligibility_assembly_v030(v_evaluation_id);
exception
  when query_canceled then
    raise exception using errcode = 'P0001', message = 'REQUEST_TIMEOUT';
  when others then
    v_error := sqlerrm;
    if v_error = any(v_allowed_errors) then
      raise exception using errcode = 'P0001', message = v_error;
    end if;
    raise exception using errcode = 'P0001', message = 'INTERNAL_ERROR';
end;
$function$;

revoke all on table
  public.program_degree_requirements_v030,
  public.program_degree_requirement_predicates_v030,
  public.degree_level_qualification_contracts_v030,
  public.degree_level_qualification_relations_v030,
  public.eligibility_evaluator_builds_v030,
  public.eligibility_degree_requirement_pins_v030,
  public.eligibility_degree_qualification_pins_v030,
  public.eligibility_degree_qualification_relation_pins_v030,
  public.eligibility_degree_snapshot_pins_v030,
  public.eligibility_degree_matches_v030,
  public.eligibility_degree_negative_proofs_v030
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
revoke all on table private.eligibility_degree_operations_v030
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;

grant select, insert, update on table
  public.program_degree_requirements_v030,
  public.program_degree_requirement_predicates_v030
to foundation_catalog_executor;
grant select on table
  public.degree_level_qualification_contracts_v030,
  public.degree_level_qualification_relations_v030,
  public.eligibility_evaluator_builds_v030
to foundation_catalog_executor;
grant select on table
  public.program_degree_requirements_v030,
  public.program_degree_requirement_predicates_v030,
  public.degree_level_qualification_contracts_v030,
  public.degree_level_qualification_relations_v030,
  public.eligibility_evaluator_builds_v030
to foundation_evaluation_executor;
grant select, insert, update, delete on table
  public.eligibility_degree_requirement_pins_v030,
  public.eligibility_degree_qualification_pins_v030,
  public.eligibility_degree_qualification_relation_pins_v030,
  public.eligibility_degree_snapshot_pins_v030,
  public.eligibility_degree_matches_v030,
  public.eligibility_degree_negative_proofs_v030,
  private.eligibility_degree_operations_v030
to foundation_evaluation_executor;

alter table public.program_degree_requirements_v030 enable row level security;
alter table public.program_degree_requirements_v030 force row level security;
create policy program_degree_requirements_v030_catalog
on public.program_degree_requirements_v030
for all to foundation_catalog_executor
using (current_user = 'foundation_catalog_executor')
with check (current_user = 'foundation_catalog_executor');
create policy program_degree_requirements_v030_evaluation
on public.program_degree_requirements_v030
for select to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor');

alter table public.program_degree_requirement_predicates_v030 enable row level security;
alter table public.program_degree_requirement_predicates_v030 force row level security;
create policy program_degree_predicates_v030_catalog
on public.program_degree_requirement_predicates_v030
for all to foundation_catalog_executor
using (current_user = 'foundation_catalog_executor')
with check (current_user = 'foundation_catalog_executor');
create policy program_degree_predicates_v030_evaluation
on public.program_degree_requirement_predicates_v030
for select to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor');

do $evaluation_rls$
declare
  v_table text;
begin
  foreach v_table in array array[
    'eligibility_degree_requirement_pins_v030',
    'eligibility_degree_qualification_pins_v030',
    'eligibility_degree_qualification_relation_pins_v030',
    'eligibility_degree_snapshot_pins_v030',
    'eligibility_degree_matches_v030',
    'eligibility_degree_negative_proofs_v030'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('alter table public.%I force row level security', v_table);
    execute format(
      'create policy %I on public.%I for all to foundation_evaluation_executor '
      || 'using (current_user = ''foundation_evaluation_executor'') '
      || 'with check (current_user = ''foundation_evaluation_executor'')',
      left(v_table || '_evaluation', 63), v_table
    );
  end loop;
end;
$evaluation_rls$;
alter table private.eligibility_degree_operations_v030 enable row level security;
alter table private.eligibility_degree_operations_v030 force row level security;
create policy eligibility_degree_operations_v030_evaluation
on private.eligibility_degree_operations_v030
for all to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (current_user = 'foundation_evaluation_executor');

grant create on schema public to foundation_catalog_executor;
grant create on schema private to foundation_catalog_executor;
alter function public.create_program_degree_requirement_v030(
  text, integer, uuid, text, public.degree_level, uuid
) owner to foundation_catalog_executor;
alter function public.verify_program_degree_requirement_v030(uuid, text)
  owner to foundation_catalog_executor;
alter function public.retire_program_degree_requirement_v030(uuid, text)
  owner to foundation_catalog_executor;
alter function public.insert_program_degree_predicate_v030(uuid, uuid)
  owner to foundation_catalog_executor;
alter function public.verify_program_requirement_rule_set_degree_v030(uuid, text, uuid)
  owner to foundation_catalog_executor;
alter table public.program_degree_requirements_v030 owner to foundation_catalog_executor;
alter table public.program_degree_requirement_predicates_v030 owner to foundation_catalog_executor;
alter table public.degree_level_qualification_contracts_v030 owner to foundation_catalog_executor;
alter table public.degree_level_qualification_relations_v030 owner to foundation_catalog_executor;
alter table public.eligibility_evaluator_builds_v030 owner to foundation_catalog_executor;
alter function private.lock_eligibility_evaluator_build_v030()
  owner to foundation_catalog_executor;
revoke create on schema public from foundation_catalog_executor;
revoke create on schema private from foundation_catalog_executor;

grant create on schema public to foundation_evaluation_executor;
grant create on schema private to foundation_evaluation_executor;
alter function private.canonical_eligibility_degree_input_v030(uuid)
  owner to foundation_evaluation_executor;
alter function private.assert_eligibility_degree_closed_world_v030(uuid)
  owner to foundation_evaluation_executor;
alter function private.canonical_eligibility_degree_result_v030(uuid, public.eligibility_outcome)
  owner to foundation_evaluation_executor;
alter function private.finalize_eligibility_degree_v030(uuid)
  owner to foundation_evaluation_executor;
alter function private.project_eligibility_assembly_v030(uuid)
  owner to foundation_evaluation_executor;
alter function public.assemble_eligibility_evaluation_v030(uuid, uuid, uuid)
  owner to foundation_evaluation_executor;
alter table public.eligibility_degree_requirement_pins_v030
  owner to foundation_evaluation_executor;
alter table public.eligibility_degree_qualification_pins_v030
  owner to foundation_evaluation_executor;
alter table public.eligibility_degree_qualification_relation_pins_v030
  owner to foundation_evaluation_executor;
alter table public.eligibility_degree_snapshot_pins_v030
  owner to foundation_evaluation_executor;
alter table public.eligibility_degree_matches_v030
  owner to foundation_evaluation_executor;
alter table public.eligibility_degree_negative_proofs_v030
  owner to foundation_evaluation_executor;
alter table private.eligibility_degree_operations_v030
  owner to foundation_evaluation_executor;
revoke create on schema public from foundation_evaluation_executor;
revoke create on schema private from foundation_evaluation_executor;

revoke all on function
  public.create_program_degree_requirement_v030(text, integer, uuid, text, public.degree_level, uuid),
  public.verify_program_degree_requirement_v030(uuid, text),
  public.retire_program_degree_requirement_v030(uuid, text),
  public.insert_program_degree_predicate_v030(uuid, uuid),
  public.verify_program_requirement_rule_set_degree_v030(uuid, text, uuid)
from public, anon, authenticated, service_role, authenticator,
  foundation_student_executor, foundation_evaluation_executor;
grant execute on function
  public.create_program_degree_requirement_v030(text, integer, uuid, text, public.degree_level, uuid),
  public.verify_program_degree_requirement_v030(uuid, text),
  public.retire_program_degree_requirement_v030(uuid, text),
  public.insert_program_degree_predicate_v030(uuid, uuid),
  public.verify_program_requirement_rule_set_degree_v030(uuid, text, uuid)
to foundation_catalog_executor;

revoke all on function private.lock_eligibility_evaluator_build_v030()
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant execute on function private.lock_eligibility_evaluator_build_v030()
to foundation_evaluation_executor;

revoke all on function
  private.canonical_eligibility_degree_input_v030(uuid),
  private.assert_eligibility_degree_closed_world_v030(uuid),
  private.canonical_eligibility_degree_result_v030(uuid, public.eligibility_outcome),
  private.finalize_eligibility_degree_v030(uuid),
  private.project_eligibility_assembly_v030(uuid)
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor;
grant execute on function
  private.canonical_eligibility_degree_input_v030(uuid),
  private.assert_eligibility_degree_closed_world_v030(uuid),
  private.canonical_eligibility_degree_result_v030(uuid, public.eligibility_outcome),
  private.finalize_eligibility_degree_v030(uuid),
  private.project_eligibility_assembly_v030(uuid)
to foundation_evaluation_executor;

revoke all on function public.assemble_eligibility_evaluation_v030(uuid, uuid, uuid)
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant execute on function public.assemble_eligibility_evaluation_v030(uuid, uuid, uuid)
to authenticated;

revoke all on function
  public.guard_program_degree_requirement_v030(),
  public.guard_degree_qualification_v030(),
  public.guard_eligibility_degree_finalizer_v030()
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;

insert into public.foundation_function_contracts (
  schema_name, function_name, identity_arguments, owner_role, prosecdef,
  search_path, allowed_caller_roles, body_digest
)
select namespace.nspname, procedure.proname,
  pg_get_function_identity_arguments(procedure.oid),
  procedure.proowner::regrole::text, procedure.prosecdef,
  'pg_catalog, public, private, extensions',
  array['authenticated']::text[],
  encode(extensions.digest(
    convert_to(pg_get_functiondef(procedure.oid), 'UTF8'), 'sha256'
  ), 'hex')
from pg_proc procedure
join pg_namespace namespace on namespace.oid = procedure.pronamespace
where namespace.nspname = 'public'
  and procedure.proname = 'assemble_eligibility_evaluation_v030'
on conflict (schema_name, function_name, identity_arguments) do update
set owner_role = excluded.owner_role,
    prosecdef = excluded.prosecdef,
    search_path = excluded.search_path,
    allowed_caller_roles = excluded.allowed_caller_roles,
    body_digest = excluded.body_digest;

comment on function public.assemble_eligibility_evaluation_v030(uuid, uuid, uuid) is
  'Authenticated owner-only Eligibility degree-v1 assembly. Legacy programs delegate to frozen M026 without reinterpretation.';
comment on table public.degree_level_qualification_contracts_v030 is
  'Explicit versioned qualification law; enum ordinal order is never authority.';
comment on table public.eligibility_degree_negative_proofs_v030 is
  'Typed COMPLETE EDUCATION_HISTORY witness for degree-level NOT_SATISFIED.';

do $assert$
declare
  v_matrix_hash text;
  v_function record;
begin
  if (select count(*) from public.degree_level_qualification_relations_v030
      where contract_code = 'DEGREE_LEVEL_QUALIFICATION_V1') <> 6 then
    raise exception '030 assertion failed: qualification matrix cardinality';
  end if;
  select encode(extensions.digest(convert_to(
    'DEGREE_LEVEL_QUALIFICATION_V1|BACHELORS>BACHELORS|BACHELORS>MASTERS|BACHELORS>DOCTORAL|MASTERS>MASTERS|MASTERS>DOCTORAL|DOCTORAL>DOCTORAL',
    'UTF8'
  ), 'sha256'), 'hex') into v_matrix_hash;
  if not exists (
    select 1 from public.degree_level_qualification_contracts_v030 contract
    where contract.contract_code = 'DEGREE_LEVEL_QUALIFICATION_V1'
      and contract.matrix_hash = v_matrix_hash
      and contract.status = 'VERIFIED'
  ) then
    raise exception '030 assertion failed: qualification matrix identity';
  end if;
  select procedure.proowner::regrole::text as owner_role,
    procedure.prosecdef, procedure.provolatile, procedure.proconfig,
    pg_get_function_identity_arguments(procedure.oid) as identity_arguments,
    procedure.prorettype::regtype::text as return_type
  into strict v_function
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'assemble_eligibility_evaluation_v030';
  if v_function.owner_role <> 'foundation_evaluation_executor'
     or not v_function.prosecdef or v_function.provolatile <> 'v'
     or v_function.proconfig is distinct from
       array['search_path=pg_catalog, public, private, extensions']::text[]
     or v_function.identity_arguments <>
       'p_profile_version_id uuid, p_program_version_id uuid, p_operation_id uuid'
     or v_function.return_type <> 'jsonb' then
    raise exception '030 assertion failed: assembly function contract';
  end if;
  if not has_function_privilege(
    'authenticated', 'public.assemble_eligibility_evaluation_v030(uuid,uuid,uuid)', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.assemble_eligibility_evaluation_v030(uuid,uuid,uuid)', 'EXECUTE'
  ) or has_function_privilege(
    'service_role', 'public.assemble_eligibility_evaluation_v030(uuid,uuid,uuid)', 'EXECUTE'
  ) or has_function_privilege(
    'authenticator', 'public.assemble_eligibility_evaluation_v030(uuid,uuid,uuid)', 'EXECUTE'
  ) then
    raise exception '030 assertion failed: assembly ACL';
  end if;
  if has_table_privilege('authenticated', 'public.program_degree_requirements_v030', 'SELECT')
     or has_table_privilege('authenticated', 'public.eligibility_degree_matches_v030', 'SELECT')
     or has_table_privilege('service_role', 'public.program_degree_requirements_v030', 'SELECT')
     or has_schema_privilege('foundation_evaluation_executor', 'auth', 'USAGE')
     or has_table_privilege('foundation_evaluation_executor', 'auth.users', 'SELECT')
     or has_schema_privilege('foundation_evaluation_executor', 'public', 'CREATE')
     or has_schema_privilege('foundation_evaluation_executor', 'private', 'CREATE')
     or has_schema_privilege('foundation_catalog_executor', 'public', 'CREATE')
     or has_schema_privilege('foundation_catalog_executor', 'private', 'CREATE') then
    raise exception '030 assertion failed: authority or installer privilege widened';
  end if;
  if not exists (
    select 1 from public.foundation_function_contracts contract
    where contract.schema_name = 'public'
      and contract.function_name = 'assemble_eligibility_evaluation_v030'
      and contract.owner_role = 'foundation_evaluation_executor'
      and contract.allowed_caller_roles = array['authenticated']
      and contract.body_digest ~ '^[a-f0-9]{64}$'
  ) then
    raise exception '030 assertion failed: function registry';
  end if;
end;
$assert$;

commit;
