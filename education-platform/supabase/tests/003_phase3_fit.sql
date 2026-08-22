begin;

create or replace function pg_temp.review_unspecified_applicability(p_observation_id uuid)
returns void
language plpgsql
as $$
declare
  o public.field_observations%rowtype;
  v_scope uuid;
  v_assertion uuid;
begin
  select * into o from public.field_observations where observation_id = p_observation_id;
  v_scope := public.create_evidence_scope(
    o.evidence_id, o.record_type, o.record_id, o.field_name,
    'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
  );
  v_assertion := public.review_evidence_applicability(
    v_scope, 'REVIEWED_APPLICABLE', 'phase3-test-reviewer', 'test applicability'
  );
  insert into public.field_observation_applicability (observation_id, assertion_id)
  values (p_observation_id, v_assertion)
  on conflict (observation_id) do update
    set assertion_id = excluded.assertion_id;
end;
$$;

-- Phase 3 contract, catalog shape, and prohibited vocabulary.
do $test$
declare
  v_actual integer;
  v_blocked boolean;
  v_definition text;
begin
  if to_regclass('public.fit_evaluations') is null
     or to_regclass('public.fit_intent_sets') is null
     or to_regclass('public.fit_context_claims') is null then
    raise exception 'Phase 3 tables are missing';
  end if;

  select count(*) into v_actual
  from public.fit_dimension_methods
  where contract_release_id = '30000000-0000-0000-0000-000000000001'
    and status = 'DRAFT';
  if v_actual <> 6 then
    raise exception 'Expected six initially DRAFT Fit methods, found %', v_actual;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema in ('public', 'private')
      and table_name like 'fit_%'
      and column_name ~ '(^|_)(score|weight|rank|probability)($|_)'
  ) then
    raise exception 'Fit schema exposes a prohibited score/weight/rank/probability output';
  end if;

  if exists (
    select 1 from public.fit_method_input_policies
    where disposition = 'ALLOWED'
      and input_domain in (
        'EXTERNAL_METRICS', 'STUDENT_DERIVED_FEATURE_VALUES',
        'PROGRAM_DERIVED_FEATURES'
      )
  ) then
    raise exception 'A generic derived-feature or external-metric domain is ALLOWED';
  end if;

  if exists (
    select 1
    from unnest(enum_range(null::public.fit_manifest_item_type)) value
    where value::text ~ '(DERIVED|EXTERNAL|DEGREE|TEST|EXPERIENCE|SKILL|ELIGIBILITY)'
  ) then
    raise exception 'Fit manifest enum contains a prohibited generic or Phase 2 decision item';
  end if;

  if exists (
    select 1
    from unnest(enum_range(null::public.fit_student_field_name)) value
    where value::text ~ '(PRIORITY|GPA|GRADE|TEST|EXPERIENCE|SKILL)'
  ) then
    raise exception 'Fit student field allowlist exposes prohibited fields';
  end if;

  if exists (
    select 1
    from unnest(enum_range(null::public.fit_context_claim_code)) value
    where value::text in ('STEM', 'CIP', 'COST', 'LOCATION', 'DELIVERY')
  ) then
    raise exception 'Phase 1 fact code leaked into Phase 3 context claims';
  end if;

  if exists (
    select 1 from unnest(enum_range(null::public.fit_manifest_item_type)) value
    where value::text like '%ELIGIBILITY%'
  ) then
    raise exception 'Eligibility became a Fit decision-manifest item';
  end if;

  if (select count(*) from public.fit_semantic_source_classes
      where not fit_permitted) < 6
     or exists (
       select 1 from pg_type
       where typtype = 'e'
         and typname like '%semantic%source%class%'
     ) then
    raise exception 'Semantic source classes do not have one authoritative registry';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'fit_dimension_results'
      and column_name = 'unknown_reason_family'
  ) then
    raise exception 'UNKNOWN reason family was denormalized onto dimension results';
  end if;
  if (select count(*) from public.fit_signal_types) <> 31 then
    raise exception 'Expected conservative signal types plus one explicit Academic strong contract';
  end if;

  if col_description(
       'public.fit_evaluations'::regclass,
       (select attnum from pg_attribute
        where attrelid = 'public.fit_evaluations'::regclass
          and attname = 'eligibility_context_evaluation_id')
     ) not like '%Excluded from Fit manifests%fingerprints%' then
    raise exception 'Eligibility display-only exclusion comment is missing';
  end if;

  select pg_get_functiondef(
    'public.finalize_fit_evaluation(uuid)'::regprocedure
  ) into v_definition;
  if v_definition like '%eligibility_context_evaluation_id%' then
    raise exception 'Fit fingerprint construction reads eligibility context';
  end if;
  if v_definition not like '%MIXED requires material supporting and contradicting%'
     or v_definition not like '%MISALIGNMENT requires a method-valid material contradiction%'
     or v_definition not like '%Required contradictions must be deterministic%'
     or v_definition not like '%STRONG_ALIGNMENT requires method permission%'
     or v_definition not like '%UNKNOWN requires at least one normalized limiting reason family%'
     or v_definition not like '%High-impact international direction requires%'
     or v_definition not like '%Directional deterministic Financial Fit requires%' then
    raise exception 'One or more approved categorical finalization guards are missing';
  end if;
  v_blocked := false;
  begin
    update public.fit_dimension_methods
    set status = 'VERIFIED',
        reviewed_by = 'bypass',
        reviewed_at = now(),
        verification_evidence_id = '00000000-0000-0000-0000-000000000701'
    where method_id = '30000000-0000-0000-0000-000000000101';
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm = 'Use controlled Fit registry verification or retirement' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Direct Fit method status bypass was accepted';
  end if;
end;
$test$;

do $test$
declare
  v_blocked boolean;
begin
  if exists (
    select 1 from public.fit_semantic_source_classes
    where (owner_layer = 'PROHIBITED') is distinct from
      (not fit_permitted)
  ) then
    raise exception 'Semantic source-class prohibited ownership is not iff';
  end if;
  v_blocked := false;
  begin
    update public.fit_semantic_source_classes
    set fit_permitted = not fit_permitted
    where source_class_code = 'PRESTIGE_RANKING';
  exception when object_not_in_prerequisite_state then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Semantic source-class meaning remained mutable';
  end if;
  v_blocked := false;
  begin
    update public.fit_mapping_relation_definitions
    set relation_domain = 'STUDENT'
    where relation_code = 'FIELD_CLASSIFICATION';
  exception when object_not_in_prerequisite_state then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Mapping relation meaning remained mutable';
  end if;
  if exists (
    select 1
    from public.fit_method_mapping_relation_policies
    where permits_strong_alignment
      and not 'STRONG_ALIGNMENT' = any(allowed_assessments)
  ) then
    raise exception 'Relation policy permits STRONG without assessment authority';
  end if;
  if exists (
    select 1
    from public.fit_signal_types signal
    join public.fit_dimension_methods method using(method_id)
    where method.inference_category <> 'HYBRID'
      and exists (
        select 1
        from unnest(signal.allowed_inference_categories) category
        where category <> method.inference_category
      )
  ) then
    raise exception 'Signal inference categories exceed their method category';
  end if;
  if exists (
    select 1
    from public.fit_method_input_policies policy
    where policy.disposition = 'ALLOWED'
      and policy.input_domain in (
        'PROGRAM_COURSES','PROGRAM_COSTS','PROGRAM_VERSIONS'
      )
      and not exists (
        select 1
        from public.fit_method_program_field_policies field_policy
        where field_policy.method_id = policy.method_id
          and field_policy.input_policy_id = policy.input_policy_id
      )
  ) then
    raise exception 'Program input policy lacks exact record/field allowlist';
  end if;
  if (
    select count(*) from public.fit_dimension_methods
    where permits_strong_alignment
  ) <> 1 or not exists (
    select 1
    from public.fit_dimension_methods
    where method_id = '30000000-0000-0000-0000-000000000101'
      and materiality_contract ? 'strongAlignmentContract'
  ) then
    raise exception 'STRONG authority is not conservative and machine-contracted';
  end if;
end;
$test$;

-- Official review evidence used to approve all six seeded methods.
insert into public.sources (
  source_id, publisher, title, url, reliability_tier, source_type
) values (
  '40000000-0000-0000-0000-000000000001',
  'Phase 3 Review Board',
  'Fit v0.1 method review record',
  'https://example.invalid/phase3-fit-review',
  'TIER_A_OFFICIAL',
  'INTERNAL_OFFICIAL_REVIEW'
);
insert into public.evidence_items (
  evidence_id, source_id, excerpt, locator, cycle_context,
  retrieved_at, verified_at, content_hash
) values (
  '40000000-0000-0000-0000-000000000002',
  '40000000-0000-0000-0000-000000000001',
  'All six Fit v0.1 methods were reviewed against the approved semantic contract.',
  'review-minute-1',
  'fit-v0.1',
  now(), now(), md5('phase3 method review')
);

insert into public.catalog_concept_mappings (
  mapping_id, record_type, record_id, concept_id, relation,
  mapping_status, method, confidence
) values (
  '40000000-0000-0000-0000-00000000007d',
  'PROGRAM_VERSION', '00000000-0000-0000-0000-000000000401',
  '10000000-0000-0000-0000-000000000052',
  'CAREER_ASSOCIATION', 'PROPOSED', 'HUMAN', 1
);
select public.review_catalog_concept_mapping(
  '40000000-0000-0000-0000-00000000007d',
  'VERIFIED',
  'phase3-test-reviewer',
  '40000000-0000-0000-0000-000000000002'
);

insert into public.fit_evaluator_builds (
  evaluator_build_id, contract_release_id, evaluator_name,
  evaluator_version, build_hash
) values (
  '40000000-0000-0000-0000-000000000003',
  '30000000-0000-0000-0000-000000000001',
  'phase3-fit-test', '0.1.0', repeat('b', 64)
);
select public.verify_fit_definition(
  'EVALUATOR_BUILD',
  '40000000-0000-0000-0000-000000000003',
  'phase3-test-reviewer',
  '40000000-0000-0000-0000-000000000002'
);

do $test$
declare
  v_method record;
  v_blocked boolean;
