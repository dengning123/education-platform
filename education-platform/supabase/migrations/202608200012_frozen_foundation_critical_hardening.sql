-- Migration 012: frozen foundation critical hardening.
-- Additive over 001-011. Does not create Eligibility v0.2 or 014 objects.

begin;

do $preflight$
declare
  v_user text := current_user;
  v_public_owner text;
  v_private_owner text;
  v_db_owner text;
  v_createrole boolean;
begin
  select rolcreaterole into v_createrole from pg_roles where rolname = v_user;
  select pg_get_userbyid(d.datdba) into v_db_owner
  from pg_database d where d.datname = current_database();
  select pg_get_userbyid(n.nspowner) into v_public_owner
  from pg_namespace n where n.nspname = 'public';
  select pg_get_userbyid(n.nspowner) into v_private_owner
  from pg_namespace n where n.nspname = 'private';
  if not coalesce(v_createrole, false)
     or v_private_owner is distinct from v_user
     or not (
          v_public_owner is not distinct from v_user
          or (
            v_public_owner = 'pg_database_owner'
            and v_db_owner is not distinct from v_user
          )
        )
  then
    raise exception using errcode = '42501',
      message = format(
        '012 preflight failed: user=%s createrole=%s public_owner=%s private_owner=%s db_owner=%s',
        v_user, v_createrole, v_public_owner, v_private_owner, v_db_owner
      );
  end if;
end;
$preflight$;

do $runtime_roles$
declare r text;
begin
  foreach r in array array['anon','authenticated','service_role','authenticator']
  loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I nologin nosuperuser nocreatedb nocreaterole nobypassrls', r);
    end if;
  end loop;
end;
$runtime_roles$;


create type public.program_foundation_state as enum ('DRAFT', 'COMPLETE');
create type public.taxonomy_release_status as enum ('DRAFT', 'VERIFIED', 'RETIRED');
create type public.applicability_granularity_scope as enum (
  'UNSPECIFIED', 'PROGRAM', 'SCHOOL', 'INSTITUTION',
  'CIP_FIELD', 'CREDENTIAL_FIELD', 'NATIONAL_OCCUPATION'
);
create type public.applicability_population_scope as enum (
  'UNSPECIFIED', 'UNDERGRADUATE', 'GRADUATE', 'ALL_STUDENTS',
  'PROGRAM_COHORT', 'UNKNOWN'
);
create type public.evidence_applicability_status as enum (
  'REVIEWED_APPLICABLE', 'REVIEWED_INAPPLICABLE', 'LEGACY_UNASSERTED'
);
create type public.student_deletion_reason_code as enum (
  'USER_REQUEST', 'LEGAL_OBLIGATION', 'TEST_LIFECYCLE', 'ADMINISTRATIVE'
);
create type public.student_deletion_request_class as enum (
  'PRIVACY_RIGHTS', 'OPERATIONAL', 'TEST'
);

create table public.foundation_function_contracts (
  schema_name text not null,
  function_name text not null,
  identity_arguments text not null,
  owner_role text not null,
  prosecdef boolean not null,
  search_path text not null,
  allowed_caller_roles text[] not null,
  body_digest text not null,
  primary key (schema_name, function_name, identity_arguments)
);

create table public.source_identities (
  source_identity_id uuid primary key default extensions.gen_random_uuid(),
  canonical_publisher text not null,
  current_source_id uuid,
  created_at timestamptz not null default now(),
  constraint source_identities_publisher_not_blank check (btrim(canonical_publisher) <> '')
);

alter table public.sources
  add column source_identity_id uuid,
  add column revision_number integer,
  add column supersedes_source_id uuid,
  add column revision_reason text,
  add column retrieval_content_hash text;

alter table public.programs
  add column foundation_state public.program_foundation_state;

alter table public.taxonomy_releases
  add column status public.taxonomy_release_status,
  add column verified_by text,
  add column verified_at timestamptz,
  add column retired_at timestamptz,
  add column retirement_reason text;

alter table public.program_derived_features
  add column supersedes_derived_feature_id uuid;

alter table public.eligibility_evaluations
  add column inputs_sealed_at timestamptz;

alter table public.student_deletion_tombstones
  rename column deletion_reason to legacy_deletion_reason;
alter table public.student_deletion_tombstones
  add column reason_code public.student_deletion_reason_code,
  add column request_class public.student_deletion_request_class;

update public.student_deletion_tombstones
set reason_code = coalesce(reason_code, 'ADMINISTRATIVE'),
    request_class = coalesce(request_class, 'OPERATIONAL')
where reason_code is null;

alter table public.student_deletion_tombstones
  alter column reason_code set not null,
  alter column request_class set not null;

create table private.student_deletion_authorizations (
  transaction_id bigint not null,
  student_id uuid not null,
  executor_role text not null,
  created_at timestamptz not null default now(),
  primary key (transaction_id, student_id)
);

create table private.student_lifecycle_audit (
  event_id uuid primary key default extensions.gen_random_uuid(),
  student_id uuid not null references public.students(student_id) on delete cascade,
  object_type text not null,
  object_id uuid,
  event_code text not null,
  actor text,
  occurred_at timestamptz not null default now()
);

-- Backfill source identities: one identity + revision 1 per existing source.
do $src$
declare r record;
begin
  for r in select * from public.sources order by source_id
  loop
    insert into public.source_identities (
      source_identity_id, canonical_publisher, current_source_id
    ) values (
      extensions.gen_random_uuid(), r.publisher, r.source_id
    );
  end loop;
  update public.sources s
  set source_identity_id = i.source_identity_id,
      revision_number = 1,
      supersedes_source_id = null,
      revision_reason = 'INITIAL',
      retrieval_content_hash = encode(
        extensions.digest(convert_to(s.url, 'UTF8'), 'sha256'), 'hex'
      )
  from public.source_identities i
  where i.current_source_id = s.source_id;
end;
$src$;

alter table public.sources
  alter column source_identity_id set not null,
  alter column revision_number set not null,
  alter column retrieval_content_hash set not null;

alter table public.sources drop constraint if exists sources_url_key;
drop index if exists sources_url_key;

create unique index sources_identity_revision_uidx
  on public.sources (source_identity_id, revision_number);
create unique index sources_identity_source_uidx
  on public.sources (source_identity_id, source_id);
create unique index sources_supersedes_uidx
  on public.sources (supersedes_source_id)
  where supersedes_source_id is not null;

alter table public.sources
  add constraint sources_identity_fk
    foreign key (source_identity_id)
    references public.source_identities(source_identity_id)
    on delete restrict;
alter table public.sources
  add constraint sources_supersedes_fk
    foreign key (supersedes_source_id)
    references public.sources(source_id)
    on delete restrict;
alter table public.sources
  add constraint sources_revision_positive check (revision_number >= 1);
alter table public.sources
  add constraint sources_hash_format check (retrieval_content_hash ~ '^[a-f0-9]{64}$');

alter table public.source_identities
  alter column current_source_id set not null;
alter table public.source_identities
  add constraint source_identities_current_unique unique (current_source_id) deferrable;
alter table public.source_identities
  add constraint source_identities_current_pair_fk
    foreign key (source_identity_id, current_source_id)
    references public.sources(source_identity_id, source_id)
    deferrable initially deferred;

drop trigger if exists sources_set_updated_at on public.sources;

alter table public.programs disable trigger programs_canonical_write_guard;
alter table public.taxonomy_releases disable trigger taxonomy_releases_immutable;
alter table public.eligibility_evaluations disable trigger eligibility_evaluations_guard;

-- Program foundation backfill.
update public.programs p
set foundation_state = case
  when (
    select count(*) from public.program_schools s
    where s.program_id = p.program_id
      and s.relationship_role = 'PRIMARY_ADMINISTRATIVE'
      and s.retired_at is null
  ) = 1 then 'COMPLETE'::public.program_foundation_state
  else 'DRAFT'::public.program_foundation_state
end;
alter table public.programs
  alter column foundation_state set not null,
  alter column foundation_state set default 'DRAFT';
alter table public.programs
  add constraint programs_active_requires_complete check (
    active_status is distinct from 'ACTIVE'
    or foundation_state = 'COMPLETE'
  );

update public.taxonomy_releases
set status = 'VERIFIED',
    verified_by = 'MIGRATION_001_011_BACKFILL',
    verified_at = published_at
where release_code = 'v0.1' and status is null;
update public.taxonomy_releases
set status = coalesce(status, 'DRAFT');
alter table public.taxonomy_releases
  alter column status set not null;

alter table public.program_derived_features
  add constraint program_derived_features_supersede_fk
    foreign key (supersedes_derived_feature_id)
    references public.program_derived_features(derived_feature_id)
    on delete restrict;
create unique index program_derived_features_superseded_uidx
  on public.program_derived_features (supersedes_derived_feature_id)
  where supersedes_derived_feature_id is not null;

update public.eligibility_evaluations
set inputs_sealed_at = evaluated_at
where evaluation_state = 'COMPLETED' and inputs_sealed_at is null;

alter table public.programs enable trigger programs_canonical_write_guard;
alter table public.taxonomy_releases enable trigger taxonomy_releases_immutable;
alter table public.eligibility_evaluations enable trigger eligibility_evaluations_guard;

create table public.evidence_applicability_scopes (
  scope_id uuid primary key default extensions.gen_random_uuid(),
  evidence_id uuid not null references public.evidence_items(evidence_id) on delete restrict,
  record_type public.catalog_record_type not null,
  record_id uuid not null,
  program_scope_key text not null,
  program_version_scope_key text not null,
  field_name text not null,
  granularity_scope public.applicability_granularity_scope not null,
  population_scope_code public.applicability_population_scope not null,
  cycle_scope_code text not null,
  resolved_program_id uuid references public.programs(program_id) on delete restrict,
  resolved_program_version_id uuid references public.program_versions(program_version_id) on delete restrict,
  scope_digest text not null,
  created_at timestamptz not null default now(),
  constraint evidence_scope_field_not_blank check (btrim(field_name) <> ''),
  constraint evidence_scope_cycle_format check (
    cycle_scope_code = 'UNSPECIFIED'
    or cycle_scope_code ~ '^[A-Z0-9][A-Z0-9._:-]{0,63}$'
  ),
  constraint evidence_scope_program_pair check (
    (program_scope_key = 'NOT_PROGRAM_SCOPED') = (resolved_program_id is null)
  ),
  constraint evidence_scope_version_pair check (
    (program_version_scope_key = 'NOT_VERSION_SCOPED') = (resolved_program_version_id is null)
  ),
  constraint evidence_scope_digest_format check (scope_digest ~ '^[a-f0-9]{64}$')
);
create unique index evidence_applicability_scopes_head_key
  on public.evidence_applicability_scopes (
    evidence_id, record_type, record_id, program_scope_key,
    program_version_scope_key, field_name, granularity_scope,
    population_scope_code, cycle_scope_code
  );

create table public.evidence_applicability_assertions (
  assertion_id uuid primary key default extensions.gen_random_uuid(),
  scope_id uuid references public.evidence_applicability_scopes(scope_id) on delete restrict,
  applicability_status public.evidence_applicability_status not null,
  asserted_by text not null,
  asserted_at timestamptz not null default now(),
  rationale text,
  foundation_contract_release_code text not null default 'foundation-integrity-v1',
  supersedes_assertion_id uuid references public.evidence_applicability_assertions(assertion_id) on delete restrict,
  constraint evidence_assertion_reviewed_has_scope check (
    (applicability_status = 'LEGACY_UNASSERTED') = (scope_id is null)
  ),
  constraint evidence_assertion_actor_not_blank check (btrim(asserted_by) <> '')
);

create table public.evidence_applicability_heads (
  scope_id uuid primary key
    references public.evidence_applicability_scopes(scope_id) on delete restrict,
  assertion_id uuid not null unique
    references public.evidence_applicability_assertions(assertion_id) on delete restrict
);

create table public.field_observation_applicability (
  observation_id uuid primary key
    references public.field_observations(observation_id) on delete restrict,
  assertion_id uuid not null
    references public.evidence_applicability_assertions(assertion_id) on delete restrict
);

-- Historical compatibility: one LEGACY_UNASSERTED assertion per pre-012 observation.
do $legacy$
declare r record;
  v_assertion uuid;
begin
  for r in
    select observation_id
    from public.field_observations
    order by observation_id
  loop
    v_assertion := extensions.gen_random_uuid();
    insert into public.evidence_applicability_assertions (
      assertion_id, scope_id, applicability_status, asserted_by, rationale
    ) values (
      v_assertion, null, 'LEGACY_UNASSERTED', 'MIGRATION_012_BACKFILL',
      'Pre-012 observation without inferred scope'
    );
    insert into public.field_observation_applicability (observation_id, assertion_id)
    values (r.observation_id, v_assertion);
  end loop;
end;
$legacy$;


create or replace function private.student_privacy_delete_allowed()
returns boolean
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  -- FK ON DELETE CASCADE runs as the table owner, not the executor.
  -- Closure is authorized only by a matching tx-bound row after the
  -- students parent is already absent. Executor identity alone is not enough.
  return exists (
    select 1
    from private.student_deletion_authorizations a
    where a.transaction_id = txid_current()
      and not exists (
        select 1 from public.students s where s.student_id = a.student_id
      )
  );
end;
$$;

create or replace function private.lock_student_row(p_student_id uuid)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform 1 from public.students where student_id = p_student_id for update;
  if not found then
    raise exception using errcode = '23503',
      message = 'Student does not exist',
      hint = 'student_lifecycle_missing';
  end if;
end;
$$;

create or replace function private.lock_student_lifecycle(p_student_id uuid)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform pg_advisory_xact_lock(
    hashtextextended('student-lifecycle:' || lower(p_student_id::text), 0)
  );
  perform private.lock_student_row(p_student_id);
end;
$$;

create or replace function private.lock_student_owned_total_order(p_student_id uuid)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform 1 from public.student_profile_versions
    where student_id = p_student_id
    order by profile_version_id for update;
  perform 1 from public.fit_intent_sets i
    join public.student_profile_versions p using (profile_version_id)
    where p.student_id = p_student_id
    order by i.intent_set_id for update;
  perform 1 from public.eligibility_evaluations e
    join public.student_profile_versions p using (profile_version_id)
    where p.student_id = p_student_id
    order by e.evaluation_id for update;
  perform 1 from public.fit_evaluations e
    join public.student_profile_versions p using (profile_version_id)
    where p.student_id = p_student_id
    order by e.evaluation_id for update;
end;
$$;

create or replace function private.json_uuid(p_row jsonb, p_keys text[])
returns uuid
language sql
immutable
as $$
  select (p_row ->> k)::uuid
  from unnest(p_keys) k
  where p_row ? k
  limit 1;
$$;

create or replace function private.student_id_from_profile(p_profile_id uuid)
returns uuid
language sql
stable
as $$
  select student_id from public.student_profile_versions
  where profile_version_id = p_profile_id;
$$;

