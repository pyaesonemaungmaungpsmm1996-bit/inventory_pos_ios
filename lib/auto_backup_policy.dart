class AutoBackupPolicy {
  static bool validMinutes(Object? value) =>
      value is int && value >= 15 && value <= 43200;
  static bool dirty(int current, Object? uploaded) =>
      current != (uploaded is int ? uploaded : -1);
  static bool catchUp({
    required bool online,
    required bool? previouslyOnline,
    required bool dirty,
  }) => online && previouslyOnline != true && dirty;
}
