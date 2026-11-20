// Каталог сочетаний `CodeLabShortcut` (задача 1.1 change
// `add-app-keyboard-page`; design.md D1, D2, D4; spec app-settings «Страница
// «Keyboard»: обозначения клавиш» и «…строки таблицы»).
//
// Красный до задачи 1.4: каталог — заглушка без комбинаций и поведения.
// Итерация 7 `fix-approval-focus` (задача 7.1, D14, D15): сочетания ответа на
// одобрение зависят от платформы (`combosFor`), точный модификатор ⌘ — `meta`.
// Платформа подменяется `debugDefaultTargetPlatformOverride` и сбрасывается в
// `tearDown`, иначе соседние тесты получат чужую платформу.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ожидаемая комбинация записи по таблице D1.
typedef _Combo = ({
  LogicalKeyboardKey key,
  bool primary,
  bool alt,
  bool shift,
  bool meta,
  List<LogicalKeyboardKey> also,
});

_Combo _c(
  LogicalKeyboardKey key, {
  bool primary = false,
  bool alt = false,
  bool shift = false,
  bool meta = false,
  List<LogicalKeyboardKey> also = const [],
}) => (
  key: key,
  primary: primary,
  alt: alt,
  shift: shift,
  meta: meta,
  also: also,
);

/// Строки таблицы D1 по порядку: запись, id, группа, комбинации. Порядок
/// альтернатив — как на странице: «↑ / ↓», «→ / ←».
final _table = <(CodeLabShortcut, String, CodeLabShortcutGroup, List<_Combo>)>[
  (
    CodeLabShortcut.commandPalette,
    'command-palette',
    CodeLabShortcutGroup.global,
    [_c(LogicalKeyboardKey.keyK, primary: true)],
  ),
  (
    CodeLabShortcut.newSession,
    'new-session',
    CodeLabShortcutGroup.global,
    [_c(LogicalKeyboardKey.keyN, primary: true)],
  ),
  (
    CodeLabShortcut.openSettings,
    'open-settings',
    CodeLabShortcutGroup.global,
    [_c(LogicalKeyboardKey.comma, primary: true)],
  ),
  (
    CodeLabShortcut.closeOverlay,
    'close-overlay',
    CodeLabShortcutGroup.global,
    [_c(LogicalKeyboardKey.escape)],
  ),
  (
    CodeLabShortcut.leaveSettings,
    'leave-settings',
    CodeLabShortcutGroup.global,
    [_c(LogicalKeyboardKey.escape)],
  ),
  (
    CodeLabShortcut.toggleSidebar,
    'toggle-sidebar',
    CodeLabShortcutGroup.navigation,
    [_c(LogicalKeyboardKey.keyB, primary: true)],
  ),
  (
    CodeLabShortcut.toggleFiles,
    'toggle-files',
    CodeLabShortcutGroup.navigation,
    [_c(LogicalKeyboardKey.keyE, primary: true, shift: true)],
  ),
  (
    CodeLabShortcut.fileTreeMove,
    'file-tree-move',
    CodeLabShortcutGroup.navigation,
    [_c(LogicalKeyboardKey.arrowUp), _c(LogicalKeyboardKey.arrowDown)],
  ),
  (
    CodeLabShortcut.fileTreeFold,
    'file-tree-fold',
    CodeLabShortcutGroup.navigation,
    [_c(LogicalKeyboardKey.arrowRight), _c(LogicalKeyboardKey.arrowLeft)],
  ),
  (
    CodeLabShortcut.fileTreeOpen,
    'file-tree-open',
    CodeLabShortcutGroup.navigation,
    [
      _c(
        LogicalKeyboardKey.enter,
        also: const [LogicalKeyboardKey.numpadEnter],
      ),
    ],
  ),
  (
    CodeLabShortcut.cancelTurn,
    'cancel-turn',
    CodeLabShortcutGroup.transcript,
    [_c(LogicalKeyboardKey.escape)],
  ),
  (
    CodeLabShortcut.send,
    'send',
    CodeLabShortcutGroup.composer,
    [_c(LogicalKeyboardKey.enter, primary: true)],
  ),
  (
    CodeLabShortcut.commandMenuMove,
    'command-menu-move',
    CodeLabShortcutGroup.composer,
    [_c(LogicalKeyboardKey.arrowUp), _c(LogicalKeyboardKey.arrowDown)],
  ),
  (
    CodeLabShortcut.commandMenuRun,
    'command-menu-run',
    CodeLabShortcutGroup.composer,
    [_c(LogicalKeyboardKey.enter)],
  ),
  (
    CodeLabShortcut.commandMenuClose,
    'command-menu-close',
    CodeLabShortcutGroup.composer,
    [_c(LogicalKeyboardKey.escape)],
  ),
  (
    CodeLabShortcut.goToApproval,
    'go-to-approval',
    CodeLabShortcutGroup.approvals,
    [_c(LogicalKeyboardKey.keyA, primary: true, shift: true)],
  ),
];

