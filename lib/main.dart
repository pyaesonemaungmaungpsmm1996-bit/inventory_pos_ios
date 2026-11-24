import 'live_sale_sync.dart';

import 'batch_barcode_labels_page.dart';
import 'sale_invoice_history_page.dart';
import 'desktop_ui.dart';
import 'desktop_navigation.dart';
import 'desktop_workspace.dart';
import 'desktop_runtime.dart';
import 'desktop_shortcuts.dart';
import 'app_capabilities.dart';
import 'desktop_viewport.dart';
import 'app_updates_page.dart';
import 'voucher_lookup_page.dart';
import 'item_catalog_page.dart';
import 'about_page.dart';
import 'simple_setup_page.dart';
import 'pos_navigation_bar.dart';
import 'dashboard_page.dart';
import 'sale_confirmation_page.dart';
import 'brand_logo.dart';
import 'app_theme.dart';
import 'user_guide_page.dart';
import 'feedback_page.dart';
import 'provider_connection.dart';
import 'stock_balance_page.dart';
import 'shared_pos_page.dart';
import 'shared_pos_session.dart';
import 'shared_pos_connection.dart';
import 'online_account_service.dart';
import 'stock_sync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_currency.dart';
import 'app_datetime.dart';
import 'invoice_printer_page.dart';
import 'app_database.dart';
import 'app_language.dart';
import 'contacts_page.dart';
import 'customer_ledger_page.dart';
import 'employees_page.dart';
import 'expenses_page.dart';
import 'expense_summary_page.dart';
import 'sales_reports_page.dart';
import 'data_export_page.dart';
import 'backup_page.dart';
import 'cloud_backup_page.dart';
import 'auto_backup_scheduler.dart';
import 'money_ledger_page.dart';
import 'supplier_ledger_page.dart';
import 'account_transfer_page.dart';
import 'other_money_page.dart';
import 'balance_check_page.dart';
import 'categories_page.dart';
import 'activity_history_page.dart';
import 'activity_repository.dart';
import 'account_settings_page.dart';
import 'subscription_banner.dart';
import 'inventory_page.dart';
import 'money_accounts_page.dart';
import 'purchase_page.dart';
import 'sale_invoices_page.dart';
import 'sale_returns_page.dart';
import 'stock_transfer_page.dart';
import 'stock_adjustment_page.dart';

final themePreference = ValueNotifier<ThemeMode>(ThemeMode.system);
final settingsStorage = SharedPreferencesAsync();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final savedTheme = await settingsStorage.getString('theme_mode');

    themePreference.value = switch (savedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  } catch (_) {
    themePreference.value = ThemeMode.system;
  }
  await AppLanguage.load();
  runApp(const _CurrencyBootstrap());
  unawaited(AutoBackupScheduler.start());
  LiveSaleSync.start(() => AppDatabase.instance.database);
}

class _CurrencyBootstrap extends StatefulWidget {
  const _CurrencyBootstrap({this.embedded = false});
  final bool embedded;
  @override
  State<_CurrencyBootstrap> createState() => _CurrencyBootstrapState();
}

class _CurrencyBootstrapState extends State<_CurrencyBootstrap> {
  late Future<void> ready;
  @override
  void initState() {
    super.initState();
    ready = load();
  }

