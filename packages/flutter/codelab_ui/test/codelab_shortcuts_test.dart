// Каталог сочетаний `CodeLabShortcut` (задача 1.1 change
// `add-app-keyboard-page`; design.md D1, D2, D4; spec app-settings «Страница
// «Keyboard»: обозначения клавиш» и «…строки таблицы»).
//
// Красный до задачи 1.4: каталог — заглушка без комбинаций и поведения.
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
  List<LogicalKeyboardKey> also,
});

_Combo _c(
  LogicalKeyboardKey key, {
  bool primary = false,
  bool alt = false,
  bool shift = false,
  List<LogicalKeyboardKey> also = const [],
}) => (key: key, primary: primary, alt: alt, shift: shift, also: also);

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
    CodeLabShortcut.allowOnce,
    'allow-once',
    CodeLabShortcutGroup.approvals,
    [_c(LogicalKeyboardKey.enter, primary: true)],
  ),
  (
    CodeLabShortcut.allowAlways,
    'allow-always',
    CodeLabShortcutGroup.approvals,
    [_c(LogicalKeyboardKey.enter, primary: true, alt: true)],
  ),
  (
    CodeLabShortcut.rejectOnce,
    'reject-once',
    CodeLabShortcutGroup.approvals,
    [_c(LogicalKeyboardKey.backspace, primary: true)],
  ),
  (
    CodeLabShortcut.rejectAlways,
    'reject-always',
    CodeLabShortcutGroup.approvals,
    [_c(LogicalKeyboardKey.backspace, primary: true, alt: true)],
  ),
];

const _macOS = TargetPlatform.macOS;
const _others = [TargetPlatform.windows, TargetPlatform.linux];

CodeLabKeyCombo _combo(CodeLabShortcut shortcut, [int index = 0]) =>
    shortcut.combos[index];

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  group('записи по таблице D1', () {
    test('19 записей по порядку и группам', () {
      expect(CodeLabShortcut.values, [for (final row in _table) row.$1]);
      expect(CodeLabShortcut.values.map((s) => s.group).toList(), [
        for (final row in _table) row.$3,
      ]);
    });

    test('id — kebab-case из спецификации', () {
      expect(CodeLabShortcut.values.map((s) => s.id).toList(), [
        for (final row in _table) row.$2,
      ]);
    });

    test('комбинации записей совпадают с таблицей', () {
      for (final (shortcut, id, _, combos) in _table) {
        expect(
          [
            for (final c in shortcut.combos)
              (
                key: c.key,
                primary: c.primary,
                alt: c.alt,
                shift: c.shift,
                also: c.alsoKeys,
              ),
          ],
          combos,
          reason: id,
        );
      }
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
      expect(_combo(CodeLabShortcut.allowAlways).capsFor(_macOS), [
        '⌥',
        '⌘',
        '⏎',
      ]);
      expect(_combo(CodeLabShortcut.rejectOnce).capsFor(_macOS), ['⌘', '⌫']);
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
        expect(_combo(CodeLabShortcut.allowAlways).capsFor(platform), [
          'Ctrl',
          'Alt',
          'Enter',
        ], reason: '$platform');
        expect(_combo(CodeLabShortcut.rejectOnce).capsFor(platform), [
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
    final expectations = <(CodeLabShortcut, String, String)>[
      (CodeLabShortcut.commandPalette, '⌘K', 'Ctrl+K'),
      (CodeLabShortcut.newSession, '⌘N', 'Ctrl+N'),
      (CodeLabShortcut.send, '⌘⏎', 'Ctrl+⏎'),
      (CodeLabShortcut.allowOnce, '⌘⏎', 'Ctrl+⏎'),
      (CodeLabShortcut.allowAlways, '⌥⌘⏎', 'Ctrl+Alt+⏎'),
      (CodeLabShortcut.rejectOnce, '⌘⌫', 'Ctrl+⌫'),
      (CodeLabShortcut.rejectAlways, '⌥⌘⌫', 'Ctrl+Alt+⌫'),
      (CodeLabShortcut.toggleFiles, '⇧⌘E', 'Ctrl+Shift+E'),
    ];

    test('macOS', () {
      debugDefaultTargetPlatformOverride = _macOS;
      for (final (shortcut, mac, _) in expectations) {
        expect(_combo(shortcut).compactFor(_macOS), mac, reason: shortcut.name);
      }
    });

    test('Windows и Linux', () {
      for (final platform in _others) {
        debugDefaultTargetPlatformOverride = platform;
        for (final (shortcut, _, other) in expectations) {
          expect(
            _combo(shortcut).compactFor(platform),
            other,
            reason: '${shortcut.name} $platform',
          );
        }
      }
    });
  });

  group('spokenFor', () {
    test('macOS: слова без символов клавиш', () {
      debugDefaultTargetPlatformOverride = _macOS;
      expect(
        _combo(CodeLabShortcut.allowAlways).spokenFor(_macOS),
        'Option+Cmd+Enter',
      );
      expect(
        _combo(CodeLabShortcut.toggleFiles).spokenFor(_macOS),
        'Shift+Cmd+E',
      );
      expect(_combo(CodeLabShortcut.fileTreeMove).spokenFor(_macOS), 'Up');
    });

    test('Windows и Linux', () {
      for (final platform in _others) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          _combo(CodeLabShortcut.allowAlways).spokenFor(platform),
          'Ctrl+Alt+Enter',
        );
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
          _combo(CodeLabShortcut.allowAlways).searchNotations(),
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

    testWidgets('Alt и Shift требуются точно: ⏎ без Alt — не allow-always', (
      tester,
    ) async {
      final always = _combo(CodeLabShortcut.allowAlways);
      final once = _combo(CodeLabShortcut.allowOnce);
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
  });
}
