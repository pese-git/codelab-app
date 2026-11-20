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
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';

/// Позиции клавиш раскладки US для правила D16 (change `fix-approval-focus`).
///
/// Почему: при русской раскладке физическая клавиша K приходит логической
/// «л», и сравнение только логической клавиши не срабатывало. Нативные
/// приложения распознают Cmd/Ctrl+буква по латинскому эквиваленту клавиши.
///
/// Для чего: таблица «латинская клавиша комбинации → физическая позиция US»;
/// есть только у букв, цифр и знаков, у Esc, Enter, Backspace и стрелок записей
/// нет — они от раскладки не зависят. Физические клавиши живут только здесь
/// (сторож 1, D3). Как использовать: через [_layoutKeyMatches].
final Map<LogicalKeyboardKey, PhysicalKeyboardKey> _usPosition = {
  LogicalKeyboardKey.keyA: PhysicalKeyboardKey.keyA,
  LogicalKeyboardKey.keyB: PhysicalKeyboardKey.keyB,
  LogicalKeyboardKey.keyC: PhysicalKeyboardKey.keyC,
  LogicalKeyboardKey.keyD: PhysicalKeyboardKey.keyD,
  LogicalKeyboardKey.keyE: PhysicalKeyboardKey.keyE,
  LogicalKeyboardKey.keyF: PhysicalKeyboardKey.keyF,
  LogicalKeyboardKey.keyG: PhysicalKeyboardKey.keyG,
  LogicalKeyboardKey.keyH: PhysicalKeyboardKey.keyH,
  LogicalKeyboardKey.keyI: PhysicalKeyboardKey.keyI,
  LogicalKeyboardKey.keyJ: PhysicalKeyboardKey.keyJ,
  LogicalKeyboardKey.keyK: PhysicalKeyboardKey.keyK,
  LogicalKeyboardKey.keyL: PhysicalKeyboardKey.keyL,
  LogicalKeyboardKey.keyM: PhysicalKeyboardKey.keyM,
  LogicalKeyboardKey.keyN: PhysicalKeyboardKey.keyN,
  LogicalKeyboardKey.keyO: PhysicalKeyboardKey.keyO,
  LogicalKeyboardKey.keyP: PhysicalKeyboardKey.keyP,
  LogicalKeyboardKey.keyQ: PhysicalKeyboardKey.keyQ,
  LogicalKeyboardKey.keyR: PhysicalKeyboardKey.keyR,
  LogicalKeyboardKey.keyS: PhysicalKeyboardKey.keyS,
  LogicalKeyboardKey.keyT: PhysicalKeyboardKey.keyT,
  LogicalKeyboardKey.keyU: PhysicalKeyboardKey.keyU,
  LogicalKeyboardKey.keyV: PhysicalKeyboardKey.keyV,
  LogicalKeyboardKey.keyW: PhysicalKeyboardKey.keyW,
  LogicalKeyboardKey.keyX: PhysicalKeyboardKey.keyX,
  LogicalKeyboardKey.keyY: PhysicalKeyboardKey.keyY,
  LogicalKeyboardKey.keyZ: PhysicalKeyboardKey.keyZ,
  LogicalKeyboardKey.digit0: PhysicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1: PhysicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2: PhysicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3: PhysicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4: PhysicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5: PhysicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6: PhysicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7: PhysicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8: PhysicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9: PhysicalKeyboardKey.digit9,
  LogicalKeyboardKey.comma: PhysicalKeyboardKey.comma,
  LogicalKeyboardKey.period: PhysicalKeyboardKey.period,
  LogicalKeyboardKey.slash: PhysicalKeyboardKey.slash,
  LogicalKeyboardKey.minus: PhysicalKeyboardKey.minus,
  LogicalKeyboardKey.equal: PhysicalKeyboardKey.equal,
};

