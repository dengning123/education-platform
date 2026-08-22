\if :{?blocked}
\else
  \set blocked false
\endif

begin;

create table public.phase014_compat_probe (
  case_code text primary key,
  evaluation_id uuid not null,
  expected_candidate_input_fingerprint text,
  expected_decision_input_fingerprint text,
  expected_result_fingerprint text
);

insert into public.students (student_id)
values ('61500000-0000-0000-0000-000000000001');
insert into public.student_profile_versions (
  profile_version_id,student_id,version_number
) values (
  '61500000-0000-0000-0000-000000000002',
  '61500000-0000-0000-0000-000000000001',1
);
insert into public.student_evidence_items (
  student_evidence_id,profile_version_id,evidence_type,content_hash
) values (
  '61500000-0000-0000-0000-000000000003',
  '61500000-0000-0000-0000-000000000002','SELF_REPORT',repeat('7',64)
);
insert into public.student_preferences (
  student_preference_id,profile_version_id,preference_type,value,priority
) values (
  '61500000-0000-0000-0000-000000000004',
  '61500000-0000-0000-0000-000000000002','BUDGET',
  '{"amount":90000,"currency":"USD","period":"PROGRAM_DURATION"}',5
);
insert into public.student_data_completeness (
  profile_version_id,domain,completeness
) select '61500000-0000-0000-0000-000000000002',domain,'COMPLETE'
  from unnest(enum_range(null::public.student_data_domain)) domain;
select public.freeze_student_profile_version(
  '61500000-0000-0000-0000-000000000002'
);

insert into public.fit_intent_sets (
  intent_set_id,profile_version_id,version_number
) values (
  '61500000-0000-0000-0000-000000000010',
  '61500000-0000-0000-0000-000000000002',1
);
insert into public.fit_intent_declarations (
  intent_declaration_id,intent_set_id,profile_version_id,origin,dimension,
  semantic_type,importance,importance_basis,importance_evidence_id,
  interpretation_method,interpretation_method_version,
  interpretation_provenance,student_evidence_id
) values (
  '61500000-0000-0000-0000-000000000011',
  '61500000-0000-0000-0000-000000000010',
  '61500000-0000-0000-0000-000000000002','PHASE3_DECLARATION','FINANCIAL',
  'FINANCIAL_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION',
  '61500000-0000-0000-0000-000000000003','HUMAN','1',
  'Migration 014 legacy compatibility fixture.',
  '61500000-0000-0000-0000-000000000003'
);
insert into public.fit_intent_financial_constraints values (
  '61500000-0000-0000-0000-000000000011',
  '61500000-0000-0000-0000-000000000010',
  '61500000-0000-0000-0000-000000000002',90000,'PREFERRED_TUITION',
  'USD','COMPONENT','PROGRAM_DURATION','GROSS',array['TUITION']
);
do $freeze_intent$
begin
  if public.freeze_fit_intent_set(
      '61500000-0000-0000-0000-000000000010')='VALIDATION_FAILED' then
    raise exception 'phase014 legacy fixture intent did not freeze';
  end if;
end
$freeze_intent$;

insert into public.fit_evaluator_builds (
  evaluator_build_id,contract_release_id,evaluator_name,
  evaluator_version,build_hash
) values (
  '61500000-0000-0000-0000-000000000020',
  '30000000-0000-0000-0000-000000000001',
  'phase014-legacy-compat','0.13.0',repeat('e',64)
);
select public.verify_fit_definition(
  'EVALUATOR_BUILD','61500000-0000-0000-0000-000000000020',
  'phase014-compat-reviewer','00000000-0000-0000-0000-000000000705'
);
do $verify_methods$
declare v_method record;
begin
  for v_method in
    select method_id from public.fit_dimension_methods
    where contract_release_id='30000000-0000-0000-0000-000000000001'
      and status='DRAFT'
  loop
    perform public.verify_fit_definition(
      'METHOD',v_method.method_id,'phase014-compat-reviewer',
      '00000000-0000-0000-0000-000000000705'
    );
  end loop;
end
$verify_methods$;

