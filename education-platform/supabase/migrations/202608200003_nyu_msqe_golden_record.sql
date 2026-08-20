begin;

-- Stable identifiers keep the golden record deterministic across environments.
insert into public.universities (
  university_id, unitid, name, short_name, country, state, city,
  institution_type, official_url
) values (
  '00000000-0000-0000-0000-000000000101',
  '193900',
  'New York University',
  'NYU',
  'United States',
  'New York',
  'New York',
  'Private nonprofit',
  'https://www.nyu.edu/'
) on conflict do nothing;

insert into public.schools (
  school_id, university_id, name, short_name, official_url
) values
  (
    '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000101',
    'Graduate School of Arts and Science',
    'GSAS',
    'https://gsas.nyu.edu/'
  ),
  (
    '00000000-0000-0000-0000-000000000202',
    '00000000-0000-0000-0000-000000000101',
    'Leonard N. Stern School of Business',
    'NYU Stern',
    'https://www.stern.nyu.edu/'
  )
on conflict do nothing;

insert into public.programs (
  program_id, university_id, program_name,
  degree_level, degree_type, field, subfield, cip_code, official_program_url
) values (
  '00000000-0000-0000-0000-000000000301',
  '00000000-0000-0000-0000-000000000101',
  'MS in Quantitative Economics',
  'MASTERS',
  'MS',
  'Economics',
  'Quantitative Economics',
  '45.0603',
  'https://as.nyu.edu/departments/econ/graduate/ms.html'
) on conflict do nothing;

insert into public.program_schools (
  program_school_id, program_id, school_id, relationship_role
) values
  (
    '00000000-0000-0000-0000-000000000211',
    '00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000201',
    'PRIMARY_ADMINISTRATIVE'
  ),
  (
    '00000000-0000-0000-0000-000000000212',
    '00000000-0000-0000-0000-000000000301',
    '00000000-0000-0000-0000-000000000202',
    'JOINT_DELIVERY'
  )
on conflict do nothing;

insert into public.program_versions (
  program_version_id, program_id,
  admission_cycle_start_year, admission_cycle_end_year,
  academic_year_start, academic_year_end,
  entry_term, entry_year, duration_months, credits_required,
  stem_status, start_month, capstone_required, verification_status
) values (
  '00000000-0000-0000-0000-000000000401',
  '00000000-0000-0000-0000-000000000301',
  2026,
  2027,
  2026,
  2027,
  'SUMMER',
  2026,
  10,
  33,
  true,
  7,
  true,
  'PARTIALLY_VERIFIED'
) on conflict do nothing;

insert into public.program_admissions (
  admission_id, program_version_id, gre_policy, gmat_policy
) values (
  '00000000-0000-0000-0000-000000000402',
  '00000000-0000-0000-0000-000000000401',
  'REQUIRED_AS_ALTERNATIVE',
  'REQUIRED_AS_ALTERNATIVE'
) on conflict do nothing;

insert into public.program_deadlines (
  deadline_id, program_version_id, deadline_type, applicant_type,
  deadline_date, rolling_admission
) values (
  '00000000-0000-0000-0000-000000000403',
  '00000000-0000-0000-0000-000000000401',
  'GENERAL',
  'ALL',
  date '2026-02-15',
  true
) on conflict do nothing;

insert into public.program_costs (
  cost_id, program_version_id, academic_year_start, academic_year_end, cost_notes
) values (
  '00000000-0000-0000-0000-000000000404',
  '00000000-0000-0000-0000-000000000401',
  2026,
  2027,
  'Program-specific cost fields were not verified for this golden-record release.'
) on conflict do nothing;

