begin;

alter table tp_inventory_sync.accounts drop constraint accounts_kind_check;
alter table tp_inventory_sync.accounts add constraint accounts_kind_check
  check (kind in ('cash', 'bank', 'wallet'));

create table tp_inventory_sync.opening_imports (
  shop_id uuid not null,
  branch_id uuid not null,
  digest bytea not null,
  history jsonb not null,
  imported_at timestamptz not null default clock_timestamp(),
  primary key (shop_id, branch_id),
  foreign key (shop_id, branch_id) references tp_inventory_sync.branches
);
alter table tp_inventory_sync.opening_imports enable row level security;
revoke all on tp_inventory_sync.opening_imports from public, anon, authenticated;

-- Opening quantities and balances are snapshots. Replaying old vouchers here
-- would apply their stock and money effects a second time.
create function public.tp_stock_sync_import_opening(
  shop uuid, device uuid, secret text, document jsonb
) returns boolean
language plpgsql security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices;
  business tp_inventory_sync.shops;
  branch_code text;
  fingerprint bytea;
  previous bytea;
  item record;
  account record;
  product_row tp_inventory_sync.products;
  account_id uuid;
  stock_lines jsonb := '[]'::jsonb;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop, device, secret);
  select * into strict business from tp_inventory_sync.shops where id = shop for update;
  select code into strict branch_code from tp_inventory_sync.branches
    where shop_id = shop and id = machine.branch_id;
  if jsonb_typeof(document) is distinct from 'object'
    or document->>'branch_code' is distinct from branch_code
    or document->>'currency' is distinct from business.currency
    or jsonb_typeof(document->'products') is distinct from 'array'
    or jsonb_typeof(document->'accounts') is distinct from 'array'
    or jsonb_typeof(document->'history') is distinct from 'array'
    or octet_length(document::text) > 2000000 then
    raise exception 'Invalid opening import, branch, currency, or size';
  end if;
  fingerprint := sha256(convert_to(document::text, 'UTF8'));
  select i.digest into previous from tp_inventory_sync.opening_imports i
    where i.shop_id = shop and i.branch_id = machine.branch_id;
  if found then
    if previous = fingerprint then return false; end if;
    raise exception 'Opening balances have already been imported for this branch';
  end if;
  if exists (select 1 from tp_inventory_sync.events where shop_id = shop and branch_id = machine.branch_id)
    or exists (select 1 from tp_inventory_sync.accounts where shop_id = shop and branch_id = machine.branch_id)
    or exists (select 1 from tp_inventory_sync.stock where shop_id = shop and branch_id = machine.branch_id) then
    raise exception 'Opening import requires a branch without cloud stock, accounts or transactions';
  end if;
  if exists (select 1 from jsonb_to_recordset(document->'products') p(code text)
    group by p.code having count(*) > 1)
    or exists (select 1 from jsonb_to_recordset(document->'accounts') a(name text)
    group by lower(a.name) having count(*) > 1) then
    raise exception 'Duplicate product or account in opening import';
  end if;

  for item in select * from jsonb_to_recordset(document->'products')
      p(code text, name text, price bigint, quantity bigint, serial_tracking boolean, serials jsonb)
  loop
    if item.quantity is null or item.quantity not between 0 and 999999999
      or item.serial_tracking is null
      or (item.serial_tracking and (jsonb_typeof(item.serials) is distinct from 'array'
        or jsonb_array_length(item.serials) <> item.quantity))
      or (not item.serial_tracking and item.serials is not null) then
      raise exception 'Invalid opening stock or serials for item %', item.code;
    end if;
    select * into product_row from tp_inventory_sync.products
      where shop_id = shop and code = item.code;
    if found then
      if product_row.name is distinct from item.name
        or product_row.sale_price_minor is distinct from item.price
        or product_row.serial_tracking is distinct from item.serial_tracking then
        raise exception 'Opening catalog conflicts with existing item %', item.code;
      end if;
    else
      insert into tp_inventory_sync.products(shop_id, code, name, sale_price_minor, serial_tracking)
        values (shop, item.code, item.name, item.price, item.serial_tracking)
        returning * into product_row;
    end if;
    if item.quantity > 0 then
      stock_lines := stock_lines || jsonb_build_array(
        jsonb_build_object('product_id', product_row.id, 'quantity', item.quantity, 'unit_minor', 0)
        || case when item.serial_tracking then jsonb_build_object('serials', item.serials) else '{}'::jsonb end
      );
      if jsonb_array_length(stock_lines) = 100 then
        perform public.tp_stock_sync_post(shop, device, secret, gen_random_uuid(),
          jsonb_build_object('kind', 'opening', 'lines', stock_lines));
        stock_lines := '[]'::jsonb;
      end if;
    end if;
  end loop;
  if jsonb_array_length(stock_lines) > 0 then
    perform public.tp_stock_sync_post(shop, device, secret, gen_random_uuid(),
      jsonb_build_object('kind', 'opening', 'lines', stock_lines));
  end if;

  for account in select * from jsonb_to_recordset(document->'accounts')
      a(name text, kind text, balance bigint)
  loop
    if account.balance is null or account.balance not between 0 and 9999999999999 then
      raise exception 'Unsupported opening balance for account %', account.name;
    end if;
    insert into tp_inventory_sync.accounts(shop_id, branch_id, name, kind)
      values (shop, machine.branch_id, account.name, account.kind) returning id into account_id;
    if account.balance > 0 then
      perform public.tp_stock_sync_post(shop, device, secret, gen_random_uuid(),
        jsonb_build_object('kind', 'deposit', 'amount_minor', account.balance, 'target_account', account_id));
    end if;
  end loop;
  if exists (
    select 1 from jsonb_to_recordset(document->'history')
      v(kind text, number text, invoice_date date, status text, total bigint, paid bigint, due bigint)
    where kind is null or kind not in ('sale', 'purchase', 'expense')
      or number is null or btrim(number) = '' or invoice_date is null
      or status is null or status not in ('posted', 'void')
      or total is null or total < 0 or paid is null or paid not between 0 and total
      or due is null or due <> total - paid
  ) then raise exception 'Invalid archived voucher'; end if;
  insert into tp_inventory_sync.opening_imports(shop_id, branch_id, digest, history)
    values (shop, machine.branch_id, fingerprint, document->'history');
  perform tp_inventory_sync.signal(shop);
  return true;
