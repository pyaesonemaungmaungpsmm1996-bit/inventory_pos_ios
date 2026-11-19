import 'desktop_ui.dart';
import 'amount_input.dart';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'subscription_billing_service.dart';

String bt(String en, String my) => AppLanguage.current.value == 'my' ? my : en;

class BillingField {
  const BillingField(
    this.keyName,
    this.label, {
    this.initial = '',
    this.options,
    this.number = false,
    this.date = false,
  });
  final String keyName, label, initial;
  final Map<String, String>? options;
  final bool number, date;
}

class BillingFormPage extends StatefulWidget {
  const BillingFormPage({
    super.key,
    required this.title,
    required this.fields,
    this.image = false,
    this.notice = '',
  });
  final String title, notice;
  final List<BillingField> fields;
  final bool image;
  @override
  State<BillingFormPage> createState() => _BillingFormPageState();
}

class _BillingFormPageState extends State<BillingFormPage> {
  final controllers = <String, TextEditingController>{};
  BillingImage? image;
  String? error;
  bool picking = false;
  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      controllers[field.keyName] = TextEditingController(
        text: field.date
            ? (DateTime.tryParse(field.initial)
                      ?.toLocal()
                      .toString()
                      .split('.')
                      .first ??
                  '')
            : field.initial,
      );
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> choose() async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final selected = await BillingService.choose();
      if (mounted && selected != null) {
        setState(() => image = selected);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = BillingService.friendly(e));
      }
    } finally {
      if (mounted) {
        setState(() => picking = false);
      }
    }
  }

  Future<void> date(BillingField f) async {
    final initial =
        DateTime.tryParse(controllers[f.keyName]!.text)?.toLocal() ??
        DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 2)),
      lastDate: DateTime.now(),
    );
    if (day == null || !mounted) {
      return;
    }
    final clock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (clock == null || !mounted) {
      return;
    }
    setState(
      () => controllers[f.keyName]!.text = DateTime(
        day.year,
        day.month,
        day.day,
        clock.hour,
        clock.minute,
      ).toString().split('.').first,
    );
  }

  void done() {
    if (widget.image && image == null) {
      setState(
        () => error = bt(
          'Choose the document image first.',
          'စာရွက်စာတမ်းပုံကို အရင်ရွေးပါ။',
        ),
      );
      return;
    }
    final result = <String, dynamic>{
      for (final e in controllers.entries) e.key: e.value.text.trim(),
      'image': image,
    };
    for (final f in widget.fields.where((f) => f.number)) {
      result[f.keyName] = (result[f.keyName] as String).replaceAll(',', '');
    }
    for (final field in widget.fields.where((f) => f.date)) {
      final date = DateTime.tryParse(controllers[field.keyName]!.text);
      if (date == null) {
        setState(
          () => error = bt('Choose a date and time.', 'နေ့နှင့်အချိန် ရွေးပါ။'),
        );
        return;
      }
      result[field.keyName] = date.toUtc().toIso8601String();
    }
    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !picking,
    child: DesktopScaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.notice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(widget.notice),
            ),
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: f.options == null
                  ? TextField(
                      controller: controllers[f.keyName],
                      readOnly: f.date,
                      onTap: f.date ? () => date(f) : null,
                      inputFormatters: f.number
                          ? const [AmountInputFormatter()]
                          : null,
                      keyboardType: f.number
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: f.label,
                        border: const OutlineInputBorder(),
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      initialValue: controllers[f.keyName]!.text.isEmpty
                          ? null
                          : controllers[f.keyName]!.text,
                      items: f.options!.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(
                                e.value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => controllers[f.keyName]!.text = v ?? '',
                      decoration: InputDecoration(
                        labelText: f.label,
                        border: const OutlineInputBorder(),
                      ),
                    ),
            ),
          if (widget.image) ...[
            OutlinedButton.icon(
              onPressed: picking ? null : choose,
              icon: const Icon(Icons.image_outlined),
              label: Text(
                bt(
                  'Choose JPG / PNG · max 8 MB',
                  'JPG / PNG ပုံရွေးရန် · အများဆုံး 8 MB',
                ),
              ),
            ),
            if (image != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Image.memory(
                  image!.bytes,
                  height: 200,
                  cacheWidth: 1000,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Text(
                    bt(
                      'Image preview unavailable. Choose a valid JPG / PNG.',
                      'ပုံဖော်ပြမရပါ။ JPG / PNG ပုံမှန်ကို ရွေးပါ။',
                    ),
                  ),
                ),
              ),
          ],
          if (picking) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: picking ? null : done,
            child: Text(bt('Continue', 'ဆက်လုပ်မည်')),
          ),
        ],
      ),
    ),
  );
}

Future<Map<String, dynamic>?> billingForm(
  BuildContext context,
  String title,
  List<BillingField> fields, {
  bool image = false,
  String notice = '',
}) => Navigator.of(context).push<Map<String, dynamic>>(
  MaterialPageRoute(
    builder: (_) => BillingFormPage(
      title: title,
      fields: fields,
      image: image,
      notice: notice,
    ),
  ),
);
Future<bool> billingConfirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => DesktopDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(bt('Cancel', 'မလုပ်တော့ပါ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(bt('Confirm', 'အတည်ပြုမည်')),
          ),
        ],
      ),
    ) ==
    true;
Future<void> billingView(
  BuildContext context,
  String document,
  String owner,
) async {
  final bytes = await BillingService.download(document, owner);
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: InteractiveViewer(
              child: Image.memory(
                bytes,
                cacheWidth: 1400,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Text(
                  bt('Cannot preview this image.', 'ဤပုံကို ဖော်ပြမရပါ။'),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(bt('Close', 'ပိတ်မည်')),
          ),
        ],
      ),
    ),
  );
}

String billingTime(dynamic value) =>
    DateTime.tryParse('$value')?.toLocal().toString().split('.').first ?? '—';
String billingState(dynamic value) {
  final en = '$value';
  if (AppLanguage.current.value != 'my') {
    return en.toUpperCase();
  }
  return const {
        'draft': 'ငွေမချေရသေး',
        'pending': 'စစ်ဆေးရန် စောင့်နေသည်',
        'approved': 'အတည်ပြုပြီး',
        'rejected': 'ပယ်ချပြီး',
        'cancelled': 'ပယ်ဖျက်ပြီး',
      }[en] ??
      en;
}
