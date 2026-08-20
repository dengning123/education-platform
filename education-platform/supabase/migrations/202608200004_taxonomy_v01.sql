begin;

create type public.taxonomy_concept_kind as enum (
  'FIELD',
  'SUBFIELD',
  'SUBJECT',
  'COURSE_CONCEPT',
  'SKILL',
  'CAREER',
  'INDUSTRY',
  'ASSESSMENT'
);

create type public.taxonomy_relationship_type as enum (
  'BROADER_THAN',
  'RELATED_TO'
);

create type public.mapping_status as enum (
  'PROPOSED',
  'VERIFIED',
  'REJECTED',
  'RETIRED'
);

create type public.mapping_method as enum ('HUMAN', 'RULE', 'MODEL');

create type public.catalog_mapping_relation as enum (
  'FIELD_CLASSIFICATION',
  'SUBFIELD_CLASSIFICATION',
  'SUBJECT_CLASSIFICATION',
  'COURSE_EQUIVALENCY',
  'SKILL_ASSOCIATION',
  'CAREER_ASSOCIATION',
  'INDUSTRY_ASSOCIATION'
);

create table public.taxonomy_releases (
  release_code text primary key,
  published_at timestamptz not null,
  notes text,
  created_at timestamptz not null default now(),
  constraint taxonomy_releases_code_format
    check (release_code ~ '^v[0-9]+\.[0-9]+$')
);

create table public.taxonomy_concepts (
  concept_id uuid primary key default extensions.gen_random_uuid(),
  canonical_key text not null unique,
  concept_kind public.taxonomy_concept_kind not null,
  display_name text not null,
  description text,
  introduced_in_release text not null
    references public.taxonomy_releases(release_code) on delete restrict,
  retired_in_release text
    references public.taxonomy_releases(release_code) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint taxonomy_concepts_key_format
    check (canonical_key ~ '^[A-Z][A-Z0-9_]*(\.[A-Z0-9_]+)+$'),
  constraint taxonomy_concepts_display_not_blank
    check (btrim(display_name) <> ''),
  constraint taxonomy_concepts_retirement_order
    check (
      retired_in_release is null
      or retired_in_release <> introduced_in_release
    )
);

comment on column public.taxonomy_concepts.canonical_key is
  'Stable semantic identity across releases. Semantic changes require a new key.';

create table public.taxonomy_aliases (
  alias_id uuid primary key default extensions.gen_random_uuid(),
  concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  alias_text text not null,
  normalized_alias text generated always as (lower(btrim(alias_text))) stored,
  introduced_in_release text not null
    references public.taxonomy_releases(release_code) on delete restrict,
  retired_in_release text
    references public.taxonomy_releases(release_code) on delete restrict,
  created_at timestamptz not null default now(),
  constraint taxonomy_aliases_not_blank check (btrim(alias_text) <> ''),
  unique (concept_id, normalized_alias, introduced_in_release)
);

create table public.taxonomy_relationships (
  relationship_id uuid primary key default extensions.gen_random_uuid(),
  source_concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  target_concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  relationship_type public.taxonomy_relationship_type not null,
  introduced_in_release text not null
    references public.taxonomy_releases(release_code) on delete restrict,
  retired_in_release text
    references public.taxonomy_releases(release_code) on delete restrict,
  created_at timestamptz not null default now(),
  constraint taxonomy_relationships_no_self
    check (source_concept_id <> target_concept_id),
  unique (
    source_concept_id,
    target_concept_id,
    relationship_type,
    introduced_in_release
  )
);

create table public.catalog_concept_mappings (
  mapping_id uuid primary key default extensions.gen_random_uuid(),
  record_type public.catalog_record_type not null,
  record_id uuid not null,
  concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  relation public.catalog_mapping_relation not null,
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
    references public.catalog_concept_mappings(mapping_id) on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  constraint catalog_concept_mappings_confidence_range
    check (confidence is null or confidence between 0 and 1),
  constraint catalog_concept_mappings_model_version
    check (method <> 'MODEL' or nullif(btrim(model_version), '') is not null),
  constraint catalog_concept_mappings_review_authority
    check (
      mapping_status not in ('VERIFIED', 'REJECTED')
      or (
        nullif(btrim(reviewed_by), '') is not null
        and reviewed_at is not null
      )
    ),
  constraint catalog_concept_mappings_verified_evidence
    check (
      mapping_status <> 'VERIFIED'
      or verification_evidence_id is not null
    ),
  constraint catalog_concept_mappings_retirement_pair
    check (
      (mapping_status = 'RETIRED')
      = (retired_at is not null and retirement_reason is not null)
    )
);

create unique index catalog_concept_mappings_active_unique
  on public.catalog_concept_mappings (
    record_type,
    record_id,
    concept_id,
    relation
  )
  where mapping_status in ('PROPOSED', 'VERIFIED');

create index taxonomy_concepts_kind_idx
  on public.taxonomy_concepts (concept_kind, canonical_key);
create index taxonomy_aliases_lookup_idx
  on public.taxonomy_aliases (normalized_alias);
