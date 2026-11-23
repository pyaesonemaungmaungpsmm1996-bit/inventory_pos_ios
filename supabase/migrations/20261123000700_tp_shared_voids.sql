begin;

create table tp_inventory_sync.voucher_voids (
  shop_id uuid not null,
  voucher_id uuid not null,
  operation_id uuid not null,
  device_id uuid not null,
  reason text not null check (length(reason) between 1 and 300),
  voided_at timestamptz not null default clock_timestamp(),
  primary key (shop_id,voucher_id),
  unique (shop_id,operation_id),
  foreign key (shop_id,voucher_id) references tp_inventory_sync.events(shop_id,id),
  foreign key (shop_id,device_id) references tp_inventory_sync.devices(shop_id,id)
);
alter table tp_inventory_sync.voucher_voids enable row level security;
revoke all on tp_inventory_sync.voucher_voids from public, anon, authenticated;

-- Settlement and void RPCs acquire the same shop lock before writing.
create function tp_inventory_sync.require_open_voucher()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if exists (select 1 from tp_inventory_sync.voucher_voids v
    where v.shop_id = new.shop_id and v.voucher_id = new.voucher_id) then
    raise exception 'Cannot settle a voided voucher';
  end if;
  return new;
end
$$;
create trigger tp_require_open_voucher before insert on tp_inventory_sync.settlements
  for each row execute function tp_inventory_sync.require_open_voucher();

create function public.tp_stock_sync_void_voucher(
  shop uuid, device uuid, secret text, operation uuid, voucher uuid, reason text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices;
  invoice tp_inventory_sync.events;
  previous tp_inventory_sync.voucher_voids;
  line record;
  payment record;
  serial_count bigint;
  affected bigint;
  clean text := btrim(reason);
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop,device,secret);
  perform 1 from tp_inventory_sync.shops where id = shop for update;
  if operation is null or voucher is null or clean is null or length(clean) not between 1 and 300 then
    raise exception 'Voucher and void reason are required';
  end if;
  select * into invoice from tp_inventory_sync.events
    where shop_id = shop and id = voucher and branch_id = machine.branch_id
      and kind in ('sale','purchase');
  if not found then raise exception 'Voucher is unavailable in this branch'; end if;
  select * into previous from tp_inventory_sync.voucher_voids v
    where v.shop_id = shop and v.voucher_id = voucher;
  if found then
    if previous.operation_id = operation and previous.device_id = device and previous.reason = clean then
      return operation;
    end if;
    raise exception 'Voucher is already voided';
  end if;
  if invoice.offline then raise exception 'Offline vouchers cannot be voided here'; end if;
  if exists (select 1 from tp_inventory_sync.settlements s
    where s.shop_id = shop and s.voucher_id = voucher) then
    raise exception 'A voucher with later payments cannot be voided here';
  end if;
  for line in
    select * from jsonb_to_recordset(invoice.payload->'lines') l(product_id uuid, quantity bigint, serials jsonb)
  loop
    serial_count := coalesce(jsonb_array_length(line.serials),0);
    if invoice.kind = 'purchase' then
      update tp_inventory_sync.stock set on_hand = on_hand-line.quantity
      where shop_id = shop and branch_id = machine.branch_id and product_id = line.product_id
        and on_hand-reserved >= line.quantity;
      if not found then raise exception 'Purchased stock is no longer available'; end if;
      if serial_count > 0 then
        delete from tp_inventory_sync.serial_units
        where shop_id = shop and branch_id = machine.branch_id and product_id = line.product_id
          and received_event = voucher and sold_event is null;
        get diagnostics affected = row_count;
        if affected <> serial_count then raise exception 'A purchased serial has already been sold'; end if;
      end if;
    else
      update tp_inventory_sync.stock set on_hand = on_hand+line.quantity
      where shop_id = shop and branch_id = machine.branch_id and product_id = line.product_id;
      if not found then raise exception 'Sold stock record is unavailable'; end if;
      if serial_count > 0 then
        update tp_inventory_sync.serial_units set sold_event = null
        where shop_id = shop and branch_id = machine.branch_id and product_id = line.product_id
          and sold_event = voucher;
        get diagnostics affected = row_count;
        if affected <> serial_count then raise exception 'A sold serial is no longer available to restore'; end if;
      end if;
    end if;
  end loop;
  for payment in
    select * from jsonb_to_recordset(invoice.payload->'payments') p(account_id uuid, amount_minor bigint)
  loop
    update tp_inventory_sync.accounts
      set balance_minor = balance_minor + case when invoice.kind = 'sale'
        then -payment.amount_minor else payment.amount_minor end
    where shop_id = shop and branch_id = machine.branch_id and id = payment.account_id;
    if not found then raise exception 'Payment account is unavailable'; end if;
  end loop;
  insert into tp_inventory_sync.voucher_voids(shop_id,voucher_id,operation_id,device_id,reason)
    values (shop,voucher,operation,device,clean);
  perform tp_inventory_sync.signal(shop);
  return operation;
end
$$;
revoke all on function public.tp_stock_sync_void_voucher(uuid,uuid,text,uuid,uuid,text)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_void_voucher(uuid,uuid,text,uuid,uuid,text)
  to authenticated;

alter function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  rename to tp_stock_sync_branch_view_with_settlements;
alter function public.tp_stock_sync_branch_view_with_settlements(uuid,uuid,text,timestamptz,timestamptz)
  set schema tp_inventory_sync;
revoke all on function tp_inventory_sync.tp_stock_sync_branch_view_with_settlements(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;

create function public.tp_stock_sync_branch_view(
  shop uuid, device uuid, secret text, from_time timestamptz, until_time timestamptz
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  result jsonb := tp_inventory_sync.tp_stock_sync_branch_view_with_settlements(
    shop,device,secret,from_time,until_time
  );
begin
  return jsonb_set(result,'{vouchers}',(
    select coalesce(jsonb_agg(
      entry.value || case
        when reversal.voucher_id is not null then jsonb_build_object(
          'status','void','void_reason',reversal.reason,'can_void',false,'due',0
        )
        when event.id is not null and event.kind in ('sale','purchase') then jsonb_build_object(
          'status','posted','can_void',not event.offline and not exists (
            select 1 from tp_inventory_sync.settlements s
            where s.shop_id = shop and s.voucher_id = event.id
          )
        )
        else '{}'::jsonb
      end order by entry.position), '[]'::jsonb)
    from jsonb_array_elements(result->'vouchers') with ordinality as entry(value,position)
    left join tp_inventory_sync.events event on event.shop_id = shop and event.id = (entry.value->>'id')::uuid
    left join tp_inventory_sync.voucher_voids reversal on reversal.shop_id = shop and reversal.voucher_id = event.id
  ));
end
$$;
revoke all on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  to authenticated;

commit;
