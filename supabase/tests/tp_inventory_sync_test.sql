begin;

select set_config('tp.fixture_owner',gen_random_uuid()::text,true);
select set_config('tp.fixture_other',gen_random_uuid()::text,true);
insert into auth.users(id) values (current_setting('tp.fixture_owner')::uuid),(current_setting('tp.fixture_other')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('tp.fixture_owner'),true);

do $$
declare
  setup jsonb := public.tp_stock_sync_create_shop('Fixture shop','MMK','MAIN','Main');
  shop uuid := (setup->>'shop_id')::uuid;
  branch uuid := (setup->>'branch_id')::uuid;
  second_branch uuid;
  device_a uuid := gen_random_uuid();
  device_b uuid := gen_random_uuid();
  secret_a text := repeat('a',64);
  secret_b text := repeat('b',64);
  product uuid;
  cash uuid;
  account_two uuid;
  key uuid;
  command jsonb;
  report jsonb;
  inventory jsonb;
begin
  perform set_config('tp.fixture_shop',shop::text,true);
  second_branch := public.tp_stock_sync_admin(shop,gen_random_uuid(),'{"action":"branch","code":"B","name":"Second"}');
  product := public.tp_stock_sync_admin(shop,gen_random_uuid(),'{"action":"product","code":"TEA","name":"Tea","sale_price_minor":2500}');
  cash := public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','account','branch_id',branch,'kind','cash','name','Till'));
  account_two := public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','account','branch_id',second_branch,'kind','bank','name','Bank'));
  if public.tp_stock_sync_enroll(shop,branch,device_a,'Windows',secret_a) then raise exception 'Unexpected approval'; end if;
  perform public.tp_stock_sync_enroll(shop,branch,device_b,'Android',secret_b);
  begin
    perform public.tp_stock_sync_snapshot(shop,device_a,secret_a);
    raise exception 'Unapproved device read succeeded';
  exception when insufficient_privilege then null;
  end;
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',device_a));
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',device_b));
  begin
    perform public.tp_stock_sync_snapshot(shop,device_b,secret_a);
    raise exception 'Wrong device secret accepted';
  exception when insufficient_privilege then null;
  end;
  perform public.tp_stock_sync_post(shop,device_a,secret_a,gen_random_uuid(),jsonb_build_object(
    'kind','opening','lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',10,'unit_minor',0))));
  key := gen_random_uuid();
  command := jsonb_build_object('action','grant_stock','device_id',device_a,'product_id',product,'quantity',4);
  perform public.tp_stock_sync_admin(shop,key,command);
  perform public.tp_stock_sync_admin(shop,key,command);
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),
    jsonb_build_object('action','grant_stock','device_id',device_b,'product_id',product,'quantity',3));
  inventory := public.tp_stock_sync_snapshot(shop,device_a,secret_a)->'products'->0;
  if (inventory->>'device_granted')::int is distinct from 4 or (inventory->>'available_online')::int is distinct from 3
    then raise exception 'Allocation or idempotent allocation failed'; end if;

  command := jsonb_build_object('kind','sale','counterparty','Customer','lines',
    jsonb_build_array(jsonb_build_object('product_id',product,'quantity',4,'unit_minor',2500)));
  begin
    perform public.tp_stock_sync_post(shop,device_b,secret_b,gen_random_uuid(),command);
    raise exception 'Online sale consumed stock reserved for devices';
  exception when raise_exception then
    if sqlerrm <> 'Insufficient available stock' then raise; end if;
  end;
  begin
    perform public.tp_stock_sync_post(shop,device_b,secret_b,gen_random_uuid(),command || '{"offline":true}');
    raise exception 'Offline sale exceeded device allowance';
  exception when raise_exception then
    if sqlerrm <> 'Offline sale exceeds device allocation' then raise; end if;
  end;
  command := jsonb_build_object('kind','sale','offline',true,
    'lines',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',2,'unit_minor',2500)),
    'payments',jsonb_build_array(jsonb_build_object('account_id',cash,'amount_minor',5000)));
  key := gen_random_uuid();
  perform public.tp_stock_sync_post(shop,device_a,secret_a,key,command);
  perform public.tp_stock_sync_post(shop,device_a,secret_a,key,command);
  begin
    perform public.tp_stock_sync_post(shop,device_a,secret_a,key,command || '{"counterparty":"Different"}');
    raise exception 'ID reuse with a different payload accepted';
  exception when raise_exception then
    if sqlerrm <> 'Operation ID was used for different data' then raise; end if;
  end;
  inventory := public.tp_stock_sync_snapshot(shop,device_b,secret_b)->'products'->0;
  if (inventory->>'on_hand')::int is distinct from 8 or (inventory->>'available_online')::int is distinct from 3
    or (inventory->>'device_consumed')::int is distinct from 0 then raise exception 'Cross-device stock mismatch'; end if;
  perform public.tp_stock_sync_post(shop,device_a,secret_a,gen_random_uuid(),
    jsonb_build_object('kind','expense','amount_minor',1000,'note','Packaging',
      'payments',jsonb_build_array(jsonb_build_object('account_id',cash,'amount_minor',1000))));
  begin
    perform public.tp_stock_sync_post(shop,device_a,secret_a,gen_random_uuid(),
      jsonb_build_object('kind','transfer','amount_minor',1000,'source_account',cash,'target_account',account_two));
    raise exception 'Cross-branch money transfer accepted';
  exception when raise_exception then
    if sqlerrm <> 'Target account is outside this branch or missing' then raise; end if;
  end;
  begin
    perform public.tp_stock_sync_post(shop,device_a,secret_a,gen_random_uuid(),
      jsonb_build_object('kind','expense','amount_minor',5000,'note','Rejected',
        'payments',jsonb_build_array(jsonb_build_object('account_id',cash,'amount_minor',5000))));
    raise exception 'Negative account balance accepted';
  exception when check_violation then null;
  end;

  report := public.tp_stock_sync_owner_report(shop,now()-interval '1 day',now()+interval '1 day')->'branches'->1;
  if report->>'name' is distinct from 'Main'
    or (report->>'sale_minor')::int is distinct from 5000
    or (report->>'expense_minor')::int is distinct from 1000
    or (report#>>'{accounts,0,balance_minor}')::int is distinct from 4000
    or report#>>'{expenses,0,note}' is distinct from 'Packaging'
    or report#>>'{devices,0,last_sync_at}' is null then raise exception 'Owner rollup mismatch: %',report; end if;
  key := gen_random_uuid();
  command := jsonb_build_object('kind','sale','counterparty','Online Customer','lines',
    jsonb_build_array(jsonb_build_object('product_id',product,'quantity',1,'unit_minor',2500)));
  perform public.tp_stock_sync_cancel_sale(shop,device_a,secret_a,key);
  perform public.tp_stock_sync_cancel_sale(shop,device_a,secret_a,key);
  begin
    perform public.tp_stock_sync_post(shop,device_a,secret_a,key,command);
    raise exception 'A cancelled sale posted';
  exception when raise_exception then
    if sqlerrm <> 'This online request was cancelled.' then raise; end if;
  end;
  key := gen_random_uuid();
  perform public.tp_stock_sync_post(shop,device_a,secret_a,key,command);
  begin
    perform public.tp_stock_sync_cancel_sale(shop,device_a,secret_a,key);
    raise exception 'A posted sale was cancelled';
  exception when raise_exception then
    if sqlerrm <> 'This online sale is already posted. Retry the original checkout.' then raise; end if;
  end;
  inventory := public.tp_stock_sync_snapshot(shop,device_b,secret_b)->'products'->0;
  if (inventory->>'on_hand')::int is distinct from 7
    or (inventory->>'available_online')::int is distinct from 2 then
    raise exception 'Cancellation changed stock';
  end if;

end
$$;

select set_config('request.jwt.claim.sub',current_setting('tp.fixture_other'),true);
do $$
declare shop uuid := current_setting('tp.fixture_shop')::uuid;
begin
  if exists(select 1 from public.tp_stock_sync_changes where shop_id=shop) then
    raise exception 'Cross-shop change feed was visible';
  end if;
  begin
    perform public.tp_stock_sync_owner_report(shop,now()-interval '1 day',now());
    raise exception 'Cross-shop owner report was visible';
  exception when insufficient_privilege then null;
  end;
end
$$;
reset role;
rollback;
select 'Legacy stock sync SQL checks passed' as result;
