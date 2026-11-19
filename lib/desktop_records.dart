part of 'desktop_ui.dart';

Widget desktopCellText(Object? value) {
  final text = value == null || '$value'.trim().isEmpty ? '—' : '$value';
  return Tooltip(message: text, child: Text(text));
}

Widget desktopMoney(Object? value, {String? currency, int? digits}) =>
    value is int
    ? Text(AppCurrency.format(value, currency: currency, decimalPlaces: digits))
    : const Text('—');
Widget desktopDate(Object? value) => Text(AppDateTime.format(value));
Widget desktopActive(Object? value) => Text(
  value == 1 ? _label('Active', 'အသုံးပြုဆဲ') : _label('Inactive', 'ရပ်ထားသည်'),
);

DesktopListTile? _recordTile(Widget widget) {
  if (widget is DesktopListTile) return widget;
  if (widget is Card && widget.child != null) return _recordTile(widget.child!);
  if (widget is Padding && widget.child != null) {
    return _recordTile(widget.child!);
  }
  if (widget is SizedBox && widget.child != null) {
    return _recordTile(widget.child!);
  }
  return null;
}

class DesktopNamedRecord extends StatelessWidget {
  const DesktopNamedRecord({
    super.key,
    required this.original,
    required this.cells,
    this.flexes,
  });
  final Widget original;
  final List<Widget> cells;
  final List<int>? flexes;
  bool _action(Widget w) =>
      w is IconButton ||
      w is PopupMenuButton ||
      w is ButtonStyleButton ||
      w is Checkbox ||
      (w is Wrap && w.children.any(_action)) ||
      w is Switch ||
      (w is Row && w.children.any(_action)) ||
      (w is Column && w.children.any(_action));
  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.windows) return original;
    final tile = _recordTile(original);
    if (tile == null) return original;
    var action = tile.trailing;
    if (action is Column) {
      action = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: action.crossAxisAlignment,
        children: action.children,
      );
    }
    if (action == null || !_action(action)) {
      action = tile.onTap == null
          ? const SizedBox.shrink()
          : const Icon(Icons.open_in_new, size: 16);
    }
    final color = original is Card
        ? (original as Card).color
        : tile.backgroundColor;
    final theme = Theme.of(context);
    return Material(
      color:
          color ??
          (tile.selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surface),
      child: InkWell(
        onTap: tile.enabled ? tile.onTap : null,
        child: Container(
          key: const ValueKey('desktop-named-record'),
          constraints: const BoxConstraints(minHeight: 40),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: .5),
              ),
            ),
          ),
          child: Row(
            children: [
              for (var i = 0; i < cells.length; i++)
                Expanded(
                  flex: flexes?[i] ?? 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: DefaultTextStyle(
                      style: theme.textTheme.bodySmall!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      child: cells[i],
                    ),
                  ),
                ),
              SizedBox(
                width: 160,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: action,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget desktopRecordHeader(
  BuildContext context,
  List<String> columns,
  List<int>? flexes,
) => Container(
  key: const ValueKey('desktop-record-heading'),
  height: 36,
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .5),
    border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
  ),
  child: Row(
    children: [
      for (var i = 0; i < columns.length; i++)
        Expanded(
          flex: flexes?[i] ?? 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              AppLanguage.text(columns[i]),
              style: Theme.of(context).textTheme.labelLarge,
              maxLines: 2,
            ),
          ),
        ),
      SizedBox(
        width: 160,
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Text(
            _label('Actions', 'လုပ်ဆောင်ချက်'),
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
      ),
    ],
  ),
);

/// Named spreadsheet for records embedded in an existing scrollable detail page.
class DesktopInlineTable extends StatelessWidget {
  const DesktopInlineTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.cells,
    this.flexes,
  });
  final List<String> columns;
  final List<Widget> rows;
  final List<List<Widget>> cells;
  final List<int>? flexes;
  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.windows) return Column(children: rows);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth > (columns.length * 120 + 160)
            ? box.maxWidth
            : (columns.length * 120 + 160).toDouble();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                desktopRecordHeader(context, columns, flexes),
                for (var i = 0; i < rows.length; i++)
                  DesktopNamedRecord(
                    original: rows[i],
                    cells: cells[i],
                    flexes: flexes,
                  ),
                if (rows.isEmpty)
                  const Padding(padding: EdgeInsets.all(24), child: Text('—')),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Bounded desktop editor: commands, metadata, spreadsheet, and payment footer.
class DesktopVoucherWorkspace extends StatelessWidget {
  const DesktopVoucherWorkspace({
    super.key,
    required this.commands,
    required this.metadata,
    required this.table,
    required this.footer,
    this.notice,
    this.entry,
  });
  final List<Widget> commands, metadata;
  final Widget table, footer;
  final Widget? notice, entry;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        Widget panel(Widget child, Color color) => Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: theme.dividerColor),
            borderRadius: BorderRadius.circular(7),
            boxShadow: const [
              BoxShadow(
                color: Color(0x140C2450),
                blurRadius: 5,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: child,
        );
        final top = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: commands,
            ),
            const SizedBox(height: 8),
            panel(
              LayoutBuilder(
                builder: (context, box) {
                  final columns = box.maxWidth >= 1100 && metadata.length >= 4
                      ? 4
                      : box.maxWidth >= 900
                      ? 3
                      : box.maxWidth >= 600
                      ? 2
                      : 1;
                  final width = (box.maxWidth - 12 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 10,
                    children: [
                      for (final field in metadata)
                        SizedBox(
                          width: width,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 38),
                            child: field,
                          ),
                        ),
                    ],
                  );
                },
              ),
              theme.colorScheme.primaryContainer.withValues(alpha: .16),
            ),
            if (entry != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: entry!),
            ?notice,
          ],
        );
        if (box.maxHeight < 600) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                top,
                SizedBox(height: 300, child: table),
                footer,
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
              const SizedBox(height: 10),
              Expanded(child: table),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: box.maxHeight * .31),
                child: SingleChildScrollView(
                  child: panel(
                    footer,
                    theme.brightness == Brightness.light
                        ? const Color(0xfffff9ed)
                        : const Color(0xff30343e),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