begin
  for v_method in
    select method_id from public.fit_dimension_methods
    where contract_release_id = '30000000-0000-0000-0000-000000000001'
    order by dimension
  loop
    perform public.verify_fit_definition(
      'METHOD', v_method.method_id, 'phase3-test-reviewer',
      '40000000-0000-0000-0000-000000000002'
    );
  end loop;

  if (select count(*) from public.fit_dimension_methods
      where contract_release_id = '30000000-0000-0000-0000-000000000001'
        and status = 'VERIFIED') <> 6 then
    raise exception 'Six Fit methods were not verified through the lifecycle API';
  end if;

  v_blocked := false;
  begin
    insert into public.fit_method_input_policies (
      method_id, input_domain, field_name, disposition, requirement,
      permits_deterministic_use, permits_model_use
    ) values (
      '30000000-0000-0000-0000-000000000101',
      'EXTERNAL_METRICS', 'GENERIC_METRIC', 'ALLOWED', 'OPTIONAL', true, true
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm = 'Input policies for verified Fit methods are append-only' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'A verified method accepted a new generic metric policy';
  end if;
end;
$test$;

-- Isolated student/profile fixture. IDs are fixed so equivalent evaluations
-- can prove insertion-order-independent fingerprints.
insert into public.students (student_id)
values
  ('40000000-0000-0000-0000-000000000010'),
  ('40000000-0000-0000-0000-000000000011');
insert into auth.users (id) values
  ('40000000-0000-0000-0000-000000000090'),
  ('40000000-0000-0000-0000-000000000091');
insert into private.student_identities (auth_user_id,student_id) values (
  '40000000-0000-0000-0000-000000000090',
  '40000000-0000-0000-0000-000000000010'
);
insert into public.student_profile_versions (
  profile_version_id, student_id, version_number
) values
  ('40000000-0000-0000-0000-000000000020',
   '40000000-0000-0000-0000-000000000010', 1),
  ('40000000-0000-0000-0000-000000000021',
   '40000000-0000-0000-0000-000000000011', 1);
insert into public.student_evidence_items (
  student_evidence_id, profile_version_id, evidence_type, content_hash
) values
  ('40000000-0000-0000-0000-000000000030',
   '40000000-0000-0000-0000-000000000020', 'SELF_REPORT', repeat('1',64)),
  ('40000000-0000-0000-0000-000000000031',
   '40000000-0000-0000-0000-000000000021', 'SELF_REPORT', repeat('2',64));
insert into public.student_goals (
  student_goal_id, profile_version_id, goal_type, concept_id, priority
) values (
  '40000000-0000-0000-0000-000000000040',
  '40000000-0000-0000-0000-000000000020',
  'CAREER', '10000000-0000-0000-0000-000000000052', 5
);
insert into public.student_preferences (
  student_preference_id, profile_version_id, preference_type, value, priority
) values (
  '40000000-0000-0000-0000-000000000041',
  '40000000-0000-0000-0000-000000000020',
  'DELIVERY_MODE', '{"deliveryMode":"ONLINE"}', 4
);
insert into public.student_courses (
  student_course_id, profile_version_id, course_code, course_title,
  course_status, student_evidence_id
) values (
  '40000000-0000-0000-0000-000000000042',
  '40000000-0000-0000-0000-000000000020',
  'FIT-101', 'Fit Fixture Course', 'COMPLETED',
  '40000000-0000-0000-0000-000000000030'
);
insert into public.student_data_completeness (
  profile_version_id, domain, completeness
)
select '40000000-0000-0000-0000-000000000020', domain, 'COMPLETE'
from unnest(enum_range(null::public.student_data_domain)) value(domain);
insert into public.student_data_completeness (
  profile_version_id, domain, completeness
)
select '40000000-0000-0000-0000-000000000021', domain, 'COMPLETE'
from unnest(enum_range(null::public.student_data_domain)) value(domain);
select public.freeze_student_profile_version('40000000-0000-0000-0000-000000000020');
select public.freeze_student_profile_version('40000000-0000-0000-0000-000000000021');

insert into public.fit_intent_sets (
  intent_set_id, profile_version_id, version_number
) values (
  '40000000-0000-0000-0000-000000000050',
  '40000000-0000-0000-0000-000000000020', 1
);

-- One declaration for each dimension. Two preserve exactly one Phase 2 origin;
-- the other four are evidence-backed native Phase 3 declarations.
insert into public.fit_intent_declarations (
  intent_declaration_id, intent_set_id, profile_version_id, origin,
  dimension, semantic_type, importance, importance_basis,
  importance_evidence_id, source_student_goal_id,
  source_student_preference_id, interpretation_method,
  interpretation_method_version, interpretation_provenance,
  student_evidence_id
) values
  ('40000000-0000-0000-0000-000000000061','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020','PHASE2_INTERPRETATION','ACADEMIC','TAXONOMY_TARGET','STRONGLY_PREFERRED','REVIEWED_INTERPRETATION',null,'40000000-0000-0000-0000-000000000040',null,'HUMAN','1','Goal interpreted without copying priority.',null),
  ('40000000-0000-0000-0000-000000000062','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020','PHASE2_INTERPRETATION','GEOGRAPHIC_DELIVERY','DELIVERY_CONSTRAINT','REQUIRED','STRUCTURED_STUDENT_DECLARATION','40000000-0000-0000-0000-000000000030',null,'40000000-0000-0000-0000-000000000041','HUMAN','1','Delivery preference interpreted without copying priority.',null),
  ('40000000-0000-0000-0000-000000000063','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020','PHASE3_DECLARATION','CAREER','TAXONOMY_TARGET','PREFERRED','STRUCTURED_STUDENT_DECLARATION','40000000-0000-0000-0000-000000000030',null,null,'HUMAN','1','Direct evidence-backed declaration.','40000000-0000-0000-0000-000000000030'),
  ('40000000-0000-0000-0000-000000000064','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020','PHASE3_DECLARATION','FINANCIAL','FINANCIAL_CONSTRAINT','REQUIRED','STRUCTURED_STUDENT_DECLARATION','40000000-0000-0000-0000-000000000030',null,null,'HUMAN','1','Direct evidence-backed declaration.','40000000-0000-0000-0000-000000000030'),
  ('40000000-0000-0000-0000-000000000065','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020','PHASE3_DECLARATION','PERSONAL_PREFERENCE','DURATION_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION','40000000-0000-0000-0000-000000000030',null,null,'HUMAN','1','Direct evidence-backed declaration.','40000000-0000-0000-0000-000000000030'),
  ('40000000-0000-0000-0000-000000000066','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020','PHASE3_DECLARATION','INTERNATIONAL_ACCESSIBILITY','PROGRAM_FEATURE_CONSTRAINT','UNSPECIFIED','STRUCTURED_STUDENT_DECLARATION','40000000-0000-0000-0000-000000000030',null,null,'HUMAN','1','Direct evidence-backed declaration.','40000000-0000-0000-0000-000000000030');
insert into public.fit_intent_taxonomy_targets values
  ('40000000-0000-0000-0000-000000000061','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020','10000000-0000-0000-0000-000000000021','DESIRED'),
  ('40000000-0000-0000-0000-000000000063','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020','10000000-0000-0000-0000-000000000052','DESIRED');
insert into public.fit_intent_delivery_constraints values
  ('40000000-0000-0000-0000-000000000062','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020','ONLINE','DESIRED');
insert into public.fit_intent_financial_constraints values
  ('40000000-0000-0000-0000-000000000064','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020',90000,'HARD_TOTAL_COST_CEILING','USD','TOTAL_COST','PROGRAM_DURATION','GROSS',array['TUITION','FEES']);
insert into public.fit_intent_duration_constraints values
  ('40000000-0000-0000-0000-000000000065','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020',6,18);
insert into public.fit_intent_program_feature_constraints values
  ('40000000-0000-0000-0000-000000000066','40000000-0000-0000-0000-000000000050','40000000-0000-0000-0000-000000000020','INTERNATIONAL_PATH_SUPPORT',true);

do $test$
declare
  v_blocked boolean;
  v_hash text;
  v_before integer;
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='fit_intent_declarations'
      and column_name in ('priority','raw_value','value')
  ) then
    raise exception 'Fit intent declaration copied Phase 2 priority/raw value';
  end if;
  if exists (
    select 1 from public.fit_intent_declarations
    where origin='PHASE2_INTERPRETATION'
      and ((source_student_goal_id is not null)::int
         +(source_student_preference_id is not null)::int) <> 1
  ) then
    raise exception 'Phase 2 intent origin does not preserve exactly one source';
  end if;

  v_blocked := false;
  begin
    insert into public.fit_intent_declarations (
      intent_set_id, profile_version_id, origin, dimension, semantic_type,
      importance, importance_basis, interpretation_method,
      interpretation_method_version,
      interpretation_provenance
    ) values (
      '40000000-0000-0000-0000-000000000050',
      '40000000-0000-0000-0000-000000000020',
      'PHASE3_DECLARATION','CAREER','TAXONOMY_TARGET','PREFERRED',
      'REVIEWED_INTERPRETATION','HUMAN','1','Missing evidence attack'
    );
  exception when check_violation then v_blocked := true;
  end;
  if not v_blocked then raise exception 'Phase 3 declaration did not require evidence'; end if;

  -- Cross-profile ownership is tested directly with a valid UUID target.
  v_blocked := false;
  begin
    insert into public.fit_intent_declarations (
      intent_declaration_id,intent_set_id,profile_version_id,origin,dimension,
      semantic_type,importance,importance_basis,importance_evidence_id,
      student_evidence_id,interpretation_method,
      interpretation_method_version,interpretation_provenance
    ) values (
      '40000000-0000-0000-0000-000000000069',
      '40000000-0000-0000-0000-000000000050',
      '40000000-0000-0000-0000-000000000020','PHASE3_DECLARATION','CAREER',
      'TAXONOMY_TARGET','PREFERRED','STRUCTURED_STUDENT_DECLARATION',
      '40000000-0000-0000-0000-000000000031',
      '40000000-0000-0000-0000-000000000031','HUMAN','1','cross profile'
    );
  exception when foreign_key_violation then v_blocked := true;
  end;
  if not v_blocked then raise exception 'Cross-profile intent evidence injection succeeded'; end if;

  v_blocked := false;
  begin
    insert into public.fit_intent_delivery_constraints values (
      '40000000-0000-0000-0000-000000000062',
      '40000000-0000-0000-0000-000000000050',
      '40000000-0000-0000-0000-000000000020','ONLINE','DESIRED'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm = 'A Fit intent declaration may have at most one typed child' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then raise exception 'Typed intent child exclusivity was bypassed'; end if;

  select count(*) into v_before from public.student_data_completeness
  where profile_version_id='40000000-0000-0000-0000-000000000020';
  v_hash := public.freeze_fit_intent_set('40000000-0000-0000-0000-000000000050');
  if v_hash !~ '^[a-f0-9]{64}$' then raise exception 'Intent snapshot hash is invalid'; end if;
  if (select count(*) from public.student_data_completeness
      where profile_version_id='40000000-0000-0000-0000-000000000020') <> v_before then
    raise exception 'Fit intent freeze changed Phase 2 completeness';
  end if;
  v_blocked := false;
  begin
    update public.fit_intent_declarations set importance='NEUTRAL'
    where intent_declaration_id='40000000-0000-0000-0000-000000000061';
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm = 'Frozen Fit intent content is immutable' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then raise exception 'Frozen intent content remained mutable'; end if;
end;
$test$;

-- REQUIRED importance needs student authority, and mutually exclusive hard
-- constraints must stay DRAFT with explicit validation issues.
insert into public.fit_intent_sets (
  intent_set_id, profile_version_id, version_number
) values (
  '40000000-0000-0000-0000-000000000051',
  '40000000-0000-0000-0000-000000000020', 2
);
insert into public.fit_intent_declarations (
  intent_declaration_id, intent_set_id, profile_version_id, origin,
  dimension, semantic_type, importance, importance_basis,
  importance_evidence_id, interpretation_method,
  interpretation_method_version, interpretation_provenance,
  student_evidence_id
) values
  (
    '40000000-0000-0000-0000-000000000067',
    '40000000-0000-0000-0000-000000000051',
    '40000000-0000-0000-0000-000000000020',
    'PHASE3_DECLARATION', 'GEOGRAPHIC_DELIVERY',
    'LOCATION_CONSTRAINT', 'REQUIRED',
    'STRUCTURED_STUDENT_DECLARATION',
    '40000000-0000-0000-0000-000000000030',
    'HUMAN', '1', 'Explicit New York requirement.',
    '40000000-0000-0000-0000-000000000030'
  ),
  (
    '40000000-0000-0000-0000-000000000068',
    '40000000-0000-0000-0000-000000000051',
    '40000000-0000-0000-0000-000000000020',
    'PHASE3_DECLARATION', 'GEOGRAPHIC_DELIVERY',
    'LOCATION_CONSTRAINT', 'REQUIRED',
    'STRUCTURED_STUDENT_DECLARATION',
    '40000000-0000-0000-0000-000000000030',
    'HUMAN', '1', 'Explicit Boston requirement.',
    '40000000-0000-0000-0000-000000000030'
  );
insert into public.fit_intent_location_constraints values
  (
    '40000000-0000-0000-0000-000000000067',
    '40000000-0000-0000-0000-000000000051',
    '40000000-0000-0000-0000-000000000020',
    'REQUIRED', 'US', null, 'New York'
  ),
  (
    '40000000-0000-0000-0000-000000000068',
    '40000000-0000-0000-0000-000000000051',
    '40000000-0000-0000-0000-000000000020',
    'REQUIRED', 'US', null, 'Boston'
  );
do $test$
declare
  v_result text;
  v_blocked boolean := false;
begin
  v_result := public.freeze_fit_intent_set(
    '40000000-0000-0000-0000-000000000051'
  );
  if v_result <> 'VALIDATION_FAILED'
     or (select status from public.fit_intent_sets
         where intent_set_id =
           '40000000-0000-0000-0000-000000000051') <> 'DRAFT'
     or not exists (
       select 1 from public.fit_intent_validation_issues
       where intent_set_id =
         '40000000-0000-0000-0000-000000000051'
         and issue_code = 'INTENT_CONFLICT'
     ) then
    raise exception 'Contradictory REQUIRED intent did not remain explicit and unfrozen';
  end if;

  begin
    insert into public.fit_intent_declarations (
      intent_set_id, profile_version_id, origin, dimension,
      semantic_type, importance, importance_basis,
      importance_evidence_id, interpretation_method,
      interpretation_method_version, interpretation_provenance,
      student_evidence_id
    ) values (
      '40000000-0000-0000-0000-000000000051',
      '40000000-0000-0000-0000-000000000020',
      'PHASE3_DECLARATION', 'FINANCIAL', 'FINANCIAL_CONSTRAINT',
      'REQUIRED', 'REVIEWED_INTERPRETATION',
      '40000000-0000-0000-0000-000000000030',
      'HUMAN', '1', 'Reviewer escalation attack.',
      '40000000-0000-0000-0000-000000000030'
    );
  exception when check_violation then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Reviewer-only interpretation escalated importance to REQUIRED';
  end if;
end;
$test$;

insert into public.fit_intent_sets (
  intent_set_id, profile_version_id, version_number
) values (
  '40000000-0000-0000-0000-000000000052',
  '40000000-0000-0000-0000-000000000020', 3
);
do $test$
declare
  v_blocked boolean;
  v_result text;
begin
  v_blocked := false;
  begin
    insert into public.fit_intent_declarations (
      intent_set_id, profile_version_id, origin, dimension,
      semantic_type, importance, importance_basis,
      interpretation_method, interpretation_method_version,
      interpretation_provenance, student_evidence_id
    ) values (
      '40000000-0000-0000-0000-000000000052',
      '40000000-0000-0000-0000-000000000020',
      'PHASE3_DECLARATION', 'ACADEMIC',
      'FINANCIAL_CONSTRAINT', 'PREFERRED',
      'STRUCTURED_STUDENT_DECLARATION',
      'HUMAN', '1', 'Dimension ownership attack.',
      '40000000-0000-0000-0000-000000000030'
    );
  exception when check_violation then v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Intent semantic type crossed its owning dimension';
  end if;

  insert into public.fit_intent_declarations (
    intent_declaration_id, intent_set_id, profile_version_id,
    origin, dimension, semantic_type, importance, importance_basis,
    importance_evidence_id, interpretation_method,
    interpretation_method_version, interpretation_provenance,
    student_evidence_id
  ) values (
    '40000000-0000-0000-0000-00000000006a',
    '40000000-0000-0000-0000-000000000052',
    '40000000-0000-0000-0000-000000000020',
    'PHASE3_DECLARATION', 'PERSONAL_PREFERENCE',
    'DURATION_CONSTRAINT', 'REQUIRED',
    'NORMALIZED_STUDENT_LANGUAGE',
    '40000000-0000-0000-0000-000000000030',
    'MODEL', 'model-v1', 'Unconfirmed model normalization.',
    '40000000-0000-0000-0000-000000000030'
  );
  insert into public.fit_intent_duration_constraints values (
    '40000000-0000-0000-0000-00000000006a',
    '40000000-0000-0000-0000-000000000052',
    '40000000-0000-0000-0000-000000000020', 6, 12
  );

  v_blocked := false;
  begin
    insert into public.fit_intent_declarations (
      intent_declaration_id, intent_set_id, profile_version_id,
      origin, dimension, semantic_type, importance, importance_basis,
      interpretation_method, interpretation_method_version,
      interpretation_provenance, student_evidence_id
    ) values (
      '40000000-0000-0000-0000-00000000006b',
      '40000000-0000-0000-0000-000000000052',
      '40000000-0000-0000-0000-000000000020',
      'PHASE3_DECLARATION', 'PERSONAL_PREFERENCE',
      'PROGRAM_FEATURE_CONSTRAINT', 'PREFERRED',
      'STRUCTURED_STUDENT_DECLARATION',
      'HUMAN', '1', 'Uncontrolled feature-key attack.',
      '40000000-0000-0000-0000-000000000030'
    );
    insert into public.fit_intent_program_feature_constraints
    values (
      '40000000-0000-0000-0000-00000000006b',
      '40000000-0000-0000-0000-000000000052',
      '40000000-0000-0000-0000-000000000020',
      'PRESTIGE', true
    );
  exception when invalid_text_representation then v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Uncontrolled or prohibited program feature key was accepted';
  end if;

  v_blocked := false;
  begin
    insert into public.fit_intent_declarations (
      intent_declaration_id, intent_set_id, profile_version_id,
      origin, dimension, semantic_type, importance, importance_basis,
      interpretation_method, interpretation_method_version,
      interpretation_provenance, student_evidence_id
    ) values (
      '40000000-0000-0000-0000-00000000006c',
      '40000000-0000-0000-0000-000000000052',
      '40000000-0000-0000-0000-000000000020',
      'PHASE3_DECLARATION', 'FINANCIAL',
      'FINANCIAL_CONSTRAINT', 'PREFERRED',
      'STRUCTURED_STUDENT_DECLARATION',
      'HUMAN', '1', 'Duplicate component attack.',
      '40000000-0000-0000-0000-000000000030'
    );
    insert into public.fit_intent_financial_constraints values (
      '40000000-0000-0000-0000-00000000006c',
      '40000000-0000-0000-0000-000000000052',
      '40000000-0000-0000-0000-000000000020',
      10000, 'PREFERRED_TOTAL_COST', 'USD', 'TOTAL_COST',
      'ACADEMIC_YEAR', 'GROSS', array['TUITION','TUITION']
    );
  exception when check_violation then v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Duplicate financial components were accepted';
  end if;

  v_result := public.freeze_fit_intent_set(
    '40000000-0000-0000-0000-000000000052'
  );
  if v_result <> 'VALIDATION_FAILED' or not exists (
    select 1 from public.fit_intent_validation_issues
    where intent_set_id =
      '40000000-0000-0000-0000-000000000052'
      and issue_code = 'REQUIRED_EVIDENCE_MISSING'
  ) then
    raise exception 'Unconfirmed model-normalized REQUIRED language froze';
  end if;
end;
$test$;

-- Context claim lifecycle, conflicts, selection control, and mapping authority.
do $test$
declare
  v_blocked boolean := false;
begin
  begin
    insert into public.fit_context_claim_definitions (
      claim_code, semantic_source_class_code, definition_version,
      description, value_contract
    ) values (
      'REVIEWED_CAREER_OUTCOME', 'FIT_CONTEXT_REGULATORY', 1,
      'Invalid source-class pairing probe.', '{"requiredKeys":["outcome"]}'
    );
  exception when check_violation then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Claim code accepted an incompatible permitted source class';
  end if;
end;
$test$;

insert into public.fit_context_claim_definitions (
  claim_definition_id, claim_code, semantic_source_class_code,
  definition_version, description, value_contract
) values (
  '40000000-0000-0000-0000-000000000070',
  'JURISDICTION_PATH_ACCESSIBILITY','FIT_CONTEXT_ACCESSIBILITY',1,
  'Whether a path is accessible in a jurisdiction.',
  '{"requiredKeys":["accessible"]}'
);
select public.verify_fit_context_definition(
  '40000000-0000-0000-0000-000000000070',
  'phase3-test-reviewer','40000000-0000-0000-0000-000000000002'
);

do $test$
declare
  v_blocked boolean := false;
begin
  begin
    insert into public.fit_context_claim_definitions (
      claim_definition_id, claim_code, semantic_source_class_code,
      definition_version, description, value_contract
    ) values (
      '40000000-0000-0000-0000-000000000074',
      'REGULATORY_WORK_AUTHORIZATION', 'PROGRAM_CANONICAL_FACT',
      1, 'Attempted Phase 1 fact wrapper.', '{"requiredKeys":["allowed"]}'
    );
  exception when others then
    if sqlstate = '23514'
       and sqlerrm =
         'new row for relation "fit_context_claim_definitions" violates check constraint "fit_context_definitions_source_class"' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Context definition wrapped an upstream Phase 1 fact class';
  end if;
end;
$test$;
insert into public.fit_context_claims (
  context_claim_id, claim_definition_id, definition_version,
  program_version_id, jurisdiction_code, path_code, valid_from, valid_to
) values (
  '40000000-0000-0000-0000-000000000071',
  '40000000-0000-0000-0000-000000000070',1,
  '00000000-0000-0000-0000-000000000401','US_NY','F1_OPT',
  date '2026-01-01',date '2027-12-31'
);
do $test$
declare
  v_blocked boolean;
begin
  v_blocked := false;
  begin
    insert into public.fit_context_claim_observations (
      context_claim_id, observed_value, authority, evidence_id,
      method, method_version
    ) values (
      '40000000-0000-0000-0000-000000000071',
      '{"accessible":true,"prestigeScore":99}',
      'OFFICIAL_REGULATORY',
      '40000000-0000-0000-0000-000000000002',
      'HUMAN', '1'
    );
  exception when others then
    if sqlstate='23514'
       and sqlerrm =
         'Invalid JURISDICTION_PATH_ACCESSIBILITY value contract' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Context observation accepted a prohibited extra key';
  end if;

  v_blocked := false;
  begin
    insert into public.fit_context_claim_observations (
      context_claim_id, observed_value, authority, evidence_id,
      method, method_version
    ) values (
      '40000000-0000-0000-0000-000000000071',
      '{"accessible":"yes"}',
      'OFFICIAL_REGULATORY',
      '40000000-0000-0000-0000-000000000002',
      'HUMAN', '1'
    );
  exception when others then
    if sqlstate='23514'
       and sqlerrm =
         'Invalid JURISDICTION_PATH_ACCESSIBILITY value contract' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Context observation accepted a wrong value type';
  end if;
end;
$test$;

insert into public.fit_context_claim_observations (
  context_observation_id, context_claim_id, observed_value, authority,
  evidence_id, method, method_version
) values
  ('40000000-0000-0000-0000-000000000072','40000000-0000-0000-0000-000000000071','{"accessible":true}','OFFICIAL_REGULATORY','40000000-0000-0000-0000-000000000002','HUMAN','1'),
  ('40000000-0000-0000-0000-000000000073','40000000-0000-0000-0000-000000000071','{"accessible":false}','OFFICIAL_REGULATORY','40000000-0000-0000-0000-000000000002','HUMAN','1');
select public.review_fit_context_observation(
  '40000000-0000-0000-0000-000000000072','VERIFIED','phase3-test-reviewer'
);
select public.select_fit_context_claim_observation(
  '40000000-0000-0000-0000-000000000071',
  '40000000-0000-0000-0000-000000000072',
  'KNOWN', 'phase3-test-reviewer'
);
insert into public.fit_context_concept_mappings (
  context_mapping_id, context_claim_id, concept_id, relation_code,
  mapping_status, method, proposed_by
) values (
  '40000000-0000-0000-0000-000000000077',
  '40000000-0000-0000-0000-000000000071',
  '10000000-0000-0000-0000-000000000052',
  'PROGRAM_ASSOCIATED_WITH_PATH', 'PROPOSED', 'HUMAN',
  'phase3-test-reviewer'
);
do $test$
declare
  v_blocked boolean := false;
begin
  begin
    update public.fit_context_concept_mappings
    set mapping_status = 'VERIFIED',
        reviewed_by = 'bypass',
        reviewed_at = now(),
        verification_evidence_id =
          '40000000-0000-0000-0000-000000000002'
    where context_mapping_id =
      '40000000-0000-0000-0000-000000000077';
  exception when object_not_in_prerequisite_state then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Direct context mapping review transition succeeded';
  end if;
  perform public.review_fit_context_mapping(
    '40000000-0000-0000-0000-000000000077',
    'VERIFIED', 'phase3-test-reviewer',
    '40000000-0000-0000-0000-000000000002'
  );
  if not exists (
    select 1 from public.fit_context_concept_mappings
    where context_mapping_id =
      '40000000-0000-0000-0000-000000000077'
      and mapping_status = 'VERIFIED'
      and reviewed_at is not null
      and verification_evidence_id =
        '40000000-0000-0000-0000-000000000002'
  ) then
    raise exception 'Controlled context mapping review did not persist authority';
  end if;
  perform public.review_fit_context_mapping(
    '40000000-0000-0000-0000-000000000077',
    'RETIRED', 'phase3-test-reviewer', null,
    'Superseded test mapping'
  );
end;
$test$;

do $test$
declare
  v_blocked boolean;
begin
  v_blocked := false;
  begin
    insert into public.fit_context_claims (
      claim_definition_id,definition_version,program_version_id,
      jurisdiction_code,path_code,valid_from,valid_to
    ) values (
      '40000000-0000-0000-0000-000000000070',1,
      '00000000-0000-0000-0000-000000000401','US_NY','F1_OPT',
      date '2026-01-01',date '2027-12-31'
    );
  exception when unique_violation then v_blocked := true;
  end;
  if not v_blocked then raise exception 'Duplicate deterministic context claim identity was accepted'; end if;

  if (select count(*) from public.fit_context_claim_observations
      where context_claim_id='40000000-0000-0000-0000-000000000071') <> 2 then
    raise exception 'Conflicting context observations were not preserved';
  end if;

  v_blocked := false;
  begin
    insert into public.fit_context_claim_selections (
      context_claim_id, context_selection_id, context_observation_id,
      knowledge_status, selected_at, selected_by
    ) values (
      '40000000-0000-0000-0000-000000000071',
      '40000000-0000-0000-0000-00000000007a',
      null, 'SOURCE_CONFLICT', now(), 'bypass'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm = 'Use select_fit_context_claim_observation()' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then raise exception 'Direct canonical context selection write succeeded'; end if;

  perform public.select_fit_context_claim_observation(
    '40000000-0000-0000-0000-000000000071',null,'SOURCE_CONFLICT','reviewer'
  );

  insert into public.fit_context_concept_mappings (
    context_claim_id,concept_id,relation_code,mapping_status,method,
    confidence,model_version
  ) values (
    '40000000-0000-0000-0000-000000000071',
    '10000000-0000-0000-0000-000000000052',
    'PROGRAM_ASSOCIATED_WITH_PATH','PROPOSED','MODEL',1,'model-v1'
  );
  v_blocked := false;
  begin
    insert into public.fit_context_concept_mappings (
      context_claim_id,concept_id,mapping_status,method,confidence,
      relation_code,reviewed_by,reviewed_at,verification_evidence_id
    ) values (
      '40000000-0000-0000-0000-000000000071',
      '10000000-0000-0000-0000-000000000051','VERIFIED','HUMAN',1,
      'PROGRAM_ASSOCIATED_WITH_PATH',
      'reviewer',now(),'40000000-0000-0000-0000-000000000002'
    );
  exception when others then
    if sqlstate = '55000'
       and (
         sqlerrm = 'Context mappings must enter as PROPOSED'
         or sqlerrm like '%cannot be inserted%'
       ) then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then raise exception 'Confidence granted mapping authority over a conflict'; end if;

  v_blocked := false;
  begin
    insert into public.fit_context_claims (
      claim_definition_id,definition_version,jurisdiction_code,path_code,
      valid_from,valid_to
    ) values (
      '40000000-0000-0000-0000-000000000070',1,'us-ny','bad path',
      date '2027-01-01',date '2026-01-01'
    );
  exception when check_violation then v_blocked := true;
  end;
  if not v_blocked then raise exception 'Invalid context jurisdiction/path/time scope was accepted'; end if;
end;
$test$;

insert into public.fit_context_claim_definitions (
  claim_definition_id, claim_code, semantic_source_class_code,
  definition_version, description, value_contract
) values (
  '40000000-0000-0000-0000-000000000075',
  'REVIEWED_CAREER_OUTCOME', 'FIT_CONTEXT_CAREER', 1,
  'Reviewed career outcome with mandatory applicability metadata.',
  '{"requiredKeys":["outcome"]}'
);
select public.verify_fit_context_definition(
  '40000000-0000-0000-0000-000000000075',
  'phase3-test-reviewer',
  '40000000-0000-0000-0000-000000000002'
);
insert into public.fit_context_claims (
  context_claim_id, claim_definition_id, definition_version,
  program_version_id, geography_code, valid_from
) values (
  '40000000-0000-0000-0000-000000000076',
  '40000000-0000-0000-0000-000000000075', 1,
  '00000000-0000-0000-0000-000000000401', 'US',
  date '2026-01-01'
);
do $test$
declare
  v_blocked boolean := false;
begin
  begin
    insert into public.fit_context_claim_observations (
      context_claim_id, observed_value, authority, evidence_id,
      method, method_version
    ) values (
      '40000000-0000-0000-0000-000000000076',
      '{"outcome":"quantitative research"}',
      'REVIEWED_STRUCTURED',
      '40000000-0000-0000-0000-000000000002',
      'HUMAN', '1'
    );
  exception when others then
    if sqlstate = '23514'
       and sqlerrm = 'Invalid REVIEWED_CAREER_OUTCOME value contract' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Career outcome omitted applicability metadata';
  end if;
end;
$test$;

-- Build a complete all-UNKNOWN evaluation. Each method has every ALLOWED policy
-- represented by an exact state and one typed intent item.
create procedure pg_temp.build_fit_evaluation(
  p_evaluation_id uuid,
  p_reverse boolean default false
)
language plpgsql
as $procedure$
declare
  v_method record;
  v_policy record;
  v_intent_id uuid;
  v_item_id uuid;
  v_state_id uuid;
  v_result_id uuid;
begin
  insert into public.fit_evaluations (
    evaluation_id,profile_version_id,profile_snapshot_hash,intent_set_id,
    intent_snapshot_hash,program_version_id,taxonomy_release_code,
    contract_release_id,evaluator_build_id,evaluator_name,evaluator_version,
    evaluator_build_hash
  ) select
    p_evaluation_id,'40000000-0000-0000-0000-000000000020',
    (select snapshot_hash from public.student_profile_versions
      where profile_version_id = '40000000-0000-0000-0000-000000000020'),
    intent_set_id,snapshot_hash,'00000000-0000-0000-0000-000000000401',
    'v0.1','30000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000003',
    'phase3-fit-test','0.1.0',repeat('b',64)
  from public.fit_intent_sets
  where intent_set_id='40000000-0000-0000-0000-000000000050';
  perform public.authorize_fit_evaluation_assembly(
    p_evaluation_id, repeat('b',64)
  );

  for v_method in
    select * from public.fit_dimension_methods
    where contract_release_id='30000000-0000-0000-0000-000000000001'
    order by case when p_reverse then dimension::text end desc,
             case when not p_reverse then dimension::text end asc
  loop
    select intent_declaration_id into v_intent_id
    from public.fit_intent_declarations
    where intent_set_id='40000000-0000-0000-0000-000000000050'
      and dimension=v_method.dimension;

    insert into public.fit_dimension_results (
      evaluation_id,dimension,assessment,confidence,evidence_coverage,
      method_id,inference_category,presentation_explanation
    ) values (
      p_evaluation_id,v_method.dimension,'UNKNOWN','LOW','INSUFFICIENT',
      v_method.method_id,v_method.inference_category,'Insufficient approved inputs.'
    ) returning dimension_result_id into v_result_id;

    v_state_id := null;
    for v_policy in
      select * from public.fit_method_input_policies
      where method_id=v_method.method_id and disposition='ALLOWED'
      order by case when p_reverse then input_policy_id end desc,
               case when not p_reverse then input_policy_id end asc
    loop
      if v_policy.input_domain='FIT_INTENTS' then
        insert into public.fit_manifest_items (
          evaluation_id,profile_version_id,method_id,input_policy_id,
          item_type,authority_role
        ) values (
          p_evaluation_id,'40000000-0000-0000-0000-000000000020',
          v_method.method_id,v_policy.input_policy_id,
          'FIT_INTENT_DECLARATION','AUTHORITATIVE'
        ) returning manifest_item_id into v_item_id;
        insert into public.fit_manifest_intent_declarations (
          manifest_item_id, evaluation_id, profile_version_id,
          intent_declaration_id, intent_set_id
        ) values (
          v_item_id,p_evaluation_id,'40000000-0000-0000-0000-000000000020',
          v_intent_id,'40000000-0000-0000-0000-000000000050'
        );
        insert into public.fit_input_domain_states (
          evaluation_id,profile_version_id,method_id,input_policy_id,availability
        ) values (
          p_evaluation_id,'40000000-0000-0000-0000-000000000020',
          v_method.method_id,v_policy.input_policy_id,'INCLUDED'
        );
      else
        insert into public.fit_input_domain_states (
          evaluation_id,profile_version_id,method_id,input_policy_id,
          availability,explanation
        ) values (
          p_evaluation_id,'40000000-0000-0000-0000-000000000020',
          v_method.method_id,v_policy.input_policy_id,'NOT_SUPPLIED',
          'Optional or unavailable in this isolated fixture.'
        ) returning input_state_id into v_state_id;
      end if;
    end loop;

    select state.input_state_id into v_state_id
    from public.fit_input_domain_states state
    where state.evaluation_id = p_evaluation_id
      and state.method_id = v_method.method_id
      and state.availability <> 'INCLUDED'
    order by state.input_policy_id
    limit 1;
    insert into public.fit_dimension_reasons (
      dimension_result_id,evaluation_id,reason_definition_id,direction,
      input_state_id,presentation_explanation
    ) values (
      v_result_id,p_evaluation_id,
      '30000000-0000-0000-0000-000000000202','LIMITING',v_state_id,
      'Required approved input was unavailable.'
    );
  end loop;
end;
$procedure$;

create procedure pg_temp.supply_required_inputs(
  p_evaluation_id uuid,
  p_dimension public.fit_dimension
)
language plpgsql
as $procedure$
declare
  v_method uuid;
  v_policy record;
  v_item uuid;
  v_course_observation uuid;
  v_version_observation uuid;
  v_cost_observation uuid;
  v_catalog_mapping uuid :=
    '40000000-0000-0000-0000-00000000007d';
  v_context_selection uuid;
begin
  select method_id into v_method
  from public.fit_dimension_methods
  where contract_release_id='30000000-0000-0000-0000-000000000001'
    and dimension=p_dimension;

  select observation_id into v_course_observation
  from public.canonical_field_selections
  where record_type='PROGRAM_COURSE'
    and field_name='course_name'
  order by record_id
  limit 1;
  select observation_id into v_version_observation
  from public.canonical_field_selections
  where record_type='PROGRAM_VERSION'
    and record_id='00000000-0000-0000-0000-000000000401'
    and field_name='duration_months';
  select observation_id into v_cost_observation
  from public.field_observations
  where record_type='PROGRAM_COST'
    and record_id='00000000-0000-0000-0000-000000000404'
    and field_name='tuition_amount'
  limit 1;
  select context_selection_id into v_context_selection
  from public.fit_context_claim_selections
  where context_claim_id =
    '40000000-0000-0000-0000-000000000071';

  for v_policy in
    select p.*
    from public.fit_method_input_policies p
    join public.fit_input_domain_states s
      on s.input_policy_id=p.input_policy_id
     and s.evaluation_id=p_evaluation_id
    where p.method_id=v_method
      and p.disposition='ALLOWED'
      and p.requirement='REQUIRED'
      and s.availability<>'INCLUDED'
  loop
    insert into public.fit_manifest_items (
      evaluation_id,profile_version_id,method_id,input_policy_id,
      item_type,authority_role,source_class_code
    ) values (
      p_evaluation_id,'40000000-0000-0000-0000-000000000020',
      v_method,v_policy.input_policy_id,
      case v_policy.input_domain
        when 'STUDENT_GOALS' then 'PHASE2_STUDENT_GOAL'
        when 'STUDENT_PREFERENCES' then 'PHASE2_STUDENT_PREFERENCE'
        when 'PROGRAM_COURSES' then 'CATALOG_FIELD_OBSERVATION'
        when 'PROGRAM_VERSIONS' then 'CATALOG_FIELD_OBSERVATION'
        when 'PROGRAM_COSTS' then 'CATALOG_FIELD_OBSERVATION'
        when 'CATALOG_MAPPINGS' then 'CATALOG_MAPPING'
        when 'FIT_CONTEXT_CLAIMS' then 'FIT_CONTEXT_CLAIM_SELECTION'
      end::public.fit_manifest_item_type,
      case when v_policy.input_domain in (
        'PROGRAM_COURSES','PROGRAM_VERSIONS','PROGRAM_COSTS',
        'CATALOG_MAPPINGS'
      ) then 'AUTHORITATIVE'
      else 'LIMITING_CONTEXT'
      end::public.fit_manifest_authority_role,
      case
        when v_policy.input_domain = 'FIT_CONTEXT_CLAIMS'
          then 'FIT_CONTEXT_ACCESSIBILITY'
        else null
      end
    ) returning manifest_item_id into v_item;

    if v_policy.input_domain='STUDENT_GOALS' then
      insert into public.fit_manifest_phase2_goals values (
        v_item,p_evaluation_id,'40000000-0000-0000-0000-000000000020',
        '40000000-0000-0000-0000-000000000040'
      );
      insert into public.fit_manifest_student_field_uses values
        (v_item,p_evaluation_id,'GOAL_TYPE'),
        (v_item,p_evaluation_id,'CONCEPT_ID');
    elsif v_policy.input_domain='STUDENT_PREFERENCES' then
      insert into public.fit_manifest_phase2_preferences values (
        v_item,p_evaluation_id,'40000000-0000-0000-0000-000000000020',
        '40000000-0000-0000-0000-000000000041'
      );
      insert into public.fit_manifest_student_field_uses values
        (v_item,p_evaluation_id,'PREFERENCE_TYPE'),
        (v_item,p_evaluation_id,'VALUE');
    elsif v_policy.input_domain in (
      'PROGRAM_COURSES', 'PROGRAM_VERSIONS', 'PROGRAM_COSTS'
    ) then
      select observation.observation_id
      into v_version_observation
      from public.canonical_field_selections selection
      join public.field_observations observation
        on observation.observation_id = selection.observation_id
      join public.fit_method_program_field_policies field_policy
        on field_policy.method_id = v_method
       and field_policy.input_policy_id = v_policy.input_policy_id
       and field_policy.record_type = observation.record_type
       and field_policy.field_name = observation.field_name
      where public.catalog_record_program_version(
        observation.record_type, observation.record_id
      ) = '00000000-0000-0000-0000-000000000401'
      order by
        (observation.knowledge_status = 'KNOWN') desc,
        (observation.field_name = 'tuition_amount') desc,
        observation.field_name
      limit 1;
      if v_version_observation is null then
        raise exception 'No allowlisted canonical program fixture for policy %',
          v_policy.input_policy_id;
      end if;
      insert into public.fit_manifest_catalog_observations values (
        v_item,p_evaluation_id,'40000000-0000-0000-0000-000000000020',
        v_version_observation
      );
    elsif v_policy.input_domain='CATALOG_MAPPINGS' then
      insert into public.fit_manifest_catalog_mappings values (
        v_item,p_evaluation_id,
        '40000000-0000-0000-0000-000000000020',
        v_catalog_mapping
      );
    elsif v_policy.input_domain='FIT_CONTEXT_CLAIMS' then
      insert into public.fit_manifest_context_claim_selections values (
        v_item,p_evaluation_id,'40000000-0000-0000-0000-000000000020',
        '40000000-0000-0000-0000-000000000071',v_context_selection,
        null,'SOURCE_CONFLICT'
      );
    else
      raise exception 'No fixture mapping for required domain %', v_policy.input_domain;
    end if;

    update public.fit_input_domain_states
    set availability='INCLUDED', explanation=null
    where evaluation_id=p_evaluation_id
      and input_policy_id=v_policy.input_policy_id;
  end loop;
end;
$procedure$;

create function pg_temp.complete_fit_evaluation(p_evaluation_id uuid)
returns text
language plpgsql
as $function$
begin
  perform public.seal_fit_evaluation_inputs(p_evaluation_id);
  return public.finalize_fit_evaluation(p_evaluation_id);
end;
$function$;

do $test$
declare
  v_evaluation uuid;
  v_other_evaluation uuid;
  v_blocked boolean := false;
begin
  execute 'set local role service_role';
  v_evaluation := public.start_fit_evaluation(
    '40000000-0000-0000-0000-000000000020',
    '40000000-0000-0000-0000-000000000050',
    '00000000-0000-0000-0000-000000000401',
    'v0.1',
    '30000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000003'
  );
  v_other_evaluation := public.start_fit_evaluation(
    '40000000-0000-0000-0000-000000000020',
    '40000000-0000-0000-0000-000000000050',
    '00000000-0000-0000-0000-000000000401',
    'v0.1',
    '30000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000003'
  );
  -- A caller-controlled legacy GUC must not replace evaluation-scoped
  -- durable authorization.
  perform set_config('app.fit_evaluator_write', 'on', true);
  begin
    insert into public.fit_dimension_results (
      evaluation_id, dimension, assessment, confidence,
      evidence_coverage, method_id, inference_category
    ) values (
      v_evaluation, 'ACADEMIC', 'UNKNOWN', 'LOW', 'INSUFFICIENT',
      '30000000-0000-0000-0000-000000000101', 'HYBRID'
    );
  exception when others then
    if sqlstate = '42501' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Service role assembled candidate output without execution authorization';
  end if;
  perform set_config('app.fit_evaluator_write', '', true);
  perform public.authorize_fit_evaluation_assembly(
    v_evaluation, repeat('b', 64)
  );
  v_blocked := false;
  begin
    insert into public.fit_dimension_results (
      evaluation_id, dimension, assessment, confidence,
      evidence_coverage, method_id, inference_category
    ) values (
      v_other_evaluation, 'ACADEMIC', 'UNKNOWN', 'LOW', 'INSUFFICIENT',
      '30000000-0000-0000-0000-000000000101', 'HYBRID'
    );
  exception when others then
    if sqlstate = '42501' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Authorization for Evaluation A mutated Evaluation B';
  end if;
  perform public.insert_fit_dimension_result(jsonb_populate_record(
    null::public.fit_dimension_results,
    jsonb_build_object(
      'evaluation_id', v_evaluation,
      'dimension', 'ACADEMIC',
      'assessment', 'UNKNOWN',
      'confidence', 'LOW',
      'evidence_coverage', 'INSUFFICIENT',
      'method_id', '30000000-0000-0000-0000-000000000101',
      'inference_category', 'HYBRID'
    )
  ));
  execute 'reset role';
  v_blocked := false;
  begin
    update public.fit_evaluation_methods
    set created_at = created_at
    where evaluation_id = v_evaluation
      and dimension = 'ACADEMIC';
  exception when others then
    if sqlstate = '55000'
       and sqlerrm = 'Pinned Fit evaluation methods are immutable' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Automatically pinned Fit evaluation method remained mutable';
  end if;
end;
$test$;

call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000081',false
);
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000082',true
);

