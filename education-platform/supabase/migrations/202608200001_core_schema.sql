begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create type public.degree_level as enum (
  'BACHELORS',
  'MASTERS',
  'DOCTORAL',
  'CERTIFICATE',
  'OTHER'
);

create type public.program_active_status as enum (
  'ACTIVE',
  'INACTIVE',
  'SUSPENDED',
  'UNKNOWN'
);

create type public.program_school_role as enum (
  'PRIMARY_ADMINISTRATIVE',
  'JOINT_DELIVERY',
  'PARTICIPATING'
);

create type public.delivery_mode as enum (
  'IN_PERSON',
  'ONLINE',
  'HYBRID',
  'UNKNOWN'
);

create type public.verification_status as enum (
  'UNVERIFIED',
  'PARTIALLY_VERIFIED',
  'VERIFIED',
  'STALE',
  'SOURCE_CONFLICT'
);

create type public.admission_policy as enum (
  'REQUIRED',
  'REQUIRED_AS_ALTERNATIVE',
  'OPTIONAL',
  'RECOMMENDED',
  'NOT_ACCEPTED',
  'NOT_STATED',
  'UNKNOWN'
);

create type public.prerequisite_requirement_type as enum (
  'REQUIRED',
  'RECOMMENDED',
  'PREFERRED',
  'EXPECTED',
  'ALTERNATIVE'
);

create type public.logical_operator as enum ('AND', 'OR', 'NONE');

create type public.course_category as enum (
  'MATHEMATICS',
  'ECONOMICS',
  'ECONOMETRICS',
  'COMPUTING',
  'FINANCE',
  'RESEARCH',
  'POLICY',
  'ELECTIVE',
  'OTHER'
);

create type public.course_required_status as enum (
  'REQUIRED',
  'ELECTIVE',
  'OPTIONAL',
  'CHOICE'
);

create type public.billing_basis as enum (
  'TOTAL_PROGRAM',
  'PER_YEAR',
  'PER_SEMESTER',
  'PER_CREDIT',
  'UNKNOWN'
);

