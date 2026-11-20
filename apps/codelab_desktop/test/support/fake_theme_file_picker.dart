import 'dart:async';

import 'package:codelab_desktop/core/platform/theme_file_picker.dart';

/// Двойник порта [ThemeFilePicker] (`add-app-appearance-page`, D9).
///
/// Почему: настоящий `file_selector` открыл бы системный диалог, а тесты
/// страницы «Appearance» проверяют только то, СКОЛЬКО раз страница открыла
/// диалог и какой путь получила.
///
/// Для чего: [results] — очередь ответов по вызовам (`null` — пользователь
/// закрыл диалог); пока очередь пуста, отвечает [next]. [gate] удерживает
/// ответ до сигнала теста (проверка «повторный импорт недоступен»).
///
/// Как использовать: `FakeThemeFilePicker(next: '/Downloads/night.json')`;
/// после жеста — `picker.calls`.
final class FakeThemeFilePicker implements ThemeFilePicker {
  FakeThemeFilePicker({this.next});

  /// Ответ, когда очередь [results] пуста.
  String? next;

  /// Ответы ближайших вызовов по порядку.
  final List<String?> results = [];

  /// Сколько раз открывали диалог.
  int calls = 0;

  /// Если задан, ответ ждёт завершения этого сигнала.
  Completer<void>? gate;

  @override
  Future<String?> pickThemeFile() async {
    calls++;
    final answer = results.isEmpty ? next : results.removeAt(0);
    final hold = gate;
    if (hold != null) await hold.future;
    return answer;
  }
}
