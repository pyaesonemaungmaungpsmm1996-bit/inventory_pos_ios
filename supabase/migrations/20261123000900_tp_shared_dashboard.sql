begin;

create function public.tp_stock_sync_dashboard(
  shop uuid, device uuid, secret text, day date
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices;
  today_start timestamptz;
  tomorrow_start timestamptz;
  month_start timestamptz;
  next_month_start timestamptz;
  history jsonb;
  live_totals record;
  archived_totals record;
  refund_totals record;
  total_balance numeric;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop,device,secret);
  if day is null then raise exception 'Report date is required'; end if;
  today_start := day::timestamp at time zone 'Asia/Yangon';
  tomorrow_start := (day+1)::timestamp at time zone 'Asia/Yangon';
  month_start := date_trunc('month',day::timestamp) at time zone 'Asia/Yangon';
  next_month_start := (date_trunc('month',day::timestamp)+interval '1 month') at time zone 'Asia/Yangon';
  select coalesce(sum(a.balance_minor),0) into total_balance
    from tp_inventory_sync.accounts a where a.shop_id = shop and a.branch_id = machine.branch_id;
  select i.history into history from tp_inventory_sync.opening_imports i
    where i.shop_id = shop and i.branch_id = machine.branch_id;
  select
    coalesce(sum(total_minor) filter (where kind='sale' and occurred_at >= today_start and occurred_at < tomorrow_start),0) sales_today,
    coalesce(sum(total_minor) filter (where kind='sale'),0) sales_month,
    coalesce(sum(total_minor) filter (where kind='expense' and occurred_at >= today_start and occurred_at < tomorrow_start),0) expenses_today,
    coalesce(sum(total_minor) filter (where kind='expense'),0) expenses_month
  into live_totals
  from tp_inventory_sync.events e
  where e.shop_id = shop and e.branch_id = machine.branch_id
    and occurred_at >= month_start and occurred_at < next_month_start
    and not exists(select 1 from tp_inventory_sync.voucher_voids v
      where v.shop_id = shop and v.voucher_id = e.id);
  select
    coalesce(sum(v.total) filter (where v.kind = 'sale' and v.invoice_date = day),0) sales_today,
    coalesce(sum(v.total) filter (where v.kind = 'sale'),0) sales_month,
    coalesce(sum(v.total) filter (where v.kind = 'expense' and v.invoice_date = day),0) expenses_today,
    coalesce(sum(v.total) filter (where v.kind = 'expense'),0) expenses_month
  into archived_totals
  from jsonb_to_recordset(coalesce(history,'[]'::jsonb))
    v(kind text, status text, invoice_date date, total bigint)
  where v.kind in ('sale','expense') and v.status='posted'
    and v.invoice_date >= date_trunc('month',day::timestamp)::date
    and v.invoice_date < (date_trunc('month',day::timestamp)+interval '1 month')::date;
  select
    coalesce(sum(r.amount) filter (where r.created_at >= today_start and r.created_at < tomorrow_start),0) refunds_today,
    coalesce(sum(r.amount),0) refunds_month
  into refund_totals
  from tp_inventory_sync.sale_refunds r
  join tp_inventory_sync.events e on e.shop_id = r.shop_id and e.id = r.sale_id
  where r.shop_id = shop and e.branch_id = machine.branch_id
    and r.created_at >= month_start and r.created_at < next_month_start;
  return jsonb_build_object(
    'balance',total_balance,
    'sales_today',live_totals.sales_today+archived_totals.sales_today-refund_totals.refunds_today,
    'sales_month',live_totals.sales_month+archived_totals.sales_month-refund_totals.refunds_month,
    'expenses_today',live_totals.expenses_today+archived_totals.expenses_today,
    'expenses_month',live_totals.expenses_month+archived_totals.expenses_month
  );
end
$$;
revoke all on function public.tp_stock_sync_dashboard(uuid,uuid,text,date)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_dashboard(uuid,uuid,text,date) to authenticated;

create function public.tp_stock_sync_open_balances(
  shop uuid, device uuid, secret text, voucher_kind text
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare machine tp_inventory_sync.devices;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop,device,secret);
  if voucher_kind is null or voucher_kind not in ('sale','purchase') then
    raise exception 'Invalid voucher kind';
  end if;
  return coalesce((
    select jsonb_agg(voucher order by voucher->>'occurred_at',voucher->>'id')
    from (
      select jsonb_build_object(
        'id',e.id,'kind',e.kind,'occurred_at',e.occurred_at,
        'counterparty',e.payload->>'counterparty',
        'total',e.total_minor,'paid',e.paid_minor+paid.amount,
        'due',e.total_minor-e.paid_minor-paid.amount
      ) as voucher
      from tp_inventory_sync.events e
      cross join lateral (
        select coalesce(sum(s.amount),0) as amount
        from tp_inventory_sync.settlements s where s.shop_id = shop and s.voucher_id = e.id
      ) paid
      where e.shop_id = shop and e.branch_id = machine.branch_id and e.kind = voucher_kind
        and e.total_minor > e.paid_minor+paid.amount
        and not exists (select 1 from tp_inventory_sync.voucher_voids v
          where v.shop_id = shop and v.voucher_id = e.id)
      union all
      select entry.value || jsonb_build_object('archived',true,'occurred_at',entry.value->>'invoice_date')
      from tp_inventory_sync.opening_imports i
      cross join lateral jsonb_array_elements(i.history) entry
      where i.shop_id = shop and i.branch_id = machine.branch_id
        and entry.value->>'kind' = voucher_kind and entry.value->>'status' = 'posted'
        and (entry.value->>'due')::bigint > 0
    ) entries
  ),'[]'::jsonb);
end
$$;
revoke all on function public.tp_stock_sync_open_balances(uuid,uuid,text,text)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_open_balances(uuid,uuid,text,text)
  to authenticated;

commit;
