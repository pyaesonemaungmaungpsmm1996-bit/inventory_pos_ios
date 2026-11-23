import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'branch_records_sync.dart';
import 'sale_confirmation_page.dart';
import 'shared_pos_session.dart';
import 'stock_sync.dart';
import 'stock_sync_checkout.dart';

class StockSyncPreviewEntry extends StatefulWidget {
  const StockSyncPreviewEntry({super.key});

  @override
  State<StockSyncPreviewEntry> createState() => _StockSyncPreviewEntryState();
}

class _StockSyncPreviewEntryState extends State<StockSyncPreviewEntry> {
  static const _url = String.fromEnvironment('TP_STOCK_SYNC_URL');
  static const _key = String.fromEnvironment('TP_STOCK_SYNC_PUBLISHABLE_KEY');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  SupabaseClient? _client;
  bool _busy = false;
  bool _emailCode = true;
  String? _codeEmail;
  String? _status;

  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    final client = _client;
    if (client != null &&
        BranchRecordsSync.publisher?.client != client &&
        BranchRecordsSync.reader?.client != client &&
        SharedPosSession.current?.connection.client != client) {
      unawaited(client.dispose());
    }
    super.dispose();
  }

  Future<void> _signIn() async {
    final url = Uri.tryParse(_url);
    if (url == null ||
        url.scheme != 'https' ||
        !_key.startsWith('sb_publishable_')) {
      setState(
        () => _status = t(
          'Configure the test project URL and publishable key at build time.',
          'စမ်းသပ် project URL နဲ့ publishable key ကို build ထုတ်ချိန် ထည့်ပါ။',
        ),
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final client = _client ??= StockSyncApi.connect(_url, _key);
      final email = _email.text.trim();
      if (_emailCode && _codeEmail != email) {
        await client.auth.signInWithOtp(email: email, shouldCreateUser: false);
        if (!mounted) return;
        setState(() {
          _codeEmail = email;
          _code.clear();
          _status = t(
            'Check your email for the sign-in code.',
            'ဝင်ရန် code ကို email ထဲမှာ စစ်ပါ။',
          );
        });
        return;
      }
      final response = _emailCode
          ? await client.auth.verifyOTP(
              email: email,
              token: _code.text.trim(),
              type: OtpType.email,
            )
          : await client.auth.signInWithPassword(
              email: email,
              password: _password.text,
            );
      final user = response.user;
      if (!mounted || user == null) return;
      _password.clear();
      _code.clear();
      _codeEmail = null;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              StockSyncSetupPage(api: StockSyncApi(client), userId: user.id),
        ),
      );
      if (BranchRecordsSync.publisher?.client != client &&
          BranchRecordsSync.reader?.client != client &&
          SharedPosSession.current?.connection.client != client) {
        await client.auth.signOut(scope: SignOutScope.local);
      }
    } catch (error) {
      if (mounted) setState(() => _status = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(t('Stock sync test login', 'စက်ကြား sync စမ်းသပ်အကောင့်')),
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (SharedPosSession.current case final shared?)
          ListTile(
            title: Text(
              t('Shared POS connected', 'မျှဝေထားသော POS ချိတ်ထားသည်'),
            ),
            subtitle: Text(shared.connection.branchCode),
            trailing: TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => SharedPosSession.current = null);
                      await shared.connection.client.auth.signOut(
                        scope: SignOutScope.local,
                      );
                      if (_client != shared.connection.client) {
                        await shared.connection.client.dispose();
                      }
                    },
              child: Text(t('Disconnect', 'ချိတ်ဆက်မှု ဖြုတ်ရန်')),
            ),
          ),
        if (BranchRecordsSync.reader case final reader?)
          ListTile(
            title: Text(
              t('Windows records connected', 'Windows စာရင်း ချိတ်ထားသည်'),
            ),
            subtitle: Text(reader.branchCode),
            onTap: _busy
                ? null
                : () {
                    final user = reader.client.auth.currentUser;
                    if (user == null) return;
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => StockSyncSetupPage(
                          api: StockSyncApi(reader.client),
                          userId: user.id,
                        ),
                      ),
                    );
                  },
            trailing: TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => BranchRecordsSync.reader = null);
                      try {
                        await reader.client.auth.signOut(
                          scope: SignOutScope.local,
                        );
                      } finally {
                        if (_client != reader.client) {
                          await reader.client.dispose();
                        }
                      }
                    },
              child: Text(t('Disconnect', 'ချိတ်ဆက်မှု ဖြုတ်ရန်')),
            ),
          ),
        if (BranchRecordsSync.publisher case final publisher?)
          ListTile(
            title: Text(
              t('Windows records sync is on', 'Windows စာရင်း ပို့နေသည်'),
            ),
            subtitle: Text(publisher.error?.toString() ?? publisher.branchCode),
            trailing: TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      await publisher.stop();
                      BranchRecordsSync.publisher = null;
                      await publisher.client.auth.signOut(
                        scope: SignOutScope.local,
                      );
                      if (_client != publisher.client) {
                        await publisher.client.dispose();
                      }
                      if (mounted) setState(() => _busy = false);
                    },
              child: Text(t('Stop sync', 'စာရင်းပို့ခြင်း ရပ်ရန်')),
            ),
          ),
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        if (!_emailCode)
          TextField(
            controller: _password,
            enabled: !_busy,
            obscureText: true,
            decoration: InputDecoration(labelText: t('Password', 'စကားဝှက်')),
          ),
        if (_emailCode && _codeEmail != null)
          TextField(
            controller: _code,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            decoration: InputDecoration(
              labelText: t('Email code', 'Email မှ code'),
            ),
          ),
        if (_status != null) SelectableText(_status!),
        if (_emailCode && _codeEmail != null)
          TextButton(
            onPressed: _busy
                ? null
                : () {
                    setState(() => _codeEmail = null);
                    unawaited(_signIn());
                  },
            child: Text(t('Send a new code', 'Code အသစ် ပို့ရန်')),
          ),
        FilledButton(
          onPressed:
              _busy ||
                  BranchRecordsSync.publisher != null ||
                  BranchRecordsSync.reader != null ||
                  SharedPosSession.current != null
              ? null
              : _signIn,
          child: Text(
            _emailCode && _codeEmail == null
                ? t('Send email code', 'Email code ပို့ရန်')
                : t('Sign in to test project', 'စမ်းသပ် project သို့ ဝင်ရန်'),
          ),
        ),
        TextButton(
          onPressed:
              _busy ||
                  BranchRecordsSync.publisher != null ||
                  BranchRecordsSync.reader != null ||
                  SharedPosSession.current != null
              ? null
              : () {
                  setState(() {
                    _emailCode = !_emailCode;
                    _codeEmail = null;
                    _code.clear();
                    _password.clear();
                    _status = null;
                  });
                },
          child: Text(
            _emailCode
                ? t('Use password', 'စကားဝှက်ဖြင့် ဝင်ရန်')
                : t('Use email code', 'Email code ဖြင့် ဝင်ရန်'),
          ),
        ),
      ],
    ),
  );
}

