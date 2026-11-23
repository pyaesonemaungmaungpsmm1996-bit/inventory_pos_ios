begin;

-- Read stock, voucher totals and account balances from the same committed
-- cloud transactions. The Windows records viewer keeps its own endpoint.
create function public.tp_stock_sync_branch_view(
  shop uuid, device uuid, secret text, from_time timestamptz, until_time timestamptz
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop, device, secret);
  if from_time is null or until_time is null or from_time >= until_time then
    raise exception 'Invalid branch history period';
  end if;

  return (
    select jsonb_build_object(
      'branch_id', branch.id,
      'branch_code', branch.code,
      'currency', business.currency,
      'stock', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', p.id, 'code', p.code, 'name', p.name,
          'price', p.sale_price_minor, 'on_hand', coalesce(s.on_hand, 0),
          'available_online', coalesce(s.on_hand - s.reserved, 0)
        ) order by p.code)
        from tp_inventory_sync.products p
        left join tp_inventory_sync.stock s
          on s.shop_id = p.shop_id and s.product_id = p.id and s.branch_id = branch.id
        where p.shop_id = shop
      ), '[]'::jsonb),
      'accounts', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', a.id, 'name', a.name, 'kind', a.kind, 'balance', a.balance_minor
        ) order by a.name, a.id)
        from tp_inventory_sync.accounts a
        where a.shop_id = shop and a.branch_id = branch.id
      ), '[]'::jsonb),
      'vouchers', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', e.id, 'kind', e.kind, 'device_id', e.device_id,
          'occurred_at', e.occurred_at, 'total', e.total_minor,
          'paid', e.paid_minor, 'due', e.total_minor - e.paid_minor
        ) order by e.occurred_at desc, e.id)
        from tp_inventory_sync.events e
        where e.shop_id = shop and e.branch_id = branch.id
          and e.kind in ('purchase', 'sale', 'expense')
          and e.occurred_at >= from_time and e.occurred_at < until_time
      ), '[]'::jsonb)
    )
    from tp_inventory_sync.branches branch
    join tp_inventory_sync.shops business on business.id = branch.shop_id
    where branch.shop_id = shop and branch.id = machine.branch_id
  );
end
$$;

revoke all on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  to authenticated;

commit;