/// Сочетания ответа на одобрение по платформам (D14, D15): запись, id,
/// комбинации macOS, комбинации Windows и Linux. На macOS только ⌘ (`meta`),
/// без Ctrl; на остальных ОС только Alt+Shift.
final _answers = <(CodeLabShortcut, String, List<_Combo>, List<_Combo>)>[
  (
    CodeLabShortcut.allowOnce,
    'allow-once',
    [_c(LogicalKeyboardKey.keyY, meta: true)],
    [_c(LogicalKeyboardKey.keyY, alt: true, shift: true)],
  ),
  (
    CodeLabShortcut.allowAlways,
    'allow-always',
    [_c(LogicalKeyboardKey.keyY, meta: true, alt: true)],
    [_c(LogicalKeyboardKey.keyQ, alt: true, shift: true)],
  ),
  (
    CodeLabShortcut.rejectOnce,
    'reject-once',
    [_c(LogicalKeyboardKey.keyZ, meta: true, alt: true)],
    [_c(LogicalKeyboardKey.keyX, alt: true, shift: true)],
  ),
  (
    CodeLabShortcut.rejectAlways,
    'reject-always',
    [_c(LogicalKeyboardKey.keyZ, meta: true, alt: true, shift: true)],
    [_c(LogicalKeyboardKey.keyW, alt: true, shift: true)],
  ),
];

/// Проекция комбинации каталога в сравнимую запись.
_Combo _project(CodeLabKeyCombo c) => (
  key: c.key,
  primary: c.primary,
  alt: c.alt,
  shift: c.shift,
  meta: c.meta,
  also: c.alsoKeys,
);

/// Комбинации записи на платформе: для ответа — по таблице [_answers].
List<_Combo> _expectedFor(CodeLabShortcut shortcut, TargetPlatform platform) {
  for (final (s, _, mac, other) in _answers) {
    if (s == shortcut) {
      return platform == TargetPlatform.macOS ? mac : other;
    }
  }
  return _table.firstWhere((row) => row.$1 == shortcut).$4;
}

const _macOS = TargetPlatform.macOS;
const _others = [TargetPlatform.windows, TargetPlatform.linux];

CodeLabKeyCombo _combo(CodeLabShortcut shortcut, [int index = 0]) =>
    shortcut.combos[index];

