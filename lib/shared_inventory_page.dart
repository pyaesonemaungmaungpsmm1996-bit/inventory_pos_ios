import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'online_account_service.dart';

class SharedInventoryPage extends StatefulWidget {
  const SharedInventoryPage({
    super.key,
    required this.business,
    required this.branch,
    required this.branchName,
    required this.account,
    required this.canEdit,
  });

  final String business, branch, branchName, account;
  final bool canEdit;

  @override
  State<SharedInventoryPage> createState() => _SharedInventoryPageState();
}

class _SharedInventoryPageState extends State<SharedInventoryPage> {
  late final Timer _poll;
  late final StreamSubscription<AuthState> _auth;
  List<Map<String, dynamic>>? _products;
  String? _error;
  bool _loading = false;
  bool _editing = false;

  bool get _sameAccount =>
      OnlineAccounts.client.auth.currentUser?.id == widget.account;

  @override
  void initState() {
    super.initState();
    _auth = OnlineAccounts.client.auth.onAuthStateChange.listen((_) {
      if (!_sameAccount && mounted) {
        setState(() {
          _products = null;
          _error = 'Sign in and reopen shared inventory.';
        });
      }
    });
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
    unawaited(_refresh());
  }

  @override
  void dispose() {
    _poll.cancel();
    unawaited(_auth.cancel());
    super.dispose();
  }

  Future<dynamic> _rpc(String function, Map<String, Object?> params) async {
    final installation = await OnlineAccounts.installation();
    if (!_sameAccount || !mounted) {
      throw StateError('Sign in and reopen shared inventory.');
    }
    return OnlineAccounts.client
        .rpc(
          function,
          params: {
            'p_business': widget.business,
            'p_branch': widget.branch,
            'p_installation': installation,
            ...params,
          },
        )
        .timeout(const Duration(seconds: 12));
  }

  Future<void> _refresh() async {
    if (_loading || _editing || !mounted) return;
    _loading = true;
    try {
      final products = <Map<String, dynamic>>[];
      String? cursor;
      while (true) {
        final page = await _rpc('tp_list_shared_inventory', {
          'p_after_product': ?cursor,
        }) as List;
        products.addAll(page.cast<Map<String, dynamic>>());
        if (page.length < 100) break;
        cursor = products.last['product_id'] as String;
      }
      products.sort(
        (a, b) => (a['name'] as String).toLowerCase().compareTo(
          (b['name'] as String).toLowerCase(),
        ),
      );
      if (mounted && _sameAccount) {
        setState(() {
          _products = products;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          if (!_sameAccount ||
              (error is PostgrestException && error.code == '42501')) {
            _products = null;
          }
          _error = 'Could not load shared products. Check the connection and device approval.';
        });
      }
    } finally {
      _loading = false;
    }
  }

  Future<void> _edit([Map<String, dynamic>? product]) async {
    if (_editing || _loading || !_sameAccount) return;
    _editing = true;
    final id = product?['product_id'] as String? ?? OnlineAccounts.newId();
    var name = product?['name'] as String? ?? '';
    var price = product?['price']?.toString() ?? '';
    var saving = false;
    var conflict = false;
    String? error;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, update) {
            return PopScope(
              canPop: !saving,
              child: AlertDialog(
                title: Text(
                  product == null
                      ? 'Add shared product'
                      : 'Edit shared product',
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: name,
                      enabled: !saving && !conflict,
                      decoration: const InputDecoration(
                        labelText: 'Product name',
                      ),
                      onChanged: (value) => name = value,
                    ),
                    TextFormField(
                      initialValue: price,
                      enabled: !saving && !conflict,
                      decoration: const InputDecoration(labelText: 'Price'),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => price = value,
                    ),
                    if (error != null) Text(error!),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    child: Text(conflict ? 'Reload list' : 'Cancel'),
                  ),
                  FilledButton(
                    onPressed: saving || conflict
                        ? null
                        : () async {
                            final amount = int.tryParse(price.trim());
                            final cleanName = name.trim();
                            if (cleanName.isEmpty ||
                                cleanName.runes.length > 250 ||
                                amount == null ||
                                amount < 0 ||
                                amount > 9000000000000) {
                              update(
                                () => error = 'Enter a name and a valid whole-number price.',
                              );
                              return;
                            }
                            update(() {
                              error = null;
                              saving = true;
                            });
                            try {
                              await _rpc('tp_save_shared_product', {
                                'p_product': id,
                                'p_expected_revision':
                                    product?['revision'] ?? 0,
                                'p_name': cleanName,
                                'p_price': amount,
                              });
                              if (context.mounted) Navigator.pop(context);
                            } catch (failure) {
                              if (!context.mounted) return;
                              update(() {
                                saving = false;
                                conflict =
                                    failure is PostgrestException &&
                                    failure.code == '40001';
                                error = conflict
                                    ? 'The shared record changed. Reload the list before editing again.'
                                    : 'Save could not be confirmed. Check the connection and retry.';
                              });
                            }
                          },
                    child: Text(saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            );
          },
        ),
      );
    } finally {
      _editing = false;
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _products;
    return Scaffold(
      appBar: AppBar(
        title: Text('Shared products · ${widget.branchName}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.canEdit && products != null && _error == null)
            IconButton(
              tooltip: 'Add shared product',
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_error case final message?)
            Padding(padding: const EdgeInsets.all(12), child: Text(message)),
          if (products == null && _error == null)
            const Expanded(child: Center(child: CircularProgressIndicator())),
          if (products != null)
            Expanded(
              child: products.isEmpty
                  ? const Center(child: Text('No shared products yet.'))
                  : ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return ListTile(
                          title: Text(product['name'] as String),
                          subtitle: Text('Price: ${product['price']}'),
                          trailing: widget.canEdit && _error == null
                              ? const Icon(Icons.edit_outlined)
                              : null,
                          onTap: widget.canEdit && _error == null
                              ? () => _edit(product)
                              : null,
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
