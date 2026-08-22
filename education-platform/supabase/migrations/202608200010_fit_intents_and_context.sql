begin;

create type public.fit_intent_set_status as enum ('DRAFT', 'FROZEN');
create type public.fit_intent_relation as enum ('DESIRED', 'EXCLUDED');
create type public.fit_location_relation as enum (
  'PREFERRED',
  'ACCEPTABLE',
  'REQUIRED',
  'EXCLUDED'
);
create type public.fit_context_claim_code as enum (
  'REGULATORY_WORK_AUTHORIZATION',
  'LICENSING_RESTRICTION',
  'CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION',
  'REVIEWED_CAREER_OUTCOME',
  'JURISDICTION_PATH_ACCESSIBILITY'
);
create type public.fit_program_feature_key as enum (
  'CAPSTONE_AVAILABLE',
  'RESEARCH_OPPORTUNITY',
  'FACULTY_ACCESS',
  'COHORT_STRUCTURE',
  'INTERNATIONAL_PATH_SUPPORT'
);
create type public.fit_intent_validation_issue_code as enum (
  'INTENT_CONFLICT',
  'REQUIRED_EVIDENCE_MISSING',
  'REQUIRED_SEMANTICS_INVALID'
);

-- Composite keys prevent an intent from pointing across profile boundaries.
create unique index student_goals_profile_id_unique
  on public.student_goals (profile_version_id, student_goal_id);
create unique index student_preferences_profile_id_unique
  on public.student_preferences (profile_version_id, student_preference_id);

create table public.fit_intent_sets (
  intent_set_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  version_number integer not null,
  status public.fit_intent_set_status not null default 'DRAFT',
  snapshot_hash text,
  frozen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fit_intent_sets_version_positive check (version_number > 0),
  constraint fit_intent_sets_freeze_state check (
    (
      status = 'DRAFT'
      and snapshot_hash is null
      and frozen_at is null
    )
    or (
      status = 'FROZEN'
      and snapshot_hash ~ '^[a-f0-9]{64}$'
      and frozen_at is not null
    )
  ),
  unique (profile_version_id, version_number),
  unique (intent_set_id, profile_version_id)
);

create table public.fit_intent_declarations (
  intent_declaration_id uuid primary key default extensions.gen_random_uuid(),
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  origin public.fit_intent_origin not null,
  dimension public.fit_dimension not null,
  semantic_type text not null,
  importance public.fit_importance not null,
  importance_basis public.fit_importance_basis not null,
  importance_evidence_id uuid,
  importance_confirmed_by_student boolean not null default false,
  importance_reviewed_by text,
  importance_reviewed_at timestamptz,
  source_student_goal_id uuid,
  source_student_preference_id uuid,
  interpretation_method public.mapping_method not null,
  interpretation_method_version text not null,
  interpretation_provenance text not null,
  student_evidence_id uuid,
  created_at timestamptz not null default now(),
  constraint fit_intent_declarations_semantic_type check (
    semantic_type in (
      'TAXONOMY_TARGET',
      'LOCATION_CONSTRAINT',
      'DELIVERY_CONSTRAINT',
      'FINANCIAL_CONSTRAINT',
      'DURATION_CONSTRAINT',
      'PROGRAM_FEATURE_CONSTRAINT'
    )
  ),
  constraint fit_intent_declarations_dimension_ownership check (
    (semantic_type = 'TAXONOMY_TARGET'
      and dimension in ('ACADEMIC', 'CAREER', 'INTERNATIONAL_ACCESSIBILITY'))
    or (semantic_type in ('LOCATION_CONSTRAINT', 'DELIVERY_CONSTRAINT')
      and dimension = 'GEOGRAPHIC_DELIVERY')
    or (semantic_type = 'FINANCIAL_CONSTRAINT'
      and dimension = 'FINANCIAL')
    or (semantic_type = 'DURATION_CONSTRAINT'
      and dimension = 'PERSONAL_PREFERENCE')
    or (semantic_type = 'PROGRAM_FEATURE_CONSTRAINT'
      and dimension in ('PERSONAL_PREFERENCE', 'INTERNATIONAL_ACCESSIBILITY'))
  ),
  constraint fit_intent_declarations_method_version check (
    btrim(interpretation_method_version) <> ''
  ),
  constraint fit_intent_declarations_provenance check (
    btrim(interpretation_provenance) <> ''
  ),
  constraint fit_intent_declarations_origin_shape check (
    (
      origin = 'PHASE2_INTERPRETATION'
      and (
        (source_student_goal_id is not null)::integer
        + (source_student_preference_id is not null)::integer
      ) = 1
    )
    or (
      origin = 'PHASE3_DECLARATION'
      and source_student_goal_id is null
      and source_student_preference_id is null
      and student_evidence_id is not null
    )
  ),
  unique (intent_declaration_id, intent_set_id, profile_version_id),
  foreign key (intent_set_id, profile_version_id)
    references public.fit_intent_sets(intent_set_id, profile_version_id)
    on delete cascade,
  foreign key (profile_version_id, source_student_goal_id)
    references public.student_goals(profile_version_id, student_goal_id)
    on delete cascade,
  foreign key (profile_version_id, source_student_preference_id)
    references public.student_preferences(
      profile_version_id,
      student_preference_id
    ) on delete cascade,
  foreign key (profile_version_id, student_evidence_id)
    references public.student_evidence_items(
      profile_version_id,
      student_evidence_id
    ) on delete cascade,
  foreign key (profile_version_id, importance_evidence_id)
    references public.student_evidence_items(
      profile_version_id,
      student_evidence_id
    ) on delete cascade,
  constraint fit_intent_required_authority check (
    importance <> 'REQUIRED'
    or (
      importance_basis in (
        'STRUCTURED_STUDENT_DECLARATION',
        'NORMALIZED_STUDENT_LANGUAGE'
      )
      and importance_evidence_id is not null
    )
  ),
  constraint fit_intent_importance_review_pair check (
    (importance_reviewed_by is null) = (importance_reviewed_at is null)
    and (
      importance_reviewed_by is null
      or nullif(btrim(importance_reviewed_by), '') is not null
    )
  )
);

create table public.fit_intent_validation_issues (
  validation_issue_id uuid primary key default extensions.gen_random_uuid(),
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  issue_code public.fit_intent_validation_issue_code not null,
  semantic_domain text not null,
  first_intent_declaration_id uuid,
  second_intent_declaration_id uuid,
  explanation text not null,
  created_at timestamptz not null default now(),
  foreign key (intent_set_id, profile_version_id)
    references public.fit_intent_sets(intent_set_id, profile_version_id)
    on delete cascade,
  foreign key (
    first_intent_declaration_id, intent_set_id, profile_version_id
  ) references public.fit_intent_declarations(
    intent_declaration_id, intent_set_id, profile_version_id
  ) on delete cascade,
  foreign key (
    second_intent_declaration_id, intent_set_id, profile_version_id
  ) references public.fit_intent_declarations(
    intent_declaration_id, intent_set_id, profile_version_id
  ) on delete cascade,
  constraint fit_intent_validation_domain
    check (semantic_domain ~ '^[A-Z][A-Z0-9_]*$'),
  constraint fit_intent_validation_explanation
    check (btrim(explanation) <> ''),
  constraint fit_intent_validation_distinct_pair check (
    second_intent_declaration_id is null
    or first_intent_declaration_id is distinct from second_intent_declaration_id
  )
);

create table public.fit_intent_taxonomy_targets (
  intent_declaration_id uuid primary key,
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  relation public.fit_intent_relation not null,
  foreign key (intent_declaration_id, intent_set_id, profile_version_id)
    references public.fit_intent_declarations(
      intent_declaration_id,
      intent_set_id,
      profile_version_id
    ) on delete cascade
);

create table public.fit_intent_location_constraints (
  intent_declaration_id uuid primary key,
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  relation public.fit_location_relation not null,
  country_code text,
  region_code text,
  locality text,
  foreign key (intent_declaration_id, intent_set_id, profile_version_id)
    references public.fit_intent_declarations(
      intent_declaration_id,
      intent_set_id,
      profile_version_id
    ) on delete cascade,
  constraint fit_intent_location_has_scope check (
    country_code is not null or region_code is not null or locality is not null
  ),
  constraint fit_intent_location_country check (
    country_code is null or country_code ~ '^[A-Z]{2}$'
  ),
  constraint fit_intent_location_region check (
    region_code is null or region_code ~ '^[A-Z0-9][A-Z0-9_-]{0,31}$'
  ),
  constraint fit_intent_location_locality check (
    locality is null or btrim(locality) <> ''
  )
);

create table public.fit_intent_delivery_constraints (
  intent_declaration_id uuid primary key,
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  delivery_mode public.delivery_mode not null,
  relation public.fit_intent_relation not null,
  foreign key (intent_declaration_id, intent_set_id, profile_version_id)
    references public.fit_intent_declarations(
      intent_declaration_id,
      intent_set_id,
      profile_version_id
    ) on delete cascade,
  constraint fit_intent_delivery_known check (delivery_mode <> 'UNKNOWN')
);

