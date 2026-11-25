class SyncProofProduct {
  const SyncProofProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.version,
  });

  final String id;
  final String name;
  final int price;
  final int version;

  factory SyncProofProduct.fromJson(Map<String, dynamic> json) =>
      SyncProofProduct(
        id: '${json['id']}',
        name: '${json['name']}',
        price: (json['price'] as num).toInt(),
        version: (json['version'] as num).toInt(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'version': version,
      };
}

enum SyncOperationStatus { pending, applied, conflict, failed }

class SyncProofOperation {
  const SyncProofOperation({
    required this.operationId,
    required this.businessId,
    required this.deviceId,
    required this.productId,
    required this.name,
    required this.price,
    required this.expectedVersion,
    required this.status,
    this.lastError,
  });

  final String operationId;
  final String businessId;
  final String deviceId;
  final String productId;
  final String name;
  final int price;
  final int? expectedVersion;
  final SyncOperationStatus status;
  final String? lastError;
}

class SyncProofEvent {
  const SyncProofEvent({
    required this.eventId,
    required this.entityId,
    required this.operationId,
    required this.version,
    required this.payload,
  });

  final int eventId;
  final String entityId;
  final String operationId;
  final int version;
  final Map<String, dynamic> payload;

  factory SyncProofEvent.fromJson(Map<String, dynamic> json) => SyncProofEvent(
        eventId: (json['event_id'] as num).toInt(),
        entityId: '${json['entity_id']}',
        operationId: '${json['operation_id']}',
        version: (json['version'] as num).toInt(),
        payload: Map<String, dynamic>.from(json['payload'] as Map),
      );
}
