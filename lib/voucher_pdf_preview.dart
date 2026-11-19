import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class VoucherPdfPreview extends StatefulWidget {
  const VoucherPdfPreview({
    super.key,
    required this.bytes,
    required this.format,
    required this.name,
  });
  final Uint8List bytes;
  final PdfPageFormat format;
  final String name;
  @override
  State<VoucherPdfPreview> createState() => _VoucherPdfPreviewState();
}

class _VoucherPdfPreviewState extends State<VoucherPdfPreview> {
  bool fitWidth = false;
  double zoom = 1;
  bool busy = false;
  Future<void> output(bool print) async {
    setState(() => busy = true);
    try {
      if (print) {
        await Printing.layoutPdf(
          onLayout: (_) async => widget.bytes,
          name: widget.name,
          format: widget.format,
          dynamicLayout: false,
        );
      } else {
        await Printing.sharePdf(bytes: widget.bytes, filename: widget.name);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('PDF output failed: $e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Material(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                key: const ValueKey('voucher-print'),
                onPressed: busy ? null : () => output(true),
                icon: const Icon(Icons.print),
                label: const Text('Print'),
              ),
              TextButton.icon(
                key: const ValueKey('voucher-save-pdf'),
                onPressed: busy ? null : () => output(false),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Save / Share PDF'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  fitWidth = false;
                  zoom = 1;
                }),
                child: const Text('Fit Page'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  fitWidth = true;
                  zoom = 1;
                }),
                child: const Text('Fit Width'),
              ),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: () =>
                    setState(() => zoom = (zoom / 1.2).clamp(.25, 4)),
                icon: const Icon(Icons.zoom_out),
              ),
              Text('${(zoom * 100).round()}%'),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: () =>
                    setState(() => zoom = (zoom * 1.2).clamp(.25, 4)),
                icon: const Icon(Icons.zoom_in),
              ),
            ],
          ),
        ),
      ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, box) {
            final fitted = math.min(
              box.maxWidth - 32,
              (box.maxHeight - 90) * widget.format.width / widget.format.height,
            );
            final width = (fitWidth ? box.maxWidth - 32 : fitted) * zoom;
            return PdfPreview(
              build: (_) async => widget.bytes,
              initialPageFormat: widget.format,
              maxPageWidth: math.max(100, width),
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              useActions: false,
              dynamicLayout: false,
              pdfFileName: widget.name,
            );
          },
        ),
      ),
    ],
  );
}
