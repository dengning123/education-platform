-- Run after Migration 028. Application/Outcome remains planning-only under a
-- provisional future Migration 030 identity.
begin;

do $test$
declare
  v_runtime_hash constant text :=
    '2cad2a2f2ea1d01b6bc1863cbbda6350e84043c865e85f266e01d0512c8dcc9f';
  v_snapshot regprocedure := to_regprocedure(
    'public.get_fit_product_evaluation_snapshot_v028(uuid,uuid,uuid,text,uuid[],uuid[],uuid[],uuid[],uuid[],uuid[],uuid[])'
  );
  v_build_projection regprocedure := to_regprocedure(
    'private.get_fit_product_evaluator_build_v028()'
  );
  v_definition text;
  v_build_definition text;
begin
  if (
    select count(*) from public.fit_evaluator_builds build
    where build.contract_release_id =
      '30000000-0000-0000-0000-000000000001'::uuid
      and build.evaluator_name = 'education-platform-fit-engine'
      and build.status = 'VERIFIED'
      and build.retired_at is null
  ) <> 2 then
    raise exception 'M028 requires exactly the legacy and product-aware VERIFIED builds';
  end if;

  if not exists (
    select 1 from public.fit_evaluator_builds build
    where build.evaluator_build_id =
      '30000000-0000-0000-0000-000000000164'::uuid
      and build.evaluator_version = '0.1.0'
      and build.build_hash =
        'e32a3ed849633a216e84dd23afae5bd60f261333c55e4c5a3c0841f6b795564e'
      and build.status = 'VERIFIED'
      and build.retired_at is null
  ) then
    raise exception 'M028 drifted the legacy Fit evaluator build';
  end if;

  if not exists (
    select 1 from public.fit_evaluator_builds build
    where build.evaluator_build_id =
      '30000000-0000-0000-0000-000000000284'::uuid
      and build.evaluator_version = '0.1.0-product-v027'
      and build.build_hash = v_runtime_hash
      and build.status = 'VERIFIED'
      and build.verification_evidence_id =
        '30000000-0000-0000-0000-000000000283'::uuid
      and build.retired_at is null
  ) then
    raise exception 'M028 product evaluator build identity is incomplete';
  end if;

  if exists (
    select 1 from public.fit_contract_releases release
    where release.contract_release_id =
      '30000000-0000-0000-0000-000000000001'::uuid
      and (
        release.release_code <> 'fit-v0.1'
        or release.specification_version <> 'v0.1'
        or release.status <> 'VERIFIED'
        or release.retired_at is not null
      )
  ) then
    raise exception 'M028 changed the frozen Fit contract release';
  end if;

  if has_table_privilege('anon', 'public.fit_evaluator_builds', 'INSERT')
     or has_table_privilege('authenticated', 'public.fit_evaluator_builds', 'INSERT')
     or has_table_privilege('service_role', 'public.fit_evaluator_builds', 'INSERT')
     or has_table_privilege('foundation_student_executor', 'public.fit_evaluator_builds', 'INSERT')
     or has_table_privilege('foundation_evaluation_executor', 'public.fit_evaluator_builds', 'INSERT') then
    raise exception 'M028 expanded external evaluator-build mutation authority';
  end if;

  if v_snapshot is null or v_build_projection is null then
    raise exception 'M028 product snapshot functions are missing';
  end if;
  select pg_get_functiondef(v_snapshot) into strict v_definition;
  select pg_get_functiondef(v_build_projection) into strict v_build_definition;
  if position('public.get_fit_evaluation_snapshot_v016' in v_definition) = 0
     or position('private.get_fit_product_evaluator_build_v028' in v_definition) = 0
     or position('fit_evaluator_builds' in v_definition) = 0 then
    raise exception 'M028 product snapshot is not the exact v016/build substitution wrapper';
  end if;
  if position('30000000-0000-0000-0000-000000000284' in v_build_definition) = 0
     or position('0.1.0-product-v027' in v_build_definition) = 0
     or position('status = ''VERIFIED''' in v_build_definition) = 0 then
    raise exception 'M028 product build projection is not exact and VERIFIED-only';
  end if;
  if not exists (
    select 1 from pg_proc procedure
    where procedure.oid = v_snapshot
      and procedure.proowner = 'foundation_evaluation_executor'::regrole
      and not procedure.prosecdef
      and procedure.provolatile = 's'
      and procedure.proconfig is not distinct from
        array['search_path=pg_catalog, public, private, extensions']::text[]
  ) then
    raise exception 'M028 product snapshot execution contract drifted';
  end if;
  if not has_function_privilege('service_role', v_snapshot, 'EXECUTE')
     or has_function_privilege('anon', v_snapshot, 'EXECUTE')
     or has_function_privilege('authenticated', v_snapshot, 'EXECUTE')
     or has_function_privilege('foundation_student_executor', v_snapshot, 'EXECUTE')
     or has_function_privilege('foundation_evaluation_executor', v_snapshot, 'EXECUTE') then
    raise exception 'M028 product snapshot ACL is not service-only';
  end if;
  if not exists (
    select 1 from pg_proc procedure
    where procedure.oid = v_build_projection
      and procedure.proowner = 'foundation_evaluation_executor'::regrole
      and procedure.prosecdef
      and procedure.provolatile = 's'
      and procedure.proconfig is not distinct from
        array['search_path=pg_catalog, public, private, extensions']::text[]
  ) or not has_function_privilege('service_role', v_build_projection, 'EXECUTE')
     or has_function_privilege('anon', v_build_projection, 'EXECUTE')
     or has_function_privilege('authenticated', v_build_projection, 'EXECUTE')
     or has_function_privilege('foundation_student_executor', v_build_projection, 'EXECUTE') then
    raise exception 'M028 product build projection boundary drifted';
  end if;
  if not exists (
    select 1 from public.foundation_function_contracts contract
    where contract.schema_name = 'public'
      and contract.function_name = 'get_fit_product_evaluation_snapshot_v028'
      and contract.owner_role = 'foundation_evaluation_executor'
      and not contract.prosecdef
      and contract.search_path = 'pg_catalog, public, private, extensions'
      and contract.allowed_caller_roles = array['service_role']::text[]
  ) then
    raise exception 'M028 product snapshot registry contract is incomplete';
  end if;
  if not exists (
    select 1 from public.foundation_function_contracts contract
    where contract.schema_name = 'private'
      and contract.function_name = 'get_fit_product_evaluator_build_v028'
      and contract.owner_role = 'foundation_evaluation_executor'
      and contract.prosecdef
      and contract.search_path = 'pg_catalog, public, private, extensions'
      and contract.allowed_caller_roles = array['service_role']::text[]
  ) then
    raise exception 'M028 product build projection registry contract is incomplete';
  end if;
end;
$test$;

rollback;
