// ЗАГЛУШКА красного шага TDD (задача 1.3 change `switch-default-agent-to-dart`).
// Настоящая реализация — задача 1.4 (design.md, D3–D4). Сигнатуры зафиксированы
// тестом `evidence_test.dart`; тела бросают `UnimplementedError`.

import 'matrix_parser.dart';

/// Вид доказательства строки матрицы (D3).
enum EvidenceKind {
  /// `acp/<id>` — golden-фикстура корпуса.
  acp,

  /// `cli/<id>` — e2e-сценарий `codelab_cli`.
  cli,

  /// `core/<id>` — тест ядра агента.
  core,

  /// `app:<файл>` — интеграционный тест десктопа.
  app,

  /// Путь файла теста (`packages/…_test.dart`, `apps/…_test.dart`).
  testFile,

  /// Шаблон `acp/*` — все фикстуры с ролью `agent`.
  allAcp,

  /// Шаблон `app:*` — все файлы `integration_test/*_test.dart`.
  allApp,
}

/// Доказательство, извлечённое из ячейки «Критерий приёмки».
class Evidence {
  const Evidence(this.kind, this.label);

  /// Вид доказательства.
  final EvidenceKind kind;

  /// Текст в том виде, как он печатается в сообщениях: `acp/x`, `app:f_test.dart`,
  /// путь файла, `acp/*`.
  final String label;
}

/// Известный пробел существования с номером задачи 9.2 (D4).
class KnownGap {
  const KnownGap(this.rowId, this.evidence, this.task);

  /// Идентификатор строки матрицы.
  final String rowId;

  /// Метка доказательства (`Evidence.label`).
  final String evidence;

  /// Номер задачи итерации 2 (`2.3`).
  final String task;
}

/// Итог проверки существования.
class ExistenceReport {
  const ExistenceReport({required this.failures, required this.knownGapLines});

  /// Строки, роняющие тест: `<строка> <доказательство> missing`,
  /// `stale known gap: …`.
  final List<String> failures;

  /// Строки `known gap: …`, которые только печатаются.
  final List<String> knownGapLines;
}

/// Извлекает доказательства из ячейки «Критерий приёмки» (D3); повтор — один раз.
List<Evidence> extractEvidence(String criterion) =>
    throw UnimplementedError('extractEvidence: задача 1.4');

/// Проверяет существование доказательств [rows] в дереве [repoRoot] (D3–D4).
ExistenceReport checkEvidenceExists({
  required List<MatrixRow> rows,
  required String repoRoot,
  List<KnownGap> knownGaps = const [],
}) => throw UnimplementedError('checkEvidenceExists: задача 1.4');
