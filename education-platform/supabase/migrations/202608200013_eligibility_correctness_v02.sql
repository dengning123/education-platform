-- Migration 013: Eligibility Correctness v0.2.
-- Additive over frozen 001-012. Does not amend 012 D-USAGE.
-- Does not create 014 or Fit Engine objects.

begin;

do $preflight$
declare
  v_user text := current_user;
  v_public_owner text;
  v_private_owner text;
  v_db_owner text;
  v_role text;
  v_is_superuser boolean;
  v_has_admin_membership boolean;
begin
  if not exists (select 1 from pg_roles where rolname = 'foundation_catalog_executor')
     or not exists (select 1 from pg_roles where rolname = 'foundation_student_executor')
     or not exists (select 1 from pg_roles where rolname = 'foundation_evaluation_executor') then
    raise exception using errcode = '55000',
      message = '013 preflight failed: 012 executor roles are required';
  end if;
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname in (
      'allocate_taxonomy_release_ordinal_v02',
      'start_eligibility_evaluation_v02',
      'finalize_eligibility_evaluation_v02'
    )
  ) then
    raise exception using errcode = '55000',
      message = '013 preflight failed: 9B objects already exist';
  end if;
  select pg_get_userbyid(d.datdba) into v_db_owner
  from pg_database d where d.datname = current_database();
  select pg_get_userbyid(n.nspowner) into v_public_owner
  from pg_namespace n where n.nspname = 'public';
  select pg_get_userbyid(n.nspowner) into v_private_owner
  from pg_namespace n where n.nspname = 'private';
  if v_private_owner is distinct from v_user
     or not (
          v_public_owner is not distinct from v_user
          or (v_public_owner = 'pg_database_owner' and v_db_owner is not distinct from v_user)
        ) then
    raise exception using errcode = '42501',
      message = format('013 preflight failed: user=%s public_owner=%s private_owner=%s',
        v_user, v_public_owner, v_private_owner);
  end if;

  select rolsuper
  into v_is_superuser
  from pg_roles
  where rolname = v_user;

  foreach v_role in array array[
    'foundation_catalog_executor',
    'foundation_student_executor',
    'foundation_evaluation_executor'
  ]
  loop
    select exists (
      select 1
      from pg_auth_members m
      join pg_roles granted_role on granted_role.oid = m.roleid
      join pg_roles member_role on member_role.oid = m.member
      where granted_role.rolname = v_role
        and member_role.rolname = v_user
        and m.admin_option
    )
    into v_has_admin_membership;

    if current_setting('server_version_num')::integer >= 160000
       and not v_is_superuser
       and v_has_admin_membership
    then
      -- Preserve the PG16+ automatic bootstrap-superuser ADMIN grant from
      -- 012 and ensure the install role retains SET/INHERIT for ownership
      -- transfer without attempting the prohibited self-ADMIN grant cycle.
      execute format(
        'grant %I to %I with admin false, inherit true, set true',
        v_role,
        v_user
      );
    else
      -- PostgreSQL 15 and superuser installs retain the frozen grant path.
      execute format('grant %I to %I with admin option', v_role, v_user);
    end if;
  end loop;
end;
$preflight$;

create type public.eligibility_projection as enum (
  'FULL',
  'ORDINARY_BARRIER',
  'CONDITIONAL_HARD',
  'CONDITIONAL_ONLY',
  'SOFT_EXPLANATION'
);
create type public.eligibility_projection_value as enum (
  'SATISFIED',
  'NOT_SATISFIED',
  'UNKNOWN',
  'ABSENT'
);
create type public.eligibility_snapshot_scope_kind as enum (
  'GLOBAL_PROFILE',
  'EDUCATION_CONTEXT',
  'UNASSIGNED_CONTEXT'
);
create type public.eligibility_mapping_universe_role as enum (
  'AUTHORITATIVE',
  'LIMITING'
);
create type public.eligibility_student_mapping_relation as enum (
  'STUDENT_CONCEPT_ASSOCIATION'
);
create type public.eligibility_v02_missing_data_code as enum (
  'PROGRAM_FACT_NOT_KNOWN',
  'MAPPED_COURSE_NOT_INCLUDED',
  'COURSE_EDUCATION_CONTEXT_MISMATCH',
  'INCOMPLETE_COURSE_OR_MAPPING_COVERAGE',
  'NO_VERIFIED_MAPPING',
  'PROPOSED_MAPPING_LIMITING',
  'INCOMPLETE_TEST_HISTORY',
  'INCOMPLETE_EDUCATION_HISTORY',
  'TAXONOMY_CONCEPT_INACTIVE_AT_PIN',
  'UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE'
);
create type public.eligibility_v02_leaf_class as enum (
  'ORDINARY_HARD',
  'CONDITIONAL_HARD',
  'SOFT'
);

-- Taxonomy ordinals first.
alter table public.taxonomy_releases
  add column release_ordinal bigint;
alter table public.taxonomy_concepts
  add column introduced_release_ordinal bigint,
  add column retired_release_ordinal bigint;
alter table public.taxonomy_aliases
  add column introduced_release_ordinal bigint,
  add column retired_release_ordinal bigint;
alter table public.taxonomy_relationships
  add column introduced_release_ordinal bigint,
  add column retired_release_ordinal bigint;

do $ordinal_backfill$
declare
  v_pos integer := 0;
  v_rel record;
begin
  alter table public.taxonomy_releases disable trigger taxonomy_releases_immutable;
  for v_rel in
    select release_code
    from public.taxonomy_releases
    order by created_at, release_code
  loop
    v_pos := v_pos + 1;
    if v_pos = 1 and v_rel.release_code is distinct from 'v0.1' then
      raise exception using errcode = '55000',
        message = 'v0.1 must receive taxonomy release ordinal 1',
        hint = 'taxonomy_ordinal_backfill_invalid';
    end if;
    update public.taxonomy_releases
    set release_ordinal = v_pos
    where release_code = v_rel.release_code;
  end loop;
  alter table public.taxonomy_releases enable trigger taxonomy_releases_immutable;

  update public.taxonomy_concepts c
  set introduced_release_ordinal = r.release_ordinal
  from public.taxonomy_releases r
  where r.release_code = c.introduced_in_release;
  update public.taxonomy_concepts c
  set retired_release_ordinal = r.release_ordinal
  from public.taxonomy_releases r
  where r.release_code = c.retired_in_release;

  update public.taxonomy_aliases a
  set introduced_release_ordinal = r.release_ordinal
  from public.taxonomy_releases r
  where r.release_code = a.introduced_in_release;
  update public.taxonomy_aliases a
  set retired_release_ordinal = r.release_ordinal
  from public.taxonomy_releases r
  where r.release_code = a.retired_in_release;

  update public.taxonomy_relationships x
  set introduced_release_ordinal = r.release_ordinal
  from public.taxonomy_releases r
  where r.release_code = x.introduced_in_release;
  update public.taxonomy_relationships x
  set retired_release_ordinal = r.release_ordinal
  from public.taxonomy_releases r
  where r.release_code = x.retired_in_release;

  if exists (
    select 1 from public.taxonomy_concepts
    where introduced_release_ordinal is null
       or (retired_in_release is not null and retired_release_ordinal is null)
       or (retired_release_ordinal is not null
           and not (introduced_release_ordinal < retired_release_ordinal))
  ) or exists (
    select 1 from public.taxonomy_aliases
    where introduced_release_ordinal is null
       or (retired_in_release is not null and retired_release_ordinal is null)
       or (retired_release_ordinal is not null
           and not (introduced_release_ordinal < retired_release_ordinal))
  ) or exists (
    select 1 from public.taxonomy_relationships
    where introduced_release_ordinal is null
       or (retired_in_release is not null and retired_release_ordinal is null)
       or (retired_release_ordinal is not null
           and not (introduced_release_ordinal < retired_release_ordinal))
  ) then
    raise exception using errcode = '55000',
      message = 'Taxonomy ordinal backfill missing release or empty/reversed interval',
      hint = 'taxonomy_ordinal_backfill_invalid';
  end if;
end;
$ordinal_backfill$;

alter table public.taxonomy_releases
  alter column release_ordinal set not null;
alter table public.taxonomy_releases
  add constraint taxonomy_releases_ordinal_positive check (release_ordinal >= 1);
create unique index taxonomy_releases_ordinal_uidx
  on public.taxonomy_releases (release_ordinal);

alter table public.taxonomy_concepts
  alter column introduced_release_ordinal set not null;
alter table public.taxonomy_concepts
  add constraint taxonomy_concepts_introduced_ordinal_positive
    check (introduced_release_ordinal >= 1),
  add constraint taxonomy_concepts_ordinal_range
    check (
      retired_release_ordinal is null
      or introduced_release_ordinal < retired_release_ordinal
    );
alter table public.taxonomy_aliases
  alter column introduced_release_ordinal set not null;
alter table public.taxonomy_aliases
  add constraint taxonomy_aliases_introduced_ordinal_positive
    check (introduced_release_ordinal >= 1),
  add constraint taxonomy_aliases_ordinal_range
    check (
      retired_release_ordinal is null
      or introduced_release_ordinal < retired_release_ordinal
    );
alter table public.taxonomy_relationships
  alter column introduced_release_ordinal set not null;
alter table public.taxonomy_relationships
  add constraint taxonomy_relationships_introduced_ordinal_positive
    check (introduced_release_ordinal >= 1),
  add constraint taxonomy_relationships_ordinal_range
    check (
      retired_release_ordinal is null
      or introduced_release_ordinal < retired_release_ordinal
    );

create table private.taxonomy_release_ordinal_allocator (
  singleton boolean primary key check (singleton),
  next_ordinal bigint not null check (next_ordinal >= 2)
);
insert into private.taxonomy_release_ordinal_allocator (singleton, next_ordinal)
select true, coalesce(max(release_ordinal), 0) + 1
from public.taxonomy_releases;

revoke all on table private.taxonomy_release_ordinal_allocator
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor,
       foundation_evaluation_executor;

create or replace function private.taxonomy_allocate_release_ordinal()
returns bigint
language plpgsql
security invoker
set search_path = pg_catalog, public, private
as $$
declare
  v_next bigint;
  v_allocated bigint;
  v_max bigint;
begin
  select next_ordinal into v_next
  from private.taxonomy_release_ordinal_allocator
  where singleton is true
  for update;
  if v_next is null then
    raise exception using errcode = '55000',
      message = 'Taxonomy ordinal allocator is missing',
      hint = 'taxonomy_ordinal_allocation_invalid';
  end if;
  select coalesce(max(release_ordinal), 0) + 1 into v_max
  from public.taxonomy_releases;
  v_allocated := greatest(v_next, v_max);
  if v_allocated < 1 then
    raise exception using errcode = '55000',
      message = 'Allocated taxonomy ordinal is invalid',
      hint = 'taxonomy_ordinal_allocation_invalid';
  end if;
  update private.taxonomy_release_ordinal_allocator
  set next_ordinal = v_allocated + 1
  where singleton is true;
  if exists (
    select 1 from public.taxonomy_releases where release_ordinal = v_allocated
  ) then
    raise exception using errcode = '55000',
      message = 'Allocated taxonomy ordinal already exists',
      hint = 'taxonomy_ordinal_allocation_invalid';
  end if;
  return v_allocated;
end;
$$;

revoke all on function private.taxonomy_allocate_release_ordinal()
  from public, anon, authenticated, service_role, authenticator,
       foundation_catalog_executor, foundation_student_executor,
       foundation_evaluation_executor;

create function public.allocate_taxonomy_release_ordinal_v02()
returns bigint
language plpgsql
security definer
set search_path = pg_catalog, private
as $$
begin
  return private.taxonomy_allocate_release_ordinal();
end;
$$;

revoke all on function public.allocate_taxonomy_release_ordinal_v02()
  from public, anon, authenticated, service_role, authenticator;
grant execute on function public.allocate_taxonomy_release_ordinal_v02()
  to foundation_catalog_executor;

create or replace function public.guard_taxonomy_release_ordinal_immutable()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if tg_op = 'UPDATE' and new.release_ordinal is distinct from old.release_ordinal then
    raise exception using errcode = '55000',
      message = 'taxonomy release_ordinal is immutable after insert',
      hint = 'taxonomy_ordinal_immutable';
  end if;
  return new;
end;
$$;
create trigger taxonomy_releases_ordinal_immutable
before update on public.taxonomy_releases
for each row execute function public.guard_taxonomy_release_ordinal_immutable();


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
declare
  allocated bigint;
begin
  allocated := public.allocate_taxonomy_release_ordinal_v02();
  insert into public.taxonomy_releases (
    release_code, published_at, notes, status, release_ordinal
  ) values (
    p_release_code, p_published_at, p_notes, 'DRAFT', allocated
  );
  perform 1 from public.taxonomy_releases where release_code = p_release_code for update;
  if allocated < 1 then
    raise exception using errcode = '55000',
      message = 'Allocated taxonomy ordinal is invalid',
      hint = 'taxonomy_ordinal_allocation_invalid';
  end if;
end;
$$;

create or replace function public.verify_taxonomy_release(p_release_code text, p_verified_by text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_ordinal bigint;
begin
  perform 1 from public.taxonomy_releases where release_code = p_release_code for update;
  select release_ordinal into v_ordinal
  from public.taxonomy_releases
  where release_code = p_release_code;
  if exists (
    select 1 from public.taxonomy_concepts
    where retired_in_release = p_release_code
      and (
        retired_release_ordinal is null
        or introduced_release_ordinal >= retired_release_ordinal
        or retired_release_ordinal is distinct from v_ordinal
      )
  ) or exists (
    select 1 from public.taxonomy_aliases
    where retired_in_release = p_release_code
      and (
        retired_release_ordinal is null
        or introduced_release_ordinal >= retired_release_ordinal
        or retired_release_ordinal is distinct from v_ordinal
      )
  ) or exists (
    select 1 from public.taxonomy_relationships
    where retired_in_release = p_release_code
      and (
        retired_release_ordinal is null
        or introduced_release_ordinal >= retired_release_ordinal
        or retired_release_ordinal is distinct from v_ordinal
      )
  ) then
    raise exception using errcode = '55000',
      message = 'Taxonomy ordinal range is invalid for this release',
      hint = 'taxonomy_ordinal_range_invalid';
  end if;
  update public.taxonomy_releases
  set status = 'VERIFIED', verified_by = p_verified_by, verified_at = now()
  where release_code = p_release_code and status = 'DRAFT';
  if not found then
    raise exception using errcode = '55000', message = 'A DRAFT taxonomy release is required';
  end if;
end;
$$;

create or replace function public.create_taxonomy_concept(p_row public.taxonomy_concepts)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_rel public.taxonomy_releases%rowtype;
  v_payload jsonb;
begin
  select * into v_rel
  from public.taxonomy_releases
  where release_code = p_row.introduced_in_release
  for update;
  if v_rel.status is distinct from 'DRAFT' then
    raise exception using errcode = '55000', message = 'A DRAFT taxonomy release is required';
  end if;
  if p_row.introduced_release_ordinal is not null
     and p_row.introduced_release_ordinal is distinct from v_rel.release_ordinal then
    raise exception using errcode = '22023',
      message = 'Caller-supplied introduced_release_ordinal does not match the release',
      hint = 'taxonomy_ordinal_payload_mismatch';
  end if;
  if p_row.retired_release_ordinal is not null then
    raise exception using errcode = '22023',
      message = 'Create must not set retired_release_ordinal',
      hint = 'taxonomy_ordinal_payload_mismatch';
  end if;
  v_payload := to_jsonb(p_row)
    || jsonb_build_object(
         'introduced_release_ordinal', v_rel.release_ordinal,
         'retired_release_ordinal', null
       );
  perform public.reject_terminal_insert(v_payload, 'taxonomy_concepts');
  perform public.insert_composite('public.taxonomy_concepts'::regclass, v_payload);
end;
$$;

create or replace function public.create_taxonomy_alias(p_row public.taxonomy_aliases)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_rel public.taxonomy_releases%rowtype;
  v_payload jsonb;
begin
  select * into v_rel
  from public.taxonomy_releases
  where release_code = p_row.introduced_in_release
  for update;
  if v_rel.status is distinct from 'DRAFT' then
    raise exception using errcode = '55000', message = 'A DRAFT taxonomy release is required';
  end if;
  if p_row.introduced_release_ordinal is not null
     and p_row.introduced_release_ordinal is distinct from v_rel.release_ordinal then
    raise exception using errcode = '22023',
      message = 'Caller-supplied introduced_release_ordinal does not match the release',
      hint = 'taxonomy_ordinal_payload_mismatch';
  end if;
  v_payload := to_jsonb(p_row)
    || jsonb_build_object(
         'introduced_release_ordinal', v_rel.release_ordinal,
         'retired_release_ordinal', null
       );
  perform public.reject_terminal_insert(v_payload, 'taxonomy_aliases');
  perform public.insert_composite('public.taxonomy_aliases'::regclass, v_payload);
end;
$$;

create or replace function public.create_taxonomy_relationship(p_row public.taxonomy_relationships)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_rel public.taxonomy_releases%rowtype;
  v_payload jsonb;
begin
  select * into v_rel
  from public.taxonomy_releases
  where release_code = p_row.introduced_in_release
  for update;
  if v_rel.status is distinct from 'DRAFT' then
    raise exception using errcode = '55000', message = 'A DRAFT taxonomy release is required';
  end if;
  v_payload := to_jsonb(p_row)
    || jsonb_build_object(
         'introduced_release_ordinal', v_rel.release_ordinal,
         'retired_release_ordinal', null
       );
  perform public.reject_terminal_insert(v_payload, 'taxonomy_relationships');
  perform public.insert_composite('public.taxonomy_relationships'::regclass, v_payload);
end;
$$;

create or replace function public.retire_taxonomy_concept(p_concept_id uuid, p_release text, p_reason text)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_rel public.taxonomy_releases%rowtype;
  v_introduced bigint;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception using errcode = '22023', message = 'Retirement reason is required';
  end if;
  select * into v_rel from public.taxonomy_releases where release_code = p_release for update;
  if v_rel.status is distinct from 'DRAFT' then
    raise exception using errcode = '55000', message = 'A later DRAFT taxonomy release is required';
  end if;
  select introduced_release_ordinal into v_introduced
  from public.taxonomy_concepts where concept_id = p_concept_id for update;
  if v_introduced is null or not (v_introduced < v_rel.release_ordinal) then
    raise exception using errcode = '55000',
      message = 'Taxonomy ordinal range is invalid',
      hint = 'taxonomy_ordinal_range_invalid';
  end if;
  update public.taxonomy_concepts
  set retired_in_release = p_release,
      retired_release_ordinal = v_rel.release_ordinal
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
declare
  v_rel public.taxonomy_releases%rowtype;
  v_introduced bigint;
begin
  select * into v_rel from public.taxonomy_releases where release_code = p_release for update;
  if v_rel.status is distinct from 'DRAFT' then
    raise exception using errcode = '55000', message = 'A later DRAFT taxonomy release is required';
  end if;
  select introduced_release_ordinal into v_introduced
  from public.taxonomy_aliases where alias_id = p_alias_id for update;
  if v_introduced is null or not (v_introduced < v_rel.release_ordinal) then
    raise exception using errcode = '55000',
      message = 'Taxonomy ordinal range is invalid',
      hint = 'taxonomy_ordinal_range_invalid';
  end if;
  update public.taxonomy_aliases
  set retired_in_release = p_release,
      retired_release_ordinal = v_rel.release_ordinal
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
declare
  v_rel public.taxonomy_releases%rowtype;
  v_introduced bigint;
begin
  select * into v_rel from public.taxonomy_releases where release_code = p_release for update;
  if v_rel.status is distinct from 'DRAFT' then
    raise exception using errcode = '55000', message = 'A later DRAFT taxonomy release is required';
  end if;
  select introduced_release_ordinal into v_introduced
  from public.taxonomy_relationships where relationship_id = p_relationship_id for update;
  if v_introduced is null or not (v_introduced < v_rel.release_ordinal) then
    raise exception using errcode = '55000',
      message = 'Taxonomy ordinal range is invalid',
      hint = 'taxonomy_ordinal_range_invalid';
  end if;
  update public.taxonomy_relationships
  set retired_in_release = p_release,
      retired_release_ordinal = v_rel.release_ordinal
  where relationship_id = p_relationship_id and retired_in_release is null;
  if not found then
    raise exception using errcode = '55000', message = 'Active taxonomy relationship is required';
  end if;
end;
$$;


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
    )
  );

create table public.requirement_group_projection_thresholds (
  rule_set_id uuid not null
    references public.program_requirement_rule_sets(rule_set_id) on delete restrict,
  group_node_id uuid not null
    references public.program_requirement_nodes(rule_node_id) on delete restrict,
  projection_kind public.eligibility_projection not null,
  projected_minimum_children integer not null
    check (projected_minimum_children >= 1),
  projected_descendant_count integer not null
    check (projected_descendant_count >= 1),
  verification_evidence_id uuid,
  verified_by text,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (rule_set_id, group_node_id, projection_kind),
  foreign key (rule_set_id, group_node_id)
    references public.program_requirement_nodes(rule_set_id, rule_node_id)
    on delete restrict,
  check (projected_minimum_children <= projected_descendant_count)
);

alter table public.eligibility_evaluations
  add column result_semantics_version text,
  add column canonicalization_version text,
  add column contract_release_code text,
  add column taxonomy_release_ordinal bigint,
  add column result_fingerprint text;

alter table public.eligibility_evaluations
  drop constraint eligibility_evaluations_identity_not_blank;
alter table public.eligibility_evaluations
  add constraint eligibility_evaluations_identity_not_blank check (
    btrim(evaluator_name) <> ''
    and btrim(evaluator_version) <> ''
  );
alter table public.eligibility_evaluations
  drop constraint eligibility_evaluations_root_outcome;
alter table public.eligibility_evaluations
  drop constraint eligibility_evaluations_completion_state;
alter table public.eligibility_evaluations
  drop constraint eligibility_evaluations_hashes;

alter table public.eligibility_evaluations
  add constraint eligibility_evaluations_hashes check (
    evaluator_build_hash ~ '^[a-f0-9]{64}$'
    and profile_snapshot_hash ~ '^[a-f0-9]{64}$'
    and (input_fingerprint is null or input_fingerprint ~ '^[a-f0-9]{64}$')
    and (result_fingerprint is null or result_fingerprint ~ '^[a-f0-9]{64}$')
  );

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
        (
          evaluation_state = 'BUILDING'
          and input_fingerprint is null
          and outcome is null
          and root_truth_value is null
          and evaluated_at is null
        ) or (
          evaluation_state = 'COMPLETED'
          and input_fingerprint is not null
          and outcome is not null
          and root_truth_value is not null
          and evaluated_at is not null
        )
      )
    ) or (
      input_schema_version = 'eligibility-v0.2'
      and result_semantics_version = 'eligibility-v0.2'
      and canonicalization_version = 'eligibility-v0.2-c14n1'
      and contract_release_code = 'phase2-v0.2'
      and taxonomy_release_ordinal >= 1
      and (
        (
          evaluation_state = 'BUILDING'
          and inputs_sealed_at is null
          and input_fingerprint is null
          and result_fingerprint is null
          and outcome is null
          and root_truth_value is null
          and evaluated_at is null
        ) or (
          evaluation_state = 'BUILDING'
          and inputs_sealed_at is not null
          and input_fingerprint ~ '^[a-f0-9]{64}$'
          and result_fingerprint is null
          and outcome is null
          and root_truth_value is null
          and evaluated_at is null
        ) or (
          evaluation_state = 'COMPLETED'
          and inputs_sealed_at is not null
          and input_fingerprint ~ '^[a-f0-9]{64}$'
          and result_fingerprint ~ '^[a-f0-9]{64}$'
          and outcome is not null
          and root_truth_value is not null
          and evaluated_at is not null
        )
      )
    )
  );

