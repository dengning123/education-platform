begin;

do $test$
declare
  actual integer;
  blocked boolean;
  v_scope uuid;
  v_obs uuid;
  v_assertion uuid;
begin
  select count(*) into actual from public.universities;
  if actual <> 1 then
    raise exception 'Expected 1 golden university, found %', actual;
  end if;

  select count(*) into actual
  from public.programs
  where program_name = 'MS in Quantitative Economics'
    and cip_code = '45.0603';
  if actual <> 1 then
    raise exception 'NYU MSQE canonical CIP is missing or incorrect';
  end if;

  select count(*) into actual
  from public.canonical_field_selections selection
  join public.field_observations observation
    on observation.observation_id = selection.observation_id
  join public.evidence_items evidence
    on evidence.evidence_id = observation.evidence_id
  join public.sources source
    on source.source_id = evidence.source_id
  where selection.record_type = 'PROGRAM'
    and selection.record_id = '00000000-0000-0000-0000-000000000301'
    and selection.field_name = 'cip_code'
    and observation.observed_value = '"45.0603"'::jsonb
    and source.reliability_tier = 'TIER_A_OFFICIAL'
    and source.url like 'https://bulletins.nyu.edu/%';
  if actual <> 1 then
    raise exception 'CIP 45.0603 lacks accepted Tier-A Bulletin evidence';
  end if;

  select count(*) into actual
  from public.program_schools
  where program_id = '00000000-0000-0000-0000-000000000301'
    and relationship_role in ('PRIMARY_ADMINISTRATIVE', 'JOINT_DELIVERY');
  if actual <> 2 then
    raise exception 'Expected GSAS and Stern program relationships, found %', actual;
  end if;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and (
        (table_name = 'programs' and column_name = 'primary_school_id')
        or (table_name = 'program_schools' and column_name = 'is_primary')
      )
  ) then
    raise exception 'Duplicate primary-school source-of-truth columns still exist';
  end if;

  select count(*) into actual
  from public.program_schools
  where program_id = '00000000-0000-0000-0000-000000000301'
    and relationship_role = 'PRIMARY_ADMINISTRATIVE'
    and retired_at is null;
  if actual <> 1 then
    raise exception 'Expected exactly one active primary administrative school, found %', actual;
  end if;

  select count(*) into actual
  from public.program_versions
  where program_version_id = '00000000-0000-0000-0000-000000000401'
    and admission_cycle_start_year = 2026
    and admission_cycle_end_year = 2027
    and admission_cycle = '2026-27'
    and academic_year_start = 2026
    and academic_year_end = 2027
    and academic_year = '2026-27'
    and entry_term = 'SUMMER'
    and entry_year = 2026
    and start_month = 7
    and duration_months = 10
    and credits_required = 33
    and stem_status is true
    and capstone_required is true
    and verification_status = 'PARTIALLY_VERIFIED';
  if actual <> 1 then
    raise exception 'Program-version timing or verified facts are incorrect';
  end if;

  select count(*) into actual
  from public.program_admissions
  where program_version_id = '00000000-0000-0000-0000-000000000401'
    and gre_policy = 'REQUIRED_AS_ALTERNATIVE'
    and gmat_policy = 'REQUIRED_AS_ALTERNATIVE';
  if actual <> 1 then
    raise exception 'GRE-or-GMAT policy is not represented as an alternative requirement';
  end if;

  select count(*) into actual
  from public.program_deadlines
  where program_version_id = '00000000-0000-0000-0000-000000000401'
    and deadline_type = 'GENERAL'
    and deadline_date = date '2026-02-15'
    and rolling_admission is true;
  if actual <> 1 then
    raise exception 'Verified deadline or rolling-admission fact is incorrect';
  end if;

  select count(*) into actual
  from public.program_courses
  where program_version_id = '00000000-0000-0000-0000-000000000401'
    and required_status = 'REQUIRED';
  if actual <> 18 then
    raise exception 'Expected 18 required courses, found %', actual;
  end if;

  select count(*) into actual
  from (
    select sum(credits) as required_credits
    from public.program_courses
    where program_version_id = '00000000-0000-0000-0000-000000000401'
      and required_status = 'REQUIRED'
    having sum(credits) = 27
  ) totals;
  if actual <> 1 then
    raise exception 'Required-course credits should total 27, excluding 6 elective credits';
  end if;

  select count(*) into actual
  from public.field_observations
  where record_id in (
    '00000000-0000-0000-0000-000000000401',
    '00000000-0000-0000-0000-000000000402',
    '00000000-0000-0000-0000-000000000404'
  )
    and knowledge_status in ('NOT_PUBLICLY_DISCLOSED', 'NOT_YET_VERIFIED')
    and observed_value is null;
  if actual <> 14 then
    raise exception 'Expected 14 explicit unverified/undisclosed fields, found %', actual;
  end if;

  select count(*) into actual
  from public.field_observations
  where knowledge_status = 'SOURCE_CONFLICT';
  if actual <> 0 then
    raise exception 'Golden record unexpectedly contains source conflicts';
  end if;

  select count(*) into actual from public.program_prerequisites;
  if actual <> 0 then
    raise exception 'Unverified admissions prerequisites must not be seeded';
  end if;

  select count(*) into actual
  from public.canonical_field_selections selection
  join public.field_observations observation
    on observation.observation_id = selection.observation_id
   and observation.record_type = selection.record_type
   and observation.record_id = selection.record_id
   and observation.field_name = selection.field_name
  where observation.knowledge_status = 'KNOWN';
  if actual <> 161 then
    raise exception 'Expected 161 accepted KNOWN canonical observations, found %', actual;
  end if;

  select count(*) into actual
  from public.canonical_field_selections selection
  join public.field_observations observation
    on observation.observation_id = selection.observation_id
   and observation.record_type = selection.record_type
   and observation.record_id = selection.record_id
   and observation.field_name = selection.field_name;
  if actual <> 175 then
    raise exception 'Expected 175 selected current field states, found %', actual;
  end if;

  blocked := false;
  begin
    update public.programs
      set cip_code = '00.0000'
      where program_id = '00000000-0000-0000-0000-000000000301';
  exception when others then
    blocked := true;
  end;
  if not blocked then
    raise exception 'Direct canonical updates were not blocked';
  end if;

  blocked := false;
  begin
    insert into public.universities (
      university_id,
      name,
      country
    ) values (
      'ffffffff-ffff-ffff-ffff-fffffffffff1',
      'Unproven University',
      'United States'
    );
    set constraints all immediate;
  exception when others then
    blocked := true;
  end;
  if not blocked then
    raise exception 'Canonical INSERT without accepted evidence was not blocked';
  end if;

  blocked := false;
  begin
    delete from public.programs
    where program_id = '00000000-0000-0000-0000-000000000301';
  exception when others then
    blocked := true;
  end;
  if not blocked then
    raise exception 'Physical deletion of a historical canonical record was not blocked';
  end if;

  select count(*) into actual
  from pg_constraint constraint_record
  join pg_class table_record
    on table_record.oid = constraint_record.conrelid
  join pg_namespace namespace_record
    on namespace_record.oid = table_record.relnamespace
  where namespace_record.nspname = 'public'
    and constraint_record.contype = 'f'
    and table_record.relname in (
      'schools',
      'programs',
      'program_schools',
      'program_versions',
      'program_admissions',
      'program_prerequisites',
      'program_courses',
      'program_costs',
      'program_deadlines',
      'program_derived_features'
    )
    and constraint_record.confdeltype <> 'r';
  if actual <> 0 then
    raise exception 'Historically important foreign keys still permit destructive parent deletion';
  end if;

  blocked := false;
  begin
    update public.field_observations
      set notes = 'mutated'
      where observation_id = '00000000-0000-0000-0000-000000000812';
  exception when others then
    blocked := true;
  end;
  if not blocked then
    raise exception 'Field observations were not append-only';
  end if;

  blocked := false;
  begin
    delete from public.audit_events
    where audit_event_id = (select min(audit_event_id) from public.audit_events);
  exception when others then
    blocked := true;
  end;
  if not blocked then
    raise exception 'Audit events were not append-only';
  end if;

  insert into public.field_observations (
    observation_id,
    record_type,
    record_id,
    field_name,
    observed_value,
    knowledge_status,
    evidence_id,
    notes
  ) values (
    'ffffffff-ffff-ffff-ffff-fffffffffff2',
    'PROGRAM',
    '00000000-0000-0000-0000-000000000301',
    'cip_code',
    to_jsonb('45.0603'::text),
    'SOURCE_CONFLICT',
    '00000000-0000-0000-0000-000000000702',
    'Test-only unresolved conflict.'
  );

  v_scope := public.create_evidence_scope(
    '00000000-0000-0000-0000-000000000702',
    'PROGRAM',
    '00000000-0000-0000-0000-000000000301',
    'cip_code',
    'UNSPECIFIED',
    'UNSPECIFIED',
    'UNSPECIFIED'
  );
  perform public.review_evidence_applicability(
    v_scope, 'REVIEWED_APPLICABLE', 'test-suite', 'test applicability'
  );
  insert into public.field_observation_applicability (observation_id, assertion_id)
  values (
    'ffffffff-ffff-ffff-ffff-fffffffffff2',
    (select h.assertion_id from public.evidence_applicability_heads h
     where h.scope_id = v_scope)
  );
  perform public.select_field_observation(
    'ffffffff-ffff-ffff-ffff-fffffffffff2',
    'test-suite'
  );
  if (select cip_code from public.programs
      where program_id = '00000000-0000-0000-0000-000000000301') is not null then
    raise exception 'SOURCE_CONFLICT did not clear the canonical value';
  end if;
  if not exists (
    select 1
    from public.canonical_field_selections
    where record_type = 'PROGRAM'
      and record_id = '00000000-0000-0000-0000-000000000301'
      and field_name = 'cip_code'
      and observation_id = 'ffffffff-ffff-ffff-ffff-fffffffffff2'
  ) then
    raise exception 'SOURCE_CONFLICT did not become the selected canonical state';
  end if;

  v_obs := public.create_field_observation(
    'PROGRAM',
    '00000000-0000-0000-0000-000000000301',
    'cip_code',
    to_jsonb('45.0603'::text),
    'KNOWN',
    '00000000-0000-0000-0000-000000000702',
    null,
    'Test-only restored KNOWN CIP after SOURCE_CONFLICT.',
    (select h.assertion_id from public.evidence_applicability_heads h
     where h.scope_id = v_scope)
  );
  perform public.accept_field_observation(
    v_obs,
    'test-suite'
  );
  if (select cip_code from public.programs
      where program_id = '00000000-0000-0000-0000-000000000301') <> '45.0603' then
    raise exception 'KNOWN evidence did not restore the canonical value';
  end if;

  select count(*) into actual
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'external_metrics'
    and column_name in ('granularity', 'applicability', 'population_scope', 'applicability_rationale')
    and is_nullable = 'NO';
  if actual <> 4 then
    raise exception 'External metric scope/applicability fields are not mandatory';
  end if;

  select count(*) into actual
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'program_derived_features'
    and column_name in ('model_version', 'calculated_at')
    and is_nullable = 'NO';
  if actual <> 2 then
    raise exception 'Derived features do not require model version and calculation time';
  end if;

  insert into public.program_derived_features (
    program_version_id,
    feature_name,
    numeric_value,
    model_version,
    calculated_at
  ) values (
    '00000000-0000-0000-0000-000000000401',
    'test_only_quant_intensity',
    91,
    'test-model-v1',
    now()
  );

  insert into public.external_metrics (
    subject_record_type,
    subject_record_id,
    metric_name,
    numeric_value,
    granularity,
    applicability,
    population_scope,
    applicability_rationale,
    evidence_id
  ) values (
    'UNIVERSITY',
    '00000000-0000-0000-0000-000000000101',
    'test_only_institution_metric',
    1,
    'INSTITUTION',
    'CONTEXT_ONLY',
    'ALL_STUDENTS',
    'Institution context is not a program-level fact.',
    '00000000-0000-0000-0000-000000000701'
  );

  blocked := false;
  begin
    insert into public.external_metrics (
      subject_record_type,
      subject_record_id,
      metric_name,
      numeric_value,
      granularity,
      applicability,
      population_scope,
      applicability_rationale,
      evidence_id
    ) values (
      'PROGRAM',
      'ffffffff-ffff-ffff-ffff-ffffffffffff',
      'invalid_subject_test',
      1,
      'PROGRAM',
      'DIRECT',
      'PROGRAM_COHORT',
      'This row must be rejected because the program does not exist.',
      '00000000-0000-0000-0000-000000000702'
    );
  exception when others then
    blocked := true;
  end;
  if not blocked then
    raise exception 'External metrics accepted a nonexistent subject record';
  end if;

  blocked := false;
  begin
    insert into public.external_metrics (
      subject_record_type,
      subject_record_id,
      metric_name,
      numeric_value,
      granularity,
      applicability,
      population_scope,
      applicability_rationale,
      evidence_id
    ) values (
      'PROGRAM',
      '00000000-0000-0000-0000-000000000301',
      'invalid_direct_institution_metric',
      1,
      'INSTITUTION',
      'DIRECT',
      'ALL_STUDENTS',
      'Must be rejected because institution data is not a direct program fact.',
      '00000000-0000-0000-0000-000000000701'
    );
  exception when others then
    blocked := true;
  end;
  if not blocked then
    raise exception 'Institution-level data was accepted as a DIRECT program fact';
  end if;

  blocked := false;
  begin
    insert into public.external_metrics (
      subject_record_type,
      subject_record_id,
      metric_name,
      numeric_value,
      granularity,
      applicability,
      population_scope,
      applicability_rationale,
      evidence_id
    ) values (
      'PROGRAM',
      '00000000-0000-0000-0000-000000000301',
      'invalid_direct_undergraduate_metric',
      1,
      'PROGRAM',
      'DIRECT',
      'UNDERGRADUATE',
      'Must be rejected because undergraduate scope is not the program cohort.',
      '00000000-0000-0000-0000-000000000701'
    );
  exception when others then
    blocked := true;
  end;
  if not blocked then
    raise exception 'Undergraduate data was accepted as a DIRECT program fact';
  end if;

  blocked := false;
  begin
    insert into public.program_versions (
      program_version_id,
      program_id,
      admission_cycle_start_year,
      admission_cycle_end_year,
      academic_year_start,
      academic_year_end,
      entry_term,
      entry_year,
      verification_status
    ) values (
      'ffffffff-ffff-ffff-ffff-fffffffffff3',
      '00000000-0000-0000-0000-000000000301',
      2027,
      2029,
      2027,
      2028,
      'SUMMER',
      2027,
      'UNVERIFIED'
    );
  exception when others then
    blocked := true;
  end;
  if not blocked then
    raise exception 'Non-consecutive admission cycle years were accepted';
  end if;

  perform public.retire_catalog_record(
    'PROGRAM',
    '00000000-0000-0000-0000-000000000301',
    'Test-only retirement',
    'test-suite'
  );
  if not exists (
    select 1
    from public.programs
    where program_id = '00000000-0000-0000-0000-000000000301'
      and retired_at is not null
      and retirement_reason like 'Test-only retirement%'
  ) then
    raise exception 'Controlled retirement did not preserve and retire the program row';
  end if;

  if not exists (select 1 from public.audit_events) then
    raise exception 'Expected audit events from golden-record creation';
  end if;