// Комбинации Ctrl+Alt+⏎ и Ctrl+Backspace прежних сочетаний ответа: после
// итерации 7 записи каталога их не используют, а правила обозначений (порядок
// модификаторов, символы ⏎ ⌫) остаются, поэтому проверяются на явных
// комбинациях, не на записях каталога.
const _primaryAltEnter = CodeLabKeyCombo(
  LogicalKeyboardKey.enter,
  primary: true,
  alt: true,
);
const _primaryBackspace = CodeLabKeyCombo(
  LogicalKeyboardKey.backspace,
  primary: true,
);
const _primaryAltBackspace = CodeLabKeyCombo(
  LogicalKeyboardKey.backspace,
  primary: true,
  alt: true,
);

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('записи по таблице D1', () {
    test('20 записей по порядку и группам', () {
      expect(CodeLabShortcut.values, [
        for (final row in _table) row.$1,
        for (final row in _answers) row.$1,
      ]);
      expect(CodeLabShortcut.values.map((s) => s.group).toList(), [
        for (final row in _table) row.$3,
        for (final _ in _answers) CodeLabShortcutGroup.approvals,
      ]);
    });

    test('id — kebab-case из спецификации', () {
      expect(CodeLabShortcut.values.map((s) => s.id).toList(), [
        for (final row in _table) row.$2,
        for (final row in _answers) row.$2,
      ]);
    });

    test('комбинации записей совпадают с таблицей на каждой платформе', () {
      for (final platform in [_macOS, ..._others]) {
        for (final shortcut in CodeLabShortcut.values) {
          expect(
            shortcut.combosFor(platform).map(_project).toList(),
            _expectedFor(shortcut, platform),
            reason: '${shortcut.id} $platform',
          );
        }
      }
    });
  });

  // Сочетания ответа на одобрение (change `fix-approval-focus`, D14, D15; spec
  // «Ответ на одобрение сочетанием с любого места рабочего места»).
  group('сочетания ответа на одобрение (D14, D15)', () {
    test('macOS: активатор только meta, без Ctrl', () {
      for (final (shortcut, id, mac, _) in _answers) {
        final activators = [
          for (final c in shortcut.combosFor(_macOS)) ...c.activators,
        ];
        expect(activators, hasLength(1), reason: id);
        final a = activators.single;
        expect(a.meta, isTrue, reason: id);
        expect(a.control, isFalse, reason: id);
        expect(a.trigger, mac.single.key, reason: id);
        expect(a.alt, mac.single.alt, reason: id);
        expect(a.shift, mac.single.shift, reason: id);
      }
    });

    test('Windows и Linux: активатор только Alt+Shift, без Ctrl и meta', () {
      for (final platform in _others) {
        for (final (shortcut, id, _, other) in _answers) {
          final activators = [
            for (final c in shortcut.combosFor(platform)) ...c.activators,
          ];
          expect(activators, hasLength(1), reason: '$id $platform');
          final a = activators.single;
          expect(a.control, isFalse, reason: '$id $platform');
          expect(a.meta, isFalse, reason: '$id $platform');
          expect(a.alt, isTrue, reason: '$id $platform');
          expect(a.shift, isTrue, reason: '$id $platform');
          expect(a.trigger, other.single.key, reason: '$id $platform');
        }
      }
    });

    test('⇧⌘Z и ⌘Z не привязаны ни к одной записи каталога на macOS', () {
      final taken = [
        for (final s in CodeLabShortcut.values)
          for (final c in s.combosFor(_macOS)) _project(c),
      ];
      expect(
        taken,
        isNot(contains(_c(LogicalKeyboardKey.keyZ, meta: true, shift: true))),
      );
      expect(taken, isNot(contains(_c(LogicalKeyboardKey.keyZ, meta: true))));
      expect(
        taken,
        isNot(contains(_c(LogicalKeyboardKey.keyZ, primary: true))),
        reason: 'Ctrl+Z и ⌘Z — отмена правки, не ответ',
      );
    });

    test('capsFor', () {
      List<String> caps(CodeLabShortcut s, TargetPlatform p) =>
          s.combosFor(p).single.capsFor(p);
      expect(caps(CodeLabShortcut.allowOnce, _macOS), ['⌘', 'Y']);
      expect(caps(CodeLabShortcut.allowAlways, _macOS), ['⌥', '⌘', 'Y']);
      expect(caps(CodeLabShortcut.rejectOnce, _macOS), ['⌥', '⌘', 'Z']);
      expect(caps(CodeLabShortcut.rejectAlways, _macOS), ['⌥', '⇧', '⌘', 'Z']);
      for (final platform in _others) {
        expect(caps(CodeLabShortcut.allowOnce, platform), [
          'Alt',
          'Shift',
          'Y',
        ]);
        expect(caps(CodeLabShortcut.allowAlways, platform), [
          'Alt',
          'Shift',
          'Q',
        ]);
        expect(caps(CodeLabShortcut.rejectOnce, platform), [
          'Alt',
          'Shift',
          'X',
        ]);
        expect(caps(CodeLabShortcut.rejectAlways, platform), [
          'Alt',
          'Shift',
          'W',
        ]);
      }
    });

    test('compactFor — подсказки кнопок', () {
      String compact(CodeLabShortcut s, TargetPlatform p) =>
          s.combosFor(p).single.compactFor(p);
      expect(compact(CodeLabShortcut.allowOnce, _macOS), '⌘Y');
      expect(compact(CodeLabShortcut.allowAlways, _macOS), '⌥⌘Y');
      expect(compact(CodeLabShortcut.rejectOnce, _macOS), '⌥⌘Z');
      expect(compact(CodeLabShortcut.rejectAlways, _macOS), '⌥⇧⌘Z');
      for (final platform in _others) {
        expect(compact(CodeLabShortcut.allowOnce, platform), 'Alt+Shift+Y');
        expect(compact(CodeLabShortcut.allowAlways, platform), 'Alt+Shift+Q');
        expect(compact(CodeLabShortcut.rejectOnce, platform), 'Alt+Shift+X');
        expect(compact(CodeLabShortcut.rejectAlways, platform), 'Alt+Shift+W');
      }
    });

    test('spokenFor — чтение с экрана без символов', () {
      String spoken(CodeLabShortcut s, TargetPlatform p) =>
          s.combosFor(p).single.spokenFor(p);
      expect(spoken(CodeLabShortcut.allowOnce, _macOS), 'Cmd+Y');
      expect(spoken(CodeLabShortcut.allowAlways, _macOS), 'Option+Cmd+Y');
      expect(spoken(CodeLabShortcut.rejectOnce, _macOS), 'Option+Cmd+Z');
      expect(
        spoken(CodeLabShortcut.rejectAlways, _macOS),
        'Option+Shift+Cmd+Z',
      );
      for (final platform in _others) {
        expect(spoken(CodeLabShortcut.allowOnce, platform), 'Alt+Shift+Y');
        expect(spoken(CodeLabShortcut.allowAlways, platform), 'Alt+Shift+Q');
        expect(spoken(CodeLabShortcut.rejectOnce, platform), 'Alt+Shift+X');
        expect(spoken(CodeLabShortcut.rejectAlways, platform), 'Alt+Shift+W');
      }
    });

    test('searchNotations записи содержит комбинации обеих платформ', () {
      for (final platform in [_macOS, ..._others]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          CodeLabShortcut.allowOnce.searchNotations(),
          containsAll(['⌘Y', 'Cmd+Y', 'Alt+Shift+Y']),
          reason: '$platform',
        );
        expect(
          CodeLabShortcut.rejectAlways.searchNotations(),
          containsAll(['⌥⇧⌘Z', 'Option+Shift+Cmd+Z', 'Alt+Shift+W']),
          reason: '$platform',
        );
      }
    });

    testWidgets('accepts: на macOS только ⌘, на остальных только Alt+Shift', (
      tester,
    ) async {
      final meta = CodeLabShortcut.allowOnce.combosFor(_macOS).single;
      final altShift = CodeLabShortcut.allowOnce.combosFor(_others[1]).single;
      final y = KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyY,
        logicalKey: LogicalKeyboardKey.keyY,
        timeStamp: Duration.zero,
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      expect(meta.accepts(y, HardwareKeyboard.instance), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(
        meta.accepts(y, HardwareKeyboard.instance),
        isFalse,
        reason: 'Ctrl+Y на macOS — «yank», не ответ',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(altShift.accepts(y, HardwareKeyboard.instance), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(
        altShift.accepts(y, HardwareKeyboard.instance),
        isFalse,
        reason: 'Ctrl+Y на Linux — повтор правки, не ответ',
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });
  });

  group('активаторы', () {
    test('основной модификатор даёт control и meta с теми же alt и shift', () {
      for (final (shortcut, id, _, _) in _table) {
        for (final combo in shortcut.combos.where((c) => c.primary)) {
          final activators = combo.activators;
          expect(activators, hasLength(2), reason: id);
          expect(activators.map((a) => (a.control, a.meta)).toSet(), {
            (true, false),
            (false, true),
          }, reason: id);
          for (final a in activators) {
            expect(a.trigger, combo.key, reason: id);
            expect(a.alt, combo.alt, reason: id);
            expect(a.shift, combo.shift, reason: id);
          }
        }
      }
    });

    test('без основного модификатора активатор один, без control и meta', () {
      for (final (shortcut, id, _, _) in _table) {
        for (final combo in shortcut.combos.where((c) => !c.primary)) {
          final activators = combo.activators;
          // У file-tree-open к Enter добавляется numpad Enter.
          expect(activators, hasLength(1 + combo.alsoKeys.length), reason: id);
          for (final a in activators) {
            expect(a.control, isFalse, reason: id);
            expect(a.meta, isFalse, reason: id);
            expect(a.alt, combo.alt, reason: id);
            expect(a.shift, combo.shift, reason: id);
          }
        }
      }
      expect(
        _combo(CodeLabShortcut.fileTreeOpen).activators.map((a) => a.trigger),
        [LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter],
      );
    });

    test('bind привязывает действие ко всем активаторам записи', () {
      var calls = 0;
      final bindings = CodeLabShortcut.commandPalette.bind(() => calls++);
      expect(bindings, hasLength(2));
      for (final action in bindings.values) {
        action();
      }
      expect(calls, 2);
    });
  });

  group('capsFor', () {
    test('macOS: символы и порядок ⌥ ⇧ ⌘', () {
      debugDefaultTargetPlatformOverride = _macOS;
      expect(_combo(CodeLabShortcut.toggleFiles).capsFor(_macOS), [
        '⇧',
        '⌘',
        'E',
      ]);
      expect(_primaryAltEnter.capsFor(_macOS), ['⌥', '⌘', '⏎']);
      expect(_primaryBackspace.capsFor(_macOS), ['⌘', '⌫']);
      expect(_combo(CodeLabShortcut.commandPalette).capsFor(_macOS), [
        '⌘',
        'K',
      ]);
      expect(_combo(CodeLabShortcut.cancelTurn).capsFor(_macOS), ['Esc']);
      expect(_combo(CodeLabShortcut.fileTreeMove).capsFor(_macOS), ['↑']);
      expect(_combo(CodeLabShortcut.fileTreeOpen).capsFor(_macOS), ['⏎']);
    });

    test('Windows и Linux: слова и порядок Ctrl Alt Shift', () {
      for (final platform in _others) {
        debugDefaultTargetPlatformOverride = platform;
        expect(_combo(CodeLabShortcut.toggleFiles).capsFor(platform), [
          'Ctrl',
          'Shift',
          'E',
        ], reason: '$platform');
        expect(_primaryAltEnter.capsFor(platform), [
          'Ctrl',
          'Alt',
          'Enter',
        ], reason: '$platform');
        expect(_primaryBackspace.capsFor(platform), [
          'Ctrl',
          'Backspace',
        ], reason: '$platform');
        expect(_combo(CodeLabShortcut.cancelTurn).capsFor(platform), ['Esc']);
        expect(_combo(CodeLabShortcut.fileTreeMove, 1).capsFor(platform), [
          '↓',
        ]);
      }
    });
  });

  group('compactFor', () {
    // Подсказки кнопок: на Windows и Linux остаются `⏎` и `⌫` (D4), порядок
    // модификаторов общий — `Ctrl+Alt+⏎` вместо прежнего `Alt+Ctrl+⏎` (Q4).
    final expectations = <(String, CodeLabKeyCombo, String, String)>[
      (
        'commandPalette',
        _combo(CodeLabShortcut.commandPalette),
        '⌘K',
        'Ctrl+K',
      ),
      ('newSession', _combo(CodeLabShortcut.newSession), '⌘N', 'Ctrl+N'),
      ('send', _combo(CodeLabShortcut.send), '⌘⏎', 'Ctrl+⏎'),
      ('primary+Alt+Enter', _primaryAltEnter, '⌥⌘⏎', 'Ctrl+Alt+⏎'),
      ('primary+Backspace', _primaryBackspace, '⌘⌫', 'Ctrl+⌫'),
      ('primary+Alt+Backspace', _primaryAltBackspace, '⌥⌘⌫', 'Ctrl+Alt+⌫'),
      (
        'toggleFiles',
        _combo(CodeLabShortcut.toggleFiles),
        '⇧⌘E',
        'Ctrl+Shift+E',
      ),
      // Задача 2.1 `fix-approval-focus` (D3): подпись перехода к одобрению.
      (
        'goToApproval',
        _combo(CodeLabShortcut.goToApproval),
        '⇧⌘A',
        'Ctrl+Shift+A',
      ),
    ];

    test('macOS', () {
      debugDefaultTargetPlatformOverride = _macOS;
      for (final (name, combo, mac, _) in expectations) {
        expect(combo.compactFor(_macOS), mac, reason: name);
      }
    });

    test('Windows и Linux', () {
      for (final platform in _others) {
        debugDefaultTargetPlatformOverride = platform;
        for (final (name, combo, _, other) in expectations) {
          expect(combo.compactFor(platform), other, reason: '$name $platform');
        }
      }
    });
  });

  group('goToApproval (change `fix-approval-focus`, D3, D7)', () {
    test('первая запись группы approvals', () {
      final approvals = CodeLabShortcut.values
          .where((s) => s.group == CodeLabShortcutGroup.approvals)
          .toList();
      expect(approvals.first, CodeLabShortcut.goToApproval);
      expect(CodeLabShortcut.goToApproval.id, 'go-to-approval');
    });

    test('активаторы: control и meta, оба с Shift, без Alt', () {
      final activators = _combo(CodeLabShortcut.goToApproval).activators;
      expect(activators, hasLength(2));
      expect(activators.map((a) => (a.control, a.meta)).toSet(), {
        (true, false),
        (false, true),
      });
      for (final a in activators) {
        expect(a.trigger, LogicalKeyboardKey.keyA);
        expect(a.shift, isTrue);
        expect(a.alt, isFalse);
      }
    });

    test('capsFor: ⇧ ⌘ A на macOS и Ctrl Shift A на остальных', () {
      final combo = _combo(CodeLabShortcut.goToApproval);
      expect(combo.capsFor(_macOS), ['⇧', '⌘', 'A']);
      for (final platform in _others) {
        expect(combo.capsFor(platform), ['Ctrl', 'Shift', 'A']);
      }
    });

    test('spokenFor: Shift+Cmd+A и Ctrl+Shift+A', () {
      final combo = _combo(CodeLabShortcut.goToApproval);
      expect(combo.spokenFor(_macOS), 'Shift+Cmd+A');
      for (final platform in _others) {
        expect(combo.spokenFor(platform), 'Ctrl+Shift+A');
      }
    });
  });

  group('spokenFor', () {
    test('macOS: слова без символов клавиш', () {
      debugDefaultTargetPlatformOverride = _macOS;
      expect(_primaryAltEnter.spokenFor(_macOS), 'Option+Cmd+Enter');
      expect(
        _combo(CodeLabShortcut.toggleFiles).spokenFor(_macOS),
        'Shift+Cmd+E',
      );
      expect(_combo(CodeLabShortcut.fileTreeMove).spokenFor(_macOS), 'Up');
    });

    test('Windows и Linux', () {
      for (final platform in _others) {
        debugDefaultTargetPlatformOverride = platform;
        expect(_primaryAltEnter.spokenFor(platform), 'Ctrl+Alt+Enter');
        expect(
          _combo(CodeLabShortcut.toggleFiles).spokenFor(platform),
          'Ctrl+Shift+E',
        );
        expect(_combo(CodeLabShortcut.fileTreeMove).spokenFor(platform), 'Up');
      }
    });
  });

  group('searchNotations (D8)', () {
    test('все три нотации независимо от платформы', () {
      for (final platform in [_macOS, ..._others]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          _primaryAltEnter.searchNotations(),
          containsAll(['⌥⌘⏎', 'Ctrl+Alt+Enter', 'Option+Cmd+Enter']),
          reason: '$platform',
        );
        expect(
          _combo(CodeLabShortcut.commandPalette).searchNotations(),
          containsAll(['⌘K', 'Ctrl+K', 'Cmd+K']),
          reason: '$platform',
        );
      }
    });
  });

  group('accepts', () {
    KeyDownEvent down(
      LogicalKeyboardKey logical,
      PhysicalKeyboardKey physical,
    ) => KeyDownEvent(
      physicalKey: physical,
      logicalKey: logical,
      timeStamp: Duration.zero,
    );

    testWidgets('принимает свою клавишу с основным модификатором', (
      tester,
    ) async {
      final combo = _combo(CodeLabShortcut.commandPalette);
      final k = down(LogicalKeyboardKey.keyK, PhysicalKeyboardKey.keyK);
      for (final modifier in const [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        expect(combo.accepts(k, HardwareKeyboard.instance), isTrue);
        await tester.sendKeyUpEvent(modifier);
      }
    });

    testWidgets('отклоняет без модификатора, с лишним и на чужой клавише', (
      tester,
    ) async {
      final combo = _combo(CodeLabShortcut.commandPalette);
      final k = down(LogicalKeyboardKey.keyK, PhysicalKeyboardKey.keyK);
      final l = down(LogicalKeyboardKey.keyL, PhysicalKeyboardKey.keyL);

      expect(combo.accepts(k, HardwareKeyboard.instance), isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(combo.accepts(l, HardwareKeyboard.instance), isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(combo.accepts(k, HardwareKeyboard.instance), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('основной модификатор — ровно один из Ctrl и ⌘, как у '
        'SingleActivator: Ctrl+⌘+K не принимается', (tester) async {
      final combo = _combo(CodeLabShortcut.commandPalette);
      final k = down(LogicalKeyboardKey.keyK, PhysicalKeyboardKey.keyK);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      expect(combo.accepts(k, HardwareKeyboard.instance), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(combo.accepts(k, HardwareKeyboard.instance), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    });

    testWidgets('Alt и Shift требуются точно: ⏎ без Alt — не Ctrl+Alt+⏎', (
      tester,
    ) async {
      final always = _primaryAltEnter;
      final once = _combo(CodeLabShortcut.send);
      final enter = down(LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      expect(always.accepts(enter, HardwareKeyboard.instance), isFalse);
      expect(once.accepts(enter, HardwareKeyboard.instance), isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      expect(always.accepts(enter, HardwareKeyboard.instance), isTrue);
      expect(once.accepts(enter, HardwareKeyboard.instance), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    });

    testWidgets('numpad Enter принимается как alsoKeys; отпускание — нет', (
      tester,
    ) async {
      final combo = _combo(CodeLabShortcut.fileTreeOpen);
      final numpad = down(
        LogicalKeyboardKey.numpadEnter,
        PhysicalKeyboardKey.numpadEnter,
      );
      final enter = down(LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter);
      final up = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.enter,
        logicalKey: LogicalKeyboardKey.enter,
        timeStamp: Duration.zero,
      );

      expect(combo.accepts(enter, HardwareKeyboard.instance), isTrue);
      expect(combo.accepts(numpad, HardwareKeyboard.instance), isTrue);
      expect(combo.accepts(up, HardwareKeyboard.instance), isFalse);
    });

    // Раскладка ввода: каталог сравнивает логическую клавишу (D16 отклонён —
    // на настоящей macOS Flutter отдаёт латинскую логическую клавишу и при
    // русской раскладке). Защитные проверки.
    group('раскладка ввода', () {
      testWidgets('AZERTY: логическая z на физической W — это ⌥⌘Z, логическая '
          'w на физической Z — нет', (tester) async {
        final combo = CodeLabShortcut.rejectOnce
            .combosFor(TargetPlatform.macOS)
            .single;
        final printedZ = down(
          LogicalKeyboardKey.keyZ,
          PhysicalKeyboardKey.keyW,
        );
        final printedW = down(
          LogicalKeyboardKey.keyW,
          PhysicalKeyboardKey.keyZ,
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        expect(combo.accepts(printedZ, HardwareKeyboard.instance), isTrue);
        expect(combo.accepts(printedW, HardwareKeyboard.instance), isFalse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      });

      testWidgets('латинская буква на чужой позиции: логическая q на '
          'физической K — не ⌘K', (tester) async {
        final combo = _combo(CodeLabShortcut.commandPalette);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        expect(
          combo.accepts(
            down(LogicalKeyboardKey.keyQ, PhysicalKeyboardKey.keyK),
            HardwareKeyboard.instance,
          ),
          isFalse,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      });

      testWidgets('кириллица при зажатом ⌘ на физической позиции буквы '
          'сочетания не совпадает: сравнивается только логическая клавиша', (
        tester,
      ) async {
        final palette = CodeLabShortcut.commandPalette
            .combosFor(TargetPlatform.macOS)
            .first;
        final answer = CodeLabShortcut.allowOnce
            .combosFor(TargetPlatform.macOS)
            .first;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        expect(
          palette.accepts(
            down(LogicalKeyboardKey(0x043b), PhysicalKeyboardKey.keyK), // л
            HardwareKeyboard.instance,
          ),
          isFalse,
        );
        expect(
          answer.accepts(
            down(LogicalKeyboardKey(0x043d), PhysicalKeyboardKey.keyY), // н
            HardwareKeyboard.instance,
          ),
          isFalse,
        );
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      });

      testWidgets('кириллица без модификатора не совпадает', (tester) async {
        final combo = _combo(CodeLabShortcut.commandPalette);
        expect(
          combo.accepts(
            down(LogicalKeyboardKey(0x043b), PhysicalKeyboardKey.keyK),
            HardwareKeyboard.instance,
          ),
          isFalse,
        );
      });

      testWidgets('Esc и стрелки совпадают по своей клавише', (tester) async {
        final up = CodeLabShortcut.fileTreeMove.combos.first;
        final escape = _combo(CodeLabShortcut.cancelTurn);
        expect(
          escape.accepts(
            down(LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape),
            HardwareKeyboard.instance,
          ),
          isTrue,
        );
        expect(
          up.accepts(
            down(LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp),
            HardwareKeyboard.instance,
          ),
          isTrue,
        );
      });
    });
  });
}
