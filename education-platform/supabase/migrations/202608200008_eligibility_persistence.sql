begin;

create type public.requirement_truth_value as enum (
  'SATISFIED',
  'NOT_SATISFIED',
  'UNKNOWN'
);
create type public.eligibility_outcome as enum (
  'ELIGIBLE',
  'NOT_ELIGIBLE',
  'UNKNOWN',
  'CONDITIONALLY_ELIGIBLE'
);
create type public.evaluation_state as enum ('BUILDING', 'COMPLETED');

create table public.eligibility_evaluations (
  evaluation_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  rule_set_id uuid not null
    references public.program_requirement_rule_sets(rule_set_id)
    on delete restrict,
  taxonomy_release_code text not null
    references public.taxonomy_releases(release_code) on delete restrict,
  evaluator_name text not null,
  evaluator_version text not null,
  evaluator_build_hash text not null,
  input_schema_version text not null,
  profile_snapshot_hash text not null,
  evaluation_state public.evaluation_state not null default 'BUILDING',
  input_fingerprint text,
  outcome public.eligibility_outcome,
  root_truth_value public.requirement_truth_value,
  created_at timestamptz not null default now(),
  evaluated_at timestamptz,
  constraint eligibility_evaluations_identity_not_blank
    check (
      btrim(evaluator_name) <> ''
      and btrim(evaluator_version) <> ''
      and input_schema_version = 'eligibility-v0.1'
    ),
  constraint eligibility_evaluations_hashes
    check (
      evaluator_build_hash ~ '^[a-f0-9]{64}$'
      and profile_snapshot_hash ~ '^[a-f0-9]{64}$'
      and (
        input_fingerprint is null
        or input_fingerprint ~ '^[a-f0-9]{64}$'
      )
    ),
  constraint eligibility_evaluations_completion_state
    check (
      (
        evaluation_state = 'BUILDING'
        and input_fingerprint is null
        and outcome is null
        and root_truth_value is null
        and evaluated_at is null
      )
      or (
        evaluation_state = 'COMPLETED'
        and input_fingerprint is not null
        and outcome is not null
        and root_truth_value is not null
        and evaluated_at is not null
      )
    ),
  constraint eligibility_evaluations_root_outcome
    check (
      outcome is null
      or (root_truth_value = 'NOT_SATISFIED' and outcome = 'NOT_ELIGIBLE')
      or (
        root_truth_value = 'UNKNOWN'
        and outcome in ('UNKNOWN', 'CONDITIONALLY_ELIGIBLE')
      )
      or (
        root_truth_value = 'SATISFIED'
        and outcome in ('ELIGIBLE', 'CONDITIONALLY_ELIGIBLE')
      )
    ),
  unique (evaluation_id, profile_version_id)
);

create table public.eligibility_manifest_degrees (
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  student_degree_id uuid not null,
  primary key (evaluation_id, student_degree_id),
  foreign key (evaluation_id, profile_version_id)
    references public.eligibility_evaluations(
      evaluation_id,
      profile_version_id
    ) on delete cascade,
  foreign key (profile_version_id, student_degree_id)
    references public.student_degrees(
      profile_version_id,
      student_degree_id
    ) on delete cascade
);

create table public.eligibility_manifest_courses (
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  student_course_id uuid not null,
  primary key (evaluation_id, student_course_id),
  foreign key (evaluation_id, profile_version_id)
    references public.eligibility_evaluations(
      evaluation_id,
      profile_version_id
    ) on delete cascade,
  foreign key (profile_version_id, student_course_id)
    references public.student_courses(
      profile_version_id,
      student_course_id
    ) on delete cascade
);

create table public.eligibility_manifest_test_scores (
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  student_test_score_id uuid not null,
  primary key (evaluation_id, student_test_score_id),
  foreign key (evaluation_id, profile_version_id)
    references public.eligibility_evaluations(
      evaluation_id,
      profile_version_id
    ) on delete cascade,
  foreign key (profile_version_id, student_test_score_id)
    references public.student_test_scores(
      profile_version_id,
      student_test_score_id
    ) on delete cascade
);

create table public.eligibility_manifest_student_mappings (
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  student_mapping_id uuid not null,
  primary key (evaluation_id, student_mapping_id),
  foreign key (evaluation_id, profile_version_id)
    references public.eligibility_evaluations(
      evaluation_id,
      profile_version_id
    ) on delete cascade,
  foreign key (profile_version_id, student_mapping_id)
    references public.student_record_concept_mappings(
      profile_version_id,
      student_mapping_id
    ) on delete cascade
);

