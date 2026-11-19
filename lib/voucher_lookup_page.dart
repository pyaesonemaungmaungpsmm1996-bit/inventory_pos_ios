import 'desktop_ui.dart';
import 'app_capabilities.dart';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:printing/printing.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'invoice_pdf.dart';
import 'invoice_print_settings.dart';
import 'invoice_printer_page.dart'
    show purchasePrintSnapshot, expensePrintSnapshot;
import 'sale_return_print_snapshot.dart';
import 'voucher_code.dart';
import 'voucher_resolver.dart';

/// Read-only lookup; it never posts, confirms, edits, or pays a voucher.
class VoucherLookupPage extends StatefulWidget {
  const VoucherLookupPage({super.key});
  @override
  State<VoucherLookupPage> createState() => _VoucherLookupPageState();
}

class _VoucherLookupPageState extends State<VoucherLookupPage> {
  final input = TextEditingController();
  final camera = AppCapabilities.camera
      ? MobileScannerController(autoStart: false)
      : null;
  bool cameraReady = false, busy = false;
  String? error;
  String? lastDetected;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void dispose() {
    camera?.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> scan() async {
    if (!AppCapabilities.camera) return;
    if (busy) return;
    if (cameraReady) {
      setState(() => lastDetected = null);
      return;
    }
    setState(() {
      cameraReady = true;
      error = null;
      lastDetected = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await camera?.start();
      } catch (_) {
        if (mounted) {
          setState(() {
            cameraReady = false;
            error = t(
              'Camera unavailable. Enter the QR text below.',
              'ကင်မရာ အသုံးမပြုနိုင်ပါ။ QR စာသားကို အောက်တွင်ထည့်ပါ။',
            );
          });
        }
      }
    });
  }

  Future<void> open(String value) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final ref = VoucherCode.parse(value);
      if (cameraReady) {
        try {
          await camera?.stop();
        } catch (_) {
          /* Manual lookup remains usable. */
        }
      }
      if (!mounted) return;
      setState(() => cameraReady = false);
      final db = AppDatabase.instance;
      final snapshot = await VoucherResolver.resolve(
        value,
        (kind, id) async => switch (kind) {
          'INV' => await db.getConfirmedSale(id),
          'PUR' => await purchasePrintSnapshot(id),
          'EXP' => await expensePrintSnapshot(id),
          _ => saleReturnPrintSnapshot(await db.getSaleReturn(id)),
        },
      );
      final saved = await InvoicePrintSettings.load();
      final settings = saved.autoHeight
          ? saved
          : InvoicePrintSettings.fromJson({
              ...saved.toJson(),
              'paper': 'a4',
              'layout': 'auto',
            });
      final pdf = await buildInvoicePdf(
        sale: snapshot,
        settings: settings,
        myanmar:
            settings.language == 'my' ||
            settings.language == 'app' && AppLanguage.current.value == 'my',
      );
      if (!mounted) return;
      final number = '${ref.kind}-${ref.id.toString().padLeft(6, '0')}';
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => DesktopScaffold(
            appBar: AppBar(
              title: Text(
                '$number - ${t('Stored voucher', 'သိမ်းထားသောဘောင်ချာ')}',
              ),
            ),
            body: PdfPreview(
              build: (_) async => pdf.bytes,
              initialPageFormat: pdf.format,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              dynamicLayout: false,
              pdfFileName: '$number.pdf',
            ),
          ),
        ),
      );
    } on FormatException catch (e) {
      if (mounted) {
        setState(
          () => error = t(
            e.message,
            'QR နှင့် သိမ်းထားသောဘောင်ချာ မကိုက်ညီပါ။ မှန်ကန်သော ဘောင်ချာ QR ကို ပြန်စစ်ပါ။',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = t(
            'Voucher could not be opened. It must exist in this device\'s business data. Check your data and retry.',
            'ဘောင်ချာကို မဖွင့်နိုင်ပါ။ ဤစက်၏ ဆိုင်ဒေတာထဲတွင် ဘောင်ချာရှိရပါမည်။ ဒေတာကို စစ်ပြီး ပြန်ကြိုးစားပါ။',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void detect(BarcodeCapture capture) {
    if (busy) return;
    final codes = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .toSet();
    if (codes.length == 1) {
      if (lastDetected == codes.single) return;
      lastDetected = codes.single;
      open(codes.single);
    } else if (codes.length > 1) {
      setState(
        () => error = t(
          'Show one voucher QR at a time.',
          'ဘောင်ချာ QR တစ်ခုတည်းကို ပြပါ။',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(title: Text(t('Scan Voucher', 'ဘောင်ချာ QR စစ်ရန်'))),
    body: DesktopListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          t(
            'Scan the printed QR to reopen the matching saved voucher. This works with records already on this device; it does not publish customer data.',
            'Print ထုတ်ထားသော QR ကို scan လုပ်ပြီး မူရင်းဘောင်ချာကို ပြန်ဖွင့်ပါ။ ဤစက်တွင် သိမ်းထားသော ဘောင်ချာဒေတာကို အသုံးပြုပါမည်။',
          ),
        ),
        const SizedBox(height: 16),
        if (cameraReady)
          SizedBox(
            height: 280,
            child: ClipRect(
              child: MobileScanner(
                controller: camera,
                onDetect: detect,
                errorBuilder: (context, error) => Center(
                  child: Text(
                    t(
                      'Camera unavailable. Allow camera permission or use manual entry.',
                      'ကင်မရာ ဖွင့်မရပါ။ Camera permission ပေးပါ သို့မဟုတ် စာသားထည့်ပါ။',
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (AppCapabilities.camera)
          OutlinedButton.icon(
            onPressed: busy ? null : scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(t('Start camera', 'ကင်မရာဖွင့်ရန်')),
          ),
        TextField(
          controller: input,
          autofocus: !AppCapabilities.camera,
          enabled: !busy,
          maxLength: 110,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: open,
          decoration: InputDecoration(
            labelText: t(
              'QR text / keyboard scanner',
              'QR စာသား / Keyboard scanner',
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        FilledButton.icon(
          onPressed: busy ? null : () => open(input.text),
          icon: const Icon(Icons.receipt_long),
          label: Text(t('Open voucher', 'ဘောင်ချာဖွင့်ရန်')),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}
