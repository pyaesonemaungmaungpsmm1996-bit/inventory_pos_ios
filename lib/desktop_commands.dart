import 'desktop_ui.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_capabilities.dart';
import 'app_language.dart';

enum DesktopCommand {
  newVoucher,
  saveDraft,
  search,
  barcode,
  addItem,
  contact,
  focusRows,
  quantity,
  discount,
  paid,
  confirm,
  print,
  removeItem,
  previousRow,
  nextRow,
  editRow,
}

class DesktopCommandInfo {
  const DesktopCommandInfo(this.key, this.hint, this.en, this.my);
  final SingleActivator key;
  final String hint, en, my;
  String get label => AppLanguage.current.value == 'my' ? my : en;
}

const desktopCommandInfo = <DesktopCommand, DesktopCommandInfo>{
  DesktopCommand.newVoucher: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.keyN, control: true),
    'Ctrl+N',
    'New voucher / reset draft',
    'ဘောင်ချာအသစ် / Draft ပြန်စရန်',
  ),
  DesktopCommand.saveDraft: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.keyS, control: true),
    'Ctrl+S',
    'Save draft / unfinished work',
    'Draft / လက်စအလုပ် သိမ်းရန်',
  ),
  DesktopCommand.search: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.keyF, control: true),
    'Ctrl+F',
    'Focus search',
    'ရှာဖွေရန် အကွက်ကိုရွေးရန်',
  ),
  DesktopCommand.barcode: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.f2),
    'F2',
    'Scan / enter barcode',
    'Barcode Scan / ရိုက်ထည့်ရန်',
  ),
  DesktopCommand.addItem: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.f3),
    'F3',
    'Choose an item',
    'ပစ္စည်းရွေးရန်',
  ),
  DesktopCommand.contact: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.f4),
    'F4',
    'Choose customer / supplier',
    'Customer / Supplier ရွေးရန်',
  ),
  DesktopCommand.focusRows: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.f5),
    'F5',
    'Focus item rows, then use arrows / Enter',
    'ပစ္စည်းစာရင်းရွေးပြီး Arrow / Enter သုံးရန်',
  ),
  DesktopCommand.quantity: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.f6),
    'F6',
    'Edit selected item quantity',
    'ရွေးထားသောပစ္စည်း အရေအတွက်ပြင်ရန်',
  ),
  DesktopCommand.discount: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.f7),
    'F7',
    'Focus voucher discount',
    'ဘောင်ချာလျှော့ဈေး အကွက်ကိုရွေးရန်',
  ),
  DesktopCommand.paid: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.f8),
    'F8',
    'Focus first payment account',
    'ပထမငွေလက်ခံအကောင့်ကို ရွေးရန်',
  ),
  DesktopCommand.confirm: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.enter, control: true),
    'Ctrl+Enter',
    'Review / confirm transaction',
    'အချက်အလက်စစ်ပြီး အတည်ပြုရန်',
  ),
  DesktopCommand.print: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.keyP, control: true),
    'Ctrl+P',
    'Open print settings / PDF preview',
    'Print ဆက်တင် / PDF အကြိုကြည့်ရန်',
  ),
  DesktopCommand.removeItem: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.delete, control: true),
    'Ctrl+Delete',
    'Remove selected draft item (asks first)',
    'ရွေးထားသော Draft ပစ္စည်းကို မေးပြီးဖယ်ရန်',
  ),
  DesktopCommand.previousRow: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.arrowUp),
    '↑',
    'Previous item row',
    'ရှေ့ပစ္စည်းတစ်ကြောင်း ရွေးရန်',
  ),
  DesktopCommand.nextRow: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.arrowDown),
    '↓',
    'Next item row',
    'နောက်ပစ္စည်းတစ်ကြောင်း ရွေးရန်',
  ),
  DesktopCommand.editRow: DesktopCommandInfo(
    SingleActivator(LogicalKeyboardKey.enter),
    'Enter',
    'Edit selected item row',
    'ရွေးထားသောပစ္စည်းကို ပြင်ရန်',
  ),
};

// Ctrl-letter bindings keep working when a Myanmar keyboard layout is active.
bool desktopCommandMatches(DesktopCommand command, KeyEvent event) {
  if (desktopCommandInfo[command]!.key.accepts(
    event,
    HardwareKeyboard.instance,
  )) {
    return true;
  }
  const physical = {
    DesktopCommand.newVoucher: PhysicalKeyboardKey.keyN,
    DesktopCommand.saveDraft: PhysicalKeyboardKey.keyS,
    DesktopCommand.search: PhysicalKeyboardKey.keyF,
    DesktopCommand.print: PhysicalKeyboardKey.keyP,
  };
  final keyboard = HardwareKeyboard.instance;
  return physical[command] == event.physicalKey &&
      keyboard.isControlPressed &&
      !keyboard.isAltPressed &&
      !keyboard.isMetaPressed &&
      !keyboard.isShiftPressed;
}

String desktopHint(String text, DesktopCommand command) =>
    AppCapabilities.windows
    ? '$text · ${desktopCommandInfo[command]!.hint}'
    : text;