/// Правило совпадения клавиши события с клавишей комбинации [key] (D16,
/// spec agent-workbench-ui «Сочетания app не зависят от раскладки ввода»):
/// 1. логическая клавиша события равна [key] — совпадение (латинские
///    раскладки, включая AZERTY, QWERTZ и Dvorak, — по напечатанной букве);
/// 2. иначе, если [key] зависит от раскладки (есть в [_usPosition]) и
///    логическая клавиша события — символ вне ASCII (кириллица и т. п.),
///    сравнивается физическая клавиша события с позицией [key] на US;
/// 3. иначе — нет: латинская буква другой позиции по позиции не
///    сравнивается, иначе на AZERTY одна клавиша давала бы два сочетания.
/// Модификаторы здесь не проверяются.
bool _layoutKeyMatches(KeyEvent event, LogicalKeyboardKey key) {
  final logical = event.logicalKey;
  if (logical == key) {
    return true;
  }
  final position = _usPosition[key];
  if (position == null) {
    return false;
  }
  // Печатный символ вне ASCII: keyId — кодовая точка Unicode (плоскость 0);
  // управляющие и функциональные клавиши лежат выше `0x100000000`.
  final id = logical.keyId;
  final nonAscii = id > 0x7f && id < 0x100000000;
  return nonAscii && event.physicalKey == position;
}

