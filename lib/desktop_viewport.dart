import 'package:flutter/material.dart';

/// Let the desktop workspace use a wide screen without stretching beyond a large monitor.
class DesktopViewport extends StatelessWidget {
  const DesktopViewport({super.key, required this.child});
  final Widget child;
  static const maxWidth = 2560.0;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxWidth),
        child: SizedBox.expand(child: child),
      ),
    ),
  );
}
