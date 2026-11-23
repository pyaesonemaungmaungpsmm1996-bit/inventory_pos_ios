begin;
insert into auth.users(id) values ('07700000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','07700000-0000-4000-8000-000000000001',true);

do $$
declare
  setup jsonb := public.tp_stock_sync_create_shop('Shared POS fixture','MMK','PZD','Pazundaung');
  shop uuid := (setup->>'shop_id')::uuid;
  branch uuid := (setup->>'branch_id')::uuid;
  windows_device uuid := gen_random_uuid();
  phone_device uuid := gen_random_uuid();
  secret text := repeat('a',64);
  product uuid;
  cash uuid;
  sale_id uuid := gen_random_uuid();
  command jsonb;
  desktop_view jsonb;
  phone_view jsonb;
  start_time timestamptz := now() - interval '1 minute';
  end_time timestamptz := now() + interval '1 minute';
  has_serials boolean := to_regprocedure('public.tp_stock_sync_enable_serial(uuid,uuid)') is not null;
begin
  perform public.tp_stock_sync_enroll(shop,branch,windows_device,'Windows',secret);
  perform public.tp_stock_sync_enroll(shop,branch,phone_device,'iPhone',secret);
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',windows_device));
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',phone_device));
  product := public.tp_stock_sync_admin(shop,gen_random_uuid(),'{"action":"product","code":"DE0001","name":"Laptop","sale_price_minor":150}');
  if has_serials then perform public.tp_stock_sync_enable_serial(shop,product); end if;
  cash := public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','account','branch_id',branch,'kind','cash','name','Cash'));
  perform public.tp_stock_sync_post(shop,windows_device,secret,gen_random_uuid(),
    jsonb_build_object('kind','deposit','amount_minor',1000,'target_account',cash));
  perform public.tp_stock_sync_post(shop,windows_device,secret,gen_random_uuid(),
    jsonb_build_object('kind','purchase','lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',3,'unit_minor',100)
      || case when has_serials then '{"serials":["SN1","SN2","SN3"]}'::jsonb else '{}'::jsonb end),
      'payments',jsonb_build_array(jsonb_build_object('account_id',cash,'amount_minor',300))));
  phone_view := public.tp_stock_sync_branch_view(shop,phone_device,secret,start_time,end_time);
  if phone_view#>>'{stock,0,available_online}' is distinct from '3'
    or phone_view#>>'{accounts,0,balance}' is distinct from '700'
    or phone_view#>>'{vouchers,0,kind}' is distinct from 'purchase' then
    raise exception 'Windows purchase was not visible on iPhone';
  end if;
  if has_serials and public.tp_stock_sync_branch_serials(shop,phone_device,secret)->product::text is distinct from '["SN1","SN2","SN3"]'::jsonb then
    raise exception 'The phone did not see the received serials';
  end if;
  command := jsonb_build_object('kind','sale','lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',1,'unit_minor',150)
    || case when has_serials then '{"serials":["sn1"]}'::jsonb else '{}'::jsonb end),
    'payments',jsonb_build_array(jsonb_build_object('account_id',cash,'amount_minor',150)));
  perform public.tp_stock_sync_post(shop,phone_device,secret,sale_id,command);
  perform public.tp_stock_sync_post(shop,phone_device,secret,sale_id,command);
  if has_serials then
    begin
      perform public.tp_stock_sync_post(shop,windows_device,secret,gen_random_uuid(),command);
      raise exception 'Duplicate serial sale unexpectedly posted' using errcode = 'XX000';
    exception when raise_exception then null;
    end;
    if public.tp_stock_sync_branch_serials(shop,windows_device,secret)->product::text is distinct from '["SN2","SN3"]'::jsonb then
      raise exception 'Sold serial still available';
    end if;
  end if;
  desktop_view := public.tp_stock_sync_branch_view(shop,windows_device,secret,start_time,end_time);
  phone_view := public.tp_stock_sync_branch_view(shop,phone_device,secret,start_time,end_time);
  if desktop_view is distinct from phone_view
    or desktop_view#>>'{stock,0,on_hand}' is distinct from '2'
    or desktop_view#>>'{accounts,0,balance}' is distinct from '850'
    or jsonb_array_length(desktop_view->'vouchers') <> 2 then
    raise exception 'iPhone sale did not produce a single shared result';
  end if;
end
$$;
rollback;
select 'Shared branch transaction checks passed' as result;
