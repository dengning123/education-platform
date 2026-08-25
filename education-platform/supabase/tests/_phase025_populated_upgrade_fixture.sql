-- Disposable populated fixture. Run after Migration 024 and before 025.

begin;

create table private.phase025_populated_upgrade_expected (
  student_id uuid primary key,
  profile_rows_hash text not null,
  operation_count bigint not null
);

insert into auth.users (id, email) values (
  '96520000-0000-4000-8000-000000000001',
  'phase025-upgrade@test.invalid'
);
select public.create_student('96520000-0000-4000-8000-000000000011');
insert into private.student_identities (auth_user_id, student_id) values (
  '96520000-0000-4000-8000-000000000001',
  '96520000-0000-4000-8000-000000000011'
);

insert into public.student_profile_versions (
  profile_version_id, student_id, version_number, status, snapshot_hash,
  frozen_at, product_managed, profile_revision
) values
  ('96520000-0000-4000-8000-000000000021',
   '96520000-0000-4000-8000-000000000011', 1, 'FROZEN', repeat('d', 64),
   '2026-08-20T00:00:00Z', true, 2),
  ('96520000-0000-4000-8000-000000000022',
   '96520000-0000-4000-8000-000000000011', 2, 'FROZEN', repeat('e', 64),
   '2026-08-21T00:00:00Z', true, 5);

insert into private.phase025_populated_upgrade_expected
select student.student_id,
  encode(extensions.digest(convert_to(coalesce(jsonb_agg(
    to_jsonb(profile) order by profile.version_number
  )::text, '[]'), 'UTF8'), 'sha256'), 'hex'),
  (select count(*) from private.profile_capability_operations_v019 operation
   where operation.student_id = student.student_id)
from public.students student
join public.student_profile_versions profile using (student_id)
where student.student_id = '96520000-0000-4000-8000-000000000011'
group by student.student_id;

commit;
