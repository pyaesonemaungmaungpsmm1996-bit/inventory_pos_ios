import 'package:flutter/material.dart';

import 'app_capabilities.dart';
import 'app_language.dart';
import 'app_currency.dart';
import 'app_datetime.dart';
part 'desktop_forms.dart';
part 'desktop_records.dart';

String _label(String en, String my) =>
    AppLanguage.current.value == 'my' ? my : en;

/// Desktop presentation only: callbacks, field controllers and validators remain
/// owned by their original pages. Android builds the original Material widgets.
class DesktopScaffold extends StatelessWidget {
  const DesktopScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });
  final PreferredSizeWidget? appBar;
  final Widget? body, floatingActionButton, bottomNavigationBar;
  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.windows) {
      return Scaffold(
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      );
    }
    final fab = floatingActionButton;
    final action = fab is FloatingActionButton ? fab : null;
    return Scaffold(
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
      body: Column(
        children: [
          if (action != null)
            Container(
              key: const ValueKey('desktop-action-toolbar'),
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  const Spacer(),
                  FilledButton(
                    onPressed: action.onPressed,
                    child: IconTheme(
                      data: const IconThemeData(size: 18),
                      child: action.child is Icon
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                action.child!,
                                const SizedBox(width: 6),
                                Text(action.tooltip ?? _label('New', 'အသစ်')),
                              ],
                            )
                          : action.child ?? Text(_label('New', 'အသစ်')),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: DesktopBodyFrame(child: body ?? const SizedBox.shrink()),
          ),
          if (fab != null && action == null)
            Padding(padding: const EdgeInsets.all(8), child: fab),
        ],
      ),
    );
  }
}

class DesktopBodyFrame extends StatelessWidget {
  const DesktopBodyFrame({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.windows || child is! Column) return child;
    final column = child as Column;
    return LayoutBuilder(
      builder: (context, box) => Column(
        mainAxisAlignment: column.mainAxisAlignment,
        mainAxisSize: column.mainAxisSize,
        crossAxisAlignment: column.crossAxisAlignment,
        textDirection: column.textDirection,
        verticalDirection: column.verticalDirection,
        textBaseline: column.textBaseline,
        children: DesktopListView._fields(column.children, box.maxWidth),
      ),
    );
  }
}