create table public.eligibility_manifest_completeness (
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  completeness_id uuid not null,
  primary key (evaluation_id, completeness_id),
  foreign key (evaluation_id, profile_version_id)
    references public.eligibility_evaluations(
      evaluation_id,
      profile_version_id
    ) on delete cascade,
  foreign key (profile_version_id, completeness_id)
    references public.student_data_completeness(
      profile_version_id,
      completeness_id
    ) on delete cascade
);

create table public.eligibility_manifest_student_evidence (
  evaluation_id uuid not null,
  profile_version_id uuid not null,
  student_evidence_id uuid not null,
  primary key (evaluation_id, student_evidence_id),
  foreign key (evaluation_id, profile_version_id)
    references public.eligibility_evaluations(
      evaluation_id,
      profile_version_id
    ) on delete cascade,
  foreign key (profile_version_id, student_evidence_id)
    references public.student_evidence_items(
      profile_version_id,
      student_evidence_id
    ) on delete cascade
);

create table public.eligibility_manifest_catalog_sources (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id)
    on delete cascade,
  field_observation_id uuid not null
    references public.field_observations(observation_id)
    on delete restrict,
  primary key (evaluation_id, field_observation_id)
);

create table public.eligibility_manifest_catalog_mappings (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id)
    on delete cascade,
  catalog_mapping_id uuid not null
    references public.catalog_concept_mappings(mapping_id)
    on delete restrict,
  primary key (evaluation_id, catalog_mapping_id)
);

create table public.eligibility_manifest_taxonomy_concepts (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id)
    on delete cascade,
  concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  primary key (evaluation_id, concept_id)
);

create table public.eligibility_requirement_results (
  requirement_result_id uuid primary key default extensions.gen_random_uuid(),
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id)
    on delete cascade,
  rule_node_id uuid not null
    references public.program_requirement_nodes(rule_node_id)
    on delete restrict,
  truth_value public.requirement_truth_value not null,
  reason_codes text[] not null default '{}',
  explanation text not null,
  supporting_fact_refs jsonb not null default '[]'::jsonb,
  missing_data jsonb not null default '[]'::jsonb,
  decisive boolean not null default false,
  created_at timestamptz not null default now(),
  constraint eligibility_requirement_reason_codes
    check (array_position(reason_codes, '') is null),
  constraint eligibility_requirement_explanation
    check (btrim(explanation) <> ''),
  constraint eligibility_requirement_json_arrays
    check (
      jsonb_typeof(supporting_fact_refs) = 'array'
      and jsonb_typeof(missing_data) = 'array'
    ),
  constraint eligibility_requirement_unknown_gap
    check (
      truth_value <> 'UNKNOWN'
      or jsonb_array_length(missing_data) > 0
    ),
  unique (evaluation_id, rule_node_id),
  unique (requirement_result_id, evaluation_id)
);

create table public.eligibility_course_matches (
  course_match_id uuid primary key default extensions.gen_random_uuid(),
  requirement_result_id uuid not null,
  evaluation_id uuid not null,
  catalog_mapping_id uuid not null,
  student_mapping_id uuid not null,
  student_course_id uuid not null,
  student_evidence_id uuid not null,
  created_at timestamptz not null default now(),
  foreign key (requirement_result_id, evaluation_id)
    references public.eligibility_requirement_results(
      requirement_result_id,
      evaluation_id
    ) on delete cascade,
  foreign key (evaluation_id, catalog_mapping_id)
    references public.eligibility_manifest_catalog_mappings(
      evaluation_id,
      catalog_mapping_id
    ) on delete restrict,
  foreign key (evaluation_id, student_mapping_id)
    references public.eligibility_manifest_student_mappings(
      evaluation_id,
      student_mapping_id
    ) on delete cascade,
  foreign key (evaluation_id, student_course_id)
    references public.eligibility_manifest_courses(
      evaluation_id,
      student_course_id
    ) on delete cascade,
  foreign key (evaluation_id, student_evidence_id)
    references public.eligibility_manifest_student_evidence(
      evaluation_id,
      student_evidence_id
    ) on delete cascade,
  unique (
    requirement_result_id,
    catalog_mapping_id,
    student_mapping_id
  )
);

