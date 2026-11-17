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

/// Результат запроса журнала с числами для лога (D12): ходы и шаги журнала.
typedef UsageLedgerResult = ({
  Map<String, Object?> result,
  int turns,
  int steps,
});

/// Метод запроса клиент → агент с историей usage сессии (design.md change
/// `add-usage-ledger`, D6: имя с `_`, ответ с тем же `id`).
const usageLedgerMethod = '_codelab/session/usage/ledger';

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

  void clear() {
    input = output = cacheRead = cacheWrite = steps = micros = 0;
    reasoning = null;
    priced = false;
    partial.clear();
  }

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

/// Поле `budget` снимков `step` и `turn` из прогресса цикла (design.md change
/// `add-desktop-usage-pane`, D7, D8; `13-acp-adapter.md` §13.12).
///
/// Почему решение здесь: ядро заполняет `BudgetProgress` всегда, а клиенту
/// поле нужно, только если задан `max_tokens`, `max_cost` или `max_duration`;
/// лимит шагов есть всегда (50), и одного его для поля мало — иначе все
/// существующие usage-фикстуры получили бы лишний ключ. `null` — поля нет
/// (событие вне цикла или лимитов, кроме шагов, нет).
///
/// Для чего: числа берутся из `BudgetProgress` как есть, то есть те же, что
/// проверяет цикл (LOOP-12); адаптер второго подсчёта не ведёт. Состав:
/// `steps` — всегда, `tokens`, `cost`, `duration` — по заданным лимитам;
/// `cost.used` нет, если цен модели нет; деньги — строки D9 из микродолларов.
Map<String, Object?>? budgetJson(BudgetProgress? progress) {
  if (progress == null) {
    return null;
  }
  final limits = progress.limits;
  final maxTokens = limits.maxTokens;
  final maxCost = limits.maxCost;
  final maxDuration = limits.maxDuration;
  if (maxTokens == null && maxCost == null && maxDuration == null) {
    return null;
  }
  Map<String, Object?>? cost;
  if (maxCost != null) {
    final limitMicros = _roundMicros(maxCost);
    // Лимит, не помещающийся в микродоллары (NaN, минус, огромное число),
    // показать нельзя: поля cost нет, остальной бюджет остаётся.
    if (limitMicros != null) {
      final used = progress.cost;
      final usedMicros = used == null ? null : _roundMicros(used);
      cost = {
        'used': ?usedMicros == null ? null : _costString(usedMicros),
        'limit': _costString(limitMicros),
      };
    }
  }
  // Невалидный `max_cost` был единственным лимитом: показывать нечего, одного
  // лимита шагов мало (D7).
  if (maxTokens == null && cost == null && maxDuration == null) {
    return null;
  }
  return {
    'steps': {'used': progress.steps, 'limit': limits.maxSteps},
    if (maxTokens != null)
      'tokens': {'used': progress.tokens, 'limit': maxTokens},
    'cost': ?cost,
    if (maxDuration != null)
      'duration': {
        'usedMs': progress.active.inMilliseconds,
        'limitMs': maxDuration.inMilliseconds,
      },
  };
}

