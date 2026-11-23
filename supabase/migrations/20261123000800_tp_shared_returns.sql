begin;

create table tp_inventory_sync.sale_refunds (
  shop_id uuid not null,
  operation_id uuid not null,
  sale_id uuid not null,
  device_id uuid not null,
  product_id uuid not null,
  account_id uuid not null,
  quantity bigint not null check (quantity > 0),
  serials text[] not null,
  amount bigint not null check (amount >= 0),
  created_at timestamptz not null default clock_timestamp(),
  primary key (shop_id, operation_id),
  foreign key (shop_id,sale_id) references tp_inventory_sync.events(shop_id,id),
  foreign key (shop_id,device_id) references tp_inventory_sync.devices(shop_id,id),
  foreign key (shop_id,product_id) references tp_inventory_sync.products(shop_id,id)
);
create index tp_sale_refunds_sale on tp_inventory_sync.sale_refunds(shop_id,sale_id);
alter table tp_inventory_sync.sale_refunds enable row level security;
revoke all on tp_inventory_sync.sale_refunds from public, anon, authenticated;

create function tp_inventory_sync.prevent_void_after_refund()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if exists (select 1 from tp_inventory_sync.sale_refunds r
    where r.shop_id = new.shop_id and r.sale_id = new.voucher_id) then
    raise exception 'A voucher with a return cannot be voided';
  end if;
  return new;
end
$$;
create trigger tp_prevent_void_after_refund before insert on tp_inventory_sync.voucher_voids
  for each row execute function tp_inventory_sync.prevent_void_after_refund();

create function public.tp_stock_sync_return_sale(
  shop uuid, device uuid, secret text, operation uuid, sale uuid, product uuid,
  units bigint, serial_numbers text[], account uuid, refund bigint
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices;
  invoice tp_inventory_sync.events;
  previous tp_inventory_sync.sale_refunds;
  sold record;
  serial_list text[];
  returned bigint;
  line_refunded numeric;
  total_refunded numeric;
  line_gross numeric;
  sale_gross numeric;
  preceding_gross numeric;
  line_paid numeric;
  affected bigint;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop,device,secret);
  perform 1 from tp_inventory_sync.shops where id = shop for update;
  if operation is null or sale is null or product is null or account is null
    or units is null or units not between 1 and 999999999
    or refund is null or refund not between 0 and 9999999999999 then
    raise exception 'Invalid sale return';
  end if;
  select coalesce(array_agg(upper(btrim(value)) order by upper(btrim(value))),array[]::text[])
    into serial_list from unnest(serial_numbers) as x(value);
  select * into invoice from tp_inventory_sync.events
    where shop_id = shop and id = sale and branch_id = machine.branch_id and kind = 'sale';
  if not found then raise exception 'Sale is unavailable in this branch'; end if;
  select * into previous from tp_inventory_sync.sale_refunds r
    where r.shop_id = shop and r.operation_id = operation;
  if found then
    if previous.sale_id = sale and previous.device_id = device and previous.product_id = product
      and previous.quantity = units and previous.serials = serial_list
      and previous.account_id = account and previous.amount = refund then return operation; end if;
    raise exception 'Return ID was already used with different details';
  end if;
  if invoice.offline or invoice.paid_minor <> invoice.total_minor
    or exists (select 1 from tp_inventory_sync.voucher_voids v
      where v.shop_id = shop and v.voucher_id = sale) then
    raise exception 'Only fully paid, active online sales can be returned here';
  end if;
  select * into sold from jsonb_to_recordset(invoice.payload->'lines')
    l(product_id uuid, quantity bigint, unit_minor bigint, line_minor bigint, serials jsonb)
    where l.product_id = product;
  if not found then raise exception 'Product is not on this sale'; end if;
  select coalesce(sum(r.quantity),0), coalesce(sum(r.amount),0) into returned,line_refunded
    from tp_inventory_sync.sale_refunds r
    where r.shop_id = shop and r.sale_id = sale and r.product_id = product;
  if units > sold.quantity - returned then raise exception 'Return exceeds the quantity sold'; end if;
  select coalesce(sum(r.amount),0) into total_refunded from tp_inventory_sync.sale_refunds r
    where r.shop_id = shop and r.sale_id = sale;
  select sum(coalesce(l.line_minor::numeric,l.quantity::numeric * l.unit_minor)),
    coalesce(sum(coalesce(l.line_minor::numeric,l.quantity::numeric * l.unit_minor))
      filter (where l.product_id < product),0)
    into sale_gross,preceding_gross
    from jsonb_to_recordset(invoice.payload->'lines')
      l(product_id uuid, quantity bigint, unit_minor bigint, line_minor bigint);
  line_gross := coalesce(sold.line_minor::numeric,sold.quantity::numeric * sold.unit_minor);
  line_paid := case when sale_gross > 0 then
    floor(invoice.paid_minor * (preceding_gross + line_gross) / sale_gross)
    - floor(invoice.paid_minor * preceding_gross / sale_gross) else 0 end;
  if refund + total_refunded > invoice.paid_minor
    or refund + line_refunded > floor(line_paid * (returned + units) / sold.quantity) then
    raise exception 'Refund exceeds the paid amount for these units';
  end if;
  if sold.serials is not null then
    if cardinality(serial_list) <> units or
      (select count(distinct value) from unnest(serial_list) x(value)) <> units then
      raise exception 'Enter one distinct serial per returned unit';
    end if;
    update tp_inventory_sync.serial_units set sold_event = null
      where shop_id = shop and branch_id = machine.branch_id and product_id = product
        and sold_event = sale and serial = any(serial_list);
    get diagnostics affected = row_count;
    if affected <> units then raise exception 'Serial was not sold on this voucher or was already returned'; end if;
  elsif cardinality(serial_list) <> 0 then
    raise exception 'This sale line does not use serial tracking';
  end if;
  update tp_inventory_sync.stock set on_hand = on_hand + units
    where shop_id = shop and branch_id = machine.branch_id and product_id = product;
  if not found then raise exception 'Sold stock record is unavailable'; end if;
  update tp_inventory_sync.accounts set balance_minor = balance_minor - refund
    where shop_id = shop and branch_id = machine.branch_id and id = account
      and balance_minor >= refund;
  if not found then raise exception 'Refund account is unavailable or has insufficient funds'; end if;
  insert into tp_inventory_sync.sale_refunds
    (shop_id,operation_id,sale_id,device_id,product_id,account_id,quantity,serials,amount)
    values (shop,operation,sale,device,product,account,units,serial_list,refund);
  perform tp_inventory_sync.signal(shop);
  return operation;
