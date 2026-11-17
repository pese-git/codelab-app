import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import 'usage_models.dart';

part 'usage_ledger_models.freezed.dart';

/// Откуда агент взял журнал (`ledger.status`, change `add-usage-ledger`, D6).
enum UsageLedgerStatus { upToDate, rebuilt, inMemory, notSaved }

/// Шаг модели хода журнала (D6, D10).
///
/// Почему отдельно от `UsageTotals`: у шага свой состав — модель и вызовы
/// инструментов, по которым хост подписывает шаг по транскрипту (D6:
/// `toolCallIds` у шага всегда, пустой список без вызовов).
///
/// ЗАГЛУШКА красных тестов 3.2/3.3: модель — задача 3.9.
@freezed
abstract class UsageLedgerStep with _$UsageLedgerStep {
  const factory UsageLedgerStep({
    required int index,
    required TokenCounts tokens,
    String? model,
    Money? cost,
    @Default(<UsagePartial>{}) Set<UsagePartial> partial,
    @Default(<String>[]) List<String> toolCallIds,
  }) = _UsageLedgerStep;
}

/// Прогоны субагентов или вызовы суммаризатора (D6: `subagents`,
/// `summaries`): число, токены, цена.
@freezed
abstract class UsageLedgerGroup with _$UsageLedgerGroup {
  const factory UsageLedgerGroup({
    /// `runs` у субагентов, `count` у суммаризатора.
    required int count,
    required TokenCounts tokens,
    Money? cost,
    @Default(<UsagePartial>{}) Set<UsagePartial> partial,
  }) = _UsageLedgerGroup;
}

/// Ход журнала (D6, D10).
@freezed
abstract class UsageLedgerTurn with _$UsageLedgerTurn {
  const factory UsageLedgerTurn({
    required int index,
    required UsageTotals total,

    /// Слова пользователя; `null` — у хода их не было.
    String? title,

    /// Ход идёт в момент построения журнала (только у последнего).
    @Default(false) bool running,
    @Default(<UsageLedgerStep>[]) List<UsageLedgerStep> steps,
    UsageLedgerGroup? subagents,
  }) = _UsageLedgerTurn;
}

/// Строка «по моделям» журнала (D6: `models`).
@freezed
abstract class UsageLedgerModel with _$UsageLedgerModel {
  const factory UsageLedgerModel({
    required String model,
    required int steps,
    required TokenCounts tokens,
    Money? cost,
    @Default(<UsagePartial>{}) Set<UsagePartial> partial,
  }) = _UsageLedgerModel;
}

/// Разобранный ответ `_codelab/session/usage/ledger` (D6, D10).
///
/// Почему: хост показывает историю расхода сессии, а форма на проводе
/// остаётся внутри `UsageLedgerDecoder` (`AGENTS.md` пакета §5).
///
/// Для чего: содержимое `UsageLedgerLoaded.view`. Kit со снимками usage не
/// сливает: хост сравнивает [seq] с `UsageView.lastSeq` (D10, R8).
@freezed
abstract class UsageLedgerView with _$UsageLedgerView {
  const factory UsageLedgerView({
    required SessionId sessionId,

    /// Последний `seq` снимков usage к моменту построения (0 — не было).
    required int seq,

    /// Сумма всего журнала; `steps` и `partial` — как в D6.
    required UsageTotals total,

    /// Число ходов суммы (`total.turns` ответа).
    @Default(0) int turnCount,
    UsageLedgerStatus? status,

    /// Причина пересчёта (`ledger.reason`), только при `rebuilt`.
    String? reason,
    int? records,
    @Default(<UsageLedgerTurn>[]) List<UsageLedgerTurn> turns,
    @Default(<UsageLedgerModel>[]) List<UsageLedgerModel> models,
    UsageLedgerGroup? subagents,
    UsageLedgerGroup? summaries,
  }) = _UsageLedgerView;
}

/// Вид сбоя запроса журнала.
enum UsageLedgerFailureKind {
  /// Агент ответил ошибкой JSON-RPC; код — в [UsageLedgerFailure.code].
  agentError,

  /// Ответ не разобрался (нет `sessionId`, `seq` или `total.tokens`).
  decode,

  /// Запрос не ушёл или не получил ответа (таймаут, обрыв).
  request,
}

/// Причина состояния `failed` (D10).
@freezed
abstract class UsageLedgerFailure with _$UsageLedgerFailure {
  const factory UsageLedgerFailure({
    required UsageLedgerFailureKind kind,

    /// Код ошибки JSON-RPC при [UsageLedgerFailureKind.agentError].
    int? code,
  }) = _UsageLedgerFailure;
}

/// Состояние журнала usage сессии — закрытая иерархия, не набор флагов
/// (`AGENTS.md` §8; D10).
@freezed
sealed class UsageLedgerState with _$UsageLedgerState {
  const UsageLedgerState._();

  /// Агент не объявил `usageLedger`.
  const factory UsageLedgerState.unavailable() = UsageLedgerUnavailable;

  /// Объявил, журнал не запрашивали (или сброшен переподключением/загрузкой).
  const factory UsageLedgerState.idle() = UsageLedgerIdle;

  /// Запрос в полёте; [previous] — прежний журнал, если был.
  const factory UsageLedgerState.loading({UsageLedgerView? previous}) =
      UsageLedgerLoading;

  const factory UsageLedgerState.loaded(UsageLedgerView view) =
      UsageLedgerLoaded;

  /// Сбой; [previous] — прежний журнал, если был.
  const factory UsageLedgerState.failed(
    UsageLedgerFailure reason, {
    UsageLedgerView? previous,
  }) = UsageLedgerFailed;
}
