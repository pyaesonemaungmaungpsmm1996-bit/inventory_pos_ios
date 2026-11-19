/// Device-local print presentation. Never changes invoice numbers or amounts.
class A4LayoutSettings {
  const A4LayoutSettings({
    this.branchMode = 'auto',
    this.primaryBranchId,
    this.secondaryBranchId,
    this.heading = '',
    this.subtitle = '',
    this.leftBranch = '',
    this.rightBranch = '',
    this.thirdBranch = '',
    this.leftBranchAlign = 'center',
    this.rightBranchAlign = 'center',
    this.remarkLabel = 'Remark',
    this.customerSignature = "Customer's Signature",
    this.cashierSignature = 'Cashier Signature',
    this.authorizedSignature = 'Authorized Signature',
    this.logoWidthMm = 48,
    this.headingSize = 25,
    this.subtitleSize = 17,
    this.infoSize = 9,
    this.tableSize = 8.2,
    this.labelWidth = 64,
    this.remarkHeightMm = 24,
    this.totalsPercent = 42,
    this.stationery = const {},
  });
  final String branchMode;
  final String leftBranchAlign, rightBranchAlign;
  final int? primaryBranchId, secondaryBranchId;
  final String heading,
      subtitle,
      leftBranch,
      rightBranch,
      thirdBranch,
      remarkLabel;
  final String customerSignature, cashierSignature, authorizedSignature;
  final double logoWidthMm, headingSize, subtitleSize, infoSize, tableSize;
  final double labelWidth, remarkHeightMm, totalsPercent;
  final Map<String, double> stationery;
  static const headerElements = [
    ...editableHeader,
    'logo',
    'heading',
    'subtitle',
    'branch-left',
    'branch-right',

    'branch-divider',
    'invoice-title',
    'invoice-date',
    'customer-block',
    'invoice-info',
    'voucher-qr',
  ];
  static const movable = [
    ...headerElements,
    'signature-left',
    'signature-middle',
    'signature-right',
    'footer',
    'print-date',
    'page-number',
  ];
  static const editableHeader = [
    'a4-logo',
    'a4-heading',
    'a4-address-1',
    'a4-address-2',
    'a4-address-3',
  ];
  static const maxHeaderOffset = 190.0;
  static const headerLabels = [
    'Logo',
    'Shop Name / Second Header',
    'Address 1',
    'Address 2',
    'Address 3',
  ];

  A4LayoutSettings resetElement(String id) => withValues({
    'stationery': {
      for (final entry in stationery.entries)
        if (!entry.key.startsWith('$id.')) entry.key: entry.value,
    },
  });

