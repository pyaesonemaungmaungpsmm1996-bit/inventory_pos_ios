import 'live_sale_sync.dart';

import 'purchase_zero_cost.dart';
import 'backup_change_tracker.dart';
import 'catalog_identity.dart';
import 'branch_phones.dart';
import 'sale_invoice_details.dart';
import 'transfer_voucher_repository.dart';
import 'voucher_permissions.dart';
import 'online_account_service.dart';
import 'account_transfer_repository.dart';
import 'other_money_repository.dart';
import 'balance_check_repository.dart';
import 'product_tracking.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'app_currency.dart';
import 'backup_files.dart';
import 'backup_gate.dart';
import 'auto_backup_store.dart';
import 'subscription_runtime.dart';
import 'sqlite_backup.dart';
import 'category_store.dart';
import 'activity_store.dart';
import 'app_datetime.dart';
import 'barcode_rules.dart';
import 'business_countries.dart';
import 'business_timezones.dart';
import 'sync_proof/local_store.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _database;
  Future<Database>? _opening;
  bool _maintenance = false;

  Future<Database> get database async {
    if (_maintenance) {
      throw StateError('Database restore is in progress');
    }
    if (_database != null) return _database!;
    final pending = _opening ??= _open();
    try {
      return _database = await pending;
    } finally {
      _opening = null;
    }
  }

  Future<void> refreshSubscriptionFence() async {
    final db = _database;
    if (db == null || !db.isOpen || _maintenance) {
      return;
    }
    try {
      await SubscriptionRuntime.apply(db);
    } catch (_) {
      /* A restore may close the old handle. */
    }
  }

  Future<Database> _open({bool recover = true}) => BackupGate.run(
    'backup_maintenance',
    () => _openUnlocked(recover: recover),
  );

  Future<Database> _openUnlocked({bool recover = true}) async {
    final folder = await getDatabasesPath();
    if (recover) {
      await BackupFiles.recover(join(folder, 'inventory_pos.db'));
    }
    return openDatabase(
      join(folder, 'inventory_pos.db'),
      version: 43,
      onConfigure: (db) async {
        final version = await db.getVersion();
        await db.execute(
          'PRAGMA foreign_keys = ${version > 0 && version < 43 ? 'OFF' : 'ON'}',
        );
      },
      onOpen: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await SubscriptionRuntime.install(db);
        await CatalogIdentity.install(db);
        await BackupChangeTracker.install(db);
        await SyncProofLocalStore.install(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL CHECK(length(trim(name)) > 0),
            price INTEGER NOT NULL CHECK(price >= 0),
            stock INTEGER NOT NULL DEFAULT 0 CHECK(stock >= 0)
          )
        ''');
        await _createBranches(db);
        await _createBranchStocks(db);
        await _createMovements(db);
        await _createMoneyAccounts(db);
        await _createEmployees(db);
        await _createContacts(db);
        await _createSaleDrafts(db);
        await _createSaleRecovery(db);
        await _createSalePosting(db);
        await _createCustomerReceipts(db);
        await _createBusinessProfile(db);
        await _createProductBarcodes(db);
        await _createInvoicePrintSnapshots(db);
        await _createProductImages(db);
        await _createPurchases(db);
        await _createCustomItemCodes(db);
        await _createSupplierCredit(db);
        await _createOpeningCorrections(db);
        await _createExpenses(db);
        await _createExpenseCategories(db);
        await _createExpenseReceipts(db);
        await _createExpenseEdits(db);
        await _createExpensePayments(db);
        await _createSaleReturns(db);
        await _addSaleReturnStaff(db);
        await _addSaleReturnCorrections(db);
        await _addPostedInvoiceVoids(db);
        await _createStockTransfers(db);
        await _addStockTransferTransport(db);
        await _addStockTransferEdits(db);
        await _addStockTransferReceiving(db);
        await _createStockAdjustments(db);
        await _createSaleExchangeLinks(db);
        await _createAccountTransfers(db);
        await _createOtherMoney(db);
        await _createBalanceChecks(db);
        await _createCategoryChanges(db);
        await ActivityStore.install(db);
        await ProductTracking.install(db);
        await TransferVoucherRepository.install(db);
        await SaleInvoiceDetails.install(db);
        await PurchaseZeroCost.install(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE stock_movements (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id INTEGER NOT NULL,
              quantity INTEGER NOT NULL CHECK(quantity > 0),
              note TEXT NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY(product_id) REFERENCES products(id)
            )
          ''');
        }
        if (oldVersion < 3) await _createBranches(db);
        if (oldVersion < 4) await _migrateLegacyStock(db);
        if (oldVersion < 5) await _createMoneyAccounts(db);
        if (oldVersion < 6) await _createEmployees(db);
        if (oldVersion < 7) await _createContacts(db);
        if (oldVersion < 8) await _createSaleDrafts(db);
        if (oldVersion < 9) await _createSaleRecovery(db);
        if (oldVersion < 10) await _createSalePosting(db);
        if (oldVersion < 11) await _createCustomerReceipts(db);
        if (oldVersion < 12) await _createBusinessProfile(db);
        if (oldVersion < 13) await _createProductBarcodes(db);
        if (oldVersion < 14) await _createInvoicePrintSnapshots(db);
        if (oldVersion < 15) await _createProductImages(db);
        if (oldVersion < 16) await _createPurchases(db);
        if (oldVersion < 17) await _createCustomItemCodes(db);
        if (oldVersion < 18) await _createSupplierCredit(db);
        if (oldVersion < 19) await _createOpeningCorrections(db);
        if (oldVersion < 20) await _createExpenses(db);
        if (oldVersion < 21) await _createExpenseCategories(db);
        if (oldVersion < 22) await _createExpenseReceipts(db);
        if (oldVersion < 23) await _createExpenseEdits(db);
        if (oldVersion < 24) await _createExpensePayments(db);
        if (oldVersion < 25) await _createSaleReturns(db);
        if (oldVersion < 26) await _addSaleReturnStaff(db);
        if (oldVersion < 27) await _addSaleReturnCorrections(db);
        if (oldVersion < 28) await _addPostedInvoiceVoids(db);
        if (oldVersion < 29) await _createStockTransfers(db);
        if (oldVersion < 30) await _addStockTransferTransport(db);
        if (oldVersion < 31) await _addStockTransferEdits(db);
        if (oldVersion < 32) await _addStockTransferReceiving(db);
        if (oldVersion < 33) await _createStockAdjustments(db);
        if (oldVersion < 34) await _createSaleExchangeLinks(db);
        if (oldVersion < 35) await _createAccountTransfers(db);
        if (oldVersion < 36) await _createOtherMoney(db);
        if (oldVersion < 37) await _createBalanceChecks(db);
        if (oldVersion < 38) await _createCategoryChanges(db);
        if (oldVersion < 39) await ActivityStore.install(db);
        if (oldVersion < 40) {
          final legacy = await SqliteBackup.schema(db);
          await db.insert('app_settings', {
            'key': 'backup_schema_v39',
            'value': legacy,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
          await ProductTracking.install(db);
        }
        if (oldVersion < 41) await TransferVoucherRepository.install(db);
        if (oldVersion < 42) await SaleInvoiceDetails.install(db);
        if (oldVersion < 43) await PurchaseZeroCost.install(db);
      },
    );
  }

  /// Restores a validated local snapshot with rollback after interruption.
  /// UI must prevent navigation during this operation and rebuild the app on success.
  Future<String> restoreLocalBackup(String source) =>
      BackupGate.run('backup_maintenance', () => _restoreLocalBackup(source));

  Future<String> _restoreLocalBackup(String source) async {
    final db = await database;
    if (_maintenance) {
      throw StateError('Database restore is already in progress');
    }
    _maintenance = true;
    final live = db.path;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final stage = '$live.stage.$stamp';
    final rollback = '$live.before_restore.$stamp.tppos';
    var closed = false;
    try {
      final schema = await SqliteBackup.schema(db);
      final version = await db.getVersion();
      if (await File(source).length() > SqliteBackup.maxBytes) {
        throw StateError('Backup is too large');
      }
      await File(source).copy(stage);
      final stagedFile = await File(stage).open(mode: FileMode.append);
      try {
        await stagedFile.flush();
      } finally {
        await stagedFile.close();
      }
      final legacy = await db.query(
        'app_settings',
        where: 'key=?',
        whereArgs: ['backup_schema_v39'],
      );
      final legacySchema = legacy.isEmpty
          ? SqliteBackup.legacy39Schema(schema)
          : legacy.single['value'] as String;
      final info = await SqliteBackup.inspect(
        stage,
        expectedSchema: schema,
        expectedVersion: version,
        legacySchema: legacySchema,
      );
      if (info.version < version && version == 43) {
        final staged = await openDatabase(
          stage,
          singleInstance: false,
          onConfigure: (d) async => d.execute('PRAGMA foreign_keys=OFF'),
        );
        try {
          await staged.transaction((t) async {
            if (info.version == 39) await ProductTracking.install(t);
            if (info.version < 41) await TransferVoucherRepository.install(t);
            if (info.version < 42) await SaleInvoiceDetails.install(t);
            await PurchaseZeroCost.install(t);
            await t.insert('app_settings', {
              'key': 'backup_schema_v39',
              'value': legacySchema,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
            await t.execute('PRAGMA user_version=43');
          });
        } finally {
          await staged.close();
        }
        await SqliteBackup.inspect(
          stage,
          expectedSchema: schema,
          expectedVersion: version,
        );
      }
      await SubscriptionRuntime.pauseAfterRestore();
      await AutoBackupStore.pause(
        'Paused after restore. Confirm the local business and enable Auto Backup again.',
      );
      await db.close();
      closed = true;
      _database = null;
      await BackupFiles.removeSidecars(live);
      await BackupFiles.begin(live, stage, rollback);
      await File(live).rename(rollback);
      await File(stage).rename(live);
      final restored = await _open(recover: false);
      _database = restored;
      final profile = await restored.query('business_profile', where: 'id = 1');
      if (profile.length != 1 ||
          !AppCurrency.precision.containsKey(profile.single['currency_code']) ||
          AppCurrency.precision[profile.single['currency_code']] !=
              profile.single['currency_digits'] ||
          (profile.single['configured'] == 1 &&
              !businessCountries.containsKey(profile.single['country_code']))) {
        throw StateError('Restored business settings are invalid');
      }
      await restored.update('activity_context', {
        'actor_id': null,
        'actor_name': 'Not recorded',
      }, where: 'id = 1');
      await ActivityStore.append(
        restored,
        key: 'backup:restore:$stamp',
        source: 'activity_events',
        record: '$stamp',
        reference: 'Local backup restore',
        module: 'system',
        action: 'restore',
        origin: 'tracked',
        after: 'Local database replaced from a validated snapshot. Previous local database retained for recovery.',
      );
      await BackupFiles.commit(live);
      return rollback;
    } catch (_) {
      if (closed) {
        await _database?.close();
        _database = null;
        await BackupFiles.recover(live);
        _database = await _open();
      }
      rethrow;
    } finally {
      _maintenance = false;
      if (await File(stage).exists() &&
          !await BackupFiles.marker(live).exists()) {
        await File(stage).delete();
      }
    }
  }

  Future<void> _createCategoryChanges(Database db) async {
    await db.execute('''CREATE TABLE category_changes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category_kind TEXT NOT NULL CHECK(category_kind IN ('product', 'expense', 'other_money')),
      category_id INTEGER NOT NULL, branch_id INTEGER,
      action TEXT NOT NULL CHECK(action IN ('baseline', 'created', 'renamed', 'archived', 'restored', 'deleted')),
      before_name TEXT NOT NULL, after_name TEXT NOT NULL,
      before_active INTEGER, after_active INTEGER, recorded_at TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX category_change_source ON category_changes(category_kind, category_id, id)',
    );
    final now = DateTime.now().toUtc().toIso8601String();
    for (final entry in [
      ('product', 'product_categories'),
      ('expense', 'expense_categories'),
      ('other_money', 'other_money_categories'),
    ]) {
      final rows = await db.query(entry.$2);
      for (final row in rows) {
        await db.insert('category_changes', {
          'category_kind': entry.$1,
          'category_id': row['id'],
          'branch_id': row['branch_id'],
          'action': 'baseline',
          'before_name': '',
          'after_name': row['name'],
          'before_active': null,
          'after_active': row['active'],
          'recorded_at': now,
        });
      }
    }
    // Inventory products created before category selection was exposed use the default.
    await db.execute(
      'UPDATE products SET category_id = 1 WHERE category_id IS NULL',
    );
  }

  Future<void> _createBalanceChecks(Database db) async {
    await db.execute('''CREATE TABLE balance_checks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request_key TEXT NOT NULL UNIQUE, request_payload TEXT NOT NULL,
      account_id INTEGER NOT NULL REFERENCES money_accounts(id),
      account_name TEXT NOT NULL, branch_name TEXT NOT NULL, check_date TEXT NOT NULL,
      book_balance INTEGER NOT NULL,
      actual_balance INTEGER NOT NULL CHECK(actual_balance BETWEEN 0 AND 9000000000000),
      difference INTEGER NOT NULL CHECK(difference = actual_balance - book_balance),
      snapshot_entry_id INTEGER NOT NULL CHECK(snapshot_entry_id >= 0),
      note TEXT NOT NULL DEFAULT '', adjust_reason TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'adjusted', 'void')),
      revision INTEGER NOT NULL DEFAULT 0 CHECK(revision >= 0),
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, applied_at TEXT,
      void_reason TEXT NOT NULL DEFAULT '', voided_at TEXT,
      CHECK(status != 'adjusted' OR difference = 0 OR length(trim(adjust_reason)) > 0)
    )''');
    await db.execute('''CREATE TABLE balance_check_revisions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      check_id INTEGER NOT NULL REFERENCES balance_checks(id),
      action TEXT NOT NULL CHECK(action IN ('created', 'edited', 'applied', 'void')),
      before_json TEXT NOT NULL, after_json TEXT NOT NULL, recorded_at TEXT NOT NULL
    )''');
    await db.execute(
      'ALTER TABLE money_entries ADD COLUMN balance_check_id INTEGER REFERENCES balance_checks(id)',
    );
    await db.execute(
      'CREATE INDEX money_balance_check ON money_entries(balance_check_id, id)',
    );
    await db.execute(
      'CREATE INDEX balance_check_date ON balance_checks(check_date, id)',
    );
  }

  Future<void> _createOtherMoney(Database db) async {
    await db.execute('''CREATE TABLE other_money_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name)) BETWEEN 1 AND 80),
      active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1))
    )''');
    for (final name in [
      'Owner capital',
      'Owner withdrawal',
      'Loan received',
      'Loan repayment',
      'Other income',
      'Other payment',
    ]) {
      await db.insert('other_money_categories', {'name': name});
    }
    await db.execute('''CREATE TABLE other_money_vouchers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request_key TEXT NOT NULL UNIQUE, request_payload TEXT NOT NULL,
      account_id INTEGER NOT NULL REFERENCES money_accounts(id),
      direction TEXT NOT NULL CHECK(direction IN ('in', 'out')),
      amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 9000000000000),
      entry_date TEXT NOT NULL, category TEXT NOT NULL CHECK(length(trim(category)) BETWEEN 1 AND 80),
      description TEXT NOT NULL DEFAULT '', account_name TEXT NOT NULL, branch_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'posted' CHECK(status IN ('posted', 'void')),
      revision INTEGER NOT NULL DEFAULT 0 CHECK(revision >= 0),
      void_reason TEXT NOT NULL DEFAULT '', voided_at TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE other_money_revisions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      voucher_id INTEGER NOT NULL REFERENCES other_money_vouchers(id),
      action TEXT NOT NULL CHECK(action IN ('created', 'edited', 'void')),
      before_json TEXT NOT NULL, after_json TEXT NOT NULL, recorded_at TEXT NOT NULL
    )''');
    await db.execute(
      'ALTER TABLE money_entries ADD COLUMN other_money_id INTEGER REFERENCES other_money_vouchers(id)',
    );
    await db.execute(
      'CREATE INDEX money_other_voucher ON money_entries(other_money_id, id)',
    );
    await db.execute(
      'CREATE INDEX other_money_date ON other_money_vouchers(entry_date, id)',
    );
  }

  Future<void> _createAccountTransfers(Database db) async {
    await db.execute('''CREATE TABLE account_transfers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request_key TEXT NOT NULL UNIQUE, request_payload TEXT NOT NULL,
      from_account_id INTEGER NOT NULL REFERENCES money_accounts(id),
      to_account_id INTEGER NOT NULL REFERENCES money_accounts(id),
      amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 9000000000000),
      transfer_date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '',
      from_account_name TEXT NOT NULL, to_account_name TEXT NOT NULL,
      from_branch_name TEXT NOT NULL, to_branch_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'posted' CHECK(status IN ('posted', 'void')),
      revision INTEGER NOT NULL DEFAULT 0 CHECK(revision >= 0),
      void_reason TEXT NOT NULL DEFAULT '', voided_at TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      CHECK(from_account_id != to_account_id)
    )''');
    await db.execute('''CREATE TABLE account_transfer_revisions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      transfer_id INTEGER NOT NULL REFERENCES account_transfers(id),
      action TEXT NOT NULL CHECK(action IN ('created', 'edited', 'void')),
      before_json TEXT NOT NULL, after_json TEXT NOT NULL,
      recorded_at TEXT NOT NULL
    )''');
    await db.execute(
      'ALTER TABLE money_entries ADD COLUMN account_transfer_id INTEGER REFERENCES account_transfers(id)',
    );
    await db.execute(
      'CREATE INDEX money_account_transfer ON money_entries(account_transfer_id, id)',
    );
    await db.execute(
      'CREATE INDEX account_transfer_date ON account_transfers(transfer_date, id)',
    );
  }

  Future<void> _createBranches(Database db) async {
    await db.execute('''
      CREATE TABLE branches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL COLLATE NOCASE UNIQUE,
        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
        phone TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)
    ''');
  }

  Future<void> _createBranchStocks(Database db) async {
    await db.execute('''
      CREATE TABLE branch_stocks (
        branch_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        stock INTEGER NOT NULL DEFAULT 0 CHECK(stock BETWEEN 0 AND 2147483647),
        PRIMARY KEY(branch_id, product_id),
        FOREIGN KEY(branch_id) REFERENCES branches(id),
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');
  }

  Future<void> _createMovements(Database db) async {
    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        branch_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        kind TEXT NOT NULL CHECK(kind IN ('opening', 'in')),
        note TEXT NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY(branch_id) REFERENCES branches(id),
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');
    await db.execute('''
      CREATE INDEX stock_movement_branch_product
      ON stock_movements(branch_id, product_id, id)
    ''');
  }

  Future<void> _migrateLegacyStock(Database db) async {
    final branches = await db.query(
      'branches',
      where: 'code = ?',
      whereArgs: ['PZD'],
    );
    final products = await db.query('products');
    final history = await db.query('stock_movements', limit: 1);
    if (branches.isEmpty && (products.isNotEmpty || history.isNotEmpty)) {
      throw StateError(
        'PZD branch is required to migrate existing stock. '
        'Keep your data and restore the previous code to add branch code PZD.',
      );
    }
    await _createBranchStocks(db);
    if (branches.isNotEmpty) {
      final pzdId = branches.single['id'] as int;
      await db.rawInsert(
        '''
        INSERT INTO branch_stocks(branch_id, product_id, stock)
        SELECT ?, id, stock FROM products
      ''',
        [pzdId],
      );
    }
    await db.execute(
      'ALTER TABLE stock_movements RENAME TO legacy_stock_movements',
    );
    await _createMovements(db);
    if (branches.isNotEmpty) {
      await db.rawInsert(
        '''
        INSERT INTO stock_movements(id, branch_id, product_id, quantity, kind, note, created_at)
        SELECT id, ?, product_id, quantity, 'in', note, created_at
        FROM legacy_stock_movements
      ''',
        [branches.single['id']],
      );
    }
    await db.execute('DROP TABLE legacy_stock_movements');
    // products.stock is retained solely as a legacy snapshot. Never use it for live stock.
  }

  void _validateProduct(String name, int price, int stock) {
    if (name.trim().isEmpty ||
        price < 0 ||
        price > 2147483647 ||
        stock < 0 ||
        stock > 2147483647) {
      throw ArgumentError('Invalid product information');
    }
  }

  Future<int> addProduct({
    required String name,
    required int price,
    required int stock,
    required int branchId,
    String? barcode,
    String? itemCode,
    Uint8List? imageBytes,
    int categoryId = 1,
    int? brandId,
    String color = '',
    String size = '',
  }) async {
    _validateProduct(name, price, stock);
    _validateProductImage(imageBytes);
    final db = await database;
    return db.transaction((txn) async {
      final category = await txn.query(
        'product_categories',
        where: 'id = ? AND active = 1',
        whereArgs: [categoryId],
      );
      if (category.isEmpty) {
        throw StateError('Choose an active product category');
      }
      if (color.trim().length > 50 || size.trim().length > 50) {
        throw ArgumentError('Variant is too long');
      }
      if (brandId != null &&
          (await txn.query(
            'product_brands',
            where: 'id=? AND category_id=? AND active=1',
            whereArgs: [brandId, categoryId],
          )).isEmpty) {
        throw StateError('Choose an active brand for this category');
      }
      await CatalogIdentity.requireAvailable(txn, name: name);
      final id = await txn.insert('products', {
        'name': name.trim(),
        'price': price,
        'stock': 0,
        'category_id': categoryId,
        'brand_id': brandId,
        'color': color.trim(),
        'size': size.trim(),
      });
      final code = BarcodeRules.forItemCode(itemCode, id);
      await txn.update(
        'products',
        {
          'item_code': code,
          'barcode': BarcodeRules.forProduct(barcode, id, itemCodeValue: code),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (imageBytes != null) {
        await txn.insert('product_images', {
          'product_id': id,
          'image': imageBytes,
        });
      }
      await txn.insert('branch_stocks', {
        'branch_id': branchId,
        'product_id': id,
        'stock': stock,
      });
      if (stock > 0) {
        await txn.insert('stock_movements', {
          'branch_id': branchId,
          'product_id': id,
          'quantity': stock,
          'kind': 'opening',
          'note': 'Opening stock',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }
      return id;
    });
  }

  Future<List<Map<String, Object?>>> getProducts({
    required int branchId,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT p.id,p.name,p.price,p.barcode,p.item_code,p.category_id,p.brand_id,p.color,p.size,p.tracking,p.warranty_days,
        COALESCE(c.name, 'Uncategorized') AS category_name, COALESCE(s.stock, 0) AS stock,
        EXISTS(SELECT 1 FROM product_images i WHERE i.product_id = p.id) AS has_image
      FROM products p
      LEFT JOIN branch_stocks s ON s.product_id = p.id AND s.branch_id = ?
      LEFT JOIN product_categories c ON c.id = p.category_id
      ORDER BY p.id DESC
    ''',
      [branchId],
    );
  }

  Future<void> updateProduct({
    required int id,
    required String name,
    required int price,
    String? barcode,
    String? itemCode,
    Uint8List? imageBytes,
    bool removeImage = false,
    int? categoryId,
    int? brandId,
    bool changeBrand = false,
    String? color,
    String? size,
  }) async {
    _validateProduct(name, price, 0);
    _validateProductImage(imageBytes);
    if (removeImage && imageBytes != null) {
      throw ArgumentError('Cannot replace and remove a product image together');
    }
    final db = await database;
    await db.transaction((txn) async {
      final old = await txn.query(
        'products',
        columns: ['item_code', 'barcode', 'category_id', 'brand_id'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (old.isEmpty) throw StateError('Product not found');
      final code = itemCode == null
          ? old.single['item_code'] as String
          : BarcodeRules.forItemCode(itemCode, id);
      final values = <String, Object?>{
        'name': name.trim(),
        'price': price,
        'item_code': code,
      };
      if (categoryId != null) {
        final categories = await txn.query(
          'product_categories',
          where: 'id = ?',
          whereArgs: [categoryId],
        );
        if (categories.isEmpty ||
            (categories.single['active'] != 1 &&
                old.single['category_id'] != categoryId)) {
          throw StateError('Choose an active product category');
        }
        values['category_id'] = categoryId;
        if (categoryId != old.single['category_id']) values['brand_id'] = null;
      }
      if (changeBrand) {
        if (brandId != old.single['brand_id'] ||
            (categoryId != null && categoryId != old.single['category_id'])) {
          await ProductTracking.brand(
            txn,
            brandId,
            categoryId ?? (old.single['category_id'] as int),
          );
        }
        values['brand_id'] = brandId;
      }
      for (final field in {'color': color, 'size': size}.entries) {
        if (field.value != null) {
          if (field.value!.trim().length > 100) {
            throw ArgumentError('Color/size must be at most 100 characters');
          }
          values[field.key] = field.value!.trim();
        }
      }
      if (code != old.single['item_code'] &&
          old.single['barcode'] == old.single['item_code'] &&
          (barcode == null || barcode.trim() == old.single['barcode'])) {
        values['barcode'] = BarcodeRules.forProduct(
          null,
          id,
          itemCodeValue: code,
        );
      } else if (barcode != null) {
        values['barcode'] = BarcodeRules.forProduct(
          barcode,
          id,
          itemCodeValue: code,
        );
      }
      final identity = (await txn.query(
        'products',
        columns: ['name', 'color', 'size'],
        where: 'id=?',
        whereArgs: [id],
      )).single;
      if (CatalogIdentity.normalize(name) !=
              CatalogIdentity.normalize(identity['name']) ||
          color != null ||
          size != null) {
        await CatalogIdentity.requireAvailable(
          txn,
          name: name,
          color: color ?? identity['color'] as String? ?? '',
          size: size ?? identity['size'] as String? ?? '',
          excluding: id,
        );
      }
      final count = await txn.update(
        'products',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count != 1) throw StateError('Product not found');
      if (removeImage) {
        await txn.delete(
          'product_images',
          where: 'product_id = ?',
          whereArgs: [id],
        );
      } else if (imageBytes != null) {
        await txn.insert('product_images', {
          'product_id': id,
          'image': imageBytes,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> addStock({
    required int productId,
    required int quantity,
    required String note,
    required int branchId,
  }) async {
    if (quantity <= 0 || quantity > 2147483647) {
      throw ArgumentError('Invalid quantity');
    }
    final db = await database;
    await db.transaction((txn) async {
      await ProductTracking.requireUntracked(txn, productId);
      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO branch_stocks(branch_id, product_id, stock) VALUES (?, ?, 0)
      ''',
        [branchId, productId],
      );
      final count = await txn.rawUpdate(
        '''
        UPDATE branch_stocks SET stock = stock + ?
        WHERE branch_id = ? AND product_id = ? AND stock <= ?
      ''',
        [quantity, branchId, productId, 2147483647 - quantity],
      );
      if (count != 1) throw StateError('Stock limit exceeded');
      await txn.insert('stock_movements', {
        'branch_id': branchId,
        'product_id': productId,
        'quantity': quantity,
        'kind': 'in',
        'note': note.trim(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<List<Map<String, Object?>>> getStockMovements(
    int productId, {
    required int branchId,
  }) async {
    final db = await database;
    return db.query(
      'stock_movements',
      where: 'product_id = ? AND branch_id = ?',
      whereArgs: [productId, branchId],
      orderBy: 'id DESC',
    );
  }

  Future<void> _createStockTransfers(Database db) async {
    await db.execute('''CREATE TABLE stock_transfers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source_branch_id INTEGER NOT NULL REFERENCES branches(id),
      destination_branch_id INTEGER NOT NULL REFERENCES branches(id),
      product_id INTEGER NOT NULL REFERENCES products(id),
      quantity INTEGER NOT NULL CHECK(quantity BETWEEN 1 AND 2147483647),
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'posted' CHECK(status IN ('posted', 'void')),
      void_reason TEXT, voided_at TEXT,
      CHECK(source_branch_id != destination_branch_id)
    )''');
    await db.execute(
      'CREATE INDEX stock_transfers_source ON stock_transfers(source_branch_id, id)',
    );
    await db.execute(
      'CREATE INDEX stock_transfers_destination ON stock_transfers(destination_branch_id, id)',
    );
  }

  Future<void> _addStockTransferTransport(Database db) async {
    await db.execute(
      "ALTER TABLE stock_transfers ADD COLUMN transport_info TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _addStockTransferEdits(Database db) async {
    await db.execute(
      "ALTER TABLE stock_transfers ADD COLUMN transfer_date TEXT NOT NULL DEFAULT ''",
    );
    await db.execute('''CREATE TABLE stock_transfer_revisions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      transfer_id INTEGER NOT NULL REFERENCES stock_transfers(id),
      previous_data TEXT NOT NULL, changed_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE stock_transfer_photos (
      transfer_id INTEGER PRIMARY KEY REFERENCES stock_transfers(id),
      photo BLOB NOT NULL CHECK(length(photo) BETWEEN 4 AND 2000000)
    )''');
  }

  Future<void> _addStockTransferReceiving(Database db) async {
    await db.execute(
      'ALTER TABLE stock_transfers ADD COLUMN receive_required INTEGER NOT NULL DEFAULT 0 CHECK(receive_required IN (0,1))',
    );
    await db.execute('ALTER TABLE stock_transfers ADD COLUMN received_at TEXT');
    // Existing transfers already credited the destination. Never credit them again.
    await db.execute(
      "UPDATE stock_transfers SET received_at = created_at WHERE status = 'posted'",
    );
    await db.execute(
      '''CREATE INDEX stock_transfer_pending
      ON stock_transfers(destination_branch_id, receive_required, received_at, status)''',
    );
  }

  Future<void> receiveStockTransfer({
    required int id,
    required int branchId,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'stock_transfers',
        where: "id = ? AND destination_branch_id = ? AND status = 'posted' AND receive_required = 1 AND received_at IS NULL",
        whereArgs: [id, branchId],
      );
      if (rows.isEmpty) {
        throw StateError('This transfer is no longer pending for this branch');
      }
      final row = rows.single;
      final productId = row['product_id'] as int;
      final quantity = row['quantity'] as int;
      await txn.rawInsert(
        '''INSERT OR IGNORE INTO branch_stocks
        (branch_id, product_id, stock) VALUES (?, ?, 0)''',
        [branchId, productId],
      );
      final added = await txn.rawUpdate(
        '''UPDATE branch_stocks SET stock = stock + ?
        WHERE branch_id = ? AND product_id = ? AND stock <= ?''',
        [quantity, branchId, productId, 2147483647 - quantity],
      );
      if (added != 1) throw StateError('Destination stock limit exceeded');
      final now = DateTime.now().toUtc().toIso8601String();
      final updated = await txn.update(
        'stock_transfers',
        {'received_at': now},
        where: "id = ? AND status = 'posted' AND receive_required = 1 AND received_at IS NULL",
        whereArgs: [id],
      );
      if (updated != 1) throw StateError('Transfer was already received');
      await txn.insert('stock_movements', {
        'branch_id': branchId,
        'product_id': productId,
        'quantity': quantity,
        'kind': 'in',
        'note': 'Received transfer #$id from branch ${row['source_branch_id']}',
        'created_at': now,
      });
    });
  }

  Future<void> _createStockAdjustments(Database db) async {
    await db.execute('''CREATE TABLE stock_adjustments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      branch_id INTEGER NOT NULL REFERENCES branches(id),
      product_id INTEGER NOT NULL REFERENCES products(id),
      counted_stock INTEGER NOT NULL CHECK(counted_stock BETWEEN 0 AND 2147483647),
      previous_stock INTEGER NOT NULL CHECK(previous_stock BETWEEN 0 AND 2147483647),
      difference INTEGER NOT NULL CHECK(difference BETWEEN -2147483647 AND 2147483647 AND difference != 0),
      reason TEXT NOT NULL CHECK(reason IN ('damage','loss','count','other')),
      note TEXT NOT NULL,
      adjustment_date TEXT NOT NULL,
      created_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'posted' CHECK(status IN ('posted','void')),
      void_reason TEXT, voided_at TEXT
    )''');
    await db.execute(
      'CREATE INDEX stock_adjustment_branch ON stock_adjustments(branch_id, id)',
    );
  }

  Future<List<Map<String, Object?>>> getStockAdjustments(int branchId) async {
    final db = await database;
    return db.rawQuery(
      '''SELECT a.*, p.item_code, p.name AS product_name
      FROM stock_adjustments a JOIN products p ON p.id = a.product_id
      WHERE a.branch_id = ? ORDER BY a.id DESC''',
      [branchId],
    );
  }

  Future<int> correctStockAdjustment({
    required int id,
    required int branchId,
    required int productId,
    required int countedStock,
    required String reason,
    required String note,
    required String adjustmentDate,
  }) async {
    await VoucherPermissions.requireEditable();
    _validateTransferDate(adjustmentDate);
    if (countedStock < 0 ||
        countedStock > 2147483647 ||
        !{'damage', 'loss', 'count', 'other'}.contains(reason) ||
        note.trim().isEmpty ||
        note.trim().length > 500) {
      throw ArgumentError('Enter a valid stock count and reason');
    }
    final db = await database;
    return db.transaction((txn) async {
      await _deleteReversevoidStockAdjustment(txn, id, 'Corrected by Owner');
      final replacement = await _postStockAdjustmentTx(
        txn,
        branchId,
        productId,
        countedStock,
        reason,
        note,
        adjustmentDate,
      );
      await txn.insert('app_settings', {
        'key': 'adjustment_correction:$id:$replacement',
        'value': DateTime.now().toUtc().toIso8601String(),
      });
      return replacement;
    });
  }

  Future<int> postStockAdjustment({
    required int branchId,
    required int productId,
    required int countedStock,
    required String reason,
    required String note,
    required String adjustmentDate,
  }) async {
    _validateTransferDate(adjustmentDate);
    if (countedStock < 0 ||
        countedStock > 2147483647 ||
        !{'damage', 'loss', 'count', 'other'}.contains(reason) ||
        note.trim().isEmpty ||
        note.trim().length > 500) {
      throw ArgumentError('Enter a valid stock count and reason');
    }
    final db = await database;
    return db.transaction(
      (txn) => _postStockAdjustmentTx(
        txn,
        branchId,
        productId,
        countedStock,
        reason,
        note,
        adjustmentDate,
      ),
    );
  }

  Future<int> _postStockAdjustmentTx(
    Transaction txn,
    int branchId,
    int productId,
    int countedStock,
    String reason,
    String note,
    String adjustmentDate,
  ) async {
    await ProductTracking.requireUntracked(txn, productId);
    if ((await txn.query(
          'branches',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [branchId],
        )).isEmpty ||
        (await txn.query(
          'products',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [productId],
        )).isEmpty) {
      throw StateError('Branch or product not found');
    }
    await txn.rawInsert(
      '''INSERT OR IGNORE INTO branch_stocks
        (branch_id, product_id, stock) VALUES (?, ?, 0)''',
      [branchId, productId],
    );
    final rows = await txn.query(
      'branch_stocks',
      columns: ['stock'],
      where: 'branch_id = ? AND product_id = ?',
      whereArgs: [branchId, productId],
    );
    final old = rows.single['stock'] as int;
    final difference = countedStock - old;
    if (difference == 0) {
      throw StateError('Count matches current stock. No adjustment needed');
    }
    if ((reason == 'damage' || reason == 'loss') && difference > 0) {
      throw StateError('Damaged or lost stock cannot increase the count');
    }
    final updated = await txn.rawUpdate(
      '''UPDATE branch_stocks SET stock = ?
        WHERE branch_id = ? AND product_id = ? AND stock = ?''',
      [countedStock, branchId, productId, old],
    );
    if (updated != 1) throw StateError('Stock changed; reload and count again');
    final now = DateTime.now().toUtc().toIso8601String();
    final id = await txn.insert('stock_adjustments', {
      'branch_id': branchId,
      'product_id': productId,
      'previous_stock': old,
      'counted_stock': countedStock,
      'difference': difference,
      'reason': reason,
      'note': note.trim(),
      'adjustment_date': adjustmentDate,
      'created_at': now,
    });
    await txn.insert('stock_movements', {
      'branch_id': branchId,
      'product_id': productId,
      'quantity': difference.abs(),
      'kind': difference > 0 ? 'in' : 'sale',
      'note': 'Stock adjustment #$id ($reason): ${note.trim()}',
      'created_at': now,
    });
    return id;
  }

  Future<void> voidStockAdjustment({
    required int id,
    required String reason,
  }) async {
    final clean = reason.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Reason required');
    }
    final db = await database;
    await db.transaction(
      (txn) => _deleteReversevoidStockAdjustment(txn, id, clean),
    );
  }

  Future<void> _deleteReversevoidStockAdjustment(
    Transaction txn,
    int id,
    String clean,
  ) async {
    final rows = await txn.query(
      'stock_adjustments',
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('Adjustment already void or missing');
    final row = rows.single;
    final delta = row['difference'] as int;
    final branch = row['branch_id'] as int, product = row['product_id'] as int;
    final current = await txn.query(
      'branch_stocks',
      columns: ['stock'],
      where: 'branch_id = ? AND product_id = ?',
      whereArgs: [branch, product],
    );
    if (current.isEmpty) throw StateError('Stock row missing');
    final balance = current.single['stock'] as int;
    final restored = balance - delta;
    if (restored < 0 || restored > 2147483647) {
      throw StateError(
        'Cannot void: stock has been used or would exceed limit',
      );
    }
    final updated = await txn.rawUpdate(
      '''UPDATE branch_stocks SET stock = ?
        WHERE branch_id = ? AND product_id = ? AND stock = ?''',
      [restored, branch, product, balance],
    );
    if (updated != 1) throw StateError('Stock changed; reload');
    final now = DateTime.now().toUtc().toIso8601String();
    await txn.insert('stock_movements', {
      'branch_id': branch,
      'product_id': product,
      'quantity': delta.abs(),
      'kind': delta > 0 ? 'sale' : 'in',
      'note': 'Void stock adjustment #$id: $clean',
      'created_at': now,
    });
    await txn.update(
      'stock_adjustments',
      {'status': 'void', 'void_reason': clean, 'voided_at': now},
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
  }

  /// Permanently removes an already reversed voucher. Its linked payments and
  /// returns must be deleted first. Verify zero net effects before erasing
  /// accounting and stock history so no balance can change on deletion.

  String _deleteActor() {
    try {
      return OnlineAccounts.client.auth.currentUser?.email ??
          OnlineAccounts.client.auth.currentUser?.phone ??
          'Local user';
    } catch (_) {
      return 'Local user';
    }
  }

  Future<void> deleteVoucher({required String kind, required int id}) async {
    const tables = {
      'sale': 'sale_invoices',
      'purchase': 'purchase_invoices',
      'expense': 'expenses',
      'return': 'sale_returns',
      'receipt': 'customer_receipts',
      'settlement': 'supplier_settlements',
      'transfer': 'stock_transfers',
      'adjustment': 'stock_adjustments',
      'account_transfer': 'account_transfers',
      'other_money': 'other_money_vouchers',
      'balance_check': 'balance_checks',
    };
    final table = tables[kind];
    if (table == null || id <= 0) throw ArgumentError('Unknown voucher');
    final db = await database;
    await db.transaction((txn) async {
      final found = await txn.query(table, where: 'id=?', whereArgs: [id]);
      if (found.isEmpty) throw StateError('Voucher no longer exists');
      final before = found.single;
      final snapshot = <String, Object?>{'header': before};
      final children = switch (kind) {
        'sale' => {'sale_items': 'sale_id', 'sale_payments': 'sale_id'},
        'purchase' => {
          'purchase_items': 'purchase_id',
          'purchase_payments': 'purchase_id',
        },
        'return' => {
          'sale_return_items': 'return_id',
          'sale_return_refunds': 'return_id',
        },
        'receipt' => {
          'receipt_allocations': 'receipt_id',
          'receipt_payments': 'receipt_id',
        },
        'expense' => {'expense_payments': 'expense_id'},
        'settlement' => {'supplier_settlement_payments': 'settlement_id'},
        _ => <String, String>{},
      };
      for (final child in children.entries) {
        snapshot[child.key] = await txn.query(
          child.key,
          where: '${child.value}=?',
          whereArgs: [id],
        );
      }
      const reason = 'Deleted by user';
      if (before['status'] != 'void') {
        switch (kind) {
          case 'sale':
            await _voidSaleInvoice(txn, id, reason);
            break;
          case 'purchase':
            await _voidPurchaseInvoice(txn, id, reason);
            break;
          case 'return':
            await _reverseSaleReturn(txn, id, reason);
            break;
          case 'receipt':
            await _voidCustomerReceipt(txn, id, reason);
            break;
          case 'expense':
            await _deleteReversevoidExpense(txn, id, reason);
            break;
          case 'settlement':
            await _deleteReversevoidSupplierSettlement(txn, id, reason);
            break;
          case 'transfer':
            await _deleteReversevoidStockTransfer(txn, id, reason);
            break;
          case 'adjustment':
            await _deleteReversevoidStockAdjustment(txn, id, reason);
            break;
          case 'account_transfer':
            await AccountTransferRepository.voidForDelete(
              txn,
              id,
              before['revision'] as int,
              reason,
            );
            break;
          case 'other_money':
            await OtherMoneyRepository.voidForDelete(
              txn,
              id,
              before['revision'] as int,
              reason,
            );
            break;
          case 'balance_check':
            await BalanceCheckRepository.voidForDelete(
              txn,
              id,
              before['revision'] as int,
              reason,
            );
            break;
        }
      }
      // Append-only archive survives row deletion and is covered by local backup.
      final stamp = DateTime.now().toUtc().toIso8601String();
      await txn.insert('app_settings', {
        'key': 'voucher_delete_archive:$kind:$id:$stamp',
        'value': jsonEncode({
          ...snapshot,
          'deleted_at': stamp,
          'actor': _deleteActor(),
        }),
      });
      await _deleteVoidedVoucherTx(txn, kind, id, table);
    });
  }

  Future<void> deleteVoidedVoucher({
    required String kind,
    required int id,
  }) async {
    const tables = <String, String>{
      'sale': 'sale_invoices',
      'purchase': 'purchase_invoices',
      'expense': 'expenses',
      'return': 'sale_returns',
      'receipt': 'customer_receipts',
      'settlement': 'supplier_settlements',
      'transfer': 'stock_transfers',
      'adjustment': 'stock_adjustments',
      'account_transfer': 'account_transfers',
      'other_money': 'other_money_vouchers',
      'balance_check': 'balance_checks',
    };
    final table = tables[kind];
    if (table == null || id <= 0) throw ArgumentError('Unknown voucher');
    final db = await database;
    await db.transaction((txn) => _deleteVoidedVoucherTx(txn, kind, id, table));
  }

  Future<void> _deleteVoidedVoucherTx(
    Transaction txn,
    String kind,
    int id,
    String table,
  ) async {
    final rows = await txn.query(
      table,
      where: 'id = ? AND status = ?',
      whereArgs: [id, 'void'],
    );
    if (rows.isEmpty) {
      throw StateError('VOID the voucher before permanent deletion');
    }
    Future<void> requireAbsent(String child, String column) async {
      final linked = await txn.query(
        child,
        columns: ['id'],
        where: '$column = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (linked.isNotEmpty) {
        final label =
            const {
              'sale_returns': 'Sale Returns',
              'receipt_allocations': 'Customer Receipts',
              'sale_drafts': 'sale correction drafts',
              'supplier_settlements': 'Supplier Payments',
              'sale_exchange_links': 'replacement / exchange link',
            }[child] ??
            'related vouchers';
        throw StateError(
          'Delete or resolve linked $label first. No records were changed.',
        );
      }
    }

    // Link tables without an id need a raw existence query.
    Future<void> requireNoLink(String child, String column) async {
      final linked = await txn.rawQuery(
        'SELECT 1 FROM $child WHERE $column = ? LIMIT 1',
        [id],
      );
      if (linked.isNotEmpty) {
        final label =
            const {
              'sale_returns': 'Sale Returns',
              'receipt_allocations': 'Customer Receipts',
              'sale_drafts': 'sale correction drafts',
              'supplier_settlements': 'Supplier Payments',
              'sale_exchange_links': 'replacement / exchange link',
            }[child] ??
            'related vouchers';
        throw StateError(
          'Delete or resolve linked $label first. No records were changed.',
        );
      }
    }

    if (kind == 'sale') {
      await requireAbsent('sale_returns', 'sale_id');
      await requireNoLink('receipt_allocations', 'sale_id');
      await requireAbsent('sale_drafts', 'correction_source_sale_id');
      await requireNoLink('sale_exchange_links', 'replacement_sale_id');
    }
    if (kind == 'purchase') {
      await requireAbsent('supplier_settlements', 'purchase_id');
      final allocations = await txn.rawQuery(
        'SELECT 1 FROM stock_lots l JOIN sale_lot_allocations a ON a.lot_id=l.id WHERE l.purchase_id=? LIMIT 1',
        [id],
      );
      if (allocations.isNotEmpty) {
        throw StateError(
          'Delete linked sales/returns for these tracked units first. No records were changed.',
        );
      }
    }
    if ({
      'sale',
      'purchase',
      'return',
      'receipt',
      'settlement',
    }.contains(kind)) {
      await txn.update(
        table,
        {'replacement_id': null},
        where: 'replacement_id = ?',
        whereArgs: [id],
      );
    }
    final moneyColumn = switch (kind) {
      'sale' => 'sale_id',
      'purchase' => 'purchase_id',
      'expense' => 'expense_id',
      'return' => 'sale_return_id',
      'receipt' => 'customer_receipt_id',
      'settlement' => 'supplier_settlement_id',
      'account_transfer' => 'account_transfer_id',
      'other_money' => 'other_money_id',
      'balance_check' => 'balance_check_id',
      _ => null,
    };
    if (moneyColumn != null) {
      final totals = await txn.rawQuery(
        '''SELECT account_id, SUM(amount) AS total
          FROM money_entries WHERE $moneyColumn = ? GROUP BY account_id''',
        [id],
      );
      if (totals.any((r) => r['total'] != 0)) {
        throw StateError('Money entries are not reversed. Cannot delete');
      }
    }
    final stockColumn = switch (kind) {
      'sale' => 'sale_id',
      'purchase' => 'purchase_id',
      'return' => 'sale_return_id',
      _ => null,
    };
    if (stockColumn != null) {
      final totals = await txn.rawQuery(
        '''SELECT branch_id, product_id,
          SUM(CASE WHEN kind = 'sale' THEN -quantity ELSE quantity END) AS total
          FROM stock_movements WHERE $stockColumn = ?
          GROUP BY branch_id, product_id''',
        [id],
      );
      if (totals.any((r) => r['total'] != 0)) {
        throw StateError('Stock movements are not reversed. Cannot delete');
      }
    }
    if (kind == 'transfer' || kind == 'adjustment') {
      final patterns = kind == 'transfer'
          ? [
              'Transfer #$id to branch *',
              'Transfer #$id from branch *',
              'Received transfer #$id from branch *',
              'Edit transfer #$id: *',
              'Void transfer #$id: *',
            ]
          : ['Stock adjustment #$id (*', 'Void stock adjustment #$id: *'];
      final where = List.filled(patterns.length, 'note GLOB ?').join(' OR ');
      final movements = await txn.rawQuery('''SELECT id, branch_id, product_id,
          quantity, kind FROM stock_movements WHERE $where''', patterns);
      final totals = <String, int>{};
      for (final m in movements) {
        final key = "${m['branch_id']}:${m['product_id']}";
        totals[key] =
            (totals[key] ?? 0) +
            (m['kind'] == 'sale'
                ? -(m['quantity'] as int)
                : m['quantity'] as int);
      }
      if (movements.isEmpty || totals.values.any((total) => total != 0)) {
        throw StateError('Stock history does not balance. Cannot delete');
      }
      for (final m in movements) {
        await txn.delete(
          'stock_movements',
          where: 'id = ?',
          whereArgs: [m['id']],
        );
      }
    } else if (stockColumn != null) {
      await txn.delete(
        'stock_movements',
        where: '$stockColumn = ?',
        whereArgs: [id],
      );
    }
    if (moneyColumn != null) {
      await txn.delete(
        'money_entries',
        where: '$moneyColumn = ?',
        whereArgs: [id],
      );
    }
    switch (kind) {
      case 'sale':
        await txn.rawDelete(
          'DELETE FROM sale_lot_allocations WHERE sale_item_id IN (SELECT id FROM sale_items WHERE sale_id=?)',
          [id],
        );
        await txn.delete(
          'sale_payments',
          where: 'sale_id = ?',
          whereArgs: [id],
        );
        await txn.delete('sale_items', where: 'sale_id = ?', whereArgs: [id]);
        break;
      case 'purchase':
        await txn.delete('stock_lots', where: 'purchase_id=?', whereArgs: [id]);
        await txn.delete(
          'purchase_payments',
          where: 'purchase_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'purchase_items',
          where: 'purchase_id = ?',
          whereArgs: [id],
        );
        break;
      case 'expense':
        await txn.delete(
          'expense_payments',
          where: 'expense_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'expense_receipts',
          where: 'expense_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'expense_edits',
          where: 'expense_id = ?',
          whereArgs: [id],
        );
        break;
      case 'return':
        await txn.delete(
          'sale_exchange_links',
          where: 'return_id=?',
          whereArgs: [id],
        );
        await txn.delete(
          'return_lot_allocations',
          where: 'return_id=?',
          whereArgs: [id],
        );
        await txn.delete(
          'sale_return_refunds',
          where: 'return_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'sale_return_items',
          where: 'return_id = ?',
          whereArgs: [id],
        );
        break;
      case 'receipt':
        await txn.delete(
          'receipt_payments',
          where: 'receipt_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'receipt_allocations',
          where: 'receipt_id = ?',
          whereArgs: [id],
        );
        break;
      case 'settlement':
        await txn.delete(
          'supplier_settlement_payments',
          where: 'settlement_id = ?',
          whereArgs: [id],
        );
        break;
      case 'transfer':
        await txn.delete(
          'stock_transfer_photos',
          where: 'transfer_id = ?',
          whereArgs: [id],
        );
        await txn.delete(
          'stock_transfer_revisions',
          where: 'transfer_id = ?',
          whereArgs: [id],
        );
        break;
      case 'adjustment':
        break;
      case 'balance_check':
        await txn.delete(
          'balance_check_revisions',
          where: 'check_id = ?',
          whereArgs: [id],
        );
        break;
      case 'other_money':
        await txn.delete(
          'other_money_revisions',
          where: 'voucher_id = ?',
          whereArgs: [id],
        );
        break;
      case 'account_transfer':
        await txn.delete(
          'account_transfer_revisions',
          where: 'transfer_id = ?',
          whereArgs: [id],
        );
        break;
    }
    if (kind == 'sale') {
      await LiveSaleSync.record(
        txn,
        origin: LiveSaleSync.origin,
        draftId: rows.single['draft_id'] as int,
        saleId: id,
        removed: true,
      );
    }
    final deleted = await txn.delete(
      table,
      where: 'id = ? AND status = ?',
      whereArgs: [id, 'void'],
    );
    if (deleted != 1) throw StateError('Voucher changed. Reload');
    if (kind == 'sale') {
      final draftId = rows.single['draft_id'] as int;
      await txn.delete(
        'sale_recovery',
        where: 'source_draft_id = ?',
        whereArgs: [draftId],
      );
      await txn.delete(
        'sale_draft_items',
        where: 'draft_id = ?',
        whereArgs: [draftId],
      );
      await txn.delete('sale_drafts', where: 'id = ?', whereArgs: [draftId]);
    }
  }

  Future<Uint8List?> getStockTransferPhoto(int id) async {
    final db = await database;
    final rows = await db.query(
      'stock_transfer_photos',
      columns: ['photo'],
      where: 'transfer_id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.single['photo'] as Uint8List;
  }

  Future<void> setStockTransferPhoto({
    required int id,
    Uint8List? photo,
  }) async {
    await VoucherPermissions.requireEditable();
    if (photo != null &&
        (photo.length < 4 ||
            photo.length > 2000000 ||
            photo[0] != 0xff ||
            photo[1] != 0xd8)) {
      throw ArgumentError('Photo must be a JPEG under 2 MB');
    }
    final db = await database;
    await db.transaction((txn) async {
      final exists = await txn.query(
        'stock_transfers',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (exists.isEmpty) throw StateError('Transfer not found');
      if (photo == null) {
        await txn.delete(
          'stock_transfer_photos',
          where: 'transfer_id = ?',
          whereArgs: [id],
        );
      } else {
        await txn.insert('stock_transfer_photos', {
          'transfer_id': id,
          'photo': photo,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  void _validateTransferDate(String date) {
    final parsed = DateTime.tryParse(date);
    final today = AppDateTime.today();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date ||
        parsed.year < 2000 ||
        parsed.isAfter(today)) {
      throw ArgumentError('Choose a valid transfer date');
    }
  }

  Future<void> editStockTransfer({
    required int id,
    required int destinationBranchId,
    required int productId,
    required int quantity,
    required String note,
    required String transportInfo,
    required String transferDate,
    Uint8List? photo,
    bool photoChanged = false,
  }) async {
    await VoucherPermissions.requireEditable();
    _validateTransferDate(transferDate);
    if (quantity <= 0 ||
        quantity > 2147483647 ||
        note.trim().length > 500 ||
        transportInfo.trim().length > 500) {
      throw ArgumentError('Invalid transfer information');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'stock_transfers',
        where: "id = ? AND status = 'posted'",
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Transfer already void or missing');
      final old = rows.single;
      if (old['received_at'] != null || old['receive_required'] != 1) {
        throw StateError('Received transfers are locked.');
      }

      final source = old['source_branch_id'] as int;
      if (source == destinationBranchId) {
        throw ArgumentError('Choose another branch');
      }
      if ((await txn.query(
            'branches',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [destinationBranchId],
          )).isEmpty ||
          (await txn.query(
            'products',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [productId],
          )).isEmpty) {
        throw StateError('Branch or product missing');
      }
      final oldDestination = old['destination_branch_id'] as int;
      final oldProduct = old['product_id'] as int;
      final oldQty = old['quantity'] as int;
      final wasReceived =
          old['receive_required'] == 0 || old['received_at'] != null;
      final now = DateTime.now().toUtc().toIso8601String();
      final changedStock =
          oldDestination != destinationBranchId ||
          oldProduct != productId ||
          oldQty != quantity;
      if (changedStock) {
        if (wasReceived) {
          final undoDest = await txn.rawUpdate(
            '''UPDATE branch_stocks SET stock = stock - ?
            WHERE branch_id = ? AND product_id = ? AND stock >= ?''',
            [oldQty, oldDestination, oldProduct, oldQty],
          );
          if (undoDest != 1) {
            throw StateError(
              'Cannot edit: original transferred stock was used',
            );
          }
        }
        final undoSource = await txn.rawUpdate(
          '''UPDATE branch_stocks SET stock = stock + ?
          WHERE branch_id = ? AND product_id = ? AND stock <= ?''',
          [oldQty, source, oldProduct, 2147483647 - oldQty],
        );
        if (undoSource != 1) throw StateError('Source stock limit exceeded');
        final removeSource = await txn.rawUpdate(
          '''UPDATE branch_stocks SET stock = stock - ?
          WHERE branch_id = ? AND product_id = ? AND stock >= ?''',
          [quantity, source, productId, quantity],
        );
        if (removeSource != 1) {
          throw StateError('Not enough stock for corrected transfer');
        }
        if (wasReceived) {
          await txn.rawInsert(
            '''INSERT OR IGNORE INTO branch_stocks
            (branch_id, product_id, stock) VALUES (?, ?, 0)''',
            [destinationBranchId, productId],
          );
          final addDest = await txn.rawUpdate(
            '''UPDATE branch_stocks SET stock = stock + ?
            WHERE branch_id = ? AND product_id = ? AND stock <= ?''',
            [quantity, destinationBranchId, productId, 2147483647 - quantity],
          );
          if (addDest != 1) {
            throw StateError('Destination stock limit exceeded');
          }
        }
        for (final move in [
          if (wasReceived)
            (
              oldDestination,
              oldProduct,
              oldQty,
              'sale',
              'Edit transfer #$id: undo old receipt',
            ),
          (
            source,
            oldProduct,
            oldQty,
            'in',
            'Edit transfer #$id: undo old dispatch',
          ),
          (
            source,
            productId,
            quantity,
            'sale',
            'Edit transfer #$id: corrected dispatch',
          ),
          if (wasReceived)
            (
              destinationBranchId,
              productId,
              quantity,
              'in',
              'Edit transfer #$id: corrected receipt',
            ),
        ]) {
          await txn.insert('stock_movements', {
            'branch_id': move.$1,
            'product_id': move.$2,
            'quantity': move.$3,
            'kind': move.$4,
            'note': move.$5,
            'created_at': now,
          });
        }
      }
      await txn.insert('stock_transfer_revisions', {
        'transfer_id': id,
        'previous_data': jsonEncode(old),
        'changed_at': now,
      });
      await txn.update(
        'stock_transfers',
        {
          'destination_branch_id': destinationBranchId,
          'product_id': productId,
          'quantity': quantity,
          'note': note.trim(),
          'transport_info': transportInfo.trim(),
          'transfer_date': transferDate,
        },
        where: "id = ? AND status = 'posted'",
        whereArgs: [id],
      );
      if (photoChanged) {
        _validateTransferPhoto(photo);
        if (photo == null) {
          await txn.delete(
            'stock_transfer_photos',
            where: 'transfer_id = ?',
            whereArgs: [id],
          );
        } else {
          await txn.insert('stock_transfer_photos', {
            'transfer_id': id,
            'photo': photo,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    });
  }

  void _validateTransferPhoto(Uint8List? photo) {
    if (photo != null &&
        (photo.length < 4 ||
            photo.length > 2000000 ||
            photo[0] != 0xff ||
            photo[1] != 0xd8 ||
            photo[photo.length - 2] != 0xff ||
            photo.last != 0xd9)) {
      throw ArgumentError('Photo must be a JPEG under 2 MB');
    }
  }

  Future<List<Map<String, Object?>>> getStockTransfers(int branchId) async {
    final db = await database;
    return db.rawQuery(
      '''SELECT t.*, p.name AS product_name, p.item_code,
      s.name AS source_name, d.name AS destination_name
      FROM stock_transfers t
      JOIN products p ON p.id = t.product_id
      JOIN branches s ON s.id = t.source_branch_id
      JOIN branches d ON d.id = t.destination_branch_id
      WHERE t.source_branch_id = ? OR t.destination_branch_id = ?
      ORDER BY t.id DESC''',
      [branchId, branchId],
    );
  }

  Future<int> postStockTransfer({
    required int sourceBranchId,
    required int destinationBranchId,
    required int productId,
    required int quantity,
    required String note,
    String transportInfo = '',
    required String transferDate,
    Uint8List? photo,
  }) async {
    _validateTransferDate(transferDate);
    _validateTransferPhoto(photo);
    if (sourceBranchId == destinationBranchId ||
        quantity <= 0 ||
        quantity > 2147483647 ||
        note.trim().length > 500 ||
        transportInfo.trim().length > 500) {
      throw ArgumentError('Choose different branches and a valid quantity');
    }
    final db = await database;
    return db.transaction((txn) async {
      await ProductTracking.requireUntracked(txn, productId);
      final branches = await txn.rawQuery(
        'SELECT id FROM branches WHERE id IN (?, ?)',
        [sourceBranchId, destinationBranchId],
      );
      if (branches.length != 2 ||
          (await txn.query(
            'products',
            columns: ['id'],
            where: 'id = ?',
            whereArgs: [productId],
          )).isEmpty) {
        throw StateError('Branch or product not found');
      }
      final removed = await txn.rawUpdate(
        '''UPDATE branch_stocks
        SET stock = stock - ? WHERE branch_id = ? AND product_id = ? AND stock >= ?''',
        [quantity, sourceBranchId, productId, quantity],
      );
      if (removed != 1) throw StateError('Not enough stock in source branch');
      final now = DateTime.now().toUtc().toIso8601String();
      final id = await txn.insert('stock_transfers', {
        'source_branch_id': sourceBranchId,
        'destination_branch_id': destinationBranchId,
        'product_id': productId,
        'quantity': quantity,
        'note': note.trim(),
        'transport_info': transportInfo.trim(),
        'transfer_date': transferDate,
        'created_at': now,
        'receive_required': 1,
      });
      if (photo != null) {
        await txn.insert('stock_transfer_photos', {
          'transfer_id': id,
          'photo': photo,
        });
      }
      await txn.insert('stock_movements', {
        'branch_id': sourceBranchId,
        'product_id': productId,
        'quantity': quantity,
        'kind': 'sale',
        'note': 'Transfer #$id to branch $destinationBranchId: ${note.trim()}',
        'created_at': now,
      });
      return id;
    });
  }

  Future<void> voidStockTransfer({
    required int id,
    required String reason,
  }) async {
    final clean = reason.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Reason required');
    }
    final db = await database;
    await db.transaction(
      (txn) => _deleteReversevoidStockTransfer(txn, id, clean),
    );
  }

  Future<void> _deleteReversevoidStockTransfer(
    Transaction txn,
    int id,
    String clean,
  ) async {
    final rows = await txn.query(
      'stock_transfers',
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('Transfer already void or missing');
    final transfer = rows.single;
    final qty = transfer['quantity'] as int;
    final source = transfer['source_branch_id'] as int;
    final destination = transfer['destination_branch_id'] as int;
    final product = transfer['product_id'] as int;
    final wasReceived =
        transfer['receive_required'] == 0 || transfer['received_at'] != null;
    if (wasReceived) {
      final removed = await txn.rawUpdate(
        '''UPDATE branch_stocks SET stock = stock - ?
          WHERE branch_id = ? AND product_id = ? AND stock >= ?''',
        [qty, destination, product, qty],
      );
      if (removed != 1) {
        throw StateError(
          'Cannot void: transferred stock was used at destination',
        );
      }
    }
    final added = await txn.rawUpdate(
      '''UPDATE branch_stocks SET stock = stock + ?
        WHERE branch_id = ? AND product_id = ? AND stock <= ?''',
      [qty, source, product, 2147483647 - qty],
    );
    if (added != 1) throw StateError('Source stock limit exceeded');
    final now = DateTime.now().toUtc().toIso8601String();
    if (wasReceived) {
      await txn.insert('stock_movements', {
        'branch_id': destination,
        'product_id': product,
        'quantity': qty,
        'kind': 'sale',
        'note': 'Void transfer #$id: $clean',
        'created_at': now,
      });
    }
    await txn.insert('stock_movements', {
      'branch_id': source,
      'product_id': product,
      'quantity': qty,
      'kind': 'in',
      'note': 'Void transfer #$id: $clean',
      'created_at': now,
    });
    await txn.update(
      'stock_transfers',
      {'status': 'void', 'void_reason': clean, 'voided_at': now},
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
  }

  Future<List<Map<String, Object?>>> getBranches() async {
    final db = await database;
    return db.query('branches', orderBy: 'name COLLATE NOCASE, id');
  }

  Future<int?> getDefaultBranchId() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['default_branch'],
    );
    return rows.isEmpty ? null : int.tryParse(rows.first['value'] as String);
  }

  Future<Map<String, Object?>> getDashboardOverview() async {
    final db = await database;
    final (monthStart, nextMonth) = AppDateTime.currentMonthUtcRange();
    return db.transaction((txn) async {
      final selected = await txn.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['default_branch'],
      );
      final id = selected.isEmpty
          ? null
          : int.tryParse(selected.single['value'] as String);
      if (id == null) {
        return <String, Object?>{
          'branch_name': null,
          'monthly_sales': 0,
          'monthly_expenses': 0,
          'account_balance': 0,
        };
      }
      final branches = await txn.query(
        'branches',
        columns: ['name', 'code'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (branches.isEmpty) {
        return <String, Object?>{
          'branch_name': null,
          'monthly_sales': 0,
          'monthly_expenses': 0,
          'account_balance': 0,
        };
      }
      // Use confirmation time, rather than an invoice date that may be backdated.
      final sales = await txn.rawQuery(
        '''
        SELECT COALESCE(SUM(total), 0) AS amount FROM sale_invoices
        WHERE branch_id = ? AND status = 'posted' AND confirmed_at >= ? AND confirmed_at < ?
      ''',
        [id, monthStart.toIso8601String(), nextMonth.toIso8601String()],
      );
      final accounts = await txn.rawQuery(
        '''
        SELECT COALESCE(SUM(e.amount), 0) AS amount
        FROM money_accounts a JOIN money_entries e ON e.account_id = a.id
        WHERE a.branch_id = ?
      ''',
        [id],
      );
      final expenses = await txn.rawQuery(
        '''
        SELECT COALESCE(SUM(amount), 0) AS amount FROM expenses
        WHERE branch_id = ? AND status = 'posted'
          AND posted_at >= ? AND posted_at < ?
      ''',
        [id, monthStart.toIso8601String(), nextMonth.toIso8601String()],
      );
      final branch = branches.single;
      return <String, Object?>{
        'branch_name': '${branch['name']} (${branch['code']})',
        'monthly_sales': sales.single['amount'] as int,
        'monthly_expenses': expenses.single['amount'] as int,
        'account_balance': accounts.single['amount'] as int,
      };
    });
  }

  Future<void> saveBranch({
    int? id,
    required String code,
    required String name,
    required String phone,
    required String address,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Branch name required');
    }
    final db = await database;
    await db.transaction((txn) async {
      var cleanCode = code.trim().toUpperCase();
      if (cleanCode.isEmpty) {
        final rows = await txn.query('branches', columns: ['id', 'code']);
        final used = rows
            .map((row) => row['code'].toString().toUpperCase())
            .toSet();
        for (final row in rows) {
          if (row['id'] == id) {
            cleanCode = (row['code'] as String).trim();
            break;
          }
        }
        if (cleanCode.isEmpty) {
          var next = 1;
          do {
            cleanCode = 'BR${(next++).toString().padLeft(2, '0')}';
          } while (used.contains(cleanCode));
        }
      }
      final values = {
        'code': cleanCode,
        'name': name.trim(),
        'phone': BranchPhones.normalize(phone),
        'address': address.trim(),
      };
      if (id == null) {
        final newId = await txn.insert('branches', values);
        final settings = await txn.query(
          'app_settings',
          where: 'key = ?',
          whereArgs: ['default_branch'],
        );
        if (settings.isEmpty) {
          await txn.insert('app_settings', {
            'key': 'default_branch',
            'value': newId.toString(),
          });
        }
      } else {
        final count = await txn.update(
          'branches',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
        if (count != 1) throw StateError('Branch not found');
      }
    });
  }

  Future<void> setDefaultBranch(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      if ((await txn.query(
        'branches',
        where: 'id = ?',
        whereArgs: [id],
      )).isEmpty) {
        throw StateError('Branch not found');
      }
      await txn.insert('app_settings', {
        'key': 'default_branch',
        'value': id.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> _createMoneyAccounts(Database db) async {
    await db.execute('''
      CREATE TABLE money_accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        branch_id INTEGER NOT NULL REFERENCES branches(id),
        name TEXT NOT NULL COLLATE NOCASE CHECK(length(trim(name)) > 0),
        type TEXT NOT NULL CHECK(type IN ('cash', 'bank', 'wallet')),
        account_number TEXT NOT NULL DEFAULT '',
        remark TEXT NOT NULL DEFAULT '',
        opening_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(branch_id, name)
      )
    ''');
    await db.execute('''
      CREATE TABLE money_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        account_id INTEGER NOT NULL REFERENCES money_accounts(id),
        kind TEXT NOT NULL CHECK(kind IN ('opening', 'receipt', 'payment', 'transfer', 'adjustment')),
        amount INTEGER NOT NULL CHECK(amount BETWEEN -9000000000000 AND 9000000000000),
        entry_date TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        CHECK(kind != 'opening' OR amount >= 0)
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX money_single_opening
      ON money_entries(account_id) WHERE kind = 'opening'
    ''');
    await db.execute('''
      CREATE INDEX money_entries_account_date
      ON money_entries(account_id, entry_date, id)
    ''');
  }

  Future<void> _createOpeningCorrections(Database db) async {
    await db.execute('''CREATE TABLE opening_balance_corrections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      account_id INTEGER NOT NULL REFERENCES money_accounts(id),
      money_entry_id INTEGER NOT NULL UNIQUE REFERENCES money_entries(id),
      previous_amount INTEGER NOT NULL CHECK(previous_amount >= 0),
      new_amount INTEGER NOT NULL CHECK(new_amount >= 0),
      delta INTEGER NOT NULL CHECK(delta != 0),
      reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 300),
      created_at TEXT NOT NULL,
      CHECK(new_amount - previous_amount = delta)
    )''');
    await db.execute(
      'CREATE INDEX opening_correction_account ON opening_balance_corrections(account_id, id)',
    );
  }

  Future<List<Map<String, Object?>>> getOpeningCorrections(
    int accountId,
  ) async {
    final db = await database;
    return db.query(
      'opening_balance_corrections',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'id DESC',
    );
  }

  Future<List<Map<String, Object?>>> getMoneyAccounts({
    required int branchId,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT a.*, (SELECT value FROM app_settings WHERE key='money_account_holder:'||a.id) account_holder, COALESCE(SUM(e.amount), 0) AS balance,
        COALESCE(MAX(CASE WHEN e.kind = 'opening' THEN e.amount END), 0) +
          COALESCE((SELECT SUM(c.delta) FROM opening_balance_corrections c WHERE c.account_id = a.id),0)
          AS opening_balance
      FROM money_accounts a
      LEFT JOIN money_entries e ON e.account_id = a.id
      WHERE a.branch_id = ?
      GROUP BY a.id
      ORDER BY a.name COLLATE NOCASE, a.id
    ''',
      [branchId],
    );
  }

  Future<void> _createExpenses(Database db) async {
    await db.execute('''CREATE TABLE expenses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      branch_id INTEGER NOT NULL REFERENCES branches(id),
      account_id INTEGER NOT NULL REFERENCES money_accounts(id),
      category TEXT NOT NULL CHECK(length(trim(category)) BETWEEN 1 AND 80),
      amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 9000000000000),
      expense_date TEXT NOT NULL,
      note TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'posted' CHECK(status IN ('posted', 'void')),
      posted_at TEXT NOT NULL, voided_at TEXT, void_reason TEXT NOT NULL DEFAULT ''
    )''');
    await db.execute(
      'ALTER TABLE money_entries ADD COLUMN expense_id INTEGER REFERENCES expenses(id)',
    );
    await db.execute('''CREATE UNIQUE INDEX money_expense_kind
      ON money_entries(expense_id, kind) WHERE expense_id IS NOT NULL''');
    await db.execute(
      'CREATE INDEX expenses_branch_date ON expenses(branch_id, posted_at, id)',
    );
  }

  Future<List<Map<String, Object?>>> getExpenses({
    required int branchId,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''SELECT x.*, a.name AS account_name,
      (SELECT GROUP_CONCAT(ma.name, ' | ') FROM expense_payments ep JOIN money_accounts ma ON ma.id=ep.account_id WHERE ep.expense_id=x.id) AS payment_account_names,
      (SELECT GROUP_CONCAT(ep.account_id) FROM expense_payments ep WHERE ep.expense_id=x.id) AS payment_account_ids,
      (SELECT COUNT(*) FROM expense_payments p WHERE p.expense_id = x.id) AS payment_count,
      EXISTS(SELECT 1 FROM expense_receipts r WHERE r.expense_id = x.id) AS has_receipt
      FROM expenses x JOIN money_accounts a ON a.id = x.account_id
      WHERE x.branch_id = ? ORDER BY x.id DESC''',
      [branchId],
    );
  }

  Future<Map<String, Object?>> getExpenseSummary({
    required int branchId,
    required String fromDate,
    required String toDate,
  }) async {
    if (fromDate.compareTo(toDate) > 0) {
      throw ArgumentError('Invalid date range');
    }
    final db = await database;
    final rows = await db.rawQuery(
      '''SELECT category, expense_date, amount
      FROM expenses WHERE branch_id = ? AND status = 'posted'
      AND expense_date >= ? AND expense_date <= ?
      ORDER BY expense_date DESC, id DESC''',
      [branchId, fromDate, toDate],
    );
    final categories = <String, Map<String, int>>{};
    final days = <String, Map<String, int>>{};
    var total = 0;
    for (final row in rows) {
      final amount = row['amount'] as int;
      total += amount;
      final category = row['category'] as String;
      final day = row['expense_date'] as String;
      final categoryBucket = categories.putIfAbsent(
        category,
        () => {'amount': 0, 'count': 0},
      );
      categoryBucket['amount'] = categoryBucket['amount']! + amount;
      categoryBucket['count'] = categoryBucket['count']! + 1;
      final dayBucket = days.putIfAbsent(day, () => {'amount': 0, 'count': 0});
      dayBucket['amount'] = dayBucket['amount']! + amount;
      dayBucket['count'] = dayBucket['count']! + 1;
    }
    return {
      'total': total,
      'count': rows.length,
      'categories': categories,
      'days': days,
    };
  }

  Future<Map<String, Object?>> getSalesReport({
    required int branchId,
    required String fromDate,
    required String toDate,
  }) async {
    if (fromDate.compareTo(toDate) > 0) {
      throw ArgumentError('Invalid date range');
    }
    final db = await database;
    return db.transaction((txn) async {
      final sales = await txn.rawQuery(
        '''SELECT invoice_date AS day, total,
        subtotal, discount_amount FROM sale_invoices
        WHERE branch_id = ? AND status = 'posted'
          AND invoice_date >= ? AND invoice_date <= ?''',
        [branchId, fromDate, toDate],
      );
      final returns = await txn.rawQuery(
        '''SELECT return_date AS day, total
        FROM sale_returns WHERE branch_id = ? AND status = 'posted'
          AND return_date >= ? AND return_date <= ?''',
        [branchId, fromDate, toDate],
      );
      final days = <String, Map<String, int>>{};
      var gross = 0, discounts = 0, refunds = 0;
      for (final row in sales) {
        final day = row['day'] as String;
        final bucket = days.putIfAbsent(
          day,
          () => {'sales': 0, 'returns': 0, 'invoices': 0, 'return_count': 0},
        );
        final amount = row['total'] as int;
        gross += row['subtotal'] as int;
        discounts += row['discount_amount'] as int;
        bucket['sales'] = bucket['sales']! + amount;
        bucket['invoices'] = bucket['invoices']! + 1;
      }
      for (final row in returns) {
        final day = row['day'] as String;
        final bucket = days.putIfAbsent(
          day,
          () => {'sales': 0, 'returns': 0, 'invoices': 0, 'return_count': 0},
        );
        final amount = row['total'] as int;
        refunds += amount;
        bucket['returns'] = bucket['returns']! + amount;
        bucket['return_count'] = bucket['return_count']! + 1;
      }
      return <String, Object?>{
        'gross': gross,
        'discounts': discounts,
        'sales': gross - discounts,
        'returns': refunds,
        'net': gross - discounts - refunds,
        'invoice_count': sales.length,
        'return_count': returns.length,
        'days': days,
      };
    });
  }

  Future<void> _createExpensePayments(Database db) async {
    await db.execute('''CREATE TABLE expense_payments (
      expense_id INTEGER NOT NULL REFERENCES expenses(id),
      account_id INTEGER NOT NULL REFERENCES money_accounts(id),
      amount INTEGER NOT NULL CHECK(amount BETWEEN 1 AND 9000000000000),
      PRIMARY KEY(expense_id, account_id)
    )''');
    await db.execute(
      '''INSERT INTO expense_payments(expense_id, account_id, amount)
      SELECT id, account_id, amount FROM expenses''',
    );
    await db.execute('DROP INDEX money_expense_initial_payment');
    await db.execute('''CREATE UNIQUE INDEX money_expense_initial_payment
      ON money_entries(expense_id, account_id)
      WHERE expense_id IS NOT NULL AND kind = 'payment' ''');
    await db.execute(
      "ALTER TABLE expense_edits ADD COLUMN previous_payments TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE expense_edits ADD COLUMN payments TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<List<Map<String, Object?>>> getExpensePayments(int expenseId) async {
    final db = await database;
    return db.query(
      'expense_payments',
      where: 'expense_id = ?',
      whereArgs: [expenseId],
      orderBy: 'account_id',
    );
  }

  Map<int, int> _expensePaymentMap(List<Map<String, int>> payments, int total) {
    if (payments.isEmpty) throw ArgumentError('Add at least one payment');
    final amounts = <int, int>{};
    var sum = 0;
    for (final row in payments) {
      final accountId = row['account_id'];
      final value = row['amount'];
      if (accountId == null ||
          value == null ||
          value <= 0 ||
          value > 9000000000000 ||
          amounts.containsKey(accountId)) {
        throw ArgumentError('Use different accounts with positive amounts');
      }
      sum += value;
      if (sum > total) {
        throw ArgumentError('Payments exceed the expense amount');
      }
      amounts[accountId] = value;
    }
    if (sum != total) {
      throw ArgumentError('Payments must equal the expense amount');
    }
    return amounts;
  }

  Future<Map<int, int>> _checkExpenseBalances(
    DatabaseExecutor txn,
    int branchId,
    Map<int, int> oldPayments,
    Map<int, int> newPayments,
  ) async {
    final result = <int, int>{};
    for (final accountId in {...oldPayments.keys, ...newPayments.keys}) {
      final rows = await txn.rawQuery(
        '''SELECT a.id, COALESCE(SUM(e.amount),0) AS balance
        FROM money_accounts a LEFT JOIN money_entries e ON e.account_id = a.id
        WHERE a.id = ? AND a.branch_id = ? GROUP BY a.id''',
        [accountId, branchId],
      );
      if (rows.isEmpty) {
        throw StateError('Payment account does not belong to branch');
      }
      final balance = rows.single['balance'] as int;
      final after =
          balance +
          (oldPayments[accountId] ?? 0) -
          (newPayments[accountId] ?? 0);
      if (after < 0 || after > 9000000000000) {
        throw StateError('Insufficient balance or account limit exceeded');
      }
      result[accountId] = after;
    }
    return result;
  }

  Future<void> _createExpenseReceipts(Database db) async {
    await db.execute('''CREATE TABLE expense_receipts (
      expense_id INTEGER PRIMARY KEY REFERENCES expenses(id),
      photo BLOB NOT NULL CHECK(length(photo) BETWEEN 4 AND 2000000),
      added_at TEXT NOT NULL
    )''');
  }

  Future<void> _createExpenseEdits(Database db) async {
    await db.execute(
      'ALTER TABLE expenses ADD COLUMN revision INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('''CREATE TABLE expense_edits (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      expense_id INTEGER NOT NULL REFERENCES expenses(id),
      previous_category TEXT NOT NULL, category TEXT NOT NULL,
      previous_account_id INTEGER NOT NULL, account_id INTEGER NOT NULL,
      previous_amount INTEGER NOT NULL, amount INTEGER NOT NULL,
      previous_expense_date TEXT NOT NULL, expense_date TEXT NOT NULL,
      previous_note TEXT NOT NULL, note TEXT NOT NULL,
      receipt_action TEXT NOT NULL CHECK(receipt_action IN ('unchanged','added','replaced','removed')),
      changed_at TEXT NOT NULL
    )''');
    await db.execute(
      'CREATE INDEX expense_edits_expense ON expense_edits(expense_id, id)',
    );
    // An expense may have several audited corrections, each with a money entry.
    await db.execute('DROP INDEX money_expense_kind');
    await db.execute(
      '''CREATE UNIQUE INDEX money_expense_initial_payment
      ON money_entries(expense_id) WHERE expense_id IS NOT NULL AND kind = 'payment' ''',
    );
  }

  Future<List<Map<String, Object?>>> getExpenseEdits(int id) async {
    final db = await database;
    return db.query(
      'expense_edits',
      where: 'expense_id = ?',
      whereArgs: [id],
      orderBy: 'id DESC',
    );
  }

  void _validateExpenseReceipt(Uint8List? photo) {
    if (photo == null) return;
    if (photo.length < 4 ||
        photo.length > 2000000 ||
        photo[0] != 0xff ||
        photo[1] != 0xd8 ||
        photo[photo.length - 2] != 0xff ||
        photo.last != 0xd9) {
      throw ArgumentError('Receipt photo must be a JPEG smaller than 2 MB');
    }
  }

  Future<Uint8List?> getExpenseReceiptPhoto(int expenseId) async {
    final db = await database;
    final rows = await db.query(
      'expense_receipts',
      columns: ['photo'],
      where: 'expense_id = ?',
      whereArgs: [expenseId],
    );
    return rows.isEmpty ? null : rows.single['photo'] as Uint8List;
  }

  Future<void> saveExpenseReceiptPhoto({
    required int expenseId,
    required Uint8List photo,
  }) async {
    await VoucherPermissions.requireEditable();
    _validateExpenseReceipt(photo);
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [expenseId],
      );
      if (rows.isEmpty || rows.single['status'] != 'posted') {
        throw StateError('Expense is not active');
      }
      final old = rows.single;
      final previous = await txn.query(
        'expense_receipts',
        columns: ['expense_id'],
        where: 'expense_id = ?',
        whereArgs: [expenseId],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      await txn.insert('expense_receipts', {
        'expense_id': expenseId,
        'photo': photo,
        'added_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.update(
        'expenses',
        {'revision': (old['revision'] as int) + 1},
        where: 'id = ?',
        whereArgs: [expenseId],
      );
      await txn.insert('expense_edits', {
        'expense_id': expenseId,
        'previous_category': old['category'],
        'category': old['category'],
        'previous_account_id': old['account_id'],
        'account_id': old['account_id'],
        'previous_amount': old['amount'],
        'amount': old['amount'],
        'previous_expense_date': old['expense_date'],
        'expense_date': old['expense_date'],
        'previous_note': old['note'],
        'note': old['note'],
        'receipt_action': previous.isEmpty ? 'added' : 'replaced',
        'changed_at': now,
      });
    });
  }

  Future<void> _createExpenseCategories(Database db) async {
    await db.execute('''CREATE TABLE expense_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      branch_id INTEGER NOT NULL REFERENCES branches(id),
      name TEXT NOT NULL COLLATE NOCASE CHECK(length(trim(name)) BETWEEN 1 AND 80),
      active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
      UNIQUE(branch_id, name)
    )''');
    // Keep existing expense text as the historical snapshot. Offer its distinct
    // values as reusable categories after upgrading an already used database.
    await db.execute(
      '''INSERT OR IGNORE INTO expense_categories(branch_id, name)
      SELECT branch_id, MIN(trim(category)) FROM expenses
      GROUP BY branch_id, trim(category) COLLATE NOCASE''',
    );
  }

  Future<List<Map<String, Object?>>> getExpenseCategories({
    required int branchId,
  }) async {
    final db = await database;
    return db.query(
      'expense_categories',
      where: 'branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'active DESC, name COLLATE NOCASE, id',
    );
  }

  Future<void> addExpenseCategory({
    required int branchId,
    required String name,
  }) async {
    final db = await database;
    await db.transaction(
      (txn) => CategoryStore.save(txn, 'expense', name, branch: branchId),
    );
  }

  Future<void> setExpenseCategoryActive({
    required int branchId,
    required int id,
    required bool active,
  }) async {
    final db = await database;
    await db.transaction(
      (txn) =>
          CategoryStore.setActive(txn, 'expense', id, active, branch: branchId),
    );
  }

  Future<void> renameExpenseCategory({
    required int branchId,
    required int id,
    required String name,
  }) async {
    final db = await database;
    await db.transaction(
      (txn) =>
          CategoryStore.save(txn, 'expense', name, id: id, branch: branchId),
    );
  }

  Future<int> postExpense({
    required int branchId,
    required List<Map<String, int>> payments,
    required int categoryId,
    required int amount,
    required String expenseDate,
    required String note,
    Uint8List? receiptPhoto,
  }) async {
    final cleanNote = note.trim();
    _validateExpenseReceipt(receiptPhoto);
    final date = DateTime.tryParse(expenseDate);
    if (cleanNote.isEmpty ||
        cleanNote.length > 500 ||
        amount <= 0 ||
        amount > 9000000000000 ||
        date == null ||
        expenseDate.length != 10 ||
        date.toIso8601String().substring(0, 10) != expenseDate) {
      throw ArgumentError('Invalid expense information');
    }
    final allocations = _expensePaymentMap(payments, amount);
    final db = await database;
    return db.transaction((txn) async {
      final categories = await txn.query(
        'expense_categories',
        columns: ['name'],
        where: 'id = ? AND branch_id = ? AND active = 1',
        whereArgs: [categoryId, branchId],
      );
      if (categories.isEmpty) {
        throw StateError('Select an active expense category');
      }
      final cleanCategory = categories.single['name'] as String;
      await _checkExpenseBalances(txn, branchId, {}, allocations);
      final now = DateTime.now().toUtc().toIso8601String();
      final id = await txn.insert('expenses', {
        'branch_id': branchId,
        'account_id': allocations.keys.first,
        'category': cleanCategory,
        'amount': amount,
        'expense_date': expenseDate,
        'note': cleanNote,
        'posted_at': now,
      });
      for (final entry in allocations.entries) {
        await txn.insert('expense_payments', {
          'expense_id': id,
          'account_id': entry.key,
          'amount': entry.value,
        });
        await txn.insert('money_entries', {
          'account_id': entry.key,
          'kind': 'payment',
          'amount': -entry.value,
          'entry_date': expenseDate,
          'note': 'Expense #$id: $cleanCategory',
          'created_at': now,
          'expense_id': id,
        });
      }
      if (receiptPhoto != null) {
        await txn.insert('expense_receipts', {
          'expense_id': id,
          'photo': receiptPhoto,
          'added_at': now,
        });
      }
      return id;
    });
  }

  Future<void> editExpense({
    required int id,
    required int expectedRevision,
    required int categoryId,
    required List<Map<String, int>> payments,
    required int amount,
    required String expenseDate,
    required String note,
    Uint8List? receiptPhoto,
    bool removeReceipt = false,
  }) async {
    await VoucherPermissions.requireEditable();
    final description = note.trim();
    final parsed = DateTime.tryParse(expenseDate);
    _validateExpenseReceipt(receiptPhoto);
    if (description.isEmpty ||
        description.length > 500 ||
        amount <= 0 ||
        amount > 9000000000000 ||
        parsed == null ||
        expenseDate.length != 10 ||
        parsed.toIso8601String().substring(0, 10) != expenseDate ||
        (receiptPhoto != null && removeReceipt)) {
      throw ArgumentError('Invalid expense correction');
    }
    final allocations = _expensePaymentMap(payments, amount);
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty ||
          rows.single['status'] != 'posted' ||
          rows.single['revision'] != expectedRevision) {
        throw StateError('Expense has changed. Reload it before editing');
      }
      final old = rows.single;
      final branchId = old['branch_id'] as int;
      final categoryRows = await txn.query(
        'expense_categories',
        columns: ['name', 'active'],
        where: 'branch_id = ? AND id = ?',
        whereArgs: [branchId, categoryId],
      );
      if (categoryRows.isEmpty ||
          (categoryRows.single['active'] != 1 &&
              categoryRows.single['name'] != old['category'])) {
        throw StateError('Select an active category');
      }
      final category = categoryRows.single['name'] as String;
      final savedPayments = await txn.query(
        'expense_payments',
        where: 'expense_id = ?',
        whereArgs: [id],
      );
      final before = {
        for (final row in savedPayments)
          row['account_id'] as int: row['amount'] as int,
      };
      final oldAmount = old['amount'] as int;
      final oldAccount = old['account_id'] as int;
      if (before.isEmpty ||
          before.values.fold<int>(0, (a, b) => a + b) != oldAmount) {
        throw StateError('Stored expense payments are inconsistent');
      }
      await _checkExpenseBalances(txn, branchId, before, allocations);
      final previousPhoto = await txn.query(
        'expense_receipts',
        columns: ['expense_id'],
        where: 'expense_id = ?',
        whereArgs: [id],
      );
      final receiptAction = removeReceipt
          ? (previousPhoto.isEmpty ? 'unchanged' : 'removed')
          : receiptPhoto == null
          ? 'unchanged'
          : previousPhoto.isEmpty
          ? 'added'
          : 'replaced';
      final now = DateTime.now().toUtc().toIso8601String();
      final changed = await txn.update(
        'expenses',
        {
          'account_id': allocations.keys.first,
          'category': category,
          'amount': amount,
          'expense_date': expenseDate,
          'note': description,
          'revision': expectedRevision + 1,
        },
        where: "id = ? AND status = 'posted' AND revision = ?",
        whereArgs: [id, expectedRevision],
      );
      if (changed != 1) throw StateError('Expense changed. Reload and retry');
      final editId = await txn.insert('expense_edits', {
        'expense_id': id,
        'previous_category': old['category'],
        'category': category,
        'previous_account_id': oldAccount,
        'account_id': allocations.keys.first,
        'previous_amount': oldAmount,
        'amount': amount,
        'previous_payments': jsonEncode(
          before.map((k, v) => MapEntry('$k', v)),
        ),
        'payments': jsonEncode(allocations.map((k, v) => MapEntry('$k', v))),
        'previous_expense_date': old['expense_date'],
        'expense_date': expenseDate,
        'previous_note': old['note'],
        'note': description,
        'receipt_action': receiptAction,
        'changed_at': now,
      });
      final correctionDate = AppDateTime.today().toIso8601String().substring(
        0,
        10,
      );
      Future<void> adjust(int targetAccount, int delta, String label) async {
        if (delta == 0) return;
        await txn.insert('money_entries', {
          'account_id': targetAccount,
          'kind': 'adjustment',
          'amount': delta,
          'entry_date': correctionDate,
          'note': 'Expense #$id edit #$editId: $label',
          'created_at': now,
          'expense_id': id,
        });
      }

      for (final account in {...before.keys, ...allocations.keys}) {
        await adjust(
          account,
          (before[account] ?? 0) - (allocations[account] ?? 0),
          'payment allocation correction',
        );
      }
      await txn.delete(
        'expense_payments',
        where: 'expense_id = ?',
        whereArgs: [id],
      );
      for (final entry in allocations.entries) {
        await txn.insert('expense_payments', {
          'expense_id': id,
          'account_id': entry.key,
          'amount': entry.value,
        });
      }
      if (removeReceipt) {
        await txn.delete(
          'expense_receipts',
          where: 'expense_id = ?',
          whereArgs: [id],
        );
      } else if (receiptPhoto != null) {
        await txn.insert('expense_receipts', {
          'expense_id': id,
          'photo': receiptPhoto,
          'added_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> voidExpense({required int id, required String reason}) async {
    final cleanReason = reason.trim();
    if (cleanReason.isEmpty || cleanReason.length > 300) {
      throw ArgumentError('Enter a reason (up to 300 characters)');
    }
    final db = await database;
    await db.transaction(
      (txn) => _deleteReversevoidExpense(txn, id, cleanReason),
    );
  }

  Future<void> _deleteReversevoidExpense(
    Transaction txn,
    int id,
    String cleanReason,
  ) async {
    final rows = await txn.query('expenses', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty || rows.single['status'] != 'posted') {
      throw StateError('Expense is missing or already void');
    }
    final old = rows.single;
    final now = DateTime.now().toUtc().toIso8601String();
    final changed = await txn.update(
      'expenses',
      {'status': 'void', 'voided_at': now, 'void_reason': cleanReason},
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
    if (changed != 1) throw StateError('Expense changed. Reload and retry');
    final payments = await txn.query(
      'expense_payments',
      where: 'expense_id = ?',
      whereArgs: [id],
    );
    if (payments.isEmpty ||
        payments.fold<int>(0, (sum, p) => sum + (p['amount'] as int)) !=
            old['amount']) {
      throw StateError('Stored expense payments are inconsistent');
    }
    for (final payment in payments) {
      await txn.insert('money_entries', {
        'account_id': payment['account_id'],
        'kind': 'adjustment',
        'amount': payment['amount'],
        'entry_date': AppDateTime.today().toIso8601String().substring(0, 10),
        'note': 'Void expense #$id: $cleanReason',
        'created_at': now,
        'expense_id': id,
      });
    }
  }

  Future<void> saveMoneyAccount({
    int? id,
    required int branchId,
    required String name,
    required String type,
    required String accountNumber,
    required String remark,
    required int openingBalance,
    required String openingDate,
    int? expectedOpeningBalance,
    String correctionReason = '',
    String accountHolder = '',
  }) async {
    if (accountHolder.trim().length > 100) {
      throw ArgumentError('Account name is too long');
    }
    final cleanName = name.trim();
    if (cleanName.isEmpty ||
        cleanName.length > 100 ||
        !['cash', 'bank', 'wallet'].contains(type) ||
        openingBalance < 0 ||
        openingBalance > 9000000000000 ||
        accountNumber.trim().length > 100 ||
        remark.trim().length > 300) {
      throw ArgumentError('Invalid money account information');
    }
    final parsed = DateTime.tryParse(openingDate);
    if (parsed == null ||
        openingDate.length != 10 ||
        parsed.toIso8601String().substring(0, 10) != openingDate) {
      throw ArgumentError('Invalid opening date');
    }
    final db = await database;
    await db.transaction((txn) async {
      final values = <String, Object?>{
        'name': cleanName,
        'account_number': accountNumber.trim(),
        'remark': remark.trim(),
      };
      if (id == null) {
        final now = DateTime.now().toUtc().toIso8601String();
        final accountId = await txn.insert('money_accounts', {
          ...values,
          'branch_id': branchId,
          'type': type,
          'opening_date': openingDate,
          'created_at': now,
        });
        await txn.insert('app_settings', {
          'key': 'money_account_holder:$accountId',
          'value': accountHolder.trim(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        // Opening is its own entry, never sales revenue.
        await txn.insert('money_entries', {
          'account_id': accountId,
          'kind': 'opening',
          'amount': openingBalance,
          'entry_date': openingDate,
          'note': 'Opening balance',
          'created_at': now,
        });
      } else {
        final rows = await txn.query(
          'money_accounts',
          where: 'id = ?',
          whereArgs: [id],
        );
        if (rows.isEmpty) throw StateError('Account not found');
        final old = rows.single;
        await txn.insert('app_settings', {
          'key': 'money_account_holder:$id',
          'value': accountHolder.trim(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        final entries = await txn.query(
          'money_entries',
          where: 'account_id = ? AND kind = ?',
          whereArgs: [id, 'opening'],
        );
        if (old['branch_id'] != branchId ||
            old['type'] != type ||
            old['opening_date'] != openingDate ||
            entries.length != 1) {
          throw StateError('Branch, type and opening date cannot be changed');
        }
        final corrections = await txn.rawQuery(
          '''SELECT COALESCE(SUM(delta),0) AS total
          FROM opening_balance_corrections WHERE account_id = ?''',
          [id],
        );
        final currentOpening =
            (entries.single['amount'] as int) +
            (corrections.single['total'] as int);
        if (expectedOpeningBalance == null ||
            currentOpening != expectedOpeningBalance) {
          throw StateError(
            'Opening balance changed. Reopen this account and try again.',
          );
        }
        final delta = openingBalance - currentOpening;
        if (delta != 0) {
          final reason = correctionReason.trim();
          if (reason.isEmpty || reason.length > 300) {
            throw ArgumentError('Explain the opening balance correction');
          }
          final balance = await txn.rawQuery(
            '''SELECT COALESCE(SUM(amount),0) AS balance
            FROM money_entries WHERE account_id = ?''',
            [id],
          );
          final nextBalance = (balance.single['balance'] as int) + delta;
          if (nextBalance < 0 || nextBalance > 9000000000000) {
            throw StateError(
              'Correction would make the current balance invalid',
            );
          }
          final now = DateTime.now().toUtc().toIso8601String();
          final today = AppDateTime.today();
          final date =
              '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
          final entryId = await txn.insert('money_entries', {
            'account_id': id,
            'kind': 'adjustment',
            'amount': delta,
            'entry_date': date,
            'note': 'Opening balance correction: $reason',
            'created_at': now,
          });
          await txn.insert('opening_balance_corrections', {
            'account_id': id,
            'money_entry_id': entryId,
            'previous_amount': currentOpening,
            'new_amount': openingBalance,
            'delta': delta,
            'reason': reason,
            'created_at': now,
          });
        }
        await txn.update(
          'money_accounts',
          values,
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }

  Future<void> _createEmployees(Database db) async {
    await db.execute('''
      CREATE TABLE employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(code)) > 0),
        name TEXT NOT NULL CHECK(length(trim(name)) > 0),
        phone TEXT NOT NULL DEFAULT '',
        position TEXT NOT NULL DEFAULT '',
        default_branch_id INTEGER NOT NULL REFERENCES branches(id),
        active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
        remark TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX employees_branch_active
      ON employees(default_branch_id, active, name)
    ''');
  }

  Future<List<Map<String, Object?>>> getEmployees({
    required int branchId,
    bool activeOnly = false,
  }) async {
    final db = await database;
    return db.query(
      'employees',
      where: activeOnly
          ? 'default_branch_id = ? AND active = 1'
          : 'default_branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'active DESC, name COLLATE NOCASE, id',
    );
  }

  Future<void> saveEmployee({
    int? id,
    required String code,
    required String name,
    required String phone,
    required String position,
    required int branchId,
    required bool active,
    required String remark,
  }) async {
    final cleanCode = code.trim().toUpperCase();
    final cleanName = name.trim();
    if (cleanCode.isEmpty ||
        cleanCode.length > 30 ||
        cleanName.isEmpty ||
        cleanName.length > 100 ||
        phone.trim().length > 40 ||
        position.trim().length > 100 ||
        remark.trim().length > 300) {
      throw ArgumentError('Invalid employee information');
    }
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'code': cleanCode,
      'name': cleanName,
      'phone': phone.trim(),
      'position': position.trim(),
      'default_branch_id': branchId,
      'active': active ? 1 : 0,
      'remark': remark.trim(),
      'updated_at': now,
    };
    if (id == null) {
      await db.insert('employees', {...values, 'created_at': now});
    } else {
      final count = await db.update(
        'employees',
        values,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (count != 1) throw StateError('Employee not found');
    }
  }

  Future<void> _createContacts(Database db) async {
    await db.execute('''
      CREATE TABLE contacts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL CHECK(kind IN ('customer', 'supplier')),
        name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 100),
        phone TEXT NOT NULL DEFAULT '',
        company TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        remark TEXT NOT NULL DEFAULT '',
        active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX contacts_kind_active_name ON contacts(kind, active, name)
    ''');
  }

  Future<List<Map<String, Object?>>> getContacts({
    required String kind,
    bool activeOnly = false,
  }) async {
    if (!['customer', 'supplier'].contains(kind)) {
      throw ArgumentError('Invalid contact type');
    }
    final db = await database;
    return db.query(
      'contacts',
      where: activeOnly ? 'kind = ? AND active = 1' : 'kind = ?',
      whereArgs: [kind],
      orderBy: 'active DESC, name COLLATE NOCASE, id',
    );
  }

  Future<void> saveContact({
    int? id,
    required String kind,
    required String name,
    required String phone,
    required String company,
    required String address,
    required String remark,
    required bool active,
  }) async {
    if (!['customer', 'supplier'].contains(kind) ||
        name.trim().isEmpty ||
        name.trim().length > 100 ||
        phone.trim().length > 80 ||
        company.trim().length > 150 ||
        address.trim().length > 500 ||
        remark.trim().length > 500) {
      throw ArgumentError('Invalid contact information');
    }
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final values = <String, Object?>{
      'name': name.trim(),
      'phone': phone.trim(),
      'company': company.trim(),
      'address': address.trim(),
      'remark': remark.trim(),
      'active': active ? 1 : 0,
      'updated_at': now,
    };
    if (id == null) {
      await db.insert('contacts', {...values, 'kind': kind, 'created_at': now});
    } else {
      final count = await db.update(
        'contacts',
        values,
        where: 'id = ? AND kind = ?',
        whereArgs: [id, kind],
      );
      if (count != 1) throw StateError('Contact not found');
    }
  }

  Future<void> _createSaleDrafts(Database db) async {
    await db.execute('''
      CREATE TABLE sale_drafts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        branch_id INTEGER NOT NULL REFERENCES branches(id),
        customer_id INTEGER REFERENCES contacts(id),
        customer_name TEXT NOT NULL DEFAULT '',
        customer_phone TEXT NOT NULL DEFAULT '',
        customer_company TEXT NOT NULL DEFAULT '',
        customer_address TEXT NOT NULL DEFAULT '',
        employee_id INTEGER NOT NULL REFERENCES employees(id),
        employee_name TEXT NOT NULL,
        invoice_date TEXT NOT NULL,
        discount_type TEXT NOT NULL CHECK(discount_type IN ('amount', 'percent')),
        discount_value INTEGER NOT NULL CHECK(discount_value >= 0),
        subtotal INTEGER NOT NULL CHECK(subtotal BETWEEN 0 AND 9000000000000),
        discount_amount INTEGER NOT NULL CHECK(discount_amount >= 0 AND discount_amount <= subtotal),
        total INTEGER NOT NULL CHECK(total = subtotal - discount_amount),
        revision INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sale_draft_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        draft_id INTEGER NOT NULL REFERENCES sale_drafts(id) ON DELETE CASCADE,
        product_id INTEGER NOT NULL REFERENCES products(id),
        item_code TEXT NOT NULL,
        item_name TEXT NOT NULL,
        price INTEGER NOT NULL CHECK(price BETWEEN 0 AND 2147483647),
        qty INTEGER NOT NULL CHECK(qty BETWEEN 1 AND 2147483647),
        amount INTEGER NOT NULL CHECK(amount = price * qty AND amount <= 9000000000000),
        UNIQUE(draft_id, product_id)
      )
    ''');
    await db.execute('''
      CREATE INDEX sale_drafts_branch_date ON sale_drafts(branch_id, invoice_date, id)
    ''');
  }

  Future<List<Map<String, Object?>>> getSaleDrafts({
    required int branchId,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''SELECT d.* FROM sale_drafts d WHERE d.branch_id = ?
      AND NOT EXISTS (SELECT 1 FROM sale_invoices s WHERE s.draft_id = d.id)
      AND d.correction_source_sale_id IS NULL
      ORDER BY d.id DESC''',
      [branchId],
    );
  }

  Future<Map<String, Object?>> getSaleDraft(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''SELECT d.*, b.name AS branch_name, b.code AS branch_code
        FROM sale_drafts d JOIN branches b ON b.id = d.branch_id WHERE d.id = ?''',
        [id],
      );
      if (rows.isEmpty) throw StateError('Draft not found');
      final items = await txn.query(
        'sale_draft_items',
        where: 'draft_id = ?',
        whereArgs: [id],
        orderBy: 'id',
      );
      final draft = rows.single;
      final source = draft['correction_source_sale_id'];
      if (source == null) return {...draft, 'items': items};
      final links = (await txn.rawQuery(
        """SELECT
        (SELECT COALESCE(SUM(a.amount),0) FROM receipt_allocations a
          JOIN customer_receipts r ON r.id=a.receipt_id
          WHERE a.sale_id=? AND r.status='posted') AS linked_paid,
        (SELECT COUNT(*) FROM sale_returns r
          WHERE r.sale_id=? AND r.status='posted') AS linked_returns,
        (SELECT COUNT(*) FROM sale_exchange_links x
          JOIN sale_returns r ON r.id=x.return_id
          WHERE r.sale_id=? OR x.replacement_sale_id=?) AS linked_exchanges""",
        [source, source, source, source],
      )).single;
      return {...draft, 'items': items, ...links};
    });
  }

  Future<int> saveSaleDraft({
    int? id,
    int? revision,
    String? recoveryKey,
    required int branchId,
    int? customerId,
    required bool saveCustomer,
    required String customerName,
    required String customerPhone,
    required String customerCompany,
    required String customerAddress,
    required int employeeId,
    required String invoiceDate,
    required String discountType,
    required int discountValue,
    required List<Map<String, Object?>> items,
    String remark = '',
    String desktopPaymentJson = '{}',
  }) async {
    if (remark.trim().length > 4000 || desktopPaymentJson.length > 2000) {
      throw ArgumentError('Invoice detail is too long');
    }
    final paymentData = jsonDecode(desktopPaymentJson);
    if (paymentData is! Map ||
        (paymentData['account_id'] != null &&
            paymentData['account_id'] is! int) ||
        (paymentData['text'] != null && paymentData['text'] is! String)) {
      throw ArgumentError('Invalid draft payment');
    }
    if (items.isEmpty ||
        items.length > 300 ||
        !['amount', 'percent'].contains(discountType) ||
        discountValue < 0 ||
        discountValue > 9000000000000 ||
        (discountType == 'percent' && discountValue > 100) ||
        customerName.trim().length > 100 ||
        customerPhone.trim().length > 80 ||
        customerCompany.trim().length > 150 ||
        customerAddress.trim().length > 500 ||
        (saveCustomer && customerName.trim().isEmpty)) {
      throw ArgumentError('Check customer, items and discount');
    }
    final date = DateTime.tryParse(invoiceDate);
    if (date == null ||
        invoiceDate.length != 10 ||
        date.toIso8601String().substring(0, 10) != invoiceDate) {
      throw ArgumentError('Invalid invoice date');
    }
    final db = await database;
    if (id != null) {
      final drafts = await db.query(
        'sale_drafts',
        columns: ['correction_source_sale_id'],
        where: 'id=?',
        whereArgs: [id],
      );
      if (drafts.isNotEmpty &&
          drafts.single['correction_source_sale_id'] != null) {
        await VoucherPermissions.requireEditable();
      }
    }
    final liveSaleOrigin = LiveSaleSync.origin;
    final result = await db.transaction((txn) async {
      if (id != null &&
          (await txn.query(
            'sale_invoices',
            where: 'draft_id = ?',
            whereArgs: [id],
          )).isNotEmpty) {
        throw StateError('This draft is already a confirmed sale.');
      }
      final staff = await txn.query(
        'employees',
        where: 'id = ? AND default_branch_id = ? AND active = 1',
        whereArgs: [employeeId, branchId],
      );
      if (staff.isEmpty) {
        throw StateError('Choose an active sale person for this branch.');
      }
      if (customerId != null) {
        final contacts = await txn.query(
          'contacts',
          where: 'id = ? AND kind = ?',
          whereArgs: [customerId, 'customer'],
        );
        if (contacts.isEmpty) throw StateError('Customer not found.');
      }
      final snapshots = <Map<String, Object?>>[];
      final seen = <int>{};
      int subtotal = 0, itemDiscounts = 0;
      for (final item in items) {
        final productId = item['product_id'] as int?;
        final price = item['price'] as int?;
        final qty = item['qty'] as int?;
        if (productId == null ||
            price == null ||
            qty == null ||
            !seen.add(productId) ||
            price < 0 ||
            price > 2147483647 ||
            qty < 1 ||
            qty > 2147483647) {
          throw ArgumentError('Invalid invoice item');
        }
        final product = await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [productId],
        );
        if (product.isEmpty) throw StateError('Product not found.');
        final amount = price * qty;
        final rowDiscount = item['item_discount'] ?? 0;
        if (rowDiscount is! int || rowDiscount < 0 || rowDiscount > amount) {
          throw ArgumentError('Item discount exceeds its row amount');
        }
        itemDiscounts += rowDiscount;
        subtotal += amount;
        if (subtotal > 9000000000000) {
          throw ArgumentError('Invoice amount is too large');
        }
        snapshots.add({
          'product_id': productId,
          'item_code': product.single['item_code'],
          'item_name': product.single['name'],
          'price': price,
          'qty': qty,
          'amount': amount,
          'item_discount': rowDiscount,
          'color_snapshot': product.single['color'] ?? '',
          'size_snapshot': product.single['size'] ?? '',
          'tracking_json': jsonEncode(
            ProductTracking.decode(item['tracking_json']),
          ),
        });
      }
      final voucherBasis = subtotal - itemDiscounts;
      final voucherDiscount = discountType == 'percent'
          ? voucherBasis * discountValue ~/ 100
          : discountValue;
      final discount = itemDiscounts + voucherDiscount;
      if (discount > subtotal) throw ArgumentError('Discount exceeds subtotal');
      final now = DateTime.now().toUtc().toIso8601String();
      var contactId = customerId;
      if (saveCustomer && contactId == null) {
        contactId = await txn.insert('contacts', {
          'kind': 'customer',
          'name': customerName.trim(),
          'phone': customerPhone.trim(),
          'company': customerCompany.trim(),
          'address': customerAddress.trim(),
          'remark': '',
          'active': 1,
          'created_at': now,
          'updated_at': now,
        });
      }
      final currency = await txn.query('business_profile', where: 'id = 1');
      final values = <String, Object?>{
        'currency_code': currency.single['currency_code'],
        'currency_digits': currency.single['currency_digits'],
        'branch_id': branchId,
        'customer_id': contactId,
        'customer_name': customerName.trim(),
        'customer_phone': customerPhone.trim(),
        'customer_company': customerCompany.trim(),
        'customer_address': customerAddress.trim(),
        'employee_id': employeeId,
        'employee_name': staff.single['name'],
        'invoice_date': invoiceDate,
        'discount_type': discountType,
        'discount_value': discountValue,
        'subtotal': subtotal,
        'discount_amount': discount,
        'voucher_discount_amount': voucherDiscount,
        'remark': remark.trim(),
        'desktop_payment_json': desktopPaymentJson,
        'total': subtotal - discount,
        'updated_at': now,
      };
      final int draftId;
      if (id == null) {
        draftId = await txn.insert('sale_drafts', {
          ...values,
          'created_at': now,
        });
      } else {
        final count = await txn.update(
          'sale_drafts',
          {...values, 'revision': (revision ?? 0) + 1},
          where: 'id = ? AND revision = ?',
          whereArgs: [id, revision],
        );
        if (count != 1) {
          throw StateError('Draft changed. Reopen it before editing.');
        }
        draftId = id;
        await txn.delete(
          'sale_draft_items',
          where: 'draft_id = ?',
          whereArgs: [draftId],
        );
      }
      for (final snapshot in snapshots) {
        await txn.insert('sale_draft_items', {
          ...snapshot,
          'draft_id': draftId,
        });
      }
      if (recoveryKey != null) {
        final expected = id == null ? 'new' : 'draft:$id';
        if (recoveryKey != expected) {
          throw ArgumentError('Invalid recovery key');
        }
        await txn.delete(
          'sale_recovery',
          where: 'recovery_key = ?',
          whereArgs: [recoveryKey],
        );
      }
      await LiveSaleSync.record(txn, origin: liveSaleOrigin, draftId: draftId);
      return draftId;
    });
    LiveSaleSync.wake();
    return result;
  }

  Future<void> _createSaleRecovery(Database db) async {
    await db.execute('''
      CREATE TABLE sale_recovery (
        recovery_key TEXT PRIMARY KEY,
        source_draft_id INTEGER REFERENCES sale_drafts(id),
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> putSaleRecovery({
    required String key,
    int? sourceId,
    required String payload,
  }) async {
    if (key != (sourceId == null ? 'new' : 'draft:$sourceId') ||
        payload.length > 2000000) {
      throw ArgumentError('Invalid recovery data');
    }
    final db = await database;
    await db.transaction((txn) async {
      if (sourceId != null &&
          (await txn.query(
            'sale_invoices',
            where: 'draft_id = ?',
            whereArgs: [sourceId],
          )).isNotEmpty) {
        throw StateError('Cannot auto-save edits to a confirmed sale.');
      }
      await txn.insert('sale_recovery', {
        'recovery_key': key,
        'source_draft_id': sourceId,
        'payload': payload,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<Map<String, Object?>?> getSaleRecovery(String key) async {
    final db = await database;
    final rows = await db.query(
      'sale_recovery',
      where: 'recovery_key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.single;
  }

  Future<List<Map<String, Object?>>> getSaleRecoveries() async {
    final db = await database;
    return db.query('sale_recovery', orderBy: 'updated_at DESC');
  }

  Future<void> deleteSaleRecovery(String key) async {
    final db = await database;
    await db.delete(
      'sale_recovery',
      where: 'recovery_key = ?',
      whereArgs: [key],
    );
  }

  Future<void> _createSalePosting(Database db) async {
    await db.execute('''
      CREATE TABLE sale_invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        draft_id INTEGER NOT NULL UNIQUE REFERENCES sale_drafts(id),
        branch_id INTEGER NOT NULL REFERENCES branches(id),
        customer_id INTEGER REFERENCES contacts(id),
        customer_name TEXT NOT NULL, customer_phone TEXT NOT NULL,
        customer_company TEXT NOT NULL, customer_address TEXT NOT NULL,
        employee_id INTEGER NOT NULL REFERENCES employees(id), employee_name TEXT NOT NULL,
        invoice_date TEXT NOT NULL,
        subtotal INTEGER NOT NULL CHECK(subtotal >= 0),
        discount_amount INTEGER NOT NULL CHECK(discount_amount >= 0 AND discount_amount <= subtotal),
        total INTEGER NOT NULL CHECK(total = subtotal - discount_amount),
        paid INTEGER NOT NULL CHECK(paid >= 0 AND paid <= total),
        balance_due INTEGER NOT NULL CHECK(balance_due = total - paid),
        confirmed_at TEXT NOT NULL,
        CHECK(balance_due = 0 OR customer_id IS NOT NULL)
      )
    ''');
    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL REFERENCES sale_invoices(id),
        product_id INTEGER NOT NULL REFERENCES products(id),
        item_code TEXT NOT NULL, item_name TEXT NOT NULL,
        price INTEGER NOT NULL CHECK(price >= 0), qty INTEGER NOT NULL CHECK(qty > 0),
        amount INTEGER NOT NULL CHECK(amount = price * qty),
        UNIQUE(sale_id, product_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE sale_payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL REFERENCES sale_invoices(id),
        account_id INTEGER NOT NULL REFERENCES money_accounts(id),
        amount INTEGER NOT NULL CHECK(amount > 0),
        payment_date TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(sale_id, account_id)
      )
    ''');
    await db.execute(
      'ALTER TABLE money_entries ADD COLUMN sale_id INTEGER REFERENCES sale_invoices(id)',
    );
    await db.execute('''
      CREATE UNIQUE INDEX money_sale_account_receipt ON money_entries(sale_id, account_id)
      WHERE sale_id IS NOT NULL AND kind = 'receipt'
    ''');
    await db.execute(
      'ALTER TABLE stock_movements RENAME TO previous_stock_movements',
    );
    await db.execute('DROP INDEX stock_movement_branch_product');
    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        branch_id INTEGER NOT NULL REFERENCES branches(id),
        product_id INTEGER NOT NULL REFERENCES products(id),
        quantity INTEGER NOT NULL CHECK(quantity > 0),
        kind TEXT NOT NULL CHECK(kind IN ('opening', 'in', 'sale')),
        note TEXT NOT NULL, created_at TEXT NOT NULL,
        sale_id INTEGER REFERENCES sale_invoices(id)
      )
    ''');
    await db.execute('''
      INSERT INTO stock_movements(id, branch_id, product_id, quantity, kind, note, created_at)
      SELECT id, branch_id, product_id, quantity, kind, note, created_at FROM previous_stock_movements
    ''');
    await db.execute('DROP TABLE previous_stock_movements');
    await db.execute(
      'CREATE INDEX stock_movement_branch_product ON stock_movements(branch_id, product_id, id)',
    );
    await db.execute(
      'CREATE INDEX sale_invoices_branch_date ON sale_invoices(branch_id, invoice_date, id)',
    );
  }

  Future<void> _createSaleReturns(Database db) async {
    await db.execute('''CREATE TABLE sale_returns (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sale_id INTEGER NOT NULL REFERENCES sale_invoices(id),
      branch_id INTEGER NOT NULL REFERENCES branches(id),
      return_date TEXT NOT NULL,
      total INTEGER NOT NULL CHECK(total > 0 AND total <= 9000000000000),
      reason TEXT NOT NULL CHECK(length(trim(reason)) BETWEEN 1 AND 500),
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE sale_return_items (
      return_id INTEGER NOT NULL REFERENCES sale_returns(id),
      sale_item_id INTEGER NOT NULL REFERENCES sale_items(id),
      product_id INTEGER NOT NULL REFERENCES products(id),
      item_code TEXT NOT NULL, item_name TEXT NOT NULL,
      qty INTEGER NOT NULL CHECK(qty > 0),
      refund_amount INTEGER NOT NULL CHECK(refund_amount >= 0),
      PRIMARY KEY(return_id, sale_item_id)
    )''');
    await db.execute('''CREATE TABLE sale_return_refunds (
      return_id INTEGER NOT NULL REFERENCES sale_returns(id),
      account_id INTEGER NOT NULL REFERENCES money_accounts(id),
      amount INTEGER NOT NULL CHECK(amount > 0),
      PRIMARY KEY(return_id, account_id)
    )''');
    await db.execute(
      'CREATE INDEX sale_returns_sale ON sale_returns(sale_id, id)',
    );
    await db.execute(
      'CREATE INDEX sale_returns_branch ON sale_returns(branch_id, id)',
    );
    await db.execute(
      'ALTER TABLE money_entries ADD COLUMN sale_return_id INTEGER REFERENCES sale_returns(id)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX money_return_refund ON money_entries(sale_return_id, account_id) WHERE sale_return_id IS NOT NULL',
    );
    await db.execute(
      'ALTER TABLE stock_movements ADD COLUMN sale_return_id INTEGER REFERENCES sale_returns(id)',
    );
  }

  Future<void> _createSaleExchangeLinks(Database db) async {
    await db.execute('''CREATE TABLE sale_exchange_links (
      return_id INTEGER PRIMARY KEY REFERENCES sale_returns(id) ON DELETE CASCADE,
      replacement_sale_id INTEGER NOT NULL UNIQUE REFERENCES sale_invoices(id) ON DELETE CASCADE,
      linked_at TEXT NOT NULL
    )''');
  }

  Future<List<Map<String, Object?>>> getSaleExchangeCandidates(
    int returnId,
  ) async {
    final db = await database;
    return db.rawQuery(
      '''SELECT n.id, n.invoice_date, n.customer_name, n.total
      FROM sale_returns r JOIN sale_invoices original ON original.id = r.sale_id
      JOIN sale_invoices n ON n.branch_id = r.branch_id
        AND n.customer_id IS original.customer_id AND n.customer_name = original.customer_name
      WHERE r.id = ? AND r.status = 'posted' AND n.status = 'posted'
        AND n.id != r.sale_id AND n.invoice_date >= r.return_date
        AND NOT EXISTS(SELECT 1 FROM sale_exchange_links x
          WHERE x.replacement_sale_id = n.id AND x.return_id != r.id)
      ORDER BY n.invoice_date DESC, n.id DESC''',
      [returnId],
    );
  }

  Future<void> linkSaleExchange({
    required int returnId,
    int? replacementSaleId,
  }) async {
    await VoucherPermissions.requireEditable();
    final db = await database;
    await db.transaction((txn) async {
      if (replacementSaleId == null) {
        await txn.delete(
          'sale_exchange_links',
          where: 'return_id = ?',
          whereArgs: [returnId],
        );
        return;
      }
      final valid = await txn.rawQuery(
        '''SELECT n.id FROM sale_returns r
        JOIN sale_invoices original ON original.id = r.sale_id
        JOIN sale_invoices n ON n.branch_id = r.branch_id
          AND n.customer_id IS original.customer_id AND n.customer_name = original.customer_name
        WHERE r.id = ? AND r.status = 'posted' AND n.id = ? AND n.status = 'posted'
          AND n.id != r.sale_id AND n.invoice_date >= r.return_date''',
        [returnId, replacementSaleId],
      );
      if (valid.length != 1) {
        throw StateError(
          'Select a posted replacement sale for the same customer and branch, dated on or after the return.',
        );
      }
      final used = await txn.query(
        'sale_exchange_links',
        where: 'replacement_sale_id = ? AND return_id != ?',
        whereArgs: [replacementSaleId, returnId],
      );
      if (used.isNotEmpty) {
        throw StateError('Replacement invoice is linked to another return.');
      }
      await txn.delete(
        'sale_exchange_links',
        where: 'return_id = ?',
        whereArgs: [returnId],
      );
      await txn.insert('sale_exchange_links', {
        'return_id': returnId,
        'replacement_sale_id': replacementSaleId,
        'linked_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<void> _addSaleReturnStaff(Database db) async {
    await db.execute(
      'ALTER TABLE sale_returns ADD COLUMN employee_id INTEGER REFERENCES employees(id)',
    );
    await db.execute(
      "ALTER TABLE sale_returns ADD COLUMN employee_name TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _addSaleReturnCorrections(Database db) async {
    await db.execute(
      "ALTER TABLE sale_returns ADD COLUMN status TEXT NOT NULL DEFAULT 'posted' CHECK(status IN ('posted', 'void'))",
    );
    await db.execute(
      "ALTER TABLE sale_returns ADD COLUMN void_reason TEXT NOT NULL DEFAULT ''",
    );
    await db.execute('ALTER TABLE sale_returns ADD COLUMN voided_at TEXT');
    await db.execute(
      'ALTER TABLE sale_returns ADD COLUMN replacement_id INTEGER REFERENCES sale_returns(id)',
    );
    await db.execute('DROP INDEX money_return_refund');
    await db.execute(
      '''CREATE UNIQUE INDEX money_return_refund
      ON money_entries(sale_return_id, account_id, kind) WHERE sale_return_id IS NOT NULL''',
    );
  }

  Future<void> _addPostedInvoiceVoids(Database db) async {
    for (final table in [
      'sale_invoices',
      'purchase_invoices',
      'supplier_settlements',
    ]) {
      await db.execute(
        "ALTER TABLE $table ADD COLUMN status TEXT NOT NULL DEFAULT 'posted' CHECK(status IN ('posted','void'))",
      );
      await db.execute(
        "ALTER TABLE $table ADD COLUMN void_reason TEXT NOT NULL DEFAULT ''",
      );
      await db.execute('ALTER TABLE $table ADD COLUMN voided_at TEXT');
    }
    await db.execute('DROP INDEX money_supplier_settlement_account');
    await db.execute('''CREATE UNIQUE INDEX money_supplier_settlement_account
      ON money_entries(supplier_settlement_id, account_id, kind)
      WHERE supplier_settlement_id IS NOT NULL''');
    await db.execute('DROP INDEX money_purchase_account_payment');
    await db.execute('''CREATE UNIQUE INDEX money_purchase_account_payment
      ON money_entries(purchase_id, account_id, kind)
      WHERE purchase_id IS NOT NULL''');
    await db.execute(
      'ALTER TABLE sale_drafts ADD COLUMN correction_source_sale_id INTEGER REFERENCES sale_invoices(id)',
    );
    await db.execute(
      'ALTER TABLE sale_invoices ADD COLUMN replacement_id INTEGER REFERENCES sale_invoices(id)',
    );
    await db.execute(
      'ALTER TABLE purchase_invoices ADD COLUMN replacement_id INTEGER REFERENCES purchase_invoices(id)',
    );
    await db.execute(
      'ALTER TABLE customer_receipts ADD COLUMN replacement_id INTEGER REFERENCES customer_receipts(id)',
    );
    await db.execute(
      'ALTER TABLE supplier_settlements ADD COLUMN replacement_id INTEGER REFERENCES supplier_settlements(id)',
    );
  }

  Future<List<Map<String, Object?>>> getSaleReturns({
    required int branchId,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''SELECT r.*, s.customer_name, s.currency_code, s.currency_digits
      FROM sale_returns r JOIN sale_invoices s ON s.id = r.sale_id
      WHERE r.branch_id = ? ORDER BY r.id DESC''',
      [branchId],
    );
  }

  Future<List<Map<String, Object?>>> _saleReturnLots(Transaction txn, int id) =>
      txn.rawQuery(
        """SELECT a.sale_item_id, a.lot_id, a.quantity, l.product_id, l.serial, l.imei
           FROM return_lot_allocations a JOIN stock_lots l ON l.id = a.lot_id
           WHERE a.return_id = ? ORDER BY a.sale_item_id, a.lot_id""",
        [id],
      );

  Future<Map<String, Object?>> getSaleReturn(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''SELECT r.*, s.customer_name, s.customer_phone, s.customer_address, s.customer_company,
        s.business_name, s.branch_name_snapshot, s.branch_code_snapshot,
        s.branch_phone_snapshot, s.branch_address_snapshot, s.currency_code, s.currency_digits
        FROM sale_returns r JOIN sale_invoices s ON s.id = r.sale_id WHERE r.id = ?''',
        [id],
      );
      if (rows.isEmpty) throw StateError('Return not found');
      var items = await txn.query(
        'sale_return_items',
        where: 'return_id = ?',
        whereArgs: [id],
        orderBy: 'sale_item_id',
      );
      var lots = await _saleReturnLots(txn, id);
      if (items.isEmpty && rows.single['status'] == 'void') {
        final archived = await txn.query(
          'app_settings',
          columns: ['value'],
          where: 'key = ?',
          whereArgs: ['sale_edit_void_return:$id'],
        );
        if (archived.isNotEmpty) {
          final snapshot =
              jsonDecode(archived.single['value'] as String) as Map;
          items = (snapshot['items'] as List)
              .map((row) => Map<String, Object?>.from(row as Map))
              .toList();
          lots = [];
          for (final raw in snapshot['lots'] as List? ?? const []) {
            final lot = Map<String, Object?>.from(raw as Map);
            if (!lot.containsKey('serial')) {
              final stock = await txn.query(
                'stock_lots',
                columns: ['serial', 'imei'],
                where: 'id = ?',
                whereArgs: [lot['lot_id']],
              );
              if (stock.isNotEmpty) lot.addAll(stock.single);
            }
            lots.add(lot);
          }
        }
      }
      final refunds = await txn.rawQuery(
        '''SELECT p.*, a.name AS account_name
        FROM sale_return_refunds p JOIN money_accounts a ON a.id = p.account_id
        WHERE p.return_id = ? ORDER BY p.account_id''',
        [id],
      );
      final exchange = await txn.rawQuery(
        '''SELECT x.*, s.status, s.invoice_date
        FROM sale_exchange_links x JOIN sale_invoices s ON s.id = x.replacement_sale_id
        WHERE x.return_id = ?''',
        [id],
      );
      final tracking = <Object?, List<Map<String, Object?>>>{};
      for (final lot in lots) {
        (tracking[lot['sale_item_id']] ??= []).add({
          'lot_id': lot['lot_id'],
          'qty': lot['quantity'],
          'serial': lot['serial'],
          'imei': lot['imei'],
        });
      }
      return {
        ...rows.single,
        'items': [
          for (final item in items)
            {
              ...item,
              'tracking_json': jsonEncode(
                tracking[item['sale_item_id']] ?? const [],
              ),
            },
        ],
        'edit_lots': lots,
        'refunds': refunds,
        'exchange': exchange.isEmpty ? null : exchange.single,
      };
    });
  }

  Future<int> postSaleReturn({
    required int saleId,
    required String returnDate,
    required String reason,
    required int employeeId,
    required Map<int, int> itemQuantities,
    required List<Map<String, int>> refunds,
    Map<int, String> trackedReturns = const {},
  }) async {
    final db = await database;
    return db.transaction(
      (txn) => _postSaleReturn(
        txn,
        saleId: saleId,
        returnDate: returnDate,
        reason: reason,
        employeeId: employeeId,
        itemQuantities: itemQuantities,
        refunds: refunds,
        trackedReturns: trackedReturns,
      ),
    );
  }

  Future<int> _postSaleReturn(
    Transaction txn, {
    required int saleId,
    required String returnDate,
    required String reason,
    required int employeeId,
    required Map<int, int> itemQuantities,
    required List<Map<String, int>> refunds,
    Map<int, String> trackedReturns = const {},
  }) async {
    final day = DateTime.tryParse(returnDate);
    if (day == null ||
        returnDate.length != 10 ||
        day.toIso8601String().substring(0, 10) != returnDate ||
        reason.trim().isEmpty ||
        reason.trim().length > 500 ||
        itemQuantities.isEmpty) {
      throw ArgumentError('Invalid return date, reason or items');
    }
    final saleRows = await txn.query(
      'sale_invoices',
      where: 'id = ?',
      whereArgs: [saleId],
    );
    if (saleRows.isEmpty) throw StateError('Sale not found');
    final sale = saleRows.single;
    if (sale['status'] != 'posted') throw StateError('Sale invoice is void');
    if (sale['balance_due'] != 0) {
      throw StateError(
        'Credit sale returns need debt adjustment. Settle the invoice first.',
      );
    }
    if (returnDate.compareTo(sale['invoice_date'] as String) < 0) {
      throw ArgumentError('Return date predates sale');
    }
    final branchId = sale['branch_id'] as int;
    final staff = await txn.query(
      'employees',
      where: 'id = ? AND default_branch_id = ? AND active = 1',
      whereArgs: [employeeId, branchId],
    );
    if (staff.isEmpty) {
      throw StateError('Choose an active sale person in this branch');
    }
    final items = await txn.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'id',
    );
    final prior = await txn.rawQuery(
      '''SELECT i.sale_item_id, SUM(i.qty) AS qty
        FROM sale_return_items i JOIN sale_returns r ON r.id = i.return_id
        WHERE r.sale_id = ? AND r.status = 'posted' GROUP BY i.sale_item_id''',
      [saleId],
    );
    final used = {
      for (final row in prior) row['sale_item_id'] as int: row['qty'] as int,
    };
    final saleTotal = sale['total'] as int;
    final netLines = SaleInvoiceDetails.lineNets(items, saleTotal);
    // Allocate the original invoice discount across lines deterministically.
    var amount = 0;
    final accepted = <Map<String, Object?>>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final lineTotal = netLines[i];
      final id = item['id'] as int;
      final qty = itemQuantities[id] ?? 0;
      final sold = item['qty'] as int;
      final previous = used[id] ?? 0;
      if (qty < 0 || qty > sold - previous) {
        throw StateError('Return quantity exceeds remaining sold quantity');
      }
      if (qty == 0) continue;
      // Last quantity absorbs any rounding remainder.
      final before =
          (BigInt.from(lineTotal) * BigInt.from(previous) ~/ BigInt.from(sold))
              .toInt();
      final after =
          (BigInt.from(lineTotal) *
                  BigInt.from(previous + qty) ~/
                  BigInt.from(sold))
              .toInt();
      final refund = after - before;
      amount += refund;
      accepted.add({...item, 'return_qty': qty, 'refund': refund});
    }
    if (accepted.isEmpty ||
        amount <= 0 ||
        amount > 9000000000000 ||
        itemQuantities.keys.any((id) => !items.any((row) => row['id'] == id))) {
      throw ArgumentError(
        'Select return items with a positive refundable amount',
      );
    }
    final seen = <int>{};
    var refundSum = 0;
    for (final p in refunds) {
      final accountId = p['account_id'];
      final value = p['amount'];
      if (accountId == null ||
          value == null ||
          value <= 0 ||
          !seen.add(accountId)) {
        throw ArgumentError('Invalid refund account or amount');
      }
      final account = await txn.query(
        'money_accounts',
        where: 'id = ? AND branch_id = ?',
        whereArgs: [accountId, branchId],
      );
      if (account.isEmpty) {
        throw StateError('Refund account belongs to another branch');
      }
      final balance = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS n FROM money_entries WHERE account_id = ?',
        [accountId],
      );
      if ((balance.single['n'] as int) < value) {
        throw StateError('Insufficient account balance for refund');
      }
      refundSum += value;
    }
    if (refundSum != amount) {
      throw ArgumentError(
        'Refund payments must equal the calculated return total of ${AppCurrency.input(amount)}.',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final returnId = await txn.insert('sale_returns', {
      'sale_id': saleId,
      'branch_id': branchId,
      'return_date': returnDate,
      'total': amount,
      'reason': reason.trim(),
      'employee_id': employeeId,
      'employee_name': staff.single['name'],
      'created_at': now,
    });
    for (final item in accepted) {
      final qty = item['return_qty'] as int;
      await ProductTracking.returnItems(
        txn,
        returnId,
        item['id'] as int,
        qty,
        trackedReturns[item['id']],
      );
      final count = await txn.rawUpdate(
        '''UPDATE branch_stocks SET stock = stock + ?
          WHERE branch_id = ? AND product_id = ? AND stock <= 9000000000000 - ?''',
        [qty, branchId, item['product_id'], qty],
      );
      if (count != 1) throw StateError('Could not restore stock');
      await txn.insert('sale_return_items', {
        'return_id': returnId,
        'sale_item_id': item['id'],
        'product_id': item['product_id'],
        'item_code': item['item_code'],
        'item_name': item['item_name'],
        'qty': qty,
        'refund_amount': item['refund'],
      });
      await txn.insert('stock_movements', {
        'branch_id': branchId,
        'product_id': item['product_id'],
        'quantity': qty,
        'kind': 'in',
        'note': 'Sale Return RET-${returnId.toString().padLeft(6, '0')}',
        'created_at': now,
        'sale_return_id': returnId,
      });
    }
    for (final p in refunds) {
      await txn.insert('sale_return_refunds', {
        'return_id': returnId,
        'account_id': p['account_id'],
        'amount': p['amount'],
      });
      await txn.insert('money_entries', {
        'account_id': p['account_id'],
        'kind': 'payment',
        'amount': -(p['amount'] as int),
        'entry_date': returnDate,
        'note': 'Sale Return RET-${returnId.toString().padLeft(6, '0')}',
        'created_at': now,
        'sale_return_id': returnId,
      });
    }
    return returnId;
  }

  Future<void> _reverseSaleReturn(
    Transaction txn,
    int id,
    String reason,
  ) async {
    final rows = await txn.query(
      'sale_returns',
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
    if (rows.length != 1) throw StateError('Return already void or missing');
    final old = rows.single;
    final branch = old['branch_id'] as int;
    final items = await txn.query(
      'sale_return_items',
      where: 'return_id = ?',
      whereArgs: [id],
    );
    final payments = await txn.query(
      'sale_return_refunds',
      where: 'return_id = ?',
      whereArgs: [id],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    for (final item in items) {
      final qty = item['qty'] as int;
      final count = await txn.rawUpdate(
        '''UPDATE branch_stocks SET stock = stock - ?
        WHERE branch_id = ? AND product_id = ? AND stock >= ?''',
        [qty, branch, item['product_id'], qty],
      );
      if (count != 1) {
        throw StateError(
          'Cannot reverse return: returned stock was already used',
        );
      }
      await txn.insert('stock_movements', {
        'branch_id': branch,
        'product_id': item['product_id'],
        'quantity': qty,
        'kind': 'sale',
        'note': 'Void RET-${id.toString().padLeft(6, '0')}: $reason',
        'created_at': now,
        'sale_return_id': id,
      });
    }
    for (final payment in payments) {
      final accountId = payment['account_id'] as int;
      final amount = payment['amount'] as int;
      final balance = await txn.rawQuery(
        '''SELECT COALESCE(SUM(amount),0) AS n
        FROM money_entries WHERE account_id = ?''',
        [accountId],
      );
      if ((balance.single['n'] as int) > 9000000000000 - amount) {
        throw StateError('Account balance limit exceeded');
      }
      await txn.insert('money_entries', {
        'account_id': accountId,
        'kind': 'adjustment',
        'amount': amount,
        'entry_date': AppDateTime.today().toIso8601String().substring(0, 10),
        'note': 'Void RET-${id.toString().padLeft(6, '0')}: $reason',
        'created_at': now,
        'sale_return_id': id,
      });
    }
    await ProductTracking.reverseReturn(txn, id);
    final changed = await txn.update(
      'sale_returns',
      {'status': 'void', 'void_reason': reason, 'voided_at': now},
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
    if (changed != 1) throw StateError('Return changed. Reload');
  }

  Future<void> voidSaleReturn({required int id, required String reason}) async {
    final clean = reason.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Void reason required (1–300 characters)');
    }
    final db = await database;
    await db.transaction((txn) => _reverseSaleReturn(txn, id, clean));
  }

  Future<int> replaceSaleReturn({
    required int id,
    required String returnDate,
    required String reason,
    required int employeeId,
    required Map<int, int> itemQuantities,
    required List<Map<String, int>> refunds,
    Map<int, String> trackedReturns = const {},
  }) async {
    await VoucherPermissions.requireEditable();
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'sale_returns',
        where: "id = ? AND status = 'posted'",
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Return changed. Reload');
      final saleId = rows.single['sale_id'] as int;
      await _reverseSaleReturn(txn, id, 'Corrected by replacement invoice');
      final replacement = await _postSaleReturn(
        txn,
        saleId: saleId,
        returnDate: returnDate,
        reason: reason,
        employeeId: employeeId,
        itemQuantities: itemQuantities,
        refunds: refunds,
        trackedReturns: trackedReturns,
      );
      await txn.update(
        'sale_returns',
        {'replacement_id': replacement},
        where: 'id = ?',
        whereArgs: [id],
      );
      return replacement;
    });
  }

  Future<List<Map<String, Object?>>> getConfirmedSales({
    required int branchId,
  }) async {
    final db = await database;
    return db.query(
      'sale_invoices',
      where: 'branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'id DESC',
    );
  }

  Future<void> voidSaleInvoice({
    required int id,
    required String reason,
  }) async {
    final clean = reason.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Void reason required');
    }
    final db = await database;
    await db.transaction((txn) => _voidSaleInvoice(txn, id, clean));
  }

  Future<void> _voidSaleInvoice(Transaction txn, int id, String clean) async {
    final liveSaleOrigin = LiveSaleSync.origin;
    final rows = await txn.query(
      'sale_invoices',
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('Sale already void or missing');
    final sale = rows.single;
    final returns = await txn.rawQuery(
      "SELECT id FROM sale_returns WHERE sale_id = ? AND status = 'posted' LIMIT 1",
      [id],
    );
    if (returns.isNotEmpty) throw StateError('Void linked Sale Returns first');
    final receipts = await txn.rawQuery(
      '''SELECT r.id FROM receipt_allocations a
        JOIN customer_receipts r ON r.id = a.receipt_id
        WHERE a.sale_id = ? AND r.status = 'posted' LIMIT 1''',
      [id],
    );
    if (receipts.isNotEmpty) {
      throw StateError('Void linked customer payments first');
    }
    final branch = sale['branch_id'] as int;
    final items = await txn.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [id],
    );
    final payments = await txn.query(
      'sale_payments',
      where: 'sale_id = ?',
      whereArgs: [id],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final day = AppDateTime.today().toIso8601String().substring(0, 10);
    for (final item in items) {
      final qty = item['qty'] as int;
      final count = await txn.rawUpdate(
        '''UPDATE branch_stocks SET stock = stock + ?
          WHERE branch_id = ? AND product_id = ? AND stock <= ?''',
        [qty, branch, item['product_id'], 2147483647 - qty],
      );
      if (count != 1) throw StateError('Stock capacity exceeded');
      await txn.insert('stock_movements', {
        'branch_id': branch,
        'product_id': item['product_id'],
        'quantity': qty,
        'kind': 'in',
        'note': 'Void sale INV-$id: $clean',
        'created_at': now,
        'sale_id': id,
      });
    }
    for (final p in payments) {
      final account = p['account_id'] as int;
      final amount = p['amount'] as int;
      final balance = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS n FROM money_entries WHERE account_id = ?',
        [account],
      );
      if ((balance.single['n'] as int) < amount) {
        throw StateError(
          'Insufficient account balance to reverse sale payment',
        );
      }
      await txn.insert('money_entries', {
        'account_id': account,
        'kind': 'adjustment',
        'amount': -amount,
        'entry_date': day,
        'note': 'Void sale INV-$id: $clean',
        'created_at': now,
        'sale_id': id,
      });
    }
    await ProductTracking.reverseSale(txn, id);
    final updated = await txn.update(
      'sale_invoices',
      {'status': 'void', 'void_reason': clean, 'voided_at': now},
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
    if (updated != 1) throw StateError('Sale changed. Reload');
    await LiveSaleSync.record(
      txn,
      origin: liveSaleOrigin,
      draftId: rows.single['draft_id'] as int,
      saleId: id,
    );
  }

  Future<int> createSaleCorrectionDraft({
    required int id,
    String reason = 'Edited using voucher unlock',
  }) async {
    await VoucherPermissions.requireEditable();
    final clean = reason.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Correction reason required');
    }
    final db = await database;
    return db.transaction((txn) async {
      final sale = await txn.query(
        'sale_invoices',
        where: "id = ? AND status = 'posted'",
        whereArgs: [id],
      );
      if (sale.isEmpty) throw StateError('Sale already void or missing');
      final source = sale.single;
      final existing = await txn.rawQuery(
        '''SELECT d.id FROM sale_drafts d
           WHERE d.correction_source_sale_id = ?
             AND NOT EXISTS (SELECT 1 FROM sale_invoices i WHERE i.draft_id = d.id)
             AND NOT EXISTS (
               SELECT 1 FROM app_settings s WHERE s.key = 'sale_edit_done:' || d.id
             )
           ORDER BY d.id DESC LIMIT 1''',
        [id],
      );
      if (existing.isNotEmpty) return existing.single['id'] as int;
      final original = (await txn.query(
        'sale_drafts',
        where: 'id = ?',
        whereArgs: [source['draft_id']],
      )).single;

      final originalPayments = await txn.query(
        'sale_payments',
        where: 'sale_id=?',
        whereArgs: [id],
      );
      final now = DateTime.now().toUtc().toIso8601String();
      final draft = await txn.insert('sale_drafts', {
        'branch_id': source['branch_id'],
        'customer_id': source['customer_id'],
        'customer_name': source['customer_name'],
        'customer_phone': source['customer_phone'],
        'customer_company': source['customer_company'],
        'customer_address': source['customer_address'],
        'employee_id': source['employee_id'],
        'employee_name': source['employee_name'],
        'invoice_date': source['invoice_date'],
        'discount_type': original['discount_type'],
        'discount_value': original['discount_value'],
        'subtotal': source['subtotal'],
        'discount_amount': source['discount_amount'],
        'voucher_discount_amount': source['voucher_discount_amount'],
        'remark': source['remark'],
        'total': source['total'],
        'currency_code': source['currency_code'],
        'currency_digits': source['currency_digits'],
        'correction_source_sale_id': id,
        'desktop_payment_json': jsonEncode({
          'text': AppCurrency.input(
            originalPayments.fold<int>(
              0,
              (sum, p) => sum + (p['amount'] as int),
            ),
          ),
          'account_id': originalPayments.firstOrNull?['account_id'],
          'date':
              originalPayments.firstOrNull?['payment_date'] ??
              source['invoice_date'],
          'splits': [
            for (final p in originalPayments)
              {'account_id': p['account_id'], 'amount': p['amount']},
          ],
        }),
        'created_at': now,
        'updated_at': now,
      });
      final items = await txn.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [id],
      );
      for (final item in items) {
        await txn.insert('sale_draft_items', {
          'draft_id': draft,
          'product_id': item['product_id'],
          'item_code': item['item_code'],
          'item_name': item['item_name'],
          'price': item['price'],
          'qty': item['qty'],
          'amount': item['amount'],
          'item_discount': item['item_discount'],
          'color_snapshot': item['color_snapshot'],
          'size_snapshot': item['size_snapshot'],
          'tracking_json': item['tracking_json'],
        });
      }
      return draft;
    });
  }

  Future<Map<String, Object?>> getConfirmedSale(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''SELECT s.*, b.name AS branch_name, b.code AS branch_code
        FROM sale_invoices s JOIN branches b ON b.id = s.branch_id WHERE s.id = ?''',
        [id],
      );
      if (rows.isEmpty) throw StateError('Sale not found');
      final items = await txn.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [id],
        orderBy: 'id',
      );
      final payments = await txn.rawQuery(
        '''
        SELECT p.*, a.name AS account_name, a.type AS account_type FROM sale_payments p
        JOIN money_accounts a ON a.id = p.account_id WHERE p.sale_id = ? ORDER BY p.id
      ''',
        [id],
      );
      final collections = await txn.rawQuery(
        '''
        SELECT r.id AS receipt_id, r.payment_date, r.status, r.created_at AS received_at, r.voided_at, a.amount
        FROM receipt_allocations a JOIN customer_receipts r ON r.id = a.receipt_id
        WHERE a.sale_id = ? ORDER BY r.payment_date, r.id
      ''',
        [id],
      );
      return {
        ...rows.single,
        'items': items,
        'payments': payments,
        'collections': collections,
      };
    });
  }

  Future<Map<String, Object?>> _preparePostedSaleEdit(
    Transaction txn, {
    required int saleId,
    required int draftId,
  }) async {
    final invoices = await txn.query(
      'sale_invoices',
      where: "id = ? AND status = 'posted'",
      whereArgs: [saleId],
    );
    if (invoices.isEmpty) {
      throw StateError('Invoice is no longer posted.');
    }
    final branchId = invoices.single['branch_id'] as int;
    final allocated = await txn.rawQuery(
      """SELECT COALESCE(SUM(a.amount), 0) AS amount
      FROM receipt_allocations a JOIN customer_receipts r ON r.id = a.receipt_id
      WHERE a.sale_id = ? AND r.status = 'posted'""",
      [saleId],
    );
    await _archiveVoidedReturnLines(txn, saleId);
    final returned = await txn.rawQuery(
      """SELECT DISTINCT i.sale_item_id FROM sale_return_items i
      JOIN sale_returns r ON r.id = i.return_id WHERE r.sale_id = ?""",
      [saleId],
    );
    final retainedIds = returned.map((r) => r['sale_item_id'] as int).toSet();
    final activeReturns = await txn.query(
      'sale_returns',
      where: "sale_id = ? AND status = 'posted'",
      whereArgs: [saleId],
    );
    final items = await txn.query(
      'sale_items',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'id',
    );
    final retained = items.where((i) => retainedIds.contains(i['id'])).toList();
    for (final item in items) {
      if (retainedIds.contains(item['id'])) continue;
      final qty = item['qty'] as int;
      final count = await txn.rawUpdate(
        '''UPDATE branch_stocks SET stock = stock + ?
           WHERE branch_id = ? AND product_id = ? AND stock <= ?''',
        [qty, branchId, item['product_id'], 2147483647 - qty],
      );
      if (count != 1) throw StateError('Stock capacity exceeded');
    }
    final payments = await txn.query(
      'sale_payments',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
    await txn.insert('app_settings', {
      'key': 'sale_edit_archive:$saleId:$draftId',
      'value': jsonEncode({
        'invoice': invoices.single,
        'items': items,
        'payments': payments,
        'edited_at': DateTime.now().toUtc().toIso8601String(),
      }),
    });
    await ProductTracking.reverseSale(txn, saleId, excluding: retainedIds);
    for (final item in items) {
      if (retainedIds.contains(item['id'])) continue;
      await txn.delete(
        'sale_lot_allocations',
        where: 'sale_item_id = ?',
        whereArgs: [item['id']],
      );
      await txn.delete('sale_items', where: 'id = ?', whereArgs: [item['id']]);
    }
    await txn.delete(
      'sale_payments',
      where: 'sale_id = ?',
      whereArgs: [saleId],
    );
    await txn.delete(
      'stock_movements',
      where: "sale_id = ? AND kind = 'sale' AND product_id NOT IN (SELECT product_id FROM sale_items WHERE sale_id = ?)",
      whereArgs: [saleId, saleId],
    );
    await txn.delete(
      'money_entries',
      where: "sale_id = ? AND kind = 'receipt'",
      whereArgs: [saleId],
    );
    return {
      ...invoices.single,
      'edit_original_items': items,
      'edit_retained': retained,
      'edit_returns': activeReturns,
      'edit_allocated': allocated.single['amount'] as int,
      'edit_accounts': payments.map((p) => p['account_id'] as int).toList(),
    };
  }

  /// Returns the exact posted records that can be corrected with this sale.
  Future<Map<String, List<Map<String, Object?>>>> saleEditLinks(
    int saleId,
  ) async {
    final db = await database;
    return db.transaction((txn) => _saleEditLinks(txn, saleId));
  }

  Future<Map<String, List<Map<String, Object?>>>> _saleEditLinks(
    Transaction txn,
    int saleId,
  ) async => {
    'returns': await txn.query(
      'sale_returns',
      columns: ['id', 'return_date', 'total'],
      where: "sale_id = ? AND status = 'posted'",
      whereArgs: [saleId],
      orderBy: 'id',
    ),
    'receipts': await txn.rawQuery(
      """SELECT r.id, r.payment_date, r.total, a.amount
         FROM receipt_allocations a JOIN customer_receipts r ON r.id = a.receipt_id
         WHERE a.sale_id = ? AND r.status = 'posted' ORDER BY r.id""",
      [saleId],
    ),
    'exchanges': await txn.rawQuery(
      """SELECT x.return_id AS id, x.replacement_sale_id FROM sale_exchange_links x
         JOIN sale_returns r ON r.id = x.return_id
         WHERE r.sale_id = ? OR x.replacement_sale_id = ?
         ORDER BY x.return_id""",
      [saleId, saleId],
    ),
  };

  Future<void> _reviseSaleReceipt(
    Transaction txn,
    int receiptId,
    int saleId,
    int amount,
    Map<int, int> payments,
    int draftId,
  ) async {
    final receipt = (await txn.query(
      'customer_receipts',
      where: "id = ? AND status = 'posted'",
      whereArgs: [receiptId],
    )).single;
    final allocations = await txn.query(
      'receipt_allocations',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    final oldPayments = await txn.query(
      'receipt_payments',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    final other = allocations
        .where((a) => a['sale_id'] != saleId)
        .fold<int>(0, (sum, a) => sum + (a['amount'] as int));
    final total = other + amount;
    if (amount < 0 ||
        total <= 0 ||
        total > 9000000000000 ||
        payments.values.any((value) => value < 0) ||
        payments.values.fold<int>(0, (sum, value) => sum + value) != total) {
      throw StateError(
        'Receipt payments must match the revised allocation plus the allocations on other invoices. Use Reverse for a receipt that should be zero.',
      );
    }
    await txn.insert('app_settings', {
      'key': 'sale_edit_receipt:$receiptId:$draftId',
      'value': jsonEncode({
        'receipt': receipt,
        'allocations': allocations,
        'payments': oldPayments,
      }),
    });
    await txn.delete(
      'receipt_allocations',
      where: 'receipt_id = ? AND sale_id = ?',
      whereArgs: [receiptId, saleId],
    );
    if (amount > 0) {
      await txn.insert('receipt_allocations', {
        'receipt_id': receiptId,
        'sale_id': saleId,
        'amount': amount,
      });
    }
    await txn.update(
      'customer_receipts',
      {'total': total},
      where: 'id = ?',
      whereArgs: [receiptId],
    );
    await txn.delete(
      'receipt_payments',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    await txn.delete(
      'money_entries',
      where: "customer_receipt_id = ? AND kind = 'receipt'",
      whereArgs: [receiptId],
    );
    for (final entry in payments.entries) {
      if (entry.value == 0) continue;
      final accounts = await txn.query(
        'money_accounts',
        where: 'id = ? AND branch_id = ?',
        whereArgs: [entry.key, receipt['branch_id']],
      );
      if (accounts.isEmpty) {
        throw StateError('Choose a receipt account from its branch.');
      }
      await txn.insert('receipt_payments', {
        'receipt_id': receiptId,
        'account_id': entry.key,
        'amount': entry.value,
      });
      await txn.insert('money_entries', {
        'account_id': entry.key,
        'kind': 'receipt',
        'amount': entry.value,
        'entry_date': receipt['payment_date'],
        'note': 'Customer credit collection',
        'created_at': receipt['created_at'],
        'customer_receipt_id': receiptId,
      });
    }
    for (final account in {
      ...payments.keys,
      ...oldPayments.map((p) => p['account_id'] as int),
    }) {
      final balance =
          (await txn.rawQuery(
                'SELECT COALESCE(SUM(amount), 0) AS n FROM money_entries WHERE account_id = ?',
                [account],
              )).single['n']
              as int;
      if (balance < 0 || balance > 9000000000000) {
        throw StateError(
          'The revised receipt would put an account outside its allowed balance.',
        );
      }
    }
  }

  Future<void> _setEditedExchange(
    Transaction txn,
    int returnId,
    int saleId,
  ) async {
    final valid = await txn.rawQuery(
      """SELECT n.id FROM sale_returns r
         JOIN sale_invoices o ON o.id = r.sale_id
         JOIN sale_invoices n ON n.branch_id = r.branch_id
           AND n.customer_id IS o.customer_id AND n.customer_name = o.customer_name
         WHERE r.id = ? AND n.id = ? AND n.id != o.id
           AND r.status = 'posted' AND n.status = 'posted' AND n.invoice_date >= r.return_date
           AND NOT EXISTS (SELECT 1 FROM sale_exchange_links x WHERE x.replacement_sale_id = n.id)""",
      [returnId, saleId],
    );
    if (valid.isEmpty) {
      throw StateError(
        'Choose an unused posted replacement invoice for the same customer and branch on or after the return date.',
      );
    }
    await txn.insert('sale_exchange_links', {
      'return_id': returnId,
      'replacement_sale_id': saleId,
      'linked_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> _postLinkedReturnEdits(
    Transaction txn,
    int saleId,
    Map<
      int,
      ({Map<int, int> quantities, Map<int, int> refunds, Map<int, String> lots})
    >
    edits,
    Map<int, int> exchanges,
  ) async {
    final products = {
      for (final item in await txn.query(
        'sale_items',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      ))
        item['product_id'] as int: item['id'] as int,
    };
    final replacements = <int, int>{};
    for (final entry in edits.entries) {
      final id = entry.key;
      final edit = entry.value;
      final original = (await txn.query(
        'sale_returns',
        where: "id = ? AND sale_id = ? AND status = 'void'",
        whereArgs: [id, saleId],
      )).single;
      if (edit.quantities.keys.any(
        (product) => !products.containsKey(product),
      )) {
        throw StateError(
          'A corrected return can only include products on the revised invoice.',
        );
      }
      final revised = await _postSaleReturn(
        txn,
        saleId: saleId,
        returnDate: original['return_date'] as String,
        reason: original['reason'] as String,
        employeeId: original['employee_id'] as int,
        itemQuantities: edit.quantities.map(
          (product, qty) => MapEntry(products[product]!, qty),
        ),
        refunds: [
          for (final p in edit.refunds.entries)
            if (p.value != 0) {'account_id': p.key, 'amount': p.value},
        ],
        trackedReturns: edit.lots.map(
          (product, lots) => MapEntry(products[product]!, lots),
        ),
      );
      await txn.update(
        'sale_returns',
        {'replacement_id': revised},
        where: 'id = ?',
        whereArgs: [id],
      );
      replacements[id] = revised;
    }
    for (final entry in exchanges.entries) {
      if (entry.value > 0) {
        await _setEditedExchange(
          txn,
          replacements[entry.key] ?? entry.key,
          entry.value,
        );
      }
    }
  }

  Future<void> _applySaleEditResolutions(
    Transaction txn,
    int saleId,
    Map<String, Set<int>> resolutions,
  ) async {
    if (resolutions.values.every((ids) => ids.isEmpty)) return;
    final links = await _saleEditLinks(txn, saleId);
    for (final entry in resolutions.entries) {
      final valid = links[entry.key]?.map((r) => r['id'] as int).toSet();
      if (valid == null || !valid.containsAll(entry.value)) {
        throw StateError(
          'Linked records changed. Reopen the review before saving.',
        );
      }
    }
    const reason = 'Reversed during confirmed invoice correction';
    for (final id in resolutions['returns'] ?? const <int>{}) {
      await _reverseSaleReturn(txn, id, reason);
    }
    for (final id in resolutions['receipts'] ?? const <int>{}) {
      await _voidCustomerReceipt(txn, id, reason);
    }
    final unlink = {...?resolutions['returns'], ...?resolutions['exchanges']};
    for (final id in unlink) {
      await txn.delete(
        'sale_exchange_links',
        where: 'return_id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _archiveVoidedReturnLines(Transaction txn, int saleId) async {
    final voided = await txn.query(
      'sale_returns',
      columns: ['id'],
      where: "sale_id = ? AND status = 'void'",
      whereArgs: [saleId],
    );
    for (final row in voided) {
      final id = row['id'] as int;
      final items = await txn.query(
        'sale_return_items',
        where: 'return_id = ?',
        whereArgs: [id],
        orderBy: 'sale_item_id',
      );
      if (items.isEmpty) continue;
      final lots = await _saleReturnLots(txn, id);
      await txn.insert('app_settings', {
        'key': 'sale_edit_void_return:$id',
        'value': jsonEncode({'items': items, 'lots': lots}),
      });
      await txn.delete(
        'return_lot_allocations',
        where: 'return_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'sale_return_items',
        where: 'return_id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<int> confirmSaleDraft({
    required int draftId,
    required int revision,
    required String paymentDate,
    required List<Map<String, int>> payments,
    int? customerIdOverride,
    bool saveNewCustomer = false,
    Map<String, Set<int>> linkedResolutions = const {},
    Map<int, ({int amount, Map<int, int> payments})> linkedReceiptEdits =
        const {},
    Map<
          int,
          ({
            Map<int, int> quantities,
            Map<int, int> refunds,
            Map<int, String> lots,
          })
        >
        linkedReturnEdits =
        const {},
    Map<int, int> linkedExchangeEdits = const {},
  }) async {
    final date = DateTime.tryParse(paymentDate);
    if (date == null ||
        paymentDate.length != 10 ||
        date.toIso8601String().substring(0, 10) != paymentDate) {
      throw ArgumentError('Invalid payment date');
    }
    final db = await database;
    final pending = await db.query(
      'sale_drafts',
      columns: ['correction_source_sale_id'],
      where: 'id=?',
      whereArgs: [draftId],
    );
    if (pending.isNotEmpty &&
        pending.single['correction_source_sale_id'] != null) {
      await VoucherPermissions.requireEditable();
    }
    final liveSaleOrigin = LiveSaleSync.origin;
    final result = await db.transaction((txn) async {
      // The draft is the idempotency key: a retry never posts stock or money twice.
      final posted = await txn.query(
        'sale_invoices',
        where: 'draft_id = ?',
        whereArgs: [draftId],
      );
      if (posted.isNotEmpty) return posted.single['id'] as int;
      final completedEdit = await txn.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['sale_edit_done:$draftId'],
      );
      if (completedEdit.isNotEmpty) {
        final id = int.tryParse(completedEdit.single['value'] as String);
        if (id == null) {
          throw StateError('Invoice changed. Reopen it before editing.');
        }
        return id;
      }
      final rows = await txn.query(
        'sale_drafts',
        where: 'id = ? AND revision = ?',
        whereArgs: [draftId, revision],
      );
      if (rows.isEmpty) {
        throw StateError('Draft changed. Reopen it before confirming.');
      }
      final d = rows.single;
      final branchId = d['branch_id'] as int;
      final sourceId = d['correction_source_sale_id'] as int?;
      if (linkedResolutions.isNotEmpty) {
        if (sourceId == null) {
          throw StateError('Linked corrections require an existing invoice.');
        }
        await _applySaleEditResolutions(txn, sourceId, linkedResolutions);
      }
      if (linkedReceiptEdits.isNotEmpty ||
          linkedReturnEdits.isNotEmpty ||
          linkedExchangeEdits.isNotEmpty) {
        if (sourceId == null) {
          throw StateError('Linked corrections require an existing invoice.');
        }
        final valid = await _saleEditLinks(txn, sourceId);
        final receiptIds = valid['receipts']!.map((r) => r['id']).toSet();
        if (!receiptIds.containsAll(linkedReceiptEdits.keys) ||
            !(linkedResolutions['returns'] ?? const <int>{}).containsAll(
              linkedReturnEdits.keys,
            ) ||
            !{
              ...?linkedResolutions['returns'],
              ...?linkedResolutions['exchanges'],
            }.containsAll(linkedExchangeEdits.keys)) {
          throw StateError(
            'Linked records changed. Reopen the review before saving.',
          );
        }
        for (final e in linkedReceiptEdits.entries) {
          await _reviseSaleReceipt(
            txn,
            e.key,
            sourceId,
            e.value.amount,
            e.value.payments,
            draftId,
          );
        }
      }
      final source = sourceId == null
          ? null
          : await _preparePostedSaleEdit(
              txn,
              saleId: sourceId,
              draftId: draftId,
            );
      final staff = await txn.query(
        'employees',
        where: 'id = ? AND default_branch_id = ? AND active = 1',
        whereArgs: [d['employee_id'], branchId],
      );
      if (staff.isEmpty) {
        throw StateError(
          'Sale person is no longer active in this branch. Edit the draft.',
        );
      }
      final items = await txn.query(
        'sale_draft_items',
        where: 'draft_id = ?',
        whereArgs: [draftId],
      );
      if (items.isEmpty) throw StateError('Draft has no items.');
      final accounts = <int>{};
      int paid = 0;
      for (final p in payments) {
        final accountId = p['account_id'];
        final amount = p['amount'];
        if (accountId == null ||
            amount == null ||
            amount <= 0 ||
            amount > 9000000000000 ||
            !accounts.add(accountId)) {
          throw ArgumentError('Invalid or repeated payment account');
        }
        final account = await txn.query(
          'money_accounts',
          where: 'id = ? AND branch_id = ?',
          whereArgs: [accountId, branchId],
        );
        if (account.isEmpty) {
          throw StateError(
            'Choose a payment account belonging to this branch.',
          );
        }
        paid += amount;
        final balance = await txn.rawQuery(
          'SELECT COALESCE(SUM(amount), 0) AS balance FROM money_entries WHERE account_id = ?',
          [accountId],
        );
        if ((balance.single['balance'] as int) + amount > 9000000000000) {
          throw StateError('Account balance limit exceeded.');
        }
      }
      final total = d['total'] as int;
      if (paid > total) {
        throw ArgumentError(
          'Payment exceeds total. Enter net payment after change.',
        );
      }
      final allocated = source?['edit_allocated'] as int? ?? 0;
      final due = total - paid - allocated;
      if (due < 0) {
        throw StateError(
          'Payments already allocated exceed the revised invoice total. Correct the customer receipt allocation first.',
        );
      }
      int? customerId = customerIdOverride ?? d['customer_id'] as int?;
      final now = DateTime.now().toUtc().toIso8601String();
      if (due > 0 && customerId == null) {
        if (!saveNewCustomer || (d['customer_name'] as String).trim().isEmpty) {
          throw StateError('Credit sales require a saved customer.');
        }
        customerId = await txn.insert('contacts', {
          'kind': 'customer',
          'name': d['customer_name'],
          'phone': d['customer_phone'],
          'company': d['customer_company'],
          'address': d['customer_address'],
          'remark': '',
          'active': 1,
          'created_at': now,
          'updated_at': now,
        });
      }
      if (customerId != null) {
        final c = await txn.query(
          'contacts',
          where: 'id = ? AND kind = ?',
          whereArgs: [customerId, 'customer'],
        );
        if (c.isEmpty) throw StateError('Customer not found.');
      }
      final retained =
          source?['edit_retained'] as List<Map<String, Object?>>? ?? [];
      if (source != null) {
        final activeReturns =
            source['edit_returns'] as List<Map<String, Object?>>;
        if (allocated > 0 &&
            (source['branch_id'] != branchId ||
                source['customer_id'] != customerId)) {
          throw StateError(
            'Correct the linked customer receipt before changing its customer or branch.',
          );
        }
        if (activeReturns.isNotEmpty &&
            (due != 0 ||
                source['branch_id'] != branchId ||
                activeReturns.any(
                  (r) =>
                      (r['return_date'] as String).compareTo(
                        d['invoice_date'] as String,
                      ) <
                      0,
                ))) {
          throw StateError(
            'A retained return requires a fully paid invoice in the same branch, dated on or before the return.',
          );
        }
        final originalItems =
            source['edit_original_items'] as List<Map<String, Object?>>;
        final oldNets = SaleInvoiceDetails.lineNets(
          originalItems,
          source['total'] as int,
        );
        final retainedProducts = retained.map((r) => r['product_id']).toSet();
        final orderedItems = [
          for (final old in retained)
            ...items.where((i) => i['product_id'] == old['product_id']),
          ...items.where((i) => !retainedProducts.contains(i['product_id'])),
        ];
        final newNets = SaleInvoiceDetails.lineNets(orderedItems, total);
        for (final old in retained) {
          final target = orderedItems.indexWhere(
            (i) => i['product_id'] == old['product_id'],
          );
          final originalIndex = originalItems.indexWhere(
            (i) => i['id'] == old['id'],
          );
          if (target < 0 ||
              orderedItems[target]['qty'] != old['qty'] ||
              orderedItems[target]['tracking_json'] != old['tracking_json'] ||
              branchId != source['branch_id'] ||
              newNets[target] != oldNets[originalIndex]) {
            throw StateError(
              'This item is referenced by a return. Correct the return before changing its quantity, tracking or refund basis.',
            );
          }
        }
      }
      final business = (await txn.query(
        'business_profile',
        where: 'id = 1',
      )).single;
      final branch = (await txn.query(
        'branches',
        where: 'id = ?',
        whereArgs: [branchId],
      )).single;
      final invoiceValues = <String, Object?>{
        'draft_id': draftId,
        'branch_id': branchId,
        'business_name': business['name'],
        'branch_name_snapshot': branch['name'],
        'branch_code_snapshot': branch['code'],
        'branch_phone_snapshot': branch['phone'],
        'branch_address_snapshot': branch['address'],
        'currency_code': d['currency_code'],
        'currency_digits': d['currency_digits'],
        'customer_id': customerId,
        'customer_name': d['customer_name'],
        'customer_phone': d['customer_phone'],
        'customer_company': d['customer_company'],
        'customer_address': d['customer_address'],
        'employee_id': d['employee_id'],
        'employee_name': d['employee_name'],
        'invoice_date': d['invoice_date'],
        'subtotal': d['subtotal'],
        'discount_amount': d['discount_amount'],
        'voucher_discount_amount': d['voucher_discount_amount'],
        'remark': d['remark'],
        'total': total,
        'paid': paid + allocated,
        'balance_due': due,
        'confirmed_at': source?['confirmed_at'] ?? now,
      };
      final int saleId;
      if (source == null) {
        saleId = await txn.insert('sale_invoices', invoiceValues);
      } else {
        saleId = sourceId!;
        // Keep the original invoice identity and branch prefix for reprints.
        invoiceValues.remove('draft_id');
        invoiceValues['branch_code_snapshot'] = source['branch_code_snapshot'];
        final updated = await txn.update(
          'sale_invoices',
          invoiceValues,
          where: "id = ? AND status = 'posted'",
          whereArgs: [saleId],
        );
        if (updated != 1) throw StateError('Invoice changed. Reload.');
        await txn.update(
          'sale_drafts',
          {
            'discount_type': d['discount_type'],
            'discount_value': d['discount_value'],
          },
          where: 'id = ?',
          whereArgs: [source['draft_id']],
        );
      }
      for (final item in items) {
        final retainedItem = retained
            .where((r) => r['product_id'] == item['product_id'])
            .firstOrNull;
        if (retainedItem != null) {
          await txn.update(
            'sale_items',
            {
              'price': item['price'],
              'amount': item['amount'],
              'item_discount': item['item_discount'],
            },
            where: 'id = ?',
            whereArgs: [retainedItem['id']],
          );
          continue;
        }
        final count = await txn.rawUpdate(
          '''
          UPDATE branch_stocks SET stock = stock - ?
          WHERE branch_id = ? AND product_id = ? AND stock >= ?
        ''',
          [item['qty'], branchId, item['product_id'], item['qty']],
        );
        if (count != 1) {
          throw StateError('Insufficient stock: ${item['item_name']}.');
        }
        final saleItemId = await txn.insert('sale_items', {
          'sale_id': saleId,
          'product_id': item['product_id'],
          'item_code': item['item_code'],
          'item_name': item['item_name'],
          'price': item['price'],
          'qty': item['qty'],
          'amount': item['amount'],
          'item_discount': item['item_discount'],
          'color_snapshot': item['color_snapshot'],
          'size_snapshot': item['size_snapshot'],
        });
        final tracking = await ProductTracking.sell(
          txn,
          item['product_id'] as int,
          branchId,
          item['qty'] as int,
          item['tracking_json'],
          saleItemId,
          d['invoice_date'] as String,
        );
        await txn.update(
          'sale_items',
          {'tracking_json': tracking},
          where: 'id=?',
          whereArgs: [saleItemId],
        );
        await txn.insert('stock_movements', {
          'branch_id': branchId,
          'product_id': item['product_id'],
          'quantity': item['qty'],
          'kind': 'sale',
          'note': 'Sale INV-${saleId.toString().padLeft(6, '0')}',
          'created_at': now,
          'sale_id': saleId,
        });
      }
      for (final p in payments) {
        await txn.insert('sale_payments', {
          'sale_id': saleId,
          'account_id': p['account_id'],
          'amount': p['amount'],
          'payment_date': paymentDate,
          'created_at': now,
        });
        await txn.insert('money_entries', {
          'account_id': p['account_id'],
          'kind': 'receipt',
          'amount': p['amount'],
          'entry_date': paymentDate,
          'note': 'Sale invoice payment',
          'created_at': now,
          'sale_id': saleId,
        });
      }
      if (source != null) {
        await _postLinkedReturnEdits(
          txn,
          saleId,
          linkedReturnEdits,
          linkedExchangeEdits,
        );
        final brokenExchange = await txn.rawQuery(
          """SELECT x.return_id FROM sale_exchange_links x
          JOIN sale_returns r ON r.id = x.return_id
          JOIN sale_invoices o ON o.id = r.sale_id
          JOIN sale_invoices n ON n.id = x.replacement_sale_id
          WHERE (o.id = ? OR n.id = ?) AND NOT (
            n.branch_id = r.branch_id AND n.customer_id IS o.customer_id
            AND n.customer_name = o.customer_name AND n.invoice_date >= r.return_date
          )""",
          [saleId, saleId],
        );
        if (brokenExchange.isNotEmpty) {
          throw StateError(
            'Correct the exchange link before changing its customer, branch or date.',
          );
        }
        for (final accountId in source['edit_accounts'] as List<int>) {
          final balance = await txn.rawQuery(
            'SELECT COALESCE(SUM(amount), 0) AS n FROM money_entries WHERE account_id = ?',
            [accountId],
          );
          if ((balance.single['n'] as int) < 0) {
            throw StateError(
              'Insufficient account balance after invoice edit.',
            );
          }
        }
        // Mark all other open drafts for this invoice stale. They must never
        // overwrite an edit based on an older invoice snapshot.
        final drafts = await txn.query(
          'sale_drafts',
          columns: ['id'],
          where: 'correction_source_sale_id = ? AND NOT EXISTS (SELECT 1 FROM sale_invoices i WHERE i.draft_id = sale_drafts.id)',
          whereArgs: [saleId],
        );
        for (final row in drafts) {
          final other = row['id'] as int;
          await txn.insert('app_settings', {
            'key': 'sale_edit_done:$other',
            'value': other == draftId ? '$saleId' : 'stale',
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          await txn.delete(
            'sale_recovery',
            where: 'source_draft_id = ?',
            whereArgs: [other],
          );
          await txn.delete('sale_drafts', where: 'id = ?', whereArgs: [other]);
        }
      }
      await txn.delete(
        'sale_recovery',
        where: 'recovery_key = ?',
        whereArgs: ['draft:$draftId'],
      );
      await LiveSaleSync.record(
        txn,
        origin: liveSaleOrigin,
        draftId: source?['draft_id'] as int? ?? draftId,
        saleId: saleId,
      );
      return saleId;
    });
    LiveSaleSync.wake();
    return result;
  }

  Future<void> _createCustomerReceipts(Database db) async {
    await db.execute('''
      CREATE TABLE customer_receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_key TEXT NOT NULL UNIQUE,
        customer_id INTEGER NOT NULL REFERENCES contacts(id),
        customer_name TEXT NOT NULL,
        branch_id INTEGER NOT NULL REFERENCES branches(id),
        employee_id INTEGER NOT NULL REFERENCES employees(id),
        employee_name TEXT NOT NULL,
        payment_date TEXT NOT NULL,
        total INTEGER NOT NULL CHECK(total > 0 AND total <= 9000000000000),
        note TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'posted' CHECK(status IN ('posted', 'void')),
        void_reason TEXT NOT NULL DEFAULT '',
        voided_at TEXT,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE receipt_allocations (
        receipt_id INTEGER NOT NULL REFERENCES customer_receipts(id),
        sale_id INTEGER NOT NULL REFERENCES sale_invoices(id),
        amount INTEGER NOT NULL CHECK(amount > 0),
        PRIMARY KEY(receipt_id, sale_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE receipt_payments (
        receipt_id INTEGER NOT NULL REFERENCES customer_receipts(id),
        account_id INTEGER NOT NULL REFERENCES money_accounts(id),
        amount INTEGER NOT NULL CHECK(amount > 0),
        PRIMARY KEY(receipt_id, account_id)
      )
    ''');
    await db.execute(
      'ALTER TABLE money_entries ADD COLUMN customer_receipt_id INTEGER REFERENCES customer_receipts(id)',
    );
    await db.execute('''
      CREATE UNIQUE INDEX money_customer_receipt_account_kind
      ON money_entries(customer_receipt_id, account_id, kind)
      WHERE customer_receipt_id IS NOT NULL
    ''');
    await db.execute(
      'CREATE INDEX customer_receipts_branch_customer_date ON customer_receipts(branch_id, customer_id, payment_date)',
    );
  }

  Future<List<Map<String, Object?>>> getCustomerBalances({
    required int branchId,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''
      SELECT c.id, c.name, c.phone, c.company, c.active,
        COUNT(s.id) AS invoice_count, SUM(s.total) AS sales_total,
        SUM(s.paid) AS paid_total, SUM(s.balance_due) AS balance_due
      FROM contacts c JOIN sale_invoices s ON s.customer_id = c.id
      WHERE c.kind = 'customer' AND s.branch_id = ? AND s.status = 'posted'
      GROUP BY c.id ORDER BY balance_due DESC, c.name COLLATE NOCASE
    ''',
      [branchId],
    );
  }

  Future<Map<String, Object?>> getCustomerLedger({
    required int customerId,
    required int branchId,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final customers = await txn.query(
        'contacts',
        where: 'id = ? AND kind = ?',
        whereArgs: [customerId, 'customer'],
      );
      if (customers.isEmpty) throw StateError('Customer not found');
      final invoices = await txn.query(
        'sale_invoices',
        where: "customer_id = ? AND branch_id = ? AND status = 'posted'",
        whereArgs: [customerId, branchId],
        orderBy: 'invoice_date DESC, id DESC',
      );
      final receipts = await txn.query(
        'customer_receipts',
        where: 'customer_id = ? AND branch_id = ?',
        whereArgs: [customerId, branchId],
        orderBy: 'payment_date DESC, id DESC',
      );
      return {
        'customer': customers.single,
        'invoices': invoices,
        'receipts': receipts,
      };
    });
  }

  Future<Map<String, Object?>> getCustomerReceipt(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.rawQuery(
        '''
        SELECT r.*, b.name AS branch_name, b.code AS branch_code
        FROM customer_receipts r JOIN branches b ON b.id = r.branch_id WHERE r.id = ?
      ''',
        [id],
      );
      if (rows.isEmpty) throw StateError('Receipt not found');
      final allocations = await txn.query(
        'receipt_allocations',
        where: 'receipt_id = ?',
        whereArgs: [id],
        orderBy: 'sale_id',
      );
      final payments = await txn.rawQuery(
        '''
        SELECT p.*, a.name AS account_name FROM receipt_payments p
        JOIN money_accounts a ON a.id = p.account_id WHERE p.receipt_id = ? ORDER BY p.account_id
      ''',
        [id],
      );
      return {...rows.single, 'allocations': allocations, 'payments': payments};
    });
  }

  Future<int> receiveCustomerPayment({
    required String requestKey,
    required int customerId,
    required int branchId,
    required int employeeId,
    required String paymentDate,
    required String note,
    required List<Map<String, int>> allocations,
    required List<Map<String, int>> payments,
  }) async {
    final date = DateTime.tryParse(paymentDate);
    if (requestKey.isEmpty ||
        requestKey.length > 150 ||
        note.trim().length > 500 ||
        date == null ||
        paymentDate.length != 10 ||
        date.toIso8601String().substring(0, 10) != paymentDate ||
        allocations.isEmpty ||
        payments.isEmpty) {
      throw ArgumentError('Invalid receipt information');
    }
    if (requestKey.startsWith('rcpt-correction-')) {
      await VoucherPermissions.requireEditable();
    }
    final db = await database;
    return db.transaction((txn) async {
      final prior = await txn.query(
        'customer_receipts',
        where: 'request_key = ?',
        whereArgs: [requestKey],
      );
      if (prior.isNotEmpty) return prior.single['id'] as int;
      final editMatch = RegExp(r'^rcpt-correction-([0-9]+)-[0-9]+$')
          .firstMatch(requestKey);
      if (editMatch != null) {
        await _voidCustomerReceipt(
          txn,
          int.parse(editMatch[1]!),
          'Edited using voucher unlock',
        );
      }
      final customer = await txn.query(
        'contacts',
        where: 'id = ? AND kind = ?',
        whereArgs: [customerId, 'customer'],
      );
      final employee = await txn.query(
        'employees',
        where: 'id = ? AND default_branch_id = ? AND active = 1',
        whereArgs: [employeeId, branchId],
      );
      if (customer.isEmpty || employee.isEmpty) {
        throw StateError('Check customer and active receiving employee.');
      }
      int allocated = 0, received = 0;
      final invoiceIds = <int>{}, accountIds = <int>{};
      for (final a in allocations) {
        final saleId = a['sale_id'];
        final amount = a['amount'];
        if (saleId == null ||
            amount == null ||
            amount <= 0 ||
            amount > 9000000000000 ||
            !invoiceIds.add(saleId)) {
          throw ArgumentError('Invalid invoice allocation');
        }
        final rows = await txn.query(
          'sale_invoices',
          where: "id = ? AND customer_id = ? AND branch_id = ? AND status = 'posted'",
          whereArgs: [saleId, customerId, branchId],
        );
        if (rows.isEmpty || (rows.single['balance_due'] as int) < amount) {
          throw StateError(
            'Invoice balance changed or payment exceeds debt. Refresh the ledger.',
          );
        }
        allocated += amount;
      }
      for (final p in payments) {
        final accountId = p['account_id'];
        final amount = p['amount'];
        if (accountId == null ||
            amount == null ||
            amount <= 0 ||
            amount > 9000000000000 ||
            !accountIds.add(accountId)) {
          throw ArgumentError('Invalid receiving account');
        }
        final accounts = await txn.query(
          'money_accounts',
          where: 'id = ? AND branch_id = ?',
          whereArgs: [accountId, branchId],
        );
        if (accounts.isEmpty) {
          throw StateError('Receiving account must belong to this branch.');
        }
        final sum = await txn.rawQuery(
          'SELECT COALESCE(SUM(amount),0) AS balance FROM money_entries WHERE account_id = ?',
          [accountId],
        );
        if ((sum.single['balance'] as int) + amount > 9000000000000) {
          throw StateError('Account balance limit exceeded.');
        }
        received += amount;
      }
      if (allocated != received || allocated > 9000000000000) {
        throw ArgumentError(
          'Invoice allocations and received amounts must match',
        );
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final receiptId = await txn.insert('customer_receipts', {
        'request_key': requestKey,
        'customer_id': customerId,
        'customer_name': customer.single['name'],
        'branch_id': branchId,
        'employee_id': employeeId,
        'employee_name': employee.single['name'],
        'payment_date': paymentDate,
        'total': allocated,
        'note': note.trim(),
        'created_at': now,
      });
      for (final a in allocations) {
        final changed = await txn.rawUpdate(
          '''
          UPDATE sale_invoices SET paid = paid + ?, balance_due = balance_due - ?
          WHERE id = ? AND customer_id = ? AND branch_id = ? AND balance_due >= ?
        ''',
          [
            a['amount'],
            a['amount'],
            a['sale_id'],
            customerId,
            branchId,
            a['amount'],
          ],
        );
        if (changed != 1) {
          throw StateError('Invoice balance changed. Retry from ledger.');
        }
        await txn.insert('receipt_allocations', {
          'receipt_id': receiptId,
          'sale_id': a['sale_id'],
          'amount': a['amount'],
        });
      }
      for (final p in payments) {
        await txn.insert('receipt_payments', {
          'receipt_id': receiptId,
          'account_id': p['account_id'],
          'amount': p['amount'],
        });
        // Do not attach sale_id: one collection may settle several invoices.
        await txn.insert('money_entries', {
          'account_id': p['account_id'],
          'kind': 'receipt',
          'amount': p['amount'],
          'entry_date': paymentDate,
          'note': 'Customer credit collection',
          'created_at': now,
          'customer_receipt_id': receiptId,
        });
      }
      final correction = RegExp(r'^rcpt-correction-([0-9]+)-[0-9]+$')
          .firstMatch(requestKey);
      if (correction != null) {
        await txn.update(
          'customer_receipts',
          {'replacement_id': receiptId},
          where: "id = ? AND status = 'void' AND replacement_id IS NULL",
          whereArgs: [int.parse(correction[1]!)],
        );
      }
      await txn.delete(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['receipt_work:$branchId:$customerId'],
      );
      return receiptId;
    });
  }

  Future<void> voidCustomerReceipt({
    required int receiptId,
    required String reason,
  }) async {
    if (reason.trim().isEmpty || reason.trim().length > 500) {
      throw ArgumentError('A cancellation reason is required');
    }
    final db = await database;
    await db.transaction(
      (txn) => _voidCustomerReceipt(txn, receiptId, reason.trim()),
    );
  }

  Future<void> _voidCustomerReceipt(
    Transaction txn,
    int receiptId,
    String reason,
  ) async {
    final rows = await txn.query(
      'customer_receipts',
      where: 'id = ?',
      whereArgs: [receiptId],
    );
    if (rows.isEmpty) throw StateError('Receipt not found');
    if (rows.single['status'] == 'void') return;
    final allocations = await txn.query(
      'receipt_allocations',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    for (final a in allocations) {
      final linkedReturn = await txn.query(
        'sale_returns',
        columns: ['id'],
        where: "sale_id = ? AND status = 'posted'",
        whereArgs: [a['sale_id']],
        limit: 1,
      );
      if (linkedReturn.isNotEmpty) {
        throw StateError('Void linked Sale Returns first');
      }
      final changed = await txn.rawUpdate(
        '''
          UPDATE sale_invoices SET paid = paid - ?, balance_due = balance_due + ? WHERE id = ? AND paid >= ?
        ''',
        [a['amount'], a['amount'], a['sale_id'], a['amount']],
      );
      if (changed != 1) {
        throw StateError('Invoice balances do not match this receipt.');
      }
    }
    final payments = await txn.query(
      'receipt_payments',
      where: 'receipt_id = ?',
      whereArgs: [receiptId],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final today = AppDateTime.today();
    final entryDate =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    for (final p in payments) {
      final sum = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS balance FROM money_entries WHERE account_id = ?',
        [p['account_id']],
      );
      if ((sum.single['balance'] as int) < (p['amount'] as int)) {
        throw StateError(
          'Insufficient account balance to reverse customer payment.',
        );
      }
      await txn.insert('money_entries', {
        'account_id': p['account_id'],
        'kind': 'adjustment',
        'amount': -(p['amount'] as int),
        'entry_date': entryDate,
        'note': 'Void customer receipt: ${reason.trim()}',
        'created_at': now,
        'customer_receipt_id': receiptId,
      });
    }
    await txn.update(
      'customer_receipts',
      {'status': 'void', 'void_reason': reason.trim(), 'voided_at': now},
      where: 'id = ?',
      whereArgs: [receiptId],
    );
  }

  Future<void> createCustomerReceiptCorrectionWork({
    required int id,
    String reason = 'Edited using voucher unlock',
  }) async {
    await VoucherPermissions.requireEditable();
    final clean = reason.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Correction reason required');
    }
    final db = await database;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'customer_receipts',
        where: "id = ? AND status = 'posted'",
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Receipt already void or missing');
      final receipt = rows.single;
      final branch = receipt['branch_id'] as int,
          customer = receipt['customer_id'] as int;
      final workKey = 'receipt_work:$branch:$customer';
      if ((await txn.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: [workKey],
      )).isNotEmpty) {
        throw StateError(
          'Finish or discard the current unfinished customer receipt first',
        );
      }
      final allocations = await txn.query(
        'receipt_allocations',
        where: 'receipt_id = ?',
        whereArgs: [id],
      );
      final payments = await txn.query(
        'receipt_payments',
        where: 'receipt_id = ?',
        whereArgs: [id],
      );

      final now = DateTime.now().toUtc().microsecondsSinceEpoch;
      final work = <String, Object?>{
        'request_key': 'rcpt-correction-$id-$now',
        'date': receipt['payment_date'],
        'employee_id': receipt['employee_id'],
        'note': receipt['note'],
        'allocation': {
          for (final a in allocations)
            (a['sale_id'] as int).toString(): AppCurrency.input(
              a['amount'] as int,
            ),
        },
        'payment': {
          for (final p in payments)
            (p['account_id'] as int).toString(): AppCurrency.input(
              p['amount'] as int,
            ),
        },
      };
      await txn.insert('app_settings', {
        'key': workKey,
        'value': jsonEncode(work),
      });
    });
  }

  Future<String?> getReceiptWork({
    required int branchId,
    required int customerId,
  }) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['receipt_work:$branchId:$customerId'],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> putReceiptWork({
    required int branchId,
    required int customerId,
    required String payload,
  }) async {
    if (payload.length > 2000000) {
      throw ArgumentError('Receipt draft too large');
    }
    final db = await database;
    await db.insert('app_settings', {
      'key': 'receipt_work:$branchId:$customerId',
      'value': payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteReceiptWork({
    required int branchId,
    required int customerId,
  }) async {
    final db = await database;
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['receipt_work:$branchId:$customerId'],
    );
  }

  Future<void> _createBusinessProfile(Database db) async {
    await db.execute('''CREATE TABLE business_profile (
      id INTEGER PRIMARY KEY CHECK(id = 1),
      name TEXT NOT NULL DEFAULT '',
      country_code TEXT NOT NULL DEFAULT '',
      currency_code TEXT NOT NULL DEFAULT 'MMK' CHECK(currency_code IN ('MMK','USD','THB','CNY','JPY')),
      currency_digits INTEGER NOT NULL DEFAULT 0,
      configured INTEGER NOT NULL DEFAULT 0 CHECK(configured IN (0,1)),
      CHECK((currency_code IN ('MMK','JPY') AND currency_digits = 0)
         OR (currency_code IN ('USD','THB','CNY') AND currency_digits = 2))
    )''');
    await db.execute("INSERT INTO business_profile(id) VALUES(1)");
    await db.execute(
      "ALTER TABLE sale_drafts ADD COLUMN currency_code TEXT NOT NULL DEFAULT 'MMK'",
    );
    await db.execute(
      "ALTER TABLE sale_drafts ADD COLUMN currency_digits INTEGER NOT NULL DEFAULT 0",
    );
    await db.execute(
      "ALTER TABLE sale_invoices ADD COLUMN currency_code TEXT NOT NULL DEFAULT 'MMK'",
    );
    await db.execute(
      "ALTER TABLE sale_invoices ADD COLUMN currency_digits INTEGER NOT NULL DEFAULT 0",
    );
  }

  Future<bool> _currencyLocked(DatabaseExecutor db) async {
    // Even zero-valued catalog/account rows and unfinished text input have units.
    // Never reinterpret them just by changing a setting.
    final rows = await db.rawQuery(
      '''SELECT
      EXISTS(SELECT 1 FROM products) OR EXISTS(SELECT 1 FROM money_accounts)
      OR EXISTS(SELECT 1 FROM money_entries) OR EXISTS(SELECT 1 FROM sale_drafts)
      OR EXISTS(SELECT 1 FROM sale_invoices) OR EXISTS(SELECT 1 FROM sale_recovery)
      OR EXISTS(SELECT 1 FROM customer_receipts)
      OR EXISTS(SELECT 1 FROM app_settings WHERE key LIKE 'receipt_work:%') AS locked''',
    );
    return rows.single['locked'] == 1;
  }

  Future<Map<String, Object?>> getBusinessProfile() async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('business_profile', where: 'id = 1');
      final profile = rows.single;
      final zoneRows = await txn.query(
        'app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['business_timezone'],
      );
      final country = profile['country_code'] as String;
      final candidate = zoneRows.isEmpty
          ? null
          : zoneRows.single['value'] as String;
      final zone = businessTimeZones[country]?.contains(candidate) == true
          ? candidate!
          : defaultBusinessTimeZone(country);
      return {
        ...profile,
        'timezone_id': zone,
        'currency_locked': await _currencyLocked(txn),
      };
    });
  }

  Future<Map<String, Object?>> saveBusinessProfile({
    required String name,
    required String countryCode,
    required String currencyCode,
    String? timezoneId,
  }) async {
    if (name.trim().isEmpty ||
        name.trim().length > 150 ||
        !businessCountries.containsKey(countryCode) ||
        !AppCurrency.precision.containsKey(currencyCode) ||
        (timezoneId != null &&
            !(businessTimeZones[countryCode]?.contains(timezoneId) ?? false))) {
      throw ArgumentError(
        'Choose a business name, country and supported currency.',
      );
    }
    final db = await database;
    return db.transaction((txn) async {
      final old = (await txn.query('business_profile', where: 'id = 1')).single;
      final locked = await _currencyLocked(txn);
      if (old['currency_code'] != currencyCode && locked) {
        throw StateError(
          'Currency is locked because product, account or invoice data already exists.',
        );
      }
      final values = <String, Object?>{
        'name': name.trim(),
        'country_code': countryCode,
        'currency_code': currencyCode,
        'currency_digits': AppCurrency.precision[currencyCode],
        'configured': 1,
      };
      await txn.update('business_profile', values, where: 'id = 1');
      final zone = timezoneId ?? defaultBusinessTimeZone(countryCode);
      await txn.insert('app_settings', {
        'key': 'business_timezone',
        'value': zone,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return {
        ...values,
        'id': 1,
        'timezone_id': zone,
        'currency_locked': locked,
      };
    });
  }

  Future<void> _createProductBarcodes(Database db) async {
    await db.execute('ALTER TABLE products ADD COLUMN barcode TEXT');
    await db.execute(
      "UPDATE products SET barcode = 'ITEM-' || printf('%06d', id)",
    );
    await db.execute('''CREATE UNIQUE INDEX product_barcode_unique ON products(
      CASE WHEN length(barcode) = 13 AND substr(barcode, 1, 1) = '0'
        AND barcode NOT GLOB '*[^0-9]*' THEN substr(barcode, 2) ELSE barcode END
    ) WHERE barcode IS NOT NULL''');
  }

  Future<void> _createProductImages(Database db) async {
    await db.execute('''CREATE TABLE product_images (
      product_id INTEGER PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
      image BLOB NOT NULL CHECK(length(image) BETWEEN 4 AND 750000)
    )''');
  }

  void _validateProductImage(Uint8List? bytes) {
    if (bytes == null) return;
    if (bytes.length < 4 ||
        bytes.length > 750000 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[bytes.length - 2] != 0xff ||
        bytes.last != 0xd9) {
      throw ArgumentError('Product photo must be a JPEG smaller than 750 KB');
    }
  }

  Future<Uint8List?> getProductImage(int productId) async {
    final db = await database;
    final rows = await db.query(
      'product_images',
      columns: ['image'],
      where: 'product_id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.single['image'] as Uint8List;
  }

  Future<void> _createCustomItemCodes(Database db) async {
    await db.execute('ALTER TABLE products ADD COLUMN item_code TEXT');
    await db.execute(
      "UPDATE products SET item_code = 'ITEM-' || printf('%06d', id)",
    );
    await db.execute('''CREATE UNIQUE INDEX product_item_code_unique
      ON products(item_code COLLATE NOCASE) WHERE item_code IS NOT NULL''');
  }

  Future<void> _createSupplierCredit(Database db) async {
    await db.execute(
      'ALTER TABLE purchase_invoices ADD COLUMN paid INTEGER NOT NULL DEFAULT 0 CHECK(paid >= 0)',
    );
    await db.execute(
      'ALTER TABLE purchase_invoices ADD COLUMN balance_due INTEGER NOT NULL DEFAULT 0 CHECK(balance_due >= 0)',
    );
    await db.execute('UPDATE purchase_invoices SET paid = total');
    await db.execute('''CREATE TABLE supplier_settlements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request_key TEXT NOT NULL UNIQUE,
      purchase_id INTEGER NOT NULL REFERENCES purchase_invoices(id),
      branch_id INTEGER NOT NULL REFERENCES branches(id),
      supplier_id INTEGER NOT NULL REFERENCES contacts(id),
      amount INTEGER NOT NULL CHECK(amount > 0),
      payment_date TEXT NOT NULL,
      created_at TEXT NOT NULL
    )''');
    await db.execute('''CREATE TABLE supplier_settlement_payments (
      settlement_id INTEGER NOT NULL REFERENCES supplier_settlements(id),
      account_id INTEGER NOT NULL REFERENCES money_accounts(id),
      account_name TEXT NOT NULL,
      amount INTEGER NOT NULL CHECK(amount > 0),
      PRIMARY KEY(settlement_id, account_id)
    )''');
    await db.execute(
      'ALTER TABLE money_entries ADD COLUMN supplier_settlement_id INTEGER REFERENCES supplier_settlements(id)',
    );
    await db.execute(
      '''CREATE UNIQUE INDEX money_supplier_settlement_account
      ON money_entries(supplier_settlement_id, account_id) WHERE supplier_settlement_id IS NOT NULL''',
    );
    await db.execute(
      'CREATE INDEX supplier_credit_branch ON purchase_invoices(branch_id, supplier_id, balance_due)',
    );
  }

  Future<void> _createPurchases(Database db) async {
    await db.execute('''CREATE TABLE product_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL COLLATE NOCASE UNIQUE CHECK(length(trim(name)) BETWEEN 1 AND 100),
      active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0, 1))
    )''');
    await db.execute(
      "INSERT INTO product_categories(name) VALUES ('Uncategorized')",
    );
    await db.execute(
      'ALTER TABLE products ADD COLUMN category_id INTEGER REFERENCES product_categories(id)',
    );
    await db.execute('UPDATE products SET category_id = 1');
    await db.execute('''CREATE TABLE purchase_invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request_key TEXT NOT NULL UNIQUE,
      branch_id INTEGER NOT NULL REFERENCES branches(id),
      supplier_id INTEGER NOT NULL REFERENCES contacts(id),
      supplier_name TEXT NOT NULL, supplier_phone TEXT NOT NULL,
      supplier_address TEXT NOT NULL,
      invoice_date TEXT NOT NULL, confirmed_at TEXT NOT NULL,
      total INTEGER NOT NULL CHECK(total > 0 AND total <= 9000000000000),
      currency_code TEXT NOT NULL, currency_digits INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE purchase_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      purchase_id INTEGER NOT NULL REFERENCES purchase_invoices(id),
      product_id INTEGER NOT NULL REFERENCES products(id),
      item_code TEXT NOT NULL, item_name TEXT NOT NULL,
      category_name TEXT NOT NULL,
      purchase_price INTEGER NOT NULL CHECK(purchase_price >= 0),
      sale_price INTEGER NOT NULL CHECK(sale_price >= 0),
      qty INTEGER NOT NULL CHECK(qty > 0),
      amount INTEGER NOT NULL CHECK(amount >= 0),
      UNIQUE(purchase_id, product_id)
    )''');
    await db.execute('''CREATE TABLE purchase_payments (
      purchase_id INTEGER NOT NULL REFERENCES purchase_invoices(id),
      account_id INTEGER NOT NULL REFERENCES money_accounts(id),
      account_name TEXT NOT NULL, amount INTEGER NOT NULL CHECK(amount > 0),
      payment_date TEXT NOT NULL, created_at TEXT NOT NULL,
      PRIMARY KEY(purchase_id, account_id)
    )''');
    await db.execute(
      'ALTER TABLE money_entries ADD COLUMN purchase_id INTEGER REFERENCES purchase_invoices(id)',
    );
    await db.execute(
      '''CREATE UNIQUE INDEX money_purchase_account_payment
      ON money_entries(purchase_id, account_id) WHERE purchase_id IS NOT NULL AND kind = 'payment' ''',
    );
    await db.execute(
      'ALTER TABLE stock_movements RENAME TO previous_purchase_movements',
    );
    await db.execute('DROP INDEX stock_movement_branch_product');
    await db.execute('''CREATE TABLE stock_movements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      branch_id INTEGER NOT NULL REFERENCES branches(id),
      product_id INTEGER NOT NULL REFERENCES products(id),
      quantity INTEGER NOT NULL CHECK(quantity > 0),
      kind TEXT NOT NULL CHECK(kind IN ('opening', 'in', 'sale', 'purchase')),
      note TEXT NOT NULL, created_at TEXT NOT NULL,
      sale_id INTEGER REFERENCES sale_invoices(id),
      purchase_id INTEGER REFERENCES purchase_invoices(id)
    )''');
    await db.execute('''INSERT INTO stock_movements
      (id, branch_id, product_id, quantity, kind, note, created_at, sale_id)
      SELECT id, branch_id, product_id, quantity, kind, note, created_at, sale_id
      FROM previous_purchase_movements''');
    await db.execute('DROP TABLE previous_purchase_movements');
    await db.execute(
      'CREATE INDEX stock_movement_branch_product ON stock_movements(branch_id, product_id, id)',
    );
    await db.execute(
      'CREATE INDEX purchase_branch_date ON purchase_invoices(branch_id, invoice_date, id)',
    );
  }

  Future<List<Map<String, Object?>>> getProductCategories({
    bool includeInactive = false,
  }) async {
    final db = await database;
    return db.query(
      'product_categories',
      where: includeInactive ? null : 'active = 1',
      orderBy: 'name COLLATE NOCASE, id',
    );
  }

  Future<void> saveProductCategory({int? id, required String name}) async {
    final db = await database;
    await db.transaction(
      (txn) => CategoryStore.save(txn, 'product', name, id: id),
    );
  }

  bool _businessDate(String value) {
    final date = DateTime.tryParse(value);
    return value.length == 10 &&
        date != null &&
        date.toIso8601String().substring(0, 10) == value;
  }

  /// Purchases are posted once, atomically: stock, product price, and account debits.
  Future<int> postPurchase({
    required String requestKey,
    required int branchId,
    required int supplierId,
    required String invoiceDate,
    required List<Map<String, Object?>> items,
    required List<Map<String, int>> payments,
  }) async {
    if (requestKey.trim().isEmpty ||
        requestKey.length > 100 ||
        !_businessDate(invoiceDate) ||
        items.isEmpty ||
        items.length > 300) {
      throw ArgumentError('Invalid purchase information');
    }
    if (requestKey.startsWith('purchase-correction-')) {
      await VoucherPermissions.requireEditable();
    }
    final db = await database;
    return db.transaction((txn) async {
      final previous = await txn.query(
        'purchase_invoices',
        columns: ['id'],
        where: 'request_key = ?',
        whereArgs: [requestKey],
      );
      if (previous.isNotEmpty) {
        await txn.delete(
          'app_settings',
          where: 'key = ? AND value LIKE ?',
          whereArgs: ['purchase_recovery', '%"request_key":"$requestKey"%'],
        );
        return previous.single['id'] as int;
      }
      final editMatch = RegExp(r'^purchase-correction-([0-9]+)-[0-9]+$')
          .firstMatch(requestKey);
      if (editMatch != null) {
        await _voidPurchaseInvoice(
          txn,
          int.parse(editMatch[1]!),
          'Edited using voucher unlock',
        );
      }
      if ((await txn.query(
        'branches',
        where: 'id = ?',
        whereArgs: [branchId],
      )).isEmpty) {
        throw StateError('Branch not found');
      }
      final supplier = await txn.query(
        'contacts',
        where: 'id = ? AND kind = ? AND active = 1',
        whereArgs: [supplierId, 'supplier'],
      );
      if (supplier.isEmpty) throw StateError('Choose an active supplier');
      final profile = (await txn.query(
        'business_profile',
        where: 'id = 1',
      )).single;
      var total = 0;
      final seenProducts = <int>{};
      for (final item in items) {
        final productId = item['product_id'] as int?;
        final name = (item['name'] as String? ?? '').trim();
        final categoryId = item['category_id'] as int?;
        final qty = item['qty'] as int?;
        final purchasePrice = item['purchase_price'] as int?;
        final salePrice = item['sale_price'] as int?;
        if ((productId == null && (name.isEmpty || name.length > 150)) ||
            categoryId == null ||
            qty == null ||
            qty <= 0 ||
            qty > 2147483647 ||
            purchasePrice == null ||
            purchasePrice < 0 ||
            purchasePrice > 2147483647 ||
            salePrice == null ||
            salePrice < 0 ||
            salePrice > 2147483647) {
          throw ArgumentError('Invalid purchase item');
        }
        if (productId != null && !seenProducts.add(productId)) {
          throw ArgumentError('Duplicate product');
        }
        if ((await txn.query(
          'product_categories',
          where: 'id = ? AND active = 1',
          whereArgs: [categoryId],
        )).isEmpty) {
          throw StateError('Category not found');
        }
        final amount = qty * purchasePrice;
        total += amount;
        if (total > 9000000000000) {
          throw ArgumentError('Purchase total exceeds limit');
        }
      }

      var paid = 0;
      final seenAccounts = <int>{};
      for (final payment in payments) {
        final accountId = payment['account_id'];
        final amount = payment['amount'];
        if (accountId == null ||
            amount == null ||
            amount <= 0 ||
            amount > 9000000000000 ||
            !seenAccounts.add(accountId)) {
          throw ArgumentError('Invalid split payment');
        }
        final account = await txn.rawQuery(
          '''SELECT a.id, COALESCE(SUM(e.amount), 0) AS balance
          FROM money_accounts a LEFT JOIN money_entries e ON e.account_id = a.id
          WHERE a.id = ? AND a.branch_id = ? GROUP BY a.id''',
          [accountId, branchId],
        );
        if (account.isEmpty || (account.single['balance'] as int) < amount) {
          throw StateError('Insufficient balance in a selected account');
        }
        paid += amount;
      }
      if (paid > total) throw ArgumentError('Payments exceed purchase total');
      final now = DateTime.now().toUtc().toIso8601String();
      final supplierRow = supplier.single;
      final purchaseId = await txn.insert('purchase_invoices', {
        'request_key': requestKey,
        'branch_id': branchId,
        'supplier_id': supplierId,
        'supplier_name': supplierRow['name'],
        'supplier_phone': supplierRow['phone'],
        'supplier_address': supplierRow['address'],
        'invoice_date': invoiceDate,
        'confirmed_at': now,
        'total': total,
        'paid': paid,
        'balance_due': total - paid,
        'currency_code': profile['currency_code'],
        'currency_digits': profile['currency_digits'],
      });
      for (final item in items) {
        final categoryId = item['category_id'] as int;
        final category = (await txn.query(
          'product_categories',
          where: 'id = ?',
          whereArgs: [categoryId],
        )).single;
        var productId = item['product_id'] as int?;
        if (productId == null) {
          productId = await txn.insert('products', {
            'name': (item['name'] as String).trim(),
            'price': item['sale_price'],
            'stock': 0,
            'category_id': categoryId,
            'brand_id': item['brand_id'],
            'color': item['color'] ?? '',
            'size': item['size'] ?? '',
            'tracking': item['tracking'] ?? 'none',
            'warranty_days': item['warranty_days'] ?? 0,
          });
          final code = BarcodeRules.forItemCode(
            item['item_code'] as String?,
            productId,
          );
          await txn.update(
            'products',
            {
              'item_code': code,
              'barcode': BarcodeRules.forProduct(
                item['barcode'] as String?,
                productId,
                itemCodeValue: code,
              ),
            },
            where: 'id = ?',
            whereArgs: [productId],
          );
        } else {
          await ProductTracking.validatePurchasePolicy(txn, productId, item);
          final count = await txn.update(
            'products',
            {
              'price': item['sale_price'],
              'category_id': categoryId,
              if (item['warranty_days'] != null)
                'warranty_days': item['warranty_days'],
              if (item.containsKey('brand_id')) 'brand_id': item['brand_id'],
            },
            where: 'id = ?',
            whereArgs: [productId],
          );
          if (count != 1) throw StateError('Product not found');
        }
        final product = (await txn.query(
          'products',
          where: 'id = ?',
          whereArgs: [productId],
        )).single;
        if (item['photo_base64'] is String) {
          final bytes = base64Decode(item['photo_base64'] as String);
          _validateProductImage(bytes);
          await txn.insert('product_images', {
            'product_id': productId,
            'image': bytes,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await ProductTracking.brand(
          txn,
          product['brand_id'] as int?,
          categoryId,
        );
        await ProductTracking.receive(
          txn,
          productId,
          branchId,
          purchaseId,
          item,
          replacingPurchaseId: editMatch == null
              ? null
              : int.parse(editMatch[1]!),
        );
        final qty = item['qty'] as int;
        await txn.rawInsert(
          'INSERT OR IGNORE INTO branch_stocks(branch_id, product_id, stock) VALUES (?, ?, 0)',
          [branchId, productId],
        );
        final stock = await txn.rawUpdate(
          '''UPDATE branch_stocks SET stock = stock + ?
          WHERE branch_id = ? AND product_id = ? AND stock <= ?''',
          [qty, branchId, productId, 2147483647 - qty],
        );
        if (stock != 1) throw StateError('Stock limit exceeded');
        await txn.insert('purchase_items', {
          'purchase_id': purchaseId,
          'product_id': productId,
          'item_code': product['item_code'],
          'item_name': product['name'],
          'category_name': category['name'],
          'tracking_json': jsonEncode(item['lots'] ?? []),
          'purchase_price': item['purchase_price'],
          'sale_price': item['sale_price'],
          'qty': qty,
          'amount': qty * (item['purchase_price'] as int),
        });
        await txn.insert('stock_movements', {
          'branch_id': branchId,
          'product_id': productId,
          'quantity': qty,
          'kind': 'purchase',
          'note': 'Purchase PUR-${purchaseId.toString().padLeft(6, '0')}',
          'created_at': now,
          'purchase_id': purchaseId,
        });
      }
      for (final payment in payments) {
        final accountId = payment['account_id']!;
        final amount = payment['amount']!;
        final account = (await txn.query(
          'money_accounts',
          where: 'id = ?',
          whereArgs: [accountId],
        )).single;
        await txn.insert('purchase_payments', {
          'purchase_id': purchaseId,
          'account_id': accountId,
          'account_name': account['name'],
          'amount': amount,
          'payment_date': invoiceDate,
          'created_at': now,
        });
        await txn.insert('money_entries', {
          'account_id': accountId,
          'kind': 'payment',
          'amount': -amount,
          'entry_date': invoiceDate,
          'note': 'Purchase PUR-${purchaseId.toString().padLeft(6, '0')}',
          'created_at': now,
          'purchase_id': purchaseId,
        });
      }
      final correction = RegExp(r'^purchase-correction-([0-9]+)-[0-9]+$')
          .firstMatch(requestKey);
      if (correction != null) {
        await txn.update(
          'purchase_invoices',
          {'replacement_id': purchaseId},
          where: "id = ? AND status = 'void' AND replacement_id IS NULL",
          whereArgs: [int.parse(correction[1]!)],
        );
      }
      await txn.delete(
        'app_settings',
        where: 'key = ? AND value LIKE ?',
        whereArgs: ['purchase_recovery', '%"request_key":"$requestKey"%'],
      );
      return purchaseId;
    });
  }

  Future<List<Map<String, Object?>>> getPurchases({
    required int branchId,
  }) async {
    final db = await database;
    return db.query(
      'purchase_invoices',
      where: 'branch_id = ?',
      whereArgs: [branchId],
      orderBy: 'id DESC',
    );
  }

  Future<void> voidSupplierSettlement({
    required int id,
    required String reason,
  }) async {
    final clean = reason.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Void reason required');
    }
    final db = await database;
    await db.transaction(
      (txn) => _deleteReversevoidSupplierSettlement(txn, id, clean),
    );
  }

  Future<void> _deleteReversevoidSupplierSettlement(
    Transaction txn,
    int id,
    String clean,
  ) async {
    final rows = await txn.query(
      'supplier_settlements',
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
    if (rows.isEmpty) {
      throw StateError('Supplier payment already void or missing');
    }
    final old = rows.single;
    final purchase = await txn.query(
      'purchase_invoices',
      where: "id = ? AND status = 'posted'",
      whereArgs: [old['purchase_id']],
    );
    if (purchase.isEmpty) throw StateError('Purchase is void');
    final paid = old['amount'] as int;
    final updated = await txn.rawUpdate(
      '''UPDATE purchase_invoices
        SET paid = paid - ?, balance_due = balance_due + ?
        WHERE id = ? AND paid >= ?''',
      [paid, paid, old['purchase_id'], paid],
    );
    if (updated != 1) throw StateError('Purchase balance changed');
    final now = DateTime.now().toUtc().toIso8601String();
    final day = AppDateTime.today().toIso8601String().substring(0, 10);
    final payments = await txn.query(
      'supplier_settlement_payments',
      where: 'settlement_id = ?',
      whereArgs: [id],
    );
    for (final p in payments) {
      final account = p['account_id'] as int;
      final amount = p['amount'] as int;
      final balance = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS n FROM money_entries WHERE account_id = ?',
        [account],
      );
      if ((balance.single['n'] as int) > 9000000000000 - amount) {
        throw StateError('Account balance limit exceeded');
      }
      await txn.insert('money_entries', {
        'account_id': account,
        'kind': 'adjustment',
        'amount': amount,
        'entry_date': day,
        'note': 'Void supplier payment #$id: $clean',
        'created_at': now,
        'supplier_settlement_id': id,
      });
    }
    await txn.update(
      'supplier_settlements',
      {'status': 'void', 'void_reason': clean, 'voided_at': now},
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
  }

  Future<void> voidPurchaseInvoice({
    required int id,
    required String reason,
  }) async {
    final clean = reason.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Void reason required');
    }
    final db = await database;
    await db.transaction((txn) => _voidPurchaseInvoice(txn, id, clean));
  }

  Future<void> _voidPurchaseInvoice(
    Transaction txn,
    int id,
    String clean,
  ) async {
    final rows = await txn.query(
      'purchase_invoices',
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
    if (rows.isEmpty) throw StateError('Purchase already void or missing');
    final purchase = rows.single;
    final settlements = await txn.query(
      'supplier_settlements',
      columns: ['id'],
      where: "purchase_id = ? AND status = 'posted'",
      whereArgs: [id],
      limit: 1,
    );
    if (settlements.isNotEmpty) {
      throw StateError('Void linked supplier payments first');
    }
    final branch = purchase['branch_id'] as int;
    final items = await txn.query(
      'purchase_items',
      where: 'purchase_id = ?',
      whereArgs: [id],
    );
    final payments = await txn.query(
      'purchase_payments',
      where: 'purchase_id = ?',
      whereArgs: [id],
    );
    final now = DateTime.now().toUtc().toIso8601String();
    final day = AppDateTime.today().toIso8601String().substring(0, 10);
    for (final item in items) {
      final qty = item['qty'] as int;
      final count = await txn.rawUpdate(
        '''UPDATE branch_stocks SET stock = stock - ?
          WHERE branch_id = ? AND product_id = ? AND stock >= ?''',
        [qty, branch, item['product_id'], qty],
      );
      if (count != 1) {
        throw StateError('Cannot void purchase: purchased stock has been used');
      }
      await txn.insert('stock_movements', {
        'branch_id': branch,
        'product_id': item['product_id'],
        'quantity': qty,
        'kind': 'sale',
        'note': 'Void purchase PUR-$id: $clean',
        'created_at': now,
        'purchase_id': id,
      });
    }
    for (final p in payments) {
      final account = p['account_id'] as int;
      final amount = p['amount'] as int;
      final balance = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount),0) AS n FROM money_entries WHERE account_id = ?',
        [account],
      );
      if ((balance.single['n'] as int) > 9000000000000 - amount) {
        throw StateError('Account balance limit exceeded');
      }
      await txn.insert('money_entries', {
        'account_id': account,
        'kind': 'adjustment',
        'amount': amount,
        'entry_date': day,
        'note': 'Void purchase PUR-$id: $clean',
        'created_at': now,
        'purchase_id': id,
      });
    }
    await ProductTracking.reversePurchase(txn, id);
    final updated = await txn.update(
      'purchase_invoices',
      {'status': 'void', 'void_reason': clean, 'voided_at': now},
      where: "id = ? AND status = 'posted'",
      whereArgs: [id],
    );
    if (updated != 1) throw StateError('Purchase changed. Reload');
  }

  Future<void> createPurchaseCorrectionWork({
    required int id,
    String reason = 'Edited using voucher unlock',
  }) async {
    await VoucherPermissions.requireEditable();
    final clean = reason.trim();
    if (clean.isEmpty || clean.length > 300) {
      throw ArgumentError('Correction reason required');
    }
    final db = await database;
    await db.transaction((txn) async {
      final saved = await txn.query(
        'app_settings',
        where: 'key = ?',
        whereArgs: ['purchase_recovery'],
      );
      if (saved.isNotEmpty) {
        throw StateError(
          'Finish or discard the current unfinished Purchase first',
        );
      }
      final rows = await txn.query(
        'purchase_invoices',
        where: "id = ? AND status = 'posted'",
        whereArgs: [id],
      );
      if (rows.isEmpty) throw StateError('Purchase already void or missing');
      final p = rows.single;
      final lines = await txn.rawQuery(
        '''SELECT i.*, p.category_id,p.brand_id,p.color,p.size,p.tracking,p.warranty_days
        FROM purchase_items i JOIN products p ON p.id = i.product_id
        WHERE i.purchase_id = ? ORDER BY i.id''',
        [id],
      );
      final payments = await txn.query(
        'purchase_payments',
        where: 'purchase_id = ?',
        whereArgs: [id],
      );

      final now = DateTime.now().toUtc().microsecondsSinceEpoch;
      final work = <String, Object?>{
        'request_key': 'purchase-correction-$id-$now',
        'branch_id': p['branch_id'],
        'supplier_id': p['supplier_id'],
        'purchase_date': p['invoice_date'],
        'lines': [
          for (final i in lines)
            {
              'product_id': i['product_id'],
              'item_code': i['item_code'],
              'name': i['item_name'],
              'category_id': i['category_id'],
              'brand_id': i['brand_id'],
              'color': i['color'],
              'size': i['size'],
              'tracking': i['tracking'],
              'warranty_days': i['warranty_days'],
              'lots': jsonDecode(i['tracking_json'] as String? ?? '[]'),
              'purchase_price': i['purchase_price'],
              'sale_price': i['sale_price'],
              'qty': i['qty'],
            },
        ],
        'payments': {
          for (final pay in payments)
            (pay['account_id'] as int).toString(): AppCurrency.input(
              pay['amount'] as int,
            ),
        },
      };
      await txn.insert('app_settings', {
        'key': 'purchase_recovery',
        'value': jsonEncode(work),
      });
    });
  }

  Future<Map<String, Object?>> getPurchase(int id) async {
    final db = await database;
    return db.transaction((txn) async {
      final headers = await txn.query(
        'purchase_invoices',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (headers.isEmpty) throw StateError('Purchase not found');
      final items = await txn.query(
        'purchase_items',
        where: 'purchase_id = ?',
        whereArgs: [id],
        orderBy: 'id',
      );
      final payments = await txn.query(
        'purchase_payments',
        where: 'purchase_id = ?',
        whereArgs: [id],
        orderBy: 'account_id',
      );
      final settlements = await txn.query(
        'supplier_settlements',
        where: 'purchase_id = ?',
        whereArgs: [id],
        orderBy: 'id',
      );
      final settledPayments = <Map<String, Object?>>[];
      for (final row in settlements) {
        final split = await txn.query(
          'supplier_settlement_payments',
          where: 'settlement_id = ?',
          whereArgs: [row['id']],
          orderBy: 'account_id',
        );
        for (final account in split) {
          settledPayments.add({
            ...account,
            'created_at': row['created_at'],
            'payment_date': row['payment_date'],
            'status': row['status'],
          });
        }
      }
      return {
        ...headers.single,
        'items': items,
        'payments': payments,
        'settlements': settlements,
        'settlement_payments': settledPayments,
      };
    });
  }

  Future<String?> getPurchaseWork() async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['purchase_recovery'],
    );
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> putPurchaseWork(String payload) async {
    if (payload.length > 2000000) {
      throw ArgumentError('Purchase draft too large');
    }
    final db = await database;
    await db.insert('app_settings', {
      'key': 'purchase_recovery',
      'value': payload,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePurchaseWork() async {
    final db = await database;
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['purchase_recovery'],
    );
  }

  /// An idempotent, atomic payment of one supplier purchase balance.
  Future<int> settleSupplierPurchase({
    required String requestKey,
    required int purchaseId,
    required String paymentDate,
    required List<Map<String, int>> payments,
  }) async {
    if (requestKey.isEmpty ||
        requestKey.length > 150 ||
        !_businessDate(paymentDate) ||
        payments.isEmpty) {
      throw ArgumentError('Invalid supplier payment');
    }
    if (requestKey.startsWith('supplier-correction-')) {
      await VoucherPermissions.requireEditable();
    }
    final db = await database;
    return db.transaction((txn) async {
      final prior = await txn.query(
        'supplier_settlements',
        where: 'request_key = ?',
        whereArgs: [requestKey],
      );
      if (prior.isNotEmpty) {
        if (prior.single['purchase_id'] != purchaseId) {
          throw StateError('Request key already used');
        }
        return prior.single['id'] as int;
      }
      final editMatch = RegExp(r'^supplier-correction-([0-9]+)-[0-9]+-[0-9]+$')
          .firstMatch(requestKey);
      if (editMatch != null) {
        await _deleteReversevoidSupplierSettlement(
          txn,
          int.parse(editMatch[1]!),
          'Edited using voucher unlock',
        );
      }
      final rows = await txn.query(
        'purchase_invoices',
        where: 'id = ?',
        whereArgs: [purchaseId],
      );
      if (rows.isEmpty) throw StateError('Purchase not found');
      final purchase = rows.single;
      if (purchase['status'] != 'posted') {
        throw StateError('Purchase invoice is void');
      }
      final branchId = purchase['branch_id'] as int;
      final due = purchase['balance_due'] as int;
      if (due <= 0) throw StateError('Purchase already fully paid');
      var amount = 0;
      final seen = <int>{};
      final accountNames = <int, String>{};
      for (final payment in payments) {
        final accountId = payment['account_id'];
        final value = payment['amount'];
        if (accountId == null ||
            value == null ||
            value <= 0 ||
            !seen.add(accountId)) {
          throw ArgumentError('Invalid split payment');
        }
        final account = await txn.rawQuery(
          '''SELECT a.id, a.name, COALESCE(SUM(e.amount),0) AS balance
          FROM money_accounts a LEFT JOIN money_entries e ON e.account_id = a.id
          WHERE a.id = ? AND a.branch_id = ? GROUP BY a.id''',
          [accountId, branchId],
        );
        if (account.isEmpty || (account.single['balance'] as int) < value) {
          throw StateError('Insufficient balance in selected branch account');
        }
        accountNames[accountId] = account.single['name'] as String;
        amount += value;
        if (amount > due) {
          throw ArgumentError('Payment exceeds outstanding balance');
        }
      }
      final now = DateTime.now().toUtc().toIso8601String();
      final settlementId = await txn.insert('supplier_settlements', {
        'request_key': requestKey,
        'purchase_id': purchaseId,
        'branch_id': branchId,
        'supplier_id': purchase['supplier_id'],
        'amount': amount,
        'payment_date': paymentDate,
        'created_at': now,
      });
      final changed = await txn.rawUpdate(
        '''UPDATE purchase_invoices
        SET paid = paid + ?, balance_due = balance_due - ? WHERE id = ? AND balance_due >= ?''',
        [amount, amount, purchaseId, amount],
      );
      if (changed != 1) throw StateError('Outstanding balance changed');
      for (final payment in payments) {
        final accountId = payment['account_id']!;
        final value = payment['amount']!;
        await txn.insert('supplier_settlement_payments', {
          'settlement_id': settlementId,
          'account_id': accountId,
          'account_name': accountNames[accountId],
          'amount': value,
        });
        await txn.insert('money_entries', {
          'account_id': accountId,
          'kind': 'payment',
          'amount': -value,
          'entry_date': paymentDate,
          'note':
              'Supplier payment PUR-${purchaseId.toString().padLeft(6, '0')}',
          'created_at': now,
          'supplier_settlement_id': settlementId,
        });
      }
      final correction = RegExp(r'^supplier-correction-([0-9]+)-[0-9]+-[0-9]+$')
          .firstMatch(requestKey);
      if (correction != null) {
        await txn.update(
          'supplier_settlements',
          {'replacement_id': settlementId},
          where: "id = ? AND status = 'void' AND replacement_id IS NULL",
          whereArgs: [int.parse(correction[1]!)],
        );
      }
      return settlementId;
    });
  }

  Future<List<Map<String, Object?>>> getSupplierBalances({
    required int branchId,
  }) async {
    final db = await database;
    return db.rawQuery(
      '''SELECT c.id, c.name, c.phone, COUNT(p.id) AS purchase_count,
      COALESCE(SUM(p.balance_due),0) AS balance_due
      FROM contacts c JOIN purchase_invoices p ON p.supplier_id = c.id
      WHERE c.kind = 'supplier' AND p.branch_id = ? AND p.status = 'posted'
      GROUP BY c.id ORDER BY balance_due DESC, c.name COLLATE NOCASE''',
      [branchId],
    );
  }

  Future<Map<String, Object?>?> getProductByBarcode({
    required int branchId,
    required String barcode,
  }) async {
    final value = barcode.trim();
    if (!BarcodeRules.valid(value)) return null;
    final db = await database;
    final rows = await db.rawQuery(
      '''SELECT p.id,p.name,p.price,p.barcode,p.item_code,p.category_id,p.brand_id,p.color,p.size,p.tracking,p.warranty_days, COALESCE(s.stock, 0) AS stock,
        EXISTS(SELECT 1 FROM product_images i WHERE i.product_id = p.id) AS has_image
      FROM products p LEFT JOIN branch_stocks s ON s.product_id = p.id AND s.branch_id = ?
      WHERE (CASE WHEN length(p.barcode) = 13 AND substr(p.barcode, 1, 1) = '0'
        AND p.barcode NOT GLOB '*[^0-9]*' THEN substr(p.barcode, 2) ELSE p.barcode END) = ?
        OR ('ITEM-' || printf('%06d', p.id)) = ?
        OR p.item_code = ? COLLATE NOCASE
      LIMIT 2''',
      [branchId, BarcodeRules.lookupKey(value), value, value],
    );
    if (rows.length > 1) {
      throw StateError(
        'Barcode matches multiple products. Check the product catalog.',
      );
    }
    return rows.isEmpty ? null : rows.single;
  }

  Future<void> _createInvoicePrintSnapshots(Database db) async {
    await db.execute(
      "ALTER TABLE sale_invoices ADD COLUMN business_name TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE sale_invoices ADD COLUMN branch_name_snapshot TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE sale_invoices ADD COLUMN branch_code_snapshot TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE sale_invoices ADD COLUMN branch_phone_snapshot TEXT NOT NULL DEFAULT ''",
    );
    await db.execute(
      "ALTER TABLE sale_invoices ADD COLUMN branch_address_snapshot TEXT NOT NULL DEFAULT ''",
    );
    // Legacy invoices did not store these fields: capture the known current
    // profile/branch once during upgrade; future sales capture at confirmation.
    await db.execute(
      '''UPDATE sale_invoices SET
      business_name = COALESCE((SELECT name FROM business_profile WHERE id = 1), ''),
      branch_name_snapshot = COALESCE((SELECT name FROM branches WHERE id = branch_id), ''),
      branch_code_snapshot = COALESCE((SELECT code FROM branches WHERE id = branch_id), ''),
      branch_phone_snapshot = COALESCE((SELECT phone FROM branches WHERE id = branch_id), ''),
      branch_address_snapshot = COALESCE((SELECT address FROM branches WHERE id = branch_id), '')''',
    );
  }
}
