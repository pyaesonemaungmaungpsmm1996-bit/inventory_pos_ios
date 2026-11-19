import 'package:sqflite/sqflite.dart';

import 'app_database.dart';
import 'app_currency.dart';
import 'app_datetime.dart';
import 'online_account_service.dart';
import 'subscription_runtime.dart';

class SimpleSetupService {
  static Future<Map<String, dynamic>> finish({
    required String name,
    required String township,
    required String city,
    required String region,
    required String ownerName,
    required String phone,
  }) async {
    final response = await OnlineAccounts.client.rpc(
      'tp_finish_simple_setup',
      params: {
        'p_name': name,
        'p_branch': name,
        'p_township': township,
        'p_city': city,
        'p_region': region,
        'p_owner_name': ownerName,
        'p_phone': phone,
        'p_installation': await OnlineAccounts.installation(),
        'p_device_name': 'Owner phone',
      },
    );
    return Map<String, dynamic>.from(response as Map);
  }

  /// The server-approved device snapshot is required before binding or local setup.
  static Future<void> connect({
    required String business,
    required String onlineBranch,
    required String businessName,
    required String branchName,
    int? localBranch,
    String currency = 'MMK',
    String phone = '',
  }) async {
    final actor = OnlineAccounts.client.auth.currentUser?.id;
    if (actor == null) throw StateError('Sign in first');
    final old = await SubscriptionRuntime.read();
    if (old['bound'] == true && old['business_id'] != business) {
      throw StateError(
        'This POS contains another business. Contact support before changing its licence.',
      );
    }
    final branches = await AppDatabase.instance.getBranches();
    if (branches.length > 1 && localBranch == null) {
      throw StateError('Choose the local branch to connect');
    }
    final local = branches.isEmpty
        ? 1
        : localBranch ?? branches.single['id'] as int;
    if (branches.isNotEmpty && !branches.any((b) => b['id'] == local)) {
      throw StateError('Local branch is unavailable');
    }
    final latest = Map<String, dynamic>.from(
      await OnlineAccounts.client.rpc(
        'tp_license_device_snapshot',
        params: {
          'p_business': business,
          'p_installation': await OnlineAccounts.installation(),
          'p_branch': onlineBranch,
        },
      ) as Map,
    );
    if (OnlineAccounts.client.auth.currentUser?.id != actor) {
      throw StateError('Account changed. Sign in again.');
    }
    if (latest['active'] != true || latest['provider_blocked'] == true) {
      throw StateError(
        'No active plan. Open Subscription to check the existing plan; do not start another trial.',
      );
    }
    latest['local_branch_name'] = branches.isEmpty
        ? branchName
        : branches.firstWhere((b) => b['id'] == local)['name'];
    final next = old['business_id'] == business
        ? old['next_local_branch'] as int?
        : null;
    await SubscriptionRuntime.bind(latest, local, next);
    await AppDatabase.instance.refreshSubscriptionFence();
    if (branches.isEmpty) {
      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        if ((await txn.query('branches', columns: ['id'])).isNotEmpty) {
          throw StateError('Branch setup changed. Retry.');
        }
        await txn.insert('branches', {
          'id': local,
          'code': 'MAIN',
          'name': branchName,
          'phone': phone,
          'address': '',
        });
        await txn.insert('app_settings', {
          'key': 'default_branch',
          'value': '$local',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.insert('app_settings', {
          'key': 'simple_setup_seed:$business:$local',
          'value': 'pending',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    }
    final profile = await AppDatabase.instance.getBusinessProfile();
    if (profile['configured'] != 1) {
      final saved = await AppDatabase.instance.saveBusinessProfile(
        name: businessName,
        countryCode: 'MM',
        currencyCode: profile['currency_locked'] == true
            ? profile['currency_code'] as String
            : currency,
        timezoneId: 'Asia/Yangon',
      );
      AppCurrency.apply(saved);
      AppDateTime.configure(saved['timezone_id'] as String);
    }
    final db = await AppDatabase.instance.database;
    await seedDefaults(db, business: business, branch: local, phone: phone);
  }

  static Future<void> seedDefaults(
    Database db, {
    required String business,
    required int branch,
    String phone = '',
  }) async {
    final local = branch;
    await db.transaction((txn) async {
      final key = 'simple_setup_seed:$business:$local';
      final marker = await txn.query(
        'app_settings',
        where: 'key=? AND value=?',
        whereArgs: [key, 'pending'],
      );
      if (marker.isEmpty) return;
      final now = DateTime.now().toUtc().toIso8601String();
      final date = AppDateTime.today().toIso8601String().substring(0, 10);
      if ((await txn.query(
        'money_accounts',
        where: 'branch_id=?',
        whereArgs: [local],
      )).isEmpty) {
        final cash = await txn.insert('money_accounts', {
          'branch_id': local,
          'name': 'Cash',
          'type': 'cash',
          'account_number': '',
          'remark': 'Created during first setup; enter actual opening balance in Money Accounts.',
          'opening_date': date,
          'created_at': now,
        });
        await txn.insert('money_entries', {
          'account_id': cash,
          'kind': 'opening',
          'amount': 0,
          'entry_date': date,
          'note': 'Initial setup — zero opening balance',
          'created_at': now,
        });
      }
      if ((await txn.query(
        'employees',
        where: 'default_branch_id=?',
        whereArgs: [local],
      )).isEmpty) {
        await txn.insert('employees', {
          'code': 'OWNER-$local',
          'name': 'Owner',
          'phone': phone,
          'position': 'Owner',
          'default_branch_id': local,
          'active': 1,
          'remark': 'Rename in Employees & Users. This is a POS salesperson record, not an access-role grant.',
          'created_at': now,
          'updated_at': now,
        });
      }
      await txn.update(
        'app_settings',
        {'value': 'complete'},
        where: 'key=?',
        whereArgs: [key],
      );
    });
  }
}
