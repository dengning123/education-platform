begin;

create type public.rule_set_status as enum ('DRAFT', 'VERIFIED', 'RETIRED');
create type public.requirement_node_kind as enum ('GROUP', 'PREDICATE');
create type public.requirement_group_operator as enum ('ALL', 'ANY', 'AT_LEAST');
create type public.requirement_strength as enum ('HARD', 'SOFT');
create type public.requirement_semantics as enum (
  'ORDINARY',
  'EXPLICIT_CONDITIONAL'
);
create type public.requirement_predicate_kind as enum (
  'HAS_COURSE_CONCEPT',
  'HAS_TEST'
);

create table public.program_requirement_rule_sets (
  rule_set_id uuid primary key default extensions.gen_random_uuid(),
  program_version_id uuid not null
    references public.program_versions(program_version_id) on delete restrict,
  rule_set_version integer not null,
  taxonomy_release_code text not null
    references public.taxonomy_releases(release_code) on delete restrict,
  rule_schema_version text not null default 'phase2-v0.1',
  engine_contract_version text not null default 'eligibility-v0.1',
  status public.rule_set_status not null default 'DRAFT',
  verification_evidence_id uuid
    references public.evidence_items(evidence_id) on delete restrict,
  verified_by text,
  verified_at timestamptz,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint program_rule_sets_positive_version
    check (rule_set_version > 0),
  constraint program_rule_sets_supported_contract
    check (
      rule_schema_version = 'phase2-v0.1'
      and engine_contract_version = 'eligibility-v0.1'
    ),
  constraint program_rule_sets_verification_state
    check (
      (
        status = 'DRAFT'
        and verified_by is null
        and verified_at is null
      )
      or (
        status in ('VERIFIED', 'RETIRED')
        and nullif(btrim(verified_by), '') is not null
        and verified_at is not null
        and verification_evidence_id is not null
      )
    ),
  constraint program_rule_sets_retirement_state
    check (
      (status = 'RETIRED')
      = (retired_at is not null and retirement_reason is not null)
    ),
  unique (program_version_id, rule_set_version),
  unique (rule_set_id, program_version_id)
);

create unique index program_requirement_one_verified_idx
  on public.program_requirement_rule_sets (program_version_id)
  where status = 'VERIFIED';

create table public.program_requirement_nodes (
  rule_node_id uuid primary key default extensions.gen_random_uuid(),
  rule_set_id uuid not null
    references public.program_requirement_rule_sets(rule_set_id)
    on delete restrict,
  parent_node_id uuid,
  sort_order integer not null default 0,
  node_kind public.requirement_node_kind not null,
  group_operator public.requirement_group_operator,
  minimum_children integer,
  predicate_kind public.requirement_predicate_kind,
  requirement_strength public.requirement_strength,
  requirement_semantics public.requirement_semantics,
  target_concept_id uuid
    references public.taxonomy_concepts(concept_id) on delete restrict,
  explanation_template text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint program_requirement_nodes_sort_order
    check (sort_order >= 0),
  constraint program_requirement_nodes_group_shape
    check (
      (
        node_kind = 'GROUP'
        and group_operator is not null
        and predicate_kind is null
        and requirement_strength is null
        and requirement_semantics is null
        and target_concept_id is null
        and (
          (group_operator = 'AT_LEAST' and minimum_children > 0)
          or (group_operator <> 'AT_LEAST' and minimum_children is null)
        )
      )
      or (
        node_kind = 'PREDICATE'
        and group_operator is null
        and minimum_children is null
        and predicate_kind is not null
        and requirement_strength is not null
        and requirement_semantics is not null
      )
    ),
  constraint program_requirement_nodes_explanation
    check (btrim(explanation_template) <> ''),
  unique (rule_set_id, rule_node_id),
  foreign key (rule_set_id, parent_node_id)
    references public.program_requirement_nodes(rule_set_id, rule_node_id)
    on delete restrict
    deferrable initially deferred
);

create unique index program_requirement_one_root_idx
  on public.program_requirement_nodes (rule_set_id)
  where parent_node_id is null;
create unique index program_requirement_sibling_order_idx
  on public.program_requirement_nodes (
    rule_set_id,
    parent_node_id,
    sort_order
  )
  where parent_node_id is not null;

