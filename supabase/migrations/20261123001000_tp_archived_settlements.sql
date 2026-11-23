begin;

create table tp_inventory_sync.archived_settlements (
  shop_id uuid not null,
  branch_id uuid not null,
  operation_id uuid not null,
  archive_key text not null,
  account_id uuid not null,
  amount bigint not null check (amount between 1 and 9999999999999),
  primary key (shop_id, operation_id),
  foreign key (shop_id,branch_id) references tp_inventory_sync.opening_imports(shop_id,branch_id),
  foreign key (shop_id,operation_id) references tp_inventory_sync.events(shop_id,id)
);
create index tp_archived_settlement_voucher
  on tp_inventory_sync.archived_settlements(shop_id,branch_id,archive_key);
alter table tp_inventory_sync.archived_settlements enable row level security;
revoke all on tp_inventory_sync.archived_settlements from public, anon, authenticated;

create function public.tp_stock_sync_settle_archived(
  shop uuid, device uuid, secret text, operation uuid, archive_key text,
  account uuid, amount_minor bigint
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices;
  invoice jsonb;
  previous tp_inventory_sync.archived_settlements;
  recorded numeric;
  target_key text := archive_key;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop,device,secret);
  perform 1 from tp_inventory_sync.shops where id = shop for update;
  if operation is null or account is null or target_key is null
    or amount_minor is null or amount_minor not between 1 and 9999999999999 then
    raise exception 'Invalid archived voucher payment';
  end if;
  select entry.value into invoice
    from tp_inventory_sync.opening_imports i
    cross join lateral jsonb_array_elements(i.history) entry
    where i.shop_id = shop and i.branch_id = machine.branch_id
      and entry.value->>'status' = 'posted' and entry.value->>'kind' in ('sale','purchase')
      and concat(entry.value->>'kind', ':', entry.value->>'number') = target_key;
  if not found then raise exception 'Archived voucher is unavailable in this branch'; end if;
  select * into previous from tp_inventory_sync.archived_settlements
    where shop_id = shop and operation_id = operation;
  if found then
    if previous.branch_id <> machine.branch_id or previous.archive_key <> target_key
      or previous.account_id <> account or previous.amount <> amount_minor then
      raise exception 'Payment ID was already used with different details';
    end if;
    return operation;
  end if;
  select coalesce(sum(s.amount),0) into recorded from tp_inventory_sync.archived_settlements s
    where s.shop_id = shop and s.branch_id = machine.branch_id and s.archive_key = target_key;
  if amount_minor > (invoice->>'due')::bigint - recorded then
    raise exception 'Payment exceeds the archived voucher balance due';
  end if;
  perform public.tp_stock_sync_post(shop,device,secret,operation,jsonb_build_object(
    'kind',case when invoice->>'kind' = 'sale' then 'deposit' else 'withdrawal' end,
    'amount_minor',amount_minor,
    case when invoice->>'kind' = 'sale' then 'target_account' else 'source_account' end,account,
    'archived_settlement_for',target_key
  ));
  insert into tp_inventory_sync.archived_settlements
    values (shop,machine.branch_id,operation,target_key,account,amount_minor);
  return operation;
end
$$;
revoke all on function public.tp_stock_sync_settle_archived(uuid,uuid,text,uuid,text,uuid,bigint)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_settle_archived(uuid,uuid,text,uuid,text,uuid,bigint)
  to authenticated;

create function tp_inventory_sync.adjust_archived_balance(shop uuid, branch uuid, voucher jsonb)
returns jsonb language sql stable set search_path = ''
as $$
  select case when voucher->>'archived' is distinct from 'true' then voucher else
    voucher || jsonb_build_object(
      'archive_key',concat(voucher->>'kind',':',voucher->>'number'),
      'paid',(voucher->>'paid')::bigint + payments.amount,
      'due',(voucher->>'due')::bigint - payments.amount
    ) end
  from (
    select coalesce(sum(s.amount),0) as amount
    from tp_inventory_sync.archived_settlements s
    where s.shop_id = shop and s.branch_id = branch
      and s.archive_key = concat(voucher->>'kind',':',voucher->>'number')
  ) payments
$$;

alter function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  rename to tp_stock_sync_branch_view_with_returns;
alter function public.tp_stock_sync_branch_view_with_returns(uuid,uuid,text,timestamptz,timestamptz)
  set schema tp_inventory_sync;
revoke all on function tp_inventory_sync.tp_stock_sync_branch_view_with_returns(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;
create function public.tp_stock_sync_branch_view(
  shop uuid, device uuid, secret text, from_time timestamptz, until_time timestamptz
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb := tp_inventory_sync.tp_stock_sync_branch_view_with_returns(shop,device,secret,from_time,until_time);
begin
  return jsonb_set(result,'{vouchers}',(
    select coalesce(jsonb_agg(tp_inventory_sync.adjust_archived_balance(
      shop,(result->>'branch_id')::uuid,entry.value
    ) order by entry.position),'[]'::jsonb)
    from jsonb_array_elements(result->'vouchers') with ordinality entry(value,position)
  ));
end
$$;
revoke all on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz) from public, anon, authenticated;
grant execute on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz) to authenticated;

alter function public.tp_stock_sync_open_balances(uuid,uuid,text,text) rename to tp_stock_sync_open_balances_before_archive_payments;
alter function public.tp_stock_sync_open_balances_before_archive_payments(uuid,uuid,text,text) set schema tp_inventory_sync;
revoke all on function tp_inventory_sync.tp_stock_sync_open_balances_before_archive_payments(uuid,uuid,text,text) from public, anon, authenticated;
create function public.tp_stock_sync_open_balances(shop uuid, device uuid, secret text, voucher_kind text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices := tp_inventory_sync.checked_device(shop,device,secret);
  result jsonb := tp_inventory_sync.tp_stock_sync_open_balances_before_archive_payments(shop,device,secret,voucher_kind);
begin
  return (
    select coalesce(jsonb_agg(voucher order by position),'[]'::jsonb)
    from (
      select tp_inventory_sync.adjust_archived_balance(shop,machine.branch_id,entry.value) voucher, entry.position
      from jsonb_array_elements(result) with ordinality entry(value,position)
    ) adjusted where (voucher->>'due')::bigint > 0
  );
end
$$;
revoke all on function public.tp_stock_sync_open_balances(uuid,uuid,text,text) from public, anon, authenticated;
grant execute on function public.tp_stock_sync_open_balances(uuid,uuid,text,text) to authenticated;

commit;
