-- Phase 4B-1B.2B-5: Assessment / Skill taxonomy admissibility core.
-- Additive over Migrations 001-023. Application/Outcome remains planning-only
-- under a provisional future Migration 025 identity.

begin;

create type public.profile_assessment_definition_status_v024 as enum (
  'DRAFT', 'VERIFIED', 'RETIRED'
);

create type public.profile_assessment_score_shape_v024 as enum (
  'TOTAL_ONLY',
  'SECTIONS_ONLY_COMPLETE',
  'SECTIONS_ONLY_PARTIAL',
  'TOTAL_AND_COMPLETE_SECTIONS',
  'TOTAL_AND_PARTIAL_SECTIONS'
);

create type public.profile_assessment_evidence_role_v024 as enum (
  'FORMAT_IDENTITY',
  'EFFECTIVE_DATE',
  'TOTAL_RANGE',
  'SECTION_SET',
  'SECTION_RANGE',
  'SCORE_INCREMENT',
  'REPORTING_RULE'
);

create type public.profile_taxonomy_reference_origin_v024 as enum (
  'NEW_SELECTION', 'HISTORICAL_FORK'
);

create table public.profile_assessment_definitions_v024 (
  assessment_definition_id uuid primary key
    default extensions.gen_random_uuid(),
  assessment_concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  definition_version bigint not null,
  format_code text not null,
  status public.profile_assessment_definition_status_v024 not null
    default 'DRAFT',
  effective_release_code text not null
    references public.taxonomy_releases(release_code) on delete restrict,
  effective_release_ordinal bigint not null
    references public.taxonomy_releases(release_ordinal) on delete restrict,
  valid_test_date_from date not null,
  valid_test_date_to date,
  total_min numeric,
  total_max numeric,
  total_increment numeric,
  total_scale smallint,
  supersedes_definition_id uuid
    references public.profile_assessment_definitions_v024(
      assessment_definition_id
    ) on delete restrict,
  manifest_hash text,
  verified_by text,
  verified_at timestamptz,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  constraint profile_assessment_definition_version_positive_v024
    check (definition_version >= 1),
  constraint profile_assessment_format_code_v024
    check (format_code ~ '^[A-Z][A-Z0-9_]{0,63}$'),
  constraint profile_assessment_date_range_v024
    check (
      valid_test_date_to is null
      or valid_test_date_to >= valid_test_date_from
    ),
  constraint profile_assessment_total_shape_v024
    check (
      (
        total_min is null and total_max is null
        and total_increment is null and total_scale is null
      ) or (
        total_min is not null and total_max is not null
        and total_increment is not null and total_increment > 0
        and total_max >= total_min
        and total_scale between 0 and 6
      )
    ),
  constraint profile_assessment_manifest_hash_v024
    check (manifest_hash is null or manifest_hash ~ '^[a-f0-9]{64}$'),
  constraint profile_assessment_lifecycle_shape_v024
    check (
      (status = 'DRAFT' and verified_by is null and verified_at is null
        and retired_at is null and retirement_reason is null
        and manifest_hash is null)
      or (status = 'VERIFIED' and verified_by is not null
        and verified_at is not null and retired_at is null
        and retirement_reason is null and manifest_hash is not null)
      or (status = 'RETIRED' and verified_by is not null
        and verified_at is not null and retired_at is not null
        and nullif(btrim(retirement_reason), '') is not null
        and manifest_hash is not null)
    ),
  unique (assessment_concept_id, format_code, definition_version)
);

create table public.profile_assessment_score_shapes_v024 (
  assessment_definition_id uuid not null
    references public.profile_assessment_definitions_v024(
      assessment_definition_id
    ) on delete cascade,
  score_shape public.profile_assessment_score_shape_v024 not null,
  primary key (assessment_definition_id, score_shape)
);

create table public.profile_assessment_sections_v024 (
  assessment_definition_id uuid not null
    references public.profile_assessment_definitions_v024(
      assessment_definition_id
    ) on delete cascade,
  section_key text not null,
  display_name text not null,
  score_min numeric not null,
  score_max numeric not null,
  score_increment numeric not null,
  score_scale smallint not null,
  required_in_complete_set boolean not null,
  display_order smallint not null,
  primary key (assessment_definition_id, section_key),
  unique (assessment_definition_id, display_order),
  constraint profile_assessment_section_key_v024
    check (section_key ~ '^[a-z][a-zA-Z0-9]{0,63}$'),
  constraint profile_assessment_section_display_v024
    check (nullif(btrim(display_name), '') is not null
      and pg_catalog.octet_length(display_name) <= 128),
  constraint profile_assessment_section_range_v024
    check (score_max >= score_min and score_increment > 0),
  constraint profile_assessment_section_scale_v024
    check (score_scale between 0 and 6),
  constraint profile_assessment_section_order_v024
    check (display_order between 1 and 64)
);

create table public.profile_assessment_definition_evidence_v024 (
  assessment_definition_id uuid not null
    references public.profile_assessment_definitions_v024(
      assessment_definition_id
    ) on delete cascade,
  evidence_role public.profile_assessment_evidence_role_v024 not null,
  evidence_id uuid not null
    references public.evidence_items(evidence_id) on delete restrict,
  primary key (assessment_definition_id, evidence_role, evidence_id)
);

alter table public.student_test_scores
  add column assessment_definition_id uuid
    references public.profile_assessment_definitions_v024(
      assessment_definition_id
    ) on delete restrict,
  add column taxonomy_release_ordinal_at_selection bigint
    references public.taxonomy_releases(release_ordinal) on delete restrict,
  add column taxonomy_reference_origin
    public.profile_taxonomy_reference_origin_v024;

alter table public.student_skills
  add column taxonomy_release_ordinal_at_selection bigint
    references public.taxonomy_releases(release_ordinal) on delete restrict,
  add column taxonomy_reference_origin
    public.profile_taxonomy_reference_origin_v024;

create table private.profile_fork_context_v024 (
  backend_pid integer not null,
  transaction_id bigint not null,
  source_profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  created_at timestamptz not null default now(),
  primary key (backend_pid, transaction_id)
);

alter table private.profile_fork_context_v024 enable row level security;

-- A hosted Supabase migration runner is intentionally non-superuser. PostgreSQL
-- therefore requires each target owner to hold CREATE on the object's schema
-- while ALTER OWNER runs. Keep these grants scoped to this transfer group and
-- revoke them before any runtime contract is installed.
grant create on schema public to foundation_catalog_executor;
grant create on schema private to foundation_student_executor;

alter table public.profile_assessment_definitions_v024
  owner to foundation_catalog_executor;
alter table public.profile_assessment_score_shapes_v024
  owner to foundation_catalog_executor;
alter table public.profile_assessment_sections_v024
  owner to foundation_catalog_executor;
alter table public.profile_assessment_definition_evidence_v024
  owner to foundation_catalog_executor;
alter table private.profile_fork_context_v024
  owner to foundation_student_executor;

revoke create on schema public from foundation_catalog_executor;
revoke create on schema private from foundation_student_executor;

revoke all on table
  public.profile_assessment_definitions_v024,
  public.profile_assessment_score_shapes_v024,
  public.profile_assessment_sections_v024,
  public.profile_assessment_definition_evidence_v024
from public, anon, authenticated, service_role, authenticator,
  foundation_student_executor, foundation_evaluation_executor;

grant select on table
  public.profile_assessment_definitions_v024,
  public.profile_assessment_score_shapes_v024,
  public.profile_assessment_sections_v024
to foundation_student_executor;

