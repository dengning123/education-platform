-- Disposable populated fixture. Run after Migration 023 and before 024.

begin;

create table private.phase024_populated_upgrade_expected (
  profile_version_id uuid primary key,
  profile_document_hash text not null
);

insert into auth.users (id, email) values
  ('96410000-0000-4000-8000-000000000001',
   'phase024-upgrade@test.invalid');

select public.create_student(
  '96410000-0000-4000-8000-000000000011'
);

insert into private.student_identities (auth_user_id, student_id) values (
  '96410000-0000-4000-8000-000000000001',
  '96410000-0000-4000-8000-000000000011'
);

insert into public.student_profile_versions (
  profile_version_id, student_id, version_number,
  product_managed, profile_revision
) values (
  '96410000-0000-4000-8000-000000000021',
  '96410000-0000-4000-8000-000000000011', 1, true, 0
);

insert into public.student_evidence_items (
  student_evidence_id, profile_version_id, evidence_type, metadata
) values (
  '96410000-0000-4000-8000-000000000031',
  '96410000-0000-4000-8000-000000000021', 'SELF_REPORT', '{}'::jsonb
);

insert into public.student_test_scores (
  student_test_score_id, profile_version_id, assessment_concept_id,
  test_date, total_score, section_scores, student_evidence_id
)
select '96410000-0000-4000-8000-000000000041',
  '96410000-0000-4000-8000-000000000021', concept.concept_id,
  '2025-01-01', 330, jsonb_build_object('quantitative', 170),
  '96410000-0000-4000-8000-000000000031'
from public.taxonomy_concepts concept
where concept.canonical_key = 'ASSESSMENT.GRE';

insert into public.student_skills (
  student_skill_id, profile_version_id, skill_concept_id,
  proficiency_level, years_experience, student_evidence_id
)
select '96410000-0000-4000-8000-000000000051',
  '96410000-0000-4000-8000-000000000021', concept.concept_id,
  4, 2, '96410000-0000-4000-8000-000000000031'
from public.taxonomy_concepts concept
where concept.canonical_key = 'SKILL.PYTHON';

do $capture$
declare
  v_document jsonb;
begin
  perform set_config(
    'request.jwt.claim.sub',
    '96410000-0000-4000-8000-000000000001', true
  );
  execute 'set local role authenticated';
  v_document := public.get_profile_document_v019(
    '96410000-0000-4000-8000-000000000021'
  );
  execute 'reset role';
  insert into private.phase024_populated_upgrade_expected values (
    '96410000-0000-4000-8000-000000000021',
    encode(extensions.digest(
      convert_to(v_document::text, 'UTF8'), 'sha256'
    ), 'hex')
  );
end;
$capture$;

commit;