create table public.program_requirement_node_sources (
  rule_node_id uuid not null
    references public.program_requirement_nodes(rule_node_id) on delete restrict,
  field_observation_id uuid not null
    references public.field_observations(observation_id) on delete restrict,
  primary key (rule_node_id, field_observation_id)
);

create table public.program_requirement_node_mappings (
  rule_node_id uuid not null
    references public.program_requirement_nodes(rule_node_id) on delete restrict,
  catalog_mapping_id uuid not null
    references public.catalog_concept_mappings(mapping_id) on delete restrict,
  primary key (rule_node_id, catalog_mapping_id)
);

comment on table public.program_requirement_node_sources is
  'References accepted canonical observations; rule nodes do not duplicate canonical values.';

create index program_requirement_nodes_parent_idx
  on public.program_requirement_nodes (rule_set_id, parent_node_id, sort_order);

create trigger program_rule_sets_set_updated_at
before update on public.program_requirement_rule_sets
for each row execute function public.set_updated_at();
create trigger program_requirement_nodes_set_updated_at
before update on public.program_requirement_nodes
for each row execute function public.set_updated_at();

create or replace function public.catalog_record_program_version(
  p_record_type public.catalog_record_type,
  p_record_id uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_program_version_id uuid;
begin
  case p_record_type
    when 'PROGRAM_VERSION' then
      select program_version_id into v_program_version_id
      from public.program_versions where program_version_id = p_record_id;
    when 'PROGRAM_ADMISSION' then
      select program_version_id into v_program_version_id
      from public.program_admissions where admission_id = p_record_id;
    when 'PROGRAM_PREREQUISITE' then
      select program_version_id into v_program_version_id
      from public.program_prerequisites where prerequisite_id = p_record_id;
    when 'PROGRAM_COURSE' then
      select program_version_id into v_program_version_id
      from public.program_courses where course_id = p_record_id;
    when 'PROGRAM_COST' then
      select program_version_id into v_program_version_id
      from public.program_costs where cost_id = p_record_id;
    when 'PROGRAM_DEADLINE' then
      select program_version_id into v_program_version_id
      from public.program_deadlines where deadline_id = p_record_id;
    else
      v_program_version_id := null;
  end case;
  return v_program_version_id;
end;
$$;

create or replace function public.guard_verified_rule_content()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_rule_set_id uuid;
  v_status public.rule_set_status;
begin
  if tg_table_name = 'program_requirement_nodes' then
    v_rule_set_id := coalesce(new.rule_set_id, old.rule_set_id);
  else
    select n.rule_set_id into v_rule_set_id
    from public.program_requirement_nodes n
    where n.rule_node_id = coalesce(new.rule_node_id, old.rule_node_id);
  end if;
  select status into v_status
  from public.program_requirement_rule_sets
  where rule_set_id = v_rule_set_id;
  if v_status in ('VERIFIED', 'RETIRED') then
    raise exception 'Verified or retired requirement rules are immutable';
  end if;
  return coalesce(new, old);
end;
$$;

create trigger program_requirement_nodes_verified_guard
before insert or update or delete on public.program_requirement_nodes
for each row execute function public.guard_verified_rule_content();
create trigger program_requirement_sources_verified_guard
before insert or update or delete on public.program_requirement_node_sources
for each row execute function public.guard_verified_rule_content();
create trigger program_requirement_mappings_verified_guard
before insert or update or delete on public.program_requirement_node_mappings
for each row execute function public.guard_verified_rule_content();

create or replace function public.guard_rule_set_status_update()
returns trigger
language plpgsql
as $$
begin
  if new.status is distinct from old.status
     and current_setting('app.rule_set_controlled_write', true)
       is distinct from 'on' then
    raise exception 'Use verify_program_requirement_rule_set() or retire_program_requirement_rule_set()';
  end if;
  if old.status in ('VERIFIED', 'RETIRED')
     and new.status = 'DRAFT' then
    raise exception 'Rule-set verification cannot be reversed';
  end if;
  return new;
end;
$$;

create trigger program_rule_sets_status_guard
before update on public.program_requirement_rule_sets
for each row execute function public.guard_rule_set_status_update();

create or replace function public.verify_program_requirement_rule_set(
  p_rule_set_id uuid,
  p_verified_by text,
  p_verification_evidence_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
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
  v_prior_control_setting text;
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
  if not exists (
    select 1 from public.evidence_items
    where evidence_id = p_verification_evidence_id
  ) then
    raise exception 'Verification evidence does not exist';
  end if;

  select rule_node_id into v_root_id
  from public.program_requirement_nodes
  where rule_set_id = p_rule_set_id and parent_node_id is null;
  if v_root_id is null then
    raise exception 'Rule set requires exactly one root';
  end if;

  select count(*) into v_total_nodes
  from public.program_requirement_nodes
  where rule_set_id = p_rule_set_id;

  with recursive reachable(rule_node_id, path) as (
    select v_root_id, array[v_root_id]
    union all
    select n.rule_node_id, r.path || n.rule_node_id
    from reachable r
    join public.program_requirement_nodes n
      on n.parent_node_id = r.rule_node_id
      and n.rule_set_id = p_rule_set_id
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
    where child.rule_set_id = n.rule_set_id
      and child.parent_node_id = n.rule_node_id
  ) c on true
  where n.rule_set_id = p_rule_set_id
    and n.node_kind = 'GROUP'
    and (
      c.child_count = 0
      or (
        n.group_operator = 'AT_LEAST'
        and n.minimum_children > c.child_count
      )
    );
  if v_invalid_groups > 0 then
    raise exception 'Every group needs children and valid AT_LEAST cardinality';
  end if;

  select count(*) into v_invalid_predicates
  from public.program_requirement_nodes n
  where n.rule_set_id = p_rule_set_id
    and n.node_kind = 'PREDICATE'
    and (
      exists (
        select 1 from public.program_requirement_nodes child
        where child.parent_node_id = n.rule_node_id
      )
      or (
        n.predicate_kind in (
          'HAS_COURSE_CONCEPT',
          'HAS_TEST'
        )
        and n.target_concept_id is null
      )
      or (
        n.predicate_kind not in (
          'HAS_COURSE_CONCEPT',
          'HAS_TEST'
        )
        and n.target_concept_id is not null
      )
      or (
        n.predicate_kind = 'HAS_COURSE_CONCEPT'
        and not exists (
          select 1
          from public.taxonomy_concepts tc
          where tc.concept_id = n.target_concept_id
            and tc.concept_kind = 'COURSE_CONCEPT'
            and tc.retired_in_release is null
        )
      )
      or (
        n.predicate_kind = 'HAS_TEST'
        and not exists (
          select 1
          from public.taxonomy_concepts tc
          where tc.concept_id = n.target_concept_id
            and tc.concept_kind = 'ASSESSMENT'
            and tc.retired_in_release is null
        )
      )
      or (
        n.requirement_semantics = 'EXPLICIT_CONDITIONAL'
        and not exists (
          select 1
          from public.program_requirement_nodes parent
          where parent.rule_node_id = n.parent_node_id
            and parent.rule_set_id = n.rule_set_id
            and parent.node_kind = 'GROUP'
            and parent.group_operator = 'ALL'
        )
      )
    );
  if v_invalid_predicates > 0 then
    raise exception 'Predicate node shape is invalid';
  end if;

  select count(*) into v_invalid_sources
  from public.program_requirement_nodes n
  where n.rule_set_id = p_rule_set_id
    and n.node_kind = 'PREDICATE'
    and not exists (
      select 1
      from public.program_requirement_node_sources ns
      join public.field_observations o
        on o.observation_id = ns.field_observation_id
      join public.canonical_field_selections c
        on c.observation_id = o.observation_id
       and c.record_type = o.record_type
       and c.record_id = o.record_id
       and c.field_name = o.field_name
      where ns.rule_node_id = n.rule_node_id
        and o.knowledge_status = 'KNOWN'
        and public.catalog_record_program_version(
          o.record_type,
          o.record_id
        ) = v_rule_set.program_version_id
    );
  if v_invalid_sources > 0 then
    raise exception 'Every predicate requires a currently selected KNOWN source observation for this program version';
  end if;

  select count(*) into v_invalid_mappings
  from public.program_requirement_nodes n
  where n.rule_set_id = p_rule_set_id
    and n.predicate_kind in (
      'HAS_COURSE_CONCEPT'
    )
    and not exists (
      select 1
      from public.program_requirement_node_mappings nm
      join public.catalog_concept_mappings m
        on m.mapping_id = nm.catalog_mapping_id
      where nm.rule_node_id = n.rule_node_id
        and m.mapping_status = 'VERIFIED'
        and m.concept_id = n.target_concept_id
        and public.catalog_record_program_version(
          m.record_type,
          m.record_id
        ) = v_rule_set.program_version_id
    );
  if v_invalid_mappings > 0 then
    raise exception 'Concept predicates require a reviewed catalog mapping for this program version';
  end if;

  v_prior_control_setting :=
    current_setting('app.rule_set_controlled_write', true);
  perform set_config('app.rule_set_controlled_write', 'on', true);
  update public.program_requirement_rule_sets
  set status = 'VERIFIED',
      verified_by = p_verified_by,
      verified_at = now(),
      verification_evidence_id = p_verification_evidence_id
  where rule_set_id = p_rule_set_id;
  perform set_config(
    'app.rule_set_controlled_write',
    coalesce(v_prior_control_setting, ''),
    true
  );
end;
$$;

create or replace function public.retire_program_requirement_rule_set(
  p_rule_set_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_prior_control_setting text;
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Retirement reason is required';
  end if;
  v_prior_control_setting :=
    current_setting('app.rule_set_controlled_write', true);
  perform set_config('app.rule_set_controlled_write', 'on', true);
  update public.program_requirement_rule_sets
  set status = 'RETIRED',
      retired_at = now(),
      retirement_reason = p_reason
  where rule_set_id = p_rule_set_id
    and status = 'VERIFIED';
  if not found then
    raise exception 'A verified rule set is required';
  end if;
  perform set_config(
    'app.rule_set_controlled_write',
    coalesce(v_prior_control_setting, ''),
    true
  );
end;
$$;

revoke all on function public.verify_program_requirement_rule_set(uuid, text, uuid) from public;
revoke all on function public.retire_program_requirement_rule_set(uuid, text) from public;
grant execute on function public.verify_program_requirement_rule_set(uuid, text, uuid) to service_role;
grant execute on function public.retire_program_requirement_rule_set(uuid, text) to service_role;

create trigger program_rule_sets_audit
after insert or update or delete on public.program_requirement_rule_sets
for each row execute function public.audit_phase2_change('rule_set_id');
create trigger program_requirement_nodes_audit
after insert or update or delete on public.program_requirement_nodes
for each row execute function public.audit_phase2_change('rule_node_id');

alter table public.program_requirement_rule_sets enable row level security;
alter table public.program_requirement_nodes enable row level security;
alter table public.program_requirement_node_sources enable row level security;
alter table public.program_requirement_node_mappings enable row level security;

create policy verified_program_rule_sets_public_read
  on public.program_requirement_rule_sets for select to public
  using (status = 'VERIFIED');
create policy verified_program_requirement_nodes_public_read
  on public.program_requirement_nodes for select to public
  using (
    exists (
      select 1 from public.program_requirement_rule_sets rs
      where rs.rule_set_id = program_requirement_nodes.rule_set_id
        and rs.status = 'VERIFIED'
    )
  );
create policy verified_program_requirement_sources_public_read
  on public.program_requirement_node_sources for select to public
  using (
    exists (
      select 1
      from public.program_requirement_nodes n
      join public.program_requirement_rule_sets rs using (rule_set_id)
      where n.rule_node_id =
        program_requirement_node_sources.rule_node_id
        and rs.status = 'VERIFIED'
    )
  );
create policy verified_program_requirement_mappings_public_read
  on public.program_requirement_node_mappings for select to public
  using (
    exists (
      select 1
      from public.program_requirement_nodes n
      join public.program_requirement_rule_sets rs using (rule_set_id)
      where n.rule_node_id =
        program_requirement_node_mappings.rule_node_id
        and rs.status = 'VERIFIED'
    )
  );

commit;