revoke all on table private.profile_fork_context_v024
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_evaluation_executor;

create or replace function private.profile_require_verified_active_concept_v024(
  p_concept_id uuid,
  p_expected_kind public.taxonomy_concept_kind
)
returns bigint
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_release_ordinal bigint;
  v_kind public.taxonomy_concept_kind;
  v_introduced bigint;
  v_retired bigint;
begin
  select release.release_ordinal
  into v_release_ordinal
  from public.taxonomy_releases release
  where release.status = 'VERIFIED'
  order by release.release_ordinal desc, release.release_code collate "C" desc
  limit 1;

  if v_release_ordinal is null then
    raise exception using errcode = '55000',
      message = 'PROFILE_TAXONOMY_CONCEPT_INVALID';
  end if;

  select concept.concept_kind, concept.introduced_release_ordinal,
    concept.retired_release_ordinal
  into v_kind, v_introduced, v_retired
  from public.taxonomy_concepts concept
  where concept.concept_id = p_concept_id;

  if not found then
    raise exception using errcode = '22023',
      message = 'PROFILE_TAXONOMY_CONCEPT_INVALID';
  end if;
  if v_kind is distinct from p_expected_kind then
    raise exception using errcode = '22023',
      message = 'PROFILE_TAXONOMY_KIND_MISMATCH';
  end if;
  if v_introduced > v_release_ordinal
     or (v_retired is not null and v_retired <= v_release_ordinal) then
    raise exception using errcode = '55000',
      message = 'PROFILE_TAXONOMY_CONCEPT_INACTIVE';
  end if;
  return v_release_ordinal;
end;
$function$;

create or replace function private.profile_assessment_definition_guard_v024()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
begin
  if tg_op = 'DELETE' then
    if old.status <> 'DRAFT' then
      raise exception using errcode = '55000',
        message = 'PROFILE_ASSESSMENT_DEFINITION_IMMUTABLE';
    end if;
    return old;
  end if;

  if old.status = 'DRAFT' then
    return new;
  end if;

  if old.status = 'VERIFIED'
     and new.status = 'RETIRED'
     and (to_jsonb(new) - array[
       'status', 'retired_at', 'retirement_reason'
     ]) = (to_jsonb(old) - array[
       'status', 'retired_at', 'retirement_reason'
     ]) then
    return new;
  end if;

  raise exception using errcode = '55000',
    message = 'PROFILE_ASSESSMENT_DEFINITION_IMMUTABLE';
end;
$function$;

create or replace function private.profile_assessment_child_guard_v024()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_definition_id uuid;
  v_status public.profile_assessment_definition_status_v024;
begin
  v_definition_id := case when tg_op = 'DELETE'
    then old.assessment_definition_id else new.assessment_definition_id end;
  select definition.status into v_status
  from public.profile_assessment_definitions_v024 definition
  where definition.assessment_definition_id = v_definition_id
  for key share;
  if v_status is distinct from 'DRAFT' then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_DEFINITION_IMMUTABLE';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

create trigger profile_assessment_definition_guard_v024
before update or delete on public.profile_assessment_definitions_v024
for each row execute function private.profile_assessment_definition_guard_v024();

create trigger profile_assessment_score_shape_guard_v024
before insert or update or delete
on public.profile_assessment_score_shapes_v024
for each row execute function private.profile_assessment_child_guard_v024();

create trigger profile_assessment_section_guard_v024
before insert or update or delete on public.profile_assessment_sections_v024
for each row execute function private.profile_assessment_child_guard_v024();

create trigger profile_assessment_evidence_guard_v024
before insert or update or delete
on public.profile_assessment_definition_evidence_v024
for each row execute function private.profile_assessment_child_guard_v024();