class DesktopListTile extends StatelessWidget {
  const DesktopListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.contentPadding,
    this.dense,
    this.enabled = true,
    this.selected = false,
    this.isThreeLine = false,
    this.backgroundColor,
  });
  final Color? backgroundColor;
  final Widget? leading, title, subtitle, trailing;
  final GestureTapCallback? onTap;
  final EdgeInsetsGeometry? contentPadding;
  final bool? dense;
  final bool enabled, selected, isThreeLine;
  ListTile get native => ListTile(
    leading: leading,
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    onTap: onTap,
    contentPadding: contentPadding,
    dense: dense,
    enabled: enabled,
    selected: selected,
    isThreeLine: isThreeLine,
  );
  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.windows) return native;
    return LayoutBuilder(
      builder: (context, box) {
        if (!box.hasBoundedWidth || box.maxWidth < 620) return native;
        final theme = Theme.of(context);
        return Material(
          color:
              backgroundColor ??
              (selected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surface),
          child: Semantics(
            selected: selected,
            enabled: enabled,
            child: InkWell(
              onTap: enabled ? onTap : null,
              child: Container(
                key: const ValueKey('desktop-record-row'),
                constraints: const BoxConstraints(minHeight: 42),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: theme.dividerColor)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (leading != null) ...[
                      SizedBox(
                        width: 34,
                        height: 32,
                        child: Center(child: leading),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 4,
                      child: DefaultTextStyle(
                        style: theme.textTheme.bodyMedium!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        child: title ?? const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 5,
                      child: DefaultTextStyle(
                        style: theme.textTheme.bodySmall!,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        child: subtitle ?? const SizedBox.shrink(),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing ?? const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class DesktopListView extends StatelessWidget {
  DesktopListView({
    super.key,
    ScrollController? controller,
    EdgeInsetsGeometry? padding,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    List<Widget> children = const [],
  }) : namedColumns = null,
       namedFlexes = null,
       recordCount = null,
       native = ListView(
         controller: controller,
         padding: padding,
         physics: physics,
         shrinkWrap: shrinkWrap,
         children: children,
       );
  DesktopListView.builder({
    super.key,
    ScrollController? controller,
    EdgeInsetsGeometry? padding,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    List<String>? desktopColumns,
    List<int>? desktopFlexes,
    List<Widget> Function(BuildContext, int)? desktopCells,
  }) : namedColumns = desktopColumns,
       namedFlexes = desktopFlexes,
       recordCount = itemCount,
       native = ListView.builder(
         controller: controller,
         padding: padding,
         physics: physics,
         shrinkWrap: shrinkWrap,
         itemCount: itemCount,
         itemBuilder: (context, index) =>
             desktopCells != null && AppCapabilities.windows
             ? DesktopNamedRecord(
                 original: itemBuilder(context, index),
                 cells: desktopCells(context, index),
                 flexes: desktopFlexes,
               )
             : _record(itemBuilder(context, index)),
       );
  DesktopListView.separated({
    super.key,
    ScrollController? controller,
    EdgeInsetsGeometry? padding,
    ScrollPhysics? physics,
    bool shrinkWrap = false,
    required int itemCount,
    required IndexedWidgetBuilder itemBuilder,
    required IndexedWidgetBuilder separatorBuilder,
    List<String>? desktopColumns,
    List<int>? desktopFlexes,
    List<Widget> Function(BuildContext, int)? desktopCells,
  }) : namedColumns = desktopColumns,
       namedFlexes = desktopFlexes,
       recordCount = itemCount,
       native = ListView.separated(
         controller: controller,
         padding: padding,
         physics: physics,
         shrinkWrap: shrinkWrap,
         itemCount: itemCount,
         itemBuilder: (context, index) =>
             desktopCells != null && AppCapabilities.windows
             ? DesktopNamedRecord(
                 original: itemBuilder(context, index),
                 cells: desktopCells(context, index),
                 flexes: desktopFlexes,
               )
             : _record(itemBuilder(context, index)),
         separatorBuilder: separatorBuilder,
       );
  final ListView native;
  final int? recordCount;
  final List<String>? namedColumns;
  final List<int>? namedFlexes;
  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.windows) return native;
    return LayoutBuilder(
      builder: (context, box) {
        final delegate = native.childrenDelegate;
        final staticChildren = delegate is SliverChildListDelegate
            ? delegate.children
            : null;
        final children = staticChildren == null
            ? null
            : _fields(staticChildren.map(_record).toList(), box.maxWidth);
        final scroll = ListView.custom(
          controller: native.controller,
          primary: native.primary,
          physics: native.physics,
          shrinkWrap: native.shrinkWrap,
          childrenDelegate: children == null
              ? delegate
              : SliverChildListDelegate(children),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        );
        final count = recordCount;
        if (namedColumns != null &&
            box.hasBoundedHeight &&
            !native.shrinkWrap) {
          final width = box.maxWidth < (namedColumns!.length * 130 + 110)
              ? (namedColumns!.length * 130 + 110).toDouble()
              : box.maxWidth;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  desktopRecordHeader(context, namedColumns!, namedFlexes),
                  Expanded(child: scroll),
                  Container(
                    height: 28,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      '${_label('Rows', 'အကြောင်းရေ')}: ${count ?? 0}',
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        if (staticChildren != null ||
            native.shrinkWrap ||
            !box.hasBoundedHeight ||
            box.maxWidth < 620) {
          return scroll;
        }
        return Column(
          children: [
            Container(
              key: const ValueKey('desktop-record-heading'),
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: .45),
                border: Border(
                  bottom: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      _label('Record', 'မှတ်တမ်း'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: Text(
                      _label('Details', 'အသေးစိတ်'),
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: Text(
                      _label('Actions / Amount', 'လုပ်ဆောင်ချက် / ပမာဏ'),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: scroll),
            if (count != null)
              Container(
                height: 28,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  '${_label('Rows', 'အကြောင်းရေ')}: $count',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        );
      },
    );
  }

  static Widget _record(Widget widget) {
    if (!AppCapabilities.windows) return widget;
    if (widget is Card && widget.child is DesktopListTile) {
      final tile = widget.child! as DesktopListTile;
      return DesktopListTile(
        key: widget.key,
        leading: tile.leading,
        title: tile.title,
        subtitle: tile.subtitle,
        trailing: tile.trailing,
        onTap: tile.onTap,
        contentPadding: tile.contentPadding,
        dense: tile.dense,
        enabled: tile.enabled,
        selected: tile.selected,
        isThreeLine: tile.isThreeLine,
        backgroundColor: widget.color,
      );
    }
    return widget;
  }

  static List<Widget> _fields(
    List<Widget> children,
    double width, {
    double formBreakpoint = 850,
  }) {
    final output = <Widget>[], fields = <Widget>[], buttons = <Widget>[];
    void flushButtons() {
      if (buttons.isEmpty) return;
      output.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(spacing: 8, runSpacing: 8, children: List.of(buttons)),
        ),
      );
      buttons.clear();
    }

    void flush() {
      if (fields.isEmpty) return;
      output.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              for (final field in fields)
                SizedBox(
                  width: width >= formBreakpoint
                      ? (width - 40) / 2
                      : width - 24,
                  child: field,
                ),
            ],
          ),
        ),
      );
      fields.clear();
    }

    for (final child in children) {
      bool isField(Widget w) =>
          w is TextField ||
          w is TextFormField ||
          w is DropdownButtonFormField ||
          w is DropdownButton ||
          w is SwitchListTile ||
          w is CheckboxListTile ||
          (w is Padding && w.child != null && isField(w.child!));
      final field = isField(child);
      bool isButton(Widget w) =>
          w is ButtonStyleButton ||
          (w is Padding && w.child != null && isButton(w.child!));
      if (field) {
        flushButtons();
        fields.add(DesktopDialog._transform(child));
      } else if (isButton(child)) {
        flush();
        buttons.add(child);
      } else if ((fields.isNotEmpty || buttons.isNotEmpty) &&
          child is SizedBox &&
          child.child == null) {
        continue;
      } else {
        flush();
        flushButtons();
        output.add(
          DesktopDialog._hasFields(child)
              ? DesktopDialog._transform(child)
              : child,
        );
      }
    }
    flush();
    flushButtons();
    return output;
  }
}

Future<T?> showDesktopSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  if (!AppCapabilities.windows) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
    );
  }
  return showDialog<T>(
    context: context,
    builder: (dialog) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 740,
          maxHeight: MediaQuery.sizeOf(dialog).height * .88,
        ),
        child: builder(dialog),
      ),
    ),
  );
}

class DesktopModuleLink extends StatelessWidget {
  const DesktopModuleLink({
    super.key,
    required this.id,
    required this.title,
    required this.icon,
    this.subtitle,
    this.onTap,
  });
  final String id, title;
  final IconData icon;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 19),
    label: Text(AppLanguage.text(title)),
  );
}