create table public.eligibility_test_matches (
  test_match_id uuid primary key default extensions.gen_random_uuid(),
  requirement_result_id uuid not null,
  evaluation_id uuid not null,
  student_test_score_id uuid not null,
  student_evidence_id uuid not null,
  created_at timestamptz not null default now(),
  foreign key (requirement_result_id, evaluation_id)
    references public.eligibility_requirement_results(
      requirement_result_id,
      evaluation_id
    ) on delete cascade,
  foreign key (evaluation_id, student_test_score_id)
    references public.eligibility_manifest_test_scores(
      evaluation_id,
      student_test_score_id
    ) on delete cascade,
  foreign key (evaluation_id, student_evidence_id)
    references public.eligibility_manifest_student_evidence(
      evaluation_id,
      student_evidence_id
    ) on delete cascade,
  unique (requirement_result_id, student_test_score_id)
);

create index eligibility_evaluations_profile_idx
  on public.eligibility_evaluations (profile_version_id, created_at desc);
create index eligibility_evaluations_rule_set_idx
  on public.eligibility_evaluations (rule_set_id, created_at desc);
create index eligibility_results_evaluation_idx
  on public.eligibility_requirement_results (
    evaluation_id,
    rule_node_id
  );

create or replace function public.validate_eligibility_evaluation_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile public.student_profile_versions%rowtype;
  v_rule_set public.program_requirement_rule_sets%rowtype;
begin
  select * into v_profile
  from public.student_profile_versions
  where profile_version_id = new.profile_version_id;
  if v_profile.status is distinct from 'FROZEN'
     or v_profile.snapshot_hash is distinct from new.profile_snapshot_hash then
    raise exception 'Evaluation must pin the matching frozen profile snapshot';
  end if;

  select * into v_rule_set
  from public.program_requirement_rule_sets
  where rule_set_id = new.rule_set_id;
  if v_rule_set.status is distinct from 'VERIFIED'
     or v_rule_set.taxonomy_release_code is distinct from new.taxonomy_release_code
     or v_rule_set.engine_contract_version is distinct from new.input_schema_version then
    raise exception 'Evaluation must pin a verified compatible rule set and taxonomy release';
  end if;

  if exists (
    select 1
    from public.program_requirement_nodes n
    join public.program_requirement_node_mappings nm using (rule_node_id)
    join public.catalog_concept_mappings m
      on m.mapping_id = nm.catalog_mapping_id
    where n.rule_set_id = new.rule_set_id
      and m.mapping_status <> 'VERIFIED'
  ) or exists (
    select 1
    from public.program_requirement_nodes n
    join public.program_requirement_node_sources ns using (rule_node_id)
    join public.field_observations o
      on o.observation_id = ns.field_observation_id
    left join public.canonical_field_selections c
      on c.observation_id = o.observation_id
     and c.record_type = o.record_type
     and c.record_id = o.record_id
     and c.field_name = o.field_name
    where n.rule_set_id = new.rule_set_id
      and (
        o.knowledge_status <> 'KNOWN'
        or c.observation_id is null
      )
  ) then
    raise exception 'Verified rule set has stale sources or mappings and must be retired';
  end if;
  return new;
end;
$$;

create or replace function public.guard_evaluation_assembly()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_evaluation_id uuid;
  v_state public.evaluation_state;
begin
  if tg_op = 'DELETE'
     and current_setting('app.student_privacy_delete', true) = 'on' then
    return old;
  end if;
  v_evaluation_id := coalesce(new.evaluation_id, old.evaluation_id);
  select evaluation_state into v_state
  from public.eligibility_evaluations
  where evaluation_id = v_evaluation_id;
  if v_state = 'COMPLETED' then
    raise exception 'Completed evaluation manifests and results are immutable';
  end if;
  return coalesce(new, old);
end;
$$;

create or replace function public.validate_eligibility_result_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_evaluation_rule_set_id uuid;
  v_node_rule_set_id uuid;
begin
  select rule_set_id into v_evaluation_rule_set_id
  from public.eligibility_evaluations
  where evaluation_id = new.evaluation_id;
  select rule_set_id into v_node_rule_set_id
  from public.program_requirement_nodes
  where rule_node_id = new.rule_node_id;
  if v_evaluation_rule_set_id is distinct from v_node_rule_set_id then
    raise exception 'Requirement result node does not belong to the evaluated rule set';
  end if;
  return new;