  Future<void> load() async {
    await DesktopRuntime.initialize();
    final profile = await AppDatabase.instance.getBusinessProfile();
    AppDateTime.configure(profile['timezone_id'] as String);
    AppCurrency.apply(profile);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: ready,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        return widget.embedded ? const HomePage() : const InventoryPosApp();
      }
      final loading = DesktopScaffold(
        body: Center(
          child: snapshot.hasError
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        AppLanguage.current.value == 'my'
                            ? 'လုပ်ငန်းဆက်တင်များ မဖတ်နိုင်ပါ။ စာရင်းမဖျက်ဘဲ ပြန်စမ်းပါ။'
                            : 'Could not load business settings. Keep your data and retry.',
                      ),
                      TextButton(
                        onPressed: () => setState(() => ready = load()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
      return widget.embedded ? loading : MaterialApp(home: loading);
    },
  );
}

class InventoryPosApp extends StatelessWidget {
  const InventoryPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        themePreference,
        AppLanguage.current,
        AppCurrency.current,
        AppDateTime.current,
      ]),
      builder: (context, child) {
        final mode = themePreference.value;
        return MaterialApp(
          navigatorObservers: AppCapabilities.windows
              ? [desktopOuterRouteObserver]
              : const [],
          debugShowCheckedModeBanner: false,
          title: 'Toe Pwar POS',
          builder: (context, child) => AppCapabilities.windows
              ? DesktopViewport(child: child ?? const SizedBox.shrink())
              : child ?? const SizedBox.shrink(),
          themeMode: mode,
          theme: AppTheme.build(
            Brightness.light,
            desktop: AppCapabilities.windows,
          ),
          darkTheme: AppTheme.build(
            Brightness.dark,
            desktop: AppCapabilities.windows,
          ),
          home: AppCapabilities.windows
              ? DesktopWorkspace(
                  child: Navigator(
                    observers: [desktopRouteObserver],
                    onGenerateRoute: (_) => MaterialPageRoute<void>(
                      builder: (_) =>
                          const OptionalUpdateHost(child: HomePage()),
                    ),
                  ),
                )
              : const OptionalUpdateHost(child: HomePage()),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int selectedPage = 0;
  final dashboardKey = GlobalKey<DashboardPageState>();
  int? viewedBranch;
  bool openingSale = false;
  StreamSubscription<AuthState>? _sharedAuth;
  Timer? _sharedRetry;
  String? _sharedUser;
  bool _connecting = false;
  bool _sharedRequired = true;
  String? _syncStatus;
  List<SharedBranch> _sharedBranches = [];
  SharedBranch? _branch;

  Future<void> _watchSharedAccount() async {
    try {
      await OnlineAccounts.initialize();
      if (!mounted) return;
      _sharedAuth = OnlineAccounts.client.auth.onAuthStateChange.listen(
        (_) => _accountChanged(),
        onError: (Object _) {},
      );
      _accountChanged();
      _sharedRetry = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_sharedRequired && SharedPosSession.current == null) {
          unawaited(_connectShared());
        }
      });
    } catch (_) {
      if (mounted) setState(() => _sharedRequired = false);
    }
  }

  void _accountChanged() {
    final user = OnlineAccounts.client.auth.currentUser?.id;
    if (_sharedUser == user && (user != null || !_sharedRequired)) return;
    setState(() {
      _sharedUser = user;
      _branch = null;
      _sharedBranches = [];
      _sharedRequired = user != null;
      _syncStatus = null;
      SharedPosSession.current = null;
    });
    unawaited(_connectShared());
  }

  Future<void> _connectShared() async {
    final user = _sharedUser;
    if (_connecting || user == null || !mounted) return;
    setState(() => _connecting = true);
    try {
      final connector = SharedPosConnection(StockSyncApi(OnlineAccounts.client), user);
      final branches = await connector.branches();
      final preferences = SharedPreferencesAsync();
      final saved = await preferences.getString('shared-pos-branch:$user');
      if (!mounted || _sharedUser != user) return;
      final branch = branches.where((item) => item.branch == (_branch?.branch ?? saved)).firstOrNull ??
          (branches.length == 1 ? branches.single : null);
      setState(() {
        _sharedBranches = branches;
        _sharedRequired = branches.isNotEmpty;
        _branch = branch;
        _syncStatus = null;
      });
      if (branch == null) return;
      final session = await connector.connect(branch);
      if (!mounted || _sharedUser != user) return;
      setState(() {
        SharedPosSession.current = session;
        _syncStatus = session == null ? 'Waiting for device approval' : null;
      });
    } catch (_) {
      if (mounted && _sharedUser == user) {
        setState(() => _syncStatus = 'Unable to connect to shared POS. Retrying automatically.');
      }
    } finally {
      if (mounted) {
        setState(() => _connecting = false);
        if (_sharedUser != user) unawaited(_connectShared());
      }
    }
  }

  Future<void> _selectSharedBranch(SharedBranch? branch) async {
    final user = _sharedUser;
    if (branch == null || user == null || _connecting) return;
    setState(() {
      _branch = branch;
      SharedPosSession.current = null;
    });
    await _connectShared();
    if (mounted && _sharedUser == user && _branch == branch) {
      await SharedPreferencesAsync().setString('shared-pos-branch:$user', branch.branch);
    }
  }

  Widget _sharedConnectionStatus() => Center(
    child: Text(AppLanguage.text(_connecting
        ? 'Connecting to shared POS…'
        : _syncStatus ?? 'Choose your shop and branch on the Dashboard.')),
  );

  @override
  void initState() {
    super.initState();
    ProviderConnection.start();
    unawaited(_watchSharedAccount());
    if (AppCapabilities.windows) {
      desktopWorkspaceNavigation.onSelected = selectDesktopMenu;
      desktopWorkspaceNavigation.onSaleAction = openDesktopSaleMenu;
      desktopWorkspaceNavigation.onGuide = () => Navigator.of(context)
          .push<void>(MaterialPageRoute(builder: (_) => const UserGuidePage()));
      desktopWorkspaceNavigation.selected = selectedPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) desktopWorkspaceNavigation.refresh();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _offerBusinessSetup();
      if (!mounted) return;
      await _offerUnfinishedSale();
    });
  }

  Future<void> openDesktopSaleMenu(int index) async {
    await selectDesktopMenu(1);
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    desktopWorkspaceNavigation.selectedSale = index;
    desktopWorkspaceNavigation.refresh();
    switch (index) {
      case 0:
        await newSale();
        return;
      case 1:
        await openPage('Sale Invoice', const SaleInvoiceHistoryPage());
        return;
      case 2:
        await openPage('Sale Return', const SaleReturnsPage());
        return;
      case 3:
        await openPage('Customer Payments', const CustomerLedgerPage());
        return;
    }
  }

  Future<void> selectDesktopMenu(int index) async {
    if (ModalRoute.of(context)?.isCurrent != true) {
      final home = ModalRoute.of(context);
      if (home == null ||
          !await desktopRouteObserver.returnTo(home) ||
          !mounted) {
        return;
      }
    }
    if (selectedPage != index) desktopWorkspaceNavigation.selectedEntry = null;
    setState(() => selectedPage = index);
    desktopWorkspaceNavigation.selected = index;
    desktopWorkspaceNavigation.refresh();
  }

  Future<void> openDesktopModuleEntry(
    int index,
    DesktopModuleLink entry,
  ) async {
    await selectDesktopMenu(index);
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    desktopWorkspaceNavigation.selectedEntry = entry.id;
    if (index == 1) {
      desktopWorkspaceNavigation.selectedSale = [
        'New Sale',
        'Sale Invoice',
        'Sale Return',
        'Customer Payments',
      ].indexOf(entry.id);
    }
    desktopWorkspaceNavigation.refresh();
    entry.onTap?.call();
  }

  @override
  void dispose() {
    unawaited(_sharedAuth?.cancel());
    _sharedRetry?.cancel();
    if (AppCapabilities.windows) {
      desktopWorkspaceNavigation.onSelected = null;
      desktopWorkspaceNavigation.onSaleAction = null;
      desktopWorkspaceNavigation.onModuleAction = null;
      desktopWorkspaceNavigation.sections = {};
      desktopWorkspaceNavigation.onGuide = null;
    }
    super.dispose();
  }

  Future<void> _offerBusinessSetup() async {
    final profile = await AppDatabase.instance.getBusinessProfile();
    if (!mounted || profile['configured'] == 1) return;
    await showSimpleSetup();
  }

  Future<void> showSimpleSetup() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SimpleSetupPage()),
    );
    if (mounted) await dashboardKey.currentState?.reload();
  }

  Future<void> _offerUnfinishedSale() async {
    try {
      final pending = await AppDatabase.instance.getSaleRecoveries();
      if (!mounted || pending.isEmpty) return;
      final resume = await showDialog<bool>(
        context: context,
        builder: (c) => DesktopDialog(
          title: Text(
            AppLanguage.current.value == 'my'
                ? 'ရေးလက်စဘောင်ချာကို ဆက်ရေးမလား?'
                : 'Resume unfinished invoice?',
          ),
          content: Text(
            AppLanguage.current.value == 'my'
                ? 'နောက်ဆုံး Auto-save ထားသော အရောင်းဘောင်ချာ ရှိပါသည်။'
                : 'An unfinished sale is saved on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(
                AppLanguage.current.value == 'my' ? 'နောက်မှ' : 'Later',
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(
                AppLanguage.current.value == 'my' ? 'ဆက်ရေးမည်' : 'Resume',
              ),
            ),
          ],
        ),
      );
      if (!mounted || resume != true) return;
      openPage(
        'Sale Invoices',
        SaleInvoicesPage(resumeKey: pending.first['recovery_key'] as String),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguage.current.value == 'my'
                ? 'ရေးလက်စဘောင်ချာ စစ်မရပါ။ Sale မှ ပြန်စမ်းပါ။'
                : 'Could not check unfinished invoices. Retry from Sale.',
          ),
        ),
      );
    }
  }

  Future<void> openPage(String title, Widget page) async {
    final session = SharedPosSession.current;
    final sharedKind = switch (page) {
      SaleInvoicesPage() => SharedPosPageKind.sale,
      PurchasePage() => SharedPosPageKind.purchase,
      SaleInvoiceHistoryPage() => SharedPosPageKind.sales,
      PurchaseHistoryPage() => SharedPosPageKind.purchases,
      StockBalancePage() => SharedPosPageKind.stock,
      MoneyAccountsPage() => SharedPosPageKind.accounts,
      AccountTransferPage() => SharedPosPageKind.transfer,
      CustomerLedgerPage() => SharedPosPageKind.customerBalances,
      SupplierLedgerPage() => SharedPosPageKind.supplierBalances,
      ExpensesPage(:final historyOnly) =>
        historyOnly ? SharedPosPageKind.expenses : SharedPosPageKind.expense,
      _ => null,
    };
    final usesOriginalLayout =
        sharedKind == SharedPosPageKind.stock ||
        sharedKind == SharedPosPageKind.purchase ||
        sharedKind == SharedPosPageKind.purchases ||
        sharedKind == SharedPosPageKind.sales ||
        sharedKind == SharedPosPageKind.expense ||
        sharedKind == SharedPosPageKind.expenses ||
        sharedKind == SharedPosPageKind.customerBalances ||
        sharedKind == SharedPosPageKind.supplierBalances ||
        sharedKind == SharedPosPageKind.accounts;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) {
          if (session != null && sharedKind == SharedPosPageKind.sale) {
            return sharedSaleForm(session);
          }
          if (session != null && sharedKind == SharedPosPageKind.stock) {
            return page;
          }
          return DesktopScaffold(
            appBar: AppBar(title: Text(AppLanguage.text(title))),
            body: sharedKind == null
                ? page
                : session != null && !usesOriginalLayout
                ? SharedPosPage(session: session, kind: sharedKind)
                : session == null && _sharedRequired
                ? _sharedConnectionStatus()
                : page,
          );
        },
      ),
    );
    if (mounted) {
      if (session != SharedPosSession.current) setState(() {});
      await dashboardKey.currentState?.reload();
    }
  }

  Future<void> dashboardAction(String action, int branch) async {
    switch (action) {
      case 'purchase':
        await openPage('Purchase', PurchasePage(initialBranchId: branch));
        return;
      case 'stock':
        await openPage('Balance Stock', StockBalancePage(initialBranchId: branch));
        return;
      case 'customers':
        await openPage('Customers', const ContactsPage(kind: 'customer'));
        return;
      case 'reports':
        await openPage(
          'Sales Reports',
          SalesReportsPage(initialBranchId: branch),
        );
        return;
      case 'collections':
        await openPage(
          'Customer Payments',
          CustomerLedgerPage(initialBranchId: branch),
        );
        return;
      case 'transfer':
        await openPage(
          'Stock Transfer',
          StockTransferPage(initialBranchId: branch),
        );
        return;
      case 'expenses':
        await openPage('Expense', ExpensesPage(initialBranchId: branch));
        return;
      case 'account':
        if (mounted) setState(() => selectedPage = 5);
        return;
    }
  }

  Future<void> recentTransaction(Map<String, Object?> row, int branch) async {
    if (row['kind'] == 'sale') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ConfirmedSaleDetailPage(saleId: row['id'] as int),
        ),
      );
    } else if (row['kind'] == 'purchase') {
      await openPage(
        'Purchase History',
        PurchaseHistoryPage(
          initialPurchaseId: row['id'] as int,
          initialBranchId: branch,
        ),
      );
    } else {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ReceiptDetail(receiptId: row['id'] as int),
        ),
      );
    }
  }

  Future<void> newSale() async {
    if (openingSale) return;
    setState(() => openingSale = true);
    try {
      final selected =
          viewedBranch ?? await AppDatabase.instance.getDefaultBranchId();
      if (!mounted) return;
      await openPage(
        'New Sale',
        SaleInvoicesPage(initialBranchId: selected, startNewSale: true),
      );
    } finally {
      if (mounted) setState(() => openingSale = false);
    }
  }

  void openLocalBackups() {
    openPage(
      'Backup & Restore',
      BackupPage(
        onRestored: () {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(
              builder: (_) => const _CurrencyBootstrap(embedded: true),
            ),
            (_) => false,
          );
        },
      ),
    );
  }

  void openPendingPage(String title) {
    openPage(
      title,
      const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'This feature will be connected in the next steps.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget menuTile(
    String title,
    IconData icon, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    if (AppCapabilities.windows) {
      return DesktopModuleLink(
        id: title,
        title: title,
        icon: icon,
        subtitle: subtitle,
        onTap: onTap ?? () => openPendingPage(title),
      );
    }
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 1,
      shadowColor: const Color(0x160C2450),
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: DesktopListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: Text(
          AppLanguage.text(title),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        subtitle: subtitle == null ? null : Text(AppLanguage.text(subtitle)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap ?? () => openPendingPage(title),
      ),
    );
  }

  Widget buildDashboard() {
    final session = SharedPosSession.current;
    if (_sharedRequired || session != null) {
      return Column(
        children: [
          if (_sharedBranches.length > 1)
            DropdownButton<SharedBranch>(
              value: _branch,
              hint: Text(AppLanguage.text('Shop and branch')),
              items: [
                for (final branch in _sharedBranches)
                  DropdownMenuItem(value: branch, child: Text(branch.label)),
              ],
              onChanged: _connecting ? null : _selectSharedBranch,
            ),
          Expanded(
            child: session == null
                ? _sharedConnectionStatus()
                : DashboardPage(
                    key: ValueKey(session),
                    sharedSession: session,
                    onAction: dashboardAction,
                    onBranch: (_) {},
                    onRecent: (row, _) async {
                      switch (row['kind']) {
                        case 'sale':
                          await openPage('Sale History', const SaleInvoiceHistoryPage());
                        case 'purchase':
                          await openPage('Purchase History', const PurchaseHistoryPage());
                        case 'expense':
                          await openPage('Expense', const ExpensesPage(historyOnly: true));
                      }
                    },
                  ),
          ),
        ],
      );
    }
    return DashboardPage(
      key: dashboardKey,
      onAction: dashboardAction,
      onRecent: recentTransaction,
      onBranch: (id) {
        viewedBranch = id;
        if (AppCapabilities.windows) {
          desktopWorkspaceNavigation.branchId = id;
          desktopWorkspaceNavigation.refresh();
        }
      },
    );
  }

  Widget buildSale() {
    return DesktopListView(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 100),
      children: [
        menuTile(
          'New Sale',
          Icons.add_shopping_cart_outlined,
          subtitle: 'Create a new sale invoice',
          onTap: newSale,
        ),
        menuTile(
          'Sale Invoice',
          Icons.receipt_long_outlined,
          subtitle: 'All saved invoices and drafts',
          onTap: () => openPage('Sale Invoice', const SaleInvoiceHistoryPage()),
        ),
        menuTile(
          'Sale Return',
          Icons.assignment_return_outlined,
          subtitle: 'Return sold items and refund the customer',
          onTap: () => openPage('Sale Return', const SaleReturnsPage()),
        ),
        menuTile(
          'Customer Payments',
          Icons.account_balance_wallet_outlined,
          subtitle: 'Receive outstanding payments',
          onTap: () =>
              openPage('Customer Payments', const CustomerLedgerPage()),
        ),
      ],
    );
  }

  Widget buildInventory() {
    return DesktopListView(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 100),
      children: [
        menuTile(
          'Barcode Labels',
          Icons.print_outlined,
          subtitle: 'Select items and print customized labels',
          onTap: () =>
              openPage('Barcode Labels', const BatchBarcodeLabelsPage()),
        ),
        menuTile(
          'Item Name',
          Icons.list_alt_outlined,
          subtitle: 'Search, edit items and print labels',
          onTap: () => Navigator.push<void>(
            context,
            MaterialPageRoute(builder: (_) => const ItemCatalogPage()),
          ),
        ),
        menuTile(
          'Purchase',
          Icons.shopping_cart_outlined,
          subtitle: 'Create a purchase',
          onTap: () => openPage('Purchase', const PurchasePage()),
        ),
        menuTile(
          'Purchase History',
          Icons.history,
          onTap: () =>
              openPage('Purchase History', const PurchaseHistoryPage()),
        ),
        menuTile(
          'Balance Stock',
          Icons.fact_check_outlined,
          subtitle: 'Check stock by category, brand and branch',
          onTap: () => openPage('Balance Stock', const StockBalancePage()),
        ),
        menuTile(
          'Stock & Products',
          Icons.inventory_2_outlined,
          subtitle: 'Products, stock-in and stock history',
          onTap: () => openPage('Stock & Products', const InventoryPage()),
        ),
        menuTile(
          'Stock Transfer',
          Icons.swap_horiz,
          subtitle: 'Transfer out and receive stock',
          onTap: () => openPage('Stock Transfer', const StockTransferPage()),
        ),
        menuTile(
          'Stock Adjustment',
          Icons.tune,
          subtitle: 'Damage and stock corrections',
          onTap: () =>
              openPage('Stock Adjustment', const StockAdjustmentPage()),
        ),
      ],
    );
  }

  Widget buildExpense() {
    return DesktopListView(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 100),
      children: [
        menuTile(
          'Expenses',
          Icons.payments_outlined,
          subtitle: 'Expense list and new expenses',
          onTap: () => openPage('Expenses', const ExpensesPage()),
        ),
        menuTile(
          'Expense History',
          Icons.history,
          subtitle: 'Find expense records by date, branch and category',
          onTap: () => openPage(
            'Expense History',
            const ExpensesPage(historyOnly: true),
          ),
        ),
        menuTile(
          'Expense Summary',
          Icons.pie_chart_outline,
          subtitle: 'Monthly and category summaries',
          onTap: () => openPage('Expense Summary', const ExpenseSummaryPage()),
        ),
      ],
    );
  }

  Widget buildLedger() {
    return DesktopListView(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 100),
      children: [
        menuTile(
          'Sales Reports',
          Icons.bar_chart,
          onTap: () => openPage('Sales Reports', const SalesReportsPage()),
        ),
        menuTile(
          'Cash / Bank / Wallet Ledger',
          Icons.account_balance_outlined,
          onTap: () =>
              openPage('Cash / Bank / Wallet Ledger', const MoneyLedgerPage()),
        ),
        menuTile(
          'Customer Ledger',
          Icons.people_outline,
          onTap: () => openPage('Customer Ledger', const CustomerLedgerPage()),
        ),
        menuTile(
          'Supplier Ledger',
          Icons.local_shipping_outlined,
          onTap: () => openPage('Supplier Ledger', const SupplierLedgerPage()),
        ),
        menuTile(
          'Account Transfer',
          Icons.swap_horiz,
          onTap: () =>
              openPage('Account Transfer', const AccountTransferPage()),
        ),
        menuTile(
          'Other Money In / Out',
          Icons.sync_alt,
          onTap: () => openPage('Other Money In / Out', const OtherMoneyPage()),
        ),
        menuTile(
          'Balance Check',
          Icons.fact_check_outlined,
          onTap: () => openPage('Balance Check', const BalanceCheckPage()),
        ),
      ],
    );
  }

  Future<void> logPreference(String key, String before, String after) async {
    try {
      await ActivityRepository.preference(key, before, after);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.current.value == 'my'
                  ? 'Setting သိမ်းပြီးသော်လည်း Activity မမှတ်နိုင်ပါ။'
                  : 'Setting saved, but activity could not be recorded.',
            ),
          ),
        );
      }
    }
  }

  Future<void> chooseLanguage() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AppCapabilities.windows
            ? DesktopDialog(
                title: Text(AppLanguage.text('Language')),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, 'en'),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('English'),
                      ),
                    ),
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, 'my'),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('မြန်မာ'),
                      ),
                    ),
                  ],
                ),
              )
            : SimpleDialog(
                title: Text(AppLanguage.text('Language')),
                children: [
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialogContext, 'en'),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('English'),
                    ),
                  ),
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialogContext, 'my'),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('မြန်မာ'),
                    ),
                  ),
                ],
              );
      },
    );

    if (selected == null || !mounted) return;

    final previousLanguage = AppLanguage.current.value;
    try {
      await AppLanguage.change(selected);
      await logPreference('language', previousLanguage, selected);
      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save language. Please retry.')),
      );
    }
  }

  Future<void> chooseTheme() async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) {
        return AppCapabilities.windows
            ? DesktopDialog(
                title: const Text('Choose Theme'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in ThemeMode.values)
                      SimpleDialogOption(
                        onPressed: () {
                          Navigator.pop(dialogContext, option);
                        },
                        child: DesktopListTile(
                          leading: Icon(
                            option == ThemeMode.light
                                ? Icons.light_mode_outlined
                                : option == ThemeMode.dark
                                ? Icons.dark_mode_outlined
                                : Icons.settings_brightness_outlined,
                          ),
                          title: Text(
                            option == ThemeMode.light
                                ? 'Light'
                                : option == ThemeMode.dark
                                ? 'Dark'
                                : 'System',
                          ),
                          trailing: themePreference.value == option
                              ? const Icon(Icons.check)
                              : null,
                        ),
                      ),
                  ],
                ),
              )
            : SimpleDialog(
                title: const Text('Choose Theme'),
                children: [
                  for (final option in ThemeMode.values)
                    SimpleDialogOption(
                      onPressed: () {
                        Navigator.pop(dialogContext, option);
                      },
                      child: DesktopListTile(
                        leading: Icon(
                          option == ThemeMode.light
                              ? Icons.light_mode_outlined
                              : option == ThemeMode.dark
                              ? Icons.dark_mode_outlined
                              : Icons.settings_brightness_outlined,
                        ),
                        title: Text(
                          option == ThemeMode.light
                              ? 'Light'
                              : option == ThemeMode.dark
                              ? 'Dark'
                              : 'System',
                        ),
                        trailing: themePreference.value == option
                            ? const Icon(Icons.check)
                            : null,
                      ),
                    ),
                ],
              );
      },
    );

    if (selected == null || !mounted) return;

    final previousTheme = themePreference.value.name;
    try {
      await settingsStorage.setString('theme_mode', selected.name);
      await logPreference('theme', previousTheme, selected.name);

      if (!mounted) return;
      themePreference.value = selected;
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save theme. Please retry.')),
      );
    }
  }

  Widget buildAccount() {
    Widget settingsRow(
      String title,
      IconData icon, {
      String? subtitle,
      VoidCallback? onTap,
    }) => AppCapabilities.windows
        ? DesktopModuleLink(
            id: title,
            title: title,
            icon: icon,
            subtitle: subtitle,
            onTap: onTap,
          )
        : DesktopListTile(
            leading: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 23,
            ),
            title: Text(
              AppLanguage.text(title),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            subtitle: subtitle == null
                ? null
                : Text(AppLanguage.text(subtitle)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: onTap,
          );
    return DesktopListView(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 100),
      children: [
        const AccountEntryCard(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            AppLanguage.current.value == 'my'
                ? 'လုပ်ငန်းနှင့် App ဆက်တင်များ'
                : 'Business & app settings',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              settingsRow(
                'Money Accounts',
                Icons.account_balance_wallet_outlined,
                onTap: () =>
                    openPage('Money Accounts', const MoneyAccountsPage()),
              ),
              settingsRow(
                'Employees & Users',
                Icons.badge_outlined,
                onTap: () =>
                    openPage('Employees & Users', const EmployeesPage()),
              ),
              settingsRow(
                'Customers',
                Icons.people_outline,
                onTap: () =>
                    openPage('Customers', const ContactsPage(kind: 'customer')),
              ),
              settingsRow(
                'Suppliers',
                Icons.local_shipping_outlined,
                onTap: () =>
                    openPage('Suppliers', const ContactsPage(kind: 'supplier')),
              ),
              settingsRow(
                'Categories',
                Icons.category_outlined,
                onTap: () => openPage('Categories', const CategoriesPage()),
              ),
              settingsRow(
                'Invoice & Printer',
                Icons.print_outlined,
                onTap: () => openPage(
                  'Invoice & Printer',
                  const InvoicePrinterSettingsPage(),
                ),
              ),
              settingsRow(
                'Language',
                Icons.language,
                subtitle: 'English / Myanmar',
                onTap: chooseLanguage,
              ),
              settingsRow(
                'Theme',
                Icons.palette_outlined,
                subtitle: 'Light / Dark / System',
                onTap: chooseTheme,
              ),
              settingsRow(
                'Backup & Restore',
                Icons.backup_outlined,
                onTap: openLocalBackups,
              ),
              settingsRow(
                'Cloud Backup',
                Icons.cloud_upload_outlined,
                onTap: () => openPage(
                  'Cloud Backup',
                  CloudBackupPage(openLocalBackups: openLocalBackups),
                ),
              ),
              settingsRow(
                'Sync & Export',
                Icons.cloud_sync_outlined,
                onTap: () => openPage('Export Reports', const DataExportPage()),
              ),
              settingsRow(
                'Activity History',
                Icons.history,
                onTap: () =>
                    openPage('Activity History', const ActivityHistoryPage()),
              ),
            ],
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              settingsRow(
                'App Updates',
                Icons.system_update,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AppUpdatesPage(
                      service: OptionalUpdateHost.serviceOf(context),
                    ),
                  ),
                ),
              ),
              settingsRow(
                'User Guide',
                Icons.menu_book_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const UserGuidePage(),
                  ),
                ),
              ),
              settingsRow(
                'Feedback & Support',
                Icons.feedback_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const FeedbackPage()),
                ),
              ),
              settingsRow(
                'About',
                Icons.info_outline,
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutPage()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildCurrentPage() {
    if (AppCapabilities.windows && selectedPage != 0) {
      final entries = desktopWorkspaceNavigation.sections[selectedPage] ?? [];
      return DesktopModuleHub(
        key: ValueKey('desktop-module-$selectedPage'),
        title: PosNavigationBar.labels[selectedPage],
        entries: entries,
        account: selectedPage == 5 ? const AccountEntryCard() : null,
        onOpen: (entry) => openDesktopModuleEntry(selectedPage, entry),
      );
    }
    switch (selectedPage) {
      case 0:
        return buildDashboard();
      case 1:
        return buildSale();
      case 2:
        return buildInventory();
      case 3:
        return buildExpense();
      case 4:
        return buildLedger();
      case 5:
        return buildAccount();
      default:
        return buildDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppCapabilities.windows) {
      desktopWorkspaceNavigation.sections = {
        1: desktopLinks(buildSale()),
        2: desktopLinks(buildInventory()),
        3: desktopLinks(buildExpense()),
        4: desktopLinks(buildLedger()),
        5: desktopLinks(buildAccount()),
      };
      desktopWorkspaceNavigation.onModuleAction = openDesktopModuleEntry;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) desktopWorkspaceNavigation.refresh();
      });
    }
    return DesktopHomeShortcuts(
      onSelected: (index) => selectDesktopMenu(index),
      onNewSale: (selectedPage == 0 || selectedPage == 1) && !openingSale
          ? newSale
          : null,
      child: DesktopScaffold(
        appBar: AppCapabilities.windows
            ? AppBar(
                automaticallyImplyLeading: false,
                title: Text(
                  AppLanguage.text(PosNavigationBar.labels[selectedPage]),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                toolbarHeight: 50,
              )
            : AppBar(
                title: const Row(
                  children: [BrandLogo(), SizedBox(width: 12), Text('TP POS')],
                ),
                toolbarHeight: 56,
                actions: [
                  IconButton(
                    tooltip: AppLanguage.current.value == 'my'
                        ? 'ဘောင်ချာ QR စစ်ရန်'
                        : 'Scan Voucher',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () => Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VoucherLookupPage(),
                      ),
                    ),
                  ),
                ],
              ),
        body: Column(
          children: [
            const SubscriptionBanner(),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppCapabilities.windows ? 0 : 24),
                ),
                child: ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: buildCurrentPage(),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: (selectedPage == 0 || selectedPage == 1)
            ? FloatingActionButton.extended(
                tooltip: AppLanguage.current.value == 'my'
                    ? 'အရောင်းအသစ်'
                    : 'New Sale',
                onPressed: openingSale ? null : newSale,
                icon: const Icon(Icons.shopping_cart_outlined),
                label: Text(
                  AppLanguage.current.value == 'my'
                      ? 'အရောင်းအသစ်'
                      : 'New Sale',
                ),
              )
            : null,
        bottomNavigationBar: AppCapabilities.windows
            ? null
            : PosNavigationBar(
                selected: selectedPage,
                onSelected: (index) {
                  setState(() => selectedPage = index);
                },
              ),
      ),
    );
  }
}
