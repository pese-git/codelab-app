// ЗАГЛУШКА красного шага TDD (задача 1.5 change `switch-default-agent-to-dart`).
// Настоящая реализация — задача 1.6 (design.md, D4–D6, D9). Сигнатуры
// зафиксированы тестом `verdict_test.dart`; тела бросают `UnimplementedError`.

import 'matrix_parser.dart';

/// Статус доказательства (D5, D9).
enum EvidenceStatus {
  /// Пройдено в обязательном источнике, нигде не упало и не пропущено.
  pass('pass'),

  /// Тест упал в любом источнике или упал набор.
  failed('failed'),

  /// Пропущен в обязательном источнике или с неразрешённой причиной.
  skipped('skipped'),

  /// В обязательном источнике нет ни одного теста id.
  notRun('not-run'),

  /// Доказательство не существует.
  missing('missing'),

  /// Отчёты app не переданы: печатается, но тест не роняет.
  deferred('deferred');

  const EvidenceStatus(this.label);

  /// Текст статуса в строке итога.
  final String label;
}

/// Разрешённая причина пропуска в дополнительном источнике (D5, Q5).
class AllowedSkip {
  const AllowedSkip(this.reason, this.requirement);

  /// Шаблон причины пропуска.
  final Pattern reason;

  /// Требование спецификации, которое разрешает пропуск.
  final String requirement;
}

/// Вердикт по одному доказательству одной строки.
class EvidenceVerdict {
  const EvidenceVerdict({
    required this.rowId,
    required this.evidence,
    required this.status,
    this.source,
    this.reason,
  });

  /// Идентификатор строки матрицы.
  final String rowId;

  /// Метка доказательства.
  final String evidence;

  /// Статус.
  final EvidenceStatus status;

  /// Файл отчёта, из-за которого выставлен статус (`scenario-embedded.xml`).
  final String? source;

  /// Причина пропуска или падения.
  final String? reason;

  /// Строка итога: `<строка> <доказательство> <статус> [<источник>] [<причина>]`.
  String toLine() => throw UnimplementedError('toLine: задача 1.6');
}

/// Считает вердикты по всем доказательствам [rows] (D5).
///
/// [resultsDir] — каталог `parity-results/`; [appResultsDir] — корень отчётов
/// app (внутри `app/<режим>/<файл>.json`), без него `app:` — `deferred` (D9).
List<EvidenceVerdict> computeVerdicts({
  required List<MatrixRow> rows,
  required String repoRoot,
  required String resultsDir,
  String? appResultsDir,
  List<AllowedSkip> allowedSkips = const [],
}) => throw UnimplementedError('computeVerdicts: задача 1.6');

/// Строки итога: первой — содержимое `meta.json`, далее вердикты по id строки.
///
/// Каталог без `meta.json` — [StateError]-подобная ошибка с текстом про
/// `meta.json` (testing-quality «Каталог отчётов без meta.json»). При
/// `run_attempt > 1` добавляется предупреждение
/// `rerun attempt: does not count for the three nights`.
List<String> renderVerdictReport({
  required String resultsDir,
  required List<EvidenceVerdict> verdicts,
}) => throw UnimplementedError('renderVerdictReport: задача 1.6');

/// Причина пропуска группы статуса или `null`, если [environment] задаёт
/// `CODELAB_PARITY_RESULTS` (D4).
String? statusGroupSkipReason(Map<String, String> environment) =>
    throw UnimplementedError('statusGroupSkipReason: задача 1.6');
