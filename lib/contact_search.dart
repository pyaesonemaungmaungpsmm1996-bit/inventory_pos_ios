class ContactSearch {
  static String code(Object? id, {String kind = 'customer'}) =>
      (kind == 'supplier' ? 'SUP-' : 'CUS-') +
      (id?.toString() ?? '').padLeft(6, '0');
  static String digits(String text) {
    for (var i = 0; i < 10; i++) {
      text = text.replaceAll(String.fromCharCode(0x1040 + i), i.toString());
    }
    return text.replaceAll(RegExp(r'[^0-9]'), '');
  }

  static String phone(String text) {
    var n = digits(text);
    if (n.startsWith('0095')) n = n.substring(2);
    if (n.startsWith('95')) n = '0${n.substring(2)}';
    return n;
  }

  static bool matches(Map row, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if ([
      row['name'],
      row['company'],
      row['address'],
      code(row['id'], kind: row['kind']?.toString() ?? 'customer'),
      '#${row['id']}',
    ].any((v) => v.toString().toLowerCase().contains(q))) {
      return true;
    }
    final n = phone(query);
    return n.isNotEmpty && phone(row['phone']?.toString() ?? '').contains(n);
  }
}
