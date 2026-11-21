begin;

-- Shared ledger entries are immutable. Reversals are separate entries.
create table tp_private.shared_money_entries (
  business_id uuid not null,
  branch_id uuid not null,
  account_id uuid not null,
  request_id uuid not null,
  amount bigint not null check (amount between -9000000000000 and 9000000000000 and amount <> 0),
  entry_date date not null,
  created_at timestamptz not null default now(),
  primary key (business_id, branch_id, account_id, request_id),
  foreign key (business_id, branch_id, account_id)
    references tp_private.shared_money_accounts (business_id, branch_id, id)
);

alter table tp_private.shared_money_entries enable row level security;
revoke all on tp_private.shared_money_entries from public, anon, authenticated;

create function public.tp_list_shared_money_balances(
  p_business uuid, p_branch uuid, p_installation uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  if tp_private.require_sale_branch(p_business, p_branch, p_installation)
      not in ('owner', 'manager', 'accountant') then
    raise exception 'Money balance access requires financial permissions' using errcode = '42501';
  end if;

  return (
    select coalesce(jsonb_agg(to_jsonb(b) order by lower(b.name), b.id), '[]'::jsonb)
    from (
      select a.id, a.name, a.kind, a.opening_date, a.revision,
             a.opening_amount + coalesce(sum(e.amount), 0) as balance
      from tp_private.shared_money_accounts a
      left join tp_private.shared_money_entries e
        on (e.business_id, e.branch_id, e.account_id) = (a.business_id, a.branch_id, a.id)
      where a.business_id = p_business and a.branch_id = p_branch
      group by a.business_id, a.branch_id, a.id
    ) b
  );
end;
$$;

revoke all on function public.tp_list_shared_money_balances(uuid, uuid, uuid) from public, anon;
grant execute on function public.tp_list_shared_money_balances(uuid, uuid, uuid) to authenticated;

commit;
