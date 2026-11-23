begin;
insert into auth.users(id) values ('01100000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','01100000-0000-4000-8000-000000000001',true);

do $$
declare
  setup jsonb := public.tp_stock_sync_create_shop('Void fixture','MMK','PZD','Pazundaung');
  shop uuid := (setup->>'shop_id')::uuid;
  branch uuid := (setup->>'branch_id')::uuid;
  desktop uuid := gen_random_uuid();
  phone uuid := gen_random_uuid();
  secret text := repeat('d',64);
  item uuid;
  till uuid;
  purchase uuid := gen_random_uuid();
  sale uuid := gen_random_uuid();
  reversal uuid := gen_random_uuid();
  result jsonb;
begin
  perform public.tp_stock_sync_enroll(shop,branch,desktop,'Windows',secret);
  perform public.tp_stock_sync_enroll(shop,branch,phone,'Phone',secret);
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',desktop));
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',phone));
  item := public.tp_stock_sync_admin(shop,gen_random_uuid(),'{"action":"product","code":"QA","name":"Laptop","sale_price_minor":150}');
  perform public.tp_stock_sync_enable_serial(shop,item);
  till := public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','account','branch_id',branch,'kind','cash','name','Cash'));
  perform public.tp_stock_sync_post(shop,desktop,secret,gen_random_uuid(),jsonb_build_object(
    'kind','deposit','amount_minor',500,'target_account',till));
  perform public.tp_stock_sync_post(shop,desktop,secret,purchase,jsonb_build_object(
    'kind','purchase','lines',jsonb_build_array(jsonb_build_object('product_id',item,'quantity',2,'unit_minor',100,'serials','["S1","S2"]'::jsonb)),
    'payments',jsonb_build_array(jsonb_build_object('account_id',till,'amount_minor',200))));
  perform public.tp_stock_sync_post(shop,phone,secret,sale,jsonb_build_object(
    'kind','sale','lines',jsonb_build_array(jsonb_build_object('product_id',item,'quantity',1,'unit_minor',150,'serials','["S1"]'::jsonb)),
    'payments',jsonb_build_array(jsonb_build_object('account_id',till,'amount_minor',150))));
  begin
    perform public.tp_stock_sync_void_voucher(shop,desktop,secret,gen_random_uuid(),purchase,'Stock already sold');
    raise exception 'Purchase with sold serial was voided' using errcode = 'XX000';
  exception when raise_exception then null;
  end;
  perform public.tp_stock_sync_void_voucher(shop,desktop,secret,reversal,sale,'Wrong voucher');
  perform public.tp_stock_sync_void_voucher(shop,desktop,secret,reversal,sale,'Wrong voucher');
  begin
    perform public.tp_stock_sync_void_voucher(shop,phone,secret,gen_random_uuid(),sale,'Another void');
    raise exception 'A second device voided the same voucher' using errcode = 'XX000';
  exception when raise_exception then null;
  end;
  result := public.tp_stock_sync_branch_view(shop,phone,secret,now()-interval '1 minute',now()+interval '1 minute');
  if result#>>'{stock,0,on_hand}' is distinct from '2'
    or result#>>'{accounts,0,balance}' is distinct from '300'
    or public.tp_stock_sync_branch_serials(shop,phone,secret)->item::text is distinct from '["S1","S2"]'::jsonb then
    raise exception 'Sale void did not restore stock and reverse money exactly once';
  end if;
  perform public.tp_stock_sync_void_voucher(shop,phone,secret,gen_random_uuid(),purchase,'Return unsold delivery');
  result := public.tp_stock_sync_branch_view(shop,desktop,secret,now()-interval '1 minute',now()+interval '1 minute');
  if result#>>'{stock,0,on_hand}' is distinct from '0'
    or result#>>'{accounts,0,balance}' is distinct from '500'
    or (select count(*) from jsonb_array_elements(result->'vouchers') v
      where v->>'status' = 'void' and v->>'can_void' = 'false') <> 2 then
    raise exception 'Voided vouchers or balances are inconsistent';
  end if;
end
$$;
set constraints all immediate;
rollback;
select 'Shared void checks passed' as result;
