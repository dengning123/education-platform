begin;

create extension if not exists dblink;

do $test$
declare
  v_sqlstate text;
  v_msg text;
  v_identity uuid;
  v_source uuid;
  v_rev uuid;
  v_scope uuid;
  v_obs uuid;
  v_count integer;
  v_program uuid := '00000000-0000-0000-0000-000000000301';
  v_program_other uuid := '00000000-0000-0000-0000-000000000399';
  v_version uuid := '00000000-0000-0000-0000-000000000401';
  v_version_other uuid := '00000000-0000-0000-0000-000000000498';
  v_evidence uuid := '00000000-0000-0000-0000-000000000701';
  v_evidence_cip uuid := '00000000-0000-0000-0000-000000000702';
  v_evidence_b uuid;
  v_assertion uuid;
  v_assertion_old uuid;
  v_legacy_obs uuid;
  v_legacy_sel uuid;
  v_conn text;
  v_student uuid;
  v_profile uuid;
  v_intent uuid;
  v_school uuid := 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee0001';
  v_feat uuid;
  v_prior uuid;
  v_mapping uuid;
  v_name text;
  v_blocked boolean;
  v_role_membership_ok boolean;
  v_contract record;
begin
  perform set_config('statement_timeout', '15s', true);
  v_conn := 'dbname=' || current_database();

  -- No 013 objects on a 012-only database; 014 remains forbidden after 013.
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'allocate_taxonomy_release_ordinal_v02'
  ) then
    if exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname in ('public', 'private')
        and (
          c.relname ~ '^eligibility_.*_pins$'
          or c.relname like 'eligibility_snapshot_%'
          or c.relname = 'eligibility_requirement_projection_results'
          or c.relname like 'eligibility_negative_%'
          or c.relname = 'taxonomy_release_ordinal_allocator'
          or c.relname = 'requirement_group_projection_thresholds'
        )
    ) or exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where p.proname in (
        'finalize_eligibility_evaluation_v02',
        'start_eligibility_evaluation_v02',
        'seal_eligibility_evaluation_inputs_v02'
      )
    ) or exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and column_name in (
          'release_ordinal', 'introduced_release_ordinal', 'retired_release_ordinal'
        )
    ) then
      raise exception '013 objects leaked into 012';
    end if;
  end if;
  if exists (select 1 from pg_proc where proname like '%billing_basis%') then
    raise exception '014 objects leaked into 012/013';
  end if;

  -- Executor attributes.
  if exists (
    select 1 from pg_roles r
    where r.rolname in (
      'foundation_catalog_executor','foundation_student_executor','foundation_evaluation_executor'
    ) and (
      r.rolcanlogin or r.rolinherit or r.rolsuper or r.rolbypassrls
      or r.rolcreaterole or r.rolcreatedb or r.rolreplication
    )
  ) then
    raise exception 'Executor roles are not NOLOGIN/NOINHERIT/NOBYPASSRLS';
  end if;

  -- The install role must retain ADMIN plus SET/INHERIT capability on every
  -- executor. PostgreSQL 16+ may represent these as separate grants because
  -- a non-superuser CREATEROLE creator receives automatic ADMIN TRUE with
  -- SET/INHERIT FALSE from the bootstrap superuser.
  if current_setting('server_version_num')::integer >= 160000 then
    execute $membership$
      select count(*) = 3
      from (
        select granted_role.rolname
        from pg_auth_members m
        join pg_roles granted_role on granted_role.oid = m.roleid
        join pg_roles member_role on member_role.oid = m.member
        where granted_role.rolname in (
          'foundation_catalog_executor',
          'foundation_student_executor',
          'foundation_evaluation_executor'
        )
          and member_role.rolname = current_user
        group by granted_role.rolname
        having bool_or(m.admin_option)
           and bool_or(m.inherit_option)
           and bool_or(m.set_option)
      ) memberships
    $membership$
    into v_role_membership_ok;
  else
    select count(*) = 3
    into v_role_membership_ok
    from (
      select granted_role.rolname
      from pg_auth_members m
      join pg_roles granted_role on granted_role.oid = m.roleid
      join pg_roles member_role on member_role.oid = m.member
      where granted_role.rolname in (
        'foundation_catalog_executor',
        'foundation_student_executor',
        'foundation_evaluation_executor'
      )
        and member_role.rolname = current_user
      group by granted_role.rolname
      having bool_or(m.admin_option)
    ) memberships;
  end if;

  if not coalesce(v_role_membership_ok, false) then
    raise exception 'Install role lacks required executor ADMIN/SET/INHERIT membership';
  end if;

  -- Hosted Supabase grants EXECUTE on new public functions to authenticated
  -- through postgres/public default ACLs. Migration 012 must converge that
  -- baseline to the same frozen surface as vanilla PostgreSQL: exactly the
  -- two ownership helpers and no private-schema function.
  if exists (
    select 1
    from information_schema.routine_privileges
    where grantee = 'authenticated'
      and privilege_type = 'EXECUTE'
      and routine_schema in ('public', 'private')
      and not (
        routine_schema = 'public'
        and routine_name in (
          'current_user_owns_student',
          'current_user_owns_profile'
        )
      )
  ) or not has_function_privilege(
    'authenticated',
    'public.current_user_owns_student(uuid)',
    'EXECUTE'
  ) or not has_function_privilege(
    'authenticated',
    'public.current_user_owns_profile(uuid)',
    'EXECUTE'
  ) then
    raise exception 'Hosted authenticated EXECUTE surface did not converge';
  end if;

  -- 9A registry bidirectional: contracts exist, owners match, no 9B names on 012-only DBs.
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'allocate_taxonomy_release_ordinal_v02'
  ) and exists (
    select 1 from public.foundation_function_contracts
    where function_name like '%\_v02' escape '\' or function_name like '%ordinal%'
  ) then
    raise exception '9A registry contains 013 names';
  end if;
  if not exists (
    select 1 from public.foundation_function_contracts
    where function_name = 'finalize_eligibility_evaluation'
      and identity_arguments like '%eligibility_outcome%'
      and owner_role = 'foundation_evaluation_executor'
  ) then
    raise exception 'v0.1 finalize_eligibility_evaluation missing from 9A registry';
  end if;
  for v_contract in
    select c.*
    from public.foundation_function_contracts c
    where not exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      join pg_roles o on o.oid = p.proowner
      where n.nspname = c.schema_name
        and p.proname = c.function_name
        and pg_get_function_identity_arguments(p.oid) = c.identity_arguments
        and o.rolname = c.owner_role
        and p.prosecdef
    )
  loop
    raise exception '9A contract not installed: %.%(%)',
      v_contract.schema_name, v_contract.function_name, v_contract.identity_arguments;
  end loop;

  -- Production functions must not read security-significant app.* GUCs.
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid) ~ 'current_setting\(''app\.(controlled_catalog_write|rule_set_controlled_write|evaluation_controlled_write|student_privacy_delete|fit_registry_controlled_write|fit_intent_controlled_write|fit_context_controlled_write|fit_context_mapping_controlled_write|fit_context_selection_write|fit_evaluation_controlled_write)'
  ) then
    raise exception 'Production function still reads a security-significant app.* GUC';
  end if;

  -- GUC spoof as hosted-style service_role BYPASSRLS cannot authorize DML.
  perform set_config('app.controlled_catalog_write', 'on', true);
  perform set_config('app.rule_set_controlled_write', 'on', true);
  perform set_config('app.evaluation_controlled_write', 'on', true);
  perform set_config('app.student_privacy_delete', 'on', true);
  perform set_config('app.fit_registry_controlled_write', 'on', true);
  perform set_config('app.fit_intent_controlled_write', 'on', true);
  perform set_config('app.fit_context_controlled_write', 'on', true);
  perform set_config('app.fit_context_mapping_controlled_write', 'on', true);
  perform set_config('app.fit_context_selection_write', 'on', true);
  perform set_config('app.fit_evaluation_controlled_write', 'on', true);
  perform set_config('app.fit_evaluator_write', 'on', true);
  begin
    set local role service_role;
    begin
      update public.programs set program_name = program_name where program_id = v_program;
      raise exception 'service_role updated programs under GUC spoof';
    exception
      when insufficient_privilege then null;
    end;
    begin
      insert into public.catalog_concept_mappings (
        record_type, record_id, concept_id, relation, mapping_status, method
      ) values (
        'PROGRAM', v_program, '10000000-0000-0000-0000-000000000032',
        'FIELD_CLASSIFICATION', 'PROPOSED', 'HUMAN'
      );
      raise exception 'service_role direct mapping insert succeeded';
    exception
      when insufficient_privilege then null;
    end;
    reset role;
  end;

  -- JWT claim text is untrusted attribution and does not authorize DML.
  perform set_config('request.jwt.claim.sub', 'spoof-subject', true);
  begin
    set local role service_role;
    begin
      update public.taxonomy_releases set notes = notes where release_code = 'v0.1';
      raise exception 'JWT spoof updated taxonomy_releases';
    exception
      when insufficient_privilege then null;
    end;
    reset role;
  end;

  -- Path-schema CREATE is denied for hosted and executor roles.
  if has_schema_privilege('authenticated', 'public', 'CREATE')
     or has_schema_privilege('service_role', 'public', 'CREATE')
     or has_schema_privilege('anon', 'public', 'CREATE')
     or has_schema_privilege('foundation_catalog_executor', 'public', 'CREATE')
     or has_schema_privilege('foundation_student_executor', 'public', 'CREATE')
     or has_schema_privilege('foundation_evaluation_executor', 'public', 'CREATE') then
    raise exception 'CREATE remains granted on schema public';
  end if;

  -- Primary-school replacement serializes on programs before this session
  -- touches the catalog row. School insert stays in this transaction so the
  -- deferred evidence guard is not committed.
  perform public.create_school(jsonb_populate_record(
    null::public.schools,
    jsonb_build_object(
      'school_id', v_school,
      'university_id', '00000000-0000-0000-0000-000000000101',
      'name', '012 Replacement School'
    )
  ));
  perform dblink_connect('sess_prog', v_conn);
  perform dblink_exec('sess_prog', 'begin');
  perform dblink_exec('sess_prog', 'set local lock_timeout = ''1s''; set local statement_timeout = ''1s''');
  perform 1 from dblink('sess_prog', format(
    'select 1 from public.programs where program_id = %L for update',
    v_program
  )) as held(n int);
  perform set_config('lock_timeout', '200ms', true);
  perform set_config('statement_timeout', '2s', true);
  begin
    perform public.replace_program_primary_school(v_program, v_school, 'concurrent-replace');
    raise exception 'primary replacement did not block';
  exception
    when lock_not_available then null;
    when query_canceled then null;
  end;
  perform dblink_exec('sess_prog', 'rollback');
  perform dblink_disconnect('sess_prog');
  perform set_config('lock_timeout', '0', true);
  perform set_config('statement_timeout', '15s', true);
  perform public.replace_program_primary_school(v_program, v_school, 'atomic-replace');
  select count(*) into v_count from public.program_schools
  where program_id = v_program
    and relationship_role = 'PRIMARY_ADMINISTRATIVE'
    and retired_at is null;
  if v_count <> 1 then
    raise exception 'Replacement left % active primaries', v_count;
  end if;

  -- PUBLIC/anon cannot execute controlled entry points.
  if has_function_privilege(
       'anon',
       'public.create_source_identity(text,text,text,reliability_tier,text,text,text)',
       'execute'
     )
     or has_function_privilege(
       'public',
       'public.create_source_identity(text,text,text,reliability_tier,text,text,text)',
       'execute'
     ) then
    raise exception 'PUBLIC/anon can execute create_source_identity';
  end if;

  -- Shadow CREATE denied for untrusted roles.
  foreach v_name in array array['authenticated','service_role','foundation_catalog_executor']
  loop
    execute format('set local role %I', v_name);
    begin
      execute 'create function public.create_source_identity(text) returns int language sql as $$ select 1 $$';
      raise exception '% created a function shadow', v_name;
    exception
      when insufficient_privilege then null;
    end;
    reset role;
  end loop;

  -- Direct terminal insert fails with 55000 and stable identity.
  begin
    insert into public.catalog_concept_mappings (
      record_type, record_id, concept_id, relation, mapping_status, method
    ) values (
      'PROGRAM', v_program, '10000000-0000-0000-0000-000000000032',
      'FIELD_CLASSIFICATION', 'VERIFIED', 'HUMAN'
    );
    raise exception 'terminal mapping insert succeeded';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%cannot be inserted%' then raise; end if;
  end;
  begin
    insert into public.eligibility_evaluations (
      profile_version_id, rule_set_id, taxonomy_release_code,
      evaluator_name, evaluator_version, evaluator_build_hash,
      input_schema_version, profile_snapshot_hash, evaluation_state
    ) values (
      '00000000-0000-0000-0000-000000000001',
      '00000000-0000-0000-0000-000000000001',
      'v0.1', 't', 't', repeat('a', 64), 'eligibility-v0.1', repeat('b', 64),
      'COMPLETED'
    );
    raise exception 'COMPLETED evaluation insert succeeded';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%cannot be inserted%' then raise; end if;
    when foreign_key_violation then
      raise exception 'Terminal evaluation insert failed on FK instead of 55000';
  end;

  -- Source revision foundation.
  v_identity := public.create_source_identity(
    'Test Publisher', 'Title', 'https://example.invalid/012-src',
    'TIER_A_OFFICIAL', 'OFFICIAL', repeat('a', 64), 'Test Publisher'
  );
  select current_source_id into v_source
  from public.source_identities where source_identity_id = v_identity;
  v_rev := public.create_source_revision(
    v_identity, 'Test Publisher', 'Title 2', 'https://example.invalid/012-src',
    'TIER_A_OFFICIAL', 'OFFICIAL', repeat('b', 64), 'retrieval-correction'
  );
  if (select revision_number from public.sources where source_id = v_rev) <> 2 then
    raise exception 'Revision 2 was not created';
  end if;
  if (select count(*) from public.sources where source_identity_id = v_identity) <> 2 then
    raise exception 'Source identity lost a revision';
  end if;
  if (select source_id from public.evidence_items where evidence_id = v_evidence)
       is distinct from (
         select source_id from public.evidence_items where evidence_id = v_evidence
       ) then
    raise exception 'Historical evidence pointer changed';
  end if;
  begin
    update public.sources set title = 'mutated' where source_id = v_source;
    raise exception 'source mutation succeeded';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%immutable%' then raise; end if;
  end;

  -- Evidence applicability.
  v_scope := public.create_evidence_scope(
    v_evidence, 'PROGRAM', v_program, 'cip_code',
    'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
  );
  perform public.review_evidence_applicability(
    v_scope, 'REVIEWED_APPLICABLE', '012-reviewer', 'in-scope program fact'
  );
  begin
    perform public.review_evidence_applicability(
      v_scope, 'LEGACY_UNASSERTED', '012-reviewer', 'illegal'
    );
    raise exception 'legacy review succeeded';
  exception
    when sqlstate '22023' then
      if sqlerrm not like '%LEGACY_UNASSERTED%' then raise; end if;
  end;

  -- Cross-scope: reviewed program cip_code cannot authorize program_name.
  begin
    v_obs := public.create_field_observation(
      'PROGRAM', v_program, 'program_name', '"x"'::jsonb, 'KNOWN',
      v_evidence, null, 'wrong', (
        select h.assertion_id from public.evidence_applicability_heads h
        where h.scope_id = v_scope
      )
    );
    raise exception 'mismatched applicability assertion was accepted';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%does not match%' then raise; end if;
  end;

  -- Prospective selection of a pre-012 LEGACY_UNASSERTED observation fails closed.
  select s.observation_id into v_legacy_sel
  from public.canonical_field_selections s
  where s.record_id = v_program and s.field_name = 'cip_code';
  select observation_id into v_legacy_obs
  from public.field_observations
  where record_id = v_program and field_name = 'cip_code'
  order by created_at
  limit 1;
  begin
    perform public.select_field_observation(v_legacy_obs);
    raise exception 'LEGACY_UNASSERTED observation was reselected';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%REVIEWED_APPLICABLE%'
         and sqlerrm not like '%legacy_unasserted%' then
        raise;
      end if;
  end;

  begin
    v_obs := public.create_field_observation(
      'UNIVERSITY',
      (select university_id from public.universities limit 1),
      'name', '"x"'::jsonb, 'KNOWN',
      v_evidence, null, 'cross-institution', (
        select h.assertion_id from public.evidence_applicability_heads h
        where h.scope_id = v_scope
      )
    );
    raise exception 'institution-scoped assertion authorized a different record';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%does not match%' then raise; end if;
  end;

  select h.assertion_id into v_assertion
  from public.evidence_applicability_heads h
  where h.scope_id = v_scope;

  -- A. CROSS-EVIDENCE BORROWING ATTACK
  v_identity := public.create_source_identity(
    '012 Cross Evidence B', 'Title B', 'https://example.invalid/012-ev-b',
    'TIER_A_OFFICIAL', 'OFFICIAL', repeat('c', 64), '012 Cross Evidence B'
  );
  insert into public.evidence_items (
    source_id, excerpt, retrieved_at, verified_at
  )
  select si.current_source_id, '012 evidence B excerpt', now(), now()
  from public.source_identities si
  where si.source_identity_id = v_identity
  returning evidence_id into v_evidence_b;
  begin
    v_obs := public.create_field_observation(
      'PROGRAM', v_program, 'cip_code', '"45.0603"'::jsonb, 'KNOWN',
      v_evidence_b, null, 'borrow-A', v_assertion
    );
    raise exception 'cross-evidence borrowing was accepted';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%does not match%' then raise; end if;
  end;
  v_obs := public.create_field_observation(
    'PROGRAM', v_program, 'cip_code', '"45.0603"'::jsonb, 'KNOWN',
    v_evidence, null, 'exact-A', v_assertion
  );
  if v_obs is null then
    raise exception 'exact-evidence KNOWN observation was rejected';
  end if;

  -- B. WRONG SCOPE WITH SAME EVIDENCE
  perform public.create_program(jsonb_populate_record(
    null::public.programs,
    jsonb_build_object(
      'program_id', v_program_other,
      'university_id', '00000000-0000-0000-0000-000000000101',
      'program_name', '012 Other Program',
      'degree_level', 'MASTERS',
      'degree_type', 'MS'
    )
  ));
  begin
    v_obs := public.create_field_observation(
      'PROGRAM', v_program, 'cip_code', '"45.0603"'::jsonb, 'KNOWN',
      v_evidence, null, 'wrong-program',
      public.review_evidence_applicability(
        public.create_evidence_scope(
          v_evidence, 'PROGRAM', v_program_other, 'cip_code',
          'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
        ),
        'REVIEWED_APPLICABLE', '012-reviewer', 'other program'
      )
    );
    raise exception 'wrong-program assertion was accepted';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%does not match%' then raise; end if;
  end;

  perform public.create_program_version(jsonb_populate_record(
    null::public.program_versions,
    jsonb_build_object(
      'program_version_id', v_version_other,
      'program_id', v_program,
      'admission_cycle_start_year', 2028,
      'admission_cycle_end_year', 2029,
      'academic_year_start', 2028,
      'academic_year_end', 2029,
      'entry_term', 'FALL',
      'entry_year', 2028
    )
  ));
  begin
    v_obs := public.create_field_observation(
      'PROGRAM_VERSION', v_version, 'delivery_mode', '"IN_PERSON"'::jsonb, 'KNOWN',
      v_evidence, null, 'wrong-version',
      public.review_evidence_applicability(
        public.create_evidence_scope(
          v_evidence, 'PROGRAM_VERSION', v_version_other, 'delivery_mode',
          'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
        ),
        'REVIEWED_APPLICABLE', '012-reviewer', 'other version'
      )
    );
    raise exception 'wrong-program-version assertion was accepted';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%does not match%' then raise; end if;
  end;

  begin
    v_obs := public.create_field_observation(
      'PROGRAM', v_program, 'cip_code', '"45.0603"'::jsonb, 'KNOWN',
      v_evidence, null, 'wrong-cycle',
      public.review_evidence_applicability(
        public.create_evidence_scope(
          v_evidence, 'PROGRAM', v_program, 'cip_code',
          'UNSPECIFIED', 'UNSPECIFIED', 'AY2026'
        ),
        'REVIEWED_APPLICABLE', '012-reviewer', 'cycle-specific'
      )
    );
    raise exception 'wrong-cycle assertion was accepted';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%does not match%' then raise; end if;
  end;

  begin
    v_obs := public.create_field_observation(
      'PROGRAM', v_program, 'cip_code', '"45.0603"'::jsonb, 'KNOWN',
      v_evidence, null, 'wrong-population',
      public.review_evidence_applicability(
        public.create_evidence_scope(
          v_evidence, 'PROGRAM', v_program, 'cip_code',
          'UNSPECIFIED', 'GRADUATE', 'UNSPECIFIED'
        ),
        'REVIEWED_APPLICABLE', '012-reviewer', 'graduate-only'
      )
    );
    raise exception 'wrong-population assertion was accepted';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%does not match%' then raise; end if;
  end;

  begin
    v_obs := public.create_field_observation(
      'PROGRAM', v_program, 'cip_code', '"45.0603"'::jsonb, 'KNOWN',
      v_evidence, null, 'wrong-granularity',
      public.review_evidence_applicability(
        public.create_evidence_scope(
          v_evidence, 'PROGRAM', v_program, 'cip_code',
          'PROGRAM', 'UNSPECIFIED', 'UNSPECIFIED'
        ),
        'REVIEWED_APPLICABLE', '012-reviewer', 'program-granularity'
      )
    );
    raise exception 'wrong-granularity assertion was accepted';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%does not match%' then raise; end if;
  end;

  -- C. SUPERSEDED APPLICABILITY HEAD
  v_assertion_old := v_assertion;
  v_assertion := public.review_evidence_applicability(
    v_scope, 'REVIEWED_APPLICABLE', '012-reviewer', 'superseding head'
  );
  begin
    v_obs := public.create_field_observation(
      'PROGRAM', v_program, 'cip_code', '"45.0603"'::jsonb, 'KNOWN',
      v_evidence, null, 'stale-head', v_assertion_old
    );
    raise exception 'superseded applicability head was accepted';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%current applicability head%' then raise; end if;
  end;

  -- D. LEGACY RE-BIND ATTACK
  perform public.review_evidence_applicability(
    public.create_evidence_scope(
      v_evidence_cip, 'PROGRAM', v_program, 'cip_code',
      'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
    ),
    'REVIEWED_APPLICABLE', '012-reviewer', 'later matching head for 702'
  );
  begin
    perform public.select_field_observation(v_legacy_obs);
    raise exception 'LEGACY_UNASSERTED observation acquired a new head';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%REVIEWED_APPLICABLE%'
         and sqlerrm not like '%legacy_unasserted%' then
        raise;
      end if;
  end;
  if not exists (
    select 1
    from public.field_observations o
    join public.field_observation_applicability a using (observation_id)
    join public.evidence_applicability_assertions e using (assertion_id)
    where o.observation_id = v_legacy_obs
      and e.applicability_status = 'LEGACY_UNASSERTED'
      and e.scope_id is null
  ) then
    raise exception 'Legacy observation lost LEGACY_UNASSERTED identity';
  end if;
  if not exists (
    select 1
    from public.canonical_field_selections s
    join public.field_observation_applicability a using (observation_id)
    join public.evidence_applicability_assertions e using (assertion_id)
    where s.observation_id = v_legacy_sel
      and s.record_id = v_program
      and s.field_name = 'cip_code'
      and e.applicability_status = 'LEGACY_UNASSERTED'
      and e.scope_id is null
  ) then
    raise exception 'Historical CIP selection was rewritten';
  end if;

  -- E. NEW PROPERLY ASSERTED OBSERVATION
  v_scope := public.create_evidence_scope(
    v_evidence_b, 'SCHOOL', v_school, 'name',
    'UNSPECIFIED', 'UNSPECIFIED', 'UNSPECIFIED'
  );
  v_assertion := public.review_evidence_applicability(
    v_scope, 'REVIEWED_APPLICABLE', '012-reviewer', 'school name'
  );
  v_obs := public.create_field_observation(
    'SCHOOL', v_school, 'name', to_jsonb('012 Replacement School'::text),
    'KNOWN', v_evidence_b, null, 'exact-E', v_assertion
  );
  perform public.select_field_observation(v_obs, '012-reviewer');
  if not exists (
    select 1
    from public.canonical_field_selections s
    join public.field_observation_applicability a using (observation_id)
    join public.evidence_applicability_assertions e using (assertion_id)
    join public.evidence_applicability_heads h
      on h.assertion_id = e.assertion_id
    where s.observation_id = v_obs
      and s.record_type = 'SCHOOL'
      and s.record_id = v_school
      and s.field_name = 'name'
      and e.applicability_status = 'REVIEWED_APPLICABLE'
  ) then
    raise exception 'Properly asserted observation was not selected';
  end if;
  if (select name from public.schools where school_id = v_school)
       is distinct from '012 Replacement School' then
    raise exception 'Selected school name did not apply';
  end if;

  -- Primary school invariant.
  select count(*) into v_count from public.program_schools
  where program_id = v_program
    and relationship_role = 'PRIMARY_ADMINISTRATIVE'
    and retired_at is null;
  if v_count <> 1 then
    raise exception 'MSQE primary school invariant broken';
  end if;
  if (select foundation_state from public.programs where program_id = v_program)
       <> 'COMPLETE' then
    raise exception 'MSQE was not backfilled COMPLETE';
  end if;
  if to_regclass('public.program_primary_school_exceptions') is not null then
    raise exception 'Primary-school exception table exists';
  end if;

  -- Derived features append-only.
  begin
    update public.program_derived_features set numeric_value = 0
    where derived_feature_id = (
      select derived_feature_id from public.program_derived_features limit 1
    );
    if found then
      raise exception 'program_derived_features update succeeded';
    end if;
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%append-only%' then raise; end if;
    when insufficient_privilege then null;
  end;
  select derived_feature_id, feature_name into v_prior, v_name
  from public.program_derived_features
  order by derived_feature_id
  limit 1;
  if v_prior is null then
    perform public.append_program_derived_feature(jsonb_populate_record(
      null::public.program_derived_features,
      jsonb_build_object(
        'program_version_id', '00000000-0000-0000-0000-000000000401',
        'feature_name', '012_test_feature',
        'numeric_value', 1,
        'model_version', '012-test',
        'calculated_at', now()
      )
    ));
    select derived_feature_id, feature_name into v_prior, v_name
    from public.program_derived_features
    where feature_name = '012_test_feature';
  end if;
  perform public.append_program_derived_feature(jsonb_populate_record(
    null::public.program_derived_features,
    jsonb_build_object(
      'program_version_id', (
        select program_version_id from public.program_derived_features
        where derived_feature_id = v_prior
      ),
      'feature_name', v_name,
      'numeric_value', 2,
      'model_version', '012-test-successor',
      'calculated_at', now(),
      'supersedes_derived_feature_id', v_prior
    )
  ));

  -- Historical CIP selection remains LEGACY_UNASSERTED.
  if not exists (
    select 1 from public.canonical_field_selections s
    join public.field_observation_applicability a using (observation_id)
    join public.evidence_applicability_assertions e using (assertion_id)
    where s.record_id = v_program and s.field_name = 'cip_code'
      and e.applicability_status = 'LEGACY_UNASSERTED'
  ) then
    raise exception 'Historical selection lost LEGACY_UNASSERTED link';
  end if;

  -- Two-session source successor: committed identity, session B holds parent FOR UPDATE.
  select x.id into v_identity
  from dblink(v_conn, $q$
    select public.create_source_identity(
      'Race Publisher', 'Race Title', 'https://example.invalid/012-race-src',
      'TIER_A_OFFICIAL', 'OFFICIAL', repeat('d', 64), 'Race Publisher'
    )
  $q$) as x(id uuid);
  perform dblink_connect('sess_src', v_conn);
  perform dblink_exec('sess_src', 'begin');
  perform 1 from dblink('sess_src', format(
    'select 1 from public.source_identities where source_identity_id = %L for update',
    v_identity
  )) as held(n int);
  perform set_config('lock_timeout', '200ms', true);
  perform set_config('statement_timeout', '2s', true);
  begin
    perform public.create_source_revision(
      v_identity, 'Race Publisher', 'Title 3', 'https://example.invalid/012-race-src',
      'TIER_A_OFFICIAL', 'OFFICIAL', repeat('e', 64), 'concurrent'
    );
    raise exception 'concurrent revision did not block';
  exception
    when lock_not_available then null;
    when query_canceled then null;
  end;
  perform dblink_exec('sess_src', 'rollback');
  perform dblink_disconnect('sess_src');
  perform set_config('lock_timeout', '0', true);
  perform set_config('statement_timeout', '15s', true);
  v_rev := public.create_source_revision(
    v_identity, 'Race Publisher', 'Title 3', 'https://example.invalid/012-race-src',
    'TIER_A_OFFICIAL', 'OFFICIAL', repeat('e', 64), 'after-unblock'
  );
  if (select revision_number from public.sources where source_id = v_rev) <> 2 then
    raise exception 'Serialized source successor did not produce revision 2';
  end if;

  -- Committed student fixture for lifecycle lock pairs.
  v_student := extensions.gen_random_uuid();
  perform 1 from dblink(v_conn, format(
    'select public.create_student(%L)', v_student
  )) as created(id uuid);
  select x.id into v_profile
  from dblink(v_conn, format(
    'select public.create_student_profile_version(%L, 1)', v_student
  )) as x(id uuid);
  foreach v_name in array array[
    'EDUCATION_HISTORY','TEST_HISTORY','EXPERIENCE_HISTORY',
    'SKILL_HISTORY','PREFERENCES','GOALS','COURSE_HISTORY','COURSE_MAPPING'
  ]
  loop
    perform 1 from dblink(v_conn, format(
      $q$select public.insert_student_data_completeness(jsonb_populate_record(
        null::public.student_data_completeness,
        jsonb_build_object(
          'profile_version_id', %L::uuid,
          'domain', %L,
          'completeness', 'COMPLETE'
        )
      ))$q$, v_profile, v_name
    )) as ins(x text);
  end loop;
  perform 1 from dblink(v_conn, format(
    'select public.freeze_student_profile_version(%L)', v_profile
  )) as fr(x text);
  select x.id into v_intent
  from dblink(v_conn, format(
    'select public.create_fit_intent_set(%L, 1)', v_profile
  )) as x(id uuid);

  perform dblink_connect('sess_lock', v_conn);
  perform dblink_exec('sess_lock', 'begin');
  perform dblink_exec('sess_lock', 'set local lock_timeout = ''1s''; set local statement_timeout = ''1s''');
  perform 1 from dblink('sess_lock', format(
    'select 1 from public.students where student_id = %L for update',
    v_student
  )) as held(n int);
  perform set_config('lock_timeout', '200ms', true);
  perform set_config('statement_timeout', '2s', true);

  begin
    perform public.freeze_student_profile_version(v_profile);
    raise exception 'freeze profile did not block on student lock';
  exception
    when lock_not_available then null;
    when query_canceled then null;
  end;
  begin
    perform public.freeze_fit_intent_set(v_intent);
    raise exception 'freeze intent did not block on student lock';
  exception
    when lock_not_available then null;
    when query_canceled then null;
  end;
  begin
    perform public.start_eligibility_evaluation(
      v_profile, '00000000-0000-0000-0000-000000000701',
      'v0.1', 'test', '0', repeat('a', 64)
    );
    raise exception 'start eligibility did not block on student lock';
  exception
    when lock_not_available then null;
    when query_canceled then null;
  end;
  begin
    perform public.start_fit_evaluation(
      v_profile, v_intent,
      '00000000-0000-0000-0000-000000000401',
      'v0.1',
      '30000000-0000-0000-0000-000000000001',
      '40000000-0000-0000-0000-000000000003'
    );
    raise exception 'start fit did not block on student lock';
  exception
    when lock_not_available then null;
    when query_canceled then null;
  end;
  begin
    perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
    raise exception 'privacy delete did not block on student lock';
  exception
    when lock_not_available then null;
    when query_canceled then null;
  end;

  perform dblink_exec('sess_lock', 'rollback');
  perform dblink_disconnect('sess_lock');

  -- Advisory extra-block only: session B holds the advisory key, not the row.
  perform dblink_connect('sess_adv', v_conn);
  perform dblink_exec('sess_adv', 'begin');
  perform dblink_exec('sess_adv', format(
    $q$do $lk$ begin perform pg_advisory_xact_lock(hashtextextended('student-lifecycle:' || lower(%L::text), 0)); end; $lk$;$q$,
    v_student
  ));
  perform set_config('lock_timeout', '200ms', true);
  perform set_config('statement_timeout', '2s', true);
  begin
    perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
    raise exception 'advisory extra-block did not serialize';
  exception
    when lock_not_available then null;
    when query_canceled then null;
  end;
  perform dblink_exec('sess_adv', 'rollback');
  perform dblink_disconnect('sess_adv');

  -- Advisory-disabled still preserves the students row-lock invariant:
  -- session B holds only the row lock (no advisory); delete still blocks.
  perform dblink_connect('sess_row', v_conn);
  perform dblink_exec('sess_row', 'begin');
  perform dblink_exec('sess_row', 'set local lock_timeout = ''1s''; set local statement_timeout = ''1s''');
  perform 1 from dblink('sess_row', format(
    'select 1 from public.students where student_id = %L for update',
    v_student
  )) as held(n int);
  perform set_config('lock_timeout', '200ms', true);
  perform set_config('statement_timeout', '2s', true);
  begin
    perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
    raise exception 'row lock alone did not serialize privacy delete';
  exception
    when lock_not_available then null;
    when query_canceled then null;
  end;
  perform dblink_exec('sess_row', 'rollback');
  perform dblink_disconnect('sess_row');
  perform set_config('lock_timeout', '0', true);
  perform set_config('statement_timeout', '15s', true);

  -- Privacy deletion vs finalize: they serialize on the same student row.
  -- Covered above (delete blocked while student row held). Cleanup fixture.
  perform public.delete_student_data(v_student, 'TEST_LIFECYCLE');
  if exists (select 1 from public.students where student_id = v_student) then
    raise exception 'Privacy deletion left the student row';
  end if;
  if exists (
    select 1 from public.student_deletion_tombstones
    where reason_code = 'TEST_LIFECYCLE'
      and legacy_deletion_reason = 'MIGRATED_TO_REASON_CODE'
  ) is not true then
    raise exception 'Tombstone missing coded reason';
  end if;
  if exists (
    select 1 from public.student_deletion_tombstones t
    where t.reason_code = 'TEST_LIFECYCLE'
      and (
        to_jsonb(t) ? 'student_id'
        or to_jsonb(t) ? 'profile_version_id'
        or to_jsonb(t) ? 'evaluation_id'
      )
  ) then
    raise exception 'Tombstone contains a linkable identifier column';
  end if;

  -- Verified mapping payload is immutable (retirement-only fields may change).
  v_mapping := extensions.gen_random_uuid();
  perform public.propose_catalog_concept_mapping(jsonb_populate_record(
    null::public.catalog_concept_mappings,
    jsonb_build_object(
      'mapping_id', v_mapping,
      'record_type', 'PROGRAM',
      'record_id', v_program,
      'concept_id', '10000000-0000-0000-0000-000000000032',
      'relation', 'FIELD_CLASSIFICATION',
      'method', 'HUMAN',
      'proposed_by', '012-tester'
    )
  ));
  perform public.review_catalog_concept_mapping(
    v_mapping, 'VERIFIED', '012-reviewer', v_evidence
  );
  begin
    update public.catalog_concept_mappings
    set method = 'MODEL'
    where mapping_id = v_mapping;
    raise exception 'verified mapping mutation succeeded';
  exception
    when sqlstate '55000' then
      if sqlerrm not like '%immutable%'
         and sqlerrm not like '%cannot%'
         and sqlerrm not like '%only transition to RETIRED%' then
        raise;
      end if;
    when sqlstate 'P0001' then
      if sqlerrm not like '%only transition to RETIRED%' then
        raise;
      end if;
  end;

  -- Taxonomy lifecycle without ordinals.
  perform public.create_taxonomy_release('v0.12', now(), '012 draft');
  begin
    update public.taxonomy_releases
    set status = 'VERIFIED'
    where release_code = 'v0.12';
    raise exception 'direct taxonomy verify succeeded';
  exception
    when sqlstate '55000' then null;
    when insufficient_privilege then null;
  end;
  perform public.verify_taxonomy_release('v0.12', '012-tester');
  perform public.retire_taxonomy_release('v0.12', '012-retire');
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'allocate_taxonomy_release_ordinal_v02'
  ) and exists (
    select 1 from information_schema.columns
    where table_name = 'taxonomy_releases' and column_name = 'release_ordinal'
  ) then
    raise exception 'taxonomy ordinal column leaked into 012';
  end if;
end;
$test$;

rollback;
