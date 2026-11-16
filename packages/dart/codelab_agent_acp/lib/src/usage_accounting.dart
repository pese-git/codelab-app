import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Ключ `_meta.codelab` согласован: значение — объект с целым `version: 1`
/// (design.md change `add-usage-extension`, D9; `add-subagents-and-tasks`,
/// D9).
///
/// Почему одна функция: правило версии одно для всех расширений CodeLab, а
/// копии в трёх местах (`usageConsent`, `subagentToolCallsConsent`,
/// согласование в `initialize`) расходились бы при следующей правке. Любое
/// другое значение (`2`, `'1'`, `1.5`, не объект) — согласия нет: агент
/// молчит, а не гадает о версии (`15-Extensibility.md`, согласование).
///
/// Как использовать: [meta] — `_meta` клиентских возможностей; читать из
/// `ClientLink.capabilities` в момент события, а не при `initialize`, потому
/// что после переподключения объявление клиента может смениться.
bool codelabKeyAgreed(Map<String, Object?>? meta, String key) {
  final codelab = meta?['codelab'];
  if (codelab is! Map) {
    return false;
  }
  final extension = codelab[key];
  if (extension is! Map) {
    return false;
  }
  final version = extension['version'];
  return version is int && version == 1;
}

/// Согласие клиента на уведомления `_codelab/session/usage`:
/// `clientCapabilities._meta.codelab.usage` (D3, D9, D18 Т4).
///
/// Для чего: мост читает согласие из `ClientLink.capabilities` в момент
/// события; правило версии — в [codelabKeyAgreed].
bool usageConsent(acp.ClientCapabilities capabilities) =>
    codelabKeyAgreed(capabilities.meta, 'usage');

/// Метод уведомления агент → клиент с usage сессии (design.md change
/// `add-usage-extension`, D1, D17: имя с `_`, без `id`).
const usageNotificationMethod = '_codelab/session/usage';

/// Причины неполноты `partial`, версия 1 (D6). Порядок значений — порядок
/// строк таблицы D6 и порядок в массиве на проводе (D19 п. 2).
enum UsagePartial { noUsage, noPrice, beforeLoad }

/// Суммы usage: шаг, ход или сессия (D2, «Агрегат»).
///
/// Почему отдельный изменяемый класс: агрегат ходов и сессии складывается из
/// кусков (шаги, итог хода), а `Usage` ядра не знает ни микроединиц денег
/// (D4 п. 7), ни причин `partial`. Деньги копятся в целых микродолларах, чтобы
/// сумма по тысяче ходов не накапливала ошибку `double` (§12.1.5).
final class _Totals {
  var input = 0;
  var output = 0;
  var cacheRead = 0;
  var cacheWrite = 0;

  /// `null`, пока ни один провайдер не сообщил рассуждения (как `Usage.toJson`).
  int? reasoning;

  /// Стоимость в микродолларах; значима только при [priced].
  var micros = 0;

  /// Цена известна хотя бы у одного шага агрегата: иначе `cost` на проводе
  /// отсутствует, а не `"0"` (D6, DSK-11).
  var priced = false;
  var steps = 0;
  final partial = <UsagePartial>{};

  /// Токены и деньги из [usage]; [priced] — известна ли цена этого куска.
  void addUsage(Usage usage, {required bool priced}) {
    input += usage.input;
    output += usage.output;
    cacheRead += usage.cacheRead;
    cacheWrite += usage.cacheWrite;
    if (usage.reasoning != null) {
      reasoning = (reasoning ?? 0) + usage.reasoning!;
    }
    if (priced) {
      this.priced = true;
      micros += _micros(usage) ?? 0;
    }
  }

  /// Подмешивает готовый агрегат [other] (итог хода в сессию).
  void merge(_Totals other) {
    input += other.input;
    output += other.output;
    cacheRead += other.cacheRead;
    cacheWrite += other.cacheWrite;
    if (other.reasoning != null) {
      reasoning = (reasoning ?? 0) + other.reasoning!;
    }
    if (other.priced) {
      priced = true;
      micros += other.micros;
    }
    steps += other.steps;
    partial.addAll(other.partial);
  }