do $test$
declare
  v_before text;
  v_after text;
begin
  v_before := public.compute_fit_result_fingerprint(
    '40000000-0000-0000-0000-000000000081'
  );
  update public.fit_dimension_results
  set confidence='MEDIUM'
  where evaluation_id='40000000-0000-0000-0000-000000000081'
    and dimension='ACADEMIC';
  v_after := public.compute_fit_result_fingerprint(
    '40000000-0000-0000-0000-000000000081'
  );
  if v_after = v_before then
    raise exception 'Authoritative structured result semantics did not change the result fingerprint';
  end if;
  update public.fit_dimension_results
  set confidence='LOW'
  where evaluation_id='40000000-0000-0000-0000-000000000081'
    and dimension='ACADEMIC';
end;
$test$;

do $test$
declare
  v_first text;
  v_second text;
  v_blocked boolean;
begin
  v_first := pg_temp.complete_fit_evaluation(
    '40000000-0000-0000-0000-000000000081'
  );
  v_second := pg_temp.complete_fit_evaluation(
    '40000000-0000-0000-0000-000000000082'
  );
  if v_first !~ '^[a-f0-9]{64}$' or v_second <> v_first then
    raise exception 'Equivalent Fit inputs did not produce one canonical 64-hex fingerprint';
  end if;
  if (
    select first_eval.result_fingerprint is distinct from
      second_eval.result_fingerprint
      or first_eval.result_fingerprint !~ '^[a-f0-9]{64}$'
      or first_eval.candidate_input_fingerprint is distinct from
        first_eval.decision_input_fingerprint
    from public.fit_evaluations first_eval
    cross join public.fit_evaluations second_eval
    where first_eval.evaluation_id =
      '40000000-0000-0000-0000-000000000081'
      and second_eval.evaluation_id =
      '40000000-0000-0000-0000-000000000082'
  ) then
    raise exception 'Canonical result fingerprint or sealed-input integrity failed';
  end if;
  if (select count(*) from public.fit_dimension_results
      where evaluation_id='40000000-0000-0000-0000-000000000081') <> 6 then
    raise exception 'Completed Fit evaluation did not persist all six results';
  end if;

  v_blocked := false;
  begin
    update public.fit_dimension_results set confidence='HIGH'
    where evaluation_id='40000000-0000-0000-0000-000000000081'
      and dimension='ACADEMIC';
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'Fit evaluation assembly is allowed only while BUILDING' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then raise exception 'Completed Fit result was mutable'; end if;
end;
$test$;

