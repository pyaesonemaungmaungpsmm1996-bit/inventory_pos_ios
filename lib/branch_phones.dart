class BranchPhones {
  static List<String> parse(String value) {
    final seen = <String>{};
    return value
        .split(RegExp(r'[\n,;]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .where(
          (s) => seen.add(s.replaceAll(RegExp(r'[\s()-]'), '').toLowerCase()),
        )
        .toList();
  }

  static String normalize(String value) => parse(value).join('\n');
}