alter table public.eligibility_evaluations
  add constraint eligibility_evaluations_v01_root_outcome check (
    input_schema_version is distinct from 'eligibility-v0.1'
    or outcome is null
    or (root_truth_value = 'NOT_SATISFIED' and outcome = 'NOT_ELIGIBLE')
    or (root_truth_value = 'UNKNOWN' and outcome in ('UNKNOWN', 'CONDITIONALLY_ELIGIBLE'))
    or (root_truth_value = 'SATISFIED' and outcome in ('ELIGIBLE', 'CONDITIONALLY_ELIGIBLE'))
  );
alter table public.eligibility_evaluations
  add constraint eligibility_evaluations_v02_root_is_full check (
    input_schema_version is distinct from 'eligibility-v0.2'
    or root_truth_value is null
    or root_truth_value in ('SATISFIED', 'NOT_SATISFIED', 'UNKNOWN')
  );

create table public.eligibility_rule_set_pins (
  evaluation_id uuid primary key
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  rule_set_id uuid not null,
  program_version_id uuid not null,
  rule_set_version integer not null,
  taxonomy_release_code text not null,
  taxonomy_release_ordinal bigint not null check (taxonomy_release_ordinal >= 1),
  rule_schema_version text not null,
  engine_contract_version text not null,
  verification_evidence_id uuid,
  verified_by text,
  verified_at timestamptz
);
create table public.eligibility_rule_node_pins (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  rule_node_id uuid not null,
  parent_node_id uuid,
  sort_order integer not null,
  node_kind public.requirement_node_kind not null,
  group_operator public.requirement_group_operator,
  minimum_children integer,
  predicate_kind public.requirement_predicate_kind,
  requirement_strength public.requirement_strength,
  requirement_semantics public.requirement_semantics,
  target_concept_id uuid,
  explanation_template text not null,
  primary key (evaluation_id, rule_node_id)
);
create table public.eligibility_rule_node_source_pins (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  rule_node_id uuid not null,
  field_observation_id uuid not null,
  source_id uuid not null,
  applicability_assertion_id uuid not null,
  applicability_head_assertion_id_at_pin uuid not null,
  applicability_scope_id uuid,
  knowledge_status_at_pin public.knowledge_status not null,
  primary key (evaluation_id, rule_node_id, field_observation_id)
);
create table public.eligibility_rule_node_mapping_pins (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  rule_node_id uuid not null,
  catalog_mapping_id uuid not null,
  primary key (evaluation_id, rule_node_id, catalog_mapping_id)
);
create table public.eligibility_projection_threshold_pins (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  rule_set_id uuid not null,
  group_node_id uuid not null,
  projection_kind public.eligibility_projection not null,
  projected_minimum_children integer not null,
  projected_descendant_count integer not null,
  verification_evidence_id uuid,
  verified_by text,
  verified_at timestamptz,
  created_at_source timestamptz,
  primary key (evaluation_id, group_node_id, projection_kind)
);
create table public.eligibility_catalog_observation_pins (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  field_observation_id uuid not null,
  source_id uuid not null,
  source_identity_id uuid not null,
  source_revision_number integer not null,
  retrieval_content_hash text not null,
  evidence_id uuid,
  record_type public.catalog_record_type not null,
  record_id uuid not null,
  field_name text not null,
  canonical_value jsonb,
  knowledge_status public.knowledge_status not null,
  program_scope_key text,
  program_version_scope_key text,
  granularity_scope public.applicability_granularity_scope,
  population_scope_code public.applicability_population_scope,
  cycle_scope_code text,
  primary key (evaluation_id, field_observation_id)
);
create table public.eligibility_catalog_selection_pins (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  record_type public.catalog_record_type not null,
  record_id uuid not null,
  field_name text not null,
  observation_id uuid not null,
  selected_at_pin timestamptz not null,
  selected_by_pin text,
  primary key (evaluation_id, record_type, record_id, field_name)
);
create table public.eligibility_catalog_mapping_pins (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  catalog_mapping_id uuid not null,
  record_type public.catalog_record_type not null,
  record_id uuid not null,
  concept_id uuid not null,
  relation_at_pin public.catalog_mapping_relation not null,
  method public.mapping_method not null,
  confidence numeric,
  model_version text,
  verification_evidence_id uuid,
  reviewed_by text,
  reviewed_at timestamptz,
  status_at_pin public.mapping_status not null,
  retired_at_pin timestamptz,
  retirement_reason_at_pin text,
  primary key (evaluation_id, catalog_mapping_id),
  check (status_at_pin in ('VERIFIED', 'PROPOSED'))
);
create table public.eligibility_student_mapping_pins (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  student_mapping_id uuid not null,
  profile_version_id uuid not null,
  record_type public.student_mapping_record_type not null,
  student_record_id uuid not null,
  concept_id uuid not null,
  relation_at_pin public.eligibility_student_mapping_relation not null
    default 'STUDENT_CONCEPT_ASSOCIATION',
  method public.mapping_method not null,
  confidence numeric,
  model_version text,
  student_evidence_id uuid,
  reviewed_by text,
  reviewed_at timestamptz,
  status_at_pin public.mapping_status not null,
  retired_at_pin timestamptz,
  retirement_reason_at_pin text,
  primary key (evaluation_id, student_mapping_id),
  check (status_at_pin in ('VERIFIED', 'PROPOSED')),
  check (relation_at_pin = 'STUDENT_CONCEPT_ASSOCIATION')
);
create table public.eligibility_taxonomy_concept_pins (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  concept_id uuid not null,
  canonical_key text not null,
  concept_kind public.taxonomy_concept_kind not null,
  introduced_release_ordinal bigint not null,
  retired_release_ordinal bigint,
  primary key (evaluation_id, concept_id)
);
create table public.eligibility_completeness_pins (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  completeness_id uuid not null,
  scope_id uuid,
  domain public.student_data_domain not null,
  completeness public.data_completeness not null,
  explanation text,
  primary key (evaluation_id, completeness_id)
);
create table public.eligibility_snapshot_scopes (
  scope_id uuid primary key default extensions.gen_random_uuid(),
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  profile_version_id uuid not null,
  scope_kind public.eligibility_snapshot_scope_kind not null,
  education_context_id uuid,
  domain public.student_data_domain not null,
  completeness_id uuid,
  completeness public.data_completeness,
  unique nulls not distinct (evaluation_id, scope_kind, education_context_id, domain)
);
create table public.eligibility_snapshot_degrees (
  scope_id uuid not null
    references public.eligibility_snapshot_scopes(scope_id) on delete cascade,
  student_degree_id uuid not null,
  primary key (scope_id, student_degree_id)
);
create table public.eligibility_snapshot_courses (
  scope_id uuid not null
    references public.eligibility_snapshot_scopes(scope_id) on delete cascade,
  student_course_id uuid not null,
  primary key (scope_id, student_course_id)
);
create table public.eligibility_snapshot_test_scores (
  scope_id uuid not null
    references public.eligibility_snapshot_scopes(scope_id) on delete cascade,
  student_test_score_id uuid not null,
  primary key (scope_id, student_test_score_id)
);
create table public.eligibility_snapshot_mapping_universe (
  scope_id uuid not null
    references public.eligibility_snapshot_scopes(scope_id) on delete cascade,
  student_mapping_id uuid not null,
  universe_role public.eligibility_mapping_universe_role not null,
  primary key (scope_id, student_mapping_id)
);
create table public.eligibility_requirement_projection_results (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  rule_node_id uuid not null,
  projection public.eligibility_projection not null,
  value public.eligibility_projection_value not null,
  primary key (evaluation_id, rule_node_id, projection)
);
create table public.eligibility_negative_fact_authorizations (
  evaluation_id uuid not null
    references public.eligibility_evaluations(evaluation_id) on delete cascade,
  rule_node_id uuid not null,
  domain public.student_data_domain not null,
  proof_version text not null default 'eligibility-v0.2-neg1',
  created_at timestamptz not null default now(),
  primary key (evaluation_id, rule_node_id),
  check (proof_version = 'eligibility-v0.2-neg1')
);
create table public.eligibility_negative_authorization_scopes (
  evaluation_id uuid not null,
  rule_node_id uuid not null,
  scope_id uuid not null
    references public.eligibility_snapshot_scopes(scope_id) on delete cascade,
  primary key (evaluation_id, rule_node_id, scope_id),
  foreign key (evaluation_id, rule_node_id)
    references public.eligibility_negative_fact_authorizations(evaluation_id, rule_node_id)
    on delete cascade
);
create table private.eligibility_v02_finalize_authorizations (
  transaction_id bigint not null,
  evaluation_id uuid not null,
  executor_role text not null
    check (executor_role = 'foundation_evaluation_executor'),
  primary key (transaction_id, evaluation_id)
);

alter table public.eligibility_snapshot_degrees
  add column evaluation_id uuid;
alter table public.eligibility_snapshot_courses
  add column evaluation_id uuid;
alter table public.eligibility_snapshot_test_scores
  add column evaluation_id uuid;
alter table public.eligibility_snapshot_mapping_universe
  add column evaluation_id uuid;


alter table public.eligibility_completeness_pins
  add constraint eligibility_completeness_pins_scope_fk
    foreign key (scope_id) references public.eligibility_snapshot_scopes(scope_id)
    on delete cascade;
alter table public.eligibility_snapshot_degrees
  add constraint eligibility_snapshot_degrees_eval_fk
    foreign key (evaluation_id, student_degree_id)
    references public.eligibility_manifest_degrees(evaluation_id, student_degree_id)
    on delete cascade;
alter table public.eligibility_snapshot_courses
  add constraint eligibility_snapshot_courses_eval_fk
    foreign key (evaluation_id, student_course_id)
    references public.eligibility_manifest_courses(evaluation_id, student_course_id)
    on delete cascade;
alter table public.eligibility_snapshot_test_scores
  add constraint eligibility_snapshot_tests_eval_fk
    foreign key (evaluation_id, student_test_score_id)
    references public.eligibility_manifest_test_scores(evaluation_id, student_test_score_id)
    on delete cascade;

create or replace function public.guard_eligibility_snapshot_scope_shape()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if new.scope_kind = 'GLOBAL_PROFILE' and new.education_context_id is not null then
    raise exception using errcode = '22023',
      message = 'GLOBAL_PROFILE education_context_id must be null',
      hint = 'eligibility_snapshot_scope_shape';
  end if;
  if new.scope_kind = 'EDUCATION_CONTEXT' and new.education_context_id is null then
    raise exception using errcode = '22023',
      message = 'EDUCATION_CONTEXT requires education_context_id',
      hint = 'eligibility_snapshot_scope_shape';
  end if;
  if new.scope_kind = 'UNASSIGNED_CONTEXT' and new.education_context_id is not null then
    raise exception using errcode = '22023',
      message = 'UNASSIGNED_CONTEXT education_context_id must be null',
      hint = 'eligibility_snapshot_scope_shape';
  end if;
  if new.scope_kind = 'GLOBAL_PROFILE'
     and new.domain in ('COURSE_HISTORY', 'COURSE_MAPPING') then
    raise exception using errcode = '22023',
      message = 'COURSE domains cannot use GLOBAL_PROFILE',
      hint = 'eligibility_snapshot_scope_shape';
  end if;
  if new.scope_kind in ('EDUCATION_CONTEXT', 'UNASSIGNED_CONTEXT')
     and new.domain in ('EDUCATION_HISTORY', 'TEST_HISTORY') then
    raise exception using errcode = '22023',
      message = 'Education/test history cannot use education or unassigned scopes',
      hint = 'eligibility_snapshot_scope_shape';
  end if;
  return new;
end;
$$;
create trigger eligibility_snapshot_scopes_shape
before insert or update on public.eligibility_snapshot_scopes
for each row execute function public.guard_eligibility_snapshot_scope_shape();

create or replace function public.guard_eligibility_mapping_universe_status()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
begin
  if new.status_at_pin in ('REJECTED', 'RETIRED') then
    raise exception using errcode = '22023',
      message = 'REJECTED/RETIRED mappings are outside the decision universe',
      hint = 'eligibility_mapping_status_not_universe_eligible';
  end if;
  return new;
end;
$$;
create trigger eligibility_catalog_mapping_pins_status
before insert or update on public.eligibility_catalog_mapping_pins
for each row execute function public.guard_eligibility_mapping_universe_status();
create trigger eligibility_student_mapping_pins_status
before insert or update on public.eligibility_student_mapping_pins
for each row execute function public.guard_eligibility_mapping_universe_status();

create or replace function public.guard_eligibility_v02_sealed_pin()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_old_eval_id uuid;
  v_new_eval_id uuid;
begin
  if tg_op = 'DELETE' and private.student_privacy_delete_allowed() then
    return old;
  end if;

  if tg_op <> 'INSERT' then
    v_old := to_jsonb(old);
    if v_old ? 'evaluation_id' then
      v_old_eval_id := (v_old->>'evaluation_id')::uuid;
    else
      select s.evaluation_id into v_old_eval_id
      from public.eligibility_snapshot_scopes s
      where s.scope_id = (v_old->>'scope_id')::uuid;
    end if;
  end if;

  if tg_op <> 'DELETE' then
    v_new := to_jsonb(new);
    if v_new ? 'evaluation_id' then
      v_new_eval_id := (v_new->>'evaluation_id')::uuid;
    else
      select s.evaluation_id into v_new_eval_id
      from public.eligibility_snapshot_scopes s
      where s.scope_id = (v_new->>'scope_id')::uuid;
    end if;
  end if;

  if exists (
    select 1
    from public.eligibility_evaluations e
    where e.evaluation_id in (v_old_eval_id, v_new_eval_id)
      and e.inputs_sealed_at is not null
  ) then
    raise exception using errcode = '55000',
      message = 'Sealed eligibility pins are immutable',
      hint = 'eligibility_v02_sealed_input_immutable';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

do $sealed_pin_triggers$
declare
  v_rel text;
begin
  foreach v_rel in array array[
    'eligibility_rule_set_pins',
    'eligibility_rule_node_pins',
    'eligibility_rule_node_source_pins',
    'eligibility_rule_node_mapping_pins',
    'eligibility_projection_threshold_pins',
    'eligibility_catalog_observation_pins',
    'eligibility_catalog_selection_pins',
    'eligibility_catalog_mapping_pins',
    'eligibility_student_mapping_pins',
    'eligibility_taxonomy_concept_pins',
    'eligibility_completeness_pins',
    'eligibility_snapshot_scopes',
    'eligibility_snapshot_degrees',
    'eligibility_snapshot_courses',
    'eligibility_snapshot_test_scores',
    'eligibility_snapshot_mapping_universe'
  ]
  loop
    execute format('drop trigger if exists %I on public.%I', left(v_rel || '_sealed', 63), v_rel);
    execute format(
      'create trigger %I before insert or update or delete on public.%I
       for each row execute function public.guard_eligibility_v02_sealed_pin()',
      left(v_rel || '_sealed', 63),
      v_rel
    );
  end loop;
end;
$sealed_pin_triggers$;

create or replace function private.eligibility_v02_active_at_ordinal(
  p_introduced bigint,
  p_pin bigint,
  p_retired bigint
) returns boolean
language sql
immutable
set search_path = pg_catalog, public
as $$
  select p_introduced <= p_pin
     and (p_retired is null or p_pin < p_retired);
$$;

create or replace function private.eligibility_v02_leaf_class(
  p_strength public.requirement_strength,
  p_semantics public.requirement_semantics
) returns public.eligibility_v02_leaf_class
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
begin
  if p_strength = 'SOFT' and p_semantics = 'EXPLICIT_CONDITIONAL' then
    raise exception using errcode = '55000',
      message = 'SOFT + EXPLICIT_CONDITIONAL is forbidden',
      hint = 'eligibility_soft_conditional_forbidden';
  end if;
  if p_strength = 'HARD' and p_semantics = 'ORDINARY' then
    return 'ORDINARY_HARD';
  end if;
  if p_strength = 'HARD' and p_semantics = 'EXPLICIT_CONDITIONAL' then
    return 'CONDITIONAL_HARD';
  end if;
  return 'SOFT';
end;
$$;

create or replace function private.eligibility_v02_project_leaf(
  p_class public.eligibility_v02_leaf_class,
  p_projection public.eligibility_projection,
  p_actual public.requirement_truth_value
) returns public.eligibility_projection_value
language sql
immutable
set search_path = pg_catalog, public
as $$
  select case
    when p_class = 'ORDINARY_HARD' then
      case when p_projection in ('CONDITIONAL_ONLY', 'SOFT_EXPLANATION')
           then 'ABSENT'::public.eligibility_projection_value
           else p_actual::text::public.eligibility_projection_value end
    when p_class = 'CONDITIONAL_HARD' then
      case when p_projection = 'ORDINARY_BARRIER' then 'SATISFIED'::public.eligibility_projection_value
           when p_projection = 'SOFT_EXPLANATION' then 'ABSENT'::public.eligibility_projection_value
           else p_actual::text::public.eligibility_projection_value end
    else
      case when p_projection in ('FULL', 'SOFT_EXPLANATION')
           then p_actual::text::public.eligibility_projection_value
           else 'ABSENT'::public.eligibility_projection_value end
  end;
$$;

create or replace function private.eligibility_v02_aggregate(
  p_operator public.requirement_group_operator,
  p_values public.eligibility_projection_value[],
  p_k integer
) returns public.eligibility_projection_value
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
declare
  v_remaining public.eligibility_projection_value[] := '{}';
  v_val public.eligibility_projection_value;
  v_s integer := 0;
  v_u integer := 0;
  v_n integer;
begin
  foreach v_val in array coalesce(p_values, '{}')
  loop
    if v_val is distinct from 'ABSENT' then
      v_remaining := v_remaining || v_val;
    end if;
  end loop;
  v_n := coalesce(array_length(v_remaining, 1), 0);
  if v_n = 0 then
    return 'ABSENT';
  end if;
  foreach v_val in array v_remaining
  loop
    if v_val = 'SATISFIED' then v_s := v_s + 1; end if;
    if v_val = 'UNKNOWN' then v_u := v_u + 1; end if;
  end loop;
  if p_operator = 'ALL' then
    if 'NOT_SATISFIED' = any (v_remaining) then return 'NOT_SATISFIED'; end if;
    if v_u > 0 then return 'UNKNOWN'; end if;
    return 'SATISFIED';
  end if;
  if p_operator = 'ANY' then
    if v_s > 0 then return 'SATISFIED'; end if;
    if v_u > 0 then return 'UNKNOWN'; end if;
    return 'NOT_SATISFIED';
  end if;
  if p_k is null then
    raise exception using errcode = '55000',
      message = 'Projected AT_LEAST threshold is missing',
      hint = 'eligibility_missing_projected_threshold';
  end if;
  if v_s >= p_k then return 'SATISFIED'; end if;
  if v_s + v_u < p_k then return 'NOT_SATISFIED'; end if;
  return 'UNKNOWN';
end;
$$;

create or replace function private.eligibility_v02_derive_outcome(
  p_ordinary public.eligibility_projection_value,
  p_conditional public.eligibility_projection_value
) returns public.eligibility_outcome
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
begin
  if p_ordinary is distinct from 'ABSENT' and p_conditional = 'ABSENT' then
    raise exception using errcode = '55000',
      message = 'Invalid ordinary/conditional projection pair',
      hint = 'eligibility_projection_invalid_state';
  end if;
  if p_ordinary = 'NOT_SATISFIED' then return 'NOT_ELIGIBLE'; end if;
  if p_ordinary = 'UNKNOWN' then return 'UNKNOWN'; end if;
  if p_ordinary in ('SATISFIED', 'ABSENT') then
    if p_conditional in ('SATISFIED', 'ABSENT') then return 'ELIGIBLE'; end if;
    if p_conditional = 'NOT_SATISFIED' then return 'CONDITIONALLY_ELIGIBLE'; end if;
    if p_conditional = 'UNKNOWN' then return 'UNKNOWN'; end if;
  end if;
  raise exception using errcode = '55000',
    message = 'Invalid ordinary/conditional projection pair',
    hint = 'eligibility_projection_invalid_state';
end;
$$;


create or replace function private.canonical_json_v02(p jsonb)
returns text
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
declare
  v_type text;
  v_keys text[];
  v_key text;
  v_parts text[] := '{}';
  v_elem jsonb;
  v_num numeric;
  v_text text;
  v_escaped text;
  i integer;