class StockSyncSetupPage extends StatefulWidget {
  final StockSyncApi api;
  final String userId;

  const StockSyncSetupPage({
    super.key,
    required this.api,
    required this.userId,
  });

  @override
  State<StockSyncSetupPage> createState() => _StockSyncSetupPageState();
}

class _StockSyncSetupPageState extends State<StockSyncSetupPage> {
  final _storage = const FlutterSecureStorage();
  List<Map<String, dynamic>> _shops = [];
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _snapshot;
  Map<String, dynamic>? _branchRecords;
  String? _shop;
  String? _branch;
  String? _error;
  bool _busy = false;
  int _pendingSales = 0;
  bool _pendingAdmin = false;
  StreamSubscription<int>? _updates;
  Timer? _poll;
  DateTimeRange? _period;

  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

  List<Map<String, dynamic>> rows(Object? value) => [
    if (value is List)
      for (final row in value) Map<String, dynamic>.from(row as Map),
  ];

  Map<String, dynamic>? get _selected {
    for (final shop in _shops) {
      if (shop['id'] == _shop) return shop;
    }
    return null;
  }

  bool get _owner => _selected?['role'] == 'owner';

  Future<BranchRecordsSync?> _recordsClient() async {
    final shop = _shop;
    final branch = _branch;
    if (shop == null || branch == null) return null;
    final identity = await _identity(shop, branch);
    if (identity == null) return null;
    final code =
        rows(_selected?['branches'])
                .singleWhere((row) => row['id'] == branch)['code']
            as String;
    return BranchRecordsSync(
      client: widget.api.client,
      shop: shop,
      branchCode: code,
      device: identity['id']!,
      secret: identity['secret']!,
    );
  }

  Future<void> _publishWindowsRecords() async {
    final sync = await _recordsClient();
    if (sync == null || BranchRecordsSync.publisher != null) return;
    await sync.start();
    BranchRecordsSync.publisher = sync;
  }

