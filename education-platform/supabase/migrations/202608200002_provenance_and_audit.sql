begin;

create type public.knowledge_status as enum (
  'KNOWN',
  'UNKNOWN',
  'NOT_PUBLICLY_DISCLOSED',
  'NOT_YET_RESEARCHED',
  'NOT_YET_VERIFIED',
  'NOT_APPLICABLE',
  'SOURCE_CONFLICT',
  'STALE'
);

create type public.reliability_tier as enum (
  'TIER_A_OFFICIAL',
  'TIER_B_GOVERNMENT',
  'TIER_C_REPUTABLE_SECONDARY',
  'TIER_D_UNVERIFIED'
);

create type public.catalog_record_type as enum (
  'UNIVERSITY',
  'SCHOOL',
  'PROGRAM',
  'PROGRAM_SCHOOL',
  'PROGRAM_VERSION',
  'PROGRAM_ADMISSION',
  'PROGRAM_PREREQUISITE',
  'PROGRAM_COURSE',
  'PROGRAM_COST',
  'PROGRAM_DEADLINE'
);

create type public.metric_granularity as enum (
  'PROGRAM',
  'SCHOOL',
  'INSTITUTION',
  'CIP_FIELD',
  'CREDENTIAL_FIELD',
  'NATIONAL_OCCUPATION'
);

create type public.metric_applicability as enum (
  'DIRECT',
  'CONTEXT_ONLY',
  'NOT_APPLICABLE',
  'UNKNOWN'
);

create type public.population_scope as enum (
  'UNDERGRADUATE',
  'GRADUATE',
  'ALL_STUDENTS',
  'PROGRAM_COHORT',
  'UNKNOWN'
);

create table public.sources (
  source_id uuid primary key default extensions.gen_random_uuid(),
  publisher text not null,
  title text not null,
  url text not null,
  reliability_tier public.reliability_tier not null,
  source_type text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sources_publisher_not_blank check (btrim(publisher) <> ''),
  constraint sources_title_not_blank check (btrim(title) <> ''),
  constraint sources_url_not_blank check (btrim(url) <> ''),
  unique (url)
);

create table public.evidence_items (
  evidence_id uuid primary key default extensions.gen_random_uuid(),
  source_id uuid not null references public.sources(source_id) on delete restrict,
  excerpt text not null,
  locator text,
  cycle_context text,
  published_at date,
  retrieved_at timestamptz not null,
  verified_at timestamptz not null,
  content_hash text,
  created_at timestamptz not null default now(),
  constraint evidence_excerpt_not_blank check (btrim(excerpt) <> ''),
  constraint evidence_verified_after_retrieved check (verified_at >= retrieved_at),
  unique (source_id, excerpt, cycle_context)
);

create table public.field_observations (
  observation_id uuid primary key default extensions.gen_random_uuid(),
  record_type public.catalog_record_type not null,
  record_id uuid not null,
  field_name text not null,
  observed_value jsonb,
  knowledge_status public.knowledge_status not null,
  evidence_id uuid references public.evidence_items(evidence_id) on delete restrict,
  supersedes_observation_id uuid references public.field_observations(observation_id) on delete restrict,
  notes text,
  observed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  constraint field_observations_field_not_blank check (btrim(field_name) <> ''),
  constraint field_observations_known_has_value_and_evidence check (
    knowledge_status <> 'KNOWN'
    or (observed_value is not null and evidence_id is not null)
  ),
  constraint field_observations_unknown_not_accepted_as_value check (
    knowledge_status = 'KNOWN' or observed_value is null or knowledge_status in ('STALE', 'SOURCE_CONFLICT')
  )
);

create table public.canonical_field_selections (
  record_type public.catalog_record_type not null,
  record_id uuid not null,
  field_name text not null,
  observation_id uuid not null unique references public.field_observations(observation_id) on delete restrict,
  selected_at timestamptz not null default now(),
  selected_by text,
  primary key (record_type, record_id, field_name)
);

