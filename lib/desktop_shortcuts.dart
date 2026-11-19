import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_capabilities.dart';
import 'desktop_commands.dart';
import 'app_language.dart';

class DesktopHomeShortcuts extends StatelessWidget {
  const DesktopHomeShortcuts({
    super.key,
    required this.child,
    required this.onSelected,
    this.onNewSale,
  });
  final Widget child;
  final ValueChanged<int> onSelected;
  final VoidCallback? onNewSale;
  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.windows) return child;
    const keys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ];
    void whenHome(VoidCallback work) {
      if (ModalRoute.of(context)?.isCurrent == true) work();
    }

    final commands = <DesktopCommand, VoidCallback>{};
    final newSale = onNewSale;
    if (newSale != null) commands[DesktopCommand.newVoucher] = newSale;
    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < keys.length; i++)
          SingleActivator(keys[i], control: true): () =>
              whenHome(() => onSelected(i)),
      },
      child: DesktopCommandScope(
        commands: commands,
        extraHelp: AppLanguage.current.value == 'my'
            ? 'ပင်မစာမျက်နှာတွင် Ctrl+1 မှ Ctrl+6 ဖြင့် Menu ပြောင်းပါ။ အခြားစာမျက်နှာမှ Esc ဖြင့် မူလနေရာပြန်ပါ။'
            : 'Ctrl+1 through Ctrl+6 selects the six home menus. Use Esc to leave the current page safely before switching menus.',
        child: child,
      ),
    );
  }
}
