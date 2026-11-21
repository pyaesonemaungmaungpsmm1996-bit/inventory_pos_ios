begin;

create table tp_private.shared_money_accounts (
  business_id uuid not null,
  branch_id uuid not null,
  id uuid not null default gen_random_uuid(),
  name text not null check (name = btrim(name) and char_length(name) between 1 and 100),
  kind text not null check (kind in ('cash', 'bank', 'wallet')),
  opening_date date not null,
  opening_amount bigint not null check (opening_amount between 0 and 9000000000000),
  revision bigint not null default 1 check (revision > 0),
  primary key (business_id, branch_id, id),
  foreign key (business_id, branch_id) references tp_private.branches(business_id, id)
);

create unique index shared_money_accounts_branch_name
  on tp_private.shared_money_accounts (business_id, branch_id, lower(name));

alter table tp_private.shared_money_accounts enable row level security;
revoke all on tp_private.shared_money_accounts from public, anon, authenticated;

-- A retry may repeat the same opening account but may never replace it.
create function public.tp_initialize_shared_money_account(
  p_business uuid, p_branch uuid, p_installation uuid,
  p_name text, p_kind text, p_opening_date date, p_opening_amount bigint
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_account tp_private.shared_money_accounts%rowtype;
  v_name text := btrim(p_name);
begin
  if tp_private.require_sale_branch(p_business, p_branch, p_installation) <> 'owner' then
    raise exception 'Only the owner can initialize an opening balance' using errcode = '42501';
  end if;

  insert into tp_private.shared_money_accounts
    (business_id, branch_id, name, kind, opening_date, opening_amount)
  values (p_business, p_branch, v_name, p_kind, p_opening_date, p_opening_amount)
  on conflict (business_id, branch_id, lower(name)) do nothing
  returning * into v_account;

  if not found then
    select * into strict v_account from tp_private.shared_money_accounts
    where business_id = p_business and branch_id = p_branch and lower(name) = lower(v_name);
    if (v_account.kind, v_account.opening_date, v_account.opening_amount)
        is distinct from (p_kind, p_opening_date, p_opening_amount) then
      raise exception 'Account already exists with different opening details' using errcode = '23505';
    end if;
  end if;
  return to_jsonb(v_account);
end;
$$;

create function public.tp_list_shared_money_accounts(
  p_business uuid, p_branch uuid, p_installation uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  if tp_private.require_sale_branch(p_business, p_branch, p_installation) not in ('owner', 'manager') then
    raise exception 'Money account access requires owner or manager permissions' using errcode = '42501';
  end if;
  return (
    select coalesce(jsonb_agg(to_jsonb(a) order by lower(a.name), a.id), '[]'::jsonb)
    from tp_private.shared_money_accounts a
    where a.business_id = p_business and a.branch_id = p_branch
  );
end;
$$;

revoke all on function public.tp_initialize_shared_money_account(uuid, uuid, uuid, text, text, date, bigint) from public, anon;
revoke all on function public.tp_list_shared_money_accounts(uuid, uuid, uuid) from public, anon;
grant execute on function public.tp_initialize_shared_money_account(uuid, uuid, uuid, text, text, date, bigint) to authenticated;
grant execute on function public.tp_list_shared_money_accounts(uuid, uuid, uuid) to authenticated;

commit;