create or replace function private.lock_student_from_row(p_row jsonb)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_student uuid;
  v_profile uuid;
begin
  v_student := private.json_uuid(p_row, array['student_id']);
  if v_student is null then
    v_profile := private.json_uuid(p_row, array['profile_version_id']);
    if v_profile is not null then
      v_student := private.student_id_from_profile(v_profile);
    end if;
  end if;
  if v_student is null and p_row ? 'intent_set_id' then
    select p.student_id into v_student
    from public.fit_intent_sets i
    join public.student_profile_versions p using (profile_version_id)
    where i.intent_set_id = (p_row ->> 'intent_set_id')::uuid;
  end if;
  if v_student is null then
    raise exception using errcode = '23503',
      message = 'Student lifecycle lock requires a resolvable student_id';
  end if;
  perform private.lock_student_lifecycle(v_student);
end;
$$;

create or replace function private.lock_evaluation_from_row(p_row jsonb)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_eval uuid;
  v_student uuid;
begin
  v_eval := private.json_uuid(p_row, array['evaluation_id']);
  if v_eval is null then
    raise exception using errcode = '23503',
      message = 'Evaluation row requires evaluation_id';
  end if;
  select p.student_id into v_student
  from public.eligibility_evaluations e
  join public.student_profile_versions p using (profile_version_id)
  where e.evaluation_id = v_eval;
  if v_student is null then
    select p.student_id into v_student
    from public.fit_evaluations e
    join public.student_profile_versions p using (profile_version_id)
    where e.evaluation_id = v_eval;
  end if;
  if v_student is null then
    v_student := private.student_id_from_profile(
      private.json_uuid(p_row, array['profile_version_id'])
    );
  end if;
  if v_student is null then
    raise exception using errcode = '23503',
      message = 'Evaluation lifecycle lock requires a student';
  end if;
  perform private.lock_student_lifecycle(v_student);
end;
$$;

create or replace function public.length_prefixed(p_value text)
returns bytea
language sql
immutable
as $$
  select int4send(octet_length(convert_to(coalesce(p_value, ''), 'UTF8')))
      || convert_to(coalesce(p_value, ''), 'UTF8');
$$;

create or replace function public.scope_digest(
  p_evidence_id uuid,
  p_record_type public.catalog_record_type,
  p_record_id uuid,
  p_program_key text,
  p_version_key text,
  p_field text,
  p_granularity public.applicability_granularity_scope,
  p_population public.applicability_population_scope,
  p_cycle text
)
returns text
language sql
immutable
as $$
  select encode(
    extensions.digest(
      public.length_prefixed(lower(p_evidence_id::text))
      || public.length_prefixed(p_record_type::text)
      || public.length_prefixed(lower(p_record_id::text))
      || public.length_prefixed(p_program_key)
      || public.length_prefixed(p_version_key)
      || public.length_prefixed(p_field)
      || public.length_prefixed(p_granularity::text)
      || public.length_prefixed(p_population::text)
      || public.length_prefixed(p_cycle),
      'sha256'
    ),
    'hex'
  );
$$;

create or replace function public.derive_program_scope(
  p_record_type public.catalog_record_type,
  p_record_id uuid,
  out o_program_id uuid,
  out o_version_id uuid,
  out o_program_key text,
  out o_version_key text
)
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, extensions
as $$
declare
  v_exists boolean;
  v_table text;
  v_pk text;
begin
  v_table := public.catalog_table_name(p_record_type);
  v_pk := public.catalog_primary_key(p_record_type);
  execute format('select exists(select 1 from public.%I where %I = $1)', v_table, v_pk)
    into v_exists using p_record_id;
  if not v_exists then
    raise exception using errcode = '23503',
      message = format('Catalog record %s %s does not exist', p_record_type, p_record_id);
  end if;
  o_program_id := null;
  o_version_id := null;
  case p_record_type
    when 'UNIVERSITY', 'SCHOOL' then
      null;
    when 'PROGRAM' then
      o_program_id := p_record_id;
    when 'PROGRAM_SCHOOL' then
      select program_id into o_program_id from public.program_schools where program_school_id = p_record_id;
    when 'PROGRAM_VERSION' then
      select program_id, program_version_id into o_program_id, o_version_id
      from public.program_versions where program_version_id = p_record_id;
    when 'PROGRAM_ADMISSION' then
      select v.program_id, a.program_version_id into o_program_id, o_version_id
      from public.program_admissions a
      join public.program_versions v using (program_version_id)
      where a.admission_id = p_record_id;
    when 'PROGRAM_PREREQUISITE' then
      select v.program_id, p.program_version_id into o_program_id, o_version_id
      from public.program_prerequisites p
      join public.program_versions v using (program_version_id)
      where p.prerequisite_id = p_record_id;
    when 'PROGRAM_COURSE' then
      select v.program_id, c.program_version_id into o_program_id, o_version_id
      from public.program_courses c
      join public.program_versions v using (program_version_id)
      where c.course_id = p_record_id;
    when 'PROGRAM_COST' then
      select v.program_id, c.program_version_id into o_program_id, o_version_id
      from public.program_costs c
      join public.program_versions v using (program_version_id)
      where c.cost_id = p_record_id;
    when 'PROGRAM_DEADLINE' then
      select v.program_id, d.program_version_id into o_program_id, o_version_id
      from public.program_deadlines d
      join public.program_versions v using (program_version_id)
      where d.deadline_id = p_record_id;
  end case;
  o_program_key := case when o_program_id is null then 'NOT_PROGRAM_SCOPED' else lower(o_program_id::text) end;
  o_version_key := case when o_version_id is null then 'NOT_VERSION_SCOPED' else lower(o_version_id::text) end;
end;
$$;

create or replace function public.assert_catalog_field(
  p_record_type public.catalog_record_type,
  p_field_name text
)
returns void
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, extensions
as $$
declare
  v_table text := public.catalog_table_name(p_record_type);
  v_pk text := public.catalog_primary_key(p_record_type);
  v_attgenerated text;
begin
  if p_field_name in (v_pk, 'created_at', 'updated_at', 'retired_at', 'retirement_reason') then
    raise exception using errcode = '22023',
      message = format('Field %s.%s is not eligible for applicability', v_table, p_field_name);
  end if;
  select a.attgenerated into v_attgenerated
  from pg_attribute a
  join pg_class c on c.oid = a.attrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = v_table and a.attname = p_field_name and a.attnum > 0 and not a.attisdropped;
  if v_attgenerated is null or v_attgenerated <> '' then
    raise exception using errcode = '22023',
      message = format('Field %s.%s is not a real non-generated column', v_table, p_field_name);
  end if;
end;
$$;

create or replace function public.reject_terminal_insert(p_row jsonb, p_table text)
returns void
language plpgsql
immutable
as $$
begin
  if coalesce(p_row ->> 'mapping_status', p_row ->> 'status', p_row ->> 'evaluation_state', p_row ->> 'workflow_status')
     in ('VERIFIED', 'REJECTED', 'RETIRED', 'FROZEN', 'COMPLETED') then
    raise exception using errcode = '55000',
      message = format('Terminal states cannot be inserted on %s', p_table),
      hint = 'terminal_insert_forbidden';
  end if;
end;
$$;

create or replace function public.insert_composite(p_rel regclass, p_row jsonb)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_cols text;
  v_sel text;
begin
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum),
         string_agg(format('r.%I', a.attname), ', ' order by a.attnum)
    into v_cols, v_sel
  from pg_attribute a
  where a.attrelid = p_rel
    and a.attnum > 0
    and not a.attisdropped
    and a.attgenerated = ''
    and p_row ? a.attname
    and jsonb_typeof(p_row -> a.attname) is distinct from 'null';
  execute format(
    'insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1) r',
    p_rel, v_cols, v_sel, p_rel
  ) using p_row;
end;
$$;

create or replace function private.write_student_lifecycle_audit(
  p_student_id uuid,
  p_object_type text,
  p_object_id uuid,
  p_event_code text
)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  insert into private.student_lifecycle_audit (
    student_id, object_type, object_id, event_code, actor
  ) values (
    p_student_id, p_object_type, p_object_id, p_event_code, session_user::text
  );
end;
$$;

