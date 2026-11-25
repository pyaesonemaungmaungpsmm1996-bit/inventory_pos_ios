import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class SyncProofRemoteRepository {
  SyncProofRemoteRepository(this.client);

  final SupabaseClient client;

  Future<Map<String, dynamic>> upsertProduct(
    SyncProofOperation operation,
  ) async {
    final result = await client.rpc(
      'sync_proof_upsert_product',
      params: {
        'p_operation_id': operation.operationId,
        'p_business_id': operation.businessId,
        'p_device_id': operation.deviceId,
        'p_product_id': operation.productId,
        'p_name': operation.name,
        'p_price': operation.price,
        'p_expected_version': operation.expectedVersion,
      },
    );
    return Map<String, dynamic>.from(result as Map);
  }

  Future<List<SyncProofEvent>> pullEvents({
    required String businessId,
    required int afterEventId,
  }) async {
    final result = await client.rpc(
      'sync_proof_pull_events',
      params: {
        'p_business_id': businessId,
        'p_after_event_id': afterEventId,
        'p_limit': 100,
      },
    );
    return (result as List)
        .map((row) => SyncProofEvent.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  RealtimeChannel watchEvents({
    required String businessId,
    required void Function() onSignal,
  }) {
    return client
        .channel('sync-proof-events-$businessId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'sync_proof_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'business_id',
            value: businessId,
          ),
          callback: (_) => onSignal(),
        )
        .subscribe();
  }
}
