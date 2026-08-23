-- Phase 4B-1B.0: authenticated Profile draft/readiness/freeze capability.
-- Additive over frozen migrations 001-018. Application/Outcome is reserved
-- for Migration 020 and is deliberately absent here.

begin;

alter table public.student_profile_versions
  add column product_managed boolean not null default false,
  add column profile_revision bigint not null default 0,
  add constraint student_profile_versions_revision_nonnegative
    check (profile_revision >= 0);

comment on column public.student_profile_versions.product_managed is
  'True only for drafts created through the Phase 4B Profile capability. Historical rows remain false.';
comment on column public.student_profile_versions.profile_revision is
  'Monotonic optimistic-lock token for browser-authorized Profile capability mutations.';

create unique index student_profile_versions_one_product_draft
  on public.student_profile_versions (student_id)
  where product_managed and status = 'DRAFT';

create type public.profile_draft_command_v019 as enum (
  'COMPLETENESS_UPSERT',
  'COMPLETENESS_DELETE',
  'EVIDENCE_CREATE',
  'EVIDENCE_UPDATE',
  'EVIDENCE_DELETE',
  'DEGREE_CREATE',
  'DEGREE_UPDATE',
  'DEGREE_DELETE',
  'COURSE_CREATE',
  'COURSE_UPDATE',
  'COURSE_DELETE',
  'TEST_SCORE_CREATE',
  'TEST_SCORE_UPDATE',
  'TEST_SCORE_DELETE',
  'EXPERIENCE_CREATE',
  'EXPERIENCE_UPDATE',
  'EXPERIENCE_DELETE',
  'SKILL_CREATE',
  'SKILL_UPDATE',
  'SKILL_DELETE',
  'EXPERIENCE_SKILL_LINK',
  'EXPERIENCE_SKILL_UNLINK',
  'GOAL_CREATE',
  'GOAL_UPDATE',
  'GOAL_DELETE',
  'PREFERENCE_CREATE',
  'PREFERENCE_UPDATE',
  'PREFERENCE_DELETE'
);

create table private.profile_capability_operations_v019 (
  student_id uuid not null
    references public.students(student_id) on delete cascade,
  operation_id uuid not null,
  operation_kind text not null,
  command_code text,
  request_fingerprint text not null,
  result_document jsonb not null,
  created_at timestamptz not null default now(),
  primary key (student_id, operation_id),
  constraint profile_operations_kind_closed
    check (operation_kind in ('CREATE_OR_RESUME', 'MUTATE', 'FREEZE')),
  constraint profile_operations_command_shape
    check (
      (operation_kind = 'MUTATE' and command_code is not null)
      or (operation_kind <> 'MUTATE' and command_code is null)
    ),
  constraint profile_operations_fingerprint_format
    check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  constraint profile_operations_result_object
    check (jsonb_typeof(result_document) = 'object')
);

alter table private.profile_capability_operations_v019 enable row level security;

create policy profile_capability_operations_student_executor
  on private.profile_capability_operations_v019
  for all to foundation_student_executor
  using (current_user = 'foundation_student_executor')
  with check (current_user = 'foundation_student_executor');

grant select, insert, update, delete
  on private.profile_capability_operations_v019
  to foundation_student_executor;

-- The browser subject must be derived through the hosted auth.uid() contract.
-- The non-login definer receives only the schema/function capabilities needed
-- for that call; it receives no Auth table privilege.
grant usage on schema auth to foundation_student_executor;
grant execute on function auth.uid() to foundation_student_executor;

revoke all on private.profile_capability_operations_v019
  from public, anon, authenticated, service_role, authenticator,
       foundation_catalog_executor, foundation_evaluation_executor;

create or replace function private.profile_require_auth_subject_v019()
returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_auth_user_id uuid;
begin
  v_auth_user_id := auth.uid();
  if v_auth_user_id is null then
    raise exception using errcode = '42501', message = 'PROFILE_AUTH_REQUIRED';
  end if;
  return v_auth_user_id;
end;
$function$;

create or replace function private.profile_bootstrap_student_v019()
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_auth_user_id uuid;
  v_student_id uuid;
  v_privacy_state public.student_privacy_state;
begin
  v_auth_user_id := private.profile_require_auth_subject_v019();
  perform pg_advisory_xact_lock(
    hashtextextended('profile-auth:' || lower(v_auth_user_id::text), 0)
  );

  select identity.student_id, student.privacy_state
  into v_student_id, v_privacy_state
  from private.student_identities identity
  join public.students student using (student_id)
  where identity.auth_user_id = v_auth_user_id;

  if v_student_id is not null then
    if v_privacy_state is distinct from 'ACTIVE' then
      raise exception using errcode = '55000', message = 'PROFILE_ACCOUNT_INACTIVE';
    end if;
    return v_student_id;
  end if;

  v_student_id := extensions.gen_random_uuid();
  perform public.create_student(v_student_id);
  insert into private.student_identities (auth_user_id, student_id)
  values (v_auth_user_id, v_student_id);
  return v_student_id;
end;
$function$;

create or replace function private.profile_student_for_auth_v019()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  select identity.student_id
  from private.student_identities identity
  join public.students student using (student_id)
  where identity.auth_user_id = auth.uid()
    and student.privacy_state = 'ACTIVE'
$function$;

create or replace function private.profile_assert_payload_keys_v019(
  p_payload jsonb,
  p_allowed_keys text[],
  p_required_keys text[] default array[]::text[]
)
returns void
language plpgsql
immutable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_key text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023', message = 'PROFILE_PAYLOAD_OBJECT_REQUIRED';
  end if;
  select key into v_key
  from jsonb_object_keys(p_payload) key
  where not (key = any(p_allowed_keys))
  order by key
  limit 1;
  if v_key is not null then
    raise exception using errcode = '22023',
      message = 'PROFILE_UNKNOWN_FIELD', detail = v_key;
  end if;
  select key into v_key
  from unnest(p_required_keys) key
  where not (p_payload ? key) or p_payload -> key = 'null'::jsonb
  order by key
  limit 1;
  if v_key is not null then
    raise exception using errcode = '22023',
      message = 'PROFILE_REQUIRED_FIELD_MISSING', detail = v_key;
  end if;
end;
$function$;

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
  v_allowed constant text[] := array[
    'quantitative', 'verbal', 'analyticalWriting', 'integratedReasoning',
    'reading', 'listening', 'speaking', 'writing', 'math', 'english',
    'science', 'composite'
  ];
