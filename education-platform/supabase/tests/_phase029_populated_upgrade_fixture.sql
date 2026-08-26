-- Run after Migration 028 and before Migration 029 on a disposable database.
create table private.phase029_upgrade_capture (
  student_id uuid not null,
  auth_user_id uuid not null,
  profile_version_id uuid not null,
  intent_set_id uuid not null,
  intent_declaration_id uuid not null,
  graph_fingerprint text not null,
  taxonomy_count bigint not null,
  program_count bigint not null,
  source_count bigint not null
);

do $fixture$
declare
  v_auth constant uuid := 'a2920000-0000-4000-8000-000000000001';
  v_profile uuid;
  v_student uuid;
  v_intent uuid;
  v_declaration uuid;
  v_result jsonb;
  v_revision bigint := 0;
  v_domain public.student_data_domain;
begin
  insert into auth.users (id, email)
  values (v_auth, 'phase029-upgrade@test.invalid');
  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();
  v_result := public.create_or_resume_profile_draft_v019(
    'a2920000-0000-4000-8000-000000000010'
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
    v_profile, 'a2920000-0000-4000-8000-000000000011', v_revision
  );
  v_result := public.create_or_resume_fit_intent_draft_v027(
    v_profile, 'a2920000-0000-4000-8000-000000000012'
  );
  v_intent := (v_result ->> 'intentSetId')::uuid;
  v_result := public.mutate_fit_intent_draft_v027(
    v_intent, 'a2920000-0000-4000-8000-000000000013', 0,
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
  execute 'reset role';
  select profile.student_id into strict v_student
  from public.student_profile_versions profile
  where profile.profile_version_id = v_profile;

  insert into private.phase029_upgrade_capture (
    student_id, auth_user_id, profile_version_id, intent_set_id,
    intent_declaration_id, graph_fingerprint,
    taxonomy_count, program_count, source_count
  ) values (
    v_student, v_auth, v_profile, v_intent, v_declaration,
    md5(jsonb_build_object(
      'intent', (select to_jsonb(intent) from public.fit_intent_sets intent
        where intent.intent_set_id = v_intent),
      'product', (select to_jsonb(state)
        from private.fit_intent_product_states_v027 state
        where state.intent_set_id = v_intent),
      'dimensions', (select jsonb_agg(to_jsonb(state) order by state.dimension)
        from private.fit_intent_dimension_states_v027 state
        where state.intent_set_id = v_intent),
      'declarations', (select jsonb_agg(to_jsonb(declaration)
        order by declaration.intent_declaration_id)
        from public.fit_intent_declarations declaration
        where declaration.intent_set_id = v_intent),
      'operations', (select jsonb_agg(to_jsonb(operation)
        order by operation.operation_id)
        from private.fit_intent_operations_v027 operation
        where operation.student_id = v_student)
    )::text),
    (select count(*) from public.taxonomy_concepts),
    (select count(*) from public.program_versions),
    (select count(*) from public.sources)
  );
end;
$fixture$;
