begin;

create table tp_private.branch_activity_reports (
  business_id uuid not null,
  branch_id uuid not null,
  installation_id uuid not null,
  reported_by uuid not null references auth.users(id),
  updated_at timestamptz not null default clock_timestamp(),
  report jsonb not null check (jsonb_typeof(report) = 'object' and octet_length(report::text) <= 524288),
  primary key (business_id, branch_id, installation_id),
  foreign key (business_id, branch_id) references tp_private.branches(business_id, id)
);
alter table tp_private.branch_activity_reports enable row level security;
revoke all on tp_private.branch_activity_reports from public, anon, authenticated;

create function public.tp_publish_branch_activity(
  p_business uuid, p_branch uuid, p_installation uuid, p_report jsonb
) returns void
language plpgsql security definer set search_path = ''
as $$
begin
  perform tp_private.require_sale_branch(p_business, p_branch, p_installation);
  insert into tp_private.branch_activity_reports as previous
    (business_id, branch_id, installation_id, reported_by, report)
  values (p_business, p_branch, p_installation, auth.uid(), p_report)
  on conflict (business_id, branch_id, installation_id) do update
    set reported_by = excluded.reported_by, report = excluded.report,
        updated_at = clock_timestamp()
    where (previous.reported_by, previous.report) is distinct from (excluded.reported_by, excluded.report);
end;
$$;

create function public.tp_owner_branch_activity(p_business uuid, p_branch uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
begin
  perform 1 from tp_private.members
  where business_id = p_business and user_id = auth.uid() and role = 'owner' and active
  for share;
  if not found then
    raise exception 'Active business owner required' using errcode = '42501';
  end if;

  return (
    select coalesce(jsonb_agg(jsonb_build_object(
      'installation_id', r.installation_id, 'updated_at', r.updated_at, 'report', r.report
    ) order by r.updated_at desc, r.installation_id), '[]'::jsonb)
    from tp_private.branch_activity_reports r
    where r.business_id = p_business and r.branch_id = p_branch
  );
end;
$$;

revoke all on function public.tp_publish_branch_activity(uuid, uuid, uuid, jsonb) from public, anon;
revoke all on function public.tp_owner_branch_activity(uuid, uuid) from public, anon;
grant execute on function public.tp_publish_branch_activity(uuid, uuid, uuid, jsonb) to authenticated;
grant execute on function public.tp_owner_branch_activity(uuid, uuid) to authenticated;

commit;
