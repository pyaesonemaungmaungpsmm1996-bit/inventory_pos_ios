import 'dart:async';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import 'package:flutter/material.dart';

import 'a4_layout_settings.dart';
import 'app_language.dart';
import 'invoice_pdf.dart';
import 'invoice_print_settings.dart';
import 'voucher_pdf_preview.dart';

class StationeryEditor extends StatefulWidget {
  const StationeryEditor({
    super.key,
    required this.initial,
    required this.document,
    required this.onSave,
  });
  final InvoicePrintSettings initial;
  final Map<String, Object?> document;
  final Future<void> Function(A4LayoutSettings) onSave;
  @override
  State<StationeryEditor> createState() => _StationeryEditorState();
}

class _StationeryEditorState extends State<StationeryEditor> {
  late A4LayoutSettings value = widget.initial.a4;
  String selected = A4LayoutSettings.editableHeader.first;
  String? error;
  bool saving = false;
  bool rendering = true;
  Timer? timer;
  int revision = 0;
  GeneratedInvoicePdf? pdf;
  Uint8List? pageImage;
  bool printPreview = false;
  String? dragging;
  Offset drag = Offset.zero;
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  void initState() {
    super.initState();
    render();
  }

  @override
  void dispose() {
    timer?.cancel();
    revision++;
    super.dispose();
  }

  InvoicePrintSettings settings() => InvoicePrintSettings.fromJson({
    ...widget.initial.toJson(),
    'paper': 'a4',
    'layout': 'auto',
    'a4': value.toJson(),
  });
  void changed(A4LayoutSettings next) {
    setState(() {
      value = next;
      error = null;
      rendering = true;
    });
    timer?.cancel();
    revision++;
    timer = Timer(const Duration(milliseconds: 250), render);
  }