create table public.program_derived_features (
  derived_feature_id uuid primary key default extensions.gen_random_uuid(),
  program_version_id uuid not null references public.program_versions(program_version_id) on delete restrict,
  feature_name text not null,
  numeric_value numeric,
  text_value text,
  model_version text not null,
  calculated_at timestamptz not null,
  input_snapshot jsonb,
  created_at timestamptz not null default now(),
  constraint derived_features_name_not_blank check (btrim(feature_name) <> ''),
  constraint derived_features_model_not_blank check (btrim(model_version) <> ''),
  constraint derived_features_exactly_one_value check (
    (numeric_value is not null)::int + (text_value is not null)::int = 1
  ),
  unique (program_version_id, feature_name, model_version, calculated_at)
);

create table public.external_metrics (
  external_metric_id uuid primary key default extensions.gen_random_uuid(),
  subject_record_type public.catalog_record_type,
  subject_record_id uuid,
  metric_name text not null,
  numeric_value numeric,
  text_value text,
  granularity public.metric_granularity not null,
  applicability public.metric_applicability not null,
  population_scope public.population_scope not null,
  credential_level text,
  applicability_rationale text not null,
  evidence_id uuid not null references public.evidence_items(evidence_id) on delete restrict,
  measurement_period text,
  created_at timestamptz not null default now(),
  constraint external_metrics_name_not_blank check (btrim(metric_name) <> ''),
  constraint external_metrics_subject_pair check (
    (subject_record_type is null) = (subject_record_id is null)
  ),
  constraint external_metrics_exactly_one_value check (
    (numeric_value is not null)::int + (text_value is not null)::int = 1
  ),
  constraint external_metrics_rationale_not_blank check (btrim(applicability_rationale) <> ''),
  constraint external_metrics_direct_scope_alignment check (
    applicability <> 'DIRECT'
    or (
      subject_record_type = 'UNIVERSITY'
      and granularity = 'INSTITUTION'
      and population_scope <> 'PROGRAM_COHORT'
    )
    or (
      subject_record_type = 'SCHOOL'
      and granularity = 'SCHOOL'
      and population_scope <> 'PROGRAM_COHORT'
    )
    or (
      subject_record_type in (
        'PROGRAM',
        'PROGRAM_VERSION',
        'PROGRAM_ADMISSION',
        'PROGRAM_PREREQUISITE',
        'PROGRAM_COURSE',
        'PROGRAM_COST',
        'PROGRAM_DEADLINE'
      )
      and granularity = 'PROGRAM'
      and population_scope = 'PROGRAM_COHORT'
    )
  )
);

create table public.audit_events (
  audit_event_id bigint generated always as identity primary key,
  table_name text not null,
  record_id uuid,
  operation text not null,
  old_row jsonb,
  new_row jsonb,
  changed_at timestamptz not null default now(),
  actor text,
  transaction_id bigint not null default txid_current(),
  constraint audit_events_operation check (operation in ('INSERT', 'UPDATE', 'DELETE'))
);

create index field_observations_record_field_idx
  on public.field_observations (record_type, record_id, field_name, observed_at desc);
create index field_observations_evidence_idx
  on public.field_observations (evidence_id);
create index external_metrics_subject_idx
  on public.external_metrics (subject_record_type, subject_record_id);
create index external_metrics_scope_idx
  on public.external_metrics (granularity, applicability, population_scope);
create index audit_events_record_idx
  on public.audit_events (table_name, record_id, changed_at desc);

create trigger sources_set_updated_at
before update on public.sources
for each row execute function public.set_updated_at();

create or replace function public.catalog_table_name(p_record_type public.catalog_record_type)
returns text
language sql
immutable
strict
as $$
  select case p_record_type
    when 'UNIVERSITY' then 'universities'
    when 'SCHOOL' then 'schools'
    when 'PROGRAM' then 'programs'
    when 'PROGRAM_SCHOOL' then 'program_schools'
    when 'PROGRAM_VERSION' then 'program_versions'
    when 'PROGRAM_ADMISSION' then 'program_admissions'
    when 'PROGRAM_PREREQUISITE' then 'program_prerequisites'
    when 'PROGRAM_COURSE' then 'program_courses'
    when 'PROGRAM_COST' then 'program_costs'
    when 'PROGRAM_DEADLINE' then 'program_deadlines'
  end;
$$;

