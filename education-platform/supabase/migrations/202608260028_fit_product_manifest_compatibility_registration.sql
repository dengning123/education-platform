begin;

-- Phase 4B Fit Input / Manifest Compatibility Closure is additive over the
-- immutable Migration 027 product-intent contract and the frozen Fit v0.1
-- semantic law. It registers one separately addressable product-aware adapter
-- build. No method, policy, truth table, assessment, confidence, coverage,
-- inference, manifest type, persistence rule, or fingerprint function changes.
do $registration$
declare
  v_reviewed_at constant timestamptz :=
    timestamptz '2026-08-26 00:00:00+00';
  v_runtime_hash constant text :=
    '2cad2a2f2ea1d01b6bc1863cbbda6350e84043c865e85f266e01d0512c8dcc9f';
begin
  if not exists (
    select 1 from public.fit_evaluator_builds build
    where build.evaluator_build_id =
      '30000000-0000-0000-0000-000000000164'::uuid
      and build.contract_release_id =
        '30000000-0000-0000-0000-000000000001'::uuid
      and build.evaluator_name = 'education-platform-fit-engine'
      and build.evaluator_version = '0.1.0'
      and build.build_hash =
        'e32a3ed849633a216e84dd23afae5bd60f261333c55e4c5a3c0841f6b795564e'
      and build.status = 'VERIFIED'
      and build.retired_at is null
  ) then
    raise exception using errcode = '23514',
      message = 'Migration 028 requires the unchanged legacy Fit evaluator build';
  end if;

  insert into public.source_identities (
    source_identity_id, canonical_publisher, current_source_id, created_at
  ) values (
    '30000000-0000-0000-0000-000000000281',
    'Education Platform Phase 4B Review',
    '30000000-0000-0000-0000-000000000282',
    v_reviewed_at
  );

  insert into public.sources (
    source_id, source_identity_id, revision_number, publisher, title, url,
    reliability_tier, source_type, retrieval_content_hash, revision_reason,
    created_at, updated_at
  ) values (
    '30000000-0000-0000-0000-000000000282',
    '30000000-0000-0000-0000-000000000281',
    1,
    'Education Platform Phase 4B Review',
    'Fit product manifest compatibility runtime review',
    'repository://education-platform/supabase/functions/_shared/fit-runtime.js@2cad2a2f2ea1d01b6bc1863cbbda6350e84043c865e85f266e01d0512c8dcc9f',
    'TIER_A_OFFICIAL',
    'INTERNAL_OFFICIAL_REVIEW',
    v_runtime_hash,
    'INITIAL',
    v_reviewed_at,
    v_reviewed_at
  );

  insert into public.evidence_items (
    evidence_id, source_id, excerpt, locator, cycle_context,
    retrieved_at, verified_at, content_hash, created_at
  ) values (
    '30000000-0000-0000-0000-000000000283',
    '30000000-0000-0000-0000-000000000282',
    'The product-only M027 parser, authenticated assembly reload, existing PHASE2_COMPLETENESS witness construction, and separately versioned adapter execution path were reviewed without changing the frozen Fit v0.1 semantic or fingerprint laws.',
    'packages/fit-engine-adapter; supabase/functions/fit-evaluate',
    'phase4b-fit-product-manifest-compatibility',
    v_reviewed_at,
    v_reviewed_at,
    v_runtime_hash,
    v_reviewed_at
  );

  insert into public.fit_evaluator_builds (
    evaluator_build_id, contract_release_id, evaluator_name,
    evaluator_version, build_hash, created_at
  ) values (
    '30000000-0000-0000-0000-000000000284',
    '30000000-0000-0000-0000-000000000001',
    'education-platform-fit-engine',
    '0.1.0-product-v027',
    v_runtime_hash,
    v_reviewed_at
  );

  perform public.verify_fit_definition(
    'EVALUATOR_BUILD',
    '30000000-0000-0000-0000-000000000284',
    'Phase 4B product manifest compatibility review',
    '30000000-0000-0000-0000-000000000283'
  );

  if not exists (
    select 1 from public.fit_evaluator_builds build
    where build.evaluator_build_id =
      '30000000-0000-0000-0000-000000000284'::uuid
      and build.contract_release_id =
        '30000000-0000-0000-0000-000000000001'::uuid
      and build.evaluator_name = 'education-platform-fit-engine'
      and build.evaluator_version = '0.1.0-product-v027'
      and build.build_hash = v_runtime_hash
      and build.status = 'VERIFIED'
      and build.verification_evidence_id =
        '30000000-0000-0000-0000-000000000283'::uuid
      and build.retired_at is null
  ) then
    raise exception using errcode = '23514',
      message = 'Migration 028 product evaluator build verification failed';
  end if;
end;
$registration$;

