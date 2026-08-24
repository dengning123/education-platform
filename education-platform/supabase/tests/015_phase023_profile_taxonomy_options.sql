-- Runs after Migration 023. Application/Outcome remains planning-only under
-- a provisional future Migration 024 identity.

begin;

do $test$
declare
  v_auth_user constant uuid := '96200000-0000-4000-8000-000000000001';
  v_student constant uuid := '96200000-0000-4000-8000-000000000011';
  v_active_skill constant uuid := '96200000-0000-4000-8000-000000000021';
  v_draft_skill constant uuid := '96200000-0000-4000-8000-000000000022';
  v_result jsonb;
  v_options jsonb;
  v_keys text[];
  v_order text[];
  v_blocked boolean;
  v_function_oid oid;
  v_retired_skill uuid;
  v_kind text;
  i integer;
begin
  perform set_config('statement_timeout', '30s', true);

  select procedure.oid
  into strict v_function_oid
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'public'
    and procedure.proname = 'get_profile_taxonomy_options_v023'
    and pg_get_function_identity_arguments(procedure.oid) =
      'p_concept_kind text';

  if exists (
    select 1
    from unnest(coalesce((
      select procedure.proargnames
      from pg_proc procedure
      where procedure.oid = v_function_oid
    ), array[]::text[])) argument_name
    where argument_name in (
      'student_id', 'p_student_id', 'profile_version_id',
      'p_profile_version_id', 'concept_ids', 'p_concept_ids',
      'query', 'p_query', 'limit', 'p_limit'
    )
  ) then
    raise exception '023 options accepts ownership, enumeration, or search input';
  end if;

  if not has_function_privilege(
    'authenticated', v_function_oid, 'EXECUTE'
  ) or has_function_privilege(
    'anon', v_function_oid, 'EXECUTE'
  ) or has_function_privilege(
    'service_role', v_function_oid, 'EXECUTE'
  ) or has_function_privilege(
    'authenticator', v_function_oid, 'EXECUTE'
  ) or has_function_privilege(
    'foundation_catalog_executor', v_function_oid, 'EXECUTE'
  ) or has_function_privilege(
    'foundation_evaluation_executor', v_function_oid, 'EXECUTE'
  ) then
    raise exception '023 options ACL drifted';
  end if;

  if has_table_privilege(
    'authenticated', 'public.taxonomy_releases', 'SELECT'
  ) or has_table_privilege(
    'authenticated', 'public.taxonomy_concepts', 'SELECT'
  ) or has_table_privilege(
    'authenticated', 'public.taxonomy_aliases', 'SELECT'
  ) or has_table_privilege(
    'authenticated', 'public.taxonomy_relationships', 'SELECT'
  ) then
    raise exception '023 options expanded direct taxonomy table access';
  end if;

  v_blocked := false;
  begin
    execute 'set local role anon';
    perform public.get_profile_taxonomy_options_v023('ASSESSMENT');
  exception when insufficient_privilege then
    v_blocked := true;
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception 'Anonymous taxonomy options was not rejected';
  end if;

  insert into auth.users (id, email)
  values (v_auth_user, 'phase023-owner@test.invalid');
  perform public.create_student(v_student);
  insert into private.student_identities (auth_user_id, student_id)
  values (v_auth_user, v_student);

  perform set_config('request.jwt.claim.sub', v_auth_user::text, true);
  execute 'set local role authenticated';

  v_result := public.get_profile_taxonomy_options_v023('ASSESSMENT');
  if v_result ->> 'schemaVersion' <>
       'PROFILE_TAXONOMY_OPTIONS_V023'
     or v_result ->> 'releaseCode' <> 'v0.1'
     or (v_result ->> 'releaseOrdinal')::bigint <> 1
     or v_result ->> 'conceptKind' <> 'ASSESSMENT'
     or jsonb_array_length(v_result -> 'options') <> 4 then
    raise exception '023 ASSESSMENT seed inventory drifted: %', v_result;
  end if;

  select array_agg(key order by key)
  into v_keys
  from jsonb_object_keys(v_result) key;
  if v_keys is distinct from array[
    'conceptKind', 'options', 'releaseCode', 'releaseOrdinal', 'schemaVersion'
  ] then
    raise exception '023 top-level DTO is not closed: %', v_keys;
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_result -> 'options') option
    cross join lateral (
      select array_agg(key order by key) as keys
      from jsonb_object_keys(option) key
    ) shape
    where shape.keys is distinct from
      array['canonicalKey', 'conceptId', 'displayName']
  ) then
    raise exception '023 option DTO is not closed';
  end if;

  select array_agg(option ->> 'canonicalKey' order by ordinal)
  into v_order
  from jsonb_array_elements(v_result -> 'options')
    with ordinality listed(option, ordinal);
  if v_order is distinct from array[
    'ASSESSMENT.GMAT', 'ASSESSMENT.GRE',
    'ASSESSMENT.IELTS', 'ASSESSMENT.TOEFL'
  ] then
    raise exception '023 ASSESSMENT order drifted: %', v_order;
  end if;
  if v_result::text ~
       '(aliases|relationships|description|reviewed|verifiedBy|retired)' then
    raise exception '023 ASSESSMENT response leaked non-option fields';
  end if;

  v_result := public.get_profile_taxonomy_options_v023('SKILL');
  select array_agg(option ->> 'canonicalKey' order by ordinal)
  into v_order
  from jsonb_array_elements(v_result -> 'options')
    with ordinality listed(option, ordinal);
  if v_result ->> 'conceptKind' <> 'SKILL'
     or v_order is distinct from
       array['SKILL.PYTHON', 'SKILL.R', 'SKILL.SQL'] then
    raise exception '023 SKILL seed inventory drifted: %', v_result;
  end if;

  foreach v_kind in array array[
    'SUBJECT', 'FIELD', 'COURSE_CONCEPT',
    'CAREER', 'INDUSTRY', 'assessment'
  ]
  loop
    v_blocked := false;
    begin
      perform public.get_profile_taxonomy_options_v023(v_kind);
    exception when sqlstate '22023' then
      if sqlerrm = 'PROFILE_TAXONOMY_KIND_NOT_ALLOWED' then
        v_blocked := true;
      else
        raise;
      end if;
    end;
    if not v_blocked then
      raise exception '023 accepted disallowed taxonomy kind: %', v_kind;
    end if;
  end loop;

  v_blocked := false;
  begin
    perform public.get_profile_taxonomy_options_v023(null);
  exception when sqlstate '22023' then
    if sqlerrm = 'PROFILE_TAXONOMY_KIND_NOT_ALLOWED' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception '023 accepted a null taxonomy kind';
  end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub', '', true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.get_profile_taxonomy_options_v023('ASSESSMENT');
  exception when sqlstate 'P0002' then
    if sqlerrm = 'PROFILE_NOT_FOUND' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception '023 options did not require a trusted active subject';
  end if;

  select concept_id
  into strict v_retired_skill
  from public.taxonomy_concepts
  where canonical_key = 'SKILL.R';

  execute 'set local role foundation_catalog_executor';
  perform public.create_taxonomy_release(
    'v0.2', '2026-08-24T00:00:00Z', 'Phase 023 verified fixture'
  );
  perform public.create_taxonomy_concept(jsonb_populate_record(
    null::public.taxonomy_concepts,
    jsonb_build_object(
      'concept_id', v_active_skill,
      'canonical_key', 'SKILL.PHASE023_ACTIVE',
      'concept_kind', 'SKILL',
      'display_name', 'Phase 023 Active Skill',
      'description', 'Must never cross the options DTO.',
      'introduced_in_release', 'v0.2'
    )
  ));
  perform public.retire_taxonomy_concept(
    v_retired_skill, 'v0.2', 'Phase 023 historical option fixture'
  );
  perform public.verify_taxonomy_release('v0.2', 'PHASE023_TEST');
  perform public.create_taxonomy_release(
    'v0.3', '2026-08-25T00:00:00Z', 'Phase 023 DRAFT fixture'
  );
  perform public.create_taxonomy_concept(jsonb_populate_record(
    null::public.taxonomy_concepts,
    jsonb_build_object(
      'concept_id', v_draft_skill,
      'canonical_key', 'SKILL.PHASE023_DRAFT',
      'concept_kind', 'SKILL',
      'display_name', 'Phase 023 Draft Skill',
      'introduced_in_release', 'v0.3'
    )
  ));
  execute 'reset role';

  perform set_config('request.jwt.claim.sub', v_auth_user::text, true);
  execute 'set local role authenticated';
  v_result := public.get_profile_taxonomy_options_v023('SKILL');
  execute 'reset role';
  if v_result ->> 'releaseCode' <> 'v0.2'
     or (v_result ->> 'releaseOrdinal')::bigint <> 2
     or exists (
       select 1
       from jsonb_array_elements(v_result -> 'options') option
       where option ->> 'canonicalKey' in ('SKILL.R', 'SKILL.PHASE023_DRAFT')
     )
     or not exists (
       select 1
       from jsonb_array_elements(v_result -> 'options') option
       where option ->> 'canonicalKey' = 'SKILL.PHASE023_ACTIVE'
     ) then
    raise exception '023 release interval semantics drifted: %', v_result;
  end if;

  v_blocked := false;
  begin
    execute 'set local role foundation_catalog_executor';
    perform public.create_taxonomy_release(
      'v0.4', '2026-08-26T00:00:00Z', 'Phase 023 length fixture'
    );
    perform public.create_taxonomy_concept(jsonb_populate_record(
      null::public.taxonomy_concepts,
      jsonb_build_object(
        'canonical_key', 'ASSESSMENT.PHASE023_TOO_LONG',
        'concept_kind', 'ASSESSMENT',
        'display_name', repeat('x', 257),
        'introduced_in_release', 'v0.4'
      )
    ));
    perform public.verify_taxonomy_release('v0.4', 'PHASE023_TEST');
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', v_auth_user::text, true);
    execute 'set local role authenticated';
    perform public.get_profile_taxonomy_options_v023('ASSESSMENT');
  exception when sqlstate '54000' then
    if sqlerrm = 'PROFILE_TAXONOMY_OPTION_VALUE_TOO_LONG' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception '023 did not fail closed for an oversized option';
  end if;

  v_blocked := false;
  begin
    execute 'set local role foundation_catalog_executor';
    perform public.create_taxonomy_release(
      'v0.4', '2026-08-26T00:00:00Z', 'Phase 023 count fixture'
    );
    for i in 1..65
    loop
      perform public.create_taxonomy_concept(jsonb_populate_record(
        null::public.taxonomy_concepts,
        jsonb_build_object(
          'canonical_key',
            'SKILL.PHASE023_' || pg_catalog.lpad(i::text, 3, '0'),
          'concept_kind', 'SKILL',
          'display_name', 'Phase 023 Skill ' || i::text,
          'introduced_in_release', 'v0.4'
        )
      ));
    end loop;
    perform public.verify_taxonomy_release('v0.4', 'PHASE023_TEST');
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', v_auth_user::text, true);
    execute 'set local role authenticated';
    perform public.get_profile_taxonomy_options_v023('SKILL');
  exception when sqlstate '54000' then
    if sqlerrm = 'PROFILE_TAXONOMY_OPTION_LIMIT_EXCEEDED' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception '023 did not fail closed above the option count limit';
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  execute 'reset role';
  if exists (
    select 1
    from private.student_identities
    where student_id = v_student
  ) then
    raise exception '023 options use survived Profile privacy deletion';
  end if;
end;
$test$;

rollback;