begin
  if p_scores is null or jsonb_typeof(p_scores) <> 'object' then
    raise exception using errcode = '22023', message = 'PROFILE_SECTION_SCORES_OBJECT_REQUIRED';
  end if;
  for v_key, v_value in select key, value from jsonb_each(p_scores)
  loop
    if not (v_key = any(v_allowed)) then
      raise exception using errcode = '22023',
        message = 'PROFILE_UNKNOWN_SECTION_SCORE', detail = v_key;
    end if;
    if jsonb_typeof(v_value) <> 'number' or (v_value #>> '{}')::numeric < 0 then
      raise exception using errcode = '22023', message = 'PROFILE_INVALID_SECTION_SCORE';
    end if;
  end loop;
  return p_scores;
end;
$function$;

create or replace function private.profile_validate_preference_value_v019(
  p_type public.preference_type,
  p_value jsonb
)
returns jsonb
language plpgsql
immutable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_item jsonb;
  v_text text;
  v_min numeric;
  v_max numeric;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'object' then
    raise exception using errcode = '22023', message = 'PROFILE_PREFERENCE_OBJECT_REQUIRED';
  end if;

  if p_type = 'LOCATION' then
    perform private.profile_assert_payload_keys_v019(
      p_value, array['countryCodes'], array['countryCodes']
    );
    if jsonb_typeof(p_value -> 'countryCodes') <> 'array'
       or jsonb_array_length(p_value -> 'countryCodes') = 0 then
      raise exception using errcode = '22023', message = 'PROFILE_COUNTRY_CODES_REQUIRED';
    end if;
    for v_item in select value from jsonb_array_elements(p_value -> 'countryCodes') value
    loop
      v_text := v_item #>> '{}';
      if jsonb_typeof(v_item) <> 'string' or v_text !~ '^[A-Z]{2}$' then
        raise exception using errcode = '22023', message = 'PROFILE_INVALID_COUNTRY_CODE';
      end if;
    end loop;
  elsif p_type = 'DELIVERY_MODE' then
    perform private.profile_assert_payload_keys_v019(
      p_value, array['modes'], array['modes']
    );
    if jsonb_typeof(p_value -> 'modes') <> 'array'
       or jsonb_array_length(p_value -> 'modes') = 0 then
      raise exception using errcode = '22023', message = 'PROFILE_DELIVERY_MODES_REQUIRED';
    end if;
    for v_item in select value from jsonb_array_elements(p_value -> 'modes') value
    loop
      v_text := v_item #>> '{}';
      if jsonb_typeof(v_item) <> 'string'
         or v_text not in ('IN_PERSON', 'ONLINE', 'HYBRID') then
        raise exception using errcode = '22023', message = 'PROFILE_INVALID_DELIVERY_MODE';
      end if;
    end loop;
  elsif p_type = 'BUDGET' then
    perform private.profile_assert_payload_keys_v019(
      p_value, array['currencyCode', 'maximumAmount'],
      array['currencyCode', 'maximumAmount']
    );
    if (p_value ->> 'currencyCode') !~ '^[A-Z]{3}$'
       or jsonb_typeof(p_value -> 'maximumAmount') <> 'number'
       or (p_value ->> 'maximumAmount')::numeric < 0 then
      raise exception using errcode = '22023', message = 'PROFILE_INVALID_BUDGET_PREFERENCE';
    end if;
  elsif p_type = 'PROGRAM_LENGTH' then
    perform private.profile_assert_payload_keys_v019(
      p_value, array['minimumMonths', 'maximumMonths']
    );
    if not (p_value ? 'minimumMonths') and not (p_value ? 'maximumMonths') then
      raise exception using errcode = '22023', message = 'PROFILE_PROGRAM_LENGTH_BOUND_REQUIRED';
    end if;
    if p_value ? 'minimumMonths' then
      if jsonb_typeof(p_value -> 'minimumMonths') <> 'number' then
        raise exception using errcode = '22023', message = 'PROFILE_INVALID_PROGRAM_LENGTH';
      end if;
      v_min := (p_value ->> 'minimumMonths')::numeric;
    end if;
    if p_value ? 'maximumMonths' then
      if jsonb_typeof(p_value -> 'maximumMonths') <> 'number' then
        raise exception using errcode = '22023', message = 'PROFILE_INVALID_PROGRAM_LENGTH';
      end if;
      v_max := (p_value ->> 'maximumMonths')::numeric;
    end if;
    if coalesce(v_min, 1) <= 0 or coalesce(v_max, 1) <= 0
       or (v_min is not null and v_max is not null and v_max < v_min) then
      raise exception using errcode = '22023', message = 'PROFILE_INVALID_PROGRAM_LENGTH';
    end if;
  else
    raise exception using errcode = '22023', message = 'PROFILE_UNSUPPORTED_PREFERENCE_TYPE';
  end if;
  return p_value;
end;
$function$;

create or replace function private.profile_request_fingerprint_v019(
  p_request jsonb
)
returns text
language sql
immutable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  select encode(
    extensions.digest(convert_to(p_request::text, 'UTF8'), 'sha256'),
    'hex'
  )
$function$;

create or replace function private.profile_replay_operation_v019(
  p_student_id uuid,
  p_operation_id uuid,
  p_operation_kind text,
  p_command_code text,
  p_request_fingerprint text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_operation private.profile_capability_operations_v019%rowtype;
begin
  select * into v_operation
  from private.profile_capability_operations_v019
  where student_id = p_student_id and operation_id = p_operation_id
  for update;
  if not found then
    return null;
  end if;
  if v_operation.operation_kind is distinct from p_operation_kind
     or v_operation.command_code is distinct from p_command_code
     or v_operation.request_fingerprint is distinct from p_request_fingerprint then
    raise exception using errcode = '23505', message = 'PROFILE_OPERATION_CONFLICT';
  end if;
  return v_operation.result_document;
end;
$function$;

create or replace function private.profile_store_operation_v019(
  p_student_id uuid,
  p_operation_id uuid,
  p_operation_kind text,
  p_command_code text,
  p_request_fingerprint text,
  p_result_document jsonb
)
returns void
language sql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  insert into private.profile_capability_operations_v019 (
    student_id, operation_id, operation_kind, command_code,
    request_fingerprint, result_document
  ) values (
    p_student_id, p_operation_id, p_operation_kind, p_command_code,
    p_request_fingerprint, p_result_document
  )
$function$;

create or replace function private.profile_readiness_document_v019(
  p_profile_version_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  with required_scope(education_context_id, domain) as (
    select null::uuid, domain
    from unnest(array[
      'EDUCATION_HISTORY', 'TEST_HISTORY', 'EXPERIENCE_HISTORY',
      'SKILL_HISTORY', 'PREFERENCES', 'GOALS'
    ]::public.student_data_domain[]) global_domain(domain)
    union all
    select degree.student_degree_id, course_domain.domain
    from public.student_degrees degree
    cross join unnest(array[
      'COURSE_HISTORY', 'COURSE_MAPPING'
    ]::public.student_data_domain[]) course_domain(domain)
    where degree.profile_version_id = p_profile_version_id
    union all
    select null::uuid, course_domain.domain
    from unnest(array[
      'COURSE_HISTORY', 'COURSE_MAPPING'
    ]::public.student_data_domain[]) course_domain(domain)
    where not exists (
      select 1 from public.student_degrees degree
      where degree.profile_version_id = p_profile_version_id
    )
  ), scope_state as (
    select required.education_context_id, required.domain,
      completeness.completeness_id,
      completeness.completeness,
      completeness.explanation
    from required_scope required
    left join public.student_data_completeness completeness
      on completeness.profile_version_id = p_profile_version_id
     and completeness.education_context_id is not distinct from required.education_context_id
     and completeness.domain = required.domain
  ), mapping_state as (
    select 'DEGREE'::text as record_type,
      degree.student_degree_id as record_id,
      exists (
        select 1 from public.student_record_concept_mappings mapping
        where mapping.profile_version_id = p_profile_version_id
          and mapping.record_type = 'DEGREE'
          and mapping.student_record_id = degree.student_degree_id
          and mapping.mapping_status = 'VERIFIED'
      ) as verified,
      coalesce((
        select jsonb_agg(distinct mapping.mapping_status order by mapping.mapping_status)
        from public.student_record_concept_mappings mapping
        where mapping.profile_version_id = p_profile_version_id
          and mapping.record_type = 'DEGREE'
          and mapping.student_record_id = degree.student_degree_id
      ), '[]'::jsonb) as statuses
    from public.student_degrees degree
    where degree.profile_version_id = p_profile_version_id
    union all
    select 'COURSE'::text,
      course.student_course_id,
      exists (
        select 1 from public.student_record_concept_mappings mapping
        where mapping.profile_version_id = p_profile_version_id
          and mapping.record_type = 'COURSE'
          and mapping.student_record_id = course.student_course_id
          and mapping.mapping_status = 'VERIFIED'
      ),
      coalesce((
        select jsonb_agg(distinct mapping.mapping_status order by mapping.mapping_status)
        from public.student_record_concept_mappings mapping
        where mapping.profile_version_id = p_profile_version_id
          and mapping.record_type = 'COURSE'
          and mapping.student_record_id = course.student_course_id
      ), '[]'::jsonb)
    from public.student_courses course
    where course.profile_version_id = p_profile_version_id
  )
  select jsonb_build_object(
    'schemaVersion', 'PROFILE_READINESS_V019',
    'freezeReady', not exists (
      select 1 from scope_state where completeness_id is null
    ),
    'requiredScopeCount', (select count(*) from scope_state),
    'declaredRequiredScopeCount', (
      select count(*) from scope_state where completeness_id is not null
    ),
    'missingDeclarations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'educationContextId', education_context_id,
        'domain', domain
      ) order by domain, education_context_id nulls first)
      from scope_state where completeness_id is null
    ), '[]'::jsonb),
    'declarations', coalesce((
      select jsonb_agg(jsonb_build_object(
        'completenessId', completeness_id,
        'educationContextId', education_context_id,
        'domain', domain,
        'completeness', completeness,
        'explanation', explanation
      ) order by domain, education_context_id nulls first)
      from scope_state where completeness_id is not null
    ), '[]'::jsonb),
    'mappingReadiness', coalesce((
      select jsonb_agg(jsonb_build_object(
        'recordType', record_type,
        'recordId', record_id,
        'verified', verified,
        'mappingStatuses', statuses
      ) order by record_type, record_id)
      from mapping_state
    ), '[]'::jsonb)
  )
$function$;