/// Активатор клавиши каталога с правилом раскладки D16.
///
/// Почему: `SingleActivator` сравнивает только логическую клавишу, поэтому
/// при русской раскладке ни одно сочетание с буквой не срабатывало.
///
/// Для чего: заменяет `SingleActivator` в [CodeLabKeyCombo.activators];
/// модификаторы, автоповтор и тип события проверяет родитель, клавишу — правило
/// [_layoutKeyMatches]. Как использовать: только через каталог (`bind`,
/// `activators`); для `CallbackShortcuts`, который опрашивает `accepts` у всех
/// привязок.
final class CodeLabLayoutActivator extends SingleActivator {
  const CodeLabLayoutActivator(
    super.trigger, {
    super.control,
    super.shift,
    super.alt,
    super.meta,
    super.includeRepeats,
  });

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (super.accepts(event, state)) {
      return true;
    }
    if (event.logicalKey == trigger || !_layoutKeyMatches(event, trigger)) {
      return false;
    }
    // Событие совпало по позиции: остальные условия (тип, автоповтор,
    // модификаторы) проверяет родитель на событии с логической клавишей
    // комбинации.
    final aligned = switch (event) {
      KeyDownEvent() => KeyDownEvent(
        physicalKey: event.physicalKey,
        logicalKey: trigger,
        timeStamp: event.timeStamp,
      ),
      KeyRepeatEvent() => KeyRepeatEvent(
        physicalKey: event.physicalKey,
        logicalKey: trigger,
        timeStamp: event.timeStamp,
      ),
      _ => null,
    };
    return aligned != null && super.accepts(aligned, state);
  }
}

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
    this.meta = false,
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

  /// Точный модификатор ⌘ без Ctrl (change `fix-approval-focus`, D15).
  ///
  /// Почему: сочетания ответа на одобрение на macOS привязаны только к ⌘
  /// (Ctrl+Y в поле ввода — «yank» Emacs-раскладки Cocoa и не должен
  /// отвечать на запрос), а [primary] привязывает и Ctrl, и ⌘.
  ///
  /// Для чего: `activators`, `accepts` и обозначения клавиш; в обозначениях
  /// ⌘ стоит там же, где у [primary]. Как использовать: задаётся в записи
  /// каталога вместо [primary], вместе с ним не указывается.
  final bool meta;

  List<LogicalKeyboardKey> get _keys => [key, ...alsoKeys];

  /// Активаторы привязки: у `primary` — по паре `control` и `meta` на каждую
  /// клавишу, у [meta] — только `meta`, иначе по одному.
  List<SingleActivator> get activators => activatorsWith();

  /// Те же активаторы; [includeRepeats] `false` отключает автоповтор
  /// удерживаемой клавиши (сочетания ответа на одобрение, D14, п. 3).
  List<SingleActivator> activatorsWith({bool includeRepeats = true}) => [
    for (final k in _keys)
      if (primary) ...[
        CodeLabLayoutActivator(
          k,
          control: true,
          alt: alt,
          shift: shift,
          includeRepeats: includeRepeats,
        ),
        CodeLabLayoutActivator(
          k,
          meta: true,
          alt: alt,
          shift: shift,
          includeRepeats: includeRepeats,
        ),
      ] else
        CodeLabLayoutActivator(
          k,
          meta: meta,
          alt: alt,
          shift: shift,
          includeRepeats: includeRepeats,
        ),
  ];

  /// Подходит ли нажатие [event] комбинации при текущих модификаторах
  /// [keyboard]. Отпускание не подходит; модификаторы сверяются точно, как у
  /// `SingleActivator`. Клавиша сверяется по правилу раскладки D16
  /// (`fix-approval-focus`): логическая клавиша, а для нелатинской
  /// раскладки — физическая позиция US (см. [CodeLabLayoutActivator]).
  bool accepts(KeyEvent event, HardwareKeyboard keyboard) {
    if (event is KeyUpEvent || !_keys.any((k) => _layoutKeyMatches(event, k))) {
      return false;
    }
    final control = keyboard.isControlPressed;
    final meta = keyboard.isMetaPressed;
    // Как `SingleActivator`: основной модификатор — ровно один из Ctrl и ⌘
    // (активаторы `control` и `meta` по отдельности), а не оба сразу.
    final primaryOk = primary ? control != meta : !control && meta == this.meta;
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
        if (primary || meta) '⌘',
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
        if (primary || meta) 'Cmd',
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

  /// «Go to approval»: перейти к активному одобрению (change
  /// `fix-approval-focus`, D3). Cmd/Ctrl+Shift+A; первая запись группы.
  goToApproval(CodeLabShortcutGroup.approvals, [
    CodeLabKeyCombo(LogicalKeyboardKey.keyA, primary: true, shift: true),
  ]),

  // Сочетания ответа на одобрение (change `fix-approval-focus`, итерация 7,
  // D14, D15): общих комбинаций нет, клавиши свои на macOS и на остальных ОС.
  // macOS — только ⌘ (`meta`): Ctrl+Y там «yank» Cocoa. Windows и Linux — только
  // Alt+Shift: Ctrl+Z и Ctrl+Shift+Z правят текст, Ctrl+Alt даёт AltGr.
  allowOnce(
    CodeLabShortcutGroup.approvals,
    [],
    macCombos: [CodeLabKeyCombo(LogicalKeyboardKey.keyY, meta: true)],
    otherCombos: [
      CodeLabKeyCombo(LogicalKeyboardKey.keyY, alt: true, shift: true),
    ],
  ),
  allowAlways(
    CodeLabShortcutGroup.approvals,
    [],
    macCombos: [
      CodeLabKeyCombo(LogicalKeyboardKey.keyY, meta: true, alt: true),
    ],
    otherCombos: [
      CodeLabKeyCombo(LogicalKeyboardKey.keyQ, alt: true, shift: true),
    ],
  ),
  rejectOnce(
    CodeLabShortcutGroup.approvals,
    [],
    macCombos: [
      CodeLabKeyCombo(LogicalKeyboardKey.keyZ, meta: true, alt: true),
    ],
    otherCombos: [
      CodeLabKeyCombo(LogicalKeyboardKey.keyX, alt: true, shift: true),
    ],
  ),
  rejectAlways(
    CodeLabShortcutGroup.approvals,
    [],
    macCombos: [
      CodeLabKeyCombo(
        LogicalKeyboardKey.keyZ,
        meta: true,
        alt: true,
        shift: true,
      ),
    ],
    otherCombos: [
      CodeLabKeyCombo(LogicalKeyboardKey.keyW, alt: true, shift: true),
    ],
  );

  const CodeLabShortcut(
    this.group,
    this.combos, {
    this.macCombos,
    this.otherCombos,
  });

  final CodeLabShortcutGroup group;

  /// Общие комбинации записи; альтернативы — по порядку показа. У записей с
  /// клавишами по платформе пусты: действуют [macCombos] и [otherCombos].
  final List<CodeLabKeyCombo> combos;

  /// Комбинации macOS; `null` — действуют общие [combos] (D15).
  final List<CodeLabKeyCombo>? macCombos;

  /// Комбинации Windows и Linux; `null` — действуют общие [combos] (D15).
  final List<CodeLabKeyCombo>? otherCombos;

  /// kebab-case идентификатор строки страницы и ключей тестов
  /// (`command-palette`, `file-tree-open`).
  String get id =>
      name.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');

  /// Комбинации записи на платформе [platform] (D15): у сочетаний ответа
  /// клавиши macOS и остальных ОС различаются, у остальных записей это
  /// общие [combos]. Платформу выбирает вызывающий (`defaultTargetPlatform`).
  List<CodeLabKeyCombo> combosFor(TargetPlatform platform) =>
      (platform == TargetPlatform.macOS ? macCombos : otherCombos) ?? combos;

  /// Нотации поиска страницы «Keyboard» (D15, D8): общие комбинации — все
  /// нотации, комбинации macOS — только нотации macOS (символы и слова ⌘/Option),
  /// комбинации Windows и Linux — только слова этих ОС. Иначе поиск находил бы
  /// клавиши, которых на платформе нет (`Y`, `Alt+Z` для записи с ⌘).
  Iterable<String> searchNotations() => {
    for (final combo in combos) ...combo.searchNotations(),
    for (final combo in macCombos ?? const <CodeLabKeyCombo>[]) ...[
      combo.compactFor(TargetPlatform.macOS),
      combo.spokenFor(TargetPlatform.macOS),
    ],
    for (final combo in otherCombos ?? const <CodeLabKeyCombo>[])
      combo.spokenFor(TargetPlatform.windows),
  };

  /// Привязка [action] ко всем активаторам комбинаций записи на
  /// `defaultTargetPlatform`, для `CallbackShortcuts`. Записи с разными
  /// действиями у альтернатив (меню команд, дерево Files) привязывают по
  /// `combos[i].activators`.
  Map<ShortcutActivator, VoidCallback> bind(
    VoidCallback action, {
    bool includeRepeats = true,
  }) => {
    for (final combo in combosFor(defaultTargetPlatform))
      for (final activator in combo.activatorsWith(
        includeRepeats: includeRepeats,
      ))
        activator: action,
  };
}

