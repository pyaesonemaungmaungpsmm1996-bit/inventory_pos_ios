begin;
insert into auth.users(id) values ('01100000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','01100000-0000-4000-8000-000000000001',true);

do $$
declare
  setup jsonb := public.tp_stock_sync_create_shop('Correction fixture','MMK','PZD','Pazundaung');
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
  replacement jsonb;
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
  replacement := jsonb_build_object(
    'lines',jsonb_build_array(jsonb_build_object('product_id',item,'quantity',1,'unit_minor',175,'serials','["S1"]'::jsonb)),
    'payments',jsonb_build_array(jsonb_build_object('account_id',till,'amount_minor',175)));
  begin
    perform public.tp_stock_sync_correct_voucher(shop,desktop,secret,gen_random_uuid(),sale,
      jsonb_set(replacement,'{lines,0,quantity}','0'), 'Invalid correction');
    raise exception 'Invalid replacement accepted' using errcode = 'XX000';
  exception when raise_exception then null;
  end;
  perform public.tp_stock_sync_correct_voucher(shop,desktop,secret,reversal,sale,replacement,'Correct price');
  perform public.tp_stock_sync_correct_voucher(shop,desktop,secret,reversal,sale,replacement,'Correct price');
  begin
    perform public.tp_stock_sync_correct_voucher(shop,phone,secret,gen_random_uuid(),sale,replacement,'Concurrent correction');
    raise exception 'A second correction succeeded' using errcode = 'XX000';
  exception when raise_exception then null;
  end;
  result := public.tp_stock_sync_branch_view(shop,phone,secret,now()-interval '1 minute',now()+interval '1 minute');
  if result#>>'{stock,0,on_hand}' is distinct from '1'
    or result#>>'{accounts,0,balance}' is distinct from '475'
    or not exists (select 1 from jsonb_array_elements(result->'vouchers') v
      where v->>'id' = sale::text and v->>'status' = 'void' and v->>'replacement_id' = reversal::text)
    or not exists (select 1 from jsonb_array_elements(result->'vouchers') v
      where v->>'id' = reversal::text and v->>'total' = '175' and v->>'corrects_voucher' = sale::text) then
    raise exception 'Correction or retry produced incorrect stock, balance or audit links';
  end if;
end
$$;
set constraints all immediate;
rollback;
select 'Cross-device correction, rollback and retry checks passed' as result;
