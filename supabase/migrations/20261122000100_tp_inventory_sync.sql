begin;

-- This schema is independent of the legacy Live Sales and Shared Products schemas.
create schema tp_inventory_sync;
revoke all on schema tp_inventory_sync from public, anon, authenticated;

create table tp_inventory_sync.shops (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now()
);
create table tp_inventory_sync.members (
  shop_id uuid not null references tp_inventory_sync.shops,
  user_id uuid not null references auth.users,
  role text not null check (role in ('owner','manager','cashier','stock_staff','accountant')),
  primary key (shop_id,user_id)
);
create table tp_inventory_sync.branches (
  shop_id uuid not null references tp_inventory_sync.shops,
  id uuid not null default gen_random_uuid(),
  code text not null check (char_length(btrim(code)) between 1 and 40),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  primary key (shop_id,id),
  unique (shop_id,code)
);
create table tp_inventory_sync.products (
  shop_id uuid not null references tp_inventory_sync.shops,
  id uuid not null default gen_random_uuid(),
  code text not null check (char_length(btrim(code)) between 1 and 80),
  name text not null check (char_length(btrim(name)) between 1 and 200),
  sale_price_minor bigint not null check (sale_price_minor between 0 and 9999999999999),
  primary key (shop_id,id),
  unique (shop_id,code)
);
create table tp_inventory_sync.accounts (
  shop_id uuid not null,
  branch_id uuid not null,
  id uuid not null default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 120),
  kind text not null check (kind in ('cash','bank')),
  balance_minor bigint not null default 0 check (balance_minor between 0 and 9999999999999),
  primary key (shop_id,branch_id,id),
  foreign key (shop_id,branch_id) references tp_inventory_sync.branches
);
create table tp_inventory_sync.devices (
  shop_id uuid not null,
  branch_id uuid not null,
  id uuid not null,
  user_id uuid not null,
  label text not null check (char_length(btrim(label)) between 1 and 120),
  secret_hash bytea not null,
  approved_at timestamptz,
  last_sync_at timestamptz,
  primary key (shop_id,id),
  unique (shop_id,branch_id,id),
  foreign key (shop_id,branch_id) references tp_inventory_sync.branches,
  foreign key (shop_id,user_id) references tp_inventory_sync.members
);
create table tp_inventory_sync.stock (
  shop_id uuid not null,
  branch_id uuid not null,
  product_id uuid not null,
  on_hand bigint not null default 0 check (on_hand between 0 and 999999999999),
  reserved bigint not null default 0 check (reserved between 0 and on_hand),
  primary key (shop_id,branch_id,product_id),
  foreign key (shop_id,branch_id) references tp_inventory_sync.branches,
  foreign key (shop_id,product_id) references tp_inventory_sync.products
);
create table tp_inventory_sync.device_stock (
  shop_id uuid not null,
  branch_id uuid not null,
  device_id uuid not null,
  product_id uuid not null,
  granted bigint not null check (granted >= 0),
  consumed bigint not null default 0 check (consumed between 0 and granted),
  primary key (shop_id,branch_id,device_id,product_id),
  foreign key (shop_id,branch_id,device_id) references tp_inventory_sync.devices(shop_id,branch_id,id),
  foreign key (shop_id,branch_id,product_id) references tp_inventory_sync.stock
);
create table tp_inventory_sync.events (
  shop_id uuid not null,
  branch_id uuid not null,
  device_id uuid not null,
  id uuid not null,
  kind text not null check (kind in ('opening','purchase','sale','expense','deposit','withdrawal','transfer')),
  offline boolean not null,
  total_minor bigint not null check (total_minor between 0 and 9999999999999),
  paid_minor bigint not null check (paid_minor between 0 and total_minor),
  payload jsonb not null,
  occurred_at timestamptz not null,
  committed_at timestamptz not null default now(),
  primary key (shop_id,id),
  foreign key (shop_id,branch_id,device_id) references tp_inventory_sync.devices(shop_id,branch_id,id)
);
create index tp_sync_events_report on tp_inventory_sync.events(shop_id,branch_id,occurred_at,id);
create table tp_inventory_sync.admin_requests (
  shop_id uuid not null references tp_inventory_sync.shops,
  id uuid not null,
  command jsonb not null,
  result uuid not null,
  primary key (shop_id,id)
);