/// Доллары в целые микродоллары; `null` — не конечное, отрицательное или не
/// помещающееся в точное целое `double` (как [_micros]).
int? _roundMicros(double dollars) {
  final micros = dollars * 1e6;
  if (!micros.isFinite || micros < 0 || micros > 9007199254740991) {
    return null;
  }
  return micros.round();
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
/// `ContextCompacted`, `CompactionDiscarded`) в параметры уведомления формы
/// D2 и ведёт `seq`.
///
/// Как использовать: мост подаёт события в [turnStarted], [stepEnded],
/// [turnEnded] всегда; снимок берёт через [stepSnapshot], [turnSnapshot],
/// [compactionSnapshot] только когда кадр действительно уйдёт — каждый
/// вызов расходует очередной `seq`, пропуски номеров клиент считает нормой
/// (D7). Клиент суммы не считает.
final class UsageAccounting {
  UsageAccounting({this.beforeLoad = false});

  /// Причина `beforeLoad` (D6, Q7 (а)): сумма сессии неполна, ранние ходы не
  /// вошли. После `session/load` агент CodeLab её не ставит — сумма полная
  /// (change `add-usage-ledger`, D8, [seed]). Исключение — откат: если засев
  /// журналом не удался, мост ставит `beforeLoad`, и клиент видит честную
  /// «неполную сумму» (Migration Plan, D15). Значение остаётся в протоколе v1
  /// для других агентов.
  bool beforeLoad;

  var _seq = 0;

  /// `seq` последнего потраченного снимка; `0` — снимков не было (D6: поле
  /// `seq` ответа журнала).
  int get seq => _seq;

  /// Число шагов завершённых ходов: засев (все шаги журнала) плюс шаги ходов
  /// этого сервера. Шагов в журнале сверх этого числа — шаги идущего хода
  /// (`running`, D6): шаг записывается в журнал раньше `StepEnded`, например
  /// пока ход ждёт разрешения инструмента. Счёт по шагам, а не по ходам:
  /// ход от уведомления субагента сливается в журнале с предыдущим (R2), и
  /// число ходов расходится навсегда, а шаги суммируются точно.
  int get completedSteps => _completed.steps;

  /// В сумме сессии есть хотя бы один шаг: без них снимок `load` не нужен
  /// (D8, «Загрузка сессии без шагов»).
  bool get hasSteps => _completed.steps > 0 || (_open?.steps ?? 0) > 0;

  /// Usage суммаризатора: входит в сумму сессии, но не в ход, не в `turns` и
  /// не в `steps` (D4, Q6 (а)).
  final _summaries = _Totals();

  /// Засевает агрегаты отчётом журнала при открытии сессии `session/load`
  /// (D8): итоги завершённых ходов, их число, причины `noUsage` и `noPrice` и
  /// суммаризатор. Те же функции, что строят ответ запроса журнала, поэтому
  /// `session` снимка `load` равен `total` ответа по построению.
  ///
  /// Как использовать: один раз, сразу после `attach` моста, созданного
  /// `session/load`; повторный `session/load` открытой сессии (`reattach`)
  /// не пересевает.
  void seed(UsageLedgerProjection projection) {
    _completed
      ..clear()
      ..merge(projection._completed);
    _completedTurns = projection.turns;
    _summaries
      ..clear()
      ..merge(projection._summaries);
  }

  /// Учитывает вызов суммаризатора (`ContextCompacted.usage`,
  /// `CompactionDiscarded.usage`): [priced] —
  /// у модели ответа в каталоге есть цена. Нулевой usage ничего не меняет;
  /// ненулевые токены без цены дают `noPrice` (D4).
  void summarizerEnded(Usage usage, {required bool priced}) {
    final tokens =
        usage.input + usage.output + usage.cacheRead + usage.cacheWrite;
    final known = priced && _micros(usage) != null;
    _summaries.addUsage(usage, priced: known && tokens > 0);
    if (!known && tokens > 0) {
      _summaries.partial.add(UsagePartial.noPrice);
    }
  }

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

  /// Поле `budget` последнего шага и итога хода (D7 change
  /// `add-desktop-usage-pane`): считается в момент события, потому что
  /// прогресс цикла — значение на границе шага, а не живой счётчик.
  Map<String, Object?>? _stepBudget;
  Map<String, Object?>? _turnBudget;

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
    _stepBudget = null;
    _turnBudget = null;
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
    // `noUsage` — ответ модели без токенов вообще: настоящий ответ всегда
    // тратит вход, значит, провайдер usage не прислал (DF-15). Кэш-токены
    // считаются: шаг только с ними — usage прислан, а `noUsage` и `noPrice`
    // у шага вместе не бывают (инвариант дельты agent-acp-server). Сюда
    // входит и `aborted` (отмена посреди потока), решение D26. `error` — в
    // том числе синтетический `overflow` из `_exhausted`, где провайдер не
    // вызывался, — не причина: ответа модели не было (D6, D26).
    if (response.stopReason != StopReason.error && stepTotal == 0) {
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
    _stepBudget = budgetJson(event.budget);
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
    _turnBudget = budgetJson(event.budget);
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
    budget: _stepBudget,
  );

  /// Снимок `turn` после [turnEnded] (`true`): итог хода (D7).
  Map<String, Object?> turnSnapshot(String sessionId) => _snapshot(
    sessionId,
    'turn',
    turnId: _turnId,
    turn: _closed!.toJson(),
    session: _sessionJson(),
    context: _contextJson(_turnContext),
    budget: _turnBudget,
  );

  /// Снимок `compaction`: `used` — `tokensAfter`, `size` и `compactAt` — из
  /// последнего `StepEnded` сессии; без шагов `context` нет (D5).
  Map<String, Object?> compactionSnapshot(String sessionId, int tokensAfter) =>
      _sessionSnapshot(sessionId, 'compaction', tokensAfter);

  /// Снимок `compactionDiscarded` (change `fix-discarded-compaction-usage`,
  /// D5, CMP-13): оплаченный вызов суммаризатора без записанного сжатия.
  ///
  /// Почему `used` — [tokensBefore]: заполнение контекста не изменилось
  /// (сжатия нет), и индикатор у клиента не должен прыгать; это та же
  /// согласованная оценка, что у `context.used` последнего снимка.
  /// Полей `turnId`, `step` и `turn` нет, как у `compaction`.
  ///
  /// Как использовать: мост зовёт после [summarizerEnded] на событие
  /// `CompactionDiscarded`, когда кадр действительно уйдёт.
  Map<String, Object?> compactionDiscardedSnapshot(
    String sessionId,
    int tokensBefore,
  ) => _sessionSnapshot(sessionId, 'compactionDiscarded', tokensBefore);

  /// Снимок уровня сессии без хода и шага: `session` — сумма, `context` —
  /// заполнение [used] с `size` и `compactAt` последнего `StepEnded`; без
  /// шагов `context` нет (D5). Общий построитель `compaction` и
  /// `compactionDiscarded`: повод — параметр, правила одни.
  Map<String, Object?> _sessionSnapshot(
    String sessionId,
    String trigger,
    int used,
  ) {
    final last = _lastContext;
    return _snapshot(
      sessionId,
      trigger,
      session: _sessionJson(),
      context: last == null
          ? null
          : {'used': used, 'size': last.window, 'compactAt': ?last.compactAt},
    );
  }

  /// Снимок `load` (D8): сумма сессии после `session/load`; `context` — если
  /// мосту известно заполнение (повторная загрузка живой сессии), `turnId`,
  /// `step` и `turn` нет.
  Map<String, Object?> loadSnapshot(String sessionId) => _snapshot(
    sessionId,
    'load',
    session: _sessionJson(),
    context: _contextJson(_lastContext),
  );

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
    session.merge(_summaries);
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
    Map<String, Object?>? budget,
  }) {
    // Лимит стоимости — тоже сумма: при `budget.cost` валюта нужна, даже если
    // `cost.used` нет (модель без цен; D7 change `add-desktop-usage-pane`).
    final hasCost =
        [
          step,
          turn,
          session,
        ].any((part) => part != null && part.containsKey('cost')) ||
        (budget?.containsKey('cost') ?? false);
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
      'budget': ?budget,
    };
  }
}