create or replace function public.fit_text_array_is_set(p_values text[])
returns boolean
language sql
immutable
strict
as $$
  select count(*) = count(distinct value)
  from unnest(p_values) value;
$$;

create table public.fit_intent_financial_constraints (
  intent_declaration_id uuid primary key,
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  amount numeric(14,2) not null,
  constraint_semantics public.fit_financial_constraint_semantics not null,
  currency char(3) not null,
  financial_scope public.fit_financial_scope not null,
  financial_period public.fit_financial_period not null,
  financial_basis public.fit_financial_basis not null,
  components text[] not null,
  foreign key (intent_declaration_id, intent_set_id, profile_version_id)
    references public.fit_intent_declarations(
      intent_declaration_id,
      intent_set_id,
      profile_version_id
    ) on delete cascade,
  constraint fit_intent_financial_amount check (amount >= 0),
  constraint fit_intent_financial_currency check (currency ~ '^[A-Z]{3}$'),
  constraint fit_intent_financial_components check (
    cardinality(components) > 0
    and array_position(components, null) is null
    and array_position(components, '') is null
    and public.fit_text_array_is_set(components)
  ),
  constraint fit_intent_financial_semantics_shape check (
    (
      constraint_semantics in (
        'HARD_TOTAL_COST_CEILING',
        'PREFERRED_TOTAL_COST'
      )
      and financial_scope = 'TOTAL_COST'
    )
    or (
      constraint_semantics in (
        'HARD_TUITION_CEILING',
        'PREFERRED_TUITION'
      )
      and financial_scope in ('COMPONENT', 'PARTIAL_TOTAL')
      and 'TUITION' = any(components)
    )
    or constraint_semantics = 'AVAILABLE_FUNDING'
  )
);

create table public.fit_intent_duration_constraints (
  intent_declaration_id uuid primary key,
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  minimum_months numeric(6,2),
  maximum_months numeric(6,2),
  foreign key (intent_declaration_id, intent_set_id, profile_version_id)
    references public.fit_intent_declarations(
      intent_declaration_id,
      intent_set_id,
      profile_version_id
    ) on delete cascade,
  constraint fit_intent_duration_bounds check (
    (minimum_months is not null or maximum_months is not null)
    and (minimum_months is null or minimum_months > 0)
    and (maximum_months is null or maximum_months > 0)
    and (
      minimum_months is null
      or maximum_months is null
      or maximum_months >= minimum_months
    )
  )
);

create table public.fit_intent_program_feature_constraints (
  intent_declaration_id uuid primary key,
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  feature_key public.fit_program_feature_key not null,
  expected boolean not null,
  foreign key (intent_declaration_id, intent_set_id, profile_version_id)
    references public.fit_intent_declarations(
      intent_declaration_id,
      intent_set_id,
      profile_version_id
    ) on delete cascade,
  constraint fit_intent_program_feature_not_prohibited check (
    feature_key::text not in (
      'PRESTIGE', 'RANKING', 'ADMISSION_PROBABILITY',
      'COMPETITIVENESS', 'ELIGIBILITY',
      'GENERIC_CAPABILITY_SCORE', 'GENERIC_QUALITY_SCORE'
    )
  )
);

create table private.fit_student_access_contexts (
  access_context_id uuid primary key default extensions.gen_random_uuid(),
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  citizenship_country_code text,
  residence_country_code text,
  governing_jurisdiction_code text,
  current_status_code text,
  authorization_path_code text,
  target_path_code text,
  student_evidence_id uuid not null,
  provenance text not null,
  created_at timestamptz not null default now(),
  foreign key (intent_set_id, profile_version_id)
    references public.fit_intent_sets(intent_set_id, profile_version_id)
    on delete cascade,
  foreign key (profile_version_id, student_evidence_id)
    references public.student_evidence_items(
      profile_version_id,
      student_evidence_id
    ) on delete cascade,
  constraint fit_student_access_context_scope check (
    citizenship_country_code is not null
    or residence_country_code is not null
    or governing_jurisdiction_code is not null
    or current_status_code is not null
    or authorization_path_code is not null
    or target_path_code is not null
  ),
  constraint fit_student_access_context_countries check (
    (citizenship_country_code is null or citizenship_country_code ~ '^[A-Z]{2}$')
    and (residence_country_code is null or residence_country_code ~ '^[A-Z]{2}$')
  ),
  constraint fit_student_access_context_codes check (
    (governing_jurisdiction_code is null or governing_jurisdiction_code ~ '^[A-Z][A-Z0-9_-]{1,31}$')
    and (current_status_code is null or current_status_code ~ '^[A-Z][A-Z0-9_-]{1,63}$')
    and (authorization_path_code is null or authorization_path_code ~ '^[A-Z][A-Z0-9_-]{1,63}$')
    and (target_path_code is null or target_path_code ~ '^[A-Z][A-Z0-9_-]{1,63}$')
  ),
  constraint fit_student_access_context_provenance check (
    btrim(provenance) <> ''
  )
);

create index fit_intent_sets_profile_idx
  on public.fit_intent_sets (profile_version_id, version_number desc);
create index fit_intent_declarations_set_idx
  on public.fit_intent_declarations (intent_set_id, dimension);
create index fit_intent_validation_issues_set_idx
  on public.fit_intent_validation_issues (intent_set_id, issue_code);
create index fit_intent_declarations_goal_idx
  on public.fit_intent_declarations (source_student_goal_id)
  where source_student_goal_id is not null;
create index fit_intent_declarations_preference_idx
  on public.fit_intent_declarations (source_student_preference_id)
  where source_student_preference_id is not null;
create index fit_student_access_context_set_idx
  on private.fit_student_access_contexts (intent_set_id);

create trigger fit_intent_sets_set_updated_at
before update on public.fit_intent_sets
for each row execute function public.set_updated_at();

create or replace function public.guard_fit_intent_content()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_row jsonb;
  v_intent_set_id uuid;
  v_status public.fit_intent_set_status;
begin
  if tg_op = 'DELETE'
     and current_setting('app.student_privacy_delete', true) = 'on' then
    return old;
  end if;
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_intent_set_id := (v_row ->> 'intent_set_id')::uuid;
  select status into v_status
  from public.fit_intent_sets
  where intent_set_id = v_intent_set_id
  for share;
  if v_status = 'FROZEN' then
    raise exception 'Frozen Fit intent content is immutable';
  end if;
  return coalesce(new, old);
end;
$$;

create or replace function public.guard_fit_intent_set()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE'
     and current_setting('app.student_privacy_delete', true) = 'on' then
    return old;
  end if;
  if tg_op = 'DELETE' or old.status = 'FROZEN' then
    raise exception 'Frozen Fit intent sets are immutable';
  end if;
  if new.status is distinct from old.status
     and current_setting('app.fit_intent_controlled_write', true)
       is distinct from 'on' then
    raise exception 'Use freeze_fit_intent_set()';
  end if;
  return new;
end;
$$;

create or replace function public.validate_fit_intent_set_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.student_profile_versions
    where profile_version_id = new.profile_version_id
      and status = 'FROZEN'
  ) then
    raise exception 'Fit intent sets require a frozen profile version';
  end if;
  return new;
end;
$$;

create or replace function public.validate_fit_intent_typed_child()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_expected text;
  v_actual text;
  v_count integer;
begin
  perform pg_advisory_xact_lock(
    hashtextextended(new.intent_declaration_id::text, 0)
  );
  v_expected := case tg_table_name
    when 'fit_intent_taxonomy_targets' then 'TAXONOMY_TARGET'
    when 'fit_intent_location_constraints' then 'LOCATION_CONSTRAINT'
    when 'fit_intent_delivery_constraints' then 'DELIVERY_CONSTRAINT'
    when 'fit_intent_financial_constraints' then 'FINANCIAL_CONSTRAINT'
    when 'fit_intent_duration_constraints' then 'DURATION_CONSTRAINT'
    when 'fit_intent_program_feature_constraints' then 'PROGRAM_FEATURE_CONSTRAINT'
  end;
  select semantic_type into v_actual
  from public.fit_intent_declarations
  where intent_declaration_id = new.intent_declaration_id
    and intent_set_id = new.intent_set_id
    and profile_version_id = new.profile_version_id;
  if v_actual is distinct from v_expected then
    raise exception 'Typed intent child % requires semantic type %',
      tg_table_name, v_expected;
  end if;
  select
    (select count(*) from public.fit_intent_taxonomy_targets where intent_declaration_id = new.intent_declaration_id)
    + (select count(*) from public.fit_intent_location_constraints where intent_declaration_id = new.intent_declaration_id)
    + (select count(*) from public.fit_intent_delivery_constraints where intent_declaration_id = new.intent_declaration_id)
    + (select count(*) from public.fit_intent_financial_constraints where intent_declaration_id = new.intent_declaration_id)
    + (select count(*) from public.fit_intent_duration_constraints where intent_declaration_id = new.intent_declaration_id)
    + (select count(*) from public.fit_intent_program_feature_constraints where intent_declaration_id = new.intent_declaration_id)
  into v_count;
  if (tg_op = 'INSERT' and v_count > 0)
     or (
       tg_op = 'UPDATE'
       and new.intent_declaration_id is distinct from
         old.intent_declaration_id
       and v_count > 0
     ) then
    raise exception 'A Fit intent declaration may have at most one typed child';
  end if;
  return new;
