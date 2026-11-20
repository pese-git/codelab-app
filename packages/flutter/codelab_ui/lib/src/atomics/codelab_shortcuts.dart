/// Каталог клавиатурных сочетаний app (change `add-app-keyboard-page`, D1–D4).
///
/// Почему: сочетания были объявлены литералами `SingleActivator` и сравнениями
/// `LogicalKeyboardKey` в девяти файлах кита и app, а подписи к ним (`⌘K`,
/// `Ctrl+⏎`) собирались отдельно, своими проверками платформы. Страница
/// «Keyboard», написанная третьим списком, разошлась бы с привязками при
/// первом же новом сочетании.
///
/// Для чего: единственный источник и активаторов привязок, и обозначений
/// клавиш по платформе. Тексты действий здесь не живут (D5): каталог — словарь
/// клавиш, а не политика; что разрешено и что опасно, решает app.
///
/// Как использовать: привязка — `CodeLabShortcut.x.bind(action)` или
/// `combo.activators`; дерево Files сравнивает событие через `combo.accepts`.
/// Обозначения для страницы и подсказок — `capsFor`, `compactFor`,
/// `spokenFor` с платформой `defaultTargetPlatform` (D4: платформу выбирает
/// только каталог, feature-код `Platform.is*` не проверяет). Литералы
/// активаторов вне этого файла запрещены сторожами (D3).
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

/// Группа строк страницы «Keyboard» (D1) в порядке показа.
enum CodeLabShortcutGroup {
  global,
  navigation,
  transcript,
  composer,
  approvals,
}