create index taxonomy_relationships_target_idx
  on public.taxonomy_relationships (target_concept_id, relationship_type);
create index catalog_concept_mappings_record_idx
  on public.catalog_concept_mappings (record_type, record_id, mapping_status);

create trigger taxonomy_concepts_set_updated_at
before update on public.taxonomy_concepts
for each row execute function public.set_updated_at();

create or replace function public.guard_taxonomy_identity()
returns trigger
language plpgsql
as $$
begin
  if tg_table_name = 'taxonomy_releases' then
    raise exception 'Taxonomy releases are immutable';
  end if;
  if new.canonical_key is distinct from old.canonical_key
     or new.concept_kind is distinct from old.concept_kind
     or new.introduced_in_release is distinct from old.introduced_in_release then
    raise exception 'Taxonomy semantic identity is immutable; retire and create a new key';
  end if;
  return new;
end;
$$;

create or replace function public.guard_catalog_mapping_history()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Catalog mappings are historical and cannot be deleted';
  end if;
  if old.mapping_status in ('REJECTED', 'RETIRED') then
    raise exception 'Rejected and retired mappings are immutable';
  end if;
  if old.mapping_status = 'VERIFIED'
     and new.mapping_status <> 'RETIRED' then
    raise exception 'Verified mappings may only transition to RETIRED';
  end if;
  return new;
end;
$$;

create trigger taxonomy_releases_immutable
before update or delete on public.taxonomy_releases
for each row execute function public.guard_taxonomy_identity();
create trigger taxonomy_concepts_identity_guard
before update on public.taxonomy_concepts
for each row execute function public.guard_taxonomy_identity();
create trigger catalog_concept_mappings_history_guard
before update or delete on public.catalog_concept_mappings
for each row execute function public.guard_catalog_mapping_history();

create or replace function public.validate_catalog_concept_mapping_record()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_table_name text;
  v_primary_key text;
  v_exists boolean;
begin
  v_table_name := public.catalog_table_name(new.record_type);
  v_primary_key := public.catalog_primary_key(new.record_type);
  execute format(
    'select exists(select 1 from public.%I where %I = $1 and retired_at is null)',
    v_table_name,
    v_primary_key
  ) into v_exists using new.record_id;

  if not v_exists then
    raise exception 'Active catalog record % % does not exist',
      new.record_type,
      new.record_id;
  end if;
  return new;
end;
$$;

create trigger catalog_concept_mappings_validate_record
before insert or update of record_type, record_id
on public.catalog_concept_mappings
for each row execute function public.validate_catalog_concept_mapping_record();

create or replace function public.audit_phase2_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row jsonb;
  v_record_id uuid;