begin
  if p is null or p = 'null'::jsonb then
    return 'null';
  end if;
  v_type := jsonb_typeof(p);
  if v_type = 'boolean' then
    return p::text;
  end if;
  if v_type = 'number' then
    v_num := (p #>> '{}')::numeric;
    if v_num = 0 then return '0'; end if;
    v_text := trim(both from v_num::text);
    if v_text ~ '[eE]' then
      raise exception using errcode = '22023',
        message = 'Canonical numeric exponent form is forbidden',
        hint = 'eligibility_v02_canonical_exponent_forbidden';
    end if;
    -- Trim trailing fractional zeros only. Never trim integer zeros:
    -- 10 must remain "10", not "1".
    if v_text like '%.%' then
      v_text := rtrim(v_text, '0');
      v_text := rtrim(v_text, '.');
    end if;
    if v_text in ('', '-', '-0') then return '0'; end if;
    return v_text;
  end if;
  if v_type = 'string' then
    v_text := normalize(p #>> '{}', nfc);
    v_escaped := v_text;
    v_escaped := replace(v_escaped, '\', '\\');
    v_escaped := replace(v_escaped, '"', '\"');
    v_escaped := replace(v_escaped, E'\b', '\b');
    v_escaped := replace(v_escaped, E'\f', '\f');
    v_escaped := replace(v_escaped, E'\n', '\n');
    v_escaped := replace(v_escaped, E'\r', '\r');
    v_escaped := replace(v_escaped, E'\t', '\t');
    return '"' || v_escaped || '"';
  end if;
  if v_type = 'array' then
    for v_elem in select value from jsonb_array_elements(p)
    loop
      v_parts := v_parts || private.canonical_json_v02(v_elem);
    end loop;
    return '[' || array_to_string(v_parts, ',') || ']';
  end if;
  select array_agg(k order by k) into v_keys
  from jsonb_object_keys(p) k;
  if v_keys is null then
    return '{}';
  end if;
  foreach v_key in array v_keys
  loop
    v_parts := v_parts || (
      private.canonical_json_v02(to_jsonb(normalize(v_key, nfc)))
      || ':'
      || private.canonical_json_v02(p -> v_key)
    );
  end loop;
  return '{' || array_to_string(v_parts, ',') || '}';
end;
$$;

create or replace function private.eligibility_v02_lock_evaluation(p_evaluation_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_student uuid;
  v_eval public.eligibility_evaluations%rowtype;
begin
  select p.student_id into v_student
  from public.eligibility_evaluations e
  join public.student_profile_versions p using (profile_version_id)
  where e.evaluation_id = p_evaluation_id;
  if v_student is null then
    raise exception using errcode = '23503', message = 'Evaluation does not exist';
  end if;
  perform private.lock_student_lifecycle(v_student);
  perform private.lock_student_owned_total_order(v_student);
  select * into v_eval
  from public.eligibility_evaluations
  where evaluation_id = p_evaluation_id
  for update;
  return v_student;
end;
$$;

create or replace function private.eligibility_v02_require_building_unsealed(p_evaluation_id uuid)
returns uuid
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_student uuid;
  v_eval public.eligibility_evaluations%rowtype;
begin
  v_student := private.eligibility_v02_lock_evaluation(p_evaluation_id);
  select * into v_eval from public.eligibility_evaluations where evaluation_id = p_evaluation_id;
  if v_eval.input_schema_version is distinct from 'eligibility-v0.2' then
    raise exception using errcode = '55000',
      message = 'v0.2 API cannot operate on a v0.1 evaluation',
      hint = 'eligibility_v02_api_on_v01_row';
  end if;
  if v_eval.evaluation_state is distinct from 'BUILDING' or v_eval.inputs_sealed_at is not null then
    raise exception using errcode = '55000',
      message = 'A BUILDING unsealed v0.2 evaluation is required';
  end if;
  return v_student;
end;
$$;

create or replace function private.eligibility_v02_pin_mismatch(p_message text)
returns void
language plpgsql
immutable
set search_path = pg_catalog, public
as $$
begin
  raise exception using errcode = '22023',
    message = p_message,
    hint = 'eligibility_pin_payload_mismatch';
end;
$$;

create or replace function private.eligibility_v02_scope_semantic(p_scope_id uuid)
returns jsonb
language sql
stable
set search_path = pg_catalog, public
as $$
  select case
    when p_scope_id is null then null
    else jsonb_build_object(
      'scopeKind', s.scope_kind,
      'educationContextId', s.education_context_id,
      'domain', s.domain
    )
  end
  from (select p_scope_id as scope_id) q
  left join public.eligibility_snapshot_scopes s on s.scope_id = q.scope_id;
$$;


create or replace function public.insert_eligibility_rule_set_pin(p_row public.eligibility_rule_set_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_src public.program_requirement_rule_sets%rowtype;
        v_eval public.eligibility_evaluations%rowtype;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_eval from public.eligibility_evaluations
    where evaluation_id = p_row.evaluation_id;
  select * into v_src from public.program_requirement_rule_sets
    where rule_set_id = p_row.rule_set_id for key share;
  if not found then
    raise exception using errcode = '23503', message = 'Rule set does not exist';
  end if;
  if v_src.rule_set_id is distinct from v_eval.rule_set_id
     or v_src.status is distinct from 'VERIFIED'
     or v_src.engine_contract_version is distinct from 'eligibility-v0.2'
     or v_src.rule_schema_version is distinct from 'phase2-v0.2'
     or v_src.rule_set_id is distinct from p_row.rule_set_id
     or v_src.program_version_id is distinct from p_row.program_version_id
     or v_src.rule_set_version is distinct from p_row.rule_set_version
     or v_src.taxonomy_release_code is distinct from p_row.taxonomy_release_code
     or v_src.taxonomy_release_code is distinct from v_eval.taxonomy_release_code
     or v_src.rule_schema_version is distinct from p_row.rule_schema_version
     or v_src.engine_contract_version is distinct from p_row.engine_contract_version
     or v_src.verification_evidence_id is distinct from p_row.verification_evidence_id
     or v_src.verified_by is distinct from p_row.verified_by
     or v_src.verified_at is distinct from p_row.verified_at
     or p_row.taxonomy_release_ordinal is distinct from v_eval.taxonomy_release_ordinal then
    perform private.eligibility_v02_pin_mismatch(
      'Rule-set pin does not match the evaluation source row');
  end if;
  perform public.insert_composite('public.eligibility_rule_set_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_rule_set_pins', p_row.evaluation_id, 'PIN');
end;
$$;

create or replace function public.insert_eligibility_rule_node_pin(p_row public.eligibility_rule_node_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_src public.program_requirement_nodes%rowtype;
        v_eval public.eligibility_evaluations%rowtype;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_eval from public.eligibility_evaluations
    where evaluation_id = p_row.evaluation_id;
  select * into v_src from public.program_requirement_nodes
    where rule_node_id = p_row.rule_node_id for key share;
  if not found then
    raise exception using errcode = '23503', message = 'Rule node does not exist';
  end if;
  if v_src.rule_set_id is distinct from v_eval.rule_set_id
     or v_src.rule_node_id is distinct from p_row.rule_node_id
     or v_src.parent_node_id is distinct from p_row.parent_node_id
     or v_src.sort_order is distinct from p_row.sort_order
     or v_src.node_kind is distinct from p_row.node_kind
     or v_src.group_operator is distinct from p_row.group_operator
     or v_src.minimum_children is distinct from p_row.minimum_children
     or v_src.predicate_kind is distinct from p_row.predicate_kind
     or v_src.requirement_strength is distinct from p_row.requirement_strength
     or v_src.requirement_semantics is distinct from p_row.requirement_semantics
     or v_src.target_concept_id is distinct from p_row.target_concept_id
     or v_src.explanation_template is distinct from p_row.explanation_template then
    perform private.eligibility_v02_pin_mismatch(
      'Rule-node pin does not match the evaluation rule set source row');
  end if;
  perform public.insert_composite('public.eligibility_rule_node_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_rule_node_pins', p_row.rule_node_id, 'PIN');
end;
$$;

create or replace function public.insert_eligibility_student_mapping_pin(p_row public.eligibility_student_mapping_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_src public.student_record_concept_mappings%rowtype;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_src from public.student_record_concept_mappings
    where student_mapping_id = p_row.student_mapping_id for key share;
  if not found then
    raise exception using errcode = '23503', message = 'Student mapping does not exist';
  end if;
  if v_src.profile_version_id is distinct from (
       select profile_version_id from public.eligibility_evaluations
        where evaluation_id = p_row.evaluation_id) then
    perform private.eligibility_v02_pin_mismatch(
      'Student mapping pin does not belong to the evaluation profile');
  end if;
  if v_src.mapping_status not in ('VERIFIED', 'PROPOSED') then
    raise exception using errcode = '22023',
      message = 'Mapping is not universe-eligible at the pin boundary',
      hint = 'eligibility_mapping_status_not_universe_eligible';
  end if;
  if p_row.status_at_pin is distinct from v_src.mapping_status
     or p_row.concept_id is distinct from v_src.concept_id
     or p_row.record_type is distinct from v_src.record_type
     or p_row.student_record_id is distinct from v_src.student_record_id
     or p_row.profile_version_id is distinct from v_src.profile_version_id
     or p_row.method is distinct from v_src.method
     or p_row.confidence is distinct from v_src.confidence
     or p_row.model_version is distinct from v_src.model_version
     or p_row.student_evidence_id is distinct from v_src.student_evidence_id
     or p_row.reviewed_by is distinct from v_src.reviewed_by
     or p_row.reviewed_at is distinct from v_src.reviewed_at
     or p_row.retired_at_pin is distinct from v_src.retired_at
     or p_row.retirement_reason_at_pin is distinct from v_src.retirement_reason
     or p_row.relation_at_pin is distinct from 'STUDENT_CONCEPT_ASSOCIATION' then
    raise exception using errcode = '22023',
      message = 'Student mapping pin does not match the source row',
      hint = 'eligibility_pin_payload_mismatch';
  end if;
  perform public.insert_composite('public.eligibility_student_mapping_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_student_mapping_pins', p_row.student_mapping_id, 'PIN');
end;
$$;

create or replace function public.insert_eligibility_catalog_mapping_pin(p_row public.eligibility_catalog_mapping_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_src public.catalog_concept_mappings%rowtype;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_src from public.catalog_concept_mappings
    where mapping_id = p_row.catalog_mapping_id for key share;
  if not found then
    raise exception using errcode = '23503', message = 'Catalog mapping does not exist';
  end if;
  if v_src.mapping_status not in ('VERIFIED', 'PROPOSED') then
    raise exception using errcode = '22023',
      message = 'Mapping is not universe-eligible at the pin boundary',
      hint = 'eligibility_mapping_status_not_universe_eligible';
  end if;
  if p_row.status_at_pin is distinct from v_src.mapping_status
     or p_row.concept_id is distinct from v_src.concept_id
     or p_row.relation_at_pin is distinct from v_src.relation
     or p_row.record_type is distinct from v_src.record_type
     or p_row.record_id is distinct from v_src.record_id
     or p_row.method is distinct from v_src.method
     or p_row.confidence is distinct from v_src.confidence
     or p_row.model_version is distinct from v_src.model_version
     or p_row.verification_evidence_id is distinct from v_src.verification_evidence_id
     or p_row.reviewed_by is distinct from v_src.reviewed_by
     or p_row.reviewed_at is distinct from v_src.reviewed_at
     or p_row.retired_at_pin is distinct from v_src.retired_at
     or p_row.retirement_reason_at_pin is distinct from v_src.retirement_reason then
    raise exception using errcode = '22023',
      message = 'Catalog mapping pin does not match the source row',
      hint = 'eligibility_pin_payload_mismatch';
  end if;
  perform public.insert_composite('public.eligibility_catalog_mapping_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_catalog_mapping_pins', p_row.catalog_mapping_id, 'PIN');
end;
$$;

create or replace function public.insert_eligibility_taxonomy_concept_pin(p_row public.eligibility_taxonomy_concept_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_src public.taxonomy_concepts%rowtype; v_pin bigint;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_src from public.taxonomy_concepts where concept_id = p_row.concept_id for key share;
  select taxonomy_release_ordinal into v_pin from public.eligibility_evaluations where evaluation_id = p_row.evaluation_id;
  if p_row.canonical_key is distinct from v_src.canonical_key
     or p_row.concept_kind is distinct from v_src.concept_kind
     or p_row.introduced_release_ordinal is distinct from v_src.introduced_release_ordinal
     or p_row.retired_release_ordinal is distinct from v_src.retired_release_ordinal
     or not private.eligibility_v02_active_at_ordinal(
          v_src.introduced_release_ordinal, v_pin, v_src.retired_release_ordinal) then
    raise exception using errcode = '22023',
      message = 'Taxonomy concept pin does not match the source row or is inactive at pin',
      hint = 'eligibility_pin_payload_mismatch';
  end if;
  perform public.insert_composite('public.eligibility_taxonomy_concept_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_taxonomy_concept_pins', p_row.concept_id, 'PIN');
end;
$$;

create or replace function public.insert_eligibility_completeness_pin(p_row public.eligibility_completeness_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_src public.student_data_completeness%rowtype;
        v_eval public.eligibility_evaluations%rowtype;
        v_scope public.eligibility_snapshot_scopes%rowtype;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_eval from public.eligibility_evaluations
    where evaluation_id = p_row.evaluation_id;
  select * into v_src from public.student_data_completeness
    where completeness_id = p_row.completeness_id for key share;
  if not found then
    raise exception using errcode = '23503', message = 'Completeness row does not exist';
  end if;
  if v_src.profile_version_id is distinct from v_eval.profile_version_id
     or p_row.domain is distinct from v_src.domain
     or p_row.completeness is distinct from v_src.completeness
     or p_row.explanation is distinct from v_src.explanation then
    perform private.eligibility_v02_pin_mismatch(
      'Completeness pin does not match the evaluation profile source row');
  end if;
  if p_row.scope_id is not null then
    select * into v_scope from public.eligibility_snapshot_scopes
      where scope_id = p_row.scope_id;
    if not found
       or v_scope.evaluation_id is distinct from p_row.evaluation_id
       or v_scope.domain is distinct from v_src.domain
       or v_scope.education_context_id is distinct from v_src.education_context_id then
      perform private.eligibility_v02_pin_mismatch(
        'Completeness pin scope is not the evaluation snapshot identity');
    end if;
  end if;
  perform public.insert_composite('public.eligibility_completeness_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_completeness_pins', p_row.completeness_id, 'PIN');
end;
$$;

create or replace function public.insert_eligibility_snapshot_scope(p_row public.eligibility_snapshot_scopes)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_eval public.eligibility_evaluations%rowtype;
        v_pin public.eligibility_completeness_pins%rowtype;
        v_has_degree boolean;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_eval from public.eligibility_evaluations
    where evaluation_id = p_row.evaluation_id;
  if p_row.profile_version_id is distinct from v_eval.profile_version_id then
    perform private.eligibility_v02_pin_mismatch(
      'Snapshot scope profile does not match the evaluation');
  end if;
  v_has_degree := exists (
    select 1 from public.student_degrees
     where profile_version_id = v_eval.profile_version_id
  );
  if p_row.scope_kind = 'UNASSIGNED_CONTEXT' and v_has_degree
     and (p_row.completeness_id is not null or p_row.completeness is not null) then
    raise exception using errcode = '55000',
      message = 'UNASSIGNED_CONTEXT completeness is not a 012 identity when degrees exist',
      hint = 'eligibility_unassigned_completeness_fabricated';
  end if;
  if (p_row.completeness is null) <> (p_row.completeness_id is null) then
    perform private.eligibility_v02_pin_mismatch(
      'Snapshot completeness identity and value must be set together');
  end if;
  if p_row.completeness is not null then
    select * into v_pin from public.eligibility_completeness_pins
      where evaluation_id = p_row.evaluation_id
        and completeness_id = p_row.completeness_id;
    if not found
       or v_pin.completeness is distinct from p_row.completeness
       or v_pin.domain is distinct from p_row.domain then
      perform private.eligibility_v02_pin_mismatch(
        'Snapshot completeness is not authorized by a completeness pin');
    end if;
  end if;
  perform public.insert_composite('public.eligibility_snapshot_scopes'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_snapshot_scopes', p_row.scope_id, 'PIN');
end;
$$;

create or replace function public.insert_eligibility_snapshot_degree(p_row public.eligibility_snapshot_degrees)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_eval uuid; v_payload jsonb;
        v_scope public.eligibility_snapshot_scopes%rowtype;
        v_src public.student_degrees%rowtype;
begin
  select * into v_scope from public.eligibility_snapshot_scopes where scope_id = p_row.scope_id;
  if not found then
    raise exception using errcode = '23503', message = 'Snapshot scope does not exist';
  end if;
  v_eval := v_scope.evaluation_id;
  v_student := private.eligibility_v02_require_building_unsealed(v_eval);
  select * into v_src from public.student_degrees
    where student_degree_id = p_row.student_degree_id for key share;
  if not found
     or v_src.profile_version_id is distinct from v_scope.profile_version_id
     or v_scope.scope_kind is distinct from 'GLOBAL_PROFILE'
     or v_scope.domain is distinct from 'EDUCATION_HISTORY' then
    perform private.eligibility_v02_pin_mismatch(
      'Degree snapshot member does not match the frozen profile scope');
  end if;
  v_payload := to_jsonb(p_row) || jsonb_build_object('evaluation_id', v_eval);
  perform public.insert_composite('public.eligibility_snapshot_degrees'::regclass, v_payload);
end;
$$;

create or replace function public.insert_eligibility_snapshot_course(p_row public.eligibility_snapshot_courses)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_eval uuid; v_payload jsonb;
        v_scope public.eligibility_snapshot_scopes%rowtype;
        v_src public.student_courses%rowtype;
begin
  select * into v_scope from public.eligibility_snapshot_scopes where scope_id = p_row.scope_id;
  if not found then
    raise exception using errcode = '23503', message = 'Snapshot scope does not exist';
  end if;
  v_eval := v_scope.evaluation_id;
  v_student := private.eligibility_v02_require_building_unsealed(v_eval);
  select * into v_src from public.student_courses
    where student_course_id = p_row.student_course_id for key share;
  if not found
     or v_src.profile_version_id is distinct from v_scope.profile_version_id
     or v_scope.domain is distinct from 'COURSE_HISTORY'
     or (
          v_src.student_degree_id is null
          and v_scope.scope_kind is distinct from 'UNASSIGNED_CONTEXT'
        )
     or (
          v_src.student_degree_id is not null
          and (
            v_scope.scope_kind is distinct from 'EDUCATION_CONTEXT'
            or v_scope.education_context_id is distinct from v_src.student_degree_id
          )
        ) then
    perform private.eligibility_v02_pin_mismatch(
      'Course snapshot member does not match the frozen profile scope');
  end if;
  v_payload := to_jsonb(p_row) || jsonb_build_object('evaluation_id', v_eval);
  perform public.insert_composite('public.eligibility_snapshot_courses'::regclass, v_payload);
end;
$$;

create or replace function public.insert_eligibility_snapshot_test_score(p_row public.eligibility_snapshot_test_scores)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_eval uuid; v_payload jsonb;
        v_scope public.eligibility_snapshot_scopes%rowtype;
        v_src public.student_test_scores%rowtype;
begin
  select * into v_scope from public.eligibility_snapshot_scopes where scope_id = p_row.scope_id;
  if not found then
    raise exception using errcode = '23503', message = 'Snapshot scope does not exist';
  end if;
  v_eval := v_scope.evaluation_id;
  perform private.eligibility_v02_require_building_unsealed(v_eval);
  select * into v_src from public.student_test_scores
    where student_test_score_id = p_row.student_test_score_id for key share;
  if not found
     or v_src.profile_version_id is distinct from v_scope.profile_version_id
     or v_scope.scope_kind is distinct from 'GLOBAL_PROFILE'
     or v_scope.domain is distinct from 'TEST_HISTORY' then
    perform private.eligibility_v02_pin_mismatch(
      'Test snapshot member does not match the frozen profile scope');
  end if;
  v_payload := to_jsonb(p_row) || jsonb_build_object('evaluation_id', v_eval);
  perform public.insert_composite('public.eligibility_snapshot_test_scores'::regclass, v_payload);
end;
$$;

create or replace function public.insert_eligibility_snapshot_mapping_universe(p_row public.eligibility_snapshot_mapping_universe)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_eval uuid; v_payload jsonb; v_status public.mapping_status;
begin
  select evaluation_id into v_eval from public.eligibility_snapshot_scopes where scope_id = p_row.scope_id;
  perform private.eligibility_v02_require_building_unsealed(v_eval);
  select status_at_pin into v_status
    from public.eligibility_student_mapping_pins
   where evaluation_id = v_eval and student_mapping_id = p_row.student_mapping_id;
  if v_status is null then
    raise exception using errcode = '22023',
      message = 'Universe member must already be pinned',
      hint = 'eligibility_authoritative_universe_mismatch';
  end if;
  if (p_row.universe_role = 'AUTHORITATIVE' and v_status is distinct from 'VERIFIED')
     or (p_row.universe_role = 'LIMITING' and v_status is distinct from 'PROPOSED') then
    raise exception using errcode = '22023',
      message = 'Universe role does not match status_at_pin',
      hint = 'eligibility_authoritative_universe_mismatch';
  end if;
  v_payload := to_jsonb(p_row) || jsonb_build_object('evaluation_id', v_eval);
  perform public.insert_composite('public.eligibility_snapshot_mapping_universe'::regclass, v_payload);
end;
$$;


create or replace function public.insert_eligibility_rule_node_source_pin(p_row public.eligibility_rule_node_source_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_student uuid;
  v_eval public.eligibility_evaluations%rowtype;
  v_node public.program_requirement_nodes%rowtype;
  v_obs public.field_observations%rowtype;
  v_ev public.evidence_items%rowtype;
  v_src public.sources%rowtype;
  v_bind public.field_observation_applicability%rowtype;
  v_assertion public.evidence_applicability_assertions%rowtype;
  v_head uuid;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_eval from public.eligibility_evaluations
    where evaluation_id = p_row.evaluation_id;
  if not exists (
    select 1 from public.program_requirement_node_sources
     where rule_node_id = p_row.rule_node_id
       and field_observation_id = p_row.field_observation_id
  ) then
    perform private.eligibility_v02_pin_mismatch(
      'Rule-node source pin is not a source membership of the pinned node');
  end if;
  select * into v_node from public.program_requirement_nodes
    where rule_node_id = p_row.rule_node_id for key share;
  if not found or v_node.rule_set_id is distinct from v_eval.rule_set_id then
    perform private.eligibility_v02_pin_mismatch(
      'Rule-node source pin does not belong to the evaluation rule set');
  end if;
  select * into v_obs from public.field_observations
    where observation_id = p_row.field_observation_id for key share;
  if not found then
    raise exception using errcode = '23503', message = 'Field observation does not exist';
  end if;
  if v_obs.knowledge_status is distinct from p_row.knowledge_status_at_pin then
    perform private.eligibility_v02_pin_mismatch(
      'Caller cannot fabricate knowledge_status_at_pin');
  end if;
  select * into v_ev from public.evidence_items
    where evidence_id = v_obs.evidence_id for key share;
  if v_obs.evidence_id is not null then
    select * into v_src from public.sources
      where source_id = v_ev.source_id for key share;
    if p_row.source_id is distinct from v_src.source_id then
      perform private.eligibility_v02_pin_mismatch(
        'Rule-node source pin source_id does not match the observation evidence source');
    end if;
  elsif p_row.source_id is not null then
    perform private.eligibility_v02_pin_mismatch(
      'Rule-node source pin source_id is not authorized by the observation');
  end if;
  select * into v_bind from public.field_observation_applicability
    where observation_id = p_row.field_observation_id;
  if not found then
    perform private.eligibility_v02_pin_mismatch(
      'v0.2 source pins require an applicability assertion');
  end if;
  select * into v_assertion from public.evidence_applicability_assertions
    where assertion_id = v_bind.assertion_id for key share;
  if v_assertion.applicability_status = 'LEGACY_UNASSERTED' then
    raise exception using errcode = '22023',
      message = 'LEGACY_UNASSERTED cannot authorize a new v0.2 pin',
      hint = 'eligibility_pin_payload_mismatch';
  end if;
  if p_row.applicability_assertion_id is distinct from v_bind.assertion_id
     or p_row.applicability_head_assertion_id_at_pin is distinct from v_bind.assertion_id
     or p_row.applicability_scope_id is distinct from v_assertion.scope_id then
    perform private.eligibility_v02_pin_mismatch(
      'Applicability assertion/head/scope at pin do not match the headed source');
  end if;
  if v_assertion.scope_id is not null then
    select assertion_id into v_head from public.evidence_applicability_heads
      where scope_id = v_assertion.scope_id;
    if v_head is distinct from v_bind.assertion_id then
      perform private.eligibility_v02_pin_mismatch(
        'Applicability assertion is not the current head at pin');
    end if;
    if v_assertion.applicability_status is distinct from 'REVIEWED_APPLICABLE' then
      perform private.eligibility_v02_pin_mismatch(
        'v0.2 authority requires headed REVIEWED_APPLICABLE');
    end if;
  end if;
  perform public.insert_composite('public.eligibility_rule_node_source_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_rule_node_source_pins', p_row.evaluation_id, 'PIN');
end;
$$;


create or replace function public.insert_eligibility_rule_node_mapping_pin(p_row public.eligibility_rule_node_mapping_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_eval public.eligibility_evaluations%rowtype;
        v_node public.program_requirement_nodes%rowtype;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_eval from public.eligibility_evaluations
    where evaluation_id = p_row.evaluation_id;
  select * into v_node from public.program_requirement_nodes
    where rule_node_id = p_row.rule_node_id for key share;
  if not found or v_node.rule_set_id is distinct from v_eval.rule_set_id then
    perform private.eligibility_v02_pin_mismatch(
      'Rule-node mapping pin does not belong to the evaluation rule set');
  end if;
  if not exists (
    select 1 from public.program_requirement_node_mappings
     where rule_node_id = p_row.rule_node_id
       and catalog_mapping_id = p_row.catalog_mapping_id
  ) then
    perform private.eligibility_v02_pin_mismatch(
      'Rule-node mapping pin is not a catalog-mapping membership of the node');
  end if;
  if not exists (
    select 1 from public.eligibility_catalog_mapping_pins
     where evaluation_id = p_row.evaluation_id
       and catalog_mapping_id = p_row.catalog_mapping_id
  ) then
    perform private.eligibility_v02_pin_mismatch(
      'Rule-node mapping pin requires a catalog mapping pin');
  end if;
  perform public.insert_composite('public.eligibility_rule_node_mapping_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_rule_node_mapping_pins', p_row.evaluation_id, 'PIN');
end;
$$;


create or replace function public.insert_eligibility_projection_threshold_pin(p_row public.eligibility_projection_threshold_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_eval public.eligibility_evaluations%rowtype;
        v_src public.requirement_group_projection_thresholds%rowtype;
        v_node public.program_requirement_nodes%rowtype;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_eval from public.eligibility_evaluations
    where evaluation_id = p_row.evaluation_id;
  select * into v_node from public.program_requirement_nodes
    where rule_node_id = p_row.group_node_id for key share;
  if not found or v_node.rule_set_id is distinct from v_eval.rule_set_id then
    perform private.eligibility_v02_pin_mismatch(
      'Projection threshold pin group is not in the evaluation rule set');
  end if;
  select * into v_src from public.requirement_group_projection_thresholds
    where rule_set_id = p_row.rule_set_id
      and group_node_id = p_row.group_node_id
      and projection_kind = p_row.projection_kind
    for key share;
  if not found
     or p_row.rule_set_id is distinct from v_eval.rule_set_id
     or p_row.projected_minimum_children is distinct from v_src.projected_minimum_children
     or p_row.projected_descendant_count is distinct from v_src.projected_descendant_count
     or p_row.verification_evidence_id is distinct from v_src.verification_evidence_id
     or p_row.verified_by is distinct from v_src.verified_by
     or p_row.verified_at is distinct from v_src.verified_at
     or p_row.created_at_source is distinct from v_src.created_at then
    perform private.eligibility_v02_pin_mismatch(
      'Projection threshold pin does not match the verified source row');
  end if;
  perform public.insert_composite('public.eligibility_projection_threshold_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_projection_threshold_pins', p_row.evaluation_id, 'PIN');
end;
$$;


create or replace function public.insert_eligibility_catalog_observation_pin(p_row public.eligibility_catalog_observation_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_student uuid;
  v_obs public.field_observations%rowtype;
  v_ev public.evidence_items%rowtype;
  v_src public.sources%rowtype;
  v_bind public.field_observation_applicability%rowtype;
  v_assertion public.evidence_applicability_assertions%rowtype;
  v_scope public.evidence_applicability_scopes%rowtype;
  v_sel public.canonical_field_selections%rowtype;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_obs from public.field_observations
    where observation_id = p_row.field_observation_id for key share;
  if not found then
    raise exception using errcode = '23503', message = 'Field observation does not exist';
  end if;
  select * into v_ev from public.evidence_items where evidence_id = v_obs.evidence_id;
  if v_obs.evidence_id is not null then
    select * into v_src from public.sources where source_id = v_ev.source_id for key share;
  end if;
  select * into v_sel from public.canonical_field_selections
    where record_type = v_obs.record_type
      and record_id = v_obs.record_id
      and field_name = v_obs.field_name;
  select * into v_bind from public.field_observation_applicability
    where observation_id = p_row.field_observation_id;
  if found then
    select * into v_assertion from public.evidence_applicability_assertions
      where assertion_id = v_bind.assertion_id;
    if v_assertion.scope_id is not null then
      select * into v_scope from public.evidence_applicability_scopes
        where scope_id = v_assertion.scope_id;
    end if;
  end if;
  if p_row.record_type is distinct from v_obs.record_type
     or p_row.record_id is distinct from v_obs.record_id
     or p_row.field_name is distinct from v_obs.field_name
     or p_row.knowledge_status is distinct from v_obs.knowledge_status
     or p_row.canonical_value is distinct from v_obs.observed_value
     or p_row.evidence_id is distinct from v_obs.evidence_id
     or (v_src.source_id is not null and (
           p_row.source_id is distinct from v_src.source_id
           or p_row.source_identity_id is distinct from v_src.source_identity_id
           or p_row.source_revision_number is distinct from v_src.revision_number
           or p_row.retrieval_content_hash is distinct from v_src.retrieval_content_hash
         ))
     or (v_scope.scope_id is not null and (
           p_row.program_scope_key is distinct from v_scope.program_scope_key
           or p_row.program_version_scope_key is distinct from v_scope.program_version_scope_key
           or p_row.granularity_scope is distinct from v_scope.granularity_scope
           or p_row.population_scope_code is distinct from v_scope.population_scope_code
           or p_row.cycle_scope_code is distinct from v_scope.cycle_scope_code
         )) then
    perform private.eligibility_v02_pin_mismatch(
      'Catalog observation pin does not match the source observation/revision/scope');
  end if;
  perform public.insert_composite('public.eligibility_catalog_observation_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_catalog_observation_pins', p_row.evaluation_id, 'PIN');
end;
$$;


create or replace function public.insert_eligibility_catalog_selection_pin(p_row public.eligibility_catalog_selection_pins)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_src public.canonical_field_selections%rowtype;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_row.evaluation_id);
  select * into v_src from public.canonical_field_selections
    where record_type = p_row.record_type
      and record_id = p_row.record_id
      and field_name = p_row.field_name
    for key share;
  if not found
     or p_row.observation_id is distinct from v_src.observation_id
     or p_row.selected_at_pin is distinct from v_src.selected_at
     or p_row.selected_by_pin is distinct from v_src.selected_by then
    perform private.eligibility_v02_pin_mismatch(
      'Catalog selection pin does not match the canonical selection row');
  end if;
  if not exists (
    select 1 from public.eligibility_catalog_observation_pins
     where evaluation_id = p_row.evaluation_id
       and field_observation_id = p_row.observation_id
  ) then
    perform private.eligibility_v02_pin_mismatch(
      'Catalog selection pin requires the selected observation pin');
  end if;
  perform public.insert_composite('public.eligibility_catalog_selection_pins'::regclass, to_jsonb(p_row));
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_catalog_selection_pins', p_row.evaluation_id, 'PIN');
end;
$$;


create or replace function public.insert_requirement_group_projection_threshold(
  p_row public.requirement_group_projection_thresholds
)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, extensions
as $$
declare v_rs public.program_requirement_rule_sets%rowtype;
begin
  if current_user is distinct from 'foundation_catalog_executor' then
    raise exception using errcode = '42501', message = 'Catalog executor required';
  end if;
  select * into v_rs from public.program_requirement_rule_sets
    where rule_set_id = p_row.rule_set_id for update;
  if v_rs.status is distinct from 'DRAFT'
     or v_rs.engine_contract_version is distinct from 'eligibility-v0.2' then
    raise exception using errcode = '55000', message = 'A DRAFT eligibility-v0.2 rule set is required';
  end if;
  if p_row.projection_kind = 'FULL' then
    raise exception using errcode = '22023',
      message = 'FULL thresholds are written at verification',
      hint = 'eligibility_full_threshold_not_reviewer_supplied';
  end if;
  perform public.insert_composite(
    'public.requirement_group_projection_thresholds'::regclass, to_jsonb(p_row));
end;
$$;

create or replace function public.start_eligibility_evaluation_v02(
  p_profile_version_id uuid,
  p_rule_set_id uuid,
  p_taxonomy_release_code text,
  p_evaluator_name text,
  p_evaluator_version text,
  p_evaluator_build_hash text
) returns uuid
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_student uuid;
  v_hash text;
  v_status public.profile_version_status;
  v_rs public.program_requirement_rule_sets%rowtype;
  v_rel public.taxonomy_releases%rowtype;
  v_id uuid;
begin
  select student_id, snapshot_hash, status into v_student, v_hash, v_status
  from public.student_profile_versions
  where profile_version_id = p_profile_version_id;
  if v_student is null then
    raise exception using errcode = '23503', message = 'Profile version does not exist';
  end if;
  perform private.lock_student_lifecycle(v_student);
  perform private.lock_student_owned_total_order(v_student);
  if v_status is distinct from 'FROZEN' then
    raise exception using errcode = '55000', message = 'A FROZEN profile is required';
  end if;
  select * into v_rs from public.program_requirement_rule_sets
    where rule_set_id = p_rule_set_id for key share;
  select * into v_rel from public.taxonomy_releases
    where release_code = p_taxonomy_release_code for key share;
  if v_rs.status is distinct from 'VERIFIED'
     or v_rs.engine_contract_version is distinct from 'eligibility-v0.2'
     or v_rs.taxonomy_release_code is distinct from p_taxonomy_release_code
     or v_rel.status is distinct from 'VERIFIED' then
    raise exception using errcode = '55000',
      message = 'A VERIFIED eligibility-v0.2 rule set and taxonomy release are required';
  end if;
  insert into public.eligibility_evaluations (
    profile_version_id, rule_set_id, taxonomy_release_code,
    evaluator_name, evaluator_version, evaluator_build_hash,
    input_schema_version, profile_snapshot_hash,
    result_semantics_version, canonicalization_version, contract_release_code,
    taxonomy_release_ordinal
  ) values (
    p_profile_version_id, p_rule_set_id, p_taxonomy_release_code,
    p_evaluator_name, p_evaluator_version, p_evaluator_build_hash,
    'eligibility-v0.2', v_hash,
    'eligibility-v0.2', 'eligibility-v0.2-c14n1', 'phase2-v0.2',
    v_rel.release_ordinal
  ) returning evaluation_id into v_id;
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_evaluations', v_id, 'START_V02');
  return v_id;
end;
$$;


create or replace function private.canonical_eligibility_v02_input_fingerprint(p_evaluation_id uuid)
returns text
language plpgsql
stable
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_eval public.eligibility_evaluations%rowtype;
  v_obj jsonb;
  v_student uuid;
begin
  select * into v_eval from public.eligibility_evaluations where evaluation_id = p_evaluation_id;
  select student_id into v_student from public.student_profile_versions
    where profile_version_id = v_eval.profile_version_id;
  v_obj := jsonb_build_object(
    'contract', jsonb_build_object(
      'releaseCode', v_eval.contract_release_code,
      'inputSchemaVersion', v_eval.input_schema_version,
      'resultSemanticsVersion', v_eval.result_semantics_version,
      'canonicalizationVersion', v_eval.canonicalization_version
    ),
    'profile', jsonb_build_object(
      'profileVersionId', v_eval.profile_version_id,
      'studentId', v_student,
      'snapshotHash', v_eval.profile_snapshot_hash
    ),
    'evaluator', jsonb_build_object(
      'name', v_eval.evaluator_name,
      'version', v_eval.evaluator_version,
      'buildHash', v_eval.evaluator_build_hash
    ),
    'taxonomy', jsonb_build_object(
      'releaseCode', v_eval.taxonomy_release_code,
      'releaseOrdinal', v_eval.taxonomy_release_ordinal
    ),
    'ruleSet', (
      select jsonb_build_object(
        'ruleSetId', rule_set_id,
        'programVersionId', program_version_id,
        'ruleSetVersion', rule_set_version,
        'ruleSchemaVersion', rule_schema_version,
        'engineContractVersion', engine_contract_version,
        'verificationEvidenceId', verification_evidence_id,
        'verifiedBy', verified_by,
        'verifiedAt', to_char(verified_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
      ) from public.eligibility_rule_set_pins where evaluation_id = p_evaluation_id
    ),
    'ruleNodes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', rule_node_id,
        'parentNodeId', parent_node_id,
        'sortOrder', sort_order,
        'nodeKind', node_kind,
        'groupOperator', group_operator,
        'minimumChildren', minimum_children,
        'predicateKind', predicate_kind,
        'requirementStrength', requirement_strength,
        'requirementSemantics', requirement_semantics,
        'targetConceptId', target_concept_id,
        'explanationTemplate', explanation_template
      ) order by rule_node_id)
      from public.eligibility_rule_node_pins where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'projectionThresholds', coalesce((
      select jsonb_agg(jsonb_build_object(
        'groupNodeId', group_node_id,
        'projection', projection_kind,
        'kProjection', projected_minimum_children,
        'nProjected', projected_descendant_count
      ) order by group_node_id, projection_kind)
      from public.eligibility_projection_threshold_pins where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'studentMappings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scopeKind', s.scope_kind,
        'educationContextId', s.education_context_id,
        'domain', s.domain,
        'studentMappingId', u.student_mapping_id,
        'universeRole', u.universe_role,
        'recordType', p.record_type,
        'studentRecordId', p.student_record_id,
        'conceptId', p.concept_id,
        'relationAtPin', p.relation_at_pin,
        'method', p.method,
        'confidence', p.confidence,
        'modelVersion', p.model_version,
        'studentEvidenceId', p.student_evidence_id,
        'reviewedBy', p.reviewed_by,
        'reviewedAt', to_char(p.reviewed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'statusAtPin', p.status_at_pin
      ) order by s.scope_kind, s.education_context_id nulls first, s.domain, u.universe_role, u.student_mapping_id)
      from public.eligibility_snapshot_mapping_universe u
      join public.eligibility_snapshot_scopes s on s.scope_id = u.scope_id
      join public.eligibility_student_mapping_pins p
        on p.evaluation_id = s.evaluation_id
       and p.student_mapping_id = u.student_mapping_id
      where s.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'courses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scopeKind', s.scope_kind,
        'educationContextId', s.education_context_id,
        'domain', s.domain,
        'studentCourseId', c.student_course_id
      ) order by s.scope_kind, s.education_context_id nulls first, s.domain, c.student_course_id)
      from public.eligibility_snapshot_courses c
      join public.eligibility_snapshot_scopes s using (scope_id)
      where s.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'degrees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scopeKind', s.scope_kind,
        'educationContextId', s.education_context_id,
        'domain', s.domain,
        'studentDegreeId', d.student_degree_id
      ) order by s.scope_kind, s.education_context_id nulls first, s.domain, d.student_degree_id)
      from public.eligibility_snapshot_degrees d
      join public.eligibility_snapshot_scopes s using (scope_id)
      where s.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'testScores', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scopeKind', s.scope_kind,
        'educationContextId', s.education_context_id,
        'domain', s.domain,
        'studentTestScoreId', t.student_test_score_id
      ) order by s.scope_kind, s.education_context_id nulls first, s.domain, t.student_test_score_id)
      from public.eligibility_snapshot_test_scores t
      join public.eligibility_snapshot_scopes s using (scope_id)
      where s.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'completenessScopes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'scopeKind', s.scope_kind,
        'educationContextId', s.education_context_id,
        'domain', s.domain,
        'completenessId', s.completeness_id,
        'completeness', s.completeness,
        'explanation', cp.explanation
      ) order by s.scope_kind, s.education_context_id nulls first, s.domain)
      from public.eligibility_snapshot_scopes s
      left join public.eligibility_completeness_pins cp
        on cp.evaluation_id = s.evaluation_id
       and cp.completeness_id = s.completeness_id
      where s.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'ruleNodeSources', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', rule_node_id,
        'fieldObservationId', field_observation_id,
        'sourceId', source_id,
        'applicabilityAssertionId', applicability_assertion_id,
        'applicabilityHeadAssertionIdAtPin', applicability_head_assertion_id_at_pin,
        'applicabilityScopeId', applicability_scope_id,
        'knowledgeStatusAtPin', knowledge_status_at_pin
      ) order by rule_node_id, field_observation_id)
      from public.eligibility_rule_node_source_pins
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'ruleNodeMappings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', rule_node_id,
        'catalogMappingId', catalog_mapping_id
      ) order by rule_node_id, catalog_mapping_id)
      from public.eligibility_rule_node_mapping_pins
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'catalogSelections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'recordType', record_type,
        'recordId', record_id,
        'fieldName', field_name,
        'observationId', observation_id,
        'selectedAtPin', to_char(selected_at_pin at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'selectedByPin', selected_by_pin
      ) order by record_type, record_id, field_name)
      from public.eligibility_catalog_selection_pins
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'catalogObservations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'fieldObservationId', field_observation_id,
        'sourceId', source_id,
        'sourceIdentityId', source_identity_id,
        'sourceRevisionNumber', source_revision_number,
        'retrievalContentHash', retrieval_content_hash,
        'evidenceId', evidence_id,
        'recordType', record_type,
        'recordId', record_id,
        'fieldName', field_name,
        'canonicalValue', canonical_value,
        'knowledgeStatus', knowledge_status,
        'programScopeKey', program_scope_key,
        'programVersionScopeKey', program_version_scope_key,
        'granularityScope', granularity_scope,
        'populationScopeCode', population_scope_code,
        'cycleScopeCode', cycle_scope_code
      ) order by field_observation_id)
      from public.eligibility_catalog_observation_pins
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'catalogMappings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'catalogMappingId', catalog_mapping_id,
        'recordType', record_type,
        'recordId', record_id,
        'conceptId', concept_id,
        'relationAtPin', relation_at_pin,
        'method', method,
        'confidence', confidence,
        'modelVersion', model_version,
        'verificationEvidenceId', verification_evidence_id,
        'reviewedBy', reviewed_by,
        'reviewedAt', to_char(reviewed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'statusAtPin', status_at_pin
      ) order by catalog_mapping_id)
      from public.eligibility_catalog_mapping_pins
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'taxonomyConcepts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'conceptId', concept_id,
        'canonicalKey', canonical_key,
        'conceptKind', concept_kind,
        'introducedReleaseOrdinal', introduced_release_ordinal,
        'retiredReleaseOrdinal', retired_release_ordinal
      ) order by concept_id)
      from public.eligibility_taxonomy_concept_pins
      where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'studentEvidence', coalesce((
      select jsonb_agg(jsonb_build_object(
        'studentEvidenceId', e.student_evidence_id,
        'evidenceType', e.evidence_type,
        'locator', e.locator,
        'contentHash', e.content_hash,
        'observedAt', to_char(e.observed_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'metadata', e.metadata
      ) order by e.student_evidence_id)
      from public.student_evidence_items e
      where e.profile_version_id = v_eval.profile_version_id
        and e.student_evidence_id in (
          select d.student_evidence_id
          from public.student_degrees d
          join public.eligibility_snapshot_degrees sd on sd.student_degree_id = d.student_degree_id
          join public.eligibility_snapshot_scopes s on s.scope_id = sd.scope_id
          where s.evaluation_id = p_evaluation_id
          union
          select c.student_evidence_id
          from public.student_courses c
          join public.eligibility_snapshot_courses sc on sc.student_course_id = c.student_course_id
          join public.eligibility_snapshot_scopes s on s.scope_id = sc.scope_id
          where s.evaluation_id = p_evaluation_id
          union
          select t.student_evidence_id
          from public.student_test_scores t
          join public.eligibility_snapshot_test_scores st on st.student_test_score_id = t.student_test_score_id
          join public.eligibility_snapshot_scopes s on s.scope_id = st.scope_id
          where s.evaluation_id = p_evaluation_id
          union
          select p.student_evidence_id
          from public.eligibility_student_mapping_pins p
          where p.evaluation_id = p_evaluation_id
            and p.student_evidence_id is not null
        )
    ), '[]'::jsonb),
    'degreeFacts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'studentDegreeId', d.student_degree_id,
        'institutionName', d.institution_name,
        'degreeName', d.degree_name,
        'degreeLevel', d.degree_level,
        'degreeStatus', d.degree_status,
        'startDate', to_char(d.start_date, 'YYYY-MM-DD'),
        'completionDate', to_char(d.completion_date, 'YYYY-MM-DD'),
        'countryCode', d.country_code,
        'gpaValue', d.gpa_value,
        'gpaScale', d.gpa_scale,
        'studentEvidenceId', d.student_evidence_id
      ) order by d.student_degree_id)
      from public.student_degrees d
      join public.eligibility_snapshot_degrees sd on sd.student_degree_id = d.student_degree_id
      join public.eligibility_snapshot_scopes s on s.scope_id = sd.scope_id
      where s.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'courseFacts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'studentCourseId', c.student_course_id,
        'studentDegreeId', c.student_degree_id,
        'courseCode', c.course_code,
        'courseTitle', c.course_title,
        'courseStatus', c.course_status,
        'term', c.term,
        'completionDate', to_char(c.completion_date, 'YYYY-MM-DD'),
        'credits', c.credits,
        'gradeValue', c.grade_value,
        'gradeScale', c.grade_scale,
        'gradeText', c.grade_text,
        'studentEvidenceId', c.student_evidence_id
      ) order by c.student_course_id)
      from public.student_courses c
      join public.eligibility_snapshot_courses sc on sc.student_course_id = c.student_course_id
      join public.eligibility_snapshot_scopes s on s.scope_id = sc.scope_id
      where s.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'testFacts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'studentTestScoreId', t.student_test_score_id,
        'assessmentConceptId', t.assessment_concept_id,
        'testDate', to_char(t.test_date, 'YYYY-MM-DD'),
        'totalScore', t.total_score,
        'sectionScores', t.section_scores,
        'studentEvidenceId', t.student_evidence_id
      ) order by t.student_test_score_id)
      from public.student_test_scores t
      join public.eligibility_snapshot_test_scores st on st.student_test_score_id = t.student_test_score_id
      join public.eligibility_snapshot_scopes s on s.scope_id = st.scope_id
      where s.evaluation_id = p_evaluation_id
    ), '[]'::jsonb)
  );
  return encode(extensions.digest(convert_to(private.canonical_json_v02(v_obj), 'UTF8'), 'sha256'), 'hex');