create type public.deadline_type as enum (
  'GENERAL',
  'ROUND',
  'PRIORITY',
  'SCHOLARSHIP_PRIORITY',
  'INTERNATIONAL',
  'FINAL',
  'ROLLING'
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create table public.universities (
  university_id uuid primary key default extensions.gen_random_uuid(),
  unitid text unique,
  name text not null,
  short_name text,
  country text not null,
  state text,
  city text,
  institution_type text,
  official_url text,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint universities_name_not_blank check (btrim(name) <> ''),
  constraint universities_country_not_blank check (btrim(country) <> ''),
  constraint universities_unitid_format check (unitid is null or unitid ~ '^[0-9]{6}$'),
  constraint universities_retirement_pair check (
    (retired_at is null) = (retirement_reason is null)
  )
);

create unique index universities_name_country_unique
  on public.universities (lower(name), lower(country));

create table public.schools (
  school_id uuid primary key default extensions.gen_random_uuid(),
  university_id uuid not null references public.universities(university_id) on delete restrict,
  name text not null,
  short_name text,
  official_url text,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schools_name_not_blank check (btrim(name) <> ''),
  constraint schools_retirement_pair check (
    (retired_at is null) = (retirement_reason is null)
  ),
  unique (university_id, name)
);

create table public.programs (
  program_id uuid primary key default extensions.gen_random_uuid(),
  university_id uuid not null references public.universities(university_id) on delete restrict,
  program_name text not null,
  degree_level public.degree_level not null,
  degree_type text not null,
  field text,
  subfield text,
  cip_code text,
  official_program_url text,
  active_status public.program_active_status,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint programs_name_not_blank check (btrim(program_name) <> ''),
  constraint programs_degree_type_not_blank check (btrim(degree_type) <> ''),
  constraint programs_cip_format check (cip_code is null or cip_code ~ '^[0-9]{2}\.[0-9]{4}$'),
  constraint programs_retirement_pair check (
    (retired_at is null) = (retirement_reason is null)
  ),
  unique (university_id, program_name, degree_type)
);

create table public.program_schools (
  program_school_id uuid primary key default extensions.gen_random_uuid(),
  program_id uuid not null references public.programs(program_id) on delete restrict,
  school_id uuid not null references public.schools(school_id) on delete restrict,
  relationship_role public.program_school_role not null,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint program_schools_retirement_pair check (
    (retired_at is null) = (retirement_reason is null)
  ),
  unique (program_id, school_id)
);

create unique index program_schools_one_primary
  on public.program_schools (program_id)
  where relationship_role = 'PRIMARY_ADMINISTRATIVE'
    and retired_at is null;

create or replace function public.validate_program_school_university()
returns trigger
language plpgsql
as $$
declare
  expected_university_id uuid;
  actual_university_id uuid;
begin
  select university_id into expected_university_id
    from public.programs
    where program_id = new.program_id;
  select university_id into actual_university_id
    from public.schools
    where school_id = new.school_id;

  if actual_university_id is distinct from expected_university_id then
    raise exception 'Program and school must belong to the same university';
  end if;
  return new;
end;
$$;

create trigger program_schools_validate_university
before insert or update on public.program_schools
for each row execute function public.validate_program_school_university();

create table public.program_versions (
  program_version_id uuid primary key default extensions.gen_random_uuid(),
  program_id uuid not null references public.programs(program_id) on delete restrict,
  admission_cycle_start_year smallint not null,
  admission_cycle_end_year smallint not null,
  admission_cycle text generated always as (
    admission_cycle_start_year::text || '-' || right(admission_cycle_end_year::text, 2)
  ) stored,
  academic_year_start smallint not null,
  academic_year_end smallint not null,
  academic_year text generated always as (
    academic_year_start::text || '-' || right(academic_year_end::text, 2)
  ) stored,
  entry_term text,
  entry_year smallint,
  delivery_mode public.delivery_mode,
  full_time boolean,
  duration_months numeric(5,2),
  credits_required numeric(6,2),
  stem_status boolean,
  start_month smallint,
  capstone_required boolean,
  valid_from date,
  valid_to date,
  verification_status public.verification_status not null default 'UNVERIFIED',
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint program_versions_admission_cycle_consecutive check (
    admission_cycle_start_year between 1900 and 2199
    and admission_cycle_end_year = admission_cycle_start_year + 1
  ),
  constraint program_versions_academic_year_consecutive check (
    academic_year_start between 1900 and 2199
    and academic_year_end = academic_year_start + 1
  ),
  constraint program_versions_duration_positive check (duration_months is null or duration_months > 0),
  constraint program_versions_credits_positive check (credits_required is null or credits_required > 0),
  constraint program_versions_entry_year_range check (entry_year is null or entry_year between 1900 and 2200),
  constraint program_versions_start_month_range check (start_month is null or start_month between 1 and 12),
  constraint program_versions_valid_range check (valid_to is null or valid_from is null or valid_to >= valid_from),
  constraint program_versions_retirement_pair check (
    (retired_at is null) = (retirement_reason is null)
  )
);

create unique index program_versions_cycle_entry_unique
  on public.program_versions (
    program_id,
    admission_cycle_start_year,
    admission_cycle_end_year,
    coalesce(entry_term, ''),
    coalesce(entry_year, 0)
  );

create table public.program_admissions (
  admission_id uuid primary key default extensions.gen_random_uuid(),
  program_version_id uuid not null unique references public.program_versions(program_version_id) on delete restrict,
  minimum_gpa numeric(4,3),
  average_gpa numeric(4,3),
  gre_policy public.admission_policy,
  gre_quant_minimum smallint,
  gre_quant_average numeric(5,2),
  gre_verbal_minimum smallint,
  gre_writing_minimum numeric(2,1),
  gmat_policy public.admission_policy,
  toefl_minimum smallint,
  ielts_minimum numeric(3,1),
  work_experience_requirement text,
  research_experience_requirement text,
  application_fee numeric(10,2),
  application_fee_currency char(3),
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint program_admissions_minimum_gpa_range check (minimum_gpa is null or minimum_gpa between 0 and 4.333),
  constraint program_admissions_average_gpa_range check (average_gpa is null or average_gpa between 0 and 4.333),
  constraint program_admissions_gre_quant_min_range check (gre_quant_minimum is null or gre_quant_minimum between 130 and 170),
  constraint program_admissions_gre_quant_avg_range check (gre_quant_average is null or gre_quant_average between 130 and 170),
  constraint program_admissions_gre_verbal_range check (gre_verbal_minimum is null or gre_verbal_minimum between 130 and 170),
  constraint program_admissions_gre_writing_range check (gre_writing_minimum is null or gre_writing_minimum between 0 and 6),
  constraint program_admissions_toefl_range check (toefl_minimum is null or toefl_minimum between 0 and 120),
  constraint program_admissions_ielts_range check (ielts_minimum is null or ielts_minimum between 0 and 9),
  constraint program_admissions_fee_nonnegative check (application_fee is null or application_fee >= 0),
  constraint program_admissions_fee_currency check (
    (application_fee is null and application_fee_currency is null)
    or (application_fee is not null and application_fee_currency ~ '^[A-Z]{3}$')
  ),
  constraint program_admissions_retirement_pair check (
    (retired_at is null) = (retirement_reason is null)
  )
);

create table public.program_prerequisites (
  prerequisite_id uuid primary key default extensions.gen_random_uuid(),
  program_version_id uuid not null references public.program_versions(program_version_id) on delete restrict,
  subject text not null,
  subject_category text,
  requirement_type public.prerequisite_requirement_type not null,
  minimum_level text,
  minimum_grade text,
  requirement_group text,
  logical_operator public.logical_operator not null default 'NONE',
  evidence_type text,
  notes text,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint program_prerequisites_subject_not_blank check (btrim(subject) <> ''),
  constraint program_prerequisites_group_required_for_operator check (
    logical_operator = 'NONE' or requirement_group is not null
  ),
  constraint program_prerequisites_retirement_pair check (
    (retired_at is null) = (retirement_reason is null)
  )
);

create index program_prerequisites_group_idx
  on public.program_prerequisites (program_version_id, requirement_group);

create table public.program_courses (
  course_id uuid primary key default extensions.gen_random_uuid(),
  program_version_id uuid not null references public.program_versions(program_version_id) on delete restrict,
  course_code text,
  course_name text not null,
  credits numeric(5,2),
  course_category public.course_category not null default 'OTHER',
  required_status public.course_required_status not null,
  official_description text,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint program_courses_name_not_blank check (btrim(course_name) <> ''),
  constraint program_courses_credits_positive check (credits is null or credits > 0),
  constraint program_courses_retirement_pair check (
    (retired_at is null) = (retirement_reason is null)
  ),
  unique (program_version_id, course_code)
);

create table public.program_costs (
  cost_id uuid primary key default extensions.gen_random_uuid(),
  program_version_id uuid not null references public.program_versions(program_version_id) on delete restrict,
  academic_year_start smallint not null,
  academic_year_end smallint not null,
  academic_year text generated always as (
    academic_year_start::text || '-' || right(academic_year_end::text, 2)
  ) stored,
  tuition_amount numeric(14,2),
  currency char(3),
  billing_basis public.billing_basis,
  mandatory_fees numeric(14,2),
  estimated_living_cost numeric(14,2),
  estimated_total_cost numeric(14,2),
  scholarship_available boolean,
  cost_notes text,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint program_costs_academic_year_consecutive check (
    academic_year_start between 1900 and 2199
    and academic_year_end = academic_year_start + 1
  ),
  constraint program_costs_amounts_nonnegative check (
    (tuition_amount is null or tuition_amount >= 0)
    and (mandatory_fees is null or mandatory_fees >= 0)
    and (estimated_living_cost is null or estimated_living_cost >= 0)
    and (estimated_total_cost is null or estimated_total_cost >= 0)
  ),
  constraint program_costs_currency check (
    currency is null or currency ~ '^[A-Z]{3}$'
  ),
  constraint program_costs_retirement_pair check (
    (retired_at is null) = (retirement_reason is null)
  )
);

create unique index program_costs_version_year_basis_unique
  on public.program_costs (
    program_version_id,
    academic_year_start,
    academic_year_end,
    coalesce(billing_basis, 'UNKNOWN'::public.billing_basis)
  );

create table public.program_deadlines (
  deadline_id uuid primary key default extensions.gen_random_uuid(),
  program_version_id uuid not null references public.program_versions(program_version_id) on delete restrict,
  deadline_type public.deadline_type not null,
  application_round text,
  applicant_type text not null default 'ALL',
  deadline_date date,
  rolling_admission boolean,
  retired_at timestamptz,
  retirement_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint program_deadlines_applicant_type_not_blank check (btrim(applicant_type) <> ''),
  constraint program_deadlines_date_or_rolling check (
    deadline_date is not null or rolling_admission is true
  ),
  constraint program_deadlines_retirement_pair check (
    (retired_at is null) = (retirement_reason is null)
  )
);

create unique index program_deadlines_unique
  on public.program_deadlines (
    program_version_id,
    deadline_type,
    coalesce(application_round, ''),
    applicant_type
  );

create index schools_university_idx on public.schools (university_id);
create index programs_university_idx on public.programs (university_id);
create index programs_cip_idx on public.programs (cip_code) where cip_code is not null;
create index program_versions_program_idx on public.program_versions (program_id);
create index program_courses_version_idx on public.program_courses (program_version_id);
create index program_deadlines_version_date_idx on public.program_deadlines (program_version_id, deadline_date);

create trigger universities_set_updated_at
before update on public.universities
for each row execute function public.set_updated_at();

create trigger schools_set_updated_at
before update on public.schools
for each row execute function public.set_updated_at();

create trigger programs_set_updated_at
before update on public.programs
for each row execute function public.set_updated_at();

create trigger program_schools_set_updated_at
before update on public.program_schools
for each row execute function public.set_updated_at();

create trigger program_versions_set_updated_at
before update on public.program_versions
for each row execute function public.set_updated_at();

create trigger program_admissions_set_updated_at
before update on public.program_admissions
for each row execute function public.set_updated_at();

create trigger program_prerequisites_set_updated_at
before update on public.program_prerequisites
for each row execute function public.set_updated_at();

create trigger program_courses_set_updated_at
before update on public.program_courses
for each row execute function public.set_updated_at();

create trigger program_costs_set_updated_at
before update on public.program_costs
for each row execute function public.set_updated_at();

create trigger program_deadlines_set_updated_at
before update on public.program_deadlines
for each row execute function public.set_updated_at();

commit;