end;
$$;

create or replace function public.validate_fit_intent_declaration_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.semantic_type is distinct from old.semantic_type
     and (
       exists (select 1 from public.fit_intent_taxonomy_targets where intent_declaration_id = old.intent_declaration_id)
       or exists (select 1 from public.fit_intent_location_constraints where intent_declaration_id = old.intent_declaration_id)
       or exists (select 1 from public.fit_intent_delivery_constraints where intent_declaration_id = old.intent_declaration_id)
       or exists (select 1 from public.fit_intent_financial_constraints where intent_declaration_id = old.intent_declaration_id)
       or exists (select 1 from public.fit_intent_duration_constraints where intent_declaration_id = old.intent_declaration_id)
       or exists (select 1 from public.fit_intent_program_feature_constraints where intent_declaration_id = old.intent_declaration_id)
     ) then
    raise exception 'Remove the typed child before changing intent semantic type';
  end if;
  return new;
end;
$$;

create trigger fit_intent_sets_validate_insert
before insert on public.fit_intent_sets
for each row execute function public.validate_fit_intent_set_insert();
create trigger fit_intent_sets_guard
before update or delete on public.fit_intent_sets
for each row execute function public.guard_fit_intent_set();
create trigger fit_intent_declarations_guard
before insert or update or delete on public.fit_intent_declarations
for each row execute function public.guard_fit_intent_content();
create trigger fit_intent_validation_issues_guard
before insert or update or delete on public.fit_intent_validation_issues
for each row execute function public.guard_fit_intent_content();
create trigger fit_intent_declarations_typed_update
before update on public.fit_intent_declarations
for each row execute function public.validate_fit_intent_declaration_update();
create trigger fit_student_access_context_guard
before insert or update or delete on private.fit_student_access_contexts
for each row execute function public.guard_fit_intent_content();

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fit_intent_taxonomy_targets',
    'fit_intent_location_constraints',
    'fit_intent_delivery_constraints',
    'fit_intent_financial_constraints',
    'fit_intent_duration_constraints',
    'fit_intent_program_feature_constraints'
  ]
  loop
    execute format(
      'create trigger %I before insert or update on public.%I for each row execute function public.validate_fit_intent_typed_child()',
      v_table || '_typed_child_validate',
      v_table
    );
    execute format(
      'create trigger %I before insert or update or delete on public.%I for each row execute function public.guard_fit_intent_content()',
      v_table || '_frozen_guard',
      v_table
    );
  end loop;
end;
$$;

create or replace function public.freeze_fit_intent_set(p_intent_set_id uuid)
returns text
language plpgsql
security definer
set search_path = public, private, extensions, pg_temp
as $$
declare
  v_set public.fit_intent_sets%rowtype;
  v_invalid integer;
  v_manifest jsonb;
  v_hash text;
  v_prior_setting text;
