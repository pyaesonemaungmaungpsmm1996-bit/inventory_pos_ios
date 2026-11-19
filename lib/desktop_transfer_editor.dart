part of 'transfer_vouchers_page.dart';

extension _DesktopTransferEditor on _TransferEditorState {
  Widget desktopTransferEditor() => DesktopScaffold(
    appBar: AppBar(
      title: Text(
        widget.editVoucher == null
            ? 'New transfer voucher'
            : 'Edit transfer voucher',
      ),
      actions: [
        if (widget.editVoucher != null)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.lock_open),
          ),
      ],
    ),
    body: DesktopVoucherWorkspace(
      commands: [
        if (widget.editVoucher == null)
          OutlinedButton.icon(
            onPressed: busy ? null : saveWork,
            icon: const Icon(Icons.save_outlined, size: 17),
            label: Text(tt('Save Draft · Ctrl+S', 'Draft သိမ်းရန် · Ctrl+S')),
          ),
        OutlinedButton.icon(
          onPressed: busy ? null : () => addLine(),
          icon: const Icon(Icons.add, size: 17),
          label: Text(
            tt('Add Item / IMEI / Serial', 'ပစ္စည်း / IMEI / Serial ထည့်ရန်'),
          ),
        ),
        FilledButton.icon(
          onPressed: busy || lines.isEmpty || !workRead ? null : keyboardPost,
          icon: const Icon(Icons.check, size: 17),
          label: Text(
            widget.editVoucher == null
                ? tt('Confirm Transfer', 'ပစ္စည်းလွှဲမှု အတည်ပြုရန်')
                : tt('Save Changes', 'ပြင်ဆင်မှုသိမ်းရန်'),
          ),
        ),
      ],
      entry: RawAutocomplete<Map<String, Object?>>(
        displayStringForOption: (p) => p['name'].toString(),
        optionsBuilder: (v) => v.text.trim().isEmpty
            ? const Iterable<Map<String, Object?>>.empty()
            : products.where(
                (p) => ['name', 'item_code', 'barcode'].any(
                  (k) => (p[k] ?? '').toString().toLowerCase().contains(
                    v.text.toLowerCase(),
                  ),
                ),
              ),
        onSelected: (p) {
          final i = lines.indexWhere((l) => l['product_id'] == p['id']);
          addLine(index: i < 0 ? null : i, selectedProduct: p);
        },
        fieldViewBuilder: (c, controller, focus, submit) => TextField(
          controller: controller,
          focusNode: focus,
          enabled: !busy,
          onSubmitted: (_) => submit(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: tt(
              'Search item name / code / barcode',
              'ပစ္စည်းအမည် / Code / Barcode ရှာရန်',
            ),
          ),
        ),
        optionsViewBuilder: (c, select, options) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            child: SizedBox(
              width: 700,
              height: 260,
              child: ListView(
                children: [
                  for (final p in options)
                    ListTile(
                      dense: true,
                      title: Text(p['name'].toString()),
                      subtitle: Text(p['item_code'].toString()),
                      onTap: () => select(p),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
      metadata: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: tt('From branch', 'မူလဆိုင်ခွဲ'),
          ),
          child: Text(
            widget.branches
                .firstWhere((b) => b['id'] == widget.source)['name']
                .toString(),
          ),
        ),
        DropdownButtonFormField<int>(
          initialValue: destination,
          decoration: InputDecoration(
            labelText: tt('To branch', 'လက်ခံဆိုင်ခွဲ'),
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
          onChanged: busy ? null : (v) => desktopUpdate(() => destination = v),
        ),
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: date,
                    firstDate: DateTime(2000),
                    lastDate: AppDateTime.today(),
                  );
                  if (d != null && mounted) desktopUpdate(() => date = d);
                },
          icon: const Icon(Icons.calendar_today, size: 17),
          label: Text(date.toIso8601String().substring(0, 10)),
        ),
      ],
      notice: error == null
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(error!),
                if (!workRead)
                  TextButton(
                    onPressed: busy ? null : discardSavedWork,
                    child: Text(
                      tt(
                        'Discard saved transfer draft',
                        'သိမ်းထားသော Transfer Draft ကိုဖယ်ရန်',
                      ),
                    ),
                  ),
              ],
            ),
      table: Focus(
        focusNode: rowsFocus,
        child: DesktopListView.builder(
          controller: keyboardScroll,
          itemCount: lines.length,
          desktopColumns: const [
            'Item code',
            'Product',
            'Color / Size',
            'Serial / IMEI / Expiry',
            'Quantity',
          ],
          desktopFlexes: const [1, 2, 1, 3, 1],
          desktopCells: (context, i) {
            final l = lines[i];
            return [
              desktopCellText(l['item_code']),
              desktopCellText(l['product_name']),
              desktopCellText(variant(l)),
              desktopCellText(
                ProductTracking.decode(l['lots'])
                    .map(
                      (lot) => desktopLotLabels[lot['lot_id']] ?? identity(lot),
                    )
                    .where((s) => s.isNotEmpty)
                    .join(', '),
              ),
              desktopCellText(l['quantity']),
            ];
          },
          itemBuilder: (context, i) => DesktopListTile(
            selected: selectedLine == i,
            onTap: busy
                ? null
                : () {
                    desktopUpdate(() => selectedLine = i);
                    addLine(index: i);
                  },
            trailing: IconButton(
              onPressed: busy
                  ? null
                  : () {
                      selectedLine = i;
                      removeSelected();
                    },
              tooltip: tt('Remove item', 'ပစ္စည်းဖယ်ရန်'),
              icon: const Icon(Icons.delete_outline, size: 17),
            ),
          ),
        ),
      ),
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DesktopPropertyFields(
            children: [
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
                  labelText: tt('Transportation info', 'ပို့ဆောင်ရေးအချက်အလက်'),
                ),
              ),
            ],
          ),
          Text(
            '${tt('Items: ', 'ပစ္စည်းအမျိုးအစား: ')}${lines.length}   |   ${tt('Total Qty: ', 'စုစုပေါင်းအရေအတွက်: ')}${lines.fold<int>(0, (n, l) => n + (l['quantity'] as int))}',
          ),
          const SizedBox(height: 6),
          Text(
            tt(
              'Destination stock is added only when the whole voucher is received.',
              'လက်ခံဆိုင်ခွဲတွင် ဘောင်ချာတစ်စောင်လုံး Receive လုပ်မှ လက်ကျန်တိုးပါမည်။',
            ),
          ),
        ],
      ),
    ),
  );
}
