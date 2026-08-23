-- Disposable populated fixture. Run after Migration 021 and before 022.

begin;

insert into auth.users (id, email) values
  ('96100000-0000-4000-8000-000000000001', 'phase022-upgrade@test.invalid');

select public.create_student('96100000-0000-4000-8000-000000000011');

insert into private.student_identities (auth_user_id, student_id) values (
  '96100000-0000-4000-8000-000000000001',
  '96100000-0000-4000-8000-000000000011'
);

insert into public.student_profile_versions (
  profile_version_id, student_id, version_number, status,
  product_managed, profile_revision
) values (
  '96100000-0000-4000-8000-000000000021',
  '96100000-0000-4000-8000-000000000011',
  1, 'DRAFT', true, 3
);

insert into public.student_evidence_items (
  student_evidence_id, profile_version_id, evidence_type, locator
) values (
  '96100000-0000-4000-8000-000000000031',
  '96100000-0000-4000-8000-000000000021',
  'SELF_REPORT', 'phase022-populated-upgrade'
);

insert into public.student_degrees (
  student_degree_id, profile_version_id, institution_name, degree_name,
  degree_level, degree_status, student_evidence_id
) values (
  '96100000-0000-4000-8000-000000000041',
  '96100000-0000-4000-8000-000000000021',
  'Populated University', 'BSc Economics', 'BACHELORS', 'COMPLETED',
  '96100000-0000-4000-8000-000000000031'
);

insert into public.student_record_concept_mappings (
  student_mapping_id, profile_version_id, record_type, student_record_id,
  concept_id, mapping_status, method
)
select
  '96100000-0000-4000-8000-000000000051',
  '96100000-0000-4000-8000-000000000021',
  'DEGREE',
  '96100000-0000-4000-8000-000000000041',
  concept.concept_id,
  'PROPOSED',
  'HUMAN'
from public.taxonomy_concepts concept
where concept.concept_kind in ('FIELD', 'SUBFIELD')
  and concept.retired_release_ordinal is null
order by concept.canonical_key, concept.concept_id
limit 1;

commit;