-- A changed exact decision-manifest item must change the fingerprint.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000083',false
);
do $test$
declare
  v_method uuid := '30000000-0000-0000-0000-000000000102';
  v_policy uuid;
  v_item uuid;
  v_international_policy uuid;
  v_international_item uuid;
  v_changed text;
  v_original text;
  v_changed_result text;
  v_original_result text;
begin
  select input_policy_id into v_policy
  from public.fit_method_input_policies
  where method_id=v_method and input_domain='STUDENT_GOALS'
    and disposition='ALLOWED';
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,item_type,authority_role
  ) values (
    '40000000-0000-0000-0000-000000000083',
    '40000000-0000-0000-0000-000000000020',v_method,v_policy,
    'PHASE2_STUDENT_GOAL','LIMITING_CONTEXT'
  ) returning manifest_item_id into v_item;
  insert into public.fit_manifest_phase2_goals values (
    v_item,'40000000-0000-0000-0000-000000000083',
    '40000000-0000-0000-0000-000000000020',
    '40000000-0000-0000-0000-000000000040'
  );
  insert into public.fit_manifest_student_field_uses values
    (v_item,'40000000-0000-0000-0000-000000000083','GOAL_TYPE'),
    (v_item,'40000000-0000-0000-0000-000000000083','CONCEPT_ID');
  update public.fit_input_domain_states set availability='INCLUDED',explanation=null
  where evaluation_id='40000000-0000-0000-0000-000000000083'
    and method_id=v_method and input_policy_id=v_policy;
  select input_policy_id into v_international_policy
  from public.fit_method_input_policies
  where method_id='30000000-0000-0000-0000-000000000106'
    and input_domain='STUDENT_GOALS'
    and disposition='ALLOWED';
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    '40000000-0000-0000-0000-000000000083',
    '40000000-0000-0000-0000-000000000020',
    '30000000-0000-0000-0000-000000000106',
    v_international_policy,'PHASE2_STUDENT_GOAL','LIMITING_CONTEXT'
  ) returning manifest_item_id into v_international_item;
  insert into public.fit_manifest_phase2_goals values (
    v_international_item,
    '40000000-0000-0000-0000-000000000083',
    '40000000-0000-0000-0000-000000000020',
    '40000000-0000-0000-0000-000000000040'
  );
  insert into public.fit_manifest_student_field_uses values
    (v_international_item,
     '40000000-0000-0000-0000-000000000083','GOAL_TYPE'),
    (v_international_item,
     '40000000-0000-0000-0000-000000000083','CONCEPT_ID');
  update public.fit_input_domain_states
  set availability='INCLUDED',explanation=null
  where evaluation_id='40000000-0000-0000-0000-000000000083'
    and method_id='30000000-0000-0000-0000-000000000106'
    and input_policy_id=v_international_policy;
  v_changed := pg_temp.complete_fit_evaluation(
    '40000000-0000-0000-0000-000000000083'
  );
  select decision_input_fingerprint into v_original from public.fit_evaluations
  where evaluation_id='40000000-0000-0000-0000-000000000081';
  if v_changed = v_original then
    raise exception 'Changing exact evidence did not change the Fit fingerprint';
  end if;
  select result_fingerprint into v_changed_result
  from public.fit_evaluations
  where evaluation_id='40000000-0000-0000-0000-000000000083';
  select result_fingerprint into v_original_result
  from public.fit_evaluations
  where evaluation_id='40000000-0000-0000-0000-000000000081';
  if v_changed_result = v_original_result then
    raise exception 'Result fingerprint did not bind the sealed decision input fingerprint';
  end if;
