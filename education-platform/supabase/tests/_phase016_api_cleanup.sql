-- Idempotent cleanup for the local-only Phase 016 Edge/API fixture.

do $cleanup$
begin
  if exists (
    select 1 from public.students
    where student_id = '61600000-0000-0000-0000-000000000001'
  ) then
    perform public.delete_student_data(
      '61600000-0000-0000-0000-000000000001',
      'TEST_LIFECYCLE'
    );
  end if;
end;
$cleanup$;
