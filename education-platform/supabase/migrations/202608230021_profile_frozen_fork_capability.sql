-- Phase 4B-1B.1: owner-scoped Frozen Profile -> new product DRAFT fork.
--
-- Migration 020 remains reserved for Application/Outcome. This local-only 021
-- must not be deployed before 020 exists and has been applied first; doing so
-- would create a late lower-version migration in Supabase history.

begin;

alter table private.profile_capability_operations_v019
  drop constraint profile_operations_kind_closed,
  add constraint profile_operations_kind_closed
    check (operation_kind in (
      'CREATE_OR_RESUME', 'MUTATE', 'FREEZE', 'FORK_FROZEN'
    ));

create or replace function public.fork_frozen_profile_to_draft_v021(
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
  v_source public.student_profile_versions%rowtype;
  v_new_profile_id uuid;
  v_new_version_number integer;
  v_request_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
  v_row record;
  v_new_id uuid;
  v_new_record_id uuid;
  v_new_evidence_id uuid;
  v_evidence_map jsonb := '{}'::jsonb;
  v_degree_map jsonb := '{}'::jsonb;
  v_course_map jsonb := '{}'::jsonb;
  v_experience_map jsonb := '{}'::jsonb;
  v_skill_map jsonb := '{}'::jsonb;
  v_mapping_map jsonb := '{}'::jsonb;
  v_mapping_total integer;
  v_mapping_done integer := 0;
  v_mapping_progress integer;
begin
  if p_source_profile_version_id is null or p_operation_id is null then
    raise exception using errcode = '22023',
      message = 'PROFILE_FORK_ARGUMENT_REQUIRED';
  end if;

  v_student_id := private.profile_student_for_auth_v019();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;

  perform private.lock_student_lifecycle(v_student_id);
  v_request_fingerprint := private.profile_request_fingerprint_v019(
    jsonb_build_object(
      'operation', 'FORK_FROZEN',
      'sourceProfileVersionId', p_source_profile_version_id
    )
  );
  v_replay := private.profile_replay_operation_v019(
    v_student_id, p_operation_id, 'FORK_FROZEN', null,
    v_request_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;

  select profile.* into v_source
  from public.student_profile_versions profile
  where profile.profile_version_id = p_source_profile_version_id
    and profile.student_id = v_student_id
  for key share;
  if not found then
    raise exception using errcode = 'P0002', message = 'PROFILE_NOT_FOUND';
  end if;
  if v_source.status <> 'FROZEN' then
    raise exception using errcode = '55000',
      message = 'PROFILE_FROZEN_REQUIRED';
  end if;

  if exists (
    select 1
    from public.student_profile_versions profile
    where profile.student_id = v_student_id
      and profile.product_managed
      and profile.status = 'DRAFT'
  ) then
    raise exception using errcode = '55000',
      message = 'PROFILE_ACTIVE_DRAFT_EXISTS';
  end if;

  select coalesce(max(profile.version_number), 0) + 1
  into v_new_version_number
  from public.student_profile_versions profile
  where profile.student_id = v_student_id;

  insert into public.student_profile_versions (
    student_id, version_number, status, snapshot_hash, frozen_at,
    product_managed, profile_revision
  ) values (
    v_student_id, v_new_version_number, 'DRAFT', null, null, true, 0
  ) returning profile_version_id into v_new_profile_id;

  perform private.write_student_lifecycle_audit(
    v_student_id, 'student_profile_versions', v_new_profile_id, 'FORK'
  );

  -- Evidence authority/control metadata is not promoted into the editable
  -- draft. Typed evidence semantics are copied; metadata is reset closed.
  for v_row in
    select evidence.*
    from public.student_evidence_items evidence
    where evidence.profile_version_id = p_source_profile_version_id
    order by evidence.student_evidence_id
  loop
    v_new_id := extensions.gen_random_uuid();
    insert into public.student_evidence_items (
      student_evidence_id, profile_version_id, evidence_type, locator,
      content_hash, observed_at, metadata
    ) values (
      v_new_id, v_new_profile_id, v_row.evidence_type, v_row.locator,
      v_row.content_hash, v_row.observed_at, '{}'::jsonb
    );
    v_evidence_map := v_evidence_map || jsonb_build_object(
      v_row.student_evidence_id::text, v_new_id::text
    );
  end loop;

  for v_row in
    select degree.*
    from public.student_degrees degree
    where degree.profile_version_id = p_source_profile_version_id
    order by degree.student_degree_id
  loop
    v_new_id := extensions.gen_random_uuid();
    v_new_evidence_id := (v_evidence_map ->> v_row.student_evidence_id::text)::uuid;
    if v_new_evidence_id is null then
      raise exception using errcode = '55000',
        message = 'PROFILE_FORK_GRAPH_INVALID';
    end if;
    insert into public.student_degrees (
      student_degree_id, profile_version_id, institution_name, degree_name,
      degree_level, degree_status, start_date, completion_date, country_code,
      gpa_value, gpa_scale, student_evidence_id
    ) values (
      v_new_id, v_new_profile_id, v_row.institution_name, v_row.degree_name,
      v_row.degree_level, v_row.degree_status, v_row.start_date,
      v_row.completion_date, v_row.country_code, v_row.gpa_value,
      v_row.gpa_scale, v_new_evidence_id
    );
    v_degree_map := v_degree_map || jsonb_build_object(
      v_row.student_degree_id::text, v_new_id::text
    );
  end loop;

  for v_row in
    select completeness.*
    from public.student_data_completeness completeness
    where completeness.profile_version_id = p_source_profile_version_id
    order by completeness.completeness_id
  loop
    v_new_id := extensions.gen_random_uuid();
    v_new_record_id := case
      when v_row.education_context_id is null then null
      else (v_degree_map ->> v_row.education_context_id::text)::uuid
    end;
    if v_row.education_context_id is not null and v_new_record_id is null then
      raise exception using errcode = '55000',
        message = 'PROFILE_FORK_GRAPH_INVALID';
    end if;
    insert into public.student_data_completeness (
      completeness_id, profile_version_id, education_context_id,
      domain, completeness, explanation
    ) values (
      v_new_id, v_new_profile_id, v_new_record_id,
      v_row.domain, v_row.completeness, v_row.explanation
    );
  end loop;

  for v_row in
    select course.*
    from public.student_courses course
    where course.profile_version_id = p_source_profile_version_id
    order by course.student_course_id
  loop
    v_new_id := extensions.gen_random_uuid();
    v_new_record_id := case
      when v_row.student_degree_id is null then null
      else (v_degree_map ->> v_row.student_degree_id::text)::uuid
    end;
    v_new_evidence_id := (v_evidence_map ->> v_row.student_evidence_id::text)::uuid;
    if (v_row.student_degree_id is not null and v_new_record_id is null)
       or v_new_evidence_id is null then
      raise exception using errcode = '55000',
        message = 'PROFILE_FORK_GRAPH_INVALID';
    end if;
    insert into public.student_courses (
      student_course_id, profile_version_id, student_degree_id,
      course_code, course_title, course_status, term, completion_date,
      credits, grade_value, grade_scale, grade_text, student_evidence_id
    ) values (
      v_new_id, v_new_profile_id, v_new_record_id,
      v_row.course_code, v_row.course_title, v_row.course_status,
      v_row.term, v_row.completion_date, v_row.credits, v_row.grade_value,
      v_row.grade_scale, v_row.grade_text, v_new_evidence_id
    );
    v_course_map := v_course_map || jsonb_build_object(
      v_row.student_course_id::text, v_new_id::text
    );
  end loop;

  for v_row in
    select score.*
    from public.student_test_scores score
    where score.profile_version_id = p_source_profile_version_id
    order by score.student_test_score_id
  loop
    v_new_id := extensions.gen_random_uuid();
    v_new_evidence_id := (v_evidence_map ->> v_row.student_evidence_id::text)::uuid;
    if v_new_evidence_id is null then
      raise exception using errcode = '55000',
        message = 'PROFILE_FORK_GRAPH_INVALID';
    end if;
    insert into public.student_test_scores (
      student_test_score_id, profile_version_id, assessment_concept_id,
      test_date, total_score, section_scores, student_evidence_id
    ) values (
      v_new_id, v_new_profile_id, v_row.assessment_concept_id,
      v_row.test_date, v_row.total_score,
      private.profile_validate_section_scores_v019(v_row.section_scores),
      v_new_evidence_id
    );
  end loop;

  for v_row in
    select experience.*
    from public.student_experiences experience
    where experience.profile_version_id = p_source_profile_version_id
    order by experience.student_experience_id
  loop
    v_new_id := extensions.gen_random_uuid();
    v_new_evidence_id := (v_evidence_map ->> v_row.student_evidence_id::text)::uuid;
    if v_new_evidence_id is null then
      raise exception using errcode = '55000',
        message = 'PROFILE_FORK_GRAPH_INVALID';
    end if;
    insert into public.student_experiences (
      student_experience_id, profile_version_id, experience_type,
      organization_name, role_title, start_date, end_date,
      hours_per_week, description, student_evidence_id
    ) values (
      v_new_id, v_new_profile_id, v_row.experience_type,
      v_row.organization_name, v_row.role_title, v_row.start_date,
      v_row.end_date, v_row.hours_per_week, v_row.description,
      v_new_evidence_id
    );
    v_experience_map := v_experience_map || jsonb_build_object(
      v_row.student_experience_id::text, v_new_id::text
    );
  end loop;

  for v_row in
    select skill.*
    from public.student_skills skill
    where skill.profile_version_id = p_source_profile_version_id
    order by skill.student_skill_id
  loop
    v_new_id := extensions.gen_random_uuid();
    v_new_evidence_id := (v_evidence_map ->> v_row.student_evidence_id::text)::uuid;
    if v_new_evidence_id is null then
      raise exception using errcode = '55000',
        message = 'PROFILE_FORK_GRAPH_INVALID';
    end if;
    insert into public.student_skills (
      student_skill_id, profile_version_id, skill_concept_id,
      proficiency_level, years_experience, student_evidence_id
    ) values (
      v_new_id, v_new_profile_id, v_row.skill_concept_id,
      v_row.proficiency_level, v_row.years_experience, v_new_evidence_id
    );
    v_skill_map := v_skill_map || jsonb_build_object(
      v_row.student_skill_id::text, v_new_id::text
    );
  end loop;

  for v_row in
    select link.*
    from public.student_experience_skills link
    where link.profile_version_id = p_source_profile_version_id
    order by link.student_experience_id, link.student_skill_id
  loop
    insert into public.student_experience_skills (
      profile_version_id, student_experience_id, student_skill_id
    ) values (
      v_new_profile_id,
      (v_experience_map ->> v_row.student_experience_id::text)::uuid,
      (v_skill_map ->> v_row.student_skill_id::text)::uuid
    );
  end loop;

  for v_row in
    select goal.*
    from public.student_goals goal
    where goal.profile_version_id = p_source_profile_version_id
    order by goal.student_goal_id
  loop
    insert into public.student_goals (
      student_goal_id, profile_version_id, goal_type,
      concept_id, goal_text, priority
    ) values (
      extensions.gen_random_uuid(), v_new_profile_id, v_row.goal_type,
      v_row.concept_id, v_row.goal_text, v_row.priority
    );
  end loop;

  for v_row in
    select preference.*
    from public.student_preferences preference
    where preference.profile_version_id = p_source_profile_version_id
    order by preference.student_preference_id
  loop
    insert into public.student_preferences (
      student_preference_id, profile_version_id,
      preference_type, value, priority
    ) values (
      extensions.gen_random_uuid(), v_new_profile_id,
      v_row.preference_type,
      private.profile_validate_preference_value_v019(
        v_row.preference_type, v_row.value
      ),
      v_row.priority
    );
  end loop;

  select count(*) into v_mapping_total
  from public.student_record_concept_mappings mapping
  where mapping.profile_version_id = p_source_profile_version_id;

  -- Rebuild the mapping history topologically. Active VERIFIED authority is
  -- intentionally demoted to PROPOSED because the new graph is editable.
  -- Terminal history remains terminal, but its reviewer/timestamps are
  -- recreated only through the existing controlled review/retire functions.
  while v_mapping_done < v_mapping_total loop
    v_mapping_progress := 0;
    for v_row in
      select mapping.*
      from public.student_record_concept_mappings mapping
      where mapping.profile_version_id = p_source_profile_version_id
        and not (v_mapping_map ? mapping.student_mapping_id::text)
        and (
          mapping.supersedes_mapping_id is null
          or v_mapping_map ? mapping.supersedes_mapping_id::text
        )
      order by
        case mapping.mapping_status
          when 'RETIRED' then 0
          when 'REJECTED' then 1
          else 2
        end,
        mapping.created_at,
        mapping.student_mapping_id
    loop
      v_new_id := extensions.gen_random_uuid();
      v_new_record_id := case v_row.record_type
        when 'DEGREE' then
          (v_degree_map ->> v_row.student_record_id::text)::uuid
        when 'COURSE' then
          (v_course_map ->> v_row.student_record_id::text)::uuid
        else null
      end;
      v_new_evidence_id := case
        when v_row.student_evidence_id is null then null
        else (v_evidence_map ->> v_row.student_evidence_id::text)::uuid
      end;
      if v_new_record_id is null
         or (v_row.student_evidence_id is not null and v_new_evidence_id is null)
         or (v_row.mapping_status = 'RETIRED' and v_new_evidence_id is null) then
        raise exception using errcode = '55000',
          message = 'PROFILE_FORK_GRAPH_INVALID';
      end if;

      insert into public.student_record_concept_mappings (
        student_mapping_id, profile_version_id, record_type,
        student_record_id, concept_id, mapping_status, method,
        confidence, model_version, reviewed_by, reviewed_at,
        student_evidence_id, supersedes_mapping_id,
        retired_at, retirement_reason
      ) values (
        v_new_id, v_new_profile_id, v_row.record_type,
        v_new_record_id, v_row.concept_id, 'PROPOSED', v_row.method,
        v_row.confidence, v_row.model_version, null, null,
        v_new_evidence_id,
        case when v_row.supersedes_mapping_id is null then null
          else (v_mapping_map ->> v_row.supersedes_mapping_id::text)::uuid
        end,
        null, null
      );

      if v_row.mapping_status = 'REJECTED' then
        perform public.review_student_record_concept_mapping(
          v_new_id, 'REJECTED', 'PROFILE_FORK_V021', v_new_evidence_id
        );
      elsif v_row.mapping_status = 'RETIRED' then
        perform public.review_student_record_concept_mapping(
          v_new_id, 'VERIFIED', 'PROFILE_FORK_V021', v_new_evidence_id
        );
        perform public.retire_student_record_concept_mapping(
          v_new_id,
          coalesce(v_row.retirement_reason, 'Recreated by PROFILE_FORK_V021')
        );
      end if;

      v_mapping_map := v_mapping_map || jsonb_build_object(
        v_row.student_mapping_id::text, v_new_id::text
      );
      v_mapping_done := v_mapping_done + 1;
      v_mapping_progress := v_mapping_progress + 1;
    end loop;

    if v_mapping_progress = 0 then
      raise exception using errcode = '55000',
        message = 'PROFILE_FORK_MAPPING_GRAPH_INVALID';
    end if;
  end loop;

  -- Mechanical graph closure: copied row counts must match and no target FK
  -- may alias a source-owned child identifier.
  if (select count(*) from public.student_data_completeness
      where profile_version_id = v_new_profile_id) <>
     (select count(*) from public.student_data_completeness
      where profile_version_id = p_source_profile_version_id)
     or (select count(*) from public.student_evidence_items
         where profile_version_id = v_new_profile_id) <>
        (select count(*) from public.student_evidence_items
         where profile_version_id = p_source_profile_version_id)
     or (select count(*) from public.student_degrees
         where profile_version_id = v_new_profile_id) <>
        (select count(*) from public.student_degrees
         where profile_version_id = p_source_profile_version_id)
     or (select count(*) from public.student_courses
         where profile_version_id = v_new_profile_id) <>
        (select count(*) from public.student_courses
         where profile_version_id = p_source_profile_version_id)
     or (select count(*) from public.student_test_scores
         where profile_version_id = v_new_profile_id) <>
        (select count(*) from public.student_test_scores
         where profile_version_id = p_source_profile_version_id)
     or (select count(*) from public.student_experiences
         where profile_version_id = v_new_profile_id) <>
        (select count(*) from public.student_experiences
         where profile_version_id = p_source_profile_version_id)
     or (select count(*) from public.student_skills
         where profile_version_id = v_new_profile_id) <>
        (select count(*) from public.student_skills
         where profile_version_id = p_source_profile_version_id)
     or (select count(*) from public.student_experience_skills
         where profile_version_id = v_new_profile_id) <>
        (select count(*) from public.student_experience_skills
         where profile_version_id = p_source_profile_version_id)
     or (select count(*) from public.student_goals
         where profile_version_id = v_new_profile_id) <>
        (select count(*) from public.student_goals
         where profile_version_id = p_source_profile_version_id)
     or (select count(*) from public.student_preferences
         where profile_version_id = v_new_profile_id) <>
        (select count(*) from public.student_preferences
         where profile_version_id = p_source_profile_version_id)
     or (select count(*) from public.student_record_concept_mappings
         where profile_version_id = v_new_profile_id) <> v_mapping_total then
    raise exception using errcode = '55000',
      message = 'PROFILE_FORK_GRAPH_INVALID';
  end if;

  if exists (
    select 1
    from public.student_data_completeness target
    where target.profile_version_id = v_new_profile_id
      and target.education_context_id in (
        select source.student_degree_id
        from public.student_degrees source
        where source.profile_version_id = p_source_profile_version_id
      )
    union all
    select 1
    from public.student_courses target
    where target.profile_version_id = v_new_profile_id
      and (
        target.student_degree_id in (
          select source.student_degree_id from public.student_degrees source
          where source.profile_version_id = p_source_profile_version_id
        )
        or target.student_evidence_id in (
          select source.student_evidence_id from public.student_evidence_items source
          where source.profile_version_id = p_source_profile_version_id
        )
      )
    union all
    select 1
    from public.student_experience_skills target
    where target.profile_version_id = v_new_profile_id
      and (
        target.student_experience_id in (
          select source.student_experience_id from public.student_experiences source
          where source.profile_version_id = p_source_profile_version_id
        )
        or target.student_skill_id in (
          select source.student_skill_id from public.student_skills source
          where source.profile_version_id = p_source_profile_version_id
        )
      )
    union all
    select 1
    from public.student_record_concept_mappings target
    where target.profile_version_id = v_new_profile_id
      and (
        target.student_record_id in (
          select source.student_degree_id from public.student_degrees source
          where source.profile_version_id = p_source_profile_version_id
          union all
          select source.student_course_id from public.student_courses source
          where source.profile_version_id = p_source_profile_version_id
        )
        or target.student_evidence_id in (
          select source.student_evidence_id from public.student_evidence_items source
          where source.profile_version_id = p_source_profile_version_id
        )
        or target.supersedes_mapping_id in (
          select source.student_mapping_id
          from public.student_record_concept_mappings source
          where source.profile_version_id = p_source_profile_version_id
        )
      )
  ) then
    raise exception using errcode = '55000',
      message = 'PROFILE_FORK_OLD_ID_ALIAS';
  end if;

  v_result := jsonb_build_object(
    'schemaVersion', 'PROFILE_OPERATION_RESULT_V021',
    'operation', 'FORK_FROZEN',
    'sourceProfileVersionId', p_source_profile_version_id,
    'profileVersionId', v_new_profile_id,
    'versionNumber', v_new_version_number,
    'status', 'DRAFT',
    'revision', 0
  );
  perform private.profile_store_operation_v019(
    v_student_id, p_operation_id, 'FORK_FROZEN', null,
    v_request_fingerprint, v_result
  );
  return v_result;
end;
$function$;

grant create on schema public to foundation_student_executor;
alter function public.fork_frozen_profile_to_draft_v021(uuid,uuid)
  owner to foundation_student_executor;
revoke create on schema public from foundation_student_executor;

revoke all on function public.fork_frozen_profile_to_draft_v021(uuid,uuid)
  from public, anon, authenticated, service_role, authenticator,
       foundation_catalog_executor, foundation_student_executor,
       foundation_evaluation_executor;
grant execute on function public.fork_frozen_profile_to_draft_v021(uuid,uuid)
  to authenticated;

insert into public.foundation_function_contracts (
  schema_name, function_name, identity_arguments, owner_role, prosecdef,
  search_path, allowed_caller_roles, body_digest
)
select namespace.nspname,
  procedure.proname,
  pg_get_function_identity_arguments(procedure.oid),
  procedure.proowner::regrole::text,
  procedure.prosecdef,
  'pg_catalog, public, private, extensions',
  array['authenticated']::text[],
  encode(
    extensions.digest(
      convert_to(pg_get_functiondef(procedure.oid), 'UTF8'), 'sha256'
    ),
    'hex'
  )
from pg_proc procedure
join pg_namespace namespace on namespace.oid = procedure.pronamespace
where namespace.nspname = 'public'
  and procedure.proname = 'fork_frozen_profile_to_draft_v021'
on conflict (schema_name, function_name, identity_arguments) do update
set owner_role = excluded.owner_role,
    prosecdef = excluded.prosecdef,
    search_path = excluded.search_path,
    allowed_caller_roles = excluded.allowed_caller_roles,
    body_digest = excluded.body_digest;

comment on function public.fork_frozen_profile_to_draft_v021(uuid,uuid) is
  'Owner-only atomic FROZEN-to-DRAFT deep fork. All profile-owned identifiers are regenerated and operation_id provides exact replay.';

do $assert$
declare
  v_function record;
begin
  select procedure.proowner::regrole::text as owner_role,
    procedure.prosecdef,
    procedure.proconfig,
    pg_get_function_identity_arguments(procedure.oid) as identity_arguments
  into strict v_function
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'fork_frozen_profile_to_draft_v021';

  if v_function.owner_role <> 'foundation_student_executor'
     or not v_function.prosecdef
     or v_function.proconfig is distinct from
       array['search_path=pg_catalog, public, private, extensions']::text[]
     or v_function.identity_arguments <> 'p_source_profile_version_id uuid, p_operation_id uuid' then
    raise exception '021 assertion failed: fork function contract';
  end if;

  if not has_function_privilege(
    'authenticated',
    'public.fork_frozen_profile_to_draft_v021(uuid,uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.fork_frozen_profile_to_draft_v021(uuid,uuid)',
    'EXECUTE'
  ) or has_function_privilege(
    'service_role',
    'public.fork_frozen_profile_to_draft_v021(uuid,uuid)',
    'EXECUTE'
  ) then
    raise exception '021 assertion failed: fork function ACL';
  end if;

  if exists (
    select 1
    from information_schema.routine_privileges privilege
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
        'freeze_profile_draft_v019',
        'fork_frozen_profile_to_draft_v021'
      )
  ) then
    raise exception '021 assertion failed: authenticated EXECUTE whitelist';
  end if;

  if pg_get_constraintdef(
       (select constraint_value.oid
        from pg_constraint constraint_value
        where constraint_value.conrelid =
          'private.profile_capability_operations_v019'::regclass
          and constraint_value.conname = 'profile_operations_kind_closed')
     ) not like '%FORK_FROZEN%' then
    raise exception '021 assertion failed: operation kind is not closed';
  end if;
end;
$assert$;

commit;
