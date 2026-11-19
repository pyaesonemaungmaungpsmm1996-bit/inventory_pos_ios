part of 'sale_invoices_page.dart';

extension _SaleItemSearch on _SaleDraftFormState {
  Future<void> selectSaleSuggestion(Map<String, Object?> product) async {
    if (saving || loading || _finalizing || saleLookupBusy) return;
    saleLookupBusy = true;
    try {
      if (_pendingLine != null) {
        await _resumeItem();
        return;
      }
      desktopSearchFocus.unfocus();
      final index = lines.indexWhere((l) => l['product_id'] == product['id']);
      await editLine(index < 0 ? null : index, product: product);
      if (!mounted) return;
      desktopSearch.clear();
      desktopSearchFocus.requestFocus();
    } finally {
      saleLookupBusy = false;
    }
  }

  Widget saleItemSearch(bool active, Color ink) => LayoutBuilder(
    builder: (context, box) => RawAutocomplete<Map<String, Object?>>(
      textEditingController: desktopSearch,
      focusNode: desktopSearchFocus,
      displayStringForOption: (p) => p['name'].toString(),
      optionsBuilder: (v) => CatalogSearch.matches(products, v.text),
      onSelected: (p) => unawaited(selectSaleSuggestion(p)),
      fieldViewBuilder: (_, controller, focus, submit) => TextField(
        key: const ValueKey('desktop-barcode-search'),
        controller: controller,
        focusNode: focus,
        enabled: active,
        onSubmitted: (_) {
          if (CatalogSearch.matches(products, controller.text).isNotEmpty) {
            submit();
          } else {
            unawaited(desktopScanCode(controller.text));
          }
        },
        decoration: InputDecoration(
          prefixIcon: Icon(Icons.view_week_rounded, color: ink),
          hintText: _t(
            'Search name / code / barcode',
            'အမည် / ကုဒ် / Barcode ရှာရန်',
          ),
        ),
      ),
      optionsViewBuilder: (context, onSelect, options) {
        final rows = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: box.maxWidth,
              height: (rows.length * 62.0).clamp(62.0, 310.0),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final p = rows[i];
                  final highlighted =
                      AutocompleteHighlightedOption.of(context) == i;
                  if (highlighted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (context.mounted) Scrollable.ensureVisible(context);
                    });
                  }
                  return ListTile(
                    key: ValueKey('sale-suggestion-${p['id']}'),
                    dense: true,
                    selected: highlighted,
                    title: Text(
                      p['name'].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${p['item_code'] ?? ''}  ·  ${p['barcode'] ?? ''}  ·  ${_money(p['price'] as int)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onSelect(p),
                  );
                },
              ),
            ),
          ),
        );
      },
    ),
  );
}
