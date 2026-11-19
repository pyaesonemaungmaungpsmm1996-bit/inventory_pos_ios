import 'package:flutter/material.dart';

import 'app_database.dart';
import 'app_language.dart';
import 'brand_logo.dart';
import 'pos_navigation_bar.dart';
import 'desktop_ui.dart';

String desktopText(String en, String my) =>
    AppLanguage.current.value == 'my' ? my : en;

class DesktopWorkspaceNavigation extends ChangeNotifier {
  int selected = 0, selectedSale = 0;
  int? branchId;
  String? selectedEntry;
  Map<int, List<DesktopModuleLink>> sections = {};
  Future<void> Function(int, DesktopModuleLink)? onModuleAction;
  Future<void> Function(int)? onSelected, onSaleAction;
  VoidCallback? onGuide;
  void refresh() => notifyListeners();
}

final desktopWorkspaceNavigation = DesktopWorkspaceNavigation();

class DesktopWorkspace extends StatefulWidget {
  const DesktopWorkspace({super.key, required this.child});
  final Widget child;
  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

class _DesktopWorkspaceState extends State<DesktopWorkspace> {
  String business = '';
  List<Map<String, Object?>> branches = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final profile = await AppDatabase.instance.getBusinessProfile();
      final rows = await AppDatabase.instance.getBranches();
      if (mounted) {
        setState(() {
          business = '${profile['name'] ?? ''}';
          branches = rows;
        });
      }
    } catch (_) {
      /* Pages retain their existing database retry actions. */
    }
  }

  static const accents = [
    Color(0xFF1680DF),
    Color(0xFF008E78),
    Color(0xFF5145CE),
    Color(0xFFD27B12),
    Color(0xFF0876BE),
    Color(0xFF1679C8),
  ];
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: desktopWorkspaceNavigation,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final nav = desktopWorkspaceNavigation,
            dark = Theme.of(context).brightness == Brightness.dark;
        final width = (box.maxWidth * .14).clamp(200.0, 224.0);
        final compact = width < 220;
        final ink = dark ? const Color(0xFFF2F6FF) : const Color(0xFF12264C);
        final border = dark ? const Color(0xFF7C8C9F) : const Color(0xFFBFD1E8);
        final size = 14.0;
        String label(int i) => AppLanguage.current.value == 'my'
            ? PosNavigationBar.myLabels[i]
            : PosNavigationBar.labels[i];
        Widget cardButton(
          Widget child, {
          VoidCallback? onTap,
          bool selected = false,
          bool logo = false,
        }) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: logo
                  ? (dark
                        ? const [Color(0xFF28544D), Color(0xFF1F4646)]
                        : const [Color(0xFFF6FFFB), Color(0xFFDBFAEF)])
                  : selected
                  ? const [Color(0xFF05A48C), Color(0xFF007E73)]
                  : (dark
                        ? const [Color(0xFF44566C), Color(0xFF334355)]
                        : const [Colors.white, Color(0xFFF8FCFF)]),
            ),
            border: logo
                ? null
                : Border.all(
                    color: selected ? const Color(0xFF54D4B4) : border,
                  ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.16 : 0.07),
                offset: const Offset(0, 2),
                blurRadius: 3,
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: onTap,
              child: child,
            ),
          ),
        );
        Widget button(int i) => KeyedSubtree(
          key: ValueKey('desktop-menu-$i'),
          child: Tooltip(
            message: '${label(i)}  Ctrl+${i + 1}',
            child: cardButton(
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 9 : 13,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: nav.selected == i
                            ? Colors.white.withValues(alpha: .11)
                            : accents[i].withValues(alpha: dark ? 0.25 : 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        i == 1
                            ? Icons.shopping_cart_outlined
                            : i == 2
                            ? Icons.inventory_2_outlined
                            : PosNavigationBar.icons[i],
                        size: 21,
                        color: nav.selected == i
                            ? Colors.white
                            : dark
                            ? Color.lerp(accents[i], Colors.white, .3)
                            : accents[i],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label(i),
                        style: TextStyle(
                          color: nav.selected == i ? Colors.white : ink,
                          fontWeight: FontWeight.w600,
                          fontSize: size,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              selected: nav.selected == i,
              onTap: nav.onSelected == null ? null : () => nav.onSelected!(i),
            ),
          ),
        );
        Widget sub(int i, int module) {
          final entries = nav.sections[module] ?? [];
          final entry = i < entries.length ? entries[i] : null;
          final active = entry == null
              ? nav.selectedSale == i
              : nav.selectedEntry == entry.id ||
                    (module == 1 &&
                        nav.selectedEntry == null &&
                        nav.selectedSale == i);
          final text = AppLanguage.text(
            entry?.title ??
                [
                  'New Sale',
                  'Sale Invoice',
                  'Sale Return',
                  'Customer Payments',
                ][i],
          );
          return Padding(
            padding: const EdgeInsets.fromLTRB(25, 3, 12, 3),
            child: Material(
              color: active
                  ? (dark ? const Color(0xFF44806D) : const Color(0xFFD3F9EA))
                  : (dark ? const Color(0xFF35475D) : const Color(0xFFFAFDFF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
                side: BorderSide(
                  color: active ? const Color(0xFF7CD8B9) : border,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: entry != null
                    ? (nav.onModuleAction == null
                          ? null
                          : () => nav.onModuleAction!(module, entry))
                    : nav.onSaleAction == null
                    ? null
                    : () => nav.onSaleAction!(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        active ? Icons.circle : Icons.radio_button_unchecked,
                        size: 14,
                        color: dark
                            ? const Color(0xFFB9F9D8)
                            : active
                            ? const Color(0xFF008A74)
                            : const Color(0xFF6A82A9),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          text,
                          style: TextStyle(
                            color: active && !dark
                                ? const Color(0xFF007F69)
                                : ink,
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        var branchName = '';
        for (final row in branches) {
          if (row['id'] == nav.branchId) branchName = '${row['name']}';
        }
        return Material(
          child: Row(
            children: [
              Container(
                key: const ValueKey('desktop-sidebar'),
                width: width,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: dark
                        ? const [Color(0xFF1F3442), Color(0xFF152231)]
                        : const [Color(0xFFFAFDFF), Color(0xFFE7F3FA)],
                  ),
                  border: Border(
                    right: BorderSide(
                      color: dark
                          ? const Color(0xFF394B61)
                          : const Color(0xFFC6D8E8),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      cardButton(
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact ? 9 : 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44.0,
                                height: 44.0,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: .09,
                                      ),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: FittedBox(child: const BrandLogo()),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Text(
                                  'TP POS',
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        logo: true,
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (var i = 0; i < 6; i++) ...[
                                button(i),
                                if (nav.selected == i)
                                  for (
                                    var j = 0;
                                    j <
                                        ((nav.sections[i]?.length ?? 0) > 0
                                            ? nav.sections[i]!.length
                                            : i == 1
                                            ? 3
                                            : 0);
                                    j++
                                  )
                                    sub(j, i),
                              ],
                            ],
                          ),
                        ),
                      ),
                      cardButton(
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD5EAFF)
                                      .withValues(alpha: dark ? 0.15 : 1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.help_outline_rounded,
                                  color: Color(0xFF1689E9),
                                  size: 21,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  AppLanguage.text('User Guide'),
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: size,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        onTap: nav.onGuide,
                      ),
                      if (business.isNotEmpty)
                        cardButton(
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.storefront_outlined,
                                  color: dark
                                      ? const Color(0xFF9CCFFF)
                                      : const Color(0xFF057FCA),
                                  size: 24,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        business,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: ink,
                                          fontSize: size,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (branchName.isNotEmpty)
                                        Text(
                                          branchName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: dark
                                                ? const Color(0xFFBCD1EF)
                                                : const Color(0xFF54739B),
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: dark
                          ? const [Color(0xFF26364B), Color(0xFF172638)]
                          : const [Color(0xFFF2F8FE), Color(0xFFEAF5FC)],
                    ),
                  ),
                  child: widget.child,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class DesktopSection extends StatelessWidget {
  const DesktopSection({
    super.key,
    required this.child,
    this.tone = 0,
    this.title,
    this.icon,
  });
  final Widget child;
  final int tone;
  final String? title;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [if (title != null) Text(title!), child],
      ),
    ),
  );
}
