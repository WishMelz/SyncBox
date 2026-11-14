import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Windows system-tray integration.
///
/// The main Flutter window remains the source of truth for the workspace. The
/// tray only changes its visibility and size, so session state and live sync
/// continue while the compact window is hidden.
class WindowsTrayController extends WindowListener with TrayListener {
  WindowsTrayController._();

  static WindowsTrayController? _instance;
  static WindowsTrayController get instance => _instance!;

  bool _compact = false;
  bool _exiting = false;

  static Future<void> initialize() async {
    if (!Platform.isWindows || _instance != null) return;
    final controller = WindowsTrayController._();
    _instance = controller;
    try {
      await windowManager.ensureInitialized();
      windowManager.addListener(controller);
      trayManager.addListener(controller);

      // Use the packaged asset path when running a release build. The simple
      // asset-relative path remains a fallback for `flutter run -d windows`.
      final executableDir = File(Platform.resolvedExecutable).parent.path;
      final packagedIcon = File(
        '$executableDir${Platform.pathSeparator}data'
        '${Platform.pathSeparator}flutter_assets${Platform.pathSeparator}'
        'assets${Platform.pathSeparator}branding${Platform.pathSeparator}'
        'syncbox-icon.ico',
      );
      await trayManager.setIcon(
        packagedIcon.existsSync()
            ? packagedIcon.path
            : 'assets/branding/syncbox-icon.ico',
      );
      await trayManager.setToolTip('SyncBox');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'open_compact', label: '打开紧凑窗口'),
            MenuItem(key: 'open_main', label: '打开完整窗口'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: '退出 SyncBox'),
          ],
        ),
      );
      await windowManager.setPreventClose(true);
    } catch (_) {
      windowManager.removeListener(controller);
      trayManager.removeListener(controller);
      _instance = null;
      rethrow;
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(showCompact());
  }

  @override
  void onTrayIconRightMouseDown() {
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'open_compact':
        unawaited(showCompact());
        return;
      case 'open_main':
        unawaited(showMainWindow());
        return;
      case 'quit':
        unawaited(quit());
        return;
    }
  }

  @override
  void onWindowClose() {
    if (_exiting) return;
    // Closing the window behaves like macOS: keep syncing in the background
    // and leave the app available from the tray.
    unawaited(windowManager.hide());
  }

  Future<void> showCompact() async {
    _compact = true;
    await windowManager.setResizable(false);
    await windowManager.setSize(const Size(420, 680));
    // Keep the compact panel close to the Windows notification area.
    await windowManager.setAlignment(Alignment.bottomRight);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> showMainWindow() async {
    _compact = false;
    await windowManager.setResizable(true);
    await windowManager.setSize(const Size(1280, 720));
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    _exiting = true;
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await windowManager.close();
  }

  bool get isCompact => _compact;

  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    unawaited(trayManager.destroy());
    _instance = null;
  }
}
