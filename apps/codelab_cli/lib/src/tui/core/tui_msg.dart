import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_setup/codelab_setup.dart'
    show AgentConfigSnapshot, ConfigTarget, ProviderSetupState, SettingsAccess;

import '../../input/key_decoder.dart';
import '../../render/terminal_renderer.dart';
import '../../repl/picker_spec.dart';
import 'tui_model.dart';

/// Сообщение ядра экрана: ввод пользователя, событие kit или результат
/// команды, уже переведённые с языка `dart_tui`.
///
/// Почему: `reduce` — чистая функция и не знает пакета (TUI-5); адаптер
/// `TuiInput` переводит сообщения пакета в эти, а `TuiRunner` — события kit
/// (§12.2.7; design.md change `add-cli-tui`, D5).
///
/// Как использовать: время, от которого зависит решение (двойной Ctrl+C,
/// начало хода), приходит в самом сообщении — его ставит адаптер.
sealed class TuiMsg {
  const TuiMsg();
}

/// Клавиша; [at] — когда она пришла.
final class KeyMsg extends TuiMsg {
  const KeyMsg(this.key, {required this.at});

  final KeyEvent key;
  final DateTime at;
}

/// Bracketed paste: текст целиком, без отправки (TUI-3).
final class PasteMsg extends TuiMsg {
  const PasteMsg(this.text);

  final String text;
}

final class ResizeMsg extends TuiMsg {
  const ResizeMsg(this.size);

  final TerminalSize size;
}

/// Ревизия сессии; [at] — когда её получил адаптер (начало хода).
final class SessionViewMsg extends TuiMsg {
  const SessionViewMsg(this.view, {required this.at});

  final SessionView view;
  final DateTime at;
}

/// Активной стала другая сессия (`/new`, `/resume`, `/profile`): её
/// ревизия заменяет транскрипт без сравнения номеров — у каждой сессии свой
/// счётчик ревизий (D10).
final class SessionAttachedMsg extends TuiMsg {
  const SessionAttachedMsg(this.view, {required this.at});

  final SessionView view;
  final DateTime at;
}

/// Строка клиента в транскрипт: вывод команды, ошибка.
final class NoteMsg extends TuiMsg {
  const NoteMsg(this.text);

  final String text;
}

/// Команда не выполнилась; причина — заметкой в транскрипт.
final class EffectFailedMsg extends TuiMsg {
  const EffectFailedMsg(this.error);

  final Object error;
}

/// Команда без аргумента просит выбрать из списка: открыть пикер (D10).
final class OpenPickerMsg extends TuiMsg {
  const OpenPickerMsg(this.spec);

  final PickerSpec spec;
}

/// В пикере выбран пункт [index] списка `PickerSpec.items`.
final class PickerChosenMsg extends TuiMsg {
  const PickerChosenMsg(this.index);

  final int index;
}

/// Пикер закрыт без выбора (Esc).
final class PickerClosedMsg extends TuiMsg {
  const PickerClosedMsg();
}

/// `/thoughts`: новый режим показа мыслей.
final class ThoughtsMsg extends TuiMsg {
  const ThoughtsMsg(this.mode);

  final ThoughtsMode mode;
}

/// `/clear`: заметки клиента убираются из транскрипта.
final class ClearNotesMsg extends TuiMsg {
  const ClearNotesMsg();
}

/// Открыть мастер `/provider add` с номером [id] на состоянии [state]
/// (design.md change `add-provider-setup-ui`, D17). [pathOf] даёт путь файла
/// слоя для сводки.
final class OpenWizardMsg extends TuiMsg {
  const OpenWizardMsg(this.id, this.state, {this.pathOf});

  final int id;
  final ProviderSetupState state;
  final String Function(ConfigTarget target)? pathOf;
}

/// Новое состояние автомата для мастера с номером [id]; чужой номер
/// игнорируется (поздние состояния прошлого мастера, AGENTS.md §9).
final class WizardStateMsg extends TuiMsg {
  const WizardStateMsg(this.id, this.state);

  final int id;
  final ProviderSetupState state;
}

/// Открыть экран `/settings` с номером [id]; [snapshot] — `null` для чужого
/// агента (локальный конфиг ему не принадлежит, SETUP-2).
final class OpenSettingsMsg extends TuiMsg {
  const OpenSettingsMsg(this.id, {required this.access, this.snapshot});

  final int id;
  final SettingsAccess access;
  final AgentConfigSnapshot? snapshot;
}

/// Исход записи экрана настроек: строка [line] и новый снимок [snapshot].
final class SettingsAppliedMsg extends TuiMsg {
  const SettingsAppliedMsg(this.id, {required this.line, this.snapshot});

  final int id;
  final String line;

  /// `null` — снимок перечитать не удалось: экран остаётся на старом и выходит
  /// из режима записи (D21).
  final AgentConfigSnapshot? snapshot;
}
