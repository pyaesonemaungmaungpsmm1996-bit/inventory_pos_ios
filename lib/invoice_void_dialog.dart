import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_database.dart';

Future<String?> askInvoiceVoidReason(BuildContext context, String title) async {
  String reason = '';
  final form = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (dialog) => DesktopDialog(
      title: Text(title),
      content: Form(
        key: form,
        child: TextFormField(
          autofocus: true,
          maxLength: 300,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: AppLanguage.current.value == 'my'
                ? 'ပယ်ဖျက်ရသည့်အကြောင်းရင်း'
                : 'Reason for void',
          ),
          onChanged: (value) => reason = value,
          validator: (value) => (value ?? '').trim().isEmpty
              ? (AppLanguage.current.value == 'my'
                    ? 'အကြောင်းရင်းရေးပါ'
                    : 'Enter a reason')
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: Text(
            AppLanguage.current.value == 'my' ? 'မလုပ်တော့ပါ' : 'Cancel',
          ),
        ),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) {
              Navigator.pop(dialog, reason.trim());
            }
          },
          child: Text(
            AppLanguage.current.value == 'my' ? 'VOID လုပ်မည်' : 'Void invoice',
          ),
        ),
      ],
    ),
  );
}

Future<bool> confirmPermanentVoucherDelete(
  BuildContext context,
  String number,
) async {
  String typed = '';
  final isMyanmar = AppLanguage.current.value == 'my';
  return await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, refresh) => DesktopDialog(
            title: Text(
              isMyanmar
                  ? 'ဘောင်ချာ အပြီးတိုင်ဖျက်မည်'
                  : 'Permanently delete voucher',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMyanmar
                      ? '$number ကိုဖျက်ပြီး Stock/ငွေစာရင်း ပြန်ညှိမည်။ မှတ်တမ်းသိမ်းထားမည်။ ချိတ်ထားသော Payment/Return နှင့် သုံးပြီး Stock ရှိလျှင် အရင်ရှင်းရန် လိုနိုင်သည်။'
                      : 'Delete $number and reverse its stock/money effects. An audit archive is kept. Related payments/returns or stock already used may need resolving first.',
                ),
                const SizedBox(height: 12),
                TextField(
                  autofocus: true,
                  onChanged: (value) => refresh(() => typed = value.trim()),
                  decoration: InputDecoration(
                    labelText: isMyanmar
                        ? 'အတည်ပြုရန် $number ရိုက်ပါ'
                        : 'Type $number to confirm',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text(isMyanmar ? 'မလုပ်တော့' : 'Cancel'),
              ),
              FilledButton(
                onPressed: typed == number
                    ? () => Navigator.pop(dialog, true)
                    : null,
                child: Text(isMyanmar ? 'အပြီးတိုင်ဖျက်မည်' : 'Delete forever'),
              ),
            ],
          ),
        ),
      ) ??
      false;
}

Future<bool> deleteVoucherWithPrompt(
  BuildContext context, {
  required String kind,
  required int id,
  required String number,
}) async {
  final approved = await confirmPermanentVoucherDelete(context, number);
  if (!approved || !context.mounted) return false;
  try {
    await AppDatabase.instance.deleteVoucher(kind: kind, id: id);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
    return false;
  }
}
