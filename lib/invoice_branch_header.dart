import 'a4_layout_settings.dart';

/// Presentation only: current branch contacts never overwrite invoice snapshots.
class InvoiceBranchHeader {
  static List<String> resolve(
    Map<String, Object?> sale,
    A4LayoutSettings settings,
    List<Map<String, Object?>> branches, {
    bool includeThird = false,
  }) {
    String text(Object? v) => v?.toString().trim() ?? '';
    String block(Map<String, Object?> b) => [
      text(b['name']),
      text(b['address']),
      text(b['phone']),
    ].where((v) => v.isNotEmpty).join('\n');
    final snapshot = [
      text(sale['branch_name_snapshot']),
      text(sale['branch_address_snapshot']),
      text(sale['branch_phone_snapshot']),
    ].where((v) => v.isNotEmpty).join('\n');
    if (settings.branchMode == 'custom') {
      return [
        settings.leftBranch.trim(),
        settings.rightBranch.trim(),
        if (includeThird) settings.thirdBranch.trim(),
      ].where((v) => v.isNotEmpty).toList();
    }
    if (settings.branchMode == 'snapshot' || branches.isEmpty) {
      return snapshot.isEmpty ? [] : [snapshot];
    }
    Map<String, Object?>? find(Object? id) {
      for (final branch in branches) {
        if (branch['id'] == id) return branch;
      }
      return null;
    }

    var first =
        find(settings.primaryBranchId) ??
        find(sale['branch_id']) ??
        branches.first;
    final requestedSecond = find(settings.secondaryBranchId);
    if (settings.branchMode != 'one' &&
        settings.primaryBranchId == null &&
        requestedSecond != null &&
        requestedSecond['id'] == first['id'] &&
        branches.length > 1) {
      first = branches.firstWhere((b) => b['id'] != requestedSecond['id']);
    }
    final selected = [first];
    if (settings.branchMode != 'one' && branches.length > 1) {
      final second = find(settings.secondaryBranchId);
      selected.add(
        second != null && second['id'] != first['id']
            ? second
            : branches.firstWhere((b) => b['id'] != first['id']),
      );
    }
    if (includeThird && settings.branchMode == 'auto' && selected.length == 2) {
      final selectedIds = selected.map((b) => b['id']).toSet();
      final remaining = branches.where((b) => !selectedIds.contains(b['id']));
      if (remaining.isNotEmpty) selected.add(remaining.first);
    }
    return selected.map(block).where((v) => v.isNotEmpty).toList();
  }
}
