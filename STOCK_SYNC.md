# Toe Pwar POS · Device stock sync foundation

This work is based on the existing `inventory_pos_ios` Flutter app. The sync schema uses a separate namespace and requires an isolated Supabase test project for deployment. It does not migrate the old local POS tables or use the Shared Products project.

## Test what has been implemented

1. In a disposable Supabase project with two test users, apply the SQL migrations in filename order in SQL Editor. Run `supabase/tests/tp_inventory_sync_test.sql`. The test creates fresh fixtures in a transaction and rolls them back.
2. Build the Flutter app with `--dart-define=TP_STOCK_SYNC_PREVIEW=true`, `--dart-define=TP_STOCK_SYNC_URL=https://YOUR_TEST_PROJECT.supabase.co` and `--dart-define=TP_STOCK_SYNC_PUBLISHABLE_KEY=sb_publishable_...`. Open **Members & roles → Stock sync test** and sign in with one of the test project users.
3. Create a sync shop, add the test branch and product, add a cash account, enroll a device, and approve it as owner. Post opening stock from the approved owner device.
4. Add the other test login as a cashier by its Supabase User ID. Enroll its device, approve it on the owner screen, and allocate stock by item and device. Compare the Owner report and both device allowance views.
5. To run the isolated SQLite tests, use `flutter test test/stock_sync_test.dart`. Run the full suite with `flutter test` before merging.

## Offline checkout pilot

1. In the legacy app create a local test branch with the same **branch code** as the isolated sync branch. Create test products with identical **item codes** and local cash accounts with identical **names**. Enter fresh local stock and matching cloud opening stock. Code and name matches must be unique.
2. Save a normal sale draft in the local test branch. Open **Members & roles → Stock sync test** while online, sign in to the isolated project, select that branch and verify the approved device has an allocation.
3. Disconnect the device and choose **Offline checkout test**. Select the saved draft, enter the full payment on a mapped cash account and confirm. The app opens the existing invoice detail/printing screen. The same SQLite transaction records the invoice, stock and cash changes, local allocation consumption and one durable upload.
4. Reconnect with the sync screen still signed in, or reopen it and sign in again. It retries the upload on refresh and its polling timer. The other device's sync preview and Owner report can pick up the new balance and cash entry. Keep the regular local-only workflow out of this test branch.

The pilot supports new paid-in-full MMK sales with untracked items. It requires previously cached allowances and a signed-in preview session before going offline. Synced pilot vouchers can be viewed and printed. Edit, return, void and delete need a cloud reversal protocol before enabling them on these vouchers. The regular inventory screens, purchases and expenses, an offline sign-in after app restart, and physical-device release testing are still outside the pilot.

## Online checkout pilot

Open **Online checkout test** while connected. The server checks shared available stock after excluding offline allocations. The app confirms the local receipt only after it receives a server response. Retry the original draft with the same items and cash payments if the response is lost. The operation ID and payload are retained across restarts. A separate **Cancel pending online request** action asks the server to block further attempts and clears the local request only after the server confirms that it never posted.

Apply migrations in order before running the SQL test. A pilot receipt can be reprinted, and changes to the receipt require a future synced reversal. Regular local-only checkout and the pilot should use separate test branches. The pilot still validates against the local branch's stock and supports paid-in-full MMK cash sales without serial or lot tracking.

## Native preview builds

Pushes to `feature/device-stock-sync` trigger the **Device stock sync native preview** workflow. In GitHub **Settings → Secrets and variables → Actions → Variables**, set `TP_STOCK_SYNC_URL` and `TP_STOCK_SYNC_PUBLISHABLE_KEY` for the isolated test project before building a preview with sync enabled. These are public client configuration values. Without both variables, a run compiles the default app with the preview disabled.

The workflow publishes a portable Windows folder and an Android test APK signed with the existing debug configuration. The iOS artifact verifies that compilation succeeded and requires Apple signing and provisioning before it can be installed on a physical iPhone. Download artifacts from the exact commit's workflow run.