end;
$$;

create or replace function public.validate_eligibility_match_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_predicate public.requirement_predicate_kind;
  v_target_concept_id uuid;
  v_catalog_concept_id uuid;
  v_student_concept_id uuid;
  v_student_record_id uuid;
  v_student_mapping_status public.mapping_status;
  v_catalog_mapping_status public.mapping_status;
  v_course_status public.course_status;
  v_test_concept_id uuid;
begin
  select n.predicate_kind, n.target_concept_id
  into v_predicate, v_target_concept_id
  from public.eligibility_requirement_results r
  join public.program_requirement_nodes n using (rule_node_id)
  where r.requirement_result_id = new.requirement_result_id
    and r.evaluation_id = new.evaluation_id
    and r.truth_value = 'SATISFIED';

  if tg_table_name = 'eligibility_course_matches' then
    if v_predicate is distinct from 'HAS_COURSE_CONCEPT' then
      raise exception 'Course matches require a satisfied course predicate';
    end if;
    select concept_id, mapping_status
    into v_catalog_concept_id, v_catalog_mapping_status
    from public.catalog_concept_mappings
    where mapping_id = new.catalog_mapping_id;
    select concept_id, student_record_id, mapping_status
    into v_student_concept_id, v_student_record_id, v_student_mapping_status
    from public.student_record_concept_mappings
    where student_mapping_id = new.student_mapping_id;
    select course_status into v_course_status
    from public.student_courses
    where student_course_id = new.student_course_id
      and student_evidence_id = new.student_evidence_id;
    if v_catalog_concept_id is distinct from v_target_concept_id
       or v_student_concept_id is distinct from v_target_concept_id
       or v_student_record_id is distinct from new.student_course_id
       or v_catalog_mapping_status is distinct from 'VERIFIED'
       or v_student_mapping_status is distinct from 'VERIFIED'
       or v_course_status is distinct from 'COMPLETED' then
      raise exception 'Course match is not an authoritative completed equivalency';
    end if;
  else
    if v_predicate is distinct from 'HAS_TEST' then
      raise exception 'Test matches require a satisfied test predicate';
    end if;
    select assessment_concept_id into v_test_concept_id
    from public.student_test_scores
    where student_test_score_id = new.student_test_score_id
      and student_evidence_id = new.student_evidence_id;
    if v_test_concept_id is distinct from v_target_concept_id then
      raise exception 'Test match does not satisfy the predicate assessment';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.guard_evaluation_update()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE'
     and current_setting('app.student_privacy_delete', true) = 'on' then
    return old;
  end if;
  if tg_op = 'UPDATE'
     and current_setting('app.evaluation_controlled_write', true) = 'on'
     and old.evaluation_state = 'BUILDING'
     and new.evaluation_state = 'COMPLETED' then
    return new;
  end if;
  raise exception 'Evaluations are append-only and finalize through finalize_eligibility_evaluation()';
end;
$$;

create or replace function public.finalize_eligibility_evaluation(
  p_evaluation_id uuid,
  p_outcome public.eligibility_outcome
)
returns text
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_evaluation public.eligibility_evaluations%rowtype;
  v_root_id uuid;
  v_root_truth public.requirement_truth_value;
  v_expected integer;
  v_actual integer;
  v_manifest jsonb;
  v_fingerprint text;
  v_prior_control_setting text;
