import 'package:codelab_client_core/codelab_client_core.dart'
    show
        Money,
        TokenCounts,
        UsageLedgerGroup,
        UsagePartial,
        formatUsageMoneyExact;

import 'usage_pane_data.dart';

/// Заголовок CSV: порядок столбцов часть формата (D5).
const _header =
    'kind,turn,step,title,model,input,output,cache_read,cache_write,'
    'reasoning,cost,currency,partial';

/// CSV журнала, показанного в панели Usage (design.md change
/// `add-desktop-usage-pane`, D5, Q2).
///
/// Почему в application: формат и защита от формульной инъекции — политика,
/// запись файла — порт `UsageCsvSaver` в `lib/core/platform/`.
///
/// Для чего: один файл воспроизводит всё, что видно в панели, включая группы
/// без шагов. RFC 4180: разделитель `,`, CRLF, без BOM (BOM ломает `cut` и
/// `awk`, Q2). Числа точные (`184200`, `0.000041`), а не форматированные;
/// неизвестное — пустая ячейка, никогда `0` (DSK-11).
///
/// Как использовать: `buildUsageCsv(data)` при `data.canExport`; результат
/// сохраняется как UTF-8 без BOM. Подписи шагов берутся из строк панели
/// (`UsagePaneStep.title`), подписи ходов и остальное — из журнала.
String buildUsageCsv(UsagePaneData data) {
  final ledger = data.ledger;
  final out = StringBuffer(_header)..write('\r\n');
  if (ledger == null) {
    return out.toString();
  }
  void row(
    String kind, {
    int? turn,
    int? step,
    String? title,
    String? model,
    required TokenCounts tokens,
    Money? cost,
    required Set<UsagePartial> partial,
  }) {
    // Агент не прислал usage: счётчики нули не по факту, а по умолчанию —
    // ячейки пустые (DSK-11), как «—» в панели.
    final silent = usageRowSilent(tokens, partial);
    final cells = <String>[
      kind,
      '${turn ?? ''}',
      '${step ?? ''}',
      _text(title),
      _text(model),
      silent ? '' : '${tokens.input}',
      silent ? '' : '${tokens.output}',
      silent ? '' : '${tokens.cacheRead}',
      silent ? '' : '${tokens.cacheWrite}',
      silent ? '' : '${tokens.reasoning ?? ''}',
      // Цена «немой» строки не факт, а умолчание (`0` при отсутствии usage):
      // пустые ячейки, как `—` в панели (D5, DSK-11).
      cost == null || silent ? '' : formatUsageMoneyExact(cost),
      cost == null || silent ? '' : cost.currency,
      _partialOf(partial),
    ];
    out
      ..write(cells.join(','))
      ..write('\r\n');
  }

  void group(String kind, UsageLedgerGroup group, {int? turn}) => row(
    kind,
    turn: turn,
    tokens: group.tokens,
    cost: group.cost,
    partial: group.partial,
  );

  final stepTitles = _stepTitlesOf(data);
  for (final turn in ledger.turns) {
    row(
      'turn',
      turn: turn.index,
      title: turn.title,
      tokens: turn.total.tokens,
      cost: turn.total.cost,
      partial: turn.total.partial,
    );
    for (final step in turn.steps) {
      row(
        'step',
        turn: turn.index,
        step: step.index + 1,
        title: stepTitles[(turn.index, step.index)],
        model: step.model,
        tokens: step.tokens,
        cost: step.cost,
        partial: step.partial,
      );
    }
    if (turn.subagents case final subagents?) {
      group('subagents', subagents, turn: turn.index);
    }
  }
  for (final model in ledger.models) {
    row(
      'model',
      model: model.model,
      tokens: model.tokens,
      cost: model.cost,
      partial: model.partial,
    );
  }
  if (ledger.subagents case final subagents?) {
    group('subagents', subagents);
  }
  if (ledger.summaries case final summaries?) {
    group('summaries', summaries);
  }
  row(
    'total',
    tokens: ledger.total.tokens,
    cost: ledger.total.cost,
    partial: ledger.total.partial,
  );
  return out.toString();
}

/// Подписи шагов по `(ход, индекс шага)` из строк панели.
Map<(int, int), String> _stepTitlesOf(UsagePaneData data) => {
  for (final turn in data.turns)
    for (final step in turn.steps)
      (step.turn, step.index): step.title.englishText,
};

/// Причины неполноты через `;` в порядке `noUsage`, `noPrice`, `beforeLoad`.
String _partialOf(Set<UsagePartial> partial) => [
  for (final reason in UsagePartial.values)
    if (partial.contains(reason)) reason.name,
].join(';');

/// Текстовая ячейка: защита от формул и квотирование RFC 4180 (D5).
///
/// Значение с первым символом `=`, `+`, `-`, `@`, TAB или CR получает префикс
/// `'`: подписи ходов — слова пользователя, подписи шагов и модели — строки
/// агента, и табличный редактор не должен исполнить их как формулу.
String _text(String? value) {
  if (value == null || value.isEmpty) {
    return '';
  }
  var cell = value;
  if ('=+-@\t\r'.contains(cell[0])) {
    cell = "'$cell";
  }
  if (cell.contains(RegExp('[,"\r\n]'))) {
    cell = '"${cell.replaceAll('"', '""')}"';
  }
  return cell;
}