end;
$test$;

-- Verify a second historical version can coexist without overwriting the golden cycle.
insert into public.program_versions (
  program_version_id,
  program_id,
  admission_cycle_start_year,
  admission_cycle_end_year,
  academic_year_start,
  academic_year_end,
  entry_term,
  entry_year,
  verification_status
) values (
  '00000000-0000-0000-0000-000000000499',
  '00000000-0000-0000-0000-000000000301',
  2027,
  2028,
  2027,
  2028,
  'SUMMER',
  2027,
  'UNVERIFIED'
);

insert into public.field_observations (
  observation_id,
  record_type,
  record_id,
  field_name,
  observed_value,
  knowledge_status,
  evidence_id,
  notes
)
select
  md5('00000000-0000-0000-0000-000000000499:' || field.key)::uuid,
  'PROGRAM_VERSION',
  '00000000-0000-0000-0000-000000000499',
  field.key,
  field.value,
  'KNOWN',
  '00000000-0000-0000-0000-000000000705',
  'Test-only evidence-backed historical version.'
from public.program_versions version
cross join lateral jsonb_each(to_jsonb(version)) field
where version.program_version_id = '00000000-0000-0000-0000-000000000499'
  and field.value <> 'null'::jsonb
  and field.key in (
    'program_id',
    'admission_cycle_start_year',
    'admission_cycle_end_year',
    'academic_year_start',
    'academic_year_end',
    'entry_term',
    'entry_year'
  );

