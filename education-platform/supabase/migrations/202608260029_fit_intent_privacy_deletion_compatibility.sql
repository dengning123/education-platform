begin;

-- Phase 4B M027 privacy-deletion compatibility repair. The frozen M027
-- product-intent command guard remains authoritative for ordinary writes.
-- The only added path is the existing M012 transaction-bound privacy cascade:
-- delete_student_data() inserts a matching private authorization, deletes the
-- student parent, and removes that authorization before returning.
create or replace function private.guard_fit_intent_product_write_v027()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_intent_set_id uuid;
begin
  if tg_op = 'DELETE'
     and private.student_privacy_delete_allowed() then
    return old;
  end if;

  v_intent_set_id := case when tg_op = 'DELETE'
    then old.intent_set_id else new.intent_set_id end;
  if exists (
    select 1 from private.fit_intent_product_states_v027 state
    where state.intent_set_id = v_intent_set_id
  ) and current_setting('app.fit_intent_product_v027_write', true)
        is distinct from 'on' then
    raise exception using errcode = '42501',
      message = 'FIT_INTENT_PRODUCT_COMMAND_REQUIRED';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$function$;

-- CREATE OR REPLACE preserves ownership and ACLs. Converge the closed caller
-- contract explicitly so a partially drifted local database cannot pass.
revoke all on function private.guard_fit_intent_product_write_v027()
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant execute on function private.guard_fit_intent_product_write_v027()
to foundation_student_executor;

do $contract$
declare
  v_function record;
begin
  select namespace.nspname,
    procedure.proname,
    pg_get_function_identity_arguments(procedure.oid) identity_arguments,
    procedure.proowner::regrole::text owner_role,
    procedure.prosecdef,
    pg_get_functiondef(procedure.oid) definition
  into strict v_function
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  where namespace.nspname = 'private'
    and procedure.proname = 'guard_fit_intent_product_write_v027';

  insert into public.foundation_function_contracts (
    schema_name, function_name, identity_arguments, owner_role, prosecdef,
    search_path, allowed_caller_roles, body_digest
  ) values (
    v_function.nspname,
    v_function.proname,
    v_function.identity_arguments,
    v_function.owner_role,
    v_function.prosecdef,
    'pg_catalog, public, private, extensions',
    array['foundation_student_executor'],
    encode(
      extensions.digest(
        convert_to(v_function.definition, 'UTF8'),
        'sha256'
      ),
      'hex'
    )
  )
  on conflict (schema_name, function_name, identity_arguments) do update
    set owner_role = excluded.owner_role,
        prosecdef = excluded.prosecdef,
        search_path = excluded.search_path,
        allowed_caller_roles = excluded.allowed_caller_roles,
        body_digest = excluded.body_digest;
end;
$contract$;

comment on function private.guard_fit_intent_product_write_v027() is
  'M027 product-intent write guard with M029 compatibility for only the existing M012 transaction-bound student privacy-deletion cascade. Ordinary direct and product-managed writes retain the frozen M027 command boundary.';

do $assert$
declare
  v_guard regprocedure := to_regprocedure(
    'private.guard_fit_intent_product_write_v027()'
  );
  v_privacy regprocedure := to_regprocedure(
    'private.student_privacy_delete_allowed()'
  );
  v_definition text;
  v_privacy_definition text;
  v_digest text;
begin
  if v_guard is null or v_privacy is null then
    raise exception '029 assertion failed: required function missing';
  end if;

  select pg_get_functiondef(v_guard) into strict v_definition;
  select pg_get_functiondef(v_privacy) into strict v_privacy_definition;
  v_digest := encode(
    extensions.digest(convert_to(v_definition, 'UTF8'), 'sha256'),
    'hex'
  );

  if not exists (
    select 1 from pg_proc procedure
    where procedure.oid = v_guard
      and procedure.proowner::regrole::text =
        'foundation_student_executor'
      and procedure.prosecdef
      and procedure.provolatile = 'v'
      and procedure.pronargs = 0
      and procedure.proconfig is not distinct from
        array['search_path=pg_catalog, public, private, extensions']::text[]
  ) or position('private.student_privacy_delete_allowed()' in v_definition) = 0
     or position('tg_op = ''DELETE''' in v_definition) = 0
     or position('app.fit_intent_product_v027_write' in v_definition) = 0
     or position('app.student_privacy_delete' in v_definition) <> 0 then
    raise exception '029 assertion failed: guard compatibility contract';
  end if;

  if position('txid_current()' in v_privacy_definition) = 0
     or position('student_deletion_authorizations' in v_privacy_definition) = 0
     or position('not exists' in lower(v_privacy_definition)) = 0
     or position('public.students' in v_privacy_definition) = 0 then
    raise exception '029 assertion failed: trusted privacy context drifted';
  end if;

  if not has_function_privilege(
    'foundation_student_executor', v_guard, 'EXECUTE'
  ) or exists (
    select 1
    from information_schema.routine_privileges privilege
    where privilege.routine_schema = 'private'
      and privilege.routine_name = 'guard_fit_intent_product_write_v027'
      and privilege.privilege_type = 'EXECUTE'
      and privilege.grantee <> 'foundation_student_executor'
  ) then
    raise exception '029 assertion failed: guard ACL';
  end if;

  if not exists (
    select 1 from public.foundation_function_contracts contract
    where contract.schema_name = 'private'
      and contract.function_name = 'guard_fit_intent_product_write_v027'
      and contract.identity_arguments = ''
      and contract.owner_role = 'foundation_student_executor'
      and contract.prosecdef
      and contract.search_path =
        'pg_catalog, public, private, extensions'
      and contract.allowed_caller_roles =
        array['foundation_student_executor']::text[]
      and contract.body_digest = v_digest
  ) then
    raise exception '029 assertion failed: function registry contract';
  end if;
end;
$assert$;

commit;
