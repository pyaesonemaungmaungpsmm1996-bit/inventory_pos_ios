begin;
insert into auth.users(id) values ('06600000-0000-4000-8000-000000000001'),
  ('06600000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claim.sub','06600000-0000-4000-8000-000000000001',true);

do $$
declare
  setup jsonb := public.tp_stock_sync_create_shop('Records fixture','MMK','MAIN','Main');
  shop uuid := (setup->>'shop_id')::uuid;
  branch uuid := (setup->>'branch_id')::uuid;
  windows_device uuid := gen_random_uuid();
  phone_device uuid := gen_random_uuid();
  secret text := repeat('a',64);
  doc jsonb := '{"branch_code":"MAIN","stock":[{"item_code":"DE0001","stock":2}],"sales":[{"number":"MAIN-000001"}],"purchases":[{"number":"PUR-000001"}]}';
begin
  perform public.tp_stock_sync_enroll(shop,branch,windows_device,'Windows',secret);
  perform public.tp_stock_sync_enroll(shop,branch,phone_device,'iPhone',secret);
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',windows_device));
  perform public.tp_stock_sync_admin(shop,gen_random_uuid(),jsonb_build_object('action','approve_device','device_id',phone_device));
  if not public.tp_stock_sync_publish_records(shop,windows_device,secret,doc) then raise exception 'First publish failed'; end if;
  if public.tp_stock_sync_publish_records(shop,windows_device,secret,doc) then raise exception 'Duplicate changed revision'; end if;
  if public.tp_stock_sync_read_records(shop,phone_device,secret)->'stock' is distinct from doc->'stock' then raise exception 'iPhone did not read published stock'; end if;
  begin
    perform public.tp_stock_sync_publish_records(shop,phone_device,secret,doc);
    raise exception 'A second device overwrote the Windows source';
  exception when insufficient_privilege then null;
  end;
  doc := jsonb_set(doc,'{stock,0,stock}','1');
  perform public.tp_stock_sync_publish_records(shop,windows_device,secret,doc);
  if public.tp_stock_sync_read_records(shop,phone_device,secret)->'stock' is distinct from doc->'stock' then raise exception 'Updated stock did not appear'; end if;
  perform set_config('request.jwt.claim.sub','06600000-0000-4000-8000-000000000002',true);
  begin
    perform public.tp_stock_sync_read_records(shop,phone_device,secret);
    raise exception 'Unrelated account read records';
  exception when insufficient_privilege then null;
  end;
end
$$;
rollback;
select 'Branch records checks passed' as result;
