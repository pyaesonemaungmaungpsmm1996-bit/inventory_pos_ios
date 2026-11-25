import 'dart:async';

import 'local_store.dart';
import 'models.dart';
import 'remote_repository.dart';

class SyncProofEngine {
  SyncProofEngine({required this.local, required this.remote});

  final SyncProofLocalStore local;
  final SyncProofRemoteRepository remote;
  bool _running = false;
  RealtimeChannelHandle? _subscription;

  Future<void> syncOnce({required String businessId}) async {
    if (_running) return;
    _running = true;
    try {
      for (final operation in await local.pendingOperations()) {
        try {
          final result = await remote.upsertProduct(operation);
          switch (result['status']) {
            case 'applied':
              await local.markApplied(
                operation.operationId,
                SyncProofProduct.fromJson(
                  Map<String, dynamic>.from(result['product'] as Map),
                ),
              );
            case 'conflict':
              await local.markConflict(
                operation.operationId,
                '${result['server']}',
              );
            default:
              throw StateError('Unexpected sync result: $result');
          }
        } catch (error) {
          await local.db.update(
            'sync_proof_outbox',
            {'status': 'failed', 'last_error': '$error'},
            where: 'operation_id = ?',
            whereArgs: [operation.operationId],
          );
        }
      }
      await pullAll(businessId: businessId);
    } finally {
      _running = false;
    }
  }

  Future<void> pullAll({required String businessId}) async {
    while (true) {
      final events = await remote.pullEvents(
        businessId: businessId,
        afterEventId: await local.cursor(businessId),
      );
      if (events.isEmpty) return;
      await local.applyEvents(businessId, events);
      if (events.length < 100) return;
    }
  }

  Future<void> start({required String businessId}) async {
    await syncOnce(businessId: businessId);
    final channel = remote.watchEvents(
      businessId: businessId,
      onSignal: () => unawaited(syncOnce(businessId: businessId)),
    );
    _subscription = RealtimeChannelHandle(channel);
  }

  Future<void> dispose() async {
    await _subscription?.dispose();
    _subscription = null;
  }
}

class RealtimeChannelHandle {
  RealtimeChannelHandle(this.channel);
  final dynamic channel;
  Future<void> dispose() async {
    await channel.unsubscribe();
  }
}
