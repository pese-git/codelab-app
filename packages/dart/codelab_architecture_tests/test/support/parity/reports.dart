/// Чтение машинных отчётов прогонов и проверка утечки секретов в них.
///
/// Почему: статус доказательства матрицы берётся из отчётов, которые Melos-
/// скрипты пишут при заданной `CODELAB_TEST_REPORT_DIR`
/// (`switch-default-agent-to-dart`, D6): JSON-репортёр `package:test` и JUnit
/// команды `codelab test-scenario --junit`. Пакет `xml` не добавляется (D15):
/// JUnit пишем мы сами, поэтому хватает узкого чтения по известной схеме.
///
/// Для чего: превращает файл отчёта в [ReportSource] — список тестов с итогом
/// и причиной пропуска, — а `verdict.dart` сворачивает их в статусы D5.
/// Неожиданная разметка — [ReportFormatException] с именем файла, а не
/// молчаливое `not-run`.
///
/// Как использовать: [readJsonReport] и [readJunitReport] принимают файл;
/// [findSecretLeaks] (D16) вызывается над каталогом `parity-results/` и не
/// печатает значения секретов.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

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
    this.complete = true,
  });

  /// Имя файла отчёта (`cli-dart.json`); печатается как источник.
  final String name;

  /// Видимые тесты; тесты загрузки файлов (`loading …`) сюда не входят.
  final List<TestRecord> tests;

  /// Пути наборов, которые не загрузились или упали в `setUpAll`.
  final List<String> failedSuitePaths;

  /// Значение `done.success`; для JUnit — «нет упавших».
  final bool success;

  /// Было ли событие `done`. Отчёт без него оборван (убитый прогон): по нему
  /// нельзя утверждать, что тест прошёл (D5).
  final bool complete;
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
///
/// Читаются только события `suite`, `testStart`, `print` (с `messageType: skip`),
/// `error`, `testDone` и `done`;
/// остальные, в том числе из будущих версий репортёра, пропускаются.
/// Тест загрузки файла (`loading …`) тестом не считается: его падение
/// превращается в [ReportSource.failedSuitePaths]. Отсутствие файла —
/// [FileSystemException], а не пустой источник.
ReportSource readJsonReport(File file) {
  final name = p.basename(file.path);
  final suites = <int, String>{};
  final starts = <int, _Start>{};
  final errored = <int>{};
  final skipMessages = <int, String>{};
  final tests = <TestRecord>[];
  final failedSuites = <String>[];
  final finished = <(int, bool, bool, bool)>[];
  var complete = false; // нет события done — прогон оборван
  var success = false;

  var lineNo = 0;
  for (final line in file.readAsLinesSync()) {
    lineNo++;
    if (line.trim().isEmpty) continue;
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException catch (e) {
      throw ReportFormatException(
        name,
        'line $lineNo is not JSON: ${e.message}',
      );
    }
    if (event is! Map<String, dynamic>) {
      throw ReportFormatException(name, 'line $lineNo is not a JSON object');
    }
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'];
        if (suite is Map && suite['id'] is int) {
          suites[suite['id'] as int] = suite['path']?.toString() ?? '';
        }
      case 'testStart':
        final test = event['test'];
        if (test is Map && test['id'] is int) {
          final metadata = test['metadata'];
          final skipped = metadata is Map && metadata['skip'] == true;
          starts[test['id'] as int] = _Start(
            test['name']?.toString() ?? '',
            suites[test['suiteID']] ?? '',
            skipped,
            skipped ? metadata['skipReason']?.toString() : null,
          );
        }
      case 'print':
        // `markTestSkipped(reason)` во время теста не попадает в metadata:
        // репортёр отдаёт причину событием print с messageType `skip`.
        final id = event['testID'];
        if (id is int && event['messageType'] == 'skip') {
          skipMessages[id] = event['message']?.toString() ?? '';
        }
      case 'error':
        final id = event['testID'];
        if (id is int) errored.add(id);
      case 'testDone':
        // Итог считается после разбора всего файла: `error` может прийти
        // после `testDone` (асинхронная ошибка уже «прошедшего» теста).
        final id = event['testID'];
        if (id is int && starts.containsKey(id)) {
          finished.add((
            id,
            event['result'] != 'success',
            event['skipped'] == true,
            event['hidden'] == true,
          ));
        }
      case 'done':
        complete = true;
        success = event['success'] == true;
    }
  }

  for (final (id, resultFailed, skipped, hidden) in finished) {
    final start = starts[id]!;
    final failed = resultFailed || errored.contains(id);
    final isLoad =
        start.name.startsWith('loading ') &&
        (start.name.endsWith('.dart') ||
            start.name == 'loading ${start.suite}');
    if (isLoad || (hidden && start.name.startsWith('('))) {
      // Загрузка набора и setUpAll/tearDownAll: не тест id, но падение
      // роняет весь файл (D5: «упал набор»).
      if (failed) {
        failedSuites.add(
          isLoad ? start.name.substring('loading '.length) : start.suite,
        );
      }
      continue;
    }
    if (hidden && !failed) continue;
    tests.add(
      TestRecord(
        start.name,
        skipped
            ? TestOutcome.skipped
            : (failed ? TestOutcome.failed : TestOutcome.pass),
        skipReason: skipped
            ? (start.skipReason ?? skipMessages[id] ?? '')
            : null,
        suitePath: start.suite,
      ),
    );
  }
  return ReportSource(
    name: name,
    tests: tests,
    failedSuitePaths: failedSuites,
    success: success,
    complete: complete,
  );
}

