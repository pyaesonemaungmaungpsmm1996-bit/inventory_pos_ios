import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'business_logo_page.dart';
import 'invoice_pdf.dart';
import 'invoice_print_settings.dart';
import 'live_pdf_preview.dart';

class SaleVoucherPreview extends StatefulWidget {
  const SaleVoucherPreview({
    super.key,
    required this.sale,
    required this.onClose,
  });
  final Map<String, Object?> sale;
  final VoidCallback onClose;
  @override
  State<SaleVoucherPreview> createState() => _SaleVoucherPreviewState();
}

class _SaleVoucherPreviewState extends State<SaleVoucherPreview> {
  InvoicePrintSettings? settings;
  Map<String, Object?> business = {};
  List<Map<String, Object?>> branches = [];
  Uint8List? logo;
  String? error;
  int request = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final ticket = ++request;
    setState(() {
      settings = null;
      error = null;
    });
    try {
      final saved = await InvoicePrintSettings.load();
      final profile = await AppDatabase.instance.getBusinessProfile();
      final rows = await AppDatabase.instance.getBranches();
      final image = await BusinessLogoStore.read();
      if (!mounted || ticket != request) return;
      setState(() {
        settings = saved;
        business = profile;
        branches = rows;
        logo = image;
      });
    } catch (_) {
      if (mounted && ticket == request) {
        setState(() => error = 'Could not load print layout');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final my = AppLanguage.current.value == 'my';
    if (error != null) {
      return Center(
        child: TextButton(
          onPressed: load,
          child: Text(my ? 'Print Layout ပြန်ယူရန်' : 'Retry print layout'),
        ),
      );
    }
    if (settings == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final sale = <String, Object?>{
      ...widget.sale,
      'business_name': business['name'],
      'currency_code': business['currency_code'] ?? 'MMK',
      'currency_digits': business['currency_digits'] ?? 0,
    };
    final saved = settings!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          color: const Color(0xFFFFEDB7),
          child: Text(
            my ? 'DRAFT · အတည်မပြုရသေးပါ' : 'DRAFT · Not confirmed',
            style: const TextStyle(
              color: Color(0xFF754600),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: LivePdfPreview(
            title: my ? 'ဘောင်ချာ Preview' : 'Voucher preview',
            revision: jsonEncode([sale, saved.toJson(), my, request]),
            onClose: widget.onClose,
            onRefresh: load,
            generate: () => buildInvoicePdf(
              sale: sale,
              settings: saved,
              myanmar:
                  saved.language == 'my' || (saved.language == 'app' && my),
              loadLogo: () async => logo,
              loadBranches: () async => branches,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(7),
          child: Text(
            my
                ? 'Confirm Sale ပြီးမှ Print ထုတ်နိုင်သည်။'
                : 'Printing is available after Confirm Sale.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
