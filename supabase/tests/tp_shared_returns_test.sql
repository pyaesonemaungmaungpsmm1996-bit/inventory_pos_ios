begin;
insert into auth.users(id) values ('01200000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','01200000-0000-4000-8000-000000000001',true);

do $$
declare
  setup jsonb := public.tp_stock_sync_create_shop('Returns fixture','MMK','PZD','Pazundaung');
  shop uuid := (setup->>'shop_id')::uuid;
  branch uuid := (setup->>'branch_id')::uuid;
  desktop uuid := gen_random_uuid();
  phone uuid := gen_random_uuid();
  secret text := repeat('e',64);
  item uuid;
  till uuid;
  sale uuid := gen_random_uuid();
  operation uuid := gen_random_uuid();
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
    'kind','opening','lines',jsonb_build_array(jsonb_build_object('product_id',item,'quantity',2,'unit_minor',0,'serials','["S1","S2"]'::jsonb))));
  perform public.tp_stock_sync_post(shop,desktop,secret,sale,jsonb_build_object(
    'kind','sale','discount_minor',20,'lines',jsonb_build_array(jsonb_build_object('product_id',item,'quantity',2,'unit_minor',150,'serials','["S1","S2"]'::jsonb)),
    'payments',jsonb_build_array(jsonb_build_object('account_id',till,'amount_minor',280))));
  begin
    perform public.tp_stock_sync_return_sale(shop,phone,secret,gen_random_uuid(),sale,item,1,array['S1'],till,141);
    raise exception 'Over-refund was accepted' using errcode='XX000';
  exception when raise_exception then null;
  end;
  perform public.tp_stock_sync_return_sale(shop,phone,secret,operation,sale,item,1,array['s1'],till,140);
  perform public.tp_stock_sync_return_sale(shop,phone,secret,operation,sale,item,1,array['S1'],till,140);
  begin
    perform public.tp_stock_sync_return_sale(shop,desktop,secret,gen_random_uuid(),sale,item,1,array['S1'],till,140);
    raise exception 'An already returned serial was accepted again' using errcode='XX000';
  exception when raise_exception then null;
  end;
  begin
    perform public.tp_stock_sync_void_voucher(shop,desktop,secret,gen_random_uuid(),sale,'Void after return');
    raise exception 'Void accepted after return' using errcode='XX000';
  exception when raise_exception then null;
  end;
  result := public.tp_stock_sync_branch_view(shop,desktop,secret,now()-interval '1 minute',now()+interval '1 minute');
  if result is distinct from public.tp_stock_sync_branch_view(shop,phone,secret,now()-interval '1 minute',now()+interval '1 minute')
    or result#>>'{stock,0,on_hand}' is distinct from '1'
    or result#>>'{accounts,0,balance}' is distinct from '140'
    or result#>>'{vouchers,0,refunded}' is distinct from '140'
    or result#>>'{vouchers,0,returns,0,serials,0}' is distinct from 'S1'
    or result#>>'{vouchers,0,can_void}' is distinct from 'false' then
    raise exception 'Partial return was not atomic and visible on both devices';
  end if;
end
$$;
set constraints all immediate;
rollback;
select 'Shared return checks passed' as result;
