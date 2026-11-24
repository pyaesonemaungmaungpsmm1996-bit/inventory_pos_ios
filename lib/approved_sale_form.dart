part of 'sale_invoices_page.dart';

/// Layout follows the approved invoice reference; every editable value is saved.
extension _ApprovedSaleForm on _SaleDraftFormState {
  Widget approvedDesktopInvoice(bool enabled) {
    final active = enabled && choicesReady && !desktopReviewing;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ink = dark ? const Color(0xFFF0F5FF) : const Color(0xFF10234D);
    final line = dark ? const Color(0xFF718093) : const Color(0xFFBED0E9);
    final surface = dark ? const Color(0xFF293B51) : Colors.white;
    final mint = dark ? const Color(0xFF255C4C) : const Color(0xFFD2F8EA);
    final green = dark ? const Color(0xFFA9F2CF) : const Color(0xFF00836E);
    final selected = lines.isEmpty
        ? null
        : lines[selectedLine.clamp(0, lines.length - 1)];
    Map<String, Object?> productFor(Map<String, Object?> row) {
      for (final p in products) {
        if (p['id'] == row['product_id']) return p;
      }
      return row;
    }

    String variant(Map<String, Object?> row) {
      final p = productFor(row);
      String value(String key) {
        final text = '${p[key] ?? ''}'.trim();
        return text.isEmpty ? '—' : text;
      }

      return '${value('color')} / ${value('size')}';
    }

    String identity(Map<String, Object?> row) {
      try {
        return (jsonDecode('${row['tracking_json'] ?? '[]'}') as List)
            .whereType<Map>()
            .map((allocation) {
              final lot = desktopLots[allocation['lot_id']] ?? allocation;
              return [lot['serial'], lot['imei']]
                  .where((value) => value != null && '$value'.isNotEmpty)
                  .join(' / ');
            })
            .where((text) => text.isNotEmpty)
            .join(', ');
      } catch (_) {
        return '';
      }
    }

    final employee = staff.where((row) => row['id'] == employeeId).toList();
    final employeeName = employee.isEmpty
        ? ''
        : employee.first['name'].toString();
    String number(int value) => _money(value).split(' ').first;
    final fieldDecoration = InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      labelStyle: TextStyle(
        fontFamily: 'Segoe UI',
        fontFamilyFallback: const ['Myanmar Text'],
        color: ink,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        fontFamily: 'Segoe UI',
        fontFamilyFallback: const ['Myanmar Text'],
        color: ink.withValues(alpha: .6),
        fontSize: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: green, width: 1.5),
      ),
    );
    Widget panel(
      Widget child, {
      required List<Color> colors,
      EdgeInsets padding = const EdgeInsets.all(10),
    }) => Material(
      color: Colors.transparent,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: line.withValues(alpha: .85)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120C2450),
              blurRadius: 5,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
    Widget tool(
      String label,
      IconData icon,
      VoidCallback? callback, {
      bool confirm = false,
    }) => SizedBox(
      height: 36,
      child: confirm
          ? FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF008875),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 0,
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: ['Myanmar Text'],
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: callback,
              icon: Icon(icon, size: 23),
              label: Text(label),
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                backgroundColor: dark ? const Color(0xFF35465E) : Colors.white,
                foregroundColor: ink,
                side: BorderSide(color: line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 0,
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: ['Myanmar Text'],
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onPressed: callback,
              icon: Icon(icon, size: 22),
              label: Text(label),
            ),
    );
    Widget labeled(String label, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Segoe UI',
            fontFamilyFallback: const ['Myanmar Text'],
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const SizedBox(height: 5),
        SizedBox(height: 34, child: child),
      ],
    );
    Future<void> datePicker() async {
      final picked = await showDatePicker(
        context: context,
        initialDate: invoiceDate,
        firstDate: DateTime(1900),
        lastDate: DateTime(2200, 12, 31),
      );
      if (picked != null && mounted) {
        desktopRefresh(() => invoiceDate = picked);
        _touch();
      }
    }

    final dateLabel =
        '${invoiceDate.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][invoiceDate.month - 1]} ${invoiceDate.year}';
    Widget header() => LayoutBuilder(
      builder: (context, box) => Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: dark
                ? const [Color(0xFF34436B), Color(0xFF25364C)]
                : const [Color(0xFFE1E6FF), Color(0xFFEDF8FC)],
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _t('Sale Invoice', 'အရောင်းဘောင်ချာ'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Segoe UI',
                        fontFamilyFallback: const ['Myanmar Text'],
                        color: ink,
                        fontSize: 23,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: green),
                    ),
                    child: Text(
                      _t('Draft', 'မူကြမ်း'),
                      style: TextStyle(
                        fontFamily: 'Segoe UI',
                        fontFamilyFallback: const ['Myanmar Text'],
                        color: green,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: (box.maxWidth * .28).clamp(160.0, 340.0),
              child: DropdownButtonFormField<int>(
                key: ValueKey('approved-branch-$branchId'),
                initialValue: branchId,
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.storefront_outlined,
                    color: ink,
                    size: 22,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  fillColor: dark
                      ? const Color(0xFF3E4D7E)
                      : const Color(0xFFE1E8FF),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: dark
                          ? const Color(0xFF7187E0)
                          : const Color(0xFF8CA4FF),
                    ),
                  ),
                ),
                items: [
                  for (final branch in widget.branches)
                    DropdownMenuItem(
                      value: branch['id'] as int,
                      child: Text(
                        '${branch['name']} (${branch['code']})',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Segoe UI',
                          fontFamilyFallback: const ['Myanmar Text'],
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
                ],
                onChanged: active
                    ? (id) {
                        if (id != null) changeBranch(id);
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Container(height: 30, width: 1, color: line),
            const SizedBox(width: 12),
            CircleAvatar(
              radius: 19,
              backgroundColor: dark
                  ? const Color(0xFF6ACD9C)
                  : const Color(0xFFAAF0D8),
              child: Text(
                employeeName.isEmpty
                    ? '—'
                    : employeeName.characters.first.toUpperCase(),
                style: const TextStyle(
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: ['Myanmar Text'],
                  color: Color(0xFF006F5C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (box.maxWidth > 650) ...[
              const SizedBox(width: 9),
              Text(
                employeeName,
                style: TextStyle(
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: const ['Myanmar Text'],
                  color: ink,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    Widget toolbar() => LayoutBuilder(
      builder: (context, box) {
        final controls = Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            tool(
              _t('New', 'အသစ်'),
              Icons.note_add_outlined,
              active ? desktopNewInvoice : null,
            ),
            tool(
              _t('Save Draft', 'မူကြမ်းသိမ်း'),
              Icons.save_outlined,
              active && widget.sharedSession == null ? () => save() : null,
            ),
            tool(
              _t('Find', 'ရှာရန်'),
              Icons.search,
              active ? chooseProduct : null,
            ),
            tool(
              'Serial / IMEI',
              Icons.view_week_rounded,
              active &&
                      selected != null &&
                      '${productFor(selected)['tracking'] ?? 'none'}' != 'none'
                  ? editDesktopIdentities
                  : null,
            ),
          ],
        );
        final confirm = tool(
          _t('Confirm Sale', 'အရောင်းအတည်ပြု'),
          Icons.check,
          active ? () => save(openPayment: true) : null,
          confirm: true,
        );
        return box.maxWidth > 1000
            ? Row(children: [controls, const Spacer(), confirm])
            : Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 8,
                children: [controls, confirm],
              );
      },
    );
    Widget progress() => Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: desktopReviewing ? Colors.transparent : mint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _t('1. Draft', '၁။ မူကြမ်း'),
            style: TextStyle(
              fontFamily: 'Segoe UI',
              fontFamilyFallback: const ['Myanmar Text'],
              color: desktopReviewing ? ink : green,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.arrow_forward, size: 19, color: ink),
        ),
        Flexible(
          child: Text(
            _t('2. Confirm sale', '၂။ အရောင်းအတည်ပြု'),
            style: TextStyle(
              fontFamily: 'Segoe UI',
              fontFamilyFallback: const ['Myanmar Text'],
              color: ink,
              fontWeight: desktopReviewing ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.arrow_forward, size: 19, color: ink),
        ),
        Flexible(
          child: Text(
            _t('3. Print preview', '၃။ ပုံနှိပ်မူကြမ်း'),
            style: TextStyle(
              fontFamily: 'Segoe UI',
              fontFamilyFallback: const ['Myanmar Text'],
              color: ink,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
    Widget metadata() => panel(
      LayoutBuilder(
        builder: (context, box) {
          final columns = box.maxWidth >= 600 ? 4 : 2;
          final width = (box.maxWidth - (columns - 1) * 14) / columns;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 14,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: width,
                    child: labeled(
                      _t('Invoice No.', 'ဘောင်ချာနံပါတ်'),
                      TextFormField(
                        readOnly: true,
                        initialValue: _t(
                          'Assigned on confirm',
                          'အတည်ပြုပြီးမှ ရမည်',
                        ),
                        style: TextStyle(
                          fontFamily: 'Segoe UI',
                          fontFamilyFallback: const ['Myanmar Text'],
                          color: ink.withValues(alpha: .7),
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          fillColor: dark
                              ? const Color(0xFF3A495D)
                              : const Color(0xFFE8EEF6),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: labeled(
                      _t('Date', 'ရက်စွဲ'),
                      InkWell(
                        onTap: active ? datePicker : null,
                        child: InputDecorator(
                          decoration: const InputDecoration(),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  dateLabel,
                                  style: TextStyle(
                                    fontFamily: 'Segoe UI',
                                    fontFamilyFallback: const ['Myanmar Text'],
                                    color: ink,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.calendar_month_outlined,
                                size: 22,
                                color: ink,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: labeled(
                      _t('Customer', 'ဝယ်သူ'),
                      TextFormField(
                        controller: name,
                        enabled: active,
                        style: TextStyle(
                          fontFamily: 'Segoe UI',
                          fontFamilyFallback: const ['Myanmar Text'],
                          color: ink,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          hintText: _t('Walk-in customer', 'လက်ငင်းဝယ်သူ'),
                          suffixIcon: IconButton(
                            tooltip: _t('Choose customer', 'ဝယ်သူရွေးရန်'),
                            onPressed: active ? chooseCustomer : null,
                            icon: Icon(
                              Icons.person_search_outlined,
                              color: ink,
                              size: 22,
                            ),
                          ),
                        ),
                        validator: (value) =>
                            saveContact &&
                                customerId == null &&
                                (value == null || value.trim().isEmpty)
                            ? _t('Enter a customer name.', 'ဝယ်သူနာမည် ထည့်ပါ')
                            : null,
                        onTapOutside: (_) =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: labeled(
                      _t('Salesperson', 'အရောင်းဝန်ထမ်း'),
                      DropdownButtonFormField<int>(
                        key: ValueKey(
                          'approved-employee-$branchId-$employeeId',
                        ),
                        initialValue: employeeId,
                        isExpanded: true,
                        style: TextStyle(
                          fontFamily: 'Segoe UI',
                          fontFamilyFallback: const ['Myanmar Text'],
                          color: ink,
                          fontSize: 13,
                        ),
                        decoration: const InputDecoration(),
                        items: [
                          for (final person in staff)
                            DropdownMenuItem(
                              value: person['id'] as int,
                              child: Text(
                                '${person['name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: active
                            ? (id) {
                                desktopRefresh(() => employeeId = id);
                                _touch();
                              }
                            : null,
                        validator: (id) => widget.sharedSession == null && id == null
                            ? _t('Choose an employee.', 'ဝန်ထမ်းရွေးပါ')
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('sale-customer-details'),
                    onPressed: active ? desktopCustomerDetails : null,
                    icon: const Icon(Icons.contact_page_outlined, size: 16),
                    label: Text(_t('Customer details', 'ဝယ်သူအချက်အလက်')),
                  ),
                  if (customerId != null)
                    Text('${ContactSearch.code(customerId)} · ${phone.text}'),
                  if (customerId == null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: saveContact,
                          onChanged: active
                              ? (v) {
                                  desktopRefresh(
                                    () => saveContact = v ?? false,
                                  );
                                  _touch();
                                }
                              : null,
                        ),
                        Text(
                          _t(
                            'Save customer for next visit',
                            'နောက်တစ်ခါအတွက် ဝယ်သူသိမ်းရန်',
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: saleItemSearch(active, ink)),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 34,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: mint,
                        foregroundColor: green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontFamily: 'Segoe UI',
                          fontFamilyFallback: ['Myanmar Text'],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: active ? chooseProduct : null,
                      icon: const Icon(Icons.add, size: 23),
                      label: Text(_t('Add Item', 'ပစ္စည်းထည့်')),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      colors: dark
          ? const [Color(0xFF293B50), Color(0xFF22354A)]
          : const [Color(0xFFF1F8FF), Color(0xFFFBFDFF)],
    );
    Widget items() => panel(
      LayoutBuilder(
        builder: (context, box) {
          final small = box.maxWidth < 1000;
          final font = small ? 12.0 : 13.0;
          final table = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: DataTable(
                key: const ValueKey('desktop-sale-items'),
                showCheckboxColumn: false,
                headingRowHeight: 34,
                dataRowMinHeight: 34,
                dataRowMaxHeight: 36,
                columnSpacing: small ? 10 : 20,
                horizontalMargin: 10,
                headingTextStyle: TextStyle(
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: const ['Myanmar Text'],
                  color: ink,
                  fontSize: font,
                  fontWeight: FontWeight.w600,
                ),
                dataTextStyle: TextStyle(
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: const ['Myanmar Text'],
                  color: ink,
                  fontSize: font,
                ),
                headingRowColor: WidgetStatePropertyAll(
                  dark ? const Color(0xFF22564D) : const Color(0xFFC9F6E9),
                ),
                columns: [
                  for (final label in [
                    _t('No.', 'စဉ်'),
                    _t('Item code', 'ကုဒ်'),
                    _t('Item name', 'ပစ္စည်းအမည်'),
                    _t('Color / Size', 'အရောင် / အရွယ်'),
                    'Serial / IMEI',
                    _t('Qty', 'ဦးရေ'),
                    _t('Unit price', 'တစ်ခုဈေး'),
                    _t('Item discount', 'ပစ္စည်းလျှော့ဈေး'),
                    _t('Net amount', 'အသားတင်'),
                    '',
                  ])
                    DataColumn(label: Text(label)),
                ],
                rows: [
                  for (var i = 0; i < lines.length; i++)
                    (() {
                      final row = lines[i], id = row['product_id'] as int;
                      final qty = desktopQtyControllers.putIfAbsent(
                        id,
                        () => TextEditingController(text: '${row['qty']}'),
                      );
                      final off = desktopDiscountControllers.putIfAbsent(
                        id,
                        () => TextEditingController(
                          text: AmountInputFormatter.group(
                            AppCurrency.input(
                              row['item_discount'] as int? ?? 0,
                            ),
                          ),
                        ),
                      );
                      final amount =
                          (row['price'] as int) * (row['qty'] as int);
                      Widget quantity() => SizedBox(
                        width: small ? 66 : 88,
                        height: 32,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                key: ValueKey('row-qty-$id'),
                                controller: qty,
                                enabled: active,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Segoe UI',
                                  fontFamilyFallback: const ['Myanmar Text'],
                                  color: ink,
                                  fontSize: font,
                                ),
                                decoration: const InputDecoration(
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 7,
                                  ),
                                ),
                                keyboardType: TextInputType.number,
                                validator: (text) {
                                  final n = int.tryParse(text ?? '');
                                  return n == null || n < 1 || n > 2147483647
                                      ? '!'
                                      : null;
                                },
                                onChanged: (text) => desktopQuantity(i, text),
                              ),
                            ),
                            SizedBox(
                              width: 19,
                              child: Column(
                                children: [
                                  InkWell(
                                    onTap: active
                                        ? () {
                                            final value =
                                                (row['qty'] as int) + 1;
                                            qty.text = '$value';
                                            desktopQuantity(i, '$value');
                                          }
                                        : null,
                                    child: Icon(
                                      Icons.keyboard_arrow_up,
                                      size: 16,
                                      color: ink,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: active && (row['qty'] as int) > 1
                                        ? () {
                                            final value =
                                                (row['qty'] as int) - 1;
                                            qty.text = '$value';
                                            desktopQuantity(i, '$value');
                                          }
                                        : null,
                                    child: Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 16,
                                      color: ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                      return DataRow(
                        selected: selectedLine == i,
                        color: WidgetStatePropertyAll(
                          selectedLine == i
                              ? (dark
                                    ? const Color(0xFF29443E)
                                    : const Color(0xFFE1FCF0))
                              : Colors.transparent,
                        ),
                        onSelectChanged: active
                            ? (_) => desktopRefresh(() => selectedLine = i)
                            : null,
                        cells: [
                          DataCell(Text('${i + 1}')),
                          DataCell(Text('${row['item_code']}')),
                          DataCell(
                            SizedBox(
                              width: small ? 110 : 210,
                              child: Text(
                                '${row['item_name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(Text(variant(row))),
                          DataCell(
                            Tooltip(
                              message: identity(row),
                              child: SizedBox(
                                width: small ? 95 : 170,
                                child: Text(
                                  identity(row).isEmpty ? '—' : identity(row),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                          DataCell(quantity()),
                          DataCell(Text(number(row['price'] as int))),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: small ? 77 : 120,
                                  height: 28,
                                  child: TextFormField(
                                    key: ValueKey('row-discount-$id'),
                                    controller: off,
                                    enabled: active,
                                    textAlign: TextAlign.right,
                                    inputFormatters: const [
                                      AmountInputFormatter(),
                                    ],
                                    style: TextStyle(
                                      fontFamily: 'Segoe UI',
                                      fontFamilyFallback: const [
                                        'Myanmar Text',
                                      ],
                                      color: ink,
                                      fontSize: font,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    decoration: InputDecoration(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 7,
                                          ),
                                      fillColor:
                                          (row['item_discount'] as int? ?? 0) >
                                              0
                                          ? (dark
                                                ? const Color(0xFF69502D)
                                                : const Color(0xFFFFF0C9))
                                          : surface,
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(6),
                                        borderSide: BorderSide(
                                          color:
                                              (row['item_discount'] as int? ??
                                                      0) >
                                                  0
                                              ? const Color(0xFFE6B75B)
                                              : line,
                                        ),
                                      ),
                                    ),
                                    validator: (value) {
                                      final n = AppCurrency.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      return n == null || n < 0 || n > amount
                                          ? '!'
                                          : null;
                                    },
                                    onChanged: (value) {
                                      final n = AppCurrency.tryParse(value);
                                      if (n != null && n >= 0 && n <= amount) {
                                        desktopRefresh(
                                          () => row['item_discount'] = n,
                                        );
                                        _touch();
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  AppCurrency.displayCode,
                                  style: TextStyle(
                                    fontFamily: 'Segoe UI',
                                    fontFamilyFallback: const ['Myanmar Text'],
                                    fontSize: font,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              number(
                                amount - (row['item_discount'] as int? ?? 0),
                              ),
                              style: TextStyle(
                                fontFamily: 'Segoe UI',
                                fontFamilyFallback: const ['Myanmar Text'],
                                color: ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: _t('Edit item', 'ပစ္စည်းပြင်ရန်'),
                                  constraints: const BoxConstraints.tightFor(
                                    width: 28,
                                    height: 30,
                                  ),
                                  padding: EdgeInsets.zero,
                                  onPressed: active && _pendingLine == null
                                      ? () {
                                          selectedLine = i;
                                          editLine(i);
                                        }
                                      : null,
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    color: green,
                                    size: 20,
                                  ),
                                ),
                                IconButton(
                                  tooltip: _t('Remove item', 'ပစ္စည်းဖယ်ရန်'),
                                  constraints: const BoxConstraints.tightFor(
                                    width: 28,
                                    height: 30,
                                  ),
                                  padding: EdgeInsets.zero,
                                  onPressed: active && _pendingLine == null
                                      ? () {
                                          selectedLine = i;
                                          removeSelected();
                                        }
                                      : null,
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Color(0xFFDA473C),
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    })(),
                ],
              ),
            ),
          );
          return Focus(
            focusNode: rowsFocus,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        table,
                        if (lines.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(25),
                            child: Text(
                              _t(
                                'Scan or add an item to start.',
                                'စတင်ရန် ပစ္စည်း Scan ဖတ်ပါ သို့မဟုတ် ထည့်ပါ',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Segoe UI',
                                fontFamilyFallback: const ['Myanmar Text'],
                                color: ink.withValues(alpha: .6),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Divider(color: line, height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: ink.withValues(alpha: .75),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _t(
                          'Item discount applies only to its row.',
                          'ပစ္စည်းလျှော့ဈေးသည် သက်ဆိုင်ရာအတန်းအတွက်သာ ဖြစ်သည်။',
                        ),
                        style: TextStyle(
                          fontFamily: 'Segoe UI',
                          fontFamilyFallback: const ['Myanmar Text'],
                          color: ink.withValues(alpha: .8),
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
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
      colors: dark
          ? const [Color(0xFF1B2C40), Color(0xFF16283A)]
          : const [Color(0xFFFFFFFF), Color(0xFFF8FCFF)],
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
    );
    Widget footer() => panel(
      LayoutBuilder(
        builder: (context, box) {
          final textSize = 13.0;
          Widget summaryRow(
            String label,
            Widget value, {
            bool bold = false,
            Color? tint,
          }) => Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: tint == null
                ? null
                : BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(7),
                  ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Segoe UI',
                      fontFamilyFallback: const ['Myanmar Text'],
                      color: ink,
                      fontSize: bold ? textSize + 1 : textSize,
                      fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                value,
              ],
            ),
          );
          Widget money(int value, {bool bold = false, Color? color}) => Text(
            _money(value),
            style: TextStyle(
              fontFamily: 'Segoe UI',
              fontFamilyFallback: const ['Myanmar Text'],
              color: color ?? ink,
              fontSize: bold ? textSize + 1 : textSize,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w600,
            ),
          );
          Widget amountInput(
            TextEditingController controller,
            Key key,
            FocusNode focus, {
            String? label,
            VoidCallback? onChanged,
          }) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: (box.maxWidth * .19).clamp(90.0, 210.0),
                height: 28,
                child: TextFormField(
                  key: key,
                  controller: controller,
                  focusNode: focus,
                  enabled: active,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: 'Segoe UI',
                    fontFamilyFallback: const ['Myanmar Text'],
                    color: ink,
                    fontSize: textSize,
                  ),
                  inputFormatters: const [AmountInputFormatter()],
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    labelText: label,
                  ),
                  onChanged: (_) {
                    desktopRefresh(() {});
                    onChanged?.call();
                  },
                  validator: (value) {
                    final n =
                        key == const ValueKey('voucher-discount') &&
                            discountType == 'percent'
                        ? int.tryParse((value ?? '').replaceAll(',', '').trim())
                        : AppCurrency.tryParse(
                            value?.trim().isEmpty ?? true ? '0' : value!.trim(),
                          );
                    if (n == null || n < 0) return '!';
                    if (key == const ValueKey('desktop-paid-amount') &&
                        n > desktopTotal) {
                      return '!';
                    }
                    if (key == const ValueKey('voucher-discount') &&
                        (voucherDiscountAmount > subtotal - itemDiscountTotal ||
                            (discountType == 'percent' && n > 100))) {
                      return '!';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 6),
              Text(
                discountType == 'percent' &&
                        key == const ValueKey('voucher-discount')
                    ? '%'
                    : AppCurrency.displayCode,
                style: TextStyle(
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: const ['Myanmar Text'],
                  color: ink,
                  fontSize: textSize,
                ),
              ),
            ],
          );
          final summary = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              summaryRow(_t('Subtotal', 'ပစ္စည်းတန်ဖိုး'), money(subtotal)),
              summaryRow(
                _t('Item discounts', 'ပစ္စည်းလျှော့ဈေးများ'),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: dark
                        ? const Color(0xFF69502D)
                        : const Color(0xFFFFEDC3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '−${_money(itemDiscountTotal)}',
                    style: TextStyle(
                      fontFamily: 'Segoe UI',
                      fontFamilyFallback: const ['Myanmar Text'],
                      color: dark
                          ? const Color(0xFFFFD376)
                          : const Color(0xFF944600),
                      fontSize: textSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              summaryRow(
                _t('Voucher discount', 'ဘောင်ချာလျှော့ဈေး'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: _t('Discount type', 'လျှော့ဈေးအမျိုးအစား'),
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.unfold_more, size: 16, color: ink),
                      onSelected: (value) {
                        desktopRefresh(() => discountType = value);
                        _touch();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'amount',
                          child: Text(AppCurrency.displayCode),
                        ),
                        const PopupMenuItem(value: 'percent', child: Text('%')),
                      ],
                    ),
                    amountInput(
                      discount,
                      const ValueKey('voucher-discount'),
                      discountFocus,
                    ),
                  ],
                ),
              ),
              summaryRow(
                _t('Total amount', 'ကျသင့်ငွေ'),
                money(desktopTotal, bold: true, color: green),
                bold: true,
                tint: mint,
              ),
              summaryRow(
                _t('Paid', 'ပေးချေငွေ'),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: _t('Split payment', 'ငွေခွဲချေမှု'),
                      constraints: const BoxConstraints.tightFor(
                        width: 26,
                        height: 28,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: active ? desktopTakePayment : null,
                      icon: Icon(Icons.expand_more, size: 18, color: ink),
                    ),
                    amountInput(
                      desktopPaid,
                      const ValueKey('desktop-paid-amount'),
                      desktopPaidFocus,
                    ),
                  ],
                ),
              ),
              summaryRow(
                _t('Balance', 'ကျန်ငွေ'),
                money(desktopBalance, bold: true),
                bold: true,
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('sale-payment-button'),
                      onPressed: active ? desktopTakePayment : null,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(_t('Payment', 'ငွေချေမည်')),
                    ),
                  ),
                  IconButton(
                    tooltip: _t(
                      'Payment account and date',
                      'ငွေစာရင်းနှင့် ငွေချေရက်',
                    ),
                    onPressed: active ? desktopPaymentDetails : null,
                    icon: const Icon(Icons.event_outlined),
                  ),
                ],
              ),
            ],
          );
          final note = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: dark
                          ? const Color(0xFF1C526F)
                          : const Color(0xFFD4ECFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.sticky_note_2_outlined,
                      color: dark
                          ? const Color(0xFFA4DCFF)
                          : const Color(0xFF0878C5),
                      size: 23,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    _t('Remark', 'မှတ်ချက်'),
                    style: TextStyle(
                      fontFamily: 'Segoe UI',
                      fontFamilyFallback: const ['Myanmar Text'],
                      color: ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: _t('Customer details', 'ဝယ်သူအချက်အလက်'),
                    onPressed: active ? desktopCustomerDetails : null,
                    icon: Icon(Icons.person_outline, color: ink, size: 20),
                    constraints: const BoxConstraints.tightFor(
                      width: 26,
                      height: 28,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: TextFormField(
                  key: const ValueKey('desktop-remark'),
                  controller: remark,
                  enabled: active,
                  expands: true,
                  maxLines: null,
                  maxLength: 4000,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(
                    fontFamily: 'Segoe UI',
                    fontFamilyFallback: const ['Myanmar Text'],
                    color: ink,
                    fontSize: textSize,
                  ),
                  decoration: const InputDecoration(counterText: ''),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${_t('Total Qty', 'စုစုပေါင်းဦးရေ')}: ${lines.fold<int>(0, (sum, row) => sum + (row['qty'] as int))}    |    ${_t('Items', 'ပစ္စည်း')}: ${lines.length}',
                style: TextStyle(
                  fontFamily: 'Segoe UI',
                  fontFamilyFallback: const ['Myanmar Text'],
                  color: ink,
                  fontSize: textSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
          return SizedBox(
            height: 224,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 5, child: note),
                const SizedBox(width: 14),
                VerticalDivider(width: 1, color: line),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: summary),
              ],
            ),
          );
        },
      ),
      colors: dark
          ? const [Color(0xFF403D37), Color(0xFF35383D)]
          : const [Color(0xFFFFF7E7), Color(0xFFFFFCF5)],
    );
    return Theme(
      data: Theme.of(context).copyWith(inputDecorationTheme: fieldDecoration),
      child: Form(
        key: form,
        child: Column(
          children: [
            header(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final diagnostics = <Widget>[
                    if (loading) const LinearProgressIndicator(),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          error!,
                          style: TextStyle(
                            fontFamily: 'Segoe UI',
                            fontFamilyFallback: const ['Myanmar Text'],
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    if (_autoError != null)
                      TextButton(
                        onPressed: () => unawaited(_persistNow()),
                        child: Text(_autoError!),
                      ),
                    if (_pendingLine != null)
                      TextButton(
                        onPressed: active ? _resumeItem : null,
                        child: Text(
                          _t(
                            'Continue unfinished item entry',
                            'မပြီးသေးသော ပစ္စည်းထည့်ခြင်း ဆက်လုပ်ရန်',
                          ),
                        ),
                      ),
                    if (!choicesReady && !loading)
                      TextButton(
                        onPressed: loadChoices,
                        child: Text(_t('Reload choices', 'စာရင်းပြန်ဖတ်ရန်')),
                      ),
                  ];
                  final top = Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      toolbar(),
                      const SizedBox(height: 8),
                      progress(),
                      const SizedBox(height: 8),
                      metadata(),
                      ...diagnostics,
                    ],
                  );
                  if (box.maxHeight < 650 || box.maxWidth < 650) {
                    return SingleChildScrollView(
                      controller: scroll,
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          top,
                          const SizedBox(height: 8),
                          SizedBox(height: 230, child: items()),
                          const SizedBox(height: 8),
                          footer(),
                        ],
                      ),
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        top,
                        const SizedBox(height: 8),
                        Expanded(child: items()),
                        const SizedBox(height: 8),
                        footer(),
                      ],
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
}
