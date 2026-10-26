import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_protocol/acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'prompt_queue.freezed.dart';

/// Промпт, отложенный до конца текущего хода своей сессии.
///
/// [id] уникален в пределах `ClientWorkspace` и не переиспользуется: по нему
/// UI правит и удаляет элемент, даже когда соседние элементы сдвинулись
/// (add-prompt-queue/design.md, Decisions).
@freezed
abstract class QueuedPrompt with _$QueuedPrompt {
  const factory QueuedPrompt({required String id, required String text}) =
      _QueuedPrompt;
}

/// Очередь промптов одной сессии.
///
/// Почему: пока идёт ход, агент не принимает новый `session/prompt`;
/// пользователь при этом продолжает писать, и сообщения не должны теряться
/// или уходить в чужую сессию (spec acp-client-kit «Очередь промптов на
/// сессию»; design D7).
///
/// Для чего: `SessionHandle.queue`. Элементы ставит `SessionHandle.send`,
/// когда сессия занята; после конца хода первый элемент уходит сам. Очередь
/// не сохраняется и не отправляется агенту иначе как промптом.
///
/// Как использовать: текущие элементы — [items] или `SessionView.queue`;
/// каждое изменение публикует новый `SessionView`.
abstract interface class PromptQueue {
  List<QueuedPrompt> get items;

  /// Убирает элемент [id] и возвращает его (например, чтобы вернуть текст в
  /// композер); неизвестный id — `null`.
  QueuedPrompt? remove(String id);

  /// Отправляет элемент [id] вне очереди, если сессия свободна. Занятая
  /// сессия или неизвестный id — `null`, элемент остаётся на месте: это
  /// ожидаемая гонка (кнопка нарисована до начала хода), а не ошибка.
  Future<PromptOutcome?> sendNow(String id);

  void clear();
}

/// Исход `SessionHandle.send` и отправки элемента очереди.
///
/// Почему: хосту нужно знать, ушёл ли промпт сразу или встал в очередь, и
/// чем закончился ход — в том числе ход промпта, который kit отправил из
/// очереди сам.
///
/// Для чего: результат `send`/`sendNow` и событие
/// `ClientWorkspace.promptOutcomes` (только [PromptCompleted] и
/// [PromptFailed]).
sealed class PromptOutcome {
  const PromptOutcome(this.sessionId);

  final SessionId sessionId;
}

/// Сессия занята — промпт встал в очередь как [item].
final class PromptQueued extends PromptOutcome {
  const PromptQueued(super.sessionId, this.item);

  final QueuedPrompt item;
}

/// Ход промпта завершился ответом агента ([turn] — итоговое состояние хода,
/// в том числе отменённого).
final class PromptCompleted extends PromptOutcome {
  const PromptCompleted(super.sessionId, this.turn);

  final PromptTurn turn;
}

/// Промпт не дошёл или ход сорвался; [error] — исключение `acp_client_core`.
final class PromptFailed extends PromptOutcome {
  const PromptFailed(super.sessionId, this.error);

  final Object error;
}