create or replace function private.profile_document_v019(
  p_profile_version_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  select jsonb_build_object(
    'schemaVersion', 'PROFILE_DOCUMENT_V019',
    'profileVersionId', profile.profile_version_id,
    'versionNumber', profile.version_number,
    'status', profile.status,
    'revision', profile.profile_revision,
    'snapshotHash', profile.snapshot_hash,
    'frozenAt', profile.frozen_at,
    'readiness', private.profile_readiness_document_v019(profile.profile_version_id),
    'evidenceItems', coalesce((
      select jsonb_agg(jsonb_build_object(
        'evidenceId', evidence.student_evidence_id,
        'evidenceType', evidence.evidence_type,
        'locator', evidence.locator,
        'contentHash', evidence.content_hash,
        'observedAt', evidence.observed_at
      ) order by evidence.student_evidence_id)
      from public.student_evidence_items evidence
      where evidence.profile_version_id = profile.profile_version_id
    ), '[]'::jsonb),
    'degrees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'degreeId', degree.student_degree_id,
        'institutionName', degree.institution_name,
        'degreeName', degree.degree_name,
        'degreeLevel', degree.degree_level,
        'degreeStatus', degree.degree_status,
        'startDate', degree.start_date,
        'completionDate', degree.completion_date,
        'countryCode', degree.country_code,
        'gpaValue', degree.gpa_value,
        'gpaScale', degree.gpa_scale,
        'evidenceId', degree.student_evidence_id
      ) order by degree.student_degree_id)
      from public.student_degrees degree
      where degree.profile_version_id = profile.profile_version_id
    ), '[]'::jsonb),
    'courses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'courseId', course.student_course_id,
        'degreeId', course.student_degree_id,
        'courseCode', course.course_code,
        'courseTitle', course.course_title,
        'courseStatus', course.course_status,
        'term', course.term,
        'completionDate', course.completion_date,
        'credits', course.credits,
        'gradeValue', course.grade_value,
        'gradeScale', course.grade_scale,
        'gradeText', course.grade_text,
        'evidenceId', course.student_evidence_id
      ) order by course.student_course_id)
      from public.student_courses course
      where course.profile_version_id = profile.profile_version_id
    ), '[]'::jsonb),
    'testScores', coalesce((
      select jsonb_agg(jsonb_build_object(
        'testScoreId', score.student_test_score_id,
        'assessmentConceptId', score.assessment_concept_id,
        'testDate', score.test_date,
        'totalScore', score.total_score,
        'sectionScores', score.section_scores,
        'evidenceId', score.student_evidence_id
      ) order by score.student_test_score_id)
      from public.student_test_scores score
      where score.profile_version_id = profile.profile_version_id
    ), '[]'::jsonb),
    'experiences', coalesce((
      select jsonb_agg(jsonb_build_object(
        'experienceId', experience.student_experience_id,
        'experienceType', experience.experience_type,
        'organizationName', experience.organization_name,
        'roleTitle', experience.role_title,
        'startDate', experience.start_date,
        'endDate', experience.end_date,
        'hoursPerWeek', experience.hours_per_week,
        'description', experience.description,
        'evidenceId', experience.student_evidence_id
      ) order by experience.student_experience_id)
      from public.student_experiences experience
      where experience.profile_version_id = profile.profile_version_id
    ), '[]'::jsonb),
    'skills', coalesce((
      select jsonb_agg(jsonb_build_object(
        'skillId', skill.student_skill_id,
        'skillConceptId', skill.skill_concept_id,
        'proficiencyLevel', skill.proficiency_level,
        'yearsExperience', skill.years_experience,
        'evidenceId', skill.student_evidence_id
      ) order by skill.student_skill_id)
      from public.student_skills skill
      where skill.profile_version_id = profile.profile_version_id
    ), '[]'::jsonb),
    'experienceSkills', coalesce((
      select jsonb_agg(jsonb_build_object(
        'experienceId', link.student_experience_id,
        'skillId', link.student_skill_id
      ) order by link.student_experience_id, link.student_skill_id)
      from public.student_experience_skills link
      where link.profile_version_id = profile.profile_version_id
    ), '[]'::jsonb),
    'goals', coalesce((
      select jsonb_agg(jsonb_build_object(
        'goalId', goal.student_goal_id,
        'goalType', goal.goal_type,
        'conceptId', goal.concept_id,
        'goalText', goal.goal_text,
        'priority', goal.priority
      ) order by goal.student_goal_id)
      from public.student_goals goal
      where goal.profile_version_id = profile.profile_version_id
    ), '[]'::jsonb),
    'preferences', coalesce((
      select jsonb_agg(jsonb_build_object(
        'preferenceId', preference.student_preference_id,
        'preferenceType', preference.preference_type,
        'value', preference.value,
        'priority', preference.priority
      ) order by preference.student_preference_id)
      from public.student_preferences preference
      where preference.profile_version_id = profile.profile_version_id
    ), '[]'::jsonb),
    'mappings', coalesce((
      select jsonb_agg(jsonb_build_object(
        'mappingId', mapping.student_mapping_id,
        'recordType', mapping.record_type,
        'recordId', mapping.student_record_id,
        'conceptId', mapping.concept_id,
        'mappingStatus', mapping.mapping_status,
        'evidenceId', mapping.student_evidence_id
      ) order by mapping.student_mapping_id)
      from public.student_record_concept_mappings mapping
      where mapping.profile_version_id = profile.profile_version_id
    ), '[]'::jsonb)
  )
  from public.student_profile_versions profile
  where profile.profile_version_id = p_profile_version_id
$function$;

create or replace function public.bootstrap_profile_identity_v019()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
begin
  v_student_id := private.profile_bootstrap_student_v019();
  return jsonb_build_object(
    'schemaVersion', 'PROFILE_ACCOUNT_V019',
    'accountState', 'ACTIVE',
    'hasCurrentDraft', exists (
      select 1 from public.student_profile_versions profile
      where profile.student_id = v_student_id
        and profile.product_managed
        and profile.status = 'DRAFT'
    )
  );
end;
$function$;