create or replace function public.create_profile_assessment_definition_v024(
  p_assessment_concept_id uuid,
  p_definition_version bigint,
  p_format_code text,
  p_effective_release_code text,
  p_valid_test_date_from date,
  p_valid_test_date_to date,
  p_total_min numeric,
  p_total_max numeric,
  p_total_increment numeric,
  p_total_scale smallint,
  p_supersedes_definition_id uuid default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_definition_id uuid;
  v_release_ordinal bigint;
begin
  select release.release_ordinal into v_release_ordinal
  from public.taxonomy_releases release
  where release.release_code = p_effective_release_code;
  if v_release_ordinal is null then
    raise exception using errcode = '22023',
      message = 'PROFILE_TAXONOMY_CONCEPT_INVALID';
  end if;
  if not exists (
    select 1 from public.taxonomy_concepts concept
    where concept.concept_id = p_assessment_concept_id
      and concept.concept_kind = 'ASSESSMENT'
  ) then
    raise exception using errcode = '22023',
      message = 'PROFILE_TAXONOMY_KIND_MISMATCH';
  end if;
  insert into public.profile_assessment_definitions_v024 (
    assessment_concept_id, definition_version, format_code,
    effective_release_code, effective_release_ordinal,
    valid_test_date_from, valid_test_date_to,
    total_min, total_max, total_increment, total_scale,
    supersedes_definition_id
  ) values (
    p_assessment_concept_id, p_definition_version, p_format_code,
    p_effective_release_code, v_release_ordinal,
    p_valid_test_date_from, p_valid_test_date_to,
    p_total_min, p_total_max, p_total_increment, p_total_scale,
    p_supersedes_definition_id
  ) returning assessment_definition_id into v_definition_id;
  return v_definition_id;
end;
$function$;

create or replace function public.add_profile_assessment_score_shape_v024(
  p_assessment_definition_id uuid,
  p_score_shape public.profile_assessment_score_shape_v024
)
returns void
language sql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  insert into public.profile_assessment_score_shapes_v024 (
    assessment_definition_id, score_shape
  ) values (p_assessment_definition_id, p_score_shape)
$function$;

create or replace function public.add_profile_assessment_section_v024(
  p_assessment_definition_id uuid,
  p_section_key text,
  p_display_name text,
  p_score_min numeric,
  p_score_max numeric,
  p_score_increment numeric,
  p_score_scale smallint,
  p_required_in_complete_set boolean,
  p_display_order smallint
)
returns void
language sql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  insert into public.profile_assessment_sections_v024 (
    assessment_definition_id, section_key, display_name,
    score_min, score_max, score_increment, score_scale,
    required_in_complete_set, display_order
  ) values (
    p_assessment_definition_id, p_section_key, p_display_name,
    p_score_min, p_score_max, p_score_increment, p_score_scale,
    p_required_in_complete_set, p_display_order
  )
$function$;

create or replace function public.add_profile_assessment_evidence_v024(
  p_assessment_definition_id uuid,
  p_evidence_role public.profile_assessment_evidence_role_v024,
  p_evidence_id uuid
)
returns void
language sql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  insert into public.profile_assessment_definition_evidence_v024 (
    assessment_definition_id, evidence_role, evidence_id
  ) values (p_assessment_definition_id, p_evidence_role, p_evidence_id)
$function$;

create or replace function public.verify_profile_assessment_definition_v024(
  p_assessment_definition_id uuid,
  p_verified_by text
)
returns text
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_definition public.profile_assessment_definitions_v024%rowtype;
  v_manifest text;
  v_required_role public.profile_assessment_evidence_role_v024;
  v_has_total_shape boolean;
  v_has_section_shape boolean;
begin
  if nullif(btrim(p_verified_by), '') is null then
    raise exception using errcode = '22023',
      message = 'PROFILE_ASSESSMENT_VERIFIER_REQUIRED';
  end if;

  select definition.* into v_definition
  from public.profile_assessment_definitions_v024 definition
  where definition.assessment_definition_id = p_assessment_definition_id
  for update;
  if not found or v_definition.status <> 'DRAFT' then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_DRAFT_REQUIRED';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'profile-assessment-definition:'
      || lower(v_definition.assessment_concept_id::text), 0
  ));

  if not exists (
    select 1 from public.taxonomy_releases release
    where release.release_code = v_definition.effective_release_code
      and release.release_ordinal = v_definition.effective_release_ordinal
      and release.status = 'VERIFIED'
  ) or not exists (
    select 1 from public.taxonomy_concepts concept
    where concept.concept_id = v_definition.assessment_concept_id
      and concept.concept_kind = 'ASSESSMENT'
      and concept.introduced_release_ordinal
        <= v_definition.effective_release_ordinal
      and (
        concept.retired_release_ordinal is null
        or concept.retired_release_ordinal
          > v_definition.effective_release_ordinal
      )
  ) then
    raise exception using errcode = '55000',
      message = 'PROFILE_TAXONOMY_CONCEPT_INACTIVE';
  end if;

  if exists (
    select 1
    from public.profile_assessment_definitions_v024 existing
    where existing.assessment_definition_id <> p_assessment_definition_id
      and existing.assessment_concept_id =
        v_definition.assessment_concept_id
      and existing.format_code = v_definition.format_code
      and existing.status = 'VERIFIED'
      and daterange(
        existing.valid_test_date_from,
        existing.valid_test_date_to,
        '[]'
      ) && daterange(
        v_definition.valid_test_date_from,
        v_definition.valid_test_date_to,
        '[]'
      )
  ) then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_DEFINITION_AMBIGUOUS';
  end if;

  if v_definition.supersedes_definition_id is not null
     and not exists (
       select 1
       from public.profile_assessment_definitions_v024 prior
       where prior.assessment_definition_id =
         v_definition.supersedes_definition_id
         and prior.assessment_concept_id =
           v_definition.assessment_concept_id
         and prior.format_code = v_definition.format_code
         and prior.definition_version < v_definition.definition_version
         and prior.status in ('VERIFIED', 'RETIRED')
     ) then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_SUPERSESSION_INVALID';
  end if;

  if not exists (
    select 1 from public.profile_assessment_score_shapes_v024 shape
    where shape.assessment_definition_id = p_assessment_definition_id
  ) then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_SCORE_INVALID';
  end if;

  select coalesce(bool_or(shape.score_shape in (
      'TOTAL_ONLY', 'TOTAL_AND_COMPLETE_SECTIONS',
      'TOTAL_AND_PARTIAL_SECTIONS'
    )), false),
    coalesce(bool_or(shape.score_shape in (
      'SECTIONS_ONLY_COMPLETE', 'SECTIONS_ONLY_PARTIAL',
      'TOTAL_AND_COMPLETE_SECTIONS', 'TOTAL_AND_PARTIAL_SECTIONS'
    )), false)
  into v_has_total_shape, v_has_section_shape
  from public.profile_assessment_score_shapes_v024 shape
  where shape.assessment_definition_id = p_assessment_definition_id;

  if v_has_total_shape is distinct from (v_definition.total_min is not null)
     or v_has_section_shape is distinct from exists (
       select 1 from public.profile_assessment_sections_v024 section
       where section.assessment_definition_id = p_assessment_definition_id
     ) then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_SCORE_INVALID';
  end if;

  if exists (
       select 1
       from public.profile_assessment_score_shapes_v024 shape
       where shape.assessment_definition_id = p_assessment_definition_id
         and shape.score_shape in (
           'SECTIONS_ONLY_COMPLETE', 'TOTAL_AND_COMPLETE_SECTIONS'
         )
     ) and not exists (
       select 1
       from public.profile_assessment_sections_v024 section
       where section.assessment_definition_id = p_assessment_definition_id
         and section.required_in_complete_set
     ) then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_SCORE_INVALID';
  end if;

  foreach v_required_role in array array[
    'FORMAT_IDENTITY'::public.profile_assessment_evidence_role_v024,
    'EFFECTIVE_DATE'::public.profile_assessment_evidence_role_v024,
    'SCORE_INCREMENT'::public.profile_assessment_evidence_role_v024,
    'REPORTING_RULE'::public.profile_assessment_evidence_role_v024
  ] loop
    if not exists (
      select 1
      from public.profile_assessment_definition_evidence_v024 manifest
      join public.evidence_items evidence
        on evidence.evidence_id = manifest.evidence_id
      join public.sources source on source.source_id = evidence.source_id
      where manifest.assessment_definition_id = p_assessment_definition_id
        and manifest.evidence_role = v_required_role
        and source.reliability_tier = 'TIER_A_OFFICIAL'
        and source.retrieval_content_hash ~ '^[a-f0-9]{64}$'
        and evidence.content_hash ~ '^[a-f0-9]{64}$'
    ) then
      raise exception using errcode = '55000',
        message = 'PROFILE_ASSESSMENT_EVIDENCE_INCOMPLETE';
    end if;
  end loop;

  if v_has_total_shape and not exists (
    select 1
    from public.profile_assessment_definition_evidence_v024 manifest
    join public.evidence_items evidence
      on evidence.evidence_id = manifest.evidence_id
    join public.sources source on source.source_id = evidence.source_id
    where manifest.assessment_definition_id = p_assessment_definition_id
      and manifest.evidence_role = 'TOTAL_RANGE'
      and source.reliability_tier = 'TIER_A_OFFICIAL'
      and source.retrieval_content_hash ~ '^[a-f0-9]{64}$'
      and evidence.content_hash ~ '^[a-f0-9]{64}$'
  ) then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_EVIDENCE_INCOMPLETE';
  end if;

  if v_has_section_shape and (
    not exists (
      select 1
      from public.profile_assessment_definition_evidence_v024 manifest
      join public.evidence_items evidence
        on evidence.evidence_id = manifest.evidence_id
      join public.sources source on source.source_id = evidence.source_id
      where manifest.assessment_definition_id = p_assessment_definition_id
        and manifest.evidence_role = 'SECTION_SET'
        and source.reliability_tier = 'TIER_A_OFFICIAL'
        and source.retrieval_content_hash ~ '^[a-f0-9]{64}$'
        and evidence.content_hash ~ '^[a-f0-9]{64}$'
    ) or not exists (
      select 1
      from public.profile_assessment_definition_evidence_v024 manifest
      join public.evidence_items evidence
        on evidence.evidence_id = manifest.evidence_id
      join public.sources source on source.source_id = evidence.source_id
      where manifest.assessment_definition_id = p_assessment_definition_id
        and manifest.evidence_role = 'SECTION_RANGE'
        and source.reliability_tier = 'TIER_A_OFFICIAL'
        and source.retrieval_content_hash ~ '^[a-f0-9]{64}$'
        and evidence.content_hash ~ '^[a-f0-9]{64}$'
    )
  ) then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_EVIDENCE_INCOMPLETE';
  end if;

  select encode(extensions.digest(convert_to(
    jsonb_build_object(
      'schema', 'PROFILE_ASSESSMENT_DEFINITION_V024',
      'definition', to_jsonb(v_definition) - array[
        'status', 'manifest_hash', 'verified_by', 'verified_at',
        'retired_at', 'retirement_reason', 'created_at'
      ],
      'shapes', coalesce((
        select jsonb_agg(shape.score_shape order by shape.score_shape)
        from public.profile_assessment_score_shapes_v024 shape
        where shape.assessment_definition_id = p_assessment_definition_id
      ), '[]'::jsonb),
      'sections', coalesce((
        select jsonb_agg(
          to_jsonb(section) - 'assessment_definition_id'
          order by section.display_order, section.section_key collate "C"
        )
        from public.profile_assessment_sections_v024 section
        where section.assessment_definition_id = p_assessment_definition_id
      ), '[]'::jsonb),
      'evidence', coalesce((
        select jsonb_agg(jsonb_build_object(
          'role', manifest.evidence_role,
          'evidenceId', manifest.evidence_id,
          'contentHash', evidence.content_hash,
          'retrievalContentHash', source.retrieval_content_hash
        ) order by manifest.evidence_role, manifest.evidence_id)
        from public.profile_assessment_definition_evidence_v024 manifest
        join public.evidence_items evidence
          on evidence.evidence_id = manifest.evidence_id
        join public.sources source on source.source_id = evidence.source_id
        where manifest.assessment_definition_id = p_assessment_definition_id
      ), '[]'::jsonb)
    )::text, 'UTF8'), 'sha256'), 'hex')
  into v_manifest;

  update public.profile_assessment_definitions_v024 definition
  set status = 'VERIFIED', manifest_hash = v_manifest,
      verified_by = btrim(p_verified_by), verified_at = now()
  where definition.assessment_definition_id = p_assessment_definition_id;
  return v_manifest;