  double placement(String element, String axis) =>
      stationery['$element.$axis'] ?? (axis == 'scale' ? 1 : 0);
  A4LayoutSettings place(String element, String axis, double value) =>
      withValues({
        'stationery': {...stationery, '$element.$axis': value},
      });
  A4LayoutSettings resetStationery(bool header) => withValues({
    'stationery': {
      for (final e in stationery.entries)
        if (headerElements.contains(e.key.split('.').first) != header)
          e.key: e.value,
    },
  });
  Map<String, Object> toJson() => {
    'branchMode': branchMode,
    'primaryBranchId': ?primaryBranchId,
    'secondaryBranchId': ?secondaryBranchId,
    'heading': heading,
    'subtitle': subtitle,
    'leftBranch': leftBranch,
    'rightBranch': rightBranch,
    'thirdBranch': thirdBranch,
    'leftBranchAlign': leftBranchAlign,
    'rightBranchAlign': rightBranchAlign,
    'remarkLabel': remarkLabel,
    'customerSignature': customerSignature,
    'cashierSignature': cashierSignature,
    'authorizedSignature': authorizedSignature,
    'logoWidthMm': logoWidthMm,
    'headingSize': headingSize,
    'subtitleSize': subtitleSize,
    'infoSize': infoSize,
    'tableSize': tableSize,
    'labelWidth': labelWidth,
    'remarkHeightMm': remarkHeightMm,
    'totalsPercent': totalsPercent,
    'stationery': stationery,
  };
  factory A4LayoutSettings.fromJson(Map<String, dynamic> json) {
    const defaults = A4LayoutSettings();
    final d = defaults.toJson();
    String s(String k) => (json[k] ?? d[k]) as String;
    double n(String k) => ((json[k] ?? d[k]) as num).toDouble();
    int? branchId(String key) {
      final v = json[key];
      if (v == null || v == 0) return null;
      if (v is! int) throw const FormatException('Invalid branch selection');
      return v;
    }

    final result = A4LayoutSettings(
      branchMode:
          json['branchMode'] as String? ??
          ((s('leftBranch').trim().isNotEmpty ||
                  s('rightBranch').trim().isNotEmpty)
              ? 'custom'
              : 'auto'),
      primaryBranchId: branchId('primaryBranchId'),
      secondaryBranchId: branchId('secondaryBranchId'),
      heading: s('heading'),
      subtitle: s('subtitle'),
      leftBranch: s('leftBranch'),
      rightBranch: s('rightBranch'),
      thirdBranch: s('thirdBranch'),
      leftBranchAlign: s('leftBranchAlign'),
      rightBranchAlign: s('rightBranchAlign'),
      remarkLabel: s('remarkLabel'),
      customerSignature: s('customerSignature'),
      cashierSignature: s('cashierSignature'),
      authorizedSignature: s('authorizedSignature'),
      logoWidthMm: n('logoWidthMm'),
      headingSize: n('headingSize'),
      subtitleSize: n('subtitleSize'),
      infoSize: n('infoSize'),
      tableSize: n('tableSize'),
      labelWidth: n('labelWidth'),
      remarkHeightMm: n('remarkHeightMm'),
      totalsPercent: n('totalsPercent'),
      stationery: Map<String, double>.unmodifiable({
        for (final e in (json['stationery'] as Map? ?? {}).entries)
          e.key as String: (e.value as num).toDouble(),
      }),
    );
    result.validate();
    return result;
  }
  A4LayoutSettings withValues(Map<String, Object> values) =>
      A4LayoutSettings.fromJson({...toJson(), ...values});
  void validate() {
    if (![
      leftBranchAlign,
      rightBranchAlign,
    ].every(['left', 'center', 'right'].contains)) {
      throw const FormatException('Invalid branch paragraph alignment');
    }
    for (final e in stationery.entries) {
      final parts = e.key.split('.');
      if (parts.length != 2 ||
          !movable.contains(parts.first) ||
          !['x', 'y', 'scale'].contains(parts.last) ||
          !e.value.isFinite ||
          (parts.last == 'scale'
              ? e.value < .5 || e.value > 1.5
              : e.value.abs() >
                    (editableHeader.contains(parts.first)
                        ? maxHeaderOffset
                        : 20))) {
        throw const FormatException('Invalid header/footer placement');
      }
    }
    bool range(double v, double min, double max) =>
        v.isFinite && v >= min && v <= max;
    if (!['auto', 'one', 'two', 'custom', 'snapshot'].contains(branchMode) ||
        (primaryBranchId != null && primaryBranchId! < 1) ||
        (secondaryBranchId != null && secondaryBranchId! < 1) ||
        (primaryBranchId != null && primaryBranchId == secondaryBranchId) ||
        heading.length > 100 ||
        subtitle.length > 120 ||
        leftBranch.length > 450 ||
        rightBranch.length > 450 ||
        thirdBranch.length > 450 ||
        [
          remarkLabel,
          customerSignature,
          cashierSignature,
          authorizedSignature,
        ].any((s) => s.length > 60) ||
        !range(logoWidthMm, 25, 55) ||
        !range(headingSize, 16, 30) ||
        !range(subtitleSize, 10, 20) ||
        !range(infoSize, 8, 11) ||
        !range(tableSize, 7, 10) ||
        !range(labelWidth, 48, 80) ||
        !range(remarkHeightMm, 18, 40) ||
        !range(totalsPercent, 28, 42)) {
      throw const FormatException('Invalid A4 layout settings');
    }
  }
}
