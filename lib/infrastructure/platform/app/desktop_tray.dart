import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

abstract interface class DesktopTray {
  void show({required void Function() onShow, required void Function() onQuit});
  void dispose();
}

/// Owns the tray, its menu, images and native event registrations.
class NativeDesktopTray implements DesktopTray {
  TrayIcon? _icon;
  Image? _image;
  Menu? _menu;
  final List<MenuItem> _items = [];
  final List<void Function()> _removeListeners = [];

  @override
  void show({required void Function() onShow, required void Function() onQuit}) {
    if (_icon != null) {
      return;
    }

    try {
      final icon = TrayIcon.createWithIdentifier('com.phonoliteorg.phonolite_app');
      if (icon == null) {
        throw StateError('Could not create the desktop tray icon.');
      }
      _icon = icon;
      final image = ImageAsset.fromAsset(
        Platform.isWindows ? 'assets/images/phonolite-tray.ico' : 'assets/images/phonolite-logo-nobackground.png',
      );
      if (image == null) {
        throw StateError('Could not load the Phonolite tray image.');
      }
      _image = image;
      icon.icon = image;
      icon.setTooltip('Phonolite');

      final menu = Menu.create();
      if (menu == null) {
        throw StateError('Could not create the desktop tray menu.');
      }
      _menu = menu;
      menu.addItem(_action('Show Phonolite', onShow));
      menu.addSeparator();
      menu.addItem(_action('Quit Phonolite', onQuit));
      icon.setContextMenu(menu);
      icon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);

      final listener = icon.addListener((event) {
        if (event is TrayIconClickedEvent) {
          if (Platform.isWindows) {
            onShow();
          } else {
            icon.openContextMenu();
          }
        }
      });
      _removeListeners.add(() => icon.removeListener(listener));

      if (!icon.setVisible(true)) {
        throw StateError('Could not show the desktop tray icon.');
      }
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  @override
  void dispose() {
    for (final remove in _removeListeners) {
      remove();
    }
    _removeListeners.clear();
    _icon?.dispose();
    _icon = null;
    _menu?.dispose();
    _menu = null;
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
    _image?.dispose();
    _image = null;
  }

  MenuItem _action(String label, void Function() action) {
    final item = MenuItem.createWithLabelAndType(label, MenuItemType.normal);
    if (item == null) {
      throw StateError('Could not create the $label tray action.');
    }
    _items.add(item);
    final listener = item.addListener((event) {
      if (event is MenuItemClickedEvent) {
        action();
      }
    });
    _removeListeners.add(() => item.removeListener(listener));

    return item;
  }
}
