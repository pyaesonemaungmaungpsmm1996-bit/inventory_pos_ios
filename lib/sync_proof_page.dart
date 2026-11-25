import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'online_account_service.dart';
import 'sync_proof/local_store.dart';
import 'sync_proof/models.dart';
import 'sync_proof/remote_repository.dart';
import 'sync_proof/sync_engine.dart';

class SyncProofPage extends StatefulWidget {
  const SyncProofPage({super.key});

  @override
  State<SyncProofPage> createState() => _SyncProofPageState();
}

class _SyncProofPageState extends State<SyncProofPage> {
  final businessController = TextEditingController();
  final productController = TextEditingController();
  final nameController = TextEditingController(text: 'Sync proof product');
  final priceController = TextEditingController(text: '1000');

  SyncProofLocalStore? local;
  SyncProofEngine? engine;
  String? deviceId;
  String status = 'Not initialized';
  String? userId;
  List<Map<String, Object?>> products = const [];
  List<Map<String, Object?>> outbox = const [];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    productController.text = _uuidV4();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    setState(() => status = 'Connecting to Supabase…');
    try {
      await OnlineAccounts.initialize();
      final db = await AppDatabase.instance.database;
      final store = SyncProofLocalStore(db);
      final installation = await OnlineAccounts.installation();
      final sessionUser = OnlineAccounts.client.auth.currentUser;
      if (!mounted) return;
      setState(() {
        local = store;
        deviceId = installation;
        userId = sessionUser?.id;
        status = sessionUser == null
            ? 'Supabase connected; sign in before syncing'
            : 'Ready';
      });
      await _refreshLocal();
    } catch (error) {
      if (mounted) setState(() => status = 'Initialization failed: $error');
    }
  }

  Future<void> _refreshLocal() async {
    final store = local;
    if (store == null) return;
    final nextProducts = await store.products();
    final nextOutbox = await store.outbox();
    if (mounted) setState(() {
      products = nextProducts;
      outbox = nextOutbox;
    });
  }

  Future<void> _queueProduct() async {
    final store = local;
    final businessId = businessController.text.trim();
    final productId = productController.text.trim();
    final name = nameController.text.trim();
    final price = int.tryParse(priceController.text.trim());
    if (store == null || deviceId == null || businessId.isEmpty ||
        productId.isEmpty || name.isEmpty || price == null || price < 0) {
      setState(() => status = 'Fill business ID, product ID, name and valid price');
      return;
    }
    final existing = products.cast<Map<String, Object?>>().where(
      (row) => '${row['id']}' == productId,
    );
    final expectedVersion = existing.isEmpty ? null : existing.first['version'] as int?;
    final operation = SyncProofOperation(
      operationId: _uuidV4(),
      businessId: businessId,
      deviceId: deviceId!,
      productId: productId,
      name: name,
      price: price,
      expectedVersion: expectedVersion,
      status: SyncOperationStatus.pending,
    );
    await store.saveLocalProductAndQueue(operation);
    await _refreshLocal();
    if (mounted) setState(() => status = 'Saved locally and queued: ${operation.operationId}');
  }

  Future<void> _syncNow() async {
    final store = local;
    final businessId = businessController.text.trim();
    if (store == null || businessId.isEmpty) {
      setState(() => status = 'Enter the shared business UUID first');
      return;
    }
    if (OnlineAccounts.client.auth.currentUser == null) {
      setState(() => status = 'Sign in to the active Supabase project first');
      return;
    }
    setState(() {
      busy = true;
      status = 'Syncing…';
    });
    try {
      final current = engine;
      if (current != null) {
        await current.syncOnce(businessId: businessId);
      } else {
        final next = SyncProofEngine(
          local: store,
          remote: SyncProofRemoteRepository(OnlineAccounts.client),
        );
        engine = next;
        await next.start(businessId: businessId);
      }
      await _refreshLocal();
      if (mounted) setState(() => status = 'Sync completed');
    } catch (error) {
      if (mounted) setState(() => status = 'Sync failed: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(engine?.dispose());
    businessController.dispose();
    productController.dispose();
    nameController.dispose();
    priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sync Proof Test')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(status),
            const SizedBox(height: 8),
            SelectableText('User: ${userId ?? 'not signed in'}'),
            SelectableText('Device: ${deviceId ?? 'loading'}'),
            const Divider(height: 32),
            TextField(
              controller: businessController,
              decoration: const InputDecoration(
                labelText: 'Shared business UUID',
                helperText: 'Use the same UUID on both native clients.',
              ),
            ),
            TextField(
              controller: productController,
              decoration: const InputDecoration(labelText: 'Product UUID'),
            ),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Product name'),
            ),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Price (integer)'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : _queueProduct,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save locally'),
                ),
                FilledButton.icon(
                  onPressed: busy ? null : _syncNow,
                  icon: const Icon(Icons.sync),
                  label: const Text('Sync now'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : _initialize,
                  child: const Text('Reconnect'),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('Local products (${products.length})', style: Theme.of(context).textTheme.titleMedium),
            for (final row in products)
              ListTile(
                dense: true,
                title: Text('${row['name']} · ${row['price']}'),
                subtitle: Text('id ${row['id']} · version ${row['version']}'),
              ),
            const SizedBox(height: 16),
            Text('Outbox (${outbox.length})', style: Theme.of(context).textTheme.titleMedium),
            for (final row in outbox)
              ListTile(
                dense: true,
                title: Text('${row['status']} · ${row['operation_id']}'),
                subtitle: Text('${row['last_error'] ?? 'no error'}'),
              ),
          ],
        ),
      );
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