end;
$test$;

-- Direct finalizer rejection probes for malformed assembly and categorical output.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000084',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-000000000084','ACADEMIC'
);
do $test$
declare
  v_blocked boolean := false;
begin
  update public.fit_dimension_results set assessment='MIXED'
  where evaluation_id='40000000-0000-0000-0000-000000000084'
    and dimension='ACADEMIC';
  update public.fit_dimension_reasons
  set reason_definition_id =
    '30000000-0000-0000-0000-000000000206'
  where dimension_result_id = (
    select dimension_result_id
    from public.fit_dimension_results
    where evaluation_id='40000000-0000-0000-0000-000000000084'
      and dimension='ACADEMIC'
  );
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-000000000084'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'MIXED requires material supporting and contradicting signals' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'MIXED without material evidence directions finalized';
  end if;
end;
$test$;

call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000085',false
);
do $test$
declare
  v_item uuid;
  v_policy uuid;
  v_blocked boolean := false;
begin
  select input_policy_id into v_policy
  from public.fit_method_input_policies
  where method_id='30000000-0000-0000-0000-000000000101'
    and input_domain='FIT_INTENTS';
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,item_type,authority_role
  ) values (
    '40000000-0000-0000-0000-000000000085',
    '40000000-0000-0000-0000-000000000020',
    '30000000-0000-0000-0000-000000000101',v_policy,
    'PHASE2_STUDENT_GOAL','LIMITING_CONTEXT'
  ) returning manifest_item_id into v_item;
  insert into public.fit_manifest_phase2_goals values (
    v_item,'40000000-0000-0000-0000-000000000085',
    '40000000-0000-0000-0000-000000000020',
    '40000000-0000-0000-0000-000000000040'
  );
  insert into public.fit_manifest_student_field_uses values (
    v_item,'40000000-0000-0000-0000-000000000085','GOAL_TYPE'
  );
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-000000000085'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'Manifest item type/source is incompatible with its input-policy domain' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Policy-domain/item-type mismatch finalized';
  end if;
end;
$test$;

-- MISALIGNMENT must have a material contradiction.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000086',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-000000000086','ACADEMIC'
);
do $test$
declare
  v_result uuid;
  v_signal uuid;
  v_blocked boolean := false;
begin
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id='40000000-0000-0000-0000-000000000086'
    and dimension='ACADEMIC';
  delete from public.fit_dimension_reasons where dimension_result_id=v_result;
  update public.fit_dimension_results set assessment='MISALIGNMENT'
  where dimension_result_id=v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category
  ) values (
    '40000000-0000-0000-0000-000000000086',v_result,'ACADEMIC',
    '30000000-0000-0000-0000-000000000101',
    md5('30000000-0000-0000-0000-000000000101:NON_MATERIAL_CONTRADICTION')::uuid,
    'CONTRADICTING',false,'RULE'
  ) returning signal_id into v_signal;
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,direction,signal_id
  ) values (
    v_result,'40000000-0000-0000-0000-000000000086',
    '30000000-0000-0000-0000-000000000204','CONTRADICTING',v_signal
  );
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-000000000086'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'MISALIGNMENT requires a method-valid material contradiction' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'MISALIGNMENT without a material contradiction finalized';
  end if;
end;
$test$;

-- A REQUIRED contradiction cannot claim authority without deterministic,
-- directly comparable evidence.
insert into public.field_observations (
  observation_id, record_type, record_id, field_name, observed_value,
  knowledge_status, evidence_id, notes
) values (
  '40000000-0000-0000-0000-000000000078',
  'PROGRAM_VERSION',
  '00000000-0000-0000-0000-000000000401',
  'delivery_mode', '"IN_PERSON"', 'KNOWN',
  '40000000-0000-0000-0000-000000000002',
  'Test-only verified delivery fixture for comparable constraint probes.'
);
select pg_temp.review_unspecified_applicability('40000000-0000-0000-0000-000000000078');
select public.select_field_observation(
  '40000000-0000-0000-0000-000000000078',
  'phase3-test-reviewer'
);
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000087',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-000000000087','GEOGRAPHIC_DELIVERY'
);
do $test$
declare
  v_result uuid;
  v_signal uuid;
  v_intent_item uuid;
  v_program_item uuid;
  v_blocked boolean := false;
begin
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id='40000000-0000-0000-0000-000000000087'
    and dimension='GEOGRAPHIC_DELIVERY';
  select i.manifest_item_id into v_intent_item
  from public.fit_manifest_items i
  join public.fit_manifest_intent_declarations d using(manifest_item_id)
  where i.evaluation_id='40000000-0000-0000-0000-000000000087'
    and d.intent_declaration_id='40000000-0000-0000-0000-000000000062';
  select manifest_item_id into v_program_item
  from public.fit_manifest_items
  where evaluation_id='40000000-0000-0000-0000-000000000087'
    and method_id='30000000-0000-0000-0000-000000000104'
    and item_type='CATALOG_FIELD_OBSERVATION';
  delete from public.fit_dimension_reasons where dimension_result_id=v_result;
  update public.fit_dimension_results set assessment='MISALIGNMENT'
  where dimension_result_id=v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,model_version,model_build_hash,intent_declaration_id,
    required_constraint_contradiction,evidence_metadata
  ) values (
    '40000000-0000-0000-0000-000000000087',v_result,
    'GEOGRAPHIC_DELIVERY','30000000-0000-0000-0000-000000000104',
    md5('30000000-0000-0000-0000-000000000104:MATERIAL_CONTRADICTION')::uuid,
    'CONTRADICTING',true,'MODEL','model-v1',repeat('c',64),
    '40000000-0000-0000-0000-000000000062',true,'{}'
  ) returning signal_id into v_signal;
  insert into public.fit_signal_evidence values (
    v_signal,'40000000-0000-0000-0000-000000000087',v_intent_item
  ), (
    v_signal,'40000000-0000-0000-0000-000000000087',v_program_item
  );
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,direction,signal_id
  ) values (
    v_result,'40000000-0000-0000-0000-000000000087',
    '30000000-0000-0000-0000-000000000205','CONTRADICTING',v_signal
  );
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-000000000087'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'Required contradictions must be deterministic, directly comparable, reference REQUIRED intent, and force MISALIGNMENT' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Non-comparable/model REQUIRED contradiction finalized';
  end if;
end;
$test$;

-- Even a directly comparable REQUIRED contradiction forces MISALIGNMENT; a
-- balancing supporting signal cannot downgrade it to MIXED.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000088',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-000000000088','GEOGRAPHIC_DELIVERY'
);
do $test$
declare
  v_result uuid;
  v_contradiction uuid;
  v_support uuid;
  v_intent_item uuid;
  v_program_item uuid;
  v_blocked boolean := false;
begin
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id='40000000-0000-0000-0000-000000000088'
    and dimension='GEOGRAPHIC_DELIVERY';
  select i.manifest_item_id into v_intent_item
  from public.fit_manifest_items i
  join public.fit_manifest_intent_declarations d using(manifest_item_id)
  where i.evaluation_id='40000000-0000-0000-0000-000000000088'
    and d.intent_declaration_id='40000000-0000-0000-0000-000000000062';
  select manifest_item_id into v_program_item
  from public.fit_manifest_items
  where evaluation_id='40000000-0000-0000-0000-000000000088'
    and method_id='30000000-0000-0000-0000-000000000104'
    and item_type='CATALOG_FIELD_OBSERVATION';
  delete from public.fit_dimension_reasons where dimension_result_id=v_result;
  update public.fit_dimension_results set assessment='MIXED'
  where dimension_result_id=v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,intent_declaration_id,
    required_constraint_contradiction,evidence_metadata
  ) values (
    '40000000-0000-0000-0000-000000000088',v_result,
    'GEOGRAPHIC_DELIVERY','30000000-0000-0000-0000-000000000104',
    md5('30000000-0000-0000-0000-000000000104:MATERIAL_CONTRADICTION')::uuid,
    'CONTRADICTING',true,'DETERMINISTIC',
    '40000000-0000-0000-0000-000000000062',true,
    '{"directComparable":true}'
  ) returning signal_id into v_contradiction;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,intent_declaration_id,evidence_metadata
  ) values (
    '40000000-0000-0000-0000-000000000088',v_result,
    'GEOGRAPHIC_DELIVERY','30000000-0000-0000-0000-000000000104',
    md5('30000000-0000-0000-0000-000000000104:MATERIAL_SUPPORT')::uuid,
    'SUPPORTING',true,'DETERMINISTIC',
    '40000000-0000-0000-0000-000000000062',
    '{"directComparable":true}'
  ) returning signal_id into v_support;
  insert into public.fit_signal_evidence values
    (v_contradiction,'40000000-0000-0000-0000-000000000088',v_intent_item),
    (v_contradiction,'40000000-0000-0000-0000-000000000088',v_program_item),
    (v_support,'40000000-0000-0000-0000-000000000088',v_intent_item),
    (v_support,'40000000-0000-0000-0000-000000000088',v_program_item);
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,direction,signal_id
  ) values
    (v_result,'40000000-0000-0000-0000-000000000088',
     '30000000-0000-0000-0000-000000000204','CONTRADICTING',v_contradiction),
    (v_result,'40000000-0000-0000-0000-000000000088',
     '30000000-0000-0000-0000-000000000203','SUPPORTING',v_support);
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-000000000088'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'Required contradictions must be deterministic, directly comparable, reference REQUIRED intent, and force MISALIGNMENT' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Comparable REQUIRED contradiction finalized as MIXED';
  end if;