begin
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_record_id := (v_row ->> tg_argv[0])::uuid;

  insert into public.audit_events (
    table_name,
    record_id,
    operation,
    old_row,
    new_row,
    actor
  ) values (
    tg_table_name,
    v_record_id,
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

create trigger taxonomy_concepts_audit
after insert or update or delete on public.taxonomy_concepts
for each row execute function public.audit_phase2_change('concept_id');
create trigger taxonomy_aliases_audit
after insert or update or delete on public.taxonomy_aliases
for each row execute function public.audit_phase2_change('alias_id');
create trigger taxonomy_relationships_audit
after insert or update or delete on public.taxonomy_relationships
for each row execute function public.audit_phase2_change('relationship_id');
create trigger catalog_concept_mappings_audit
after insert or update or delete on public.catalog_concept_mappings
for each row execute function public.audit_phase2_change('mapping_id');

alter table public.taxonomy_releases enable row level security;
alter table public.taxonomy_concepts enable row level security;
alter table public.taxonomy_aliases enable row level security;
alter table public.taxonomy_relationships enable row level security;
alter table public.catalog_concept_mappings enable row level security;

create policy taxonomy_releases_public_read
  on public.taxonomy_releases for select to public using (true);
create policy taxonomy_concepts_public_read
  on public.taxonomy_concepts for select to public using (true);
create policy taxonomy_aliases_public_read
  on public.taxonomy_aliases for select to public using (true);
create policy taxonomy_relationships_public_read
  on public.taxonomy_relationships for select to public using (true);
create policy catalog_concept_mappings_public_read
  on public.catalog_concept_mappings for select to public
  using (mapping_status = 'VERIFIED');

insert into public.taxonomy_releases (
  release_code,
  published_at,
  notes
) values (
  'v0.1',
  timestamptz '2026-08-20 00:00:00+00',
  'Minimal concepts required for Phase 2 eligibility fixtures.'
) on conflict do nothing;

insert into public.taxonomy_concepts (
  concept_id,
  canonical_key,
  concept_kind,
  display_name,
  introduced_in_release
) values
  ('10000000-0000-0000-0000-000000000001', 'FIELD.ECONOMICS', 'FIELD', 'Economics', 'v0.1'),
  ('10000000-0000-0000-0000-000000000002', 'FIELD.FINANCE', 'FIELD', 'Finance', 'v0.1'),
  ('10000000-0000-0000-0000-000000000003', 'FIELD.MATHEMATICS', 'FIELD', 'Mathematics', 'v0.1'),
  ('10000000-0000-0000-0000-000000000004', 'FIELD.STATISTICS', 'FIELD', 'Statistics', 'v0.1'),
  ('10000000-0000-0000-0000-000000000005', 'FIELD.COMPUTER_SCIENCE', 'FIELD', 'Computer Science', 'v0.1'),
  ('10000000-0000-0000-0000-000000000011', 'SUBFIELD.QUANTITATIVE_ECONOMICS', 'SUBFIELD', 'Quantitative Economics', 'v0.1'),
  ('10000000-0000-0000-0000-000000000012', 'SUBFIELD.QUANTITATIVE_FINANCE', 'SUBFIELD', 'Quantitative Finance', 'v0.1'),
  ('10000000-0000-0000-0000-000000000021', 'SUBJECT.MATHEMATICS', 'SUBJECT', 'Mathematics', 'v0.1'),
  ('10000000-0000-0000-0000-000000000022', 'SUBJECT.STATISTICS', 'SUBJECT', 'Statistics', 'v0.1'),
  ('10000000-0000-0000-0000-000000000023', 'SUBJECT.ECONOMETRICS', 'SUBJECT', 'Econometrics', 'v0.1'),
  ('10000000-0000-0000-0000-000000000024', 'SUBJECT.COMPUTING', 'SUBJECT', 'Computing', 'v0.1'),
  ('10000000-0000-0000-0000-000000000031', 'COURSE_CONCEPT.CALCULUS_I', 'COURSE_CONCEPT', 'Calculus I', 'v0.1'),
  ('10000000-0000-0000-0000-000000000032', 'COURSE_CONCEPT.CALCULUS_II', 'COURSE_CONCEPT', 'Calculus II', 'v0.1'),
  ('10000000-0000-0000-0000-000000000033', 'COURSE_CONCEPT.MULTIVARIABLE_CALCULUS', 'COURSE_CONCEPT', 'Multivariable Calculus', 'v0.1'),
  ('10000000-0000-0000-0000-000000000034', 'COURSE_CONCEPT.LINEAR_ALGEBRA', 'COURSE_CONCEPT', 'Linear Algebra', 'v0.1'),
  ('10000000-0000-0000-0000-000000000035', 'COURSE_CONCEPT.PROBABILITY', 'COURSE_CONCEPT', 'Probability', 'v0.1'),
  ('10000000-0000-0000-0000-000000000036', 'COURSE_CONCEPT.STATISTICS', 'COURSE_CONCEPT', 'Statistics', 'v0.1'),
  ('10000000-0000-0000-0000-000000000037', 'COURSE_CONCEPT.ECONOMETRICS', 'COURSE_CONCEPT', 'Econometrics', 'v0.1'),
  ('10000000-0000-0000-0000-000000000041', 'SKILL.PYTHON', 'SKILL', 'Python', 'v0.1'),
  ('10000000-0000-0000-0000-000000000042', 'SKILL.R', 'SKILL', 'R', 'v0.1'),
  ('10000000-0000-0000-0000-000000000043', 'SKILL.SQL', 'SKILL', 'SQL', 'v0.1'),
  ('10000000-0000-0000-0000-000000000051', 'CAREER.QUANTITATIVE_RESEARCHER', 'CAREER', 'Quantitative Researcher', 'v0.1'),
  ('10000000-0000-0000-0000-000000000052', 'CAREER.ECONOMIST', 'CAREER', 'Economist', 'v0.1'),
  ('10000000-0000-0000-0000-000000000061', 'INDUSTRY.FINANCIAL_SERVICES', 'INDUSTRY', 'Financial Services', 'v0.1'),
  ('10000000-0000-0000-0000-000000000062', 'INDUSTRY.TECHNOLOGY', 'INDUSTRY', 'Technology', 'v0.1'),
  ('10000000-0000-0000-0000-000000000071', 'ASSESSMENT.GRE', 'ASSESSMENT', 'GRE', 'v0.1'),
  ('10000000-0000-0000-0000-000000000072', 'ASSESSMENT.GMAT', 'ASSESSMENT', 'GMAT', 'v0.1'),
  ('10000000-0000-0000-0000-000000000073', 'ASSESSMENT.TOEFL', 'ASSESSMENT', 'TOEFL', 'v0.1'),
  ('10000000-0000-0000-0000-000000000074', 'ASSESSMENT.IELTS', 'ASSESSMENT', 'IELTS', 'v0.1')
on conflict do nothing;

insert into public.taxonomy_aliases (
  concept_id,
  alias_text,
  introduced_in_release
) values
  ('10000000-0000-0000-0000-000000000032', 'Calc II', 'v0.1'),
  ('10000000-0000-0000-0000-000000000033', 'Multivariable Calculus', 'v0.1'),
  ('10000000-0000-0000-0000-000000000034', 'Linear Algebra', 'v0.1'),
  ('10000000-0000-0000-0000-000000000071', 'GRE General Test', 'v0.1'),
  ('10000000-0000-0000-0000-000000000072', 'Graduate Management Admission Test', 'v0.1')
on conflict do nothing;

commit;