class _Start {
  const _Start(this.name, this.suite, this.skipped, this.skipReason);
  final String name;
  final String suite;
  final bool skipped;
  final String? skipReason;
}

final _attr = RegExp(r'(\w+)="([^"]*)"');
final _testcase = RegExp(r'<testcase((?:\s+\w+="[^"]*")*)\s*(/?)>');

/// Читает JUnit-отчёт `codelab test-scenario --junit` (D6, D8).
///
/// Схема — только та, что пишет сам `test-scenario`: `testsuite`, `testcase`
/// с `name` и дочерними `failure` или `skipped`. Любая другая разметка —
/// [ReportFormatException].
ReportSource readJunitReport(File file) {
  final name = p.basename(file.path);
  final text = file.readAsStringSync();
  if (!RegExp(r'<testsuites?\b').hasMatch(text)) {
    throw ReportFormatException(name, 'no testsuite element');
  }
  final tests = <TestRecord>[];
  var failures = 0;
  for (final match in _testcase.allMatches(text)) {
    final attrs = {
      for (final a in _attr.allMatches(match[1]!)) a[1]!: _unescape(a[2]!),
    };
    final testName = attrs['name'];
    if (testName == null) {
      throw ReportFormatException(name, 'testcase without a name attribute');
    }
    var outcome = TestOutcome.pass;
    String? reason;
    if (match[2] != '/') {
      final close = text.indexOf('</testcase>', match.end);
      if (close < 0) {
        throw ReportFormatException(name, 'testcase "$testName" is not closed');
      }
      final body = text.substring(match.end, close);
      if (RegExp(r'<(failure|error)\b').hasMatch(body)) {
        outcome = TestOutcome.failed;
        failures++;
      } else {
        final skipped = RegExp(
          r'<skipped((?:\s+\w+="[^"]*")*)\s*/?>',
        ).firstMatch(body);
        if (skipped != null) {
          outcome = TestOutcome.skipped;
          final message = _attr
              .allMatches(skipped[1]!)
              .where((a) => a[1] == 'message')
              .firstOrNull;
          reason = message == null ? '' : _unescape(message[2]!);
        }
      }
    }
    tests.add(TestRecord(testName, outcome, skipReason: reason));
  }
  return ReportSource(name: name, tests: tests, success: failures == 0);
}

String _unescape(String value) => value.replaceAllMapped(
  RegExp(r'&(lt|gt|quot|apos|amp|#\d+|#x[0-9a-fA-F]+);'),
  (m) {
    final entity = m[1]!;
    return switch (entity) {
      'lt' => '<',
      'gt' => '>',
      'quot' => '"',
      'apos' => "'",
      'amp' => '&',
      _ => String.fromCharCode(
        entity.startsWith('#x')
            ? int.parse(entity.substring(2), radix: 16)
            : int.parse(entity.substring(1)),
      ),
    };
  },
);

