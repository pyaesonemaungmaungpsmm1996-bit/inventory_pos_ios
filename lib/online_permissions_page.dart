import 'desktop_ui.dart';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'online_account_service.dart';

/// Edits the online role policy; local SQLite POS enforcement is a later step.
class OnlinePermissionsPage extends StatefulWidget {
  const OnlinePermissionsPage({
    super.key,
    required this.businessId,
    required this.businessName,
  });
  final String businessId, businessName;
  @override
  State<OnlinePermissionsPage> createState() => _OnlinePermissionsPageState();
}

class _OnlinePermissionsPageState extends State<OnlinePermissionsPage> {
  List<Map<String, dynamic>> catalog = [], roles = [];
  Set<String> selection = {}, saved = {};
  String selectedRole = 'cashier', search = '';
  String? error, message;
  int revision = 0;
  bool loading = true, busy = false;
  bool get dirty =>
      selection.length != saved.length || !selection.containsAll(saved);
  String text(String en, String my) =>
      AppLanguage.current.value == 'my' ? my : en;

  @override
  void initState() {
    super.initState();
    load();
  }

  void choose(String role) {
    final config = roles.singleWhere((r) => r['role'] == role);
    selectedRole = role;
    selection = Set<String>.from(config['permissions'] as List);
    saved = Set.of(selection);
    revision = (config['revision'] as num).toInt();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = Map<String, dynamic>.from(
        await OnlineAccounts.client.rpc(
          'tp_role_configuration',
          params: {'p_business': widget.businessId},
        ) as Map,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        catalog = (result['catalog'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        roles = (result['roles'] as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        choose(selectedRole);
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<bool> discard() async {
    if (!dirty) {
      return true;
    }
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => DesktopDialog(
            title: Text(
              text(
                'Discard unsaved changes?',
                'မသိမ်းရသေးသော ပြင်ဆင်မှုများ ပယ်မလား?',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> switchRole(String? role) async {
    if (role == null || role == selectedRole) {
      return;
    }
    if (!await discard() || !mounted) {
      return;
    }
    setState(() {
      choose(role);
      message = null;
      error = null;
    });
  }

  void toggle(String key, bool enabled) {
    setState(() {
      if (enabled) {
        selection.add(key);
        // Catalog dependencies are acyclic. Selecting an action enables its view.
        var changed = true;
        while (changed) {
          final before = selection.length;
          for (final item in catalog.where(
            (r) => selection.contains(r['key']),
          )) {
            selection.addAll(List<String>.from(item['requires'] as List));
          }
          changed = before != selection.length;
        }
      } else {
        selection.remove(key);
        var changed = true;
        while (changed) {
          final before = selection.length;
          for (final item in catalog) {
            if (!(item['requires'] as List).every(selection.contains)) {
              selection.remove(item['key']);
            }
          }
          changed = before != selection.length;
        }
      }
      message = null;
    });
  }

  Future<void> save() async {
    if (busy || !dirty) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => DesktopDialog(
        title: Text('Save $selectedRole permissions?'),
        content: Text(
          text(
            'This policy applies to all staff assigned this role in this online business. Local POS action enforcement is not connected yet.',
            'ဤ Online လုပ်ငန်းထဲက Role တူဝန်ထမ်းအားလုံးအတွက် သက်ရောက်မည့် policy ဖြစ်ပါသည်။ လက်ရှိ POS လုပ်ဆောင်ခွင့်များနှင့် မချိတ်ရသေးပါ။',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final permissions = selection.toList()..sort();
    setState(() {
      busy = true;
      error = null;
      message = null;
    });
    try {
      final next = await OnlineAccounts.client.rpc(
        'tp_save_role',
        params: {
          'p_business': widget.businessId,
          'p_role': selectedRole,
          'p_permissions': permissions,
          'p_revision': revision,
        },
      );
      if (!mounted) {
        return;
      }
      setState(() {
        revision = (next as num).toInt();
        saved = Set.of(selection);
        final config = roles.singleWhere((r) => r['role'] == selectedRole);
        config['permissions'] = permissions;
        config['revision'] = revision;
        message = text('Saved on server.', 'Server တွင် သိမ်းပြီးပါပြီ။');
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = search.toLowerCase().trim();
    final visible = catalog
        .where(
          (r) =>
              query.isEmpty ||
              '${r['key']} ${r['section']} ${r['label_en']} ${r['label_my']}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    final groups = visible.map((r) => r['section'] as String).toSet();
    return DesktopScaffold(
      appBar: AppBar(
        title: const Text('Role Permissions'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: busy
              ? null
              : () async {
                  if (await discard() && mounted && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
        ),
      ),
      body: DesktopListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.businessName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text(
            'Online policy configuration · Local POS permission enforcement pending',
          ),
          const Text(
            'Owner keeps all permissions and exclusive account administration rights. Staff permissions do not grant Owner access.',
          ),
          if (loading || busy) const LinearProgressIndicator(),
          if (error != null)
            SelectableText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (message != null) Text(message!),
          if (roles.isNotEmpty)
            DropdownButton<String>(
              isExpanded: true,
              value: selectedRole,
              items: roles
                  .map(
                    (r) => DropdownMenuItem(
                      value: r['role'] as String,
                      child: Text(r['role'] as String),
                    ),
                  )
                  .toList(),
              onChanged: loading || busy ? null : switchRole,
            ),
          if (roles.isNotEmpty) ...[
            Text(
              'Revision $revision · ${selection.length} permissions${dirty ? ' · Unsaved changes' : ''}',
            ),
            TextField(
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: 'Search permissions',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => search = value),
            ),
            const SizedBox(height: 8),
            const Text(
              'Selecting an action also selects its required view permission. Turning off a view removes dependent actions.',
            ),
            for (final group in groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  group,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...visible
                  .where((r) => r['section'] == group)
                  .map(
                    (item) => CheckboxListTile(
                      title: Text(
                        text(
                          item['label_en'] as String,
                          item['label_my'] as String,
                        ),
                      ),
                      subtitle: Text(item['key'] as String),
                      value: selection.contains(item['key']),
                      onChanged: busy || loading
                          ? null
                          : (value) =>
                                toggle(item['key'] as String, value == true),
                    ),
                  ),
            ],
            FilledButton(
              onPressed: busy || loading || !dirty ? null : save,
              child: const Text('Save permissions'),
            ),
          ],
          OutlinedButton(
            onPressed: busy || loading
                ? null
                : () async {
                    if (await discard() && mounted) {
                      await load();
                    }
                  },
            child: const Text('Reload from server'),
          ),
        ],
      ),
    );
  }
}
