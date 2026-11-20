begin;

create table if not exists public.tp_live_sales (
  account_id uuid not null references auth.users(id) on delete cascade,
  voucher_id text not null check (voucher_id ~ '^[a-f0-9]{32}$'),
  revision bigint not null check (revision > 0),
  payload jsonb not null check (
    jsonb_typeof(payload) = 'object'
    and coalesce(payload->>'status', '') in ('draft', 'posted', 'void', 'removed')
    and octet_length(payload::text) <= 524288
  ),
  updated_at timestamptz not null default now(),
  primary key (account_id, voucher_id)
);

alter table public.tp_live_sales enable row level security;
revoke all on public.tp_live_sales from anon, authenticated;
grant select on public.tp_live_sales to authenticated;
drop policy if exists tp_live_sales_read_own on public.tp_live_sales;
create policy tp_live_sales_read_own on public.tp_live_sales
  for select to authenticated using (account_id = (select auth.uid()));
create index if not exists tp_live_sales_account_updated
  on public.tp_live_sales (account_id, updated_at desc);

create or replace function public.tp_publish_live_sale(
  p_account uuid, p_voucher text, p_revision bigint, p_payload jsonb
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null or auth.uid() is distinct from p_account then
    raise exception 'Account mismatch' using errcode = '42501';
  end if;
  insert into public.tp_live_sales as existing
    (account_id, voucher_id, revision, payload)
  values (p_account, p_voucher, p_revision, p_payload)
  on conflict (account_id, voucher_id) do update
    set revision = excluded.revision,
        payload = excluded.payload,
        updated_at = now()
    where existing.revision < excluded.revision;
end;
$$;

revoke all on function public.tp_publish_live_sale(uuid, text, bigint, jsonb)
  from public, anon;
grant execute on function public.tp_publish_live_sale(uuid, text, bigint, jsonb)
  to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'tp_live_sales'
  ) then
    alter publication supabase_realtime add table public.tp_live_sales;
  end if;
end;
$$;

commit;