end;
$$;

drop function if exists private.eligibility_v02_assert_closed_world(uuid);

create or replace function private.eligibility_v02_assert_closed_world(
  p_evaluation_id uuid,
  p_require_live_mapping_universe boolean default true
)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_eval public.eligibility_evaluations%rowtype;
  v_profile uuid;
  v_has_degree boolean;
begin
  select * into v_eval from public.eligibility_evaluations where evaluation_id = p_evaluation_id;
  v_profile := v_eval.profile_version_id;
  v_has_degree := exists (
    select 1
    from public.eligibility_snapshot_degrees d
    join public.eligibility_snapshot_scopes s using (scope_id)
    where s.evaluation_id = p_evaluation_id
      and s.scope_kind = 'GLOBAL_PROFILE'
      and s.domain = 'EDUCATION_HISTORY'
  );

  if exists (
    (select student_degree_id from public.student_degrees where profile_version_id = v_profile
     except
     select d.student_degree_id
     from public.eligibility_snapshot_degrees d
     join public.eligibility_snapshot_scopes s using (scope_id)
     where s.evaluation_id = p_evaluation_id
       and s.scope_kind = 'GLOBAL_PROFILE' and s.domain = 'EDUCATION_HISTORY')
    union all
    (select d.student_degree_id
     from public.eligibility_snapshot_degrees d
     join public.eligibility_snapshot_scopes s using (scope_id)
     where s.evaluation_id = p_evaluation_id
       and s.scope_kind = 'GLOBAL_PROFILE' and s.domain = 'EDUCATION_HISTORY'
     except
     select student_degree_id from public.student_degrees where profile_version_id = v_profile)
  ) then
    raise exception using errcode = '55000',
      message = 'Degree snapshot is not closed-world equal to the frozen profile',
      hint = 'eligibility_degree_universe_mismatch';
  end if;

  if exists (
    (select student_course_id from public.student_courses where profile_version_id = v_profile
     except
     select c.student_course_id
     from public.eligibility_snapshot_courses c
     join public.eligibility_snapshot_scopes s using (scope_id)
     where s.evaluation_id = p_evaluation_id and s.domain = 'COURSE_HISTORY')
    union all
    (select c.student_course_id
     from public.eligibility_snapshot_courses c
     join public.eligibility_snapshot_scopes s using (scope_id)
     where s.evaluation_id = p_evaluation_id and s.domain = 'COURSE_HISTORY'
     except
     select student_course_id from public.student_courses where profile_version_id = v_profile)
  ) then
    raise exception using errcode = '55000',
      message = 'Course snapshot is not closed-world equal to the frozen profile',
      hint = 'eligibility_course_universe_mismatch';
  end if;

  if exists (
    (select student_test_score_id from public.student_test_scores where profile_version_id = v_profile
     except
     select t.student_test_score_id
     from public.eligibility_snapshot_test_scores t
     join public.eligibility_snapshot_scopes s using (scope_id)
     where s.evaluation_id = p_evaluation_id
       and s.scope_kind = 'GLOBAL_PROFILE' and s.domain = 'TEST_HISTORY')
    union all
    (select t.student_test_score_id
     from public.eligibility_snapshot_test_scores t
     join public.eligibility_snapshot_scopes s using (scope_id)
     where s.evaluation_id = p_evaluation_id
       and s.scope_kind = 'GLOBAL_PROFILE' and s.domain = 'TEST_HISTORY'
     except
     select student_test_score_id from public.student_test_scores where profile_version_id = v_profile)
  ) then
    raise exception using errcode = '55000',
      message = 'Test snapshot is not closed-world equal to the frozen profile',
      hint = 'eligibility_test_universe_mismatch';
  end if;

  if not exists (
    select 1 from public.eligibility_snapshot_scopes
    where evaluation_id = p_evaluation_id
      and scope_kind = 'UNASSIGNED_CONTEXT' and domain = 'COURSE_HISTORY'
  ) or not exists (
    select 1 from public.eligibility_snapshot_scopes
    where evaluation_id = p_evaluation_id
      and scope_kind = 'UNASSIGNED_CONTEXT' and domain = 'COURSE_MAPPING'
  ) then
    raise exception using errcode = '55000',
      message = 'UNASSIGNED_CONTEXT snapshot scopes are required',
      hint = 'eligibility_course_universe_mismatch';
  end if;

  if exists (
    select 1 from public.eligibility_snapshot_scopes s
    where s.evaluation_id = p_evaluation_id
      and s.scope_kind = 'UNASSIGNED_CONTEXT'
      and v_has_degree
      and (s.completeness_id is not null or s.completeness is not null)
  ) then
    raise exception using errcode = '55000',
      message = 'UNASSIGNED_CONTEXT completeness is not a 012 identity when degrees exist',
      hint = 'eligibility_unassigned_completeness_fabricated';
  end if;

  if exists (
    select 1
    from public.student_courses c
    join public.eligibility_snapshot_courses sc on sc.student_course_id = c.student_course_id
    join public.eligibility_snapshot_scopes s on s.scope_id = sc.scope_id
    where c.profile_version_id = v_profile
      and s.evaluation_id = p_evaluation_id
      and s.domain = 'COURSE_HISTORY'
      and (
        (c.student_degree_id is null and s.scope_kind is distinct from 'UNASSIGNED_CONTEXT')
        or (c.student_degree_id is not null and (
              s.scope_kind is distinct from 'EDUCATION_CONTEXT'
              or s.education_context_id is distinct from c.student_degree_id
            ))
      )
  ) then
    raise exception using errcode = '55000',
      message = 'Course snapshot partition does not match education context',
      hint = 'eligibility_snapshot_scope_shape';
  end if;

  if exists (
    (
      select student_course_id from public.eligibility_manifest_courses
      where evaluation_id = p_evaluation_id
      except
      select c.student_course_id
      from public.eligibility_snapshot_courses c
      join public.eligibility_snapshot_scopes s using (scope_id)
      where s.evaluation_id = p_evaluation_id and s.domain = 'COURSE_HISTORY'
    )
    union all
    (
      select c.student_course_id
      from public.eligibility_snapshot_courses c
      join public.eligibility_snapshot_scopes s using (scope_id)
      where s.evaluation_id = p_evaluation_id and s.domain = 'COURSE_HISTORY'
      except
      select student_course_id from public.eligibility_manifest_courses
      where evaluation_id = p_evaluation_id
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Course snapshot is not closed-world equal to the identity manifest',
      hint = 'eligibility_course_universe_mismatch';
  end if;

  if p_require_live_mapping_universe and exists (
    (
      select student_mapping_id
      from private.eligibility_v02_required_student_mappings(p_evaluation_id)
      except
      select student_mapping_id
      from public.eligibility_student_mapping_pins
      where evaluation_id = p_evaluation_id
    )
    union all
    (
      select student_mapping_id
      from public.eligibility_student_mapping_pins
      where evaluation_id = p_evaluation_id
      except
      select student_mapping_id
      from private.eligibility_v02_required_student_mappings(p_evaluation_id)
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Student mapping pins are not the required decision universe',
      hint = 'eligibility_authoritative_universe_mismatch';
  end if;

  if p_require_live_mapping_universe and exists (
    (
      select n.rule_node_id, n.parent_node_id, n.sort_order, n.node_kind,
             n.group_operator, n.minimum_children, n.predicate_kind,
             n.requirement_strength, n.requirement_semantics, n.target_concept_id,
             n.explanation_template
      from public.program_requirement_nodes n
      where n.rule_set_id = v_eval.rule_set_id
      except
      select p.rule_node_id, p.parent_node_id, p.sort_order, p.node_kind,
             p.group_operator, p.minimum_children, p.predicate_kind,
             p.requirement_strength, p.requirement_semantics, p.target_concept_id,
             p.explanation_template
      from public.eligibility_rule_node_pins p
      where p.evaluation_id = p_evaluation_id
    )
    union all
    (
      select p.rule_node_id, p.parent_node_id, p.sort_order, p.node_kind,
             p.group_operator, p.minimum_children, p.predicate_kind,
             p.requirement_strength, p.requirement_semantics, p.target_concept_id,
             p.explanation_template
      from public.eligibility_rule_node_pins p
      where p.evaluation_id = p_evaluation_id
      except
      select n.rule_node_id, n.parent_node_id, n.sort_order, n.node_kind,
             n.group_operator, n.minimum_children, n.predicate_kind,
             n.requirement_strength, n.requirement_semantics, n.target_concept_id,
             n.explanation_template
      from public.program_requirement_nodes n
      where n.rule_set_id = v_eval.rule_set_id
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Rule-node pins are not closed-world equal to the rule set',
      hint = 'eligibility_rule_node_universe_mismatch';
  end if;

  if (select count(*) from public.eligibility_rule_set_pins
       where evaluation_id = p_evaluation_id) <> 1
     or exists (
       select 1 from public.eligibility_rule_set_pins p
       where p.evaluation_id = p_evaluation_id
         and (p.rule_set_id is distinct from v_eval.rule_set_id
              or p.taxonomy_release_code is distinct from v_eval.taxonomy_release_code
              or p.taxonomy_release_ordinal is distinct from v_eval.taxonomy_release_ordinal
              or p.engine_contract_version is distinct from 'eligibility-v0.2'
              or p.rule_schema_version is distinct from 'phase2-v0.2')
     ) then
    raise exception using errcode = '55000',
      message = 'Exactly one matching rule-set pin is required',
      hint = 'eligibility_rule_node_universe_mismatch';
  end if;

  if p_require_live_mapping_universe and exists (
    (
      select ns.rule_node_id, ns.field_observation_id
      from public.program_requirement_node_sources ns
      join public.program_requirement_nodes n using (rule_node_id)
      where n.rule_set_id = v_eval.rule_set_id
      except
      select p.rule_node_id, p.field_observation_id
      from public.eligibility_rule_node_source_pins p
      where p.evaluation_id = p_evaluation_id
    )
    union all
    (
      select p.rule_node_id, p.field_observation_id
      from public.eligibility_rule_node_source_pins p
      where p.evaluation_id = p_evaluation_id
      except
      select ns.rule_node_id, ns.field_observation_id
      from public.program_requirement_node_sources ns
      join public.program_requirement_nodes n using (rule_node_id)
      where n.rule_set_id = v_eval.rule_set_id
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Rule-node source pins are not closed-world equal to the rule set',
      hint = 'eligibility_rule_node_source_universe_mismatch';
  end if;

  if p_require_live_mapping_universe and exists (
    (
      select nm.rule_node_id, nm.catalog_mapping_id
      from public.program_requirement_node_mappings nm
      join public.program_requirement_nodes n using (rule_node_id)
      join public.catalog_concept_mappings m on m.mapping_id = nm.catalog_mapping_id
      where n.rule_set_id = v_eval.rule_set_id
        and m.mapping_status in ('VERIFIED', 'PROPOSED')
      except
      select p.rule_node_id, p.catalog_mapping_id
      from public.eligibility_rule_node_mapping_pins p
      where p.evaluation_id = p_evaluation_id
    )
    union all
    (
      select p.rule_node_id, p.catalog_mapping_id
      from public.eligibility_rule_node_mapping_pins p
      where p.evaluation_id = p_evaluation_id
      except
      select nm.rule_node_id, nm.catalog_mapping_id
      from public.program_requirement_node_mappings nm
      join public.program_requirement_nodes n using (rule_node_id)
      join public.catalog_concept_mappings m on m.mapping_id = nm.catalog_mapping_id
      where n.rule_set_id = v_eval.rule_set_id
        and m.mapping_status in ('VERIFIED', 'PROPOSED')
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Rule-node catalog-mapping pins are not closed-world equal to the rule set',
      hint = 'eligibility_rule_node_mapping_universe_mismatch';
  end if;

  if exists (
    select 1 from public.eligibility_rule_node_mapping_pins nm
    where nm.evaluation_id = p_evaluation_id
      and not exists (
        select 1 from public.eligibility_catalog_mapping_pins cp
         where cp.evaluation_id = nm.evaluation_id
           and cp.catalog_mapping_id = nm.catalog_mapping_id
      )
  ) then
    raise exception using errcode = '55000',
      message = 'Rule-node catalog-mapping pins require catalog mapping pins',
      hint = 'eligibility_rule_node_mapping_universe_mismatch';
  end if;

  if p_require_live_mapping_universe and exists (
    (
      select t.group_node_id, t.projection_kind, t.projected_minimum_children,
             t.projected_descendant_count
      from public.requirement_group_projection_thresholds t
      where t.rule_set_id = v_eval.rule_set_id
      except
      select p.group_node_id, p.projection_kind, p.projected_minimum_children,
             p.projected_descendant_count
      from public.eligibility_projection_threshold_pins p
      where p.evaluation_id = p_evaluation_id
    )
    union all
    (
      select p.group_node_id, p.projection_kind, p.projected_minimum_children,
             p.projected_descendant_count
      from public.eligibility_projection_threshold_pins p
      where p.evaluation_id = p_evaluation_id
      except
      select t.group_node_id, t.projection_kind, t.projected_minimum_children,
             t.projected_descendant_count
      from public.requirement_group_projection_thresholds t
      where t.rule_set_id = v_eval.rule_set_id
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Projection threshold pins are not closed-world equal to the verified source',
      hint = 'eligibility_missing_projected_threshold';
  end if;

  if exists (
    (
      select x.concept_id
      from (
        select n.target_concept_id as concept_id
        from public.eligibility_rule_node_pins n
        where n.evaluation_id = p_evaluation_id and n.target_concept_id is not null
        union
        select p.concept_id from public.eligibility_student_mapping_pins p
        where p.evaluation_id = p_evaluation_id
        union
        select c.concept_id from public.eligibility_catalog_mapping_pins c
        where c.evaluation_id = p_evaluation_id
      ) x
      except
      select tp.concept_id
      from public.eligibility_taxonomy_concept_pins tp
      where tp.evaluation_id = p_evaluation_id
    )
    union all
    (
      select tp.concept_id
      from public.eligibility_taxonomy_concept_pins tp
      where tp.evaluation_id = p_evaluation_id
      except
      select x.concept_id
      from (
        select n.target_concept_id as concept_id
        from public.eligibility_rule_node_pins n
        where n.evaluation_id = p_evaluation_id and n.target_concept_id is not null
        union
        select p.concept_id from public.eligibility_student_mapping_pins p
        where p.evaluation_id = p_evaluation_id
        union
        select c.concept_id from public.eligibility_catalog_mapping_pins c
        where c.evaluation_id = p_evaluation_id
      ) x
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Taxonomy concept pins are not the required evaluation universe',
      hint = 'eligibility_taxonomy_concept_universe_mismatch';
  end if;

  if exists (
    select 1 from public.eligibility_taxonomy_concept_pins tp
    join public.eligibility_evaluations e on e.evaluation_id = tp.evaluation_id
    where tp.evaluation_id = p_evaluation_id
      and not private.eligibility_v02_active_at_ordinal(
            tp.introduced_release_ordinal, e.taxonomy_release_ordinal, tp.retired_release_ordinal)
  ) then
    raise exception using errcode = '55000',
      message = 'A pinned taxonomy concept is inactive at the pinned ordinal',
      hint = 'eligibility_taxonomy_concept_universe_mismatch';
  end if;

  if exists (
    (
      select p.student_mapping_id, p.status_at_pin
      from public.eligibility_student_mapping_pins p
      where p.evaluation_id = p_evaluation_id
      except
      select u.student_mapping_id,
             case u.universe_role
               when 'AUTHORITATIVE' then 'VERIFIED'::public.mapping_status
               else 'PROPOSED'::public.mapping_status
             end
      from public.eligibility_snapshot_mapping_universe u
      join public.eligibility_snapshot_scopes s using (scope_id)
      where s.evaluation_id = p_evaluation_id
    )
    union all
    (
      select u.student_mapping_id,
             case u.universe_role
               when 'AUTHORITATIVE' then 'VERIFIED'::public.mapping_status
               else 'PROPOSED'::public.mapping_status
             end
      from public.eligibility_snapshot_mapping_universe u
      join public.eligibility_snapshot_scopes s using (scope_id)
      where s.evaluation_id = p_evaluation_id
      except
      select p.student_mapping_id, p.status_at_pin
      from public.eligibility_student_mapping_pins p
      where p.evaluation_id = p_evaluation_id
    )
  ) then
    raise exception using errcode = '55000',
      message = 'Mapping universe rows do not equal mapping pins',
      hint = 'eligibility_authoritative_universe_mismatch';
  end if;
end;
$$;

create or replace function private.eligibility_v02_required_student_mappings(p_evaluation_id uuid)
returns table(student_mapping_id uuid)
language sql
stable
set search_path = pg_catalog, public, private, extensions
as $$
  with eval as (
    select profile_version_id
    from public.eligibility_evaluations
    where evaluation_id = p_evaluation_id
  ),
  scoped_courses as (
    select c.student_course_id
    from public.eligibility_snapshot_courses c
    join public.eligibility_snapshot_scopes s using (scope_id)
    where s.evaluation_id = p_evaluation_id and s.domain = 'COURSE_HISTORY'
  ),
  targets as (
    select distinct n.target_concept_id as concept_id
    from public.eligibility_rule_node_pins n
    where n.evaluation_id = p_evaluation_id
      and n.predicate_kind = 'HAS_COURSE_CONCEPT'
      and n.target_concept_id is not null
  )
  select m.student_mapping_id
  from public.student_record_concept_mappings m
  join eval e on e.profile_version_id = m.profile_version_id
  where m.mapping_status = 'VERIFIED'
    and m.record_type = 'COURSE'
    and m.student_record_id in (select student_course_id from scoped_courses)
  union
  select m.student_mapping_id
  from public.student_record_concept_mappings m
  join eval e on e.profile_version_id = m.profile_version_id
  where m.mapping_status = 'PROPOSED'
    and m.record_type = 'COURSE'
    and m.concept_id in (select concept_id from targets)
    and m.student_record_id in (select student_course_id from scoped_courses);
$$;

create or replace function public.seal_eligibility_evaluation_inputs_v02(p_evaluation_id uuid)
returns text
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_student uuid;
  v_hash text;
begin
  v_student := private.eligibility_v02_require_building_unsealed(p_evaluation_id);
  perform private.eligibility_v02_assert_closed_world(p_evaluation_id);
  v_hash := private.canonical_eligibility_v02_input_fingerprint(p_evaluation_id);
  update public.eligibility_evaluations
  set inputs_sealed_at = now(), input_fingerprint = v_hash
  where evaluation_id = p_evaluation_id
    and evaluation_state = 'BUILDING'
    and inputs_sealed_at is null;
  if not found then
    raise exception using errcode = '55000',
      message = 'A BUILDING unsealed eligibility evaluation is required';
  end if;
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_evaluations', p_evaluation_id, 'SEAL_V02');
  return v_hash;
end;
$$;


create or replace function private.eligibility_v02_leaf_decision(
  p_evaluation_id uuid,
  p_node public.eligibility_rule_node_pins,
  out actual public.requirement_truth_value,
  out reason text,
  out missing_code public.eligibility_v02_missing_data_code
)
language plpgsql
stable
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_ks public.knowledge_status;
  v_has_auth boolean := false;
  v_has_limit boolean := false;
  v_has_degree boolean;
  v_unassigned_complete boolean := false;
  v_contexts_complete boolean := true;
  v_catalog_ok boolean := false;
  v_profile uuid;
  v_test_hit boolean := false;
  v_active boolean := true;
begin
  if not exists (
       select 1 from public.eligibility_rule_node_source_pins
        where evaluation_id = p_evaluation_id and rule_node_id = p_node.rule_node_id
     )
     or exists (
       select 1 from public.eligibility_rule_node_source_pins
        where evaluation_id = p_evaluation_id
          and rule_node_id = p_node.rule_node_id
          and knowledge_status_at_pin is distinct from 'KNOWN'
     ) then
    actual := 'UNKNOWN';
    reason := 'PROGRAM_FACT_UNKNOWN';
    missing_code := 'PROGRAM_FACT_NOT_KNOWN';
    return;
  end if;

  select e.profile_version_id into v_profile
  from public.eligibility_evaluations e where e.evaluation_id = p_evaluation_id;
  v_has_degree := exists (
    select 1
    from public.eligibility_snapshot_degrees d
    join public.eligibility_snapshot_scopes s using (scope_id)
    where s.evaluation_id = p_evaluation_id
      and s.scope_kind = 'GLOBAL_PROFILE'
      and s.domain = 'EDUCATION_HISTORY'
  );
  if p_node.target_concept_id is not null then
    select private.eligibility_v02_active_at_ordinal(
             tp.introduced_release_ordinal, e.taxonomy_release_ordinal, tp.retired_release_ordinal
           )
      into v_active
    from public.eligibility_evaluations e
    join public.eligibility_taxonomy_concept_pins tp
      on tp.evaluation_id = e.evaluation_id and tp.concept_id = p_node.target_concept_id
    where e.evaluation_id = p_evaluation_id;
    if not found then
      raise exception using errcode = '55000',
        message = 'Target concept is not pinned',
        hint = 'eligibility_taxonomy_concept_universe_mismatch';
    end if;
    if not v_active then
      actual := 'UNKNOWN';
      reason := 'TAXONOMY_CONCEPT_INACTIVE_AT_PIN';
      missing_code := 'TAXONOMY_CONCEPT_INACTIVE_AT_PIN';
      return;
    end if;
  end if;

  if p_node.predicate_kind = 'HAS_TEST' then
    select exists (
      select 1
      from public.eligibility_snapshot_test_scores t
      join public.eligibility_snapshot_scopes s using (scope_id)
      join public.student_test_scores ts on ts.student_test_score_id = t.student_test_score_id
      where s.evaluation_id = p_evaluation_id
        and ts.assessment_concept_id = p_node.target_concept_id
    ) into v_test_hit;
    if v_test_hit then
      actual := 'SATISFIED';
      reason := 'VERIFIED_TEST_PRESENT';
      return;
    end if;
    if exists (
      select 1 from public.eligibility_snapshot_scopes s
      where s.evaluation_id = p_evaluation_id
        and s.scope_kind = 'GLOBAL_PROFILE' and s.domain = 'TEST_HISTORY'
        and s.completeness = 'COMPLETE'
    ) then
      actual := 'NOT_SATISFIED';
      reason := 'REQUIRED_TEST_ABSENT';
      return;
    end if;
    actual := 'UNKNOWN';
    reason := 'TEST_HISTORY_INCOMPLETE';
    missing_code := 'INCOMPLETE_TEST_HISTORY';
    return;
  end if;

  select exists (
    select 1
    from public.eligibility_rule_node_mapping_pins nm
    join public.eligibility_catalog_mapping_pins cp
      on cp.evaluation_id = nm.evaluation_id
     and cp.catalog_mapping_id = nm.catalog_mapping_id
    where nm.evaluation_id = p_evaluation_id
      and nm.rule_node_id = p_node.rule_node_id
      and cp.status_at_pin = 'VERIFIED'
      and cp.relation_at_pin = 'COURSE_EQUIVALENCY'
      and cp.concept_id = p_node.target_concept_id
  ) into v_catalog_ok;

  select exists (
    select 1
    from public.eligibility_snapshot_mapping_universe u
    join public.eligibility_snapshot_scopes s using (scope_id)
    join public.eligibility_student_mapping_pins p
      on p.evaluation_id = s.evaluation_id and p.student_mapping_id = u.student_mapping_id
    join public.student_courses c on c.student_course_id = p.student_record_id
    join public.eligibility_snapshot_courses sc
      on sc.student_course_id = c.student_course_id
    join public.eligibility_snapshot_scopes cs
      on cs.scope_id = sc.scope_id
     and cs.evaluation_id = p_evaluation_id
     and cs.domain = 'COURSE_HISTORY'
    where s.evaluation_id = p_evaluation_id
      and u.universe_role = 'AUTHORITATIVE'
      and p.status_at_pin = 'VERIFIED'
      and p.concept_id = p_node.target_concept_id
      and c.course_status = 'COMPLETED'
      and v_catalog_ok
  ) into v_has_auth;
  if v_has_auth then
    actual := 'SATISFIED';
    reason := 'VERIFIED_COURSE_MATCH';
    return;
  end if;

  select exists (
    select 1
    from public.eligibility_snapshot_mapping_universe u
    join public.eligibility_snapshot_scopes s using (scope_id)
    join public.eligibility_student_mapping_pins p
      on p.evaluation_id = s.evaluation_id and p.student_mapping_id = u.student_mapping_id
    where s.evaluation_id = p_evaluation_id
      and u.universe_role = 'LIMITING'
      and p.status_at_pin = 'PROPOSED'
      and p.concept_id = p_node.target_concept_id
  ) into v_has_limit;
  if v_has_limit then
    actual := 'UNKNOWN';
    reason := 'PROPOSED_MAPPING_LIMITING';
    missing_code := 'PROPOSED_MAPPING_LIMITING';
    return;
  end if;

  select not exists (
    select 1 from public.eligibility_snapshot_scopes s
    where s.evaluation_id = p_evaluation_id
      and s.scope_kind = 'EDUCATION_CONTEXT'
      and s.domain in ('COURSE_HISTORY', 'COURSE_MAPPING')
      and s.completeness is distinct from 'COMPLETE'
  ) into v_contexts_complete;

  if not v_has_degree then
    select exists (
      select 1 from public.eligibility_snapshot_scopes s
      where s.evaluation_id = p_evaluation_id
        and s.scope_kind = 'UNASSIGNED_CONTEXT'
        and s.domain = 'COURSE_HISTORY' and s.completeness = 'COMPLETE'
    ) and exists (
      select 1 from public.eligibility_snapshot_scopes s
      where s.evaluation_id = p_evaluation_id
        and s.scope_kind = 'UNASSIGNED_CONTEXT'
        and s.domain = 'COURSE_MAPPING' and s.completeness = 'COMPLETE'
    ) into v_unassigned_complete;
  else
    v_unassigned_complete := false;
  end if;

  if v_catalog_ok and v_contexts_complete and v_unassigned_complete then
    actual := 'NOT_SATISFIED';
    reason := 'REQUIRED_COURSE_ABSENT';
    return;
  end if;
  if v_has_degree then
    actual := 'UNKNOWN';
    reason := 'UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE';
    missing_code := 'UNASSIGNED_CONTEXT_COMPLETENESS_UNAVAILABLE';
    return;
  end if;
  actual := 'UNKNOWN';
  reason := 'COURSE_HISTORY_INCOMPLETE';
  missing_code := 'INCOMPLETE_COURSE_OR_MAPPING_COVERAGE';
end;
$$;

create or replace function private.eligibility_v02_leaf_actual(
  p_evaluation_id uuid,
  p_node public.eligibility_rule_node_pins
) returns public.requirement_truth_value
language sql
stable
set search_path = pg_catalog, public, private, extensions
as $$
  select actual from private.eligibility_v02_leaf_decision(p_evaluation_id, p_node);
$$;

create or replace function private.eligibility_v02_assert_completed_tree(
  p_evaluation_id uuid,
  p_outcome public.eligibility_outcome,
  p_root_full public.requirement_truth_value
)
returns void
language plpgsql
volatile
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_root_count integer;
  v_node_count integer;
  v_full_count integer;
  v_proj_count integer;
  v_ord public.eligibility_projection_value;
  v_cond public.eligibility_projection_value;
begin
  select count(*) into v_root_count
  from public.eligibility_rule_node_pins
  where evaluation_id = p_evaluation_id and parent_node_id is null;
  if v_root_count <> 1 then
    raise exception using errcode = '55000',
      message = 'v0.2 evaluation requires exactly one root',
      hint = 'eligibility_rule_node_universe_mismatch';
  end if;
  select count(*) into v_node_count
  from public.eligibility_rule_node_pins where evaluation_id = p_evaluation_id;
  select count(*) into v_full_count
  from public.eligibility_requirement_results where evaluation_id = p_evaluation_id;
  if v_full_count <> v_node_count then
    raise exception using errcode = '55000',
      message = 'Every pinned rule node requires exactly one FULL result',
      hint = 'eligibility_tree_postcondition';
  end if;
  select count(*) into v_proj_count
  from public.eligibility_requirement_projection_results
  where evaluation_id = p_evaluation_id;
  if v_proj_count <> v_node_count * 5 then
    raise exception using errcode = '55000',
      message = 'Every pinned rule node requires exactly five projection results',
      hint = 'eligibility_tree_postcondition';
  end if;
  if exists (
    select 1 from public.eligibility_requirement_projection_results pr
    where pr.evaluation_id = p_evaluation_id
      and not exists (
        select 1 from public.eligibility_rule_node_pins n
         where n.evaluation_id = pr.evaluation_id and n.rule_node_id = pr.rule_node_id
      )
  ) then
    raise exception using errcode = '55000',
      message = 'Projection results exist for a foreign rule node',
      hint = 'eligibility_tree_postcondition';
  end if;
  if exists (
    select 1
    from public.eligibility_requirement_results r
    join public.eligibility_rule_node_pins n
      on n.evaluation_id = r.evaluation_id and n.rule_node_id = r.rule_node_id
    where r.evaluation_id = p_evaluation_id
      and r.truth_value = 'SATISFIED'
      and n.predicate_kind = 'HAS_COURSE_CONCEPT'
      and not exists (
        select 1 from public.eligibility_course_matches m
         where m.evaluation_id = r.evaluation_id
           and m.requirement_result_id = r.requirement_result_id
      )
  ) or exists (
    select 1
    from public.eligibility_requirement_results r
    join public.eligibility_rule_node_pins n
      on n.evaluation_id = r.evaluation_id and n.rule_node_id = r.rule_node_id
    where r.evaluation_id = p_evaluation_id
      and r.truth_value = 'SATISFIED'
      and n.predicate_kind = 'HAS_TEST'
      and not exists (
        select 1 from public.eligibility_test_matches m
         where m.evaluation_id = r.evaluation_id
           and m.requirement_result_id = r.requirement_result_id
      )
  ) then
    raise exception using errcode = '55000',
      message = 'SATISFIED leaf is missing an exact match',
      hint = 'eligibility_satisfied_without_match';
  end if;
  if exists (
    select 1
    from public.eligibility_requirement_results r
    join public.eligibility_rule_node_pins n
      on n.evaluation_id = r.evaluation_id and n.rule_node_id = r.rule_node_id
    where r.evaluation_id = p_evaluation_id
      and r.truth_value = 'NOT_SATISFIED'
      and n.node_kind = 'PREDICATE'
      and not exists (
        select 1 from public.eligibility_negative_fact_authorizations a
         where a.evaluation_id = r.evaluation_id and a.rule_node_id = r.rule_node_id
      )
  ) then
    raise exception using errcode = '55000',
      message = 'NOT_SATISFIED leaf is missing SQL-created negative proof',
      hint = 'eligibility_negative_authority_missing';
  end if;
  select pr.value into v_ord
  from public.eligibility_requirement_projection_results pr
  join public.eligibility_rule_node_pins n
    on n.evaluation_id = pr.evaluation_id and n.rule_node_id = pr.rule_node_id
  where pr.evaluation_id = p_evaluation_id and n.parent_node_id is null
    and pr.projection = 'ORDINARY_BARRIER';
  select pr.value into v_cond
  from public.eligibility_requirement_projection_results pr
  join public.eligibility_rule_node_pins n
    on n.evaluation_id = pr.evaluation_id and n.rule_node_id = pr.rule_node_id
  where pr.evaluation_id = p_evaluation_id and n.parent_node_id is null
    and pr.projection = 'CONDITIONAL_HARD';
  if private.eligibility_v02_derive_outcome(v_ord, v_cond) is distinct from p_outcome then
    raise exception using errcode = '55000',
      message = 'v0.2 outcome does not equal the ordinary × conditional table',
      hint = 'eligibility_projection_invalid_state';
  end if;
  if p_root_full is distinct from (
       select rr.truth_value
       from public.eligibility_requirement_results rr
       join public.eligibility_rule_node_pins n
         on n.evaluation_id = rr.evaluation_id and n.rule_node_id = rr.rule_node_id
       where rr.evaluation_id = p_evaluation_id and n.parent_node_id is null
     ) then
    raise exception using errcode = '55000',
      message = 'root_truth_value must equal the FULL root',
      hint = 'eligibility_tree_postcondition';
  end if;
end;
$$;

create or replace function public.finalize_eligibility_evaluation_v02(p_evaluation_id uuid)
returns text
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_student uuid;
  v_eval public.eligibility_evaluations%rowtype;
  r public.eligibility_rule_node_pins;
  v_actual public.requirement_truth_value;
  v_class public.eligibility_v02_leaf_class;
  v_proj public.eligibility_projection;
  v_val public.eligibility_projection_value;
  v_child public.eligibility_projection_value[];
  v_k integer;
  v_root_full public.requirement_truth_value;
  v_ord public.eligibility_projection_value;
  v_cond public.eligibility_projection_value;
  v_outcome public.eligibility_outcome;
  v_in_hash text;
  v_out_hash text;
  v_progress boolean;
  v_result_id uuid;
  v_missing jsonb;
  v_reasons text[];
  v_reason text;
  v_missing_code public.eligibility_v02_missing_data_code;
  v_has_degree boolean;
  v_cat uuid;
  v_stu uuid;
  v_course uuid;
  v_evidence uuid;
  v_test uuid;
begin
  select p.student_id into v_student
  from public.eligibility_evaluations e
  join public.student_profile_versions p using (profile_version_id)
  where e.evaluation_id = p_evaluation_id;
  perform private.lock_student_lifecycle(v_student);
  perform private.lock_student_owned_total_order(v_student);
  perform 1 from public.eligibility_snapshot_scopes
    where evaluation_id = p_evaluation_id order by scope_id for update;
  perform 1 from public.eligibility_student_mapping_pins
    where evaluation_id = p_evaluation_id order by student_mapping_id for update;
  perform 1 from public.eligibility_catalog_mapping_pins
    where evaluation_id = p_evaluation_id order by catalog_mapping_id for update;
  select * into v_eval from public.eligibility_evaluations
    where evaluation_id = p_evaluation_id for update;
  perform 1 from public.program_requirement_rule_sets
    where rule_set_id = v_eval.rule_set_id for update;
  perform 1 from public.taxonomy_releases
    where release_code = v_eval.taxonomy_release_code for update;
  perform 1 from public.catalog_concept_mappings m
    join public.eligibility_catalog_mapping_pins p on p.catalog_mapping_id = m.mapping_id
    where p.evaluation_id = p_evaluation_id
    order by m.mapping_id
    for key share;
  if v_eval.evaluation_state is distinct from 'BUILDING'
     or v_eval.inputs_sealed_at is null
     or v_eval.input_schema_version is distinct from 'eligibility-v0.2' then
    if v_eval.input_schema_version = 'eligibility-v0.1' then
      raise exception using errcode = '55000',
        message = 'v0.2 API cannot operate on a v0.1 evaluation',
        hint = 'eligibility_v02_api_on_v01_row';
    end if;
    raise exception using errcode = '55000',
      message = 'A sealed BUILDING eligibility-v0.2 evaluation is required';
  end if;
  perform private.eligibility_v02_assert_closed_world(p_evaluation_id, false);
  v_in_hash := private.canonical_eligibility_v02_input_fingerprint(p_evaluation_id);
  if v_in_hash is distinct from v_eval.input_fingerprint then
    raise exception using errcode = '55000',
      message = 'Sealed input fingerprint drifted',
      hint = 'eligibility_v02_input_fingerprint_drift';
  end if;

  insert into private.eligibility_v02_finalize_authorizations
    (transaction_id, evaluation_id, executor_role)
  values (txid_current(), p_evaluation_id, 'foundation_evaluation_executor');

  for r in
    select * from public.eligibility_rule_node_pins
    where evaluation_id = p_evaluation_id and node_kind = 'PREDICATE'
  loop
    select d.actual, d.reason, d.missing_code
      into v_actual, v_reason, v_missing_code
    from private.eligibility_v02_leaf_decision(p_evaluation_id, r) d;
    v_class := private.eligibility_v02_leaf_class(r.requirement_strength, r.requirement_semantics);
    v_reasons := array[v_reason];
    v_missing := case when v_missing_code is null then '[]'::jsonb
                      else jsonb_build_array(jsonb_build_object('code', v_missing_code)) end;
    insert into public.eligibility_requirement_results (
      evaluation_id, rule_node_id, truth_value, reason_codes, explanation, missing_data
    ) values (
      p_evaluation_id, r.rule_node_id, v_actual, v_reasons, r.explanation_template, v_missing
    ) returning requirement_result_id into v_result_id;
    foreach v_proj in array enum_range(null::public.eligibility_projection)
    loop
      insert into public.eligibility_requirement_projection_results
        (evaluation_id, rule_node_id, projection, value)
      values (
        p_evaluation_id, r.rule_node_id, v_proj,
        private.eligibility_v02_project_leaf(v_class, v_proj, v_actual)
      );
    end loop;
    if v_actual = 'SATISFIED' and r.predicate_kind = 'HAS_COURSE_CONCEPT' then
      for v_cat, v_stu, v_course, v_evidence in
        select nm.catalog_mapping_id, p.student_mapping_id, p.student_record_id, c.student_evidence_id
        from public.eligibility_rule_node_mapping_pins nm
        join public.eligibility_catalog_mapping_pins cp
          on cp.evaluation_id = nm.evaluation_id and cp.catalog_mapping_id = nm.catalog_mapping_id
        join public.eligibility_snapshot_mapping_universe u on true
        join public.eligibility_snapshot_scopes s on s.scope_id = u.scope_id
        join public.eligibility_student_mapping_pins p
          on p.evaluation_id = s.evaluation_id and p.student_mapping_id = u.student_mapping_id
        join public.student_courses c on c.student_course_id = p.student_record_id
        where nm.evaluation_id = p_evaluation_id
          and nm.rule_node_id = r.rule_node_id
          and s.evaluation_id = p_evaluation_id
          and cp.status_at_pin = 'VERIFIED'
          and cp.relation_at_pin = 'COURSE_EQUIVALENCY'
          and cp.concept_id = r.target_concept_id
          and u.universe_role = 'AUTHORITATIVE'
          and p.status_at_pin = 'VERIFIED'
          and p.concept_id = r.target_concept_id
          and c.course_status = 'COMPLETED'
        order by nm.catalog_mapping_id, p.student_mapping_id
      loop
        perform public.insert_eligibility_course_match(row(
          extensions.gen_random_uuid(), v_result_id, p_evaluation_id,
          v_cat, v_stu, v_course, v_evidence, now()
        )::public.eligibility_course_matches);
      end loop;
      if not exists (
        select 1 from public.eligibility_course_matches m
        where m.evaluation_id = p_evaluation_id and m.requirement_result_id = v_result_id
      ) then
        raise exception using errcode = '55000',
          message = 'SATISFIED HAS_COURSE_CONCEPT requires an exact course match',
          hint = 'eligibility_satisfied_without_match';
      end if;
    elsif v_actual = 'SATISFIED' and r.predicate_kind = 'HAS_TEST' then
      for v_test, v_evidence in
        select ts.student_test_score_id, ts.student_evidence_id
        from public.eligibility_snapshot_test_scores t
        join public.eligibility_snapshot_scopes s using (scope_id)
        join public.student_test_scores ts on ts.student_test_score_id = t.student_test_score_id
        where s.evaluation_id = p_evaluation_id
          and ts.assessment_concept_id = r.target_concept_id
        order by ts.student_test_score_id
      loop
        perform public.insert_eligibility_test_match(row(
          extensions.gen_random_uuid(), v_result_id, p_evaluation_id,
          v_test, v_evidence, now()
        )::public.eligibility_test_matches);
      end loop;
      if not exists (
        select 1 from public.eligibility_test_matches m
        where m.evaluation_id = p_evaluation_id and m.requirement_result_id = v_result_id
      ) then
        raise exception using errcode = '55000',
          message = 'SATISFIED HAS_TEST requires an exact test match',
          hint = 'eligibility_satisfied_without_match';
      end if;
    elsif v_actual = 'NOT_SATISFIED' then
      insert into public.eligibility_negative_fact_authorizations (
        evaluation_id, rule_node_id, domain
      ) values (
        p_evaluation_id, r.rule_node_id,
        case
          when r.predicate_kind = 'HAS_TEST'
            then 'TEST_HISTORY'::public.student_data_domain
          else
            'COURSE_HISTORY'::public.student_data_domain
        end
      );
      select exists (
        select 1
        from public.eligibility_snapshot_degrees d
        join public.eligibility_snapshot_scopes s using (scope_id)
        where s.evaluation_id = p_evaluation_id
          and s.scope_kind = 'GLOBAL_PROFILE'
          and s.domain = 'EDUCATION_HISTORY'
      )
        into v_has_degree;
      insert into public.eligibility_negative_authorization_scopes (
        evaluation_id, rule_node_id, scope_id
      )
      select p_evaluation_id, r.rule_node_id, s.scope_id
      from public.eligibility_snapshot_scopes s
      where s.evaluation_id = p_evaluation_id
        and (
          (r.predicate_kind = 'HAS_TEST'
           and s.scope_kind = 'GLOBAL_PROFILE' and s.domain = 'TEST_HISTORY')
          or (r.predicate_kind = 'HAS_COURSE_CONCEPT'
              and s.domain in ('COURSE_HISTORY', 'COURSE_MAPPING')
              and (
                s.scope_kind = 'EDUCATION_CONTEXT'
                or (s.scope_kind = 'UNASSIGNED_CONTEXT' and not v_has_degree)
              ))
        );
    end if;
  end loop;

  loop
    v_progress := false;
    for r in
      select n.*
      from public.eligibility_rule_node_pins n
      where n.evaluation_id = p_evaluation_id
        and n.node_kind = 'GROUP'
        and not exists (
          select 1 from public.eligibility_requirement_results x
          where x.evaluation_id = p_evaluation_id and x.rule_node_id = n.rule_node_id
        )
        and not exists (
          select 1 from public.eligibility_rule_node_pins c
          where c.evaluation_id = p_evaluation_id and c.parent_node_id = n.rule_node_id
            and not exists (
              select 1 from public.eligibility_requirement_results x
              where x.evaluation_id = p_evaluation_id and x.rule_node_id = c.rule_node_id
            )
        )
    loop
      v_progress := true;
      foreach v_proj in array enum_range(null::public.eligibility_projection)
      loop
        select coalesce(array_agg(pr.value order by c.sort_order), '{}')
          into v_child
        from public.eligibility_rule_node_pins c
        join public.eligibility_requirement_projection_results pr
          on pr.evaluation_id = c.evaluation_id
         and pr.rule_node_id = c.rule_node_id
         and pr.projection = v_proj
        where c.evaluation_id = p_evaluation_id and c.parent_node_id = r.rule_node_id;
        v_k := null;
        if r.group_operator = 'AT_LEAST'
           and exists (select 1 from unnest(v_child) v where v is distinct from 'ABSENT') then
          if v_proj = 'FULL' then
            v_k := r.minimum_children;
          else
            select projected_minimum_children into v_k
            from public.eligibility_projection_threshold_pins
            where evaluation_id = p_evaluation_id
              and group_node_id = r.rule_node_id
              and projection_kind = v_proj;
          end if;
          if v_k is null then
            raise exception using errcode = '55000',
              message = 'Projected AT_LEAST threshold is missing',
              hint = 'eligibility_missing_projected_threshold';
          end if;
        end if;
        v_val := private.eligibility_v02_aggregate(r.group_operator, v_child, v_k);
        insert into public.eligibility_requirement_projection_results
          (evaluation_id, rule_node_id, projection, value)
        values (p_evaluation_id, r.rule_node_id, v_proj, v_val);
        if v_proj = 'FULL' then
          if v_val = 'ABSENT' and r.parent_node_id is null then
            raise exception using errcode = '55000',
              message = 'FULL root cannot be ABSENT',
              hint = 'eligibility_full_root_absent';
          end if;
          insert into public.eligibility_requirement_results (
            evaluation_id, rule_node_id, truth_value, reason_codes, explanation, missing_data
          ) values (
            p_evaluation_id, r.rule_node_id,
            case when v_val = 'ABSENT' then 'UNKNOWN' else v_val::text::public.requirement_truth_value end,
            array[case when v_val = 'SATISFIED' then 'GROUP_SATISFIED'
                       when v_val = 'NOT_SATISFIED' then 'GROUP_NOT_SATISFIED'
                       else 'GROUP_UNKNOWN' end],
            r.explanation_template,
            case when v_val in ('UNKNOWN', 'ABSENT')
                 then jsonb_build_array(jsonb_build_object('code', 'INCOMPLETE_COURSE_OR_MAPPING_COVERAGE'))
                 else '[]'::jsonb end
          );
        end if;
      end loop;
    end loop;
    exit when not v_progress;
  end loop;

  select pr.value into v_ord
  from public.eligibility_requirement_projection_results pr
  join public.eligibility_rule_node_pins n
    on n.evaluation_id = pr.evaluation_id and n.rule_node_id = pr.rule_node_id
  where pr.evaluation_id = p_evaluation_id and n.parent_node_id is null
    and pr.projection = 'ORDINARY_BARRIER';
  select pr.value into v_cond
  from public.eligibility_requirement_projection_results pr
  join public.eligibility_rule_node_pins n
    on n.evaluation_id = pr.evaluation_id and n.rule_node_id = pr.rule_node_id
  where pr.evaluation_id = p_evaluation_id and n.parent_node_id is null
    and pr.projection = 'CONDITIONAL_HARD';
  v_outcome := private.eligibility_v02_derive_outcome(v_ord, v_cond);
  select truth_value into v_root_full
  from public.eligibility_requirement_results rr
  join public.eligibility_rule_node_pins n
    on n.evaluation_id = rr.evaluation_id and n.rule_node_id = rr.rule_node_id
  where rr.evaluation_id = p_evaluation_id and n.parent_node_id is null;

  v_in_hash := private.canonical_eligibility_v02_input_fingerprint(p_evaluation_id);
  if v_in_hash is distinct from v_eval.input_fingerprint then
    raise exception using errcode = '55000',
      message = 'Sealed input fingerprint drifted',
      hint = 'eligibility_v02_input_fingerprint_drift';
  end if;
  perform private.eligibility_v02_assert_completed_tree(p_evaluation_id, v_outcome, v_root_full);
  v_out_hash := private.canonical_eligibility_v02_result_fingerprint(p_evaluation_id, v_outcome);
  update public.eligibility_evaluations
  set evaluation_state = 'COMPLETED',
      outcome = v_outcome,
      root_truth_value = v_root_full,
      evaluated_at = now(),
      result_fingerprint = v_out_hash
  where evaluation_id = p_evaluation_id
    and evaluation_state = 'BUILDING';

  delete from private.eligibility_v02_finalize_authorizations
  where transaction_id = txid_current() and evaluation_id = p_evaluation_id;
  perform private.write_student_lifecycle_audit(v_student, 'eligibility_evaluations', p_evaluation_id, 'FINALIZE_V02');
  return v_out_hash;
end;
$$;


create or replace function private.canonical_eligibility_v02_result_fingerprint(
  p_evaluation_id uuid,
  p_outcome public.eligibility_outcome
) returns text
language plpgsql
stable
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_eval public.eligibility_evaluations%rowtype;
  v_obj jsonb;
  v_roots jsonb;
begin
  select * into v_eval from public.eligibility_evaluations where evaluation_id = p_evaluation_id;
  select jsonb_object_agg(projection::text, value::text) into v_roots
  from (
    select pr.projection, pr.value
    from public.eligibility_requirement_projection_results pr
    join public.eligibility_rule_node_pins n
      on n.evaluation_id = pr.evaluation_id and n.rule_node_id = pr.rule_node_id
    where pr.evaluation_id = p_evaluation_id and n.parent_node_id is null
  ) r;
  v_obj := jsonb_build_object(
    'contract', jsonb_build_object(
      'resultSemanticsVersion', v_eval.result_semantics_version,
      'canonicalizationVersion', v_eval.canonicalization_version
    ),
    'decisionInputFingerprint', v_eval.input_fingerprint,
    'roots', jsonb_build_object(
      'full', v_roots ->> 'FULL',
      'ordinaryBarrier', v_roots ->> 'ORDINARY_BARRIER',
      'conditionalHard', v_roots ->> 'CONDITIONAL_HARD',
      'conditionalOnly', v_roots ->> 'CONDITIONAL_ONLY',
      'softExplanation', v_roots ->> 'SOFT_EXPLANATION'
    ),
    'outcome', p_outcome,
    'nodeResults', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', rule_node_id,
        'truthValue', truth_value,
        'reasonCodes', coalesce((
          select jsonb_agg(code order by code)
          from unnest(reason_codes) code
        ), '[]'::jsonb),
        'explanation', explanation,
        'supportingFactRefs', coalesce((
          select jsonb_agg(ref order by ref->>'type', ref->>'id')
          from jsonb_array_elements(supporting_fact_refs) ref
        ), '[]'::jsonb),
        'missingData', coalesce((
          select jsonb_agg(md order by md->>'code', md->>'scopeKind' nulls first, md->>'field')
          from jsonb_array_elements(missing_data) md
        ), '[]'::jsonb),
        'decisive', decisive
      ) order by rule_node_id)
      from public.eligibility_requirement_results where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'projectionResults', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', rule_node_id, 'projection', projection, 'value', value
      ) order by rule_node_id, projection)
      from public.eligibility_requirement_projection_results where evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'courseMatches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', r.rule_node_id,
        'catalogMappingId', m.catalog_mapping_id,
        'studentMappingId', m.student_mapping_id,
        'studentCourseId', m.student_course_id,
        'studentEvidenceId', m.student_evidence_id
      ) order by r.rule_node_id, m.student_course_id, m.catalog_mapping_id, m.student_mapping_id)
      from public.eligibility_course_matches m
      join public.eligibility_requirement_results r
        on r.requirement_result_id = m.requirement_result_id
       and r.evaluation_id = m.evaluation_id
      where m.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'testMatches', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', r.rule_node_id,
        'studentTestScoreId', m.student_test_score_id,
        'studentEvidenceId', m.student_evidence_id
      ) order by r.rule_node_id, m.student_test_score_id)
      from public.eligibility_test_matches m
      join public.eligibility_requirement_results r
        on r.requirement_result_id = m.requirement_result_id
       and r.evaluation_id = m.evaluation_id
      where m.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'negativeAuthorizations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'ruleNodeId', a.rule_node_id,
        'domain', a.domain,
        'proofVersion', a.proof_version,
        'scopes', coalesce((
          select jsonb_agg(
                   jsonb_build_object(
                     'scopeKind', sc.scope_kind,
                     'educationContextId', sc.education_context_id,
                     'domain', sc.domain
                   )
                   order by sc.scope_kind, sc.education_context_id nulls first, sc.domain
                 )
          from public.eligibility_negative_authorization_scopes s
          join public.eligibility_snapshot_scopes sc on sc.scope_id = s.scope_id
          where s.evaluation_id = a.evaluation_id and s.rule_node_id = a.rule_node_id
        ), '[]'::jsonb)
      ) order by a.rule_node_id)
      from public.eligibility_negative_fact_authorizations a
      where a.evaluation_id = p_evaluation_id
    ), '[]'::jsonb)
  );
  return encode(extensions.digest(convert_to(private.canonical_json_v02(v_obj), 'UTF8'), 'sha256'), 'hex');
end;
$$;

create or replace function private.canonical_eligibility_v02_result_fingerprint(p_evaluation_id uuid)
returns text
language plpgsql
stable
set search_path = pg_catalog, public, private, extensions
as $$
declare v_outcome public.eligibility_outcome;
begin
  select outcome into v_outcome from public.eligibility_evaluations where evaluation_id = p_evaluation_id;
  return private.canonical_eligibility_v02_result_fingerprint(p_evaluation_id, v_outcome);
end;
$$;


create or replace function public.verify_program_requirement_rule_set(
  p_rule_set_id uuid,
  p_verified_by text,
  p_verification_evidence_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_rule_set public.program_requirement_rule_sets%rowtype;
  v_root_id uuid;
  v_total_nodes integer;
  v_reachable_nodes integer;
  v_invalid_groups integer;
  v_invalid_predicates integer;
  v_invalid_sources integer;
  v_invalid_mappings integer;
  v_pin bigint;
  v_group record;
  v_proj public.eligibility_projection;
  v_count integer;
  v_k integer;
begin
  select * into v_rule_set
  from public.program_requirement_rule_sets
  where rule_set_id = p_rule_set_id
  for update;
  if not found or v_rule_set.status <> 'DRAFT' then
    raise exception 'A draft rule set is required';
  end if;
  if nullif(btrim(p_verified_by), '') is null then
    raise exception 'Verifier identity is required';
  end if;
  if not exists (select 1 from public.evidence_items where evidence_id = p_verification_evidence_id) then
    raise exception 'Verification evidence does not exist';
  end if;
  select rule_node_id into v_root_id
  from public.program_requirement_nodes
  where rule_set_id = p_rule_set_id and parent_node_id is null;
  if v_root_id is null then
    raise exception 'Rule set requires exactly one root';
  end if;
  select count(*) into v_total_nodes from public.program_requirement_nodes where rule_set_id = p_rule_set_id;
  with recursive reachable(rule_node_id, path) as (
    select v_root_id, array[v_root_id]
    union all
    select n.rule_node_id, r.path || n.rule_node_id
    from reachable r
    join public.program_requirement_nodes n
      on n.parent_node_id = r.rule_node_id and n.rule_set_id = p_rule_set_id
    where not n.rule_node_id = any(r.path)
  )
  select count(distinct rule_node_id) into v_reachable_nodes from reachable;
  if v_reachable_nodes <> v_total_nodes then
    raise exception 'Rule tree contains a cycle or unreachable node';
  end if;
  select count(*) into v_invalid_groups
  from public.program_requirement_nodes n
  left join lateral (
    select count(*)::integer as child_count
    from public.program_requirement_nodes child
    where child.rule_set_id = n.rule_set_id and child.parent_node_id = n.rule_node_id
  ) c on true
  where n.rule_set_id = p_rule_set_id
    and n.node_kind = 'GROUP'
    and (c.child_count = 0 or (n.group_operator = 'AT_LEAST' and n.minimum_children > c.child_count));
  if v_invalid_groups > 0 then
    raise exception 'Every group needs children and valid AT_LEAST cardinality';
  end if;

  if v_rule_set.engine_contract_version = 'eligibility-v0.1' then
    if exists (
      select 1 from public.requirement_group_projection_thresholds t
      where t.rule_set_id = p_rule_set_id
    ) then
      raise exception using errcode = '55000',
        message = 'v0.1 rule sets cannot store projection thresholds';
    end if;
  end if;

  select count(*) into v_invalid_predicates
  from public.program_requirement_nodes n
  where n.rule_set_id = p_rule_set_id
    and n.node_kind = 'PREDICATE'
    and (
      exists (select 1 from public.program_requirement_nodes child where child.parent_node_id = n.rule_node_id)
      or (n.predicate_kind in ('HAS_COURSE_CONCEPT', 'HAS_TEST') and n.target_concept_id is null)
      or (n.requirement_strength = 'SOFT' and n.requirement_semantics = 'EXPLICIT_CONDITIONAL'
          and v_rule_set.engine_contract_version = 'eligibility-v0.2')
    );
  if v_invalid_predicates > 0 then
    raise exception using errcode = '55000',
      message = 'Predicate node shape is invalid',
      hint = 'eligibility_soft_conditional_forbidden';
  end if;

  select count(*) into v_invalid_sources
  from public.program_requirement_nodes n
  where n.rule_set_id = p_rule_set_id
    and n.node_kind = 'PREDICATE'
    and not exists (
      select 1
      from public.program_requirement_node_sources ns
      join public.field_observations o on o.observation_id = ns.field_observation_id
      join public.canonical_field_selections c
        on c.observation_id = o.observation_id
       and c.record_type = o.record_type and c.record_id = o.record_id and c.field_name = o.field_name
      where ns.rule_node_id = n.rule_node_id and o.knowledge_status = 'KNOWN'
        and public.catalog_record_program_version(o.record_type, o.record_id) = v_rule_set.program_version_id
    );
  if v_invalid_sources > 0 then
    raise exception 'Every predicate requires a currently selected KNOWN source observation for this program version';
  end if;

  select count(*) into v_invalid_mappings
  from public.program_requirement_nodes n
  where n.rule_set_id = p_rule_set_id
    and n.predicate_kind = 'HAS_COURSE_CONCEPT'
    and not exists (
      select 1
      from public.program_requirement_node_mappings nm
      join public.catalog_concept_mappings m on m.mapping_id = nm.catalog_mapping_id
      where nm.rule_node_id = n.rule_node_id
        and m.mapping_status = 'VERIFIED'
        and m.concept_id = n.target_concept_id
        and (v_rule_set.engine_contract_version is distinct from 'eligibility-v0.2'
             or m.relation = 'COURSE_EQUIVALENCY')
        and public.catalog_record_program_version(m.record_type, m.record_id) = v_rule_set.program_version_id
    );
  if v_invalid_mappings > 0 then
    raise exception 'Concept predicates require a reviewed catalog mapping for this program version';
  end if;

  if v_rule_set.engine_contract_version = 'eligibility-v0.2' then
    select release_ordinal into v_pin from public.taxonomy_releases
      where release_code = v_rule_set.taxonomy_release_code;
    if exists (
      select 1 from public.program_requirement_nodes n
      join public.taxonomy_concepts tc on tc.concept_id = n.target_concept_id
      where n.rule_set_id = p_rule_set_id
        and n.target_concept_id is not null
        and not (tc.introduced_release_ordinal <= v_pin
                 and (tc.retired_release_ordinal is null or v_pin < tc.retired_release_ordinal))
    ) then
      raise exception using errcode = '55000',
        message = 'Rule set references a concept inactive at the taxonomy release',
        hint = 'taxonomy_ordinal_range_invalid';
    end if;
    for v_group in
      select n.rule_node_id, n.minimum_children
      from public.program_requirement_nodes n
      where n.rule_set_id = p_rule_set_id
        and n.node_kind = 'GROUP' and n.group_operator = 'AT_LEAST'
    loop
      foreach v_proj in array enum_range(null::public.eligibility_projection)
      loop
        with recursive belong(rule_node_id) as (
          select ln.rule_node_id
          from public.program_requirement_nodes ln
          where ln.rule_set_id = p_rule_set_id
            and ln.node_kind = 'PREDICATE'
            and (
              (ln.requirement_strength = 'HARD' and ln.requirement_semantics = 'ORDINARY'
               and v_proj in ('FULL', 'ORDINARY_BARRIER', 'CONDITIONAL_HARD'))
              or (ln.requirement_strength = 'HARD' and ln.requirement_semantics = 'EXPLICIT_CONDITIONAL'
               and v_proj in ('FULL', 'ORDINARY_BARRIER', 'CONDITIONAL_HARD', 'CONDITIONAL_ONLY'))
              or (ln.requirement_strength = 'SOFT'
               and v_proj in ('FULL', 'SOFT_EXPLANATION'))
            )
          union
          select g.rule_node_id
          from public.program_requirement_nodes g
          join belong b on b.rule_node_id in (
            select c.rule_node_id from public.program_requirement_nodes c
            where c.parent_node_id = g.rule_node_id
          )
          where g.rule_set_id = p_rule_set_id and g.node_kind = 'GROUP'
        )
        select count(*) into v_count
        from public.program_requirement_nodes c
        where c.parent_node_id = v_group.rule_node_id
          and c.rule_node_id in (select rule_node_id from belong);
        if v_count = 0 then
          if exists (
            select 1 from public.requirement_group_projection_thresholds t
            where t.rule_set_id = p_rule_set_id
              and t.group_node_id = v_group.rule_node_id
              and t.projection_kind = v_proj
          ) then
            raise exception using errcode = '55000',
              message = 'Threshold row is forbidden when projected descendant count is 0';
          end if;
        elsif v_proj = 'FULL' then
          insert into public.requirement_group_projection_thresholds (
            rule_set_id, group_node_id, projection_kind,
            projected_minimum_children, projected_descendant_count,
            verification_evidence_id, verified_by, verified_at
          ) values (
            p_rule_set_id, v_group.rule_node_id, 'FULL',
            v_group.minimum_children, v_count,
            p_verification_evidence_id, p_verified_by, now()
          );
        else
          select projected_minimum_children into v_k
          from public.requirement_group_projection_thresholds t
          where t.rule_set_id = p_rule_set_id
            and t.group_node_id = v_group.rule_node_id
            and t.projection_kind = v_proj;
          if v_k is null or v_k > v_count then
            raise exception using errcode = '55000',
              message = 'Missing or invalid reviewer projection threshold',
              hint = 'eligibility_missing_projected_threshold';
          end if;
          update public.requirement_group_projection_thresholds
          set projected_descendant_count = v_count,
              verification_evidence_id = p_verification_evidence_id,
              verified_by = p_verified_by,
              verified_at = now()
          where rule_set_id = p_rule_set_id
            and group_node_id = v_group.rule_node_id
            and projection_kind = v_proj;
        end if;
      end loop;
    end loop;
  end if;

  update public.program_requirement_rule_sets
  set status = 'VERIFIED',
      verified_by = p_verified_by,
      verified_at = now(),
      verification_evidence_id = p_verification_evidence_id
  where rule_set_id = p_rule_set_id;
end;
$$;

create or replace function public.validate_eligibility_match_insert()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_schema text;
  v_predicate public.requirement_predicate_kind;
  v_target uuid;
  v_cat_status public.mapping_status;
  v_stu_status public.mapping_status;
  v_cat_concept uuid;
  v_stu_concept uuid;
  v_stu_record uuid;
  v_course_status public.course_status;
  v_test_concept uuid;
  v_pin_cat public.mapping_status;
  v_pin_stu public.mapping_status;
  v_rel_cat public.catalog_mapping_relation;
  v_rel_stu public.eligibility_student_mapping_relation;
begin
  select e.input_schema_version into v_schema
  from public.eligibility_evaluations e where e.evaluation_id = new.evaluation_id;
  if v_schema = 'eligibility-v0.2' then
    select n.predicate_kind, n.target_concept_id into v_predicate, v_target
    from public.eligibility_requirement_results r
    join public.eligibility_rule_node_pins n
      on n.evaluation_id = r.evaluation_id and n.rule_node_id = r.rule_node_id
    where r.requirement_result_id = new.requirement_result_id
      and r.evaluation_id = new.evaluation_id
      and r.truth_value = 'SATISFIED';
    if tg_table_name = 'eligibility_course_matches' then
      if v_predicate is distinct from 'HAS_COURSE_CONCEPT' then
        raise exception 'Course matches require a satisfied course predicate';
      end if;
      select status_at_pin, concept_id, relation_at_pin
        into v_pin_cat, v_cat_concept, v_rel_cat
      from public.eligibility_catalog_mapping_pins
      where evaluation_id = new.evaluation_id and catalog_mapping_id = new.catalog_mapping_id;
      select status_at_pin, concept_id, relation_at_pin, student_record_id
        into v_pin_stu, v_stu_concept, v_rel_stu, v_stu_record
      from public.eligibility_student_mapping_pins
      where evaluation_id = new.evaluation_id and student_mapping_id = new.student_mapping_id;
      select course_status into v_course_status
      from public.student_courses
      where student_course_id = new.student_course_id
        and student_evidence_id = new.student_evidence_id;
      if v_pin_cat is distinct from 'VERIFIED'
         or v_pin_stu is distinct from 'VERIFIED'
         or v_rel_cat is distinct from 'COURSE_EQUIVALENCY'
         or v_rel_stu is distinct from 'STUDENT_CONCEPT_ASSOCIATION'
         or v_cat_concept is distinct from v_target
         or v_stu_concept is distinct from v_target
         or v_stu_record is distinct from new.student_course_id
         or v_course_status is distinct from 'COMPLETED' then
        raise exception 'Course match is not an authoritative completed equivalency';
      end if;
    else
      if v_predicate is distinct from 'HAS_TEST' then
        raise exception 'Test matches require a satisfied test predicate';
      end if;
      select assessment_concept_id into v_test_concept
      from public.student_test_scores
      where student_test_score_id = new.student_test_score_id
        and student_evidence_id = new.student_evidence_id;
      if v_test_concept is distinct from v_target then
        raise exception 'Test match does not satisfy the predicate assessment';
      end if;
    end if;
    return new;
  end if;
  select n.predicate_kind, n.target_concept_id into v_predicate, v_target
  from public.eligibility_requirement_results r
  join public.program_requirement_nodes n using (rule_node_id)
  where r.requirement_result_id = new.requirement_result_id
    and r.evaluation_id = new.evaluation_id
    and r.truth_value = 'SATISFIED';
  if tg_table_name = 'eligibility_course_matches' then
    if v_predicate is distinct from 'HAS_COURSE_CONCEPT' then
      raise exception 'Course matches require a satisfied course predicate';
    end if;
    select concept_id, mapping_status into v_cat_concept, v_cat_status
    from public.catalog_concept_mappings where mapping_id = new.catalog_mapping_id;
    select concept_id, student_record_id, mapping_status
      into v_stu_concept, v_stu_record, v_stu_status
    from public.student_record_concept_mappings where student_mapping_id = new.student_mapping_id;
    select course_status into v_course_status
    from public.student_courses
    where student_course_id = new.student_course_id
      and student_evidence_id = new.student_evidence_id;
    if v_cat_concept is distinct from v_target
       or v_stu_concept is distinct from v_target
       or v_stu_record is distinct from new.student_course_id
       or v_cat_status is distinct from 'VERIFIED'
       or v_stu_status is distinct from 'VERIFIED'
       or v_course_status is distinct from 'COMPLETED' then
      raise exception 'Course match is not an authoritative completed equivalency';
    end if;
  else
    if v_predicate is distinct from 'HAS_TEST' then
      raise exception 'Test matches require a satisfied test predicate';
    end if;
    select assessment_concept_id into v_test_concept
    from public.student_test_scores
    where student_test_score_id = new.student_test_score_id
      and student_evidence_id = new.student_evidence_id;
    if v_test_concept is distinct from v_target then
      raise exception 'Test match does not satisfy the predicate assessment';
    end if;
  end if;
  return new;
end;
$$;


create or replace function public.guard_projection_threshold_immutable()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public
as $$
declare v_status public.rule_set_status;
begin
  select status into v_status from public.program_requirement_rule_sets
    where rule_set_id = coalesce(new.rule_set_id, old.rule_set_id);
  if tg_op = 'UPDATE' and v_status = 'DRAFT'
     and current_user = 'foundation_catalog_executor' then
    return new;
  end if;
  if v_status is distinct from 'DRAFT' then
    raise exception using errcode = '55000',
      message = 'Projection thresholds are immutable after verification';
  end if;
  return coalesce(new, old);
end;
$$;
create trigger requirement_group_projection_thresholds_immutable
before update or delete on public.requirement_group_projection_thresholds
for each row execute function public.guard_projection_threshold_immutable();

create or replace function public.guard_eligibility_v02_finalizer_only_row()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private
as $$
begin
  if not exists (
    select 1 from private.eligibility_v02_finalize_authorizations a
     where a.transaction_id = txid_current()
       and a.evaluation_id = new.evaluation_id
  ) then
    raise exception using errcode = '55000',
      message = 'v0.2 negative-authority and projection result rows are written only by finalize_eligibility_evaluation_v02',
      hint = 'eligibility_v02_negative_authority_caller_forbidden';
  end if;
  return new;
end;
$$;
create trigger eligibility_negative_fact_authorizations_finalizer_only
before insert on public.eligibility_negative_fact_authorizations
for each row execute function public.guard_eligibility_v02_finalizer_only_row();
create trigger eligibility_negative_authorization_scopes_finalizer_only
before insert on public.eligibility_negative_authorization_scopes
for each row execute function public.guard_eligibility_v02_finalizer_only_row();
create trigger eligibility_requirement_projection_results_finalizer_only
before insert on public.eligibility_requirement_projection_results
for each row execute function public.guard_eligibility_v02_finalizer_only_row();

create or replace function public.insert_eligibility_requirement_result(p_row public.eligibility_requirement_results)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_schema text;
begin
  select input_schema_version into v_schema
  from public.eligibility_evaluations where evaluation_id = p_row.evaluation_id;
  if v_schema = 'eligibility-v0.2' and not exists (
    select 1 from private.eligibility_v02_finalize_authorizations a
    where a.transaction_id = txid_current() and a.evaluation_id = p_row.evaluation_id
  ) then
    raise exception using errcode = '55000',
      message = 'v0.2 requirement results are written only by finalize_eligibility_evaluation_v02',
      hint = 'eligibility_v02_caller_outcome_forbidden';
  end if;
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_requirement_results');
  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_requirement_results'::regclass, to_jsonb(p_row));
end;
$$;

create or replace function public.insert_eligibility_course_match(p_row public.eligibility_course_matches)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_schema text;
begin
  select input_schema_version into v_schema
  from public.eligibility_evaluations where evaluation_id = p_row.evaluation_id;
  if v_schema = 'eligibility-v0.2' and not exists (
    select 1 from private.eligibility_v02_finalize_authorizations a
    where a.transaction_id = txid_current() and a.evaluation_id = p_row.evaluation_id
  ) then
    raise exception using errcode = '55000',
      message = 'v0.2 matches are written only by finalize_eligibility_evaluation_v02',
      hint = 'eligibility_v02_caller_outcome_forbidden';
  end if;
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_course_matches');
  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_course_matches'::regclass, to_jsonb(p_row));
end;
$$;

create or replace function public.insert_eligibility_test_match(p_row public.eligibility_test_matches)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_schema text;
begin
  select input_schema_version into v_schema
  from public.eligibility_evaluations where evaluation_id = p_row.evaluation_id;
  if v_schema = 'eligibility-v0.2' and not exists (
    select 1 from private.eligibility_v02_finalize_authorizations a
    where a.transaction_id = txid_current() and a.evaluation_id = p_row.evaluation_id
  ) then
    raise exception using errcode = '55000',
      message = 'v0.2 matches are written only by finalize_eligibility_evaluation_v02',
      hint = 'eligibility_v02_caller_outcome_forbidden';
  end if;
  perform public.reject_terminal_insert(to_jsonb(p_row), 'eligibility_test_matches');
  perform private.lock_evaluation_from_row(to_jsonb(p_row));
  perform public.insert_composite('public.eligibility_test_matches'::regclass, to_jsonb(p_row));
end;
$$;

create or replace function public.seal_eligibility_evaluation_inputs(p_evaluation_id uuid)
returns void
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare v_student uuid; v_schema text;
begin
  select p.student_id, e.input_schema_version into v_student, v_schema
  from public.eligibility_evaluations e
  join public.student_profile_versions p using (profile_version_id)
  where e.evaluation_id = p_evaluation_id;
  if v_schema = 'eligibility-v0.2' then
    raise exception using errcode = '55000',
      message = 'v0.1 seal cannot operate on a v0.2 evaluation',
      hint = 'eligibility_v01_api_on_v02_row';
  end if;
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

create or replace function public.finalize_eligibility_evaluation(
  p_evaluation_id uuid,
  p_outcome public.eligibility_outcome
)
returns text
language plpgsql security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_evaluation public.eligibility_evaluations%rowtype;
  v_root_id uuid;
  v_root_truth public.requirement_truth_value;
  v_expected integer;
  v_actual integer;
  v_manifest jsonb;
  v_fingerprint text;
  v_student uuid;
begin
  select p.student_id into v_student
  from public.eligibility_evaluations e
  join public.student_profile_versions p using (profile_version_id)
  where e.evaluation_id = p_evaluation_id;
  perform private.lock_student_lifecycle(v_student);
  perform private.lock_student_owned_total_order(v_student);
  select * into v_evaluation from public.eligibility_evaluations
    where evaluation_id = p_evaluation_id for update;
  if v_evaluation.input_schema_version = 'eligibility-v0.2' then
    raise exception using errcode = '55000',
      message = 'v0.1 finalize cannot operate on a v0.2 evaluation',
      hint = 'eligibility_v01_api_on_v02_row';
  end if;
  if not found or v_evaluation.evaluation_state <> 'BUILDING' then
    raise exception 'A building evaluation is required';
  end if;
  if v_evaluation.inputs_sealed_at is null then
    raise exception using errcode = '55000',
      message = 'Eligibility inputs must be sealed before finalization';
  end if;
  select rule_node_id into v_root_id from public.program_requirement_nodes
    where rule_set_id = v_evaluation.rule_set_id and parent_node_id is null;
  select truth_value into v_root_truth from public.eligibility_requirement_results
    where evaluation_id = p_evaluation_id and rule_node_id = v_root_id;
  if v_root_truth is null then raise exception 'Root result is required'; end if;
  select count(*) into v_expected from public.program_requirement_nodes where rule_set_id = v_evaluation.rule_set_id;
  select count(*) into v_actual from public.eligibility_requirement_results where evaluation_id = p_evaluation_id;
  if v_actual <> v_expected then raise exception 'Every rule node requires exactly one result'; end if;
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
    'degreeIds', coalesce((select jsonb_agg(student_degree_id order by student_degree_id) from public.eligibility_manifest_degrees where evaluation_id = p_evaluation_id), '[]'::jsonb),
    'courseIds', coalesce((select jsonb_agg(student_course_id order by student_course_id) from public.eligibility_manifest_courses where evaluation_id = p_evaluation_id), '[]'::jsonb),
    'testScoreIds', coalesce((select jsonb_agg(student_test_score_id order by student_test_score_id) from public.eligibility_manifest_test_scores where evaluation_id = p_evaluation_id), '[]'::jsonb),
    'studentMappingIds', coalesce((select jsonb_agg(student_mapping_id order by student_mapping_id) from public.eligibility_manifest_student_mappings where evaluation_id = p_evaluation_id), '[]'::jsonb),
    'completenessScopes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'completenessId', manifest.completeness_id,
        'educationContextId', completeness.education_context_id,
        'domain', completeness.domain
      ) order by completeness.domain, completeness.education_context_id nulls first, manifest.completeness_id)
      from public.eligibility_manifest_completeness manifest
      join public.student_data_completeness completeness
        on completeness.completeness_id = manifest.completeness_id
       and completeness.profile_version_id = manifest.profile_version_id
      where manifest.evaluation_id = p_evaluation_id
    ), '[]'::jsonb),
    'studentEvidenceIds', coalesce((select jsonb_agg(student_evidence_id order by student_evidence_id) from public.eligibility_manifest_student_evidence where evaluation_id = p_evaluation_id), '[]'::jsonb),
    'catalogSourceIds', coalesce((select jsonb_agg(field_observation_id order by field_observation_id) from public.eligibility_manifest_catalog_sources where evaluation_id = p_evaluation_id), '[]'::jsonb),
    'catalogMappingIds', coalesce((select jsonb_agg(catalog_mapping_id order by catalog_mapping_id) from public.eligibility_manifest_catalog_mappings where evaluation_id = p_evaluation_id), '[]'::jsonb),
    'taxonomyConceptIds', coalesce((select jsonb_agg(concept_id order by concept_id) from public.eligibility_manifest_taxonomy_concepts where evaluation_id = p_evaluation_id), '[]'::jsonb)
  ) into v_manifest;
  v_fingerprint := encode(extensions.digest(convert_to(v_manifest::text, 'UTF8'), 'sha256'), 'hex');
  update public.eligibility_evaluations
  set evaluation_state = 'COMPLETED',
      input_fingerprint = v_fingerprint,
      outcome = p_outcome,
      root_truth_value = v_root_truth,
      evaluated_at = now()
  where evaluation_id = p_evaluation_id;
  return v_fingerprint;