end;
$test$;

-- A genuinely comparable REQUIRED delivery contradiction finalizes only as
-- dimension-level MISALIGNMENT.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000095',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-000000000095','GEOGRAPHIC_DELIVERY'
);
do $test$
declare
  v_result uuid;
  v_signal uuid;
  v_intent_item uuid;
  v_program_item uuid;
begin
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id='40000000-0000-0000-0000-000000000095'
    and dimension='GEOGRAPHIC_DELIVERY';
  select manifest_item_id into v_intent_item
  from public.fit_manifest_intent_declarations
  where evaluation_id='40000000-0000-0000-0000-000000000095'
    and intent_declaration_id =
      '40000000-0000-0000-0000-000000000062';
  select manifest_item_id into v_program_item
  from public.fit_manifest_items
  where evaluation_id='40000000-0000-0000-0000-000000000095'
    and method_id='30000000-0000-0000-0000-000000000104'
    and item_type='CATALOG_FIELD_OBSERVATION';
  delete from public.fit_dimension_reasons
  where dimension_result_id=v_result;
  update public.fit_dimension_results
  set assessment='MISALIGNMENT', confidence='HIGH',
      evidence_coverage='SUFFICIENT'
  where dimension_result_id=v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,intent_declaration_id,
    required_constraint_contradiction,evidence_metadata
  ) values (
    '40000000-0000-0000-0000-000000000095',v_result,
    'GEOGRAPHIC_DELIVERY',
    '30000000-0000-0000-0000-000000000104',
    md5('30000000-0000-0000-0000-000000000104:MATERIAL_CONTRADICTION')::uuid,
    'CONTRADICTING',true,'DETERMINISTIC',
    '40000000-0000-0000-0000-000000000062',true,
    '{"directComparable":true}'
  ) returning signal_id into v_signal;
  insert into public.fit_signal_evidence values
    (v_signal,'40000000-0000-0000-0000-000000000095',v_intent_item),
    (v_signal,'40000000-0000-0000-0000-000000000095',v_program_item);
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,direction,
    signal_id
  ) values (
    v_result,'40000000-0000-0000-0000-000000000095',
    '30000000-0000-0000-0000-000000000205',
    'CONTRADICTING',v_signal
  );
  perform pg_temp.complete_fit_evaluation(
    '40000000-0000-0000-0000-000000000095'
  );
  if not exists (
    select 1 from public.fit_dimension_results
    where evaluation_id =
      '40000000-0000-0000-0000-000000000095'
      and dimension='GEOGRAPHIC_DELIVERY'
      and assessment='MISALIGNMENT'
  ) then
    raise exception 'Comparable REQUIRED contradiction did not persist MISALIGNMENT';
  end if;
end;
$test$;

-- Free-form directComparable metadata cannot manufacture a contradiction
-- when the typed authoritative values actually match.
insert into public.field_observations (
  observation_id, record_type, record_id, field_name, observed_value,
  knowledge_status, evidence_id, notes
) values (
  '40000000-0000-0000-0000-00000000007c',
  'PROGRAM_VERSION',
  '00000000-0000-0000-0000-000000000401',
  'delivery_mode', '"ONLINE"', 'KNOWN',
  '40000000-0000-0000-0000-000000000002',
  'Test-only matching delivery fixture for metadata-authority probe.'
);
select pg_temp.review_unspecified_applicability('40000000-0000-0000-0000-00000000007c');
select public.select_field_observation(
  '40000000-0000-0000-0000-00000000007c',
  'phase3-test-reviewer'
);
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-00000000009d',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-00000000009d','GEOGRAPHIC_DELIVERY'
);
do $test$
declare
  v_result uuid;
  v_signal uuid;
  v_intent_item uuid;
  v_program_item uuid;
  v_blocked boolean := false;
begin
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id='40000000-0000-0000-0000-00000000009d'
    and dimension='GEOGRAPHIC_DELIVERY';
  select item.manifest_item_id into v_intent_item
  from public.fit_manifest_items item
  join public.fit_manifest_intent_declarations intent
    using(manifest_item_id)
  where item.evaluation_id='40000000-0000-0000-0000-00000000009d'
    and intent.intent_declaration_id =
      '40000000-0000-0000-0000-000000000062';
  select manifest_item_id into v_program_item
  from public.fit_manifest_items
  where evaluation_id='40000000-0000-0000-0000-00000000009d'
    and item_type='CATALOG_FIELD_OBSERVATION'
    and method_id='30000000-0000-0000-0000-000000000104';
  delete from public.fit_dimension_reasons
  where dimension_result_id=v_result;
  update public.fit_dimension_results
  set assessment='MISALIGNMENT',confidence='HIGH',
      evidence_coverage='SUFFICIENT'
  where dimension_result_id=v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,intent_declaration_id,
    required_constraint_contradiction,evidence_metadata
  ) values (
    '40000000-0000-0000-0000-00000000009d',v_result,
    'GEOGRAPHIC_DELIVERY',
    '30000000-0000-0000-0000-000000000104',
    md5(
      '30000000-0000-0000-0000-000000000104:MATERIAL_CONTRADICTION'
    )::uuid,
    'CONTRADICTING',true,'DETERMINISTIC',
    '40000000-0000-0000-0000-000000000062',true,
    '{"directComparable":true}'
  ) returning signal_id into v_signal;
  insert into public.fit_signal_evidence values
    (v_signal,'40000000-0000-0000-0000-00000000009d',v_intent_item),
    (v_signal,'40000000-0000-0000-0000-00000000009d',v_program_item);
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,
    direction,signal_id
  ) values (
    v_result,'40000000-0000-0000-0000-00000000009d',
    '30000000-0000-0000-0000-000000000205',
    'CONTRADICTING',v_signal
  );
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-00000000009d'
    );
  exception when others then
    if sqlstate='P0001'
       and sqlerrm =
         'Required contradictions must be deterministic, directly comparable, reference REQUIRED intent, and force MISALIGNMENT' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Fake directComparable metadata granted REQUIRED authority';
  end if;
end;
$test$;
select pg_temp.review_unspecified_applicability(
  '40000000-0000-0000-0000-000000000078'
);
select public.select_field_observation(
  '40000000-0000-0000-0000-000000000078',
  'phase3-test-reviewer'
);

-- Model-only support cannot establish STRONG_ALIGNMENT.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000089',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-000000000089','ACADEMIC'
);
do $test$
declare
  v_result uuid;
  v_signal uuid;
  v_intent_item uuid;
  v_program_item uuid;
  v_blocked boolean := false;
begin
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id='40000000-0000-0000-0000-000000000089'
    and dimension='ACADEMIC';
  select i.manifest_item_id into v_intent_item
  from public.fit_manifest_items i
  join public.fit_manifest_intent_declarations d using(manifest_item_id)
  where i.evaluation_id='40000000-0000-0000-0000-000000000089'
    and d.intent_declaration_id='40000000-0000-0000-0000-000000000061';
  select i.manifest_item_id into v_program_item
  from public.fit_manifest_items i
  where i.evaluation_id='40000000-0000-0000-0000-000000000089'
    and i.method_id='30000000-0000-0000-0000-000000000101'
    and i.item_type='CATALOG_FIELD_OBSERVATION';
  update public.fit_manifest_items
  set authority_role = 'AUTHORITATIVE'
  where manifest_item_id = v_program_item;
  delete from public.fit_dimension_reasons where dimension_result_id=v_result;
  update public.fit_dimension_results set assessment='STRONG_ALIGNMENT'
  where dimension_result_id=v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,model_version,model_build_hash,
    intent_declaration_id
  ) values (
    '40000000-0000-0000-0000-000000000089',v_result,'ACADEMIC',
    '30000000-0000-0000-0000-000000000101',
    md5('30000000-0000-0000-0000-000000000101:DIRECT_HIGH_IMPORTANCE_AUTHORITATIVE_MATCH')::uuid,
    'SUPPORTING',true,'MODEL','model-v1',repeat('c',64),
    '40000000-0000-0000-0000-000000000061'
  ) returning signal_id into v_signal;
  insert into public.fit_signal_evidence values (
    v_signal,'40000000-0000-0000-0000-000000000089',v_intent_item
  ), (
    v_signal,'40000000-0000-0000-0000-000000000089',v_program_item
  );
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,direction,signal_id
  ) values (
    v_result,'40000000-0000-0000-0000-000000000089',
    '30000000-0000-0000-0000-000000000203','SUPPORTING',v_signal
  );
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-000000000089'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'STRONG_ALIGNMENT requires method permission, qualifying non-model positive evidence, and no material contradiction' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Model-only STRONG_ALIGNMENT finalized';
  end if;
end;
$test$;

-- Signal materiality is registry-owned; a caller cannot relabel a signal type.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000092',false
);
do $test$
declare
  v_result uuid;
  v_blocked boolean := false;
begin
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id =
    '40000000-0000-0000-0000-000000000092'
    and dimension = 'ACADEMIC';
  begin
    insert into public.fit_signals (
      evaluation_id, dimension_result_id, dimension, method_id,
      signal_type_id, direction, material, inference_category
    ) values (
      '40000000-0000-0000-0000-000000000092', v_result,
      'ACADEMIC', '30000000-0000-0000-0000-000000000101',
      md5('30000000-0000-0000-0000-000000000101:MATERIAL_SUPPORT')::uuid,
      'SUPPORTING', false, 'RULE'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'Signal method, direction, materiality, and inference must match its result and registered signal type' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Caller overrode registry-owned signal materiality';
  end if;
end;
$test$;

-- Sealing is a distinct lifecycle step: exact decision inputs cannot change
-- after the evaluator candidate binds itself to their canonical fingerprint.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000093',false
);
do $test$
declare
  v_blocked boolean := false;
begin
  perform public.seal_fit_evaluation_inputs(
    '40000000-0000-0000-0000-000000000093'
  );
  begin
    update public.fit_input_domain_states
    set explanation = 'post-seal mutation'
    where evaluation_id =
      '40000000-0000-0000-0000-000000000093'
      and availability <> 'INCLUDED';
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'Fit decision inputs are immutable after candidate input sealing' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Decision inputs remained mutable after candidate sealing';
  end if;
end;
$test$;

-- UNKNOWN is invalid when every input of its method is INCLUDED and no
-- limiting reason remains.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-00000000008a',false
);
do $test$
declare
  v_method uuid := '30000000-0000-0000-0000-000000000105';
  v_policy record;
  v_item uuid;
  v_observation uuid;
  v_completeness uuid;
  v_result uuid;
  v_blocked boolean := false;
begin
  select observation_id into v_observation
  from public.canonical_field_selections
  where record_type='PROGRAM_VERSION'
    and record_id='00000000-0000-0000-0000-000000000401'
    and field_name='duration_months';
  select completeness_id into v_completeness
  from public.student_data_completeness
  where profile_version_id='40000000-0000-0000-0000-000000000020'
    and domain='PREFERENCES';
  for v_policy in
    select * from public.fit_method_input_policies
    where method_id=v_method and disposition='ALLOWED'
      and input_domain<>'FIT_INTENTS'
  loop
    insert into public.fit_manifest_items (
      evaluation_id,profile_version_id,method_id,input_policy_id,
      item_type,authority_role
    ) values (
      '40000000-0000-0000-0000-00000000008a',
      '40000000-0000-0000-0000-000000000020',v_method,
      v_policy.input_policy_id,
      case v_policy.input_domain
        when 'STUDENT_PREFERENCES' then 'PHASE2_STUDENT_PREFERENCE'
        when 'PROGRAM_VERSIONS' then 'CATALOG_FIELD_OBSERVATION'
        when 'STUDENT_COMPLETENESS' then 'PHASE2_STUDENT_COMPLETENESS'
      end::public.fit_manifest_item_type,
      'AUTHORITATIVE'
    ) returning manifest_item_id into v_item;
    if v_policy.input_domain='STUDENT_PREFERENCES' then
      insert into public.fit_manifest_phase2_preferences values (
        v_item,'40000000-0000-0000-0000-00000000008a',
        '40000000-0000-0000-0000-000000000020',
        '40000000-0000-0000-0000-000000000041'
      );
      insert into public.fit_manifest_student_field_uses values
        (v_item,'40000000-0000-0000-0000-00000000008a','PREFERENCE_TYPE'),
        (v_item,'40000000-0000-0000-0000-00000000008a','VALUE');
    elsif v_policy.input_domain='PROGRAM_VERSIONS' then
      insert into public.fit_manifest_catalog_observations values (
        v_item,'40000000-0000-0000-0000-00000000008a',
        '40000000-0000-0000-0000-000000000020',v_observation
      );
    else
      insert into public.fit_manifest_phase2_completeness values (
        v_item,'40000000-0000-0000-0000-00000000008a',
        '40000000-0000-0000-0000-000000000020',v_completeness
      );
      insert into public.fit_manifest_student_field_uses values
        (v_item,'40000000-0000-0000-0000-00000000008a','DOMAIN'),
        (v_item,'40000000-0000-0000-0000-00000000008a','COMPLETENESS');
    end if;
    update public.fit_input_domain_states
    set availability='INCLUDED',explanation=null
    where evaluation_id='40000000-0000-0000-0000-00000000008a'
      and method_id=v_method and input_policy_id=v_policy.input_policy_id;
  end loop;
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id='40000000-0000-0000-0000-00000000008a'
    and dimension='PERSONAL_PREFERENCE';
  delete from public.fit_dimension_reasons where dimension_result_id=v_result;
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-00000000008a'
    );
  exception when others then
    -- The general structured-reason invariant is intentionally earlier than
    -- the UNKNOWN-specific guard. With all states INCLUDED, removing the only
    -- limiting reason must be rejected by one of these two executable guards.
    if sqlstate = 'P0001'
       and sqlerrm in (
         'Every result requires valid verified structured reasons',
         'UNKNOWN requires at least one normalized limiting reason family'
       ) then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Unexplained UNKNOWN with all method inputs INCLUDED finalized';
  end if;
