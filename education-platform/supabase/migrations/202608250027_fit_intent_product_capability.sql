-- Phase 4B: real-student Fit Intent product capability core.
--
-- This migration is additive over the frozen Fit v0.1 contract. It adds a
-- product authoring/lifecycle boundary, but does not change Fit dimensions,
-- truth tables, evaluator identity, fingerprint algorithms, Financial
-- semantics, or Eligibility semantics.

begin;

create type public.fit_intent_product_dimension_state_v027 as enum (
  'UNANSWERED',
  'DECLARED',
  'EXPLICIT_NOT_SUPPLIED'
);

create type public.fit_intent_product_command_v027 as enum (
  'DECLARATION_CREATE',
  'DECLARATION_REPLACE',
  'DECLARATION_DELETE',
  'DIMENSION_MARK_NOT_SUPPLIED',
  'ACCESS_CONTEXT_REPLACE',
  'ACCESS_CONTEXT_DELETE'
);

create type public.fit_intent_student_assertion_kind_v027 as enum (
  'INTENT_DECLARATION',
  'ACCESS_CONTEXT'
);

create table private.fit_intent_product_states_v027 (
  intent_set_id uuid primary key,
  profile_version_id uuid not null,
  intent_revision bigint not null default 0,
  taxonomy_release_code text not null,
  taxonomy_release_ordinal bigint not null,
  active_draft boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (intent_set_id, profile_version_id)
    references public.fit_intent_sets(intent_set_id, profile_version_id)
    on delete cascade,
  foreign key (taxonomy_release_code)
    references public.taxonomy_releases(release_code) on delete restrict,
  foreign key (taxonomy_release_ordinal)
    references public.taxonomy_releases(release_ordinal) on delete restrict,
  constraint fit_intent_product_revision_v027
    check (intent_revision >= 0),
  unique (intent_set_id, profile_version_id)
);

create unique index fit_intent_one_product_draft_v027
  on private.fit_intent_product_states_v027(profile_version_id)
  where active_draft;

create table private.fit_intent_dimension_states_v027 (
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  dimension public.fit_dimension not null,
  disposition public.fit_intent_product_dimension_state_v027 not null
    default 'UNANSWERED',
  updated_at timestamptz not null default now(),
  primary key (intent_set_id, dimension),
  foreign key (intent_set_id, profile_version_id)
    references private.fit_intent_product_states_v027(
      intent_set_id, profile_version_id
    ) on delete cascade
);

create table private.fit_intent_student_assertions_v027 (
  assertion_id uuid primary key default extensions.gen_random_uuid(),
  intent_set_id uuid not null,
  profile_version_id uuid not null,
  assertion_kind public.fit_intent_student_assertion_kind_v027 not null,
  dimension public.fit_dimension,
  semantic_payload_hash text not null,
  required_importance_confirmed boolean not null default false,
  created_at timestamptz not null default now(),
  foreign key (intent_set_id, profile_version_id)
    references private.fit_intent_product_states_v027(
      intent_set_id, profile_version_id
    ) on delete cascade,
  constraint fit_intent_assertion_hash_v027
    check (semantic_payload_hash ~ '^[a-f0-9]{64}$'),
  constraint fit_intent_assertion_shape_v027 check (
    (assertion_kind = 'INTENT_DECLARATION' and dimension is not null)
    or (assertion_kind = 'ACCESS_CONTEXT'
      and dimension = 'INTERNATIONAL_ACCESSIBILITY')
  ),
  unique (assertion_id, intent_set_id, profile_version_id)
);

create table private.fit_intent_operations_v027 (
  student_id uuid not null
    references public.students(student_id) on delete cascade,
  operation_id uuid not null,
  operation_kind text not null,
  command_code text,
  request_fingerprint text not null,
  result_document jsonb not null,
  created_at timestamptz not null default now(),
  primary key (student_id, operation_id),
  constraint fit_intent_operation_kind_v027 check (
    operation_kind in ('CREATE_OR_RESUME', 'MUTATE', 'FREEZE')
  ),
  constraint fit_intent_operation_fingerprint_v027
    check (request_fingerprint ~ '^[a-f0-9]{64}$'),
  constraint fit_intent_operation_result_v027
    check (jsonb_typeof(result_document) = 'object')
);

alter table public.fit_intent_declarations
  add column student_assertion_id uuid;

alter table private.fit_student_access_contexts
  alter column student_evidence_id drop not null,
  add column student_assertion_id uuid;

alter table public.fit_intent_declarations
  add foreign key (
    student_assertion_id, intent_set_id, profile_version_id
  ) references private.fit_intent_student_assertions_v027(
    assertion_id, intent_set_id, profile_version_id
  ) on delete no action deferrable initially immediate;

alter table private.fit_student_access_contexts
  add foreign key (
    student_assertion_id, intent_set_id, profile_version_id
  ) references private.fit_intent_student_assertions_v027(
    assertion_id, intent_set_id, profile_version_id
  ) on delete no action deferrable initially immediate;

alter table public.fit_intent_declarations
  drop constraint fit_intent_declarations_origin_shape,
  add constraint fit_intent_declarations_origin_shape check (
    (
      origin = 'PHASE2_INTERPRETATION'
      and (
        (source_student_goal_id is not null)::integer
        + (source_student_preference_id is not null)::integer
      ) = 1
      and student_assertion_id is null
    )
    or (
      origin = 'PHASE3_DECLARATION'
      and source_student_goal_id is null
      and source_student_preference_id is null
      and (
        (student_evidence_id is not null)::integer
        + (student_assertion_id is not null)::integer
      ) = 1
    )
  ),
  drop constraint fit_intent_required_authority,
  add constraint fit_intent_required_authority check (
    importance <> 'REQUIRED'
    or (
      importance_basis in (
        'STRUCTURED_STUDENT_DECLARATION',
        'NORMALIZED_STUDENT_LANGUAGE'
      )
      and (
        importance_evidence_id is not null
        or student_assertion_id is not null
      )
    )
  );

alter table private.fit_student_access_contexts
  add constraint fit_student_access_context_provenance_v027 check (
    (
      (student_evidence_id is not null)::integer
      + (student_assertion_id is not null)::integer
    ) = 1
  );

create unique index fit_intent_product_access_singleton_v027
  on private.fit_student_access_contexts(intent_set_id)
  where student_assertion_id is not null;

create or replace function private.fit_intent_student_for_auth_v027()
returns uuid
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  select identity.student_id
  from private.student_identities identity
  join public.students student using (student_id)
  where identity.auth_user_id = private.profile_request_auth_subject_v021()
    and student.privacy_state = 'ACTIVE'
$function$;

create or replace function private.fit_intent_assert_payload_keys_v027(
  p_payload jsonb,
  p_allowed text[],
  p_required text[]
)
returns void
language plpgsql
immutable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_key text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_PAYLOAD_INVALID';
  end if;
  for v_key in select jsonb_object_keys(p_payload)
  loop
    if not (v_key = any(p_allowed)) then
      raise exception using errcode = '22023',
        message = 'FIT_INTENT_PAYLOAD_KEY_FORBIDDEN';
    end if;
  end loop;
  if exists (
    select 1 from unnest(p_required) required_key
    where not p_payload ? required_key
  ) then
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_PAYLOAD_KEY_REQUIRED';
  end if;
end;
$function$;