create table public.tp_stock_sync_changes (
  shop_id uuid primary key references tp_inventory_sync.shops,
  revision bigint not null default 1
);
alter table public.tp_stock_sync_changes enable row level security;
revoke all on public.tp_stock_sync_changes from public, anon, authenticated;
grant select on public.tp_stock_sync_changes to authenticated;
create function public.tp_stock_sync_is_member(shop uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from tp_inventory_sync.members where shop_id=shop and user_id=auth.uid())
$$;
revoke all on function public.tp_stock_sync_is_member(uuid) from public, anon, authenticated;
grant execute on function public.tp_stock_sync_is_member(uuid) to authenticated;
create policy tp_stock_sync_changes_member on public.tp_stock_sync_changes for select to authenticated
  using (public.tp_stock_sync_is_member(shop_id));
alter publication supabase_realtime add table public.tp_stock_sync_changes;

create function tp_inventory_sync.signal(shop uuid)
returns void language sql set search_path = ''
as $$
  insert into public.tp_stock_sync_changes(shop_id) values (shop)
  on conflict (shop_id) do update set revision=tp_stock_sync_changes.revision+1
$$;

do $$
declare name text;
begin
  foreach name in array array['shops','members','branches','products','accounts','devices','stock','device_stock','events','admin_requests'] loop
    execute format('alter table tp_inventory_sync.%I enable row level security',name);
    execute format('revoke all on tp_inventory_sync.%I from public, anon, authenticated',name);
  end loop;
end
$$;

create function tp_inventory_sync.require_owner(shop uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from tp_inventory_sync.members where shop_id=shop
    and user_id=auth.uid() and role='owner') then
    raise exception 'Owner access required' using errcode='42501';
  end if;
end
$$;

create function tp_inventory_sync.checked_device(shop uuid, device uuid, secret text)
returns tp_inventory_sync.devices language plpgsql security definer set search_path = ''
as $$
declare row tp_inventory_sync.devices;
begin
  if auth.uid() is null or secret is null or char_length(secret) <> 64 then
    raise exception 'Device access denied' using errcode='42501';
  end if;
  select * into row from tp_inventory_sync.devices where shop_id=shop and id=device
    and user_id=auth.uid() and approved_at is not null
    and secret_hash=sha256(convert_to(secret,'UTF8'));
  if not found then raise exception 'Device access denied' using errcode='42501'; end if;
  return row;
end
$$;

