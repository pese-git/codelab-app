/// Каталог клавиатурных сочетаний app: заглушка сигнатур для красных тестов.
///
/// Почему: сочетания сейчас объявлены литералами в девяти файлах кита и app,
/// а подписи к ним собираются отдельно; страница «Keyboard» третьим списком
/// разошлась бы с привязками (change `add-app-keyboard-page`, D2, D3).
///
/// Для чего: единственный источник активаторов привязок и обозначений клавиш
/// по платформе. Записи идут в порядке строк страницы (D1).
///
/// Как использовать: сейчас здесь только типы и значения без поведения —
/// задачи 1.1–1.3 (красные тесты). Методы бросают [UnimplementedError], у
/// записей нет комбинаций. Поведение — задача 1.4 (D2–D4).
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// Группа строк страницы «Keyboard» (D1).
enum CodeLabShortcutGroup {
  global,
  navigation,
  transcript,
  composer,
  approvals,
}

/// Одна комбинация: основной модификатор (Ctrl и ⌘), Alt, Shift и клавиша.
final class CodeLabKeyCombo {
  const CodeLabKeyCombo(
    this.key, {
    this.primary = false,
    this.alt = false,
    this.shift = false,
    this.alsoKeys = const [],
  });

  final LogicalKeyboardKey key;

  /// Дополнительные клавиши с тем же действием (numpad Enter у дерева Files).
  final List<LogicalKeyboardKey> alsoKeys;

  final bool primary;
  final bool alt;
  final bool shift;

  /// Активаторы привязки; заглушка.
  List<SingleActivator> get activators => throw UnimplementedError();

  /// Подходит ли [event] этой комбинации; заглушка.
  bool accepts(KeyEvent event, HardwareKeyboard keyboard) =>
      throw UnimplementedError();

  /// Кейкапы страницы; заглушка.
  List<String> capsFor(TargetPlatform platform) => throw UnimplementedError();

  /// Короткая подсказка кнопок; заглушка.
  String compactFor(TargetPlatform platform) => throw UnimplementedError();

  /// Подпись для чтения с экрана; заглушка.
  String spokenFor(TargetPlatform platform) => throw UnimplementedError();

  /// Нотации для поиска страницы; заглушка.
  Iterable<String> searchNotations() => throw UnimplementedError();
}

/// Записи каталога в порядке строк страницы (D1); комбинации — задача 1.4.
enum CodeLabShortcut {
  commandPalette(CodeLabShortcutGroup.global),
  newSession(CodeLabShortcutGroup.global),
  openSettings(CodeLabShortcutGroup.global),
  closeOverlay(CodeLabShortcutGroup.global),
  leaveSettings(CodeLabShortcutGroup.global),
  toggleSidebar(CodeLabShortcutGroup.navigation),
  toggleFiles(CodeLabShortcutGroup.navigation),
  fileTreeMove(CodeLabShortcutGroup.navigation),
  fileTreeFold(CodeLabShortcutGroup.navigation),
  fileTreeOpen(CodeLabShortcutGroup.navigation),
  cancelTurn(CodeLabShortcutGroup.transcript),
  send(CodeLabShortcutGroup.composer),
  commandMenuMove(CodeLabShortcutGroup.composer),
  commandMenuRun(CodeLabShortcutGroup.composer),
  commandMenuClose(CodeLabShortcutGroup.composer),
  allowOnce(CodeLabShortcutGroup.approvals),
  allowAlways(CodeLabShortcutGroup.approvals),
  rejectOnce(CodeLabShortcutGroup.approvals),
  rejectAlways(CodeLabShortcutGroup.approvals);

  const CodeLabShortcut(this.group);

  final CodeLabShortcutGroup group;

  /// Комбинации записи; пока пусто (заглушка).
  List<CodeLabKeyCombo> get combos => const [];

  /// kebab-case идентификатор строки страницы; заглушка.
  String get id => throw UnimplementedError();

  /// Привязка действия к активаторам записи; заглушка.
  Map<ShortcutActivator, VoidCallback> bind(VoidCallback action) =>
      throw UnimplementedError();
}