Future<void> desktopFocusInScroll(
  FocusNode node,
  ScrollController scroll,
) async {
  if (!scroll.hasClients) {
    node.requestFocus();
    return;
  }
  if (node.context == null) {
    scroll.jumpTo(0);
    await WidgetsBinding.instance.endOfFrame;
    for (var i = 0; node.context == null && scroll.hasClients && i < 200; i++) {
      final position = scroll.position;
      final next = (position.pixels + position.viewportDimension * .75).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if (next == position.pixels) break;
      scroll.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
    }
  }
  final context = node.context;
  if (context != null && context.mounted) {
    await Scrollable.ensureVisible(context, alignment: .5);
    node.requestFocus();
  }
}

Future<bool> desktopAsk(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c, false),
            child: Text(
              AppLanguage.current.value == 'my' ? 'မလုပ်တော့ပါ' : 'Cancel',
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              AppLanguage.current.value == 'my' ? 'အတည်ပြု' : 'Confirm',
            ),
          ),
        ],
      ),
    ) ==
    true;

/// Page-local, no repeat activation, and never active behind a modal route.
class DesktopCommandScope extends StatefulWidget {
  const DesktopCommandScope({
    super.key,
    required this.child,
    required this.commands,
    this.enabled = true,
    this.onEscape,
    this.extraHelp = '',
  });
  final Widget child;
  final Map<DesktopCommand, FutureOr<void> Function()> commands;
  final bool enabled;
  final String extraHelp;
  final FutureOr<void> Function()? onEscape;
  @override
  State<DesktopCommandScope> createState() => _DesktopCommandScopeState();
}

class _DesktopCommandScopeState extends State<DesktopCommandScope> {
  static final scopes = <_DesktopCommandScopeState>{};
  bool running = false;
  @override
  void initState() {
    super.initState();
    scopes.add(this);
    FocusManager.instance.addEarlyKeyEventHandler(handle);
  }

  @override
  void dispose() {
    scopes.remove(this);
    FocusManager.instance.removeEarlyKeyEventHandler(handle);
    super.dispose();
  }

  bool get editing {
    final c = FocusManager.instance.primaryFocus?.context;
    return c?.widget is EditableText ||
        c?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  Future<void> run(FutureOr<void> Function() fn) async {
    if (running || !widget.enabled) return;
    running = true;
    try {
      await fn();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              AppLanguage.current.value == 'my'
                  ? 'လုပ်ဆောင်မှု မပြီးပါ။ အချက်အလက်စစ်ပြီး ပြန်လုပ်ပါ။'
                  : 'Action did not complete. Check the page and retry.',
            ),
          ),
        );
      }
    } finally {
      running = false;
    }
  }

  Future<void> help() async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          AppLanguage.current.value == 'my'
              ? 'ဤစာမျက်နှာ၏ Keyboard Shortcut များ'
              : 'Keyboard shortcuts for this page',
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final command in widget.commands.keys)
                  DesktopListTile(
                    dense: true,
                    leading: Text(desktopCommandInfo[command]!.hint),
                    title: Text(desktopCommandInfo[command]!.label),
                  ),
                const Divider(),
                Text(
                  AppLanguage.current.value == 'my'
                      ? 'Tab / Shift+Tab ဖြင့် အကွက်ပြောင်းပါ။ Dialog ကို Esc ဖြင့်ပိတ်ပါ။ စာရိုက်နေချိန် Arrow / Enter / Ctrl+Delete သည် စာသားပြင်ရန်သာဖြစ်သည်။'
                      : 'Tab / Shift+Tab moves between controls. Esc closes a dialog. Arrow / Enter / Ctrl+Delete keep their text-editing meaning inside a text box.',
                ),
                if (widget.extraHelp.isNotEmpty) Text(widget.extraHelp),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(c),
            child: Text(
              AppLanguage.current.value == 'my' ? 'ပိတ်ရန်' : 'Close',
            ),
          ),
        ],
      ),
    );
  }

  KeyEventResult handle(KeyEvent event) {
    if (!AppCapabilities.windows) return KeyEventResult.ignored;
    for (final scope in scopes) {
      if (identical(scope, this) ||
          !scope.mounted ||
          ModalRoute.of(scope.context)?.isCurrent != true) {
        continue;
      }
      var descendant = false;
      scope.context.visitAncestorElements((element) {
        if (identical(element, context)) {
          descendant = true;
          return false;
        }
        return true;
      });
      if (descendant) return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent || ModalRoute.of(context)?.isCurrent != true) {
      return KeyEventResult.ignored;
    }
    if (const SingleActivator(LogicalKeyboardKey.f1)
        .accepts(event, HardwareKeyboard.instance)) {
      if (!running) unawaited(run(help));
      return KeyEventResult.handled;
    }
    if (!widget.enabled || running) return KeyEventResult.ignored;
    if (const SingleActivator(LogicalKeyboardKey.escape)
        .accepts(event, HardwareKeyboard.instance)) {
      unawaited(run(widget.onEscape ?? () => Navigator.of(context).maybePop()));
      return KeyEventResult.handled;
    }
    for (final entry in widget.commands.entries) {
      if (!desktopCommandMatches(entry.key, event)) continue;
      if (editing &&
          const {
            DesktopCommand.previousRow,
            DesktopCommand.nextRow,
            DesktopCommand.editRow,
            DesktopCommand.removeItem,
          }.contains(entry.key)) {
        return KeyEventResult.ignored;
      }
      unawaited(run(entry.value));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => !AppCapabilities.windows
      ? widget.child
      : Focus(autofocus: true, child: widget.child);
}