end;
$function$;

create or replace function public.retire_profile_assessment_definition_v024(
  p_assessment_definition_id uuid,
  p_reason text
)
returns void
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = '22023',
      message = 'PROFILE_ASSESSMENT_RETIREMENT_REASON_REQUIRED';
  end if;
  update public.profile_assessment_definitions_v024 definition
  set status = 'RETIRED', retired_at = now(),
      retirement_reason = btrim(p_reason)
  where definition.assessment_definition_id = p_assessment_definition_id
    and definition.status = 'VERIFIED';
  if not found then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_VERIFIED_REQUIRED';
  end if;
end;
$function$;

alter table public.student_test_scores
  add constraint student_test_scores_taxonomy_pin_shape_v024
  check (
    (assessment_definition_id is null
      and taxonomy_release_ordinal_at_selection is null
      and taxonomy_reference_origin is null)
    or (assessment_definition_id is not null
      and taxonomy_release_ordinal_at_selection is not null
      and taxonomy_reference_origin is not null)
  );

alter table public.student_skills
  add constraint student_skills_taxonomy_pin_shape_v024
  check (
    (taxonomy_release_ordinal_at_selection is null
      and taxonomy_reference_origin is null)
    or (taxonomy_release_ordinal_at_selection is not null
      and taxonomy_reference_origin is not null)
  );