/// Имена переменных окружения, значения которых считаются секретами: имя
/// целиком или суффикс после `_`, без учёта регистра (D16).
final _secretName = RegExp(
  r'(^|_)(TOKEN|KEY|SECRET|PASSWORD|PASS|PAT|CREDENTIALS?|AUTH)$',
  caseSensitive: false,
);

/// Вымышленный секрет, которым тесты проверяют маскирование (cli-scenario-
/// driver, D8): в публикуемом отчёте его быть не должно.
const _leakMarker = 'sk-test-leak-';

final _homePath = RegExp(r'/(Users|home)/[^/\s"\x27<>\\]+/');

/// Формы значения, в которых оно может встретиться в отчёте: как есть,
/// JSON-экранированное (`print`-события и тексты ошибок лежат в JSON-строках)
/// и XML-экранированное (JUnit).
Set<String> _forms(String value) => {
  value,
  jsonEncode(value).substring(1, jsonEncode(value).length - 1),
  value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;'),
};

/// Ищет в файлах [resultsDir] значения секретов окружения (D16).
///
/// Почему: отчёты публикуются артефактами CI на 90 дней, а отчёты app
/// попадают в репозиторий (D9). Секретов CI в ночном прогоне нет, но проверка
/// дешёвая и ловит случайную печать ключа тестом.
///
/// Проверяются: значения переменных [environment] с именем на `_TOKEN`,
/// `_KEY`, `_SECRET`, `_PASSWORD`, `_PASS`, `_PAT`, `_CREDENTIAL(S)`, `_AUTH`
/// (без учёта регистра) длиной от 8 символов, в трёх формах ([_forms]);
/// маркер `sk-test-leak-` (см. ниже); при [checkHomePaths] ещё значение `HOME` и
/// абсолютные пути `/Users/<имя>/`, `/home/<имя>/` — отчёты app в репозитории
/// не должны раскрывать каталог пользователя (D9). В CI флаг не нужен:
/// `flutter test` пишет там абсолютные пути рабочей копии.
///
/// Маркер блокирует только при [checkHomePaths] (отчёты app попадают в
/// репозиторий). В отчётах CI это предупреждение в [warnings]: упавший тест
/// может честно напечатать маркер в тексте ожидания, и снимать из-за этого
/// публикацию отчёта джоба нельзя (D7, D16). Значения секретных переменных
/// блокируют всегда. Символическая ссылка в каталоге — ошибка: `upload-artifact`
/// пошёл бы по ней за пределы каталога.
///
/// Возвращает по одному сообщению на пару «файл, причина»; значение в
/// сообщение НЕ попадает.
List<String> findSecretLeaks({
  required Directory resultsDir,
  required Map<String, String> environment,
  bool checkHomePaths = false,
  List<String>? warnings,
}) {
  final secrets = {
    for (final MapEntry(:key, :value) in environment.entries)
      if (_secretName.hasMatch(key) && value.length >= 8) key: _forms(value),
  };
  final home = environment['HOME'];
  final homeForms = checkHomePaths && home != null && home.length > 1
      ? _forms(home)
      : const <String>{};
  if (!resultsDir.existsSync()) return const [];
  final leaks = <String>[];
  final files = resultsDir.listSync(recursive: true, followLinks: false)
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final entity in files) {
    final relative = p.relative(entity.path, from: resultsDir.path);
    if (entity is Link) {
      leaks.add('secret leak: $relative is a symbolic link in the reports');
      continue;
    }
    if (entity is! File) continue;
    final text = utf8.decode(entity.readAsBytesSync(), allowMalformed: true);
    var named = false;
    for (final MapEntry(:key, :value) in secrets.entries) {
      if (value.any(text.contains)) {
        leaks.add('secret leak: $relative contains the value of $key');
        named = true;
      }
    }
    // Маркер ловит секрет, которого нет в окружении; если файл уже назван
    // по переменной, второе сообщение о том же ничего не добавит.
    if (!named && text.contains(_leakMarker)) {
      if (checkHomePaths) {
        leaks.add('secret leak: $relative contains the test secret marker');
      } else {
        warnings?.add('warning: $relative contains the test secret marker');
      }
    }
    if (checkHomePaths &&
        (homeForms.any(text.contains) || _homePath.hasMatch(text))) {
      leaks.add('secret leak: $relative contains a user home path');
    }
  }
  return leaks;
}
