import 'package:dart_tui/dart_tui.dart' as tea;

import '../input/key_bindings.dart';

/// Реестр клавиш TUI как `KeyMap` `dart_tui` — источник строки подсказок.
///
/// Почему: строку подсказок рисует компонент пакета `HelpModel`, а
/// таблица действий остаётся одна — [KeyBindings.tui]; подсказка не может
/// разойтись с обработкой клавиш (TUI-7; §12.2.7, «Компоненты dart_tui»;
/// design.md change `add-cli-tui`, D12).
///
/// Для чего: на каждое действие из [hinted] — одна привязка со всеми его
/// клавишами и короткой подписью.
///
/// Как использовать: `TuiApp` строит `HelpModel.fromKeyMap(RegistryKeyMap())`
/// и сворачивает его вывод в одну строку ([hintLine]).
final class RegistryKeyMap implements tea.KeyMap {
  RegistryKeyMap([this._keys]);

  final KeyBindings? _keys;

  /// Действия строки подсказок и их короткие подписи.
  static const hinted = {
    KeyAction.submit: 'send',
    KeyAction.newline: 'new line',
    KeyAction.cancelTurn: 'cancel',
    KeyAction.scrollUp: 'scroll',
    KeyAction.exit: 'exit',
  };

  @override
  List<tea.KeyBinding> get bindings {
    final keys = _keys ?? KeyBindings.tui;
    return [
      for (final MapEntry(key: action, value: label) in hinted.entries)
        if (keys.bindings.where((b) => b.action == action).toList()
            case final bound when bound.isNotEmpty)
          tea.KeyBinding(
            keys: [for (final b in bound) b.key.label],
            help: (
              key: {for (final b in bound) b.key.label}.join('/'),
              description: label,
            ),
          ),
    ];
  }
}

/// Вывод `HelpModel` одной строкой: без заголовка, пункты через ` · `.
String hintLine(tea.HelpModel help) => help
    .view()
    .content
    .split('\n')
    .map((line) => line.trim().replaceAll(RegExp(' {2,}'), ' '))
    // Пустой заголовок тоже может прийти со стилем: пустой — без SGR.
    .where((line) => line.replaceAll(RegExp('\x1b\\[[0-9;]*m'), '').isNotEmpty)
    .join(' · ');