  _Totals copy() => _Totals()..merge(this);

  Map<String, Object?> tokensJson() => {
    'input': input,
    'output': output,
    'cacheRead': cacheRead,
    'cacheWrite': cacheWrite,
    'reasoning': ?reasoning,
  };

  /// Общие поля агрегата; `steps`, `turns` и `partial` дополняет вызывающий.
  Map<String, Object?> toJson({int? turns}) => {
    'turns': ?turns,
    'steps': steps,
    'tokens': tokensJson(),
    if (priced) 'cost': _costString(micros),
    'partial': ?_partialJson(partial),
  };
}

/// Стоимость usage в целых микродолларах (D4 п. 7); `null` — стоимость
/// бессмысленна: не конечная, отрицательная или не помещающаяся в точное
/// целое `double` (больше 2^53 − 1 микродолларов).
///
/// Почему защита здесь: цены моделей приходят из конфигурации и фикстур, и
/// `Infinity`, `NaN` или минус дали бы исключение `round()` в обработчике
/// события моста либо отрицательную «стоимость» на проводе. Такая цена — «цены
/// нет» (`noPrice`, без `cost`), а ход идёт штатно (D6, §12.1.5).
int? _micros(Usage usage) {
  final micros = usage.cost.total * 1e6;
  if (!micros.isFinite || micros < 0 || micros > 9007199254740991) {
    return null;
  }
  return micros.round();
}