/// Проекция отчёта журнала usage в форму D6 и в засев агрегатов (design.md
/// change `add-usage-ledger`, D2, D6, D8).
///
/// Почему один класс на два применения: сумма сессии снимка `load` и `total`
/// ответа журнала обязаны совпадать (D8, инвариант), а проще всего это
/// гарантировать, строя оба из одних и тех же объектов: те же микродоллары
/// (`_micros`), та же печать денег (`_costString`), те же причины.
///
/// Для чего: `UsageLedgerReport` ядра хранит сырые `Usage` (доллары `double`)
/// и множество моделей без цены; перевод в микродоллары и причины `partial`
/// делает адаптер (D2, Q4). Правила цены те же, что у живых снимков: часть с
/// моделью с ценами и нулём токенов — с ценой `0` (D20 change
/// `add-usage-extension`), субагенты судятся по каждому прогону (D2).
///
/// Как использовать: [UsageLedgerProjection.of] по отчёту
/// `AgentSession.usageLedger` (запрос журнала, [result]) или
/// `usageLedgerInMemory` (засев, `UsageAccounting.seed`).
final class UsageLedgerProjection {
  UsageLedgerProjection._({
    required UsageLedgerReport report,
    required this.turns,
    required this.steps,
    required this.hasCost,
    required _Totals completed,
    required _Totals summaries,
    required List<Map<String, Object?>> turnsJson,
    required List<Map<String, Object?>> modelsJson,
    required Map<String, Object?>? subagentsJson,
    required Map<String, Object?>? summariesJson,
  }) : _report = report,
       _completed = completed,
       _summaries = summaries,
       _turnsJson = turnsJson,
       _modelsJson = modelsJson,
       _subagentsJson = subagentsJson,
       _summariesJson = summariesJson;

