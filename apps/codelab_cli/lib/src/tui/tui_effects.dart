import 'dart:async';

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:dart_tui/dart_tui.dart' as tea;

import '../input/history.dart';
import 'core/tui_cmd.dart';
import 'core/tui_msg.dart';

/// Сообщение ядра экрана внутри цикла `dart_tui`: событие kit или
/// результат команды.
final class DomainMsg extends tea.Msg {
  DomainMsg(this.msg);

  final TuiMsg msg;
}

/// Исполнение команд ядра экрана — единственный владелец сессии в TUI.
///
/// Почему: `reduce` возвращает команды-данные, а ввод-вывод собран здесь,
/// в функциях `Cmd` пакета (TUI-5; §12.2.7, шаг 7; design.md change
/// `add-cli-tui`, D7).
///
/// Для чего: [SubmitCmd] — `SessionHandle.send` (очередь kit),
/// [CancelTurnCmd] — `cancel`, [RespondCmd] — `respond` (D9),
/// [RunCommandCmd] — [runCommand],
/// [SaveHistoryCmd] — [history], [QuitCmd] — код в [onQuit] и `QuitMsg`.
/// Исключение команды возвращается `DomainMsg(EffectFailedMsg)`: иначе
/// обработчик пакета напечатал бы его поверх кадра и завершил программу.
///
/// Как использовать: `TuiApp` переводит список команд [toDartTuiCmd];
/// [session] читается в момент исполнения — после `/resume` это новая
/// сессия.
final class TuiEffects {
  TuiEffects({
    required SessionHandle Function() session,
    required HistoryStore history,
    required void Function(int code) onQuit,
    required Future<void> Function(String line) runCommand,
  }) : _session = session,
       _history = history,
       _onQuit = onQuit,
       _runCommand = runCommand;

  final SessionHandle Function() _session;
  final HistoryStore _history;
  final void Function(int code) _onQuit;
  final Future<void> Function(String line) _runCommand;

  /// Один `Cmd` на список команд: несколько — `batch`, пусто — `null`.
  tea.Cmd? toDartTuiCmd(List<TuiCmd> cmds) {
    final out = [for (final cmd in cmds) _cmd(cmd)];
    return switch (out.length) {
      0 => null,
      1 => out.single,
      _ => tea.batch(out),
    };
  }

  tea.Cmd _cmd(TuiCmd cmd) => switch (cmd) {
    SubmitCmd(:final text) => _guarded(() => _session().send(text)),
    CancelTurnCmd() => _guarded(() => _session().cancel()),
    RespondCmd(:final approvalId, :final optionId) => _guarded(
      () => _session().respond(approvalId, optionId),
    ),
    RunCommandCmd(:final line) => _guarded(() => _runCommand(line)),
    SaveHistoryCmd(:final entries) => _guarded(() => _history.save(entries)),
    QuitCmd(:final code) => () {
      _onQuit(code);
      return tea.QuitMsg();
    },
  };

  static tea.Cmd _guarded(Future<Object?> Function() action) => () async {
    try {
      await action();
      return null;
    } on Object catch (error) {
      return DomainMsg(EffectFailedMsg(error));
    }
  };
}
