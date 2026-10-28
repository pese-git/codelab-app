// Перевод сообщений dart_tui в язык ядра экрана (tasks 3.1 change
// `add-cli-tui`; spec codelab-tui «Граница ядра экрана и адаптера»;
// design.md, D7; разведка 6.11, D14 пункт 3).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:dart_tui/dart_tui.dart' as tea;
import 'package:test/test.dart';

tea.KeyPressMsg _press(
  tea.KeyCode code, {
  String text = '',
  Set<tea.KeyMod> mods = const {},
}) => tea.KeyPressMsg(tea.TeaKey(code: code, text: text, modifiers: mods));

void main() {
  final now = DateTime.utc(2026, 10, 28);
  late TuiInput input;

  setUp(() => input = TuiInput());

  KeyEvent? key(tea.Msg msg) => switch (input.translate(msg, now: now)) {
    KeyMsg(:final key) => key,
    _ => null,
  };

  test('special keys', () {
    expect(key(_press(tea.KeyCode.enter)), const SpecialKey(Key.enter));
    expect(
      key(_press(tea.KeyCode.enter, mods: {tea.KeyMod.shift})),
      const SpecialKey(Key.shiftEnter),
    );
    expect(
      key(_press(tea.KeyCode.enter, mods: {tea.KeyMod.alt})),
      const SpecialKey(Key.altEnter),
    );
    expect(key(_press(tea.KeyCode.escape)), const SpecialKey(Key.escape));
    expect(key(_press(tea.KeyCode.pageUp)), const SpecialKey(Key.pageUp));
    expect(key(_press(tea.KeyCode.pageDown)), const SpecialKey(Key.pageDown));
    expect(key(_press(tea.KeyCode.end)), const SpecialKey(Key.end));
    expect(key(_press(tea.KeyCode.backspace)), const SpecialKey(Key.backspace));
    expect(key(_press(tea.KeyCode.tab)), const SpecialKey(Key.tab));
  });

  test('control letters', () {
    for (final (letter, expected) in [
      ('c', Key.ctrlC),
      ('d', Key.ctrlD),
      ('a', Key.ctrlA),
      ('e', Key.ctrlE),
      ('l', Key.ctrlL),
      ('u', Key.ctrlU),
    ]) {
      expect(
        key(_press(tea.KeyCode.rune, text: letter, mods: {tea.KeyMod.ctrl})),
        SpecialKey(expected),
        reason: letter,
      );
    }
  });

  test('printable text', () {
    expect(key(_press(tea.KeyCode.rune, text: 'я')), const TextKey('я'));
    expect(key(_press(tea.KeyCode.space, text: ' ')), const TextKey(' '));
  });

  test('the key time comes from the clock', () {
    final msg = input.translate(_press(tea.KeyCode.enter), now: now);

    expect((msg! as KeyMsg).at, now);
  });

  test('paste and size', () {
    expect(
      input.translate(tea.PasteMsg('a\nb'), now: now),
      isA<PasteMsg>().having((m) => m.text, 'text', 'a\nb'),
    );
    expect(
      input.translate(tea.WindowSizeMsg(100, 30), now: now),
      isA<ResizeMsg>().having(
        (m) => m.size,
        'size',
        const TerminalSize(columns: 100, rows: 30),
      ),
    );
    expect(
      input.translate(tea.WindowSizeMsg(100, 30), now: now),
      isNull,
      reason: 'the same size again',
    );
  });

  test('terminal reports do not reach the core', () {
    for (final msg in <tea.Msg>[
      tea.PasteStartMsg(),
      tea.PasteEndMsg(),
      tea.KeyboardEnhancementsMsg(1),
      tea.ModeReportMsg(mode: 2026, value: 2),
    ]) {
      expect(input.translate(msg, now: now), isNull, reason: '$msg');
    }
  });
}
