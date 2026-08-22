-- Local-only committed fixture for the Phase 016 Edge/API integration test.
-- The caller must pass -v auth_user_id=<uuid> for a local Auth user.

begin;

set local search_path = public, private, extensions, pg_catalog;

insert into public.students (student_id)
values ('61600000-0000-0000-0000-000000000001');

insert into private.student_identities (auth_user_id, student_id)
values (
  :'auth_user_id'::uuid,
  '61600000-0000-0000-0000-000000000001'
);

insert into public.student_profile_versions (
  profile_version_id, student_id, version_number
) values (
  '61600000-0000-0000-0000-000000000002',
  '61600000-0000-0000-0000-000000000001',
  1
);

insert into public.student_evidence_items (
  student_evidence_id, profile_version_id, evidence_type, content_hash
) values (
  '61600000-0000-0000-0000-000000000003',
  '61600000-0000-0000-0000-000000000002',
  'SELF_REPORT',
  repeat('6', 64)
);

insert into public.student_preferences (
  student_preference_id, profile_version_id, preference_type, value, priority
) values (
  '61600000-0000-0000-0000-000000000004',
  '61600000-0000-0000-0000-000000000002',
  'BUDGET',
  '{"amount":90000,"currency":"USD","period":"PROGRAM_DURATION","scope":"TOTAL_COST","basis":"GROSS","components":["TOTAL_COST"]}',
  5
);

insert into public.student_data_completeness (
  profile_version_id, domain, completeness, explanation
)
select
  '61600000-0000-0000-0000-000000000002',
  domain,
  'UNKNOWN',
  'No profile evidence was selected for the all-UNKNOWN API fixture.'
from unnest(enum_range(null::public.student_data_domain)) value(domain);

select public.freeze_student_profile_version(
  '61600000-0000-0000-0000-000000000002'
);

insert into public.fit_intent_sets (
  intent_set_id, profile_version_id, version_number
) values (
  '61600000-0000-0000-0000-000000000010',
  '61600000-0000-0000-0000-000000000002',
  1
);

insert into public.fit_intent_declarations (
  intent_declaration_id, intent_set_id, profile_version_id, origin,
  dimension, semantic_type, importance, importance_basis,
  interpretation_method, interpretation_method_version,
  interpretation_provenance, student_evidence_id,
  source_student_preference_id
) values
  ('61600000-0000-0000-0000-000000000021','61600000-0000-0000-0000-000000000010','61600000-0000-0000-0000-000000000002','PHASE3_DECLARATION','ACADEMIC','TAXONOMY_TARGET','PREFERRED','STRUCTURED_STUDENT_DECLARATION','HUMAN','1','Local Phase 016 API fixture.','61600000-0000-0000-0000-000000000003',null),
  ('61600000-0000-0000-0000-000000000022','61600000-0000-0000-0000-000000000010','61600000-0000-0000-0000-000000000002','PHASE3_DECLARATION','CAREER','TAXONOMY_TARGET','PREFERRED','STRUCTURED_STUDENT_DECLARATION','HUMAN','1','Local Phase 016 API fixture.','61600000-0000-0000-0000-000000000003',null),
  ('61600000-0000-0000-0000-000000000023','61600000-0000-0000-0000-000000000010','61600000-0000-0000-0000-000000000002','PHASE2_INTERPRETATION','FINANCIAL','FINANCIAL_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION','HUMAN','1','Local Phase 016 API fixture.',null,'61600000-0000-0000-0000-000000000004'),
  ('61600000-0000-0000-0000-000000000024','61600000-0000-0000-0000-000000000010','61600000-0000-0000-0000-000000000002','PHASE3_DECLARATION','GEOGRAPHIC_DELIVERY','DELIVERY_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION','HUMAN','1','Local Phase 016 API fixture.','61600000-0000-0000-0000-000000000003',null),
  ('61600000-0000-0000-0000-000000000025','61600000-0000-0000-0000-000000000010','61600000-0000-0000-0000-000000000002','PHASE3_DECLARATION','PERSONAL_PREFERENCE','DURATION_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION','HUMAN','1','Local Phase 016 API fixture.','61600000-0000-0000-0000-000000000003',null),
  ('61600000-0000-0000-0000-000000000026','61600000-0000-0000-0000-000000000010','61600000-0000-0000-0000-000000000002','PHASE3_DECLARATION','INTERNATIONAL_ACCESSIBILITY','PROGRAM_FEATURE_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION','HUMAN','1','Local Phase 016 API fixture.','61600000-0000-0000-0000-000000000003',null),
  ('61600000-0000-0000-0000-000000000027','61600000-0000-0000-0000-000000000010','61600000-0000-0000-0000-000000000002','PHASE3_DECLARATION','FINANCIAL','FINANCIAL_CONSTRAINT','PREFERRED','STRUCTURED_STUDENT_DECLARATION','HUMAN','1','Local Phase 017 funding fixture.','61600000-0000-0000-0000-000000000003',null);

insert into public.fit_intent_taxonomy_targets values
  ('61600000-0000-0000-0000-000000000021','61600000-0000-0000-0000-000000000010','61600000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000021','DESIRED'),
  ('61600000-0000-0000-0000-000000000022','61600000-0000-0000-0000-000000000010','61600000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000052','DESIRED');

insert into public.fit_intent_financial_constraints values (
  '61600000-0000-0000-0000-000000000023',
  '61600000-0000-0000-0000-000000000010',
  '61600000-0000-0000-0000-000000000002',
  90000, 'PREFERRED_TOTAL_COST', 'USD', 'TOTAL_COST',
  'PROGRAM_DURATION', :'financial_basis'::public.fit_financial_basis, array['TOTAL_COST']
);

insert into public.fit_intent_financial_constraints values (
  '61600000-0000-0000-0000-000000000027',
  '61600000-0000-0000-0000-000000000010',
  '61600000-0000-0000-0000-000000000002',
  15000, 'AVAILABLE_FUNDING', 'USD', 'TOTAL_COST',
  'PROGRAM_DURATION', 'GROSS', array['TOTAL_COST']
);

insert into public.fit_intent_delivery_constraints values (
  '61600000-0000-0000-0000-000000000024',
  '61600000-0000-0000-0000-000000000010',
  '61600000-0000-0000-0000-000000000002',
  'ONLINE', 'DESIRED'
);

insert into public.fit_intent_duration_constraints values (
  '61600000-0000-0000-0000-000000000025',
  '61600000-0000-0000-0000-000000000010',
  '61600000-0000-0000-0000-000000000002',
  6, 24
);

insert into public.fit_intent_program_feature_constraints values (
  '61600000-0000-0000-0000-000000000026',
  '61600000-0000-0000-0000-000000000010',
  '61600000-0000-0000-0000-000000000002',
  'INTERNATIONAL_PATH_SUPPORT', true
);

select public.freeze_fit_intent_set(
  '61600000-0000-0000-0000-000000000010'
);

commit;
