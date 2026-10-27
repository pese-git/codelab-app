import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import '../exit_codes.dart';

/// Исход headless-прогона.
///
/// Почему: код выхода — контракт со скриптами и CI, и он вычисляется из
/// ответа `session/prompt`, ошибок и сигналов, а не из текста транскрипта
/// (H-02, документ ядра §13). Закрытая иерархия делает каждый исход явным
/// (design.md change `add-codelab-cli`, D9).
///
/// Как использовать: `HeadlessRunner.run` возвращает исход, `exitCodeOf` —
/// код выхода процесса.
sealed class HeadlessOutcome {
  const HeadlessOutcome();
}

/// Агент ответил на `session/prompt`; [hadText] — в ходе был хотя бы один
/// непустой `agent_message_chunk`.
final class TurnCompleted extends HeadlessOutcome {
  const TurnCompleted(this.stopReason, {required this.hadText});

  final StopReason? stopReason;
  final bool hadText;
}

/// `session/prompt` завершился ошибкой: JSON-RPC ошибка агента или обрыв.
final class TurnFailed extends HeadlessOutcome {
  const TurnFailed(this.message);

  final String message;
}

/// Не удалось подключиться к агенту или открыть сессию.
final class ConnectFailed extends HeadlessOutcome {
  const ConnectFailed(this.message);

  final String message;
}

/// Истёк `--timeout`: ход отменён `session/cancel`.
final class TimedOut extends HeadlessOutcome {
  const TimedOut();
}

/// Прогон прерван сигналом; [code] — `130` или `143`.
final class Signalled extends HeadlessOutcome {
  const Signalled(this.code);

  final int code;
}

/// Код выхода по исходу — единственное место таблицы кодов headless
/// (`09-11-stage-6-cli-mvp.md`, «Headless»; spec cli-headless «Коды выхода
/// headless»).
int exitCodeOf(HeadlessOutcome outcome) => switch (outcome) {
  TurnCompleted(stopReason: StopReason.endTurn, hadText: true) => okExit,
  TurnCompleted(stopReason: StopReason.cancelled) => sigintExit,
  TurnCompleted() => failureExit,
  TurnFailed() || ConnectFailed() => failureExit,
  TimedOut() => sigintExit,
  Signalled(:final code) => code,
};