-- Product lifecycle RPCs accept no caller-supplied student identity. Ownership
-- is derived from the trusted M021 request subject and rechecked transactionally.
create or replace function public.create_or_resume_fit_intent_draft_v027(
  p_profile_version_id uuid,
  p_operation_id uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_intent_set_id uuid;
  v_version_number integer;
  v_release_code text;
  v_release_ordinal bigint;
  v_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
begin
  if p_profile_version_id is null or p_operation_id is null then
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_CREATE_ARGUMENT_REQUIRED';
  end if;
  v_student_id := private.fit_intent_student_for_auth_v027();
  if v_student_id is null then
    raise exception using errcode = 'P0002',
      message = 'FIT_INTENT_PROFILE_NOT_FOUND';
  end if;
  perform private.lock_student_lifecycle(v_student_id);
  perform private.lock_student_owned_total_order(v_student_id);
  if not exists (
    select 1 from public.student_profile_versions profile
    where profile.profile_version_id = p_profile_version_id
      and profile.student_id = v_student_id
      and profile.status = 'FROZEN'
  ) then
    raise exception using errcode = 'P0002',
      message = 'FIT_INTENT_PROFILE_NOT_FOUND';
  end if;
  v_fingerprint := private.fit_intent_request_fingerprint_v027(
    jsonb_build_object(
      'operation', 'CREATE_OR_RESUME',
      'profileVersionId', p_profile_version_id
    )
  );
  v_replay := private.fit_intent_replay_operation_v027(
    v_student_id, p_operation_id, 'CREATE_OR_RESUME', null, v_fingerprint
  );
  if v_replay is not null then
    return v_replay;
  end if;
  select state.intent_set_id, intent.version_number
  into v_intent_set_id, v_version_number
  from private.fit_intent_product_states_v027 state
  join public.fit_intent_sets intent
    using(intent_set_id, profile_version_id)
  where state.profile_version_id = p_profile_version_id
    and state.active_draft and intent.status = 'DRAFT'
  for update of state, intent;
  if v_intent_set_id is null then
    select release.release_code, release.release_ordinal
    into v_release_code, v_release_ordinal
    from public.taxonomy_releases release
    where release.status = 'VERIFIED'
    order by release.release_ordinal desc,
      release.release_code collate "C" desc limit 1;
    if v_release_code is null then
      raise exception using errcode = '55000',
        message = 'FIT_INTENT_VERIFIED_TAXONOMY_REQUIRED';
    end if;
    select coalesce(max(intent.version_number), 0) + 1
    into v_version_number
    from public.fit_intent_sets intent
    where intent.profile_version_id = p_profile_version_id;
    insert into public.fit_intent_sets (profile_version_id, version_number)
    values (p_profile_version_id, v_version_number)
    returning intent_set_id into v_intent_set_id;
    insert into private.fit_intent_product_states_v027 (
      intent_set_id, profile_version_id, taxonomy_release_code,
      taxonomy_release_ordinal
    ) values (
      v_intent_set_id, p_profile_version_id, v_release_code,
      v_release_ordinal
    );
    insert into private.fit_intent_dimension_states_v027 (
      intent_set_id, profile_version_id, dimension
    )
    select v_intent_set_id, p_profile_version_id, dimension
    from unnest(enum_range(null::public.fit_dimension)) dimension;
  end if;
  v_result := jsonb_build_object(
    'schemaVersion', 'FIT_INTENT_OPERATION_RESULT_V027',
    'operation', 'CREATE_OR_RESUME',
    'intentSetId', v_intent_set_id,
    'profileVersionId', p_profile_version_id,
    'versionNumber', v_version_number,
    'status', 'DRAFT',
    'revision', (
      select state.intent_revision
      from private.fit_intent_product_states_v027 state
      where state.intent_set_id = v_intent_set_id
    )
  );
  perform private.fit_intent_store_operation_v027(
    v_student_id, p_operation_id, 'CREATE_OR_RESUME', null,
    v_fingerprint, v_result
  );
  return v_result;
end;
$function$;

create or replace function public.get_fit_intent_document_v027(
  p_intent_set_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
begin
  v_student_id := private.fit_intent_student_for_auth_v027();
  if v_student_id is null or not exists (
    select 1 from public.fit_intent_sets intent
    join public.student_profile_versions profile using(profile_version_id)
    join private.fit_intent_product_states_v027 state
      using(intent_set_id, profile_version_id)
    where intent.intent_set_id = p_intent_set_id
      and profile.student_id = v_student_id
  ) then
    raise exception using errcode = 'P0002', message = 'FIT_INTENT_NOT_FOUND';
  end if;
  return private.fit_intent_document_v027(p_intent_set_id);
end;
$function$;

create or replace function public.discover_fit_intent_v027(
  p_profile_version_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_draft_id uuid;
  v_frozen_id uuid;
begin
  v_student_id := private.fit_intent_student_for_auth_v027();
  if v_student_id is null or not exists (
    select 1 from public.student_profile_versions profile
    where profile.profile_version_id = p_profile_version_id
      and profile.student_id = v_student_id
  ) then
    raise exception using errcode = 'P0002',
      message = 'FIT_INTENT_PROFILE_NOT_FOUND';
  end if;
  select intent.intent_set_id into v_draft_id
  from public.fit_intent_sets intent
  join private.fit_intent_product_states_v027 state
    using(intent_set_id, profile_version_id)
  where intent.profile_version_id = p_profile_version_id
    and intent.status = 'DRAFT' and state.active_draft
  order by intent.version_number desc limit 1;
  select intent.intent_set_id into v_frozen_id
  from public.fit_intent_sets intent
  join private.fit_intent_product_states_v027 state
    using(intent_set_id, profile_version_id)
  where intent.profile_version_id = p_profile_version_id
    and intent.status = 'FROZEN' and not state.active_draft
  order by intent.version_number desc limit 1;
  return jsonb_build_object(
    'schemaVersion', 'FIT_INTENT_DISCOVERY_V027',
    'profileVersionId', p_profile_version_id,
    'activeDraft', case when v_draft_id is null then null
      else private.fit_intent_document_v027(v_draft_id) end,
    'latestFrozen', case when v_frozen_id is null then null
      else private.fit_intent_document_v027(v_frozen_id) end
  );
end;
$function$;

create or replace function private.fit_intent_request_fingerprint_v027(
  p_request jsonb
)
returns text
language sql
immutable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  select encode(
    extensions.digest(convert_to(p_request::text, 'UTF8'), 'sha256'),
    'hex'
  )
$function$;

create or replace function private.fit_intent_replay_operation_v027(
  p_student_id uuid,
  p_operation_id uuid,
  p_operation_kind text,
  p_command_code text,
  p_request_fingerprint text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_operation private.fit_intent_operations_v027%rowtype;
begin
  select * into v_operation
  from private.fit_intent_operations_v027 operation
  where operation.student_id = p_student_id
    and operation.operation_id = p_operation_id;
  if not found then
    return null;
  end if;
  if v_operation.operation_kind is distinct from p_operation_kind
     or v_operation.command_code is distinct from p_command_code
     or v_operation.request_fingerprint is distinct from p_request_fingerprint then
    raise exception using errcode = '23505',
      message = 'FIT_INTENT_OPERATION_CONFLICT';
  end if;
  return v_operation.result_document;
end;
$function$;

create or replace function private.fit_intent_store_operation_v027(
  p_student_id uuid,
  p_operation_id uuid,
  p_operation_kind text,
  p_command_code text,
  p_request_fingerprint text,
  p_result_document jsonb
)
returns void
language sql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  insert into private.fit_intent_operations_v027 (
    student_id, operation_id, operation_kind, command_code,
    request_fingerprint, result_document
  ) values (
    p_student_id, p_operation_id, p_operation_kind, p_command_code,
    p_request_fingerprint, p_result_document
  )
$function$;

create or replace function private.guard_fit_intent_product_write_v027()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_intent_set_id uuid;
begin
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

create or replace function private.guard_fit_intent_product_freeze_v027()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
begin
  if exists (
    select 1 from private.fit_intent_product_states_v027 state
    where state.intent_set_id = new.intent_set_id
  ) and (
    new.status is distinct from old.status
    or new.snapshot_hash is distinct from old.snapshot_hash
    or new.frozen_at is distinct from old.frozen_at
  ) and current_setting('app.fit_intent_product_v027_write', true)
        is distinct from 'on' then
    raise exception using errcode = '42501',
      message = 'FIT_INTENT_PRODUCT_FREEZE_REQUIRED';
  end if;
  return new;
end;
$function$;

create trigger fit_intent_product_set_freeze_guard_v027
before update of status, snapshot_hash, frozen_at
on public.fit_intent_sets
for each row execute function private.guard_fit_intent_product_freeze_v027();

do $triggers$
declare
  v_table text;
begin
  foreach v_table in array array[
    'fit_intent_declarations',
    'fit_intent_taxonomy_targets',
    'fit_intent_location_constraints',
    'fit_intent_delivery_constraints',
    'fit_intent_financial_constraints',
    'fit_intent_duration_constraints',
    'fit_intent_program_feature_constraints'
  ]
  loop
    execute format(
      'create trigger %I before insert or update or delete on public.%I for each row execute function private.guard_fit_intent_product_write_v027()',
      v_table || '_product_guard_v027', v_table
    );
  end loop;
end;
$triggers$;

create trigger fit_student_access_context_product_guard_v027
before insert or update or delete on private.fit_student_access_contexts
for each row execute function private.guard_fit_intent_product_write_v027();

create or replace function private.fit_intent_typed_value_v027(
  p_declaration_id uuid,
  p_semantic_type text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_value jsonb;
begin
  case p_semantic_type
    when 'TAXONOMY_TARGET' then
      select jsonb_build_object(
        'conceptId', child.concept_id,
        'relation', child.relation
      ) into v_value
      from public.fit_intent_taxonomy_targets child
      where child.intent_declaration_id = p_declaration_id;
    when 'DELIVERY_CONSTRAINT' then
      select jsonb_build_object(
        'deliveryMode', child.delivery_mode,
        'relation', child.relation
      ) into v_value
      from public.fit_intent_delivery_constraints child
      where child.intent_declaration_id = p_declaration_id;
    when 'FINANCIAL_CONSTRAINT' then
      select jsonb_build_object(
        'amount', child.amount,
        'constraintSemantics', child.constraint_semantics,
        'currency', btrim(child.currency),
        'scope', child.financial_scope,
        'period', child.financial_period,
        'basis', child.financial_basis,
        'components', to_jsonb(child.components)
      ) into v_value
      from public.fit_intent_financial_constraints child
      where child.intent_declaration_id = p_declaration_id;
    when 'DURATION_CONSTRAINT' then
      select jsonb_build_object(
        'minimumMonths', child.minimum_months,
        'maximumMonths', child.maximum_months
      ) into v_value
      from public.fit_intent_duration_constraints child
      where child.intent_declaration_id = p_declaration_id;
    when 'PROGRAM_FEATURE_CONSTRAINT' then
      select jsonb_build_object(
        'featureKey', child.feature_key,
        'expected', child.expected
      ) into v_value
      from public.fit_intent_program_feature_constraints child
      where child.intent_declaration_id = p_declaration_id;
    else
      raise exception using errcode = '22023',
        message = 'FIT_INTENT_SEMANTIC_TYPE_UNSUPPORTED';
  end case;
  if v_value is null then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_TYPED_CHILD_REQUIRED';
  end if;
  return v_value;
end;
$function$;

create or replace function private.fit_intent_document_v027(
  p_intent_set_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  select jsonb_build_object(
    'schemaVersion', 'FIT_INTENT_DOCUMENT_V027',
    'intentSetId', intent.intent_set_id,
    'profileVersionId', intent.profile_version_id,
    'versionNumber', intent.version_number,
    'status', intent.status,
    'revision', product.intent_revision,
    'snapshotHash', intent.snapshot_hash,
    'taxonomyRelease', jsonb_build_object(
      'releaseCode', product.taxonomy_release_code,
      'releaseOrdinal', product.taxonomy_release_ordinal
    ),
    'dimensions', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'dimension', state.dimension,
          'state', state.disposition
        ) order by state.dimension
      )
      from private.fit_intent_dimension_states_v027 state
      where state.intent_set_id = intent.intent_set_id
    ), '[]'::jsonb),
    'declarations', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'declarationId', declaration.intent_declaration_id,
          'dimension', declaration.dimension,
          'semanticType', declaration.semantic_type,
          'importance', declaration.importance,
          'importanceConfirmedByStudent',
            declaration.importance_confirmed_by_student,
          'provenance', 'SELF_ASSERTED',
          'typedValue', private.fit_intent_typed_value_v027(
            declaration.intent_declaration_id,
            declaration.semantic_type
          )
        ) order by declaration.dimension,
          declaration.intent_declaration_id
      )
      from public.fit_intent_declarations declaration
      where declaration.intent_set_id = intent.intent_set_id
        and declaration.student_assertion_id is not null
    ), '[]'::jsonb),
    'accessContext', (
      select jsonb_build_object(
        'accessContextId', context.access_context_id,
        'citizenshipCountryCode', context.citizenship_country_code,
        'residenceCountryCode', context.residence_country_code,
        'jurisdictionCode', context.governing_jurisdiction_code,
        'currentStatusCode', context.current_status_code,
        'authorizationPathCode', context.authorization_path_code,
        'targetPathCode', context.target_path_code,
        'provenance', 'SELF_ASSERTED'
      )
      from private.fit_student_access_contexts context
      where context.intent_set_id = intent.intent_set_id
        and context.student_assertion_id is not null
    )
  )
  from public.fit_intent_sets intent
  join private.fit_intent_product_states_v027 product
    using(intent_set_id, profile_version_id)
  where intent.intent_set_id = p_intent_set_id