  /// Строит проекцию отчёта.
  factory UsageLedgerProjection.of(UsageLedgerReport report) {
    final ledger = report.ledger;
    final noPrice = report.noPriceModels;
    final completed = _Totals();
    final turnsJson = <Map<String, Object?>>[];
    final modelPartial = <String, Set<UsagePartial>>{};
    var turnUsage = const Usage();
    var turnSteps = 0;
    var index = 0;
    for (final turn in ledger.turns) {
      index += 1;
      turnUsage += turn.usage;
      turnSteps += turn.steps.length;
      final stepsJson = <Map<String, Object?>>[];
      final partial = <UsagePartial>{};
      var anyPriced = false;
      for (final (i, step) in turn.steps.indexed) {
        final tokens = _tokenSum(step.usage);
        // Модель с ценами при нуле токенов — с ценой `0`, как у живого шага.
        final priced =
            !noPrice.contains(step.model) && _micros(step.usage) != null;
        final reasons = <UsagePartial>{
          if (step.noUsage) UsagePartial.noUsage,
          if (!priced && tokens > 0) UsagePartial.noPrice,
        };
        final totals = _Totals()..addUsage(step.usage, priced: priced);
        partial.addAll(reasons);
        modelPartial.putIfAbsent(step.model, () => {}).addAll(reasons);
        anyPriced = anyPriced || priced;
        stepsJson.add({
          'index': i,
          'model': step.model,
          'tokens': totals.tokensJson(),
          if (priced) 'cost': _costString(totals.micros),
          'partial': ?_partialJson(reasons),
          'toolCallIds': step.toolCallIds,
        });
      }
      Map<String, Object?>? subagents;
      if (turn.subagents case final group?) {
        // Цена по каждому прогону хода (D2): токены при нулевой стоимости —
        // «без цены», иначе «с ценой».
        final judged = _judgeRuns(turn.subagentRuns, group.usage);
        anyPriced = anyPriced || judged.priced;
        if (judged.unpriced) {
          partial.add(UsagePartial.noPrice);
        }
        subagents = _groupJson('runs', group.count, group.usage, judged);
      }
      final turnPriced = anyPriced && _micros(turn.usage) != null;
      final total = _Totals()
        ..addUsage(turn.usage, priced: turnPriced)
        ..steps = turn.steps.length
        ..partial.addAll(partial);
      if (anyPriced && !turnPriced) {
        total.partial.add(UsagePartial.noPrice);
      }
      completed.merge(total);
      turnsJson.add({
        'index': index,
        if (turn.title.isNotEmpty) 'title': turn.title,
        'total': {
          'steps': total.steps,
          'tokens': total.tokensJson(),
          if (total.priced) 'cost': _costString(total.micros),
          'partial': ?_partialJson(total.partial),
        },
        'steps': stepsJson,
        'subagents': ?subagents,
      });
    }

    // Суммаризатор: цена по модели каждого вызова (D2, D4).
    final summaries = _Totals();
    Map<String, Object?>? summariesJson;
    var summariesUsage = const Usage();
    if (ledger.summaries case final group?) {
      var unpriced = false;
      var priced = false;
      for (final call in ledger.summaryCalls) {
        if (_tokenSum(call.usage) == 0) {
          continue;
        }
        final known =
            call.model != null &&
            !noPrice.contains(call.model) &&
            _micros(call.usage) != null;
        if (known) {
          priced = true;
        } else {
          unpriced = true;
        }
      }
      summariesUsage = group.usage;
      final judged = (priced: priced, unpriced: unpriced);
      summaries.addUsage(
        group.usage,
        priced: priced && _micros(group.usage) != null,
      );
      if (unpriced) {
        summaries.partial.add(UsagePartial.noPrice);
      }
      summariesJson = _groupJson(
        'count',
        group.count,
        group.usage,
        judged,
        // Отброшенные проходы (CMP-13) показываются отдельным числом только
        // при ненулевом значении; версия `usageLedger` остаётся 1 (D5, Q2).
        discarded: group.discarded,
      );
    }

    // Всё, что журнал насчитал сверх перечисленных ходов и суммаризатора: шаги
    // до первых слов пользователя, шаги вне пути до листа (D1 п. 8). Модели
    // таких шагов в ходах не видны, поэтому цена — по моделям журнала: все с
    // ценами — «с ценой», все без — «без цены», смесь — по ненулевой
    // стоимости остатка (как эвристика субагентов).
    final rest = _minus(_minus(ledger.total, turnUsage), summariesUsage);
    final restTokens = _tokenSum(rest);
    final extraSteps = ledger.steps - turnSteps;
    if (restTokens > 0 || extraSteps > 0) {
      final allPriced = ledger.byModel.every((m) => !noPrice.contains(m.model));
      final nonePriced = ledger.byModel.every((m) => noPrice.contains(m.model));
      final priced =
          !nonePriced &&
          (allPriced || rest.cost.total > 0) &&
          _micros(rest) != null;
      completed.addUsage(rest, priced: priced);
      completed.steps += extraSteps > 0 ? extraSteps : 0;
      if (!priced && restTokens > 0) {
        completed.partial.add(UsagePartial.noPrice);
      }
    }

    // Субагенты сессии: цена по каждому прогону (D2); usage уже в ходах.
    Map<String, Object?>? subagentsJson;
    if (ledger.subagents case final group?) {
      final judged = _judgeRuns(ledger.subagentRuns, group.usage);
      if (judged.unpriced) {
        completed.partial.add(UsagePartial.noPrice);
      }
      subagentsJson = _groupJson('runs', group.count, group.usage, judged);
    }

    final modelsJson = [
      for (final model in ledger.byModel)
        () {
          final priced = !noPrice.contains(model.model);
          final totals = _Totals()..addUsage(model.usage, priced: priced);
          return <String, Object?>{
            'model': model.model,
            'steps': model.steps,
            'tokens': totals.tokensJson(),
            if (totals.priced) 'cost': _costString(totals.micros),
            'partial': ?_partialJson({...?modelPartial[model.model]}),
          };
        }(),
    ];

    return UsageLedgerProjection._(
      report: report,
      turns: ledger.turns.length,
      steps: completed.steps,
      // `cost` есть где-либо в результате, только если он есть у `total`: цена
      // хода, шага, модели и групп входит в сумму завершённых ходов или
      // суммаризатора. Один источник вместо флагов у каждого места.
      hasCost: completed.priced || summaries.priced,
      completed: completed,
      summaries: summaries,
      turnsJson: turnsJson,
      modelsJson: modelsJson,
      subagentsJson: subagentsJson,
      summariesJson: summariesJson,
    );
  }

