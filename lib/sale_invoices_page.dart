import 'split_payment_dialog.dart';
import 'catalog_search.dart';
import 'product_tracking.dart';
import 'sale_voucher_preview.dart';
import 'portable_preferences.dart';
import 'contact_search.dart';
import 'desktop_ui.dart';
import 'desktop_workspace.dart';
import 'app_capabilities.dart';
import 'invoice_printer_page.dart';
import 'desktop_commands.dart';
import 'pos_ui.dart';
import 'product_details_form.dart';
import 'amount_input.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'app_currency.dart';
import 'app_datetime.dart';
import 'barcode_scan_page.dart';
import 'app_database.dart';
import 'app_language.dart';
import 'sale_confirmation_page.dart';
import 'product_photo.dart';

part 'approved_sale_form.dart';
part 'sale_item_search.dart';

String _t(String en, String my) => AppLanguage.current.value == 'my' ? my : en;
String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _draftNo(int id) => 'DRAFT-${id.toString().padLeft(6, '0')}';
String _itemCode(int id) => 'ITEM-${id.toString().padLeft(6, '0')}';
String _money(int amount) => AppCurrency.format(amount);

Future<Map<String, Object?>?> _pick(
  BuildContext context,
  String title,
  List<Map<String, Object?>> rows,
  String Function(Map<String, Object?>) label, {
  bool productPhotos = false,
}) {
  String search = '';
  return showDialog<Map<String, Object?>>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) {
        final matches = rows
            .where(
              (r) =>
                  label(r)
                      .toLowerCase()
                      .contains(search.toLowerCase().trim()) ||
                  (r.containsKey('phone') && ContactSearch.matches(r, search)),
            )
            .toList();
        return DesktopDialog(
          title: Text(title),
          content: SizedBox(
            width: 500,
            height: 420,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  onChanged: (v) => update(() => search = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: _t('Search', 'ရှာရန်'),
                  ),
                ),
                Expanded(
                  child: matches.isEmpty
                      ? Center(
                          child: Text(
                            _t('No records found.', 'စာရင်းမတွေ့ပါ။'),
                          ),
                        )
                      : DesktopListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (context, i) => DesktopListTile(
                            leading: productPhotos
                                ? ProductPhoto(
                                    key: ValueKey(matches[i]['id']),
                                    productId: matches[i]['id'] as int,
                                    hasImage: matches[i]['has_image'] == 1,
                                  )
                                : null,
                            title: Text(label(matches[i])),
                            onTap: () =>
                                Navigator.pop(dialogContext, matches[i]),
                          ),
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
            ),
          ],
        );
      },
    ),
  );
}

class _DraftResult {
  const _DraftResult(
    this.branchId, {
    this.paymentDraftId,
    this.confirmedSaleId,
    this.startNew = false,
  });
  final int branchId;
  final int? paymentDraftId, confirmedSaleId;
  final bool startNew;
}

class SaleInvoicesPage extends StatefulWidget {
  const SaleInvoicesPage({
    super.key,
    this.resumeKey,
    this.initialDraftId,
    this.initialBranchId,
    this.startNewSale = false,
  });
  final String? resumeKey;
  final int? initialDraftId;
  final int? initialBranchId;
  final bool startNewSale;
  @override
  State<SaleInvoicesPage> createState() => _SaleInvoicesPageState();
}