create or replace function public.catalog_primary_key(p_record_type public.catalog_record_type)
returns text
language sql
immutable
strict
as $$
  select case p_record_type
    when 'UNIVERSITY' then 'university_id'
    when 'SCHOOL' then 'school_id'
    when 'PROGRAM' then 'program_id'
    when 'PROGRAM_SCHOOL' then 'program_school_id'
    when 'PROGRAM_VERSION' then 'program_version_id'
    when 'PROGRAM_ADMISSION' then 'admission_id'
    when 'PROGRAM_PREREQUISITE' then 'prerequisite_id'
    when 'PROGRAM_COURSE' then 'course_id'
    when 'PROGRAM_COST' then 'cost_id'
    when 'PROGRAM_DEADLINE' then 'deadline_id'
  end;
$$;

create or replace function public.validate_catalog_record_reference()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  table_name text;
  primary_key text;
  record_exists boolean;
begin
  table_name := public.catalog_table_name(new.record_type);
  primary_key := public.catalog_primary_key(new.record_type);
  execute format(
    'select exists(select 1 from public.%I where %I = $1)',
    table_name,
    primary_key
  ) into record_exists using new.record_id;

  if not record_exists then
    raise exception 'Referenced % record % does not exist', new.record_type, new.record_id;
  end if;
  return new;
end;
$$;

create trigger field_observations_validate_record
before insert on public.field_observations
for each row execute function public.validate_catalog_record_reference();

create or replace function public.validate_external_metric_subject()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_table_name text;
  v_primary_key text;
  record_exists boolean;
begin
  if new.subject_record_type is null then
    return new;
  end if;

  v_table_name := public.catalog_table_name(new.subject_record_type);
  v_primary_key := public.catalog_primary_key(new.subject_record_type);
  execute format(
    'select exists(select 1 from public.%I where %I = $1)',
    v_table_name,
    v_primary_key
  ) into record_exists using new.subject_record_id;

  if not record_exists then
    raise exception 'External metric subject % record % does not exist',
      new.subject_record_type,
      new.subject_record_id;
  end if;
  return new;
end;
$$;

create trigger external_metrics_validate_subject
before insert or update of subject_record_type, subject_record_id on public.external_metrics
for each row execute function public.validate_external_metric_subject();

create or replace function public.prevent_immutable_change()
returns trigger
language plpgsql
as $$
begin
  raise exception '% is append-only', tg_table_name;
end;
$$;

create trigger field_observations_immutable
before update or delete on public.field_observations
for each row execute function public.prevent_immutable_change();

create trigger evidence_items_immutable
before update or delete on public.evidence_items
for each row execute function public.prevent_immutable_change();

create trigger audit_events_immutable
before update or delete on public.audit_events
for each row execute function public.prevent_immutable_change();

create or replace function public.guard_canonical_selection_write()
returns trigger
language plpgsql
as $$
begin
  if current_setting('app.controlled_catalog_write', true) is distinct from 'on' then
    raise exception 'Canonical selections may only be changed through select_field_observation()';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger canonical_field_selections_guard
before insert or update or delete on public.canonical_field_selections
for each row execute function public.guard_canonical_selection_write();

create or replace function public.guard_direct_canonical_write()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception '% records are historical and cannot be physically deleted; retire the record instead',
      tg_table_name;
  end if;

  if current_setting('app.controlled_catalog_write', true) is distinct from 'on'
     and (to_jsonb(new) - 'updated_at') is distinct from (to_jsonb(old) - 'updated_at') then
    raise exception 'Canonical fields may only be changed through select_field_observation() or retire_catalog_record()';
  end if;
  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'universities',
    'schools',
    'programs',
    'program_schools',
    'program_versions',
    'program_admissions',
    'program_prerequisites',
    'program_courses',
    'program_costs',
    'program_deadlines'
  ]
  loop
    execute format(
      'create trigger %I before update or delete on public.%I
       for each row execute function public.guard_direct_canonical_write()',
      table_name || '_canonical_write_guard',
      table_name
    );
  end loop;
end;
$$;

create or replace function public.assert_canonical_insert_has_evidence()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_record_type public.catalog_record_type;
  v_primary_key text;
  v_record_id uuid;
  v_row jsonb;
  v_field record;