create or replace function private.profile_validate_section_scores_v019(
  p_scores jsonb
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_key text;
  v_value jsonb;
  v_count integer;
begin
  if p_scores is null or jsonb_typeof(p_scores) <> 'object' then
    raise exception using errcode = '22023',
      message = 'PROFILE_SECTION_SCORES_OBJECT_REQUIRED';
  end if;
  select count(*) into v_count from jsonb_object_keys(p_scores);
  if v_count > 64 then
    raise exception using errcode = '22023',
      message = 'PROFILE_ASSESSMENT_SECTION_INVALID';
  end if;
  for v_key, v_value in select key, value from jsonb_each(p_scores)
  loop
    if pg_catalog.octet_length(v_key) > 64
       or jsonb_typeof(v_value) <> 'number'
       or (v_value #>> '{}')::numeric < 0 then
      raise exception using errcode = '22023',
        message = 'PROFILE_ASSESSMENT_SECTION_INVALID';
    end if;
  end loop;
  return p_scores;
end;
$function$;

create or replace function private.profile_resolve_assessment_definition_v024(
  p_assessment_concept_id uuid,
  p_test_date date,
  p_release_ordinal bigint
)
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_definition_id uuid;
  v_count bigint;
begin
  select (array_agg(
      definition.assessment_definition_id
      order by definition.assessment_definition_id
    ))[1], count(*)
  into v_definition_id, v_count
  from public.profile_assessment_definitions_v024 definition
  where definition.assessment_concept_id = p_assessment_concept_id
    and definition.status = 'VERIFIED'
    and definition.effective_release_ordinal <= p_release_ordinal
    and definition.valid_test_date_from <= p_test_date
    and (
      definition.valid_test_date_to is null
      or definition.valid_test_date_to >= p_test_date
    );
  if v_count = 0 then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_UNSUPPORTED';
  end if;
  if v_count <> 1 then
    raise exception using errcode = 'XX000',
      message = 'PROFILE_ASSESSMENT_DEFINITION_AMBIGUOUS';
  end if;
  return v_definition_id;
end;
$function$;

create or replace function private.profile_validate_assessment_score_v024(
  p_assessment_definition_id uuid,
  p_total_score numeric,
  p_section_scores jsonb
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_definition public.profile_assessment_definitions_v024%rowtype;
  v_total_present boolean := p_total_score is not null;
  v_section_count integer;
  v_complete boolean;
  v_shape public.profile_assessment_score_shape_v024;
  v_section record;
  v_value numeric;
begin
  if p_section_scores is null or jsonb_typeof(p_section_scores) <> 'object' then
    raise exception using errcode = '22023',
      message = 'PROFILE_ASSESSMENT_SECTION_INVALID';
  end if;
  select count(*) into v_section_count
  from jsonb_object_keys(p_section_scores);
  if not v_total_present and v_section_count = 0 then
    raise exception using errcode = '22023',
      message = 'PROFILE_ASSESSMENT_SCORE_INVALID';
  end if;

  select definition.* into v_definition
  from public.profile_assessment_definitions_v024 definition
  where definition.assessment_definition_id = p_assessment_definition_id;
  if not found or v_definition.status not in ('VERIFIED', 'RETIRED') then
    raise exception using errcode = '55000',
      message = 'PROFILE_ASSESSMENT_UNSUPPORTED';
  end if;

  if exists (
    select 1 from jsonb_object_keys(p_section_scores) key
    where not exists (
      select 1 from public.profile_assessment_sections_v024 section
      where section.assessment_definition_id = p_assessment_definition_id
        and section.section_key = key
    )
  ) then
    raise exception using errcode = '22023',
      message = 'PROFILE_ASSESSMENT_SECTION_INVALID';
  end if;

  v_complete := v_section_count > 0
    and not exists (
      select 1
      from public.profile_assessment_sections_v024 section
      where section.assessment_definition_id = p_assessment_definition_id
        and section.required_in_complete_set
        and not (p_section_scores ? section.section_key)
    )
    and not exists (
      select 1
      from jsonb_object_keys(p_section_scores) key
      join public.profile_assessment_sections_v024 section
        on section.assessment_definition_id = p_assessment_definition_id
       and section.section_key = key
      where not section.required_in_complete_set
    );
  if v_total_present and v_section_count = 0 then
    v_shape := 'TOTAL_ONLY';
  elsif not v_total_present and v_complete then
    v_shape := 'SECTIONS_ONLY_COMPLETE';
  elsif not v_total_present then
    v_shape := 'SECTIONS_ONLY_PARTIAL';
  elsif v_complete then
    v_shape := 'TOTAL_AND_COMPLETE_SECTIONS';
  else
    v_shape := 'TOTAL_AND_PARTIAL_SECTIONS';
  end if;

  if not exists (
    select 1 from public.profile_assessment_score_shapes_v024 shape
    where shape.assessment_definition_id = p_assessment_definition_id
      and shape.score_shape = v_shape
  ) then
    raise exception using errcode = '22023',
      message = 'PROFILE_ASSESSMENT_SCORE_INVALID';
  end if;

  if v_total_present and (
    p_total_score < v_definition.total_min
    or p_total_score > v_definition.total_max
    or mod(
      p_total_score - v_definition.total_min,
      v_definition.total_increment
    ) <> 0
    or round(p_total_score, v_definition.total_scale) <> p_total_score
  ) then
    raise exception using errcode = '22023',
      message = 'PROFILE_ASSESSMENT_SCORE_INVALID';
  end if;

  for v_section in
    select section.*
    from public.profile_assessment_sections_v024 section
    where section.assessment_definition_id = p_assessment_definition_id
      and p_section_scores ? section.section_key
  loop
    begin
      v_value := (p_section_scores ->> v_section.section_key)::numeric;
    exception when others then
      raise exception using errcode = '22023',
        message = 'PROFILE_ASSESSMENT_SECTION_INVALID';
    end;
    if v_value < v_section.score_min
       or v_value > v_section.score_max
       or mod(v_value - v_section.score_min, v_section.score_increment) <> 0
       or round(v_value, v_section.score_scale) <> v_value then
      raise exception using errcode = '22023',
        message = 'PROFILE_ASSESSMENT_SECTION_INVALID';
    end if;
  end loop;
end;
$function$;

create or replace function public.validate_student_taxonomy_kind()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_release_ordinal bigint;
  v_definition_id uuid;
  v_context_source uuid;
  v_source_count bigint;
  v_source_pin_count bigint;
  v_source_definition_id uuid;
  v_source_release_ordinal bigint;
  v_context_origin public.profile_taxonomy_reference_origin_v024;
begin
  select context.source_profile_version_id
  into v_context_source
  from private.profile_fork_context_v024 context
  join public.student_profile_versions source_profile
    on source_profile.profile_version_id = context.source_profile_version_id
  join public.student_profile_versions target_profile
    on target_profile.profile_version_id = new.profile_version_id
  where context.backend_pid = pg_backend_pid()
    and context.transaction_id = txid_current()
    and source_profile.status = 'FROZEN'
    and source_profile.student_id = target_profile.student_id
    and source_profile.student_id = private.profile_student_for_auth_v019();

  if tg_table_name = 'student_test_scores' then
    if tg_op = 'UPDATE'
       and old.assessment_definition_id is null
       and v_context_source is null then
      raise exception using errcode = '55000',
        message = 'PROFILE_ASSESSMENT_UNSUPPORTED';
    end if;

    if v_context_source is not null and tg_op = 'INSERT' then
      select count(*),
        count(distinct concat_ws(':',
          coalesce(source.assessment_definition_id::text, 'LEGACY'),
          coalesce(source.taxonomy_release_ordinal_at_selection::text, 'LEGACY')
        )),
        (array_agg(source.assessment_definition_id))[1],
        (array_agg(source.taxonomy_release_ordinal_at_selection))[1]
      into v_source_count, v_source_pin_count,
        v_source_definition_id, v_source_release_ordinal
      from public.student_test_scores source
      where source.profile_version_id = v_context_source
        and source.assessment_concept_id = new.assessment_concept_id
        and source.test_date = new.test_date
        and source.total_score is not distinct from new.total_score
        and source.section_scores = new.section_scores;
      if v_source_count = 0 or v_source_pin_count <> 1 then
        raise exception using errcode = '55000',
          message = 'PROFILE_FORK_GRAPH_INVALID';
      end if;
      new.assessment_definition_id := v_source_definition_id;
      new.taxonomy_release_ordinal_at_selection := v_source_release_ordinal;
      new.taxonomy_reference_origin := case
        when v_source_definition_id is null then null
        else 'HISTORICAL_FORK' end;
      return new;
    end if;

    v_release_ordinal := private.profile_require_verified_active_concept_v024(
      new.assessment_concept_id, 'ASSESSMENT'
    );
    if tg_op = 'UPDATE'
       and old.taxonomy_reference_origin = 'HISTORICAL_FORK'
       and new.assessment_concept_id = old.assessment_concept_id then
      if new.test_date is distinct from old.test_date then
        raise exception using errcode = '55000',
          message = 'PROFILE_ASSESSMENT_UNSUPPORTED';
      end if;
      v_definition_id := old.assessment_definition_id;
      v_release_ordinal := old.taxonomy_release_ordinal_at_selection;
    else
      v_definition_id := private.profile_resolve_assessment_definition_v024(
        new.assessment_concept_id, new.test_date, v_release_ordinal
      );
    end if;
    perform private.profile_validate_assessment_score_v024(
      v_definition_id, new.total_score, new.section_scores
    );
    new.assessment_definition_id := v_definition_id;
    new.taxonomy_release_ordinal_at_selection := v_release_ordinal;
    new.taxonomy_reference_origin := case
      when tg_op = 'UPDATE'
        and old.taxonomy_reference_origin = 'HISTORICAL_FORK'
        and new.assessment_concept_id = old.assessment_concept_id
      then 'HISTORICAL_FORK'
      else 'NEW_SELECTION' end;
    return new;
  end if;

  if tg_table_name = 'student_skills' then
    if v_context_source is not null and tg_op = 'INSERT' then
      select count(*),
        (array_agg(source.taxonomy_release_ordinal_at_selection))[1]
      into v_source_count, v_source_release_ordinal
      from public.student_skills source
      where source.profile_version_id = v_context_source
        and source.skill_concept_id = new.skill_concept_id
        and source.proficiency_level is not distinct from new.proficiency_level
        and source.years_experience is not distinct from new.years_experience;
      if v_source_count <> 1 then
        raise exception using errcode = '55000',
          message = 'PROFILE_FORK_GRAPH_INVALID';
      end if;
      new.taxonomy_release_ordinal_at_selection := v_source_release_ordinal;
      new.taxonomy_reference_origin := case
        when v_source_release_ordinal is null then null
        else 'HISTORICAL_FORK' end;
      return new;
    end if;

    if tg_op = 'UPDATE'
       and old.taxonomy_release_ordinal_at_selection is null then
      raise exception using errcode = '55000',
        message = 'PROFILE_TAXONOMY_CONCEPT_INACTIVE';
    end if;
    v_release_ordinal := private.profile_require_verified_active_concept_v024(
      new.skill_concept_id, 'SKILL'
    );
    if tg_op = 'UPDATE'
       and old.taxonomy_reference_origin = 'HISTORICAL_FORK'
       and new.skill_concept_id = old.skill_concept_id then
      new.taxonomy_release_ordinal_at_selection :=
        old.taxonomy_release_ordinal_at_selection;
      new.taxonomy_reference_origin := 'HISTORICAL_FORK';
    else
      new.taxonomy_release_ordinal_at_selection := v_release_ordinal;
      new.taxonomy_reference_origin := 'NEW_SELECTION';
    end if;
    return new;
  end if;
  return new;
end;
$function$;

alter function public.fork_frozen_profile_to_draft_v020(uuid,uuid)
  rename to profile_fork_v020_impl_v024;
alter function public.profile_fork_v020_impl_v024(uuid,uuid)
  set schema private;

revoke all on function private.profile_fork_v020_impl_v024(uuid,uuid)
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_evaluation_executor;
grant execute on function private.profile_fork_v020_impl_v024(uuid,uuid)
to foundation_student_executor;

create or replace function public.fork_frozen_profile_to_draft_v020(
  p_source_profile_version_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_result jsonb;
begin
  if p_source_profile_version_id is null or p_operation_id is null then
    raise exception using errcode = '22023',
      message = 'PROFILE_FORK_ARGUMENT_REQUIRED';
  end if;
  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  if not exists (
    select 1 from public.student_profile_versions source_profile
    where source_profile.profile_version_id = p_source_profile_version_id
      and source_profile.student_id = v_student_id
      and source_profile.status = 'FROZEN'
  ) then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;

  insert into private.profile_fork_context_v024 (
    backend_pid, transaction_id, source_profile_version_id
  ) values (
    pg_backend_pid(), txid_current(), p_source_profile_version_id
  );

  v_result := private.profile_fork_v020_impl_v024(
    p_source_profile_version_id, p_operation_id
  );

  delete from private.profile_fork_context_v024 context
  where context.backend_pid = pg_backend_pid()
    and context.transaction_id = txid_current();
  return v_result;
end;
$function$;

grant create on schema public, private to foundation_student_executor;
grant create on schema private to foundation_catalog_executor;
alter function public.fork_frozen_profile_to_draft_v020(uuid,uuid)
  owner to foundation_student_executor;
alter function public.validate_student_taxonomy_kind()
  owner to foundation_student_executor;
alter function private.profile_require_verified_active_concept_v024(
  uuid, public.taxonomy_concept_kind
) owner to foundation_student_executor;
alter function private.profile_resolve_assessment_definition_v024(
  uuid,date,bigint
) owner to foundation_student_executor;
alter function private.profile_validate_assessment_score_v024(
  uuid,numeric,jsonb
) owner to foundation_student_executor;
alter function private.profile_validate_section_scores_v019(jsonb)
  owner to foundation_student_executor;
alter function private.profile_assessment_definition_guard_v024()
  owner to foundation_catalog_executor;
alter function private.profile_assessment_child_guard_v024()
  owner to foundation_catalog_executor;
revoke create on schema public, private from foundation_student_executor;
revoke create on schema private from foundation_catalog_executor;

revoke all on function public.fork_frozen_profile_to_draft_v020(uuid,uuid)
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant execute on function public.fork_frozen_profile_to_draft_v020(uuid,uuid)
to authenticated;

revoke all on function public.validate_student_taxonomy_kind()
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;

create or replace function public.get_profile_taxonomy_projection_v024(
  p_profile_version_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_profile_id uuid;
  v_release_code text;
  v_release_ordinal bigint;
begin
  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  if p_profile_version_id is null then
    select profile.profile_version_id into v_profile_id
    from public.student_profile_versions profile
    where profile.student_id = v_student_id
      and profile.product_managed and profile.status = 'DRAFT'
    order by profile.version_number desc limit 1;
  else
    select profile.profile_version_id into v_profile_id
    from public.student_profile_versions profile
    where profile.profile_version_id = p_profile_version_id
      and profile.student_id = v_student_id;
  end if;
  if v_profile_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  select release.release_code, release.release_ordinal
  into v_release_code, v_release_ordinal
  from public.taxonomy_releases release
  where release.status = 'VERIFIED'
  order by release.release_ordinal desc, release.release_code collate "C" desc
  limit 1;
  if v_release_ordinal is null then
    raise exception using errcode = '55000',
      message = 'PROFILE_TAXONOMY_CONCEPT_INVALID';
  end if;

  return jsonb_build_object(
    'schemaVersion', 'PROFILE_TAXONOMY_PROJECTION_V024',
    'releaseCode', v_release_code,
    'releaseOrdinal', v_release_ordinal,
    'concepts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'conceptId', referenced.concept_id,
        'canonicalKey', referenced.canonical_key,
        'conceptKind', referenced.concept_kind,
        'displayName', referenced.display_name,
        'activeAtRelease',
          referenced.introduced_release_ordinal <= v_release_ordinal
          and (referenced.retired_release_ordinal is null
            or referenced.retired_release_ordinal > v_release_ordinal)
      ) order by referenced.canonical_key collate "C", referenced.concept_id)
      from (
        select distinct concept.concept_id, concept.canonical_key,
          concept.concept_kind, concept.display_name,
          concept.introduced_release_ordinal,
          concept.retired_release_ordinal
        from public.taxonomy_concepts concept
        join (
          select mapping.concept_id
          from public.student_record_concept_mappings mapping
          where mapping.profile_version_id = v_profile_id
          union
          select score.assessment_concept_id
          from public.student_test_scores score
          where score.profile_version_id = v_profile_id
          union
          select skill.skill_concept_id
          from public.student_skills skill
          where skill.profile_version_id = v_profile_id
        ) used on used.concept_id = concept.concept_id
        where concept.concept_kind in (
          'FIELD', 'SUBFIELD', 'COURSE_CONCEPT', 'ASSESSMENT', 'SKILL'
        )
      ) referenced
    ), '[]'::jsonb)
  );
end;
$function$;

create or replace function public.get_profile_assessment_definitions_v024()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_release_code text;
  v_release_ordinal bigint;
  v_count bigint;
  v_max_definitions constant integer := 64;
begin
  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  select release.release_code, release.release_ordinal
  into v_release_code, v_release_ordinal
  from public.taxonomy_releases release
  where release.status = 'VERIFIED'
  order by release.release_ordinal desc, release.release_code collate "C" desc
  limit 1;
  if v_release_ordinal is null then
    raise exception using errcode = '55000',
      message = 'PROFILE_TAXONOMY_CONCEPT_INVALID';
  end if;

  select count(*) into v_count
  from public.profile_assessment_definitions_v024 definition
  join public.taxonomy_concepts concept
    on concept.concept_id = definition.assessment_concept_id
  where definition.status = 'VERIFIED'
    and definition.effective_release_ordinal <= v_release_ordinal
    and concept.concept_kind = 'ASSESSMENT'
    and concept.introduced_release_ordinal <= v_release_ordinal
    and (concept.retired_release_ordinal is null
      or concept.retired_release_ordinal > v_release_ordinal);
  if v_count > v_max_definitions then
    raise exception using errcode = '54000',
      message = 'PROFILE_ASSESSMENT_DEFINITION_LIMIT_EXCEEDED';
  end if;

  return jsonb_build_object(
    'schemaVersion', 'PROFILE_ASSESSMENT_DEFINITIONS_V024',
    'releaseCode', v_release_code,
    'releaseOrdinal', v_release_ordinal,
    'definitions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'assessmentDefinitionId', definition.assessment_definition_id,
        'assessmentConceptId', definition.assessment_concept_id,
        'canonicalKey', concept.canonical_key,
        'displayName', concept.display_name,
        'definitionVersion', definition.definition_version,
        'formatCode', definition.format_code,
        'validTestDateFrom', definition.valid_test_date_from,
        'validTestDateTo', definition.valid_test_date_to,
        'total', case when definition.total_min is null then null else
          jsonb_build_object(
            'minimum', definition.total_min,
            'maximum', definition.total_max,
            'increment', definition.total_increment,
            'scale', definition.total_scale
          ) end,
        'scoreShapes', coalesce((
          select jsonb_agg(shape.score_shape order by shape.score_shape)
          from public.profile_assessment_score_shapes_v024 shape
          where shape.assessment_definition_id =
            definition.assessment_definition_id
        ), '[]'::jsonb),
        'sections', coalesce((
          select jsonb_agg(jsonb_build_object(
            'sectionKey', section.section_key,
            'displayName', section.display_name,
            'minimum', section.score_min,
            'maximum', section.score_max,
            'increment', section.score_increment,
            'scale', section.score_scale,
            'requiredInCompleteSet', section.required_in_complete_set,
            'displayOrder', section.display_order
          ) order by section.display_order, section.section_key collate "C")
          from public.profile_assessment_sections_v024 section
          where section.assessment_definition_id =
            definition.assessment_definition_id
        ), '[]'::jsonb)
      ) order by concept.canonical_key collate "C", definition.format_code,
        definition.definition_version)
      from public.profile_assessment_definitions_v024 definition
      join public.taxonomy_concepts concept
        on concept.concept_id = definition.assessment_concept_id
      where definition.status = 'VERIFIED'
        and definition.effective_release_ordinal <= v_release_ordinal
        and concept.concept_kind = 'ASSESSMENT'
        and concept.introduced_release_ordinal <= v_release_ordinal
        and (concept.retired_release_ordinal is null
          or concept.retired_release_ordinal > v_release_ordinal)
    ), '[]'::jsonb)
  );
