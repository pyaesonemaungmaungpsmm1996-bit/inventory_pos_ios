import 'print_template.dart';
import 'portable_preferences.dart';
import 'a4_layout_settings.dart';

import 'dart:convert';

import 'package:pdf/pdf.dart';

class InvoicePrintSettings {
  const InvoicePrintSettings({
    this.paper = 'receipt80',
    this.language = 'app',
    this.customWidthMm = 80,
    this.customHeightMm = 200,
    this.showPayments = true,
    this.showSalePerson = true,
    this.footer = '',
    this.showLogo = true,
    this.showItemPhotos = false,
    this.showCustomer = true,
    this.showBranch = true,
    this.showDate = true,
    this.showItemCode = true,
    this.showPrices = true,
    this.showDiscount = true,
    this.layout = 'auto',
    this.a4 = const A4LayoutSettings(),
    this.template,
  });
  final A4LayoutSettings a4;
  final PrintTemplate? template;
  final String paper, language, footer, layout;
  final double customWidthMm, customHeightMm;
  final bool showPayments,
      showSalePerson,
      showLogo,
      showItemPhotos,
      showCustomer,
      showBranch,
      showDate,
      showItemCode,
      showPrices,
      showDiscount;
  static const papers = <String, String>{
    'receipt58': '58 mm Receipt',
    'receipt80': '80 mm Receipt',
    'a4': 'A4',
    'a5': 'A5',
    'letter': 'Letter',
    'legal': 'Legal',
    'custom': 'Custom',
  };
  bool get narrow =>
      layout == 'compact' ||
      paper == 'receipt58' ||
      paper == 'receipt80' ||
      (paper == 'custom' && customWidthMm <= 90);
  bool get autoHeight => paper == 'receipt58' || paper == 'receipt80';
  double get marginMm => narrow ? 3 : 10;
  PdfPageFormat get pageFormat {
    switch (paper) {
      case 'a4':
        return PdfPageFormat.a4;
      case 'a5':
        return PdfPageFormat.a5;
      case 'letter':
        return PdfPageFormat.letter;
      case 'legal':
        return PdfPageFormat.legal;
      case 'custom':
        return PdfPageFormat(
          customWidthMm * PdfPageFormat.mm,
          customHeightMm * PdfPageFormat.mm,
        );
      case 'receipt58':
        return PdfPageFormat(58 * PdfPageFormat.mm, 300 * PdfPageFormat.mm);
      default:
        return PdfPageFormat(80 * PdfPageFormat.mm, 300 * PdfPageFormat.mm);
    }
  }

  void validate() {
    a4.validate();
    template?.validate();
    if (layout == 'designer' && template == null) {
      throw const FormatException('Create or select a print template first');
    }
    if (!['auto', 'compact', 'designer'].contains(layout) ||
        !papers.containsKey(paper) ||
        !['app', 'en', 'my'].contains(language) ||
        !customWidthMm.isFinite ||
        !customHeightMm.isFinite ||
        customWidthMm < 58 ||
        customWidthMm > 216 ||
        customHeightMm < 100 ||
        customHeightMm > 1000 ||
        footer.trim().length > 300) {
      throw const FormatException('Invalid invoice print settings');
    }
  }

  Map<String, Object> toJson() => {
    'paper': paper,
    'language': language,
    'width': customWidthMm,
    'height': customHeightMm,
    'payments': showPayments,
    'sale_person': showSalePerson,
    'footer': footer.trim(),
    'logo': showLogo,
    'item_photos': showItemPhotos,
    'customer': showCustomer,
    'branch': showBranch,
    'date': showDate,
    'item_code': showItemCode,
    'prices': showPrices,
    'discount': showDiscount,
    'layout': layout,
    'a4': a4.toJson(),
    if (template != null) 'template': template!.toJson(),
  };
  factory InvoicePrintSettings.fromJson(Map<String, dynamic> data) {
    var savedTemplate = data['template'] is Map
        ? PrintTemplate.fromJson(data['template'] as Map)
        : null;
    // Only replace an untouched generated default. A user's edited template
    // keeps its geometry and receives a bound QR only when none exists.
    if (savedTemplate != null && !savedTemplate.label) {
      final raw = jsonEncode(savedTemplate.toJson());
      if (raw == jsonEncode(PrintTemplate.legacyInvoice().toJson()) ||
          raw == jsonEncode(referenceInvoiceTemplate().toJson())) {
        savedTemplate = PrintTemplate.invoice(previous: savedTemplate);
      }
      if (!savedTemplate.elements.any(
        (e) => e.kind == 'barcode' && e.qr && e.text.contains('{invoice.qr}'),
      )) {
        var qr = PrintTemplate.invoice().elements.singleWhere(
          (e) => e.id == 'voucher-qr',
        );
        if (savedTemplate.elements.any((e) => e.id == qr.id)) {
          qr = qr.withValues({'id': 'restored-voucher-qr'});
        }
        if (savedTemplate.width < 100) {
          qr = qr.withValues({
            'x': savedTemplate.width - 24,
            'y': 3.0,
            'width': 20.0,
            'height': 20.0,
          });
        }
        savedTemplate = savedTemplate.copyWith(
          elements: [...savedTemplate.elements, qr],
        );
      }
    }
    final result = InvoicePrintSettings(
      template: savedTemplate,
      paper: data['paper'] as String,
      language: data['language'] as String,
      customWidthMm: (data['width'] as num).toDouble(),
      customHeightMm: (data['height'] as num).toDouble(),
      showPayments: data['payments'] as bool,
      showSalePerson: data['sale_person'] as bool,
      footer: data['footer'] as String,
      showLogo: data['logo'] as bool? ?? true,
      showItemPhotos: data['item_photos'] as bool? ?? false,
      showCustomer: data['customer'] as bool? ?? true,
      showBranch: data['branch'] as bool? ?? true,
      showDate: data['date'] as bool? ?? true,
      showItemCode: data['item_code'] as bool? ?? true,
      showPrices: data['prices'] as bool? ?? true,
      showDiscount: data['discount'] as bool? ?? true,
      layout: data['layout'] as String? ?? 'auto',
      a4: A4LayoutSettings.fromJson(
        Map<String, dynamic>.from(data['a4'] as Map? ?? const {}),
      ),
    );
    result.validate();
    return result;
  }
  static Future<InvoicePrintSettings> load() async {
    final value = await PortablePreferences.read('invoice_print_settings_v1');
    if (value == null) {
      return const InvoicePrintSettings();
    }
    return InvoicePrintSettings.fromJson(
      jsonDecode(value) as Map<String, dynamic>,
    );
  }

  Future<void> save() async {
    validate();
    await PortablePreferences.write(
      'invoice_print_settings_v1',
      jsonEncode(toJson()),
    );
  }
}