begin
  v_record_type := case tg_table_name
    when 'universities' then 'UNIVERSITY'::public.catalog_record_type
    when 'schools' then 'SCHOOL'::public.catalog_record_type
    when 'programs' then 'PROGRAM'::public.catalog_record_type
    when 'program_schools' then 'PROGRAM_SCHOOL'::public.catalog_record_type
    when 'program_versions' then 'PROGRAM_VERSION'::public.catalog_record_type
    when 'program_admissions' then 'PROGRAM_ADMISSION'::public.catalog_record_type
    when 'program_prerequisites' then 'PROGRAM_PREREQUISITE'::public.catalog_record_type
    when 'program_courses' then 'PROGRAM_COURSE'::public.catalog_record_type
    when 'program_costs' then 'PROGRAM_COST'::public.catalog_record_type
    when 'program_deadlines' then 'PROGRAM_DEADLINE'::public.catalog_record_type
  end;
  v_primary_key := public.catalog_primary_key(v_record_type);
  v_record_id := (to_jsonb(new) ->> v_primary_key)::uuid;

  execute format(
    'select to_jsonb(record) from public.%I record where %I = $1',
    tg_table_name,
    v_primary_key
  ) into v_row using v_record_id;

  for v_field in
    select key, value
    from jsonb_each(v_row)
    where value <> 'null'::jsonb
      and key <> v_primary_key
      and key not in (
        'created_at',
        'updated_at',
        'retired_at',
        'retirement_reason',
        'verification_status',
        'notes',
        'cost_notes',
        'admission_cycle',
        'academic_year'
      )
  loop
    if not exists (
      select 1
      from public.canonical_field_selections selection
      where selection.record_type = v_record_type
        and selection.record_id = v_record_id
        and selection.field_name = v_field.key
    ) then
      raise exception 'Canonical insert %.% lacks an accepted evidence observation',
        tg_table_name,
        v_field.key;
    end if;
  end loop;

  return null;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'universities',
    'schools',
    'programs',
    'program_schools',
    'program_versions',
    'program_admissions',
    'program_prerequisites',
    'program_courses',
    'program_costs',
    'program_deadlines'
  ]
  loop
    execute format(
      'create constraint trigger %I after insert on public.%I
       deferrable initially deferred
       for each row execute function public.assert_canonical_insert_has_evidence()',
      table_name || '_insert_evidence_guard',
      table_name
    );
  end loop;
end;
$$;

create or replace function public.select_field_observation(
  p_observation_id uuid,
  p_selected_by text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  observation public.field_observations%rowtype;
  v_table_name text;
  v_primary_key text;
  column_exists boolean;
begin
  select * into observation
    from public.field_observations
    where observation_id = p_observation_id;

  if not found then
    raise exception 'Observation % does not exist', p_observation_id;
  end if;

  v_table_name := public.catalog_table_name(observation.record_type);
  v_primary_key := public.catalog_primary_key(observation.record_type);

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and information_schema.columns.table_name = v_table_name
      and column_name = observation.field_name
  ) into column_exists;

  if not column_exists or observation.field_name in (
    v_primary_key, 'created_at', 'updated_at'
  ) then
    raise exception 'Field %.% is not eligible for canonical acceptance', v_table_name, observation.field_name;
  end if;

  perform set_config('app.controlled_catalog_write', 'on', true);

  execute format(
    'update public.%I
       set %I = case
         when $1 = ''KNOWN''::public.knowledge_status then (
           select %I
           from jsonb_populate_record(
             null::public.%I,
             jsonb_build_object(%L, $2)
           )
         )
         else null
       end
     where %I = $3',
    v_table_name,
    observation.field_name,
    observation.field_name,
    v_table_name,
    observation.field_name,
    v_primary_key
  ) using observation.knowledge_status, observation.observed_value, observation.record_id;

  if not found then
    raise exception 'Canonical record % % no longer exists',
      observation.record_type,
      observation.record_id;
  end if;

  insert into public.canonical_field_selections (
    record_type,
    record_id,
    field_name,
    observation_id,
    selected_at,
    selected_by
  ) values (
    observation.record_type,
    observation.record_id,
    observation.field_name,
    observation.observation_id,
    now(),
    p_selected_by
  )
  on conflict (record_type, record_id, field_name)
  do update set
    observation_id = excluded.observation_id,
    selected_at = excluded.selected_at,
    selected_by = excluded.selected_by;

  perform set_config('app.controlled_catalog_write', 'off', true);
