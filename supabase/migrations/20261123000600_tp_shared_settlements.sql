begin;

create table tp_inventory_sync.settlements (
  shop_id uuid not null,
  operation_id uuid not null,
  voucher_id uuid not null,
  account_id uuid not null,
  amount bigint not null check (amount between 1 and 9999999999999),
  primary key (shop_id, operation_id),
  foreign key (shop_id, operation_id) references tp_inventory_sync.events(shop_id,id),
  foreign key (shop_id, voucher_id) references tp_inventory_sync.events(shop_id,id)
);
create index tp_settlements_voucher on tp_inventory_sync.settlements(shop_id,voucher_id);
alter table tp_inventory_sync.settlements enable row level security;
revoke all on tp_inventory_sync.settlements from public, anon, authenticated;

create function public.tp_stock_sync_settle_voucher(
  shop uuid, device uuid, secret text, operation uuid, voucher uuid,
  account uuid, amount_minor bigint
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices;
  previous tp_inventory_sync.settlements;
  invoice tp_inventory_sync.events;
  settled numeric;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop,device,secret);
  perform 1 from tp_inventory_sync.shops where id = shop for update;
  if operation is null or voucher is null or account is null
    or amount_minor is null or amount_minor not between 1 and 9999999999999 then
    raise exception 'Invalid voucher payment';
  end if;
  select * into invoice from tp_inventory_sync.events
    where shop_id = shop and id = voucher and branch_id = machine.branch_id
      and kind in ('purchase','sale');
  if not found then raise exception 'Voucher is unavailable in this branch'; end if;
  select * into previous from tp_inventory_sync.settlements
    where shop_id = shop and operation_id = operation;
  if found then
    if previous.voucher_id <> voucher or previous.account_id <> account
      or previous.amount <> amount_minor then
      raise exception 'Payment ID was already used with different details';
    end if;
    return operation;
  end if;
  select coalesce(sum(s.amount),0) into settled from tp_inventory_sync.settlements s
    where s.shop_id = shop and s.voucher_id = voucher;
  if amount_minor > invoice.total_minor - invoice.paid_minor - settled then
    raise exception 'Payment exceeds the voucher balance due';
  end if;
  perform public.tp_stock_sync_post(
    shop,device,secret,operation,
    jsonb_build_object('kind',case when invoice.kind='sale' then 'deposit' else 'withdrawal' end,
      'amount_minor',amount_minor,
      case when invoice.kind='sale' then 'target_account' else 'source_account' end,account,
      'settlement_for',voucher)
  );
  insert into tp_inventory_sync.settlements values (shop,operation,voucher,account,amount_minor);
  return operation;
end
$$;
revoke all on function public.tp_stock_sync_settle_voucher(uuid,uuid,text,uuid,uuid,uuid,bigint)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_settle_voucher(uuid,uuid,text,uuid,uuid,uuid,bigint)
  to authenticated;

alter function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  rename to tp_stock_sync_branch_view_with_history;
alter function public.tp_stock_sync_branch_view_with_history(uuid,uuid,text,timestamptz,timestamptz)
  set schema tp_inventory_sync;
revoke all on function tp_inventory_sync.tp_stock_sync_branch_view_with_history(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;

create function public.tp_stock_sync_branch_view(
  shop uuid, device uuid, secret text, from_time timestamptz, until_time timestamptz
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  result jsonb := tp_inventory_sync.tp_stock_sync_branch_view_with_history(
    shop,device,secret,from_time,until_time
  );
begin
  return jsonb_set(result,'{vouchers}',(
    select coalesce(jsonb_agg(
      case when event.id is null then entry.value else entry.value || jsonb_build_object(
        'paid', (entry.value->>'paid')::bigint + payments.amount,
        'due', (entry.value->>'due')::bigint - payments.amount,
        'counterparty', event.payload->>'counterparty'
      ) end order by entry.position), '[]'::jsonb)
    from jsonb_array_elements(result->'vouchers') with ordinality as entry(value,position)
    left join tp_inventory_sync.events event
      on event.shop_id = shop and event.id = (entry.value->>'id')::uuid
    cross join lateral (
      select coalesce(sum(s.amount),0) as amount from tp_inventory_sync.settlements s
      where s.shop_id = shop and s.voucher_id = (entry.value->>'id')::uuid
    ) payments
  ));
end
$$;
revoke all on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  to authenticated;

commit;