insert into public.program_courses (
  course_id, program_version_id, course_code, course_name, credits,
  course_category, required_status
) values
  ('00000000-0000-0000-0000-000000004011', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4011', 'Mathematical Methods for Economists I', 1.5, 'MATHEMATICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004012', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4012', 'Mathematical Methods for Economists II', 1.5, 'MATHEMATICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004021', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4021', 'Data and Computation I', 1.5, 'COMPUTING', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004022', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4022', 'Data and Computation II', 1.5, 'COMPUTING', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004031', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4031', 'Microeconomics I', 1.5, 'ECONOMICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004032', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4032', 'Microeconomics II', 1.5, 'ECONOMICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004041', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4041', 'Macroeconomics I', 1.5, 'ECONOMICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004042', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4042', 'Macroeconomics II', 1.5, 'ECONOMICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004043', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4043', 'Macroeconomics III', 1.5, 'ECONOMICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004044', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4044', 'Macroeconomics IV', 1.5, 'ECONOMICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004051', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4051', 'Game Theory I', 1.5, 'ECONOMICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004052', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4052', 'Game Theory II', 1.5, 'ECONOMICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004061', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4061', 'Applied Microeconomics I', 1.5, 'ECONOMICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004062', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4062', 'Applied Microeconomics II', 1.5, 'ECONOMICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004071', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4071', 'Econometrics I', 1.5, 'ECONOMETRICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004072', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4072', 'Econometrics II', 1.5, 'ECONOMETRICS', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004121', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4121', 'Research Practicum I', 1.5, 'RESEARCH', 'REQUIRED'),
  ('00000000-0000-0000-0000-000000004122', '00000000-0000-0000-0000-000000000401', 'ECON-GA 4122', 'Research Practicum II', 1.5, 'RESEARCH', 'REQUIRED')
on conflict do nothing;

insert into public.sources (
  source_id, publisher, title, url, reliability_tier, source_type
) values
  (
    '00000000-0000-0000-0000-000000000601',
    'U.S. Department of Education',
    'College Scorecard: New York University',
    'https://collegescorecard.ed.gov/school/?193900-New-York-University',
    'TIER_B_GOVERNMENT',
    'GOVERNMENT_PROFILE'
  ),
  (
    '00000000-0000-0000-0000-000000000602',
    'New York University',
    'Quantitative Economics (MS) — NYU Bulletin',
    'https://bulletins.nyu.edu/graduate/arts-science/programs/quantitative-economics-ms/quantitative-economics-ms.pdf',
    'TIER_A_OFFICIAL',
    'OFFICIAL_BULLETIN'
  ),
  (
    '00000000-0000-0000-0000-000000000603',
    'New York University Department of Economics',
    'MS in Quantitative Economics — Apply',
    'https://as.nyu.edu/departments/econ/graduate/ms/apply.html',
    'TIER_A_OFFICIAL',
    'OFFICIAL_PROGRAM_PAGE'
  ),
  (
    '00000000-0000-0000-0000-000000000604',
    'New York University Graduate School of Arts and Science',
    'Economics — Program Requirements and Deadlines',
    'https://gsas.nyu.edu/admissions/arc/programs/economics.html',
    'TIER_A_OFFICIAL',
    'OFFICIAL_ADMISSIONS_PAGE'
  ),
  (
    '00000000-0000-0000-0000-000000000605',
    'New York University Graduate School of Arts and Science',
    'Graduate School of Arts and Science',
    'https://gsas.nyu.edu/',
    'TIER_A_OFFICIAL',
    'OFFICIAL_SCHOOL_PAGE'
  ),
  (
    '00000000-0000-0000-0000-000000000606',
    'New York University Stern School of Business',
    'NYU Stern School of Business',
    'https://www.stern.nyu.edu/',
    'TIER_A_OFFICIAL',
    'OFFICIAL_SCHOOL_PAGE'
  )
on conflict do nothing;

