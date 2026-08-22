begin;

-- Migration 018 is an ACL-only correction for 13 v014 private functions that
-- retained PostgreSQL's implicit PUBLIC EXECUTE. It does not alter default
-- privileges, function definitions, owners, data, or migrations 014-017.

do $preflight$
declare
  v_signature text;
  v_oid regprocedure;
  v_owner text;
  v_schema text;
  v_security_definer boolean;
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
    v_oid := to_regprocedure(v_signature);
    if v_oid is null then
      raise exception using
        errcode = '42704',
        message = format('Migration 018 expected function is missing: %s', v_signature);
    end if;

    select namespace.nspname,
           pg_get_userbyid(procedure.proowner),
           procedure.prosecdef
    into strict v_schema, v_owner, v_security_definer
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where procedure.oid = v_oid;

    if v_schema <> 'private'
       or v_owner <> 'foundation_evaluation_executor'
       or not v_security_definer then
      raise exception using
        errcode = '55000',
        message = format(
          'Migration 018 function contract drifted: %s', v_signature
        );
    end if;
  end loop;
end;
$preflight$;

revoke all on function
  private.create_fit_financial_review_v014(),
  private.fit_decision_input_payload_v011(uuid),
  private.fit_financial_normalization_payload_v014(uuid),
  private.fit_financial_payload_collections_v014(uuid),
  private.fit_financial_source_payload_v014(uuid),
  private.guard_fit_financial_contract_v014(),
  private.guard_fit_financial_normalization_update_v014(),
  private.guard_fit_financial_review_insert_v014(),
  private.guard_fit_financial_review_update_v014(),
  private.guard_fit_financial_typed_rows_v014(),
  private.require_fit_financial_v014_assembly(uuid),
  private.set_fit_financial_contract_v014(),
  private.validate_fit_financial_finalization_v014(uuid)
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor;

do $assertions$
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
    foreach v_role in array array[
      'public', 'anon', 'authenticated', 'service_role', 'authenticator',
      'foundation_catalog_executor', 'foundation_student_executor'
    ]
    loop
      if has_function_privilege(v_role, v_signature, 'EXECUTE') then
        raise exception using
          errcode = '42501',
          message = format(
            'Migration 018 EXECUTE remained for %s on %s',
            v_role, v_signature
          );
      end if;
    end loop;

    if not has_function_privilege(
      'foundation_evaluation_executor', v_signature, 'EXECUTE'
    ) then
      raise exception using
        errcode = '42501',
        message = format(
          'Migration 018 removed owner EXECUTE from %s', v_signature
        );
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
    raise exception using
      errcode = '42501',
      message = format(
        'Migration 018 authenticated function whitelist has %s unexpected entries',
        v_unexpected
      );
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
    raise exception using
      errcode = '42501',
      message = 'Migration 018 removed an authenticated whitelist entry';
  end if;
end;
$assertions$;

commit;
