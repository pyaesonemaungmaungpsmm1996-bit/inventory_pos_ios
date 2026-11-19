import 'package:flutter/material.dart';

import 'a4_layout_settings.dart';
import 'app_database.dart';
import 'app_language.dart';

class InvoiceBranchPicker extends StatefulWidget {
  const InvoiceBranchPicker({
    super.key,
    required this.value,
    required this.onChanged,
    required this.enabled,
  });
  final A4LayoutSettings value;
  final ValueChanged<A4LayoutSettings> onChanged;
  final bool enabled;
  @override
  State<InvoiceBranchPicker> createState() => _InvoiceBranchPickerState();
}

class _InvoiceBranchPickerState extends State<InvoiceBranchPicker> {
  late Future<List<Map<String, Object?>>> branches;
  @override
  void initState() {
    super.initState();
    branches = AppDatabase.instance.getBranches();
  }

  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey(widget.value.branchMode),
        initialValue: widget.value.branchMode,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: t(
            'Branch addresses on voucher',
            'ဘောင်ချာတွင် ပြမည့် ဆိုင်ခွဲလိပ်စာ',
          ),
        ),
        items: [
          DropdownMenuItem(
            value: 'auto',
            child: Text(
              t(
                'Auto: one or two saved branches',
                'အလိုအလျောက် — သိမ်းထားသော ဆိုင်ခွဲ ၁/၂ ခု',
              ),
            ),
          ),
          DropdownMenuItem(
            value: 'one',
            child: Text(
              t('One branch, centered', 'ဆိုင်ခွဲတစ်ခု — အလယ်တည့်တည့်'),
            ),
          ),
          DropdownMenuItem(
            value: 'two',
            child: Text(
              t('Two branches, side by side', 'ဆိုင်ခွဲနှစ်ခု — ဘေးချင်းယှဉ်'),
            ),
          ),
          DropdownMenuItem(
            value: 'custom',
            child: Text(
              t('Custom address text', 'လိပ်စာစာသား ကိုယ်တိုင်ပြင်ရန်'),
            ),
          ),
          DropdownMenuItem(
            value: 'snapshot',
            child: Text(
              t(
                'Original invoice branch snapshot',
                'မူရင်းဘောင်ချာထဲ သိမ်းထားသောလိပ်စာ',
              ),
            ),
          ),
        ],
        onChanged: widget.enabled
            ? (v) {
                if (v != null) {
                  widget.onChanged(widget.value.withValues({'branchMode': v}));
                }
              }
            : null,
      ),
      if (['one', 'two', 'auto'].contains(widget.value.branchMode))
        FutureBuilder<List<Map<String, Object?>>>(
          future: branches,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton.icon(
                onPressed: () => setState(
                  () => branches = AppDatabase.instance.getBranches(),
                ),
                icon: const Icon(Icons.refresh),
                label: Text(
                  t(
                    'Could not load branches. Retry.',
                    'ဆိုင်ခွဲများ ဖတ်မရပါ။ ပြန်ကြိုးစားရန်။',
                  ),
                ),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final rows = snapshot.data!;
            Widget picker(bool second) {
              final id = second
                  ? widget.value.secondaryBranchId
                  : widget.value.primaryBranchId;
              final options = rows
                  .where(
                    (b) => !second || b['id'] != widget.value.primaryBranchId,
                  )
                  .toList();
              final value = options.any((b) => b['id'] == id) ? id! : 0;
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DropdownButtonFormField<int>(
                  key: ValueKey(
                    '${second ? 'right' : 'left'}:$value:${widget.value.primaryBranchId}',
                  ),
                  initialValue: value,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: second
                        ? t('Second / right branch', 'ဒုတိယ / ညာဘက်ဆိုင်ခွဲ')
                        : t(
                            'First / centered branch',
                            'ပထမ / အလယ်တွင်ပြမည့် ဆိုင်ခွဲ',
                          ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 0,
                      child: Text(
                        t('Automatic selection', 'အလိုအလျောက် ရွေးရန်'),
                      ),
                    ),
                    for (final branch in options)
                      DropdownMenuItem(
                        value: branch['id'] as int,
                        child: Text(
                          '${branch['name']} (${branch['code']})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: widget.enabled
                      ? (v) {
                          if (v == null) return;
                          widget.onChanged(
                            widget.value.withValues({
                              second ? 'secondaryBranchId' : 'primaryBranchId':
                                  v,
                              if (!second &&
                                  v == widget.value.secondaryBranchId)
                                'secondaryBranchId': 0,
                            }),
                          );
                        }
                      : null,
                ),
              );
            }

            return Column(
              children: [
                picker(false),
                if (widget.value.branchMode != 'one') picker(true),
              ],
            );
          },
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          t(
            'Auto uses current Business Info > Branches addresses, including reprints. One branch is centered; two branches use two columns. Save print settings after changing the selection.',
            'Auto သည် Business Info > Branches ထဲက လက်ရှိလိပ်စာကို ပြန်ထုတ်သောဘောင်ချာများတွင်ပါ အသုံးပြုမည်။ တစ်ခုဆို အလယ်၊ နှစ်ခုဆို နှစ်ကွက် ပြမည်။ ရွေးပြီး Print settings ကို Save လုပ်ပါ။',
          ),
        ),
      ),
    ],
  );
}
