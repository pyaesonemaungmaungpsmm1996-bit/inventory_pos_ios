part of 'desktop_ui.dart';

/// A Windows dialog is a bounded property editor. The original Form key,
/// controllers, validators, actions and modal route are retained.
class DesktopDialog extends StatelessWidget {
  const DesktopDialog({super.key, this.title, this.content, this.actions});
  final Widget? title, content;
  final List<Widget>? actions;
  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.windows) {
      return AlertDialog(title: title, content: content, actions: actions);
    }
    final wide = content != null && _hasFields(content!);
    final available = MediaQuery.sizeOf(context).width - 80;
    final width = (wide ? 840.0 : 560.0).clamp(
      280.0,
      available < 280 ? 280 : available,
    );
    return AlertDialog(
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          gradient: LinearGradient(
            colors: Theme.of(context).brightness == Brightness.dark
                ? const [Color(0xFF293E5D), Color(0xFF22344A)]
                : const [Color(0xFFE4ECFF), Color(0xFFF0FAFF)],
          ),
        ),
        child: title,
      ),
      titleTextStyle: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      titlePadding: EdgeInsets.zero,
      content: content == null
          ? null
          : SizedBox(width: width.toDouble(), child: _transform(content!)),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      actions: actions,
      actionsAlignment: MainAxisAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
    );
  }

  static bool _hasFields(Widget w) {
    if (w is Form ||
        w is TextField ||
        w is TextFormField ||
        w is DropdownButtonFormField ||
        w is StatefulBuilder) {
      return true;
    }
    if (w is Card && w.child != null) return _hasFields(w.child!);
    if (w is SizedBox && w.child != null) return _hasFields(w.child!);
    if (w is Padding && w.child != null) return _hasFields(w.child!);
    if (w is SingleChildScrollView && w.child != null) {
      return _hasFields(w.child!);
    }
    if (w is Column) return w.children.any(_hasFields);
    return false;
  }

  static Widget _transform(Widget w) {
    if (w is StatefulBuilder) {
      return StatefulBuilder(
        key: w.key,
        builder: (context, setState) =>
            _transform(w.builder(context, setState)),
      );
    }
    if (w is Card && w.child != null && _hasFields(w.child!)) {
      return Card(
        key: w.key,
        color: w.color,
        elevation: w.elevation,
        shape: w.shape,
        margin: w.margin,
        child: _transform(w.child!),
      );
    }
    if (w is SwitchListTile) {
      return _DesktopToggle(
        key: w.key,
        title: w.title,
        subtitle: w.subtitle,
        value: w.value,
        onChanged: w.onChanged == null ? null : (v) => w.onChanged!(v ?? false),
      );
    }
    if (w is CheckboxListTile) {
      return _DesktopToggle(
        key: w.key,
        title: w.title,
        subtitle: w.subtitle,
        value: w.value,
        onChanged: w.onChanged,
        tristate: w.tristate,
      );
    }
    if (w is Form) {
      return Form(
        key: w.key,
        canPop: w.canPop,
        onPopInvokedWithResult: w.onPopInvokedWithResult,
        onChanged: w.onChanged,
        autovalidateMode: w.autovalidateMode,
        child: _transform(w.child),
      );
    }
    if (w is SizedBox && w.child != null) {
      return SizedBox(
        key: w.key,
        height: w.height,
        child: _transform(w.child!),
      );
    }
    if (w is Padding) {
      return Padding(
        key: w.key,
        padding: w.padding,
        child: w.child == null ? null : _transform(w.child!),
      );
    }
    if (w is SingleChildScrollView) {
      return SingleChildScrollView(
        key: w.key,
        controller: w.controller,
        scrollDirection: w.scrollDirection,
        reverse: w.reverse,
        primary: w.primary,
        physics: w.physics,
        padding: w.padding,
        keyboardDismissBehavior: w.keyboardDismissBehavior,
        child: w.child == null ? null : _transform(w.child!),
      );
    }
    if (w is Column &&
        !w.children.any((child) => child is Expanded || child is Flexible)) {
      return DesktopPropertyFields(
        key: w.key,
        children: w.children.map(_transform).toList(),
      );
    }
    return w;
  }
}

class DesktopPropertyFields extends StatelessWidget {
  const DesktopPropertyFields({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => !AppCapabilities.windows
      ? Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        )
      : LayoutBuilder(
          builder: (context, box) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: DesktopListView._fields(
              children,
              box.maxWidth,
              formBreakpoint: 620,
            ),
          ),
        );
}

class _DesktopToggle extends StatelessWidget {
  const _DesktopToggle({
    super.key,
    this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.tristate = false,
  });
  final Widget? title, subtitle;
  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final bool tristate;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 34),
    child: Row(
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          tristate: tristate,
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ?title,
              if (subtitle != null)
                DefaultTextStyle(
                  style: Theme.of(context).textTheme.bodySmall!,
                  child: subtitle!,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Persistent property sections on desktop; native expansion tiles on mobile.
class DesktopSection extends StatefulWidget {
  const DesktopSection({
    super.key,
    required this.title,
    this.subtitle,
    this.children = const [],
    this.initiallyExpanded,
    this.tilePadding,
  });
  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;
  final bool? initiallyExpanded;
  final EdgeInsetsGeometry? tilePadding;
  @override
  State<DesktopSection> createState() => _DesktopSectionState();
}

class _DesktopSectionState extends State<DesktopSection> {
  late bool open;
  @override
  void initState() {
    super.initState();
    open = widget.initiallyExpanded ?? true;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.windows) {
      return ExpansionTile(
        key: widget.key,
        title: widget.title,
        subtitle: widget.subtitle,
        initiallyExpanded: widget.initiallyExpanded ?? false,
        tilePadding: widget.tilePadding,
        children: widget.children,
      );
    }
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('desktop-property-section'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: theme.brightness == Brightness.dark
                ? const Color(0xFF293E5D)
                : const Color(0xFFE9F1FC),
            child: InkWell(
              onTap: () => setState(() => open = !open),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: DefaultTextStyle(
                        style: theme.textTheme.titleSmall!,
                        child: widget.title,
                      ),
                    ),
                    if (widget.subtitle != null)
                      Flexible(
                        child: DefaultTextStyle(
                          style: theme.textTheme.bodySmall!,
                          child: widget.subtitle!,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      open
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.all(12),
              child: DesktopPropertyFields(children: widget.children),
            ),
        ],
      ),
    );
  }
}