insert into public.evidence_items (
  evidence_id, source_id, excerpt, locator, cycle_context,
  retrieved_at, verified_at, content_hash
) values
  (
    '00000000-0000-0000-0000-000000000701',
    '00000000-0000-0000-0000-000000000601',
    'College Scorecard school profile for New York University, institution ID (UNITID) 193900.',
    'School profile URL and institution identifier',
    'Institution identity',
    timestamptz '2026-08-20 09:44:00+00',
    timestamptz '2026-08-20 09:44:00+00',
    md5('NYU UNITID 193900')
  ),
  (
    '00000000-0000-0000-0000-000000000702',
    '00000000-0000-0000-0000-000000000602',
    'NYSED: 41911 HEGIS: 0506.00 CIP: 45.0603',
    'Program header',
    'Current NYU Bulletin program identity',
    timestamptz '2026-08-20 09:44:00+00',
    timestamptz '2026-08-20 09:44:00+00',
    md5('NYSED: 41911 HEGIS: 0506.00 CIP: 45.0603')
  ),
  (
    '00000000-0000-0000-0000-000000000703',
    '00000000-0000-0000-0000-000000000602',
    'Drawing on the combined resources of the Economics Departments of the Faculty of Arts and Science and NYU’s Stern School ... Our ten month program ... Starting in July and ending in May ... Our STEM certified MS in Quantitative Economics ... The final two modules include a “capstone experience”.',
    'Program Description',
    'Current NYU Bulletin program description',
    timestamptz '2026-08-20 09:44:00+00',
    timestamptz '2026-08-20 09:44:00+00',
    md5('MSQE GSAS Stern ten month July May STEM capstone')
  ),
  (
    '00000000-0000-0000-0000-000000000704',
    '00000000-0000-0000-0000-000000000602',
    'Major Requirements list 18 required 1.5-credit courses, including ECON-GA 4011 through ECON-GA 4122; Other Elective Credits: 6; Total Credits: 33.',
    'Program Requirements table',
    'Current NYU Bulletin curriculum',
    timestamptz '2026-08-20 09:44:00+00',
    timestamptz '2026-08-20 09:44:00+00',
    md5('MSQE 18 required courses 6 elective credits total 33')
  ),
  (
    '00000000-0000-0000-0000-000000000705',
    '00000000-0000-0000-0000-000000000603',
    'The application for the 2026-27 academic year will open on October 31, 2025. Our admission requirements are: ... GRE or GMAT ... Admissions are on a rolling basis ... The deadline for applications will be February 15, 2026.',
    'Apply page, admissions requirements',
    'MSQE 2026-27',
    timestamptz '2026-08-20 09:44:00+00',
    timestamptz '2026-08-20 09:44:00+00',
    md5('MSQE 2026-27 GRE or GMAT rolling February 15 2026')
  ),
  (
    '00000000-0000-0000-0000-000000000706',
    '00000000-0000-0000-0000-000000000604',
    'M.S. Program — February 15: Summer admission. GRE or GMAT Required — M.S. in Quantitative Economics — Applicants may choose to submit either the GMAT or the GRE general test.',
    'M.S. Program and Test Scores sections',
    'MS in Quantitative Economics; GSAS page last updated May 2026',
    timestamptz '2026-08-20 09:44:00+00',
    timestamptz '2026-08-20 09:44:00+00',
    md5('GSAS MSQE February 15 Summer GRE or GMAT required')
  ),
  (
    '00000000-0000-0000-0000-000000000707',
    '00000000-0000-0000-0000-000000000605',
    'New York University Graduate School of Arts and Science.',
    'Official school homepage',
    'Persistent school identity',
    timestamptz '2026-08-20 09:44:00+00',
    timestamptz '2026-08-20 09:44:00+00',
    md5('NYU Graduate School of Arts and Science')
  ),
  (
    '00000000-0000-0000-0000-000000000708',
    '00000000-0000-0000-0000-000000000606',
    'New York University Stern School of Business.',
    'Official school homepage',
    'Persistent school identity',
    timestamptz '2026-08-20 09:44:00+00',
    timestamptz '2026-08-20 09:44:00+00',
    md5('NYU Stern School of Business')
  )
on conflict do nothing;