\if :blocked
do $blocked_cases$
declare
  v_child uuid;
  v_candidate uuid;
  v_item uuid;
begin
  v_child:=public.start_fit_evaluation(
    '61500000-0000-0000-0000-000000000002',
    '61500000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000401','v0.1',
    '30000000-0000-0000-0000-000000000001',
    '61500000-0000-0000-0000-000000000020'
  );
  perform public.authorize_fit_evaluation_assembly(v_child,repeat('e',64));
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    v_child,'61500000-0000-0000-0000-000000000002',
    '30000000-0000-0000-0000-000000000103',
    '94646dff-73a0-0db4-be99-363a5f0b1a28',
    'PHASE2_STUDENT_PREFERENCE','LIMITING_CONTEXT'
  ) returning manifest_item_id into v_item;
  insert into public.fit_manifest_phase2_preferences (
    manifest_item_id,evaluation_id,profile_version_id,student_preference_id
  ) values (
    v_item,v_child,'61500000-0000-0000-0000-000000000002',
    '61500000-0000-0000-0000-000000000004'
  );
  insert into public.fit_manifest_student_field_uses values
    (v_item,v_child,'PREFERENCE_TYPE'),
    (v_item,v_child,'VALUE');
  insert into public.phase014_compat_probe(case_code,evaluation_id)
  values ('BLOCK_FINANCIAL_PREFERENCE_MANIFEST',v_child);

  v_candidate:=public.start_fit_evaluation(
    '61500000-0000-0000-0000-000000000002',
    '61500000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000401','v0.1',
    '30000000-0000-0000-0000-000000000001',
    '61500000-0000-0000-0000-000000000020'
  );
  perform public.authorize_fit_evaluation_assembly(v_candidate,repeat('e',64));
  perform public.seal_fit_evaluation_inputs(v_candidate);
  insert into public.phase014_compat_probe(
    case_code,evaluation_id,expected_candidate_input_fingerprint
  ) select 'BLOCK_CANDIDATE_FINGERPRINT',evaluation_id,
      candidate_input_fingerprint
    from public.fit_evaluations where evaluation_id=v_candidate;
end
$blocked_cases$;
\else
do $compatible_cases$
declare
  v_empty uuid;
  v_completed uuid;
  v_candidate text;
begin
  v_empty:=public.start_fit_evaluation(
    '61500000-0000-0000-0000-000000000002',
    '61500000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000401','v0.1',
    '30000000-0000-0000-0000-000000000001',
    '61500000-0000-0000-0000-000000000020'
  );
  perform public.authorize_fit_evaluation_assembly(v_empty,repeat('e',64));
  insert into public.phase014_compat_probe(case_code,evaluation_id)
  values ('EMPTY_BUILDING',v_empty);

  v_completed:=public.start_fit_evaluation(
    '61500000-0000-0000-0000-000000000002',
    '61500000-0000-0000-0000-000000000010',
    '00000000-0000-0000-0000-000000000401','v0.1',
    '30000000-0000-0000-0000-000000000001',
    '61500000-0000-0000-0000-000000000020'
  );
  v_candidate:=public.seal_fit_evaluation_inputs(v_completed);
  execute 'alter table public.fit_evaluations disable trigger fit_evaluations_guard';
  update public.fit_evaluations
  set evaluation_state='COMPLETED',
      decision_input_fingerprint=v_candidate,
      result_fingerprint=repeat('c',64),
      evaluated_at='2026-08-20 00:00:00+00',
      finalized_by='phase014-legacy-fixture'
  where evaluation_id=v_completed;
  execute 'alter table public.fit_evaluations enable trigger fit_evaluations_guard';
  insert into public.phase014_compat_probe(
    case_code,evaluation_id,expected_candidate_input_fingerprint,
    expected_decision_input_fingerprint,expected_result_fingerprint
  ) select 'COMPLETED',evaluation_id,candidate_input_fingerprint,
      decision_input_fingerprint,result_fingerprint
    from public.fit_evaluations where evaluation_id=v_completed;
end
$compatible_cases$;
\endif

commit;