end;
$function$;

grant create on schema public to foundation_student_executor;
alter function public.get_profile_taxonomy_projection_v024(uuid)
  owner to foundation_student_executor;
alter function public.get_profile_assessment_definitions_v024()
  owner to foundation_student_executor;
revoke create on schema public from foundation_student_executor;

revoke all on function public.get_profile_taxonomy_projection_v024(uuid)
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
revoke all on function public.get_profile_assessment_definitions_v024()
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant execute on function public.get_profile_taxonomy_projection_v024(uuid),
  public.get_profile_assessment_definitions_v024()
to authenticated;

grant create on schema public to foundation_catalog_executor;
alter function public.create_profile_assessment_definition_v024(
  uuid,bigint,text,text,date,date,numeric,numeric,numeric,smallint,uuid
) owner to foundation_catalog_executor;
alter function public.add_profile_assessment_score_shape_v024(
  uuid,public.profile_assessment_score_shape_v024
) owner to foundation_catalog_executor;
alter function public.add_profile_assessment_section_v024(
  uuid,text,text,numeric,numeric,numeric,smallint,boolean,smallint
) owner to foundation_catalog_executor;
alter function public.add_profile_assessment_evidence_v024(
  uuid,public.profile_assessment_evidence_role_v024,uuid
) owner to foundation_catalog_executor;
alter function public.verify_profile_assessment_definition_v024(uuid,text)
  owner to foundation_catalog_executor;
