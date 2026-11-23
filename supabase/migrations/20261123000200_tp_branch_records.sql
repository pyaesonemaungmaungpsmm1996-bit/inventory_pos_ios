begin;

create table tp_inventory_sync.branch_records (
  shop_id uuid not null,
  branch_id uuid not null,
  device_id uuid not null,
  records jsonb not null,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (shop_id, branch_id),
  foreign key (shop_id, branch_id, device_id)
    references tp_inventory_sync.devices(shop_id, branch_id, id)
);
alter table tp_inventory_sync.branch_records enable row level security;
revoke all on tp_inventory_sync.branch_records from public, anon, authenticated;

create function public.tp_stock_sync_publish_records(shop uuid, device uuid, secret text, document jsonb)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices;
  branch_code text;
  existing tp_inventory_sync.branch_records;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop, device, secret);
  perform 1 from tp_inventory_sync.shops where id = shop for update;
  select code into strict branch_code from tp_inventory_sync.branches
    where shop_id = shop and id = machine.branch_id;
  if jsonb_typeof(document) is distinct from 'object'
    or document->>'branch_code' is distinct from branch_code
    or octet_length(document::text) > 2000000
    or jsonb_typeof(document->'stock') is distinct from 'array'
    or jsonb_typeof(document->'sales') is distinct from 'array'
    or jsonb_typeof(document->'purchases') is distinct from 'array' then
    raise exception 'Invalid branch records or 2 MB limit exceeded';
  end if;
  select * into existing from tp_inventory_sync.branch_records
    where shop_id = shop and branch_id = machine.branch_id;
  if found then
    if existing.device_id <> device then
      raise exception 'A different Windows device already publishes this branch' using errcode = '42501';
    end if;
    if existing.records = document then return false; end if;
  end if;
  insert into tp_inventory_sync.branch_records(shop_id, branch_id, device_id, records)
    values (shop, machine.branch_id, device, document)
    on conflict (shop_id, branch_id) do update
      set records = excluded.records, updated_at = clock_timestamp();
  perform tp_inventory_sync.signal(shop);
  return true;
end
$$;

create function public.tp_stock_sync_read_records(shop uuid, device uuid, secret text)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare machine tp_inventory_sync.devices;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop, device, secret);
  return (select records || jsonb_build_object('updated_at', updated_at)
    from tp_inventory_sync.branch_records where shop_id = shop and branch_id = machine.branch_id);
end
$$;

revoke all on function public.tp_stock_sync_publish_records(uuid,uuid,text,jsonb),
  public.tp_stock_sync_read_records(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.tp_stock_sync_publish_records(uuid,uuid,text,jsonb),
  public.tp_stock_sync_read_records(uuid,uuid,text) to authenticated;

commit;