begin
  select * into v_evaluation
  from public.eligibility_evaluations
  where evaluation_id = p_evaluation_id
  for update;
  if not found or v_evaluation.evaluation_state <> 'BUILDING' then
    raise exception 'A building evaluation is required';
  end if;

  select rule_node_id into v_root_id
  from public.program_requirement_nodes
  where rule_set_id = v_evaluation.rule_set_id
    and parent_node_id is null;
  select truth_value into v_root_truth
  from public.eligibility_requirement_results
  where evaluation_id = p_evaluation_id
    and rule_node_id = v_root_id;
  if v_root_truth is null then
    raise exception 'Root result is required';
  end if;

  select count(*) into v_expected
  from public.program_requirement_nodes
  where rule_set_id = v_evaluation.rule_set_id;
  select count(*) into v_actual
  from public.eligibility_requirement_results
  where evaluation_id = p_evaluation_id;
  if v_actual <> v_expected then
    raise exception 'Every rule node requires exactly one result';
  end if;

  if exists (
    select 1
    from public.eligibility_requirement_results r
    join public.program_requirement_nodes n using (rule_node_id)
    where r.evaluation_id = p_evaluation_id
      and r.truth_value = 'SATISFIED'
      and n.predicate_kind = 'HAS_COURSE_CONCEPT'
      and not exists (
        select 1 from public.eligibility_course_matches m
        where m.requirement_result_id = r.requirement_result_id
      )
  ) or exists (
    select 1
    from public.eligibility_requirement_results r
    join public.program_requirement_nodes n using (rule_node_id)
    where r.evaluation_id = p_evaluation_id
      and r.truth_value = 'SATISFIED'
      and n.predicate_kind = 'HAS_TEST'
      and not exists (
        select 1 from public.eligibility_test_matches m
        where m.requirement_result_id = r.requirement_result_id
      )
  ) then
    raise exception 'Satisfied predicates require an exact typed fact match';
  end if;

  if exists (
    (
      select ns.field_observation_id
      from public.program_requirement_nodes n
      join public.program_requirement_node_sources ns using (rule_node_id)
      where n.rule_set_id = v_evaluation.rule_set_id
      except
      select field_observation_id
      from public.eligibility_manifest_catalog_sources
      where evaluation_id = p_evaluation_id
    )
    union all
    (
      select field_observation_id
      from public.eligibility_manifest_catalog_sources
      where evaluation_id = p_evaluation_id
      except
      select ns.field_observation_id
      from public.program_requirement_nodes n
      join public.program_requirement_node_sources ns using (rule_node_id)
      where n.rule_set_id = v_evaluation.rule_set_id
    )
  ) then
    raise exception 'Catalog-source manifest must exactly match rule-set sources';
  end if;

  if exists (
    (
      select nm.catalog_mapping_id
      from public.program_requirement_nodes n
      join public.program_requirement_node_mappings nm using (rule_node_id)
      where n.rule_set_id = v_evaluation.rule_set_id
      except
      select catalog_mapping_id
      from public.eligibility_manifest_catalog_mappings
      where evaluation_id = p_evaluation_id
    )
    union all
    (
      select catalog_mapping_id
      from public.eligibility_manifest_catalog_mappings
      where evaluation_id = p_evaluation_id
      except
      select nm.catalog_mapping_id
      from public.program_requirement_nodes n
      join public.program_requirement_node_mappings nm using (rule_node_id)
      where n.rule_set_id = v_evaluation.rule_set_id
    )
  ) then
    raise exception 'Catalog-mapping manifest must exactly match rule-set mappings';
  end if;

  select jsonb_build_object(
    'profileVersionId', v_evaluation.profile_version_id,
    'profileSnapshotHash', v_evaluation.profile_snapshot_hash,
    'ruleSetId', v_evaluation.rule_set_id,
    'taxonomyRelease', v_evaluation.taxonomy_release_code,
    'evaluator', jsonb_build_object(
      'name', v_evaluation.evaluator_name,
      'version', v_evaluation.evaluator_version,
      'buildHash', v_evaluation.evaluator_build_hash,
      'inputSchemaVersion', v_evaluation.input_schema_version
    ),
    'degreeIds', coalesce((
      select jsonb_agg(student_degree_id order by student_degree_id)
      from public.eligibility_manifest_degrees
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'courseIds', coalesce((
      select jsonb_agg(student_course_id order by student_course_id)
      from public.eligibility_manifest_courses
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'testScoreIds', coalesce((
      select jsonb_agg(student_test_score_id order by student_test_score_id)
      from public.eligibility_manifest_test_scores
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'studentMappingIds', coalesce((
      select jsonb_agg(student_mapping_id order by student_mapping_id)
      from public.eligibility_manifest_student_mappings
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'completenessScopes', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'completenessId', manifest.completeness_id,
          'educationContextId', completeness.education_context_id,
          'domain', completeness.domain
        )
        order by
          completeness.domain,
          completeness.education_context_id nulls first,
          manifest.completeness_id
      )
      from public.eligibility_manifest_completeness manifest
      join public.student_data_completeness completeness
        on completeness.completeness_id = manifest.completeness_id
       and completeness.profile_version_id = manifest.profile_version_id
      where manifest.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'studentEvidenceIds', coalesce((
      select jsonb_agg(student_evidence_id order by student_evidence_id)
      from public.eligibility_manifest_student_evidence
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'catalogSourceIds', coalesce((
      select jsonb_agg(field_observation_id order by field_observation_id)
      from public.eligibility_manifest_catalog_sources
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'catalogMappingIds', coalesce((
      select jsonb_agg(catalog_mapping_id order by catalog_mapping_id)
      from public.eligibility_manifest_catalog_mappings
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'taxonomyConceptIds', coalesce((
      select jsonb_agg(concept_id order by concept_id)
      from public.eligibility_manifest_taxonomy_concepts
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb)
  ) into v_manifest;

  v_fingerprint := encode(
    extensions.digest(convert_to(v_manifest::text, 'UTF8'), 'sha256'),
    'hex'
  );

  v_prior_control_setting :=
    current_setting('app.evaluation_controlled_write', true);
  perform set_config('app.evaluation_controlled_write', 'on', true);
  update public.eligibility_evaluations
  set evaluation_state = 'COMPLETED',
      input_fingerprint = v_fingerprint,
      outcome = p_outcome,
      root_truth_value = v_root_truth,
      evaluated_at = now()
  where evaluation_id = p_evaluation_id;
  perform set_config(
    'app.evaluation_controlled_write',
    coalesce(v_prior_control_setting, ''),
    true
  );
  return v_fingerprint;
end;
$$;

revoke all on function public.finalize_eligibility_evaluation(uuid, public.eligibility_outcome) from public;
grant execute on function public.finalize_eligibility_evaluation(uuid, public.eligibility_outcome) to service_role;

create trigger eligibility_evaluations_validate
before insert on public.eligibility_evaluations
for each row execute function public.validate_eligibility_evaluation_insert();
create trigger eligibility_evaluations_guard
before update or delete on public.eligibility_evaluations
for each row execute function public.guard_evaluation_update();
create trigger eligibility_results_validate
before insert on public.eligibility_requirement_results
for each row execute function public.validate_eligibility_result_insert();
create trigger eligibility_course_matches_validate
before insert on public.eligibility_course_matches
for each row execute function public.validate_eligibility_match_insert();
create trigger eligibility_test_matches_validate
before insert on public.eligibility_test_matches
for each row execute function public.validate_eligibility_match_insert();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'eligibility_manifest_degrees',
    'eligibility_manifest_courses',
    'eligibility_manifest_test_scores',
    'eligibility_manifest_student_mappings',
    'eligibility_manifest_completeness',
    'eligibility_manifest_student_evidence',
    'eligibility_manifest_catalog_sources',
    'eligibility_manifest_catalog_mappings',
    'eligibility_manifest_taxonomy_concepts',
    'eligibility_requirement_results',
    'eligibility_course_matches',
    'eligibility_test_matches'
  ]
  loop
    execute format(
      'create trigger %I before insert or update or delete on public.%I for each row execute function public.guard_evaluation_assembly()',
      v_table || '_assembly_guard',
      v_table
    );
  end loop;
end;
$$;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'eligibility_evaluations',
    'eligibility_manifest_degrees',
    'eligibility_manifest_courses',
    'eligibility_manifest_test_scores',
    'eligibility_manifest_student_mappings',
    'eligibility_manifest_completeness',
    'eligibility_manifest_student_evidence',
    'eligibility_manifest_catalog_sources',
    'eligibility_manifest_catalog_mappings',
    'eligibility_manifest_taxonomy_concepts',
    'eligibility_requirement_results',
    'eligibility_course_matches',
    'eligibility_test_matches'
  ]
  loop
    execute format('alter table public.%I enable row level security', v_table);
  end loop;
end;
$$;

create policy eligibility_evaluations_owner_read
  on public.eligibility_evaluations for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'eligibility_manifest_degrees',
    'eligibility_manifest_courses',
    'eligibility_manifest_test_scores',
    'eligibility_manifest_student_mappings',
    'eligibility_manifest_completeness',
    'eligibility_manifest_student_evidence',
    'eligibility_manifest_catalog_sources',
    'eligibility_manifest_catalog_mappings',
    'eligibility_manifest_taxonomy_concepts',
    'eligibility_requirement_results',
    'eligibility_course_matches',
    'eligibility_test_matches'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated using (exists (select 1 from public.eligibility_evaluations e where e.evaluation_id = %I.evaluation_id and public.current_user_owns_profile(e.profile_version_id)))',
      v_table || '_owner_read',
      v_table,
      v_table
    );
  end loop;
end;
$$;

commit;
