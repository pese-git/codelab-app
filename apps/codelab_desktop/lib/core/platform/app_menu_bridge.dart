import 'package:flutter/services.dart';

/// Имя канала нативного меню: Dart слушает, нативная сторона вызывает.
const kAppMenuChannelName = 'codelab/app_menu';

/// Мост нативного меню приложения (macOS) в Dart.
///
/// Почему: главное меню macOS перехватывает сочетания раньше Flutter. Пункт
/// «Настройки…» (⌘,) без действия ничего не запускал, а сочетание
/// `open-settings` Dart-стороны до него не доходило (ручная проверка собранного
/// app). Поэтому пункт получил действие, а нативная сторона сообщает о нём в
/// канал [kAppMenuChannelName]: настройки открываются тем же путём, что
/// сочетание (`SettingsOpenSource.shortcut`).
///
/// Для чего: единственное место, где Dart принимает команды нативного меню;
/// проверок платформы нет (`AGENTS.md` §11): на системах без такого меню
/// канал просто никто не вызывает.
///
/// Как использовать: владелец (`CodeLabBootstrap`) создаёт мост, зовёт
/// [attach] при старте и [dispose] при закрытии; [onOpenSettings] открывает
/// настройки через `NavigationCubit`. Неизвестная команда отвечает
/// `MissingPluginException`, как неподдержанный метод.
final class AppMenuBridge {
  AppMenuBridge({
    required this.onOpenSettings,
    MethodChannel channel = const MethodChannel(kAppMenuChannelName),
  }) : _channel = channel;

  /// Пункт «Настройки…» нажат.
  final void Function() onOpenSettings;

  final MethodChannel _channel;

  /// Начинает слушать канал.
  void attach() => _channel.setMethodCallHandler(_handle);

  /// Перестаёт слушать канал: поздний вызов после закрытия app ничего не
  /// делает.
  void dispose() => _channel.setMethodCallHandler(null);

  Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'openSettings':
        onOpenSettings();
      default:
        throw MissingPluginException(call.method);
    }
  }
}