begin
  select * into v_set
  from public.fit_intent_sets
  where intent_set_id = p_intent_set_id
  for update;
  if not found or v_set.status <> 'DRAFT' then
    raise exception 'A draft Fit intent set is required';
  end if;
  if not exists (
    select 1 from public.student_profile_versions
    where profile_version_id = v_set.profile_version_id
      and status = 'FROZEN'
  ) then
    raise exception 'The source profile version must remain frozen';
  end if;

  select count(*) into v_invalid
  from public.fit_intent_declarations d
  where d.intent_set_id = p_intent_set_id
    and (
      (select count(*) from public.fit_intent_taxonomy_targets c where c.intent_declaration_id = d.intent_declaration_id)
      + (select count(*) from public.fit_intent_location_constraints c where c.intent_declaration_id = d.intent_declaration_id)
      + (select count(*) from public.fit_intent_delivery_constraints c where c.intent_declaration_id = d.intent_declaration_id)
      + (select count(*) from public.fit_intent_financial_constraints c where c.intent_declaration_id = d.intent_declaration_id)
      + (select count(*) from public.fit_intent_duration_constraints c where c.intent_declaration_id = d.intent_declaration_id)
      + (select count(*) from public.fit_intent_program_feature_constraints c where c.intent_declaration_id = d.intent_declaration_id)
    ) <> 1;
  if v_invalid > 0 then
    raise exception 'Every frozen Fit intent declaration requires exactly one typed child';
  end if;
  if exists (
    select 1
    from public.fit_intent_taxonomy_targets target
    join public.taxonomy_concepts concept using(concept_id)
    join public.taxonomy_releases introduced
      on introduced.release_code = concept.introduced_in_release
    where target.intent_set_id = p_intent_set_id
      and (
        introduced.published_at > now()
        or concept.retired_in_release is not null
      )
  ) then
    raise exception using errcode='23514',
      message='Frozen Fit intent taxonomy targets must be active published concepts';
  end if;

  delete from public.fit_intent_validation_issues
  where intent_set_id = p_intent_set_id;

  insert into public.fit_intent_validation_issues (
    intent_set_id, profile_version_id, issue_code, semantic_domain,
    first_intent_declaration_id, explanation
  )
  select
    d.intent_set_id, d.profile_version_id, 'REQUIRED_EVIDENCE_MISSING',
    d.semantic_type, d.intent_declaration_id,
    'REQUIRED importance lacks explicit student evidence or student-authorized basis.'
  from public.fit_intent_declarations d
  where d.intent_set_id = p_intent_set_id
    and d.importance = 'REQUIRED'
    and (
      d.importance_evidence_id is null
      or not exists (
        select 1
        from public.student_evidence_items evidence
        where evidence.student_evidence_id = d.importance_evidence_id
          and evidence.profile_version_id = d.profile_version_id
          and (
            evidence.content_hash is not null
            or nullif(btrim(evidence.locator), '') is not null
          )
      )
      or d.importance_basis = 'REVIEWED_INTERPRETATION'
      or (
        d.importance_basis = 'NORMALIZED_STUDENT_LANGUAGE'
        and (
          d.interpretation_method = 'MODEL'
          or (
            not d.importance_confirmed_by_student
            and d.importance_reviewed_by is null
          )
        )
      )
    );

  -- v0.1 delivery compatibility contract: at most one REQUIRED DESIRED
  -- delivery mode. Distinct REQUIRED DESIRED modes are incompatible.
  insert into public.fit_intent_validation_issues (
    intent_set_id, profile_version_id, issue_code, semantic_domain,
    first_intent_declaration_id, explanation
  )
  select
    d.intent_set_id, d.profile_version_id, 'REQUIRED_SEMANTICS_INVALID',
    d.semantic_type, d.intent_declaration_id,
    'REQUIRED importance must use hard typed comparison semantics.'
  from public.fit_intent_declarations d
  left join public.fit_intent_location_constraints location
    on location.intent_declaration_id = d.intent_declaration_id
  left join public.fit_intent_financial_constraints financial
    on financial.intent_declaration_id = d.intent_declaration_id
  where d.intent_set_id = p_intent_set_id
    and d.importance = 'REQUIRED'
    and (
      (location.intent_declaration_id is not null
        and location.relation not in ('REQUIRED', 'EXCLUDED'))
      or (financial.intent_declaration_id is not null
        and financial.constraint_semantics in (
          'PREFERRED_TOTAL_COST', 'PREFERRED_TUITION'
        ))
    );

  insert into public.fit_intent_validation_issues (
    intent_set_id, profile_version_id, issue_code, semantic_domain,
    first_intent_declaration_id, second_intent_declaration_id, explanation
  )
  select
    a.intent_set_id, a.profile_version_id, 'INTENT_CONFLICT',
    'LOCATION_CONSTRAINT', a.intent_declaration_id, b.intent_declaration_id,
    'Mutually exclusive REQUIRED locations must be resolved by the student.'
  from public.fit_intent_declarations da
  join public.fit_intent_location_constraints a
    on a.intent_declaration_id = da.intent_declaration_id
  join public.fit_intent_location_constraints b
    on b.intent_set_id = a.intent_set_id
   and b.intent_declaration_id > a.intent_declaration_id
  join public.fit_intent_declarations db
    on db.intent_declaration_id = b.intent_declaration_id
  where da.intent_set_id = p_intent_set_id
    and da.importance = 'REQUIRED'
    and db.importance = 'REQUIRED'
    and (
      (
        a.relation = 'REQUIRED'
        and b.relation = 'REQUIRED'
        and (
          (a.country_code is not null and b.country_code is not null
            and a.country_code <> b.country_code)
          or (a.region_code is not null and b.region_code is not null
            and a.region_code <> b.region_code)
          or (a.locality is not null and b.locality is not null
            and lower(btrim(a.locality)) <> lower(btrim(b.locality)))
        )
      )
      or (
        a.relation <> b.relation
        and 'EXCLUDED' in (a.relation, b.relation)
        and a.country_code is not distinct from b.country_code
        and a.region_code is not distinct from b.region_code
        and lower(btrim(a.locality)) is not distinct from
          lower(btrim(b.locality))
      )
    );

  insert into public.fit_intent_validation_issues (
    intent_set_id, profile_version_id, issue_code, semantic_domain,
    first_intent_declaration_id, second_intent_declaration_id, explanation
  )
  select
    a.intent_set_id, a.profile_version_id, 'INTENT_CONFLICT',
    'DELIVERY_CONSTRAINT', a.intent_declaration_id, b.intent_declaration_id,
    'Mutually exclusive REQUIRED delivery modes must be resolved by the student.'
  from public.fit_intent_declarations da
  join public.fit_intent_delivery_constraints a
    on a.intent_declaration_id = da.intent_declaration_id
  join public.fit_intent_delivery_constraints b
    on b.intent_set_id = a.intent_set_id
   and b.intent_declaration_id > a.intent_declaration_id
  join public.fit_intent_declarations db
    on db.intent_declaration_id = b.intent_declaration_id
  where da.intent_set_id = p_intent_set_id
    and da.importance = 'REQUIRED'
    and db.importance = 'REQUIRED'
    and (
      (a.relation = 'DESIRED' and b.relation = 'DESIRED'
        and a.delivery_mode <> b.delivery_mode)
      or (a.relation <> b.relation
        and a.delivery_mode = b.delivery_mode)
    );

  if exists (
    select 1 from public.fit_intent_validation_issues
    where intent_set_id = p_intent_set_id
  ) then
    return 'VALIDATION_FAILED';
  end if;

  select jsonb_build_object(
    'profileVersionId', v_set.profile_version_id,
    'versionNumber', v_set.version_number,
    'declarations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', d.intent_declaration_id,
          'origin', d.origin,
          'dimension', d.dimension,
          'semanticType', d.semantic_type,
          'importance', d.importance,
          'importanceBasis', d.importance_basis,
          'importanceEvidenceId', d.importance_evidence_id,
          'importanceConfirmedByStudent',
            d.importance_confirmed_by_student,
          'importanceReviewedBy', d.importance_reviewed_by,
          'importanceReviewedAt', d.importance_reviewed_at,
          'sourceGoalId', d.source_student_goal_id,
          'sourcePreferenceId', d.source_student_preference_id,
          'method', d.interpretation_method,
          'methodVersion', d.interpretation_method_version,
          'provenance', d.interpretation_provenance,
          'studentEvidenceId', d.student_evidence_id,
          'typedValue', coalesce(
            (select jsonb_build_object('conceptId', c.concept_id, 'relation', c.relation) from public.fit_intent_taxonomy_targets c where c.intent_declaration_id = d.intent_declaration_id),
            (select jsonb_build_object('relation', c.relation, 'countryCode', c.country_code, 'regionCode', c.region_code, 'locality', c.locality) from public.fit_intent_location_constraints c where c.intent_declaration_id = d.intent_declaration_id),
            (select jsonb_build_object('deliveryMode', c.delivery_mode, 'relation', c.relation) from public.fit_intent_delivery_constraints c where c.intent_declaration_id = d.intent_declaration_id),
            (select jsonb_build_object(
              'amount', c.amount,
              'constraintSemantics', c.constraint_semantics,
              'currency', c.currency,
              'scope', c.financial_scope,
              'period', c.financial_period,
              'basis', c.financial_basis,
              'components', (
                select jsonb_agg(component order by component)
                from unnest(c.components) component
              )
            ) from public.fit_intent_financial_constraints c where c.intent_declaration_id = d.intent_declaration_id),
            (select jsonb_build_object('minimumMonths', c.minimum_months, 'maximumMonths', c.maximum_months) from public.fit_intent_duration_constraints c where c.intent_declaration_id = d.intent_declaration_id),
            (select jsonb_build_object('featureKey', c.feature_key, 'expected', c.expected) from public.fit_intent_program_feature_constraints c where c.intent_declaration_id = d.intent_declaration_id)
          )
        )
        order by d.intent_declaration_id
      )
      from public.fit_intent_declarations d
      where d.intent_set_id = p_intent_set_id
    ), '[]'::jsonb),
    'accessContexts', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id', c.access_context_id,
          'citizenshipCountryCode', c.citizenship_country_code,
          'residenceCountryCode', c.residence_country_code,
          'jurisdictionCode', c.governing_jurisdiction_code,
          'statusCode', c.current_status_code,
          'authorizationPathCode', c.authorization_path_code,
          'targetPathCode', c.target_path_code,
          'studentEvidenceId', c.student_evidence_id,
          'provenance', c.provenance
        )
        order by c.access_context_id
      )
      from private.fit_student_access_contexts c
      where c.intent_set_id = p_intent_set_id
    ), '[]'::jsonb)
  ) into v_manifest;
  v_hash := encode(
    extensions.digest(convert_to(v_manifest::text, 'UTF8'), 'sha256'),
    'hex'
  );
  v_prior_setting := current_setting('app.fit_intent_controlled_write', true);
  perform set_config('app.fit_intent_controlled_write', 'on', true);
  update public.fit_intent_sets
  set status = 'FROZEN', snapshot_hash = v_hash, frozen_at = now()
  where intent_set_id = p_intent_set_id;
  perform set_config(
    'app.fit_intent_controlled_write',
    coalesce(v_prior_setting, ''),
    true
  );
  return v_hash;
end;
$$;

