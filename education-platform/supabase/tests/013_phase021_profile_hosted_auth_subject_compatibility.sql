-- Runs after Migration 021. Verifies the project-owned request-subject bridge
-- without granting the Profile executor access to the managed auth schema.
-- Taxonomy Projection is Migration 022; Application/Outcome is planning-only
-- under a provisional future Migration 023 identity.

begin;

do $test$
declare
  v_owner_auth constant uuid := '97000000-0000-4000-8000-000000000001';
  v_other_auth constant uuid := '97000000-0000-4000-8000-000000000002';
  v_bridge oid := to_regprocedure(
    'private.profile_request_auth_subject_v021()'
  );
  v_require oid := to_regprocedure(
    'private.profile_require_auth_subject_v019()'
  );
  v_lookup oid := to_regprocedure(
    'private.profile_student_for_auth_v019()'
  );
  v_expected uuid;
  v_actual uuid;
  v_profile_id uuid;
  v_other_profile_id uuid;
  v_document jsonb;
  v_blocked boolean;
  v_signature text;
begin
  if v_bridge is null or v_require is null or v_lookup is null
     or to_regprocedure(
       'private.profile_request_auth_subject_v021(uuid)'
     ) is not null then
    raise exception '021 subject bridge signature is not closed';
  end if;

  if not exists (
    select 1
    from pg_proc procedure
    where procedure.oid = v_bridge
      and procedure.proowner::regrole::text = 'foundation_student_executor'
      and not procedure.prosecdef
      and procedure.provolatile = 's'
      and procedure.pronargs = 0
      and procedure.proconfig is not distinct from
        array['search_path=pg_catalog, public, private, extensions']::text[]
      and position(
        'request.jwt.claim.sub' in pg_get_functiondef(procedure.oid)
      ) > 0
      and position(
        'request.jwt.claims' in pg_get_functiondef(procedure.oid)
      ) > 0
      and position(
        'auth.' in lower(pg_get_functiondef(procedure.oid))
      ) = 0
  ) then
    raise exception '021 subject bridge owner/body/search_path drifted';
  end if;

  if exists (
    select 1
    from pg_proc procedure
    where procedure.oid in (v_require, v_lookup)
      and (
        procedure.proowner::regrole::text <> 'foundation_student_executor'
        or not procedure.prosecdef
        or procedure.provolatile <> 's'
        or procedure.proconfig is distinct from
          array['search_path=pg_catalog, public, private, extensions']::text[]
        or position(
          'private.profile_request_auth_subject_v021()'
          in pg_get_functiondef(procedure.oid)
        ) = 0
        or position(
          'auth.uid' in lower(pg_get_functiondef(procedure.oid))
        ) <> 0
      )
  ) then
    raise exception '021 did not converge both v019 subject helpers';
  end if;

  if not has_function_privilege(
    'foundation_student_executor', v_bridge, 'EXECUTE'
  ) or exists (
    select 1
    from information_schema.routine_privileges privilege
    where privilege.routine_schema = 'private'
      and privilege.routine_name = 'profile_request_auth_subject_v021'
      and privilege.privilege_type = 'EXECUTE'
      and privilege.grantee <> 'foundation_student_executor'
  ) then
    raise exception '021 subject bridge ACL is not closed';
  end if;

  if has_schema_privilege(
    'foundation_student_executor', 'auth', 'USAGE'
  ) or has_schema_privilege(
    'foundation_student_executor', 'auth', 'CREATE'
  ) or has_table_privilege(
    'foundation_student_executor', 'auth.users',
    'SELECT,INSERT,UPDATE,DELETE'
  ) or pg_has_role(
    'foundation_student_executor', 'service_role', 'MEMBER'
  ) then
    raise exception '021 expanded the Profile executor Auth capability';
  end if;

  if (
    select count(*)
    from public.foundation_function_contracts contract
    join pg_proc procedure
      on procedure.oid = to_regprocedure(
        format(
          '%I.%I(%s)',
          contract.schema_name,
          contract.function_name,
          contract.identity_arguments
        )
      )
    where contract.schema_name = 'private'
      and contract.function_name in (
        'profile_request_auth_subject_v021',
        'profile_require_auth_subject_v019',
        'profile_student_for_auth_v019'
      )
      and contract.owner_role = 'foundation_student_executor'
      and contract.search_path =
        'pg_catalog, public, private, extensions'
      and contract.allowed_caller_roles =
        array['foundation_student_executor']
      and contract.body_digest = encode(
        extensions.digest(
          convert_to(pg_get_functiondef(procedure.oid), 'UTF8'),
          'sha256'
        ),
        'hex'
      )
  ) <> 3 then
    raise exception '021 function registry digest/ACL contract drifted';
  end if;

  -- The legacy scalar claim wins exactly as it does in the live auth.uid().
  perform set_config('request.jwt.claim.sub', v_owner_auth::text, true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_other_auth)::text,
    true
  );
  execute 'set local role authenticated';
  v_expected := auth.uid();
  execute 'reset role';
  execute 'set local role foundation_student_executor';
  v_actual := private.profile_request_auth_subject_v021();
  execute 'reset role';
  if v_actual is distinct from v_expected or v_actual <> v_owner_auth then
    raise exception '021 legacy subject precedence diverged from auth.uid()';
  end if;

  -- PostgreSQL 14+ PostgREST uses the JSON request.jwt.claims setting.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_owner_auth)::text,
    true
  );
  execute 'set local role authenticated';
  v_expected := auth.uid();
  execute 'reset role';
  execute 'set local role foundation_student_executor';
  v_actual := private.profile_request_auth_subject_v021();
  execute 'reset role';
  if v_actual is distinct from v_expected or v_actual <> v_owner_auth then
    raise exception '021 JSON subject fallback diverged from auth.uid()';
  end if;

  -- Missing, malformed JSON, and non-UUID subjects fail closed.
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '', true);
  execute 'set local role foundation_student_executor';
  if private.profile_request_auth_subject_v021() is not null then
    raise exception '021 missing request subject did not return NULL';
  end if;
  v_blocked := false;
  begin
    perform private.profile_require_auth_subject_v019();
  exception when insufficient_privilege then
    v_blocked := sqlerrm = 'PROFILE_AUTH_REQUIRED';
  end;
  if not v_blocked then
    raise exception '021 missing request subject did not fail closed';
  end if;

  perform set_config('request.jwt.claim.sub', 'not-a-uuid', true);
  v_blocked := false;
  begin
    perform private.profile_request_auth_subject_v021();
  exception when invalid_text_representation then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception '021 non-UUID request subject did not fail closed';
  end if;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claims', '{', true);
  v_blocked := false;
  begin
    perform private.profile_request_auth_subject_v021();
  exception when invalid_text_representation then
    v_blocked := true;
  end;
  if not v_blocked then
    raise exception '021 malformed JWT claims did not fail closed';
  end if;
  execute 'reset role';

  -- Object-level PUBLIC EXECUTE on Supabase claim helpers must not become
  -- runtime-callable without auth schema USAGE.
  foreach v_signature in array array[
    'auth.uid()', 'auth.email()', 'auth.role()', 'auth.jwt()'
  ]
  loop
    execute 'set local role foundation_student_executor';
    v_blocked := false;
    begin
      execute format('select %s', v_signature);
    exception when insufficient_privilege then
      v_blocked := true;
    end;
    execute 'reset role';
    if not v_blocked then
      raise exception '021 Profile executor invoked unintended helper %',
        v_signature;
    end if;
  end loop;

  -- Existing Profile identity and owner isolation continue through the bridge.
  insert into auth.users (id, email) values
    (v_owner_auth, 'phase021-owner@test.invalid'),
    (v_other_auth, 'phase021-other@test.invalid');

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_owner_auth)::text,
    true
  );
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();
  v_profile_id := (
    public.create_or_resume_profile_draft_v019(
      '97000000-0000-4000-8000-000000000101'
    ) ->> 'profileVersionId'
  )::uuid;
  v_document := public.get_profile_document_v019(v_profile_id);
  execute 'reset role';
  if (v_document ->> 'profileVersionId')::uuid <> v_profile_id
     or v_document ->> 'status' <> 'DRAFT' then
    raise exception '021 owner Profile read contract drifted';
  end if;

  perform set_config(
    'request.jwt.claims',
    jsonb_build_object('sub', v_other_auth)::text,
    true
  );
  execute 'set local role authenticated';
  perform public.bootstrap_profile_identity_v019();
  v_other_profile_id := (
    public.create_or_resume_profile_draft_v019(
      '97000000-0000-4000-8000-000000000102'
    ) ->> 'profileVersionId'
  )::uuid;
  v_blocked := false;
  begin
    perform public.get_profile_document_v019(v_profile_id);
  exception when no_data_found then
    v_blocked := sqlerrm = 'PROFILE_NOT_FOUND';
  end;
  execute 'reset role';
  if not v_blocked or v_other_profile_id = v_profile_id then
    raise exception '021 changed unrelated-user Profile isolation';
  end if;
end;
$test$;

rollback;
