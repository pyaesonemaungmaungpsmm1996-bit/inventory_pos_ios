import 'desktop_ui.dart';
import 'app_capabilities.dart';
import 'transfer_work_store.dart';
import 'desktop_commands.dart';

import 'dart:math';

import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'app_datetime.dart';
import 'product_tracking.dart';
import 'transfer_voucher_repository.dart';
import 'voucher_permissions.dart';

part 'desktop_transfer_editor.dart';
part 'desktop_transfer_history.dart';

String tt(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String variant(Map p) =>
    [p['color'], p['size']].where((x) => x != null && x != '').join(' / ');
String identity(Map p) => [
  p['serial'],
  p['imei'],
  p['expires_on'],
].where((x) => x != null && x != '').join(' / ');

class TransferVouchersPage extends StatefulWidget {
  const TransferVouchersPage({super.key, this.initialBranchId});
  final int? initialBranchId;
  @override
  State<TransferVouchersPage> createState() => _TransferVouchersPageState();
}

class _TransferVouchersPageState extends State<TransferVouchersPage> {
  int? branch;
  String filterQuery = '', filterStatus = 'all';
  String? filterFrom, filterTo;
  void updateHistory(VoidCallback change) => setState(change);
  bool busy = true;
  String? error;
  List<Map<String, Object?>> branches = [], rows = [];
  @override
  void initState() {
    super.initState();
    branch = widget.initialBranchId;
    load();
  }

  Future<void> load() async {
    try {
      final db = AppDatabase.instance;
      final b = await db.getBranches();
      final selected = branch ?? await db.getDefaultBranchId();
      if (selected == null) throw StateError('Add a branch first');
      final r = await TransferVoucherRepository.list(
        await db.database,
        selected,
      );
      if (mounted) {
        setState(() {
          branches = b;
          branch = selected;
          rows = r;
          busy = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  Future<void> action(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      await load();
    }
  }

  Future<void> create() async {
    if (busy || branches.length < 2 || branch == null) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransferEditor(source: branch!, branches: branches),
      ),
    );
    if (saved == true && mounted) await load();
  }

  Future<void> detail(Map<String, Object?> v) async {
    final items = await TransferVoucherRepository.items(
      await AppDatabase.instance.database,
      v['id'] as int,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => DesktopDialog(
        title: Row(
          children: [
            Expanded(child: Text('TRV-${v['id']}')),
            if (v['status'] == 'posted' && v['received_at'] == null)
              IconButton(
                tooltip: tt('Unlock to edit', 'သော့ဖွင့်ပြင်ရန်'),
                icon: const Icon(Icons.lock_outline),
                onPressed: () async {
                  try {
                    await VoucherPermissions.requireEditable();
                    if (!c.mounted || !mounted) return;
                    Navigator.pop(c);
                    await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TransferEditor(
                          source: v['branch_id'] as int,
                          branches: branches,
                          editVoucher: v,
                        ),
                      ),
                    );
                    if (mounted) await load();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text('$e')));
                    }
                  }
                },
              ),
          ],
        ),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${v['source_name']} → ${v['destination_name']}'),
                Text(v['transfer_date'].toString()),
                for (final i in items) ...[
                  const Divider(),
                  Text(
                    '${i['item_code']} · ${i['product_name']} × ${i['quantity']}',
                  ),
                  Text(variant(i)),
                  for (final a in (i['lots'] as List).cast<Map>())
                    Text('${identity(a)} × ${a['quantity']}'),
                ],
                const Divider(),
                Text(v['note'].toString()),
                Text(v['transport_info'].toString()),
                if (v['status'] == 'void') Text(v['void_reason'].toString()),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tt('Close', 'ပိတ်ရန်')),
          ),
        ],
      ),
    );
  }

  Future<void> receive(Map<String, Object?> v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => DesktopDialog(
        title: Text(
          tt('Receive all items?', 'ဘောင်ချာတစ်စောင်လုံး လက်ခံမလား?'),
        ),
        content: Text('TRV-${v['id']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tt('Cancel', 'မလုပ်တော့')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tt('Receive all', 'အားလုံးလက်ခံမည်')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await action(
        () async => TransferVoucherRepository.receive(
          await AppDatabase.instance.database,
          v['id'] as int,
          branch!,
        ),
      );
    }
  }

  Future<void> voidVoucher(Map<String, Object?> v) async {
    final reason = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => DesktopDialog(
        title: Text(
          tt('Void whole transfer', 'ဘောင်ချာတစ်စောင်လုံး ပယ်ဖျက်ရန်'),
        ),
        content: TextField(
          controller: reason,
          maxLength: 300,
          decoration: InputDecoration(
            labelText: tt('Reason', 'အကြောင်းပြချက်'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tt('Cancel', 'မလုပ်တော့')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, reason.text.trim()),
            child: Text(tt('Void', 'ပယ်ဖျက်မည်')),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty || !mounted) return;
    await action(() async {
      await VoucherPermissions.requireOwner();
      await TransferVoucherRepository.voidVoucher(
        await AppDatabase.instance.database,
        v['id'] as int,
        text,
      );
    });
  }

  @override
  Widget build(BuildContext context) => AppCapabilities.windows
      ? transferDesktop()
      : DesktopCommandScope(
          enabled: !busy && branches.length >= 2,
          commands: {DesktopCommand.newVoucher: create},
          child: DesktopScaffold(
            floatingActionButton: busy || branches.length < 2
                ? null
                : FloatingActionButton.extended(
                    tooltip: tt('New transfer', 'အလွှဲအသစ်'),
                    icon: const Icon(Icons.add),
                    label: Text(tt('New transfer', 'ပစ္စည်းလွှဲရန်')),
                    onPressed: create,
                  ),
            body: Column(
              children: [
                if (branches.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: DropdownButtonFormField<int>(
                      key: ValueKey(branch),
                      initialValue: branch,
                      decoration: InputDecoration(
                        labelText: tt('Branch', 'ဆိုင်ခွဲ'),
                      ),
                      items: [
                        for (final b in branches)
                          DropdownMenuItem(
                            value: b['id'] as int,
                            child: Text(b['name'].toString()),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (v) {
                              setState(() {
                                branch = v;
                                busy = true;
                              });
                              load();
                            },
                    ),
                  ),
                if (busy) const LinearProgressIndicator(),
                if (error != null) SelectableText(error!),
                if (branches.length < 2)
                  Text(
                    tt(
                      'Add a second branch first.',
                      'ဆိုင်ခွဲ အနည်းဆုံးနှစ်ခု လိုပါသည်။',
                    ),
                  ),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(
                            tt(
                              'No transfer vouchers yet',
                              'ပစ္စည်းလွှဲဘောင်ချာ မရှိသေးပါ',
                            ),
                          ),
                        )
                      : DesktopListView.builder(
                          itemCount: rows.length,
                          desktopColumns: const [
                            'Transfer No.',
                            'From',
                            'To',
                            'Date',
                            'Items',
                            'Status',
                          ],
                          desktopCells: (context, index) {
                            final r = rows[index];
                            return [
                              desktopCellText('TRV-${r['id']}'),
                              desktopCellText(r['source_name']),
                              desktopCellText(r['destination_name']),
                              desktopCellText(r['transfer_date']),
                              desktopCellText(r['line_count']),
                              desktopCellText(
                                r['status'] == 'void'
                                    ? 'Void'
                                    : r['received_at'] == null
                                    ? 'Pending receipt'
                                    : 'Received',
                              ),
                            ];
                          },
                          itemBuilder: (context, index) {
                            final v = rows[index];
                            return Card(
                              child: DesktopListTile(
                                onTap: () => detail(v),
                                title: Text(
                                  'TRV-${v['id']} · ${v['line_count']} ${tt('items', 'မျိုး')}',
                                ),
                                subtitle: Text(
                                  '${v['source_name']} → ${v['destination_name']} · ${v['transfer_date']} · ${v['status'] == 'void'
                                      ? tt('Void', 'ပယ်ဖျက်ပြီး')
                                      : v['received_at'] == null
                                      ? tt('Pending receipt', 'လက်ခံရန်စောင့်နေ')
                                      : tt('Received', 'လက်ခံပြီး')}',
                                ),
                                trailing: busy || v['status'] == 'void'
                                    ? null
                                    : PopupMenuButton<String>(
                                        onSelected: (a) {
                                          if (a == 'receive') receive(v);
                                          if (a == 'void') voidVoucher(v);
                                        },
                                        itemBuilder: (_) => [
                                          if (v['destination_branch_id'] ==
                                                  branch &&
                                              v['received_at'] == null)
                                            PopupMenuItem(
                                              value: 'receive',
                                              child: Text(
                                                tt(
                                                  'Receive all',
                                                  'အားလုံးလက်ခံရန်',
                                                ),
                                              ),
                                            ),
                                          PopupMenuItem(
                                            value: 'void',
                                            child: Text(
                                              tt(
                                                'Void (Owner)',
                                                'ပယ်ဖျက်ရန် (Owner)',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
}

class TransferEditor extends StatefulWidget {
  const TransferEditor({
    super.key,
    required this.source,
    required this.branches,
    this.editVoucher,
  });
  final int source;
  final Map<String, Object?>? editVoucher;
  final List<Map<String, Object?>> branches;
  @override
  State<TransferEditor> createState() => _TransferEditorState();
}

class _TransferEditorState extends State<TransferEditor> {
  final note = TextEditingController(), transport = TextEditingController();
  final rowsFocus = FocusNode();
  final keyboardScroll = ScrollController();
  int selectedLine = 0;
  String requestKey = List.generate(
    24,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  final lines = <Map<String, Object?>>[];
  final desktopLotLabels = <int, String>{};
  final originalTransferLots = <int, int>{};
  List<Map<String, Object?>> products = [];
  int? destination;
  bool busy = true, allowLeave = false, leaving = false, workRead = false;
  String? error;
  DateTime date = AppDateTime.today();
  @override
  void initState() {
    super.initState();
    destination =
        widget.branches.firstWhere((b) => b['id'] != widget.source)['id']
            as int;
    load();
  }

  @override
  void dispose() {
    keyboardScroll.dispose();
    rowsFocus.dispose();
    note.dispose();
    transport.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final p = (await AppDatabase.instance.getProducts(
        branchId: widget.source,
      )).map((r) => Map<String, Object?>.from(r)).toList();
      if (AppCapabilities.windows) {
        final lotRows = await (await AppDatabase.instance.database).query(
          'stock_lots',
          columns: ['id', 'serial', 'imei', 'expires_on'],
          where: 'branch_id=?',
          whereArgs: [widget.source],
        );
        for (final lot in lotRows) {
          desktopLotLabels[lot['id'] as int] = identity(lot);
        }
      }

      if (!workRead && widget.editVoucher != null) {
        final saved = widget.editVoucher!;
        final original = await TransferVoucherRepository.items(
          await AppDatabase.instance.database,
          saved['id'] as int,
        );
        destination = saved['destination_branch_id'] as int;
        date = DateTime.parse(saved['transfer_date'] as String);
        note.text = saved['note'] as String;
        transport.text = saved['transport_info'] as String;
        for (final i in original) {
          final product = p
              .where((r) => r['id'] == i['product_id'])
              .firstOrNull;
          if (product != null) {
            product['stock'] =
                (product['stock'] as int) + (i['quantity'] as int);
          }
          for (final l in (i['lots'] as List).cast<Map>()) {
            originalTransferLots[l['lot_id'] as int] = l['quantity'] as int;
          }
          lines.add({
            'product_id': i['product_id'],
            'item_code': i['item_code'],
            'product_name': i['product_name'],
            'quantity': i['quantity'],
            'color': i['color'],
            'size': i['size'],
            'tracking': i['tracking'],
            'lots': [
              for (final l in (i['lots'] as List).cast<Map>())
                {'lot_id': l['lot_id'], 'qty': l['quantity']},
            ],
          });
        }
        workRead = true;
      }
      if (!workRead && AppCapabilities.windows) {
        final work = await TransferWorkStore.read(
          await AppDatabase.instance.database,
          widget.source,
        );
        if (work != null) {
          final dest = work['destination'];
          if (!widget.branches.any((b) => b['id'] == dest) ||
              dest == widget.source) {
            throw StateError('Saved transfer destination is unavailable');
          }
          destination = dest as int;
          requestKey = work['request_key'] as String;
          date = DateTime.parse(work['date'] as String);
          note.text = work['note'] as String;
          transport.text = work['transport'] as String;
          lines.addAll(
            (work['lines'] as List).map(
              (l) => Map<String, Object?>.from(l as Map),
            ),
          );
        }
        workRead = true;
      }
      if (mounted) {
        setState(() {
          products = p;
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          busy = false;
        });
      }
    }
  }

  Future<void> addLine({
    int? index,
    Map<String, Object?>? selectedProduct,
  }) async {
    Map<String, Object?>? p = selectedProduct;
    if (index != null) {
      p = products.firstWhere((v) => v['id'] == lines[index]['product_id']);
    } else if (p == null) {
      var search = '';
      p = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, refresh) {
            final found = products
                .where(
                  (v) =>
                      ('${v['item_code']} ${v['name']} ${v['barcode']} ${variant(v)}')
                          .toLowerCase()
                          .contains(search.toLowerCase()),
                )
                .toList();
            return DesktopDialog(
              title: Text(
                tt(
                  'Choose item / Color / Size',
                  'ပစ္စည်း / Color / Size ရွေးရန်',
                ),
              ),
              content: SizedBox(
                width: 650,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      onChanged: (v) => refresh(() => search = v),
                      decoration: InputDecoration(
                        labelText: tt(
                          'Search code, name, barcode, Color, Size',
                          'ကုဒ်၊ အမည်၊ Barcode၊ Color၊ Size ရှာရန်',
                        ),
                      ),
                    ),
                    Expanded(
                      child: DesktopListView(
                        children: [
                          for (final v in found)
                            DesktopListTile(
                              enabled:
                                  (v['stock'] as int) > 0 &&
                                  !lines.any((l) => l['product_id'] == v['id']),
                              title: Text('${v['item_code']} · ${v['name']}'),
                              subtitle: Text(
                                '${variant(v)} · ${tt('Stock', 'လက်ကျန်')}: ${v['stock']}',
                              ),
                              onTap: () => Navigator.pop(c, v),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: Text(tt('Cancel', 'မလုပ်တော့')),
                ),
              ],
            );
          },
        ),
      );
    }
    if (p == null || !mounted) return;
    final selected = Map<String, Object?>.from(p);
    final db = await AppDatabase.instance.database;
    final lots = (await db.query(
      'stock_lots',
      where: 'product_id=? AND branch_id=?',
      whereArgs: [selected['id'], widget.source],
      orderBy: 'expires_on,id',
    )).map((r) => Map<String, Object?>.from(r)).toList();
    for (final lot in lots) {
      lot['available'] =
          (lot['available'] as int) + (originalTransferLots[lot['id']] ?? 0);
    }
    lots.removeWhere((l) => (l['available'] as int) <= 0);
    if (!mounted) return;
    final qty = TextEditingController(
      text: index == null ? '1' : lines[index]['quantity'].toString(),
    );
    final choices = <int, int>{};
    if (index != null) {
      for (final lot in ProductTracking.decode(lines[index]['lots'])) {
        choices[lot['lot_id'] as int] = lot['qty'] as int;
      }
    }
    String? issue;
    var filter = '';
    final line = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, refresh) => DesktopDialog(
          title: Text('${selected['item_code']} · ${variant(selected)}'),
          content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(selected['name'].toString()),
                  Text(
                    tt('Available: ', 'လက်ကျန်: ') +
                        selected['stock'].toString(),
                  ),
                  if (!ProductTracking.tracked(selected))
                    TextField(
                      autofocus: AppCapabilities.windows,
                      controller: qty,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tt('Quantity', 'အရေအတွက်'),
                      ),
                    ),
                  if (ProductTracking.tracked(selected)) ...[
                    TextField(
                      onChanged: (v) => refresh(() => filter = v),
                      decoration: InputDecoration(
                        labelText: tt(
                          'Search IMEI / Serial / expiry',
                          'IMEI / Serial / သက်တမ်း ရှာရန်',
                        ),
                      ),
                    ),
                    for (final lot in lots.where(
                      (v) =>
                          identity(v)
                              .toLowerCase()
                              .contains(filter.toLowerCase()),
                    ))
                      if (lot['serial'] != null || lot['imei'] != null)
                        CheckboxListTile(
                          value: choices.containsKey(lot['id']),
                          title: Text(identity(lot)),
                          onChanged: (v) => refresh(() {
                            if (v == true) {
                              choices[lot['id'] as int] = 1;
                            } else {
                              choices.remove(lot['id']);
                            }
                          }),
                        )
                      else
                        TextFormField(
                          key: ValueKey(lot['id']),
                          initialValue: (choices[lot['id']] ?? 0).toString(),
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText:
                                '${identity(lot)} · ${tt('Available', 'လက်ကျန်')} ${lot['available']}',
                          ),
                          onChanged: (v) =>
                              choices[lot['id'] as int] = int.tryParse(v) ?? -1,
                        ),
                  ],
                  if (issue != null)
                    Text(
                      issue!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(tt('Cancel', 'မလုပ်တော့')),
            ),
            FilledButton(
              onPressed: () {
                final tracked = ProductTracking.tracked(selected);
                final n = tracked
                    ? choices.values.fold<int>(0, (a, b) => a + b)
                    : int.tryParse(qty.text.trim()) ?? 0;
                if (n < 1 ||
                    n > (selected['stock'] as int) ||
                    choices.entries.any(
                      (e) =>
                          e.value < 0 ||
                          e.value >
                              (lots.firstWhere(
                                    (l) => l['id'] == e.key,
                                  )['available']
                                  as int),
                    )) {
                  refresh(
                    () => issue = tt(
                      'Check quantity and available stock.',
                      'အရေအတွက်နှင့် လက်ကျန်ကို စစ်ပါ။',
                    ),
                  );
                  return;
                }
                Navigator.pop(c, {
                  'product_id': selected['id'],
                  'quantity': n,
                  'item_code': selected['item_code'],
                  'product_name': selected['name'],
                  'color': selected['color'],
                  'size': selected['size'],
                  'tracking': selected['tracking'],
                  'lots': [
                    for (final e in choices.entries.where((e) => e.value > 0))
                      {'lot_id': e.key, 'qty': e.value},
                  ],
                });
              },
              child: Text(tt('Add / Update', 'ထည့်ရန် / ပြင်ရန်')),
            ),
          ],
        ),
      ),
    );
    if (line != null && mounted) {
      setState(() {
        if (index == null) {
          lines.add(line);
        } else {
          lines[index] = line;
        }
      });
    }
  }

  Future<void> discardSavedWork() async {
    if (!await desktopAsk(
          context,
          tt(
            'Discard saved transfer draft?',
            'သိမ်းထားသော Transfer Draft ကိုဖယ်မလား။',
          ),
          tt(
            'This removes only the unfinished draft, not posted transfers.',
            'လက်စ Draft ကိုသာဖယ်မည်။ ပို့ပြီးသော Transfer များ မဖျက်ပါ။',
          ),
        ) ||
        !mounted) {
      return;
    }
    await TransferWorkStore.clear(
      await AppDatabase.instance.database,
      widget.source,
    );
    setState(() {
      error = null;
      workRead = true;
      busy = false;
    });
  }

  Future<void> saveWork() async {
    if (widget.editVoucher != null) return;
    await TransferWorkStore.save(
      await AppDatabase.instance.database,
      widget.source,
      {
        'request_key': requestKey,
        'destination': destination,
        'date': date.toIso8601String(),
        'note': note.text,
        'transport': transport.text,
        'lines': lines,
      },
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tt(
              'Transfer draft saved locally',
              'Transfer Draft ကို စက်တွင်သိမ်းပြီးပါပြီ။',
            ),
          ),
        ),
      );
    }
  }

  Future<void> leave() async {
    if (busy || leaving) return;
    if (widget.editVoucher != null) {
      final discard = await desktopAsk(
        context,
        tt('Cancel changes?', 'ပြင်ဆင်မှု ပယ်ဖျက်မလား။'),
        tt(
          'The saved transfer stays unchanged.',
          'သိမ်းထားသော ဘောင်ချာသည် မပြောင်းပါ။',
        ),
      );
      if (discard && mounted) {
        setState(() => allowLeave = true);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context);
      }
      return;
    }
    leaving = true;
    try {
      if (lines.isNotEmpty ||
          note.text.isNotEmpty ||
          transport.text.isNotEmpty) {
        final choice = await showDialog<String>(
          context: context,
          builder: (c) => DesktopDialog(
            title: Text(
              tt('Leave transfer draft?', 'Transfer Draft မှထွက်မလား။'),
            ),
            actions: [
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.pop(c),
                child: Text(tt('Keep editing', 'ဆက်ပြင်မည်')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, 'discard'),
                child: Text(tt('Discard', 'မသိမ်းဘဲဖယ်မည်')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, 'save'),
                child: Text(tt('Save & leave', 'သိမ်းပြီးထွက်မည်')),
              ),
            ],
          ),
        );
        if (choice == null || !mounted) return;
        if (choice == 'save') {
          await saveWork();
        } else {
          await TransferWorkStore.clear(
            await AppDatabase.instance.database,
            widget.source,
          );
        }
      }
      if (!mounted) return;
      setState(() => allowLeave = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    } finally {
      leaving = false;
    }
  }

  Future<void> keyboardPost() async {
    if (!await desktopAsk(
          context,
          tt('Dispatch this transfer?', 'ဤလွှဲပြောင်းမှုကို ပို့မလား။'),
          tt(
            'All selected items will leave source stock. Receive separately at the destination.',
            'ရွေးထားသောပစ္စည်းအားလုံး မူလ Stock မှထွက်မည်။ လက်ခံဆိုင်တွင် သီးခြား Receive လုပ်ရမည်။',
          ),
        ) ||
        !mounted) {
      return;
    }
    await save();
  }

  void selectLine(int delta) {
    if (lines.isNotEmpty) {
      setState(
        () => selectedLine = (selectedLine + delta).clamp(0, lines.length - 1),
      );
    }
  }

  Future<void> removeSelected() async {
    if (lines.isEmpty) return;
    selectedLine = selectedLine.clamp(0, lines.length - 1);
    if (!await desktopAsk(
          context,
          tt('Remove draft item?', 'Draft ပစ္စည်းဖယ်မလား။'),
          '${lines[selectedLine]['product_name']}',
        ) ||
        !mounted) {
      return;
    }
    setState(() => lines.removeAt(selectedLine));
  }

  Future<void> save() async {
    if (busy || lines.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await TransferVoucherRepository.post(
        await AppDatabase.instance.database,
        requestKey: requestKey,
        source: widget.source,
        destination: destination!,
        date: date.toIso8601String().substring(0, 10),
        note: note.text,
        transport: transport.text,
        lines: lines,
        replaceId: widget.editVoucher?['id'] as int?,
        expectedPayload: widget.editVoucher?['request_payload'] as String?,
      );
      try {
        if (widget.editVoucher == null) {
          await TransferWorkStore.clear(
            await AppDatabase.instance.database,
            widget.source,
          );
        }
      } catch (_) {
        /* Posted request keys are detected when reopening. */
      }
      if (mounted) {
        setState(() {
          allowLeave = true;
          busy = false;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = '$e';
        });
      }
    }
  }

  void desktopUpdate(VoidCallback change) => setState(change);

  @override
  Widget build(BuildContext context) => DesktopCommandScope(
    enabled: !busy && workRead,
    onEscape: leave,
    commands: {
      DesktopCommand.saveDraft: saveWork,
      DesktopCommand.addItem: () => addLine(),
      DesktopCommand.confirm: keyboardPost,
      DesktopCommand.focusRows: () =>
          desktopFocusInScroll(rowsFocus, keyboardScroll),
      DesktopCommand.previousRow: () => selectLine(-1),
      DesktopCommand.nextRow: () => selectLine(1),
      DesktopCommand.quantity: () => lines.isEmpty
          ? Future<void>.value()
          : addLine(index: selectedLine.clamp(0, lines.length - 1)),
      DesktopCommand.editRow: () => lines.isEmpty
          ? Future<void>.value()
          : addLine(index: selectedLine.clamp(0, lines.length - 1)),
      DesktopCommand.removeItem: removeSelected,
    },
    child: PopScope(
      canPop: !busy && (!AppCapabilities.windows || allowLeave),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && AppCapabilities.windows) leave();
      },
      child: AppCapabilities.windows
          ? desktopTransferEditor()
          : DesktopScaffold(
              appBar: AppBar(
                title: Text(
                  tt('New transfer voucher', 'ပစ္စည်းလွှဲဘောင်ချာအသစ်'),
                ),
              ),
              body: DesktopListView(
                controller: keyboardScroll,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    tt('From: ', 'မှ: ') +
                        widget.branches
                            .firstWhere((b) => b['id'] == widget.source)['name']
                            .toString(),
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: destination,
                    decoration: InputDecoration(
                      labelText: tt('To branch', 'သို့ ဆိုင်ခွဲ'),
                    ),
                    items: [
                      for (final b in widget.branches.where(
                        (b) => b['id'] != widget.source,
                      ))
                        DropdownMenuItem(
                          value: b['id'] as int,
                          child: Text(b['name'].toString()),
                        ),
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() => destination = v),
                  ),
                  DesktopListTile(
                    title: Text(
                      tt('Date: ', 'ရက်စွဲ: ') +
                          date.toIso8601String().substring(0, 10),
                    ),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: busy
                        ? null
                        : () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: date,
                              firstDate: DateTime(2000),
                              lastDate: AppDateTime.today(),
                            );
                            if (d != null && mounted) setState(() => date = d);
                          },
                  ),
                  if (AppCapabilities.windows)
                    TextButton(
                      onPressed: () => rowsFocus.requestFocus(),
                      child: Text(
                        tt(
                          'Items · F5 / ↑ ↓ / Enter',
                          'ပစ္စည်းများ · F5 / ↑ ↓ / Enter',
                        ),
                      ),
                    ),
                  Focus(
                    focusNode: rowsFocus,
                    child: Column(
                      children: [
                        for (var i = 0; i < lines.length; i++)
                          Card(
                            color: AppCapabilities.windows && selectedLine == i
                                ? Theme.of(context).colorScheme.primaryContainer
                                : null,
                            child: DesktopListTile(
                              onTap: busy
                                  ? null
                                  : () async {
                                      selectedLine = i;
                                      await addLine(index: i);
                                    },
                              title: Text(
                                '${lines[i]['item_code']} · ${lines[i]['product_name']} × ${lines[i]['quantity']}',
                              ),
                              subtitle: Text(
                                '${variant(lines[i])} · ${ProductTracking.decode(lines[i]['lots']).length} ${tt('selected lots', 'ရွေးထားသော Serial/lot')}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: busy
                                    ? null
                                    : () => setState(() => lines.removeAt(i)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (AppCapabilities.windows)
                    OutlinedButton.icon(
                      onPressed: busy ? null : saveWork,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        tt("Save Draft · Ctrl+S", "Draft သိမ်းရန် · Ctrl+S"),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : addLine,
                    icon: const Icon(Icons.add),
                    label: Text(
                      tt(
                        'Add item / IMEI / Serial',
                        'ပစ္စည်း / IMEI / Serial ထည့်ရန်',
                      ),
                    ),
                  ),
                  TextField(
                    controller: note,
                    enabled: !busy,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: tt('Remark', 'မှတ်ချက်'),
                    ),
                  ),
                  TextField(
                    controller: transport,
                    enabled: !busy,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: tt(
                        'Transportation info',
                        'ပို့ဆောင်ရေးအချက်အလက်',
                      ),
                    ),
                  ),
                  Text(
                    tt(
                      'Source stock leaves now. Destination stock is added when the whole voucher is received.',
                      'လွှဲသိမ်းချိန် source လက်ကျန်လျော့ပြီး destination က ဘောင်ချာတစ်စောင်လုံး Receive လုပ်မှ လက်ကျန်တိုးပါမည်။',
                    ),
                  ),
                  if (error != null) SelectableText(error!),
                  if (AppCapabilities.windows && error != null && !workRead)
                    OutlinedButton(
                      onPressed: busy ? null : discardSavedWork,
                      child: Text(
                        tt(
                          'Discard saved transfer draft',
                          'သိမ်းထားသော Transfer Draft ကိုဖယ်ရန်',
                        ),
                      ),
                    ),
                  if (busy) const LinearProgressIndicator(),
                  FilledButton(
                    onPressed:
                        busy ||
                            lines.isEmpty ||
                            (AppCapabilities.windows && !workRead)
                        ? null
                        : AppCapabilities.windows
                        ? keyboardPost
                        : save,
                    child: Text(
                      tt('Transfer all items', 'ပစ္စည်းအားလုံး လွှဲမည်'),
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}
