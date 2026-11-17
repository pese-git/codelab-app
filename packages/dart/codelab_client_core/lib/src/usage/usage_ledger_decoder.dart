import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import 'usage_ledger_models.dart';
import 'usage_parsing.dart';

/// Разбор ответа `_codelab/session/usage/ledger` версии 1 (change
/// `add-usage-ledger`, D6, D10).
///
/// Почему: форма расширения известна одному месту — `_meta.codelab.*` и
/// ответы расширений разбирает только ядро клиента, хосты форму не парсят
/// (`AGENTS.md` пакета §5). Деньги, валюта и причины разбираются общими
/// функциями `usage_parsing.dart`, как в `UsageDecoder`.
///
/// Для чего: превращает сырой результат в [UsageLedgerView]. Разбор
/// терпимый, исключений нет: обязательны `sessionId`, `seq` (≥ 0: 0 — снимков
/// не было) и `total.tokens` — без них `null`; ход без `index` и итога и шаг
/// без `index` и `tokens` пропускаются; необязательное поле неверного типа
/// отсутствует. На каждое неразобранное поле — вызов `onWarning` с именем и
/// короткой причиной, без сырого значения; «не чаще раза на сессию и поле»
/// накладывает вызывающий (`ClientWorkspace`).
///
/// Как использовать: `UsageLedgerDecoder().decode(result, onWarning: …)`.
final class UsageLedgerDecoder {
  const UsageLedgerDecoder();

  UsageLedgerView? decode(
    Map<String, Object?> result, {
    required UsageWarn onWarning,
  }) {
    final sessionId = result['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) {
      onWarning('sessionId', 'required');
      return null;
    }
    final seq = result['seq'];
    if (seq is! int || seq < 0) {
      onWarning('seq', 'required');
      return null;
    }
    final currency = UsageCurrency(result['currency'], onWarning);

    final rawTotal = result['total'];
    if (rawTotal is! Map) {
      onWarning('total.tokens', 'required');
      return null;
    }
    final total = parseUsageTotals(
      rawTotal,
      'total',
      required: true,
      currency: currency,
      onWarning: onWarning,
    );
    if (total == null) {
      return null;
    }

    UsageLedgerStatus? status;
    String? reason;
    int? records;
    final ledger = result['ledger'];
    if (ledger is Map) {
      status = switch (ledger['status']) {
        'upToDate' => UsageLedgerStatus.upToDate,
        'rebuilt' => UsageLedgerStatus.rebuilt,
        'inMemory' => UsageLedgerStatus.inMemory,
        'notSaved' => UsageLedgerStatus.notSaved,
        // Незнакомое значение — поля нет (совместимость D6, п. 5).
        _ => null,
      };
      final rawReason = ledger['reason'];
      reason = rawReason is String ? _clean(rawReason, 64) : null;
      records = usageCount(ledger['records']);
    } else if (ledger != null) {
      onWarning('ledger', 'wrong_type');
    }

    final turnsRaw = result['turns'];
    final turns = <UsageLedgerTurn>[];
    if (turnsRaw is List) {
      for (final raw in turnsRaw) {
        final turn = _turn(raw, currency, onWarning);
        if (turn != null) {
          turns.add(turn);
        }
      }
    } else if (turnsRaw != null) {
      onWarning('turns', 'wrong_type');
    }

    final modelsRaw = result['models'];
    final models = <UsageLedgerModel>[];
    if (modelsRaw is List) {
      for (final raw in modelsRaw) {
        final model = _model(raw, currency, onWarning);
        if (model != null) {
          models.add(model);
        }
      }
    } else if (modelsRaw != null) {
      onWarning('models', 'wrong_type');
    }

    return UsageLedgerView(
      sessionId: SessionId(sessionId),
      seq: seq,
      total: total,
      turnCount: usageCount(rawTotal['turns']) ?? 0,
      status: status,
      reason: reason,
      records: records,
      turns: List.unmodifiable(turns),
      models: List.unmodifiable(models),
      subagents: _group(
        result['subagents'],
        'subagents',
        countKey: 'runs',
        currency: currency,
        onWarning: onWarning,
      ),
      summaries: _group(
        result['summaries'],
        'summaries',
        countKey: 'count',
        currency: currency,
        onWarning: onWarning,
      ),
    );
  }

