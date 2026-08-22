begin;

-- Migration 015 is additive over frozen 014. It preserves the 014 decision
-- and result fingerprint algorithms and moves full live-authority validation
-- to the seal boundary for explicitly versioned v015 evaluations.

-- Supabase's hosted migration connection can have a temporary session role
-- while executing as the canonical installer role. Preserve that effective
-- installer before the executor-scoped adoption update so RESET ROLE cannot
-- strand the remainder of this migration on the temporary login role.
do $capture_phase015_installer$
begin
  perform set_config(
    'app.migration_015_installer_role',
    current_user,
    true
  );
end;
$capture_phase015_installer$;

alter table public.fit_evaluations
  add column replay_contract_version text;

alter table public.fit_evaluations
  add constraint fit_evaluations_replay_contract_v015
  check (
    replay_contract_version is null
    or replay_contract_version = 'FIT_REPLAY_SEAL_V015'
  );

create function private.assign_fit_replay_contract_v015()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if new.replay_contract_version is null then
    new.replay_contract_version := 'FIT_REPLAY_SEAL_V015';
  elsif new.replay_contract_version <> 'FIT_REPLAY_SEAL_V015' then
    raise exception using
      errcode = '55000',
      message = 'Unknown Fit replay contract version';
  end if;
  return new;
end;
$$;

create function private.guard_fit_replay_contract_v015()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if old.replay_contract_version is null
     and new.replay_contract_version = 'FIT_REPLAY_SEAL_V015'
     and old.evaluation_state = 'BUILDING'
     and old.candidate_input_fingerprint is null
     and current_user = 'foundation_evaluation_executor' then
    return new;
  end if;
  if new.replay_contract_version is distinct from old.replay_contract_version then
    raise exception using
      errcode = '55000',
      message = 'Fit replay contract version is immutable';
  end if;
  return new;
end;
$$;

create trigger fit_evaluations_assign_replay_contract_v015
before insert on public.fit_evaluations
for each row execute function private.assign_fit_replay_contract_v015();

create trigger fit_evaluations_replay_contract_immutable_v015
before update of replay_contract_version on public.fit_evaluations
for each row execute function private.guard_fit_replay_contract_v015();

-- Existing unsealed BUILDING evaluations can safely adopt v015 because seal
-- performs the complete 014 validator before persisting a pin. Already sealed
-- BUILDING and COMPLETED evaluations remain legacy-null and keep 014 behavior.
set local role foundation_evaluation_executor;
update public.fit_evaluations
set replay_contract_version = 'FIT_REPLAY_SEAL_V015'
where evaluation_state = 'BUILDING'
  and candidate_input_fingerprint is null
  and replay_contract_version is null;
reset role;
do $restore_phase015_installer$
begin
  execute format(
    'set role %I',
    current_setting('app.migration_015_installer_role')
  );
end;
$restore_phase015_installer$;

do $assert_phase015_installer$
begin
  if current_user is distinct from
       current_setting('app.migration_015_installer_role') then
    raise exception using
      errcode = '42501',
      message = 'Migration 015 could not restore its installer role';
  end if;
end;
$assert_phase015_installer$;

create table private.fit_evaluation_semantic_pins (
  evaluation_id uuid primary key
    references public.fit_evaluations(evaluation_id) on delete cascade,
  replay_contract_version text not null
    check (replay_contract_version = 'FIT_REPLAY_SEAL_V015'),
  semantic_envelope jsonb not null
    check (jsonb_typeof(semantic_envelope) = 'object'),
  semantic_fingerprint text not null
    check (semantic_fingerprint ~ '^[0-9a-f]{64}$'),
  decision_input_fingerprint text not null
    check (decision_input_fingerprint ~ '^[0-9a-f]{64}$'),
  result_fingerprint text not null
    check (result_fingerprint ~ '^[0-9a-f]{64}$'),
  pinned_at timestamptz not null default now()
);

-- The non-super Supabase migration runner can transfer ownership only while
-- the target owner temporarily has CREATE on the containing schemas. This
-- grant is transaction-local in effect and is revoked before commit.
grant create on schema public, private to foundation_evaluation_executor;

