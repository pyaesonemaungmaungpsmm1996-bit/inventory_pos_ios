begin;
insert into auth.users(id) values ('08800000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','08800000-0000-4000-8000-000000000001',true);

do $$
declare
  setup jsonb := public.tp_stock_sync_create_shop('Import fixture','MMK','PZD','Pazundaung');
  shop uuid := (setup->>'shop_id')::uuid;
  branch uuid := (setup->>'branch_id')::uuid;
  desktop uuid := gen_random_uuid();
  phone uuid := gen_random_uuid();
  secret text := repeat('b',64);
  document jsonb := jsonb_build_object(
    'branch_code','PZD','currency','MMK',
    'products','[{"code":"DE0001","name":"Laptop","price":150,"quantity":2,"serial_tracking":true,"serials":["S1","S2"]}]'::jsonb,
    'accounts','[{"name":"Cash","kind":"cash","balance":500}]'::jsonb,
    'history',jsonb_build_array(jsonb_build_object('kind','purchase','number','PUR-000002',
      'invoice_date',(now() at time zone 'Asia/Yangon')::date,'status','posted','total',300,'paid',300,'due',0,
      'lines','[{"item_code":"DE0001","item_name":"Laptop","qty":2,"unit_price":150,"amount":300}]'::jsonb))
  );
  result jsonb;
  product uuid;
  cash uuid;
  start_time timestamptz := now() - interval '1 day';
  end_time timestamptz := now() + interval '1 day';
begin
  perform public.tp_stock_sync_enroll(shop,branch,desktop,'Windows',secret);
  perform public.tp_stock_sync_enroll(shop,branch,phone,'Phone',secret);
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',desktop));
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',phone));
  begin
    perform public.tp_stock_sync_import_opening(shop,desktop,secret,jsonb_set(document,'{history,0,paid}','999'));
    raise exception 'Invalid import accepted' using errcode = 'XX000';
  exception when raise_exception then null;
  end;
  if not public.tp_stock_sync_import_opening(shop,desktop,secret,document) then raise exception 'Initial import failed'; end if;
  if public.tp_stock_sync_import_opening(shop,desktop,secret,document) then raise exception 'Repeat import posted again'; end if;

  result := public.tp_stock_sync_branch_view(shop,phone,secret,start_time,end_time);
  product := (result#>>'{stock,0,id}')::uuid;
  cash := (result#>>'{accounts,0,id}')::uuid;
  if result#>>'{stock,0,on_hand}' is distinct from '2'
    or result#>>'{accounts,0,balance}' is distinct from '500'
    or result#>>'{vouchers,0,number}' is distinct from 'PUR-000002'
    or result#>>'{vouchers,0,lines,0,item_code}' is distinct from 'DE0001'
    or public.tp_stock_sync_branch_serials(shop,phone,secret)->product::text is distinct from '["S1","S2"]'::jsonb then
    raise exception 'Imported serials, balances or archived history differ from source';
  end if;
  perform public.tp_stock_sync_post(shop,phone,secret,gen_random_uuid(),
    jsonb_build_object('kind','sale','lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',1,'unit_minor',150,'serials','["S1"]'::jsonb)),
      'payments',jsonb_build_array(jsonb_build_object('account_id',cash,'amount_minor',150))));
  result := public.tp_stock_sync_branch_view(shop,desktop,secret,start_time,end_time);
  if result#>>'{stock,0,on_hand}' is distinct from '1'
    or result#>>'{accounts,0,balance}' is distinct from '650'
    or result#>>'{vouchers,0,lines,0,serials,0}' is distinct from 'S1'
    or jsonb_array_length(result->'vouchers') <> 2 then
    raise exception 'Post-import sale was not reflected on Windows';
  end if;
end
$$;
set constraints all immediate;
rollback;
select 'Opening import checks passed' as result;