/// Одна комбинация: основной модификатор (Ctrl и ⌘), Alt, Shift и клавиша.
///
/// Почему: «основной модификатор» привязывается и к Ctrl, и к ⌘ на всех
/// платформах, как было до change (D3); поэтому `primary` — признак, а не
/// конкретная клавиша.
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

  /// Основной модификатор: Ctrl или ⌘ (по одному, не оба сразу).
  final bool primary;

  /// Нужен ли Alt (⌥ на macOS). Почему поле, а не клавиша: модификаторы
  /// сверяются точно, как у `SingleActivator`, поэтому Cmd/Ctrl+Enter и
  /// Cmd/Ctrl+Alt+Enter — разные сочетания. Для чего: `activators`,
  /// `accepts` и обозначения клавиш. Как использовать: задаётся в записи
  /// каталога.
  final bool alt;

  /// Нужен ли Shift (⇧ на macOS); смысл и использование как у [alt].
  final bool shift;

  List<LogicalKeyboardKey> get _keys => [key, ...alsoKeys];

  /// Активаторы привязки: у `primary` — по паре `control` и `meta` на каждую
  /// клавишу, иначе по одному.
  List<SingleActivator> get activators => [
    for (final k in _keys)
      if (primary) ...[
        SingleActivator(k, control: true, alt: alt, shift: shift),
        SingleActivator(k, meta: true, alt: alt, shift: shift),
      ] else
        SingleActivator(k, alt: alt, shift: shift),
  ];

  /// Подходит ли нажатие [event] комбинации при текущих модификаторах
  /// [keyboard]. Отпускание не подходит; модификаторы сверяются точно, как у
  /// `SingleActivator`.
  bool accepts(KeyEvent event, HardwareKeyboard keyboard) {
    if (event is KeyUpEvent || !_keys.contains(event.logicalKey)) {
      return false;
    }
    final control = keyboard.isControlPressed;
    final meta = keyboard.isMetaPressed;
    // Как `SingleActivator`: основной модификатор — ровно один из Ctrl и ⌘
    // (активаторы `control` и `meta` по отдельности), а не оба сразу.
    final primaryOk = primary ? control != meta : !control && !meta;
    return primaryOk &&
        keyboard.isAltPressed == alt &&
        keyboard.isShiftPressed == shift;
  }

  static bool _isMac(TargetPlatform platform) =>
      platform == TargetPlatform.macOS;

  /// Кейкапы страницы: macOS — символы в порядке ⌥ ⇧ ⌘, остальные ОС — слова
  /// в порядке Ctrl Alt Shift (D4).
  List<String> capsFor(TargetPlatform platform) {
    final mac = _isMac(platform);
    return [
      if (mac) ...[
        if (alt) '⌥',
        if (shift) '⇧',
        if (primary) '⌘',
      ] else ...[
        if (primary) 'Ctrl',
        if (alt) 'Alt',
        if (shift) 'Shift',
      ],
      _keyCap(key, mac: mac),
    ];
  }

  /// Короткая подсказка кнопок: `⌘K`, `Ctrl+K`. На Windows и Linux остаются
  /// символы `⏎` и `⌫` (кнопки узкие), порядок модификаторов общий (D4, Q4).
  String compactFor(TargetPlatform platform) {
    final mac = _isMac(platform);
    final parts = [
      ...capsFor(platform).take(capsFor(platform).length - 1),
      _keyCap(key, mac: true),
    ];
    return mac ? parts.join() : parts.join('+');
  }

  /// Подпись для чтения с экрана словами: `Option+Cmd+Enter`,
  /// `Ctrl+Alt+Enter` (D4).
  String spokenFor(TargetPlatform platform) {
    final mac = _isMac(platform);
    return [
      if (mac) ...[
        if (alt) 'Option',
        if (shift) 'Shift',
        if (primary) 'Cmd',
      ] else ...[
        if (primary) 'Ctrl',
        if (alt) 'Alt',
        if (shift) 'Shift',
      ],
      _keyWord(key),
    ].join('+');
  }

  /// Нотации для поиска страницы независимо от платформы (D8): символы macOS,
  /// слова Windows и Linux, слова macOS.
  Iterable<String> searchNotations() => [
    compactFor(TargetPlatform.macOS),
    spokenFor(TargetPlatform.windows),
    spokenFor(TargetPlatform.macOS),
  ];

  static String _keyCap(LogicalKeyboardKey key, {required bool mac}) {
    if (key == LogicalKeyboardKey.enter) return mac ? '⏎' : 'Enter';
    if (key == LogicalKeyboardKey.backspace) return mac ? '⌫' : 'Backspace';
    return _commonCap(key);
  }

  static String _commonCap(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.arrowUp) return '↑';
    if (key == LogicalKeyboardKey.arrowDown) return '↓';
    if (key == LogicalKeyboardKey.arrowLeft) return '←';
    if (key == LogicalKeyboardKey.arrowRight) return '→';
    if (key == LogicalKeyboardKey.comma) return ',';
    return key.keyLabel.toUpperCase();
  }

  static String _keyWord(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.enter) return 'Enter';
    if (key == LogicalKeyboardKey.backspace) return 'Backspace';
    if (key == LogicalKeyboardKey.escape) return 'Esc';
    if (key == LogicalKeyboardKey.arrowUp) return 'Up';
    if (key == LogicalKeyboardKey.arrowDown) return 'Down';
    if (key == LogicalKeyboardKey.arrowLeft) return 'Left';
    if (key == LogicalKeyboardKey.arrowRight) return 'Right';
    if (key == LogicalKeyboardKey.comma) return 'Comma';
    return key.keyLabel.toUpperCase();
  }
}