/// Сколько Alt и Shift зажаты одновременно, до текущего нажатия.
///
/// Почему: на Windows и Linux Alt+Shift — ещё и смена раскладки. Если буква
/// ответа наложилась на смену раскладки, пользователь не собирался отвечать на
/// одобрение (решение пользователя 2026-11-20, `fix-approval-focus`, D14).
/// Различить это можно только по времени: модификаторы «зажаты заранее»,
/// а не нажаты вместе с буквой.
///
/// Для чего: кит различает нажатие и сообщает хосту, сколько модификаторы уже
/// зажаты (`CodeLabWorkbenchShortcuts.onAnswerApproval`); сколько этого
/// достаточно, решает хост (политика — application, AGENTS.md §10). Класс не
/// читает клавиши событий, а только состояние модификаторов
/// `HardwareKeyboard`, поэтому литералов клавиш (сторож каталога, D3) нет.
///
/// Как использовать: владелец вызывает [attach] один раз и [detach] при
/// освобождении; [heldFor] читают в момент нажатия сочетания. Обработчик
/// `HardwareKeyboard` вызывается раньше фокус-дерева, поэтому к нажатию буквы
/// отсчёт уже обновлён. [clock] — внедряемые часы (тесты двигают их явно).
final class CodeLabModifierHoldTracker {
  CodeLabModifierHoldTracker({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  DateTime? _since;
  bool _attached = false;

  /// Подписывается на события клавиатуры; повторный вызов ничего не делает.
  void attach() {
    if (_attached) {
      return;
    }
    _attached = true;
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  /// Отписывается; без вызова подписка пережила бы владельца.
  void detach() {
    if (!_attached) {
      return;
    }
    _attached = false;
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
  }

  bool _onKeyEvent(KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed && keyboard.isShiftPressed) {
      _since ??= _clock();
    } else {
      _since = null;
    }
    // Событие не поглощается: фокус-дерево обработает его как обычно.
    return false;
  }

  /// Сколько Alt и Shift зажаты вместе; [Duration.zero] — не зажаты или
  /// зажаты только что.
  Duration get heldFor {
    final since = _since;
    if (since == null) {
      return Duration.zero;
    }
    return _clock().difference(since);
  }
}