class DesktopGrid extends StatelessWidget {
  const DesktopGrid({
    super.key,
    required this.columns,
    required this.rows,
    this.flexes,
    this.onRowTap,
    this.minWidth = 900,
    this.emptyText,
  });
  final List<String> columns;
  final List<List<Widget>> rows;
  final List<int>? flexes;
  final void Function(int)? onRowTap;
  final double minWidth;
  final String? emptyText;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = box.maxWidth < minWidth ? minWidth : box.maxWidth;
      final theme = Theme.of(context);
      Widget cells(List<Widget> content, {bool heading = false}) => Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            Expanded(
              flex: flexes?[i] ?? 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                child: DefaultTextStyle(
                  style: (heading
                      ? theme.textTheme.labelLarge
                      : theme.textTheme.bodySmall)!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  child: content[i],
                ),
              ),
            ),
        ],
      );
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: width,
                child: Column(
                  children: [
                    Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(
                          alpha: .5,
                        ),
                        border: Border(
                          bottom: BorderSide(color: theme.dividerColor),
                        ),
                      ),
                      child: cells(
                        columns.map((s) => Text(s)).toList(),
                        heading: true,
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? Center(
                              child: Text(
                                emptyText ??
                                    _label(
                                      'No matching records',
                                      'ကိုက်ညီသော မှတ်တမ်းမရှိပါ',
                                    ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: rows.length,
                              itemBuilder: (context, index) => Material(
                                color: index.isEven
                                    ? theme.colorScheme.surface
                                    : theme.scaffoldBackgroundColor,
                                child: InkWell(
                                  onTap: onRowTap == null
                                      ? null
                                      : () => onRowTap!(index),
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 40,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: theme.dividerColor.withValues(
                                            alpha: .6,
                                          ),
                                        ),
                                      ),
                                    ),
                                    child: cells(rows[index]),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            height: 28,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${_label('Rows', 'အကြောင်းရေ')}: ${rows.length}',
              style: theme.textTheme.labelSmall,
            ),
          ),
        ],
      );
    },
  );
}

