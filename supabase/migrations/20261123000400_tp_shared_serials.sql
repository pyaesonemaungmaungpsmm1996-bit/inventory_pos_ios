begin;

alter table tp_inventory_sync.products
  add column serial_tracking boolean not null default false;

create table tp_inventory_sync.serial_units (
  shop_id uuid not null,
  branch_id uuid not null,
  product_id uuid not null,
  serial text not null check (length(serial) between 1 and 100),
  received_event uuid not null,
  sold_event uuid,
  primary key (shop_id, serial),
  foreign key (shop_id, branch_id, product_id) references tp_inventory_sync.stock,
  foreign key (shop_id, received_event) references tp_inventory_sync.events deferrable initially deferred,
  foreign key (shop_id, sold_event) references tp_inventory_sync.events deferrable initially deferred
);
create index tp_serial_available on tp_inventory_sync.serial_units(shop_id, branch_id, product_id)
  where sold_event is null;
alter table tp_inventory_sync.serial_units enable row level security;
revoke all on tp_inventory_sync.serial_units from public, anon, authenticated;

create function public.tp_stock_sync_enable_serial(shop uuid, product uuid)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform tp_inventory_sync.require_owner(shop);
  perform 1 from tp_inventory_sync.shops where id = shop for update;
  if exists (select 1 from tp_inventory_sync.products
    where shop_id = shop and id = product and serial_tracking) then return; end if;
  if exists (select 1 from tp_inventory_sync.stock where shop_id = shop and product_id = product) then
    raise exception 'Set serial tracking before receiving stock';
  end if;
  update tp_inventory_sync.products set serial_tracking = true
    where shop_id = shop and id = product;
  if not found then raise exception 'Product not found'; end if;
  perform tp_inventory_sync.signal(shop);
end
$$;
revoke all on function public.tp_stock_sync_enable_serial(uuid,uuid) from public, anon, authenticated;
grant execute on function public.tp_stock_sync_enable_serial(uuid,uuid) to authenticated;

create function tp_inventory_sync.record_serial_units()
returns trigger language plpgsql set search_path = ''
as $$
declare
  line record;
  serial_list text[];
  code text;
begin
  if new.kind not in ('opening','purchase','sale') then return new; end if;
  for line in
    select l.*, p.serial_tracking
    from jsonb_to_recordset(new.payload->'lines') l(product_id uuid, quantity bigint, serials jsonb)
    join tp_inventory_sync.products p on p.shop_id = new.shop_id and p.id = l.product_id
  loop
    if not line.serial_tracking then
      if line.serials is not null then raise exception 'This item does not use serial tracking'; end if;
      continue;
    end if;
    if new.offline then raise exception 'Serial-tracked sales require an online connection'; end if;
    if jsonb_typeof(line.serials) is distinct from 'array'
      or jsonb_array_length(line.serials) <> line.quantity then
      raise exception 'Enter one serial per unit';
    end if;
    if exists (select 1 from jsonb_array_elements(line.serials) as item(value)
      where jsonb_typeof(value) <> 'string') then
      raise exception 'Serials must be text';
    end if;
    select array_agg(upper(btrim(value))) into serial_list
      from jsonb_array_elements_text(line.serials);
    if exists (select 1 from unnest(serial_list) as item(value)
      where length(value) not between 1 and 100)
      or (select count(distinct value) from unnest(serial_list) as item(value)) <> line.quantity then
      raise exception 'Serials must be nonempty, unique and at most 100 characters';
    end if;
    foreach code in array serial_list loop
      if new.kind = 'sale' then
        update tp_inventory_sync.serial_units set sold_event = new.id
        where shop_id = new.shop_id and branch_id = new.branch_id
          and product_id = line.product_id and serial = code and sold_event is null;
        if not found then raise exception 'Serial is not available at this branch: %', code; end if;
      else
        insert into tp_inventory_sync.serial_units(shop_id, branch_id, product_id, serial, received_event)
          values (new.shop_id, new.branch_id, line.product_id, code, new.id);
      end if;
    end loop;
  end loop;
  return new;
end
$$;
create trigger tp_record_serial_units before insert on tp_inventory_sync.events
  for each row execute function tp_inventory_sync.record_serial_units();

create function tp_inventory_sync.prevent_serial_allocation()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if exists (select 1 from tp_inventory_sync.products
    where shop_id = new.shop_id and id = new.product_id and serial_tracking) then
    raise exception 'Serial-tracked products cannot use offline allocations';
  end if;
  return new;
end
$$;
create trigger tp_prevent_serial_allocation before insert or update on tp_inventory_sync.device_stock
  for each row execute function tp_inventory_sync.prevent_serial_allocation();

create function public.tp_stock_sync_branch_serials(shop uuid, device uuid, secret text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare machine tp_inventory_sync.devices;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop, device, secret);
  return coalesce((
    select jsonb_object_agg(p.id, coalesce((
      select jsonb_agg(u.serial order by u.serial)
      from tp_inventory_sync.serial_units u
      where u.shop_id = shop and u.branch_id = machine.branch_id
        and u.product_id = p.id and u.sold_event is null
    ), '[]'::jsonb))
    from tp_inventory_sync.products p where p.shop_id = shop and p.serial_tracking
  ), '{}'::jsonb);
end
$$;
revoke all on function public.tp_stock_sync_branch_serials(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.tp_stock_sync_branch_serials(uuid,uuid,text) to authenticated;

commit;
