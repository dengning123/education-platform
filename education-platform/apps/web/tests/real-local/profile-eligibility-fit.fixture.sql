-- LOCAL TEST ONLY. Never loaded by migrations, application source, seed, or production bundles.
-- Evidence classification: GOLDEN PROGRAM RECORD + SYNTHETIC ELIGIBILITY RULES (MIXED).
-- The NYU MSQE Program/source rows are the existing golden record. Only the Eligibility rule below is synthetic.

\set ON_ERROR_STOP on

begin;
set local search_path = public, private, extensions, pg_catalog;

select
  p.program_version_id,
  c.course_id,
  s.observation_id as prior_observation_id,
  o.evidence_id as catalog_evidence_id
from public.program_versions p
join public.program_courses c on c.program_version_id = p.program_version_id and c.retired_at is null
join public.canonical_field_selections s
  on s.record_type = 'PROGRAM_COURSE' and s.record_id = c.course_id and s.field_name = 'course_name'
join public.field_observations o on o.observation_id = s.observation_id
where p.program_id = '00000000-0000-0000-0000-000000000301'
order by c.created_at
limit 1
\gset fixture_

select public.create_evidence_scope(
  :'fixture_catalog_evidence_id'::uuid,
  'PROGRAM_COURSE',
  :'fixture_course_id'::uuid,
  'course_name',
  'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
) as scope_id
\gset applicability_

select public.review_evidence_applicability(
  :'applicability_scope_id'::uuid,
  'REVIEWED_APPLICABLE',
  'phase4b-local-e2e-reviewer',
  'GOLDEN PROGRAM RECORD + SYNTHETIC ELIGIBILITY RULES'
) as assertion_id
\gset applicability_

select public.create_field_observation(
  'PROGRAM_COURSE',
  :'fixture_course_id'::uuid,
  'course_name',
  (select observed_value from public.field_observations where observation_id = :'fixture_prior_observation_id'::uuid),
  'KNOWN',
  :'fixture_catalog_evidence_id'::uuid,
  :'fixture_prior_observation_id'::uuid,
  'Phase 4B local-only headed observation for a synthetic Eligibility rule.',
  :'applicability_assertion_id'::uuid
) as observation_id
\gset fixture_

select public.select_field_observation(:'fixture_observation_id'::uuid, 'phase4b-local-e2e-reviewer');

select public.create_requirement_rule_set(jsonb_populate_record(
  null::public.program_requirement_rule_sets,
  jsonb_build_object(
    'rule_set_id', '4b400000-0000-4000-8000-000000000001'::uuid,
    'program_version_id', :'fixture_program_version_id'::uuid,
    'rule_set_version', 9401,
    'taxonomy_release_code', 'v0.1',
    'rule_schema_version', 'phase2-v0.2',
    'engine_contract_version', 'eligibility-v0.2'
  )
));

select public.insert_requirement_node(jsonb_populate_record(
  null::public.program_requirement_nodes,
  jsonb_build_object(
    'rule_node_id', '4b400000-0000-4000-8000-000000000002'::uuid,
    'rule_set_id', '4b400000-0000-4000-8000-000000000001'::uuid,
    'sort_order', 0,
    'node_kind', 'PREDICATE',
    'predicate_kind', 'HAS_TEST',
    'requirement_strength', 'HARD',
    'requirement_semantics', 'ORDINARY',
    'target_concept_id', '10000000-0000-0000-0000-000000000071'::uuid,
    'explanation_template', 'The synthetic local rule requires GRE evidence.'
  )
));

select public.insert_requirement_node_source(jsonb_populate_record(
  null::public.program_requirement_node_sources,
  jsonb_build_object(
    'rule_node_id', '4b400000-0000-4000-8000-000000000002'::uuid,
    'field_observation_id', :'fixture_observation_id'::uuid
  )
));

select public.verify_program_requirement_rule_set(
  '4b400000-0000-4000-8000-000000000001'::uuid,
  'phase4b-local-e2e-reviewer',
  :'fixture_catalog_evidence_id'::uuid
);

commit;

select jsonb_build_object(
  'classification', 'GOLDEN PROGRAM RECORD + SYNTHETIC ELIGIBILITY RULES',
  'profileVersionId', :'profile_version_id'::uuid,
  'programVersionId', :'fixture_program_version_id'::uuid,
  'ruleSetId', '4b400000-0000-4000-8000-000000000001'::uuid
);
