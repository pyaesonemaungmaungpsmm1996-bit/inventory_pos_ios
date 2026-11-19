import 'history_date_filter.dart';
import 'desktop_ui.dart';
import 'app_capabilities.dart';
import 'invoice_printer_page.dart';
import 'amount_input.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_currency.dart';
import 'app_database.dart';
import 'categories_page.dart';
import 'app_datetime.dart';
import 'app_language.dart';
import 'expense_receipt_photo.dart';
import 'invoice_void_dialog.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

const _receiptPickerTarget = 'expense_receipt_picker_target_v1';

Future<Uint8List?> _chooseReceiptPhoto(BuildContext context, int target) async {
  final source = await showDesktopSheet<ImageSource>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (AppCapabilities.camera)
            DesktopListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(_t('Camera', 'ကင်မရာ')),
              onTap: () => Navigator.pop(sheet, ImageSource.camera),
            ),
          DesktopListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(_t('Gallery', 'ဓာတ်ပုံများ')),
            onTap: () => Navigator.pop(sheet, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null || !context.mounted) return null;
  final prefs = SharedPreferencesAsync();
  await prefs.setInt(_receiptPickerTarget, target);
  try {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2200,
      maxHeight: 2200,
      imageQuality: 90,
      requestFullMetadata: false,
    );
    if (picked == null) return null;
    if (await picked.length() > 12000000) {
      throw const FormatException('Photo too large');
    }
    return await prepareExpenseReceiptPhoto(await picked.readAsBytes());
  } finally {
    await prefs.remove(_receiptPickerTarget);
  }
}

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({
    super.key,
    this.initialBranchId,
    this.historyOnly = false,
  });
  final bool historyOnly;
  final int? initialBranchId;
  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  List<Map<String, Object?>> branches = [],
      accounts = [],
      expenses = [],
      categories = [];
  int? branchId;
  bool loading = true, busy = false;
  String? error;
  int ticket = 0;
  Uint8List? recoveredPhoto;

  DateTime? historyFrom, historyTo;
  String? historyCategory;
  int? historyAccount;
  String historyStatus = 'all', historySearch = '';
  List<Map<String, Object?>> get historyRows => expenses
      .where(
        (r) =>
            HistoryDates.includes(r['expense_date'], historyFrom, historyTo) &&
            (historyCategory == null || r['category'] == historyCategory) &&
            (historyStatus == 'all' || r['status'] == historyStatus) &&
            (historyAccount == null ||
                ',${r['payment_account_ids'] ?? r['account_id']},'.contains(
                  ',$historyAccount,',
                )) &&
            (historySearch.trim().isEmpty ||
                'EXP-${r['id']} EXP-${r['id'].toString().padLeft(6, '0')} ${r['category']} ${r['note']} ${r['payment_account_names'] ?? r['account_name']}'
                    .toLowerCase()
                    .contains(historySearch.trim().toLowerCase())),
      )
      .toList();

  Widget historyFilters() {
    final names = {
      for (final r in expenses) '${r['category']}',
      ?historyCategory,
    }.toList()..sort();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          HistoryDateFilter(
            from: historyFrom,
            to: historyTo,
            onChanged: (from, to) => setState(() {
              historyFrom = from;
              historyTo = to;
            }),
          ),
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey('expense-category-$branchId-$historyCategory'),
              initialValue: historyCategory,
              decoration: InputDecoration(
                labelText: _t('Category', 'အမျိုးအစား'),
              ),
              items: [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text(_t('All categories', 'အမျိုးအစားအားလုံး')),
                ),
                for (final name in names)
                  DropdownMenuItem(value: name, child: Text(name)),
              ],
              onChanged: (v) => setState(() => historyCategory = v),
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<int>(
              isExpanded: true,
              key: ValueKey('expense-account-$branchId-$historyAccount'),
              initialValue: historyAccount,
              decoration: InputDecoration(
                labelText: _t('Payment account', 'ငွေစာရင်း'),
              ),
              items: [
                DropdownMenuItem<int>(
                  value: null,
                  child: Text(_t('All accounts', 'ငွေစာရင်းအားလုံး')),
                ),
                for (final a in accounts)
                  DropdownMenuItem(
                    value: a['id'] as int,
                    child: Text('${a['name']}'),
                  ),
              ],
              onChanged: (v) => setState(() => historyAccount = v),
            ),
          ),
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              key: const ValueKey('expense-history-status'),
              initialValue: historyStatus,
              decoration: InputDecoration(labelText: _t('Status', 'အခြေအနေ')),
              items: [
                for (final v in ['all', 'posted', 'void'])
                  DropdownMenuItem(value: v, child: Text(v)),
              ],
              onChanged: (v) => setState(() => historyStatus = v!),
            ),
          ),
          SizedBox(
            width: 280,
            child: TextField(
              key: const ValueKey('expense-history-search'),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: _t(
                  'Expense / category / note / account',
                  'အသုံးစရိတ် / အမျိုးအစား / မှတ်ချက် / ငွေစာရင်း',
                ),
              ),
              onChanged: (v) => setState(() => historySearch = v),
            ),
          ),
          OutlinedButton.icon(
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
            label: Text(_t('Refresh', 'ပြန်ဖတ်မည်')),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    branchId = widget.initialBranchId;
    load();
    recoverPickedPhoto();
  }

  Future<void> recoverPickedPhoto() async {
    if (AppCapabilities.windows) return;
    try {
      final prefs = SharedPreferencesAsync();
      final target = await prefs.getInt(_receiptPickerTarget);
      if (target == null) return;
      final response = await ImagePicker().retrieveLostData();
      await prefs.remove(_receiptPickerTarget);
      if (response.files == null || response.files!.isEmpty) return;
      final file = response.files!.first;
      if (await file.length() > 12000000) return;
      final bytes = await prepareExpenseReceiptPhoto(await file.readAsBytes());
      if (target == 0) {
        if (mounted) setState(() => recoveredPhoto = bytes);
      } else {
        await AppDatabase.instance.saveExpenseReceiptPhoto(
          expenseId: target,
          photo: bytes,
        );
        if (mounted) await load();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              target == 0
                  ? _t(
                      'Receipt photo recovered. Open New Expense to save it.',
                      'ဘောင်ချာပုံ ပြန်ရပါပြီ။ Expense အသစ်ဖွင့်၍ သိမ်းပါ။',
                    )
                  : _t(
                      'Receipt photo restored to expense.',
                      'ဘောင်ချာပုံကို Expense နှင့် ပြန်တွဲပြီးပါပြီ။',
                    ),
            ),
          ),
        );
      }
    } catch (_) {
      // Failed picker recovery must never affect saved expenses.
    }
  }

  Future<void> load() async {
    final request = ++ticket;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final db = AppDatabase.instance;
      final allBranches = await db.getBranches();
      final preferred = branchId ?? await db.getDefaultBranchId();
      final selected = allBranches.any((b) => b['id'] == preferred)
          ? preferred
          : (allBranches.isEmpty ? null : allBranches.first['id'] as int);
      final money = selected == null
          ? <Map<String, Object?>>[]
          : await db.getMoneyAccounts(branchId: selected);
      final rows = selected == null
          ? <Map<String, Object?>>[]
          : await db.getExpenses(branchId: selected);
      final types = selected == null
          ? <Map<String, Object?>>[]
          : await db.getExpenseCategories(branchId: selected);
      if (!mounted || ticket != request) return;
      setState(() {
        branches = allBranches;
        branchId = selected;
        accounts = money;
        expenses = rows;
        categories = types;
        loading = false;
      });
    } catch (_) {
      if (!mounted || ticket != request) return;
      setState(() {
        loading = false;
        error = _t(
          'Could not load expenses. Retry.',
          'အသုံးစရိတ်များ မဖတ်နိုင်ပါ။ ပြန်စမ်းပါ။',
        );
      });
    }
  }

  Future<void> add() async {
    final active = categories.where((c) => c['active'] == 1).toList();
    if (busy || branchId == null || accounts.isEmpty || active.isEmpty) return;
    setState(() => busy = true);
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ExpenseForm(
          branchId: branchId!,
          accounts: accounts,
          categories: active,
          recoveredPhoto: recoveredPhoto,
        ),
      );
      if (saved == true && mounted) {
        recoveredPhoto = null;
        await load();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editEntry(Map<String, Object?> row) async {
    if (busy || row['status'] != 'posted' || branchId == null) return;
    setState(() => busy = true);
    try {
      final photo = await AppDatabase.instance.getExpenseReceiptPhoto(
        row['id'] as int,
      );
      final payments = await AppDatabase.instance.getExpensePayments(
        row['id'] as int,
      );
      if (!mounted) return;
      final choices = categories
          .where((c) => c['active'] == 1 || c['name'] == row['category'])
          .toList();
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ExpenseForm(
          branchId: branchId!,
          accounts: accounts,
          categories: choices,
          expense: row,
          existingPhoto: photo,
          savedPayments: payments,
        ),
      );
      if (saved == true && mounted) await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Could not open expense for editing.',
                'အသုံးစရိတ် ပြင်ရန် မဖွင့်နိုင်ပါ။',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showHistory(int id) async {
    try {
      final rows = await AppDatabase.instance.getExpenseEdits(id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => DesktopDialog(
          title: Text(
            _t('Expense edit history', 'အသုံးစရိတ် ပြင်ဆင်မှုမှတ်တမ်း'),
          ),
          content: SizedBox(
            width: 440,
            height: 380,
            child: rows.isEmpty
                ? Center(
                    child: Text(_t('No edits yet', 'ပြင်ဆင်မှု မရှိသေးပါ')),
                  )
                : DesktopListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      final h = rows[index];
                      return DesktopListTile(
                        title: Text(
                          '${AppDateTime.format(h['changed_at'])} · '
                          '${AppCurrency.format(h['previous_amount'] as int)} → '
                          '${AppCurrency.format(h['amount'] as int)}',
                        ),
                        subtitle: Text(
                          '${h['previous_category']} → ${h['category']}\n'
                          '${_t('Payment allocations', 'ငွေရှင်းခွဲဝေမှု')}: '
                          '${(h['previous_payments'] as String).isEmpty ? h['previous_account_id'] : h['previous_payments']}'
                          ' → ${(h['payments'] as String).isEmpty ? h['account_id'] : h['payments']}\n'
                          '${h['previous_note']} → ${h['note']}\n'
                          '${h['previous_expense_date']} → ${h['expense_date']} · '
                          '${_t('Receipt', 'ဘောင်ချာပုံ')}: ${h['receipt_action']}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(_t('Close', 'ပိတ်မည်')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Could not load edit history.',
                'ပြင်ဆင်မှုမှတ်တမ်း မဖတ်နိုင်ပါ။',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> showReceipt(Map<String, Object?> row) async {
    try {
      final id = row['id'] as int;
      final bytes = await AppDatabase.instance.getExpenseReceiptPhoto(id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => DesktopDialog(
          title: Text(_t('Expense receipt', 'အသုံးစရိတ်ဘောင်ချာ')),
          content: SizedBox(
            width: 420,
            height: 500,
            child: bytes == null
                ? Center(
                    child: Text(
                      _t('No photo attached yet.', 'ဘောင်ချာပုံ မတွဲရသေးပါ။'),
                    ),
                  )
                : InteractiveViewer(
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
          ),
          actions: [
            if (row['status'] == 'posted')
              TextButton.icon(
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(_t('Add / replace photo', 'ပုံထည့် / ပြန်ရွေးရန်')),
                onPressed: () async {
                  try {
                    final photo = await _chooseReceiptPhoto(dialog, id);
                    if (photo == null) return;
                    await AppDatabase.instance.saveExpenseReceiptPhoto(
                      expenseId: id,
                      photo: photo,
                    );
                    if (dialog.mounted) Navigator.pop(dialog);
                    if (mounted) await load();
                  } catch (_) {
                    if (dialog.mounted) {
                      ScaffoldMessenger.of(dialog).showSnackBar(
                        SnackBar(
                          content: Text(
                            _t(
                              'Could not save photo. Try a clear image under 12 MB.',
                              'ပုံမသိမ်းနိုင်ပါ။ 12 MB အောက် ကြည်လင်သောပုံ ပြန်ရွေးပါ။',
                            ),
                          ),
                        ),
                      );
                    }
                  }
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(_t('Close', 'ပိတ်မည်')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t('Could not open receipt photo.', 'ဘောင်ချာပုံ မဖွင့်နိုင်ပါ။'),
            ),
          ),
        );
      }
    }
  }

  Future<void> manageCategories() async {
    if (busy || branchId == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DesktopScaffold(
          appBar: AppBar(title: Text(_t('Categories', 'အမျိုးအစားများ'))),
          body: CategoriesPage(
            initialKind: 'expense',
            initialBranchId: branchId,
          ),
        ),
      ),
    );
    if (mounted) await load();
  }

  Future<void> voidEntry(Map<String, Object?> row) async {
    if (busy || row['status'] != 'posted') return;
    final reason = TextEditingController();
    final answer = await showDialog<String>(
      context: context,
      builder: (dialog) => DesktopDialog(
        title: Text(_t('Void expense', 'အသုံးစရိတ် ပယ်ဖျက်ရန်')),
        content: TextField(
          controller: reason,
          maxLength: 300,
          decoration: InputDecoration(
            labelText: _t('Reason', 'ပယ်ဖျက်ရသည့်အကြောင်းရင်း'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, reason.text.trim()),
            child: Text(
              _t('Void and refund account', 'ပယ်ဖျက်ပြီး ငွေပြန်ထည့်မည်'),
            ),
          ),
        ],
      ),
    );
    reason.dispose();
    if (!mounted || answer == null || answer.isEmpty) return;
    setState(() => busy = true);
    try {
      await AppDatabase.instance.voidExpense(
        id: row['id'] as int,
        reason: answer,
      );
      if (mounted) await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Could not void expense. Reload and retry.',
                'အသုံးစရိတ် မပယ်ဖျက်နိုင်ပါ။ ပြန်ဖတ်ပြီး စမ်းပါ။',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.historyOnly ? historyRows : expenses;
    return DesktopScaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButton<int>(
              value: branches.any((b) => b['id'] == branchId) ? branchId : null,
              isExpanded: true,
              hint: Text(_t('Select branch', 'ဆိုင်ခွဲရွေးပါ')),
              items: branches
                  .map(
                    (b) => DropdownMenuItem<int>(
                      value: b['id'] as int,
                      child: Text('${b['name']} (${b['code']})'),
                    ),
                  )
                  .toList(),
              onChanged: loading || busy
                  ? null
                  : (id) {
                      if (id != null && id != branchId) {
                        setState(() {
                          branchId = id;
                          historyCategory = null;
                          historyAccount = null;
                        });
                        load();
                      }
                    },
            ),
          ),
          if (widget.historyOnly)
            if (AppCapabilities.windows)
              historyFilters()
            else
              ExpansionTile(
                key: const ValueKey('mobile-expense-filters'),
                title: Text(_t('Filters', 'စစ်ထုတ်ရန်')),
                children: [
                  SizedBox(
                    height: 220,
                    child: SingleChildScrollView(child: historyFilters()),
                  ),
                ],
              ),
          if (!widget.historyOnly &&
              !loading &&
              error == null &&
              branchId != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: TextButton.icon(
                  onPressed: busy ? null : manageCategories,
                  icon: const Icon(Icons.category_outlined),
                  label: Text(
                    _t('Manage Categories', 'အသုံးစရိတ်အမျိုးအစား သတ်မှတ်ရန်'),
                  ),
                ),
              ),
            ),
          if (!widget.historyOnly &&
              !loading &&
              branchId != null &&
              categories.every((c) => c['active'] != 1))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _t(
                  'Add a category before recording an expense.',
                  'အသုံးစရိတ်မသွင်းမီ အမျိုးအစားတစ်ခု ထည့်ပါ။',
                ),
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: TextButton(onPressed: load, child: Text(error!)),
                  )
                : branchId == null
                ? Center(
                    child: Text(
                      _t('Add a branch first.', 'ဆိုင်ခွဲအရင်ထည့်ပါ။'),
                    ),
                  )
                : visible.isEmpty
                ? Center(
                    child: Text(
                      _t(
                        widget.historyOnly
                            ? 'No matching expenses.'
                            : 'No expenses yet. Tap + to add one.',
                        widget.historyOnly
                            ? 'ကိုက်ညီသော အသုံးစရိတ်မှတ်တမ်း မရှိပါ။'
                            : 'အသုံးစရိတ် မရှိသေးပါ။ အသစ်ထည့်ရန် + နှိပ်ပါ။',
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: load,
                    child: DesktopListView.builder(
                      desktopColumns: const [
                        "Expense No.",
                        "Date",
                        "Category",
                        "Note",
                        "Payment account",
                        "Amount",
                        "Status",
                      ],
                      desktopCells: (context, index) {
                        final r = visible[index];
                        return [
                          desktopCellText('EXP-${r['id']}'),
                          desktopCellText(r['expense_date']),
                          desktopCellText(r['category']),
                          desktopCellText(r['note']),
                          desktopCellText(
                            r['payment_count'] == 1
                                ? r['account_name']
                                : '${r['payment_count']} accounts',
                          ),
                          desktopMoney(r['amount']),
                          desktopCellText(r['status']),
                        ];
                      },

                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final row = visible[index];
                        final isVoid = row['status'] == 'void';
                        final paymentLabel = row['payment_count'] == 1
                            ? row['account_name'] as String
                            : '${row['payment_count']} ${_t('accounts', 'အကောင့်')}';
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          child: DesktopListTile(
                            onTap: isVoid
                                ? () => showReceipt(row)
                                : () => editEntry(row),
                            title: Text(
                              '${row['category']} · ${AppCurrency.format(row['amount'] as int)}',
                            ),
                            subtitle: Text(
                              '${row['expense_date']} · $paymentLabel\n'
                              '${_t('Recorded', 'မှတ်တမ်းတင်ချိန်')}: ${AppDateTime.format(row['posted_at'])}'
                              '${isVoid ? '\n${_t('Void', 'ပယ်ဖျက်ပြီး')}: ${row['void_reason']}' : ''}'
                              '${(row['note'] as String).isEmpty ? '' : '\n${row['note']}'}',
                            ),
                            isThreeLine: true,
                            leading: row['has_receipt'] == 1
                                ? const Icon(Icons.receipt_long_outlined)
                                : const Icon(Icons.receipt_outlined),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) async {
                                if (action == 'edit') editEntry(row);
                                if (action == 'photo') showReceipt(row);
                                if (action == 'history') {
                                  showHistory(row['id'] as int);
                                }
                                if (action == 'print') {
                                  await Navigator.push<void>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => InvoicePrintPage(
                                        saleId: row['id'] as int,
                                        expense: true,
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                if (action == 'void') voidEntry(row);
                                if (action == 'delete') {
                                  final ok = await deleteVoucherWithPrompt(
                                    context,
                                    kind: 'expense',
                                    id: row['id'] as int,
                                    number: 'EXP-${row['id']}',
                                  );
                                  if (ok && mounted) await load();
                                }
                              },
                              itemBuilder: (context) => [
                                if (!isVoid)
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text(_t('Edit', 'ပြင်ရန်')),
                                  ),
                                PopupMenuItem(
                                  value: 'print',
                                  child: Text(_t('Print / PDF', 'Print / PDF')),
                                ),
                                PopupMenuItem(
                                  value: 'photo',
                                  child: Text(
                                    _t('Receipt photo', 'ဘောင်ချာပုံ'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'history',
                                  child: Text(
                                    _t('Edit history', 'ပြင်ဆင်မှုမှတ်တမ်း'),
                                  ),
                                ),
                                if (!isVoid)
                                  PopupMenuItem(
                                    value: 'void',
                                    child: Text(_t('Void', 'ပယ်ဖျက်ရန်')),
                                  ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text(
                                    _t(
                                      'Delete permanently',
                                      'အပြီးတိုင်ဖျက်ရန်',
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
          ),
        ],
      ),
      floatingActionButton: widget.historyOnly
          ? null
          : FloatingActionButton(
              onPressed:
                  loading ||
                      busy ||
                      branchId == null ||
                      accounts.isEmpty ||
                      categories.every((c) => c['active'] != 1)
                  ? null
                  : add,
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({
    required this.branchId,
    required this.accounts,
    required this.categories,
    this.recoveredPhoto,
    this.expense,
    this.existingPhoto,
    this.savedPayments = const [],
  });
  final int branchId;
  final List<Map<String, Object?>> accounts, categories;
  final List<Map<String, Object?>> savedPayments;
  final Uint8List? recoveredPhoto, existingPhoto;
  final Map<String, Object?>? expense;
  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpensePaymentInput {
  _ExpensePaymentInput(this.accountId, String value)
    : amount = TextEditingController(text: value);
  int accountId;
  final TextEditingController amount;
  void dispose() => amount.dispose();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(), note = TextEditingController();
  final payments = <_ExpensePaymentInput>[];
  final retiredPayments = <_ExpensePaymentInput>[];
  bool autoSinglePayment = true;
  late int categoryId;
  late DateTime date;
  Uint8List? photo;
  bool photoChanged = false;
  bool saving = false;
  bool unlocked = true;
  String? error;

  @override
  void initState() {
    super.initState();
    final old = widget.expense;
    unlocked = old == null;
    if (widget.savedPayments.isEmpty) {
      payments.add(
        _ExpensePaymentInput(widget.accounts.first['id'] as int, ''),
      );
    } else {
      for (final payment in widget.savedPayments) {
        payments.add(
          _ExpensePaymentInput(
            payment['account_id'] as int,
            AppCurrency.input(payment['amount'] as int),
          ),
        );
      }
    }
    autoSinglePayment = payments.length == 1;
    categoryId =
        widget.categories.firstWhere(
              (c) => c['name'] == old?['category'],
              orElse: () => widget.categories.first,
            )['id']
            as int;
    date = old == null
        ? AppDateTime.today()
        : DateTime.parse(old['expense_date'] as String);
    amount.text = old == null ? '' : AppCurrency.input(old['amount'] as int);
    note.text = old?['note'] as String? ?? '';
    photo = widget.existingPhoto ?? widget.recoveredPhoto;
    amount.addListener(_syncSinglePayment);
  }

  @override
  void dispose() {
    amount.removeListener(_syncSinglePayment);
    amount.dispose();
    note.dispose();
    for (final payment in payments) {
      payment.dispose();
    }
    for (final payment in retiredPayments) {
      payment.dispose();
    }
    super.dispose();
  }

  void _syncSinglePayment() {
    if (autoSinglePayment && payments.length == 1) {
      payments.first.amount.text = amount.text;
    }
    if (mounted) setState(() {});
  }

  void addPayment() {
    final used = payments.map((p) => p.accountId).toSet();
    final available = widget.accounts
        .where((a) => !used.contains(a['id']))
        .toList();
    if (available.isEmpty) return;
    setState(() {
      autoSinglePayment = false;
      payments.add(_ExpensePaymentInput(available.first['id'] as int, ''));
    });
  }

  List<Map<String, int>> paymentValues() => [
    for (final p in payments)
      {'account_id': p.accountId, 'amount': AppCurrency.parse(p.amount.text)},
  ];

  Future<void> choosePhoto() async {
    try {
      final bytes = await _chooseReceiptPhoto(context, 0);
      if (bytes != null && mounted) {
        setState(() {
          photo = bytes;
          photoChanged = true;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = _t(
            'Could not open photo. Choose a clear photo under 12 MB.',
            'ပုံမဖွင့်နိုင်ပါ။ 12 MB အောက် ကြည်လင်သောပုံ ရွေးပါ။',
          ),
        );
      }
    }
  }

  Future<void> save() async {
    if (saving || !unlocked || !form.currentState!.validate()) return;
    final total = AppCurrency.tryParse(amount.text);
    final values = paymentValues();
    if (total == null ||
        values.map((p) => p['account_id']).toSet().length != values.length ||
        values.fold<int>(0, (sum, p) => sum + p['amount']!) != total) {
      setState(
        () => error = _t(
          'Payment amounts must add up to the expense total; choose each account once.',
          'ငွေရှင်းပမာဏများပေါင်းခြင်းသည် Expense စုစုပေါင်းနှင့် တူရမည်။ အကောင့်တစ်ခု တစ်ကြိမ်သာရွေးပါ။',
        ),
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      if (widget.expense == null) {
        await AppDatabase.instance.postExpense(
          branchId: widget.branchId,
          payments: values,
          categoryId: categoryId,
          amount: AppCurrency.parse(amount.text),
          expenseDate: _date(date),
          note: note.text,
          receiptPhoto: photo,
        );
      } else {
        await AppDatabase.instance.editExpense(
          id: widget.expense!['id'] as int,
          expectedRevision: widget.expense!['revision'] as int,
          payments: values,
          categoryId: categoryId,
          amount: AppCurrency.parse(amount.text),
          expenseDate: _date(date),
          note: note.text,
          receiptPhoto: photoChanged ? photo : null,
          removeReceipt: photoChanged && photo == null,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is StateError
              ? _t(
                  'Insufficient balance or account changed. Retry.',
                  'လက်ကျန်မလုံလောက်ပါ သို့မဟုတ် အကောင့်ပြောင်းထားသည်။',
                )
              : _t(
                  'Could not save expense. Check the details.',
                  'အသုံးစရိတ် မသိမ်းနိုင်ပါ။ အချက်အလက်စစ်ပါ။',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopDialog(
    title: Row(
      children: [
        Expanded(
          child: Text(
            widget.expense == null
                ? _t('New Expense', 'အသုံးစရိတ်အသစ်')
                : _t('Expense voucher', 'အသုံးစရိတ်ဘောင်ချာ'),
          ),
        ),
        if (widget.expense != null)
          IconButton(
            tooltip: _t('Unlock to edit', 'သော့ဖွင့်ပြင်ရန်'),
            onPressed: saving
                ? null
                : () => setState(() => unlocked = !unlocked),
            icon: Icon(unlocked ? Icons.lock_open : Icons.lock_outline),
          ),
      ],
    ),
    content: AbsorbPointer(
      absorbing: !unlocked,
      child: FocusScope(
        canRequestFocus: unlocked,
        child: SizedBox(
          width: 420,
          child: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: categoryId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _t('Category', 'အသုံးစရိတ်အမျိုးအစား'),
                    ),
                    items: widget.categories
                        .map(
                          (c) => DropdownMenuItem<int>(
                            value: c['id'] as int,
                            child: Text(
                              c['name'] as String,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (id) {
                            if (id != null) setState(() => categoryId = id);
                          },
                  ),
                  TextFormField(
                    controller: amount,
                    inputFormatters: const [AmountInputFormatter()],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          '${_t('Amount', 'ငွေပမာဏ')} (${AppCurrency.displayCode})',
                    ),
                    validator: (v) {
                      final n = AppCurrency.tryParse(v ?? '');
                      return n == null || n == 0
                          ? _t(
                              'Enter a positive amount',
                              'သုညထက်ကြီးသော ပမာဏထည့်ပါ',
                            )
                          : null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _t('Pay from accounts', 'ငွေရှင်းမည့်အကောင့်များ'),
                    ),
                  ),
                  for (final payment in payments)
                    Row(
                      key: ValueKey(payment),
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: payment.accountId,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: _t('Account', 'အကောင့်'),
                            ),
                            items: widget.accounts
                                .map(
                                  (a) => DropdownMenuItem<int>(
                                    value: a['id'] as int,
                                    child: Text(
                                      a['name'] as String,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: saving
                                ? null
                                : (id) {
                                    if (id != null) {
                                      setState(() => payment.accountId = id);
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 105,
                          child: TextFormField(
                            controller: payment.amount,
                            inputFormatters: const [AmountInputFormatter()],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: AppCurrency.displayCode,
                            ),
                            onChanged: (_) =>
                                setState(() => autoSinglePayment = false),
                            validator: (v) {
                              final n = AppCurrency.tryParse(v ?? '');
                              return n == null || n == 0
                                  ? _t('Required', 'ဖြည့်ပါ')
                                  : null;
                            },
                          ),
                        ),
                        if (payments.length > 1)
                          IconButton(
                            onPressed: saving
                                ? null
                                : () {
                                    setState(() {
                                      payments.remove(payment);
                                      retiredPayments.add(payment);
                                    });
                                  },
                            icon: const Icon(Icons.remove_circle_outline),
                            tooltip: _t(
                              'Remove payment',
                              'ငွေရှင်းတစ်ခုဖယ်ရန်',
                            ),
                          ),
                      ],
                    ),
                  TextButton.icon(
                    onPressed:
                        saving || payments.length >= widget.accounts.length
                        ? null
                        : addPayment,
                    icon: const Icon(Icons.add),
                    label: Text(
                      _t('Add payment account', 'ငွေရှင်းအကောင့် ထပ်ထည့်ရန်'),
                    ),
                  ),
                  Text(
                    '${_t('Payment total', 'ငွေရှင်းစုစုပေါင်း')}: '
                    '${AppCurrency.format(payments.fold<int>(0, (sum, p) => sum + (AppCurrency.tryParse(p.amount.text) ?? 0)))}',
                  ),
                  DesktopListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${_t('Expense date', 'အသုံးစရိတ်ရက်စွဲ')}: ${_date(date)}',
                    ),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: saving
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: date,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null && mounted) {
                              setState(() => date = picked);
                            }
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: note,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: _t('Description', 'သုံးစွဲရသည့်အကြောင်းအရာ'),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? _t(
                            'Describe what this expense was for.',
                            'သုံးစွဲရသည့်အကြောင်းအရာ ဖြည့်ပါ။',
                          )
                        : null,
                  ),
                  Row(
                    children: [
                      if (photo != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            photo!,
                            width: 64,
                            height: 72,
                            fit: BoxFit.cover,
                          ),
                        ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: saving ? null : choosePhoto,
                          icon: const Icon(Icons.add_a_photo_outlined),
                          label: Text(
                            _t(
                              'Camera / Gallery receipt',
                              'ဘောင်ချာပုံ ရိုက် / ရွေးရန်',
                            ),
                          ),
                        ),
                      ),
                      if (photo != null)
                        IconButton(
                          onPressed: saving
                              ? null
                              : () => setState(() {
                                  photo = null;
                                  photoChanged = true;
                                }),
                          icon: const Icon(Icons.close),
                          tooltip: _t('Remove photo', 'ပုံဖယ်ရန်'),
                        ),
                    ],
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
      ),
      FilledButton(
        onPressed: saving || !unlocked ? null : save,
        child: Text(
          saving
              ? _t('Saving...', 'သိမ်းနေသည်...')
              : widget.expense == null
              ? _t('Save Expense', 'အသုံးစရိတ်သိမ်းမည်')
              : _t('Save Changes', 'ပြင်ဆင်မှုသိမ်းမည်'),
        ),
      ),
    ],
  );
}
