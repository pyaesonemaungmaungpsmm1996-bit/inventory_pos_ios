begin;

create table tp_private.shared_inventory (
  business_id uuid not null,
  branch_id uuid not null,
  product_id uuid not null,
  name text not null check (char_length(btrim(name)) between 1 and 250),
  price bigint not null check (price between 0 and 9000000000000),
  stock integer not null default 0 check (stock >= 0),
  revision bigint not null default 1 check (revision > 0),
  primary key (business_id, branch_id, product_id),
  foreign key (business_id, branch_id)
    references tp_private.branches(business_id, id)
);

alter table tp_private.shared_inventory enable row level security;
revoke all on tp_private.shared_inventory from public, anon, authenticated;

create function public.tp_list_shared_inventory(
  p_business uuid, p_branch uuid, p_installation uuid,
  p_after_product uuid default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  perform tp_private.require_sale_branch(p_business, p_branch, p_installation);
  return (
    select coalesce(jsonb_agg(to_jsonb(item) order by item.product_id), '[]'::jsonb)
    from (
      select product_id, name, price, stock, revision
      from tp_private.shared_inventory
      where business_id = p_business and branch_id = p_branch
        and (p_after_product is null or product_id > p_after_product)
      order by product_id
      limit 100
    ) as item
  );
end;
$$;

create function public.tp_save_shared_product(
  p_business uuid, p_branch uuid, p_installation uuid, p_product uuid,
  p_expected_revision bigint, p_name text, p_price bigint
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_product tp_private.shared_inventory%rowtype;
begin
  if tp_private.require_sale_branch(p_business, p_branch, p_installation)
      is distinct from 'owner' then
    raise exception 'Active business owner required' using errcode = '42501';
  end if;
  if p_expected_revision is null or p_expected_revision < 0 then
    raise exception 'Expected revision must be zero for a new product or positive for an edit'
      using errcode = '22023';
  end if;

  if p_expected_revision = 0 then
    insert into tp_private.shared_inventory (business_id, branch_id, product_id, name, price)
      values (p_business, p_branch, p_product, btrim(p_name), p_price)
      on conflict (business_id, branch_id, product_id) do nothing
      returning * into v_product;
  else
    update tp_private.shared_inventory
      set name = btrim(p_name), price = p_price, revision = revision + 1
      where business_id = p_business and branch_id = p_branch
        and product_id = p_product and revision = p_expected_revision
      returning * into v_product;
  end if;

  if not found then
    raise exception 'Product changed. Reload it before saving.' using errcode = '40001';
  end if;
  return jsonb_build_object(
    'product_id', v_product.product_id, 'name', v_product.name,
    'price', v_product.price, 'stock', v_product.stock, 'revision', v_product.revision
  );
end;
$$;

revoke all on function public.tp_list_shared_inventory(uuid, uuid, uuid, uuid)
  from public, anon;
revoke all on function public.tp_save_shared_product(uuid, uuid, uuid, uuid, bigint, text, bigint)
  from public, anon;
grant execute on function public.tp_list_shared_inventory(uuid, uuid, uuid, uuid)
  to authenticated;
grant execute on function public.tp_save_shared_product(uuid, uuid, uuid, uuid, bigint, text, bigint)
  to authenticated;

commit;
