\set ON_ERROR_STOP on
set search_path = public, private, extensions, pg_catalog;

-- Disposable multi-session probe. Run last on a disposable database.
create extension if not exists dblink;

do $fixture$
declare
  v_concept uuid;
  v_identity uuid;
  v_source uuid;
  v_evidence uuid;
  v_first uuid;
  v_second uuid;
  v_role public.profile_assessment_evidence_role_v024;
begin
  select concept_id into strict v_concept
  from public.taxonomy_concepts
  where canonical_key = 'ASSESSMENT.TOEFL';
  execute 'set local role foundation_catalog_executor';
  v_identity := public.create_source_identity(
    'Phase 024 Concurrency Fixture', 'Synthetic definition authority',
    'https://test.invalid/phase024-concurrency',
    'TIER_A_OFFICIAL', 'TEST_FIXTURE', repeat('c', 64),
    'Phase 024 Concurrency Fixture'
  );
  select current_source_id into strict v_source
  from public.source_identities where source_identity_id = v_identity;
  insert into public.evidence_items (
    source_id, excerpt, locator, cycle_context,
    retrieved_at, verified_at, content_hash
  ) values (
    v_source, 'Synthetic concurrency fixture.', 'fixture',
    'PHASE024_CONCURRENCY', now(), now(), repeat('d', 64)
  ) returning evidence_id into v_evidence;

  v_first := public.create_profile_assessment_definition_v024(
    v_concept, 101::bigint, 'SYNTHETIC_RACE', 'v0.1',
    '2000-01-01'::date, '2030-12-31'::date,
    0, 100, 1, 0::smallint, null
  );
  v_second := public.create_profile_assessment_definition_v024(
    v_concept, 102::bigint, 'SYNTHETIC_RACE', 'v0.1',
    '2020-01-01'::date, null, 0, 100, 1, 0::smallint, null
  );
  foreach v_role in array enum_range(
    null::public.profile_assessment_evidence_role_v024
  ) loop
    perform public.add_profile_assessment_evidence_v024(
      v_first, v_role, v_evidence
    );
    perform public.add_profile_assessment_evidence_v024(
      v_second, v_role, v_evidence
    );
  end loop;
  perform public.add_profile_assessment_score_shape_v024(
    v_first, 'TOTAL_ONLY'
  );
  perform public.add_profile_assessment_score_shape_v024(
    v_second, 'TOTAL_ONLY'
  );
  perform set_config('phase024.first', v_first::text, false);
  perform set_config('phase024.second', v_second::text, false);
  execute 'reset role';
end;
$fixture$;

do $race$
declare
  v_conn text := 'dbname=' || current_database();
  v_first uuid := current_setting('phase024.first')::uuid;
  v_second uuid := current_setting('phase024.second')::uuid;
  v_first_result text;
  v_second_blocked boolean := false;
begin
  perform dblink_connect('p24_first', v_conn);
  perform dblink_connect('p24_second', v_conn);
  perform dblink_exec('p24_first', 'begin');
  perform dblink_exec('p24_second', 'begin');
  perform dblink_exec(
    'p24_first', 'set local role foundation_catalog_executor'
  );
  perform dblink_exec(
    'p24_second', 'set local role foundation_catalog_executor'
  );
  perform dblink_send_query('p24_first', format(
    $$select public.verify_profile_assessment_definition_v024(
      %L, 'PHASE024_RACE_FIRST'
    )$$, v_first
  ));
  perform pg_sleep(0.1);
  perform dblink_send_query('p24_second', format(
    $$select public.verify_profile_assessment_definition_v024(
      %L, 'PHASE024_RACE_SECOND'
    )$$, v_second
  ));
  perform pg_sleep(0.2);
  if dblink_is_busy('p24_second') <> 1 then
    raise exception '024 concurrent definition verification did not serialize';
  end if;
  select result into v_first_result
  from dblink_get_result('p24_first') as result(result text);
  perform count(*)
  from dblink_get_result('p24_first') as result(result text);
  perform dblink_exec('p24_first', 'commit');
  begin
    perform count(*)
    from dblink_get_result('p24_second') as result(result text);
  exception when others then
    v_second_blocked :=
      sqlerrm like '%PROFILE_ASSESSMENT_DEFINITION_AMBIGUOUS%';
  end;
  perform count(*)
  from dblink_get_result('p24_second') as result(result text);
  perform dblink_exec('p24_second', 'rollback');
  perform dblink_disconnect('p24_first');
  perform dblink_disconnect('p24_second');

  if not v_second_blocked
     or v_first_result !~ '^[a-f0-9]{64}$'
     or (select count(*)
         from public.profile_assessment_definitions_v024 definition
         where definition.assessment_definition_id in (v_first, v_second)
           and definition.status = 'VERIFIED') <> 1 then
    raise exception '024 concurrent verification failed closed-world policy';
  end if;
end;
$race$;
