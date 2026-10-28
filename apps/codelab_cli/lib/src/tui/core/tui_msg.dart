import 'package:codelab_client_core/codelab_client_core.dart';

import '../../input/key_decoder.dart';
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
