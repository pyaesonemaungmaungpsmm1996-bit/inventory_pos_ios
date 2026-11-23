begin;
insert into auth.users(id) values ('01300000-0000-4000-8000-000000000001');
set local role authenticated;
select set_config('request.jwt.claim.sub','01300000-0000-4000-8000-000000000001',true);

do $$
declare
  setup jsonb := public.tp_stock_sync_create_shop('Dashboard fixture','MMK','PZD','Pazundaung');
  shop uuid := (setup->>'shop_id')::uuid;
  branch uuid := (setup->>'branch_id')::uuid;
  windows uuid := gen_random_uuid();
  phone uuid := gen_random_uuid();
  secret text := repeat('f',64);
  product uuid;
  cash uuid;
  old_credit uuid := gen_random_uuid();
  live_sale uuid := gen_random_uuid();
  today date := (now() at time zone 'Asia/Yangon')::date;
  result jsonb;
  ledger jsonb;
begin
  perform public.tp_stock_sync_enroll(shop,branch,windows,'Windows',secret);
  perform public.tp_stock_sync_enroll(shop,branch,phone,'iPhone',secret);
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',windows));
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',phone));
  perform public.tp_stock_sync_import_opening(shop,windows,secret,jsonb_build_object(
    'branch_code','PZD','currency','MMK',
    'products','[{"code":"DE0001","name":"Laptop","price":150,"quantity":4,"serial_tracking":false}]'::jsonb,
    'accounts','[{"name":"Cash","kind":"cash","balance":500}]'::jsonb,
    'history',jsonb_build_array(
      jsonb_build_object('kind','sale','number','INV-000001','invoice_date',today,'status','posted','total',100,'paid',100,'due',0),
      jsonb_build_object('kind','expense','number','EXP-000001','invoice_date',today,'status','posted','total',7,'paid',7,'due',0),
      jsonb_build_object('kind','purchase','number','PUR-000001','invoice_date',today-90,'status','posted',
        'counterparty','Supplier fixture','total',150,'paid',50,'due',100)
    )
  ));
  result := public.tp_stock_sync_branch_view(shop,windows,secret,now()-interval '1 day',now()+interval '1 day');
  product := (result#>>'{stock,0,id}')::uuid;
  cash := (result#>>'{accounts,0,id}')::uuid;
  perform public.tp_stock_sync_post(shop,windows,secret,old_credit,jsonb_build_object(
    'kind','sale','occurred_at',now()-interval '90 days','counterparty','Customer fixture',
    'lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',1,'unit_minor',150))));
  perform public.tp_stock_sync_post(shop,phone,secret,live_sale,jsonb_build_object(
    'kind','sale','occurred_at',today::timestamp at time zone 'Asia/Yangon',
    'lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',1,'unit_minor',150)),
    'payments',jsonb_build_array(jsonb_build_object('account_id',cash,'amount_minor',150))));
  perform public.tp_stock_sync_post(shop,phone,secret,gen_random_uuid(),jsonb_build_object(
    'kind','expense','amount_minor',20,'payments',jsonb_build_array(jsonb_build_object('account_id',cash,'amount_minor',20))));
  perform public.tp_stock_sync_return_sale(shop,windows,secret,gen_random_uuid(),live_sale,product,1,array[]::text[],cash,150);
  perform public.tp_stock_sync_settle_voucher(shop,phone,secret,gen_random_uuid(),old_credit,cash,40);
  result := public.tp_stock_sync_dashboard(shop,windows,secret,today);
  if result is distinct from public.tp_stock_sync_dashboard(shop,phone,secret,today)
    or result->>'sales_today' is distinct from '100'
    or result->>'sales_month' is distinct from '100'
    or result->>'expenses_today' is distinct from '27'
    or result->>'balance' is distinct from '520' then
    raise exception 'Dashboard totals differ after sale, expense, refund or settlement';
  end if;
  ledger := public.tp_stock_sync_open_balances(shop,windows,secret,'sale');
  if ledger#>>'{0,due}' is distinct from '110' then raise exception 'Older credit missing'; end if;
  ledger := public.tp_stock_sync_open_balances(shop,phone,secret,'purchase');
  if ledger#>>'{0,due}' is distinct from '100' or ledger#>>'{0,archived}' is distinct from 'true' then
    raise exception 'Older imported supplier balance missing';
  end if;
end
$$;
set constraints all immediate;
rollback;
select 'Shared dashboard checks passed' as result;