end;
$$;

create or replace function private.close_student_owned_rows(p_student_id uuid)
returns void
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if exists (select 1 from private.student_identities where student_id = p_student_id)
     or exists (select 1 from public.student_profile_versions where student_id = p_student_id)
     or exists (select 1 from private.student_lifecycle_audit where student_id = p_student_id)
     or exists (select 1 from public.student_data_completeness c join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.student_evidence_items e join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.student_degrees d join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.student_courses c join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.student_test_scores t join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.student_experiences x join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.student_skills k join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.student_goals g join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.student_preferences f join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.student_record_concept_mappings m join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.student_derived_feature_values v join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_evaluations e join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.fit_evaluations e join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.fit_intent_sets i join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from private.fit_student_access_contexts c join public.student_profile_versions p using (profile_version_id) where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_rule_node_source_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_rule_node_mapping_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_projection_threshold_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_catalog_observation_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_catalog_selection_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_snapshot_scopes s join public.eligibility_evaluations e on e.evaluation_id = s.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_rule_set_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_rule_node_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_student_mapping_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_catalog_mapping_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_taxonomy_concept_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_completeness_pins x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_snapshot_degrees x join public.eligibility_snapshot_scopes s on s.scope_id = x.scope_id join public.eligibility_evaluations e on e.evaluation_id = s.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_snapshot_courses x join public.eligibility_snapshot_scopes s on s.scope_id = x.scope_id join public.eligibility_evaluations e on e.evaluation_id = s.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_snapshot_test_scores x join public.eligibility_snapshot_scopes s on s.scope_id = x.scope_id join public.eligibility_evaluations e on e.evaluation_id = s.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_snapshot_mapping_universe x join public.eligibility_snapshot_scopes s on s.scope_id = x.scope_id join public.eligibility_evaluations e on e.evaluation_id = s.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_requirement_projection_results x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_negative_fact_authorizations x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from public.eligibility_negative_authorization_scopes x join public.eligibility_evaluations e on e.evaluation_id = x.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
     or exists (select 1 from private.eligibility_v02_finalize_authorizations a join public.eligibility_evaluations e on e.evaluation_id = a.evaluation_id join public.student_profile_versions p on p.profile_version_id = e.profile_version_id where p.student_id = p_student_id)
  then
    raise exception using errcode = '55000',
      message = 'Student-owned rows remain after privacy cascade',
      hint = 'privacy_closure_incomplete';
  end if;
end;
$$;


grant select, insert, update, delete on public.requirement_group_projection_thresholds to foundation_catalog_executor;
grant select on public.requirement_group_projection_thresholds to foundation_evaluation_executor;

do $dml013$
declare t text;
begin
  foreach t in array array[
    'eligibility_rule_set_pins','eligibility_rule_node_pins','eligibility_rule_node_source_pins',
    'eligibility_rule_node_mapping_pins','eligibility_projection_threshold_pins',
    'eligibility_catalog_observation_pins','eligibility_catalog_selection_pins',
    'eligibility_catalog_mapping_pins','eligibility_student_mapping_pins',
    'eligibility_taxonomy_concept_pins','eligibility_completeness_pins',
    'eligibility_snapshot_scopes','eligibility_snapshot_degrees','eligibility_snapshot_courses',
    'eligibility_snapshot_test_scores','eligibility_snapshot_mapping_universe',
    'eligibility_requirement_projection_results','eligibility_negative_fact_authorizations',
    'eligibility_negative_authorization_scopes'
  ]
  loop
    execute format('grant select, insert, update, delete on public.%I to foundation_evaluation_executor', t);
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy %I on public.%I for select to authenticated using (exists (select 1 from public.eligibility_evaluations e where e.evaluation_id = %I.evaluation_id and public.current_user_owns_profile(e.profile_version_id)))',
      t || '_owner_read', t, t
    );
    execute format(
      'create policy %I on public.%I for all to foundation_evaluation_executor using (current_user = %L) with check (current_user = %L)',
      t || '_eval_executor', t, 'foundation_evaluation_executor', 'foundation_evaluation_executor'
    );
    execute format(
      'create policy %I on public.%I for all to foundation_student_executor using (current_user = %L) with check (current_user = %L)',
      t || '_student_lock', t, 'foundation_student_executor', 'foundation_student_executor'
    );
    execute format(
      'revoke insert, update, delete on public.%I from public, anon, authenticated, service_role',
      t
    );
    execute format('grant select on public.%I to foundation_student_executor', t);
  end loop;
