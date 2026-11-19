import 'desktop_ui.dart';
import 'app_capabilities.dart';
import 'transfer_vouchers_page.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_database.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'barcode_scan_page.dart';
import 'expense_receipt_photo.dart';
import 'invoice_void_dialog.dart';

class LegacyStockTransferPage extends StatefulWidget {
  const LegacyStockTransferPage({super.key, this.initialBranchId});
  final int? initialBranchId;
  @override
  State<LegacyStockTransferPage> createState() =>
      _LegacyStockTransferPageState();
}

class _LegacyStockTransferPageState extends State<LegacyStockTransferPage> {
  List<Map<String, Object?>> branches = [], products = [], transfers = [];
  int? branchId;
  bool loading = true;
  String? error;
  String tr(String en, String my) =>
      AppLanguage.current.value == 'my' ? my : en;

  @override
  void initState() {
    super.initState();
    branchId = widget.initialBranchId;
    load();
  }

  Future<void> load() async {
    try {
      final db = AppDatabase.instance;
      final b = await db.getBranches();
      final initial = branchId ?? await db.getDefaultBranchId();
      final selected = b.any((row) => row['id'] == initial)
          ? initial
          : (b.isEmpty ? null : b.first['id'] as int);
      final p = selected == null
          ? <Map<String, Object?>>[]
          : await db.getProducts(branchId: selected);
      final t = selected == null
          ? <Map<String, Object?>>[]
          : await db.getStockTransfers(selected);
      if (!mounted) return;
      setState(() {
        branches = b;
        branchId = selected;
        products = p;
        transfers = t;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = e.toString();
      });
    }
  }

