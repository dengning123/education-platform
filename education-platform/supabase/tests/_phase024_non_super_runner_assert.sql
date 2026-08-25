-- Run after clean 001-024 installation by the dedicated non-superuser runner.
-- The transaction rolls back its disposable owner-transfer control probe.

begin;

do $assert$
declare
  v_runner name := current_user;
  v_blocked boolean := false;
begin
  if session_user <> current_user then
    raise exception '024 non-super runner assertion requires one active login role';
  end if;
  if (select rolsuper from pg_roles where rolname = current_user) then
    raise exception '024 non-super runner assertion used a superuser';
  end if;
  if not pg_has_role(current_user, 'foundation_catalog_executor', 'MEMBER')
     or not pg_has_role(current_user, 'foundation_student_executor', 'MEMBER') then
    raise exception '024 non-super runner lacks executor SET ROLE capability';
  end if;

  if exists (
    select 1
    from unnest(array[
      'foundation_catalog_executor', 'foundation_student_executor',
      'anon', 'authenticated', 'authenticator', 'service_role'
    ]::text[]) role_name
    cross join unnest(array['public', 'private']::text[]) schema_name
    where has_schema_privilege(role_name, schema_name, 'CREATE')
  ) or exists (
    select 1
    from pg_namespace namespace
    cross join lateral aclexplode(coalesce(
      namespace.nspacl, acldefault('n', namespace.nspowner)
    )) privilege
    where namespace.nspname in ('public', 'private')
      and privilege.grantee = 0
      and privilege.privilege_type = 'CREATE'
  ) then
    raise exception '024 non-super runner found persisted schema CREATE';
  end if;

  execute 'create table public.phase024_owner_transfer_control (id integer)';
  begin
    execute 'alter table public.phase024_owner_transfer_control owner to foundation_catalog_executor';
  exception when insufficient_privilege then
    v_blocked := sqlerrm = 'permission denied for schema public';
  end;
  if not v_blocked then
    raise exception '024 owner transfer control did not fail without target CREATE';
  end if;

  execute 'grant create on schema public to foundation_catalog_executor';
  execute 'alter table public.phase024_owner_transfer_control owner to foundation_catalog_executor';
  execute 'revoke create on schema public from foundation_catalog_executor';

  if (
    select pg_get_userbyid(relation.relowner)
    from pg_class relation
    where relation.oid = 'public.phase024_owner_transfer_control'::regclass
  ) <> 'foundation_catalog_executor' then
    raise exception '024 owner transfer control assigned the wrong owner';
  end if;
  if has_schema_privilege(
    'foundation_catalog_executor', 'public', 'CREATE'
  ) then
    raise exception '024 owner transfer control leaked target CREATE';
  end if;

  execute format('set local role %I', 'foundation_catalog_executor');
  if current_user <> 'foundation_catalog_executor' then
    raise exception '024 non-super runner cannot SET ROLE to catalog executor';
  end if;
  execute 'reset role';
  if current_user <> v_runner then
    raise exception '024 non-super runner role restore failed';
  end if;
end;
$assert$;

select 'PHASE024_NON_SUPER_RUNNER_PASS';

rollback;
