-- Run after Migration 027 Real Student Fit Intent capability core.

begin;

do $test$
declare
  v_owner_auth constant uuid := 'a2700000-0000-4000-8000-000000000001';
  v_other_auth constant uuid := 'a2700000-0000-4000-8000-000000000002';
  v_profile_id uuid;
  v_student_id uuid;
  v_intent_id uuid;
  v_program_id uuid;
  v_revision bigint := 0;
  v_result jsonb;
  v_replay jsonb;
  v_operation uuid := 'a2700000-0000-4000-8000-000000000101';
  v_mutation_operation uuid :=
    'a2700000-0000-4000-8000-000000000102';
  v_delivery_id uuid;
  v_dimension public.fit_dimension;
  v_domain public.student_data_domain;
  v_blocked boolean;
begin
  if to_regprocedure(
    'public.create_or_resume_fit_intent_draft_v027(uuid,uuid)'
  ) is null then
    raise exception '027 product capability is missing';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.mutate_fit_intent_draft_v027(uuid,uuid,bigint,public.fit_intent_product_command_v027,jsonb)',
    'EXECUTE'
  ) or has_function_privilege(
    'anon',
    'public.mutate_fit_intent_draft_v027(uuid,uuid,bigint,public.fit_intent_product_command_v027,jsonb)',
    'EXECUTE'
  ) or has_table_privilege(
    'authenticated','private.fit_intent_student_assertions_v027','SELECT'
  ) then
    raise exception '027 capability ACL is not closed';
  end if;

  insert into auth.users (id, email) values
    (v_owner_auth, 'phase027-owner@test.invalid'),
    (v_other_auth, 'phase027-other@test.invalid');
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();
  v_result := public.create_or_resume_profile_draft_v019(
    extensions.gen_random_uuid()
  );
  v_profile_id := (v_result ->> 'profileVersionId')::uuid;
  foreach v_domain in array enum_range(null::public.student_data_domain)
  loop
    perform public.mutate_profile_draft_v019(
      v_profile_id, extensions.gen_random_uuid(), v_revision,
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
    v_profile_id, extensions.gen_random_uuid(), v_revision
  );

  v_result := public.create_or_resume_fit_intent_draft_v027(
    v_profile_id, v_operation
  );
  v_replay := public.create_or_resume_fit_intent_draft_v027(
    v_profile_id, v_operation
  );
  if v_result is distinct from v_replay then
    raise exception '027 create replay diverged';
  end if;
  v_intent_id := (v_result ->> 'intentSetId')::uuid;
  if jsonb_array_length(
       public.get_fit_intent_document_v027(v_intent_id) -> 'dimensions'
     ) <> 6 then
    raise exception '027 did not create exactly six dimension states';
  end if;
  v_result := public.get_fit_intent_taxonomy_options_v027(
    v_intent_id, 'ACADEMIC'
  );
  if v_result ->> 'schemaVersion' <>
       'FIT_INTENT_TAXONOMY_OPTIONS_V027'
     or jsonb_typeof(v_result -> 'options') <> 'array' then
    raise exception '027 taxonomy options contract failed';
  end if;

  v_blocked := false;
  begin
    perform public.create_or_resume_fit_intent_draft_v027(
      v_profile_id, v_operation
    );
  exception when others then
    v_blocked := sqlerrm = 'FIT_INTENT_OPERATION_CONFLICT';
  end;
  if v_blocked then
    raise exception '027 exact replay unexpectedly conflicted';
  end if;

  v_result := public.mutate_fit_intent_draft_v027(
    v_intent_id, v_mutation_operation, 0,
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
  v_delivery_id := (v_result ->> 'resourceId')::uuid;
  v_blocked := false;
  begin
    perform public.mutate_fit_intent_draft_v027(
      v_intent_id, v_mutation_operation, 0,
      'DECLARATION_CREATE', jsonb_build_object(
        'declaration', jsonb_build_object(
          'dimension', 'GEOGRAPHIC_DELIVERY',
          'semanticType', 'DELIVERY_CONSTRAINT',
          'importance', 'PREFERRED',
          'importanceConfirmedByStudent', false,
          'typedValue', jsonb_build_object(
            'deliveryMode', 'HYBRID', 'relation', 'DESIRED'
          )
        )
      )
    );
  exception when unique_violation then
    v_blocked := sqlerrm = 'FIT_INTENT_OPERATION_CONFLICT';
  end;
  if not v_blocked then
    raise exception '027 conflicting replay did not fail closed';
  end if;
  v_revision := 1;
  foreach v_dimension in array array[
    'ACADEMIC','CAREER','FINANCIAL','PERSONAL_PREFERENCE',
    'INTERNATIONAL_ACCESSIBILITY'
  ]::public.fit_dimension[]
  loop
    perform public.mutate_fit_intent_draft_v027(
      v_intent_id, extensions.gen_random_uuid(), v_revision,
      'DIMENSION_MARK_NOT_SUPPLIED',
      jsonb_build_object('dimension', v_dimension)
    );
    v_revision := v_revision + 1;
  end loop;
  execute 'reset role';
  if exists (
    select 1 from public.fit_intent_declarations declaration
    where declaration.intent_set_id = v_intent_id
      and declaration.dimension <> 'GEOGRAPHIC_DELIVERY'
  ) then
    raise exception '027 explicit-not-supplied fabricated an intent';
  end if;
  if not exists (
    select 1 from public.fit_intent_declarations declaration
    join private.fit_intent_student_assertions_v027 assertion
      on assertion.assertion_id = declaration.student_assertion_id
    where declaration.intent_declaration_id = v_delivery_id
      and declaration.interpretation_provenance = 'SELF_ASSERTED'
      and assertion.assertion_kind = 'INTENT_DECLARATION'
  ) then
    raise exception '027 student self-assertion provenance is missing';
  end if;
  if exists (
    select 1 from public.student_evidence_items evidence
    where evidence.profile_version_id = v_profile_id
      and evidence.student_evidence_id in (
        select declaration.student_assertion_id
        from public.fit_intent_declarations declaration
        where declaration.intent_set_id = v_intent_id
      )
  ) then
    raise exception '027 self-assertion escaped into evidence authority';
  end if;

  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_blocked := false;
  begin
    perform public.mutate_fit_intent_draft_v027(
      v_intent_id, extensions.gen_random_uuid(), v_revision,
      'DECLARATION_CREATE', jsonb_build_object(
        'declaration', jsonb_build_object(
          'dimension', 'ACADEMIC',
          'semanticType', 'DELIVERY_CONSTRAINT',
          'importance', 'NEUTRAL',
          'importanceConfirmedByStudent', false,
          'typedValue', jsonb_build_object(
            'deliveryMode', 'ONLINE', 'relation', 'DESIRED'
          )
        )
      )
    );
  exception when others then
    v_blocked := sqlerrm in (
      'FIT_INTENT_NOT_SUPPLIED_CONFLICT',
      'FIT_INTENT_DIMENSION_TYPE_MISMATCH'
    );
  end;
  if not v_blocked then
    raise exception '027 invalid/fake declaration did not fail closed';
  end if;

  v_blocked := false;
  begin
    perform public.freeze_fit_intent_set(v_intent_id);
  exception when insufficient_privilege then
    v_blocked := true;
  end;
  if not v_blocked or public.get_fit_intent_document_v027(v_intent_id)
      ->> 'status' <> 'DRAFT' then
    raise exception '027 legacy freeze bypass was not blocked';
  end if;

  v_result := public.freeze_fit_intent_draft_v027(
    v_intent_id, extensions.gen_random_uuid(), v_revision
  );
  if v_result ->> 'status' <> 'FROZEN'
     or (v_result ->> 'snapshotHash') !~ '^[a-f0-9]{64}$' then
    raise exception '027 freeze result is invalid';
  end if;
  execute 'reset role';
  select version.program_version_id into strict v_program_id
  from public.program_versions version
  order by version.program_version_id limit 1;
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  execute 'set local role authenticated';
  v_result := public.get_fit_evaluation_assembly_v027(
    v_profile_id, v_intent_id, v_program_id
  );
  if not exists (
    select 1 from jsonb_array_elements(v_result -> 'dimensions') dimension
    where dimension ->> 'dimension' = 'ACADEMIC'
      and dimension ->> 'disposition' = 'EXPLICIT_NOT_SUPPLIED'
      and dimension ->> 'inputAvailability' = 'NOT_SUPPLIED'
  ) then
    raise exception '027 explicit not supplied did not assemble as NOT_SUPPLIED';
  end if;

  execute 'reset role';
  select profile.student_id into strict v_student_id
  from public.student_profile_versions profile
  where profile.profile_version_id = v_profile_id;
  perform set_config('request.jwt.claim.sub', v_other_auth::text, true);
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();
  v_blocked := false;
  begin
    perform public.get_fit_intent_document_v027(v_intent_id);
  exception when no_data_found then
    v_blocked := sqlerrm = 'FIT_INTENT_NOT_FOUND';
  end;
  execute 'reset role';
  if not v_blocked then
    raise exception '027 unrelated user enumerated owner intent';
  end if;

  perform public.delete_student_data(v_student_id, 'TEST_LIFECYCLE');
  if exists (
    select 1 from private.fit_intent_product_states_v027 state
    where state.intent_set_id = v_intent_id
  ) or exists (
    select 1 from private.fit_intent_student_assertions_v027 assertion
    where assertion.intent_set_id = v_intent_id
  ) then
    raise exception '027 privacy deletion left product intent state';
  end if;
end;
$test$;

rollback;

select 'PHASE027_FIT_INTENT_PRODUCT_PASS';