create or replace function public.create_or_resume_profile_draft_v019(
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
  v_profile_id uuid;
  v_version_number integer;
  v_request_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
begin
  if p_operation_id is null then
    raise exception using errcode = '22023', message = 'PROFILE_OPERATION_ID_REQUIRED';
  end if;
  v_student_id := private.profile_bootstrap_student_v019();
  perform private.lock_student_lifecycle(v_student_id);
  v_request_fingerprint := private.profile_request_fingerprint_v019(
    jsonb_build_object('operation', 'CREATE_OR_RESUME')
  );
  v_replay := private.profile_replay_operation_v019(
    v_student_id, p_operation_id, 'CREATE_OR_RESUME', null,
    v_request_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;

  select profile_version_id, version_number
  into v_profile_id, v_version_number
  from public.student_profile_versions
  where student_id = v_student_id
    and product_managed
    and status = 'DRAFT'
  for update;

  if v_profile_id is null then
    select coalesce(max(version_number), 0) + 1
    into v_version_number
    from public.student_profile_versions
    where student_id = v_student_id;
    insert into public.student_profile_versions (
      student_id, version_number, product_managed, profile_revision
    ) values (
      v_student_id, v_version_number, true, 0
    ) returning profile_version_id into v_profile_id;
    perform private.write_student_lifecycle_audit(
      v_student_id, 'student_profile_versions', v_profile_id, 'CREATE'
    );
  end if;

  v_result := jsonb_build_object(
    'schemaVersion', 'PROFILE_OPERATION_RESULT_V019',
    'operation', 'CREATE_OR_RESUME',
    'profileVersionId', v_profile_id,
    'versionNumber', v_version_number,
    'status', 'DRAFT',
    'revision', 0
  );
  if exists (
    select 1 from public.student_profile_versions
    where profile_version_id = v_profile_id and profile_revision <> 0
  ) then
    select jsonb_set(v_result, '{revision}', to_jsonb(profile_revision), false)
    into v_result
    from public.student_profile_versions
    where profile_version_id = v_profile_id;
  end if;
  perform private.profile_store_operation_v019(
    v_student_id, p_operation_id, 'CREATE_OR_RESUME', null,
    v_request_fingerprint, v_result
  );
  return v_result;
end;
$function$;

create or replace function public.get_profile_readiness_v019(
  p_profile_version_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
begin
  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null or not exists (
    select 1 from public.student_profile_versions profile
    where profile.profile_version_id = p_profile_version_id
      and profile.student_id = v_student_id
  ) then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  return private.profile_readiness_document_v019(p_profile_version_id);
end;
$function$;

create or replace function public.get_profile_document_v019(
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
begin
  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  if p_profile_version_id is null then
    select profile.profile_version_id into v_profile_id
    from public.student_profile_versions profile
    where profile.student_id = v_student_id
      and profile.product_managed
      and profile.status = 'DRAFT'
    order by profile.version_number desc
    limit 1;
  else
    select profile.profile_version_id into v_profile_id
    from public.student_profile_versions profile
    where profile.profile_version_id = p_profile_version_id
      and profile.student_id = v_student_id;
  end if;
  if v_profile_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  return private.profile_document_v019(v_profile_id);
end;
$function$;

create or replace function public.mutate_profile_draft_v019(
  p_profile_version_id uuid,
  p_operation_id uuid,
  p_expected_revision bigint,
  p_command public.profile_draft_command_v019,
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_profile public.student_profile_versions%rowtype;
  v_request_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
  v_resource_id uuid;
  v_resource_key jsonb;
  v_evidence_id uuid;
  v_degree_id uuid;
  v_experience_id uuid;
  v_skill_id uuid;
  v_domain public.student_data_domain;
  v_completeness public.data_completeness;
  v_education_context_id uuid;
  v_explanation text;
  v_preference_type public.preference_type;
  v_preference_value jsonb;
  v_section_scores jsonb;
begin
  if p_profile_version_id is null or p_operation_id is null
     or p_expected_revision is null or p_expected_revision < 0
     or p_command is null then
    raise exception using errcode = '22023', message = 'PROFILE_MUTATION_ARGUMENT_REQUIRED';
  end if;
  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  perform private.lock_student_lifecycle(v_student_id);

  v_request_fingerprint := private.profile_request_fingerprint_v019(
    jsonb_build_object(
      'operation', 'MUTATE',
      'profileVersionId', p_profile_version_id,
      'expectedRevision', p_expected_revision,
      'command', p_command,
      'payload', p_payload
    )
  );
  v_replay := private.profile_replay_operation_v019(
    v_student_id, p_operation_id, 'MUTATE', p_command::text,
    v_request_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;

  select * into v_profile
  from public.student_profile_versions profile
  where profile.profile_version_id = p_profile_version_id
    and profile.student_id = v_student_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  if not v_profile.product_managed or v_profile.status <> 'DRAFT' then
    raise exception using errcode = '55000', message = 'PROFILE_DRAFT_REQUIRED';
  end if;
  if v_profile.profile_revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'PROFILE_REVISION_CONFLICT';
  end if;

  if p_command = 'COMPLETENESS_UPSERT' then
    perform private.profile_assert_payload_keys_v019(
      p_payload,
      array['educationContextId', 'domain', 'completeness', 'explanation'],
      array['domain', 'completeness']
    );
    v_domain := (p_payload ->> 'domain')::public.student_data_domain;
    v_completeness := (p_payload ->> 'completeness')::public.data_completeness;
    v_education_context_id := nullif(p_payload ->> 'educationContextId', '')::uuid;
    v_explanation := nullif(btrim(p_payload ->> 'explanation'), '');
    if v_domain in ('COURSE_HISTORY', 'COURSE_MAPPING') then
      if exists (
        select 1 from public.student_degrees degree
        where degree.profile_version_id = p_profile_version_id
      ) then
        if v_education_context_id is null or not exists (
          select 1 from public.student_degrees degree
          where degree.profile_version_id = p_profile_version_id
            and degree.student_degree_id = v_education_context_id
        ) then
          raise exception using errcode = '22023', message = 'PROFILE_EDUCATION_CONTEXT_REQUIRED';
        end if;
      elsif v_education_context_id is not null then
        raise exception using errcode = '22023', message = 'PROFILE_EDUCATION_CONTEXT_NOT_ALLOWED';
      end if;
    elsif v_education_context_id is not null then
      raise exception using errcode = '22023', message = 'PROFILE_EDUCATION_CONTEXT_NOT_ALLOWED';
    end if;
    if v_completeness = 'COMPLETE' then
      v_explanation := null;
    elsif v_explanation is null then
      raise exception using errcode = '22023', message = 'PROFILE_COMPLETENESS_EXPLANATION_REQUIRED';
    end if;
    select completeness_id into v_resource_id
    from public.student_data_completeness completeness
    where completeness.profile_version_id = p_profile_version_id
      and completeness.education_context_id is not distinct from v_education_context_id
      and completeness.domain = v_domain
    for update;
    if v_resource_id is null then
      insert into public.student_data_completeness (
        profile_version_id, education_context_id, domain,
        completeness, explanation
      ) values (
        p_profile_version_id, v_education_context_id, v_domain,
        v_completeness, v_explanation
      ) returning completeness_id into v_resource_id;
    else
      update public.student_data_completeness
      set completeness = v_completeness, explanation = v_explanation
      where completeness_id = v_resource_id;
    end if;

  elsif p_command = 'COMPLETENESS_DELETE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload, array['educationContextId', 'domain'], array['domain']
    );
    v_domain := (p_payload ->> 'domain')::public.student_data_domain;
    v_education_context_id := nullif(p_payload ->> 'educationContextId', '')::uuid;
    delete from public.student_data_completeness completeness
    where completeness.profile_version_id = p_profile_version_id
      and completeness.education_context_id is not distinct from v_education_context_id
      and completeness.domain = v_domain
    returning completeness_id into v_resource_id;
    if v_resource_id is null then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;

  elsif p_command = 'EVIDENCE_CREATE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload,
      array['evidenceType', 'locator', 'contentHash', 'observedAt'],
      array['evidenceType']
    );
    insert into public.student_evidence_items (
      profile_version_id, evidence_type, locator, content_hash,
      observed_at, metadata
    ) values (
      p_profile_version_id,
      (p_payload ->> 'evidenceType')::public.student_evidence_type,
      nullif(btrim(p_payload ->> 'locator'), ''),
      lower(nullif(btrim(p_payload ->> 'contentHash'), '')),
      coalesce(nullif(p_payload ->> 'observedAt', '')::timestamptz, now()),
      '{}'::jsonb
    ) returning student_evidence_id into v_resource_id;

  elsif p_command = 'EVIDENCE_UPDATE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload,
      array['evidenceId', 'evidenceType', 'locator', 'contentHash', 'observedAt'],
      array['evidenceId', 'evidenceType']
    );
    v_resource_id := (p_payload ->> 'evidenceId')::uuid;
    update public.student_evidence_items evidence
    set evidence_type = (p_payload ->> 'evidenceType')::public.student_evidence_type,
        locator = nullif(btrim(p_payload ->> 'locator'), ''),
        content_hash = lower(nullif(btrim(p_payload ->> 'contentHash'), '')),
        observed_at = case when p_payload ? 'observedAt'
          then (p_payload ->> 'observedAt')::timestamptz
          else evidence.observed_at end,
        metadata = '{}'::jsonb
    where evidence.student_evidence_id = v_resource_id
      and evidence.profile_version_id = p_profile_version_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;

  elsif p_command = 'EVIDENCE_DELETE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload, array['evidenceId'], array['evidenceId']
    );
    v_resource_id := (p_payload ->> 'evidenceId')::uuid;
    if exists (
      select 1 from public.student_degrees row_value
      where row_value.profile_version_id = p_profile_version_id
        and row_value.student_evidence_id = v_resource_id
      union all
      select 1 from public.student_courses row_value
      where row_value.profile_version_id = p_profile_version_id
        and row_value.student_evidence_id = v_resource_id
      union all
      select 1 from public.student_test_scores row_value
      where row_value.profile_version_id = p_profile_version_id
        and row_value.student_evidence_id = v_resource_id
      union all
      select 1 from public.student_experiences row_value
      where row_value.profile_version_id = p_profile_version_id
        and row_value.student_evidence_id = v_resource_id
      union all
      select 1 from public.student_skills row_value
      where row_value.profile_version_id = p_profile_version_id
        and row_value.student_evidence_id = v_resource_id
      union all
      select 1 from public.student_record_concept_mappings row_value
      where row_value.profile_version_id = p_profile_version_id
        and row_value.student_evidence_id = v_resource_id
    ) then
      raise exception using errcode = '55000', message = 'PROFILE_EVIDENCE_IN_USE';
    end if;
    delete from public.student_evidence_items evidence
    where evidence.student_evidence_id = v_resource_id
      and evidence.profile_version_id = p_profile_version_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;

  elsif p_command in ('DEGREE_CREATE', 'DEGREE_UPDATE') then
    perform private.profile_assert_payload_keys_v019(
      p_payload,
      case when p_command = 'DEGREE_UPDATE' then
        array['degreeId', 'institutionName', 'degreeName', 'degreeLevel',
          'degreeStatus', 'startDate', 'completionDate', 'countryCode',
          'gpaValue', 'gpaScale', 'evidenceId']
      else
        array['institutionName', 'degreeName', 'degreeLevel', 'degreeStatus',
          'startDate', 'completionDate', 'countryCode', 'gpaValue',
          'gpaScale', 'evidenceId'] end,
      case when p_command = 'DEGREE_UPDATE' then
        array['degreeId', 'institutionName', 'degreeName', 'degreeLevel',
          'degreeStatus', 'evidenceId']
      else
        array['institutionName', 'degreeName', 'degreeLevel',
          'degreeStatus', 'evidenceId'] end
    );
    v_evidence_id := (p_payload ->> 'evidenceId')::uuid;
    if not exists (
      select 1 from public.student_evidence_items evidence
      where evidence.profile_version_id = p_profile_version_id
        and evidence.student_evidence_id = v_evidence_id
    ) then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;
    if p_command = 'DEGREE_CREATE' then
      insert into public.student_degrees (
        profile_version_id, institution_name, degree_name, degree_level,
        degree_status, start_date, completion_date, country_code,
        gpa_value, gpa_scale, student_evidence_id
      ) values (
        p_profile_version_id,
        btrim(p_payload ->> 'institutionName'),
        btrim(p_payload ->> 'degreeName'),
        (p_payload ->> 'degreeLevel')::public.degree_level,
        (p_payload ->> 'degreeStatus')::public.degree_status,
        nullif(p_payload ->> 'startDate', '')::date,
        nullif(p_payload ->> 'completionDate', '')::date,
        upper(nullif(btrim(p_payload ->> 'countryCode'), '')),
        nullif(p_payload ->> 'gpaValue', '')::numeric,
        nullif(p_payload ->> 'gpaScale', '')::numeric,
        v_evidence_id
      ) returning student_degree_id into v_resource_id;
    else
      v_resource_id := (p_payload ->> 'degreeId')::uuid;
      update public.student_degrees degree
      set institution_name = btrim(p_payload ->> 'institutionName'),
          degree_name = btrim(p_payload ->> 'degreeName'),
          degree_level = (p_payload ->> 'degreeLevel')::public.degree_level,
          degree_status = (p_payload ->> 'degreeStatus')::public.degree_status,
          start_date = nullif(p_payload ->> 'startDate', '')::date,
          completion_date = nullif(p_payload ->> 'completionDate', '')::date,
          country_code = upper(nullif(btrim(p_payload ->> 'countryCode'), '')),
          gpa_value = nullif(p_payload ->> 'gpaValue', '')::numeric,
          gpa_scale = nullif(p_payload ->> 'gpaScale', '')::numeric,
          student_evidence_id = v_evidence_id
      where degree.student_degree_id = v_resource_id
        and degree.profile_version_id = p_profile_version_id;
      if not found then
        raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
      end if;
    end if;

  elsif p_command = 'DEGREE_DELETE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload, array['degreeId'], array['degreeId']
    );
    v_resource_id := (p_payload ->> 'degreeId')::uuid;
    if exists (
      select 1 from public.student_record_concept_mappings mapping
      where mapping.profile_version_id = p_profile_version_id
        and (
          (mapping.record_type = 'DEGREE' and mapping.student_record_id = v_resource_id)
          or (
            mapping.record_type = 'COURSE'
            and mapping.student_record_id in (
              select course.student_course_id from public.student_courses course
              where course.profile_version_id = p_profile_version_id
                and course.student_degree_id = v_resource_id
            )
          )
        )
    ) then
      raise exception using errcode = '55000', message = 'PROFILE_RECORD_HAS_MAPPING';
    end if;
    delete from public.student_degrees degree
    where degree.student_degree_id = v_resource_id
      and degree.profile_version_id = p_profile_version_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;

  elsif p_command in ('COURSE_CREATE', 'COURSE_UPDATE') then
    perform private.profile_assert_payload_keys_v019(
      p_payload,
      case when p_command = 'COURSE_UPDATE' then
        array['courseId', 'degreeId', 'courseCode', 'courseTitle',
          'courseStatus', 'term', 'completionDate', 'credits', 'gradeValue',
          'gradeScale', 'gradeText', 'evidenceId']
      else
        array['degreeId', 'courseCode', 'courseTitle', 'courseStatus',
          'term', 'completionDate', 'credits', 'gradeValue', 'gradeScale',
          'gradeText', 'evidenceId'] end,
      case when p_command = 'COURSE_UPDATE' then
        array['courseId', 'courseTitle', 'courseStatus', 'evidenceId']
      else array['courseTitle', 'courseStatus', 'evidenceId'] end
    );
    v_degree_id := nullif(p_payload ->> 'degreeId', '')::uuid;
    v_evidence_id := (p_payload ->> 'evidenceId')::uuid;
    if v_degree_id is not null and not exists (
      select 1 from public.student_degrees degree
      where degree.profile_version_id = p_profile_version_id
        and degree.student_degree_id = v_degree_id
    ) then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;
    if not exists (
      select 1 from public.student_evidence_items evidence
      where evidence.profile_version_id = p_profile_version_id
        and evidence.student_evidence_id = v_evidence_id
    ) then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;
    if p_command = 'COURSE_CREATE' then
      insert into public.student_courses (
        profile_version_id, student_degree_id, course_code, course_title,
        course_status, term, completion_date, credits, grade_value,
        grade_scale, grade_text, student_evidence_id
      ) values (
        p_profile_version_id, v_degree_id,
        nullif(btrim(p_payload ->> 'courseCode'), ''),
        btrim(p_payload ->> 'courseTitle'),
        (p_payload ->> 'courseStatus')::public.course_status,
        nullif(btrim(p_payload ->> 'term'), ''),
        nullif(p_payload ->> 'completionDate', '')::date,
        nullif(p_payload ->> 'credits', '')::numeric,
        nullif(p_payload ->> 'gradeValue', '')::numeric,
        nullif(p_payload ->> 'gradeScale', '')::numeric,
        nullif(btrim(p_payload ->> 'gradeText'), ''), v_evidence_id
      ) returning student_course_id into v_resource_id;
    else
      v_resource_id := (p_payload ->> 'courseId')::uuid;
      update public.student_courses course
      set student_degree_id = v_degree_id,
          course_code = nullif(btrim(p_payload ->> 'courseCode'), ''),
          course_title = btrim(p_payload ->> 'courseTitle'),
          course_status = (p_payload ->> 'courseStatus')::public.course_status,
          term = nullif(btrim(p_payload ->> 'term'), ''),
          completion_date = nullif(p_payload ->> 'completionDate', '')::date,
          credits = nullif(p_payload ->> 'credits', '')::numeric,
          grade_value = nullif(p_payload ->> 'gradeValue', '')::numeric,
          grade_scale = nullif(p_payload ->> 'gradeScale', '')::numeric,
          grade_text = nullif(btrim(p_payload ->> 'gradeText'), ''),
          student_evidence_id = v_evidence_id
      where course.student_course_id = v_resource_id
        and course.profile_version_id = p_profile_version_id;
      if not found then
        raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
      end if;
    end if;

  elsif p_command = 'COURSE_DELETE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload, array['courseId'], array['courseId']
    );
    v_resource_id := (p_payload ->> 'courseId')::uuid;
    if exists (
      select 1 from public.student_record_concept_mappings mapping
      where mapping.profile_version_id = p_profile_version_id
        and mapping.record_type = 'COURSE'
        and mapping.student_record_id = v_resource_id
    ) then
      raise exception using errcode = '55000', message = 'PROFILE_RECORD_HAS_MAPPING';
    end if;
    delete from public.student_courses course
    where course.student_course_id = v_resource_id
      and course.profile_version_id = p_profile_version_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;

  elsif p_command in ('TEST_SCORE_CREATE', 'TEST_SCORE_UPDATE') then
    perform private.profile_assert_payload_keys_v019(
      p_payload,
      case when p_command = 'TEST_SCORE_UPDATE' then
        array['testScoreId', 'assessmentConceptId', 'testDate', 'totalScore',
          'sectionScores', 'evidenceId']
      else array['assessmentConceptId', 'testDate', 'totalScore',
        'sectionScores', 'evidenceId'] end,
      case when p_command = 'TEST_SCORE_UPDATE' then
        array['testScoreId', 'assessmentConceptId', 'testDate', 'evidenceId']
      else array['assessmentConceptId', 'testDate', 'evidenceId'] end
    );
    v_evidence_id := (p_payload ->> 'evidenceId')::uuid;
    if not exists (
      select 1 from public.student_evidence_items evidence
      where evidence.profile_version_id = p_profile_version_id
        and evidence.student_evidence_id = v_evidence_id
    ) then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;
    v_section_scores := private.profile_validate_section_scores_v019(
      coalesce(p_payload -> 'sectionScores', '{}'::jsonb)
    );
    if p_command = 'TEST_SCORE_CREATE' then
      insert into public.student_test_scores (
        profile_version_id, assessment_concept_id, test_date, total_score,
        section_scores, student_evidence_id
      ) values (
        p_profile_version_id,
        (p_payload ->> 'assessmentConceptId')::uuid,
        (p_payload ->> 'testDate')::date,
        nullif(p_payload ->> 'totalScore', '')::numeric,
        v_section_scores, v_evidence_id
      ) returning student_test_score_id into v_resource_id;
    else
      v_resource_id := (p_payload ->> 'testScoreId')::uuid;
      update public.student_test_scores score
      set assessment_concept_id = (p_payload ->> 'assessmentConceptId')::uuid,
          test_date = (p_payload ->> 'testDate')::date,
          total_score = nullif(p_payload ->> 'totalScore', '')::numeric,
          section_scores = v_section_scores,
          student_evidence_id = v_evidence_id
      where score.student_test_score_id = v_resource_id
        and score.profile_version_id = p_profile_version_id;
      if not found then
        raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
      end if;
    end if;

  elsif p_command = 'TEST_SCORE_DELETE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload, array['testScoreId'], array['testScoreId']
    );
    v_resource_id := (p_payload ->> 'testScoreId')::uuid;
    delete from public.student_test_scores score
    where score.student_test_score_id = v_resource_id
      and score.profile_version_id = p_profile_version_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;

  elsif p_command in ('EXPERIENCE_CREATE', 'EXPERIENCE_UPDATE') then
    perform private.profile_assert_payload_keys_v019(
      p_payload,
      case when p_command = 'EXPERIENCE_UPDATE' then
        array['experienceId', 'experienceType', 'organizationName', 'roleTitle',
          'startDate', 'endDate', 'hoursPerWeek', 'description', 'evidenceId']
      else array['experienceType', 'organizationName', 'roleTitle', 'startDate',
        'endDate', 'hoursPerWeek', 'description', 'evidenceId'] end,
      case when p_command = 'EXPERIENCE_UPDATE' then
        array['experienceId', 'experienceType', 'roleTitle', 'evidenceId']
      else array['experienceType', 'roleTitle', 'evidenceId'] end
    );
    v_evidence_id := (p_payload ->> 'evidenceId')::uuid;
    if not exists (
      select 1 from public.student_evidence_items evidence
      where evidence.profile_version_id = p_profile_version_id
        and evidence.student_evidence_id = v_evidence_id
    ) then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;
    if p_command = 'EXPERIENCE_CREATE' then
      insert into public.student_experiences (
        profile_version_id, experience_type, organization_name, role_title,
        start_date, end_date, hours_per_week, description, student_evidence_id
      ) values (
        p_profile_version_id,
        (p_payload ->> 'experienceType')::public.experience_type,
        nullif(btrim(p_payload ->> 'organizationName'), ''),
        btrim(p_payload ->> 'roleTitle'),
        nullif(p_payload ->> 'startDate', '')::date,
        nullif(p_payload ->> 'endDate', '')::date,
        nullif(p_payload ->> 'hoursPerWeek', '')::numeric,
        nullif(btrim(p_payload ->> 'description'), ''), v_evidence_id
      ) returning student_experience_id into v_resource_id;
    else
      v_resource_id := (p_payload ->> 'experienceId')::uuid;
      update public.student_experiences experience
      set experience_type = (p_payload ->> 'experienceType')::public.experience_type,
          organization_name = nullif(btrim(p_payload ->> 'organizationName'), ''),
          role_title = btrim(p_payload ->> 'roleTitle'),
          start_date = nullif(p_payload ->> 'startDate', '')::date,
          end_date = nullif(p_payload ->> 'endDate', '')::date,
          hours_per_week = nullif(p_payload ->> 'hoursPerWeek', '')::numeric,
          description = nullif(btrim(p_payload ->> 'description'), ''),
          student_evidence_id = v_evidence_id
      where experience.student_experience_id = v_resource_id
        and experience.profile_version_id = p_profile_version_id;
      if not found then
        raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
      end if;
    end if;

  elsif p_command = 'EXPERIENCE_DELETE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload, array['experienceId'], array['experienceId']
    );
    v_resource_id := (p_payload ->> 'experienceId')::uuid;
    delete from public.student_experiences experience
    where experience.student_experience_id = v_resource_id
      and experience.profile_version_id = p_profile_version_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;

  elsif p_command in ('SKILL_CREATE', 'SKILL_UPDATE') then
    perform private.profile_assert_payload_keys_v019(
      p_payload,
      case when p_command = 'SKILL_UPDATE' then
        array['skillId', 'skillConceptId', 'proficiencyLevel',
          'yearsExperience', 'evidenceId']
      else array['skillConceptId', 'proficiencyLevel',
        'yearsExperience', 'evidenceId'] end,
      case when p_command = 'SKILL_UPDATE' then
        array['skillId', 'skillConceptId', 'evidenceId']
      else array['skillConceptId', 'evidenceId'] end
    );
    v_evidence_id := (p_payload ->> 'evidenceId')::uuid;
    if not exists (
      select 1 from public.student_evidence_items evidence
      where evidence.profile_version_id = p_profile_version_id
        and evidence.student_evidence_id = v_evidence_id
    ) then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;
    if p_command = 'SKILL_CREATE' then
      insert into public.student_skills (
        profile_version_id, skill_concept_id, proficiency_level,
        years_experience, student_evidence_id
      ) values (
        p_profile_version_id,
        (p_payload ->> 'skillConceptId')::uuid,
        nullif(p_payload ->> 'proficiencyLevel', '')::integer,
        nullif(p_payload ->> 'yearsExperience', '')::numeric,
        v_evidence_id
      ) returning student_skill_id into v_resource_id;
    else
      v_resource_id := (p_payload ->> 'skillId')::uuid;
      update public.student_skills skill
      set skill_concept_id = (p_payload ->> 'skillConceptId')::uuid,
          proficiency_level = nullif(p_payload ->> 'proficiencyLevel', '')::integer,
          years_experience = nullif(p_payload ->> 'yearsExperience', '')::numeric,
          student_evidence_id = v_evidence_id
      where skill.student_skill_id = v_resource_id
        and skill.profile_version_id = p_profile_version_id;
      if not found then
        raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
      end if;
    end if;

  elsif p_command = 'SKILL_DELETE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload, array['skillId'], array['skillId']
    );
    v_resource_id := (p_payload ->> 'skillId')::uuid;
    delete from public.student_skills skill
    where skill.student_skill_id = v_resource_id
      and skill.profile_version_id = p_profile_version_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;

  elsif p_command in ('EXPERIENCE_SKILL_LINK', 'EXPERIENCE_SKILL_UNLINK') then
    perform private.profile_assert_payload_keys_v019(
      p_payload, array['experienceId', 'skillId'],
      array['experienceId', 'skillId']
    );
    v_experience_id := (p_payload ->> 'experienceId')::uuid;
    v_skill_id := (p_payload ->> 'skillId')::uuid;
    if not exists (
      select 1 from public.student_experiences experience
      where experience.profile_version_id = p_profile_version_id
        and experience.student_experience_id = v_experience_id
    ) or not exists (
      select 1 from public.student_skills skill
      where skill.profile_version_id = p_profile_version_id
        and skill.student_skill_id = v_skill_id
    ) then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;
    if p_command = 'EXPERIENCE_SKILL_LINK' then
      insert into public.student_experience_skills (
        profile_version_id, student_experience_id, student_skill_id
      ) values (p_profile_version_id, v_experience_id, v_skill_id);
    else
      delete from public.student_experience_skills link
      where link.profile_version_id = p_profile_version_id
        and link.student_experience_id = v_experience_id
        and link.student_skill_id = v_skill_id;
      if not found then
        raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
      end if;
    end if;
    v_resource_key := jsonb_build_object(
      'experienceId', v_experience_id, 'skillId', v_skill_id
    );

  elsif p_command in ('GOAL_CREATE', 'GOAL_UPDATE') then
    perform private.profile_assert_payload_keys_v019(
      p_payload,
      case when p_command = 'GOAL_UPDATE' then
        array['goalId', 'goalType', 'conceptId', 'goalText', 'priority']
      else array['goalType', 'conceptId', 'goalText', 'priority'] end,
      case when p_command = 'GOAL_UPDATE' then
        array['goalId', 'goalType', 'priority']
      else array['goalType', 'priority'] end
    );
    if p_command = 'GOAL_CREATE' then
      insert into public.student_goals (
        profile_version_id, goal_type, concept_id, goal_text, priority
      ) values (
        p_profile_version_id,
        (p_payload ->> 'goalType')::public.goal_type,
        nullif(p_payload ->> 'conceptId', '')::uuid,
        nullif(btrim(p_payload ->> 'goalText'), ''),
        (p_payload ->> 'priority')::integer
      ) returning student_goal_id into v_resource_id;
    else
      v_resource_id := (p_payload ->> 'goalId')::uuid;
      update public.student_goals goal
      set goal_type = (p_payload ->> 'goalType')::public.goal_type,
          concept_id = nullif(p_payload ->> 'conceptId', '')::uuid,
          goal_text = nullif(btrim(p_payload ->> 'goalText'), ''),
          priority = (p_payload ->> 'priority')::integer
      where goal.student_goal_id = v_resource_id
        and goal.profile_version_id = p_profile_version_id;
      if not found then
        raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
      end if;
    end if;

  elsif p_command = 'GOAL_DELETE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload, array['goalId'], array['goalId']
    );
    v_resource_id := (p_payload ->> 'goalId')::uuid;
    delete from public.student_goals goal
    where goal.student_goal_id = v_resource_id
      and goal.profile_version_id = p_profile_version_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;

  elsif p_command in ('PREFERENCE_CREATE', 'PREFERENCE_UPDATE') then
    perform private.profile_assert_payload_keys_v019(
      p_payload,
      case when p_command = 'PREFERENCE_UPDATE' then
        array['preferenceId', 'preferenceType', 'value', 'priority']
      else array['preferenceType', 'value', 'priority'] end,
      case when p_command = 'PREFERENCE_UPDATE' then
        array['preferenceId', 'preferenceType', 'value', 'priority']
      else array['preferenceType', 'value', 'priority'] end
    );
    v_preference_type := (p_payload ->> 'preferenceType')::public.preference_type;
    v_preference_value := private.profile_validate_preference_value_v019(
      v_preference_type, p_payload -> 'value'
    );
    if p_command = 'PREFERENCE_CREATE' then
      insert into public.student_preferences (
        profile_version_id, preference_type, value, priority
      ) values (
        p_profile_version_id, v_preference_type, v_preference_value,
        (p_payload ->> 'priority')::integer
      ) returning student_preference_id into v_resource_id;
    else
      v_resource_id := (p_payload ->> 'preferenceId')::uuid;
      update public.student_preferences preference
      set preference_type = v_preference_type,
          value = v_preference_value,
          priority = (p_payload ->> 'priority')::integer
      where preference.student_preference_id = v_resource_id
        and preference.profile_version_id = p_profile_version_id;
      if not found then
        raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
      end if;
    end if;

  elsif p_command = 'PREFERENCE_DELETE' then
    perform private.profile_assert_payload_keys_v019(
      p_payload, array['preferenceId'], array['preferenceId']
    );
    v_resource_id := (p_payload ->> 'preferenceId')::uuid;
    delete from public.student_preferences preference
    where preference.student_preference_id = v_resource_id
      and preference.profile_version_id = p_profile_version_id;
    if not found then
      raise exception using errcode = 'P0002', message = 'PROFILE_CHILD_NOT_FOUND';
    end if;
  else
    raise exception using errcode = '22023', message = 'PROFILE_COMMAND_UNSUPPORTED';
  end if;

  update public.student_profile_versions profile
  set profile_revision = profile_revision + 1
  where profile.profile_version_id = p_profile_version_id
    and profile.profile_revision = p_expected_revision
    and profile.status = 'DRAFT';
  if not found then
    raise exception using errcode = '40001', message = 'PROFILE_REVISION_CONFLICT';
  end if;

  v_result := jsonb_build_object(
    'schemaVersion', 'PROFILE_OPERATION_RESULT_V019',
    'operation', 'MUTATE',
    'command', p_command,
    'profileVersionId', p_profile_version_id,
    'revision', p_expected_revision + 1,
    'resourceId', v_resource_id,
    'resourceKey', v_resource_key
  );
  perform private.profile_store_operation_v019(
    v_student_id, p_operation_id, 'MUTATE', p_command::text,
    v_request_fingerprint, v_result
  );
  return v_result;
