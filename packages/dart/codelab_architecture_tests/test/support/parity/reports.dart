// ЗАГЛУШКА красного шага TDD (задачи 1.5 и 1.7 change
// `switch-default-agent-to-dart`). Настоящая реализация — задачи 1.6 и 1.8
// (design.md, D5–D6, D16). Сигнатуры зафиксированы тестами `reports_test.dart`
// и `secret_leak_test.dart`; тела бросают `UnimplementedError`.

import 'dart:io';

/// Итог одного теста в отчёте.
enum TestOutcome {
  /// Тест прошёл.
  pass,

  /// Тест упал (`failure` или `error`).
  failed,

  /// Тест пропущен (`skip`, `markTestSkipped`, `<skipped>`).
  skipped,
}

/// Тест из отчёта.
class TestRecord {
  const TestRecord(this.name, this.outcome, {this.skipReason, this.suitePath});

  /// Полное имя: группы и тест через пробел, как в отчёте `package:test`.
  final String name;

  /// Итог.
  final TestOutcome outcome;

  /// Причина пропуска, если она есть.
  final String? skipReason;

  /// Путь файла набора (`suite.path`); для JUnit — `null`.
  final String? suitePath;
}

/// Прочитанный файл отчёта.
class ReportSource {
  const ReportSource({
    required this.name,
    required this.tests,
    this.failedSuitePaths = const [],
    this.success = true,
  });

  /// Имя файла отчёта (`cli-dart.json`); печатается как источник.
  final String name;

  /// Видимые тесты; тесты загрузки файлов (`loading …`) сюда не входят.
  final List<TestRecord> tests;

  /// Пути наборов, которые не загрузились (тест загрузки с ошибкой).
  final List<String> failedSuitePaths;

  /// Значение `done.success`; для JUnit — «нет упавших».
  final bool success;
}

/// Отчёт нельзя разобрать: неожиданная разметка, битый JSON (D6).
class ReportFormatException implements Exception {
  const ReportFormatException(this.file, this.message);

  /// Имя или путь файла отчёта.
  final String file;

  /// Описание ошибки.
  final String message;

  @override
  String toString() => 'ReportFormatException($file): $message';
}

/// Читает JSON-отчёт `package:test` (`--file-reporter json:`) (D6).
ReportSource readJsonReport(File file) =>
    throw UnimplementedError('readJsonReport: задача 1.6');

/// Читает JUnit-отчёт `codelab test-scenario --junit` (D6, D8).
ReportSource readJunitReport(File file) =>
    throw UnimplementedError('readJunitReport: задача 1.6');

/// Ищет в файлах [resultsDir] значения секретов окружения (D16).
///
/// Проверяются переменные [environment] с именем на `_TOKEN`, `_KEY`,
/// `_SECRET` и значением от 8 символов. Возвращает по одному сообщению на
/// пару «файл, переменная»; значение в сообщение НЕ попадает.
List<String> findSecretLeaks({
  required Directory resultsDir,
  required Map<String, String> environment,
}) => throw UnimplementedError('findSecretLeaks: задача 1.8');
