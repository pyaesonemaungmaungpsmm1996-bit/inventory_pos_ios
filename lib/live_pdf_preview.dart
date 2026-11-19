import 'dart:async';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'app_language.dart';
import 'invoice_pdf.dart';

/// Uses the same PDF bytes as printing, rather than a second screen-only layout.
/// Debounces edits and discards late results from superseded document versions.
class LivePdfPreview extends StatefulWidget {
  const LivePdfPreview({
    super.key,
    required this.revision,
    required this.generate,
    this.title = 'Voucher preview',
    this.onClose,
    this.onRefresh,
    this.viewerBuilder,
  });
  final String revision, title;
  final Future<GeneratedInvoicePdf> Function() generate;
  final VoidCallback? onClose, onRefresh;
  final Widget Function(BuildContext, GeneratedInvoicePdf)? viewerBuilder;
  @override
  State<LivePdfPreview> createState() => _LivePdfPreviewState();
}

class _LivePdfPreviewState extends State<LivePdfPreview> {
  Timer? timer;
  int generation = 0;
  GeneratedInvoicePdf? pdf;
  String? error;
  bool loading = true;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    schedule();
  }

  @override
  void didUpdateWidget(LivePdfPreview old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision) schedule();
  }

  void schedule() {
    timer?.cancel();
    final ticket = ++generation;
    final build = widget.generate;
    loading = true;
    pdf = null;
    error = null;
    timer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final result = await build();
        if (!mounted || generation != ticket) return;
        setState(() {
          pdf = result;
          loading = false;
        });
      } catch (_) {
        if (!mounted || generation != ticket) return;
        setState(() {
          error = t(
            'Could not render preview. Check layout and retry.',
            'Preview မပြနိုင်ပါ။ Layout စစ်ပြီး ပြန်စမ်းပါ။',
          );
          loading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    generation++;
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = pdf;
    final theme = Theme.of(context),
        dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const ValueKey('live-voucher-preview'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140C2450),
            blurRadius: 7,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 5, 5, 5),
            color: dark ? const Color(0xFF273D59) : const Color(0xFFE7EFFD),
            child: Row(
              children: [
                Expanded(
                  child: Text(widget.title, style: theme.textTheme.titleSmall),
                ),
                if (widget.onRefresh != null)
                  IconButton(
                    tooltip: t('Reload print layout', 'Print Layout ပြန်ယူရန်'),
                    onPressed: widget.onRefresh,
                    icon: const Icon(Icons.refresh, size: 18),
                  ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: t(
                      'Hide voucher preview',
                      'ဘောင်ချာ Preview ပိတ်ရန်',
                    ),
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(error!),
                          TextButton(
                            onPressed: () => setState(schedule),
                            child: Text(t('Retry', 'ပြန်စမ်းရန်')),
                          ),
                        ],
                      ),
                    ),
                  )
                : widget.viewerBuilder?.call(context, current!) ??
                      PdfPreview(
                        key: ValueKey(generation),
                        build: (_) async => current.bytes,
                        initialPageFormat: current!.format,
                        canChangePageFormat: false,
                        canChangeOrientation: false,
                        canDebug: false,
                        dynamicLayout: false,
                        allowPrinting: false,
                        allowSharing: false,
                        useActions: false,
                        pdfFileName: 'voucher-preview.pdf',
                      ),
          ),
        ],
      ),
    );
  }
}