do $test$
declare
  observation record;
  v_scope uuid;
begin
  for observation in
    select *
    from public.field_observations
    where record_id = '00000000-0000-0000-0000-000000000499'
  loop
    v_scope := public.create_evidence_scope(
      observation.evidence_id,
      observation.record_type,
      observation.record_id,
      observation.field_name,
      'UNSPECIFIED',
      'UNSPECIFIED',
      'UNSPECIFIED'
    );
    perform public.review_evidence_applicability(
      v_scope, 'REVIEWED_APPLICABLE', 'test-suite', 'test applicability'
    );
    insert into public.field_observation_applicability (observation_id, assertion_id)
    values (
      observation.observation_id,
      (select h.assertion_id from public.evidence_applicability_heads h
       where h.scope_id = v_scope)
    );
    perform public.accept_field_observation(observation.observation_id, 'test-suite');
  end loop;
end;
$test$;

set constraints all immediate;

do $test$
begin
  if (select count(*) from public.program_versions
      where program_id = '00000000-0000-0000-0000-000000000301') <> 2 then
    raise exception 'Program-version history cannot coexist';
  end if;

  perform public.retire_catalog_record(
    'PROGRAM_VERSION',
    '00000000-0000-0000-0000-000000000499',
    'Test-only historical version retirement',
    'test-suite'
  );
  if not exists (
    select 1
    from public.program_versions
    where program_version_id = '00000000-0000-0000-0000-000000000499'
      and retired_at is not null
  ) then
    raise exception 'Historical program version was not preserved during retirement';
  end if;
end;
$test$;

rollback;