create or replace function private.close_student_owned_rows(p_student_id uuid)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  -- 012 closed set only. Must not name 013 pin/snapshot/projection tables.
  if exists (select 1 from private.student_identities where student_id = p_student_id)
     or exists (select 1 from public.student_profile_versions where student_id = p_student_id)
     or exists (select 1 from private.student_lifecycle_audit where student_id = p_student_id)
     or exists (
          select 1 from public.student_data_completeness c
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.student_evidence_items e
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.student_degrees d
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.student_courses c
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.student_test_scores t
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.student_experiences x
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.student_skills k
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.student_goals g
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.student_preferences f
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.student_record_concept_mappings m
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.student_derived_feature_values v
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.eligibility_evaluations e
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.fit_evaluations e
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from public.fit_intent_sets i
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
     or exists (
          select 1 from private.fit_student_access_contexts c
          join public.student_profile_versions p using (profile_version_id)
          where p.student_id = p_student_id
        )
  then
    raise exception using errcode = '55000',
      message = 'Student-owned rows remain after privacy cascade',
      hint = 'privacy_closure_incomplete';
  end if;
end;
$$;


-- Neutralize every production app.* authorization GUC in 001-011 functions.
do $guc$
declare
  r record;
  def text;
begin
  for r in
    select p.oid,
           n.nspname,
           p.proname,
           pg_get_functiondef(p.oid) as def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid) ~ 'app\.(controlled_catalog_write|rule_set_controlled_write|evaluation_controlled_write|student_privacy_delete|fit_registry_controlled_write|fit_intent_controlled_write|fit_context_controlled_write|fit_context_mapping_controlled_write|fit_context_selection_write|fit_evaluation_controlled_write)'
  loop
    def := r.def;
    def := regexp_replace(def,
      $re$current_setting\('app\.student_privacy_delete',\s*true\)\s*=\s*'on'$re$,
      'private.student_privacy_delete_allowed()', 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.controlled_catalog_write',\s*true\)\s*is distinct from 'on'$re$,
      $re$current_user is distinct from 'foundation_catalog_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.rule_set_controlled_write',\s*true\)\s*is distinct from 'on'$re$,
      $re$current_user is distinct from 'foundation_catalog_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.fit_registry_controlled_write',\s*true\)\s*is distinct from 'on'$re$,
      $re$current_user is distinct from 'foundation_catalog_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.fit_context_controlled_write',\s*true\)\s*is distinct from 'on'$re$,
      $re$current_user is distinct from 'foundation_catalog_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.fit_context_mapping_controlled_write',\s*true\)\s*is distinct from 'on'$re$,
      $re$current_user is distinct from 'foundation_catalog_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.fit_context_selection_write',\s*true\)\s*=\s*'on'$re$,
      $re$current_user = 'foundation_catalog_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.fit_context_selection_write',\s*true\)\s*is distinct from 'on'$re$,
      $re$current_user is distinct from 'foundation_catalog_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.fit_intent_controlled_write',\s*true\)\s*is distinct from 'on'$re$,
      $re$current_user is distinct from 'foundation_student_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.evaluation_controlled_write',\s*true\)\s*=\s*'on'$re$,
      $re$current_user = 'foundation_evaluation_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.fit_evaluation_controlled_write',\s*true\)\s*=\s*'on'$re$,
      $re$current_user = 'foundation_evaluation_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$current_setting\('app\.fit_evaluation_controlled_write',\s*true\)\s*is distinct from 'on'$re$,
      $re$current_user is distinct from 'foundation_evaluation_executor'$re$, 'g');
    def := regexp_replace(def,
      $re$perform set_config\(\s*'app\.[^']+'[^;]*;$re$,
      '', 'g');
    def := regexp_replace(def,
      $re$[ \t]*v_(prior|prior_setting|prior_control_setting)\s+text;\n$re$,
      '', 'g');
    def := regexp_replace(def,
      $re$[ \t]*v_(prior|prior_setting|prior_control_setting)\s*:=\s*current_setting\(\s*'app\.[^']+'[^;]*;\n$re$,
      '', 'g');
    def := regexp_replace(def, 'pg_temp', 'extensions', 'g');
    if def ~ $re$current_setting\('app\.|set_config\('app\.$re$ then
      raise exception using errcode = '55000',
        message = format('GUC neutralization left app.* in %s.%s', r.nspname, r.proname);
    end if;
    execute def;
  end loop;
end;
$guc$;

-- Remaining explicit search_path hardening for owner-read helpers.
alter function public.current_user_owns_student(uuid)
  set search_path = pg_catalog, public, private, extensions;
alter function public.current_user_owns_profile(uuid)
  set search_path = pg_catalog, public, private, extensions;
revoke all on function public.current_user_owns_student(uuid) from public, anon;
revoke all on function public.current_user_owns_profile(uuid) from public, anon;
grant execute on function public.current_user_owns_student(uuid) to authenticated;
grant execute on function public.current_user_owns_profile(uuid) to authenticated;


create or replace function public.create_source_identity(
  p_canonical_publisher text,
  p_title text,
  p_url text,
  p_reliability_tier public.reliability_tier,
  p_source_type text,
  p_retrieval_content_hash text,
  p_publisher text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_identity uuid;
  v_source uuid;
begin
  if p_retrieval_content_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'retrieval_content_hash must be SHA-256 hex';
  end if;
  v_identity := extensions.gen_random_uuid();
  v_source := extensions.gen_random_uuid();
  insert into public.source_identities (
    source_identity_id, canonical_publisher, current_source_id
  ) values (v_identity, p_canonical_publisher, v_source);
  insert into public.sources (
    source_id, source_identity_id, revision_number, publisher, title, url,
    reliability_tier, source_type, retrieval_content_hash, revision_reason
  ) values (
    v_source, v_identity, 1, coalesce(nullif(btrim(p_publisher), ''), p_canonical_publisher),
    p_title, p_url, p_reliability_tier, p_source_type, p_retrieval_content_hash, 'INITIAL'
  );
  insert into public.audit_events (table_name, record_id, operation, new_row, actor)
  values ('source_identities', v_identity, 'INSERT', jsonb_build_object('source_id', v_source), session_user::text);
  return v_identity;
end;
$$;

create or replace function public.create_source_revision(
  p_source_identity_id uuid,
  p_publisher text,
  p_title text,
  p_url text,
  p_reliability_tier public.reliability_tier,
  p_source_type text,
  p_retrieval_content_hash text,
  p_revision_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_identity public.source_identities%rowtype;
  v_current public.sources%rowtype;
  v_new uuid;
begin
  if nullif(btrim(p_revision_reason), '') is null then
    raise exception using errcode = '22023', message = 'revision_reason is required';
  end if;
  if p_retrieval_content_hash !~ '^[a-f0-9]{64}$' then
    raise exception using errcode = '22023', message = 'retrieval_content_hash must be SHA-256 hex';
  end if;
  select * into v_identity from public.source_identities
  where source_identity_id = p_source_identity_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'Source identity does not exist';
  end if;
  select * into v_current from public.sources
  where source_id = v_identity.current_source_id for key share;
  if v_current.source_identity_id is distinct from p_source_identity_id then
    raise exception using errcode = '55000', message = 'Current source is not the identity head';
  end if;
  begin
    insert into public.sources (
      source_identity_id, revision_number, supersedes_source_id, publisher, title, url,
      reliability_tier, source_type, retrieval_content_hash, revision_reason
    ) values (
      p_source_identity_id, v_current.revision_number + 1, v_current.source_id,
      p_publisher, p_title, p_url, p_reliability_tier, p_source_type,
      p_retrieval_content_hash, p_revision_reason
    ) returning source_id into v_new;
  exception when unique_violation then
    raise exception using errcode = '55000',
      message = 'Stale source head cannot be superseded',
      hint = 'source_revision_conflict';
  end;
  update public.source_identities
  set current_source_id = v_new
  where source_identity_id = p_source_identity_id
    and current_source_id = v_current.source_id;
  if not found then
    raise exception using errcode = '55000',
      message = 'Stale source head cannot be superseded',
      hint = 'source_revision_conflict';
  end if;
  insert into public.audit_events (table_name, record_id, operation, new_row, actor)
  values ('sources', v_new, 'INSERT', jsonb_build_object('revision', v_current.revision_number + 1), session_user::text);
  return v_new;
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
set search_path = pg_catalog, public, extensions
as $$
declare
  v_table_name text;
  v_primary_key text;
  v_n integer;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'A retirement reason is required';
  end if;
  v_table_name := public.catalog_table_name(p_record_type);
  v_primary_key := public.catalog_primary_key(p_record_type);
  perform pg_advisory_xact_lock(hashtextextended(
    'catalog:' || p_record_type::text || ':' || p_record_id::text, 0));
  execute format(
    'select 1 from public.%I where %I = $1 and retired_at is null for update',
    v_table_name, v_primary_key
  ) using p_record_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'Active canonical record % % does not exist',
      p_record_type, p_record_id;
  end if;
  execute format(
    'update public.%I
       set retired_at = now(),
           retirement_reason = $1
     where %I = $2
       and retired_at is null',
    v_table_name, v_primary_key
  ) using p_reason || coalesce(' [actor: ' || p_retired_by || ']', ''), p_record_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    raise exception 'Active canonical record % % does not exist',
      p_record_type, p_record_id;
  end if;
end;
$$;

create or replace function public.create_evidence_scope(
  p_evidence_id uuid,
  p_record_type public.catalog_record_type,
  p_record_id uuid,
  p_field_name text,
  p_granularity public.applicability_granularity_scope,
  p_population public.applicability_population_scope,
  p_cycle text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_prog uuid; v_ver uuid; v_prog_key text; v_ver_key text;
  v_cycle text;
  v_digest text;
  v_scope uuid;
begin
  if not exists (select 1 from public.evidence_items where evidence_id = p_evidence_id) then
    raise exception using errcode = '23503', message = 'Evidence item does not exist';
  end if;
  perform public.assert_catalog_field(p_record_type, p_field_name);
  select o_program_id, o_version_id, o_program_key, o_version_key
    into v_prog, v_ver, v_prog_key, v_ver_key
  from public.derive_program_scope(p_record_type, p_record_id);
  v_cycle := coalesce(nullif(btrim(p_cycle), ''), 'UNSPECIFIED');
  if v_cycle <> 'UNSPECIFIED' then
    v_cycle := upper(v_cycle);
    if v_cycle !~ '^[A-Z0-9][A-Z0-9._:-]{0,63}$' then
      raise exception using errcode = '22023',
        message = 'cycle_scope_code must be UNSPECIFIED or an uppercase NFC token';
    end if;
  end if;
  v_digest := public.scope_digest(
    p_evidence_id, p_record_type, p_record_id, v_prog_key, v_ver_key,
    p_field_name, p_granularity, p_population, v_cycle
  );
  perform pg_advisory_xact_lock(hashtextextended(v_digest, 0));
  insert into public.evidence_applicability_scopes (
    evidence_id, record_type, record_id, program_scope_key, program_version_scope_key,
    field_name, granularity_scope, population_scope_code, cycle_scope_code,
    resolved_program_id, resolved_program_version_id, scope_digest
  ) values (
    p_evidence_id, p_record_type, p_record_id, v_prog_key, v_ver_key,
    p_field_name, p_granularity, p_population, v_cycle, v_prog, v_ver, v_digest
  )
  on conflict (evidence_id, record_type, record_id, program_scope_key,
               program_version_scope_key, field_name, granularity_scope,
               population_scope_code, cycle_scope_code)
  do nothing;
  select scope_id into v_scope
  from public.evidence_applicability_scopes
  where evidence_id = p_evidence_id
    and record_type = p_record_type
    and record_id = p_record_id
    and program_scope_key = v_prog_key
    and program_version_scope_key = v_ver_key
    and field_name = p_field_name
    and granularity_scope = p_granularity
    and population_scope_code = p_population
    and cycle_scope_code = v_cycle
  for update;
  return v_scope;
end;
$$;

create or replace function public.review_evidence_applicability(
  p_scope_id uuid,
  p_status public.evidence_applicability_status,
  p_actor text,
  p_rationale text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_scope public.evidence_applicability_scopes%rowtype;
  v_head uuid;
  v_new uuid;
begin
  if p_status = 'LEGACY_UNASSERTED' then
    raise exception using errcode = '22023',
      message = 'LEGACY_UNASSERTED cannot be created by review';
  end if;
  if nullif(btrim(p_actor), '') is null then
    raise exception using errcode = '22023', message = 'Review actor is required';
  end if;
  select * into v_scope from public.evidence_applicability_scopes
  where scope_id = p_scope_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'Applicability scope does not exist';
  end if;
  select assertion_id into v_head
  from public.evidence_applicability_heads
  where scope_id = p_scope_id for update;
  insert into public.evidence_applicability_assertions (
    scope_id, applicability_status, asserted_by, rationale, supersedes_assertion_id
  ) values (
    p_scope_id, p_status, p_actor, p_rationale, v_head
  ) returning assertion_id into v_new;
  insert into public.evidence_applicability_heads (scope_id, assertion_id)
  values (p_scope_id, v_new)
  on conflict (scope_id) do update
    set assertion_id = excluded.assertion_id
    where evidence_applicability_heads.assertion_id is not distinct from v_head;
  if not exists (
    select 1 from public.evidence_applicability_heads
    where scope_id = p_scope_id and assertion_id = v_new
  ) then
    raise exception using errcode = '55000',
      message = 'Stale applicability head cannot be superseded',
      hint = 'applicability_head_conflict';
  end if;
  return v_new;
end;
$$;

create or replace function public.create_field_observation(
  p_record_type public.catalog_record_type,
  p_record_id uuid,
  p_field_name text,
  p_observed_value jsonb,
  p_knowledge_status public.knowledge_status,
  p_evidence_id uuid,
  p_supersedes_observation_id uuid,
  p_notes text,
  p_assertion_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_id uuid;
  v_status public.evidence_applicability_status;
  v_scope uuid;
  v_is_head boolean;
  v_prog uuid;
  v_ver uuid;
  v_prog_key text;
  v_ver_key text;
begin
  perform public.assert_catalog_field(p_record_type, p_field_name);
  if p_knowledge_status = 'KNOWN' then
    if p_assertion_id is null then
      raise exception using errcode = '55000',
        message = 'KNOWN observations require a headed REVIEWED_APPLICABLE assertion';
    end if;
  end if;
  if p_assertion_id is not null then
    select o_program_id, o_version_id, o_program_key, o_version_key
      into v_prog, v_ver, v_prog_key, v_ver_key
    from public.derive_program_scope(p_record_type, p_record_id);
    -- One exact nine-part identity lookup: the assertion must be the current
    -- head of the scope whose semantic key equals this observation request.
    -- Observations do not carry cycle/population/granularity; those default
    -- to UNSPECIFIED and must not be borrowed from another scope.
    select a.applicability_status, s.scope_id, (h.assertion_id is not null)
      into v_status, v_scope, v_is_head
    from public.evidence_applicability_assertions a
    left join public.evidence_applicability_scopes s
      on s.scope_id = a.scope_id
     and s.evidence_id is not distinct from p_evidence_id
     and s.record_type = p_record_type
     and s.record_id = p_record_id
     and s.field_name = p_field_name
     and s.program_scope_key = v_prog_key
     and s.program_version_scope_key = v_ver_key
     and s.granularity_scope = 'UNSPECIFIED'
     and s.population_scope_code = 'UNSPECIFIED'
     and s.cycle_scope_code = 'UNSPECIFIED'
    left join public.evidence_applicability_heads h
      on h.scope_id = s.scope_id
     and h.assertion_id = a.assertion_id
    where a.assertion_id = p_assertion_id;
    if not found or v_scope is null then
      raise exception using errcode = '55000',
        message = 'Applicability assertion scope does not match the observation subject',
        hint = 'applicability_scope_mismatch';
    end if;
    if v_status is distinct from 'REVIEWED_APPLICABLE'
       or v_status = 'LEGACY_UNASSERTED' then
      raise exception using errcode = '55000',
        message = 'Observation assertion must be headed REVIEWED_APPLICABLE';
    end if;
    if v_is_head is not true then
      raise exception using errcode = '55000',
        message = 'Observation assertion is not the current applicability head';
    end if;
  elsif p_evidence_id is not null then
    raise exception using errcode = '55000',
      message = 'Evidence-backed observations require a reviewed applicability assertion';
  end if;
  insert into public.field_observations (
    record_type, record_id, field_name, observed_value, knowledge_status,
    evidence_id, supersedes_observation_id, notes
  ) values (
    p_record_type, p_record_id, p_field_name, p_observed_value, p_knowledge_status,
    p_evidence_id, p_supersedes_observation_id, p_notes
  ) returning observation_id into v_id;
  if p_assertion_id is not null then
    insert into public.field_observation_applicability (observation_id, assertion_id)
    values (v_id, p_assertion_id);
  end if;
  return v_id;
end;
$$;


create or replace function public.complete_program_foundation(p_program_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare v_count integer;
begin
  perform pg_advisory_xact_lock(hashtextextended('program-lifecycle:' || lower(p_program_id::text), 0));
  perform 1 from public.programs where program_id = p_program_id for update;
  if not found then
    raise exception using errcode = '23503', message = 'Program does not exist';
  end if;
  perform 1 from public.program_schools
  where program_id = p_program_id and retired_at is null
  order by program_school_id for update;
  select count(*) into v_count from public.program_schools
  where program_id = p_program_id
    and relationship_role = 'PRIMARY_ADMINISTRATIVE'
    and retired_at is null;
  if v_count <> 1 then
    raise exception using errcode = '55000',
      message = 'Program completion requires exactly one active primary administrative school';
  end if;
  update public.programs set foundation_state = 'COMPLETE' where program_id = p_program_id;
end;
$$;

create or replace function public.replace_program_primary_school(
  p_program_id uuid,
  p_new_school_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_old uuid;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = '22023', message = 'Replacement reason is required';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('program-lifecycle:' || lower(p_program_id::text), 0));
  perform 1 from public.programs where program_id = p_program_id for update;
  perform 1 from public.program_schools
  where program_id = p_program_id order by program_school_id for update;
  select program_school_id into v_old from public.program_schools
  where program_id = p_program_id
    and relationship_role = 'PRIMARY_ADMINISTRATIVE'
    and retired_at is null;
  if v_old is not null then
    update public.program_schools
    set retired_at = now(), retirement_reason = p_reason
    where program_school_id = v_old;
  end if;
  insert into public.program_schools (program_id, school_id, relationship_role)
  values (p_program_id, p_new_school_id, 'PRIMARY_ADMINISTRATIVE');
end;
$$;

create or replace function public.create_taxonomy_release(
  p_release_code text,
  p_published_at timestamptz,
  p_notes text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  insert into public.taxonomy_releases (release_code, published_at, notes, status)
  values (p_release_code, p_published_at, p_notes, 'DRAFT');
  perform 1 from public.taxonomy_releases where release_code = p_release_code for update;
end;
$$;

create or replace function public.verify_taxonomy_release(p_release_code text, p_verified_by text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform 1 from public.taxonomy_releases where release_code = p_release_code for update;
  update public.taxonomy_releases
  set status = 'VERIFIED', verified_by = p_verified_by, verified_at = now()
  where release_code = p_release_code and status = 'DRAFT';
  if not found then
    raise exception using errcode = '55000', message = 'A DRAFT taxonomy release is required';
  end if;
end;
$$;

create or replace function public.retire_taxonomy_release(p_release_code text, p_reason text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = '22023', message = 'Retirement reason is required';
  end if;
  perform 1 from public.taxonomy_releases where release_code = p_release_code for update;
  update public.taxonomy_releases
  set status = 'RETIRED', retired_at = now(), retirement_reason = p_reason
  where release_code = p_release_code and status = 'VERIFIED';
  if not found then
    raise exception using errcode = '55000', message = 'A VERIFIED taxonomy release is required';
  end if;
end;
$$;

create or replace function public.retire_taxonomy_concept(p_concept_id uuid, p_release text, p_reason text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform 1 from public.taxonomy_releases where release_code = p_release for update;
  update public.taxonomy_concepts
  set retired_in_release = p_release
  where concept_id = p_concept_id and retired_in_release is null;
  if not found then
    raise exception using errcode = '55000', message = 'Active taxonomy concept is required';
  end if;
end;
$$;

create or replace function public.retire_taxonomy_alias(p_alias_id uuid, p_release text, p_reason text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform 1 from public.taxonomy_releases where release_code = p_release for update;
  update public.taxonomy_aliases
  set retired_in_release = p_release
  where alias_id = p_alias_id and retired_in_release is null;
  if not found then
    raise exception using errcode = '55000', message = 'Active taxonomy alias is required';
  end if;
end;
$$;

create or replace function public.retire_taxonomy_relationship(p_relationship_id uuid, p_release text, p_reason text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform 1 from public.taxonomy_releases where release_code = p_release for update;
  update public.taxonomy_relationships
  set retired_in_release = p_release
  where relationship_id = p_relationship_id and retired_in_release is null;
  if not found then
    raise exception using errcode = '55000', message = 'Active taxonomy relationship is required';
  end if;
end;
$$;

create or replace function public.review_catalog_concept_mapping(
  p_mapping_id uuid,
  p_status public.mapping_status,
  p_reviewed_by text,
  p_verification_evidence_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('mapping:' || p_mapping_id::text, 0));
  perform 1 from public.catalog_concept_mappings where mapping_id = p_mapping_id for update;
  if p_status not in ('VERIFIED', 'REJECTED') then
    raise exception using errcode = '22023', message = 'Review status must be VERIFIED or REJECTED';
  end if;
  update public.catalog_concept_mappings
  set mapping_status = p_status,
      reviewed_by = p_reviewed_by,
      reviewed_at = now(),
      verification_evidence_id = p_verification_evidence_id
  where mapping_id = p_mapping_id and mapping_status = 'PROPOSED';
  if not found then
    raise exception using errcode = '55000', message = 'A PROPOSED catalog mapping is required';
  end if;
end;
$$;

create or replace function public.retire_catalog_concept_mapping(p_mapping_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform pg_advisory_xact_lock(hashtextextended('mapping:' || p_mapping_id::text, 0));
  perform 1 from public.catalog_concept_mappings where mapping_id = p_mapping_id for update;
  update public.catalog_concept_mappings
  set mapping_status = 'RETIRED', retired_at = now(), retirement_reason = p_reason
  where mapping_id = p_mapping_id and mapping_status = 'VERIFIED';
  if not found then
    raise exception using errcode = '55000', message = 'A VERIFIED catalog mapping is required';
  end if;
end;
$$;


create or replace function public.create_student(p_student_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  insert into public.students (student_id) values (p_student_id);
  perform private.lock_student_lifecycle(p_student_id);
  perform private.write_student_lifecycle_audit(p_student_id, 'students', p_student_id, 'CREATE');
  return p_student_id;
end;
$$;

create or replace function public.create_student_profile_version(
  p_student_id uuid,
  p_version_number integer
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_id uuid;
begin
  perform private.lock_student_lifecycle(p_student_id);
  insert into public.student_profile_versions (student_id, version_number)
  values (p_student_id, p_version_number)
  returning profile_version_id into v_id;
  perform private.write_student_lifecycle_audit(p_student_id, 'student_profile_versions', v_id, 'CREATE');
  return v_id;
end;
$$;

create or replace function public.freeze_student_profile_version(p_profile_version_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_student uuid;
  v_status public.profile_version_status;
  v_missing integer;
  v_hash text;
begin
  select student_id, status into v_student, v_status
  from public.student_profile_versions
  where profile_version_id = p_profile_version_id;
  if v_student is null then
    raise exception using errcode = '23503', message = 'Profile version does not exist';
  end if;
  perform private.lock_student_lifecycle(v_student);
  perform private.lock_student_owned_total_order(v_student);
  perform 1 from public.student_profile_versions
  where profile_version_id = p_profile_version_id for update;
  if v_status is distinct from 'DRAFT' then
    raise exception using errcode = '55000', message = 'A DRAFT profile version is required';
  end if;
  with required_scope(education_context_id, domain) as (
    select null::uuid, domain
    from unnest(array[
      'EDUCATION_HISTORY','TEST_HISTORY','EXPERIENCE_HISTORY',
      'SKILL_HISTORY','PREFERENCES','GOALS'
    ]::public.student_data_domain[]) as global_domain(domain)
    union all
    select d.student_degree_id, course_domain.domain
    from public.student_degrees d
    cross join unnest(array['COURSE_HISTORY','COURSE_MAPPING']::public.student_data_domain[]) as course_domain(domain)
    where d.profile_version_id = p_profile_version_id
    union all
    select null::uuid, course_domain.domain
    from unnest(array['COURSE_HISTORY','COURSE_MAPPING']::public.student_data_domain[]) as course_domain(domain)
    where not exists (
      select 1 from public.student_degrees d
      where d.profile_version_id = p_profile_version_id
    )
  )
  select count(*) into v_missing
  from required_scope expected
  where not exists (
    select 1 from public.student_data_completeness c
    where c.profile_version_id = p_profile_version_id
      and c.education_context_id is not distinct from expected.education_context_id
      and c.domain = expected.domain
  );
  if v_missing > 0 then
    raise exception 'Every required profile and education context requires explicit completeness';
  end if;
  v_hash := encode(extensions.digest(convert_to(p_profile_version_id::text, 'UTF8'), 'sha256'), 'hex');
  update public.student_profile_versions
  set status = 'FROZEN', snapshot_hash = v_hash, frozen_at = now()
  where profile_version_id = p_profile_version_id;
  perform private.write_student_lifecycle_audit(v_student, 'student_profile_versions', p_profile_version_id, 'FREEZE');
end;
$$;

create or replace function public.review_student_record_concept_mapping(
  p_mapping_id uuid,
  p_status public.mapping_status,
  p_reviewed_by text,
  p_student_evidence_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid;
begin
  select p.student_id into v_student
  from public.student_record_concept_mappings m
  join public.student_profile_versions p using (profile_version_id)
  where m.student_mapping_id = p_mapping_id;
  perform private.lock_student_lifecycle(v_student);
  perform 1 from public.student_record_concept_mappings where student_mapping_id = p_mapping_id for update;
  update public.student_record_concept_mappings
  set mapping_status = p_status,
      reviewed_by = p_reviewed_by,
      reviewed_at = now(),
      student_evidence_id = coalesce(p_student_evidence_id, student_evidence_id)
  where student_mapping_id = p_mapping_id and mapping_status = 'PROPOSED';
  if not found then
    raise exception using errcode = '55000', message = 'A PROPOSED student mapping is required';
  end if;
end;
$$;

create or replace function public.retire_student_record_concept_mapping(p_mapping_id uuid, p_reason text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid;
begin
  select p.student_id into v_student
  from public.student_record_concept_mappings m
  join public.student_profile_versions p using (profile_version_id)
  where m.student_mapping_id = p_mapping_id;
  perform private.lock_student_lifecycle(v_student);
  update public.student_record_concept_mappings
  set mapping_status = 'RETIRED', retired_at = now(), retirement_reason = p_reason
  where student_mapping_id = p_mapping_id and mapping_status = 'VERIFIED';
  if not found then
    raise exception using errcode = '55000', message = 'A VERIFIED student mapping is required';
  end if;
end;
$$;

create or replace function public.retire_student_feature_definition(p_definition_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  update public.student_feature_definitions
  set retired_at = now()
  where feature_definition_id = p_definition_id and retired_at is null;
  if not found then
    raise exception using errcode = '55000', message = 'An active student feature definition is required';
  end if;
end;
$$;

create or replace function public.create_fit_intent_set(
  p_profile_version_id uuid,
  p_version_number integer
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_id uuid;
begin
  v_student := private.student_id_from_profile(p_profile_version_id);
  perform private.lock_student_lifecycle(v_student);
  insert into public.fit_intent_sets (profile_version_id, version_number)
  values (p_profile_version_id, p_version_number)
  returning intent_set_id into v_id;
  perform private.write_student_lifecycle_audit(v_student, 'fit_intent_sets', v_id, 'CREATE');
  return v_id;
end;
$$;

create or replace function public.delete_student_data(
  p_student_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_code public.student_deletion_reason_code;
  v_class public.student_deletion_request_class;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Deletion reason is required';
  end if;
  perform private.lock_student_lifecycle(p_student_id);
  perform private.lock_student_owned_total_order(p_student_id);
  begin
    v_code := p_reason::public.student_deletion_reason_code;
    v_class := 'OPERATIONAL';
  exception when invalid_text_representation then
    v_code := 'TEST_LIFECYCLE';
    v_class := 'TEST';
  end;
  insert into private.student_deletion_authorizations (transaction_id, student_id, executor_role)
  values (txid_current(), p_student_id, 'foundation_student_executor');
  delete from public.students where student_id = p_student_id;
  if not found then
    raise exception 'Student % does not exist', p_student_id;
  end if;
  perform private.close_student_owned_rows(p_student_id);
  insert into public.student_deletion_tombstones (
    legacy_deletion_reason, reason_code, request_class
  ) values (
    'MIGRATED_TO_REASON_CODE', v_code, v_class
  );
  delete from private.student_deletion_authorizations
  where transaction_id = txid_current() and student_id = p_student_id;
end;
$$;


create or replace function public.start_eligibility_evaluation(
  p_profile_version_id uuid,
  p_rule_set_id uuid,
  p_taxonomy_release_code text,
  p_evaluator_name text,
  p_evaluator_version text,
  p_evaluator_build_hash text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_student uuid;
  v_hash text;
  v_id uuid;
begin
  select student_id, snapshot_hash into v_student, v_hash
  from public.student_profile_versions
  where profile_version_id = p_profile_version_id;
  perform private.lock_student_lifecycle(v_student);
  perform private.lock_student_owned_total_order(v_student);
  insert into public.eligibility_evaluations (
    profile_version_id, rule_set_id, taxonomy_release_code,
    evaluator_name, evaluator_version, evaluator_build_hash,
    input_schema_version, profile_snapshot_hash
  ) values (
    p_profile_version_id, p_rule_set_id, p_taxonomy_release_code,
    p_evaluator_name, p_evaluator_version, p_evaluator_build_hash,
    'eligibility-v0.1', v_hash
  ) returning evaluation_id into v_id;
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_evaluations', v_id, 'START');
  return v_id;
end;
$$;

create or replace function public.guard_evaluation_update()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if tg_op = 'DELETE'
     and private.student_privacy_delete_allowed() then
    return old;
  end if;
  if tg_op = 'UPDATE'
     and current_user = 'foundation_evaluation_executor'
     and old.evaluation_state = 'BUILDING' then
    if new.evaluation_state = 'COMPLETED' then
      return new;
    end if;
    if new.evaluation_state = 'BUILDING'
       and old.inputs_sealed_at is null
       and new.inputs_sealed_at is not null then
      return new;
    end if;
  end if;
  raise exception using errcode = '55000',
    message = 'Evaluations are append-only and finalize through finalize_eligibility_evaluation()';
end;
$$;

create or replace function public.guard_fit_evaluation_row()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if tg_op = 'DELETE'
     and private.student_privacy_delete_allowed() then
    return old;
  end if;
  if tg_op = 'UPDATE'
     and current_user = 'foundation_evaluation_executor'
     and old.evaluation_state = 'BUILDING'
     and new.evaluation_state in ('BUILDING', 'COMPLETED') then
    return new;
  end if;
  raise exception using errcode = '55000',
    message = 'Fit evaluations are immutable and finalize through finalize_fit_evaluation()';
end;
$$;

create or replace function public.seal_eligibility_evaluation_inputs(p_evaluation_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid;
begin
  select p.student_id into v_student
  from public.eligibility_evaluations e
  join public.student_profile_versions p using (profile_version_id)
  where e.evaluation_id = p_evaluation_id;
  perform private.lock_student_lifecycle(v_student);
  update public.eligibility_evaluations
  set inputs_sealed_at = now()
  where evaluation_id = p_evaluation_id
    and evaluation_state = 'BUILDING'
    and inputs_sealed_at is null;
  if not found then
    raise exception using errcode = '55000',
      message = 'A BUILDING unsealed eligibility evaluation is required';
  end if;
end;
$$;

create or replace function public.review_student_lifecycle_before_finalize()
returns void language sql as $$ select 1; $$;

-- Harden existing select/accept/retire/finalize search_path and add locks/applicability.
create or replace function public.select_field_observation(
  p_observation_id uuid,
  p_selected_by text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  observation public.field_observations%rowtype;
  v_table_name text;
  v_primary_key text;
  v_assertion public.evidence_applicability_assertions%rowtype;
  v_matched_head uuid;
  v_prog uuid;
  v_ver uuid;
  v_prog_key text;
  v_ver_key text;
begin
  select * into observation from public.field_observations where observation_id = p_observation_id;
  if not found then
    raise exception 'Observation % does not exist', p_observation_id;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'catalog:' || observation.record_type::text || ':' || observation.record_id::text, 0));
  execute format(
    'select 1 from public.%I where %I = $1 for update',
    public.catalog_table_name(observation.record_type),
    public.catalog_primary_key(observation.record_type)
  ) using observation.record_id;
  v_table_name := public.catalog_table_name(observation.record_type);
  v_primary_key := public.catalog_primary_key(observation.record_type);
  perform public.assert_catalog_field(observation.record_type, observation.field_name);
  select a.* into v_assertion
  from public.field_observation_applicability l
  join public.evidence_applicability_assertions a using (assertion_id)
  where l.observation_id = observation.observation_id;
  -- LEGACY_UNASSERTED and unheaded rows are historical only. scope_id IS NULL
  -- is not permission to search for or attach a later head.
  if not found
     or v_assertion.applicability_status = 'LEGACY_UNASSERTED'
     or v_assertion.scope_id is null then
    raise exception using errcode = '55000',
      message = 'New canonical selection requires headed REVIEWED_APPLICABLE authority',
      hint = 'legacy_unasserted_rejected';
  end if;
  perform 1 from public.evidence_applicability_scopes s
  where s.scope_id = v_assertion.scope_id
  for update;
  select o_program_id, o_version_id, o_program_key, o_version_key
    into v_prog, v_ver, v_prog_key, v_ver_key
  from public.derive_program_scope(observation.record_type, observation.record_id);
  select h.assertion_id into v_matched_head
  from public.evidence_applicability_scopes s
  join public.evidence_applicability_heads h
    on h.scope_id = s.scope_id
   and h.assertion_id = v_assertion.assertion_id
  join public.evidence_applicability_assertions a
    on a.assertion_id = h.assertion_id
  where s.scope_id = v_assertion.scope_id
    and a.applicability_status = 'REVIEWED_APPLICABLE'
    and s.evidence_id is not distinct from observation.evidence_id
    and s.record_type = observation.record_type
    and s.record_id = observation.record_id
    and s.field_name = observation.field_name
    and s.program_scope_key = v_prog_key
    and s.program_version_scope_key = v_ver_key
    and s.granularity_scope = 'UNSPECIFIED'
    and s.population_scope_code = 'UNSPECIFIED'
    and s.cycle_scope_code = 'UNSPECIFIED';
  if v_matched_head is null then
    raise exception using errcode = '55000',
      message = 'New canonical selection requires headed REVIEWED_APPLICABLE authority',
      hint = 'legacy_unasserted_rejected';
  end if;
  execute format(
    'update public.%I
       set %I = case
         when $1 = ''KNOWN''::public.knowledge_status then (
           select %I from jsonb_populate_record(null::public.%I, jsonb_build_object(%L, $2))
         ) else null end
     where %I = $3',
    v_table_name, observation.field_name, observation.field_name, v_table_name,
    observation.field_name, v_primary_key
  ) using observation.knowledge_status, observation.observed_value, observation.record_id;
  insert into public.canonical_field_selections (
    record_type, record_id, field_name, observation_id, selected_at, selected_by
  ) values (
    observation.record_type, observation.record_id, observation.field_name,
    observation.observation_id, now(), p_selected_by
  )
  on conflict (record_type, record_id, field_name)
  do update set
    observation_id = excluded.observation_id,
    selected_at = excluded.selected_at,
    selected_by = excluded.selected_by;
end;
$$;


create or replace function public.create_university(p_row public.universities)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'universities');
  perform public.insert_composite('public.universities'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_school(p_row public.schools)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'schools');
  perform public.insert_composite('public.schools'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_program(p_row public.programs)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'programs');
  perform public.insert_composite('public.programs'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_program_school(p_row public.program_schools)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_schools');
  perform public.insert_composite('public.program_schools'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_program_version(p_row public.program_versions)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_versions');
  perform public.insert_composite('public.program_versions'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_program_admission(p_row public.program_admissions)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_admissions');
  perform public.insert_composite('public.program_admissions'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_program_prerequisite(p_row public.program_prerequisites)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_prerequisites');
  perform public.insert_composite('public.program_prerequisites'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_program_course(p_row public.program_courses)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_courses');
  perform public.insert_composite('public.program_courses'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_program_cost(p_row public.program_costs)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_costs');
  perform public.insert_composite('public.program_costs'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_program_deadline(p_row public.program_deadlines)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_deadlines');
  perform public.insert_composite('public.program_deadlines'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_taxonomy_concept(p_row public.taxonomy_concepts)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'taxonomy_concepts');
  perform public.insert_composite('public.taxonomy_concepts'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_taxonomy_alias(p_row public.taxonomy_aliases)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'taxonomy_aliases');
  perform public.insert_composite('public.taxonomy_aliases'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_taxonomy_relationship(p_row public.taxonomy_relationships)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'taxonomy_relationships');
  perform public.insert_composite('public.taxonomy_relationships'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.propose_catalog_concept_mapping(p_row public.catalog_concept_mappings)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'catalog_concept_mappings');
  perform public.insert_composite('public.catalog_concept_mappings'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_requirement_rule_set(p_row public.program_requirement_rule_sets)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_requirement_rule_sets');
  perform public.insert_composite('public.program_requirement_rule_sets'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_requirement_node(p_row public.program_requirement_nodes)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_requirement_nodes');
  perform public.insert_composite('public.program_requirement_nodes'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.append_program_derived_feature(p_row public.program_derived_features)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_derived_features');
  perform public.insert_composite('public.program_derived_features'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.create_student_feature_definition(p_row public.student_feature_definitions)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_feature_definitions');
  perform public.insert_composite('public.student_feature_definitions'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_contract_release(p_row public.fit_contract_releases)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_contract_releases');
  perform public.insert_composite('public.fit_contract_releases'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_semantic_source_class(p_row public.fit_semantic_source_classes)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_semantic_source_classes');
  perform public.insert_composite('public.fit_semantic_source_classes'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_evaluator_build(p_row public.fit_evaluator_builds)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_evaluator_builds');
  perform public.insert_composite('public.fit_evaluator_builds'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_dimension_method(p_row public.fit_dimension_methods)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_dimension_methods');
  perform public.insert_composite('public.fit_dimension_methods'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_method_source_class_policy(p_row public.fit_method_source_class_policies)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_method_source_class_policies');
  perform public.insert_composite('public.fit_method_source_class_policies'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_mapping_relation_definition(p_row public.fit_mapping_relation_definitions)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_mapping_relation_definitions');
  perform public.insert_composite('public.fit_mapping_relation_definitions'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_method_mapping_relation_policy(p_row public.fit_method_mapping_relation_policies)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_method_mapping_relation_policies');
  perform public.insert_composite('public.fit_method_mapping_relation_policies'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_signal_type(p_row public.fit_signal_types)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_signal_types');
  perform public.insert_composite('public.fit_signal_types'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_method_input_policy(p_row public.fit_method_input_policies)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_method_input_policies');
  perform public.insert_composite('public.fit_method_input_policies'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_method_program_field_policy(p_row public.fit_method_program_field_policies)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_method_program_field_policies');
  perform public.insert_composite('public.fit_method_program_field_policies'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_reason_definition(p_row public.fit_reason_definitions)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_reason_definitions');
  perform public.insert_composite('public.fit_reason_definitions'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_financial_normalization_method(p_row public.fit_financial_normalization_methods)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_financial_normalization_methods');
  perform public.insert_composite('public.fit_financial_normalization_methods'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_context_claim_definition(p_row public.fit_context_claim_definitions)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_context_claim_definitions');
  perform public.insert_composite('public.fit_context_claim_definitions'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_context_claim(p_row public.fit_context_claims)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_context_claims');
  perform public.insert_composite('public.fit_context_claims'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_context_claim_observation(p_row public.fit_context_claim_observations)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_context_claim_observations');
  perform public.insert_composite('public.fit_context_claim_observations'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_context_concept_mapping(p_row public.fit_context_concept_mappings)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_context_concept_mappings');
  perform public.insert_composite('public.fit_context_concept_mappings'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_requirement_node_source(p_row public.program_requirement_node_sources)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_requirement_node_sources');
  perform public.insert_composite('public.program_requirement_node_sources'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_requirement_node_mapping(p_row public.program_requirement_node_mappings)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'program_requirement_node_mappings');
  perform public.insert_composite('public.program_requirement_node_mappings'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.propose_student_record_concept_mapping(p_row public.student_record_concept_mappings)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_record_concept_mappings');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_record_concept_mappings'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.append_student_derived_feature_value(p_row public.student_derived_feature_values)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_derived_feature_values');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_derived_feature_values'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_student_data_completeness(p_row public.student_data_completeness)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_data_completeness');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_data_completeness'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_student_evidence_item(p_row public.student_evidence_items)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_evidence_items');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_evidence_items'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_student_degree(p_row public.student_degrees)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_degrees');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_degrees'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_student_course(p_row public.student_courses)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_courses');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_courses'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_student_test_score(p_row public.student_test_scores)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_test_scores');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_test_scores'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_student_experience(p_row public.student_experiences)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_experiences');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_experiences'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_student_skill(p_row public.student_skills)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_skills');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_skills'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_student_experience_skill(p_row public.student_experience_skills)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_experience_skills');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_experience_skills'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_student_goal(p_row public.student_goals)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_goals');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_goals'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_student_preference(p_row public.student_preferences)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'student_preferences');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.student_preferences'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_intent_declaration(p_row public.fit_intent_declarations)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_intent_declarations');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_intent_declarations'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_intent_validation_issue(p_row public.fit_intent_validation_issues)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_intent_validation_issues');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_intent_validation_issues'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_intent_taxonomy_target(p_row public.fit_intent_taxonomy_targets)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_intent_taxonomy_targets');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_intent_taxonomy_targets'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_intent_location_constraint(p_row public.fit_intent_location_constraints)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_intent_location_constraints');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_intent_location_constraints'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_intent_delivery_constraint(p_row public.fit_intent_delivery_constraints)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_intent_delivery_constraints');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_intent_delivery_constraints'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_intent_financial_constraint(p_row public.fit_intent_financial_constraints)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_intent_financial_constraints');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_intent_financial_constraints'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_intent_duration_constraint(p_row public.fit_intent_duration_constraints)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_intent_duration_constraints');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_intent_duration_constraints'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_intent_program_feature_constraint(p_row public.fit_intent_program_feature_constraints)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_intent_program_feature_constraints');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_intent_program_feature_constraints'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_student_access_context(p_row private.fit_student_access_contexts)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_student_access_contexts');

  perform private.lock_student_from_row(to_jsonb(p_row));
  perform public.insert_composite('private.fit_student_access_contexts'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_manifest_degree(p_row public.eligibility_manifest_degrees)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_manifest_degrees');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_manifest_degrees'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_manifest_course(p_row public.eligibility_manifest_courses)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_manifest_courses');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_manifest_courses'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_manifest_test_score(p_row public.eligibility_manifest_test_scores)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_manifest_test_scores');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_manifest_test_scores'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_manifest_student_mapping(p_row public.eligibility_manifest_student_mappings)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_manifest_student_mappings');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_manifest_student_mappings'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_manifest_completeness(p_row public.eligibility_manifest_completeness)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_manifest_completeness');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_manifest_completeness'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_manifest_student_evidence(p_row public.eligibility_manifest_student_evidence)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_manifest_student_evidence');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_manifest_student_evidence'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_manifest_catalog_source(p_row public.eligibility_manifest_catalog_sources)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_manifest_catalog_sources');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_manifest_catalog_sources'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_manifest_catalog_mapping(p_row public.eligibility_manifest_catalog_mappings)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_manifest_catalog_mappings');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_manifest_catalog_mappings'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_manifest_taxonomy_concept(p_row public.eligibility_manifest_taxonomy_concepts)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_manifest_taxonomy_concepts');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_manifest_taxonomy_concepts'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_requirement_result(p_row public.eligibility_requirement_results)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_requirement_results');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_requirement_results'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_course_match(p_row public.eligibility_course_matches)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_course_matches');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_course_matches'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_eligibility_test_match(p_row public.eligibility_test_matches)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_test_matches');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_test_matches'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_evaluation_method(p_row public.fit_evaluation_methods)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_evaluation_methods');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_evaluation_methods'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_item(p_row public.fit_manifest_items)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_items');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_items'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_intent_declaration(p_row public.fit_manifest_intent_declarations)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_intent_declarations');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_intent_declarations'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_student_access_context(p_row public.fit_manifest_student_access_contexts)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_student_access_contexts');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_student_access_contexts'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_phase2_goal(p_row public.fit_manifest_phase2_goals)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_phase2_goals');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_phase2_goals'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_phase2_preference(p_row public.fit_manifest_phase2_preferences)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_phase2_preferences');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_phase2_preferences'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_phase2_course(p_row public.fit_manifest_phase2_courses)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_phase2_courses');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_phase2_courses'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_phase2_completeness(p_row public.fit_manifest_phase2_completeness)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_phase2_completeness');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_phase2_completeness'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_phase2_mapping(p_row public.fit_manifest_phase2_mappings)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_phase2_mappings');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_phase2_mappings'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_catalog_observation(p_row public.fit_manifest_catalog_observations)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_catalog_observations');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_catalog_observations'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_catalog_mapping(p_row public.fit_manifest_catalog_mappings)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_catalog_mappings');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_catalog_mappings'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_taxonomy_concept(p_row public.fit_manifest_taxonomy_concepts)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_taxonomy_concepts');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_taxonomy_concepts'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_context_claim_selection(p_row public.fit_manifest_context_claim_selections)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_context_claim_selections');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_context_claim_selections'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_context_mapping(p_row public.fit_manifest_context_mappings)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_context_mappings');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_context_mappings'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_student_field_use(p_row public.fit_manifest_student_field_uses)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_student_field_uses');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_student_field_uses'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_financial_normalization(p_row public.fit_financial_normalizations)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_financial_normalizations');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_financial_normalizations'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_manifest_financial_normalization(p_row public.fit_manifest_financial_normalizations)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_manifest_financial_normalizations');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_manifest_financial_normalizations'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_input_domain_state(p_row public.fit_input_domain_states)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_input_domain_states');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_input_domain_states'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_dimension_result(p_row public.fit_dimension_results)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_dimension_results');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_dimension_results'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_signal(p_row public.fit_signals)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_signals');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_signals'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_signal_evidence(p_row public.fit_signal_evidence)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_signal_evidence');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_signal_evidence'::regclass, to_jsonb(p_row));
end;
$$;


create or replace function public.insert_fit_dimension_reason(p_row public.fit_dimension_reasons)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  perform public.reject_terminal_insert(to_jsonb(p_row), 'fit_dimension_reasons');

  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.fit_dimension_reasons'::regclass, to_jsonb(p_row));
end;
$$;


-- Extra lifecycle guards that 001-011 cannot express.
create or replace function public.prevent_source_mutation()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'Source revisions are immutable';
  end if;
  raise exception using errcode = '55000', message = 'Source revisions are immutable';
end;
$$;
create or replace function public.fill_source_identity_on_owner_insert()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $$
declare v_identity uuid;
begin
  if new.source_identity_id is not null then
    return new;
  end if;
  if current_user = 'foundation_catalog_executor' then
    raise exception using errcode = '55000',
      message = 'Executor source inserts must supply source_identity_id';
  end if;
  v_identity := extensions.gen_random_uuid();
  insert into public.source_identities (source_identity_id, canonical_publisher, current_source_id)
  values (v_identity, new.publisher, new.source_id);
  new.source_identity_id := v_identity;
  new.revision_number := coalesce(new.revision_number, 1);
  new.revision_reason := coalesce(new.revision_reason, 'INITIAL');
  new.retrieval_content_hash := coalesce(
    new.retrieval_content_hash,
    encode(extensions.digest(convert_to(new.url, 'UTF8'), 'sha256'), 'hex')
  );
  return new;
end;
$$;
drop trigger if exists sources_fill_identity on public.sources;
create trigger sources_fill_identity
before insert on public.sources
for each row execute function public.fill_source_identity_on_owner_insert();
drop trigger if exists sources_immutable on public.sources;
create trigger sources_immutable
before update or delete on public.sources
for each row execute function public.prevent_source_mutation();

create or replace function public.prevent_program_derived_mutation()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $$
begin
  raise exception using errcode = '55000',
    message = 'program_derived_features is append-only';
end;
$$;
drop trigger if exists program_derived_features_immutable on public.program_derived_features;
create trigger program_derived_features_immutable
before update or delete on public.program_derived_features
for each row execute function public.prevent_program_derived_mutation();

create or replace function public.validate_program_derived_supersession()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $$
declare v_prior public.program_derived_features%rowtype;
begin
  if new.supersedes_derived_feature_id is null then
    return new;
  end if;
  select * into v_prior from public.program_derived_features
  where derived_feature_id = new.supersedes_derived_feature_id;
  if v_prior.program_version_id is distinct from new.program_version_id
     or v_prior.feature_name is distinct from new.feature_name then
    raise exception using errcode = '55000',
      message = 'Derived-feature supersession must reference the same program version and feature name';
  end if;
  if exists (
    select 1 from public.program_derived_features
    where supersedes_derived_feature_id = new.supersedes_derived_feature_id
  ) then
    raise exception using errcode = '55000',
      message = 'Derived-feature head already has a successor',
      hint = 'derived_feature_supersession_conflict';
  end if;
  return new;
end;
$$;
drop trigger if exists program_derived_features_supersede on public.program_derived_features;
create trigger program_derived_features_supersede
before insert on public.program_derived_features
for each row execute function public.validate_program_derived_supersession();

create or replace function public.guard_complete_program_has_primary()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $$
declare
  v_program uuid;
  v_state public.program_foundation_state;
  v_retired timestamptz;
  v_count integer;
begin
  v_program := coalesce(new.program_id, old.program_id);
  if tg_table_name = 'programs' then
    v_program := coalesce(new.program_id, old.program_id);
    v_state := coalesce(new.foundation_state, old.foundation_state);
    v_retired := coalesce(new.retired_at, old.retired_at);
  else
    select foundation_state, retired_at into v_state, v_retired
    from public.programs where program_id = v_program;
  end if;
  if v_state = 'COMPLETE' and v_retired is null then
    select count(*) into v_count from public.program_schools
    where program_id = v_program
      and relationship_role = 'PRIMARY_ADMINISTRATIVE'
      and retired_at is null;
    if v_count <> 1 then
      raise exception using errcode = '55000',
        message = 'A non-retired COMPLETE program must have exactly one active primary administrative school';
    end if;
  end if;
  return coalesce(new, old);
end;
$$;
drop trigger if exists programs_primary_at_least_one on public.programs;
create constraint trigger programs_primary_at_least_one
after insert or update on public.programs
deferrable initially deferred
for each row execute function public.guard_complete_program_has_primary();
drop trigger if exists program_schools_primary_at_least_one on public.program_schools;
create constraint trigger program_schools_primary_at_least_one
after insert or update or delete on public.program_schools
deferrable initially deferred
for each row execute function public.guard_complete_program_has_primary();

create or replace function public.guard_taxonomy_release_lifecycle()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $$
begin
  if tg_op = 'DELETE' then
    raise exception using errcode = '55000', message = 'Taxonomy releases are historical';
  end if;
  if tg_table_name = 'taxonomy_releases' then
    if current_user is distinct from 'foundation_catalog_executor' then
      if (to_jsonb(new) - 'status' - 'verified_by' - 'verified_at' - 'retired_at' - 'retirement_reason')
         is distinct from (to_jsonb(old) - 'status' - 'verified_by' - 'verified_at' - 'retired_at' - 'retirement_reason')
         or new.status is distinct from old.status then
        raise exception using errcode = '55000', message = 'Taxonomy releases are immutable';
      end if;
    else
      if new.release_code is distinct from old.release_code
         or new.published_at is distinct from old.published_at then
        raise exception using errcode = '55000', message = 'Taxonomy release identity is immutable';
      end if;
    end if;
    return new;
  end if;
  if new.canonical_key is distinct from old.canonical_key
     or new.concept_kind is distinct from old.concept_kind
     or new.introduced_in_release is distinct from old.introduced_in_release then
    raise exception 'Taxonomy semantic identity is immutable; retire and create a new key';
  end if;
  return new;
end;
$$;
drop trigger if exists taxonomy_releases_immutable on public.taxonomy_releases;
create trigger taxonomy_releases_immutable
before update or delete on public.taxonomy_releases
for each row execute function public.guard_taxonomy_release_lifecycle();
drop trigger if exists taxonomy_concepts_identity_guard on public.taxonomy_concepts;
create trigger taxonomy_concepts_identity_guard
before update on public.taxonomy_concepts
for each row execute function public.guard_taxonomy_release_lifecycle();

create or replace function public.guard_mapping_terminal_insert()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $$
begin
  if new.mapping_status in ('VERIFIED', 'REJECTED', 'RETIRED') then
    raise exception using errcode = '55000',
      message = 'Terminal mapping states cannot be inserted',
      hint = 'terminal_insert_forbidden';
  end if;
  return new;
end;
$$;
drop trigger if exists catalog_mappings_no_terminal_insert on public.catalog_concept_mappings;
create trigger catalog_mappings_no_terminal_insert
before insert on public.catalog_concept_mappings
for each row execute function public.guard_mapping_terminal_insert();
drop trigger if exists student_mappings_no_terminal_insert on public.student_record_concept_mappings;
create trigger student_mappings_no_terminal_insert
before insert on public.student_record_concept_mappings
for each row execute function public.guard_mapping_terminal_insert();
drop trigger if exists fit_context_mappings_no_terminal_insert on public.fit_context_concept_mappings;
create trigger fit_context_mappings_no_terminal_insert
before insert on public.fit_context_concept_mappings
for each row execute function public.guard_mapping_terminal_insert();

create or replace function public.guard_mapping_status_executor()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, extensions
as $$
begin
  if old.mapping_status in ('REJECTED', 'RETIRED') then
    raise exception using errcode = '55000',
      message = 'Rejected/retired mappings are immutable';
  end if;
  if old.mapping_status = 'VERIFIED' then
    if new.mapping_status = 'RETIRED'
       and current_user in ('foundation_catalog_executor', 'foundation_student_executor')
       and (to_jsonb(new) - 'mapping_status' - 'retired_at' - 'retirement_reason' - 'updated_at')
         is not distinct from
          (to_jsonb(old) - 'mapping_status' - 'retired_at' - 'retirement_reason' - 'updated_at')
    then
      return new;
    end if;
    raise exception using errcode = '55000',
      message = 'Verified mapping payload is immutable';
  end if;
  if new.mapping_status is distinct from old.mapping_status
     and current_user not in ('foundation_catalog_executor', 'foundation_student_executor') then
    raise exception using errcode = '55000',
      message = 'Mapping status changes require the controlled entry point';
  end if;
  return new;
end;
$$;
drop trigger if exists catalog_mappings_status_executor on public.catalog_concept_mappings;
create trigger catalog_mappings_status_executor
before update on public.catalog_concept_mappings
for each row execute function public.guard_mapping_status_executor();
drop trigger if exists student_mappings_status_executor on public.student_record_concept_mappings;
create trigger student_mappings_status_executor
before update on public.student_record_concept_mappings
for each row execute function public.guard_mapping_status_executor();

create or replace function public.guard_eligibility_terminal_insert()
returns trigger
language plpgsql
security invoker
as $$
begin
  if new.evaluation_state = 'COMPLETED' then
    raise exception using errcode = '55000',
      message = 'COMPLETED evaluations cannot be inserted',
      hint = 'terminal_insert_forbidden';
  end if;
  return new;
end;
$$;
drop trigger if exists eligibility_no_terminal_insert on public.eligibility_evaluations;
drop trigger if exists a_eligibility_no_terminal_insert on public.eligibility_evaluations;
create trigger a_eligibility_no_terminal_insert
before insert on public.eligibility_evaluations
for each row execute function public.guard_eligibility_terminal_insert();
drop trigger if exists fit_eval_no_terminal_insert on public.fit_evaluations;
drop trigger if exists a_fit_eval_no_terminal_insert on public.fit_evaluations;
create trigger a_fit_eval_no_terminal_insert
before insert on public.fit_evaluations
for each row execute function public.guard_eligibility_terminal_insert();

create or replace function public.guard_profile_freeze_executor()
returns trigger
language plpgsql
security invoker
as $$
begin
  if new.status is distinct from old.status
     and current_user is distinct from 'foundation_student_executor' then
    raise exception using errcode = '55000',
      message = 'Profile freeze requires freeze_student_profile_version()';
  end if;
  return new;
end;
$$;
drop trigger if exists student_profile_freeze_executor on public.student_profile_versions;
create trigger student_profile_freeze_executor
before update of status on public.student_profile_versions
for each row execute function public.guard_profile_freeze_executor();

-- Inject student-lifecycle lock into existing 9A evaluation/intent functions after GUC rewrite.
do $inject$
declare
  r record;
  def text;
  lock_sql text;
begin
  for r in
    select p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as args,
           pg_get_functiondef(p.oid) as def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'finalize_eligibility_evaluation',
        'freeze_fit_intent_set',
        'start_fit_evaluation',
        'seal_fit_evaluation_inputs',
        'finalize_fit_evaluation',
        'authorize_fit_evaluation_assembly'
      )
  loop
    lock_sql := $lk$
  perform private.lock_student_lifecycle(
    coalesce(
      (select p.student_id from public.student_profile_versions p
         join public.eligibility_evaluations e using (profile_version_id)
        where e.evaluation_id = coalesce($1, $1)),
      (select p.student_id from public.student_profile_versions p
         join public.fit_evaluations e using (profile_version_id)
        where e.evaluation_id = coalesce($1, $1)),
      (select p.student_id from public.student_profile_versions p
         join public.fit_intent_sets i using (profile_version_id)
        where i.intent_set_id = coalesce($1, $1)),
      (select student_id from public.student_profile_versions where profile_version_id = coalesce($1, $1))
    )
  );
$lk$;
    if r.proname = 'finalize_eligibility_evaluation' then
      lock_sql := $lk$
  perform private.lock_student_lifecycle((
    select p.student_id from public.eligibility_evaluations e
    join public.student_profile_versions p using (profile_version_id)
    where e.evaluation_id = p_evaluation_id
  ));
  perform private.lock_student_owned_total_order((
    select p.student_id from public.eligibility_evaluations e
    join public.student_profile_versions p using (profile_version_id)
    where e.evaluation_id = p_evaluation_id
  ));
  if exists (
    select 1 from public.eligibility_evaluations
    where evaluation_id = p_evaluation_id and inputs_sealed_at is null
  ) then
    raise exception using errcode = '55000',
      message = 'Eligibility inputs must be sealed before finalization';
  end if;
$lk$;
    elsif r.proname = 'freeze_fit_intent_set' then
      lock_sql := $lk$
  perform private.lock_student_lifecycle((
    select p.student_id from public.fit_intent_sets i
    join public.student_profile_versions p using (profile_version_id)
    where i.intent_set_id = p_intent_set_id
  ));
  perform private.lock_student_owned_total_order((
    select p.student_id from public.fit_intent_sets i
    join public.student_profile_versions p using (profile_version_id)
    where i.intent_set_id = p_intent_set_id
  ));
$lk$;
    elsif r.proname in ('start_fit_evaluation') then
      lock_sql := $lk$
  perform private.lock_student_lifecycle((
    select student_id from public.student_profile_versions
    where profile_version_id = p_profile_version_id
  ));
  perform private.lock_student_owned_total_order((
    select student_id from public.student_profile_versions
    where profile_version_id = p_profile_version_id
  ));
$lk$;
    elsif r.proname in ('seal_fit_evaluation_inputs', 'finalize_fit_evaluation', 'authorize_fit_evaluation_assembly') then
      lock_sql := $lk$
  perform private.lock_student_lifecycle((
    select p.student_id from public.fit_evaluations e
    join public.student_profile_versions p using (profile_version_id)
    where e.evaluation_id = p_evaluation_id
  ));
  perform private.lock_student_owned_total_order((
    select p.student_id from public.fit_evaluations e
    join public.student_profile_versions p using (profile_version_id)
    where e.evaluation_id = p_evaluation_id
  ));
$lk$;
    end if;
    def := r.def;
    if def !~* $re$AS \$function\$[\s\S]*?\nbegin\n$re$ then
      raise exception using errcode = '55000',
        message = format('Could not inject student lock into %s', r.proname);
    end if;
    def := regexp_replace(
      def,
      $re$(AS \$function\$[\s\S]*?\n)begin\n$re$,
      E'\\1begin\n' || lock_sql,
      'i'
    );
    execute def;
  end loop;
end;
$inject$;


do $roles$
declare
  r text;
  v_is_superuser boolean;
  v_has_admin_membership boolean;
begin
  select rolsuper
  into v_is_superuser
  from pg_roles
  where rolname = current_user;

  foreach r in array array[
    'foundation_catalog_executor',
    'foundation_student_executor',
    'foundation_evaluation_executor'
  ]
  loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format(
        'create role %I nologin noinherit nosuperuser nocreatedb nocreaterole nobypassrls noreplication',
        r
      );
    else
      execute format('alter role %I nologin noinherit nosuperuser nocreatedb nocreaterole nobypassrls noreplication', r);
    end if;

    select exists (
      select 1
      from pg_auth_members m
      join pg_roles granted_role on granted_role.oid = m.roleid
      join pg_roles member_role on member_role.oid = m.member
      where granted_role.rolname = r
        and member_role.rolname = current_user
        and m.admin_option
    )
    into v_has_admin_membership;

    if current_setting('server_version_num')::integer >= 160000
       and not v_is_superuser
       and v_has_admin_membership
    then
      -- PostgreSQL 16+ automatically grants a non-superuser CREATEROLE
      -- creator ADMIN TRUE / SET FALSE / INHERIT FALSE. Re-granting ADMIN
      -- back to that same creator is a prohibited grant cycle. Add the
      -- SET/INHERIT membership required for ownership transfer while
      -- retaining the bootstrap-superuser ADMIN membership.
      execute format(
        'grant %I to %I with admin false, inherit true, set true',
        r,
        current_user
      );
    else
      -- PostgreSQL 15 and superuser installs retain the frozen grant path.
      execute format('grant %I to %I with admin option', r, current_user);
    end if;
  end loop;
end;
$roles$;

grant usage on schema public, extensions to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
grant usage on schema private to foundation_student_executor, foundation_evaluation_executor;

-- Temporary schema CREATE required before ALTER FUNCTION OWNER (revoked after transfer).
grant create on schema public to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
grant create on schema private to foundation_student_executor, foundation_evaluation_executor;

do $dml$
declare t text;
begin
  foreach t in array array['universities',
    'schools',
    'programs',
    'program_schools',
    'program_versions',
    'program_admissions',
    'program_prerequisites',
    'program_courses',
    'program_costs',
    'program_deadlines',
    'source_identities',
    'sources',
    'evidence_items',
    'field_observations',
    'evidence_applicability_scopes',
    'evidence_applicability_assertions',
    'evidence_applicability_heads',
    'field_observation_applicability',
    'canonical_field_selections',
    'taxonomy_releases',
    'taxonomy_concepts',
    'taxonomy_aliases',
    'taxonomy_relationships',
    'catalog_concept_mappings',
    'program_requirement_rule_sets',
    'program_requirement_nodes',
    'program_requirement_node_sources',
    'program_requirement_node_mappings',
    'program_derived_features',
    'student_feature_definitions',
    'fit_contract_releases',
    'fit_semantic_source_classes',
    'fit_evaluator_builds',
    'fit_dimension_methods',
    'fit_method_source_class_policies',
    'fit_mapping_relation_definitions',
    'fit_method_mapping_relation_policies',
    'fit_signal_types',
    'fit_method_input_policies',
    'fit_method_program_field_policies',
    'fit_reason_definitions',
    'fit_financial_normalization_methods',
    'fit_context_claim_definitions',
    'fit_context_claims',
    'fit_context_claim_observations',
    'fit_context_claim_selection_history',
    'fit_context_claim_selections',
    'fit_context_concept_mappings',
    'external_metrics']
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=t) then
      execute format('grant select, insert, update, delete on public.%I to foundation_catalog_executor', t);
    end if;
  end loop;
  foreach t in array array['students',
    'student_profile_versions',
    'student_data_completeness',
    'student_evidence_items',
    'student_degrees',
    'student_courses',
    'student_test_scores',
    'student_experiences',
    'student_skills',
    'student_experience_skills',
    'student_goals',
    'student_preferences',
    'student_record_concept_mappings',
    'student_derived_feature_values',
    'student_deletion_tombstones',
    'fit_intent_sets',
    'fit_intent_declarations',
    'fit_intent_validation_issues',
    'fit_intent_taxonomy_targets',
    'fit_intent_location_constraints',
    'fit_intent_delivery_constraints',
    'fit_intent_financial_constraints',
    'fit_intent_duration_constraints',
    'fit_intent_program_feature_constraints']
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=t) then
      execute format('grant select, insert, update, delete on public.%I to foundation_student_executor', t);
    end if;
  end loop;
  foreach t in array array['eligibility_evaluations',
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
    'eligibility_test_matches',
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
    'fit_dimension_reasons']
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=t) then
      execute format('grant select, insert, update, delete on public.%I to foundation_evaluation_executor', t);
    end if;
  end loop;
  foreach t in array array['student_identities', 'student_lifecycle_audit', 'student_deletion_authorizations', 'fit_student_access_contexts']
  loop
    execute format('grant select, insert, update, delete on private.%I to foundation_student_executor', t);
  end loop;
  foreach t in array array['fit_evaluation_assembly_authorizations']
  loop
    execute format('grant select, insert, update, delete on private.%I to foundation_evaluation_executor', t);
  end loop;
  grant select, insert, update, delete on private.student_lifecycle_audit to foundation_evaluation_executor;
end;
$dml$;

-- Evaluation and catalog entry points must lock/read student and catalog parents.
grant select, update on public.students to foundation_evaluation_executor;
grant select, update on public.student_profile_versions, public.fit_intent_sets to foundation_evaluation_executor;
grant select, update on public.eligibility_evaluations, public.fit_evaluations to foundation_student_executor;
grant select on public.universities, public.schools, public.programs, public.program_versions,
  public.taxonomy_concepts, public.evidence_items, public.sources, public.source_identities
  to foundation_student_executor, foundation_evaluation_executor;
grant select on public.canonical_field_selections, public.field_observations,
  public.catalog_concept_mappings, public.program_requirement_rule_sets
  to foundation_evaluation_executor;

grant create on schema public to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
grant create on schema private to foundation_student_executor, foundation_evaluation_executor;

do $xfer$
declare
  r record;
  v_owner text;
  v_callers text[];
  v_path text;
begin
  for r in
    select n.nspname, p.proname, p.oid, pg_get_function_identity_arguments(p.oid) as ident
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.proname in ('accept_field_observation',
    'append_program_derived_feature',
    'append_student_derived_feature_value',
    'authorize_fit_evaluation_assembly',
    'complete_program_foundation',
    'create_evidence_scope',
    'create_field_observation',
    'create_fit_intent_set',
    'create_program',
    'create_program_admission',
    'create_program_cost',
    'create_program_course',
    'create_program_deadline',
    'create_program_prerequisite',
    'create_program_school',
    'create_program_version',
    'create_requirement_rule_set',
    'create_school',
    'create_source_identity',
    'create_source_revision',
    'create_student',
    'create_student_feature_definition',
    'create_student_profile_version',
    'create_taxonomy_alias',
    'create_taxonomy_concept',
    'create_taxonomy_relationship',
    'create_taxonomy_release',
    'create_university',
    'delete_student_data',
    'finalize_eligibility_evaluation',
    'finalize_fit_evaluation',
    'freeze_fit_intent_set',
    'freeze_student_profile_version',
    'insert_eligibility_course_match',
    'insert_eligibility_manifest_catalog_mapping',
    'insert_eligibility_manifest_catalog_source',
    'insert_eligibility_manifest_completeness',
    'insert_eligibility_manifest_course',
    'insert_eligibility_manifest_degree',
    'insert_eligibility_manifest_student_evidence',
    'insert_eligibility_manifest_student_mapping',
    'insert_eligibility_manifest_taxonomy_concept',
    'insert_eligibility_manifest_test_score',
    'insert_eligibility_requirement_result',
    'insert_eligibility_test_match',
    'insert_fit_context_claim',
    'insert_fit_context_claim_definition',
    'insert_fit_context_claim_observation',
    'insert_fit_context_concept_mapping',
    'insert_fit_contract_release',
    'insert_fit_dimension_method',
    'insert_fit_dimension_reason',
    'insert_fit_dimension_result',
    'insert_fit_evaluation_method',
    'insert_fit_evaluator_build',
    'insert_fit_financial_normalization',
    'insert_fit_financial_normalization_method',
    'insert_fit_input_domain_state',
    'insert_fit_intent_declaration',
    'insert_fit_intent_delivery_constraint',
    'insert_fit_intent_duration_constraint',
    'insert_fit_intent_financial_constraint',
    'insert_fit_intent_location_constraint',
    'insert_fit_intent_program_feature_constraint',
    'insert_fit_intent_taxonomy_target',
    'insert_fit_intent_validation_issue',
    'insert_fit_manifest_catalog_mapping',
    'insert_fit_manifest_catalog_observation',
    'insert_fit_manifest_context_claim_selection',
    'insert_fit_manifest_context_mapping',
    'insert_fit_manifest_financial_normalization',
    'insert_fit_manifest_intent_declaration',
    'insert_fit_manifest_item',
    'insert_fit_manifest_phase2_completeness',
    'insert_fit_manifest_phase2_course',
    'insert_fit_manifest_phase2_goal',
    'insert_fit_manifest_phase2_mapping',
    'insert_fit_manifest_phase2_preference',
    'insert_fit_manifest_student_access_context',
    'insert_fit_manifest_student_field_use',
    'insert_fit_manifest_taxonomy_concept',
    'insert_fit_mapping_relation_definition',
    'insert_fit_method_input_policy',
    'insert_fit_method_mapping_relation_policy',
    'insert_fit_method_program_field_policy',
    'insert_fit_method_source_class_policy',
    'insert_fit_reason_definition',
    'insert_fit_semantic_source_class',
    'insert_fit_signal',
    'insert_fit_signal_evidence',
    'insert_fit_signal_type',
    'insert_fit_student_access_context',
    'insert_requirement_node',
    'insert_requirement_node_mapping',
    'insert_requirement_node_source',
    'insert_student_course',
    'insert_student_data_completeness',
    'insert_student_degree',
    'insert_student_evidence_item',
    'insert_student_experience',
    'insert_student_experience_skill',
    'insert_student_goal',
    'insert_student_preference',
    'insert_student_skill',
    'insert_student_test_score',
    'propose_catalog_concept_mapping',
    'propose_student_record_concept_mapping',
    'replace_program_primary_school',
    'retire_catalog_concept_mapping',
    'retire_catalog_record',
    'retire_fit_context_definition',
    'retire_fit_definition',
    'retire_program_requirement_rule_set',
    'retire_student_feature_definition',
    'retire_student_record_concept_mapping',
    'retire_taxonomy_alias',
    'retire_taxonomy_concept',
    'retire_taxonomy_relationship',
    'retire_taxonomy_release',
    'review_catalog_concept_mapping',
    'review_evidence_applicability',
    'review_fit_context_mapping',
    'review_fit_context_observation',
    'review_student_record_concept_mapping',
    'seal_eligibility_evaluation_inputs',
    'seal_fit_evaluation_inputs',
    'select_field_observation',
    'select_fit_context_claim_observation',
    'start_eligibility_evaluation',
    'start_fit_evaluation',
    'verify_fit_context_definition',
    'verify_fit_definition',
    'verify_program_requirement_rule_set',
    'verify_taxonomy_release')
  loop
    if r.proname in ('accept_field_observation',
    'append_program_derived_feature',
    'complete_program_foundation',
    'create_evidence_scope',
    'create_field_observation',
    'create_program',
    'create_program_admission',
    'create_program_cost',
    'create_program_course',
    'create_program_deadline',
    'create_program_prerequisite',
    'create_program_school',
    'create_program_version',
    'create_requirement_rule_set',
    'create_school',
    'create_source_identity',
    'create_source_revision',
    'create_student_feature_definition',
    'create_taxonomy_alias',
    'create_taxonomy_concept',
    'create_taxonomy_relationship',
    'create_taxonomy_release',
    'create_university',
    'insert_fit_context_claim',
    'insert_fit_context_claim_definition',
    'insert_fit_context_claim_observation',
    'insert_fit_context_concept_mapping',
    'insert_fit_contract_release',
    'insert_fit_dimension_method',
    'insert_fit_evaluator_build',
    'insert_fit_financial_normalization_method',
    'insert_fit_mapping_relation_definition',
    'insert_fit_method_input_policy',
    'insert_fit_method_mapping_relation_policy',
    'insert_fit_method_program_field_policy',
    'insert_fit_method_source_class_policy',
    'insert_fit_reason_definition',
    'insert_fit_semantic_source_class',
    'insert_fit_signal_type',
    'insert_requirement_node',
    'insert_requirement_node_mapping',
    'insert_requirement_node_source',
    'propose_catalog_concept_mapping',
    'replace_program_primary_school',
    'retire_catalog_concept_mapping',
    'retire_catalog_record',
    'retire_fit_context_definition',
    'retire_fit_definition',
    'retire_program_requirement_rule_set',
    'retire_student_feature_definition',
    'retire_taxonomy_alias',
    'retire_taxonomy_concept',
    'retire_taxonomy_relationship',
    'retire_taxonomy_release',
    'review_catalog_concept_mapping',
    'review_evidence_applicability',
    'review_fit_context_mapping',
    'review_fit_context_observation',
    'select_field_observation',
    'select_fit_context_claim_observation',
    'verify_fit_context_definition',
    'verify_fit_definition',
    'verify_program_requirement_rule_set',
    'verify_taxonomy_release') then
      v_owner := 'foundation_catalog_executor';
      v_path := 'pg_catalog, public, extensions';
    elsif r.proname in ('append_student_derived_feature_value',
    'create_fit_intent_set',
    'create_student',
    'create_student_profile_version',
    'delete_student_data',
    'freeze_fit_intent_set',
    'freeze_student_profile_version',
    'insert_fit_intent_declaration',
    'insert_fit_intent_delivery_constraint',
    'insert_fit_intent_duration_constraint',
    'insert_fit_intent_financial_constraint',
    'insert_fit_intent_location_constraint',
    'insert_fit_intent_program_feature_constraint',
    'insert_fit_intent_taxonomy_target',
    'insert_fit_intent_validation_issue',
    'insert_fit_student_access_context',
    'insert_student_course',
    'insert_student_data_completeness',
    'insert_student_degree',
    'insert_student_evidence_item',
    'insert_student_experience',
    'insert_student_experience_skill',
    'insert_student_goal',
    'insert_student_preference',
    'insert_student_skill',
    'insert_student_test_score',
    'propose_student_record_concept_mapping',
    'retire_student_record_concept_mapping',
    'review_student_record_concept_mapping') then
      v_owner := 'foundation_student_executor';
      v_path := 'pg_catalog, public, private, extensions';
    else
      v_owner := 'foundation_evaluation_executor';
      v_path := 'pg_catalog, public, private, extensions';
    end if;
    v_callers := array['service_role'];
    execute format('alter function %I.%I(%s) set search_path = %s', r.nspname, r.proname, r.ident, v_path);
    execute format('revoke all on function %I.%I(%s) from public, anon, authenticated, service_role, authenticator', r.nspname, r.proname, r.ident);
    execute format('alter function %I.%I(%s) owner to %I', r.nspname, r.proname, r.ident, v_owner);
    execute format('revoke all on function %I.%I(%s) from public, anon, authenticated, service_role, authenticator', r.nspname, r.proname, r.ident);
    execute format('grant execute on function %I.%I(%s) to service_role', r.nspname, r.proname, r.ident);
    insert into public.foundation_function_contracts (
      schema_name, function_name, identity_arguments, owner_role, prosecdef,
      search_path, allowed_caller_roles, body_digest
    ) values (
      r.nspname, r.proname, r.ident, v_owner, true, v_path, v_callers,
      encode(extensions.digest(convert_to(pg_get_functiondef(r.oid), 'UTF8'), 'sha256'), 'hex')
    )
    on conflict (schema_name, function_name, identity_arguments) do update
      set owner_role = excluded.owner_role,
          search_path = excluded.search_path,
          body_digest = excluded.body_digest;
  end loop;
end;
$xfer$;

-- Helper EXECUTE only to executors.
do $helpers$
declare r record;
begin
  for r in
    select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as ident
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where (
        n.nspname = 'private'
        and (
          p.proname like 'lock_%'
          or p.proname in (
            'student_privacy_delete_allowed',
            'write_student_lifecycle_audit', 'close_student_owned_rows',
            'json_uuid', 'student_id_from_profile', 'lock_student_from_row',
            'lock_evaluation_from_row', 'lock_student_row', 'lock_student_owned_total_order'
          )
        )
      )
      or (
        n.nspname = 'public'
        and p.proname in (
          'length_prefixed', 'scope_digest', 'derive_program_scope',
          'assert_catalog_field', 'reject_terminal_insert', 'insert_composite'
        )
      )
  loop
    execute format('revoke all on function %I.%I(%s) from public, anon, authenticated, service_role', r.nspname, r.proname, r.ident);
    execute format('grant execute on function %I.%I(%s) to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor', r.nspname, r.proname, r.ident);
  end loop;
  revoke all on function private.close_student_owned_rows(uuid) from public, anon, authenticated, service_role, foundation_catalog_executor, foundation_evaluation_executor;
  grant execute on function private.close_student_owned_rows(uuid) to foundation_student_executor;
end;
$helpers$;

revoke create on schema public from foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor, public, anon, authenticated, service_role;
revoke create on schema private from foundation_student_executor, foundation_evaluation_executor, public, anon, authenticated, service_role;
revoke create on schema extensions from public, anon, authenticated, service_role, foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
revoke create on schema pg_catalog from public, anon, authenticated, service_role, foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;

revoke all on all functions in schema public from public, anon, authenticated;
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on all functions in schema public
  to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
grant execute on all functions in schema private
  to foundation_student_executor, foundation_evaluation_executor;
grant execute on function public.current_user_owns_student(uuid) to authenticated;
grant execute on function public.current_user_owns_profile(uuid) to authenticated;
revoke all on function private.close_student_owned_rows(uuid)
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_evaluation_executor;
grant execute on function private.close_student_owned_rows(uuid) to foundation_student_executor;

do $rls$
declare t text;
begin
  foreach t in array array['universities',
    'schools',
    'programs',
    'program_schools',
    'program_versions',
    'program_admissions',
    'program_prerequisites',
    'program_courses',
    'program_costs',
    'program_deadlines',
    'source_identities',
    'sources',
    'evidence_items',
    'field_observations',
    'evidence_applicability_scopes',
    'evidence_applicability_assertions',
    'evidence_applicability_heads',
    'field_observation_applicability',
    'canonical_field_selections',
    'taxonomy_releases',
    'taxonomy_concepts',
    'taxonomy_aliases',
    'taxonomy_relationships',
    'catalog_concept_mappings',
    'program_requirement_rule_sets',
    'program_requirement_nodes',
    'program_requirement_node_sources',
    'program_requirement_node_mappings',
    'program_derived_features',
    'student_feature_definitions',
    'fit_contract_releases',
    'fit_semantic_source_classes',
    'fit_evaluator_builds',
    'fit_dimension_methods',
    'fit_method_source_class_policies',
    'fit_mapping_relation_definitions',
    'fit_method_mapping_relation_policies',
    'fit_signal_types',
    'fit_method_input_policies',
    'fit_method_program_field_policies',
    'fit_reason_definitions',
    'fit_financial_normalization_methods',
    'fit_context_claim_definitions',
    'fit_context_claims',
    'fit_context_claim_observations',
    'fit_context_claim_selection_history',
    'fit_context_claim_selections',
    'fit_context_concept_mappings',
    'external_metrics']
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=t) then
      execute format('drop policy if exists %I on public.%I', t || '_catalog_executor', t);
      execute format(
        'create policy %I on public.%I for all to foundation_catalog_executor using (current_user = %L) with check (current_user = %L)',
        t || '_catalog_executor', t, 'foundation_catalog_executor', 'foundation_catalog_executor'
      );
    end if;
  end loop;
  foreach t in array array['students',
    'student_profile_versions',
    'student_data_completeness',
    'student_evidence_items',
    'student_degrees',
    'student_courses',
    'student_test_scores',
    'student_experiences',
    'student_skills',
    'student_experience_skills',
    'student_goals',
    'student_preferences',
    'student_record_concept_mappings',
    'student_derived_feature_values',
    'student_deletion_tombstones',
    'fit_intent_sets',
    'fit_intent_declarations',
    'fit_intent_validation_issues',
    'fit_intent_taxonomy_targets',
    'fit_intent_location_constraints',
    'fit_intent_delivery_constraints',
    'fit_intent_financial_constraints',
    'fit_intent_duration_constraints',
    'fit_intent_program_feature_constraints']
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=t) then
      execute format('drop policy if exists %I on public.%I', t || '_student_executor', t);
      execute format(
        'create policy %I on public.%I for all to foundation_student_executor using (current_user = %L) with check (current_user = %L)',
        t || '_student_executor', t, 'foundation_student_executor', 'foundation_student_executor'
      );
    end if;
  end loop;
  foreach t in array array['eligibility_evaluations',
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
    'eligibility_test_matches',
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
    'fit_dimension_reasons']
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=t) then
      execute format('drop policy if exists %I on public.%I', t || '_eval_executor', t);
      execute format(
        'create policy %I on public.%I for all to foundation_evaluation_executor using (current_user = %L) with check (current_user = %L)',
        t || '_eval_executor', t, 'foundation_evaluation_executor', 'foundation_evaluation_executor'
      );
    end if;
  end loop;
end;
$rls$;

drop policy if exists students_eval_lock on public.students;
create policy students_eval_lock on public.students
  for all to foundation_evaluation_executor
  using (current_user = 'foundation_evaluation_executor')
  with check (current_user = 'foundation_evaluation_executor');
drop policy if exists student_profile_versions_eval_lock on public.student_profile_versions;
create policy student_profile_versions_eval_lock on public.student_profile_versions
  for all to foundation_evaluation_executor
  using (current_user = 'foundation_evaluation_executor')
  with check (current_user = 'foundation_evaluation_executor');
drop policy if exists fit_intent_sets_eval_lock on public.fit_intent_sets;
create policy fit_intent_sets_eval_lock on public.fit_intent_sets
  for all to foundation_evaluation_executor
  using (current_user = 'foundation_evaluation_executor')
  with check (current_user = 'foundation_evaluation_executor');
drop policy if exists eligibility_evaluations_student_lock on public.eligibility_evaluations;
create policy eligibility_evaluations_student_lock on public.eligibility_evaluations
  for all to foundation_student_executor
  using (current_user = 'foundation_student_executor')
  with check (current_user = 'foundation_student_executor');
drop policy if exists fit_evaluations_student_lock on public.fit_evaluations;
create policy fit_evaluations_student_lock on public.fit_evaluations
  for all to foundation_student_executor
  using (current_user = 'foundation_student_executor')
  with check (current_user = 'foundation_student_executor');

do $revoke$
declare t text;
begin
  foreach t in array array['universities',
    'schools',
    'programs',
    'program_schools',
    'program_versions',
    'program_admissions',
    'program_prerequisites',
    'program_courses',
    'program_costs',
    'program_deadlines',
    'source_identities',
    'sources',
    'evidence_items',
    'field_observations',
    'evidence_applicability_scopes',
    'evidence_applicability_assertions',
    'evidence_applicability_heads',
    'field_observation_applicability',
    'canonical_field_selections',
    'taxonomy_releases',
    'taxonomy_concepts',
    'taxonomy_aliases',
    'taxonomy_relationships',
    'catalog_concept_mappings',
    'program_requirement_rule_sets',
    'program_requirement_nodes',
    'program_requirement_node_sources',
    'program_requirement_node_mappings',
    'program_derived_features',
    'student_feature_definitions',
    'fit_contract_releases',
    'fit_semantic_source_classes',
    'fit_evaluator_builds',
    'fit_dimension_methods',
    'fit_method_source_class_policies',
    'fit_mapping_relation_definitions',
    'fit_method_mapping_relation_policies',
    'fit_signal_types',
    'fit_method_input_policies',
    'fit_method_program_field_policies',
    'fit_reason_definitions',
    'fit_financial_normalization_methods',
    'fit_context_claim_definitions',
    'fit_context_claims',
    'fit_context_claim_observations',
    'fit_context_claim_selection_history',
    'fit_context_claim_selections',
    'fit_context_concept_mappings',
    'external_metrics',
    'students',
    'student_profile_versions',
    'student_data_completeness',
    'student_evidence_items',
    'student_degrees',
    'student_courses',
    'student_test_scores',
    'student_experiences',
    'student_skills',
    'student_experience_skills',
    'student_goals',
    'student_preferences',
    'student_record_concept_mappings',
    'student_derived_feature_values',
    'student_deletion_tombstones',
    'fit_intent_sets',
    'fit_intent_declarations',
    'fit_intent_validation_issues',
    'fit_intent_taxonomy_targets',
    'fit_intent_location_constraints',
    'fit_intent_delivery_constraints',
    'fit_intent_financial_constraints',
    'fit_intent_duration_constraints',
    'fit_intent_program_feature_constraints',
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
    'eligibility_test_matches',
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
    'fit_dimension_reasons']
  loop
    if exists (select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname=t) then
      execute format('revoke insert, update, delete on public.%I from public, anon, authenticated, service_role', t);
    end if;
  end loop;
  execute 'revoke insert, update, delete on private.student_identities from public, anon, authenticated, service_role';
  execute 'revoke insert, update, delete on private.fit_student_access_contexts from public, anon, authenticated, service_role';
  execute 'revoke insert, update, delete on private.fit_evaluation_assembly_authorizations from public, anon, authenticated, service_role';
  execute 'revoke insert, update, delete on all tables in schema public from public, anon, authenticated, service_role';
  execute 'revoke insert, update, delete on all tables in schema private from public, anon, authenticated, service_role';
end;
$revoke$;

grant insert on public.audit_events to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
grant usage, select on all sequences in schema public to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
grant select on all tables in schema public to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
grant select on all tables in schema private to foundation_student_executor, foundation_evaluation_executor;

drop policy if exists audit_events_executor_insert on public.audit_events;
create policy audit_events_executor_insert on public.audit_events
  for insert to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor
  with check (current_user in (
    'foundation_catalog_executor',
    'foundation_student_executor',
    'foundation_evaluation_executor'
  ));
drop policy if exists audit_events_public_read on public.audit_events;
create policy audit_events_public_read on public.audit_events
  for select to anon, authenticated using (true);

-- PUBLIC policies apply to every role, including executors, and cause RLS recursion
-- on Fit context tables. Runtime public-read remains for anon/authenticated.
do $pol$
declare r record;
begin
  for r in
    select n.nspname, c.relname, p.polname
    from pg_policy p
    join pg_class c on c.oid = p.polrelid
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'private')
      and 0 = any (p.polroles)
      and p.polname not like '%_executor%'
      and p.polname not like '%_eval_lock%'
      and p.polname not like '%_student_lock%'
  loop
    execute format(
      'alter policy %I on %I.%I to anon, authenticated',
      r.polname, r.nspname, r.relname
    );
  end loop;
end;
$pol$;

do $exec_read$
declare r record;
begin
  for r in
    select n.nspname, c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'private')
      and c.relkind = 'r'
      and c.relrowsecurity
  loop
    execute format('drop policy if exists %I on %I.%I', r.relname || '_executor_read', r.nspname, r.relname);
    execute format(
      'create policy %I on %I.%I for select to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor using (true)',
      r.relname || '_executor_read', r.nspname, r.relname
    );
  end loop;
end;
$exec_read$;

drop policy if exists fit_evaluation_assembly_authorizations_eval_write
  on private.fit_evaluation_assembly_authorizations;
create policy fit_evaluation_assembly_authorizations_eval_write
  on private.fit_evaluation_assembly_authorizations
  for all to foundation_evaluation_executor
  using (current_user = 'foundation_evaluation_executor')
  with check (current_user = 'foundation_evaluation_executor');
drop policy if exists fit_student_access_contexts_student_write
  on private.fit_student_access_contexts;
create policy fit_student_access_contexts_student_write
  on private.fit_student_access_contexts
  for all to foundation_student_executor
  using (current_user = 'foundation_student_executor')
  with check (current_user = 'foundation_student_executor');
drop policy if exists student_identities_student_write
  on private.student_identities;
create policy student_identities_student_write
  on private.student_identities
  for all to foundation_student_executor
  using (current_user = 'foundation_student_executor')
  with check (current_user = 'foundation_student_executor');
drop policy if exists student_lifecycle_audit_write
  on private.student_lifecycle_audit;
alter table private.student_lifecycle_audit enable row level security;
create policy student_lifecycle_audit_write
  on private.student_lifecycle_audit
  for all to foundation_student_executor, foundation_evaluation_executor
  using (current_user in ('foundation_student_executor', 'foundation_evaluation_executor'))
  with check (current_user in ('foundation_student_executor', 'foundation_evaluation_executor'));

grant select on public.student_deletion_tombstones to public;
revoke select (legacy_deletion_reason) on public.student_deletion_tombstones from public, anon, authenticated, service_role;

-- Materialize path-schema ACLs so PUBLIC CREATE is explicitly absent.
grant usage on schema public to public, anon, authenticated, service_role;
grant usage on schema extensions to public, anon, authenticated, service_role,
  foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
grant usage on schema private to foundation_student_executor, foundation_evaluation_executor;
revoke create on schema public from public, anon, authenticated, service_role;
revoke create on schema private from public, anon, authenticated, service_role;
revoke create on schema extensions from public, anon, authenticated, service_role,
  foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;

-- Post-install assertions (must be empty).
do $assert$
declare n integer;
begin
  select count(*) into n from pg_roles r
  where r.rolname in ('foundation_catalog_executor','foundation_student_executor','foundation_evaluation_executor')
    and (r.rolcanlogin or r.rolbypassrls or r.rolcreaterole or r.rolcreatedb or r.rolsuper or r.rolinherit or r.rolreplication);
  if n <> 0 then
    raise exception '012 assertion A failed: executor attributes';
  end if;
  if exists (
    select n.nspname, p.proname
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_roles r on r.oid = p.proowner
    where r.rolname in (
      'foundation_catalog_executor','foundation_student_executor','foundation_evaluation_executor'
    )
      and not exists (
        select 1 from public.foundation_function_contracts c
        where c.schema_name = n.nspname
          and c.function_name = p.proname
          and c.identity_arguments = pg_get_function_identity_arguments(p.oid)
          and c.owner_role = r.rolname
      )
  ) or exists (
    select 1 from pg_class t
    join pg_namespace n on n.oid = t.relnamespace
    join pg_roles r on r.oid = t.relowner
    where r.rolname in (
      'foundation_catalog_executor','foundation_student_executor','foundation_evaluation_executor'
    )
  ) then
    raise exception '012 assertion B failed: executor owns unexpected object';
  end if;
  if exists (
    select 1 from (
      select unnest(array['anon','authenticated','service_role','authenticator','foundation_catalog_executor','foundation_student_executor','foundation_evaluation_executor']) as role_name
    ) roles
    cross join (select unnest(array['pg_catalog','public','private','extensions']) as schema_name) schemas
    where has_schema_privilege(roles.role_name, schemas.schema_name, 'CREATE')
  ) then
    raise exception '012 assertion C failed: unexpected schema CREATE';
  end if;
  if exists (
    select 1
    from pg_namespace n
    where n.nspname in ('public','private','extensions')
      and (
        n.nspacl is null
        or exists (
          select 1 from aclexplode(n.nspacl) a
          where a.grantee = 0 and a.privilege_type = 'CREATE'
        )
      )
  ) then
    raise exception '012 assertion C-PUBLIC failed: PUBLIC CREATE on path schema';
  end if;
  if exists (
    select 1 from pg_roles r
    cross join pg_namespace n
    where (
      (r.rolname = 'foundation_catalog_executor' and n.nspname in ('public','extensions'))
      or (r.rolname in ('foundation_student_executor','foundation_evaluation_executor')
          and n.nspname in ('public','private','extensions'))
    )
      and not has_schema_privilege(r.rolname, n.nspname, 'USAGE')
  ) then
    raise exception '012 assertion D-USAGE failed: missing executor schema USAGE';
  end if;
  if has_schema_privilege('foundation_catalog_executor', 'private', 'USAGE') then
    raise exception '012 assertion D-USAGE failed: catalog executor has private USAGE';
  end if;
  if exists (
    select 1 from information_schema.routine_privileges
    where grantee in ('PUBLIC','anon')
      and privilege_type = 'EXECUTE'
      and routine_schema in ('public','private')
  ) then
    raise exception '012 assertion E failed: PUBLIC/anon EXECUTE remains';
  end if;
  if exists (
    select 1 from information_schema.routine_privileges
    where grantee = 'authenticated'
      and privilege_type = 'EXECUTE'
      and routine_schema in ('public','private')
      and not (
        routine_schema = 'public'
        and routine_name in ('current_user_owns_student','current_user_owns_profile')
      )
  ) then
    raise exception '012 assertion F failed: authenticated EXECUTE too broad';
  end if;
  if exists (
    select 1 from information_schema.role_table_grants
    where grantee = 'service_role'
      and privilege_type in ('INSERT','UPDATE','DELETE')
      and table_schema in ('public','private')
  ) then
    raise exception '012 assertion G failed: service_role retains direct DML';
  end if;
  if exists (
    select 1
    from pg_auth_members m
    join pg_roles r on r.oid = m.member
    join pg_roles e on e.oid = m.roleid
    where e.rolname in (
      'foundation_catalog_executor','foundation_student_executor','foundation_evaluation_executor'
    )
      and r.rolname in ('anon','authenticated','service_role','authenticator')
  ) then
    raise exception '012 assertion H failed: runtime role is executor member';
  end if;
  if exists (
    select 1 from public.foundation_function_contracts c
    where c.function_name like '%\_v02' escape '\'
       or c.function_name like '%ordinal%'
       or c.function_name like '%snapshot%'
       or c.function_name like '%\_pin%' escape '\'
  ) then
    raise exception '012 assertion I failed: 9B names in 9A registry';
  end if;
  if exists (
    select 1 from public.foundation_function_contracts c
    where not exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_roles r on r.oid = p.proowner
      where n.nspname = c.schema_name
        and p.proname = c.function_name
        and pg_get_function_identity_arguments(p.oid) = c.identity_arguments
        and r.rolname = c.owner_role
        and p.prosecdef = c.prosecdef
    )
  ) then
    raise exception '012 assertion I failed: contract/pg_proc mismatch';
  end if;
end;
$assert$;

commit;
