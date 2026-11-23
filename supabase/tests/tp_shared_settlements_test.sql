begin;
insert into auth.users(id) values ('09900000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','09900000-0000-4000-8000-000000000001',true);

do $$
declare
  setup jsonb := public.tp_stock_sync_create_shop('Payment fixture','MMK','PZD','Pazundaung');
  shop uuid := (setup->>'shop_id')::uuid;
  branch uuid := (setup->>'branch_id')::uuid;
  desktop uuid := gen_random_uuid();
  phone uuid := gen_random_uuid();
  secret text := repeat('c',64);
  item uuid;
  till uuid;
  purchase uuid := gen_random_uuid();
  sale uuid := gen_random_uuid();
  payment uuid := gen_random_uuid();
  result jsonb;
begin
  perform public.tp_stock_sync_enroll(shop,branch,desktop,'Windows',secret);
  perform public.tp_stock_sync_enroll(shop,branch,phone,'Phone',secret);
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',desktop));
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',phone));
  item := public.tp_stock_sync_admin(shop,gen_random_uuid(),'{"action":"product","code":"QA","name":"Test","sale_price_minor":150}');
  till := public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','account','branch_id',branch,'kind','cash','name','Cash'));
  perform public.tp_stock_sync_post(shop,desktop,secret,purchase,jsonb_build_object(
    'kind','purchase','counterparty','Supplier fixture',
    'lines',jsonb_build_array(jsonb_build_object('product_id',item,'quantity',2,'unit_minor',100))));
  begin
    perform public.tp_stock_sync_settle_voucher(shop,desktop,secret,gen_random_uuid(),purchase,till,1);
    raise exception 'Insufficient balance accepted' using errcode = 'XX000';
  exception when check_violation then null;
  end;
  perform public.tp_stock_sync_post(shop,phone,secret,sale,jsonb_build_object(
    'kind','sale','counterparty','Customer fixture',
    'lines',jsonb_build_array(jsonb_build_object('product_id',item,'quantity',1,'unit_minor',150))));
  perform public.tp_stock_sync_settle_voucher(shop,phone,secret,payment,sale,till,100);
  perform public.tp_stock_sync_settle_voucher(shop,phone,secret,payment,sale,till,100);
  perform public.tp_stock_sync_settle_voucher(shop,desktop,secret,gen_random_uuid(),purchase,till,60);
  begin
    perform public.tp_stock_sync_settle_voucher(shop,desktop,secret,gen_random_uuid(),sale,till,51);
    raise exception 'Overpayment accepted' using errcode = 'XX000';
  exception when raise_exception then null;
  end;

  result := public.tp_stock_sync_branch_view(shop,desktop,secret,now()-interval '1 minute',now()+interval '1 minute');
  if result is distinct from public.tp_stock_sync_branch_view(shop,phone,secret,now()-interval '1 minute',now()+interval '1 minute')
    or result#>>'{stock,0,on_hand}' is distinct from '1'
    or result#>>'{accounts,0,balance}' is distinct from '40'
    or not exists (select 1 from jsonb_array_elements(result->'vouchers') v
      where v->>'id'=sale::text and v->>'paid'='100' and v->>'due'='50')
    or not exists (select 1 from jsonb_array_elements(result->'vouchers') v
      where v->>'id'=purchase::text and v->>'paid'='60' and v->>'due'='140') then
    raise exception 'Shared settlement totals are inconsistent';
  end if;
end
$$;
set constraints all immediate;
rollback;
select 'Shared settlement checks passed' as result;
