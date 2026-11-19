import 'package:sqflite/sqflite.dart';

class MoneyPosting {
  const MoneyPosting(this.accountId, this.amount, this.date, this.label);
  final int accountId, amount;
  final String date, label;
}

Map<int, int> moneyPostingNet(Iterable<MoneyPosting> legs) {
  final net = <int, int>{};
  for (final leg in legs) {
    net[leg.accountId] = (net[leg.accountId] ?? 0) + leg.amount;
  }
  return net;
}

int checkedMoneyBalance(int balance, int delta, String accountName) {
  final result = balance + delta;
  if (result < 0) {
    throw StateError(
      'Insufficient balance in $accountName. Restore funds before reducing or voiding money already used.',
    );
  }
  if (result > 9000000000000) {
    throw StateError('Account balance limit exceeded: $accountName');
  }
  return result;
}

void validateMoneyPostingHistory({
  required Map<String, int> daily,
  required Map<String, int> changes,
  required String accountName,
}) {
  final updates = Map<String, int>.of(changes)
    ..removeWhere((_, amount) => amount == 0);
  if (updates.isEmpty) return;
  final first = (updates.keys.toList()..sort()).first;
  var running = 0;
  for (final e in daily.entries) {
    if (e.key.compareTo(first) < 0) {
      running += e.value;
    } else {
      updates[e.key] = (updates[e.key] ?? 0) + e.value;
    }
  }
  final days = updates.keys.toList()..sort();
  for (final day in days) {
    running = checkedMoneyBalance(
      running,
      updates[day]!,
      '$accountName on $day',
    );
  }
}

Future<void> validateMoneyPostings(
  Transaction txn,
  List<MoneyPosting> legs,
) async {
  for (final e in moneyPostingNet(legs).entries) {
    final rows = await txn.query(
      'money_accounts',
      where: 'id = ?',
      whereArgs: [e.key],
    );
    if (rows.length != 1) throw StateError('Account no longer exists');
    final name = rows.single['name'] as String;
    final balances = await txn.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS balance FROM money_entries WHERE account_id = ?',
      [e.key],
    );
    checkedMoneyBalance(balances.single['balance'] as int, e.value, name);
    final changes = <String, int>{};
    for (final leg in legs.where((l) => l.accountId == e.key)) {
      changes[leg.date] = (changes[leg.date] ?? 0) + leg.amount;
    }
    final history = await txn.rawQuery(
      'SELECT entry_date, SUM(amount) AS amount FROM money_entries WHERE account_id = ? GROUP BY entry_date',
      [e.key],
    );
    validateMoneyPostingHistory(
      daily: {
        for (final row in history)
          row['entry_date'] as String: row['amount'] as int,
      },
      changes: changes,
      accountName: name,
    );
  }
}
