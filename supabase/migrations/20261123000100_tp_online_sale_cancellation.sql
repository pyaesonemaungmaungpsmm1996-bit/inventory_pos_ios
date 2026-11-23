begin;

create table tp_inventory_sync.cancelled_sales (
  shop_id uuid not null,
  device_id uuid not null,
  id uuid not null,
  cancelled_at timestamptz not null default now(),
  primary key (shop_id,id),
  foreign key (shop_id,device_id) references tp_inventory_sync.devices
);
alter table tp_inventory_sync.cancelled_sales enable row level security;
revoke all on tp_inventory_sync.cancelled_sales from public, anon, authenticated;

create function public.tp_stock_sync_cancel_sale(shop uuid, device uuid, secret text, operation uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if operation is null then raise exception 'Operation required'; end if;
  perform tp_inventory_sync.checked_device(shop,device,secret);
  if not exists (select 1 from tp_inventory_sync.members where shop_id=shop and user_id=auth.uid()
    and role in ('owner','manager','cashier')) then
    raise exception 'Sale cancellation access denied' using errcode='42501';
  end if;
  perform 1 from tp_inventory_sync.shops where id=shop for update;
  if exists (select 1 from tp_inventory_sync.events where shop_id=shop and id=operation) then
    raise exception 'This online sale is already posted. Retry the original checkout.';
  end if;
  insert into tp_inventory_sync.cancelled_sales (shop_id,device_id,id)
  values (shop,device,operation) on conflict (shop_id,id) do nothing;
  if not exists (select 1 from tp_inventory_sync.cancelled_sales where shop_id=shop and id=operation and device_id=device) then
    raise exception 'Operation belongs to another device' using errcode='42501';
  end if;
end
$$;
revoke all on function public.tp_stock_sync_cancel_sale(uuid,uuid,text,uuid) from public, anon, authenticated;
grant execute on function public.tp_stock_sync_cancel_sale(uuid,uuid,text,uuid) to authenticated;


create or replace function public.tp_stock_sync_post(shop uuid, device uuid, secret text, operation uuid, command jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices;
  role_name text;
  previous tp_inventory_sync.events;
  operation_kind text := command->>'kind';
  offline_sale boolean := coalesce((command->>'offline')::boolean,false);
  items jsonb := coalesce(command->'lines','[]'::jsonb);
  payments jsonb := coalesce(command->'payments','[]'::jsonb);
  total numeric := 0;
  discount bigint := coalesce((command->>'discount_minor')::bigint,0);
  paid numeric := 0;
  item record;
  settlement record;
  happened timestamptz := coalesce((command->>'occurred_at')::timestamptz,now());
  source_account uuid := (command->>'source_account')::uuid;
  target_account uuid := (command->>'target_account')::uuid;
begin
  if operation is null or jsonb_typeof(command) is distinct from 'object'
    or operation_kind is null or operation_kind not in ('opening','purchase','sale','expense','deposit','withdrawal','transfer')
    or jsonb_typeof(items) is distinct from 'array' or jsonb_typeof(payments) is distinct from 'array'
    or jsonb_array_length(items)>100 or jsonb_array_length(payments)>20 then
    raise exception 'Invalid stock sync command';
  end if;
  machine := tp_inventory_sync.checked_device(shop,device,secret);
  perform 1 from tp_inventory_sync.shops where id=shop for update;
  if exists (select 1 from tp_inventory_sync.cancelled_sales where shop_id=shop and id=operation) then
    raise exception 'This online request was cancelled.';
  end if;

  select * into previous from tp_inventory_sync.events where shop_id=shop and id=operation;
  if found then
    if previous.device_id <> device or previous.payload is distinct from command then
      raise exception 'Operation ID was used for different data';
    end if;
    return operation;
  end if;

  select member.role into role_name from tp_inventory_sync.members as member
  where member.shop_id=shop and member.user_id=machine.user_id;
  if not (role_name in ('owner','manager')
    or (role_name='cashier' and operation_kind='sale')
    or (role_name='stock_staff' and operation_kind in ('opening','purchase') and jsonb_array_length(payments)=0)
    or (role_name='accountant' and operation_kind in ('expense','deposit','withdrawal','transfer'))) then
    raise exception 'Permission denied for this operation' using errcode='42501';
  end if;
  if offline_sale and operation_kind <> 'sale' then raise exception 'Only sales use offline allocation'; end if;

  if operation_kind in ('opening','purchase','sale') then
    if jsonb_array_length(items)=0 then raise exception 'At least one product is required'; end if;
    if exists (select 1 from jsonb_to_recordset(items) as row(product_id uuid,quantity bigint,unit_minor bigint,line_minor bigint)
      left join tp_inventory_sync.products as product on product.shop_id=shop and product.id=row.product_id
      where product.id is null or row.quantity is null or row.quantity not between 1 and 999999999
        or row.unit_minor is null or row.unit_minor not between 0 and 9999999999999
        or (row.line_minor is not null and row.line_minor not between 0 and row.quantity::numeric*row.unit_minor)
        or (operation_kind='opening' and row.unit_minor<>0))
      or exists (select 1 from jsonb_to_recordset(items) as row(product_id uuid)
        group by product_id having count(*)>1) then raise exception 'Invalid or repeated product line'; end if;
    select sum(coalesce(line_minor::numeric,quantity::numeric*unit_minor)) into total
      from jsonb_to_recordset(items) as row(quantity bigint,unit_minor bigint,line_minor bigint);
    if discount < 0 or discount > total or (discount > 0 and operation_kind <> 'sale') then
      raise exception 'Invalid document discount';
    end if;
    total := total-discount;
  else
    if jsonb_array_length(items)<>0 then raise exception 'Non-stock operation has product lines'; end if;
    total := (command->>'amount_minor')::bigint;
    if total is null or total<=0 then raise exception 'A positive amount is required'; end if;
    if operation_kind <> 'expense' and jsonb_array_length(payments)<>0 then
      raise exception 'Account adjustments use source and target accounts';
    end if;
  end if;
  if total>9999999999999 then raise exception 'Operation total too large'; end if;
  if operation_kind='opening' and jsonb_array_length(payments)<>0 then raise exception 'Opening stock cannot have payments'; end if;

  if exists (select 1 from jsonb_to_recordset(payments) as row(account_id uuid,amount_minor bigint)
    left join tp_inventory_sync.accounts as account
      on account.shop_id=shop and account.branch_id=machine.branch_id and account.id=row.account_id
    where account.id is null or row.amount_minor is null or row.amount_minor not between 1 and 9999999999999
      or (offline_sale and account.kind <> 'cash')) then raise exception 'Invalid payment for this branch or mode'; end if;
  select coalesce(sum(amount_minor::numeric),0) into paid
    from jsonb_to_recordset(payments) as row(amount_minor bigint);
  if paid>total or (operation_kind='expense' and paid<>total) then raise exception 'Invalid settlement total'; end if;
  if operation_kind in ('sale','purchase') and paid<total
    and nullif(btrim(command->>'counterparty'),'') is null then
    raise exception 'Counterparty required on outstanding balances';
  end if;

  for item in select * from jsonb_to_recordset(items) as row(product_id uuid,quantity bigint) loop
    if operation_kind='sale' then
      if offline_sale then
        update tp_inventory_sync.device_stock set consumed=consumed+item.quantity
        where shop_id=shop and branch_id=machine.branch_id and device_id=device and product_id=item.product_id
          and granted-consumed>=item.quantity;
        if not found then raise exception 'Offline sale exceeds device allocation'; end if;
        update tp_inventory_sync.stock set on_hand=on_hand-item.quantity,reserved=reserved-item.quantity
        where shop_id=shop and branch_id=machine.branch_id and product_id=item.product_id
          and reserved>=item.quantity;
      else
        update tp_inventory_sync.stock set on_hand=on_hand-item.quantity
        where shop_id=shop and branch_id=machine.branch_id and product_id=item.product_id
          and on_hand-reserved>=item.quantity;
      end if;
      if not found then raise exception 'Insufficient available stock'; end if;
    else
      if operation_kind='opening' then
        insert into tp_inventory_sync.stock(shop_id,branch_id,product_id,on_hand)
          values (shop,machine.branch_id,item.product_id,item.quantity)
          on conflict (shop_id,branch_id,product_id) do nothing;
        if not found then raise exception 'Opening stock already recorded or a movement exists'; end if;
      else
        insert into tp_inventory_sync.stock(shop_id,branch_id,product_id,on_hand)
          values (shop,machine.branch_id,item.product_id,item.quantity)
          on conflict (shop_id,branch_id,product_id) do update set on_hand=stock.on_hand+excluded.on_hand;
      end if;
    end if;
  end loop;

  for settlement in select * from jsonb_to_recordset(payments) as row(account_id uuid,amount_minor bigint) loop
    update tp_inventory_sync.accounts set balance_minor=balance_minor
      + case when operation_kind='sale' then settlement.amount_minor else -settlement.amount_minor end
      where shop_id=shop and branch_id=machine.branch_id and id=settlement.account_id;
  end loop;
  if operation_kind in ('withdrawal','transfer') then
    update tp_inventory_sync.accounts set balance_minor=balance_minor-total
      where shop_id=shop and branch_id=machine.branch_id and id=source_account;
    if not found then raise exception 'Source account is outside this branch or missing'; end if;
    paid := total;
  end if;
  if operation_kind in ('deposit','transfer') then
    if operation_kind='transfer' and source_account=target_account then raise exception 'Transfer requires different accounts'; end if;
    update tp_inventory_sync.accounts set balance_minor=balance_minor+total
      where shop_id=shop and branch_id=machine.branch_id and id=target_account;
    if not found then raise exception 'Target account is outside this branch or missing'; end if;
    paid := total;
  end if;
  insert into tp_inventory_sync.events(shop_id,branch_id,device_id,id,kind,offline,total_minor,paid_minor,payload,occurred_at)
    values (shop,machine.branch_id,device,operation,operation_kind,offline_sale,total,paid,command,happened);
  update tp_inventory_sync.devices set last_sync_at=clock_timestamp() where shop_id=shop and id=device;
  perform tp_inventory_sync.signal(shop);
  return operation;
end
$$;

commit;