end;
$test$;

-- Model-only high-impact international direction lacks the required paired
-- authoritative access context and current verified claim.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-00000000008b',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-00000000008b','INTERNATIONAL_ACCESSIBILITY'
);
do $test$
declare
  v_result uuid;
  v_signal uuid;
  v_intent_item uuid;
  v_program_policy uuid;
  v_program_item uuid;
  v_program_observation uuid;
  v_blocked boolean := false;
begin
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id='40000000-0000-0000-0000-00000000008b'
    and dimension='INTERNATIONAL_ACCESSIBILITY';
  select i.manifest_item_id into v_intent_item
  from public.fit_manifest_items i
  join public.fit_manifest_intent_declarations d using(manifest_item_id)
  where i.evaluation_id='40000000-0000-0000-0000-00000000008b'
    and d.intent_declaration_id='40000000-0000-0000-0000-000000000066';
  select input_policy_id into v_program_policy
  from public.fit_method_input_policies
  where method_id='30000000-0000-0000-0000-000000000106'
    and input_domain='PROGRAM_VERSIONS'
    and field_name='INTERNATIONAL_PROGRAM_FACTS';
  select observation_id into v_program_observation
  from public.canonical_field_selections
  where record_type='PROGRAM_VERSION'
    and record_id='00000000-0000-0000-0000-000000000401'
    and field_name='stem_status';
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    '40000000-0000-0000-0000-00000000008b',
    '40000000-0000-0000-0000-000000000020',
    '30000000-0000-0000-0000-000000000106',
    v_program_policy,'CATALOG_FIELD_OBSERVATION','AUTHORITATIVE'
  ) returning manifest_item_id into v_program_item;
  insert into public.fit_manifest_catalog_observations values (
    v_program_item,'40000000-0000-0000-0000-00000000008b',
    '40000000-0000-0000-0000-000000000020',
    v_program_observation
  );
  update public.fit_input_domain_states
  set availability='INCLUDED', explanation=null
  where evaluation_id='40000000-0000-0000-0000-00000000008b'
    and input_policy_id=v_program_policy;
  delete from public.fit_dimension_reasons where dimension_result_id=v_result;
  update public.fit_dimension_results
  set assessment='ALIGNMENT',evidence_coverage='SUFFICIENT'
  where dimension_result_id=v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,model_version,model_build_hash,intent_declaration_id,
    international_high_impact
  ) values (
    '40000000-0000-0000-0000-00000000008b',v_result,
    'INTERNATIONAL_ACCESSIBILITY','30000000-0000-0000-0000-000000000106',
    md5('30000000-0000-0000-0000-000000000106:MATERIAL_SUPPORT')::uuid,
    'SUPPORTING',true,'MODEL',
    'model-v1',repeat('d',64),
    '40000000-0000-0000-0000-000000000066',true
  ) returning signal_id into v_signal;
  insert into public.fit_signal_evidence values (
    v_signal,'40000000-0000-0000-0000-00000000008b',v_intent_item
  ), (
    v_signal,'40000000-0000-0000-0000-00000000008b',v_program_item
  );
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,direction,signal_id
  ) values (
    v_result,'40000000-0000-0000-0000-00000000008b',
    '30000000-0000-0000-0000-000000000203','SUPPORTING',v_signal
  );
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-00000000008b'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'High-impact international direction requires matching authoritative student access and current VERIFIED claim evidence and cannot be model-only' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Model-only high-impact international direction finalized';
  end if;
end;
$test$;

-- Deterministic Financial direction requires either a verified normalization
-- or direct-comparable authoritative catalog and intent evidence.
insert into public.field_observations (
  observation_id, record_type, record_id, field_name, observed_value,
  knowledge_status, evidence_id, notes
) values (
  '40000000-0000-0000-0000-000000000079',
  'PROGRAM_COST',
  '00000000-0000-0000-0000-000000000404',
  'tuition_amount', '60000', 'KNOWN',
  '40000000-0000-0000-0000-000000000002',
  'Test-only verified tuition fixture for financial comparability probes.'
);
select pg_temp.review_unspecified_applicability('40000000-0000-0000-0000-000000000079');
select public.select_field_observation(
  '40000000-0000-0000-0000-000000000079',
  'phase3-test-reviewer'
);
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-00000000008c',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-00000000008c','FINANCIAL'
);
do $test$
declare
  v_result uuid;
  v_signal uuid;
  v_intent_item uuid;
  v_program_item uuid;
  v_blocked boolean := false;
begin
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id='40000000-0000-0000-0000-00000000008c'
    and dimension='FINANCIAL';
  select i.manifest_item_id into v_intent_item
  from public.fit_manifest_items i
  join public.fit_manifest_intent_declarations d using(manifest_item_id)
  where i.evaluation_id='40000000-0000-0000-0000-00000000008c'
    and d.intent_declaration_id='40000000-0000-0000-0000-000000000064';
  select manifest_item_id into v_program_item
  from public.fit_manifest_items
  where evaluation_id='40000000-0000-0000-0000-00000000008c'
    and method_id='30000000-0000-0000-0000-000000000103'
    and item_type='CATALOG_FIELD_OBSERVATION';
  delete from public.fit_dimension_reasons where dimension_result_id=v_result;
  update public.fit_dimension_results
  set assessment='ALIGNMENT',inference_category='DETERMINISTIC',
      evidence_coverage='SUFFICIENT'
  where dimension_result_id=v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,intent_declaration_id,evidence_metadata
  ) values (
    '40000000-0000-0000-0000-00000000008c',v_result,'FINANCIAL',
    '30000000-0000-0000-0000-000000000103',
    md5('30000000-0000-0000-0000-000000000103:MATERIAL_SUPPORT')::uuid,
    'SUPPORTING',true,'DETERMINISTIC',
    '40000000-0000-0000-0000-000000000064','{}'
  ) returning signal_id into v_signal;
  insert into public.fit_signal_evidence values (
    v_signal,'40000000-0000-0000-0000-00000000008c',v_intent_item
  ), (
    v_signal,'40000000-0000-0000-0000-00000000008c',v_program_item
  );
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,direction,signal_id
  ) values (
    v_result,'40000000-0000-0000-0000-00000000008c',
    '30000000-0000-0000-0000-000000000203','SUPPORTING',v_signal
  );
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-00000000008c'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'Directional deterministic Financial Fit requires direct comparable facts or a VERIFIED normalization artifact' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Unsupported deterministic Financial direction finalized';
  end if;
end;
$test$;

-- Direction, coverage, confidence, and ordinary MIXED precedence are
-- independently executable finalization invariants.
create procedure pg_temp.prepare_academic_direction_probe(
  p_evaluation_id uuid,
  p_assessment public.fit_assessment,
  p_confidence public.fit_confidence,
  p_coverage public.fit_coverage,
  p_inference public.fit_inference_category,
  p_material_support boolean,
  p_add_contradiction boolean
)
language plpgsql
as $procedure$
declare
  v_result uuid;
  v_intent_item uuid;
  v_program_item uuid;
  v_support uuid;
  v_contradiction uuid;
begin
  call pg_temp.build_fit_evaluation(p_evaluation_id,false);
  call pg_temp.supply_required_inputs(p_evaluation_id,'ACADEMIC');
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id=p_evaluation_id and dimension='ACADEMIC';
  select item.manifest_item_id into v_intent_item
  from public.fit_manifest_items item
  join public.fit_manifest_intent_declarations intent
    using(manifest_item_id)
  where item.evaluation_id=p_evaluation_id
    and item.method_id='30000000-0000-0000-0000-000000000101';
  select manifest_item_id into v_program_item
  from public.fit_manifest_items
  where evaluation_id=p_evaluation_id
    and method_id='30000000-0000-0000-0000-000000000101'
    and item_type='CATALOG_FIELD_OBSERVATION';
  delete from public.fit_dimension_reasons
  where dimension_result_id=v_result;
  update public.fit_dimension_results
  set assessment=p_assessment,confidence=p_confidence,
      evidence_coverage=p_coverage
  where dimension_result_id=v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,model_version,model_build_hash,
    intent_declaration_id
  ) values (
    p_evaluation_id,v_result,'ACADEMIC',
    '30000000-0000-0000-0000-000000000101',
    md5(
      '30000000-0000-0000-0000-000000000101:'
      || case when p_material_support
        then 'MATERIAL_SUPPORT' else 'NON_MATERIAL_SUPPORT' end
    )::uuid,
    'SUPPORTING',p_material_support,p_inference,
    case when p_inference='MODEL' then 'model-v1' end,
    case when p_inference='MODEL' then repeat('e',64) end,
    '40000000-0000-0000-0000-000000000061'
  ) returning signal_id into v_support;
  insert into public.fit_signal_evidence values
    (v_support,p_evaluation_id,v_intent_item),
    (v_support,p_evaluation_id,v_program_item);
  if p_add_contradiction then
    insert into public.fit_signals (
      evaluation_id,dimension_result_id,dimension,method_id,
      signal_type_id,direction,material,inference_category,
      intent_declaration_id
    ) values (
      p_evaluation_id,v_result,'ACADEMIC',
      '30000000-0000-0000-0000-000000000101',
      md5(
        '30000000-0000-0000-0000-000000000101:MATERIAL_CONTRADICTION'
      )::uuid,
      'CONTRADICTING',true,p_inference,
      '40000000-0000-0000-0000-000000000061'
    ) returning signal_id into v_contradiction;
    insert into public.fit_signal_evidence values
      (v_contradiction,p_evaluation_id,v_intent_item),
      (v_contradiction,p_evaluation_id,v_program_item);
    insert into public.fit_dimension_reasons (
      dimension_result_id,evaluation_id,reason_definition_id,
      direction,signal_id
    ) values (
      v_result,p_evaluation_id,
      '30000000-0000-0000-0000-000000000204',
      'CONTRADICTING',v_contradiction
    );
  else
    insert into public.fit_dimension_reasons (
      dimension_result_id,evaluation_id,reason_definition_id,
      direction,signal_id
    ) values (
      v_result,p_evaluation_id,
      '30000000-0000-0000-0000-000000000203',
      'SUPPORTING',v_support
    );
  end if;
end;
$procedure$;

call pg_temp.prepare_academic_direction_probe(
  '40000000-0000-0000-0000-000000000097',
  'ALIGNMENT','MEDIUM','SUFFICIENT','RULE',false,false
);
call pg_temp.prepare_academic_direction_probe(
  '40000000-0000-0000-0000-000000000098',
  'ALIGNMENT','MEDIUM','INSUFFICIENT','RULE',true,false
);
call pg_temp.prepare_academic_direction_probe(
  '40000000-0000-0000-0000-00000000009a',
  'ALIGNMENT','HIGH','SUFFICIENT','MODEL',true,false
);
call pg_temp.prepare_academic_direction_probe(
  '40000000-0000-0000-0000-00000000009b',
  'MISALIGNMENT','MEDIUM','SUFFICIENT','RULE',true,true
);
do $test$
declare
  v_blocked boolean;
begin
  v_blocked := false;
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-000000000097'
    );
  exception when others then
    if sqlstate='P0001'
       and sqlerrm =
         'ALIGNMENT requires material support and no material contradiction' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'ALIGNMENT without material support finalized';
  end if;

  v_blocked := false;
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-000000000098'
    );
  exception when others then
    if sqlstate='P0001'
       and sqlerrm =
         'INSUFFICIENT evidence coverage permits only UNKNOWN' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'INSUFFICIENT coverage produced directional Fit';
  end if;

  v_blocked := false;
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-00000000009a'
    );
  exception when others then
    if sqlstate='P0001'
       and sqlerrm =
         'Model-only directional evidence cannot receive HIGH confidence' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Model-only directional evidence received HIGH confidence';
  end if;

  v_blocked := false;
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-00000000009b'
    );
  exception when others then
    if sqlstate='P0001'
       and sqlerrm =
         'Ordinary material support and contradiction require MIXED, not MISALIGNMENT' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Ordinary support and contradiction finalized as MISALIGNMENT';
  end if;
end;
$test$;

-- VERIFIED mapping workflow status cannot exceed the relation-specific
-- assessment authority.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-00000000009c',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-00000000009c','CAREER'
);
do $test$
declare
  v_result uuid;
  v_signal uuid;
  v_intent_item uuid;
  v_mapping_item uuid;
  v_taxonomy_policy uuid;
  v_taxonomy_item uuid;
  v_blocked boolean := false;