end;
$dml013$;

-- snapshot membership tables expose evaluation_id; owner-read uses it.
grant select, insert, update, delete on private.eligibility_v02_finalize_authorizations to foundation_evaluation_executor;
grant select on private.eligibility_v02_finalize_authorizations to foundation_student_executor;
alter table private.eligibility_v02_finalize_authorizations enable row level security;
create policy eligibility_v02_finalize_authorizations_eval
  on private.eligibility_v02_finalize_authorizations
  for all to foundation_evaluation_executor
  using (current_user = 'foundation_evaluation_executor')
  with check (current_user = 'foundation_evaluation_executor');
create policy eligibility_v02_finalize_authorizations_student
  on private.eligibility_v02_finalize_authorizations
  for all to foundation_student_executor
  using (current_user = 'foundation_student_executor')
  with check (current_user = 'foundation_student_executor');
revoke all on table private.taxonomy_release_ordinal_allocator
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
alter table public.requirement_group_projection_thresholds enable row level security;
create policy requirement_group_projection_thresholds_catalog_executor
  on public.requirement_group_projection_thresholds
  for all to foundation_catalog_executor
  using (current_user = 'foundation_catalog_executor')
  with check (current_user = 'foundation_catalog_executor');
revoke insert, update, delete on public.requirement_group_projection_thresholds
  from public, anon, authenticated, service_role;

