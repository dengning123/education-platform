\set ON_ERROR_STOP on

-- Run after Migration 019 on the disposable database prepared by the paired
-- fixture. Verifies historical semantics, server allocation, then cleans up.

do $assert$
declare
  v_auth constant uuid := '94000000-0000-0000-0000-000000000001';
  v_student constant uuid := '94000000-0000-0000-0000-000000000002';
  v_historical_profile uuid;
  v_product_profile uuid;
  v_result jsonb;
begin
  select profile_version_id into strict v_historical_profile
  from public.student_profile_versions
  where student_id = v_student and version_number = 1;
  if exists (
    select 1 from public.student_profile_versions
    where profile_version_id = v_historical_profile
      and (product_managed or profile_revision <> 0 or status <> 'DRAFT')
  ) then
    raise exception '019 changed historical Profile semantics during upgrade';
  end if;

  perform set_config('request.jwt.claim.sub', v_auth::text, true);
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();
  v_result := public.create_or_resume_profile_draft_v019(
    '94000000-0000-0000-0000-000000000011'
  );
  v_product_profile := (v_result ->> 'profileVersionId')::uuid;
  if (v_result ->> 'versionNumber')::integer <> 2
     or v_product_profile = v_historical_profile then
    raise exception '019 did not allocate after the populated historical version';
  end if;
  execute 'reset role';

  if (select count(*) from public.student_profile_versions
      where student_id = v_student and status = 'DRAFT') <> 2
     or (select count(*) from public.student_profile_versions
         where student_id = v_student and product_managed and status = 'DRAFT') <> 1 then
    raise exception '019 product-draft policy modified or duplicated historical DRAFT rows';
  end if;

  execute 'set local role service_role';
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  execute 'reset role';
  if exists (
    select 1 from private.profile_capability_operations_v019
    where student_id = v_student
  ) or exists (
    select 1 from public.student_profile_versions where student_id = v_student
  ) then
    raise exception '019 populated-upgrade cleanup retained student state';
  end if;
  delete from auth.users where id = v_auth;
end;
$assert$;
