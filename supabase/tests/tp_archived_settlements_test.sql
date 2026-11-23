begin;
insert into auth.users(id) values ('01400000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','01400000-0000-4000-8000-000000000001',true);

do $$
declare
  setup jsonb := public.tp_stock_sync_create_shop('Archived debt fixture','MMK','PZD','Pazundaung');
  shop uuid := (setup->>'shop_id')::uuid;
  branch uuid := (setup->>'branch_id')::uuid;
  windows uuid := gen_random_uuid();
  phone uuid := gen_random_uuid();
  secret text := repeat('a',64);
  cash uuid;
  wire uuid;
  transfer uuid := gen_random_uuid();
  transfer_data jsonb;
  operation uuid := gen_random_uuid();
  day date := (now() at time zone 'Asia/Yangon')::date;
  result jsonb;
begin
  perform public.tp_stock_sync_enroll(shop,branch,windows,'Windows',secret);
  perform public.tp_stock_sync_enroll(shop,branch,phone,'Phone',secret);
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',windows));
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',phone));
  perform public.tp_stock_sync_import_opening(shop,windows,secret,jsonb_build_object(
    'branch_code','PZD','currency','MMK',
    'products','[{"code":"DE0001","name":"Laptop","price":150,"quantity":4,"serial_tracking":false}]'::jsonb,
    'accounts','[{"name":"Cash","kind":"cash","balance":500},{"name":"Wire","kind":"bank","balance":0}]'::jsonb,
    'history',jsonb_build_array(
      jsonb_build_object('kind','sale','number','INV-000001','invoice_date',day,'status','posted','total',100,'paid',30,'due',70),
      jsonb_build_object('kind','purchase','number','PUR-000001','invoice_date',day,'status','posted','total',150,'paid',50,'due',100)
    )
  ));
  result := public.tp_stock_sync_branch_view(shop,windows,secret,now()-interval '1 day',now()+interval '1 day');
  cash := (result#>>'{accounts,0,id}')::uuid;
  wire := (result#>>'{accounts,1,id}')::uuid;
  perform public.tp_stock_sync_settle_archived(shop,phone,secret,operation,'sale:INV-000001',cash,70);
  perform public.tp_stock_sync_settle_archived(shop,phone,secret,operation,'sale:INV-000001',cash,70);
  perform public.tp_stock_sync_settle_archived(shop,windows,secret,gen_random_uuid(),'purchase:PUR-000001',cash,60);
  begin
    perform public.tp_stock_sync_settle_archived(shop,phone,secret,gen_random_uuid(),'purchase:PUR-000001',cash,41);
    raise exception 'Overpayment accepted' using errcode='XX000';
  exception when raise_exception then null;
  end;
  transfer_data := jsonb_build_object('kind','transfer','amount_minor',50,
    'source_account',cash,'target_account',wire);
  perform public.tp_stock_sync_post(shop,windows,secret,transfer,transfer_data);
  perform public.tp_stock_sync_post(shop,windows,secret,transfer,transfer_data);
  result := public.tp_stock_sync_branch_view(shop,phone,secret,now()-interval '1 day',now()+interval '1 day');
  if result is distinct from public.tp_stock_sync_branch_view(shop,windows,secret,now()-interval '1 day',now()+interval '1 day')
    or result#>>'{stock,0,on_hand}' is distinct from '4'
    or result#>>'{accounts,0,balance}' is distinct from '460'
    or result#>>'{accounts,1,balance}' is distinct from '50'
    or public.tp_stock_sync_open_balances(shop,phone,secret,'sale') <> '[]'::jsonb
    or public.tp_stock_sync_open_balances(shop,windows,secret,'purchase')#>>'{0,due}' is distinct from '40' then
    raise exception 'Archived payments changed stock, double-counted, or varied by device';
  end if;
end
$$;
set constraints all immediate;
rollback;
select 'Archived settlement checks passed' as result;