  Future<void> render() async {
    final ticket = ++revision;
    try {
      final result = await buildInvoicePdf(
        sale: widget.document,
        settings: settings(),
        myanmar:
            widget.initial.language == 'my' ||
            (widget.initial.language == 'app' &&
                AppLanguage.current.value == 'my'),
      );
      Uint8List? image;
      try {
        final page = await Printing.raster(
          result.bytes,
          pages: [0],
          dpi: 110,
        ).first;
        image = await page.toPng();
      } catch (_) {
        // Position controls remain available without page rasterization.
      }
      if (mounted && ticket == revision) {
        setState(() {
          pdf = result;
          pageImage = image;
          error = null;
          rendering = false;
        });
      }
    } catch (e) {
      if (mounted && ticket == revision) {
        setState(() {
          error = '${t('Preview failed', 'Preview မရပါ')}: $e';
          rendering = false;
        });
      }
    }
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      await widget.onSave(value);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '${t('Could not save', 'သိမ်းမရပါ')}: $e';
        });
      }
    }
  }

  Widget adjustment(String axis, String label, double min, double max) {
    final n = value.placement(selected, axis);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ${axis == 'scale' ? '${(n * 100).round()}%' : '${n.toStringAsFixed(1)} mm'}',
        ),
        Row(
          children: [
            IconButton(
              onPressed: saving
                  ? null
                  : () => changed(
                      value.place(
                        selected,
                        axis,
                        (n - (axis == 'scale' ? .05 : .5)).clamp(min, max),
                      ),
                    ),
              icon: const Icon(Icons.remove),
            ),
            Expanded(
              child: Slider(
                key: ValueKey('stationery-$axis'),
                value: n,
                min: min,
                max: max,
                divisions: axis == 'scale' ? 20 : 80,
                onChanged: saving
                    ? null
                    : (v) => changed(value.place(selected, axis, v)),
              ),
            ),
            IconButton(
              onPressed: saving
                  ? null
                  : () => changed(
                      value.place(
                        selected,
                        axis,
                        (n + (axis == 'scale' ? .05 : .5)).clamp(min, max),
                      ),
                    ),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }

  Widget editablePage(
    GeneratedInvoicePdf result,
    Uint8List image,
  ) => LayoutBuilder(
    builder: (context, box) {
      final pageWidth = box.maxWidth - 24;
      final scale = pageWidth / result.format.width;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: pageWidth,
          height: result.format.height * scale,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.memory(
                  image,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
              ),
              for (final entry in result.headerRegions.entries)
                Positioned.fromRect(
                  rect: Rect.fromLTWH(
                    entry.value.left * scale,
                    entry.value.top * scale,
                    entry.value.width * scale,
                    entry.value.height * scale,
                  ).shift(dragging == entry.key ? drag : Offset.zero),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => selected = entry.key),
                      onPanStart: saving
                          ? null
                          : (_) => setState(() {
                              selected = entry.key;
                              dragging = entry.key;
                              drag = Offset.zero;
                            }),
                      onPanUpdate: saving
                          ? null
                          : (event) => setState(() {
                              drag += event.delta;
                            }),
                      onPanCancel: () => setState(() {
                        dragging = null;
                        drag = Offset.zero;
                      }),
                      onPanEnd: saving
                          ? null
                          : (_) {
                              final delta = drag / (scale * PdfPageFormat.mm);
                              dragging = null;
                              drag = Offset.zero;
                              changed(
                                value
                                    .place(
                                      entry.key,
                                      'x',
                                      (value.placement(entry.key, 'x') +
                                              delta.dx)
                                          .clamp(
                                            -A4LayoutSettings.maxHeaderOffset,
                                            A4LayoutSettings.maxHeaderOffset,
                                          ),
                                    )
                                    .place(
                                      entry.key,
                                      'y',
                                      (value.placement(entry.key, 'y') +
                                              delta.dy)
                                          .clamp(
                                            -A4LayoutSettings.maxHeaderOffset,
                                            A4LayoutSettings.maxHeaderOffset,
                                          ),
                                    ),
                              );
                            },
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selected == entry.key
                                ? Colors.blue.shade800
                                : Colors.blue.withAlpha(140),
                            width: selected == entry.key ? 2 : 1,
                          ),
                        ),
                        child: const Align(
                          alignment: Alignment.topRight,
                          child: Icon(
                            Icons.open_with,
                            color: Colors.blue,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final result = pdf;
    final image = pageImage;
    final controls = ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('A4 Layout', style: Theme.of(context).textTheme.titleLarge),
        for (var i = 0; i < A4LayoutSettings.editableHeader.length; i++)
          ListTile(
            dense: true,
            leading: const Icon(Icons.drag_indicator),
            title: Text(A4LayoutSettings.headerLabels[i]),
            selected: A4LayoutSettings.editableHeader[i] == selected,
            onTap: saving
                ? null
                : () => setState(() {
                    selected = A4LayoutSettings.editableHeader[i];
                    printPreview = false;
                  }),
          ),
        adjustment(
          'x',
          'X offset',
          -A4LayoutSettings.maxHeaderOffset,
          A4LayoutSettings.maxHeaderOffset,
        ),
        adjustment(
          'y',
          'Y offset',
          -A4LayoutSettings.maxHeaderOffset,
          A4LayoutSettings.maxHeaderOffset,
        ),
        adjustment('scale', 'Width / size', .5, 1.5),
        OutlinedButton(
          onPressed: saving
              ? null
              : () => changed(value.resetElement(selected)),
          child: const Text('Reset Position'),
        ),
        FilledButton.icon(
          key: const ValueKey('save-stationery'),
          onPressed: saving ? null : save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save Layout'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
    final preview = Stack(
      fit: StackFit.expand,
      children: [
        if (result == null)
          const Center(child: CircularProgressIndicator())
        else if (!printPreview && image != null)
          editablePage(result, image)
        else
          VoucherPdfPreview(
            bytes: result.bytes,
            format: result.format,
            name: 'a4-invoice-preview.pdf',
          ),
        if (rendering)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(),
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('A4 Invoice Header Editor')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Editor'),
                  icon: Icon(Icons.edit_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Print Preview'),
                  icon: Icon(Icons.print_outlined),
                ),
              ],
              selected: {printPreview},
              onSelectionChanged: (selection) =>
                  setState(() => printPreview = selection.single),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => box.maxWidth >= 850
                  ? Row(
                      children: [
                        Expanded(child: preview),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 310, child: controls),
                      ],
                    )
                  : Column(
                      children: [
                        Expanded(child: preview),
                        const Divider(height: 1),
                        SizedBox(height: box.maxHeight * .48, child: controls),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