-- Evaluation-executor v0.2 start/pin/finalize take FOR KEY SHARE / FOR UPDATE on
-- catalog and student source rows (plan §6.2). PostgreSQL requires UPDATE table
-- privilege AND UPDATE RLS USING visibility for those locks; WITH CHECK (false)
-- keeps this from becoming mutation authority.
grant select, update on
  public.program_requirement_rule_sets,
  public.program_requirement_nodes,
  public.taxonomy_releases,
  public.taxonomy_concepts,
  public.catalog_concept_mappings,
  public.field_observations,
  public.canonical_field_selections,
  public.evidence_items,
  public.sources,
  public.evidence_applicability_assertions,
  public.evidence_applicability_scopes,
  public.evidence_applicability_heads,
  public.field_observation_applicability,
  public.requirement_group_projection_thresholds,
  public.student_data_completeness,
  public.student_courses,
  public.student_degrees,
  public.student_test_scores,
  public.student_record_concept_mappings
  to foundation_evaluation_executor;

do $eval_lock_rls$
declare
  t text;
begin
  foreach t in array array[
    'program_requirement_rule_sets',
    'program_requirement_nodes',
    'taxonomy_releases',
    'taxonomy_concepts',
    'catalog_concept_mappings',
    'field_observations',
    'canonical_field_selections',
    'evidence_items',
    'sources',
    'evidence_applicability_assertions',
    'evidence_applicability_scopes',
    'evidence_applicability_heads',
    'field_observation_applicability',
    'requirement_group_projection_thresholds',
    'student_data_completeness',
    'student_courses',
    'student_degrees',
    'student_test_scores',
    'student_record_concept_mappings'
  ]
  loop
    execute format('drop policy if exists %I on public.%I', t || '_eval_lock_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_eval_lock_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_evaluation_executor_lock', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_executor_read', t);
    execute format(
      'create policy %I on public.%I for select to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor using (true)',
      t || '_executor_read', t
    );
    execute format(
      'create policy %I on public.%I for update to foundation_evaluation_executor using (current_user = %L) with check (false)',
      t || '_evaluation_executor_lock', t, 'foundation_evaluation_executor'
    );
  end loop;
end;
$eval_lock_rls$;

-- Hosted Supabase grants EXECUTE on new public functions to external roles
-- through postgres/public default ACLs. These functions are trigger-only
-- guards and have no callable external surface.
revoke all on function
  public.guard_taxonomy_release_ordinal_immutable(),
  public.guard_eligibility_snapshot_scope_shape(),
  public.guard_eligibility_mapping_universe_status(),
  public.guard_eligibility_v02_sealed_pin(),
  public.guard_projection_threshold_immutable(),
  public.guard_eligibility_v02_finalizer_only_row()
from public, anon, authenticated, service_role, authenticator;

grant create on schema public to foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
grant create on schema private to foundation_student_executor, foundation_evaluation_executor;

do $xfer013$
declare
  r record;
  v_owner text;
  v_path text;
  v_callers text[];
begin
  for r in
    select n.nspname, p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as ident
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'start_eligibility_evaluation_v02',
        'seal_eligibility_evaluation_inputs_v02',
        'finalize_eligibility_evaluation_v02',
        'insert_eligibility_rule_set_pin',
        'insert_eligibility_rule_node_pin',
        'insert_eligibility_rule_node_source_pin',
        'insert_eligibility_rule_node_mapping_pin',
        'insert_eligibility_projection_threshold_pin',
        'insert_eligibility_catalog_observation_pin',
        'insert_eligibility_catalog_selection_pin',
        'insert_eligibility_catalog_mapping_pin',
        'insert_eligibility_student_mapping_pin',
        'insert_eligibility_taxonomy_concept_pin',
        'insert_eligibility_completeness_pin',
        'insert_eligibility_snapshot_scope',
        'insert_eligibility_snapshot_degree',
        'insert_eligibility_snapshot_course',
        'insert_eligibility_snapshot_test_score',
        'insert_eligibility_snapshot_mapping_universe',
        'insert_requirement_group_projection_threshold'
      )
  loop
    if r.proname = 'insert_requirement_group_projection_threshold' then
      v_owner := 'foundation_catalog_executor';
      v_path := 'pg_catalog, public, extensions';
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
$xfer013$;