end;
$function$;

create or replace function public.freeze_profile_draft_v019(
  p_profile_version_id uuid,
  p_operation_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_profile public.student_profile_versions%rowtype;
  v_request_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
begin
  if p_profile_version_id is null or p_operation_id is null
     or p_expected_revision is null or p_expected_revision < 0 then
    raise exception using errcode = '22023', message = 'PROFILE_FREEZE_ARGUMENT_REQUIRED';
  end if;
  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  perform private.lock_student_lifecycle(v_student_id);
  perform private.lock_student_owned_total_order(v_student_id);
  v_request_fingerprint := private.profile_request_fingerprint_v019(
    jsonb_build_object(
      'operation', 'FREEZE',
      'profileVersionId', p_profile_version_id,
      'expectedRevision', p_expected_revision
    )
  );
  v_replay := private.profile_replay_operation_v019(
    v_student_id, p_operation_id, 'FREEZE', null, v_request_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;
  select * into v_profile
  from public.student_profile_versions profile
  where profile.profile_version_id = p_profile_version_id
    and profile.student_id = v_student_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  if not v_profile.product_managed or v_profile.status <> 'DRAFT' then
    raise exception using errcode = '55000', message = 'PROFILE_DRAFT_REQUIRED';
  end if;
  if v_profile.profile_revision <> p_expected_revision then
    raise exception using errcode = '40001', message = 'PROFILE_REVISION_CONFLICT';
  end if;

  update public.student_profile_versions
  set profile_revision = profile_revision + 1
  where profile_version_id = p_profile_version_id;
  perform public.freeze_student_profile_version(p_profile_version_id);
  v_result := jsonb_build_object(
    'schemaVersion', 'PROFILE_OPERATION_RESULT_V019',
    'operation', 'FREEZE',
    'profileVersionId', p_profile_version_id,
    'status', 'FROZEN',
    'revision', p_expected_revision + 1,
    'document', private.profile_document_v019(p_profile_version_id)
  );
  perform private.profile_store_operation_v019(
    v_student_id, p_operation_id, 'FREEZE', null,
    v_request_fingerprint, v_result
  );
  return v_result;
end;
$function$;

-- Transfer every capability function to the existing non-login student
-- executor. CREATE is temporary and is revoked before commit.
grant create on schema public, private to foundation_student_executor;

alter function private.profile_require_auth_subject_v019()
  owner to foundation_student_executor;
alter function private.profile_bootstrap_student_v019()
  owner to foundation_student_executor;
alter function private.profile_student_for_auth_v019()
  owner to foundation_student_executor;
alter function private.profile_assert_payload_keys_v019(jsonb,text[],text[])
  owner to foundation_student_executor;
alter function private.profile_validate_section_scores_v019(jsonb)
  owner to foundation_student_executor;
alter function private.profile_validate_preference_value_v019(public.preference_type,jsonb)
  owner to foundation_student_executor;
alter function private.profile_request_fingerprint_v019(jsonb)
  owner to foundation_student_executor;
alter function private.profile_replay_operation_v019(uuid,uuid,text,text,text)
  owner to foundation_student_executor;
alter function private.profile_store_operation_v019(uuid,uuid,text,text,text,jsonb)
  owner to foundation_student_executor;
alter function private.profile_readiness_document_v019(uuid)
  owner to foundation_student_executor;
alter function private.profile_document_v019(uuid)
  owner to foundation_student_executor;
alter function public.bootstrap_profile_identity_v019()
  owner to foundation_student_executor;
alter function public.create_or_resume_profile_draft_v019(uuid)
  owner to foundation_student_executor;
alter function public.get_profile_readiness_v019(uuid)
  owner to foundation_student_executor;
alter function public.get_profile_document_v019(uuid)
  owner to foundation_student_executor;
alter function public.mutate_profile_draft_v019(
  uuid,uuid,bigint,public.profile_draft_command_v019,jsonb
) owner to foundation_student_executor;
alter function public.freeze_profile_draft_v019(uuid,uuid,bigint)
  owner to foundation_student_executor;

revoke create on schema public, private from foundation_student_executor;

do $acl$
declare
  v_function record;
begin
  for v_function in
    select namespace.nspname,
      procedure.proname,
      pg_get_function_identity_arguments(procedure.oid) as identity_arguments
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where procedure.proname in (
      'profile_require_auth_subject_v019',
      'profile_bootstrap_student_v019',
      'profile_student_for_auth_v019',
      'profile_assert_payload_keys_v019',
      'profile_validate_section_scores_v019',
      'profile_validate_preference_value_v019',
      'profile_request_fingerprint_v019',
      'profile_replay_operation_v019',
      'profile_store_operation_v019',
      'profile_readiness_document_v019',
      'profile_document_v019',
      'bootstrap_profile_identity_v019',
      'create_or_resume_profile_draft_v019',
      'get_profile_readiness_v019',
      'get_profile_document_v019',
      'mutate_profile_draft_v019',
      'freeze_profile_draft_v019'
    )
  loop
    execute format(
      'revoke all on function %I.%I(%s) from public, anon, authenticated, service_role, authenticator, foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor',
      v_function.nspname, v_function.proname, v_function.identity_arguments
    );
    if v_function.nspname = 'private' then
      execute format(
        'grant execute on function %I.%I(%s) to foundation_student_executor',
        v_function.nspname, v_function.proname, v_function.identity_arguments
      );
    end if;
  end loop;
end;
$acl$;

revoke usage on type public.profile_draft_command_v019
  from public, anon, authenticated, service_role, authenticator,
       foundation_catalog_executor, foundation_evaluation_executor;
grant usage on type public.profile_draft_command_v019
  to authenticated, foundation_student_executor;

grant execute on function public.bootstrap_profile_identity_v019()
  to authenticated;
grant execute on function public.create_or_resume_profile_draft_v019(uuid)
  to authenticated;
grant execute on function public.get_profile_readiness_v019(uuid)
  to authenticated;
grant execute on function public.get_profile_document_v019(uuid)
  to authenticated;
grant execute on function public.mutate_profile_draft_v019(
  uuid,uuid,bigint,public.profile_draft_command_v019,jsonb
) to authenticated;
grant execute on function public.freeze_profile_draft_v019(uuid,uuid,bigint)
  to authenticated;

do $contracts$
declare
  v_function record;
  v_allowed text[];
begin
  for v_function in
    select namespace.nspname,
      procedure.proname,
      pg_get_function_identity_arguments(procedure.oid) as identity_arguments,
      procedure.proowner::regrole::text as owner_role,
      procedure.prosecdef,
      pg_get_functiondef(procedure.oid) as definition
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where procedure.proname in (
      'profile_require_auth_subject_v019',
      'profile_bootstrap_student_v019',
      'profile_student_for_auth_v019',
      'profile_assert_payload_keys_v019',
      'profile_validate_section_scores_v019',
      'profile_validate_preference_value_v019',
      'profile_request_fingerprint_v019',
      'profile_replay_operation_v019',
      'profile_store_operation_v019',
      'profile_readiness_document_v019',
      'profile_document_v019',
      'bootstrap_profile_identity_v019',
      'create_or_resume_profile_draft_v019',
      'get_profile_readiness_v019',
      'get_profile_document_v019',
      'mutate_profile_draft_v019',
      'freeze_profile_draft_v019'
    )
  loop
    v_allowed := case when v_function.nspname = 'public'
      then array['authenticated']
      else array['foundation_student_executor'] end;
    insert into public.foundation_function_contracts (
      schema_name, function_name, identity_arguments, owner_role, prosecdef,
      search_path, allowed_caller_roles, body_digest
    ) values (
      v_function.nspname, v_function.proname,
      v_function.identity_arguments, v_function.owner_role,
      v_function.prosecdef,
      'pg_catalog, public, private, extensions',
      v_allowed,
      encode(extensions.digest(convert_to(v_function.definition, 'UTF8'), 'sha256'), 'hex')
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

comment on function public.bootstrap_profile_identity_v019() is
  'Bootstraps exactly one private student binding from auth.uid(); accepts no caller-supplied ownership identifier.';
comment on function public.create_or_resume_profile_draft_v019(uuid) is
  'Race-safe create/resume for the single active product-managed DRAFT, with operation-id replay.';
comment on function public.mutate_profile_draft_v019(
  uuid,uuid,bigint,public.profile_draft_command_v019,jsonb
) is
  'Closed typed Profile mutation surface. Unknown keys fail closed and every committed command advances profile_revision exactly once.';
comment on function public.freeze_profile_draft_v019(uuid,uuid,bigint) is
  'Owner-scoped atomic freeze that preserves the Migration 012 completeness and snapshot_hash law.';

do $assert$
declare
  v_count integer;
begin
  if exists (
    select 1 from public.student_profile_versions
    where not product_managed and profile_revision <> 0
  ) then
    raise exception '019 assertion failed: historical profile revision drift';
  end if;
  select count(*) into v_count
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  join pg_roles owner_role on owner_role.oid = procedure.proowner
  where procedure.proname in (
    'profile_require_auth_subject_v019',
    'profile_bootstrap_student_v019',
    'profile_student_for_auth_v019',
    'profile_assert_payload_keys_v019',
    'profile_validate_section_scores_v019',
    'profile_validate_preference_value_v019',
    'profile_request_fingerprint_v019',
    'profile_replay_operation_v019',
    'profile_store_operation_v019',
    'profile_readiness_document_v019',
    'profile_document_v019',
    'bootstrap_profile_identity_v019',
    'create_or_resume_profile_draft_v019',
    'get_profile_readiness_v019',
    'get_profile_document_v019',
    'mutate_profile_draft_v019',
    'freeze_profile_draft_v019'
  ) and (
    owner_role.rolname <> 'foundation_student_executor'
    or not procedure.prosecdef
    or procedure.proconfig is distinct from
      array['search_path=pg_catalog, public, private, extensions']::text[]
  );
  if v_count <> 0 then
    raise exception '019 assertion failed: function owner/definer/search_path';
  end if;
  if exists (
    select 1 from information_schema.routine_privileges privilege
    where privilege.grantee in (
      'PUBLIC', 'anon', 'service_role', 'authenticator',
      'foundation_catalog_executor', 'foundation_evaluation_executor'
    )
      and privilege.privilege_type = 'EXECUTE'
      and privilege.routine_schema in ('public', 'private')
      and privilege.routine_name like '%\_v019' escape '\'
  ) then
    raise exception '019 assertion failed: external v019 EXECUTE';
  end if;
  if exists (
    select 1 from information_schema.routine_privileges privilege
    where privilege.grantee = 'authenticated'
      and privilege.privilege_type = 'EXECUTE'
      and privilege.routine_schema in ('public', 'private')
      and privilege.routine_name not in (
        'current_user_owns_student',
        'current_user_owns_profile',
        'review_fit_financial_normalization_v017',
        'bootstrap_profile_identity_v019',
        'create_or_resume_profile_draft_v019',
        'get_profile_readiness_v019',
        'get_profile_document_v019',
        'mutate_profile_draft_v019',
        'freeze_profile_draft_v019'
      )
  ) then
    raise exception '019 assertion failed: authenticated EXECUTE whitelist';
  end if;
  if not has_function_privilege(
    'authenticated', 'public.bootstrap_profile_identity_v019()', 'EXECUTE'
  ) or not has_function_privilege(
    'authenticated', 'public.create_or_resume_profile_draft_v019(uuid)', 'EXECUTE'
  ) or not has_function_privilege(
    'authenticated', 'public.get_profile_readiness_v019(uuid)', 'EXECUTE'
  ) or not has_function_privilege(
    'authenticated', 'public.get_profile_document_v019(uuid)', 'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.mutate_profile_draft_v019(uuid,uuid,bigint,public.profile_draft_command_v019,jsonb)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated', 'public.freeze_profile_draft_v019(uuid,uuid,bigint)', 'EXECUTE'
  ) then
    raise exception '019 assertion failed: authenticated capability missing';
  end if;
  if has_table_privilege(
    'authenticated', 'public.student_profile_versions', 'INSERT,UPDATE,DELETE'
  ) or has_table_privilege(
    'authenticated', 'private.profile_capability_operations_v019', 'SELECT,INSERT,UPDATE,DELETE'
  ) then
    raise exception '019 assertion failed: direct browser DML';
  end if;
end;
$assert$;

commit;