-- Phase 3 contextual facts form a separate definition-versioned ledger.
create table public.fit_context_claim_definitions (
  claim_definition_id uuid primary key default extensions.gen_random_uuid(),
  owner_layer text not null default 'PHASE3_CONTEXT',
  claim_code public.fit_context_claim_code not null,
  semantic_source_class_code text not null
    references public.fit_semantic_source_classes(source_class_code)
    on delete restrict,
  definition_version integer not null,
  description text not null,
  value_contract jsonb not null,
  status public.fit_definition_status not null default 'DRAFT',
  reviewed_by text,
  reviewed_at timestamptz,
  verification_evidence_id uuid
    references public.evidence_items(evidence_id) on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint fit_context_definitions_owner check (
    owner_layer = 'PHASE3_CONTEXT'
  ),
  constraint fit_context_definitions_source_class check (
    (claim_code = 'REGULATORY_WORK_AUTHORIZATION'
      and semantic_source_class_code = 'FIT_CONTEXT_REGULATORY')
    or (claim_code = 'REVIEWED_CAREER_OUTCOME'
      and semantic_source_class_code = 'FIT_CONTEXT_CAREER')
    or (claim_code in (
        'LICENSING_RESTRICTION',
        'CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION',
        'JURISDICTION_PATH_ACCESSIBILITY'
      )
      and semantic_source_class_code = 'FIT_CONTEXT_ACCESSIBILITY')
  ),
  constraint fit_context_definitions_version check (definition_version > 0),
  constraint fit_context_definitions_description check (btrim(description) <> ''),
  constraint fit_context_definitions_contract check (
    jsonb_typeof(value_contract) = 'object'
    and value_contract ? 'requiredKeys'
    and jsonb_typeof(value_contract -> 'requiredKeys') = 'array'
  ),
  constraint fit_context_definitions_review_state check (
    (
      status = 'DRAFT'
      and reviewed_by is null and reviewed_at is null
      and verification_evidence_id is null
      and retired_at is null and retirement_reason is null
    )
    or (
      status = 'VERIFIED'
      and nullif(btrim(reviewed_by), '') is not null
      and reviewed_at is not null
      and verification_evidence_id is not null
      and retired_at is null and retirement_reason is null
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
  unique (claim_code, definition_version),
  unique (claim_definition_id, definition_version)
);

create table public.fit_context_claims (
  context_claim_id uuid primary key default extensions.gen_random_uuid(),
  claim_definition_id uuid not null,
  definition_version integer not null,
  program_version_id uuid
    references public.program_versions(program_version_id) on delete restrict,
  geography_code text,
  jurisdiction_code text,
  concept_id uuid
    references public.taxonomy_concepts(concept_id) on delete restrict,
  path_code text,
  valid_from date not null,
  valid_to date,
  claim_key text generated always as (
    encode(
      extensions.digest(
        claim_definition_id::text || '|' || definition_version::text || '|'
        || coalesce(program_version_id::text, '') || '|'
        || coalesce(lower(btrim(geography_code)), '') || '|'
        || coalesce(upper(btrim(jurisdiction_code)), '') || '|'
        || coalesce(concept_id::text, '') || '|'
        || coalesce(upper(btrim(path_code)), '') || '|'
        || (valid_from - date '2000-01-01')::text || '|'
        || coalesce(
          (valid_to - date '2000-01-01')::text,
          'INFINITY'
        ),
        'sha256'
      ),
      'hex'
    )
  ) stored,
  created_at timestamptz not null default now(),
  foreign key (claim_definition_id, definition_version)
    references public.fit_context_claim_definitions(
      claim_definition_id,
      definition_version
    ) on delete restrict,
  constraint fit_context_claims_scope_present check (
    program_version_id is not null
    or geography_code is not null
    or jurisdiction_code is not null
    or concept_id is not null
    or path_code is not null
  ),
  constraint fit_context_claims_geography check (
    geography_code is null or geography_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$'
  ),
  constraint fit_context_claims_jurisdiction check (
    jurisdiction_code is null or jurisdiction_code ~ '^[A-Z][A-Z0-9_-]{1,31}$'
  ),
  constraint fit_context_claims_path check (
    path_code is null or path_code ~ '^[A-Z][A-Z0-9_-]{1,63}$'
  ),
  constraint fit_context_claims_validity check (
    valid_to is null or valid_to >= valid_from
  ),
  unique (claim_key)
);

create table public.fit_context_claim_observations (
  context_observation_id uuid primary key default extensions.gen_random_uuid(),
  context_claim_id uuid not null
    references public.fit_context_claims(context_claim_id) on delete restrict,
  observed_value jsonb not null,
  authority public.fit_claim_authority not null,
  workflow_status public.fit_claim_workflow_status not null default 'PROPOSED',
  evidence_id uuid not null
    references public.evidence_items(evidence_id) on delete restrict,
  method public.mapping_method not null,
  method_version text not null,
  model_version text,
  reviewed_by text,
  reviewed_at timestamptz,
  supersedes_observation_id uuid
    references public.fit_context_claim_observations(context_observation_id)
    on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint fit_context_observations_value_object check (
    jsonb_typeof(observed_value) = 'object'
  ),
  constraint fit_context_observations_method_version check (
    btrim(method_version) <> ''
  ),
  constraint fit_context_observations_model check (
    method <> 'MODEL' or nullif(btrim(model_version), '') is not null
  ),
  constraint fit_context_observations_review check (
    workflow_status not in ('VERIFIED', 'REJECTED', 'RETIRED')
    or (
      nullif(btrim(reviewed_by), '') is not null
      and reviewed_at is not null
    )
  ),
  constraint fit_context_observations_retirement check (
    (workflow_status = 'RETIRED')
    = (retired_at is not null and retirement_reason is not null)
  ),
  unique (context_observation_id, context_claim_id)
);

create table public.fit_context_claim_selection_history (
  context_selection_id uuid primary key default extensions.gen_random_uuid(),
  context_claim_id uuid not null
    references public.fit_context_claims(context_claim_id) on delete restrict,
  context_observation_id uuid
    ,
  observation_workflow_status_at_selection
    public.fit_claim_workflow_status,
  observation_reviewed_at_at_selection timestamptz,
  knowledge_status public.knowledge_status not null,
  selected_at timestamptz not null default now(),
  selected_by text not null,
  supersedes_selection_id uuid
    references public.fit_context_claim_selection_history(context_selection_id)
    on delete restrict,
  unique (context_selection_id, context_claim_id),
  foreign key (context_observation_id, context_claim_id)
    references public.fit_context_claim_observations(
      context_observation_id, context_claim_id
    ) on delete restrict,
  constraint fit_context_selection_history_shape check (
    (
      knowledge_status = 'KNOWN'
      and context_observation_id is not null
      and observation_workflow_status_at_selection = 'VERIFIED'
      and observation_reviewed_at_at_selection is not null
    )
    or (
      knowledge_status <> 'KNOWN'
      and context_observation_id is null
      and observation_workflow_status_at_selection is null
      and observation_reviewed_at_at_selection is null
    )
  ),
  constraint fit_context_selection_history_actor
    check (btrim(selected_by) <> '')
);

create table public.fit_context_claim_selections (
  context_claim_id uuid primary key
    references public.fit_context_claims(context_claim_id) on delete restrict,
  context_selection_id uuid not null unique,
  context_observation_id uuid unique
    ,
  knowledge_status public.knowledge_status not null,
  selected_at timestamptz not null default now(),
  selected_by text not null,
  foreign key (context_selection_id, context_claim_id)
    references public.fit_context_claim_selection_history(
      context_selection_id, context_claim_id
    ) on delete restrict,
  foreign key (context_observation_id, context_claim_id)
    references public.fit_context_claim_observations(
      context_observation_id, context_claim_id
    ) on delete restrict,
  constraint fit_context_selections_shape check (
    (
      knowledge_status = 'KNOWN'
      and context_observation_id is not null
    )
    or (
      knowledge_status in (
        'UNKNOWN',
        'NOT_PUBLICLY_DISCLOSED',
        'NOT_YET_RESEARCHED',
        'NOT_YET_VERIFIED',
        'NOT_APPLICABLE',
        'SOURCE_CONFLICT',
        'STALE'
      )
      and context_observation_id is null
    )
  ),
  constraint fit_context_selections_actor check (btrim(selected_by) <> '')
);

create table public.fit_context_concept_mappings (
  context_mapping_id uuid primary key default extensions.gen_random_uuid(),
  context_claim_id uuid not null
    references public.fit_context_claims(context_claim_id) on delete restrict,
  concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  relation_code text not null
    references public.fit_mapping_relation_definitions(relation_code)
    on delete restrict,
  mapping_status public.mapping_status not null default 'PROPOSED',
  method public.mapping_method not null,
  confidence numeric(5,4),
  model_version text,
  proposed_by text,
  reviewed_by text,
  reviewed_at timestamptz,
  verification_evidence_id uuid
    references public.evidence_items(evidence_id) on delete restrict,
  supersedes_mapping_id uuid
    references public.fit_context_concept_mappings(context_mapping_id)
    on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  constraint fit_context_mappings_confidence check (
    confidence is null or confidence between 0 and 1
  ),
  constraint fit_context_mappings_model check (
    method <> 'MODEL' or nullif(btrim(model_version), '') is not null
  ),
  constraint fit_context_mappings_review check (
    mapping_status not in ('VERIFIED', 'REJECTED')
    or (
      nullif(btrim(reviewed_by), '') is not null
      and reviewed_at is not null
    )
  ),
  constraint fit_context_mappings_verified_evidence check (
    mapping_status <> 'VERIFIED' or verification_evidence_id is not null
  ),
  constraint fit_context_mappings_retirement check (
    (mapping_status = 'RETIRED')
    = (retired_at is not null and retirement_reason is not null)
  )
);

create unique index fit_context_mappings_active_unique
  on public.fit_context_concept_mappings (
    context_claim_id,
    concept_id,
    relation_code
  )
  where mapping_status in ('PROPOSED', 'VERIFIED');
create index fit_context_claims_scope_idx
  on public.fit_context_claims (
    program_version_id,
    jurisdiction_code,
    geography_code,
    valid_from,
    valid_to
  );
create index fit_context_observations_claim_idx
  on public.fit_context_claim_observations (
    context_claim_id,
    workflow_status,
    observed_at desc
  );
create index fit_context_mappings_claim_idx
  on public.fit_context_concept_mappings (
    context_claim_id,
    mapping_status
  );

create trigger fit_context_definitions_set_updated_at
before update on public.fit_context_claim_definitions
for each row execute function public.set_updated_at();

create or replace function public.guard_fit_context_definition()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Fit context definitions are historical and cannot be deleted';
  end if;
  if new.claim_definition_id is distinct from old.claim_definition_id
     or new.owner_layer is distinct from old.owner_layer
     or new.claim_code is distinct from old.claim_code
     or new.semantic_source_class_code is distinct from
       old.semantic_source_class_code
     or new.definition_version is distinct from old.definition_version then
    raise exception 'Fit context definition identity is immutable';
  end if;
  if new.status is distinct from old.status
     and current_setting('app.fit_context_controlled_write', true)
       is distinct from 'on' then
    raise exception 'Use controlled Fit context lifecycle functions';
  end if;
  if old.status in ('VERIFIED', 'RETIRED')
     and current_setting('app.fit_context_controlled_write', true)
       is distinct from 'on'
     and (to_jsonb(new) - 'updated_at') is distinct from
       (to_jsonb(old) - 'updated_at') then
    raise exception 'Verified Fit context definitions are immutable';
  end if;
  if old.status = 'RETIRED' then
    raise exception 'Retired Fit context definitions are immutable';
  end if;
  return new;
end;
$$;

create or replace function public.guard_fit_context_claim()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Fit context claim slots are append-only';
end;
$$;

create or replace function public.review_fit_context_mapping(
  p_context_mapping_id uuid,
  p_mapping_status public.mapping_status,
  p_reviewed_by text,
  p_verification_evidence_id uuid default null,
  p_retirement_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_prior text;
begin
  if p_mapping_status not in ('VERIFIED', 'REJECTED', 'RETIRED') then
    raise exception using errcode='22023',
      message='Mapping review status must be VERIFIED, REJECTED, or RETIRED';
  end if;
  if nullif(btrim(p_reviewed_by), '') is null then
    raise exception using errcode='22023', message='Reviewer identity is required';
  end if;
  if p_mapping_status = 'VERIFIED'
     and not exists (
       select 1 from public.evidence_items
       where evidence_id = p_verification_evidence_id
     ) then
    raise exception using errcode='23503',
      message='Verified mapping requires existing review evidence';
  end if;
  if (p_mapping_status = 'RETIRED') <>
     (nullif(btrim(p_retirement_reason), '') is not null) then
    raise exception using errcode='22023',
      message='Retirement status and reason must be supplied together';
  end if;
  v_prior := current_setting(
    'app.fit_context_mapping_controlled_write', true
  );
  perform set_config(
    'app.fit_context_mapping_controlled_write', 'on', true
  );
  update public.fit_context_concept_mappings
  set mapping_status = p_mapping_status,
      reviewed_by = p_reviewed_by,
      reviewed_at = now(),
      verification_evidence_id = case
        when p_mapping_status = 'VERIFIED'
          then p_verification_evidence_id
        else verification_evidence_id
      end,
      retired_at = case
        when p_mapping_status = 'RETIRED' then now()
      end,
      retirement_reason = p_retirement_reason
  where context_mapping_id = p_context_mapping_id
    and (
      (mapping_status = 'PROPOSED'
        and p_mapping_status in ('VERIFIED', 'REJECTED'))
      or (mapping_status = 'VERIFIED'
        and p_mapping_status = 'RETIRED')
    );
  if not found then
    raise exception using errcode='55000',
      message='Context mapping is not eligible for the requested transition';
  end if;
  perform set_config(
    'app.fit_context_mapping_controlled_write',
    coalesce(v_prior, ''), true
  );
end;
$$;

create or replace function public.validate_fit_context_observation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_required_keys jsonb;
  v_claim_code public.fit_context_claim_code;
begin
  select d.value_contract -> 'requiredKeys', d.claim_code
  into v_required_keys, v_claim_code
  from public.fit_context_claims c
  join public.fit_context_claim_definitions d
    on d.claim_definition_id = c.claim_definition_id
   and d.definition_version = c.definition_version
  where c.context_claim_id = new.context_claim_id
    and (
      d.status = 'VERIFIED'
      or (tg_op = 'UPDATE' and d.status = 'RETIRED')
    );
  if v_required_keys is null then
    raise exception 'Observations require a verified Phase 3 context definition';
  end if;
  if exists (
    select 1
    from jsonb_array_elements_text(v_required_keys)
      as required(required_key)
    where not new.observed_value ? required_key
  ) then
    raise exception 'Observation does not satisfy its definition-version contract';
  end if;
  case v_claim_code
    when 'REGULATORY_WORK_AUTHORIZATION' then
      if new.observed_value - array['allowed','authorizationType','notes'] <> '{}'::jsonb
         or jsonb_typeof(new.observed_value->'allowed') <> 'boolean'
         or (new.observed_value ? 'authorizationType'
           and jsonb_typeof(new.observed_value->'authorizationType') <> 'string')
         or (new.observed_value ? 'notes'
           and jsonb_typeof(new.observed_value->'notes') <> 'string') then
        raise exception using errcode='23514',
          message='Invalid REGULATORY_WORK_AUTHORIZATION value contract';
      end if;
    when 'LICENSING_RESTRICTION' then
      if new.observed_value - array['restricted','licenseType','notes'] <> '{}'::jsonb
         or jsonb_typeof(new.observed_value->'restricted') <> 'boolean'
         or (new.observed_value ? 'licenseType'
           and jsonb_typeof(new.observed_value->'licenseType') <> 'string')
         or (new.observed_value ? 'notes'
           and jsonb_typeof(new.observed_value->'notes') <> 'string') then
        raise exception using errcode='23514',
          message='Invalid LICENSING_RESTRICTION value contract';
      end if;
    when 'CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION' then
      if new.observed_value -
           array['restricted','citizenships','clearanceType','notes'] <> '{}'::jsonb
         or jsonb_typeof(new.observed_value->'restricted') <> 'boolean'
         or (new.observed_value ? 'citizenships'
           and jsonb_typeof(new.observed_value->'citizenships') <> 'array')
         or (new.observed_value ? 'clearanceType'
           and jsonb_typeof(new.observed_value->'clearanceType') <> 'string')
         or (new.observed_value ? 'notes'
           and jsonb_typeof(new.observed_value->'notes') <> 'string') then
        raise exception using errcode='23514',
          message='Invalid CITIZENSHIP_SECURITY_CLEARANCE_RESTRICTION value contract';
      end if;
    when 'REVIEWED_CAREER_OUTCOME' then
      if new.observed_value - array[
           'outcome','populationDenominator','cohortPeriod','geography',
           'reportingCoverage','outcomeDefinition','sampleSource',
           'applicabilityScope'
         ] <> '{}'::jsonb
         or not new.observed_value ?& array[
           'outcome','populationDenominator','cohortPeriod','geography',
           'reportingCoverage','outcomeDefinition','sampleSource',
           'applicabilityScope'
         ]
         or jsonb_typeof(new.observed_value->'outcome') <> 'string'
         or jsonb_typeof(new.observed_value->'populationDenominator') <> 'number'
         or (new.observed_value->>'populationDenominator')::numeric <= 0
         or jsonb_typeof(new.observed_value->'cohortPeriod') <> 'string'
         or jsonb_typeof(new.observed_value->'geography') <> 'string'
         or jsonb_typeof(new.observed_value->'reportingCoverage') <> 'number'
         or (new.observed_value->>'reportingCoverage')::numeric not between 0 and 1
         or jsonb_typeof(new.observed_value->'outcomeDefinition') <> 'string'
         or jsonb_typeof(new.observed_value->'sampleSource') <> 'string'
         or jsonb_typeof(new.observed_value->'applicabilityScope') <> 'object' then
        raise exception using errcode='23514',
          message='Invalid REVIEWED_CAREER_OUTCOME value contract';
      end if;
    when 'JURISDICTION_PATH_ACCESSIBILITY' then
      if new.observed_value - array['accessible','restrictionCode','notes'] <> '{}'::jsonb
         or jsonb_typeof(new.observed_value->'accessible') <> 'boolean'
         or (new.observed_value ? 'restrictionCode'
           and jsonb_typeof(new.observed_value->'restrictionCode') <> 'string')
         or (new.observed_value ? 'notes'
           and jsonb_typeof(new.observed_value->'notes') <> 'string') then
        raise exception using errcode='23514',
          message='Invalid JURISDICTION_PATH_ACCESSIBILITY value contract';
      end if;
  end case;
  if new.supersedes_observation_id is not null
     and not exists (
       select 1 from public.fit_context_claim_observations prior
       where prior.context_observation_id = new.supersedes_observation_id
         and prior.context_claim_id = new.context_claim_id
     ) then
    raise exception 'Superseded observation must belong to the same claim';
  end if;
  return new;
end;
$$;

create or replace function public.guard_fit_context_observation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Fit context observations are historical and cannot be deleted';
  end if;
  if old.workflow_status in ('VERIFIED', 'REJECTED', 'RETIRED')
     and current_setting('app.fit_context_controlled_write', true)
       is distinct from 'on' then
    raise exception 'Reviewed Fit context observations are immutable';
  end if;
  if new.workflow_status is distinct from old.workflow_status
     and current_setting('app.fit_context_controlled_write', true)
       is distinct from 'on' then
    raise exception 'Use review_fit_context_observation()';
  end if;
  if old.workflow_status = 'RETIRED' then
    raise exception 'Retired Fit context observations are immutable';
  end if;
  return new;
end;
$$;

create or replace function public.guard_fit_context_mapping()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Fit context mappings are historical and cannot be deleted';
  end if;
  if new.mapping_status is distinct from old.mapping_status
     and current_setting('app.fit_context_mapping_controlled_write', true)
       is distinct from 'on' then
    raise exception using errcode='55000',
      message='Use review_fit_context_mapping()';
  end if;
  if old.mapping_status in ('REJECTED', 'RETIRED') then
    raise exception 'Rejected and retired Fit context mappings are immutable';
  end if;
  if old.mapping_status = 'VERIFIED'
     and new.mapping_status <> 'RETIRED' then
    raise exception 'Verified Fit context mappings may only be retired';
  end if;
  if old.mapping_status = 'VERIFIED'
     and new.mapping_status = 'RETIRED'
     and (
       new.context_mapping_id is distinct from old.context_mapping_id
       or new.context_claim_id is distinct from old.context_claim_id
       or new.concept_id is distinct from old.concept_id
       or new.relation_code is distinct from old.relation_code
       or new.method is distinct from old.method
       or new.confidence is distinct from old.confidence
       or new.model_version is distinct from old.model_version
       or new.proposed_by is distinct from old.proposed_by
       or new.reviewed_by is distinct from old.reviewed_by
       or new.reviewed_at is distinct from old.reviewed_at
       or new.verification_evidence_id is distinct from
         old.verification_evidence_id
       or new.supersedes_mapping_id is distinct from
         old.supersedes_mapping_id
       or new.created_at is distinct from old.created_at
     ) then
    raise exception 'Retiring a verified Fit context mapping may only change status and retirement fields';
  end if;
  return new;
end;
$$;

create or replace function public.validate_fit_context_mapping()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT'
     and new.mapping_status <> 'PROPOSED'
     and current_setting('app.fit_context_mapping_controlled_write', true)
       is distinct from 'on' then
    raise exception using errcode='55000',
      message='Context mappings must enter as PROPOSED';
  end if;
  if not exists (
    select 1 from public.fit_mapping_relation_definitions relation
    where relation.relation_code = new.relation_code
      and relation.relation_domain = 'FIT_CONTEXT'
  ) then
    raise exception 'Fit context mapping requires a FIT_CONTEXT relation';
  end if;
  if new.mapping_status = 'VERIFIED'
     and not exists (
       select 1
       from public.fit_context_claim_selections s
       join public.fit_context_claim_observations o
         on o.context_observation_id = s.context_observation_id
        and o.context_claim_id = s.context_claim_id
       where s.context_claim_id = new.context_claim_id
         and s.knowledge_status = 'KNOWN'
         and o.workflow_status = 'VERIFIED'
     ) then
    raise exception 'Verified context mappings require a selected verified claim fact';
  end if;
  return new;
end;
$$;

create or replace function public.guard_fit_context_selection()
returns trigger
language plpgsql
as $$
begin
  if current_setting('app.fit_context_selection_write', true)
       is distinct from 'on' then
    raise exception 'Use select_fit_context_claim_observation()';
  end if;
  return coalesce(new, old);
end;
$$;

create or replace function public.guard_fit_context_selection_history()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT'
     and current_setting('app.fit_context_selection_write', true) = 'on' then
    return new;
  end if;
  raise exception 'Fit context selection history is append-only';
end;
$$;

create trigger fit_context_definitions_guard
before update or delete on public.fit_context_claim_definitions
for each row execute function public.guard_fit_context_definition();
create trigger fit_context_claims_immutable
before update or delete on public.fit_context_claims
for each row execute function public.guard_fit_context_claim();
create trigger fit_context_observations_validate
before insert or update on public.fit_context_claim_observations
for each row execute function public.validate_fit_context_observation();
create trigger fit_context_observations_guard
before update or delete on public.fit_context_claim_observations
for each row execute function public.guard_fit_context_observation();
create trigger fit_context_mappings_validate
before insert or update on public.fit_context_concept_mappings
for each row execute function public.validate_fit_context_mapping();
create trigger fit_context_mappings_guard
before update or delete on public.fit_context_concept_mappings
for each row execute function public.guard_fit_context_mapping();
create trigger fit_context_selections_guard
before insert or update or delete on public.fit_context_claim_selections
for each row execute function public.guard_fit_context_selection();
create trigger fit_context_selection_history_guard
before insert or update or delete on public.fit_context_claim_selection_history
for each row execute function public.guard_fit_context_selection_history();

create or replace function public.verify_fit_context_definition(
  p_claim_definition_id uuid,
  p_reviewed_by text,
  p_verification_evidence_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_prior text;
begin
  if nullif(btrim(p_reviewed_by), '') is null then
    raise exception 'Reviewer identity is required';
  end if;
  if not exists (
    select 1 from public.evidence_items
    where evidence_id = p_verification_evidence_id
  ) then
    raise exception 'Verification evidence does not exist';
  end if;
  if not exists (
    select 1
    from public.fit_context_claim_definitions d
    join public.fit_semantic_source_classes source_class
      on source_class.source_class_code = d.semantic_source_class_code
    where d.claim_definition_id = p_claim_definition_id
      and d.owner_layer = 'PHASE3_CONTEXT'
      and source_class.fit_permitted
      and source_class.owner_layer = 'PHASE3'
      and d.semantic_source_class_code in (
        'FIT_CONTEXT_REGULATORY',
        'FIT_CONTEXT_CAREER',
        'FIT_CONTEXT_FINANCIAL',
        'FIT_CONTEXT_ACCESSIBILITY'
      )
  ) then
    raise exception 'Context definitions cannot duplicate upstream-owned or prohibited semantic facts';
  end if;
  v_prior := current_setting('app.fit_context_controlled_write', true);
  perform set_config('app.fit_context_controlled_write', 'on', true);
  update public.fit_context_claim_definitions
  set status = 'VERIFIED',
      reviewed_by = p_reviewed_by,
      reviewed_at = now(),
      verification_evidence_id = p_verification_evidence_id
  where claim_definition_id = p_claim_definition_id
    and status = 'DRAFT';
  if not found then
    raise exception 'A draft Fit context definition is required';
  end if;
  perform set_config('app.fit_context_controlled_write', coalesce(v_prior, ''), true);
end;
$$;

create or replace function public.retire_fit_context_definition(
  p_claim_definition_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_prior text;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Retirement reason is required';
  end if;
  v_prior := current_setting('app.fit_context_controlled_write', true);
  perform set_config('app.fit_context_controlled_write', 'on', true);
  update public.fit_context_claim_definitions
  set status = 'RETIRED', retired_at = now(), retirement_reason = p_reason
  where claim_definition_id = p_claim_definition_id
    and status = 'VERIFIED';
  if not found then
    raise exception 'A verified Fit context definition is required';
  end if;
  perform set_config('app.fit_context_controlled_write', coalesce(v_prior, ''), true);
end;
$$;

create or replace function public.review_fit_context_observation(
  p_context_observation_id uuid,
  p_workflow_status public.fit_claim_workflow_status,
  p_reviewed_by text,
  p_retirement_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_prior text;
begin
  if p_workflow_status not in ('VERIFIED', 'REJECTED', 'RETIRED') then
    raise exception 'Review status must be VERIFIED, REJECTED, or RETIRED';
  end if;
  if nullif(btrim(p_reviewed_by), '') is null then
    raise exception 'Reviewer identity is required';
  end if;
  if (p_workflow_status = 'RETIRED')
     <> (nullif(btrim(p_retirement_reason), '') is not null) then
    raise exception 'Retirement status and reason must be supplied together';
  end if;
  v_prior := current_setting('app.fit_context_controlled_write', true);
  perform set_config('app.fit_context_controlled_write', 'on', true);
  update public.fit_context_claim_observations
  set workflow_status = p_workflow_status,
      reviewed_by = p_reviewed_by,
      reviewed_at = now(),
      retired_at = case when p_workflow_status = 'RETIRED' then now() end,
      retirement_reason = p_retirement_reason
  where context_observation_id = p_context_observation_id
    and (
      workflow_status = 'PROPOSED'
      or (workflow_status = 'VERIFIED' and p_workflow_status = 'RETIRED')
    );
  if not found then
    raise exception 'Observation is not eligible for the requested review transition';
  end if;
  perform set_config('app.fit_context_controlled_write', coalesce(v_prior, ''), true);
end;
$$;

create or replace function public.select_fit_context_claim_observation(
  p_context_claim_id uuid,
  p_context_observation_id uuid,
  p_knowledge_status public.knowledge_status,
  p_selected_by text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_prior text;
  v_selection_id uuid;
  v_prior_selection_id uuid;
begin
  if nullif(btrim(p_selected_by), '') is null then
    raise exception 'Selector identity is required';
  end if;
  if not exists (
    select 1
    from public.fit_context_claims claim
    join public.fit_context_claim_definitions definition
      on definition.claim_definition_id = claim.claim_definition_id
     and definition.definition_version = claim.definition_version
    where claim.context_claim_id = p_context_claim_id
      and definition.status = 'VERIFIED'
      and definition.retired_at is null
  ) then
    raise exception using errcode='55000',
      message='Context selection requires an active VERIFIED definition';
  end if;
  if p_context_observation_id is not null then
    if p_knowledge_status <> 'KNOWN'
       or not exists (
         select 1
         from public.fit_context_claim_observations
         where context_observation_id = p_context_observation_id
           and context_claim_id = p_context_claim_id
           and workflow_status = 'VERIFIED'
       ) then
      raise exception 'Canonical facts require a VERIFIED observation for this claim';
    end if;
  elsif p_knowledge_status not in (
    'UNKNOWN',
    'NOT_PUBLICLY_DISCLOSED',
    'NOT_YET_RESEARCHED',
    'NOT_YET_VERIFIED',
    'NOT_APPLICABLE',
    'SOURCE_CONFLICT',
    'STALE'
  ) then
    raise exception 'An explicit unresolved knowledge status is required';
  end if;
  v_prior := current_setting('app.fit_context_selection_write', true);
  perform set_config('app.fit_context_selection_write', 'on', true);
  select context_selection_id into v_prior_selection_id
  from public.fit_context_claim_selections
  where context_claim_id = p_context_claim_id;
  insert into public.fit_context_claim_selection_history (
    context_claim_id, context_observation_id, knowledge_status,
    observation_workflow_status_at_selection,
    observation_reviewed_at_at_selection,
    selected_at, selected_by, supersedes_selection_id
  )
  select
    p_context_claim_id, p_context_observation_id, p_knowledge_status,
    case when p_context_observation_id is not null
      then observation.workflow_status end,
    case when p_context_observation_id is not null
      then observation.reviewed_at end,
    now(), p_selected_by, v_prior_selection_id
  from (select 1) seed
  left join public.fit_context_claim_observations observation
    on observation.context_observation_id = p_context_observation_id
   and observation.context_claim_id = p_context_claim_id
  returning context_selection_id into v_selection_id;
  insert into public.fit_context_claim_selections (
    context_claim_id,
    context_selection_id,
    context_observation_id,
    knowledge_status,
    selected_at,
    selected_by
  ) values (
    p_context_claim_id,
    v_selection_id,
    p_context_observation_id,
    p_knowledge_status,
    now(),
    p_selected_by
  )
  on conflict (context_claim_id) do update set
    context_selection_id = excluded.context_selection_id,
    context_observation_id = excluded.context_observation_id,
    knowledge_status = excluded.knowledge_status,
    selected_at = excluded.selected_at,
    selected_by = excluded.selected_by;
  perform set_config('app.fit_context_selection_write', coalesce(v_prior, ''), true);
end;
$$;

revoke all on function public.freeze_fit_intent_set(uuid) from public;
revoke all on function public.verify_fit_context_definition(uuid, text, uuid) from public;
revoke all on function public.retire_fit_context_definition(uuid, text) from public;
revoke all on function public.review_fit_context_observation(
  uuid,
  public.fit_claim_workflow_status,
  text,
  text
) from public;
revoke all on function public.select_fit_context_claim_observation(
  uuid,
  uuid,
  public.knowledge_status,
  text
) from public;
revoke all on function public.review_fit_context_mapping(
  uuid, public.mapping_status, text, uuid, text
) from public;
grant execute on function public.freeze_fit_intent_set(uuid) to service_role;
grant execute on function public.verify_fit_context_definition(uuid, text, uuid)
  to service_role;
grant execute on function public.retire_fit_context_definition(uuid, text)
  to service_role;
grant execute on function public.review_fit_context_observation(
  uuid,
  public.fit_claim_workflow_status,
  text,
  text
) to service_role;
grant execute on function public.select_fit_context_claim_observation(
  uuid,
  uuid,
  public.knowledge_status,
  text
) to service_role;
grant execute on function public.review_fit_context_mapping(
  uuid, public.mapping_status, text, uuid, text
) to service_role;

-- Only registry/history data is globally audited; private student intent is not.
create trigger fit_context_definitions_audit
after insert or update or delete on public.fit_context_claim_definitions
for each row execute function public.audit_phase2_change('claim_definition_id');
create trigger fit_context_claims_audit
after insert or update or delete on public.fit_context_claims
for each row execute function public.audit_phase2_change('context_claim_id');
create trigger fit_context_observations_audit
after insert or update or delete on public.fit_context_claim_observations
for each row execute function public.audit_phase2_change('context_observation_id');
create trigger fit_context_selections_audit
after insert or update or delete on public.fit_context_claim_selections
for each row execute function public.audit_phase2_change('context_claim_id');
create trigger fit_context_mappings_audit
after insert or update or delete on public.fit_context_concept_mappings
for each row execute function public.audit_phase2_change('context_mapping_id');

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fit_intent_sets',
    'fit_intent_declarations',
    'fit_intent_validation_issues',
    'fit_intent_taxonomy_targets',
    'fit_intent_location_constraints',
    'fit_intent_delivery_constraints',
    'fit_intent_financial_constraints',
    'fit_intent_duration_constraints',
    'fit_intent_program_feature_constraints',
    'fit_context_claim_definitions',
    'fit_context_claims',
    'fit_context_claim_observations',
    'fit_context_claim_selection_history',
    'fit_context_claim_selections',
    'fit_context_concept_mappings'
  ]
  loop
    execute format('alter table public.%I enable row level security', v_table);
  end loop;
end;
$$;
alter table private.fit_student_access_contexts enable row level security;

create policy fit_intent_sets_owner_read on public.fit_intent_sets
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy fit_intent_declarations_owner_read
  on public.fit_intent_declarations for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy fit_intent_validation_issues_owner_read
  on public.fit_intent_validation_issues for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fit_intent_taxonomy_targets',
    'fit_intent_location_constraints',
    'fit_intent_delivery_constraints',
    'fit_intent_financial_constraints',
    'fit_intent_duration_constraints',
    'fit_intent_program_feature_constraints'
  ]
  loop
    execute format(
      'create policy %I on public.%I for select to authenticated using (public.current_user_owns_profile(profile_version_id))',
      v_table || '_owner_read',
      v_table
    );
  end loop;
end;
$$;

create policy fit_student_access_context_owner_read
  on private.fit_student_access_contexts for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
grant usage on schema private to authenticated;
grant select on private.fit_student_access_contexts to authenticated;
grant select, insert, update, delete
  on private.fit_student_access_contexts to service_role;

create policy fit_context_definitions_public_read
  on public.fit_context_claim_definitions for select to public
  using (status = 'VERIFIED' and retired_at is null);
create policy fit_context_claims_public_read
  on public.fit_context_claims for select to public
  using (
    exists (
      select 1
      from public.fit_context_claim_definitions d
      join public.fit_context_claim_selections s
        on s.context_claim_id = fit_context_claims.context_claim_id
      where d.claim_definition_id = fit_context_claims.claim_definition_id
        and d.definition_version = fit_context_claims.definition_version
        and d.status = 'VERIFIED'
        and d.retired_at is null
    )
  );
create policy fit_context_observations_public_read
  on public.fit_context_claim_observations for select to public
  using (
    workflow_status = 'VERIFIED'
    and exists (
      select 1 from public.fit_context_claim_selections s
      where s.context_claim_id =
        fit_context_claim_observations.context_claim_id
        and s.context_observation_id =
          fit_context_claim_observations.context_observation_id
        and s.knowledge_status = 'KNOWN'
    )
  );
create policy fit_context_selection_history_public_read
  on public.fit_context_claim_selection_history for select to public
  using (
    exists (
      select 1 from public.fit_context_claim_definitions d
      join public.fit_context_claims c
        on c.claim_definition_id = d.claim_definition_id
       and c.definition_version = d.definition_version
      where c.context_claim_id =
        fit_context_claim_selection_history.context_claim_id
        and d.status = 'VERIFIED'
        and d.retired_at is null
    )
  );
create policy fit_context_selections_public_read
  on public.fit_context_claim_selections for select to public
  using (
    exists (
      select 1
      from public.fit_context_claims claim
      join public.fit_context_claim_definitions definition
        on definition.claim_definition_id = claim.claim_definition_id
       and definition.definition_version = claim.definition_version
      where claim.context_claim_id =
        fit_context_claim_selections.context_claim_id
        and definition.status = 'VERIFIED'
        and definition.retired_at is null
    )
    and (
      knowledge_status <> 'KNOWN'
      or exists (
      select 1 from public.fit_context_claim_observations o
      where o.context_observation_id =
        fit_context_claim_selections.context_observation_id
        and o.context_claim_id =
          fit_context_claim_selections.context_claim_id
        and o.workflow_status = 'VERIFIED'
      )
    )
  );
create policy fit_context_mappings_public_read
  on public.fit_context_concept_mappings for select to public
  using (
    mapping_status = 'VERIFIED'
    and retired_at is null
    and exists (
      select 1
      from public.fit_context_claim_selections s
      join public.fit_context_claim_observations o
        on o.context_observation_id = s.context_observation_id
       and o.context_claim_id = s.context_claim_id
      join public.fit_context_claims claim
        on claim.context_claim_id = s.context_claim_id
      join public.fit_context_claim_definitions definition
        on definition.claim_definition_id = claim.claim_definition_id
       and definition.definition_version = claim.definition_version
      where s.context_claim_id =
        fit_context_concept_mappings.context_claim_id
        and s.knowledge_status = 'KNOWN'
        and o.workflow_status = 'VERIFIED'
        and definition.status = 'VERIFIED'
        and definition.retired_at is null
    )
  );

commit;