do $helpers013$
declare r record;
begin
  for r in
    select n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) as ident
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private'
      and p.proname in (
        'canonical_json_v02',
        'canonical_eligibility_v02_input_fingerprint',
        'canonical_eligibility_v02_result_fingerprint',
        'eligibility_v02_leaf_class',
        'eligibility_v02_project_leaf',
        'eligibility_v02_aggregate',
        'eligibility_v02_derive_outcome',
        'eligibility_v02_active_at_ordinal',
        'eligibility_v02_lock_evaluation',
        'eligibility_v02_require_building_unsealed',
        'eligibility_v02_assert_closed_world',
        'eligibility_v02_required_student_mappings',
        'eligibility_v02_leaf_actual',
        'eligibility_v02_leaf_decision',
        'eligibility_v02_pin_mismatch',
        'eligibility_v02_scope_semantic',
        'eligibility_v02_assert_completed_tree'
      )
  loop
    execute format('revoke all on function %I.%I(%s) from public, anon, authenticated, service_role', r.nspname, r.proname, r.ident);
    execute format('grant execute on function %I.%I(%s) to foundation_evaluation_executor', r.nspname, r.proname, r.ident);
  end loop;
  revoke all on function private.taxonomy_allocate_release_ordinal()
    from public, anon, authenticated, service_role, authenticator,
         foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;
  revoke all on function public.allocate_taxonomy_release_ordinal_v02()
    from public, anon, authenticated, service_role, authenticator,
         foundation_student_executor, foundation_evaluation_executor;
  grant execute on function public.allocate_taxonomy_release_ordinal_v02() to foundation_catalog_executor;
  revoke all on function private.close_student_owned_rows(uuid)
    from public, anon, authenticated, service_role, foundation_catalog_executor, foundation_evaluation_executor;
  grant execute on function private.close_student_owned_rows(uuid) to foundation_student_executor;
end;
$helpers013$;

do $registry013$
declare
  r record;
  v_owner text;
  v_path text;
  v_callers text[];
  v_prosecdef boolean;
begin
  -- Replaced 012 signatures: update body_digest only.
  for r in
    select n.nspname, p.oid, p.proname, pg_get_function_identity_arguments(p.oid) as ident,
           pg_get_userbyid(p.proowner) as owner, p.prosecdef
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where (n.nspname, p.proname) in (
      ('public', 'create_taxonomy_release'),
      ('public', 'verify_taxonomy_release'),
      ('public', 'create_taxonomy_concept'),
      ('public', 'create_taxonomy_alias'),
      ('public', 'create_taxonomy_relationship'),
      ('public', 'retire_taxonomy_concept'),
      ('public', 'retire_taxonomy_alias'),
      ('public', 'retire_taxonomy_relationship'),
      ('public', 'verify_program_requirement_rule_set'),
      ('public', 'validate_eligibility_match_insert'),
      ('public', 'seal_eligibility_evaluation_inputs'),
      ('public', 'finalize_eligibility_evaluation'),
      ('public', 'insert_eligibility_requirement_result'),
      ('public', 'insert_eligibility_course_match'),
      ('public', 'insert_eligibility_test_match'),
      ('public', 'allocate_taxonomy_release_ordinal_v02')
    )
  loop
    if r.proname = 'allocate_taxonomy_release_ordinal_v02' then
      v_owner := current_user;
      v_path := 'pg_catalog, private';
      v_callers := array['foundation_catalog_executor'];
      v_prosecdef := true;
    elsif r.proname = 'taxonomy_allocate_release_ordinal' then
      v_owner := current_user;
      v_path := 'pg_catalog, public, private';
      v_callers := '{}';
      v_prosecdef := false;
    else
      select owner_role, search_path, allowed_caller_roles
        into v_owner, v_path, v_callers
      from public.foundation_function_contracts
      where schema_name = r.nspname and function_name = r.proname
        and identity_arguments = r.ident;
      if v_owner is null then
        v_owner := r.owner;
        v_path := case when r.nspname = 'private' then 'pg_catalog, public, private, extensions'
                       when r.proname like 'create_taxonomy%' or r.proname like 'retire_taxonomy%'
                            or r.proname like 'verify_%'
                         then 'pg_catalog, public, extensions'
                       else 'pg_catalog, public, private, extensions' end;
        v_callers := array['service_role'];
        v_prosecdef := r.prosecdef;
      end if;
    end if;
    insert into public.foundation_function_contracts (
      schema_name, function_name, identity_arguments, owner_role, prosecdef,
      search_path, allowed_caller_roles, body_digest
    ) values (
      r.nspname, r.proname, r.ident, coalesce(v_owner, r.owner), coalesce(v_prosecdef, r.prosecdef),
      coalesce(v_path, 'pg_catalog, public, private, extensions'),
      coalesce(v_callers, array['service_role']),
      encode(extensions.digest(convert_to(pg_get_functiondef(r.oid), 'UTF8'), 'sha256'), 'hex')
    )
    on conflict (schema_name, function_name, identity_arguments) do update
      set body_digest = excluded.body_digest,
          owner_role = excluded.owner_role,
          search_path = excluded.search_path,
          allowed_caller_roles = excluded.allowed_caller_roles,
          prosecdef = excluded.prosecdef;
  end loop;
end;
$registry013$;

revoke create on schema public from foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor, public, anon, authenticated, service_role;
revoke create on schema private from foundation_student_executor, foundation_evaluation_executor, public, anon, authenticated, service_role;
revoke create on schema extensions from public, anon, authenticated, service_role, foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor;

do $assert013$
declare
  v_owner text;
  v_cfg text;
begin
  if has_schema_privilege('foundation_catalog_executor', 'private', 'USAGE') then
    raise exception using errcode = '55000',
      message = '013 must not grant catalog-executor USAGE on private';
  end if;
  select pg_get_userbyid(p.proowner), array_to_string(p.proconfig, ',')
    into v_owner, v_cfg
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'allocate_taxonomy_release_ordinal_v02'
    and pg_get_function_identity_arguments(p.oid) = '';
  if v_owner is distinct from current_user
     or v_owner is not distinct from 'foundation_catalog_executor'
     or v_owner is not distinct from 'service_role' then
    raise exception using errcode = '55000',
      message = format('ordinal wrapper owner is %s', v_owner);
  end if;
  if v_cfg is distinct from 'search_path=pg_catalog, private' then
    raise exception using errcode = '55000',
      message = format('ordinal wrapper search_path is %s', v_cfg);
  end if;
  if has_function_privilege('service_role', 'public.allocate_taxonomy_release_ordinal_v02()', 'EXECUTE')
     or has_function_privilege('anon', 'public.allocate_taxonomy_release_ordinal_v02()', 'EXECUTE')
     or has_function_privilege('authenticated', 'public.allocate_taxonomy_release_ordinal_v02()', 'EXECUTE')
     or not has_function_privilege('foundation_catalog_executor', 'public.allocate_taxonomy_release_ordinal_v02()', 'EXECUTE') then
    raise exception using errcode = '55000',
      message = 'ordinal wrapper EXECUTE grant is incorrect';
  end if;
  if has_function_privilege('foundation_catalog_executor', 'private.taxonomy_allocate_release_ordinal()', 'EXECUTE') then
    raise exception using errcode = '55000',
      message = 'catalog executor must not EXECUTE private allocator';
  end if;
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_roles o on o.oid = p.proowner
    where n.nspname = 'public' and p.proname = 'create_taxonomy_release'
      and pg_get_function_identity_arguments(p.oid) = 'text, timestamp with time zone, text'
      and (
        o.rolname is distinct from 'foundation_catalog_executor'
        or array_to_string(p.proconfig, ',') is distinct from 'search_path=pg_catalog, public, extensions'
        or pg_get_functiondef(p.oid) ~ 'private\.'
      )
  ) then
    raise exception using errcode = '55000',
      message = 'create_taxonomy_release owner/path/private qualifier contract failed';
  end if;
  if not has_table_privilege('foundation_evaluation_executor', 'public.program_requirement_rule_sets', 'UPDATE')
     or not has_table_privilege('foundation_evaluation_executor', 'public.taxonomy_releases', 'UPDATE')
     or not has_table_privilege('foundation_evaluation_executor', 'public.student_record_concept_mappings', 'UPDATE') then
    raise exception using errcode = '55000',
      message = 'evaluation executor lacks UPDATE lock privilege on v0.2 source parents';
  end if;
  if exists (
    select 1
    from unnest(array[
      'program_requirement_rule_sets',
      'program_requirement_nodes',
      'taxonomy_releases',
      'taxonomy_concepts',
      'catalog_concept_mappings',
      'field_observations',
      'canonical_field_selections',
      'evidence_items',
      'sources',
      'evidence_applicability_assertions',
      'evidence_applicability_scopes',
      'evidence_applicability_heads',
      'field_observation_applicability',
      'requirement_group_projection_thresholds',
      'student_data_completeness',
      'student_courses',
      'student_degrees',
      'student_test_scores',
      'student_record_concept_mappings'
    ]) as t(relname)
    where not exists (
      select 1
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = t.relname
        and p.polname = left(t.relname || '_evaluation_executor_lock', 63)
        and p.polcmd = 'w'
        and pg_get_expr(p.polqual, p.polrelid) like '%foundation_evaluation_executor%'
        and pg_get_expr(p.polwithcheck, p.polrelid) = 'false'
    )
    or exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = t.relname
        and not c.relrowsecurity
    )
    or exists (
      select 1
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      join pg_roles r on r.oid = any (p.polroles)
      where n.nspname = 'public'
        and c.relname = t.relname
        and r.rolname = 'foundation_evaluation_executor'
        and p.polcmd = '*'
    )
  ) then
    raise exception using errcode = '55000',
      message = 'evaluation executor lock policy must be FOR UPDATE WITH CHECK (false)';
  end if;
end;
$assert013$;

commit;
