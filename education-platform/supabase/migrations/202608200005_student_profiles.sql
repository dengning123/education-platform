begin;

create schema if not exists private;

create type public.student_privacy_state as enum (
  'ACTIVE',
  'ANONYMIZED',
  'DELETION_PENDING'
);
create type public.profile_version_status as enum ('DRAFT', 'FROZEN');
create type public.student_data_domain as enum (
  'EDUCATION_HISTORY',
  'COURSE_HISTORY',
  'COURSE_MAPPING',
  'TEST_HISTORY',
  'EXPERIENCE_HISTORY',
  'SKILL_HISTORY',
  'PREFERENCES',
  'GOALS'
);
create type public.data_completeness as enum ('COMPLETE', 'PARTIAL', 'UNKNOWN');
create type public.student_evidence_type as enum (
  'SELF_REPORT',
  'TRANSCRIPT',
  'TEST_REPORT',
  'RESUME',
  'OTHER'
);
create type public.degree_status as enum (
  'IN_PROGRESS',
  'COMPLETED',
  'WITHDRAWN'
);
create type public.course_status as enum (
  'PLANNED',
  'IN_PROGRESS',
  'COMPLETED',
  'WITHDRAWN'
);
create type public.experience_type as enum (
  'EMPLOYMENT',
  'INTERNSHIP',
  'RESEARCH',
  'PROJECT',
  'LEADERSHIP',
  'VOLUNTEERING',
  'OTHER'
);
create type public.student_mapping_record_type as enum ('DEGREE', 'COURSE');
create type public.goal_type as enum ('CAREER', 'INDUSTRY', 'FIELD', 'OTHER');
create type public.preference_type as enum (
  'LOCATION',
  'DELIVERY_MODE',
  'BUDGET',
  'PROGRAM_LENGTH',
  'OTHER'
);

create table public.students (
  student_id uuid primary key default extensions.gen_random_uuid(),
  privacy_state public.student_privacy_state not null default 'ACTIVE',
  anonymized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint students_anonymization_state
    check (
      (privacy_state = 'ANONYMIZED') = (anonymized_at is not null)
      or privacy_state = 'DELETION_PENDING'
    )
);

comment on table public.students is
  'Anonymous analytical identity. Direct account identity is isolated in student_identities.';