alter table private.fit_evaluation_semantic_pins
  owner to foundation_evaluation_executor;
alter table private.fit_evaluation_semantic_pins enable row level security;
alter table private.fit_evaluation_semantic_pins force row level security;
revoke all on private.fit_evaluation_semantic_pins
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor;

create policy fit_evaluation_semantic_pins_executor_v015
on private.fit_evaluation_semantic_pins
for all to foundation_evaluation_executor
using (current_user = 'foundation_evaluation_executor')
with check (current_user = 'foundation_evaluation_executor');

create function private.guard_fit_semantic_pin_v015()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if tg_op = 'DELETE'
     and private.student_privacy_delete_allowed() then
    return old;
  end if;
  raise exception using
    errcode = '55000',
    message = 'Sealed Fit semantic pins are immutable';
end;
$$;

create trigger fit_evaluation_semantic_pins_immutable_v015
before update or delete on private.fit_evaluation_semantic_pins
for each row execute function private.guard_fit_semantic_pin_v015();

-- Frozen 014 lifecycle guards did not distinguish privacy-cascade DELETE from
-- business mutation. Preserve every 014 update rule and add only the scoped
-- 012 privacy-delete authorization for evaluation-owned Financial children.
create or replace function private.guard_fit_financial_typed_rows_v014()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if tg_op = 'DELETE' and private.student_privacy_delete_allowed() then
    return old;
  end if;
  if tg_op = 'INSERT' then
    return new;
  end if;
  raise exception using
    errcode = '55000',
    message = 'Typed Financial conversion rows are append-only';
end;
$$;

create or replace function private.guard_fit_financial_normalization_update_v014()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if tg_op = 'DELETE' and private.student_privacy_delete_allowed() then
    return old;
  end if;
  if exists (
    select 1
    from public.fit_evaluations e
    join public.fit_financial_normalization_reviews_v014 r
      on r.evaluation_id = e.evaluation_id
    where e.evaluation_id = old.evaluation_id
      and e.financial_contract_version = 'FINANCIAL_BILLING_BASIS_V014'
      and r.financial_normalization_id = old.financial_normalization_id
      and r.status in ('VERIFIED', 'RETIRED')
  ) then
    raise exception using
      errcode = '55000',
      message = 'VERIFIED Financial normalization payloads are immutable';
  end if;
  return coalesce(new, old);
end;
$$;

create or replace function private.guard_fit_financial_review_update_v014()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
begin
  if tg_op = 'DELETE' and private.student_privacy_delete_allowed() then
    return old;
  end if;
  if current_setting('app.fit_financial_v014_review_update', true)
       is distinct from 'on' then
    raise exception using
      errcode = '55000',
      message = 'Financial normalization lifecycle changes require an authorized entry point';
  end if;
  if old.status = 'DRAFT' and new.status = 'VERIFIED' then
    return new;
  end if;
  if old.status = 'VERIFIED' and new.status = 'RETIRED'
     and (
       to_jsonb(new)
         - 'status' - 'retired_at' - 'retirement_reason' - 'updated_at'
     ) is not distinct from (
       to_jsonb(old)
         - 'status' - 'retired_at' - 'retirement_reason' - 'updated_at'
     ) then
    return new;
  end if;
  raise exception using
    errcode = '55000',
    message = 'Only DRAFT to VERIFIED to RETIRED is permitted';
end;
$$;

-- A typed AVAILABLE_FUNDING input is owned by its evaluation through the
-- normalization graph. The frozen 014 RESTRICT edge to the student's intent
-- declaration prevented that graph from participating in the authorized
-- student privacy cascade. Keep the reference strict during ordinary writes,
-- but cascade the child row when its owning student graph is deleted.
alter table public.fit_financial_conversion_inputs_v014
  drop constraint
    fit_financial_conversion_inputs_v014_intent_declaration_id_fkey;
alter table public.fit_financial_conversion_inputs_v014
  add constraint
    fit_financial_conversion_inputs_v014_intent_declaration_id_fkey
  foreign key (intent_declaration_id)
  references public.fit_intent_declarations(intent_declaration_id)
  on delete cascade;