create function public.tp_stock_sync_create_shop(name text, currency text, branch_code text, branch_name text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare shop uuid; branch uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  insert into tp_inventory_sync.shops(name,currency) values (btrim(name),currency) returning id into shop;
  insert into tp_inventory_sync.members values (shop,auth.uid(),'owner');
  insert into tp_inventory_sync.branches(shop_id,code,name)
    values (shop,btrim(branch_code),btrim(branch_name)) returning id into branch;
  perform tp_inventory_sync.signal(shop);
  return jsonb_build_object('shop_id',shop,'branch_id',branch);
end
$$;

create function public.tp_stock_sync_admin(shop uuid, operation uuid, command jsonb)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  action text := command->>'action';
  branch uuid := (command->>'branch_id')::uuid;
  product uuid := (command->>'product_id')::uuid;
  device uuid := (command->>'device_id')::uuid;
  target_user uuid := (command->>'user_id')::uuid;
  quantity bigint := (command->>'quantity')::bigint;
  row_id uuid;
  previous tp_inventory_sync.admin_requests;
begin
  perform tp_inventory_sync.require_owner(shop);
  if operation is null or action is null then raise exception 'Invalid admin request'; end if;
  perform 1 from tp_inventory_sync.shops where id=shop for update;
  select * into previous from tp_inventory_sync.admin_requests where shop_id=shop and id=operation;
  if found then
    if previous.command is distinct from command then raise exception 'Operation ID was used for different data'; end if;
    return previous.result;
  end if;
  case action
  when 'member' then
    if command->>'role' is null or command->>'role' not in ('manager','cashier','stock_staff','accountant') then
      raise exception 'Invalid role';
    end if;
    insert into tp_inventory_sync.members values (shop,target_user,command->>'role');
    row_id := target_user;
  when 'branch' then
    insert into tp_inventory_sync.branches(shop_id,code,name)
    values (shop,btrim(command->>'code'),btrim(command->>'name')) returning id into row_id;
  when 'product' then
    insert into tp_inventory_sync.products(shop_id,id,code,name,sale_price_minor)
    values (shop,coalesce(product,gen_random_uuid()),btrim(command->>'code'),btrim(command->>'name'),(command->>'sale_price_minor')::bigint)
    on conflict (shop_id,id) do update set code=excluded.code,name=excluded.name,sale_price_minor=excluded.sale_price_minor
    returning id into row_id;
  when 'account' then
    insert into tp_inventory_sync.accounts(shop_id,branch_id,name,kind)
    values (shop,branch,btrim(command->>'name'),command->>'kind') returning id into row_id;
  when 'approve_device' then
    update tp_inventory_sync.devices set approved_at=coalesce(approved_at,clock_timestamp())
    where shop_id=shop and id=device returning id into row_id;
    if not found then raise exception 'Device not enrolled'; end if;
  when 'grant_stock' then
    if quantity is null or quantity not between 1 and 999999999 or device is null then
      raise exception 'Invalid device allocation';
    end if;
    select branch_id into branch from tp_inventory_sync.devices as d
    join tp_inventory_sync.members as member using (shop_id,user_id)
    where d.shop_id=shop and d.id=device and d.approved_at is not null
      and member.role in ('owner','manager','cashier');
    if not found then raise exception 'Approved selling device required'; end if;
    update tp_inventory_sync.stock set reserved=reserved+quantity
    where shop_id=shop and branch_id=branch and product_id=product and on_hand-reserved>=quantity;
    if not found then raise exception 'Insufficient unallocated stock'; end if;
    insert into tp_inventory_sync.device_stock(shop_id,branch_id,device_id,product_id,granted)
    values (shop,branch,device,product,quantity)
    on conflict (shop_id,branch_id,device_id,product_id) do update
    set granted=device_stock.granted+excluded.granted;
    row_id := device;
  else raise exception 'Unknown admin command';
  end case;
  insert into tp_inventory_sync.admin_requests values (shop,operation,command,row_id);
  perform tp_inventory_sync.signal(shop);
  return row_id;
end
$$;

create function public.tp_stock_sync_enroll(shop uuid, branch uuid, device uuid, label text, secret text)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare current_device tp_inventory_sync.devices;
begin
  if auth.uid() is null or secret is null or secret !~ '^[0-9a-f]{64}$' or device is null then
    raise exception 'Authentication and a device secret are required' using errcode='42501';
  end if;
  if not exists (select 1 from tp_inventory_sync.members where shop_id=shop and user_id=auth.uid()) then
    raise exception 'Shop membership required' using errcode='42501';
  end if;
  insert into tp_inventory_sync.devices(shop_id,branch_id,id,user_id,label,secret_hash)
    values (shop,branch,device,auth.uid(),btrim(label),sha256(convert_to(secret,'UTF8')))
    on conflict (shop_id,id) do nothing;
  if found then perform tp_inventory_sync.signal(shop); end if;
  select * into strict current_device from tp_inventory_sync.devices where shop_id=shop and id=device;
  if current_device.user_id <> auth.uid() or current_device.branch_id <> branch
    or current_device.secret_hash <> sha256(convert_to(secret,'UTF8')) then
    raise exception 'Device access denied' using errcode='42501';
  end if;
  return current_device.approved_at is not null;
end
$$;

create function public.tp_stock_sync_post(shop uuid, device uuid, secret text, operation uuid, command jsonb)
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

create function public.tp_stock_sync_snapshot(shop uuid, device uuid, secret text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare machine tp_inventory_sync.devices;
begin
  machine := tp_inventory_sync.checked_device(shop,device,secret);
  update tp_inventory_sync.devices set last_sync_at=clock_timestamp() where shop_id=shop and id=device;
  return (
    select jsonb_build_object('branch_id',machine.branch_id,'currency',s.currency,
      'products',coalesce((
        select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name,'sale_price_minor',p.sale_price_minor,
          'on_hand',coalesce(i.on_hand,0),'available_online',coalesce(i.on_hand-i.reserved,0),
          'device_granted',coalesce(q.granted,0),'device_consumed',coalesce(q.consumed,0)) order by p.code)
        from tp_inventory_sync.products as p
        left join tp_inventory_sync.stock as i on i.shop_id=p.shop_id and i.product_id=p.id and i.branch_id=machine.branch_id
        left join tp_inventory_sync.device_stock as q on q.shop_id=p.shop_id and q.product_id=p.id and q.branch_id=machine.branch_id and q.device_id=device
        where p.shop_id=shop
      ),'[]'::jsonb),
      'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'kind',a.kind) order by a.name)
        from tp_inventory_sync.accounts as a where a.shop_id=shop and a.branch_id=machine.branch_id),'[]'::jsonb))
    from tp_inventory_sync.shops as s where s.id=shop
  );
end
$$;

