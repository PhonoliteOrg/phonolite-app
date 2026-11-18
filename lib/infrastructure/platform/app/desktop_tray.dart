abstract interface class DesktopTray {
  void show({required void Function() onShow, required void Function() onQuit});
  void dispose();
}
