import 'package:dart_tui/dart_tui.dart' as tea;

import '../input/key_decoder.dart';
import 'core/tui_model.dart';
import 'core/tui_msg.dart';

/// Перевод сообщений `dart_tui` на язык ядра экрана.
///
/// Почему: ядро не знает пакета (TUI-5), а клавиши и вставку разбирает
/// `Program` — kitty CSI u, modifyOtherKeys, bracketed paste (разведка
/// 6.11, design.md change `add-cli-tui`, D14 пункты 2–3). Перевод — одно
/// место, где встречаются `TeaKey` и наш `Key`.
///
/// Для чего: `KeyPressMsg` → [KeyMsg] (`shift+enter` и `alt+enter` —
/// отдельные клавиши, Ctrl+буква — свои `Key`); `PasteMsg` → [PasteMsg];
/// `WindowSizeMsg` → [ResizeMsg], если размер изменился; отчёты терминала
/// (`KeyboardEnhancementsMsg`, `ModeReportMsg`, начало и конец вставки) ядру
/// не нужны — `null`.
///
/// Как использовать: один экземпляр на запуск TUI; `TuiApp.update`
/// вызывает [translate] с текущим временем.
final class TuiInput {
  TerminalSize? _size;

  TuiMsg? translate(tea.Msg msg, {required DateTime now}) => switch (msg) {
    tea.KeyPressMsg(:final keyEvent) => switch (_key(keyEvent)) {
      final key? => KeyMsg(key, at: now),
      null => null,
    },
    tea.PasteMsg(:final content) => PasteMsg(content),
    tea.WindowSizeMsg(:final width, :final height) => _resize(
      TerminalSize(columns: width, rows: height),
    ),
    _ => null,
  };

  ResizeMsg? _resize(TerminalSize size) {
    if (size == _size) {
      return null;
    }
    _size = size;
    return ResizeMsg(size);
  }

  static KeyEvent? _key(tea.TeaKey key) {
    final mods = key.modifiers;
    final ctrl = mods.contains(tea.KeyMod.ctrl);
    final alt = mods.contains(tea.KeyMod.alt);
    Key? special = switch (key.code) {
      tea.KeyCode.enter when mods.contains(tea.KeyMod.shift) => Key.shiftEnter,
      tea.KeyCode.enter when alt => Key.altEnter,
      tea.KeyCode.enter => Key.enter,
      tea.KeyCode.tab => Key.tab,
      tea.KeyCode.backspace => Key.backspace,
      tea.KeyCode.delete => Key.delete,
      tea.KeyCode.escape => Key.escape,
      tea.KeyCode.up => Key.up,
      tea.KeyCode.down => Key.down,
      tea.KeyCode.left => Key.left,
      tea.KeyCode.right => Key.right,
      tea.KeyCode.home => Key.home,
      tea.KeyCode.end => Key.end,
      tea.KeyCode.pageUp => Key.pageUp,
      tea.KeyCode.pageDown => Key.pageDown,
      _ => null,
    };
    if (special != null) {
      return SpecialKey(special);
    }
    final text = key.text.isNotEmpty
        ? key.text
        : key.code == tea.KeyCode.space
        ? ' '
        : key.codePoint == null
        ? ''
        : String.fromCharCode(key.codePoint!);
    if (ctrl) {
      special = switch (text.toLowerCase()) {
        'a' => Key.ctrlA,
        'c' => Key.ctrlC,
        'd' => Key.ctrlD,
        'e' => Key.ctrlE,
        'l' => Key.ctrlL,
        'u' => Key.ctrlU,
        _ => null,
      };
      return special == null ? null : SpecialKey(special);
    }
    if (alt || text.isEmpty) {
      return null;
    }
    return TextKey(text);
  }
}