insert into public.field_observations (
  observation_id, record_type, record_id, field_name, observed_value,
  knowledge_status, evidence_id, notes
) values
  ('00000000-0000-0000-0000-000000000812', 'PROGRAM_VERSION', '00000000-0000-0000-0000-000000000401', 'delivery_mode', null, 'NOT_YET_VERIFIED', null, 'No exact delivery-mode claim was verified for this release.'),
  ('00000000-0000-0000-0000-000000000813', 'PROGRAM_VERSION', '00000000-0000-0000-0000-000000000401', 'full_time', null, 'NOT_YET_VERIFIED', null, 'Program pace does not by itself establish an official full-time classification.'),
  ('00000000-0000-0000-0000-000000000814', 'PROGRAM_ADMISSION', '00000000-0000-0000-0000-000000000402', 'minimum_gpa', null, 'NOT_PUBLICLY_DISCLOSED', null, 'No minimum GPA is stated on the captured official admissions pages.'),
  ('00000000-0000-0000-0000-000000000815', 'PROGRAM_ADMISSION', '00000000-0000-0000-0000-000000000402', 'average_gpa', null, 'NOT_PUBLICLY_DISCLOSED', null, 'No average GPA is stated on the captured official admissions pages.'),
  ('00000000-0000-0000-0000-000000000816', 'PROGRAM_ADMISSION', '00000000-0000-0000-0000-000000000402', 'gre_quant_minimum', null, 'NOT_PUBLICLY_DISCLOSED', null, 'No GRE quantitative minimum is stated on the captured official admissions pages.'),
  ('00000000-0000-0000-0000-000000000817', 'PROGRAM_ADMISSION', '00000000-0000-0000-0000-000000000402', 'gre_quant_average', null, 'NOT_PUBLICLY_DISCLOSED', null, 'No GRE quantitative average is stated on the captured official admissions pages.'),
  ('00000000-0000-0000-0000-000000000818', 'PROGRAM_ADMISSION', '00000000-0000-0000-0000-000000000402', 'toefl_minimum', null, 'NOT_YET_VERIFIED', null, 'English-test waiver details were linked but score minimums were not verified.'),
  ('00000000-0000-0000-0000-000000000819', 'PROGRAM_ADMISSION', '00000000-0000-0000-0000-000000000402', 'ielts_minimum', null, 'NOT_YET_VERIFIED', null, 'English-test waiver details were linked but score minimums were not verified.'),
  ('00000000-0000-0000-0000-000000000820', 'PROGRAM_ADMISSION', '00000000-0000-0000-0000-000000000402', 'application_fee', null, 'NOT_YET_VERIFIED', null, 'Program-cycle-specific application fee was not verified.'),
  ('00000000-0000-0000-0000-000000000821', 'PROGRAM_COST', '00000000-0000-0000-0000-000000000404', 'tuition_amount', null, 'NOT_YET_VERIFIED', null, 'Program-specific 2026-27 tuition was not verified.'),
  ('00000000-0000-0000-0000-000000000822', 'PROGRAM_COST', '00000000-0000-0000-0000-000000000404', 'mandatory_fees', null, 'NOT_YET_VERIFIED', null, 'Program-specific mandatory fees were not verified.'),
  ('00000000-0000-0000-0000-000000000823', 'PROGRAM_COST', '00000000-0000-0000-0000-000000000404', 'estimated_living_cost', null, 'NOT_YET_VERIFIED', null, 'A directly applicable program-level living-cost estimate was not verified.'),
  ('00000000-0000-0000-0000-000000000824', 'PROGRAM_COST', '00000000-0000-0000-0000-000000000404', 'estimated_total_cost', null, 'NOT_YET_VERIFIED', null, 'A directly applicable total program cost was not verified.'),
  ('00000000-0000-0000-0000-000000000825', 'PROGRAM_COST', '00000000-0000-0000-0000-000000000404', 'scholarship_available', null, 'NOT_YET_VERIFIED', null, 'Program-specific scholarship availability was not verified.')
on conflict do nothing;