end
$$;
revoke all on function public.tp_stock_sync_import_opening(uuid,uuid,text,jsonb) from public, anon, authenticated;
grant execute on function public.tp_stock_sync_import_opening(uuid,uuid,text,jsonb) to authenticated;

alter function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  set schema tp_inventory_sync;
revoke all on function tp_inventory_sync.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;

create function public.tp_stock_sync_branch_view(
  shop uuid, device uuid, secret text, from_time timestamptz, until_time timestamptz
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  result jsonb := tp_inventory_sync.tp_stock_sync_branch_view(shop, device, secret, from_time, until_time);
  history jsonb;
begin
  select i.history into history from tp_inventory_sync.opening_imports i
    where i.shop_id = shop and i.branch_id = (result->>'branch_id')::uuid;
  return jsonb_set(result, '{vouchers}', (
    select coalesce(jsonb_agg(voucher order by voucher->>'occurred_at' desc, voucher->>'number'), '[]'::jsonb)
    from (
      select entry.value || jsonb_build_object('lines', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'product_id', product.id, 'item_code', product.code, 'item_name', product.name, 'qty', line.quantity,
          'unit_price', line.unit_minor, 'amount', coalesce(line.line_minor, line.quantity * line.unit_minor),
          'serials', line.serials
        ) order by line.product_id), '[]'::jsonb)
        from jsonb_to_recordset(event.payload->'lines')
          line(product_id uuid, quantity bigint, unit_minor bigint, line_minor bigint, serials jsonb)
        join tp_inventory_sync.products product on product.shop_id = shop and product.id = line.product_id
      )) as voucher
      from jsonb_array_elements(result->'vouchers') entry
      join tp_inventory_sync.events event on event.shop_id = shop and event.id = (entry.value->>'id')::uuid
      union all
      select value || jsonb_build_object('occurred_at',
        (value->>'invoice_date')::date::timestamp at time zone 'Asia/Yangon', 'archived', true)
      from jsonb_array_elements(history)
      where ((value->>'invoice_date')::date::timestamp at time zone 'Asia/Yangon') >= from_time
        and ((value->>'invoice_date')::date::timestamp at time zone 'Asia/Yangon') < until_time
    ) v
  ));
end
$$;
revoke all on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  to authenticated;

commit;
