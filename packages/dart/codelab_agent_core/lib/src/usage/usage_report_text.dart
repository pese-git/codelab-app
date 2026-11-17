/// Текст команды `/usage` по отчёту журнала usage (design.md change
/// `add-usage-ledger`, D2, D5, Q7; `agent-core/12-observability-and-errors.md`
/// §12.6.1).
///
/// Почему отдельная функция: текст фиксирован побайтово и проверяется
/// фикстурой `acp/slash-usage`; правило цены (`$`, `~$`, `cost unknown`)
/// не должно расползаться по рантайму.
///
/// Как использовать: `formatUsageReport(await session.usageLedger())` — строки
/// через `\n`, без `\n` после последней.
library;

import '../llm/usage.dart';
import 'usage_ledger_report.dart';

/// Часть строки для правила цены: её usage и признак «цена известна» (D2).
typedef _Part = ({Usage usage, bool priced});

/// Текст `/usage` для [report] (D5).
String formatUsageReport(UsageLedgerReport report) {
  final ledger = report.ledger;
  if (ledger.steps == 0) {
    return 'Session usage: no model requests yet';
  }
  bool priced(String? model) =>
      model != null && !report.noPriceModels.contains(model);

  // Модели, у которых есть шаг без usage провайдера: перед `input` — «~».
  final approxModels = {
    for (final t in ledger.turns)
      for (final s in t.steps)
        if (s.noUsage) s.model,
  };

  final List<_Part> modelParts = [
    for (final m in ledger.byModel) (usage: m.usage, priced: priced(m.model)),
  ];
  final List<_Part> runParts = [
    for (final u in ledger.subagentRuns)
      // Эвристика Q13 (б): токены при нулевой стоимости — цена неизвестна.
      (usage: u, priced: !(_tokens(u) > 0 && u.cost.total == 0)),
  ];
  final List<_Part> summaryParts = [
    for (final c in ledger.summaryCalls)
      (usage: c.usage, priced: priced(c.model)),
  ];

  // Вызов суммаризатора без usage провайдера — по правилу шага (D1 п. 2):
  // все четыре счётчика нулевые. К прогонам субагентов правило не применяется:
  // у записи `subagent` нет `stopReason`, а нулевой usage — это и ребёнок, не
  // обращавшийся к модели (отменён в очереди), поэтому «~» там была бы ложью.
  final summaryApprox = ledger.summaryCalls.any((c) => _tokens(c.usage) == 0);
  final total = _usage(ledger.total, [
    ...modelParts,
    ...runParts,
    ...summaryParts,
  ], approx: approxModels.isNotEmpty || summaryApprox);
  return [
    'Session usage: ${ledger.turns.length} turns, ${ledger.steps} steps',
    'Total: $total',
    'By model:',
    for (final (i, m) in ledger.byModel.indexed)
      '  ${m.model}: ${m.steps} steps, '
          '${_usage(m.usage, [modelParts[i]], approx: approxModels.contains(m.model))}',
    if (ledger.subagents case final g?)
      'Subagents: ${g.count} runs, ${_usage(g.usage, runParts)}',
    if (ledger.summaries case final g?)
      'Summaries: ${g.count}, '
          '${_usage(g.usage, summaryParts, approx: summaryApprox)}',
    _ledgerLine(report),
  ].join('\n');
}

int _tokens(Usage u) => u.input + u.output + u.cacheRead + u.cacheWrite;

/// Строка usage: `input N, output N, cache read N, cache write N`, затем
/// `reasoning N` (если есть) и `cost ...` (D5).
String _usage(Usage u, List<_Part> parts, {bool approx = false}) {
  // Правило Q7: «с ценой» у всех частей с токенами — `$`, у части — `~$`, ни у
  // одной — `unknown`; части без токенов на цену не влияют (D2).
  final withTokens = [
    for (final p in parts)
      if (_tokens(p.usage) > 0) p,
  ];
  final known = withTokens.where((p) => p.priced).length;
  final amount = u.cost.total.toStringAsFixed(4);
  final cost = withTokens.isNotEmpty && known == 0
      ? 'unknown'
      : '${known < withTokens.length ? '~' : ''}\$$amount';
  return 'input ${approx ? '~' : ''}${u.input}, output ${u.output}, '
      'cache read ${u.cacheRead}, cache write ${u.cacheWrite}'
      '${u.reasoning == null ? '' : ', reasoning ${u.reasoning}'}, '
      'cost $cost';
}

String _ledgerLine(UsageLedgerReport r) {
  final n = r.ledger.records;
  return switch (r.state) {
    UsageLedgerFileState.upToDate => 'Ledger: up to date ($n records)',
    UsageLedgerFileState.rebuilt => 'Ledger: rebuilt from journal ($n records)',
    UsageLedgerFileState.inMemory => 'Ledger: rebuilt in memory ($n records)',
    UsageLedgerFileState.notSaved =>
      'Ledger: rebuilt, not saved (${r.saveError})',
  };
}