class _SaleInvoicesPageState extends State<SaleInvoicesPage> {
  List<Map<String, Object?>> branches = [], drafts = [], recoveries = [];
  int? branchId;
  bool loading = true, busy = false;
  String? error;
  int request = 0;
  int previousDesktopMenu = 0;
  @override
  void initState() {
    super.initState();
    if (AppCapabilities.windows) {
      previousDesktopMenu = desktopWorkspaceNavigation.selected;
      desktopWorkspaceNavigation.selected = 1;
      desktopWorkspaceNavigation.selectedSale = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) desktopWorkspaceNavigation.refresh();
      });
    }
    _start();
  }

  @override
  void dispose() {
    if (AppCapabilities.windows && desktopWorkspaceNavigation.selected == 1) {
      desktopWorkspaceNavigation.selected = previousDesktopMenu;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        desktopWorkspaceNavigation.refresh();
      });
    }
    super.dispose();
  }

  Future<void> _start() async {
    branchId = widget.initialBranchId;
    await load();
    if (mounted && error == null && widget.startNewSale) {
      await edit();
      return;
    }
    if (mounted && error == null && widget.initialDraftId != null) {
      await edit(widget.initialDraftId);
      return;
    }
    if (!mounted ||
        error != null ||
        branches.isEmpty ||
        widget.resumeKey == null) {
      return;
    }
    final rows = recoveries
        .where((r) => r['recovery_key'] == widget.resumeKey)
        .toList();
    if (rows.isNotEmpty) {
      await edit(rows.first['source_draft_id'] as int?, true);
    }
  }

  Future<void> load() async {
    final ticket = ++request;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final db = AppDatabase.instance;
      final rows = await db.getBranches();
      final preferred = branchId ?? await db.getDefaultBranchId();
      final chosen = rows.any((b) => b['id'] == preferred)
          ? preferred
          : (rows.isEmpty ? null : rows.first['id'] as int);
      final pending = await db.getSaleRecoveries();
      final invoices = chosen == null
          ? <Map<String, Object?>>[]
          : await db.getSaleDrafts(branchId: chosen);
      if (!mounted || ticket != request) return;
      setState(() {
        branches = rows;
        branchId = chosen;
        drafts = invoices;
        recoveries = pending;
        loading = false;
      });
    } catch (_) {
      if (!mounted || ticket != request) return;
      setState(() {
        loading = false;
        error = _t('Could not load drafts.', 'Draft စာရင်း မဖတ်နိုင်ပါ။');
      });
    }
  }

  Future<void> edit([int? id, bool autoResume = false]) async {
    if (busy || loading || branchId == null) return;
    setState(() => busy = true);
    try {
      final draft = id == null
          ? null
          : await AppDatabase.instance.getSaleDraft(id);
      final key = id == null ? 'new' : 'draft:$id';
      final recovery = await AppDatabase.instance.getSaleRecovery(key);
      Map<String, Object?>? restored;
      if (!mounted) return;
      if (recovery != null) {
        final choice = autoResume
            ? 'resume'
            : await showDialog<String>(
                context: context,
                builder: (c) => DesktopDialog(
                  title: Text(
                    _t(
                      'Resume unfinished invoice?',
                      'ရေးလက်စဘောင်ချာကို ဆက်ရေးမလား?',
                    ),
                  ),
                  content: Text(
                    _t(
                      'Resume auto-saved work, or discard it and open the saved draft / a new invoice.',
                      'Auto-save ထားသောအချက်များ ဆက်သုံးနိုင်ပါသည်။ ဖျက်သိမ်းလျှင် သိမ်းပြီးသား Draft သို့မဟုတ် ဘောင်ချာအသစ်ကို ဖွင့်မည်။',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, 'discard'),
                      child: Text(
                        _t('Discard auto-save', 'ယာယီမိတ္တူ ဖျက်မည်'),
                      ),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, 'resume'),
                      child: Text(_t('Resume', 'ဆက်ရေးမည်')),
                    ),
                  ],
                ),
              );
        if (!mounted || choice == null) return;
        if (choice == 'discard') {
          await AppDatabase.instance.deleteSaleRecovery(key);
        } else {
          restored = Map<String, Object?>.from(
            jsonDecode(recovery['payload'] as String) as Map,
          );
        }
      }
      if (!mounted) return;
      if (restored?['stage'] == 'payment' && id != null) {
        await _openPayment(id);
        return;
      }
      final result = await Navigator.push<_DraftResult>(
        context,
        MaterialPageRoute(
          builder: (_) => _SaleDraftForm(
            branches: branches,
            initialBranchId: branchId!,
            draft: draft,
            recovery: restored,
          ),
        ),
      );
      if (!mounted) return;
      if (result != null) setState(() => branchId = result.branchId);
      if (result?.startNew == true) {
        setState(() => busy = false);
        await edit();
        return;
      }
      if (result?.confirmedSaleId != null) {
        await load();
        if (mounted) {
          try {
            await showInvoicePrintPopup(context, result!.confirmedSaleId!);
          } catch (_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _t(
                      'Sale saved. Open Sale Invoice to retry printing.',
                      'အရောင်းသိမ်းပြီးပါပြီ။ Sale Invoice မှ Print ပြန်ထုတ်နိုင်သည်။',
                    ),
                  ),
                ),
              );
            }
          }
        }
        return;
      }
      if (result?.paymentDraftId != null) {
        await _openPayment(result!.paymentDraftId!);
      } else {
        await load();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_t('Could not open draft.', 'Draft မဖွင့်နိုင်ပါ။')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _openPayment(int id) async {
    final saleId = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => SaleConfirmationPage(draftId: id)),
    );
    if (!mounted) return;
    await load();
    if (!mounted || saleId == null) return;
    await showInvoicePrintPopup(context, saleId);
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ConfirmedSaleDetailPage(saleId: saleId),
      ),
    );
  }

  Future<void> confirmDraft(int id) async {
    if (busy || loading) return;
    setState(() => busy = true);
    try {
      final recovery = await AppDatabase.instance.getSaleRecovery('draft:$id');
      if (!mounted) return;
      if (recovery != null &&
          (jsonDecode(recovery['payload'] as String) as Map)['stage'] !=
              'payment') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Resume unfinished edits and Save Draft before confirming.',
                'ရေးလက်စပြင်ဆင်ချက်များကို ဆက်ရေးပြီး Draft အရင်သိမ်းပါ။',
              ),
            ),
          ),
        );
        return;
      }
      await _openPayment(id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t('Could not open payment form.', 'ငွေရှင်းရန် မဖွင့်နိုင်ပါ။'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => DesktopCommandScope(
    enabled: !loading && !busy,
    commands: {DesktopCommand.newVoucher: () => edit()},
    child: DesktopScaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButton<int>(
              isExpanded: true,
              value: branches.any((b) => b['id'] == branchId) ? branchId : null,
              hint: Text(_t('Select branch', 'ဆိုင်ခွဲရွေးရန်')),
              items: branches
                  .map(
                    (b) => DropdownMenuItem<int>(
                      value: b['id'] as int,
                      child: Text("${b['name']} (${b['code']})"),
                    ),
                  )
                  .toList(),
              onChanged: loading || busy
                  ? null
                  : (id) {
                      if (id != null && id != branchId) {
                        setState(() {
                          branchId = id;
                          drafts = [];
                        });
                        load();
                      }
                    },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _t(
                'Drafts do not change stock or money. Confirm Sale posts the transaction.',
                'Draft တွင် Stock နှင့် ငွေ မပြောင်းပါ။ အရောင်းအတည်ပြုမှ စာရင်းတင်မည်။',
              ),
            ),
          ),
          TextButton.icon(
            onPressed: loading || busy || branchId == null
                ? null
                : () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConfirmedSalesPage(
                        initialBranchId: branchId!,
                        branches: branches,
                      ),
                    ),
                  ),
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(_t('Confirmed Sales', 'အတည်ပြုပြီးအရောင်းများ')),
          ),
          if (!loading && recoveries.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: DesktopListView(
                shrinkWrap: true,
                children: [
                  for (final r in recoveries)
                    Card(
                      child: DesktopListTile(
                        leading: const Icon(Icons.restore),
                        title: Text(
                          r['source_draft_id'] == null
                              ? _t('Resume new invoice', 'ဘောင်ချာအသစ် ရေးလက်စ')
                              : '${_t('Resume', 'ဆက်ရေးရန်')} ${_draftNo(r['source_draft_id'] as int)}',
                        ),
                        subtitle: Text(
                          _t(
                            'Auto-saved on this device',
                            'ဤစက်တွင် ယာယီသိမ်းထားသည်',
                          ),
                        ),
                        onTap: busy
                            ? null
                            : () => edit(r['source_draft_id'] as int?),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error!),
                        TextButton(
                          onPressed: load,
                          child: Text(_t('Retry', 'ပြန်စမ်းရန်')),
                        ),
                      ],
                    ),
                  )
                : branches.isEmpty
                ? Center(
                    child: Text(
                      _t('Add a branch first.', 'ဆိုင်ခွဲအရင်ထည့်ပါ။'),
                    ),
                  )
                : drafts.isEmpty
                ? Center(
                    child: Text(
                      _t(
                        'Tap + to create a sale draft.',
                        'အရောင်း Draft ဖန်တီးရန် + ကိုနှိပ်ပါ။',
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: load,
                    child: DesktopListView.builder(
                      desktopColumns: const [
                        "Draft No.",
                        "Date",
                        "Customer",
                        "Salesperson",
                        "Total",
                      ],
                      desktopCells: (context, index) {
                        final r = drafts[index];
                        return [
                          desktopCellText('DRAFT-${r['id']}'),
                          desktopCellText(r['invoice_date']),
                          desktopCellText(r['customer_name']),
                          desktopCellText(r['employee_name']),
                          desktopMoney(r['total']),
                        ];
                      },

                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: drafts.length,
                      itemBuilder: (context, i) {
                        final d = drafts[i];
                        final name = d['customer_name'] as String;
                        return DesktopListTile(
                          onTap: busy ? null : () => edit(d['id'] as int),
                          leading: const Icon(Icons.edit_note),
                          title: Text(_draftNo(d['id'] as int)),
                          subtitle: Text(
                            "${d['invoice_date']} · ${name.isEmpty ? _t('Walk-in', 'လက်ငင်းဝယ်သူ') : name}\n${d['employee_name']}",
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MoneyText(d['total'] as int),
                              PopupMenuButton<String>(
                                enabled: !busy,
                                onSelected: (value) {
                                  if (value == 'confirm') {
                                    confirmDraft(d['id'] as int);
                                  } else {
                                    edit(d['id'] as int);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text(
                                      _t('Edit Draft', 'Draft ပြင်ရန်'),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'confirm',
                                    child: Text(
                                      _t(
                                        'Payment / Confirm Sale',
                                        'ငွေရှင်း / အရောင်းအတည်ပြုရန်',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: loading || busy || branchId == null || error != null
            ? null
            : () => edit(),
        child: const Icon(Icons.add),
      ),
    ),
  );
}

class _SaleDraftForm extends StatefulWidget {
  const _SaleDraftForm({
    required this.branches,
    required this.initialBranchId,
    this.draft,
    this.recovery,
  });
  final List<Map<String, Object?>> branches;
  final int initialBranchId;
  final Map<String, Object?>? draft;
  final Map<String, Object?>? recovery;
  @override
  State<_SaleDraftForm> createState() => _SaleDraftFormState();
}

class _SaleDraftFormState extends State<_SaleDraftForm>
    with WidgetsBindingObserver {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, phone, company, address, discount;
  late int branchId;
  int? savedDraftId, savedDraftRevision, desktopAccountId;
  final remark = TextEditingController(),
      desktopPaid = TextEditingController(text: '0'),
      desktopSearch = TextEditingController();
  final desktopPaidFocus = FocusNode(), desktopSearchFocus = FocusNode();
  DateTime desktopPaymentDate = AppDateTime.today();
  bool desktopReviewing = false, saleLookupBusy = false;
  bool voucherPreviewVisible = false, previewPreferenceTouched = false;
  int previewPreferenceRevision = 0;
  Future<void> previewPreferenceWrites = Future<void>.value();
  List<Map<String, Object?>> desktopAccounts = [];
  final desktopDiscountControllers = <int, TextEditingController>{},
      desktopQtyControllers = <int, TextEditingController>{};

  int? customerId, employeeId;
  late String discountType;
  late DateTime invoiceDate;
  List<Map<String, Object?>> products = [],
      staff = [],
      customers = [],
      lines = [];
  bool loading = true,
      saving = false,
      saveContact = false,
      choicesReady = false;
  String? error;
  int request = 0;
  final ScrollController scroll = ScrollController();
  final discountFocus = FocusNode(), rowsFocus = FocusNode();
  int selectedLine = 0;
  Map<int, Map<String, Object?>> desktopLots = {};
  Timer? _timer;
  Future<void> _writes = Future<void>.value();
  bool _ready = false,
      _dirty = false,
      _finalizing = false,
      _allowPop = false,
      _leaving = false;
  bool _autoPending = false;
  String? _autoError;
  int _generation = 0;
  double _restoreOffset = 0;
  Map<String, Object?>? _pendingLine;
  String get recoveryKey =>
      savedDraftId == null ? 'new' : 'draft:$savedDraftId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final d = widget.draft;
    savedDraftId = d?['id'] as int?;
    savedDraftRevision =
        (widget.recovery?['revision'] ?? d?['revision']) as int?;
    remark.text = d?['remark'] as String? ?? '';
    try {
      final payment =
          jsonDecode(d?['desktop_payment_json'] as String? ?? '{}') as Map;
      desktopPaid.text = payment['text'] as String? ?? '0';
      desktopAccountId = payment['account_id'] as int?;
      desktopPaymentSplits = [
        for (final p in payment['splits'] as List? ?? const [])
          Map<String, int>.from(p as Map),
      ];
      desktopPaymentDate =
          DateTime.tryParse('${payment['date']}') ?? AppDateTime.today();
    } catch (_) {
      /* Older drafts have no payment metadata. */
    }
    branchId = d?['branch_id'] as int? ?? widget.initialBranchId;
    customerId = d?['customer_id'] as int?;
    employeeId = d?['employee_id'] as int?;
    name = TextEditingController(text: d?['customer_name'] as String? ?? '');
    phone = TextEditingController(text: d?['customer_phone'] as String? ?? '');
    company = TextEditingController(
      text: d?['customer_company'] as String? ?? '',
    );
    address = TextEditingController(
      text: d?['customer_address'] as String? ?? '',
    );
    discount = TextEditingController(
      text: d == null
          ? '0'
          : d['discount_type'] == 'percent'
          ? d['discount_value'].toString()
          : AppCurrency.input(d['discount_value'] as int),
    );
    discountType = d?['discount_type'] as String? ?? 'amount';
    invoiceDate = d == null
        ? AppDateTime.today()
        : DateTime.parse(d['invoice_date'] as String);
    if (d != null) {
      lines = (d['items'] as List)
          .map((r) => Map<String, Object?>.from(r as Map))
          .toList();
    }
    final r = widget.recovery;
    if (r != null) {
      remark.text = r['remark'] as String? ?? remark.text;
      desktopPaid.text = r['desktop_paid'] as String? ?? desktopPaid.text;
      desktopPaymentSplits = [
        for (final p in r['desktop_splits'] as List? ?? desktopPaymentSplits)
          Map<String, int>.from(p as Map),
      ];
      desktopAccountId = r['desktop_account'] as int? ?? desktopAccountId;
      desktopPaymentDate =
          DateTime.tryParse('${r['desktop_payment_date']}') ??
          desktopPaymentDate;
      branchId = r['branch_id'] as int;
      customerId = r['customer_id'] as int?;
      employeeId = r['employee_id'] as int?;
      name.text = r['name'] as String;
      phone.text = r['phone'] as String;
      company.text = r['company'] as String;
      address.text = r['address'] as String;
      discount.text = r['discount_text'] as String;
      discountType = r['discount_type'] as String;
      invoiceDate = DateTime.parse(r['invoice_date'] as String);
      saveContact = r['save_contact'] as bool;
      lines = (r['lines'] as List)
          .map((l) => Map<String, Object?>.from(l as Map))
          .toList();
      _pendingLine = r['pending_line'] == null
          ? null
          : Map<String, Object?>.from(r['pending_line'] as Map);
      _restoreOffset = (r['scroll'] as num?)?.toDouble() ?? 0;
      _dirty = true;
    }
    if (AppCapabilities.windows) {
      desktopPaid.text = AmountInputFormatter.group(desktopPaid.text);
      if (discountType == 'amount') {
        discount.text = AmountInputFormatter.group(discount.text);
      }
    }
    for (final c in [
      name,
      phone,
      company,
      address,
      discount,
      remark,
      desktopPaid,
    ]) {
      c.addListener(_touch);
    }
    scroll.addListener(_touch);
    loadChoices();
    if (AppCapabilities.windows) loadPreviewPreference();
  }

  @override
  void dispose() {
    desktopPaidFocus.dispose();
    desktopSearchFocus.dispose();
    desktopSearch.dispose();
    for (final controller in [
      ...desktopDiscountControllers.values,
      ...desktopQtyControllers.values,
    ]) {
      controller.dispose();
    }
    discountFocus.dispose();
    rowsFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    for (final c in [
      name,
      phone,
      company,
      address,
      discount,
      remark,
      desktopPaid,
    ]) {
      c.removeListener(_touch);
      c.dispose();
    }
    scroll.removeListener(_touch);
    scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_persistNow());
    }
  }

  void _touch() {
    if (!_ready || _finalizing || !mounted) return;
    _generation++;
    _dirty = true;
    _timer?.cancel();
    setState(() {
      _autoPending = true;
    });
    _timer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persistNow());
    });
  }

  Map<String, Object?> _snapshot() => {
    'branch_id': branchId,
    'customer_id': customerId,
    'employee_id': employeeId,
    'name': name.text,
    'phone': phone.text,
    'company': company.text,
    'address': address.text,
    'discount_text': discount.text,
    'discount_type': discountType,
    'remark': remark.text,
    'desktop_paid': desktopPaid.text,
    'desktop_splits': desktopPaymentSplits,
    'desktop_account': desktopAccountId,
    'desktop_payment_date': _date(desktopPaymentDate),
    'invoice_date': _date(invoiceDate),
    'save_contact': saveContact,
    'lines': lines.map((l) => Map<String, Object?>.from(l)).toList(),
    'pending_line': _pendingLine,
    'revision': savedDraftRevision,
    'scroll': scroll.hasClients ? scroll.offset : _restoreOffset,
  };

  Future<bool> _persistNow() async {
    _timer?.cancel();
    if (!_ready || !_dirty || _finalizing) return true;
    final generation = _generation;
    final payload = jsonEncode(_snapshot());
    bool ok = false;
    final task = _writes.then((_) async {
      try {
        await AppDatabase.instance.putSaleRecovery(
          key: recoveryKey,
          sourceId: savedDraftId,
          payload: payload,
        );
        ok = true;
        if (mounted && generation == _generation) {
          setState(() {
            _autoPending = false;
            _autoError = null;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _autoPending = false;
            _autoError = _t(
              'Auto-save failed. Retry before leaving.',
              'Auto-save မအောင်မြင်ပါ။ မထွက်မီ ပြန်စမ်းပါ။',
            );
          });
        }
      }
    });
    _writes = task;
    await task;
    return ok;
  }

  Future<void> _pop([_DraftResult? result]) async {
    if (!mounted) return;
    setState(() {
      _allowPop = true;
      saving = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _leave() async {
    if (_leaving || saving || _finalizing) return;
    setState(() => _leaving = true);
    try {
      if (!_dirty) {
        await _pop();
        return;
      }
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => DesktopDialog(
          title: Text(_t('Leave this invoice?', 'ဘောင်ချာမှ ထွက်မလား?')),
          content: Text(
            _t(
              'Keep unfinished work on this device, continue editing, or discard the temporary copy.',
              'ရေးလက်စကို ဤစက်တွင်သိမ်းထားနိုင်ပါသည်။ Draft အတည်ပြုသိမ်းခြင်း မဟုတ်ပါ။',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(_t('Continue editing', 'ဆက်ရေးမည်')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, 'discard'),
              child: Text(_t('Discard', 'ယာယီမိတ္တူဖျက်မည်')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, 'keep'),
              child: Text(_t('Save & leave', 'သိမ်းပြီးထွက်မည်')),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'keep') {
        final ok = await _persistNow();
        if (!ok || !mounted) return;
      }
      _finalizing = true;
      _timer?.cancel();
      await _writes;
      if (choice == 'discard') {
        await AppDatabase.instance.deleteSaleRecovery(recoveryKey);
      }
      await _pop();
    } catch (_) {
      _finalizing = false;
      if (mounted) {
        setState(
          () => _autoError = _t(
            'Could not leave safely. Please retry.',
            'မသိမ်းနိုင်ပါ။ ပြန်စမ်းပါ။',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _leaving = false);
    }
  }

  Future<void> _resumeItem() async {
    final row = _pendingLine;
    if (row == null) return;
    await editLine(
      row['index'] as int?,
      product: {
        'id': row['product_id'],
        'name': row['item_name'],
        'price': row['base_price'],
      },
    );
  }

  Future<List<Map<String, Object?>>> readDesktopLots(
    List<Map<String, Object?>> rows,
  ) async {
    final ids = <int>{};
    for (final row in rows) {
      try {
        for (final lot
            in jsonDecode('${row['tracking_json'] ?? '[]'}') as List) {
          if (lot is Map && lot['lot_id'] is int) ids.add(lot['lot_id'] as int);
        }
      } catch (_) {
        /* Validation remains in the posting flow. */
      }
    }
    final list = ids.toList(), result = <Map<String, Object?>>[];
    final database = await AppDatabase.instance.database;
    for (var i = 0; i < list.length; i += 200) {
      final batch = list.skip(i).take(200).toList();
      result.addAll(
        await database.query(
          'stock_lots',
          columns: ['id', 'serial', 'imei'],
          where:
              'branch_id=? AND id IN (${List.filled(batch.length, '?').join(',')})',
          whereArgs: [branchId, ...batch],
        ),
      );
    }
    return result;
  }

  Future<void> loadChoices() async {
    final ticket = ++request;
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
        choicesReady = false;
      });
    }
    try {
      final db = AppDatabase.instance;
      final p = (await db.getProducts(branchId: branchId))
          .map((r) => Map<String, Object?>.from(r))
          .toList();
      final editing = widget.draft?['correction_source_sale_id'];
      if (editing != null) {
        for (final row in await (await db.database).query(
          'sale_items',
          where: 'sale_id=?',
          whereArgs: [editing],
        )) {
          final product = p
              .where((p) => p['id'] == row['product_id'])
              .firstOrNull;
          if (product != null) {
            product['stock'] = (product['stock'] as int) + (row['qty'] as int);
          }
        }
      }
      final lots = AppCapabilities.windows
          ? await readDesktopLots(lines)
          : <Map<String, Object?>>[];
      final accounts = await db.getMoneyAccounts(branchId: branchId);
      final e = await db.getEmployees(branchId: branchId, activeOnly: true);
      final c = await db.getContacts(kind: 'customer', activeOnly: true);
      if (!mounted || ticket != request) return;
      setState(() {
        desktopAccounts = accounts;
        desktopWorkspaceNavigation.branchId = branchId;
        desktopWorkspaceNavigation.refresh();
        if (!accounts.any((row) => row['id'] == desktopAccountId)) {
          desktopAccountId = accounts.isEmpty
              ? null
              : ((accounts.where((row) => row['type'] == 'cash').firstOrNull ??
                        accounts.first)['id']
                    as int);
        }
        products = p;
        desktopLots = {for (final lot in lots) lot['id'] as int: lot};
        staff = e;
        customers = c;
        loading = false;
        choicesReady = true;
        if (!staff.any((r) => r['id'] == employeeId)) employeeId = null;
      });
      _ready = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scroll.hasClients) return;
        if (_restoreOffset > 0) {
          scroll.jumpTo(
            _restoreOffset
                .clamp(0.0, scroll.position.maxScrollExtent)
                .toDouble(),
          );
          _restoreOffset = 0;
        }
      });
    } catch (_) {
      if (!mounted || ticket != request) return;
      setState(() {
        loading = false;
        error = _t(
          'Could not load products or employees.',
          'ပစ္စည်း သို့မဟုတ် ဝန်ထမ်းစာရင်း မဖတ်နိုင်ပါ။',
        );
      });
    }
  }

  int get subtotal => lines.fold<int>(
    0,
    (sum, l) => sum + (l['price'] as int) * (l['qty'] as int),
  );
  int? get parsedDiscount => discountType == 'percent'
      ? int.tryParse(discount.text.replaceAll(',', '').trim())
      : AppCurrency.tryParse(discount.text.trim());
  int get discountAmount => itemDiscountTotal + voucherDiscountAmount;

  int stockOf(int id) {
    for (final p in products) {
      if (p['id'] == id) return p['stock'] as int;
    }
    return 0;
  }

  Future<void> chooseCustomer() async {
    final selected = await _pick(
      context,
      _t('Choose Customer', 'ဝယ်သူရွေးရန်'),
      customers,
      (c) =>
          "${c['name']} (${ContactSearch.code(c['id'])})\n${c['phone']} · ${c['company']}",
    );
    if (selected == null || !mounted) return;
    setState(() {
      customerId = selected['id'] as int;
      saveContact = false;
      name.text = selected['name'] as String;
      phone.text = selected['phone'] as String;
      company.text = selected['company'] as String;
      address.text = selected['address'] as String;
    });
    _touch();
  }

  Future<void> scanProduct() async {
    if (_pendingLine != null) {
      await _resumeItem();
      return;
    }
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScanPage()),
    );
    if (!mounted || value == null) return;
    try {
      final product = await AppDatabase.instance.getProductByBarcode(
        branchId: branchId,
        barcode: value,
      );
      if (!mounted) return;
      if (product == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'No product found for this barcode. Add it under Stock & Products first.',
                'ဤ Barcode အတွက် ပစ္စည်းမတွေ့ပါ။ Stock & Products တွင် အရင်ထည့်ပါ။',
              ),
            ),
          ),
        );
        return;
      }
      // Refresh stock shown in the quantity form without altering other invoice fields.
      setState(() {
        products = [
          product,
          ...products.where((p) => p['id'] != product['id']),
        ];
      });
      final index = lines.indexWhere(
        (line) => line['product_id'] == product['id'],
      );
      if (index >= 0) {
        await editLine(index);
        return;
      }
      if (lines.length >= 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Maximum 300 different items per draft.',
                'Draft တစ်စောင်တွင် ပစ္စည်းအမျိုးအစား 300 အထိသာ ထည့်နိုင်ပါသည်။',
              ),
            ),
          ),
        );
        return;
      }
      await editLine(null, product: product);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t(
                'Could not look up barcode. Please retry.',
                'Barcode ဖြင့် ပစ္စည်းမရှာနိုင်ပါ။ ပြန်စမ်းပါ။',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> chooseProduct() async {
    if (_pendingLine != null) {
      await _resumeItem();
      return;
    }
    final p = await _pick(
      context,
      _t('Choose Item', 'ပစ္စည်းရွေးရန်'),
      products,
      (p) =>
          "${p['item_code']} · ${p['name']} · ${p['barcode'] ?? ''}\n${_money(p['price'] as int)} · ${_t('Stock', 'လက်ကျန်')}: ${p['stock']}",
      productPhotos: true,
    );
    if (p == null || !mounted) return;
    final index = lines.indexWhere((l) => l['product_id'] == p['id']);
    if (index >= 0) {
      await editLine(index);
      return;
    }
    if (lines.length >= 300) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Maximum 300 different items per draft.',
              'Draft တစ်စောင်တွင် ပစ္စည်းအမျိုးအစား 300 အထိသာ ထည့်နိုင်ပါသည်။',
            ),
          ),
        ),
      );
      return;
    }
    await editLine(null, product: p);
  }

  Future<void> editLine(
    int? index, {
    Map<String, Object?>? product,
    bool focusQuantity = false,
  }) async {
    final old = index == null ? null : lines[index];
    final id = (old?['product_id'] ?? product!['id']) as int;
    final itemName = (old?['item_name'] ?? product!['name']) as String;
    int price = (old?['price'] ?? product!['price']) as int;
    int qty = old?['qty'] as int? ?? 1;
    if (_pendingLine != null) {
      qty = int.tryParse('${_pendingLine!['qty_text']}') ?? qty;
      price = AppCurrency.tryParse('${_pendingLine!['price_text']}') ?? price;
    }
    final selectedProduct =
        product ?? products.where((p) => p['id'] == id).firstOrNull;
    if (index == null &&
        _pendingLine == null &&
        selectedProduct != null &&
        (selectedProduct['tracking'] ?? 'none') == 'none' &&
        '${selectedProduct['color'] ?? ''}'.isEmpty &&
        '${selectedProduct['size'] ?? ''}'.isEmpty) {
      setState(
        () => lines.add({
          'product_id': id,
          'item_name': itemName,
          'item_code': selectedProduct['item_code'],
          'price': price,
          'qty': 1,
          'item_discount': 0,
          'tracking_json': '[]',
        }),
      );
      _touch();
      return;
    }
    // One popup owns quantity, price and required identities on every platform.
    _pendingLine = null;
    _touch();
    final tracking = await pickSaleLots(
      context,
      id,
      branchId,
      qty,
      old?['tracking_json'],
      unitPrice: price,
      onDetails: (q, p) {
        qty = q;
        price = p;
      },
      editingSaleId: widget.draft?['correction_source_sale_id'] as int?,
    );
    if (tracking == null || !mounted) return;
    final row = <String, Object?>{
      'tracking_json': tracking,
      'product_id': id,
      'item_name': itemName,
      'item_code': old?['item_code'] ?? product?['item_code'] ?? _itemCode(id),
      'price': price,
      'qty': qty,
      'item_discount': old?['item_discount'] ?? 0,
    };
    final labels = AppCapabilities.windows
        ? await readDesktopLots([row])
        : <Map<String, Object?>>[];
    if (!mounted) return;
    setState(() {
      desktopLots.addAll({for (final lot in labels) lot['id'] as int: lot});
      desktopQtyControllers[id]?.text = '$qty';
      desktopDiscountControllers[id]?.text = AmountInputFormatter.group(
        AppCurrency.input(row['item_discount'] as int? ?? 0),
      );
      if (index == null) {
        lines.add(row);
      } else {
        lines[index] = row;
      }
    });
    _touch();
  }

  Future<void> changeBranch(int id) async {
    if (id == branchId) return;
    if (lines.isNotEmpty || _pendingLine != null) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => DesktopDialog(
          title: Text(_t('Change branch?', 'ဆိုင်ခွဲပြောင်းမလား?')),
          content: Text(
            _t(
              'Current item rows will be cleared so stock can be checked for the new branch.',
              'ဆိုင်ခွဲအသစ်အတွက် လက်ကျန်ပြန်စစ်ရန် လက်ရှိပစ္စည်းအတန်းများကို ရှင်းမည်။',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(_t('Change', 'ပြောင်းမည်')),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    desktopAccountId = null;
    desktopPaid.text = '0';
    desktopPaymentSplits = [];
    setState(() {
      branchId = id;
      employeeId = null;
      lines = [];
      _pendingLine = null;
      products = [];
      staff = [];
    });
    _touch();
    await loadChoices();
  }

  Future<void> save({bool openPayment = false}) async {
    if (saving ||
        _finalizing ||
        loading ||
        !choicesReady ||
        !form.currentState!.validate()) {
      return;
    }
    if (_pendingLine != null ||
        lines.isEmpty ||
        employeeId == null ||
        subtotal > 9000000000000) {
      setState(
        () => error = _t(
          'Finish any pending item, add items, select a sale person and check the total.',
          'ပစ္စည်းထည့်ပြီး အရောင်းဝန်ထမ်းရွေးပါ။ စုစုပေါင်းငွေကို စစ်ပါ။',
        ),
      );
      return;
    }
    if (openPayment && !await desktopReview()) {
      return;
    }
    if (!mounted) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      int? contactId = customerId;
      bool createContact =
          (saveContact || (openPayment && desktopBalance > 0)) &&
          contactId == null;
      if (createContact && phone.text.trim().isNotEmpty) {
        final all = await AppDatabase.instance.getContacts(kind: 'customer');
        final normalized = phone.text.replaceAll(RegExp(r'[^0-9+]'), '');
        final matches = all
            .where(
              (c) =>
                  normalized.isNotEmpty &&
                  (c['phone'] as String).replaceAll(RegExp(r'[^0-9+]'), '') ==
                      normalized,
            )
            .toList();
        if (!mounted) return;
        if (matches.isNotEmpty) {
          final choice = await showDialog<String>(
            context: context,
            builder: (c) => DesktopDialog(
              title: Text(
                _t(
                  'Matching phone found',
                  'ဖုန်းနံပါတ်တူ ရှိပြီးသားဖြစ်ပါသည်။',
                ),
              ),
              content: Text(
                _t(
                  'Use an existing customer or save a separate new contact?',
                  'ရှိပြီးသားဝယ်သူ သုံးမလား၊ Contact အသစ်သိမ်းမလား?',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c, 'existing'),
                  child: Text(_t('Use existing', 'ရှိပြီးသားသုံးမည်')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(c, 'new'),
                  child: Text(_t('Save new', 'အသစ်သိမ်းမည်')),
                ),
              ],
            ),
          );
          if (!mounted || choice == null) return;
          if (choice == 'existing') {
            final selected = await _pick(
              context,
              _t('Choose matching customer', 'ဝယ်သူရွေးရန်'),
              matches,
              (c) => "${c['name']} (#${c['id']}) · ${c['phone']}",
            );
            if (!mounted || selected == null) return;
            contactId = selected['id'] as int;
            createContact = false;
          }
        }
      }
      if (!mounted) return;
      await _persistNow();
      _finalizing = true;
      _timer?.cancel();
      await _writes;
      final savedId = await AppDatabase.instance.saveSaleDraft(
        recoveryKey: recoveryKey,
        id: savedDraftId,
        revision: savedDraftRevision,
        branchId: branchId,
        customerId: contactId,
        saveCustomer: createContact,
        customerName: name.text,
        customerPhone: phone.text,
        customerCompany: company.text,
        customerAddress: address.text,
        employeeId: employeeId!,
        invoiceDate: _date(invoiceDate),
        discountType: discountType,
        discountValue: parsedDiscount!,
        remark: remark.text,
        desktopPaymentJson: desktopPaymentJson,
        items: lines
            .map(
              (l) => <String, Object?>{
                'product_id': l['product_id'] as int,
                'price': l['price'] as int,
                'qty': l['qty'] as int,
                'tracking_json': l['tracking_json'] ?? '[]',
                'item_discount': l['item_discount'] ?? 0,
              },
            )
            .toList(),
      );
      if (!mounted) return;
      final saved = await AppDatabase.instance.getSaleDraft(savedId);
      savedDraftId = savedId;
      savedDraftRevision = saved['revision'] as int;
      if (openPayment) {
        final saleId = await AppDatabase.instance.confirmSaleDraft(
          draftId: savedId,
          revision: savedDraftRevision!,
          paymentDate: _date(desktopPaymentDate),
          payments: desktopPaymentSplits,
        );
        _dirty = false;
        await _pop(_DraftResult(branchId, confirmedSaleId: saleId));
        return;
      }
      _dirty = false;
      await _pop(
        _DraftResult(branchId, paymentDraftId: openPayment ? savedId : null),
      );
    } catch (e) {
      _finalizing = false;
      _touch();
      if (mounted) {
        setState(
          () => error = e is StateError
              ? e.message
              : _t(
                  'Could not save. Check fields and retry.',
                  'မသိမ်းနိုင်ပါ။ ဖြည့်ထားသောအချက်များကို စစ်ပါ။',
                ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> focusDiscount() => desktopFocusInScroll(discountFocus, scroll);

  void selectLine(int delta) {
    if (lines.isEmpty) return;
    setState(
      () => selectedLine = (selectedLine + delta).clamp(0, lines.length - 1),
    );
  }

  Future<void> selectedQuantity() async {
    if (lines.isEmpty) return;
    selectedLine = selectedLine.clamp(0, lines.length - 1);
    await editLine(selectedLine, focusQuantity: true);
  }

  Future<void> removeSelected() async {
    if (lines.isEmpty || _pendingLine != null) return;
    selectedLine = selectedLine.clamp(0, lines.length - 1);
    if (!await desktopAsk(
          context,
          _t('Remove draft item?', 'Draft ပစ္စည်းဖယ်မလား။'),
          '${lines[selectedLine]['item_name']}',
        ) ||
        !mounted) {
      return;
    }
    setState(() => lines.removeAt(selectedLine));
    _touch();
  }

  Widget field(
    TextEditingController c,
    String label,
    int max, {
    bool multiline = false,
    bool isName = false,
    bool isPhone = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: c,
      enabled: !saving && !loading && !_leaving && !_finalizing,
      maxLength: max,
      maxLines: multiline ? 3 : 1,
      keyboardType: multiline
          ? TextInputType.multiline
          : isPhone
          ? TextInputType.phone
          : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: isName
          ? (v) =>
                saveContact &&
                    customerId == null &&
                    (v == null || v.trim().isEmpty)
                ? _t(
                    'Name is required to save a contact.',
                    'Contact သိမ်းရန် အမည်လိုပါသည်။',
                  )
                : null
          : null,
    ),
  );

  Future<void> editDesktopIdentities() async {
    if (lines.isEmpty || _pendingLine != null) return;
    final index = selectedLine.clamp(0, lines.length - 1);
    final row = Map<String, Object?>.from(lines[index]);
    final tracking = await pickSaleLots(
      context,
      row['product_id'] as int,
      branchId,
      row['qty'] as int,
      row['tracking_json'],
      editingSaleId: widget.draft?['correction_source_sale_id'] as int?,
    );
    if (!mounted || tracking == null) return;
    row['tracking_json'] = tracking;
    final labels = await readDesktopLots([row]);
    if (!mounted) return;
    setState(() {
      lines[index] = row;
      desktopLots.addAll({for (final lot in labels) lot['id'] as int: lot});
    });
    _touch();
  }

  int get itemDiscountTotal => lines.fold<int>(
    0,
    (sum, line) => sum + (line['item_discount'] as int? ?? 0),
  );
  int get voucherDiscountAmount => discountType == 'percent'
      ? (subtotal - itemDiscountTotal) * (parsedDiscount ?? 0) ~/ 100
      : (parsedDiscount ?? 0);
  int get desktopTotal => subtotal - itemDiscountTotal - voucherDiscountAmount;
  int get desktopPaidAmount =>
      AppCurrency.tryParse(
        desktopPaid.text.trim().isEmpty ? '0' : desktopPaid.text.trim(),
      ) ??
      0;
  int get desktopBalance => desktopTotal - desktopPaidAmount;
  String get desktopPaymentJson => jsonEncode({
    'account_id': desktopAccountId,
    'text': desktopPaid.text,
    'splits': desktopPaymentSplits,
    'date': _date(desktopPaymentDate),
  });
  void desktopRefresh(VoidCallback update) => setState(update);

  Future<void> desktopNewInvoice() async {
    if (saving || _finalizing) return;
    if (!await desktopAsk(
          context,
          _t('New invoice?', 'ဘောင်ချာအသစ် စတင်မလား'),
          _t(
            'Discard unsaved changes and start a new sale? Saved drafts are kept.',
            'မသိမ်းရသေးသော ပြင်ဆင်မှုများကို ပယ်ဖျက်ပြီး အရောင်းအသစ် စတင်မလား။ သိမ်းထားသော Draft များ မပျက်ပါ။',
          ),
        ) ||
        !mounted) {
      return;
    }
    _finalizing = true;
    _timer?.cancel();
    await _writes;
    await AppDatabase.instance.deleteSaleRecovery(recoveryKey);
    _dirty = false;
    await _pop(_DraftResult(branchId, startNew: true));
  }

  Future<void> desktopScanCode(String input) async {
    if (input.trim().isEmpty || saving || loading) return;
    if (_pendingLine != null) {
      await _resumeItem();
      return;
    }
    try {
      var product = await AppDatabase.instance.getProductByBarcode(
        branchId: branchId,
        barcode: input.trim(),
      );
      if (!mounted) return;
      if (product == null) {
        final found = CatalogSearch.matches(products, input);
        if (found.length == 1) {
          product = found.single;
        } else if (found.isNotEmpty) {
          product = await _pick(
            context,
            _t('Choose item', 'ပစ္စည်းရွေးပါ'),
            found,
            (row) => '${row['item_code']} · ${row['name']}',
            productPhotos: true,
          );
        }
      }
      if (!mounted || product == null) return;
      final index = lines.indexWhere(
        (line) => line['product_id'] == product!['id'],
      );
      await editLine(index < 0 ? null : index, product: product);
      desktopSearch.clear();
      if (mounted) desktopSearchFocus.requestFocus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _t('Could not find this item.', 'ဤပစ္စည်းကို ရှာမတွေ့ပါ။'),
            ),
          ),
        );
      }
    }
  }

  void desktopQuantity(int index, String input) {
    final value = int.tryParse(input.trim());
    if (value == null || value < 1 || value > 2147483647) return;
    setState(() {
      final line = lines[index];
      if (line['qty'] != value) {
        line['qty'] = value;
        line['tracking_json'] = '[]';
      }
    });
    _touch();
  }

  Future<void> desktopCustomerDetails() async {
    await showDialog<void>(
      context: context,
      builder: (dialog) => DesktopDialog(
        title: Text(_t('Customer details', 'ဝယ်သူအချက်အလက်')),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                field(name, _t('Customer name', 'ဝယ်သူအမည်'), 100),
                if (customerId != null) Text(ContactSearch.code(customerId)),
                field(phone, _t('Phone', 'ဖုန်းနံပါတ်'), 80, isPhone: true),
                field(company, _t('Company', 'ကုမ္ပဏီ'), 150),
                field(address, _t('Address', 'လိပ်စာ'), 500, multiline: true),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(_t('Done', 'ပြီးပါပြီ')),
          ),
        ],
      ),
    );
  }

  Future<void> desktopPaymentDetails() async {
    var account = desktopAccountId, date = desktopPaymentDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => DesktopDialog(
          title: Text(_t('Payment details', 'ငွေပေးချေမှု အချက်အလက်')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: account,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _t(
                      'Receive into account',
                      'လက်ခံမည့် ငွေစာရင်း',
                    ),
                  ),
                  items: [
                    for (final row in desktopAccounts)
                      DropdownMenuItem(
                        value: row['id'] as int,
                        child: Text('${row['name']}'),
                      ),
                  ],
                  onChanged: (id) => update(() => account = id),
                ),
                DesktopListTile(
                  title: Text(_t('Payment date', 'ငွေလက်ခံရက်')),
                  subtitle: Text(_date(date)),
                  trailing: const Icon(Icons.calendar_month_outlined),
                  onTap: () async {
                    final selected = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2200, 12, 31),
                    );
                    if (selected != null && context.mounted) {
                      update(() => date = selected);
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(_t('Cancel', 'မလုပ်တော့ပါ')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(_t('Apply', 'အသုံးပြုမည်')),
            ),
          ],
        ),
      ),
    );
    if (ok == true && mounted) {
      setState(() {
        desktopAccountId = account;
        desktopPaymentDate = date;
      });
      _touch();
    }
  }

  List<Map<String, int>> desktopPaymentSplits = [];
  Future<void> desktopTakePayment() async {
    final splits = await showSplitPaymentDialog(
      context,
      total: desktopTotal,
      actionLabel: _t('Apply payment', 'ငွေပေးချေမှု သတ်မှတ်မည်'),
      accounts: desktopAccounts,
      initial:
          desktopPaymentSplits.isNotEmpty &&
              desktopPaymentSplits.fold<int>(
                    0,
                    (sum, p) => sum + p['amount']!,
                  ) ==
                  desktopPaidAmount
          ? desktopPaymentSplits
          : [
              if (desktopPaidAmount > 0 && desktopAccountId != null)
                {'account_id': desktopAccountId!, 'amount': desktopPaidAmount},
            ],
    );
    if (splits == null || !mounted) return;
    desktopPaymentSplits = splits;
    desktopPaid.text = AmountInputFormatter.group(
      AppCurrency.input(splits.fold<int>(0, (sum, p) => sum + p['amount']!)),
    );
    desktopAccountId = splits.isEmpty ? null : splits.first['account_id'];
    setState(() {});
    _touch();
  }

  Future<bool> desktopReview() async {
    if (desktopPaymentSplits.fold<int>(0, (sum, p) => sum + p['amount']!) !=
        desktopPaidAmount) {
      desktopPaymentSplits = [
        if (desktopPaidAmount > 0 && desktopAccountId != null)
          {'account_id': desktopAccountId!, 'amount': desktopPaidAmount},
      ];
    }
    if (desktopPaidAmount < 0 ||
        desktopPaidAmount > desktopTotal ||
        (desktopPaidAmount > 0 && desktopAccountId == null)) {
      setState(
        () => error = _t(
          'Check Paid and choose a payment account.',
          'ပေးချေငွေနှင့် လက်ခံမည့်ငွေစာရင်းကို စစ်ပါ။',
        ),
      );
      return false;
    }
    if (desktopBalance > 0 && customerId == null && name.text.trim().isEmpty) {
      setState(
        () => error = _t(
          'A credit sale needs a customer name or saved customer.',
          'အကြွေးရောင်းရန် ဝယ်သူနာမည်ထည့်ပါ သို့မဟုတ် သိမ်းထားသော ဝယ်သူကို ရွေးပါ။',
        ),
      );
      return false;
    }
    // Changing tracked quantities requires a fresh exact lot selection.
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      Map<String, Object?>? product;
      for (final row in products) {
        if (row['id'] == line['product_id']) product = row;
      }
      if (product == null || '${product['tracking'] ?? 'none'}' == 'none') {
        continue;
      }
      final lots = jsonDecode('${line['tracking_json'] ?? '[]'}') as List;
      if (lots.fold<int>(
            0,
            (sum, lot) => sum + ((lot as Map)['qty'] as int? ?? 0),
          ) ==
          line['qty']) {
        continue;
      }
      final picked = await pickSaleLots(
        context,
        line['product_id'] as int,
        branchId,
        line['qty'] as int,
        line['tracking_json'],
        editingSaleId: widget.draft?['correction_source_sale_id'] as int?,
      );
      if (!mounted || picked == null) return false;
      final labels = await readDesktopLots([
        {...line, 'tracking_json': picked},
      ]);
      if (!mounted) return false;
      setState(() {
        line['tracking_json'] = picked;
        desktopLots.addAll({for (final lot in labels) lot['id'] as int: lot});
      });
      _touch();
    }
    return true;
  }

  Future<void> loadPreviewPreference() async {
    try {
      final v = await PortablePreferences.read('sale_voucher_preview_visible');
      if (mounted && !previewPreferenceTouched) {
        setState(() => voucherPreviewVisible = v == 'true');
      }
    } catch (_) {
      /* Optional presentation preference; the invoice remains usable. */
    }
  }

  void setVoucherPreview(bool visible) {
    previewPreferenceTouched = true;
    setState(() => voucherPreviewVisible = visible);
    final ticket = ++previewPreferenceRevision;
    previewPreferenceWrites = previewPreferenceWrites.then((_) async {
      try {
        await PortablePreferences.write(
          'sale_voucher_preview_visible',
          visible.toString(),
        );
      } catch (_) {
        if (mounted && ticket == previewPreferenceRevision) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _t(
                  'Preview changed, but this preference could not be saved.',
                  'Preview ပြောင်းပြီးသော်လည်း ရွေးချယ်မှုကို မသိမ်းနိုင်ပါ။',
                ),
              ),
            ),
          );
        }
      }
    });
  }

  Map<String, Object?> voucherPreviewSnapshot() {
    final branch = widget.branches
        .where((b) => b['id'] == branchId)
        .firstOrNull;
    final employee = staff.where((s) => s['id'] == employeeId).firstOrNull;
    return {
      'id': 0,
      'status': 'draft',
      'document_title': _t('SALE INVOICE · DRAFT', 'အရောင်းဘောင်ချာ · မူကြမ်း'),
      'document_number': _t('Assigned on confirm', 'အတည်ပြုပြီးမှ ရမည်'),
      'branch_id': branchId,
      'branch_name_snapshot': branch?['name'] ?? '',
      'branch_code_snapshot': branch?['code'] ?? '',
      'branch_phone_snapshot': branch?['phone'] ?? '',
      'branch_address_snapshot': branch?['address'] ?? '',
      'invoice_date': _date(invoiceDate),
      'customer_id': customerId,
      'customer_name': name.text,
      'customer_phone': phone.text,
      'customer_company': company.text,
      'customer_address': address.text,
      'employee_name': employee?['name'] ?? '',
      'remark': remark.text,
      'subtotal': subtotal,
      'discount_amount': discountAmount,
      'voucher_discount_amount': voucherDiscountAmount,
      'total': desktopTotal,
      'paid': desktopPaidAmount,
      'balance_due': desktopBalance,
      'items': [
        for (final line in lines)
          {
            ...line,
            'amount': (line['qty'] as int) * (line['price'] as int),
            'tracking_json': jsonEncode([
              for (final allocation in ProductTracking.decode(
                line['tracking_json'],
              ))
                {...?desktopLots[allocation['lot_id']], ...allocation},
            ]),
          },
      ],
    };
  }

  Widget desktopInvoice(bool enabled) => LayoutBuilder(
    builder: (context, box) {
      final wide = box.maxWidth >= 1080;
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(
              children: [
                const Spacer(),
                if (voucherPreviewVisible && !wide)
                  Flexible(
                    child: Text(
                      _t(
                        'Widen the window to show the side preview.',
                        'ဘေးတွင် Preview ပြရန် Window ကို ချဲ့ပါ။',
                      ),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                Text(_t('Voucher preview', 'ဘောင်ချာ Preview')),
                Switch(
                  key: const ValueKey('sale-preview-toggle'),
                  value: voucherPreviewVisible,
                  onChanged: setVoucherPreview,
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: approvedDesktopInvoice(enabled)),
                if (voucherPreviewVisible && wide)
                  SizedBox(
                    width: (box.maxWidth * .29).clamp(320.0, 460.0),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 6, 10, 10),
                      child: SaleVoucherPreview(
                        sale: voucherPreviewSnapshot(),
                        onClose: () => setVoucherPreview(false),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final enabled =
        !saving && !loading && !_leaving && !_finalizing && !desktopReviewing;
    return DesktopCommandScope(
      enabled: enabled && choicesReady,
      onEscape: _leave,
      commands: {
        DesktopCommand.saveDraft: () => save(),
        DesktopCommand.newVoucher: desktopNewInvoice,
        DesktopCommand.barcode: AppCapabilities.windows
            ? () => desktopSearchFocus.requestFocus()
            : scanProduct,
        DesktopCommand.search: AppCapabilities.windows
            ? () => desktopSearchFocus.requestFocus()
            : chooseProduct,
        DesktopCommand.addItem: chooseProduct,
        DesktopCommand.contact: chooseCustomer,
        DesktopCommand.focusRows: () => desktopFocusInScroll(rowsFocus, scroll),
        DesktopCommand.quantity: selectedQuantity,
        DesktopCommand.discount: focusDiscount,
        DesktopCommand.paid: () =>
            desktopFocusInScroll(desktopPaidFocus, scroll),
        DesktopCommand.confirm: () => save(openPayment: true),
        DesktopCommand.removeItem: removeSelected,
        DesktopCommand.previousRow: () => selectLine(-1),
        DesktopCommand.nextRow: () => selectLine(1),
        DesktopCommand.editRow: () => lines.isEmpty
            ? Future<void>.value()
            : editLine(selectedLine.clamp(0, lines.length - 1)),
      },
      child: PopScope<_DraftResult>(
        canPop: _allowPop && !saving,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) unawaited(_leave());
        },
        child: DesktopScaffold(
          appBar: AppCapabilities.windows
              ? null
              : AppBar(
                  title: Text(
                    AppCapabilities.windows
                        ? _t('Sale Invoice', 'အရောင်းဘောင်ချာ')
                        : widget.draft == null
                        ? _t('New Sale Draft', 'အရောင်း Draft အသစ်')
                        : _draftNo(widget.draft!['id'] as int),
                  ),
                ),
          body: AppCapabilities.windows
              ? desktopInvoice(enabled)
              : Form(
                  key: form,
                  child: DesktopListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(_t('Branch', 'ဆိုင်ခွဲ')),
                      DropdownButton<int>(
                        value: branchId,
                        isExpanded: true,
                        items: widget.branches
                            .map(
                              (b) => DropdownMenuItem<int>(
                                value: b['id'] as int,
                                child: Text("${b['name']} (${b['code']})"),
                              ),
                            )
                            .toList(),
                        onChanged: enabled
                            ? (id) {
                                if (id != null) changeBranch(id);
                              }
                            : null,
                      ),
                      if (_autoError != null) ...[
                        Text(
                          _autoError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: _autoPending
                              ? null
                              : () {
                                  unawaited(_persistNow());
                                },
                          child: Text(
                            _t('Retry auto-save', 'Auto-save ပြန်စမ်းရန်'),
                          ),
                        ),
                      ],
                      if (_pendingLine != null)
                        OutlinedButton(
                          onPressed: enabled ? _resumeItem : null,
                          child: Text(
                            _t(
                              'Continue unfinished item entry',
                              'ရေးလက်စပစ္စည်းကို ဆက်ဖြည့်ရန်',
                            ),
                          ),
                        ),
                      DesktopListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_t('Invoice Date', 'ဘောင်ချာရက်')),
                        subtitle: Text(_date(invoiceDate)),
                        trailing: const Icon(Icons.calendar_today_outlined),
                        onTap: !enabled
                            ? null
                            : () async {
                                final d = await showDatePicker(
                                  context: context,
                                  initialDate: invoiceDate,
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime(2200, 12, 31),
                                );
                                if (d != null && mounted) {
                                  setState(() => invoiceDate = d);
                                  _touch();
                                }
                              },
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: enabled ? chooseCustomer : null,
                            child: Text(
                              desktopHint(
                                _t('Choose Customer', 'ဝယ်သူရွေးရန်'),
                                DesktopCommand.contact,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: enabled
                                ? () {
                                    setState(() {
                                      customerId = null;
                                      saveContact = false;
                                    });
                                    _touch();
                                  }
                                : null,
                            child: Text(
                              _t('Enter directly', 'တိုက်ရိုက်ဖြည့်ရန်'),
                            ),
                          ),
                        ],
                      ),
                      if (customerId != null)
                        Text(
                          '${_t('Linked customer', 'ချိတ်ထားသောဝယ်သူ')}: #$customerId',
                        ),
                      field(
                        name,
                        _t('Customer Name', 'ဝယ်သူအမည်'),
                        100,
                        isName: true,
                      ),
                      field(
                        phone,
                        _t('Phone', 'ဖုန်းနံပါတ်'),
                        80,
                        isPhone: true,
                      ),
                      field(company, _t('Company', 'ကုမ္ပဏီ'), 150),
                      field(
                        address,
                        _t('Address', 'လိပ်စာ'),
                        500,
                        multiline: true,
                      ),
                      if (customerId == null)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: saveContact,
                          onChanged: enabled
                              ? (v) {
                                  setState(() => saveContact = v ?? false);
                                  _touch();
                                }
                              : null,
                          title: Text(
                            _t(
                              'Save this customer to Contacts',
                              'ဤဝယ်သူကို Contacts ထဲ သိမ်းမည်',
                            ),
                          ),
                        ),
                      if (customerId != null)
                        Text(
                          _t(
                            'Changes here affect this draft only, not the saved contact.',
                            'ဤနေရာတွင်ပြင်ခြင်းသည် Draft အတွက်သာဖြစ်ပြီး Contact မပြောင်းပါ။',
                          ),
                        ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        key: ValueKey('employee-$branchId-$employeeId'),
                        initialValue: employeeId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _t('Sale Person', 'အရောင်းဝန်ထမ်း'),
                        ),
                        items: staff
                            .map(
                              (e) => DropdownMenuItem<int>(
                                value: e['id'] as int,
                                child: Text("${e['name']} (${e['code']})"),
                              ),
                            )
                            .toList(),
                        onChanged: enabled
                            ? (id) {
                                setState(() => employeeId = id);
                                _touch();
                              }
                            : null,
                        validator: (id) => id == null
                            ? _t(
                                'Select an active employee for this branch.',
                                'ဤဆိုင်ခွဲ၏ အသုံးပြုဆဲဝန်ထမ်း ရွေးပါ။',
                              )
                            : null,
                      ),
                      if (!loading && staff.isEmpty)
                        Text(
                          _t(
                            'Add an active employee under Account > Employees & Users first.',
                            'အကောင့် > ဝန်ထမ်းများတွင် ဤဆိုင်ခွဲအတွက် ဝန်ထမ်းအရင်ထည့်ပါ။',
                          ),
                        ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: enabled ? chooseProduct : null,
                        icon: const Icon(Icons.add),
                        label: Text(
                          desktopHint(
                            _t('Add Item', 'ပစ္စည်းထည့်ရန်'),
                            DesktopCommand.addItem,
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: enabled && choicesReady ? scanProduct : null,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: Text(
                          desktopHint(
                            _t(
                              'Scan Barcode / Enter Code',
                              'Barcode ဖတ် / ကုဒ်ရိုက်ထည့်ရန်',
                            ),
                            DesktopCommand.barcode,
                          ),
                        ),
                      ),
                      if (AppCapabilities.windows)
                        TextButton(
                          onPressed: () => rowsFocus.requestFocus(),
                          child: Text(
                            _t(
                              "Items · F5 / ↑ ↓ / Enter",
                              "ပစ္စည်းများ · F5 / ↑ ↓ / Enter",
                            ),
                          ),
                        ),
                      Focus(
                        focusNode: rowsFocus,
                        child: Column(
                          children: [
                            for (int i = 0; i < lines.length; i++)
                              Card(
                                color:
                                    AppCapabilities.windows && selectedLine == i
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : null,
                                child: DesktopListTile(
                                  onTap: enabled
                                      ? () async {
                                          selectedLine = i;
                                          await (_pendingLine != null
                                              ? _resumeItem()
                                              : editLine(i));
                                        }
                                      : null,
                                  title: Text(
                                    "${lines[i]['item_code']} · ${lines[i]['item_name']}",
                                  ),
                                  subtitle: Text(
                                    "${lines[i]['qty']} × ${_money(lines[i]['price'] as int)} = ${_money((lines[i]['qty'] as int) * (lines[i]['price'] as int))}\n${_t('Stock', 'လက်ကျန်')}: ${stockOf(lines[i]['product_id'] as int)}${(lines[i]['qty'] as int) > stockOf(lines[i]['product_id'] as int) ? _t(' — exceeds stock; draft only', ' — လက်ကျန်ထက်များသည်။ Draft သာဖြစ်သည်။') : ''}",
                                  ),
                                  trailing: IconButton(
                                    onPressed: enabled && _pendingLine == null
                                        ? () {
                                            setState(() => lines.removeAt(i));
                                            _touch();
                                          }
                                        : null,
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: discountType,
                        decoration: InputDecoration(
                          labelText: _t('Discount Type', 'လျှော့ဈေးအမျိုးအစား'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'amount',
                            child: Text(
                              '${_t('Amount', 'ငွေပမာဏ')} (${AppCurrency.displayCode})',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'percent',
                            child: Text(
                              _t(
                                'Percent (whole %)',
                                'ရာခိုင်နှုန်း (ပြည့်ကိန်း %)',
                              ),
                            ),
                          ),
                        ],
                        onChanged: enabled
                            ? (v) {
                                if (v != null) {
                                  setState(() => discountType = v);
                                  _touch();
                                }
                              }
                            : null,
                      ),
                      TextFormField(
                        focusNode: discountFocus,
                        controller: discount,
                        enabled: enabled,
                        inputFormatters: const [AmountInputFormatter()],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _t('Discount', 'လျှော့ဈေး'),
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final n = parsedDiscount;
                          if (n == null ||
                              n < 0 ||
                              n > 9000000000000 ||
                              (discountType == 'percent' && n > 100) ||
                              discountAmount > subtotal) {
                            return _t(
                              'Check the discount amount or percent.',
                              'လျှော့ဈေးပမာဏ သို့မဟုတ် ရာခိုင်နှုန်း စစ်ပါ။',
                            );
                          }
                          return null;
                        },
                      ),
                      if (discountType == 'percent')
                        Text(
                          _t(
                            'Percentage discount rounds down to the smallest supported currency unit.',
                            'ရာခိုင်နှုန်းလျှော့ဈေးကို အငယ်ဆုံးငွေယူနစ်အထိ အောက်ဘက်ချ၍ တွက်ပါသည်။',
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        '${_t('Subtotal', 'စုစုပေါင်း')}: ${_money(subtotal)}',
                      ),
                      Text(
                        '${_t('Discount', 'လျှော့ဈေး')}: ${_money(discountAmount)}',
                      ),
                      AmountSummary(
                        label: _t('Total Amount', 'ကျသင့်ငွေ'),
                        amount: subtotal - discountAmount,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_t('Paid', 'ပေးချေပြီး')}: ${_money(desktopPaidAmount)}',
                      ),
                      Text(
                        '${_t('Balance', 'ကျန်ငွေ')}: ${_money(desktopBalance)}',
                      ),
                      OutlinedButton.icon(
                        key: const ValueKey('mobile-sale-payment'),
                        onPressed: enabled && choicesReady
                            ? desktopTakePayment
                            : null,
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(_t('Payment', 'ငွေပေးချေမည်')),
                      ),
                      if (loading) const LinearProgressIndicator(),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      if (!choicesReady && !loading)
                        TextButton(
                          onPressed: saving ? null : loadChoices,
                          child: Text(
                            _t('Reload choices', 'ရွေးချယ်စရာများ ပြန်ဖတ်ရန်'),
                          ),
                        ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: enabled && choicesReady
                            ? () => save()
                            : null,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          saving
                              ? _t('Saving...', 'သိမ်းနေသည်…')
                              : desktopHint(
                                  _t('Save Draft', 'Draft သိမ်းမည်'),
                                  DesktopCommand.saveDraft,
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        key: const ValueKey('mobile-confirm-sale'),
                        onPressed: enabled && choicesReady
                            ? () => save(openPayment: true)
                            : null,
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(
                          desktopHint(
                            _t(
                              'Confirm Sale',
                              'အရောင်းအတည်ပြုမည်',
                            ),
                            DesktopCommand.confirm,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