begin
  select dimension_result_id into v_result
  from public.fit_dimension_results
  where evaluation_id='40000000-0000-0000-0000-00000000009c'
    and dimension='CAREER';
  select item.manifest_item_id into v_intent_item
  from public.fit_manifest_items item
  join public.fit_manifest_intent_declarations intent
    using(manifest_item_id)
  where item.evaluation_id='40000000-0000-0000-0000-00000000009c'
    and intent.intent_declaration_id =
      '40000000-0000-0000-0000-000000000063';
  select manifest_item_id into v_mapping_item
  from public.fit_manifest_items
  where evaluation_id='40000000-0000-0000-0000-00000000009c'
    and item_type='CATALOG_MAPPING';
  select input_policy_id into v_taxonomy_policy
  from public.fit_method_input_policies
  where method_id='30000000-0000-0000-0000-000000000102'
    and input_domain='TAXONOMY_CONCEPTS'
    and disposition='ALLOWED';
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,
    item_type,authority_role
  ) values (
    '40000000-0000-0000-0000-00000000009c',
    '40000000-0000-0000-0000-000000000020',
    '30000000-0000-0000-0000-000000000102',
    v_taxonomy_policy,'TAXONOMY_CONCEPT','LIMITING_CONTEXT'
  ) returning manifest_item_id into v_taxonomy_item;
  insert into public.fit_manifest_taxonomy_concepts values (
    v_taxonomy_item,
    '40000000-0000-0000-0000-00000000009c',
    '40000000-0000-0000-0000-000000000020',
    '10000000-0000-0000-0000-000000000052'
  );
  update public.fit_input_domain_states
  set availability='INCLUDED',explanation=null
  where evaluation_id='40000000-0000-0000-0000-00000000009c'
    and input_policy_id=v_taxonomy_policy;
  delete from public.fit_dimension_reasons
  where dimension_result_id=v_result;
  update public.fit_dimension_results
  set assessment='STRONG_ALIGNMENT',confidence='MEDIUM',
      evidence_coverage='SUFFICIENT'
  where dimension_result_id=v_result;
  insert into public.fit_signals (
    evaluation_id,dimension_result_id,dimension,method_id,signal_type_id,
    direction,material,inference_category,intent_declaration_id
  ) values (
    '40000000-0000-0000-0000-00000000009c',v_result,'CAREER',
    '30000000-0000-0000-0000-000000000102',
    md5(
      '30000000-0000-0000-0000-000000000102:MATERIAL_SUPPORT'
    )::uuid,
    'SUPPORTING',true,'REVIEWED_MAPPING',
    '40000000-0000-0000-0000-000000000063'
  ) returning signal_id into v_signal;
  insert into public.fit_signal_evidence values
    (v_signal,'40000000-0000-0000-0000-00000000009c',v_intent_item),
    (v_signal,'40000000-0000-0000-0000-00000000009c',v_mapping_item);
  insert into public.fit_dimension_reasons (
    dimension_result_id,evaluation_id,reason_definition_id,
    direction,signal_id
  ) values (
    v_result,'40000000-0000-0000-0000-00000000009c',
    '30000000-0000-0000-0000-000000000203',
    'SUPPORTING',v_signal
  );
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-00000000009c'
    );
  exception when others then
    if sqlstate='42501'
       and sqlerrm =
         'Mapping relation policy does not authorize this result assessment' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Weak VERIFIED relation supported STRONG_ALIGNMENT';
  end if;
end;
$test$;

-- Eligibility context is display-only: a missing evaluation cannot be
-- attached, and a FORBIDDEN prestige/derived-feature policy cannot become a
-- decision-manifest input.
do $test$
declare
  v_blocked boolean := false;
  v_policy uuid;
  v_item uuid;
begin
  begin
    insert into public.fit_evaluations (
      evaluation_id,profile_version_id,profile_snapshot_hash,intent_set_id,
      intent_snapshot_hash,program_version_id,taxonomy_release_code,
      contract_release_id,evaluator_build_id,evaluator_name,evaluator_version,
      evaluator_build_hash,
      eligibility_context_evaluation_id
    ) select
      '40000000-0000-0000-0000-00000000008d',
      '40000000-0000-0000-0000-000000000020',
      (select snapshot_hash from public.student_profile_versions
        where profile_version_id = '40000000-0000-0000-0000-000000000020'),
      intent_set_id,snapshot_hash,'00000000-0000-0000-0000-000000000401',
      'v0.1','30000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000003',
      'phase3-fit-test','0.1.0',repeat('b',64),
      '40000000-0000-0000-0000-000000000099'
    from public.fit_intent_sets
    where intent_set_id='40000000-0000-0000-0000-000000000050';
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'Eligibility context must be completed for the same profile and program version' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'Fit evaluation accepted a non-existent eligibility context';
  end if;

  select input_policy_id into v_policy
  from public.fit_method_input_policies
  where method_id='30000000-0000-0000-0000-000000000101'
    and input_domain='EXTERNAL_METRICS'
    and field_name='PRESTIGE'
    and disposition='FORBIDDEN';
  if v_policy is null then
    raise exception 'Prestige is not forbidden on Academic Alignment';
  end if;
  insert into public.fit_manifest_items (
    evaluation_id,profile_version_id,method_id,input_policy_id,item_type,authority_role
  ) values (
    '40000000-0000-0000-0000-000000000085',
    '40000000-0000-0000-0000-000000000020',
    '30000000-0000-0000-0000-000000000101',v_policy,
    'TAXONOMY_CONCEPT','AUTHORITATIVE'
  ) returning manifest_item_id into v_item;
  insert into public.fit_manifest_taxonomy_concepts values (
    v_item,'40000000-0000-0000-0000-000000000085',
    '40000000-0000-0000-0000-000000000020',
    '10000000-0000-0000-0000-000000000021'
  );
  v_blocked := false;
  begin
    perform pg_temp.complete_fit_evaluation(
      '40000000-0000-0000-0000-000000000085'
    );
  exception when others then
    if sqlstate = 'P0001'
       and sqlerrm =
         'Manifest items and input states require an ALLOWED policy of a VERIFIED evaluation method' then
      v_blocked := true;
    else
      raise;
    end if;
  end;
  if not v_blocked then
    raise exception 'FORBIDDEN prestige policy was accepted as a Fit decision input';
  end if;
end;
$test$;

-- Composite ownership prevents a manifest from importing another profile's
-- completeness source.
do $test$
declare
  v_item uuid;
  v_policy uuid;
  v_other_completeness uuid;
  v_blocked boolean := false;
begin
  select input_policy_id into v_policy
  from public.fit_method_input_policies
  where method_id='30000000-0000-0000-0000-000000000101'
    and input_domain='STUDENT_COMPLETENESS';
  select completeness_id into v_other_completeness
  from public.student_data_completeness
  where profile_version_id='40000000-0000-0000-0000-000000000021'
  limit 1;
  begin
    insert into public.fit_manifest_items (
      evaluation_id,profile_version_id,method_id,input_policy_id,
      item_type,authority_role
    ) values (
      '40000000-0000-0000-0000-000000000085',
      '40000000-0000-0000-0000-000000000020',
      '30000000-0000-0000-0000-000000000101',v_policy,
      'PHASE2_STUDENT_COMPLETENESS','LIMITING_CONTEXT'
    ) returning manifest_item_id into v_item;
    insert into public.fit_manifest_phase2_completeness values (
      v_item,'40000000-0000-0000-0000-000000000085',
      '40000000-0000-0000-0000-000000000020',v_other_completeness
    );
  exception when foreign_key_violation then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Cross-profile manifest source injection succeeded';
  end if;
end;
$test$;

-- Context selections are historical inputs. A later reviewed selection must
-- not rewrite a completed International Accessibility evaluation.
call pg_temp.build_fit_evaluation(
  '40000000-0000-0000-0000-000000000094',false
);
call pg_temp.supply_required_inputs(
  '40000000-0000-0000-0000-000000000094',
  'INTERNATIONAL_ACCESSIBILITY'
);
do $test$
declare
  v_before text;
  v_recomputed text;
  v_old_selection uuid;
  v_new_selection uuid;
begin
  perform pg_temp.complete_fit_evaluation(
    '40000000-0000-0000-0000-000000000094'
  );
  select decision_input_fingerprint into v_before
  from public.fit_evaluations
  where evaluation_id =
    '40000000-0000-0000-0000-000000000094';
  select context_selection_id into v_old_selection
  from public.fit_manifest_context_claim_selections
  where evaluation_id =
    '40000000-0000-0000-0000-000000000094';

  perform public.select_fit_context_claim_observation(
    '40000000-0000-0000-0000-000000000071',
    '40000000-0000-0000-0000-000000000072',
    'KNOWN', 'later-reviewer'
  );
  select context_selection_id into v_new_selection
  from public.fit_context_claim_selections
  where context_claim_id =
    '40000000-0000-0000-0000-000000000071';
  v_recomputed := public.compute_fit_decision_input_fingerprint(
    '40000000-0000-0000-0000-000000000094'
  );
  if v_old_selection = v_new_selection
     or v_recomputed <> v_before
     or not exists (
       select 1 from public.fit_context_claim_selection_history
       where context_selection_id = v_old_selection
         and knowledge_status = 'SOURCE_CONFLICT'
     ) then
    raise exception 'Later context selection rewrote historical Fit decision inputs';
  end if;
end;
$test$;

-- RLS and privacy lifecycle: private Fit artifacts disappear, public context stays.
do $test$
declare
  v_actual integer;
  v_expected integer;
  v_expected_intents integer;
  v_public_before integer;
  v_blocked boolean;
  v_table text;
  v_survivors bigint;
begin
  select count(*) into v_actual
  from pg_class
  where relnamespace in ('public'::regnamespace,'private'::regnamespace)
    and relname like 'fit_%'
    and relkind='r'
    and not relrowsecurity;
  if v_actual <> 0 then
    raise exception '% Phase 3 Fit tables are missing RLS', v_actual;
  end if;
  if has_function_privilege(
       'authenticated',
       'public.start_fit_evaluation(uuid,uuid,uuid,text,uuid,uuid,uuid,uuid)',
       'EXECUTE'
     )
     or has_function_privilege(
       'authenticated',
       'public.finalize_fit_evaluation(uuid)',
       'EXECUTE'
     )
     or has_table_privilege(
       'authenticated', 'public.fit_dimension_results', 'INSERT'
     ) then
    raise exception 'Authenticated students can fabricate Fit execution or output';
  end if;

  execute 'grant select on public.fit_evaluations, public.fit_intent_sets to authenticated';
  select count(*) into v_expected from public.fit_evaluations
  where profile_version_id='40000000-0000-0000-0000-000000000020';
  select count(*) into v_expected_intents from public.fit_intent_sets
  where profile_version_id='40000000-0000-0000-0000-000000000020';
  perform set_config(
    'request.jwt.claim.sub','40000000-0000-0000-0000-000000000091',true
  );
  execute 'set local role authenticated';
  select count(*) into v_actual from public.fit_evaluations;
  if v_actual <> 0 then
    raise exception 'RLS exposed Fit evaluations to an unrelated student';
  end if;
  select count(*) into v_actual from public.fit_intent_sets;
  if v_actual <> 0 then
    raise exception 'RLS exposed Fit intents to an unrelated student';
  end if;
  execute 'reset role';

  perform set_config(
    'request.jwt.claim.sub','40000000-0000-0000-0000-000000000090',true
  );
  execute 'set local role authenticated';
  select count(*) into v_actual from public.fit_evaluations;
  if v_actual <> v_expected then
    raise exception 'RLS denied the owner access to completed/building Fit history';
  end if;
  select count(*) into v_actual from public.fit_intent_sets;
  if v_actual <> v_expected_intents then
    raise exception 'RLS denied the owner access to authorized Fit intents';
  end if;
  execute 'reset role';

  v_blocked := false;
  begin
    execute $sql$
      insert into public.fit_manifest_student_field_uses
      values (
        extensions.gen_random_uuid(),
        '40000000-0000-0000-0000-000000000085',
        'GPA'
      )
    $sql$;
  exception when invalid_text_representation then v_blocked := true;
  end;
  if not v_blocked then
    raise exception 'Hard student field allowlist accepted GPA';
  end if;

  select count(*) into v_public_before from public.fit_context_claims;
  perform public.delete_student_data(
    '40000000-0000-0000-0000-000000000010',
    'Phase 3 Fit privacy lifecycle test'
  );
  if exists (
    select 1 from public.fit_evaluations
    where profile_version_id='40000000-0000-0000-0000-000000000020'
  ) or exists (
    select 1 from public.fit_intent_sets
    where profile_version_id='40000000-0000-0000-0000-000000000020'
  ) then
    raise exception 'Privacy deletion retained replayable Fit artifacts';
  end if;
  foreach v_table in array array[
    'fit_intent_declarations',
    'fit_intent_validation_issues',
    'fit_intent_taxonomy_targets',
    'fit_intent_location_constraints',
    'fit_intent_delivery_constraints',
    'fit_intent_financial_constraints',
    'fit_intent_duration_constraints',
    'fit_intent_program_feature_constraints',
    'fit_evaluation_methods',
    'fit_manifest_items',
    'fit_manifest_intent_declarations',
    'fit_manifest_student_access_contexts',
    'fit_manifest_phase2_goals',
    'fit_manifest_phase2_preferences',
    'fit_manifest_phase2_courses',
    'fit_manifest_phase2_completeness',
    'fit_manifest_phase2_mappings',
    'fit_manifest_catalog_observations',
    'fit_manifest_catalog_mappings',
    'fit_manifest_taxonomy_concepts',
    'fit_manifest_context_claim_selections',
    'fit_manifest_context_mappings',
    'fit_manifest_student_field_uses',
    'fit_financial_normalizations',
    'fit_manifest_financial_normalizations',
    'fit_input_domain_states',
    'fit_dimension_results',
    'fit_signals',
    'fit_signal_evidence',
    'fit_dimension_reasons'
  ]
  loop
    execute format('select count(*) from public.%I',v_table)
    into v_survivors;
    if v_survivors <> 0 then
      raise exception 'Privacy deletion retained % rows in %',
        v_survivors,v_table;
    end if;
  end loop;
  select count(*) into v_survivors
  from private.fit_evaluation_assembly_authorizations;
  if v_survivors <> 0 then
    raise exception 'Privacy deletion retained scoped assembly authorization';
  end if;
  if (select count(*) from public.fit_context_claims) <> v_public_before then
    raise exception 'Student privacy deletion removed public context history';
  end if;
  if exists (
    select 1 from private.fit_student_access_contexts
    where profile_version_id =
      '40000000-0000-0000-0000-000000000020'
  ) or exists (
    select 1 from public.audit_events
    where table_name like 'fit_%'
      and (
        coalesce(old_row::text, '') like
          '%40000000-0000-0000-0000-000000000010%'
        or coalesce(new_row::text, '') like
          '%40000000-0000-0000-0000-000000000010%'
        or coalesce(old_row::text, '') like
          '%40000000-0000-0000-0000-000000000020%'
        or coalesce(new_row::text, '') like
          '%40000000-0000-0000-0000-000000000020%'
      )
  ) then
    raise exception 'Student-linked Fit data survived in private context or global audit payloads';
  end if;
  if not exists (
    select 1 from public.student_deletion_tombstones
    where reason_code = 'TEST_LIFECYCLE'
      and legacy_deletion_reason = 'MIGRATED_TO_REASON_CODE'
  ) then
    raise exception 'Phase 3 privacy deletion did not leave a non-PII tombstone';
  end if;
end;
$test$;

rollback;
