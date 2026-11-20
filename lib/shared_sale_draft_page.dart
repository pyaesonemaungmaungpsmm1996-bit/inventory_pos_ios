import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'desktop_ui.dart';
import 'online_account_service.dart';

class SharedDraftBranch {
  const SharedDraftBranch(
    this.business,
    this.id,
    this.installation,
    this.account,
    this.localId,
    this.name,
    this.canEdit,
  );

  final String business, id, installation, account, name;
  final int localId;
  final bool canEdit;

  static Future<List<SharedDraftBranch>> approved(
    List<Map<String, Object?>> local,
  ) async {
    await OnlineAccounts.initialize();
    final user = OnlineAccounts.client.auth.currentUser;
    if (user == null) return [];
    final installation = await OnlineAccounts.installation();
    final memberships = await OnlineAccounts.snapshot();
    if (OnlineAccounts.client.auth.currentUser?.id != user.id) return [];
    final choices = <SharedDraftBranch>[];
    for (final membership in memberships.where((m) => m['active'] == true)) {
      final role = membership['role'];
      final branches = (membership['branches'] as List? ?? []).whereType<Map>();
      final devices = (membership['devices'] as List? ?? []).whereType<Map>();
      for (final device in devices.where(
        (d) =>
            d['status'] == 'approved' &&
            d['installation_id'] == installation &&
            d['user_id'] == user.id,
      )) {
        final cloud = branches
            .where((b) => b['id'] == device['branch_id'])
            .firstOrNull;
        if (cloud == null) continue;
        final name = cloud['name'] as String;
        final matches = local
            .where(
              (b) =>
                  b['name'].toString().trim().toLowerCase() ==
                  name.trim().toLowerCase(),
            )
            .toList();
        if (matches.length != 1) continue;
        choices.add(
          SharedDraftBranch(
            membership['id'] as String,
            cloud['id'] as String,
            installation,
            user.id,
            matches.single['id'] as int,
            name,
            const ['owner', 'manager', 'cashier'].contains(role),
          ),
        );
      }
    }
    return choices
        .where((b) => choices.where((a) => a.localId == b.localId).length == 1)
        .toList();
  }

  Future<dynamic> _call(String name, [Map<String, Object?> extra = const {}]) {
    if (OnlineAccounts.client.auth.currentUser?.id != account) {
      throw StateError('The signed-in account changed. Reopen Sale Invoice.');
    }
    return OnlineAccounts.client
        .rpc(
          name,
          params: {
            'p_business': business,
            'p_branch': id,
            'p_installation': installation,
            ...extra,
          },
        )
        .timeout(const Duration(seconds: 12));
  }

  Future<List<Map<String, Object?>>> list() async {
    final rows = await _call('tp_list_shared_sale_drafts');
    return [
      for (final row in rows as List)
        {
          'shared_branch': this,
          'shared_id': row['id'],
          'branch_id': localId,
          'branch_name': name,
          'status': 'draft',
          'record_kind': 'shared_draft',
          'invoice_date': row['invoice_date'],
          'customer_name': row['customer_name'],
          'updated_at': row['updated_at'],
          'currency_code': 'MMK',
          'currency_digits': 0,
        },
    ];
  }

  Future<Map<String, Object?>> read(String id) async =>
      Map<String, Object?>.from(
        await _call('tp_get_shared_sale_draft', {'p_voucher': id}) as Map,
      );

  Future<void> save(
    String id,
    int revision,
    String request,
    Map<String, Object?> document,
  ) async {
    await _call('tp_save_shared_sale_draft', {
      'p_voucher': id,
      'p_expected_revision': revision,
      'p_request': request,
      'p_document': document,
    });
  }
}

String _uuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class SharedSaleDraftPage extends StatefulWidget {
  const SharedSaleDraftPage({super.key, required this.branch, this.id});
  final SharedDraftBranch branch;
  final String? id;

  @override
  State<SharedSaleDraftPage> createState() => _SharedSaleDraftPageState();
}

