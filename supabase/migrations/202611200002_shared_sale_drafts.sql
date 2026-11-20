-- Branch-scoped shared draft storage. Install after the account-management schema.
-- This migration only creates draft endpoints. Posting and historical import
-- require the shared inventory and payments transaction before rollout.
begin;

create table tp_private.shared_sale_drafts (
  business_id uuid not null,
  branch_id uuid not null,
  id uuid not null,
  revision bigint not null default 1 check (revision > 0),
  document jsonb not null check (
    jsonb_typeof(document) = 'object'
    and octet_length(document::text) <= 524288
  ),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default clock_timestamp(),
  last_request uuid not null,
  primary key (business_id, branch_id, id),
  foreign key (business_id, branch_id)
    references tp_private.branches(business_id,id)
);

create index shared_sale_drafts_branch_updated
  on tp_private.shared_sale_drafts(business_id, branch_id, updated_at desc, id);
alter table tp_private.shared_sale_drafts enable row level security;
revoke all on tp_private.shared_sale_drafts from public, anon, authenticated;

create function tp_private.require_sale_branch(
  p_business uuid, p_branch uuid, p_installation uuid
) returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_role text;
begin
  if auth.uid() is null then
    raise exception 'Sign in first' using errcode = '42501';
  end if;

  select m.role into v_role
  from tp_private.members m
  join tp_private.devices d
    on (d.business_id, d.user_id) = (m.business_id, m.user_id)
  where m.business_id = p_business
    and m.user_id = auth.uid()
    and m.active
    and (m.role = 'owner' or m.branch_id = p_branch)
    and d.branch_id = p_branch
    and d.installation_id = p_installation
    and d.status = 'approved'
  for share of m, d;

  if v_role is null then
    raise exception 'An approved device for this branch is required'
      using errcode = '42501';
  end if;
  return v_role;
end;
$$;

create function public.tp_list_shared_sale_drafts(
  p_business uuid, p_branch uuid, p_installation uuid,
  p_before timestamptz default null, p_before_id uuid default null
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform tp_private.require_sale_branch(p_business, p_branch, p_installation);

  if (p_before is null) <> (p_before_id is null) then
    raise exception 'Both cursor fields are required' using errcode = '22023';
  end if;
  select coalesce(jsonb_agg(to_jsonb(result) order by updated_at desc, id desc), '[]'::jsonb)
    into v_result
  from (
    select id, revision, updated_at,
           document->>'invoice_date' as invoice_date,
           document->>'customer_name' as customer_name
    from tp_private.shared_sale_drafts
    where business_id = p_business and branch_id = p_branch
      and (p_before is null or (updated_at,id) < (p_before,p_before_id))
    order by updated_at desc, id desc
    limit 100
  ) as result;

  return v_result;
end;
$$;

create function public.tp_get_shared_sale_draft(
  p_business uuid, p_branch uuid, p_installation uuid, p_voucher uuid
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_result jsonb;
begin
  perform tp_private.require_sale_branch(p_business, p_branch, p_installation);
  select jsonb_build_object('id', id, 'revision', revision,
      'updated_at', updated_at, 'document', document)
    into v_result
  from tp_private.shared_sale_drafts
  where business_id = p_business and branch_id = p_branch and id = p_voucher;

  if not found then
    raise exception 'Draft not found in this branch' using errcode = 'P0002';
  end if;
  return v_result;
end;
$$;

create function public.tp_save_shared_sale_draft(
  p_business uuid, p_branch uuid, p_installation uuid,
  p_voucher uuid, p_expected_revision bigint, p_request uuid, p_document jsonb
) returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  v_role text;
  v_draft tp_private.shared_sale_drafts;
  v_items jsonb;
begin
  v_role := tp_private.require_sale_branch(p_business, p_branch, p_installation);
  if v_role not in ('owner', 'manager', 'cashier') then
    raise exception 'This account cannot edit sales' using errcode = '42501';
  end if;

  if p_voucher is null or p_request is null or p_expected_revision is null
      or p_expected_revision < 0 or p_document is null
      or jsonb_typeof(p_document) <> 'object'
      or octet_length(p_document::text) > 524288 then
    raise exception 'Invalid draft' using errcode = '22023';
  end if;

  v_items := p_document->'items';
  if jsonb_typeof(v_items) is distinct from 'array' then
    raise exception 'Draft items must be an array' using errcode = '22023';
  end if;
  if jsonb_array_length(v_items) > 300
      or coalesce(p_document->>'invoice_date', '') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'Invalid draft date or item count' using errcode = '22023';
  end if;
  perform (p_document->>'invoice_date')::date;

  if p_expected_revision = 0 then
    insert into tp_private.shared_sale_drafts
      (business_id, branch_id, id, document, created_by, updated_by, last_request)
    values (p_business, p_branch, p_voucher, p_document, auth.uid(), auth.uid(), p_request)
    on conflict (business_id, branch_id, id) do nothing
    returning * into v_draft;
    if found then
      return jsonb_build_object('id', v_draft.id, 'revision', v_draft.revision);
    end if;
  end if;

  select * into v_draft
  from tp_private.shared_sale_drafts
  where business_id = p_business and branch_id = p_branch and id = p_voucher
  for update;

  if not found then
    raise exception 'Draft not found in this branch' using errcode = 'P0002';
  end if;

  -- A timed-out request can be repeated without advancing the revision twice.
  if v_draft.last_request = p_request then
    if v_draft.updated_by = auth.uid() and v_draft.document = p_document
        and v_draft.revision = p_expected_revision + 1 then
      return jsonb_build_object('id', v_draft.id, 'revision', v_draft.revision);
    end if;
    raise exception 'Request ID was already used' using errcode = '22023';
  end if;

  if v_draft.revision <> p_expected_revision then
    raise exception 'Draft changed. Reload before saving.' using errcode = '40001';
  end if;

  update tp_private.shared_sale_drafts
  set document = p_document, revision = revision + 1,
      updated_by = auth.uid(), updated_at = clock_timestamp(), last_request = p_request
  where business_id = p_business and branch_id = p_branch and id = p_voucher
  returning * into v_draft;

  return jsonb_build_object('id', v_draft.id, 'revision', v_draft.revision);
end;
$$;

revoke all on function tp_private.require_sale_branch(uuid,uuid,uuid)
  from public, anon, authenticated;

revoke all on function
  public.tp_list_shared_sale_drafts(uuid,uuid,uuid,timestamptz,uuid),
  public.tp_get_shared_sale_draft(uuid,uuid,uuid,uuid),
  public.tp_save_shared_sale_draft(uuid,uuid,uuid,uuid,bigint,uuid,jsonb)
  from public, anon, authenticated;

grant execute on function
  public.tp_list_shared_sale_drafts(uuid,uuid,uuid,timestamptz,uuid),
  public.tp_get_shared_sale_draft(uuid,uuid,uuid,uuid),
  public.tp_save_shared_sale_draft(uuid,uuid,uuid,uuid,bigint,uuid,jsonb)
  to authenticated;

commit;