alter function public.retire_profile_assessment_definition_v024(uuid,text)
  owner to foundation_catalog_executor;
revoke create on schema public from foundation_catalog_executor;

revoke all on function public.create_profile_assessment_definition_v024(
  uuid,bigint,text,text,date,date,numeric,numeric,numeric,smallint,uuid
) from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
revoke all on function public.add_profile_assessment_score_shape_v024(
  uuid,public.profile_assessment_score_shape_v024
) from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
revoke all on function public.add_profile_assessment_section_v024(
  uuid,text,text,numeric,numeric,numeric,smallint,boolean,smallint
) from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
revoke all on function public.add_profile_assessment_evidence_v024(
  uuid,public.profile_assessment_evidence_role_v024,uuid
) from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
revoke all on function public.verify_profile_assessment_definition_v024(
  uuid,text
) from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
revoke all on function public.retire_profile_assessment_definition_v024(
  uuid,text
) from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;

grant execute on function public.create_profile_assessment_definition_v024(
  uuid,bigint,text,text,date,date,numeric,numeric,numeric,smallint,uuid
), public.add_profile_assessment_score_shape_v024(
  uuid,public.profile_assessment_score_shape_v024
), public.add_profile_assessment_section_v024(
  uuid,text,text,numeric,numeric,numeric,smallint,boolean,smallint
), public.add_profile_assessment_evidence_v024(
  uuid,public.profile_assessment_evidence_role_v024,uuid
), public.verify_profile_assessment_definition_v024(uuid,text),
  public.retire_profile_assessment_definition_v024(uuid,text)
to foundation_catalog_executor;

revoke all on function private.profile_require_verified_active_concept_v024(
  uuid,public.taxonomy_concept_kind
), private.profile_resolve_assessment_definition_v024(uuid,date,bigint),
  private.profile_validate_assessment_score_v024(uuid,numeric,jsonb),
  private.profile_assessment_definition_guard_v024(),
  private.profile_assessment_child_guard_v024()
from public, anon, authenticated, service_role, authenticator,
  foundation_evaluation_executor;

do $contracts$
declare
  v_function record;
  v_allowed text[];
begin
  for v_function in
    select namespace.nspname as schema_name, procedure.proname,
      pg_get_function_identity_arguments(procedure.oid) as identity_arguments,
      procedure.proowner::regrole::text as owner_role,
      procedure.prosecdef,
      pg_get_functiondef(procedure.oid) as definition
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname = 'public'
      and procedure.proname in (
        'fork_frozen_profile_to_draft_v020',
        'get_profile_taxonomy_projection_v024',
        'get_profile_assessment_definitions_v024',
        'create_profile_assessment_definition_v024',
        'add_profile_assessment_score_shape_v024',
        'add_profile_assessment_section_v024',
        'add_profile_assessment_evidence_v024',
        'verify_profile_assessment_definition_v024',
        'retire_profile_assessment_definition_v024'
      )
  loop
    v_allowed := case
      when v_function.proname in (
        'fork_frozen_profile_to_draft_v020',
        'get_profile_taxonomy_projection_v024',
        'get_profile_assessment_definitions_v024'
      ) then array['authenticated']::text[]
      else array['foundation_catalog_executor']::text[]
    end;
    insert into public.foundation_function_contracts (
      schema_name, function_name, identity_arguments, owner_role, prosecdef,
      search_path, allowed_caller_roles, body_digest
    ) values (
      v_function.schema_name, v_function.proname,
      v_function.identity_arguments, v_function.owner_role,
      v_function.prosecdef,
      'pg_catalog, public, private, extensions', v_allowed,
      encode(extensions.digest(
        convert_to(v_function.definition, 'UTF8'), 'sha256'
      ), 'hex')
    )
    on conflict (schema_name, function_name, identity_arguments) do update
    set owner_role = excluded.owner_role,
        prosecdef = excluded.prosecdef,
        search_path = excluded.search_path,
        allowed_caller_roles = excluded.allowed_caller_roles,
        body_digest = excluded.body_digest;
  end loop;
end;
$contracts$;

comment on function private.profile_require_verified_active_concept_v024(
  uuid,public.taxonomy_concept_kind
) is 'Shared highest-VERIFIED active-at-release authority for Profile ASSESSMENT and SKILL mutations.';
comment on function public.get_profile_taxonomy_projection_v024(uuid) is
  'Owner-scoped referenced-concept projection including historical ASSESSMENT and SKILL labels. displayName is the current canonical catalog label at query time.';
comment on function public.get_profile_assessment_definitions_v024() is
  'Bounded rendering contract for currently supported VERIFIED assessment definitions; evidence and control metadata are excluded.';
comment on column public.student_test_scores.assessment_definition_id is
  'Server-resolved immutable definition pin. NULL identifies a legacy row and is never reinterpreted.';
comment on column public.student_skills.taxonomy_release_ordinal_at_selection is
  'Server-resolved taxonomy release pin for a student self-report; it is not verification, employer rating, Eligibility proof, Fit output, or Competitiveness signal.';

do $assert$
declare
  v_function_oid oid;
