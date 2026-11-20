import 'dart:async';

import 'package:codelab_desktop/core/platform/system_accent_source.dart';

/// Двойник порта системного акцента (`add-app-appearance-page`, D7).
///
/// Почему: настоящий адаптер ходит в канал плагина `system_theme`, а тестам
/// Cubit-а нужны управляемые значения, ошибки и счётчик чтений.
///
/// Как использовать: [accent] — ARGB для `read()`; [readError] — исключение
/// вместо значения; [emit] и [emitError] — событие потока `changes`;
/// [listening] — есть ли подписчик (проверка отписки в `close()`);
/// [readCount] — сколько раз вызван `read()` (Linux без уведомлений: одно
/// чтение на открытие страницы).
final class FakeSystemAccentSource implements SystemAccentSource {
  FakeSystemAccentSource({this.supported = true, this.accent});

  @override
  final bool supported;

  int? accent;
  Object? readError;
  int readCount = 0;

  late final StreamController<int?> _controller = StreamController<int?>(
    onListen: () => listening = true,
    onCancel: () => listening = false,
  );

  bool listening = false;

  @override
  Future<int?> read() async {
    readCount++;
    final error = readError;
    if (error != null) throw error;
    return accent;
  }

  @override
  Stream<int?> get changes => _controller.stream;

  void emit(int? value) => _controller.add(value);

  void emitError(Object error) => _controller.addError(error);
}
