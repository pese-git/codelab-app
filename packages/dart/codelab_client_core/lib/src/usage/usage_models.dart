import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'usage_models.freezed.dart';

/// Знает ли клиент о расходе сессии и пришло ли что-нибудь.
///
/// Почему три значения, а не `bool`: «агент не умеет» и «агент умеет, но
/// ещё не прислал» показываются по-разному (`usage: —` и ожидание), а
/// невозможное «пришло, но не умеет» не должно быть выразимо (VIEW-6,
/// `AGENTS.md` §8).
///
/// Для чего: [UsageView.support] — единственный признак, по которому хост
/// решает, рисовать ли сегменты токенов, денег и контекста.
enum UsageSupport {
  /// Агент не объявил `usage` и ничего не прислал: числа не рисуются
  /// (не «0»).
  unknown,

  /// Агент объявил `usage`, снимков ещё нет.
  awaiting,

  /// Принят хотя бы один снимок текущего соединения.
  reported,
}

/// Причина неполноты суммы (D6): клиент ставит перед числом «~».
///
/// Незнакомые строки провода декодер отбрасывает (D2, правила
/// совместимости).
enum UsagePartial {
  /// Провайдер не прислал usage у успешного ответа: токены занижены.
  noUsage,

  /// У модели нет цены: стоимость занижена или неизвестна.
  noPrice,

  /// Сессия открыта через `session/load`: ранние ходы в сумму не вошли.
  beforeLoad,
}

/// Что вызвало снимок (D2).
enum UsageTrigger {
  step,
  turn,
  compaction,

  /// Незнакомое значение: снимок принимается как снимок без шага (D2).
  unknown,
}

/// Токены агрегата (D2): целые ≥ 0.
@freezed
abstract class TokenCounts with _$TokenCounts {
  const factory TokenCounts({
    required int input,
    required int output,
    required int cacheRead,
    required int cacheWrite,

    /// Только если провайдер сообщил (как `Usage.toJson` агента).
    int? reasoning,
  }) = _TokenCounts;
}

/// Деньги в целых микроединицах валюты (D9).
///
/// Почему не `double`: сумма дробных долларов в двоичной дроби накапливает
/// ошибку, а на проводе стоимость — десятичная строка до 6 знаков, которая
/// точно ложится в целое число микроединиц.
///
/// Для чего: единственное представление стоимости в `UsageView`. Клиент
/// стоимость не суммирует — суммы приходят готовыми от агента.
@freezed
abstract class Money with _$Money {
  const factory Money({
    /// Миллионные доли [currency] (`"0.000001"` → 1).
    required int micros,

    /// Код ISO 4217 из корня снимка; в v1 — `USD`.
    required String currency,
  }) = _Money;
}

/// Агрегат расхода: ход или сессия (D2, D8).
@freezed
abstract class UsageTotals with _$UsageTotals {
  const factory UsageTotals({
    required TokenCounts tokens,

    /// `null` — цена неизвестна целиком: хост показывает «—», не `$0` (D9).
    Money? cost,

    /// Число шагов модели агрегата (`steps`; 0, если агент не прислал).
    @Default(0) int steps,

    /// Причины неполноты (D6); пусто — сумма полная.
    @Default(<UsagePartial>{}) Set<UsagePartial> partial,
  }) = _UsageTotals;
}

/// Заполнение окна контекста модели (D5): считает агент, клиент не оценивает.
@freezed
abstract class ContextFillView with _$ContextFillView {
  const ContextFillView._();

  const factory ContextFillView({
    /// Занято токенов.
    required int used,

    /// Размер окна; `null` — агент не прислал.
    int? size,

    /// Порог автосжатия; `null` — автосжатие выключено (Q3 (б)).
    int? compactAt,
  }) = _ContextFillView;

  /// Доля занятого окна; `null` без размера или при нулевом размере.
  double? get fraction {
    final size = this.size;
    return size == null || size <= 0 ? null : used / size;
  }

  /// Подпись «скоро сжатие»: `used ≥ 0.9 × compactAt` (решение Q3 (б)).
  ///
  /// Сравнение в целых без `double` и без умножения: `used·10 ≥ compactAt·9`
  /// равносильно `used ≥ compactAt − ⌊compactAt/10⌋` (потолок от 0.9·compactAt),
  /// а умножение огромных значений с провода переполнило бы `int` на VM и
  /// дало бы неверный ответ. Без `compactAt` — всегда `false`.
  bool get compactionSoon {
    final compactAt = this.compactAt;
    return compactAt != null && used >= compactAt - compactAt ~/ 10;
  }
}

/// Расход сессии для отображения (`SessionView.usage`, D8).
///
/// Почему: расход — не часть автомата хода; хосты (desktop, CLI) только
/// рисуют готовые числа агента, а политика «что считается новым снимком»
/// живёт в `UsageFold` (VIEW-6, §12.1.5).
///
/// Для чего: `SessionView.usage`. По умолчанию — [UsageSupport.unknown].
@freezed
abstract class UsageView with _$UsageView {
  const factory UsageView({
    @Default(UsageSupport.unknown) UsageSupport support,

    /// Агрегат хода последнего снимка с `turnId` (идущий или завершённый).
    /// Привязан к `turnId` (D8): новый ход без разобранного `turn` даёт
    /// `null`, а не агрегат прошлого хода.
    UsageTotals? lastTurn,

    /// Все ходы сессии, видимые агенту (после `session/load` — неполно,
    /// `UsagePartial.beforeLoad`).
    UsageTotals? session,
    ContextFillView? context,

    /// `seq` последнего применённого снимка; 0 — снимков нет.
    @Default(0) int lastSeq,
  }) = _UsageView;
}

/// Разобранный снимок `_codelab/session/usage` (D2): вход `UsageFold`.
///
/// Почему отдельно от [UsageView]: снимок — одно уведомление, а вид — то,
/// что осталось после свёртки многих.
final class UsageSnapshot {
  const UsageSnapshot({
    required this.sessionId,
    required this.seq,
    required this.trigger,
    required this.session,
    this.turnId,
    this.turn,
    this.context,
  });

  final SessionId sessionId;

  /// Номер снимка сессии агента, ≥ 1 (D7).
  final int seq;
  final UsageTrigger trigger;

  /// Есть при `step` и `turn`.
  final String? turnId;
  final UsageTotals? turn;
  final UsageTotals session;
  final ContextFillView? context;
}