begin
  if exists (
    select 1 from public.profile_assessment_definitions_v024
  ) then
    raise exception '024 assertion failed: production definition seed';
  end if;

  if exists (
    select 1 from information_schema.role_table_grants privilege
    where privilege.table_schema in ('public', 'private')
      and privilege.table_name in (
        'profile_assessment_definitions_v024',
        'profile_assessment_score_shapes_v024',
        'profile_assessment_sections_v024',
        'profile_assessment_definition_evidence_v024',
        'profile_fork_context_v024'
      )
      and privilege.grantee in (
        'PUBLIC', 'anon', 'authenticated', 'service_role', 'authenticator'
      )
  ) then
    raise exception '024 assertion failed: direct external table ACL';
  end if;

  if exists (
    select 1
    from unnest(array[
      'foundation_catalog_executor', 'foundation_student_executor',
      'anon', 'authenticated', 'authenticator', 'service_role'
    ]::text[]) role_name
    cross join unnest(array['public', 'private']::text[]) schema_name
    where has_schema_privilege(role_name, schema_name, 'CREATE')
  ) or exists (
    select 1
    from pg_namespace namespace
    cross join lateral aclexplode(coalesce(
      namespace.nspacl, acldefault('n', namespace.nspowner)
    )) privilege
    where namespace.nspname in ('public', 'private')
      and privilege.grantee = 0
      and privilege.privilege_type = 'CREATE'
  ) then
    raise exception '024 assertion failed: temporary schema CREATE survived';
  end if;

  if not has_schema_privilege(
    'foundation_catalog_executor', 'public', 'USAGE'
  ) or not has_schema_privilege(
    'foundation_catalog_executor', 'private', 'USAGE'
  ) or not has_schema_privilege(
    'foundation_student_executor', 'public', 'USAGE'
  ) or not has_schema_privilege(
    'foundation_student_executor', 'private', 'USAGE'
  ) then
    raise exception '024 assertion failed: required executor schema USAGE';
  end if;

  if exists (
    select 1
    from (values
      ('public', 'profile_assessment_definitions_v024',
        'foundation_catalog_executor'),
      ('public', 'profile_assessment_score_shapes_v024',
        'foundation_catalog_executor'),
      ('public', 'profile_assessment_sections_v024',
        'foundation_catalog_executor'),
      ('public', 'profile_assessment_definition_evidence_v024',
        'foundation_catalog_executor'),
      ('private', 'profile_fork_context_v024',
        'foundation_student_executor')
    ) expected(schema_name, object_name, owner_role)
    left join pg_namespace namespace
      on namespace.nspname = expected.schema_name
    left join pg_class relation
      on relation.relnamespace = namespace.oid
      and relation.relname = expected.object_name
    where relation.oid is null
      or pg_get_userbyid(relation.relowner) <> expected.owner_role
  ) then
    raise exception '024 assertion failed: table owner';
  end if;

  if exists (
    select 1
    from (values
      ('private.profile_require_verified_active_concept_v024(uuid,public.taxonomy_concept_kind)',
        'foundation_student_executor'),
      ('private.profile_assessment_definition_guard_v024()',
        'foundation_catalog_executor'),
      ('private.profile_assessment_child_guard_v024()',
        'foundation_catalog_executor'),
      ('public.create_profile_assessment_definition_v024(uuid,bigint,text,text,date,date,numeric,numeric,numeric,smallint,uuid)',
        'foundation_catalog_executor'),
      ('public.add_profile_assessment_score_shape_v024(uuid,public.profile_assessment_score_shape_v024)',
        'foundation_catalog_executor'),
      ('public.add_profile_assessment_section_v024(uuid,text,text,numeric,numeric,numeric,smallint,boolean,smallint)',
        'foundation_catalog_executor'),
      ('public.add_profile_assessment_evidence_v024(uuid,public.profile_assessment_evidence_role_v024,uuid)',
        'foundation_catalog_executor'),
      ('public.verify_profile_assessment_definition_v024(uuid,text)',
        'foundation_catalog_executor'),
      ('public.retire_profile_assessment_definition_v024(uuid,text)',
        'foundation_catalog_executor'),
      ('private.profile_validate_section_scores_v019(jsonb)',
        'foundation_student_executor'),
      ('private.profile_resolve_assessment_definition_v024(uuid,date,bigint)',
        'foundation_student_executor'),
      ('private.profile_validate_assessment_score_v024(uuid,numeric,jsonb)',
        'foundation_student_executor'),
      ('public.validate_student_taxonomy_kind()',
        'foundation_student_executor'),
      ('private.profile_fork_v020_impl_v024(uuid,uuid)',
        'foundation_student_executor'),
      ('public.fork_frozen_profile_to_draft_v020(uuid,uuid)',
        'foundation_student_executor'),
      ('public.get_profile_taxonomy_projection_v024(uuid)',
        'foundation_student_executor'),
      ('public.get_profile_assessment_definitions_v024()',
        'foundation_student_executor')
    ) expected(function_identity, owner_role)
    left join pg_proc procedure
      on procedure.oid = to_regprocedure(expected.function_identity)
    where procedure.oid is null
      or pg_get_userbyid(procedure.proowner) <> expected.owner_role
      or not procedure.prosecdef
      or procedure.proconfig is distinct from array[
        'search_path=pg_catalog, public, private, extensions'
      ]::text[]
  ) then
    raise exception '024 assertion failed: function owner/security contract';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.fork_frozen_profile_to_draft_v020(uuid,uuid)', 'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.get_profile_taxonomy_projection_v024(uuid)', 'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.get_profile_assessment_definitions_v024()', 'EXECUTE'
  ) or has_function_privilege(
    'anon', 'public.get_profile_taxonomy_projection_v024(uuid)', 'EXECUTE'
  ) or has_function_privilege(
    'service_role',
    'public.get_profile_assessment_definitions_v024()', 'EXECUTE'
  ) then
    raise exception '024 assertion failed: browser function ACL';
  end if;

  if has_schema_privilege(
    'foundation_student_executor', 'auth', 'USAGE'
  ) or has_table_privilege(
    'foundation_student_executor', 'auth.users', 'SELECT'
  ) then
    raise exception '024 assertion failed: hosted Auth capability widened';
  end if;

  if exists (
    select 1 from public.foundation_function_contracts contract
    where contract.function_name in (
      'fork_frozen_profile_to_draft_v020',
      'get_profile_taxonomy_projection_v024',
      'get_profile_assessment_definitions_v024'
    ) and (
      contract.owner_role <> 'foundation_student_executor'
      or not contract.prosecdef
      or contract.search_path <>
        'pg_catalog, public, private, extensions'
      or contract.allowed_caller_roles <> array['authenticated']
      or contract.body_digest !~ '^[a-f0-9]{64}$'
    )
  ) then
    raise exception '024 assertion failed: browser function registry';
  end if;

  if not exists (
    select 1 from pg_trigger trigger_value
    join pg_proc procedure on procedure.oid = trigger_value.tgfoid
    where trigger_value.tgrelid = 'public.student_test_scores'::regclass
      and procedure.proname = 'validate_student_taxonomy_kind'
      and not trigger_value.tgisinternal
  ) or not exists (
    select 1 from pg_trigger trigger_value
    join pg_proc procedure on procedure.oid = trigger_value.tgfoid
    where trigger_value.tgrelid = 'public.student_skills'::regclass
      and procedure.proname = 'validate_student_taxonomy_kind'
      and not trigger_value.tgisinternal
  ) then
    raise exception '024 assertion failed: taxonomy mutation triggers';
  end if;
end;
$assert$;

commit;
