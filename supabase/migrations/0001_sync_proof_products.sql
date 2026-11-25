-- Toe Pwar POS sync proof: one product entity only.
-- This migration is intentionally namespaced so it can be tested without touching
-- the existing POS tables. Do not treat this as the full production schema.

create extension if not exists pgcrypto;

create table if not exists public.sync_proof_memberships (
  business_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'manager', 'cashier')),
  active boolean not null default true,
  primary key (business_id, user_id)
);

create table if not exists public.sync_proof_products (
  id uuid primary key,
  business_id uuid not null,
  name text not null check (length(trim(name)) between 1 and 160),
  price bigint not null check (price >= 0),
  version bigint not null default 1 check (version > 0),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (business_id, id)
);

create index if not exists sync_proof_products_business_updated
  on public.sync_proof_products (business_id, updated_at, id);

create table if not exists public.sync_proof_operations (
  operation_id uuid primary key,
  business_id uuid not null,
  device_id text not null check (length(trim(device_id)) between 1 and 120),
  operation_type text not null,
  entity_id uuid not null,
  payload jsonb not null,
  result jsonb,
  created_at timestamptz not null default now(),
  applied_at timestamptz
);

create table if not exists public.sync_proof_events (
  event_id bigint generated always as identity primary key,
  business_id uuid not null,
  entity_type text not null,
  entity_id uuid not null,
  operation_id uuid not null references public.sync_proof_operations(operation_id),
  event_type text not null,
  version bigint not null,
  payload jsonb not null,
  created_at timestamptz not null default now()
);

create index if not exists sync_proof_events_business_cursor
  on public.sync_proof_events (business_id, event_id);

create or replace function public.sync_proof_is_member(p_business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.sync_proof_memberships m
    where m.business_id = p_business_id
      and m.user_id = auth.uid()
      and m.active
  );
$$;

revoke all on function public.sync_proof_is_member(uuid) from public;
grant execute on function public.sync_proof_is_member(uuid) to authenticated;

create or replace function public.sync_proof_upsert_product(
  p_operation_id uuid,
  p_business_id uuid,
  p_device_id text,
  p_product_id uuid,
  p_name text,
  p_price bigint,
  p_expected_version bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  existing public.sync_proof_operations;
  current_product public.sync_proof_products;
  next_version bigint;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'Authentication required';
  end if;
  if not public.sync_proof_is_member(p_business_id) then
    raise exception using errcode = '42501', message = 'Business membership required';
  end if;
  if length(trim(p_device_id)) = 0 or length(trim(p_name)) = 0 or p_price < 0 then
    raise exception using errcode = '22023', message = 'Invalid product payload';
  end if;

  select * into existing
  from public.sync_proof_operations
  where operation_id = p_operation_id;

  if found then
    if existing.business_id <> p_business_id or existing.entity_id <> p_product_id then
      raise exception using errcode = '23505', message = 'Operation id was reused for another entity';
    end if;
    return coalesce(existing.result, jsonb_build_object('status', 'pending'));
  end if;

  insert into public.sync_proof_operations(
    operation_id, business_id, device_id, operation_type, entity_id, payload
  ) values (
    p_operation_id, p_business_id, p_device_id, 'product.upsert', p_product_id,
    jsonb_build_object('name', trim(p_name), 'price', p_price, 'expected_version', p_expected_version)
  );

  select * into current_product
  from public.sync_proof_products
  where business_id = p_business_id and id = p_product_id
  for update;

  if found and p_expected_version is not null and current_product.version <> p_expected_version then
    v_result := jsonb_build_object(
      'status', 'conflict',
      'operation_id', p_operation_id,
      'server', jsonb_build_object(
        'id', current_product.id,
        'name', current_product.name,
        'price', current_product.price,
        'version', current_product.version,
        'updated_at', current_product.updated_at
      )
    );
    update public.sync_proof_operations
    set result = v_result, applied_at = now()
    where operation_id = p_operation_id;
    return v_result;
  end if;

  next_version := case when found then current_product.version + 1 else 1 end;

  insert into public.sync_proof_products(
    id, business_id, name, price, version, updated_by, updated_at, deleted_at
  ) values (
    p_product_id, p_business_id, trim(p_name), p_price, next_version, auth.uid(), now(), null
  )
  on conflict (id) do update set
    name = excluded.name,
    price = excluded.price,
    version = excluded.version,
    updated_by = excluded.updated_by,
    updated_at = excluded.updated_at,
    deleted_at = null;

  insert into public.sync_proof_events(
    business_id, entity_type, entity_id, operation_id, event_type, version, payload
  ) values (
    p_business_id, 'product', p_product_id, p_operation_id, 'upsert', next_version,
    jsonb_build_object('id', p_product_id, 'name', trim(p_name), 'price', p_price, 'version', next_version)
  );

  v_result := jsonb_build_object(
    'status', 'applied',
    'operation_id', p_operation_id,
    'product', jsonb_build_object(
      'id', p_product_id,
      'name', trim(p_name),
      'price', p_price,
      'version', next_version
    )
  );

  update public.sync_proof_operations
  set result = v_result, applied_at = now()
  where operation_id = p_operation_id;
  return v_result;
end;
$$;

revoke all on function public.sync_proof_upsert_product(uuid, uuid, text, uuid, text, bigint, bigint) from public;
grant execute on function public.sync_proof_upsert_product(uuid, uuid, text, uuid, text, bigint, bigint) to authenticated;

create or replace function public.sync_proof_pull_events(
  p_business_id uuid,
  p_after_event_id bigint default 0,
  p_limit integer default 100
)
returns table (
  event_id bigint,
  entity_type text,
  entity_id uuid,
  operation_id uuid,
  event_type text,
  version bigint,
  payload jsonb,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select e.event_id, e.entity_type, e.entity_id, e.operation_id,
         e.event_type, e.version, e.payload, e.created_at
  from public.sync_proof_events e
  where e.business_id = p_business_id
    and e.event_id > greatest(p_after_event_id, 0)
    and public.sync_proof_is_member(p_business_id)
  order by e.event_id
  limit least(greatest(p_limit, 1), 500);
$$;

revoke all on function public.sync_proof_pull_events(uuid, bigint, integer) from public;
grant execute on function public.sync_proof_pull_events(uuid, bigint, integer) to authenticated;

alter table public.sync_proof_memberships enable row level security;
alter table public.sync_proof_products enable row level security;
alter table public.sync_proof_operations enable row level security;
alter table public.sync_proof_events enable row level security;

drop policy if exists sync_proof_memberships_select on public.sync_proof_memberships;
create policy sync_proof_memberships_select on public.sync_proof_memberships
  for select to authenticated using (user_id = auth.uid());

drop policy if exists sync_proof_products_select on public.sync_proof_products;
create policy sync_proof_products_select on public.sync_proof_products
  for select to authenticated using (public.sync_proof_is_member(business_id));

drop policy if exists sync_proof_operations_select on public.sync_proof_operations;
create policy sync_proof_operations_select on public.sync_proof_operations
  for select to authenticated using (public.sync_proof_is_member(business_id));

drop policy if exists sync_proof_events_select on public.sync_proof_events;
create policy sync_proof_events_select on public.sync_proof_events
  for select to authenticated using (public.sync_proof_is_member(business_id));

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'sync_proof_events'
  ) then
    alter publication supabase_realtime add table public.sync_proof_events;
  end if;
end
$$;
