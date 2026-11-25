# Toe Pwar POS — Sync Proof Milestone

This branch proves the smallest safe synchronization unit before the full POS is rebuilt. It is based on the supplied Flutter project, but the proof tables and RPCs are namespaced with `sync_proof_` and do not replace the existing POS schema.

## What this milestone proves

- Two authenticated Flutter clients can update the same product through a Supabase RPC.
- A retry with the same `operation_id` is idempotent and does not create a duplicate product event.
- A second client receives a Realtime signal and pulls the authoritative event by cursor.
- Offline local writes survive in a SQLite outbox and are retried later.
- An optimistic version mismatch is returned as an explicit conflict rather than silently overwriting data.
- RLS/membership checks are performed on the server, not only in the UI.

## What this milestone does not claim

This is not yet full POS synchronization. Sales, purchases, stock movements, transfers, money ledger, reports, backup/restore, voucher printing, and production roles remain outside this proof.

## Supabase setup

1. Run `supabase/migrations/0001_sync_proof_products.sql` in the target Supabase SQL Editor.
2. Sign in as two test users.
3. Choose one UUID as `business_id` and insert one membership row for each test user using the SQL Editor. Do not commit credentials.
4. Enable Realtime for `public.sync_proof_events` if the migration cannot alter the publication in the target project.

Example membership setup:

```sql
insert into public.sync_proof_memberships (business_id, user_id, role)
values
  ('BUSINESS_UUID', 'USER_A_UUID', 'owner'),
  ('BUSINESS_UUID', 'USER_B_UUID', 'manager');
```

## Required test matrix

### Online propagation

- Client A creates a product.
- Client B sees it after the Realtime signal without a manual full refresh.
- Client B can close and reopen the page and still gets the product from the cursor pull.

### Offline queue

- Disable the network on Client A.
- Create or edit a product.
- Close and reopen the app.
- Confirm the outbox remains pending and the local product remains visible.
- Restore the network and confirm one server event is created.

### Idempotency

- Force a timeout after the server commits but before the client marks the outbox applied.
- Retry the same operation ID.
- Confirm exactly one product event exists.

### Conflict

- Both clients read version N.
- Both edit the product offline with expected version N.
- The first operation applies as version N+1.
- The second operation returns `conflict` with the server copy.
- No silent last-write-wins overwrite is allowed.

### Realtime gap recovery

- Disconnect Client B after cursor N.
- Commit several updates from Client A.
- Reconnect Client B.
- Confirm Client B pulls every event with `event_id > N`.

## Build limitation in the current sandbox

The current build sandbox has Git but does not have Flutter/Dart installed. Source and SQL can be reviewed here, but the native compile, device installation, and two-device acceptance tests must be run in a Flutter-capable Windows/Android/iOS environment before this milestone is called passed.
