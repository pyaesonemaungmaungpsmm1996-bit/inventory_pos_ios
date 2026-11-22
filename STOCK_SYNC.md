# Toe Pwar POS · Device stock sync foundation

This work is based on the existing `inventory_pos_ios` Flutter app. The sync schema uses a separate namespace and requires an isolated Supabase test project for deployment. It does not migrate the old local POS tables or use the Shared Products project.

## Test what has been implemented

1. In a disposable Supabase project with two test users, apply `supabase/migrations/20261122000100_tp_inventory_sync.sql` in SQL Editor. Run `supabase/tests/tp_inventory_sync_test.sql`. The test creates fresh fixtures in a transaction and rolls them back.
2. Build the Flutter app with `--dart-define=TP_STOCK_SYNC_PREVIEW=true`, `--dart-define=TP_STOCK_SYNC_URL=https://YOUR_TEST_PROJECT.supabase.co` and `--dart-define=TP_STOCK_SYNC_PUBLISHABLE_KEY=sb_publishable_...`. Open **Members & roles → Stock sync test** and sign in with one of the test project users.
3. Create a sync shop, add the test branch and product, add a cash account, enroll a device, and approve it as owner. Post opening stock from the approved owner device.
4. Add the other test login as a cashier by its Supabase User ID. Enroll its device, approve it on the owner screen, and allocate stock by item and device. Compare the Owner report and both device allowance views.
5. To run the isolated SQLite tests, use `flutter test test/stock_sync_test.dart`. Run the full suite with `flutter test` before merging.

## Current integration boundary

The gated Flutter screen covers setup, device approval, allocations, and the Owner report for synced events. The sync RPCs support stock intake and sales, expenses and cash/bank ledger postings. A SQLite outbox can atomically reserve local offline allowance inside a caller-supplied voucher transaction, and supports retry with the same operation ID.

Legacy checkout, invoice printing, purchases, customer and supplier payments, expenses, adjustments, returns/voids, and money transfers still call their original local transaction code. They are not connected to the new RPCs or the outbox. The synced screens should therefore only be used for isolated testing.

Before the preview becomes the regular POS workflow, connect branch/product/account identities and the existing invoice transaction to the outbox, add the online confirmation and local projection recovery flow, and wire the remaining money/stock postings into the shared ledger. Then verify the existing invoice output and accounting in the full app on Windows, Android, and iPhone with fresh data.
