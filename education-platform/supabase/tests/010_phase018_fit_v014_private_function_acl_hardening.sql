-- PHASE 018 V014 PRIVATE FUNCTION ACL HARDENING TEST.
-- Runs after migrations 001-018 and proves exact revocation, owner retention,
-- and the complete authenticated function whitelist.

begin;

set local search_path = public, private, extensions, pg_catalog;

do $test$
declare
  v_signature text;
  v_role text;
  v_unexpected integer;
begin
  foreach v_signature in array array[
    'private.create_fit_financial_review_v014()',
    'private.fit_decision_input_payload_v011(uuid)',
    'private.fit_financial_normalization_payload_v014(uuid)',
    'private.fit_financial_payload_collections_v014(uuid)',
    'private.fit_financial_source_payload_v014(uuid)',
    'private.guard_fit_financial_contract_v014()',
    'private.guard_fit_financial_normalization_update_v014()',
    'private.guard_fit_financial_review_insert_v014()',
    'private.guard_fit_financial_review_update_v014()',
    'private.guard_fit_financial_typed_rows_v014()',
    'private.require_fit_financial_v014_assembly(uuid)',
    'private.set_fit_financial_contract_v014()',
    'private.validate_fit_financial_finalization_v014(uuid)'
  ]
  loop
    if to_regprocedure(v_signature) is null then
      raise exception 'Phase 018 expected function is missing: %', v_signature;
    end if;

    if pg_get_userbyid(
         (select proowner from pg_proc where oid = v_signature::regprocedure)
       ) <> 'foundation_evaluation_executor'
       or not (
         select prosecdef from pg_proc where oid = v_signature::regprocedure
       ) then
      raise exception 'Phase 018 function contract drifted: %', v_signature;
    end if;

    foreach v_role in array array[
      'public', 'anon', 'authenticated', 'service_role', 'authenticator',
      'foundation_catalog_executor', 'foundation_student_executor'
    ]
    loop
      if has_function_privilege(v_role, v_signature, 'EXECUTE') then
        raise exception 'Phase 018 EXECUTE remained for % on %',
          v_role, v_signature;
      end if;
    end loop;

    if not has_function_privilege(
      'foundation_evaluation_executor', v_signature, 'EXECUTE'
    ) then
      raise exception 'Phase 018 owner EXECUTE is missing on %', v_signature;
    end if;
  end loop;

  select count(*) into v_unexpected
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname in ('public', 'private')
    and has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
    and procedure.oid not in (
      'public.current_user_owns_student(uuid)'::regprocedure,
      'public.current_user_owns_profile(uuid)'::regprocedure,
      'public.review_fit_financial_normalization_v017(uuid,uuid)'::regprocedure
    );

  if v_unexpected <> 0 then
    raise exception 'Phase 018 authenticated whitelist has % unexpected functions',
      v_unexpected;
  end if;

  if (
    select count(*)
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public', 'private')
      and has_function_privilege('authenticated', procedure.oid, 'EXECUTE')
  ) <> 3 then
    raise exception 'Phase 018 authenticated whitelist is not exactly three functions';
  end if;

  if not has_function_privilege(
       'authenticated', 'public.current_user_owns_student(uuid)', 'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated', 'public.current_user_owns_profile(uuid)', 'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.review_fit_financial_normalization_v017(uuid,uuid)',
       'EXECUTE'
     ) then
    raise exception 'Phase 018 authenticated whitelist entry is missing';
  end if;
end;
$test$;

rollback;