create table private.student_identities (
  identity_id uuid primary key default extensions.gen_random_uuid(),
  auth_user_id uuid not null unique
    references auth.users(id) on delete cascade,
  student_id uuid not null unique
    references public.students(student_id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.student_deletion_tombstones (
  tombstone_id uuid primary key default extensions.gen_random_uuid(),
  deleted_at timestamptz not null default now(),
  deletion_reason text not null,
  constraint student_deletion_tombstones_reason
    check (btrim(deletion_reason) <> '')
);

comment on table public.student_deletion_tombstones is
  'Non-PII proof of deletion; deliberately contains no student identifier or document hash.';

create table public.student_profile_versions (
  profile_version_id uuid primary key default extensions.gen_random_uuid(),
  student_id uuid not null
    references public.students(student_id) on delete cascade,
  version_number integer not null,
  status public.profile_version_status not null default 'DRAFT',
  snapshot_hash text,
  frozen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint student_profile_versions_positive check (version_number > 0),
  constraint student_profile_versions_frozen_state
    check (
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
  unique (student_id, version_number)
);

create table public.student_data_completeness (
  completeness_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  education_context_id uuid,
  domain public.student_data_domain not null,
  completeness public.data_completeness not null,
  explanation text,
  updated_at timestamptz not null default now(),
  constraint student_completeness_context_scope
    check (
      domain in ('COURSE_HISTORY', 'COURSE_MAPPING')
      or education_context_id is null
    ),
  constraint student_completeness_explanation
    check (
      completeness = 'COMPLETE'
      or nullif(btrim(explanation), '') is not null
    ),
  unique (profile_version_id, completeness_id)
);

create unique index student_data_completeness_scope_unique
  on public.student_data_completeness (
    profile_version_id,
    education_context_id,
    domain
  ) nulls not distinct;

create table public.student_evidence_items (
  student_evidence_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  evidence_type public.student_evidence_type not null,
  locator text,
  content_hash text,
  observed_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint student_evidence_hash_format
    check (content_hash is null or content_hash ~ '^[a-f0-9]{64}$'),
  constraint student_evidence_metadata_object
    check (jsonb_typeof(metadata) = 'object'),
  unique (profile_version_id, student_evidence_id)
);

create table public.student_degrees (
  student_degree_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  institution_name text not null,
  degree_name text not null,
  degree_level public.degree_level not null,
  degree_status public.degree_status not null,
  start_date date,
  completion_date date,
  country_code text,
  gpa_value numeric(6,3),
  gpa_scale numeric(6,3),
  student_evidence_id uuid not null
    references public.student_evidence_items(student_evidence_id)
    on delete cascade,
  created_at timestamptz not null default now(),
  constraint student_degrees_names_not_blank
    check (btrim(institution_name) <> '' and btrim(degree_name) <> ''),
  constraint student_degrees_date_order
    check (
      start_date is null
      or completion_date is null
      or completion_date >= start_date
    ),
  constraint student_degrees_gpa_pair
    check (
      (gpa_value is null and gpa_scale is null)
      or (
        gpa_value is not null
        and gpa_scale is not null
        and gpa_scale > 0
        and gpa_value between 0 and gpa_scale
      )
    ),
  constraint student_degrees_country_code
    check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  unique (profile_version_id, student_degree_id),
  foreign key (profile_version_id, student_evidence_id)
    references public.student_evidence_items(
      profile_version_id,
      student_evidence_id
    ) on delete cascade
);

alter table public.student_data_completeness
  add foreign key (profile_version_id, education_context_id)
  references public.student_degrees(
    profile_version_id,
    student_degree_id
  ) on delete cascade;

create table public.student_courses (
  student_course_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  student_degree_id uuid
    references public.student_degrees(student_degree_id) on delete cascade,
  course_code text,
  course_title text not null,
  course_status public.course_status not null,
  term text,
  completion_date date,
  credits numeric(6,2),
  grade_value numeric(6,3),
  grade_scale numeric(6,3),
  grade_text text,
  student_evidence_id uuid not null
    references public.student_evidence_items(student_evidence_id)
    on delete cascade,
  created_at timestamptz not null default now(),
  constraint student_courses_title_not_blank check (btrim(course_title) <> ''),
  constraint student_courses_credits_positive
    check (credits is null or credits > 0),
  constraint student_courses_grade_pair
    check (
      (grade_value is null and grade_scale is null)
      or (
        grade_value is not null
        and grade_scale is not null
        and grade_scale > 0
        and grade_value between 0 and grade_scale
      )
    ),
  unique (profile_version_id, student_course_id),
  foreign key (profile_version_id, student_degree_id)
    references public.student_degrees(profile_version_id, student_degree_id)
    on delete cascade,
  foreign key (profile_version_id, student_evidence_id)
    references public.student_evidence_items(
      profile_version_id,
      student_evidence_id
    ) on delete cascade
);

create table public.student_test_scores (
  student_test_score_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  assessment_concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  test_date date not null,
  total_score numeric(8,2),
  section_scores jsonb not null default '{}'::jsonb,
  student_evidence_id uuid not null
    references public.student_evidence_items(student_evidence_id)
    on delete cascade,
  created_at timestamptz not null default now(),
  constraint student_test_scores_value_present
    check (total_score is not null or section_scores <> '{}'::jsonb),
  constraint student_test_scores_sections_object
    check (jsonb_typeof(section_scores) = 'object'),
  unique (profile_version_id, student_test_score_id),
  foreign key (profile_version_id, student_evidence_id)
    references public.student_evidence_items(
      profile_version_id,
      student_evidence_id
    ) on delete cascade
);

create table public.student_experiences (
  student_experience_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  experience_type public.experience_type not null,
  organization_name text,
  role_title text not null,
  start_date date,
  end_date date,
  hours_per_week numeric(5,2),
  description text,
  student_evidence_id uuid not null
    references public.student_evidence_items(student_evidence_id)
    on delete cascade,
  created_at timestamptz not null default now(),
  constraint student_experiences_role_not_blank check (btrim(role_title) <> ''),
  constraint student_experiences_date_order
    check (start_date is null or end_date is null or end_date >= start_date),
  constraint student_experiences_hours
    check (hours_per_week is null or hours_per_week between 0 and 168),
  unique (profile_version_id, student_experience_id),
  foreign key (profile_version_id, student_evidence_id)
    references public.student_evidence_items(
      profile_version_id,
      student_evidence_id
    ) on delete cascade
);

create table public.student_skills (
  student_skill_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  skill_concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  proficiency_level integer,
  years_experience numeric(5,2),
  student_evidence_id uuid not null
    references public.student_evidence_items(student_evidence_id)
    on delete cascade,
  created_at timestamptz not null default now(),
  constraint student_skills_proficiency_range
    check (proficiency_level is null or proficiency_level between 1 and 5),
  constraint student_skills_experience_nonnegative
    check (years_experience is null or years_experience >= 0),
  unique (profile_version_id, skill_concept_id),
  unique (profile_version_id, student_skill_id),
  foreign key (profile_version_id, student_evidence_id)
    references public.student_evidence_items(
      profile_version_id,
      student_evidence_id
    ) on delete cascade
);

create table public.student_experience_skills (
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  student_experience_id uuid not null
    references public.student_experiences(student_experience_id),
  student_skill_id uuid not null
    references public.student_skills(student_skill_id),
  primary key (
    profile_version_id,
    student_experience_id,
    student_skill_id
  ),
  foreign key (profile_version_id, student_experience_id)
    references public.student_experiences(
      profile_version_id,
      student_experience_id
    ) on delete cascade,
  foreign key (profile_version_id, student_skill_id)
    references public.student_skills(profile_version_id, student_skill_id)
    on delete cascade
);

create table public.student_goals (
  student_goal_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  goal_type public.goal_type not null,
  concept_id uuid
    references public.taxonomy_concepts(concept_id) on delete restrict,
  goal_text text,
  priority integer not null default 1,
  created_at timestamptz not null default now(),
  constraint student_goals_content
    check (concept_id is not null or nullif(btrim(goal_text), '') is not null),
  constraint student_goals_priority check (priority between 1 and 5)
);

create table public.student_preferences (
  student_preference_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  preference_type public.preference_type not null,
  value jsonb not null,
  priority integer not null default 1,
  created_at timestamptz not null default now(),
  constraint student_preferences_value_not_null
    check (value <> 'null'::jsonb),
  constraint student_preferences_priority check (priority between 1 and 5)
);

create table public.student_record_concept_mappings (
  student_mapping_id uuid primary key default extensions.gen_random_uuid(),
  profile_version_id uuid not null
    references public.student_profile_versions(profile_version_id)
    on delete cascade,
  record_type public.student_mapping_record_type not null,
  student_record_id uuid not null,
  concept_id uuid not null
    references public.taxonomy_concepts(concept_id) on delete restrict,
  mapping_status public.mapping_status not null default 'PROPOSED',
  method public.mapping_method not null,
  confidence numeric(5,4),
  model_version text,
  reviewed_by text,
  reviewed_at timestamptz,
  student_evidence_id uuid
    references public.student_evidence_items(student_evidence_id)
    on delete cascade,
  supersedes_mapping_id uuid
    references public.student_record_concept_mappings(student_mapping_id)
    on delete restrict,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  constraint student_record_mappings_confidence
    check (confidence is null or confidence between 0 and 1),
  constraint student_record_mappings_model_version
    check (method <> 'MODEL' or nullif(btrim(model_version), '') is not null),
  constraint student_record_mappings_review_authority
    check (
      mapping_status not in ('VERIFIED', 'REJECTED')
      or (
        nullif(btrim(reviewed_by), '') is not null
        and reviewed_at is not null
      )
    ),
  constraint student_record_mappings_verified_evidence
    check (
      mapping_status <> 'VERIFIED'
      or student_evidence_id is not null
    ),
  constraint student_record_mappings_retirement_pair
    check (
      (mapping_status = 'RETIRED')
      = (retired_at is not null and retirement_reason is not null)
    ),
  unique (profile_version_id, student_mapping_id),
  foreign key (profile_version_id, student_evidence_id)
    references public.student_evidence_items(
      profile_version_id,
      student_evidence_id
    ) on delete cascade
);

create unique index student_record_mappings_active_unique
  on public.student_record_concept_mappings (
    record_type,
    student_record_id,
    concept_id
  )
  where mapping_status in ('PROPOSED', 'VERIFIED');

create index student_profiles_student_idx
  on public.student_profile_versions (student_id, version_number desc);
create index student_degrees_profile_idx
  on public.student_degrees (profile_version_id);
create index student_courses_profile_idx
  on public.student_courses (profile_version_id);
create index student_tests_profile_idx
  on public.student_test_scores (profile_version_id);
create index student_experiences_profile_idx
  on public.student_experiences (profile_version_id);
create index student_skills_profile_idx
  on public.student_skills (profile_version_id);
create index student_mappings_profile_idx
  on public.student_record_concept_mappings (
    profile_version_id,
    mapping_status
  );

create trigger students_set_updated_at
before update on public.students
for each row execute function public.set_updated_at();
create trigger student_profile_versions_set_updated_at
before update on public.student_profile_versions
for each row execute function public.set_updated_at();
create trigger student_data_completeness_set_updated_at
before update on public.student_data_completeness
for each row execute function public.set_updated_at();

create or replace function public.validate_student_taxonomy_kind()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_concept_id uuid;
  v_expected public.taxonomy_concept_kind;
  v_actual public.taxonomy_concept_kind;
begin
  if tg_table_name = 'student_test_scores' then
    v_concept_id := new.assessment_concept_id;
    v_expected := 'ASSESSMENT';
  elsif tg_table_name = 'student_skills' then
    v_concept_id := new.skill_concept_id;
    v_expected := 'SKILL';
  else
    return new;
  end if;

  select concept_kind into v_actual
  from public.taxonomy_concepts
  where concept_id = v_concept_id
    and retired_in_release is null;
  if v_actual is distinct from v_expected then
    raise exception 'Expected active % concept, received %', v_expected, v_actual;
  end if;
  return new;
end;
$$;

create or replace function public.validate_student_record_mapping()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_profile_id uuid;
  v_concept_kind public.taxonomy_concept_kind;
begin
  if new.record_type = 'DEGREE' then
    select profile_version_id into v_profile_id
    from public.student_degrees
    where student_degree_id = new.student_record_id;
    select concept_kind into v_concept_kind
    from public.taxonomy_concepts where concept_id = new.concept_id;
    if v_concept_kind not in ('FIELD', 'SUBFIELD') then
      raise exception 'Degree mappings require FIELD or SUBFIELD concepts';
    end if;
  elsif new.record_type = 'COURSE' then
    select profile_version_id into v_profile_id
    from public.student_courses
    where student_course_id = new.student_record_id;
    select concept_kind into v_concept_kind
    from public.taxonomy_concepts where concept_id = new.concept_id;
    if v_concept_kind <> 'COURSE_CONCEPT' then
      raise exception 'Course mappings require COURSE_CONCEPT concepts';
    end if;
  end if;

  if v_profile_id is null or v_profile_id <> new.profile_version_id then
    raise exception 'Mapped record must belong to the declared profile version';
  end if;
  return new;
end;
$$;

create or replace function public.guard_frozen_profile_child_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row jsonb;
  v_profile_id uuid;
  v_status public.profile_version_status;
begin
  if tg_op = 'DELETE'
     and current_setting('app.student_privacy_delete', true) = 'on' then
    return old;
  end if;
  v_row := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_profile_id := (v_row ->> tg_argv[0])::uuid;
  select status into v_status
  from public.student_profile_versions
  where profile_version_id = v_profile_id;
  if v_status = 'FROZEN' then
    raise exception 'Frozen profile versions are immutable';
  end if;
  return coalesce(new, old);
end;
$$;

create or replace function public.guard_student_profile_version()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_missing integer;
begin
  if old.status = 'FROZEN' then
    raise exception 'Frozen profile versions are immutable';
  end if;

  if new.status = 'FROZEN' then
    with required_scope(education_context_id, domain) as (
      select null::uuid, domain
      from unnest(array[
        'EDUCATION_HISTORY',
        'TEST_HISTORY',
        'EXPERIENCE_HISTORY',
        'SKILL_HISTORY',
        'PREFERENCES',
        'GOALS'
      ]::public.student_data_domain[]) as global_domain(domain)
      union all
      select d.student_degree_id, course_domain.domain
      from public.student_degrees d
      cross join unnest(array[
        'COURSE_HISTORY',
        'COURSE_MAPPING'
      ]::public.student_data_domain[]) as course_domain(domain)
      where d.profile_version_id = new.profile_version_id
      union all
      select null::uuid, course_domain.domain
      from unnest(array[
        'COURSE_HISTORY',
        'COURSE_MAPPING'
      ]::public.student_data_domain[]) as course_domain(domain)
      where not exists (
        select 1
        from public.student_degrees d
        where d.profile_version_id = new.profile_version_id
      )
    )
    select count(*) into v_missing
    from required_scope expected
    where not exists (
      select 1
      from public.student_data_completeness c
      where c.profile_version_id = new.profile_version_id
        and c.education_context_id is not distinct from
          expected.education_context_id
        and c.domain = expected.domain
    );
    if v_missing > 0 then
      raise exception 'Every required profile and education context requires explicit completeness';
    end if;
  end if;
  return new;
end;
$$;

create trigger student_tests_validate_kind
before insert or update on public.student_test_scores
for each row execute function public.validate_student_taxonomy_kind();
create trigger student_skills_validate_kind
before insert or update on public.student_skills
for each row execute function public.validate_student_taxonomy_kind();
create trigger student_record_mappings_validate
before insert or update on public.student_record_concept_mappings
for each row execute function public.validate_student_record_mapping();
create trigger student_profile_versions_guard
before update on public.student_profile_versions
for each row execute function public.guard_student_profile_version();

create trigger student_data_completeness_frozen_guard
before insert or update or delete on public.student_data_completeness
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');
create trigger student_evidence_frozen_guard
before insert or update or delete on public.student_evidence_items
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');
create trigger student_degrees_frozen_guard
before insert or update or delete on public.student_degrees
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');
create trigger student_courses_frozen_guard
before insert or update or delete on public.student_courses
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');
create trigger student_tests_frozen_guard
before insert or update or delete on public.student_test_scores
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');
create trigger student_experiences_frozen_guard
before insert or update or delete on public.student_experiences
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');
create trigger student_skills_frozen_guard
before insert or update or delete on public.student_skills
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');
create trigger student_experience_skills_frozen_guard
before insert or update or delete on public.student_experience_skills
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');
create trigger student_goals_frozen_guard
before insert or update or delete on public.student_goals
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');
create trigger student_preferences_frozen_guard
before insert or update or delete on public.student_preferences
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');
create trigger student_record_mappings_frozen_guard
before insert or update or delete on public.student_record_concept_mappings
for each row execute function public.guard_frozen_profile_child_write('profile_version_id');

create or replace function public.current_user_owns_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from private.student_identities
    where student_id = p_student_id
      and auth_user_id = auth.uid()
  );
$$;

create or replace function public.current_user_owns_profile(p_profile_version_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.student_profile_versions p
    join private.student_identities i using (student_id)
    where p.profile_version_id = p_profile_version_id
      and i.auth_user_id = auth.uid()
  );
$$;

create or replace function public.delete_student_data(
  p_student_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if nullif(btrim(p_reason), '') is null then
    raise exception 'Deletion reason is required';
  end if;
  perform set_config('app.student_privacy_delete', 'on', true);
  delete from public.students where student_id = p_student_id;
  if not found then
    raise exception 'Student % does not exist', p_student_id;
  end if;
  insert into public.student_deletion_tombstones (deletion_reason)
  values (p_reason);
end;
$$;

revoke all on function public.delete_student_data(uuid, text) from public;
grant execute on function public.delete_student_data(uuid, text) to service_role;

do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'students',
    'student_deletion_tombstones',
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
    'student_record_concept_mappings'
  ]
  loop
    execute format('alter table public.%I enable row level security', v_table);
  end loop;
end;
$$;

create policy students_owner_read on public.students
  for select to authenticated
  using (public.current_user_owns_student(student_id));
alter table private.student_identities enable row level security;

grant usage on schema private to service_role;
grant select, insert, update, delete
  on private.student_identities to service_role;

create policy student_profile_versions_owner_read on public.student_profile_versions
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_completeness_owner_read on public.student_data_completeness
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_evidence_owner_read on public.student_evidence_items
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_degrees_owner_read on public.student_degrees
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_courses_owner_read on public.student_courses
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_tests_owner_read on public.student_test_scores
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_experiences_owner_read on public.student_experiences
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_skills_owner_read on public.student_skills
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_goals_owner_read on public.student_goals
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_preferences_owner_read on public.student_preferences
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_record_mappings_owner_read
  on public.student_record_concept_mappings
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));
create policy student_experience_skills_owner_read
  on public.student_experience_skills
  for select to authenticated
  using (public.current_user_owns_profile(profile_version_id));

commit;