insert into public.field_observations (
  observation_id, record_type, record_id, field_name, observed_value,
  knowledge_status, evidence_id, notes
)
with records as (
  select
    'UNIVERSITY'::public.catalog_record_type as record_type,
    university_id as record_id,
    to_jsonb(university) as record_data
  from public.universities university
  where university_id = '00000000-0000-0000-0000-000000000101'
  union all
  select 'SCHOOL', school_id, to_jsonb(school)
  from public.schools school
  where university_id = '00000000-0000-0000-0000-000000000101'
  union all
  select 'PROGRAM', program_id, to_jsonb(program)
  from public.programs program
  where program_id = '00000000-0000-0000-0000-000000000301'
  union all
  select 'PROGRAM_SCHOOL', program_school_id, to_jsonb(program_school)
  from public.program_schools program_school
  where program_id = '00000000-0000-0000-0000-000000000301'
  union all
  select 'PROGRAM_VERSION', program_version_id, to_jsonb(program_version)
  from public.program_versions program_version
  where program_version_id = '00000000-0000-0000-0000-000000000401'
  union all
  select 'PROGRAM_ADMISSION', admission_id, to_jsonb(admission)
  from public.program_admissions admission
  where admission_id = '00000000-0000-0000-0000-000000000402'
  union all
  select 'PROGRAM_COURSE', course_id, to_jsonb(course)
  from public.program_courses course
  where program_version_id = '00000000-0000-0000-0000-000000000401'
  union all
  select 'PROGRAM_COST', cost_id, to_jsonb(cost)
  from public.program_costs cost
  where cost_id = '00000000-0000-0000-0000-000000000404'
  union all
  select 'PROGRAM_DEADLINE', deadline_id, to_jsonb(deadline)
  from public.program_deadlines deadline
  where deadline_id = '00000000-0000-0000-0000-000000000403'
),
record_fields as (
  select
    record_type,
    record_id,
    field.key as field_name,
    field.value as observed_value
  from records
  cross join lateral jsonb_each(record_data) field
  where field.value <> 'null'::jsonb
    and field.key <> public.catalog_primary_key(record_type)
    and field.key not in (
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
)
select
  md5(record_id::text || ':' || field_name)::uuid,
  record_type,
  record_id,
  field_name,
  observed_value,
  'KNOWN'::public.knowledge_status,
  case
    when record_type = 'UNIVERSITY' then '00000000-0000-0000-0000-000000000701'::uuid
    when record_type = 'SCHOOL'
      and record_id = '00000000-0000-0000-0000-000000000201'
      then '00000000-0000-0000-0000-000000000707'::uuid
    when record_type = 'SCHOOL'
      then '00000000-0000-0000-0000-000000000708'::uuid
    when record_type in ('PROGRAM', 'PROGRAM_SCHOOL')
      and field_name = 'cip_code'
      then '00000000-0000-0000-0000-000000000702'::uuid
    when record_type in ('PROGRAM', 'PROGRAM_SCHOOL')
      then '00000000-0000-0000-0000-000000000703'::uuid
    when record_type = 'PROGRAM_VERSION'
      and field_name = 'credits_required'
      then '00000000-0000-0000-0000-000000000704'::uuid
    when record_type = 'PROGRAM_VERSION'
      and field_name in (
        'admission_cycle_start_year',
        'admission_cycle_end_year',
        'academic_year_start',
        'academic_year_end',
        'entry_term',
        'entry_year'
      )
      then '00000000-0000-0000-0000-000000000705'::uuid
    when record_type = 'PROGRAM_VERSION'
      then '00000000-0000-0000-0000-000000000703'::uuid
    when record_type in ('PROGRAM_ADMISSION', 'PROGRAM_DEADLINE', 'PROGRAM_COST')
      then '00000000-0000-0000-0000-000000000705'::uuid
    when record_type = 'PROGRAM_COURSE'
      then '00000000-0000-0000-0000-000000000704'::uuid
  end,
  'Golden-record canonical value selected from the cited official evidence.'
from record_fields
on conflict do nothing;

do $$
declare
  observation record;
begin
  for observation in
    select observation_id
    from public.field_observations
    order by created_at, observation_id
  loop
    perform public.select_field_observation(observation.observation_id, 'golden-record-migration');
  end loop;
end;
$$;

commit;