class _SharedSaleDraftPageState extends State<SharedSaleDraftPage> {
  late final String id = widget.id ?? _uuid();
  final form = GlobalKey<FormState>();
  final date = TextEditingController();
  final customer = TextEditingController();
  final remark = TextEditingController();
  final lines = <_DraftLine>[];
  Map<String, Object?> document = {};
  String? error, _lastRequest, _lastDocument;
  int revision = 0;
  bool loading = true, saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final saved = widget.id == null ? null : await widget.branch.read(id);
      if (!mounted) return;
      document = saved == null
          ? {}
          : Map<String, Object?>.from(saved['document'] as Map);
      revision = saved?['revision'] as int? ?? 0;
      date.text =
          document['invoice_date'] as String? ??
          DateTime.now().toIso8601String().substring(0, 10);
      customer.text = document['customer_name'] as String? ?? '';
      remark.text = document['remark'] as String? ?? '';
      for (final line in lines) {
        line.dispose();
      }
      lines
        ..clear()
        ..addAll([
          for (final item in (document['items'] as List? ?? []))
            _DraftLine(Map<String, Object?>.from(item as Map)),
        ]);
      _lastRequest = null;
      _lastDocument = null;
    } catch (e) {
      if (mounted) error = _message(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _message(Object e) {
    if (e is PostgrestException && e.code == '40001') {
      return 'Another device saved a newer version. Reload before editing again.';
    }
    if (e is PostgrestException) return e.message;
    if (e is FormatException) return e.message;
    return 'Could not complete the change. Check the connection and retry.';
  }

  Future<void> _save() async {
    if (saving ||
        !widget.branch.canEdit ||
        !(form.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final next = <String, Object?>{
        ...document,
        'invoice_date': date.text.trim(),
        'customer_name': customer.text.trim(),
        'remark': remark.text.trim(),
        'items': [for (final line in lines) line.value()],
      };
      final serialized = jsonEncode(next);
      if (_lastDocument != serialized) {
        _lastDocument = serialized;
        _lastRequest = _uuid();
      }
      await widget.branch.save(id, revision, _lastRequest!, next);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = _message(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    date.dispose();
    customer.dispose();
    remark.dispose();
    for (final line in lines) {
      line.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DesktopScaffold(
    appBar: AppBar(title: Text('Sale Invoice Draft · ${widget.branch.name}')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (error != null) Text(error!),
                TextFormField(
                  controller: date,
                  readOnly: !widget.branch.canEdit,
                  decoration: const InputDecoration(
                    labelText: 'Invoice date (YYYY-MM-DD)',
                  ),
                  validator: (value) {
                    final raw = value?.trim() ?? '';
                    final parsed = DateTime.tryParse(raw);
                    return parsed != null &&
                            parsed.toIso8601String().substring(0, 10) == raw
                        ? null
                        : 'Enter a valid date';
                  },
                ),
                TextFormField(
                  controller: customer,
                  readOnly: !widget.branch.canEdit,
                  decoration: const InputDecoration(labelText: 'Customer'),
                ),
                TextFormField(
                  controller: remark,
                  readOnly: !widget.branch.canEdit,
                  decoration: const InputDecoration(labelText: 'Remark'),
                ),
                for (final line in lines)
                  Card(
                    key: ObjectKey(line),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: line.code,
                            readOnly: !widget.branch.canEdit,
                            decoration: const InputDecoration(
                              labelText: 'Item code',
                            ),
                            validator: (value) =>
                                (value?.trim().isEmpty ?? true)
                                ? 'Enter an item code'
                                : null,
                          ),
                          TextFormField(
                            controller: line.quantity,
                            readOnly: !widget.branch.canEdit,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Quantity',
                            ),
                            validator: (value) =>
                                (int.tryParse(value ?? '') ?? 0) < 1
                                ? 'Enter a positive quantity'
                                : null,
                          ),
                          TextFormField(
                            controller: line.price,
                            readOnly: !widget.branch.canEdit,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Unit price',
                            ),
                            validator: (value) =>
                                (int.tryParse(value ?? '') ?? -1) < 0
                                ? 'Enter a valid unit price'
                                : null,
                          ),
                          if (widget.branch.canEdit)
                            TextButton(
                              onPressed: saving
                                  ? null
                                  : () {
                                      setState(() => lines.remove(line));
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => line.dispose(),
                                          );
                                    },
                              child: const Text('Remove item'),
                            ),
                        ],
                      ),
                    ),
                  ),
                if (widget.branch.canEdit && lines.length < 300)
                  OutlinedButton(
                    onPressed: saving
                        ? null
                        : () => setState(() => lines.add(_DraftLine({}))),
                    child: const Text('Add item'),
                  ),
                if (widget.branch.canEdit)
                  FilledButton(
                    onPressed: saving || (widget.id != null && revision == 0)
                        ? null
                        : _save,
                    child: const Text('Save Draft'),
                  ),
                if (widget.id != null)
                  TextButton(
                    onPressed: saving ? null : _load,
                    child: const Text('Reload saved draft'),
                  ),
              ],
            ),
          ),
  );
}

class _DraftLine {
  _DraftLine(this.saved)
    : code = TextEditingController(text: saved['item_code']?.toString() ?? ''),
      quantity = TextEditingController(text: saved['qty']?.toString() ?? '1'),
      price = TextEditingController(text: saved['price']?.toString() ?? '0');

  final Map<String, Object?> saved;
  final TextEditingController code, quantity, price;

  Map<String, Object?> value() {
    final item = code.text.trim();
    final count = int.tryParse(quantity.text.trim());
    final unitPrice = int.tryParse(price.text.trim());
    if (item.isEmpty ||
        count == null ||
        count < 1 ||
        count > 2147483647 ||
        unitPrice == null ||
        unitPrice < 0 ||
        unitPrice > 2147483647) {
      throw const FormatException(
        'Check the item code, quantity and unit price.',
      );
    }
    return {
      if (item == saved['item_code']) ...saved,
      'item_code': item,
      'qty': count,
      'price': unitPrice,
    };
  }

  void dispose() {
    code.dispose();
    quantity.dispose();
    price.dispose();
  }
}
