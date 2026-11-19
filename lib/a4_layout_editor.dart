import 'desktop_ui.dart';
import 'invoice_branch_picker.dart';

import 'package:flutter/material.dart';

import 'a4_layout_settings.dart';
import 'app_language.dart';

class A4LayoutEditor extends StatelessWidget {
  const A4LayoutEditor({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onReset,
    this.enabled = true,
    this.receipt = false,
  });
  final A4LayoutSettings value;
  final ValueChanged<A4LayoutSettings> onChanged;
  final VoidCallback onReset;
  final bool enabled;
  final bool receipt;
  @override
  Widget build(BuildContext context) {
    String t(String en, String my) =>
        AppLanguage.current.value == 'my' ? my : en;
    void change(String key, Object v) => onChanged(value.withValues({key: v}));
    Widget field(String key, String label, int length, {int lines = 1}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            initialValue: value.toJson()[key] as String,
            enabled: enabled,
            maxLength: length,
            minLines: lines,
            maxLines: lines + 2,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) {
              if (v.length <= length) change(key, v);
            },
            validator: (v) => (v?.length ?? 0) > length
                ? t('Text is too long.', 'စာသားရှည်လွန်းသည်။')
                : null,
          ),
        );
    Widget slider(
      String key,
      String label,
      double min,
      double max, {
      String unit = 'pt',
    }) {
      final n = value.toJson()[key] as double;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ${n.toStringAsFixed(1)} $unit'),
          Slider(
            value: n,
            min: min,
            max: max,
            divisions: ((max - min) * 2).round(),
            onChanged: enabled ? (v) => change(key, v) : null,
          ),
        ],
      );
    }

    return DesktopSection(
      tilePadding: EdgeInsets.zero,
      title: Text(
        receipt
            ? t('Customize slip voucher', 'Slip ဘောင်ချာပုံစံ ပြင်ရန်')
            : t('Customize A4 voucher', 'A4 ဘောင်ချာပုံစံ ပြင်ဆင်ရန်'),
      ),
      subtitle: Text(
        t(
          'Header, addresses, alignment, Remark and signatures',
          'ခေါင်းစီး၊ လိပ်စာ၊ စာတန်းညှိမှု၊ Remark နှင့် လက်မှတ်',
        ),
      ),
      children: [
        if (receipt)
          Text(
            t(
              'Shop text and text sizes are shared with A4. Slip length adjusts automatically.',
              'ဆိုင်ခေါင်းစီးနှင့် စာလုံးအရွယ်တို့ကို A4 နှင့် မျှသုံးပါသည်။ Slip အရှည်ကို အလိုအလျောက် ချိန်ပေးသည်။',
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: enabled ? onReset : null,
            icon: const Icon(Icons.restart_alt),
            label: Text(
              t(
                'Reset shared voucher appearance',
                'ဘောင်ချာပုံစံကို မူလအတိုင်း ပြန်ထားရန်',
              ),
            ),
          ),
        ),
        Text(
          t(
            'Blank heading uses the business name. Choose current saved branch contacts, custom text, or the original invoice snapshot below. Presentation changes never edit the saved invoice.',
            'ခေါင်းစီးအလွတ်ထားလျှင် ဆိုင်အမည်ကို သုံးမည်။ အောက်တွင် လက်ရှိဆိုင်ခွဲလိပ်စာ၊ ကိုယ်တိုင်ဖြည့်သောစာသား သို့မဟုတ် မူရင်းဘောင်ချာလိပ်စာကို ရွေးပါ။ သိမ်းထားသော ဘောင်ချာဒေတာကို မပြင်ပါ။',
          ),
        ),
        field(
          'heading',
          t('Shop heading (optional)', 'ဆိုင်ခေါင်းစီး (မဖြည့်လည်းရ)'),
          100,
        ),
        field(
          'subtitle',
          t(
            'Second heading / service description',
            'ဒုတိယခေါင်းစီး / ဝန်ဆောင်မှု',
          ),
          120,
        ),
        InvoiceBranchPicker(
          value: value,
          onChanged: onChanged,
          enabled: enabled,
        ),
        if (value.branchMode == 'custom')
          field(
            'leftBranch',
            t(
              'Left branch: name, address, phones',
              'ဘယ်ဘက်ဆိုင်ခွဲ — အမည်၊ လိပ်စာ၊ ဖုန်း',
            ),
            450,
            lines: 4,
          ),
        if (value.branchMode == 'custom')
          field(
            'rightBranch',
            t(
              'Right branch: name, address, phones',
              'ညာဘက်ဆိုင်ခွဲ — အမည်၊ လိပ်စာ၊ ဖုန်း',
            ),
            450,
            lines: 4,
          ),
        if (!receipt && value.branchMode == 'custom')
          field(
            'thirdBranch',
            'Third branch: name, address, phones',
            450,
            lines: 4,
          ),
        if (!receipt)
          slider(
            'logoWidthMm',
            t('Logo width', 'Logo အကျယ်'),
            25,
            55,
            unit: 'mm',
          ),
        if (!receipt)
          slider(
            'headingSize',
            t('Shop heading size', 'ဆိုင်ခေါင်းစီး စာလုံးအရွယ်'),
            16,
            30,
          ),
        if (!receipt)
          slider(
            'subtitleSize',
            t('Second heading size', 'ဒုတိယခေါင်းစီး စာလုံးအရွယ်'),
            10,
            20,
          ),
        slider(
          'infoSize',
          t('Customer / invoice text size', 'Customer / Invoice စာလုံးအရွယ်'),
          8,
          11,
        ),
        if (!receipt)
          slider(
            'labelWidth',
            t('Label-to-value spacing', 'အညွှန်းနှင့် အချက်အလက်ကြား အကွာအဝေး'),
            48,
            80,
          ),
        slider(
          'tableSize',
          t('Item table text size', 'ပစ္စည်းဇယား စာလုံးအရွယ်'),
          7,
          10,
        ),
        if (!receipt)
          slider(
            'totalsPercent',
            t('Totals box width', 'Totals box အကျယ်'),
            28,
            42,
            unit: '%',
          ),
        field('remarkLabel', t('Remark heading', 'Remark ခေါင်းစဉ်'), 60),
        if (!receipt)
          field(
            'customerSignature',
            t('Left signature label', 'ဘယ်ဘက် လက်မှတ်ခေါင်းစဉ်'),
            60,
          ),
        if (!receipt)
          field(
            'cashierSignature',
            t('Middle signature label', 'အလယ် လက်မှတ်ခေါင်းစဉ်'),
            60,
          ),
        if (!receipt)
          field(
            'authorizedSignature',
            t('Right signature label', 'ညာဘက် လက်မှတ်ခေါင်းစဉ်'),
            60,
          ),
        Text(
          t(
            'Save default print settings in Invoice & Printer. Preview changes before printing. Actual invoice and customer details come from the saved voucher.',
            'Invoice & Printer တွင် Save နှိပ်ပြီး ပုံစံကို သိမ်းပါ။ Print မထုတ်မီ Preview ကြည့်ပါ။ Invoice နံပါတ်နှင့် Customer အချက်အလက်များကို သိမ်းထားသော ဘောင်ချာမှ အသုံးပြုမည်။',
          ),
        ),
      ],
    );
  }
}
