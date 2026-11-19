import 'dart:async';

import 'package:flutter/material.dart';

/// Tracks the inner workspace navigator; the sidebar lives outside that route
/// stack. A sidebar click waits for existing leave guards before opening a page.
class DesktopRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];
  Route<dynamic>? get current => _routes.isEmpty ? null : _routes.last;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute == null) _routes.clear();
    _routes.remove(route);
    _routes.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i >= 0) {
      if (newRoute == null) {
        _routes.removeAt(i);
      } else {
        _routes[i] = newRoute;
      }
    } else if (newRoute != null) {
      _routes.add(newRoute);
    }
  }

  Future<bool> returnTo(Route<dynamic> target) async {
    if (popup != null) return false;
    for (var attempt = 0; attempt < 20 && current != target; attempt++) {
      final before = current;
      if (before == null) return false;
      var popped = false;
      unawaited(before.popped.then((_) => popped = true));
      final handled = await navigator!.maybePop();
      if (!handled) return false;
      await Future<void>.delayed(Duration.zero);
      if (popup != null) {
        final answer = await popup!.popped;
        if (answer == null ||
            answer == false ||
            const ['stay', 'continue', 'cancel', 'edit'].contains(answer)) {
          return false;
        }
        // The editor can flush its local recovery write after the leave choice.
        try {
          await before.popped.timeout(const Duration(seconds: 10));
        } on TimeoutException {
          return false;
        }
      } else if (!popped && current == before) {
        // PopScope may schedule its leave dialog for the next frame.
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(Duration.zero);
        if (popup != null) {
          final answer = await popup!.popped;
          if (answer == null ||
              answer == false ||
              const ['stay', 'continue', 'cancel', 'edit'].contains(answer)) {
            return false;
          }
          try {
            await before.popped.timeout(const Duration(seconds: 10));
          } on TimeoutException {
            return false;
          }
        } else if (current == before) {
          return false;
        }
      }
    }
    return current == target;
  }

  Route<dynamic>? get popup => current is PopupRoute
      ? current
      : desktopOuterRouteObserver.current is PopupRoute
      ? desktopOuterRouteObserver.current
      : null;
}

final desktopRouteObserver = DesktopRouteObserver();
final desktopOuterRouteObserver = DesktopRouteObserver();