end
$$;
revoke all on function public.tp_stock_sync_return_sale(uuid,uuid,text,uuid,uuid,uuid,bigint,text[],uuid,bigint)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_return_sale(uuid,uuid,text,uuid,uuid,uuid,bigint,text[],uuid,bigint)
  to authenticated;

alter function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  rename to tp_stock_sync_branch_view_with_voids;
alter function public.tp_stock_sync_branch_view_with_voids(uuid,uuid,text,timestamptz,timestamptz)
  set schema tp_inventory_sync;
revoke all on function tp_inventory_sync.tp_stock_sync_branch_view_with_voids(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;

create function public.tp_stock_sync_branch_view(
  shop uuid, device uuid, secret text, from_time timestamptz, until_time timestamptz
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare result jsonb := tp_inventory_sync.tp_stock_sync_branch_view_with_voids(shop,device,secret,from_time,until_time);
begin
  return jsonb_set(result,'{vouchers}',(
    select coalesce(jsonb_agg(
      case when event.id is null then entry.value else entry.value || jsonb_build_object(
        'can_return', not event.offline and event.paid_minor = event.total_minor
          and entry.value->>'status' = 'posted',
        'can_void', coalesce((entry.value->>'can_void')::boolean,false) and returns.amount is null,
        'refunded', coalesce(returns.amount,0),
        'returns', coalesce(returns.details,'[]'::jsonb)
      ) end order by entry.position), '[]'::jsonb)
    from jsonb_array_elements(result->'vouchers') with ordinality as entry(value,position)
    left join tp_inventory_sync.events event
      on event.shop_id = shop and event.id = (entry.value->>'id')::uuid and event.kind = 'sale'
    cross join lateral (
      select sum(r.amount) as amount, jsonb_agg(jsonb_build_object(
        'product_id',r.product_id,'quantity',r.quantity,'serials',r.serials,'amount',r.amount,
        'created_at',r.created_at
      ) order by r.created_at,r.operation_id) as details
      from tp_inventory_sync.sale_refunds r where r.shop_id = shop and r.sale_id = event.id
    ) returns
  ));
end
$$;
revoke all on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  to authenticated;

commit;