/// Десятичная строка из микроединиц: `^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$`, без
/// хвостовых нулей, ноль — `"0"` (D9). Печать целочисленная: `double` в
/// деньгах на проводе не участвует.
String _costString(int micros) {
  final whole = micros ~/ 1000000;
  final fraction = micros % 1000000;
  if (fraction == 0) {
    return '$whole';
  }
  final digits = fraction
      .toString()
      .padLeft(6, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '$whole.$digits';
}

/// Массив причин в порядке таблицы D6; пустой не отправляется (D19 п. 2).
List<String>? _partialJson(Set<UsagePartial> partial) {
  if (partial.isEmpty) {
    return null;
  }
  return [
    for (final reason in UsagePartial.values)
      if (partial.contains(reason)) reason.name,
  ];
}

/// Агрегаты usage сессии сервера и построение снимков `_codelab/session/usage`.
///
/// Почему отдельный объект: считать надо на сессию сервера, а не на
/// соединение (D4), и независимо от того, объявил ли текущий владелец
/// `usage`: после `reattach` агрегаты и `seq` продолжаются без сброса
/// (Q11 (а)). Чистая логика без ввода-вывода — тестируется и читается отдельно
/// от моста, который решает, кому и когда слать кадр (D7, D18 Т5).
///
/// Для чего: превращает события ядра (`TurnStarted`, `StepEnded`, `TurnEnded`,
/// `ContextCompacted`) в параметры уведомления формы D2 и ведёт `seq`.
///
/// Как использовать: мост подаёт события в [turnStarted], [stepEnded],
/// [turnEnded] всегда; снимок берёт через [stepSnapshot], [turnSnapshot],
/// [compactionSnapshot] только когда кадр действительно уйдёт — каждый
/// вызов расходует очередной `seq`, пропуски номеров клиент считает нормой
/// (D7). Клиент суммы не считает.
final class UsageAccounting {
  UsageAccounting({this.beforeLoad = false});

  /// Сессия открыта через `session/load` с ответами модели в журнале: ранние
  /// ходы в сумму не вошли (D6, Q7 (а)); только у моста, созданного
  /// `session/load`, и не меняется при `reattach`.
  bool beforeLoad;

  var _seq = 0;

  /// Итоги завершённых ходов, где были шаги, и их число (D19 п. 3).
  final _completed = _Totals();
  var _completedTurns = 0;

  /// Идущий ход: сумма его шагов; `null` — хода нет (поздний `StepEnded`
  /// после `TurnEnded` не учитывается, AGENTS.md §9).
  _Totals? _open;

  /// Закрытый ход: итог по `TurnEnded` до следующего [turnStarted] — из него
  /// строится снимок `turn`.
  _Totals? _closed;
  String? _turnId;

  /// Заполнение контекста последнего `StepEnded` хода (D19 п. 4) и сессии
  /// (источник `size` и `compactAt` для снимка `compaction`, D5).
  ContextFill? _turnContext;
  ContextFill? _lastContext;

  /// Последний шаг хода — для снимка `step`.
  Map<String, Object?>? _lastStep;

  /// Начинает ход: сбрасывает его накопления и запоминает [turnId].
  ///
  /// Почему здесь нет переноса незакрытого хода в сессию: ядро гарантирует
  /// `TurnEnded` на каждый `TurnStarted` (LOOP-1) — цикл ловит любое
  /// исключение хода, публикует `AgentError(hook)` и всё равно выпускает
  /// `TurnEnded(failed)` (`agent_loop.dart`, `run`: блок `on Object catch` и
  /// безусловный `_emit(TurnEnded)` после него), а встроенные команды
  /// завершаются `TurnEnded` в каждой ветке (`agent_runtime.dart`, ход
  /// команды). Закрытие сессии посреди хода гасит и подписку моста, и сам
  /// мост. Поэтому к новому `TurnStarted` `_open` всегда `null`; если
  /// гарантию когда-нибудь нарушат, накопления прерванного хода будут
  /// потеряны, а не размазаны по следующему (D4 п. 3, AGENTS.md §9).
  ///
  /// Как использовать: мост зовёт на каждый `TurnStarted` до шагов хода.
  void turnStarted(TurnId turnId) {
    _turnId = turnId.value;
    _open = _Totals();
    _closed = null;
    _turnContext = null;
    _lastStep = null;
  }

  /// Учитывает шаг: usage и модель берутся из `StepEnded.result` (D4 п. 1).
  /// Возвращает `true`, если шаг учтён и нужен снимок `step`; шаг вне хода
  /// (поздний после `TurnEnded` или до `TurnStarted`) не учитывается и кадра
  /// не даёт (AGENTS.md §9) — как у [turnEnded].
  bool stepEnded(StepEnded event) {
    final turn = _open;
    if (turn == null) {
      return false;
    }
    final result = event.result;
    final response = result.response;
    final usage = result.usage;
    final model = response.model;
    final stepTotal =
        usage.input + usage.output + usage.cacheRead + usage.cacheWrite;
    // Цена известна, если у модели она есть и стоимость шага осмысленна
    // (`_micros`): у шага на модели с ценами `cost` присутствует всегда,
    // `"0"` при нуле токенов (D6, дельта agent-acp-server).
    final priced = model.cost != null && _micros(usage) != null;
    final step = _Totals()..addUsage(usage, priced: priced);
    // `noUsage` — только успешный ответ без входных и выходных токенов:
    // настоящий ответ всегда тратит вход, значит, провайдер usage не прислал
    // (DF-15); ответ с ошибкой или отменой и нулём — не причина (D6).
    final succeeded =
        response.stopReason != StopReason.error &&
        response.stopReason != StopReason.aborted;
    if (succeeded && usage.input + usage.output == 0) {
      step.partial.add(UsagePartial.noUsage);
    }
    if (!priced && stepTotal > 0) {
      step.partial.add(UsagePartial.noPrice);
    }
    turn
      ..addUsage(usage, priced: priced)
      ..partial.addAll(step.partial)
      ..steps += 1;
    _turnContext = event.context;
    _lastContext = event.context;
    _lastStep = {
      'index': result.stepIndex,
      'model': '${model.provider}/${model.id}',
      'tokens': step.tokensJson(),
      if (priced) 'cost': _costString(step.micros),
      'partial': ?_partialJson(step.partial),
    };
    return true;
  }

  /// Закрывает ход: итог — `TurnEnded.usage`, а не собственная сумма шагов
  /// (D4 п. 3); `noPrice` по usage детей — эвристика Q13 (б). Возвращает
  /// `true`, если в ходе были шаги и нужен снимок `turn`; ход без шагов
  /// (`/status`, отмена до первого запроса) в сессию не входит (D4 п. 5).
  bool turnEnded(TurnEnded event) {
    final turn = _open;
    _open = null;
    if (turn == null || turn.steps == 0) {
      return false;
    }
    final usage = event.usage;
    // Цена у хода известна, если известна у шага корня или итог хода уже
    // содержит стоимость детей (их модели с ценами); бессмысленная
    // стоимость итога — «цены нет» (`_micros`, D6).
    final totalMicros = _micros(usage);
    final total = _Totals()
      ..addUsage(
        usage,
        priced: totalMicros != null && (turn.priced || totalMicros > 0),
      )
      ..steps = turn.steps
      ..partial.addAll(turn.partial);
    if (totalMicros == null) {
      total.partial.add(UsagePartial.noPrice);
    }
    final children = event.subagentUsage;
    if (children != null &&
        children.input +
                children.output +
                children.cacheRead +
                children.cacheWrite >
            0 &&
        children.cost.total == 0) {
      // Цены моделей детей адаптеру не видны (D6, R3).
      total.partial.add(UsagePartial.noPrice);
    }
    _closed = total;
    _completed.merge(total);
    _completedTurns += 1;
    return true;
  }

  /// Снимок `step` последнего учтённого шага.
  Map<String, Object?> stepSnapshot(String sessionId) => _snapshot(
    sessionId,
    'step',
    turnId: _turnId,
    step: _lastStep,
    turn: _open!.toJson(),
    session: _sessionJson(),
    context: _contextJson(_turnContext),
  );

  /// Снимок `turn` после [turnEnded] (`true`): итог хода (D7).
  Map<String, Object?> turnSnapshot(String sessionId) => _snapshot(
    sessionId,
    'turn',
    turnId: _turnId,
    turn: _closed!.toJson(),
    session: _sessionJson(),
    context: _contextJson(_turnContext),
  );

  /// Снимок `compaction`: `used` — `tokensAfter`, `size` и `compactAt` — из
  /// последнего `StepEnded` сессии; без шагов `context` нет (D5).
  Map<String, Object?> compactionSnapshot(String sessionId, int tokensAfter) {
    final last = _lastContext;
    return _snapshot(
      sessionId,
      'compaction',
      session: _sessionJson(),
      context: last == null
          ? null
          : {
              'used': tokensAfter,
              'size': last.window,
              'compactAt': ?last.compactAt,
            },
    );
  }

  /// Сессия: итоги завершённых ходов плюс идущий ход (D4 п. 4); `turns`
  /// считает и текущий ход, если в нём уже были шаги (D19 п. 3).
  Map<String, Object?> _sessionJson() {
    final session = _completed.copy();
    var turns = _completedTurns;
    final running = _open;
    if (running != null && running.steps > 0) {
      session.merge(running);
      turns += 1;
    }
    if (beforeLoad) {
      session.partial.add(UsagePartial.beforeLoad);
    }
    return session.toJson(turns: turns);
  }

  Map<String, Object?>? _contextJson(ContextFill? fill) => fill == null
      ? null
      : {'used': fill.used, 'size': fill.window, 'compactAt': ?fill.compactAt};

  Map<String, Object?> _snapshot(
    String sessionId,
    String trigger, {
    String? turnId,
    Map<String, Object?>? step,
    Map<String, Object?>? turn,
    required Map<String, Object?> session,
    Map<String, Object?>? context,
  }) {
    final hasCost = [
      step,
      turn,
      session,
    ].any((part) => part != null && part.containsKey('cost'));
    return {
      'sessionId': sessionId,
      'seq': ++_seq,
      'trigger': trigger,
      'turnId': ?turnId,
      'step': ?step,
      'turn': ?turn,
      'session': session,
      if (hasCost) 'currency': 'USD',
      'context': ?context,
    };
  }
}
