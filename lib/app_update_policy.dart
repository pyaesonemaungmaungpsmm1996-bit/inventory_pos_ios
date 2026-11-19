class AppUpdatePolicy {
  static const snooze = Duration(hours: 24);
  static const checkInterval = Duration(hours: 6);
  static bool shouldPrompt({
    required int installed,
    required int available,
    required DateTime now,
    int? deferredBuild,
    DateTime? deferredUntil,
  }) =>
      available > installed &&
      !(deferredBuild == available &&
          deferredUntil != null &&
          now.isBefore(deferredUntil));
  static String topic(String package) =>
      'tp_updates_${package.replaceAll(RegExp('[^a-zA-Z0-9_]'), '_')}';
  static Uri storeUri(String package) =>
      Uri.https('play.google.com', '/store/apps/details', {'id': package});
}
