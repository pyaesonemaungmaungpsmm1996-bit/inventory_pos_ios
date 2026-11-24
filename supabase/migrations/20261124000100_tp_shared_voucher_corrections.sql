begin;

create function public.tp_stock_sync_correct_voucher(
  shop uuid, device uuid, secret text, operation uuid, voucher uuid,
  replacement jsonb, reason text
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  machine tp_inventory_sync.devices;
  original tp_inventory_sync.events;
  command jsonb;
begin
  perform tp_inventory_sync.require_owner(shop);
  machine := tp_inventory_sync.checked_device(shop,device,secret);
  perform 1 from tp_inventory_sync.shops where id = shop for update;

  select e.* into original from tp_inventory_sync.events e
    where e.shop_id = shop and e.id = voucher
      and e.branch_id = machine.branch_id and e.kind in ('sale','purchase');
  if not found or jsonb_typeof(replacement) is distinct from 'object'
      or operation is null or operation = voucher then
    raise exception 'A posted voucher in this branch and a replacement are required';
  end if;

  command := jsonb_build_object(
    'kind', original.kind,
    'occurred_at', original.occurred_at,
    'lines', replacement->'lines',
    'payments', replacement->'payments',
    'discount_minor', coalesce(replacement->'discount_minor','0'::jsonb),
    'counterparty', replacement->>'counterparty',
    'corrects_voucher', voucher
  );
  -- The two calls share the shop lock and PostgreSQL transaction. The void and
  -- post functions each validate the operation ID on a retry.
  perform public.tp_stock_sync_void_voucher(shop,device,secret,operation,voucher,reason);
  return public.tp_stock_sync_post(shop,device,secret,operation,command);
end
$$;
revoke all on function public.tp_stock_sync_correct_voucher(uuid,uuid,text,uuid,uuid,jsonb,text)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_correct_voucher(uuid,uuid,text,uuid,uuid,jsonb,text)
  to authenticated;

alter function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  rename to tp_stock_sync_branch_view_before_corrections;
alter function public.tp_stock_sync_branch_view_before_corrections(uuid,uuid,text,timestamptz,timestamptz)
  set schema tp_inventory_sync;
revoke all on function tp_inventory_sync.tp_stock_sync_branch_view_before_corrections(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;

create function public.tp_stock_sync_branch_view(
  shop uuid, device uuid, secret text, from_time timestamptz, until_time timestamptz
) returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  result jsonb := tp_inventory_sync.tp_stock_sync_branch_view_before_corrections(shop,device,secret,from_time,until_time);
  owner_access boolean;
begin
  select exists (select 1 from tp_inventory_sync.members m
    where m.shop_id = shop and m.user_id = auth.uid() and m.role = 'owner') into owner_access;
  return jsonb_set(result,'{vouchers}',(
    select coalesce(jsonb_agg(entry.value || case when event.kind in ('sale','purchase') then
      jsonb_build_object(
        'number',coalesce(entry.value->>'number',
          case when event.kind='sale' then 'INV-' else 'PUR-' end || event.id::text),
        'counterparty',event.payload->>'counterparty',
        'can_void',owner_access and coalesce((entry.value->>'can_void')::boolean,false),
        'payments',event.payload->'payments',
        'discount',coalesce(event.payload->'discount_minor','0'::jsonb),
        'corrects_voucher',event.payload->>'corrects_voucher',
        'replacement_id',correction.id
      ) else '{}'::jsonb end order by entry.position),'[]'::jsonb)
    from jsonb_array_elements(result->'vouchers') with ordinality entry(value,position)
    left join tp_inventory_sync.events event
      on event.shop_id = shop and event.id = (entry.value->>'id')::uuid
    left join tp_inventory_sync.voucher_voids reversal
      on reversal.shop_id = shop and reversal.voucher_id = event.id
    left join tp_inventory_sync.events correction
      on correction.shop_id = shop and correction.id = reversal.operation_id
      and correction.payload->>'corrects_voucher' = event.id::text
  ));
end
$$;
revoke all on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  from public, anon, authenticated;
grant execute on function public.tp_stock_sync_branch_view(uuid,uuid,text,timestamptz,timestamptz)
  to authenticated;
commit;