-- The frozen v016 snapshot intentionally projects only the legacy 0.1.0
-- evaluator build. Reuse its complete bounded source projection and replace
-- only that one registry array with the separately verified product build.
-- This avoids both a live post-snapshot registry read and any modification to
-- the frozen v016 function.
create function private.get_fit_product_evaluator_build_v028()
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $build$
declare
  v_build public.fit_evaluator_builds%rowtype;
begin
  select build.* into strict v_build
  from public.fit_evaluator_builds build
  where build.evaluator_build_id =
      '30000000-0000-0000-0000-000000000284'::uuid
    and build.contract_release_id =
      '30000000-0000-0000-0000-000000000001'::uuid
    and build.evaluator_name = 'education-platform-fit-engine'
    and build.evaluator_version = '0.1.0-product-v027'
    and build.status = 'VERIFIED'
    and build.retired_at is null;
  return to_jsonb(v_build);
exception
  when no_data_found or too_many_rows then
    raise exception using errcode = '23514',
      message = 'M028_PRODUCT_EVALUATOR_BUILD_NOT_EXACT';
end;
$build$;

create function public.get_fit_product_evaluation_snapshot_v028(
  p_profile_version_id uuid,
  p_intent_set_id uuid,
  p_program_version_id uuid,
  p_taxonomy_release_code text,
  p_observation_ids uuid[],
  p_catalog_mapping_ids uuid[],
  p_student_course_ids uuid[],
  p_student_mapping_ids uuid[],
  p_taxonomy_concept_ids uuid[],
  p_context_claim_ids uuid[],
  p_context_mapping_ids uuid[]
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = pg_catalog, public, private, extensions
as $snapshot$
declare
  v_snapshot jsonb;
  v_build jsonb;
begin
  v_snapshot := public.get_fit_evaluation_snapshot_v016(
    p_profile_version_id,
    p_intent_set_id,
    p_program_version_id,
    p_taxonomy_release_code,
    p_observation_ids,
    p_catalog_mapping_ids,
    p_student_course_ids,
    p_student_mapping_ids,
    p_taxonomy_concept_ids,
    p_context_claim_ids,
    p_context_mapping_ids
  );

  v_build := private.get_fit_product_evaluator_build_v028();

  return jsonb_set(
    v_snapshot,
    '{fit_evaluator_builds}',
    jsonb_build_array(v_build),
    false
  );
end;
$snapshot$;

grant create on schema public to foundation_evaluation_executor;
grant create on schema private to foundation_evaluation_executor;
alter function private.get_fit_product_evaluator_build_v028()
  owner to foundation_evaluation_executor;
alter function public.get_fit_product_evaluation_snapshot_v028(
  uuid, uuid, uuid, text, uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]
) owner to foundation_evaluation_executor;
revoke create on schema public from foundation_evaluation_executor;
revoke create on schema private from foundation_evaluation_executor;

revoke all on function private.get_fit_product_evaluator_build_v028()
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
revoke all on function public.get_fit_product_evaluation_snapshot_v028(
  uuid, uuid, uuid, text, uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]
) from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant execute on function private.get_fit_product_evaluator_build_v028()
to service_role;
grant execute on function public.get_fit_product_evaluation_snapshot_v028(
  uuid, uuid, uuid, text, uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]
) to service_role;

do $contract$
declare
  v_function record;
begin
  for v_function in
    select namespace.nspname,
      procedure.proname,
      procedure.prosecdef,
      pg_get_function_identity_arguments(procedure.oid) identity_arguments,
      pg_get_functiondef(procedure.oid) definition
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where (namespace.nspname, procedure.proname) in (
      ('private', 'get_fit_product_evaluator_build_v028'),
      ('public', 'get_fit_product_evaluation_snapshot_v028')
    )
    order by namespace.nspname, procedure.proname
  loop
    insert into public.foundation_function_contracts (
      schema_name, function_name, identity_arguments, owner_role, prosecdef,
      search_path, allowed_caller_roles, body_digest
    ) values (
      v_function.nspname,
      v_function.proname,
      v_function.identity_arguments,
      'foundation_evaluation_executor',
      v_function.prosecdef,
      'pg_catalog, public, private, extensions',
      array['service_role'],
      encode(
        extensions.digest(convert_to(v_function.definition, 'UTF8'), 'sha256'),
        'hex'
      )
    );
  end loop;
end;
$contract$;

comment on function private.get_fit_product_evaluator_build_v028() is
  'Service-only exact projection of the separately verified M028 product Fit evaluator build. It does not expose or mutate any other registry row.';

comment on function public.get_fit_product_evaluation_snapshot_v028(
  uuid, uuid, uuid, text, uuid[], uuid[], uuid[], uuid[], uuid[], uuid[], uuid[]
) is
  'Service-only M028 product Fit projection. It reuses the frozen v016 source snapshot and substitutes exactly one verified product evaluator build; it performs no scoring, inference, or semantic conversion.';

commit;
