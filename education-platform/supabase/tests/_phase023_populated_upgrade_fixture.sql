-- Disposable populated fixture. Run after Migration 022 and before 023.

begin;

insert into auth.users (id, email) values
  ('96300000-0000-4000-8000-000000000001',
   'phase023-upgrade@test.invalid');

select public.create_student(
  '96300000-0000-4000-8000-000000000011'
);

insert into private.student_identities (auth_user_id, student_id) values (
  '96300000-0000-4000-8000-000000000001',
  '96300000-0000-4000-8000-000000000011'
);

commit;
