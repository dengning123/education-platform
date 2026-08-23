\set ON_ERROR_STOP on

-- Run after Migration 018 and before Migration 019 on a disposable database.
-- Commits one historical, non-product DRAFT to verify additive upgrade shape.

begin;
insert into auth.users (id, email) values (
  '94000000-0000-0000-0000-000000000001',
  'phase019-upgrade@test.invalid'
);
select public.create_student('94000000-0000-0000-0000-000000000002');
insert into private.student_identities (auth_user_id, student_id) values (
  '94000000-0000-0000-0000-000000000001',
  '94000000-0000-0000-0000-000000000002'
);
select public.create_student_profile_version(
  '94000000-0000-0000-0000-000000000002', 1
);
commit;