$function$;

create or replace function private.fit_intent_require_taxonomy_v027(
  p_intent_set_id uuid,
  p_dimension public.fit_dimension,
  p_concept_id uuid
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_release bigint;
  v_kind public.taxonomy_concept_kind;
  v_covered boolean;
begin
  select product.taxonomy_release_ordinal into v_release
  from private.fit_intent_product_states_v027 product
  where product.intent_set_id = p_intent_set_id;
  select concept.concept_kind into v_kind
  from public.taxonomy_concepts concept
  where concept.concept_id = p_concept_id
    and concept.introduced_release_ordinal <= v_release
    and (
      concept.retired_release_ordinal is null
      or concept.retired_release_ordinal > v_release
    );
  if v_kind is null then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_TAXONOMY_CONCEPT_INACTIVE';
  end if;
  if (p_dimension = 'ACADEMIC'
      and v_kind not in ('FIELD','SUBFIELD','SUBJECT','COURSE_CONCEPT'))
     or (p_dimension = 'CAREER' and v_kind not in ('CAREER','INDUSTRY'))
     or (p_dimension = 'INTERNATIONAL_ACCESSIBILITY'
         and v_kind <> 'CAREER')
     or p_dimension not in (
       'ACADEMIC','CAREER','INTERNATIONAL_ACCESSIBILITY'
     ) then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_TAXONOMY_KIND_FORBIDDEN';
  end if;

  select case p_dimension
    when 'ACADEMIC' then exists (
      select 1 from public.catalog_concept_mappings mapping
      where mapping.concept_id = p_concept_id
        and mapping.mapping_status = 'VERIFIED'
        and mapping.retired_at is null
        and mapping.relation in (
          'FIELD_CLASSIFICATION','SUBFIELD_CLASSIFICATION',
          'SUBJECT_CLASSIFICATION','COURSE_EQUIVALENCY'
        )
    )
    when 'CAREER' then exists (
      select 1 from public.catalog_concept_mappings mapping
      where mapping.concept_id = p_concept_id
        and mapping.mapping_status = 'VERIFIED'
        and mapping.retired_at is null
        and mapping.relation in ('CAREER_ASSOCIATION','INDUSTRY_ASSOCIATION')
      union all
      select 1 from public.fit_context_concept_mappings mapping
      where mapping.concept_id = p_concept_id
        and mapping.mapping_status = 'VERIFIED'
        and mapping.retired_at is null
        and mapping.relation_code = 'PROGRAM_RELATED_TO_CAREER'
    )
    when 'INTERNATIONAL_ACCESSIBILITY' then exists (
      select 1 from public.fit_context_concept_mappings mapping
      where mapping.concept_id = p_concept_id
        and mapping.mapping_status = 'VERIFIED'
        and mapping.retired_at is null
        and mapping.relation_code in (
          'PROGRAM_ASSOCIATED_WITH_PATH','CLAIM_APPLIES_TO_CONCEPT'
        )
    )
    else false
  end into v_covered;
  if not coalesce(v_covered, false) then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_TAXONOMY_COVERAGE_UNAVAILABLE';
  end if;
end;
$function$;

create or replace function private.fit_intent_require_access_option_v027(
  p_jurisdiction_code text,
  p_target_path_code text
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
begin
  if p_jurisdiction_code is null or p_target_path_code is null
     or not exists (
       select 1
       from public.fit_context_claims claim
       join public.fit_context_claim_definitions definition
         on definition.claim_definition_id = claim.claim_definition_id
        and definition.definition_version = claim.definition_version
       join public.fit_context_claim_selections selection
         using(context_claim_id)
       join public.fit_context_claim_observations observation
         on observation.context_observation_id =
            selection.context_observation_id
       where claim.jurisdiction_code = p_jurisdiction_code
         and claim.path_code = p_target_path_code
         and definition.claim_code in (
           'REGULATORY_WORK_AUTHORIZATION',
           'JURISDICTION_PATH_ACCESSIBILITY'
         )
         and claim.valid_from <= current_date
         and (claim.valid_to is null or claim.valid_to >= current_date)
         and definition.status = 'VERIFIED'
         and definition.retired_at is null
         and selection.knowledge_status = 'KNOWN'
         and observation.workflow_status = 'VERIFIED'
         and observation.retired_at is null
         and observation.authority = 'OFFICIAL_REGULATORY'
     ) then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_ACCESS_OPTION_UNAVAILABLE';
  end if;
end;
$function$;

create or replace function private.fit_intent_write_declaration_v027(
  p_intent_set_id uuid,
  p_profile_version_id uuid,
  p_declaration_id uuid,
  p_payload jsonb
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_dimension public.fit_dimension;
  v_semantic_type text;
  v_importance public.fit_importance;
  v_confirmed boolean;
  v_typed jsonb;
  v_assertion_id uuid;
  v_old_assertion_id uuid;
  v_existing public.fit_intent_declarations%rowtype;
  v_components text[];
  v_declaration_id uuid := coalesce(
    p_declaration_id, extensions.gen_random_uuid()
  );
begin
  perform private.fit_intent_assert_payload_keys_v027(
    p_payload,
    array[
      'dimension','semanticType','importance',
      'importanceConfirmedByStudent','typedValue'
    ],
    array[
      'dimension','semanticType','importance',
      'importanceConfirmedByStudent','typedValue'
    ]
  );
  v_dimension := (p_payload ->> 'dimension')::public.fit_dimension;
  v_semantic_type := p_payload ->> 'semanticType';
  v_importance := (p_payload ->> 'importance')::public.fit_importance;
  v_confirmed := (p_payload ->> 'importanceConfirmedByStudent')::boolean;
  v_typed := p_payload -> 'typedValue';
  if jsonb_typeof(v_typed) <> 'object' then
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_TYPED_VALUE_INVALID';
  end if;
  if v_importance = 'REQUIRED' and not v_confirmed then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_REQUIRED_CONFIRMATION_REQUIRED';
  end if;

  if p_declaration_id is null then
    if (
      select count(*) from public.fit_intent_declarations declaration
      where declaration.intent_set_id = p_intent_set_id
        and declaration.student_assertion_id is not null
    ) >= 64 or (
      select count(*) from public.fit_intent_declarations declaration
      where declaration.intent_set_id = p_intent_set_id
        and declaration.dimension = v_dimension
        and declaration.student_assertion_id is not null
    ) >= 16 then
      raise exception using errcode = '54000',
        message = 'FIT_INTENT_DECLARATION_LIMIT_EXCEEDED';
    end if;
  else
    select * into v_existing
    from public.fit_intent_declarations declaration
    where declaration.intent_declaration_id = p_declaration_id
      and declaration.intent_set_id = p_intent_set_id
      and declaration.profile_version_id = p_profile_version_id
      and declaration.student_assertion_id is not null
    for update;
    if not found then
      raise exception using errcode = 'P0002',
        message = 'FIT_INTENT_DECLARATION_NOT_FOUND';
    end if;
    if v_existing.dimension is distinct from v_dimension
       or v_existing.semantic_type is distinct from v_semantic_type then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_DECLARATION_IDENTITY_IMMUTABLE';
    end if;
    v_old_assertion_id := v_existing.student_assertion_id;
  end if;

  if v_semantic_type = 'TAXONOMY_TARGET' then
    perform private.fit_intent_assert_payload_keys_v027(
      v_typed, array['conceptId','relation'],
      array['conceptId','relation']
    );
    perform private.fit_intent_require_taxonomy_v027(
      p_intent_set_id,
      v_dimension,
      (v_typed ->> 'conceptId')::uuid
    );
    perform (v_typed ->> 'relation')::public.fit_intent_relation;
  elsif v_semantic_type = 'DELIVERY_CONSTRAINT' then
    if v_dimension <> 'GEOGRAPHIC_DELIVERY' then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_DIMENSION_TYPE_MISMATCH';
    end if;
    perform private.fit_intent_assert_payload_keys_v027(
      v_typed, array['deliveryMode','relation'],
      array['deliveryMode','relation']
    );
    if (v_typed ->> 'deliveryMode')::public.delivery_mode = 'UNKNOWN' then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_DELIVERY_UNKNOWN_FORBIDDEN';
    end if;
    perform (v_typed ->> 'relation')::public.fit_intent_relation;
  elsif v_semantic_type = 'FINANCIAL_CONSTRAINT' then
    if v_dimension <> 'FINANCIAL' then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_DIMENSION_TYPE_MISMATCH';
    end if;
    perform private.fit_intent_assert_payload_keys_v027(
      v_typed,
      array[
        'amount','constraintSemantics','currency','scope',
        'period','basis','components'
      ],
      array[
        'amount','constraintSemantics','currency','scope',
        'period','basis','components'
      ]
    );
    if (v_typed ->> 'constraintSemantics')::public.fit_financial_constraint_semantics
         = 'AVAILABLE_FUNDING'
       or (v_typed ->> 'basis')::public.fit_financial_basis <> 'GROSS'
       or jsonb_typeof(v_typed -> 'components') <> 'array' then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_FINANCIAL_V027_UNSUPPORTED';
    end if;
    select array_agg(component order by component) into v_components
    from jsonb_array_elements_text(v_typed -> 'components') component;
    if (v_typed ->> 'constraintSemantics') in (
         'HARD_TOTAL_COST_CEILING','PREFERRED_TOTAL_COST'
       ) and (
         (v_typed ->> 'scope') <> 'TOTAL_COST'
         or v_components is distinct from array['TOTAL_COST']::text[]
       ) then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_FINANCIAL_TUPLE_INVALID';
    elsif (v_typed ->> 'constraintSemantics') in (
         'HARD_TUITION_CEILING','PREFERRED_TUITION'
       ) and (
         (v_typed ->> 'scope') <> 'COMPONENT'
         or v_components is distinct from array['TUITION']::text[]
       ) then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_FINANCIAL_TUPLE_INVALID';
    end if;
    if v_importance = 'REQUIRED'
       and (v_typed ->> 'constraintSemantics') in (
         'PREFERRED_TOTAL_COST','PREFERRED_TUITION'
       ) then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_REQUIRED_SEMANTICS_INVALID';
    end if;
  elsif v_semantic_type = 'DURATION_CONSTRAINT' then
    if v_dimension <> 'PERSONAL_PREFERENCE' then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_DIMENSION_TYPE_MISMATCH';
    end if;
    perform private.fit_intent_assert_payload_keys_v027(
      v_typed, array['minimumMonths','maximumMonths'],
      array['minimumMonths','maximumMonths']
    );
  elsif v_semantic_type = 'PROGRAM_FEATURE_CONSTRAINT' then
    if v_dimension <> 'PERSONAL_PREFERENCE' then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_DIMENSION_TYPE_MISMATCH';
    end if;
    perform private.fit_intent_assert_payload_keys_v027(
      v_typed, array['featureKey','expected'],
      array['featureKey','expected']
    );
    if v_typed ->> 'featureKey' <> 'CAPSTONE_AVAILABLE' then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_FEATURE_V027_UNSUPPORTED';
    end if;
  else
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_SEMANTIC_TYPE_UNSUPPORTED';
  end if;

  insert into private.fit_intent_student_assertions_v027 (
    intent_set_id, profile_version_id, assertion_kind, dimension,
    semantic_payload_hash, required_importance_confirmed
  ) values (
    p_intent_set_id, p_profile_version_id, 'INTENT_DECLARATION',
    v_dimension,
    private.fit_intent_request_fingerprint_v027(
      jsonb_build_object(
        'schemaVersion', 'FIT_INTENT_ASSERTION_V027',
        'dimension', v_dimension,
        'semanticType', v_semantic_type,
        'importance', v_importance,
        'importanceConfirmedByStudent', v_confirmed,
        'typedValue', v_typed
      )
    ),
    v_importance = 'REQUIRED' and v_confirmed
  ) returning assertion_id into v_assertion_id;

  if p_declaration_id is null then
    insert into public.fit_intent_declarations (
      intent_declaration_id, intent_set_id, profile_version_id,
      origin, dimension, semantic_type, importance, importance_basis,
      importance_confirmed_by_student, interpretation_method,
      interpretation_method_version, interpretation_provenance,
      student_assertion_id
    ) values (
      v_declaration_id, p_intent_set_id, p_profile_version_id,
      'PHASE3_DECLARATION', v_dimension, v_semantic_type, v_importance,
      'STRUCTURED_STUDENT_DECLARATION', v_confirmed, 'HUMAN',
      'FIT_INTENT_PRODUCT_V027', 'SELF_ASSERTED', v_assertion_id
    );
  else
    delete from public.fit_intent_taxonomy_targets
      where intent_declaration_id = v_declaration_id;
    delete from public.fit_intent_delivery_constraints
      where intent_declaration_id = v_declaration_id;
    delete from public.fit_intent_financial_constraints
      where intent_declaration_id = v_declaration_id;
    delete from public.fit_intent_duration_constraints
      where intent_declaration_id = v_declaration_id;
    delete from public.fit_intent_program_feature_constraints
      where intent_declaration_id = v_declaration_id;
    update public.fit_intent_declarations declaration
    set importance = v_importance,
        importance_basis = 'STRUCTURED_STUDENT_DECLARATION',
        importance_evidence_id = null,
        importance_confirmed_by_student = v_confirmed,
        importance_reviewed_by = null,
        importance_reviewed_at = null,
        interpretation_method = 'HUMAN',
        interpretation_method_version = 'FIT_INTENT_PRODUCT_V027',
        interpretation_provenance = 'SELF_ASSERTED',
        student_evidence_id = null,
        student_assertion_id = v_assertion_id
    where declaration.intent_declaration_id = v_declaration_id;
  end if;

  if v_semantic_type = 'TAXONOMY_TARGET' then
    insert into public.fit_intent_taxonomy_targets (
      intent_declaration_id, intent_set_id, profile_version_id,
      concept_id, relation
    ) values (
      v_declaration_id, p_intent_set_id, p_profile_version_id,
      (v_typed ->> 'conceptId')::uuid,
      (v_typed ->> 'relation')::public.fit_intent_relation
    );
  elsif v_semantic_type = 'DELIVERY_CONSTRAINT' then
    insert into public.fit_intent_delivery_constraints (
      intent_declaration_id, intent_set_id, profile_version_id,
      delivery_mode, relation
    ) values (
      v_declaration_id, p_intent_set_id, p_profile_version_id,
      (v_typed ->> 'deliveryMode')::public.delivery_mode,
      (v_typed ->> 'relation')::public.fit_intent_relation
    );
  elsif v_semantic_type = 'FINANCIAL_CONSTRAINT' then
    insert into public.fit_intent_financial_constraints (
      intent_declaration_id, intent_set_id, profile_version_id,
      amount, constraint_semantics, currency, financial_scope,
      financial_period, financial_basis, components
    ) values (
      v_declaration_id, p_intent_set_id, p_profile_version_id,
      (v_typed ->> 'amount')::numeric,
      (v_typed ->> 'constraintSemantics')::public.fit_financial_constraint_semantics,
      upper(v_typed ->> 'currency'),
      (v_typed ->> 'scope')::public.fit_financial_scope,
      (v_typed ->> 'period')::public.fit_financial_period,
      (v_typed ->> 'basis')::public.fit_financial_basis,
      v_components
    );
  elsif v_semantic_type = 'DURATION_CONSTRAINT' then
    insert into public.fit_intent_duration_constraints (
      intent_declaration_id, intent_set_id, profile_version_id,
      minimum_months, maximum_months
    ) values (
      v_declaration_id, p_intent_set_id, p_profile_version_id,
      case when v_typed -> 'minimumMonths' = 'null'::jsonb
        then null else (v_typed ->> 'minimumMonths')::numeric end,
      case when v_typed -> 'maximumMonths' = 'null'::jsonb
        then null else (v_typed ->> 'maximumMonths')::numeric end
    );
  elsif v_semantic_type = 'PROGRAM_FEATURE_CONSTRAINT' then
    insert into public.fit_intent_program_feature_constraints (
      intent_declaration_id, intent_set_id, profile_version_id,
      feature_key, expected
    ) values (
      v_declaration_id, p_intent_set_id, p_profile_version_id,
      (v_typed ->> 'featureKey')::public.fit_program_feature_key,
      (v_typed ->> 'expected')::boolean
    );
  end if;

  update private.fit_intent_dimension_states_v027 state
  set disposition = 'DECLARED', updated_at = now()
  where state.intent_set_id = p_intent_set_id
    and state.dimension = v_dimension;
  if v_old_assertion_id is not null then
    delete from private.fit_intent_student_assertions_v027 assertion
    where assertion.assertion_id = v_old_assertion_id;
  end if;
  return v_declaration_id;
exception
  when invalid_text_representation or numeric_value_out_of_range
       or not_null_violation then
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_PAYLOAD_INVALID';
end;
$function$;

create or replace function public.mutate_fit_intent_draft_v027(
  p_intent_set_id uuid,
  p_operation_id uuid,
  p_expected_revision bigint,
  p_command public.fit_intent_product_command_v027,
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_profile_version_id uuid;
  v_revision bigint;
  v_status public.fit_intent_set_status;
  v_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
  v_resource_id uuid;
  v_dimension public.fit_dimension;
  v_assertion_id uuid;
  v_old_assertion_id uuid;
begin
  if p_intent_set_id is null or p_operation_id is null
     or p_expected_revision is null or p_expected_revision < 0
     or p_command is null then
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_MUTATION_ARGUMENT_REQUIRED';
  end if;
  v_student_id := private.fit_intent_student_for_auth_v027();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'FIT_INTENT_NOT_FOUND';
  end if;
  perform private.lock_student_lifecycle(v_student_id);
  v_fingerprint := private.fit_intent_request_fingerprint_v027(
    jsonb_build_object(
      'operation', 'MUTATE', 'intentSetId', p_intent_set_id,
      'expectedRevision', p_expected_revision, 'command', p_command,
      'payload', p_payload
    )
  );
  v_replay := private.fit_intent_replay_operation_v027(
    v_student_id, p_operation_id, 'MUTATE', p_command::text, v_fingerprint
  );
  if v_replay is not null then return v_replay; end if;
  select intent.profile_version_id, state.intent_revision, intent.status
  into v_profile_version_id, v_revision, v_status
  from public.fit_intent_sets intent
  join private.fit_intent_product_states_v027 state
    using(intent_set_id, profile_version_id)
  join public.student_profile_versions profile using(profile_version_id)
  where intent.intent_set_id = p_intent_set_id
    and profile.student_id = v_student_id
  for update of intent, state;
  if not found then
    raise exception using errcode = 'P0002', message = 'FIT_INTENT_NOT_FOUND';
  end if;
  if v_status <> 'DRAFT' then
    raise exception using errcode = '55000', message = 'FIT_INTENT_DRAFT_REQUIRED';
  end if;
  if v_revision <> p_expected_revision then
    raise exception using errcode = 'P0001',
      message = 'FIT_INTENT_REVISION_CONFLICT';
  end if;
  perform set_config('app.fit_intent_product_v027_write', 'on', true);

  if p_command in ('DECLARATION_CREATE', 'DECLARATION_REPLACE') then
    perform private.fit_intent_assert_payload_keys_v027(
      p_payload,
      case when p_command = 'DECLARATION_CREATE'
        then array['declaration']
        else array['declarationId','declaration'] end,
      case when p_command = 'DECLARATION_CREATE'
        then array['declaration']
        else array['declarationId','declaration'] end
    );
    v_resource_id := private.fit_intent_write_declaration_v027(
      p_intent_set_id, v_profile_version_id,
      case when p_command = 'DECLARATION_REPLACE'
        then (p_payload ->> 'declarationId')::uuid else null end,
      p_payload -> 'declaration'
    );
  elsif p_command = 'DECLARATION_DELETE' then
    perform private.fit_intent_assert_payload_keys_v027(
      p_payload, array['declarationId'], array['declarationId']
    );
    v_resource_id := (p_payload ->> 'declarationId')::uuid;
    select declaration.dimension, declaration.student_assertion_id
    into v_dimension, v_old_assertion_id
    from public.fit_intent_declarations declaration
    where declaration.intent_declaration_id = v_resource_id
      and declaration.intent_set_id = p_intent_set_id
      and declaration.student_assertion_id is not null
    for update;
    if not found then
      raise exception using errcode = 'P0002',
        message = 'FIT_INTENT_DECLARATION_NOT_FOUND';
    end if;
    delete from public.fit_intent_declarations declaration
    where declaration.intent_declaration_id = v_resource_id;
    delete from private.fit_intent_student_assertions_v027 assertion
    where assertion.assertion_id = v_old_assertion_id;
    if not exists (
      select 1 from public.fit_intent_declarations declaration
      where declaration.intent_set_id = p_intent_set_id
        and declaration.dimension = v_dimension
        and declaration.student_assertion_id is not null
    ) then
      update private.fit_intent_dimension_states_v027 state
      set disposition = 'UNANSWERED', updated_at = now()
      where state.intent_set_id = p_intent_set_id
        and state.dimension = v_dimension;
    end if;
  elsif p_command = 'DIMENSION_MARK_NOT_SUPPLIED' then
    perform private.fit_intent_assert_payload_keys_v027(
      p_payload, array['dimension'], array['dimension']
    );
    v_dimension := (p_payload ->> 'dimension')::public.fit_dimension;
    if exists (
      select 1 from public.fit_intent_declarations declaration
      where declaration.intent_set_id = p_intent_set_id
        and declaration.dimension = v_dimension
        and declaration.student_assertion_id is not null
    ) or (
      v_dimension = 'INTERNATIONAL_ACCESSIBILITY' and exists (
        select 1 from private.fit_student_access_contexts context
        where context.intent_set_id = p_intent_set_id
          and context.student_assertion_id is not null
      )
    ) then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_NOT_SUPPLIED_CONFLICT';
    end if;
    update private.fit_intent_dimension_states_v027 state
    set disposition = 'EXPLICIT_NOT_SUPPLIED', updated_at = now()
    where state.intent_set_id = p_intent_set_id
      and state.dimension = v_dimension;
  elsif p_command = 'ACCESS_CONTEXT_REPLACE' then
    perform private.fit_intent_assert_payload_keys_v027(
      p_payload,
      array[
        'citizenshipCountryCode','residenceCountryCode',
        'jurisdictionCode','currentStatusCode',
        'authorizationPathCode','targetPathCode'
      ],
      array['jurisdictionCode','targetPathCode']
    );
    if not exists (
      select 1 from private.fit_intent_dimension_states_v027 state
      where state.intent_set_id = p_intent_set_id
        and state.dimension = 'INTERNATIONAL_ACCESSIBILITY'
        and state.disposition = 'DECLARED'
    ) then
      raise exception using errcode = '23514',
        message = 'FIT_INTENT_ACCESS_DECLARATION_REQUIRED';
    end if;
    perform private.fit_intent_require_access_option_v027(
      p_payload ->> 'jurisdictionCode', p_payload ->> 'targetPathCode'
    );
    select context.student_assertion_id into v_old_assertion_id
    from private.fit_student_access_contexts context
    where context.intent_set_id = p_intent_set_id
      and context.student_assertion_id is not null for update;
    insert into private.fit_intent_student_assertions_v027 (
      intent_set_id, profile_version_id, assertion_kind, dimension,
      semantic_payload_hash
    ) values (
      p_intent_set_id, v_profile_version_id, 'ACCESS_CONTEXT',
      'INTERNATIONAL_ACCESSIBILITY',
      private.fit_intent_request_fingerprint_v027(
        jsonb_build_object(
          'schemaVersion', 'FIT_ACCESS_CONTEXT_ASSERTION_V027',
          'payload', p_payload
        )
      )
    ) returning assertion_id into v_assertion_id;
    if v_old_assertion_id is null then
      insert into private.fit_student_access_contexts (
        intent_set_id, profile_version_id, citizenship_country_code,
        residence_country_code, governing_jurisdiction_code,
        current_status_code, authorization_path_code, target_path_code,
        provenance, student_assertion_id
      ) values (
        p_intent_set_id, v_profile_version_id,
        nullif(upper(p_payload ->> 'citizenshipCountryCode'), ''),
        nullif(upper(p_payload ->> 'residenceCountryCode'), ''),
        upper(p_payload ->> 'jurisdictionCode'),
        nullif(upper(p_payload ->> 'currentStatusCode'), ''),
        nullif(upper(p_payload ->> 'authorizationPathCode'), ''),
        upper(p_payload ->> 'targetPathCode'),
        'SELF_ASSERTED:FIT_INTENT_PRODUCT_V027', v_assertion_id
      ) returning access_context_id into v_resource_id;
    else
      update private.fit_student_access_contexts context
      set citizenship_country_code =
            nullif(upper(p_payload ->> 'citizenshipCountryCode'), ''),
          residence_country_code =
            nullif(upper(p_payload ->> 'residenceCountryCode'), ''),
          governing_jurisdiction_code = upper(p_payload ->> 'jurisdictionCode'),
          current_status_code =
            nullif(upper(p_payload ->> 'currentStatusCode'), ''),
          authorization_path_code =
            nullif(upper(p_payload ->> 'authorizationPathCode'), ''),
          target_path_code = upper(p_payload ->> 'targetPathCode'),
          student_evidence_id = null,
          provenance = 'SELF_ASSERTED:FIT_INTENT_PRODUCT_V027',
          student_assertion_id = v_assertion_id
      where context.intent_set_id = p_intent_set_id
        and context.student_assertion_id = v_old_assertion_id
      returning access_context_id into v_resource_id;
      delete from private.fit_intent_student_assertions_v027 assertion
      where assertion.assertion_id = v_old_assertion_id;
    end if;
  elsif p_command = 'ACCESS_CONTEXT_DELETE' then
    perform private.fit_intent_assert_payload_keys_v027(
      p_payload, array[]::text[], array[]::text[]
    );
    delete from private.fit_student_access_contexts context
    where context.intent_set_id = p_intent_set_id
      and context.student_assertion_id is not null
    returning access_context_id, student_assertion_id
    into v_resource_id, v_old_assertion_id;
    if not found then
      raise exception using errcode = 'P0002',
        message = 'FIT_INTENT_ACCESS_CONTEXT_NOT_FOUND';
    end if;
    delete from private.fit_intent_student_assertions_v027 assertion
    where assertion.assertion_id = v_old_assertion_id;
  else
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_COMMAND_UNSUPPORTED';
  end if;
  update private.fit_intent_product_states_v027 state
  set intent_revision = intent_revision + 1, updated_at = now()
  where state.intent_set_id = p_intent_set_id
    and state.intent_revision = p_expected_revision and state.active_draft;
  if not found then
    raise exception using errcode = 'P0001',
      message = 'FIT_INTENT_REVISION_CONFLICT';
  end if;
  v_result := jsonb_build_object(
    'schemaVersion', 'FIT_INTENT_OPERATION_RESULT_V027',
    'operation', 'MUTATE', 'command', p_command,
    'intentSetId', p_intent_set_id,
    'revision', p_expected_revision + 1,
    'resourceId', v_resource_id,
    'document', private.fit_intent_document_v027(p_intent_set_id)
  );
  perform private.fit_intent_store_operation_v027(
    v_student_id, p_operation_id, 'MUTATE', p_command::text,
    v_fingerprint, v_result
  );
  return v_result;
exception
  when invalid_text_representation or numeric_value_out_of_range
       or not_null_violation then
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_PAYLOAD_INVALID';
end;
$function$;

create or replace function public.freeze_fit_intent_draft_v027(
  p_intent_set_id uuid,
  p_operation_id uuid,
  p_expected_revision bigint
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_profile_version_id uuid;
  v_revision bigint;
  v_status public.fit_intent_set_status;
  v_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
  v_hash text;
begin
  if p_intent_set_id is null or p_operation_id is null
     or p_expected_revision is null or p_expected_revision < 0 then
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_FREEZE_ARGUMENT_REQUIRED';
  end if;
  v_student_id := private.fit_intent_student_for_auth_v027();
  if v_student_id is null then
    raise exception using errcode = 'P0002', message = 'FIT_INTENT_NOT_FOUND';
  end if;
  perform private.lock_student_lifecycle(v_student_id);
  perform private.lock_student_owned_total_order(v_student_id);
  v_fingerprint := private.fit_intent_request_fingerprint_v027(
    jsonb_build_object(
      'operation', 'FREEZE', 'intentSetId', p_intent_set_id,
      'expectedRevision', p_expected_revision
    )
  );
  v_replay := private.fit_intent_replay_operation_v027(
    v_student_id, p_operation_id, 'FREEZE', null, v_fingerprint
  );
  if v_replay is not null then return v_replay; end if;
  select intent.profile_version_id, state.intent_revision, intent.status
  into v_profile_version_id, v_revision, v_status
  from public.fit_intent_sets intent
  join private.fit_intent_product_states_v027 state
    using(intent_set_id, profile_version_id)
  join public.student_profile_versions profile using(profile_version_id)
  where intent.intent_set_id = p_intent_set_id
    and profile.student_id = v_student_id
  for update of intent, state;
  if not found then
    raise exception using errcode = 'P0002', message = 'FIT_INTENT_NOT_FOUND';
  end if;
  if v_status <> 'DRAFT' then
    raise exception using errcode = '55000', message = 'FIT_INTENT_DRAFT_REQUIRED';
  end if;
  if v_revision <> p_expected_revision then
    raise exception using errcode = 'P0001',
      message = 'FIT_INTENT_REVISION_CONFLICT';
  end if;
  if not exists (
    select 1 from public.student_profile_versions profile
    where profile.profile_version_id = v_profile_version_id
      and profile.status = 'FROZEN'
  ) then
    raise exception using errcode = '55000',
      message = 'FIT_INTENT_FROZEN_PROFILE_REQUIRED';
  end if;
  if (select count(*) from private.fit_intent_dimension_states_v027 state
      where state.intent_set_id = p_intent_set_id) <> 6
     or exists (
       select 1 from private.fit_intent_dimension_states_v027 state
       where state.intent_set_id = p_intent_set_id
         and state.disposition = 'UNANSWERED'
     ) then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_DIMENSIONS_INCOMPLETE';
  end if;
  if exists (
    select 1 from private.fit_intent_dimension_states_v027 state
    where state.intent_set_id = p_intent_set_id
      and (
        (state.disposition = 'DECLARED' and not exists (
          select 1 from public.fit_intent_declarations declaration
          where declaration.intent_set_id = state.intent_set_id
            and declaration.dimension = state.dimension
            and declaration.student_assertion_id is not null
        ))
        or (state.disposition = 'EXPLICIT_NOT_SUPPLIED' and exists (
          select 1 from public.fit_intent_declarations declaration
          where declaration.intent_set_id = state.intent_set_id
            and declaration.dimension = state.dimension
            and declaration.student_assertion_id is not null
        ))
      )
  ) then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_DIMENSION_STATE_CONFLICT';
  end if;
  if exists (
    select 1 from private.fit_intent_student_assertions_v027 assertion
    left join public.fit_intent_declarations declaration
      on declaration.student_assertion_id = assertion.assertion_id
    where assertion.intent_set_id = p_intent_set_id
      and assertion.assertion_kind = 'INTENT_DECLARATION'
      and (
        declaration.intent_declaration_id is null
        or declaration.dimension is distinct from assertion.dimension
        or declaration.interpretation_provenance <> 'SELF_ASSERTED'
        or (declaration.importance = 'REQUIRED' and (
          not declaration.importance_confirmed_by_student
          or not assertion.required_importance_confirmed
        ))
      )
  ) then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_ASSERTION_INVALID';
  end if;
  if exists (
    select 1 from private.fit_intent_dimension_states_v027 state
    where state.intent_set_id = p_intent_set_id
      and state.dimension = 'INTERNATIONAL_ACCESSIBILITY'
      and state.disposition = 'EXPLICIT_NOT_SUPPLIED'
      and exists (
        select 1 from private.fit_student_access_contexts context
        where context.intent_set_id = p_intent_set_id
          and context.student_assertion_id is not null
      )
  ) then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_NOT_SUPPLIED_CONFLICT';
  end if;
  if exists (
    select 1
    from public.fit_intent_declarations first_declaration
    join public.fit_intent_delivery_constraints first_delivery
      on first_delivery.intent_declaration_id =
         first_declaration.intent_declaration_id
    join public.fit_intent_declarations second_declaration
      on second_declaration.intent_set_id = first_declaration.intent_set_id
     and second_declaration.intent_declaration_id >
         first_declaration.intent_declaration_id
    join public.fit_intent_delivery_constraints second_delivery
      on second_delivery.intent_declaration_id =
         second_declaration.intent_declaration_id
    where first_declaration.intent_set_id = p_intent_set_id
      and first_declaration.importance = 'REQUIRED'
      and second_declaration.importance = 'REQUIRED'
      and (
        (first_delivery.relation = 'DESIRED'
          and second_delivery.relation = 'DESIRED'
          and first_delivery.delivery_mode <> second_delivery.delivery_mode)
        or (first_delivery.relation <> second_delivery.relation
          and first_delivery.delivery_mode = second_delivery.delivery_mode)
      )
  ) then
    raise exception using errcode = '23514',
      message = 'FIT_INTENT_REQUIRED_DELIVERY_CONFLICT';
  end if;
  v_hash := private.fit_intent_request_fingerprint_v027(
    jsonb_build_object(
      'schemaVersion', 'FIT_INTENT_SNAPSHOT_V027',
      'document', private.fit_intent_document_v027(p_intent_set_id)
    )
  );
  perform set_config('app.fit_intent_product_v027_write', 'on', true);
  perform set_config('app.fit_intent_controlled_write', 'on', true);
  update public.fit_intent_sets intent
  set status = 'FROZEN', snapshot_hash = v_hash, frozen_at = now()
  where intent.intent_set_id = p_intent_set_id;
  update private.fit_intent_product_states_v027 state
  set active_draft = false,
      intent_revision = intent_revision + 1,
      updated_at = now()
  where state.intent_set_id = p_intent_set_id;
  v_result := jsonb_build_object(
    'schemaVersion', 'FIT_INTENT_OPERATION_RESULT_V027',
    'operation', 'FREEZE', 'intentSetId', p_intent_set_id,
    'profileVersionId', v_profile_version_id,
    'status', 'FROZEN', 'revision', p_expected_revision + 1,
    'snapshotHash', v_hash,
    'document', private.fit_intent_document_v027(p_intent_set_id)
  );
  perform private.fit_intent_store_operation_v027(
    v_student_id, p_operation_id, 'FREEZE', null, v_fingerprint, v_result
  );
  return v_result;
end;
$function$;

create or replace function public.get_fit_intent_taxonomy_options_v027(
  p_intent_set_id uuid,
  p_dimension public.fit_dimension
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_release_code text;
  v_release_ordinal bigint;
  v_count integer;
  v_oversized boolean;
begin
  if p_dimension not in (
    'ACADEMIC','CAREER','INTERNATIONAL_ACCESSIBILITY'
  ) then
    raise exception using errcode = '22023',
      message = 'FIT_INTENT_TAXONOMY_DIMENSION_FORBIDDEN';
  end if;
  v_student_id := private.fit_intent_student_for_auth_v027();
  select state.taxonomy_release_code, state.taxonomy_release_ordinal
  into v_release_code, v_release_ordinal
  from private.fit_intent_product_states_v027 state
  join public.fit_intent_sets intent
    using(intent_set_id, profile_version_id)
  join public.student_profile_versions profile using(profile_version_id)
  where state.intent_set_id = p_intent_set_id
    and profile.student_id = v_student_id and intent.status = 'DRAFT';
  if not found then
    raise exception using errcode = 'P0002', message = 'FIT_INTENT_NOT_FOUND';
  end if;
  select count(*), coalesce(bool_or(
    octet_length(concept.canonical_key) > 128
    or octet_length(concept.display_name) > 256
  ), false)
  into v_count, v_oversized
  from public.taxonomy_concepts concept
  where concept.introduced_release_ordinal <= v_release_ordinal
    and (concept.retired_release_ordinal is null
      or concept.retired_release_ordinal > v_release_ordinal)
    and (
      (p_dimension = 'ACADEMIC' and concept.concept_kind in (
        'FIELD','SUBFIELD','SUBJECT','COURSE_CONCEPT'
      ))
      or (p_dimension = 'CAREER'
        and concept.concept_kind in ('CAREER','INDUSTRY'))
      or (p_dimension = 'INTERNATIONAL_ACCESSIBILITY'
        and concept.concept_kind = 'CAREER')
    )
    and (
      (p_dimension = 'ACADEMIC' and exists (
        select 1 from public.catalog_concept_mappings mapping
        where mapping.concept_id = concept.concept_id
          and mapping.mapping_status = 'VERIFIED'
          and mapping.retired_at is null
          and mapping.relation in (
            'FIELD_CLASSIFICATION','SUBFIELD_CLASSIFICATION',
            'SUBJECT_CLASSIFICATION','COURSE_EQUIVALENCY'
          )
      ))
      or (p_dimension = 'CAREER' and (
        exists (
          select 1 from public.catalog_concept_mappings mapping
          where mapping.concept_id = concept.concept_id
            and mapping.mapping_status = 'VERIFIED'
            and mapping.retired_at is null
            and mapping.relation in (
              'CAREER_ASSOCIATION','INDUSTRY_ASSOCIATION'
            )
        ) or exists (
          select 1 from public.fit_context_concept_mappings mapping
          where mapping.concept_id = concept.concept_id
            and mapping.mapping_status = 'VERIFIED'
            and mapping.retired_at is null
            and mapping.relation_code = 'PROGRAM_RELATED_TO_CAREER'
        )
      ))
      or (p_dimension = 'INTERNATIONAL_ACCESSIBILITY' and exists (
        select 1 from public.fit_context_concept_mappings mapping
        where mapping.concept_id = concept.concept_id
          and mapping.mapping_status = 'VERIFIED'
          and mapping.retired_at is null
          and mapping.relation_code in (
            'PROGRAM_ASSOCIATED_WITH_PATH','CLAIM_APPLIES_TO_CONCEPT'
          )
      ))
    );
  if v_count > 64 then
    raise exception using errcode = '54000',
      message = 'FIT_INTENT_OPTION_LIMIT_EXCEEDED';
  end if;
  if v_oversized then
    raise exception using errcode = '54000',
      message = 'FIT_INTENT_OPTION_VALUE_TOO_LONG';
  end if;
  return jsonb_build_object(
    'schemaVersion', 'FIT_INTENT_TAXONOMY_OPTIONS_V027',
    'intentSetId', p_intent_set_id,
    'dimension', p_dimension,
    'releaseCode', v_release_code,
    'releaseOrdinal', v_release_ordinal,
    'options', coalesce((
      select jsonb_agg(jsonb_build_object(
        'conceptId', concept.concept_id,
        'conceptKind', concept.concept_kind,
        'canonicalKey', concept.canonical_key,
        'displayName', concept.display_name
      ) order by concept.canonical_key collate "C", concept.concept_id)
      from public.taxonomy_concepts concept
      where concept.introduced_release_ordinal <= v_release_ordinal
        and (concept.retired_release_ordinal is null
          or concept.retired_release_ordinal > v_release_ordinal)
        and (
          (p_dimension = 'ACADEMIC' and concept.concept_kind in (
            'FIELD','SUBFIELD','SUBJECT','COURSE_CONCEPT'
          ))
          or (p_dimension = 'CAREER'
            and concept.concept_kind in ('CAREER','INDUSTRY'))
          or (p_dimension = 'INTERNATIONAL_ACCESSIBILITY'
            and concept.concept_kind = 'CAREER')
        )
        and private.fit_intent_taxonomy_is_covered_v027(
          p_dimension, concept.concept_id
        )
    ), '[]'::jsonb)
  );
end;
$function$;

create or replace function private.fit_intent_taxonomy_is_covered_v027(
  p_dimension public.fit_dimension,
  p_concept_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
  select case p_dimension
    when 'ACADEMIC' then exists (
      select 1 from public.catalog_concept_mappings mapping
      where mapping.concept_id = p_concept_id
        and mapping.mapping_status = 'VERIFIED'
        and mapping.retired_at is null
        and mapping.relation in (
          'FIELD_CLASSIFICATION','SUBFIELD_CLASSIFICATION',
          'SUBJECT_CLASSIFICATION','COURSE_EQUIVALENCY'
        )
    )
    when 'CAREER' then exists (
      select 1 from public.catalog_concept_mappings mapping
      where mapping.concept_id = p_concept_id
        and mapping.mapping_status = 'VERIFIED'
        and mapping.retired_at is null
        and mapping.relation in ('CAREER_ASSOCIATION','INDUSTRY_ASSOCIATION')
      union all
      select 1 from public.fit_context_concept_mappings mapping
      where mapping.concept_id = p_concept_id
        and mapping.mapping_status = 'VERIFIED'
        and mapping.retired_at is null
        and mapping.relation_code = 'PROGRAM_RELATED_TO_CAREER'
    )
    when 'INTERNATIONAL_ACCESSIBILITY' then exists (
      select 1 from public.fit_context_concept_mappings mapping
      where mapping.concept_id = p_concept_id
        and mapping.mapping_status = 'VERIFIED'
        and mapping.retired_at is null
        and mapping.relation_code in (
          'PROGRAM_ASSOCIATED_WITH_PATH','CLAIM_APPLIES_TO_CONCEPT'
        )
    )
    else false
  end
$function$;

create or replace function public.get_fit_access_context_options_v027(
  p_intent_set_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
  v_count integer;
begin
  v_student_id := private.fit_intent_student_for_auth_v027();
  if v_student_id is null or not exists (
    select 1 from public.fit_intent_sets intent
    join private.fit_intent_product_states_v027 state
      using(intent_set_id, profile_version_id)
    join public.student_profile_versions profile using(profile_version_id)
    where intent.intent_set_id = p_intent_set_id
      and profile.student_id = v_student_id and intent.status = 'DRAFT'
  ) then
    raise exception using errcode = 'P0002', message = 'FIT_INTENT_NOT_FOUND';
  end if;
  select count(*) into v_count from (
    select claim.jurisdiction_code, claim.path_code
    from public.fit_context_claims claim
    join public.fit_context_claim_definitions definition
      on definition.claim_definition_id = claim.claim_definition_id
     and definition.definition_version = claim.definition_version
    join public.fit_context_claim_selections selection using(context_claim_id)
    join public.fit_context_claim_observations observation
      on observation.context_observation_id = selection.context_observation_id
    where claim.jurisdiction_code is not null and claim.path_code is not null
      and definition.claim_code in (
        'REGULATORY_WORK_AUTHORIZATION',
        'JURISDICTION_PATH_ACCESSIBILITY'
      )
      and claim.valid_from <= current_date
      and (claim.valid_to is null or claim.valid_to >= current_date)
      and definition.status = 'VERIFIED' and definition.retired_at is null
      and selection.knowledge_status = 'KNOWN'
      and observation.workflow_status = 'VERIFIED'
      and observation.retired_at is null
      and observation.authority = 'OFFICIAL_REGULATORY'
    group by claim.jurisdiction_code, claim.path_code
  ) option;
  if v_count > 64 then
    raise exception using errcode = '54000',
      message = 'FIT_INTENT_OPTION_LIMIT_EXCEEDED';
  end if;
  return jsonb_build_object(
    'schemaVersion', 'FIT_ACCESS_CONTEXT_OPTIONS_V027',
    'intentSetId', p_intent_set_id,
    'options', coalesce((
      select jsonb_agg(jsonb_build_object(
        'jurisdictionCode', option.jurisdiction_code,
        'targetPathCode', option.path_code
      ) order by option.jurisdiction_code collate "C",
        option.path_code collate "C")
      from (
        select claim.jurisdiction_code, claim.path_code
        from public.fit_context_claims claim
        join public.fit_context_claim_definitions definition
          on definition.claim_definition_id = claim.claim_definition_id
         and definition.definition_version = claim.definition_version
        join public.fit_context_claim_selections selection using(context_claim_id)
        join public.fit_context_claim_observations observation
          on observation.context_observation_id =
             selection.context_observation_id
        where claim.jurisdiction_code is not null
          and claim.path_code is not null
          and definition.claim_code in (
            'REGULATORY_WORK_AUTHORIZATION',
            'JURISDICTION_PATH_ACCESSIBILITY'
          )
          and claim.valid_from <= current_date
          and (claim.valid_to is null or claim.valid_to >= current_date)
          and definition.status = 'VERIFIED'
          and definition.retired_at is null
          and selection.knowledge_status = 'KNOWN'
          and observation.workflow_status = 'VERIFIED'
          and observation.retired_at is null
          and observation.authority = 'OFFICIAL_REGULATORY'
        group by claim.jurisdiction_code, claim.path_code
      ) option
    ), '[]'::jsonb)
  );
end;
$function$;

create or replace function public.get_fit_evaluation_assembly_v027(
  p_profile_version_id uuid,
  p_intent_set_id uuid,
  p_program_version_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $function$
declare
  v_student_id uuid;
begin
  v_student_id := private.fit_intent_student_for_auth_v027();
  if v_student_id is null or not exists (
    select 1 from public.student_profile_versions profile
    where profile.profile_version_id = p_profile_version_id
      and profile.student_id = v_student_id and profile.status = 'FROZEN'
  ) then
    raise exception using errcode = 'P0002',
      message = 'FIT_ASSEMBLY_PROFILE_NOT_FOUND';
  end if;
  if not exists (
    select 1 from public.fit_intent_sets intent
    join private.fit_intent_product_states_v027 state
      using(intent_set_id, profile_version_id)
    where intent.intent_set_id = p_intent_set_id
      and intent.profile_version_id = p_profile_version_id
      and intent.status = 'FROZEN' and not state.active_draft
  ) then
    raise exception using errcode = 'P0002',
      message = 'FIT_ASSEMBLY_INTENT_NOT_FOUND';
  end if;
  if not exists (
    select 1 from public.program_versions version
    where version.program_version_id = p_program_version_id
  ) then
    raise exception using errcode = 'P0002',
      message = 'FIT_ASSEMBLY_PROGRAM_NOT_FOUND';
  end if;
  return jsonb_build_object(
    'schemaVersion', 'FIT_EVALUATION_ASSEMBLY_V027',
    'profileVersionId', p_profile_version_id,
    'intentSetId', p_intent_set_id,
    'programVersionId', p_program_version_id,
    'intentSnapshotHash', (
      select intent.snapshot_hash from public.fit_intent_sets intent
      where intent.intent_set_id = p_intent_set_id
    ),
    'dimensions', (
      select jsonb_agg(jsonb_build_object(
        'dimension', state.dimension,
        'disposition', state.disposition,
        'inputAvailability', case
          when state.disposition = 'EXPLICIT_NOT_SUPPLIED'
            then 'NOT_SUPPLIED'
          else 'INCLUDED'
        end,
        'completenessDomain', case
          when state.dimension in (
            'ACADEMIC','CAREER','INTERNATIONAL_ACCESSIBILITY'
          ) then 'GOALS' else 'PREFERENCES' end,
        'completenessId', completeness.completeness_id,
        'profileCompleteness', completeness.completeness
      ) order by state.dimension)
      from private.fit_intent_dimension_states_v027 state
      join public.student_data_completeness completeness
        on completeness.profile_version_id = p_profile_version_id
       and completeness.education_context_id is null
       and completeness.domain = case
         when state.dimension in (
           'ACADEMIC','CAREER','INTERNATIONAL_ACCESSIBILITY'
         ) then 'GOALS'::public.student_data_domain
         else 'PREFERENCES'::public.student_data_domain end
      where state.intent_set_id = p_intent_set_id
    ),
    'intentDocument', private.fit_intent_document_v027(p_intent_set_id)
  );
end;
$function$;

alter table private.fit_intent_product_states_v027 enable row level security;
alter table private.fit_intent_dimension_states_v027 enable row level security;
alter table private.fit_intent_student_assertions_v027 enable row level security;
alter table private.fit_intent_operations_v027 enable row level security;

create policy fit_intent_product_states_executor_v027
  on private.fit_intent_product_states_v027
  for all to foundation_student_executor
  using (current_user = 'foundation_student_executor')
  with check (current_user = 'foundation_student_executor');
create policy fit_intent_dimension_states_executor_v027
  on private.fit_intent_dimension_states_v027
  for all to foundation_student_executor
  using (current_user = 'foundation_student_executor')
  with check (current_user = 'foundation_student_executor');
create policy fit_intent_student_assertions_executor_v027
  on private.fit_intent_student_assertions_v027
  for all to foundation_student_executor
  using (current_user = 'foundation_student_executor')
  with check (current_user = 'foundation_student_executor');
create policy fit_intent_operations_executor_v027
  on private.fit_intent_operations_v027
  for all to foundation_student_executor
  using (current_user = 'foundation_student_executor')
  with check (current_user = 'foundation_student_executor');

revoke all on table
  private.fit_intent_product_states_v027,
  private.fit_intent_dimension_states_v027,
  private.fit_intent_student_assertions_v027,
  private.fit_intent_operations_v027
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant select, insert, update, delete on table
  private.fit_intent_product_states_v027,
  private.fit_intent_dimension_states_v027,
  private.fit_intent_student_assertions_v027,
  private.fit_intent_operations_v027
to foundation_student_executor;

grant create on schema public, private to foundation_student_executor;

do $owners$
declare
  v_function record;
begin
  for v_function in
    select namespace.nspname,
      procedure.proname,
      pg_get_function_identity_arguments(procedure.oid) identity_arguments
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public','private')
      and procedure.proname like '%\_v027' escape '\'
  loop
    execute format(
      'alter function %I.%I(%s) owner to foundation_student_executor',
      v_function.nspname, v_function.proname,
      v_function.identity_arguments
    );
  end loop;
end;
$owners$;

alter table private.fit_intent_product_states_v027
  owner to foundation_student_executor;
alter table private.fit_intent_dimension_states_v027
  owner to foundation_student_executor;
alter table private.fit_intent_student_assertions_v027
  owner to foundation_student_executor;
alter table private.fit_intent_operations_v027
  owner to foundation_student_executor;

revoke create on schema public, private from foundation_student_executor;

do $function_acl$
declare
  v_function record;
begin
  for v_function in
    select namespace.nspname,
      procedure.proname,
      pg_get_function_identity_arguments(procedure.oid) identity_arguments
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public','private')
      and procedure.proname like '%\_v027' escape '\'
  loop
    execute format(
      'revoke all on function %I.%I(%s) from public, anon, authenticated, service_role, authenticator, foundation_catalog_executor, foundation_student_executor, foundation_evaluation_executor',
      v_function.nspname, v_function.proname,
      v_function.identity_arguments
    );
    if v_function.nspname = 'private' then
      execute format(
        'grant execute on function %I.%I(%s) to foundation_student_executor',
        v_function.nspname, v_function.proname,
        v_function.identity_arguments
      );
    end if;
  end loop;
end;
$function_acl$;

revoke usage on type
  public.fit_intent_product_dimension_state_v027,
  public.fit_intent_product_command_v027,
  public.fit_intent_student_assertion_kind_v027
from public, anon, authenticated, service_role, authenticator,
  foundation_catalog_executor, foundation_student_executor,
  foundation_evaluation_executor;
grant usage on type
  public.fit_intent_product_dimension_state_v027,
  public.fit_intent_product_command_v027,
  public.fit_intent_student_assertion_kind_v027
to foundation_student_executor;
grant usage on type public.fit_intent_product_command_v027
to authenticated;

grant execute on function
  public.create_or_resume_fit_intent_draft_v027(uuid,uuid),
  public.get_fit_intent_document_v027(uuid),
  public.discover_fit_intent_v027(uuid),
  public.mutate_fit_intent_draft_v027(
    uuid,uuid,bigint,public.fit_intent_product_command_v027,jsonb
  ),
  public.freeze_fit_intent_draft_v027(uuid,uuid,bigint),
  public.get_fit_intent_taxonomy_options_v027(uuid,public.fit_dimension),
  public.get_fit_access_context_options_v027(uuid),
  public.get_fit_evaluation_assembly_v027(uuid,uuid,uuid)
to authenticated;

do $contracts$
declare
  v_function record;
  v_allowed text[];
begin
  for v_function in
    select namespace.nspname,
      procedure.proname,
      pg_get_function_identity_arguments(procedure.oid) identity_arguments,
      procedure.proowner::regrole::text owner_role,
      procedure.prosecdef,
      pg_get_functiondef(procedure.oid) definition
    from pg_proc procedure
    join pg_namespace namespace on namespace.oid = procedure.pronamespace
    where namespace.nspname in ('public','private')
      and procedure.proname like '%\_v027' escape '\'
  loop
    v_allowed := case when v_function.nspname = 'public'
      then array['authenticated']
      else array['foundation_student_executor'] end;
    insert into public.foundation_function_contracts (
      schema_name, function_name, identity_arguments, owner_role, prosecdef,
      search_path, allowed_caller_roles, body_digest
    ) values (
      v_function.nspname, v_function.proname,
      v_function.identity_arguments, v_function.owner_role,
      v_function.prosecdef,
      'pg_catalog, public, private, extensions', v_allowed,
      encode(extensions.digest(
        convert_to(v_function.definition, 'UTF8'), 'sha256'
      ), 'hex')
    )
    on conflict (schema_name, function_name, identity_arguments) do update
      set owner_role = excluded.owner_role,
          prosecdef = excluded.prosecdef,
          search_path = excluded.search_path,
          allowed_caller_roles = excluded.allowed_caller_roles,
          body_digest = excluded.body_digest;
  end loop;
end;
$contracts$;

comment on function public.freeze_fit_intent_draft_v027(uuid,uuid,bigint) is
  'Freezes an owner-scoped product intent only after each frozen Fit v0.1 dimension is explicitly DECLARED or EXPLICIT_NOT_SUPPLIED; the latter contains no fabricated intent and assembles as NOT_SUPPLIED.';
comment on table private.fit_intent_student_assertions_v027 is
  'Private self-assertion provenance. It proves only that the student explicitly declared the payload; it is not external VERIFIED evidence.';

do $assert$
declare
  v_count integer;
begin
  select count(*) into v_count
  from pg_proc procedure
  join pg_namespace namespace on namespace.oid = procedure.pronamespace
  join pg_roles owner_role on owner_role.oid = procedure.proowner
  where namespace.nspname in ('public','private')
    and procedure.proname like '%\_v027' escape '\'
    and (
      owner_role.rolname <> 'foundation_student_executor'
      or not procedure.prosecdef
      or procedure.proconfig is distinct from
        array['search_path=pg_catalog, public, private, extensions']::text[]
    );
  if v_count <> 0 then
    raise exception '027 assertion failed: function owner/definer/search_path';
  end if;
  if exists (
    select 1 from information_schema.routine_privileges privilege
    where privilege.grantee in (
      'PUBLIC','anon','service_role','authenticator',
      'foundation_catalog_executor','foundation_evaluation_executor'
    ) and privilege.privilege_type = 'EXECUTE'
      and privilege.routine_schema in ('public','private')
      and privilege.routine_name like '%\_v027' escape '\'
  ) then
    raise exception '027 assertion failed: external v027 EXECUTE';
  end if;
  if exists (
    select 1 from information_schema.routine_privileges privilege
    where privilege.grantee = 'authenticated'
      and privilege.privilege_type = 'EXECUTE'
      and privilege.routine_schema = 'private'
      and privilege.routine_name like '%\_v027' escape '\'
  ) then
    raise exception '027 assertion failed: authenticated private EXECUTE';
  end if;
  if has_schema_privilege(
       'foundation_student_executor','auth','USAGE'
     ) or has_table_privilege(
       'foundation_student_executor','auth.users','SELECT'
     ) then
    raise exception '027 assertion failed: hosted auth boundary widened';
  end if;
  if exists (
    select 1 from private.fit_intent_dimension_states_v027 state
    group by state.intent_set_id having count(*) <> 6
  ) then
    raise exception '027 assertion failed: incomplete product dimension state';
  end if;
  if exists (
    select 1 from private.fit_intent_student_assertions_v027 assertion
    where assertion.semantic_payload_hash !~ '^[a-f0-9]{64}$'
  ) then
    raise exception '027 assertion failed: malformed student assertion';
  end if;
end;
$assert$;

commit;