end;
$$;

create or replace function public.accept_field_observation(
  p_observation_id uuid,
  p_selected_by text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1
    from public.field_observations
    where observation_id = p_observation_id
      and knowledge_status = 'KNOWN'
  ) then
    raise exception 'accept_field_observation() requires a KNOWN observation';
  end if;

  perform public.select_field_observation(p_observation_id, p_selected_by);
end;
$$;

create or replace function public.retire_catalog_record(
  p_record_type public.catalog_record_type,
  p_record_id uuid,
  p_reason text,
  p_retired_by text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_table_name text;
  v_primary_key text;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'A retirement reason is required';
  end if;

  v_table_name := public.catalog_table_name(p_record_type);
  v_primary_key := public.catalog_primary_key(p_record_type);
  perform set_config('app.controlled_catalog_write', 'on', true);

  execute format(
    'update public.%I
       set retired_at = now(),
           retirement_reason = $1
     where %I = $2
       and retired_at is null',
    v_table_name,
    v_primary_key
  ) using p_reason || coalesce(' [actor: ' || p_retired_by || ']', ''), p_record_id;

  if not found then
    raise exception 'Active canonical record % % does not exist',
      p_record_type,
      p_record_id;
  end if;

  perform set_config('app.controlled_catalog_write', 'off', true);
end;
$$;

create or replace function public.audit_catalog_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  row_data jsonb;
  primary_key_name text;
  affected_id uuid;
begin
  row_data := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  primary_key_name := case tg_table_name
    when 'universities' then 'university_id'
    when 'schools' then 'school_id'
    when 'programs' then 'program_id'
    when 'program_schools' then 'program_school_id'
    when 'program_versions' then 'program_version_id'
    when 'program_admissions' then 'admission_id'
    when 'program_prerequisites' then 'prerequisite_id'
    when 'program_courses' then 'course_id'
    when 'program_costs' then 'cost_id'
    when 'program_deadlines' then 'deadline_id'
    when 'sources' then 'source_id'
    when 'canonical_field_selections' then 'record_id'
    when 'program_derived_features' then 'derived_feature_id'
    when 'external_metrics' then 'external_metric_id'
  end;

  if primary_key_name is not null then
    affected_id := (row_data ->> primary_key_name)::uuid;
  end if;

  insert into public.audit_events (
    table_name,
    record_id,
    operation,
    old_row,
    new_row,
    actor
  ) values (
    tg_table_name,
    affected_id,
    tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end,
    coalesce(
      nullif(current_setting('request.jwt.claim.sub', true), ''),
      current_user
    )
  );

  return coalesce(new, old);
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'universities',
    'schools',
    'programs',
    'program_schools',
    'program_versions',
    'program_admissions',
    'program_prerequisites',
    'program_courses',
    'program_costs',
    'program_deadlines',
    'sources',
    'canonical_field_selections',
    'program_derived_features',
    'external_metrics'
  ]
  loop
    execute format(
      'create trigger %I after insert or update or delete on public.%I
       for each row execute function public.audit_catalog_change()',
      table_name || '_audit',
      table_name
    );
  end loop;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'universities',
    'schools',
    'programs',
    'program_schools',
    'program_versions',
    'program_admissions',
    'program_prerequisites',
    'program_courses',
    'program_costs',
    'program_deadlines',
    'sources',
    'evidence_items',
    'field_observations',
    'canonical_field_selections',
    'program_derived_features',
    'external_metrics'
  ]
  loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format(
      'create policy %I on public.%I for select to public using (true)',
      table_name || '_public_read',
      table_name
    );
  end loop;
end;
$$;

alter table public.audit_events enable row level security;

revoke execute on function public.select_field_observation(uuid, text) from public;
revoke execute on function public.accept_field_observation(uuid, text) from public;
revoke execute on function public.retire_catalog_record(public.catalog_record_type, uuid, text, text) from public;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    grant execute on function public.select_field_observation(uuid, text) to service_role;
    grant execute on function public.accept_field_observation(uuid, text) to service_role;
    grant execute on function public.retire_catalog_record(public.catalog_record_type, uuid, text, text) to service_role;
  end if;
end;
$$;

commit;