/// Записи каталога в порядке строк страницы «Keyboard» (D1).
///
/// Альтернативы одной строки идут в порядке показа: «↑ / ↓», «→ / ←».
enum CodeLabShortcut {
  commandPalette(CodeLabShortcutGroup.global, [
    CodeLabKeyCombo(LogicalKeyboardKey.keyK, primary: true),
  ]),
  newSession(CodeLabShortcutGroup.global, [
    CodeLabKeyCombo(LogicalKeyboardKey.keyN, primary: true),
  ]),
  openSettings(CodeLabShortcutGroup.global, [
    CodeLabKeyCombo(LogicalKeyboardKey.comma, primary: true),
  ]),
  closeOverlay(CodeLabShortcutGroup.global, [
    CodeLabKeyCombo(LogicalKeyboardKey.escape),
  ]),
  leaveSettings(CodeLabShortcutGroup.global, [
    CodeLabKeyCombo(LogicalKeyboardKey.escape),
  ]),
  toggleSidebar(CodeLabShortcutGroup.navigation, [
    CodeLabKeyCombo(LogicalKeyboardKey.keyB, primary: true),
  ]),
  toggleFiles(CodeLabShortcutGroup.navigation, [
    CodeLabKeyCombo(LogicalKeyboardKey.keyE, primary: true, shift: true),
  ]),
  fileTreeMove(CodeLabShortcutGroup.navigation, [
    CodeLabKeyCombo(LogicalKeyboardKey.arrowUp),
    CodeLabKeyCombo(LogicalKeyboardKey.arrowDown),
  ]),
  fileTreeFold(CodeLabShortcutGroup.navigation, [
    CodeLabKeyCombo(LogicalKeyboardKey.arrowRight),
    CodeLabKeyCombo(LogicalKeyboardKey.arrowLeft),
  ]),
  fileTreeOpen(CodeLabShortcutGroup.navigation, [
    CodeLabKeyCombo(
      LogicalKeyboardKey.enter,
      alsoKeys: [LogicalKeyboardKey.numpadEnter],
    ),
  ]),
  cancelTurn(CodeLabShortcutGroup.transcript, [
    CodeLabKeyCombo(LogicalKeyboardKey.escape),
  ]),
  send(CodeLabShortcutGroup.composer, [
    CodeLabKeyCombo(LogicalKeyboardKey.enter, primary: true),
  ]),
  commandMenuMove(CodeLabShortcutGroup.composer, [
    CodeLabKeyCombo(LogicalKeyboardKey.arrowUp),
    CodeLabKeyCombo(LogicalKeyboardKey.arrowDown),
  ]),
  commandMenuRun(CodeLabShortcutGroup.composer, [
    CodeLabKeyCombo(LogicalKeyboardKey.enter),
  ]),
  commandMenuClose(CodeLabShortcutGroup.composer, [
    CodeLabKeyCombo(LogicalKeyboardKey.escape),
  ]),
  allowOnce(CodeLabShortcutGroup.approvals, [
    CodeLabKeyCombo(LogicalKeyboardKey.enter, primary: true),
  ]),
  allowAlways(CodeLabShortcutGroup.approvals, [
    CodeLabKeyCombo(LogicalKeyboardKey.enter, primary: true, alt: true),
  ]),
  rejectOnce(CodeLabShortcutGroup.approvals, [
    CodeLabKeyCombo(LogicalKeyboardKey.backspace, primary: true),
  ]),
  rejectAlways(CodeLabShortcutGroup.approvals, [
    CodeLabKeyCombo(LogicalKeyboardKey.backspace, primary: true, alt: true),
  ]);

  const CodeLabShortcut(this.group, this.combos);

  final CodeLabShortcutGroup group;

  /// Комбинации записи; альтернативы — по порядку показа.
  final List<CodeLabKeyCombo> combos;

  /// kebab-case идентификатор строки страницы и ключей тестов
  /// (`command-palette`, `file-tree-open`).
  String get id =>
      name.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');

  /// Привязка [action] ко всем активаторам всех комбинаций записи, для
  /// `CallbackShortcuts`. Записи с разными действиями у альтернатив (меню
  /// команд, дерево Files) привязывают по `combos[i].activators`.
  Map<ShortcutActivator, VoidCallback> bind(VoidCallback action) => {
    for (final combo in combos)
      for (final activator in combo.activators) activator: action,
  };
}
