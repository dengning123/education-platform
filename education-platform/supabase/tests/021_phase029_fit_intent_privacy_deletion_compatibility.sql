-- Run after Migration 029. Application/Outcome remains planning-only under a
-- provisional future Migration 030 identity.
begin;

do $test$
declare
  v_owner_auth constant uuid := 'a2900000-0000-4000-8000-000000000001';
  v_student uuid;
  v_spare_student constant uuid := 'a2900000-0000-4000-8000-000000000003';
  v_profile uuid;
  v_intent uuid;
  v_declaration uuid;
  v_international_declaration uuid := extensions.gen_random_uuid();
  v_international_assertion uuid;
  v_concept uuid;
  v_assertion uuid;
  v_access uuid;
  v_revision bigint := 0;
  v_result jsonb;
  v_domain public.student_data_domain;
  v_dimension public.fit_dimension;
  v_blocked boolean;
  v_before_product bigint;
  v_before_declarations bigint;
  v_before_operations bigint;
  v_before_taxonomy bigint;
  v_before_programs bigint;
  v_before_sources bigint;
  v_before_builds bigint;
begin
  if to_regprocedure(
    'private.guard_fit_intent_product_write_v027()'
  ) is null then
    raise exception '029 guard compatibility repair is missing';
  end if;

  insert into auth.users (id, email)
  values (v_owner_auth, 'phase029-owner@test.invalid');
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();

  v_result := public.create_or_resume_profile_draft_v019(
    extensions.gen_random_uuid()
  );
  v_profile := (v_result ->> 'profileVersionId')::uuid;
  foreach v_domain in array enum_range(null::public.student_data_domain)
  loop
    perform public.mutate_profile_draft_v019(
      v_profile, extensions.gen_random_uuid(), v_revision,
      'COMPLETENESS_UPSERT', jsonb_build_object(
        'educationContextId', null,
        'domain', v_domain,
        'completeness', 'COMPLETE',
        'explanation', null
      )
    );
    v_revision := v_revision + 1;
  end loop;
  perform public.freeze_profile_draft_v019(
    v_profile, extensions.gen_random_uuid(), v_revision
  );

  v_result := public.create_or_resume_fit_intent_draft_v027(
    v_profile, extensions.gen_random_uuid()
  );
  v_intent := (v_result ->> 'intentSetId')::uuid;
  v_result := public.mutate_fit_intent_draft_v027(
    v_intent, extensions.gen_random_uuid(), 0,
    'DECLARATION_CREATE', jsonb_build_object(
      'declaration', jsonb_build_object(
        'dimension', 'GEOGRAPHIC_DELIVERY',
        'semanticType', 'DELIVERY_CONSTRAINT',
        'importance', 'PREFERRED',
        'importanceConfirmedByStudent', false,
        'typedValue', jsonb_build_object(
          'deliveryMode', 'ONLINE', 'relation', 'DESIRED'
        )
      )
    )
  );
  v_declaration := (v_result ->> 'resourceId')::uuid;
  v_revision := 1;
  foreach v_dimension in array array[
    'ACADEMIC','CAREER','FINANCIAL','PERSONAL_PREFERENCE'
  ]::public.fit_dimension[]
  loop
    perform public.mutate_fit_intent_draft_v027(
      v_intent, extensions.gen_random_uuid(), v_revision,
      'DIMENSION_MARK_NOT_SUPPLIED',
      jsonb_build_object('dimension', v_dimension)
    );
    v_revision := v_revision + 1;
  end loop;
  execute 'reset role';
  select profile.student_id into strict v_student
  from public.student_profile_versions profile
  where profile.profile_version_id = v_profile;

  -- The golden catalog has no active international access option. Seed only
  -- the exact typed, self-asserted product storage shape so privacy closure
  -- covers the M027 access-context relation without inventing product data.
  perform set_config('app.fit_intent_product_v027_write', 'on', true);
  select concept.concept_id into strict v_concept
  from public.taxonomy_concepts concept
  join private.fit_intent_product_states_v027 state
    on state.intent_set_id = v_intent
   and concept.introduced_release_ordinal <= state.taxonomy_release_ordinal
   and (
     concept.retired_release_ordinal is null
     or concept.retired_release_ordinal > state.taxonomy_release_ordinal
   )
  where concept.concept_kind = 'CAREER'
    and concept.retired_in_release is null
  order by concept.concept_id
  limit 1;
  update private.fit_intent_dimension_states_v027 state
  set disposition = 'DECLARED'
  where state.intent_set_id = v_intent
    and state.dimension = 'INTERNATIONAL_ACCESSIBILITY';
  insert into private.fit_intent_student_assertions_v027 (
    intent_set_id, profile_version_id, assertion_kind, dimension,
    semantic_payload_hash
  ) values (
    v_intent, v_profile, 'INTENT_DECLARATION',
    'INTERNATIONAL_ACCESSIBILITY', repeat('b', 64)
  ) returning assertion_id into v_international_assertion;
  insert into public.fit_intent_declarations (
    intent_declaration_id, intent_set_id, profile_version_id,
    origin, dimension, semantic_type, importance, importance_basis,
    importance_confirmed_by_student, interpretation_method,
    interpretation_method_version, interpretation_provenance,
    student_assertion_id
  ) values (
    v_international_declaration, v_intent, v_profile,
    'PHASE3_DECLARATION', 'INTERNATIONAL_ACCESSIBILITY',
    'TAXONOMY_TARGET', 'PREFERRED',
    'STRUCTURED_STUDENT_DECLARATION', false, 'HUMAN',
    'PHASE029_PRIVACY_FIXTURE', 'SELF_ASSERTED',
    v_international_assertion
  );
  insert into public.fit_intent_taxonomy_targets (
    intent_declaration_id, intent_set_id, profile_version_id,
    concept_id, relation
  ) values (
    v_international_declaration, v_intent, v_profile,
    v_concept, 'DESIRED'
  );
  insert into private.fit_intent_student_assertions_v027 (
    intent_set_id, profile_version_id, assertion_kind, dimension,
    semantic_payload_hash
  ) values (
    v_intent, v_profile, 'ACCESS_CONTEXT',
    'INTERNATIONAL_ACCESSIBILITY', repeat('a', 64)
  ) returning assertion_id into v_assertion;
  insert into private.fit_student_access_contexts (
    intent_set_id, profile_version_id, governing_jurisdiction_code,
    target_path_code, provenance, student_assertion_id
  ) values (
    v_intent, v_profile, 'US', 'F1',
    'SELF_ASSERTED:PHASE029_PRIVACY_FIXTURE', v_assertion
  ) returning access_context_id into v_access;
  perform set_config('app.fit_intent_product_v027_write', 'off', true);

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  perform public.freeze_fit_intent_draft_v027(
    v_intent, extensions.gen_random_uuid(), v_revision
  );
  execute 'reset role';

  select count(*) into v_before_product
  from private.fit_intent_product_states_v027 state
  where state.intent_set_id = v_intent;
  select count(*) into v_before_declarations
  from public.fit_intent_declarations declaration
  where declaration.intent_set_id = v_intent;
  select count(*) into v_before_operations
  from private.fit_intent_operations_v027 operation
  where operation.student_id = v_student;
  select count(*) into v_before_taxonomy from public.taxonomy_concepts;
  select count(*) into v_before_programs from public.program_versions;
  select count(*) into v_before_sources from public.sources;
  select count(*) into v_before_builds from public.fit_evaluator_builds;

  -- Browser/session roles have no direct DML authority.
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    delete from public.fit_intent_declarations
    where intent_declaration_id = v_declaration;
  exception when others then
    v_blocked := true;
  end;
  execute 'reset role';
  if not v_blocked or not exists (
    select 1 from public.fit_intent_declarations
    where intent_declaration_id = v_declaration
  ) then
    raise exception '029 authenticated direct delete was not closed';
  end if;

  execute 'set local role service_role';
  v_blocked := false;
  begin
    delete from public.fit_intent_declarations
    where intent_declaration_id = v_declaration;
  exception when others then
    v_blocked := true;
  end;
  execute 'reset role';
  if not v_blocked or not exists (
    select 1 from public.fit_intent_declarations
    where intent_declaration_id = v_declaration
  ) then
    raise exception '029 service-role direct delete was not closed';
  end if;

  -- The executor and installer can reach the table, but ordinary direct and
  -- partial child deletes must still be rejected by the M027 command guard.
  execute 'set local role foundation_student_executor';
  v_blocked := false;
  begin
    delete from public.fit_intent_declarations
    where intent_declaration_id = v_declaration;
  exception when others then
    v_blocked := sqlerrm in (
      'FIT_INTENT_PRODUCT_COMMAND_REQUIRED',
      'Frozen Fit intent content is immutable'
    );
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception '029 executor direct delete bypassed product command';
  end if;

  v_blocked := false;
  begin
    delete from public.fit_intent_delivery_constraints
    where intent_declaration_id = v_declaration;
  exception when others then
    v_blocked := sqlerrm in (
      'FIT_INTENT_PRODUCT_COMMAND_REQUIRED',
      'Frozen Fit intent content is immutable'
    );
  end;
  if not v_blocked then
    raise exception '029 partial child delete bypassed product command';
  end if;

  -- No caller-controlled setting authorizes privacy deletion.
  perform set_config('app.student_privacy_delete', 'on', true);
  v_blocked := false;
  begin
    delete from public.fit_intent_declarations
    where intent_declaration_id = v_declaration;
  exception when others then
    v_blocked := sqlerrm in (
      'FIT_INTENT_PRODUCT_COMMAND_REQUIRED',
      'Frozen Fit intent content is immutable'
    );
  end;
  perform set_config('app.student_privacy_delete', 'off', true);
  if not v_blocked then
    raise exception '029 spoofed setting authorized direct deletion';
  end if;

  -- A completed deletion for a different student leaves no reusable or stale
  -- transaction authorization for this graph.
  perform public.create_student(v_spare_student);
  perform public.delete_student_data(v_spare_student, 'TEST_LIFECYCLE');
  v_blocked := false;
  begin
    delete from public.fit_intent_declarations
    where intent_declaration_id = v_declaration;
  exception when others then
    v_blocked := sqlerrm in (
      'FIT_INTENT_PRODUCT_COMMAND_REQUIRED',
      'Frozen Fit intent content is immutable'
    );
  end;
  if not v_blocked or exists (
    select 1 from private.student_deletion_authorizations authorization_row
    where authorization_row.transaction_id = txid_current()
  ) then
    raise exception '029 stale/cross-student authorization was reusable';
  end if;

  -- Force a late failure after the student cascade. The whole privacy graph,
  -- authorization row, and parent must roll back atomically.
  create function private.phase029_injected_tombstone_failure()
  returns trigger
  language plpgsql
  security definer
  set search_path = pg_catalog, public, private, extensions
  as $failure$
  begin
    raise exception using errcode = 'P0001',
      message = 'PHASE029_INJECTED_FAILURE';
  end;
  $failure$;
  create trigger phase029_injected_tombstone_failure
  before insert on public.student_deletion_tombstones
  for each row execute function private.phase029_injected_tombstone_failure();

  v_blocked := false;
  begin
    perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  exception when raise_exception then
    v_blocked := sqlerrm = 'PHASE029_INJECTED_FAILURE';
  end;
  if not v_blocked
     or not exists (
       select 1 from public.students where student_id = v_student
     )
     or (select count(*) from private.fit_intent_product_states_v027
         where intent_set_id = v_intent) <> v_before_product
     or (select count(*) from public.fit_intent_declarations
         where intent_set_id = v_intent) <> v_before_declarations
     or (select count(*) from private.fit_intent_operations_v027
         where student_id = v_student) <> v_before_operations
     or exists (
       select 1 from private.student_deletion_authorizations authorization_row
       where authorization_row.transaction_id = txid_current()
     ) then
    raise exception '029 injected failure did not roll back atomically';
  end if;

  drop trigger phase029_injected_tombstone_failure
    on public.student_deletion_tombstones;
  drop function private.phase029_injected_tombstone_failure();

  -- Only the established service-only privacy lifecycle may delete the graph.
  execute 'set local role service_role';
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  execute 'reset role';

  if exists (
    select 1 from public.students where student_id = v_student
  ) or exists (
    select 1 from public.student_profile_versions
    where profile_version_id = v_profile
  ) or exists (
    select 1 from public.student_data_completeness
    where profile_version_id = v_profile
  ) or exists (
    select 1 from public.fit_intent_sets where intent_set_id = v_intent
  ) or exists (
    select 1 from public.fit_intent_declarations
    where intent_set_id = v_intent
  ) or exists (
    select 1 from public.fit_intent_delivery_constraints
    where intent_declaration_id = v_declaration
  ) or exists (
    select 1 from private.fit_intent_product_states_v027
    where intent_set_id = v_intent
  ) or exists (
    select 1 from private.fit_intent_dimension_states_v027
    where intent_set_id = v_intent
  ) or exists (
    select 1 from private.fit_intent_student_assertions_v027
    where intent_set_id = v_intent
  ) or exists (
    select 1 from private.fit_intent_operations_v027
    where student_id = v_student
  ) or exists (
    select 1 from private.fit_student_access_contexts
    where access_context_id = v_access
  ) or exists (
    select 1 from public.eligibility_evaluations
    where profile_version_id = v_profile
  ) or exists (
    select 1 from public.fit_evaluations
    where profile_version_id = v_profile
  ) or exists (
    select 1 from private.student_deletion_authorizations authorization_row
    where authorization_row.transaction_id = txid_current()
  ) then
    raise exception '029 authorized privacy deletion left student-linked state';
  end if;

  if (select count(*) from public.taxonomy_concepts) <> v_before_taxonomy
     or (select count(*) from public.program_versions) <> v_before_programs
     or (select count(*) from public.sources) <> v_before_sources
     or (select count(*) from public.fit_evaluator_builds) <> v_before_builds then
    raise exception '029 privacy deletion changed global catalog state';
  end if;
end;
$test$;

rollback;

select 'PHASE029_FIT_INTENT_PRIVACY_COMPATIBILITY_PASS';
