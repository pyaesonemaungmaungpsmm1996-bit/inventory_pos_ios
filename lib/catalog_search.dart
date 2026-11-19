/// Shared by desktop suggestions and the barcode/Enter path. Exact matches are
/// ranked first without discarding other matching catalog records.
class CatalogSearch {
  static List<Map<String, Object?>> matches(
    List<Map<String, Object?>> products,
    String input,
  ) {
    final query = input.trim().toLowerCase();
    if (query.isEmpty) return [];
    final words = query.split(RegExp(r'\s+'));
    String text(Map row, String key) => '${row[key] ?? ''}'.toLowerCase();
    int rank(Map row) {
      final values = ['name', 'item_code', 'barcode'].map((k) => text(row, k));
      if (values.any((v) => v == query)) return 0;
      if (values.any((v) => v.startsWith(query))) return 1;
      return 2;
    }

    final result = products.where((row) {
      final combined = [
        'name',
        'item_code',
        'barcode',
      ].map((k) => text(row, k)).join(' ');
      return words.every(combined.contains);
    }).toList();
    result.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r == 0 ? text(a, 'name').compareTo(text(b, 'name')) : r;
    });
    return result;
  }
}