create function public.tp_stock_sync_owner_report(shop uuid, from_time timestamptz, until_time timestamptz)
returns jsonb language plpgsql security definer set search_path = ''
as $$
begin
  perform tp_inventory_sync.require_owner(shop);
  if from_time is null or until_time is null or from_time>=until_time then raise exception 'Invalid report period'; end if;
  return (
    select jsonb_build_object('name',s.name,'currency',s.currency,'branches',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',b.id,'name',b.name,'code',b.code,
        'sale_minor',coalesce(t.sales,0),'paid_sale_minor',coalesce(t.paid,0),
        'expense_minor',coalesce(t.expense,0),
        'sales',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'amount_minor',e.total_minor,
          'paid_minor',e.paid_minor,'occurred_at',e.occurred_at,'offline',e.offline,
          'voucher',e.payload->>'voucher') order by e.occurred_at desc,e.id)
          from tp_inventory_sync.events as e where e.shop_id=shop and e.branch_id=b.id
          and e.kind='sale' and e.occurred_at>=from_time and e.occurred_at<until_time),'[]'::jsonb),
        'expenses',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'amount_minor',e.total_minor,
          'note',e.payload->>'note','payments',e.payload->'payments','occurred_at',e.occurred_at) order by e.occurred_at desc,e.id)
          from tp_inventory_sync.events as e where e.shop_id=shop and e.branch_id=b.id
          and e.kind='expense' and e.occurred_at>=from_time and e.occurred_at<until_time),'[]'::jsonb),
        'stock',coalesce((select jsonb_agg(jsonb_build_object('product_id',p.id,'name',p.name,'code',p.code,
          'on_hand',i.on_hand,'reserved',i.reserved,'available_online',i.on_hand-i.reserved) order by p.code)
          from tp_inventory_sync.stock as i join tp_inventory_sync.products as p on p.shop_id=i.shop_id and p.id=i.product_id
          where i.shop_id=shop and i.branch_id=b.id),'[]'::jsonb),
        'accounts',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'name',a.name,'kind',a.kind,'balance_minor',a.balance_minor)
          order by a.name) from tp_inventory_sync.accounts as a where a.shop_id=shop and a.branch_id=b.id),'[]'::jsonb),
        'devices',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'label',d.label,
          'approved',d.approved_at is not null,'last_sync_at',d.last_sync_at) order by d.label)
          from tp_inventory_sync.devices as d where d.shop_id=shop and d.branch_id=b.id),'[]'::jsonb)
      ) order by b.code)
      from tp_inventory_sync.branches as b
      left join lateral (
        select sum(total_minor) filter (where kind='sale') as sales,
          sum(paid_minor) filter (where kind='sale') as paid,
          sum(total_minor) filter (where kind='expense') as expense
        from tp_inventory_sync.events as e where e.shop_id=shop and e.branch_id=b.id
          and e.occurred_at>=from_time and e.occurred_at<until_time
      ) as t on true
      where b.shop_id=shop
    ),'[]'::jsonb))
    from tp_inventory_sync.shops as s where s.id=shop
  );
end
$$;

create function public.tp_stock_sync_catalog()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'role',m.role,'currency',s.currency,
    'branches',coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'code',b.code) order by b.code)
      from tp_inventory_sync.branches as b where b.shop_id=s.id),'[]'::jsonb),
    'products',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'code',p.code) order by p.code)
      from tp_inventory_sync.products as p where p.shop_id=s.id),'[]'::jsonb)
  ) order by s.name),'[]'::jsonb)
  from tp_inventory_sync.members as m join tp_inventory_sync.shops as s on s.id=m.shop_id
  where m.user_id=auth.uid()
$$;
revoke all on function public.tp_stock_sync_catalog() from public, anon, authenticated;
grant execute on function public.tp_stock_sync_catalog() to authenticated;

revoke all on function public.tp_stock_sync_create_shop(text,text,text,text),
  public.tp_stock_sync_admin(uuid,uuid,jsonb), public.tp_stock_sync_enroll(uuid,uuid,uuid,text,text),
  public.tp_stock_sync_post(uuid,uuid,text,uuid,jsonb), public.tp_stock_sync_snapshot(uuid,uuid,text),
  public.tp_stock_sync_owner_report(uuid,timestamptz,timestamptz) from public, anon, authenticated;
grant execute on function public.tp_stock_sync_create_shop(text,text,text,text),
  public.tp_stock_sync_admin(uuid,uuid,jsonb), public.tp_stock_sync_enroll(uuid,uuid,uuid,text,text),
  public.tp_stock_sync_post(uuid,uuid,text,uuid,jsonb), public.tp_stock_sync_snapshot(uuid,uuid,text),
  public.tp_stock_sync_owner_report(uuid,timestamptz,timestamptz) to authenticated;

commit;