  Iterable<Widget> _recordSections(Map<String, dynamic> records) sync* {
    yield Text(t('Synced Windows records', 'Windows မှ တင်ထားသော စာရင်းများ'));
    yield Text('${records['updated_at']}');
    for (final (key, label) in [
      ('stock', t('Balance stock', 'ပစ္စည်းလက်ကျန်')),
      ('sales', t('Sale history', 'အရောင်းမှတ်တမ်း')),
      ('purchases', t('Purchase history', 'အဝယ်မှတ်တမ်း')),
    ]) {
      final items = rows(records[key]);
      yield ExpansionTile(
        title: Text('$label (${items.length})'),
        children: [
          for (final row in items)
            ListTile(
              title: Text(
                key == 'stock'
                    ? '${row['item_code']} · ${row['name']}'
                    : '${row['number']} · ${row['invoice_date']}',
              ),
              subtitle: Text(
                key == 'stock'
                    ? '${t('Stock', 'လက်ကျန်')}: ${row['stock']}'
                    : '${row['total']} ${row['currency_code']} · ${row['status']}',
              ),
            ),
        ],
      );
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_run(_refresh));
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!_busy && mounted) unawaited(_run(_refresh));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_updates?.cancel());
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, String>?> _identity(String shop, String branch) async {
    final raw = await _storage.read(key: _deviceKey(shop, branch));
    if (raw == null) return null;
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  String _deviceKey(String shop, String branch) =>
      'tp_stock_sync_${widget.userId}_${shop}_$branch';

  DateTime _yangonStart(DateTime day) => DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).subtract(const Duration(hours: 6, minutes: 30));

  Future<void> _refresh() async {
    final shops = await widget.api.catalog();
    if (!mounted) return;
    final selection = shops.any((row) => row['id'] == _shop)
        ? _shop
        : shops.firstOrNull?['id'] as String?;
    final changed = selection != _shop;
    _shops = shops;
    _shop = selection;
    final branches = rows(_selected?['branches']);
    final branch = branches.any((row) => row['id'] == _branch)
        ? _branch
        : branches.firstOrNull?['id'] as String?;
    if (branch != _branch) {
      _snapshot = null;
      _branchRecords = null;
      _pendingSales = 0;
    }
    _branch = branch;
    if (changed) {
      _report = null;
      _snapshot = null;
      _branchRecords = null;
      _pendingSales = 0;
    }
    _pendingAdmin =
        selection != null &&
        await _storage.read(key: _adminKey(selection)) != null;
    if (selection == null) return;
    if (_updates == null || changed) {
      await _updates?.cancel();
      if (!mounted) return;
      _updates = widget.api.revisions(selection).listen((_) {
        if (!_busy) unawaited(_run(_refresh));
      }, onError: (Object _) {});
    }

    if (_owner) {
      final now = DateTime.now().toUtc().add(
        const Duration(hours: 6, minutes: 30),
      );
      final start = _yangonStart(_period?.start ?? now);
      final until = _yangonStart(_period?.end ?? now)
          .add(const Duration(days: 1));
      _report = await widget.api.ownerReport(
        shop: selection,
        from: start,
        until: until,
      );
    }
    if (branch == null) return;
    final device = await _identity(selection, branch);
    if (device == null) return;
    final approved = await widget.api.enroll(
      shop: selection,
      branch: branch,
      device: device['id']!,
      label: device['label']!,
      secret: device['secret']!,
    );
    if (!approved) return;
    if (_owner && !Platform.isWindows) {
      final records = await _recordsClient();
      _branchRecords = await records?.read();
    }
    final db = await AppDatabase.instance.database;
    final store = OfflineStockStore(shop: selection, device: device['id']!);
    await OfflineStockStore.ensureTables(db);
    _pendingSales = await store.pendingCount(db);
    await OfflineStockUploader(
      store: store,
      api: widget.api,
      secret: device['secret']!,
    ).flush(db);
    final snapshot = await widget.api.snapshot(
      shop: selection,
      device: device['id']!,
      secret: device['secret']!,
    );
    _pendingSales = 0;
    await store.applySnapshot(
      db,
      rows(snapshot['products']),
      snapshot: snapshot,
    );
    final products = rows(snapshot['products']);
    for (final product in products) {
      product['offline_remaining'] = await store.remaining(
        db,
        product['id'] as String,
      );
    }
    snapshot['products'] = products;
    _snapshot = snapshot;
  }

  Map<int, String> _mapCodes(
    List<Map<String, Object?>> local,
    List<Map<String, dynamic>> remote,
    String localField,
    String remoteField,
  ) {
    return {
      for (final row in local)
        if (row[localField] != null &&
            local.where((item) => item[localField] == row[localField]).length ==
                1 &&
            remote
                    .where((item) => item[remoteField] == row[localField])
                    .length ==
                1)
          row['id'] as int:
              remote.singleWhere(
                    (item) => item[remoteField] == row[localField],
                  )['id']
                  as String,
    };
  }

  Future<void> _openSyncDraft({
    required bool online,
    bool cancel = false,
  }) async {
    final shop = _shop;
    final branch = _branch;
    final snapshot = _snapshot;
    if (shop == null ||
        branch == null ||
        snapshot == null ||
        snapshot['branch_id'] != branch ||
        _busy) {
      return;
    }
    final branches = rows(_selected?['branches']);
    final branchCode = branches.singleWhere(
      (row) => row['id'] == branch,
    )['code'];
    try {
      final app = AppDatabase.instance;
      final local = (await app.getBranches())
          .where((item) => item['code'] == branchCode)
          .toList();
      if (local.length != 1) {
        throw StateError(
          t(
            'Create a local branch with the same branch code.',
            'တူညီတဲ့ ဆိုင်ခွဲကုဒ်နဲ့ local ဆိုင်ခွဲဖန်တီးပါ။',
          ),
        );
      }
      final localBranchId = local.single['id'] as int;
      final device = await _identity(shop, branch);
      if (device == null) return;
      final drafts = await app.getSaleDrafts(branchId: localBranchId);
      final products = await app.getProducts(branchId: localBranchId);
      final accounts = (await app.getMoneyAccounts(branchId: localBranchId))
          .where((item) => item['type'] == 'cash')
          .toList();
      if (!mounted || shop != _shop || branch != _branch) return;
      if (drafts.isEmpty) {
        throw StateError(
          t(
            'Save a regular sale draft for this local branch first.',
            'ဒီ local ဆိုင်ခွဲအတွက် ပုံမှန်အရောင်း Draft ကို အရင်သိမ်းပါ။',
          ),
        );
      }
      final checkout = StockSyncCheckout(
        store: OfflineStockStore(shop: shop, device: device['id']!),
        localBranchId: localBranchId,
        onlineApi: online ? widget.api : null,
        onlineSecret: online ? device['secret'] : null,
        products: _mapCodes(
          products,
          rows(snapshot['products']),
          'item_code',
          'code',
        ),
        cashAccounts: _mapCodes(
          accounts,
          rows(snapshot['accounts'])
              .where((row) => row['kind'] == 'cash')
              .toList(),
          'name',
          'name',
        ),
      );
      final draft = await showDialog<int>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: Text(
            t(
              'Open a draft for offline checkout',
              'Offline အရောင်းအတွက် Draft ဖွင့်ရန်',
            ),
          ),
          children: [
            for (final row in drafts)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, row['id'] as int),
                child: Text(
                  'Draft #${row['id']} · ${row['invoice_date']} · ${row['total']} MMK',
                ),
              ),
          ],
        ),
      );
      if (!mounted || draft == null || shop != _shop || branch != _branch) {
        return;
      }
      if (cancel) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(
              t(
                'Cancel pending online checkout?',
                'စောင့်နေတဲ့ online အရောင်း ပယ်ဖျက်မလား။',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(t('Keep request', 'တောင်းဆိုမှု ဆက်ထားရန်')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text(t('Cancel request', 'တောင်းဆိုမှု ပယ်ဖျက်ရန်')),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
        final db = await app.database;
        final cancelled = await checkout.cancelOnline(db, draft);
        if (!cancelled) {
          throw StateError('This draft has no pending online request.');
        }
        return;
      }

      final id = await Navigator.of(context).push(
        MaterialPageRoute<int>(
          builder: (_) =>
              SaleConfirmationPage(draftId: draft, offlineCheckout: checkout),
        ),
      );
      if (!mounted || id == null) return;
      final db = await app.database;
      final waiting = await checkout.store.pendingCount(db);
      if (!mounted) return;
      setState(() => _pendingSales = waiting);
      unawaited(_run(_refresh));
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ConfirmedSaleDetailPage(saleId: id),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<List<String>?> _ask(String title, List<String> labels) async {
    final controllers = [for (final _ in labels) TextEditingController()];
    try {
      return await showDialog<List<String>>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < labels.length; i++)
                  TextField(
                    controller: controllers[i],
                    decoration: InputDecoration(labelText: labels[i]),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('Cancel', 'ပယ်ဖျက်ရန်')),
            ),
            FilledButton(
              onPressed: () {
                final values = controllers
                    .map((field) => field.text.trim())
                    .toList();
                if (values.any((value) => value.isEmpty)) return;
                Navigator.pop(context, values);
              },
              child: Text(t('Save', 'သိမ်းရန်')),
            ),
          ],
        ),
      );
    } finally {
      for (final field in controllers) {
        field.dispose();
      }
    }
  }

  Future<void> _newShop() async {
    final answer = await _ask(t('New sync shop', 'စမ်းသပ်ဆိုင်အသစ်'), [
      t('Shop name', 'ဆိုင်အမည်'),
      t('Branch code', 'ဆိုင်ခွဲကုဒ်'),
      t('Branch name', 'ဆိုင်ခွဲအမည်'),
    ]);
    if (answer == null) return;
    await _run(() async {
      final shop = await widget.api.createShop(
        name: answer[0],
        currency: 'MMK',
        branchCode: answer[1],
        branchName: answer[2],
      );
      await _updates?.cancel();
      _updates = null;
      _shop = shop['shop_id'] as String;
      _branch = shop['branch_id'] as String;
      await _refresh();
    });
  }

  Future<void> _enroll() async {
    final shop = _shop;
    final branch = _branch;
    if (shop == null || branch == null) return;
    final answer = await _ask(
      t('Enroll this device', 'ဤစက်ကို စာရင်းသွင်းရန်'),
      [t('Device name', 'စက်အမည်')],
    );
    if (answer == null) return;
    await _run(() async {
      final existing = await _identity(shop, branch);
      if (existing == null) {
        final device = {
          'id': newStockSyncId(),
          'label': answer.single,
          'secret': newStockSyncSecret(),
        };
        await _storage.write(
          key: _deviceKey(shop, branch),
          value: jsonEncode(device),
        );
      }
      await _refresh();
    });
  }

  String _adminKey(String shop) => 'tp_stock_sync_admin_${widget.userId}_$shop';

  Future<void> _admin(Map<String, Object?>? command) async {
    final shop = _shop;
    if (shop == null) return;
    await _run(() async {
      final key = _adminKey(shop);
      final existing = await _storage.read(key: key);
      if (existing != null && command != null) {
        throw StateError(
          t(
            'Retry the previous request first.',
            'အရင်တောင်းဆိုမှုကို အရင်ပြန်စမ်းပါ။',
          ),
        );
      }
      if (existing == null && command == null) return;
      final request = existing == null
          ? {'operation': newStockSyncId(), 'command': command}
          : Map<String, Object?>.from(jsonDecode(existing) as Map);
      await _storage.write(key: key, value: jsonEncode(request));
      _pendingAdmin = true;
      try {
        await widget.api.admin(
          shop: shop,
          operation: request['operation'] as String,
          command: Map<String, Object?>.from(request['command'] as Map),
        );
      } on PostgrestException catch (error) {
        if (const {
          '42501',
          'P0001',
          '23505',
          '23503',
          '23514',
          '22P02',
        }.contains(error.code)) {
          await _storage.delete(key: key);
          _pendingAdmin = false;
        }
        rethrow;
      }
      await _storage.delete(key: key);
      _pendingAdmin = false;
      await _refresh();
    });
  }

  Future<void> _addBranch() async {
    final values = await _ask(t('Add branch', 'ဆိုင်ခွဲထည့်ရန်'), [
      t('Branch code', 'ဆိုင်ခွဲကုဒ်'),
      t('Branch name', 'ဆိုင်ခွဲအမည်'),
    ]);
    if (values != null) {
      await _admin({'action': 'branch', 'code': values[0], 'name': values[1]});
    }
  }

  Future<void> _addCashAccount() async {
    final branch = _branch;
    if (branch == null) return;
    final values = await _ask(t('Add cash account', 'Cash account ထည့်ရန်'), [
      t('Account name', 'အကောင့်အမည်'),
    ]);
    if (values != null) {
      await _admin({
        'action': 'account',
        'branch_id': branch,
        'kind': 'cash',
        'name': values.single,
      });
    }
  }

  Future<void> _addProduct() async {
    final values = await _ask(t('Add product', 'ပစ္စည်းထည့်ရန်'), [
      t('Item code', 'ပစ္စည်းကုဒ်'),
      t('Product name', 'ပစ္စည်းအမည်'),
      t('Selling price (MMK)', 'ရောင်းဈေး (ကျပ်)'),
    ]);
    if (values == null) return;
    final price = int.tryParse(values[2]);
    if (price == null || price < 0) {
      setState(
        () => _error = t('Enter a valid amount.', 'ဈေးနှုန်းမှန်ကို ထည့်ပါ။'),
      );
      return;
    }
    await _admin({
      'action': 'product',
      'code': values[0],
      'name': values[1],
      'sale_price_minor': price,
    });
  }

  Future<void> _fundTestCash() async {
    final values = await _ask(t('Add test cash', 'စမ်းသပ်ငွေ ထည့်ရန်'), [
      t('Cash account name', 'ငွေအကောင့်နာမည်'),
      t('Amount (MMK)', 'ငွေပမာဏ (ကျပ်)'),
    ]);
    if (values == null) return;
    await _run(() async {
      final connection = await _recordsClient();
      final account = rows(_snapshot?['accounts'])
          .where((row) => row['kind'] == 'cash' && row['name'] == values[0])
          .firstOrNull;
      final amount = int.tryParse(values[1]);
      if (connection == null || account == null || amount == null) {
        throw StateError('Check the cash account and amount.');
      }
      await SharedPosSession(connection)
          .deposit(account['id'] as String, amount);
      await _refresh();
    });
  }

  Future<void> _enableSerial() async {
    final shop = _shop;
    if (shop == null) return;
    final values = await _ask(
      t('Enable serial tracking', 'Serial မှတ်တမ်း ဖွင့်ရန်'),
      [t('Item code', 'ပစ္စည်းကုဒ်')],
    );
    if (values == null) return;
    await _run(() async {
      final product = rows(_selected?['products'])
          .where((item) => item['code'] == values.single)
          .firstOrNull;
      if (product == null) throw StateError('Item code not found.');
      await widget.api.client.rpc(
        'tp_stock_sync_enable_serial',
        params: {'shop': shop, 'product': product['id']},
      );
      await _refresh();
    });
  }

  Future<void> _openingStock() async {
    final shop = _shop;
    final branch = _branch;
    if (shop == null || branch == null || _snapshot == null) return;
    final values = await _ask(t('Opening stock', 'အဖွင့်လက်ကျန်'), [
      t('Item code', 'ပစ္စည်းကုဒ်'),
      t('Quantity', 'အရေအတွက်'),
    ]);
    if (values == null) return;
    final product = rows(_snapshot?['products'])
        .where((item) => item['code'] == values[0])
        .firstOrNull;
    final quantity = int.tryParse(values[1]);
    if (product == null || quantity == null || quantity <= 0) {
      setState(
        () => _error = t(
          'Check the item code and quantity.',
          'ပစ္စည်းကုဒ်နဲ့ အရေအတွက် စစ်ပါ။',
        ),
      );
      return;
    }
    await _run(() async {
      final device = await _identity(shop, branch);
      if (device == null) return;
      await widget.api.post(
        shop: shop,
        device: device['id']!,
        secret: device['secret']!,
        operation: newStockSyncId(),
        command: {
          'kind': 'opening',
          'lines': [
            {
              'product_id': product['id'],
              'quantity': quantity,
              'unit_minor': 0,
            },
          ],
        },
      );
      await _refresh();
    });
  }

  Future<void> _addMember() async {
    final roles = ['manager', 'cashier', 'stock_staff', 'accountant'];
    final values = await _ask(
      t('Add existing login', 'ရှိပြီးသား login ချိတ်ရန်'),
      [t('Supabase User ID', 'Supabase User ID'), roles.join(' / ')],
    );
    if (values == null) return;
    if (!roles.contains(values[1])) {
      setState(
        () => _error = t(
          'Enter a role from the list.',
          'စာရင်းထဲက role တစ်ခု ထည့်ပါ။',
        ),
      );
      return;
    }
    await _admin({'action': 'member', 'user_id': values[0], 'role': values[1]});
  }

  Future<void> _allocate(
    String device,
    List<Map<String, dynamic>> products,
  ) async {
    if (products.isEmpty) return;
    String product = products.first['id'] as String;
    final input = TextEditingController();
    try {
      final answer = await showDialog<MapEntry<String, int>>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              t('Allocate offline selling stock', 'Offline ရောင်းခွင့် ခွဲရန်'),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: product,
                  isExpanded: true,
                  items: [
                    for (final row in products)
                      DropdownMenuItem(
                        value: row['id'] as String,
                        child: Text('${row['code']} · ${row['name']}'),
                      ),
                  ],
                  onChanged: (value) => update(() => product = value!),
                ),
                TextField(
                  controller: input,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: t('Quantity', 'အရေအတွက်'),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('Cancel', 'ပယ်ဖျက်ရန်')),
              ),
              FilledButton(
                onPressed: () {
                  final quantity = int.tryParse(input.text.trim());
                  if (quantity != null && quantity > 0) {
                    Navigator.pop(context, MapEntry(product, quantity));
                  }
                },
                child: Text(t('Allocate', 'ခွဲဝေရန်')),
              ),
            ],
          ),
        ),
      );
      if (answer != null) {
        await _admin({
          'action': 'grant_stock',
          'device_id': device,
          'product_id': answer.key,
          'quantity': answer.value,
        });
      }
    } finally {
      input.dispose();
    }
  }

  Widget _branchCard(Map<String, dynamic> details) {
    final currency = _selected?['currency'] ?? 'MMK';
    return Card(
      child: ExpansionTile(
        title: Text('${details['name']} (${details['code']})'),
        subtitle: Text(
          '${t('Sales', 'အရောင်း')}: ${details['sale_minor']} $currency · '
          '${t('Received', 'လက်ခံပြီး')}: ${details['paid_sale_minor']} $currency · '
          '${t('Outstanding', 'အကြွေးကျန်')}: ${(details['sale_minor'] as int) - (details['paid_sale_minor'] as int)} $currency · '
          '${t('Expenses', 'အသုံးစရိတ်')}: ${details['expense_minor']} $currency',
        ),
        children: [
          for (final stock in rows(details['stock']))
            ListTile(
              title: Text('${stock['code']} · ${stock['name']}'),
              subtitle: Text(
                '${t('On hand', 'လက်ကျန်')} ${stock['on_hand']} · '
                '${t('Reserved', 'စက်အတွက် ခွဲထား')} ${stock['reserved']} · '
                '${t('Available online', 'Online ရောင်းနိုင်')} ${stock['available_online']}',
              ),
            ),
          for (final account in rows(details['accounts']))
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text('${account['name']}'),
              trailing: Text('${account['balance_minor']} $currency'),
            ),
          for (final sale in rows(details['sales']))
            ListTile(
              leading: const Icon(Icons.point_of_sale_outlined),
              title: Text(sale['voucher']?.toString() ?? t('Sale', 'အရောင်း')),
              subtitle: Text(
                sale['offline'] == true
                    ? t('Offline sale', 'Offline အရောင်း')
                    : t('Online sale', 'Online အရောင်း'),
              ),
              trailing: Text('${sale['amount_minor']} $currency'),
            ),

          for (final expense in rows(details['expenses']))
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(
                expense['note']?.toString() ?? t('Expense', 'အသုံးစရိတ်'),
              ),
              trailing: Text('${expense['amount_minor']} $currency'),
            ),
          for (final device in rows(details['devices']))
            ListTile(
              leading: const Icon(Icons.devices_outlined),
              title: Text('${device['label']}'),
              subtitle: Text(
                '${t('Last sync', 'နောက်ဆုံး sync')}: ${device['last_sync_at'] ?? '—'}',
              ),
              trailing: device['approved'] == true
                  ? TextButton(
                      onPressed: _busy || rows(_selected?['products']).isEmpty
                          ? null
                          : () => _allocate(
                              device['id'] as String,
                              rows(_selected?['products']),
                            ),
                      child: Text(t('Allocate', 'ခွဲဝေရန်')),
                    )
                  : TextButton(
                      onPressed: _busy
                          ? null
                          : () => _admin({
                              'action': 'approve_device',
                              'device_id': device['id'],
                            }),
                      child: Text(t('Approve', 'အတည်ပြုရန်')),
                    ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branches = rows(_selected?['branches']);
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Stock sync test', 'စက်ကြား လက်ကျန် စမ်းသပ်မှု')),
        actions: [
          IconButton(
            onPressed: _busy ? null : () => _run(_refresh),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            SelectableText(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (_shops.isEmpty)
            OutlinedButton(
              onPressed: _busy ? null : _newShop,
              child: Text(t('New sync shop', 'စမ်းသပ်ဆိုင်အသစ်')),
            ),
          if (_shops.isNotEmpty)
            DropdownButton<String>(
              isExpanded: true,
              value: _shop,
              items: [
                for (final row in _shops)
                  DropdownMenuItem(
                    value: row['id'] as String,
                    child: Text('${row['name']}'),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => _run(() async {
                      await _updates?.cancel();
                      _updates = null;
                      _snapshot = null;
                      _branchRecords = null;
                      _report = null;
                      _pendingSales = 0;
                      _shop = value;
                      _branch = null;
                      await _refresh();
                    }),
            ),
          if (branches.isNotEmpty) ...[
            DropdownButton<String>(
              isExpanded: true,
              value: _branch,
              items: [
                for (final row in branches)
                  DropdownMenuItem(
                    value: row['id'] as String,
                    child: Text('${row['name']}'),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => _run(() async {
                      _snapshot = null;
                      _branchRecords = null;
                      _pendingSales = 0;
                      _branch = value;
                      await _refresh();
                    }),
            ),
            if (_snapshot == null)
              OutlinedButton(
                onPressed: _busy ? null : _enroll,
                child: Text(t('Enroll this device', 'ဤစက်ကို စာရင်းသွင်းရန်')),
              ),
          ],
          if (_snapshot != null && _owner && Platform.isWindows)
            OutlinedButton(
              onPressed: _busy || BranchRecordsSync.publisher != null
                  ? null
                  : () => _run(_publishWindowsRecords),
              child: Text(
                t('Sync Windows POS records', 'Windows POS စာရင်း ပို့ရန်'),
              ),
            ),
          if (_snapshot != null &&
              _owner &&
              SharedPosSession.current == null &&
              BranchRecordsSync.reader == null &&
              BranchRecordsSync.publisher == null)
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                      final connection = await _recordsClient();
                      if (connection == null) return;
                      final session = SharedPosSession(connection);
                      await session.load();
                      if (context.mounted) {
                        SharedPosSession.current = session;
                        Navigator.of(context).pop();
                      }
                    }),
              child: Text(
                t(
                  'Open shared POS test mode',
                  'မျှဝေထားသော POS စမ်းသပ်မုဒ် ဖွင့်ရန်',
                ),
              ),
            ),
          if (_snapshot != null && _owner && _branchRecords != null) ...[
            if (!Platform.isWindows)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        BranchRecordsSync.reader = await _recordsClient();
                      }),
                child: Text(
                  t(
                    'Use Windows records in POS menus',
                    'ပုံမှန် POS မီနူးတွင် Windows စာရင်းပြရန်',
                  ),
                ),
              ),
            ..._recordSections(_branchRecords!),
          ],
          if (_snapshot != null &&
              const [
                'owner',
                'manager',
                'cashier',
              ].contains(_selected?['role']))
            OutlinedButton(
              onPressed: _busy ? null : () => _openSyncDraft(online: false),
              child: Text(
                t('Offline checkout test', 'Offline အရောင်း စမ်းသပ်ရန်'),
              ),
            ),
          if (_snapshot != null &&
              const [
                'owner',
                'manager',
                'cashier',
              ].contains(_selected?['role']))
            OutlinedButton(
              onPressed: _busy ? null : () => _openSyncDraft(online: true),
              child: Text(
                t('Online checkout test', 'Online အရောင်း စမ်းသပ်ရန်'),
              ),
            ),
          if (_snapshot != null &&
              const [
                'owner',
                'manager',
                'cashier',
              ].contains(_selected?['role']))
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _openSyncDraft(online: true, cancel: true),
              child: Text(
                t(
                  'Cancel pending online request',
                  'စောင့်နေတဲ့ online request ပယ်ဖျက်ရန်',
                ),
              ),
            ),

          if (_pendingSales > 0)
            Text(
              '${t('Sales waiting to sync', 'Sync ပို့ရန်ကျန်သော အရောင်း')}: $_pendingSales',
            ),

          if (_snapshot != null)
            for (final stock in rows(_snapshot!['products']))
              ListTile(
                title: Text('${stock['name']}'),
                subtitle: Text(
                  '${t('Shared on hand', 'ဆိုင်ခွဲ လက်ကျန်')}: ${stock['on_hand']} · '
                  '${t('Available online', 'Online ရောင်းနိုင်')}: ${stock['available_online']}',
                ),
                trailing: Text(
                  '${t('This device', 'ဤစက်ရောင်းခွင့်')} '
                  '${stock['offline_remaining']}',
                ),
              ),
          if (_owner) ...[
            if (_pendingAdmin)
              FilledButton(
                onPressed: _busy ? null : () => _admin(null),
                child: Text(
                  t(
                    'Retry previous request',
                    'အရင်တောင်းဆိုမှုကို ပြန်စမ်းရန်',
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : _addBranch,
                  child: Text(t('Add branch', 'ဆိုင်ခွဲထည့်ရန်')),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _addProduct,
                  child: Text(t('Add product', 'ပစ္စည်းထည့်ရန်')),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _enableSerial,
                  child: Text(
                    t('Enable serial tracking', 'Serial မှတ်တမ်း ဖွင့်ရန်'),
                  ),
                ),
                OutlinedButton(
                  onPressed: _busy || _branch == null ? null : _addCashAccount,
                  child: Text(t('Add cash account', 'Cash account ထည့်ရန်')),
                ),
                OutlinedButton(
                  onPressed: _busy || _snapshot == null ? null : _fundTestCash,
                  child: Text(t('Add test cash', 'စမ်းသပ်ငွေ ထည့်ရန်')),
                ),
                OutlinedButton(
                  onPressed: _busy || _snapshot == null ? null : _openingStock,
                  child: Text(t('Opening stock', 'အဖွင့်လက်ကျန်')),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _addMember,
                  child: Text(
                    t('Add existing login', 'ရှိပြီးသား login ချိတ်ရန်'),
                  ),
                ),
              ],
            ),

            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final now = DateTime.now();
                      final period = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(now.year + 1),
                        initialDateRange: _period,
                      );
                      if (period != null && mounted) {
                        await _run(() async {
                          _period = period;
                          await _refresh();
                        });
                      }
                    },
              child: Text(t('Report date range', 'Report ရက်စွဲ ရွေးရန်')),
            ),
            for (final details in rows(_report?['branches']))
              _branchCard(details),
          ],
        ],
      ),
    );
  }
}
