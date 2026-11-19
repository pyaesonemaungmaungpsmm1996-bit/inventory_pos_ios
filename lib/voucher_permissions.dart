import 'online_account_service.dart';
import 'subscription_runtime.dart';

class VoucherPermissions {
  static bool allowsOwner(
    String? businessId,
    List<Map<String, dynamic>> memberships,
  ) =>
      businessId != null &&
      memberships.any(
        (b) =>
            b['id'] == businessId &&
            b['role'] == 'owner' &&
            b['active'] == true,
      );
  static Future<void> requireOwner() async {
    await OnlineAccounts.initialize();
    final actor = OnlineAccounts.client.auth.currentUser;
    if (actor == null || actor.isAnonymous) {
      throw StateError('Sign in as the business Owner to edit vouchers.');
    }
    final license = await SubscriptionRuntime.read();
    final rows = await OnlineAccounts.snapshot();
    if (OnlineAccounts.client.auth.currentUser?.id != actor.id ||
        !allowsOwner(license['business_id'] as String?, rows)) {
      throw StateError('Only the business Owner can edit posted vouchers.');
    }
  }

  static bool allowsEditing(Map<String, dynamic> license, DateTime wall) =>
      SubscriptionRuntime.effective(license, wall)['writable'] == true;

  static Future<void> requireEditable() async {
    final license = await SubscriptionRuntime.read();
    // Editing uses the same local license gate as posting; no network round trip
    // is needed to unlock. Database guards still enforce branch and stock rules.
    if (!allowsEditing(license, DateTime.now())) {
      throw StateError(
        'This device is read-only. Check its subscription and branch activation.',
      );
    }
  }
}