List<DesktopModuleLink> desktopLinks(Widget widget) {
  if (widget is DesktopModuleLink) return [widget];
  if (widget is ListView &&
      widget.childrenDelegate is SliverChildListDelegate) {
    return [
      for (final child
          in (widget.childrenDelegate as SliverChildListDelegate).children)
        ...desktopLinks(child),
    ];
  }
  if (widget is DesktopListView) return desktopLinks(widget.native);
  if (widget is Column) {
    return [for (final child in widget.children) ...desktopLinks(child)];
  }
  if (widget is Card && widget.child != null) {
    return desktopLinks(widget.child!);
  }
  if (widget is Padding) {
    return desktopLinks(widget.child ?? const SizedBox.shrink());
  }
  return [];
}

class DesktopModuleHub extends StatefulWidget {
  const DesktopModuleHub({
    super.key,
    required this.title,
    required this.entries,
    required this.onOpen,
    this.account,
  });
  final String title;
  final List<DesktopModuleLink> entries;
  final void Function(DesktopModuleLink) onOpen;
  final Widget? account;
  @override
  State<DesktopModuleHub> createState() => _DesktopModuleHubState();
}

class _DesktopModuleHubState extends State<DesktopModuleHub> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final entries = widget.entries
        .where(
          (e) => '${AppLanguage.text(e.title)} ${e.subtitle ?? ''}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.title == 'Settings')
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Text(
              AppLanguage.text('Business & app settings'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('module-search-${widget.title}'),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: _label(
                      'Find a command or setting',
                      'လုပ်ဆောင်ချက် သို့မဟုတ် Setting ရှာရန်',
                    ),
                  ),
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              const SizedBox(width: 12),
              Text('${entries.length} ${_label('commands', 'လုပ်ဆောင်ချက်')}'),
            ],
          ),
        ),
        if (widget.account != null)
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: widget.account!,
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final entry in entries)
                    SizedBox(
                      width: box.maxWidth >= 900
                          ? (box.maxWidth - 48) / 3
                          : box.maxWidth >= 580
                          ? (box.maxWidth - 36) / 2
                          : box.maxWidth - 24,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                          side: BorderSide(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: InkWell(
                          onTap: entry.onTap == null
                              ? null
                              : () => widget.onOpen(entry),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      entry.icon,
                                      size: 22,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        AppLanguage.text(entry.title),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall,
                                      ),
                                    ),
                                    const Icon(Icons.open_in_new, size: 15),
                                  ],
                                ),
                                if (entry.subtitle != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    AppLanguage.text(entry.subtitle!),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
