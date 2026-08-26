-- Run after Migration 026 and before Migration 027.
do $fixture$
declare
  v_student constant uuid := 'a2720000-0000-4000-8000-000000000001';
  v_profile constant uuid := 'a2720000-0000-4000-8000-000000000002';
  v_intent constant uuid := 'a2720000-0000-4000-8000-000000000003';
  v_evidence constant uuid := 'a2720000-0000-4000-8000-000000000004';
  v_declaration constant uuid := 'a2720000-0000-4000-8000-000000000005';
  v_domain public.student_data_domain;
begin
  perform public.create_student(v_student);
  insert into public.student_profile_versions (
    profile_version_id, student_id, version_number
  ) values (v_profile, v_student, 1);
  insert into public.student_evidence_items (
    student_evidence_id, profile_version_id, evidence_type,
    locator, content_hash
  ) values (
    v_evidence, v_profile, 'SELF_REPORT', 'phase027-upgrade', repeat('b',64)
  );
  foreach v_domain in array enum_range(null::public.student_data_domain)
  loop
    insert into public.student_data_completeness (
      profile_version_id, domain, completeness
    ) values (v_profile, v_domain, 'COMPLETE');
  end loop;
  perform public.freeze_student_profile_version(v_profile);
  insert into public.fit_intent_sets (
    intent_set_id, profile_version_id, version_number
  ) values (v_intent, v_profile, 1);
  insert into public.fit_intent_declarations (
    intent_declaration_id, intent_set_id, profile_version_id,
    origin, dimension, semantic_type, importance, importance_basis,
    importance_confirmed_by_student, interpretation_method,
    interpretation_method_version, interpretation_provenance,
    student_evidence_id
  ) values (
    v_declaration, v_intent, v_profile, 'PHASE3_DECLARATION',
    'GEOGRAPHIC_DELIVERY', 'DELIVERY_CONSTRAINT', 'PREFERRED',
    'STRUCTURED_STUDENT_DECLARATION', false, 'HUMAN',
    'LEGACY_PHASE3_FIXTURE', 'SELF_REPORTED', v_evidence
  );
  insert into public.fit_intent_delivery_constraints (
    intent_declaration_id, intent_set_id, profile_version_id,
    delivery_mode, relation
  ) values (v_declaration, v_intent, v_profile, 'ONLINE', 'DESIRED');
  insert into private.fit_student_access_contexts (
    intent_set_id, profile_version_id, governing_jurisdiction_code,
    target_path_code, student_evidence_id, provenance
  ) values (
    v_intent, v_profile, 'US', 'F1', v_evidence, 'SELF_REPORTED'
  );
end;
$fixture$;
