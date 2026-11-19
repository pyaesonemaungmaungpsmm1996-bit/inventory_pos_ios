import 'package:flutter/material.dart';

import 'app_language.dart';
import 'desktop_ui.dart';

Future<int?> pickBranchDefinition(
  BuildContext context, {
  required String title,
  required List<Map<String, Object?>> rows,
  bool money = false,
}) {
  String t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
  var search = '';
  return showDialog<int>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) {
        final visible = rows
            .where(
              (r) => [r['name'], r['branch_name'], r['account_number']].any(
                (v) =>
                    v.toString().toLowerCase().contains(search.toLowerCase()),
              ),
            )
            .toList();
        return DesktopDialog(
          title: Text(title),
          content: SizedBox(
            width: 800,
            height: 420,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: t(
                      'Search name / source branch',
                      'အမည် / မူလဆိုင်ခွဲ ရှာရန်',
                    ),
                  ),
                  onChanged: (v) => update(() => search = v),
                ),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            t(
                              'No reusable entries found',
                              'ပြန်ရွေးသုံးနိုင်သောစာရင်း မရှိပါ',
                            ),
                          ),
                        )
                      : DesktopListView.builder(
                          itemCount: visible.length,
                          desktopColumns: money
                              ? const [
                                  'Name',
                                  'Source branch',
                                  'Type',
                                  'Account number',
                                ]
                              : const ['Name', 'Source branch'],
                          desktopCells: (context, i) {
                            final r = visible[i];
                            return [
                              desktopCellText(r['name']),
                              desktopCellText(r['branch_name']),
                              if (money) ...[
                                desktopCellText(r['type']),
                                desktopCellText(r['account_number']),
                              ],
                            ];
                          },
                          itemBuilder: (context, i) {
                            final r = visible[i];
                            return DesktopListTile(
                              title: Text(r['name'].toString()),
                              subtitle: Text(
                                r['branch_name'].toString() +
                                    (money
                                        ? ' · ${r['account_number']}'
                                        : ''),
                              ),
                              onTap: () =>
                                  Navigator.pop(dialog, r['id'] as int),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(t('Cancel', 'မလုပ်တော့ပါ')),
            ),
          ],
        );
      },
    ),
  );
}