  UsageLedgerTurn? _turn(Object? raw, UsageCurrency currency, UsageWarn warn) {
    if (raw is! Map) {
      warn('turns', 'wrong_type');
      return null;
    }
    final index = usageCount(raw['index']);
    if (index == null) {
      warn('turns.index', 'required');
      return null;
    }
    final total = parseUsageTotals(
      raw['total'],
      'turns.total',
      required: true,
      currency: currency,
      onWarning: warn,
    );
    if (total == null) {
      return null;
    }
    final title = raw['title'];
    if (title != null && title is! String) {
      warn('turns.title', 'wrong_type');
    }
    final running = raw['running'];
    if (running != null && running is! bool) {
      warn('turns.running', 'wrong_type');
    }
    final stepsRaw = raw['steps'];
    final steps = <UsageLedgerStep>[];
    if (stepsRaw is List) {
      for (final item in stepsRaw) {
        final step = _step(item, currency, warn);
        if (step != null) {
          steps.add(step);
        }
      }
    } else if (stepsRaw != null) {
      warn('turns.steps', 'wrong_type');
    }
    return UsageLedgerTurn(
      index: index,
      total: total,
      title: title is String ? _clean(title, 64) : null,
      running: running is bool && running,
      steps: List.unmodifiable(steps),
      subagents: _group(
        raw['subagents'],
        'turns.subagents',
        countKey: 'runs',
        currency: currency,
        onWarning: warn,
      ),
    );
  }

  UsageLedgerStep? _step(Object? raw, UsageCurrency currency, UsageWarn warn) {
    if (raw is! Map) {
      warn('turns.steps', 'wrong_type');
      return null;
    }
    final index = usageCount(raw['index']);
    final tokens = parseUsageTokens(raw['tokens']);
    if (index == null || tokens == null) {
      warn(
        index == null ? 'turns.steps.index' : 'turns.steps.tokens',
        'required',
      );
      return null;
    }
    final model = raw['model'];
    if (model != null && model is! String) {
      warn('turns.steps.model', 'wrong_type');
    }
    final ids = raw['toolCallIds'];
    if (ids != null && ids is! List) {
      warn('turns.steps.toolCallIds', 'wrong_type');
    }
    return UsageLedgerStep(
      index: index,
      tokens: tokens,
      model: model is String ? _clean(model, 128) : null,
      cost: parseUsageCost(raw, 'turns.steps', currency, warn),
      partial: parseUsagePartial(raw, 'turns.steps', warn),
      // Идентификаторы вызовов сохраняются как есть, в порядке ответа; не
      // строки отбрасываются (D6: подпись шага по транскрипту).
      toolCallIds: ids is List
          ? List.unmodifiable([
              for (final id in ids)
                if (id is String) sanitizeUsageText(id, maxRunes: 128),
            ])
          : const <String>[],
    );
  }

  UsageLedgerModel? _model(
    Object? raw,
    UsageCurrency currency,
    UsageWarn warn,
  ) {
    if (raw is! Map) {
      warn('models', 'wrong_type');
      return null;
    }
    final model = raw['model'];
    final tokens = parseUsageTokens(raw['tokens']);
    if (model is! String || tokens == null) {
      warn(model is! String ? 'models.model' : 'models.tokens', 'required');
      return null;
    }
    return UsageLedgerModel(
      model: sanitizeUsageText(model, maxRunes: 128),
      steps: usageCount(raw['steps']) ?? 0,
      tokens: tokens,
      cost: parseUsageCost(raw, 'models', currency, warn),
      partial: parseUsagePartial(raw, 'models', warn),
    );
  }

  /// Группа `subagents` (`runs`) или `summaries` (`count`); `null` — поля нет.
  UsageLedgerGroup? _group(
    Object? raw,
    String name, {
    required String countKey,
    required UsageCurrency currency,
    required UsageWarn onWarning,
  }) {
    if (raw == null) {
      return null;
    }
    if (raw is! Map) {
      onWarning(name, 'wrong_type');
      return null;
    }
    final count = usageCount(raw[countKey]);
    final tokens = parseUsageTokens(raw['tokens']);
    if (count == null || tokens == null) {
      onWarning(name, 'wrong_type');
      return null;
    }
    return UsageLedgerGroup(
      count: count,
      tokens: tokens,
      cost: parseUsageCost(raw, name, currency, onWarning),
      partial: parseUsagePartial(raw, name, onWarning),
    );
  }

  /// Очищенная строка агента; пустая после очистки — поля нет.
  static String? _clean(String text, int maxRunes) {
    final cleaned = sanitizeUsageText(text, maxRunes: maxRunes);
    return cleaned.isEmpty ? null : cleaned;
  }
}
