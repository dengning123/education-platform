begin;

create table public.student_feature_definitions (
  feature_definition_id uuid primary key default extensions.gen_random_uuid(),
  feature_key text not null,
  definition_version integer not null,
  description text not null,
  algorithm_name text not null,
  algorithm_version text not null,
  input_contract jsonb not null,
  output_contract jsonb not null,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  constraint student_feature_definitions_key_format
    check (feature_key ~ '^[a-z][a-z0-9_]*$'),
  constraint student_feature_definitions_version
    check (definition_version > 0),
  constraint student_feature_definitions_contracts
    check (
      jsonb_typeof(input_contract) = 'object'
      and jsonb_typeof(output_contract) = 'object'
    ),
  unique (feature_key, definition_version)
);

create table public.student_derived_feature_values (
  feature_value_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  feature_definition_id uuid not null
    references public.student_feature_definitions(feature_definition_id)
    on delete restrict,
  input_manifest_hash text not null,
  feature_value jsonb not null,
  computed_at timestamptz not null default now(),
  constraint student_feature_values_hash_format
    check (input_manifest_hash ~ '^[a-f0-9]{64}$'),
  constraint student_feature_values_not_null
    check (feature_value <> 'null'::jsonb),
  unique (
    profile_version_id,
    feature_definition_id,
    input_manifest_hash
  )
);

comment on table public.student_derived_feature_values is
  'Append-only derived data. Explicitly excluded from eligibility-engine v0.1 inputs.';

create index student_feature_values_profile_idx
  on public.student_derived_feature_values (
    profile_version_id,
    feature_definition_id
  );

create or replace function public.validate_derived_feature_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_status public.profile_version_status;
begin
  select status into v_status
  from public.student_profile_versions
  where profile_version_id = new.profile_version_id;
  if v_status is distinct from 'FROZEN' then
    raise exception 'Derived features require a frozen profile version';
  end if;
  return new;
end;
$$;

create or replace function public.prevent_row_mutation()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'DELETE'
     and current_setting('app.student_privacy_delete', true) = 'on' then
    return old;
  end if;
  raise exception '% rows are append-only', tg_table_name;
end;
$$;

create trigger student_feature_values_validate_insert
before insert on public.student_derived_feature_values
for each row execute function public.validate_derived_feature_insert();
create trigger student_feature_values_immutable
before update or delete on public.student_derived_feature_values
for each row execute function public.prevent_row_mutation();

alter table public.student_feature_definitions enable row level security;
alter table public.student_derived_feature_values enable row level security;

create policy student_feature_definitions_public_read
  on public.student_feature_definitions for select to public using (true);
create policy student_feature_values_owner_read
  on public.student_derived_feature_values for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));

commit;