  final UsageLedgerReport _report;
  final _Totals _completed;
  final _Totals _summaries;
  final List<Map<String, Object?>> _turnsJson;
  final List<Map<String, Object?>> _modelsJson;
  final Map<String, Object?>? _subagentsJson;
  final Map<String, Object?>? _summariesJson;

  /// Число ходов со шагами и число шагов журнала по всем записям файла.
  final int turns;
  final int steps;

  /// В результате есть хотя бы одно `cost`: тогда нужен `currency` (D6).
  /// Собирается по признакам цены при построении, без разбора результата.
  final bool hasCost;

  /// `total` ответа: весь журнал плюс суммаризатор (D6).
  Map<String, Object?> get totalJson {
    final total = _completed.copy()..merge(_summaries);
    return total.toJson(turns: turns);
  }

  /// Результат `_codelab/session/usage/ledger` (D6).
  ///
  /// [seq] — `UsageAccounting.seq` моста, [running] — последний ход идёт.
  /// `reason` — только у `rebuilt`; `currency` — если в результате есть
  /// хоть одно `cost`.
  Map<String, Object?> result({
    required String sessionId,
    required int seq,
    required bool running,
  }) {
    final report = _report;
    final turnsJson = [
      for (final (i, turn) in _turnsJson.indexed)
        if (running && i == _turnsJson.length - 1)
          {...turn, 'running': true}
        else
          turn,
    ];
    return {
      'sessionId': sessionId,
      'seq': seq,
      'ledger': {
        'status': report.state.name,
        if (report.state == UsageLedgerFileState.rebuilt)
          'reason': ?report.reason?.name,
        'records': report.ledger.records,
      },
      'total': totalJson,
      'turns': turnsJson,
      'models': _modelsJson,
      'subagents': ?_subagentsJson,
      'summaries': ?_summariesJson,
      if (hasCost) 'currency': 'USD',
    };
  }
}