  String dateText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<Uint8List?> pickPhoto(BuildContext parent) async {
    final source = await showDesktopSheet<ImageSource>(
      context: parent,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (AppCapabilities.camera)
              DesktopListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: Text(tr('Camera', 'ကင်မရာ')),
                onTap: () => Navigator.pop(sheet, ImageSource.camera),
              ),
            DesktopListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(tr('Gallery', 'ဓာတ်ပုံများ')),
              onTap: () => Navigator.pop(sheet, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2200,
      maxHeight: 2200,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (picked == null || await picked.length() > 12000000) return null;
    return prepareExpenseReceiptPhoto(await picked.readAsBytes());
  }

  Future<void> create({Map<String, Object?>? editing}) async {
    if (branchId == null || branches.length < 2) return;
    final sourceBranch = editing?['source_branch_id'] as int? ?? branchId!;
    final sourceProducts = sourceBranch == branchId
        ? products
        : await AppDatabase.instance.getProducts(branchId: sourceBranch);
    if (!mounted) return;
    final quantity = TextEditingController(
      text: editing?['quantity']?.toString() ?? '',
    );
    final note = TextEditingController(text: editing?['note'] as String? ?? '');
    final transport = TextEditingController(
      text: editing?['transport_info'] as String? ?? '',
    );
    final productText = TextEditingController(
      text: editing == null
          ? ''
          : '${editing['item_code']} · ${editing['product_name']}',
    );
    final key = GlobalKey<FormState>();
    int? destination =
        editing?['destination_branch_id'] as int? ??
        branches.where((b) => b['id'] != sourceBranch).first['id'] as int;
    int? product = editing?['product_id'] as int?;
    final existingDate = editing?['transfer_date'] as String?;
    DateTime transferDate =
        DateTime.tryParse(
          existingDate != null && existingDate.isNotEmpty
              ? existingDate
              : editing?['created_at'] as String? ?? '',
        ) ??
        AppDateTime.today();
    Uint8List? photo;
    if (editing != null) {
      photo = await AppDatabase.instance.getStockTransferPhoto(
        editing['id'] as int,
      );
    }
    if (!mounted) return;
    bool photoChanged = false;
    bool saving = false;
    Future<Map<String, Object?>?> searchProduct(BuildContext parent) async {
      final search = TextEditingController();
      var filter = '';
      return showDialog<Map<String, Object?>>(
        context: parent,
        builder: (searchContext) => StatefulBuilder(
          builder: (context, refresh) {
            final matches = sourceProducts
                .where(
                  (p) =>
                      ('${p['item_code']} ${p['name']} ${p['barcode'] ?? ''}')
                          .toLowerCase()
                          .contains(filter.toLowerCase()),
                )
                .toList();
            return DesktopDialog(
              title: Text(tr('Choose Product', 'ပစ္စည်းရွေးရန်')),
              content: SizedBox(
                width: double.maxFinite,
                height: 370,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      autofocus: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: tr(
                          'Item code / name / barcode',
                          'Item Code / အမည် / Barcode',
                        ),
                      ),
                      onChanged: (v) => refresh(() => filter = v),
                    ),
                    Expanded(
                      child: DesktopListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, i) {
                          final p = matches[i];
                          return DesktopListTile(
                            title: Text('${p['item_code']} · ${p['name']}'),
                            subtitle: Text(
                              '${tr('Available', 'လက်ကျန်')}: ${p['stock']}',
                            ),
                            enabled:
                                (p['stock'] as int) > 0 ||
                                editing?['product_id'] == p['id'],
                            onTap: () => Navigator.pop(searchContext, p),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(searchContext),
                  child: Text(tr('Cancel', 'မလုပ်တော့')),
                ),
              ],
            );
          },
        ),
      );
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !saving,
          child: DesktopDialog(
            title: Text(
              editing == null
                  ? tr('New Stock Transfer', 'ပစ္စည်းဆိုင်ခွဲလွှဲရန်')
                  : tr('Edit Stock Transfer', 'ပစ္စည်းလွှဲမှု ပြန်ပြင်ရန်'),
            ),
            content: SingleChildScrollView(
              child: Form(
                key: key,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${tr('From', 'မှ')}: ${branches.firstWhere((b) => b['id'] == sourceBranch)['name']}',
                    ),
                    DropdownButtonFormField<int>(
                      initialValue: destination,
                      decoration: InputDecoration(
                        labelText: tr('To branch', 'သို့ ဆိုင်ခွဲ'),
                      ),
                      items: branches
                          .where((b) => b['id'] != sourceBranch)
                          .map(
                            (b) => DropdownMenuItem(
                              value: b['id'] as int,
                              child: Text(b['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (v) => update(() => destination = v),
                    ),
                    TextFormField(
                      controller: productText,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: tr(
                          'Product · item code / name',
                          'ပစ္စည်း · ကုဒ် / အမည်',
                        ),
                        suffixIcon: IconButton(
                          tooltip: tr('Scan barcode', 'Barcode ဖတ်ရန်'),
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: saving
                              ? null
                              : () async {
                                  final code = await Navigator.push<String>(
                                    dialogContext,
                                    MaterialPageRoute(
                                      builder: (_) => const BarcodeScanPage(),
                                    ),
                                  );
                                  if (code == null || !dialogContext.mounted) {
                                    return;
                                  }
                                  try {
                                    final found = await AppDatabase.instance
                                        .getProductByBarcode(
                                          branchId: sourceBranch,
                                          barcode: code,
                                        );
                                    if (!dialogContext.mounted) return;
                                    if (found == null ||
                                        ((found['stock'] as int) <= 0 &&
                                            editing?['product_id'] !=
                                                found['id'])) {
                                      ScaffoldMessenger.of(dialogContext)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                tr(
                                                  'Product not found or no stock in this branch.',
                                                  'ပစ္စည်းမတွေ့ပါ သို့မဟုတ် ဤဆိုင်ခွဲတွင် လက်ကျန်မရှိပါ။',
                                                ),
                                              ),
                                            ),
                                          );
                                      return;
                                    }
                                    update(() {
                                      product = found['id'] as int;
                                      productText.text =
                                          '${found['item_code']} · ${found['name']}';
                                    });
                                  } catch (e) {
                                    if (dialogContext.mounted) {
                                      ScaffoldMessenger.of(dialogContext)
                                          .showSnackBar(
                                            SnackBar(content: Text('$e')),
                                          );
                                    }
                                  }
                                },
                        ),
                      ),
                      onTap: saving
                          ? null
                          : () async {
                              final found = await searchProduct(dialogContext);
                              if (found == null || !dialogContext.mounted) {
                                return;
                              }
                              update(() {
                                product = found['id'] as int;
                                productText.text =
                                    '${found['item_code']} · ${found['name']}';
                              });
                            },
                      validator: (_) => product == null
                          ? tr('Choose a product', 'ပစ္စည်းရွေးပါ')
                          : null,
                    ),
                    TextFormField(
                      controller: quantity,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: tr('Quantity', 'အရေအတွက်'),
                      ),
                      validator: (v) {
                        final n = int.tryParse(v?.trim() ?? '');
                        if (n == null || n <= 0) {
                          return tr(
                            'Enter a positive quantity',
                            'အရေအတွက်ဖြည့်ပါ',
                          );
                        }
                        final stock = sourceProducts.where(
                          (p) => p['id'] == product,
                        );
                        if (editing == null &&
                            stock.isNotEmpty &&
                            n > (stock.first['stock'] as int)) {
                          return tr(
                            'Exceeds available stock',
                            'လက်ကျန်ထက်များနေသည်',
                          );
                        }
                        return null;
                      },
                    ),
                    TextFormField(
                      controller: note,
                      maxLength: 500,
                      decoration: InputDecoration(
                        labelText: tr(
                          'Note (optional)',
                          'မှတ်ချက် (မဖြစ်မနေ မဟုတ်)',
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: transport,
                      maxLength: 500,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: tr(
                          'Transportation info (optional)',
                          'ပို့ဆောင်ရေးအချက်အလက် (မဖြစ်မနေ မဟုတ်)',
                        ),
                        hintText: tr(
                          'Vehicle, driver, tracking number',
                          'ယာဉ်၊ ယာဉ်မောင်း၊ ပို့ဆောင်ရေးအမှတ်',
                        ),
                      ),
                    ),
                    DesktopListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${tr('Transfer date', 'လွှဲသည့်ရက်')}: ${dateText(transferDate)}',
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: saving
                          ? null
                          : () async {
                              final chosen = await showDatePicker(
                                context: dialogContext,
                                initialDate:
                                    transferDate.isAfter(AppDateTime.today())
                                    ? AppDateTime.today()
                                    : transferDate,
                                firstDate: DateTime(2000),
                                lastDate: AppDateTime.today(),
                              );
                              if (chosen != null && dialogContext.mounted) {
                                update(() => transferDate = chosen);
                              }
                            },
                    ),
                    if (photo != null)
                      InkWell(
                        onTap: () => showDialog<void>(
                          context: dialogContext,
                          builder: (photoDialog) => Dialog(
                            child: InteractiveViewer(
                              child: Image.memory(photo!),
                            ),
                          ),
                        ),
                        child: Image.memory(
                          photo!,
                          height: 90,
                          fit: BoxFit.contain,
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: saving
                              ? null
                              : () async {
                                  try {
                                    final picked = await pickPhoto(
                                      dialogContext,
                                    );
                                    if (picked != null &&
                                        dialogContext.mounted) {
                                      update(() {
                                        photo = picked;
                                        photoChanged = true;
                                      });
                                    }
                                  } catch (e) {
                                    if (dialogContext.mounted) {
                                      ScaffoldMessenger.of(dialogContext)
                                          .showSnackBar(
                                            SnackBar(content: Text('$e')),
                                          );
                                    }
                                  }
                                },
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(
                            tr('Camera / Gallery photo', 'ကင်မရာ / ပုံရွေးရန်'),
                          ),
                        ),
                        if (photo != null)
                          TextButton(
                            onPressed: saving
                                ? null
                                : () => update(() {
                                    photo = null;
                                    photoChanged = true;
                                  }),
                            child: Text(tr('Remove photo', 'ပုံဖယ်ရန်')),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: Text(tr('Cancel', 'မလုပ်တော့')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (!key.currentState!.validate() ||
                            product == null ||
                            destination == null) {
                          return;
                        }
                        update(() => saving = true);
                        try {
                          if (editing == null) {
                            await AppDatabase.instance.postStockTransfer(
                              sourceBranchId: sourceBranch,
                              destinationBranchId: destination!,
                              productId: product!,
                              quantity: int.parse(quantity.text.trim()),
                              note: note.text,
                              transportInfo: transport.text,
                              transferDate: dateText(transferDate),
                              photo: photo,
                            );
                          } else {
                            await AppDatabase.instance.editStockTransfer(
                              id: editing['id'] as int,
                              destinationBranchId: destination!,
                              productId: product!,
                              quantity: int.parse(quantity.text.trim()),
                              note: note.text,
                              transportInfo: transport.text,
                              transferDate: dateText(transferDate),
                              photo: photo,
                              photoChanged: photoChanged,
                            );
                          }
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            update(() => saving = false);
                            ScaffoldMessenger.of(dialogContext)
                                .showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                child: Text(
                  editing == null
                      ? tr('Transfer', 'လွှဲရန်')
                      : tr('Save', 'သိမ်းရန်'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Controllers are intentionally left to Flutter's widget teardown; disposing
    // immediately after a dialog pop can race its exit animation.
    if (result == true) await load();
  }

  Future<void> voidTransfer(Map<String, Object?> transfer) async {
    final reason = TextEditingController();
    bool saving = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !saving,
          child: DesktopDialog(
            title: Text(
              tr('Void stock transfer?', 'ပစ္စည်းလွှဲမှု ပယ်ဖျက်မလား?'),
            ),
            content: TextField(
              controller: reason,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: tr('Reason', 'အကြောင်းပြချက်'),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: Text(tr('Cancel', 'မလုပ်တော့')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        if (reason.text.trim().isEmpty) return;
                        update(() => saving = true);
                        try {
                          await AppDatabase.instance.voidStockTransfer(
                            id: transfer['id'] as int,
                            reason: reason.text,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            update(() => saving = false);
                            ScaffoldMessenger.of(dialogContext)
                                .showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                child: Text(tr('Void', 'ပယ်ဖျက်ရန်')),
              ),
            ],
          ),
        ),
      ),
    );
    if (result == true) await load();
  }

  Future<void> receive(Map<String, Object?> transfer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => DesktopDialog(
        title: Text(tr('Receive stock?', 'ပစ္စည်းလက်ခံမလား?')),
        content: Text(
          '${transfer['source_name']} → ${transfer['destination_name']}\n'
          '${transfer['item_code']} · ${transfer['product_name']} × ${transfer['quantity']}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('Cancel', 'မလုပ်တော့')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('Receive', 'လက်ခံရန်')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || branchId == null) return;
    try {
      await AppDatabase.instance.receiveStockTransfer(
        id: transfer['id'] as int,
        branchId: branchId!,
      );
      await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  bool isPending(Map<String, Object?> row) =>
      row['status'] == 'posted' &&
      row['receive_required'] == 1 &&
      row['received_at'] == null;

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    floatingActionButton: null,
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : error != null
        ? Center(child: Text(error!))
        : Column(
            children: [
              if (branches.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: DropdownButtonFormField<int>(
                    initialValue: branchId,
                    decoration: InputDecoration(
                      labelText: tr('Branch', 'ဆိုင်ခွဲ'),
                    ),
                    items: branches
                        .map(
                          (b) => DropdownMenuItem(
                            value: b['id'] as int,
                            child: Text(b['name'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() {
                        branchId = v;
                        loading = true;
                      });
                      load();
                    },
                  ),
                ),
              if (branches.length < 2)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    tr(
                      'Add another branch to transfer stock.',
                      'ပစ္စည်းလွှဲရန် နောက်ထပ် ဆိုင်ခွဲတစ်ခု လိုအပ်ပါသည်။',
                    ),
                  ),
                ),
              if (transfers.any(
                (row) =>
                    isPending(row) && row['destination_branch_id'] == branchId,
              ))
                Card(
                  child: DesktopListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text(
                      '${transfers.where((row) => isPending(row) && row['destination_branch_id'] == branchId).length} '
                      '${tr('incoming transfer(s)', 'ဝင်လာမည့် ပစ္စည်းလွှဲမှု')}',
                    ),
                    subtitle: Text(
                      tr(
                        'Tap Receive to add stock to this branch.',
                        'ဤဆိုင်ခွဲ stock ထဲဝင်ရန် Receive နှိပ်ပါ။',
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: transfers.isEmpty
                    ? Center(
                        child: Text(
                          tr(
                            'No stock transfers yet',
                            'လွှဲထားသောပစ္စည်း မရှိသေးပါ',
                          ),
                        ),
                      )
                    : DesktopListView.builder(
                        desktopColumns: const [
                          "Item code",
                          "Item Name",
                          "From",
                          "To",
                          "Quantity",
                          "Date",
                          "Status",
                        ],
                        desktopCells: (context, index) {
                          final r = transfers[index];
                          return [
                            desktopCellText(r['item_code']),
                            desktopCellText(r['product_name']),
                            desktopCellText(r['source_name']),
                            desktopCellText(r['destination_name']),
                            desktopCellText(r['quantity']),
                            desktopCellText(r['transfer_date']),
                            desktopCellText(r['status']),
                          ];
                        },

                        itemCount: transfers.length,
                        itemBuilder: (context, i) {
                          final row = transfers[i];
                          return Card(
                            child: DesktopListTile(
                              title: Text(
                                '${row['item_code']} · ${row['product_name']}  × ${row['quantity']}',
                              ),
                              subtitle: Text(
                                '${row['source_name']} → ${row['destination_name']}\n'
                                '${tr('Transfer date', 'လွှဲသည့်ရက်')}: '
                                '${(row['transfer_date'] as String).isEmpty ? AppDateTime.format(row['created_at']).split(' ').first : row['transfer_date']} · ${AppDateTime.format(row['created_at'])}'
                                '${row['status'] == 'void' ? ' · VOID' : ''}'
                                '${isPending(row) ? ' · ${tr('Pending receipt', 'လက်ခံရန်စောင့်နေ')}' : ''}'
                                '${row['received_at'] != null && row['receive_required'] == 1 ? '\n${tr('Received', 'လက်ခံပြီး')}: ${AppDateTime.format(row['received_at'])}' : ''}'
                                '${(row['note'] as String).isEmpty ? '' : '\n${row['note']}'}'
                                '${(row['transport_info'] as String).isEmpty ? '' : '\n${tr('Transport', 'ပို့ဆောင်ရေး')}: ${row['transport_info']}'}'
                                '${row['status'] == 'void' ? '\n${row['void_reason']}' : ''}',
                              ),
                              isThreeLine: true,
                              onTap: () async {
                                final photo = await AppDatabase.instance
                                    .getStockTransferPhoto(row['id'] as int);
                                if (!context.mounted) return;
                                if (photo == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr(
                                          'No photo attached',
                                          'တွဲထားသောပုံ မရှိပါ',
                                        ),
                                      ),
                                    ),
                                  );
                                } else {
                                  await showDialog<void>(
                                    context: context,
                                    builder: (photoDialog) => Dialog(
                                      child: InteractiveViewer(
                                        child: Image.memory(photo),
                                      ),
                                    ),
                                  );
                                }
                              },
                              trailing: row['status'] == 'posted'
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isPending(row) &&
                                            row['destination_branch_id'] ==
                                                branchId)
                                          IconButton(
                                            tooltip: tr(
                                              'Receive stock',
                                              'ပစ္စည်းလက်ခံရန်',
                                            ),
                                            icon: const Icon(
                                              Icons.move_to_inbox_outlined,
                                            ),
                                            onPressed: () => receive(row),
                                          ),
                                        PopupMenuButton<String>(
                                          onSelected: (action) async {
                                            if (action == 'receive') {
                                              receive(row);
                                            }
                                            if (action == 'edit' &&
                                                isPending(row)) {
                                              create(editing: row);
                                            }
                                            if (action == 'void') {
                                              voidTransfer(row);
                                            }
                                            if (action == 'delete') {
                                              final ok =
                                                  await deleteVoucherWithPrompt(
                                                    context,
                                                    kind: 'transfer',
                                                    id: row['id'] as int,
                                                    number: 'TRF-${row['id']}',
                                                  );
                                              if (ok && mounted) await load();
                                            }
                                          },
                                          itemBuilder: (_) => [
                                            PopupMenuItem(
                                              value: 'edit',
                                              enabled: isPending(row),
                                              child: Text(
                                                tr(
                                                  'Edit / attach photo',
                                                  'ပြန်ပြင်ရန် / ပုံတွဲရန်',
                                                ),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'void',
                                              child: Text(
                                                tr('Void', 'ပယ်ဖျက်ရန်'),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Text(
                                                tr(
                                                  'Delete permanently',
                                                  'အပြီးတိုင်ဖျက်ရန်',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    )
                                  : IconButton(
                                      tooltip: tr(
                                        'Delete permanently',
                                        'အပြီးတိုင်ဖျက်ရန်',
                                      ),
                                      icon: const Icon(
                                        Icons.delete_forever_outlined,
                                      ),
                                      onPressed: () async {
                                        final ok =
                                            await deleteVoucherWithPrompt(
                                              context,
                                              kind: 'transfer',
                                              id: row['id'] as int,
                                              number: 'TRF-${row['id']}',
                                            );
                                        if (ok && mounted) await load();
                                      },
                                    ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
  );
}

class StockTransferPage extends StatelessWidget {
  const StockTransferPage({super.key, this.initialBranchId});
  final int? initialBranchId;
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        TabBar(
          tabs: [
            Tab(
              text: AppLanguage.current.value == 'my'
                  ? 'ဘောင်ချာအသစ်'
                  : 'Transfer vouchers',
            ),
            Tab(
              text: AppLanguage.current.value == 'my'
                  ? 'ယခင်တစ်မျိုးချင်း'
                  : 'Legacy transfers',
            ),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              TransferVouchersPage(initialBranchId: initialBranchId),
              LegacyStockTransferPage(initialBranchId: initialBranchId),
            ],
          ),
        ),
      ],
    ),
  );
}