-- Return the exact payload hashed by frozen 014. The public 014 fingerprint
-- function remains unchanged; seal cross-checks this payload against it.
create function private.fit_v015_decision_input_payload(p_evaluation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_contract text;
  v_payload jsonb;
  v_financial jsonb;
begin
  select financial_contract_version into v_contract
  from public.fit_evaluations
  where evaluation_id = p_evaluation_id;
  if not found then
    return null;
  end if;

  v_payload := private.fit_decision_input_payload_v011(p_evaluation_id);
  if v_contract is null then
    return v_payload;
  end if;
  if v_contract <> 'FINANCIAL_BILLING_BASIS_V014' then
    raise exception using
      errcode = '55000',
      message = 'Unknown Financial contract version';
  end if;

  v_financial :=
    private.fit_financial_payload_collections_v014(p_evaluation_id);
  v_payload := jsonb_set(
    v_payload - 'normalizations',
    '{manifestItems}',
    coalesce((
      select jsonb_agg(item order by item::text)
      from jsonb_array_elements(v_payload -> 'manifestItems') item
      where item ->> 'type' <> 'FIT_FINANCIAL_NORMALIZATION'
    ), '[]'::jsonb)
  ) || jsonb_build_object(
    'financialContractVersion', v_contract,
    'financialSources', v_financial -> 'financialSources',
    'financialNormalizations',
      v_financial -> 'financialNormalizations'
  );
  return v_payload;
end;
$$;

-- Preserve the frozen 014 entry points as internal compatibility/validation
-- helpers. Their existing runtime grants are revoked after the rename.
alter function public.seal_fit_evaluation_inputs(uuid)
  rename to seal_fit_evaluation_inputs_v014;
alter function public.finalize_fit_evaluation(uuid)
  rename to finalize_fit_evaluation_v014_validator;

alter function public.seal_fit_evaluation_inputs_v014(uuid)
  set search_path to pg_catalog, public, private, extensions;
alter function public.finalize_fit_evaluation_v014_validator(uuid)
  set search_path to pg_catalog, public, private, extensions;

create function public.seal_fit_evaluation_inputs(p_evaluation_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_eval public.fit_evaluations%rowtype;
  v_payload jsonb;
  v_input_fingerprint text;
  v_payload_fingerprint text;
  v_result_fingerprint text;
  v_envelope jsonb;
  v_semantic_fingerprint text;
begin
  select * into v_eval
  from public.fit_evaluations
  where evaluation_id = p_evaluation_id
  for update;

  if not found then
    raise exception using
      errcode = '55000',
      message = 'A Fit evaluation is required';
  end if;
  if v_eval.replay_contract_version is null then
    if exists (
      select 1 from private.fit_evaluation_semantic_pins
      where evaluation_id = p_evaluation_id
    ) then
      raise exception using
        errcode = '55000',
        message = 'Legacy Fit evaluation cannot have a v015 semantic pin';
    end if;
    return public.seal_fit_evaluation_inputs_v014(p_evaluation_id);
  end if;
  if v_eval.replay_contract_version <> 'FIT_REPLAY_SEAL_V015' then
    raise exception using
      errcode = '55000',
      message = 'Unknown Fit replay contract version';
  end if;
  if v_eval.evaluation_state <> 'BUILDING'
     or v_eval.candidate_input_fingerprint is not null then
    raise exception using
      errcode = '55000',
      message = 'An unsealed BUILDING Fit evaluation is required';
  end if;

  perform 1
  from private.fit_evaluation_assembly_authorizations
  where evaluation_id = p_evaluation_id
  for update;
  if not found then
    raise exception using
      errcode = '42501',
      message = 'Active Fit assembly authorization is required';
  end if;

  v_payload := private.fit_v015_decision_input_payload(p_evaluation_id);
  if v_payload is null then
    raise exception using
      errcode = '55000',
      message = 'Fit decision input payload could not be materialized';
  end if;
  v_payload_fingerprint := encode(
    extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256'),
    'hex'
  );
  v_input_fingerprint :=
    public.compute_fit_decision_input_fingerprint(p_evaluation_id);
  if v_payload_fingerprint is distinct from v_input_fingerprint then
    raise exception using
      errcode = '55000',
      message = 'Fit v015 payload is not identical to the frozen 014 fingerprint payload';
  end if;

  update public.fit_evaluations
  set candidate_input_fingerprint = v_input_fingerprint
  where evaluation_id = p_evaluation_id;

  -- Execute the complete frozen 014 validator while live authority is present.
  -- The deliberate subtransaction error rolls back only its COMPLETED write.
  begin
    perform public.finalize_fit_evaluation_v014_validator(p_evaluation_id);
    raise exception using
      errcode = 'P5015',
      message = 'fit_v015_validation_rollback';
  exception
    when sqlstate 'P5015' then
      if sqlerrm <> 'fit_v015_validation_rollback' then
        raise;
      end if;
  end;

  v_result_fingerprint :=
    public.compute_fit_result_fingerprint(p_evaluation_id);
  v_envelope := jsonb_build_object(
    'replayContractVersion', 'FIT_REPLAY_SEAL_V015',
    'financialContractVersion', v_eval.financial_contract_version,
    'decisionInputPayload', v_payload,
    'decisionInputFingerprint', v_input_fingerprint,
    'resultFingerprint', v_result_fingerprint
  );
  v_semantic_fingerprint := encode(
    extensions.digest(convert_to(v_envelope::text, 'UTF8'), 'sha256'),
    'hex'
  );

  insert into private.fit_evaluation_semantic_pins (
    evaluation_id, replay_contract_version, semantic_envelope,
    semantic_fingerprint, decision_input_fingerprint, result_fingerprint
  ) values (
    p_evaluation_id, 'FIT_REPLAY_SEAL_V015', v_envelope,
    v_semantic_fingerprint, v_input_fingerprint, v_result_fingerprint
  );

  delete from private.fit_evaluation_assembly_authorizations
  where evaluation_id = p_evaluation_id;
  return v_input_fingerprint;
end;
$$;

create function public.finalize_fit_evaluation(p_evaluation_id uuid)
returns text
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions
as $$
declare
  v_eval public.fit_evaluations%rowtype;
  v_pin private.fit_evaluation_semantic_pins%rowtype;
  v_semantic_fingerprint text;
  v_payload_fingerprint text;
  v_current_result_fingerprint text;
begin
  select * into v_eval
  from public.fit_evaluations
  where evaluation_id = p_evaluation_id
  for update;

  if not found then
    raise exception using
      errcode = '55000',
      message = 'A Fit evaluation is required';
  end if;
  if v_eval.replay_contract_version is null then
    if exists (
      select 1 from private.fit_evaluation_semantic_pins
      where evaluation_id = p_evaluation_id
    ) then
      raise exception using
        errcode = '55000',
        message = 'Legacy Fit evaluation cannot have a v015 semantic pin';
    end if;
    return public.finalize_fit_evaluation_v014_validator(p_evaluation_id);
  end if;
  if v_eval.replay_contract_version <> 'FIT_REPLAY_SEAL_V015' then
    raise exception using
      errcode = '55000',
      message = 'Unknown Fit replay contract version';
  end if;
  if v_eval.evaluation_state <> 'BUILDING'
     or v_eval.candidate_input_fingerprint is null then
    raise exception using
      errcode = '55000',
      message = 'A sealed BUILDING Fit evaluation is required';
  end if;

  select * into v_pin
  from private.fit_evaluation_semantic_pins
  where evaluation_id = p_evaluation_id;
  if not found
     or v_pin.replay_contract_version <> 'FIT_REPLAY_SEAL_V015'
     or v_pin.decision_input_fingerprint
          is distinct from v_eval.candidate_input_fingerprint
     or v_pin.semantic_envelope ->> 'replayContractVersion'
          is distinct from 'FIT_REPLAY_SEAL_V015'
     or v_pin.semantic_envelope ->> 'decisionInputFingerprint'
          is distinct from v_pin.decision_input_fingerprint
     or v_pin.semantic_envelope ->> 'resultFingerprint'
          is distinct from v_pin.result_fingerprint then
    raise exception using
      errcode = '55000',
      message = 'Sealed Fit semantic pin is missing or inconsistent';
  end if;

  v_semantic_fingerprint := encode(
    extensions.digest(
      convert_to(v_pin.semantic_envelope::text, 'UTF8'), 'sha256'
    ),
    'hex'
  );
  v_payload_fingerprint := encode(
    extensions.digest(
      convert_to(
        (v_pin.semantic_envelope -> 'decisionInputPayload')::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );
  if v_semantic_fingerprint is distinct from v_pin.semantic_fingerprint
     or v_payload_fingerprint
          is distinct from v_pin.decision_input_fingerprint then
    raise exception using
      errcode = '55000',
      message = 'Sealed Fit semantic pin is corrupt';
  end if;

  -- Output rows are evaluation-owned and immutable after seal. Recompute only
  -- their frozen result hash; do not read mutable upstream semantic authority.
  v_current_result_fingerprint :=
    public.compute_fit_result_fingerprint(p_evaluation_id);
  if v_current_result_fingerprint is distinct from v_pin.result_fingerprint then
    raise exception using
      errcode = '55000',
      message = 'Sealed Fit result changed after input sealing';
  end if;

  update public.fit_evaluations
  set evaluation_state = 'COMPLETED',
      decision_input_fingerprint = v_pin.decision_input_fingerprint,
      result_fingerprint = v_pin.result_fingerprint,
      evaluated_at = now(),
      finalized_by = coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        session_user::text
      )
  where evaluation_id = p_evaluation_id;
  return v_pin.decision_input_fingerprint;
end;
$$;

alter function private.assign_fit_replay_contract_v015()
  owner to foundation_evaluation_executor;
alter function private.guard_fit_replay_contract_v015()
  owner to foundation_evaluation_executor;
alter function private.guard_fit_semantic_pin_v015()
  owner to foundation_evaluation_executor;
alter function private.fit_v015_decision_input_payload(uuid)
  owner to foundation_evaluation_executor;
alter function private.guard_fit_financial_typed_rows_v014()
  owner to foundation_evaluation_executor;
alter function private.guard_fit_financial_normalization_update_v014()
  owner to foundation_evaluation_executor;
alter function private.guard_fit_financial_review_update_v014()
  owner to foundation_evaluation_executor;
alter function public.seal_fit_evaluation_inputs_v014(uuid)
  owner to foundation_evaluation_executor;
alter function public.finalize_fit_evaluation_v014_validator(uuid)
  owner to foundation_evaluation_executor;
alter function public.seal_fit_evaluation_inputs(uuid)
  owner to foundation_evaluation_executor;
alter function public.finalize_fit_evaluation(uuid)
  owner to foundation_evaluation_executor;

revoke create on schema public, private from foundation_evaluation_executor;

revoke all on function private.assign_fit_replay_contract_v015()
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor;
revoke all on function private.guard_fit_replay_contract_v015()
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor;
revoke all on function private.guard_fit_semantic_pin_v015()
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor;
revoke all on function private.fit_v015_decision_input_payload(uuid)
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor;
revoke all on function public.seal_fit_evaluation_inputs_v014(uuid)
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor;
revoke all on function public.finalize_fit_evaluation_v014_validator(uuid)
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor;

revoke all on function public.seal_fit_evaluation_inputs(uuid)
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor;
revoke all on function public.finalize_fit_evaluation(uuid)
  from public, anon, authenticated, service_role,
       foundation_catalog_executor, foundation_student_executor;
grant execute on function public.seal_fit_evaluation_inputs(uuid)
  to service_role;
grant execute on function public.finalize_fit_evaluation(uuid)
  to service_role;

comment on column public.fit_evaluations.replay_contract_version is
  'FIT_REPLAY_SEAL_V015 opts an evaluation into seal-time semantic pinning; NULL preserves pre-015 lifecycle behavior.';
comment on table private.fit_evaluation_semantic_pins is
  'Immutable v015 decision/result envelope captured only after the complete frozen 014 validator succeeds at seal.';

commit;