int _tokenSum(Usage u) => u.input + u.output + u.cacheRead + u.cacheWrite;

/// Разность `a − b` по токенам и категориям стоимости; отрицательное
/// (погрешность `double`, лишний вычитаемый) обрезается до нуля.
Usage _minus(Usage a, Usage b) {
  int sub(int x, int y) => x > y ? x - y : 0;
  double subCost(double x, double y) => x - y > 1e-9 ? x - y : 0;
  return Usage(
    input: sub(a.input, b.input),
    output: sub(a.output, b.output),
    cacheRead: sub(a.cacheRead, b.cacheRead),
    cacheWrite: sub(a.cacheWrite, b.cacheWrite),
    cost: UsageCost(
      input: subCost(a.cost.input, b.cost.input),
      output: subCost(a.cost.output, b.cost.output),
      cacheRead: subCost(a.cost.cacheRead, b.cost.cacheRead),
      cacheWrite: subCost(a.cost.cacheWrite, b.cost.cacheWrite),
    ),
  );
}

/// Цена прогонов субагентов по каждому прогону (D2): токены при нулевой
/// стоимости — «без цены» (`unpriced`), токены с ненулевой стоимостью — «с
/// ценой» (`priced`); прогон без токенов на цену не влияет. Без списка
/// прогонов (старая свёртка) — по сумме группы.
({bool priced, bool unpriced}) _judgeRuns(List<Usage> runs, Usage fallback) {
  var priced = false;
  var unpriced = false;
  for (final run in runs.isEmpty ? [fallback] : runs) {
    if (_tokenSum(run) == 0) {
      continue;
    }
    if (run.cost.total == 0) {
      unpriced = true;
    } else {
      priced = true;
    }
  }
  return (priced: priced, unpriced: unpriced);
}

/// Группа без шагов — субагенты (`runs`) или суммаризатор (`count`): токены,
/// `cost` при известной цене хотя бы у одной части с токенами, `noPrice` при
/// неизвестной (D2, D6). [discarded] — только у суммаризатора: число
/// отброшенных вызовов, ключ при нуле не пишется.
Map<String, Object?> _groupJson(
  String countKey,
  int count,
  Usage usage,
  ({bool priced, bool unpriced}) judged, {
  int discarded = 0,
}) {
  final totals = _Totals()
    ..addUsage(usage, priced: judged.priced && _micros(usage) != null);
  return {
    countKey: count,
    if (discarded > 0) 'discarded': discarded,
    'tokens': totals.tokensJson(),
    if (totals.priced) 'cost': _costString(totals.micros),
    'partial': ?_partialJson({if (judged.unpriced) UsagePartial.noPrice}),
  };
}
