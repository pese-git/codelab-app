// Построители отчётов и временных деревьев для модульных тестов проверки
// доказательств (задачи 1.5 и 1.7 change `switch-default-agent-to-dart`).
// Формат событий JSON — репортёр `package:test`; JUnit — схема
// `codelab test-scenario --junit` (design.md, D6, D8).

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Описание теста для построителя JSON-отчёта.
class T {
  const T(this.name, {this.result = 'success', this.skip, this.suite});

  /// Полное имя теста.
  final String name;

  /// `success`, `failure` или `error`.
  final String result;

  /// Причина пропуска; `''` — пропуск без причины; `null` — не пропущен.
  final String? skip;

  /// Путь набора; по умолчанию `/work/test/a_test.dart`.
  final String? suite;
}

/// Собирает JSON-отчёт `package:test`: события start, suite, testStart/testDone,
/// print, неизвестное будущее событие и done.
String jsonReport(
  List<T> tests, {
  bool success = true,
  List<String> failedLoads = const [],
}) {
  final events = <Map<String, Object?>>[
    {'type': 'start', 'protocolVersion': '0.1.1', 'runnerVersion': '1.26.3'},
  ];
  final suiteIds = <String, int>{};
  int suiteOf(String path) => suiteIds.putIfAbsent(path, () {
    final id = suiteIds.length;
    events.add({
      'type': 'suite',
      'suite': {'id': id, 'platform': 'vm', 'path': path},
    });
    return id;
  });

  var id = 0;
  for (final path in failedLoads) {
    final suiteId = suiteOf(path);
    final testId = id++;
    events
      ..add({
        'type': 'testStart',
        'test': {
          'id': testId,
          'name': 'loading $path',
          'suiteID': suiteId,
          'groupIDs': <int>[],
          'metadata': {'skip': false, 'skipReason': null},
        },
      })
      ..add({
        'type': 'error',
        'testID': testId,
        'error': 'Failed to load "$path"',
        'stackTrace': '',
        'isFailure': false,
      })
      ..add({
        'type': 'testDone',
        'testID': testId,
        'result': 'error',
        'skipped': false,
        'hidden': true,
      });
  }
  for (final t in tests) {
    final suiteId = suiteOf(t.suite ?? '/work/test/a_test.dart');
    final testId = id++;
    events.add({
      'type': 'testStart',
      'test': {
        'id': testId,
        'name': t.name,
        'suiteID': suiteId,
        'groupIDs': <int>[],
        'metadata': {'skip': t.skip != null, 'skipReason': t.skip},
      },
    });
    events.add({'type': 'print', 'testID': testId, 'message': 'noise'});
    if (t.result != 'success') {
      events.add({
        'type': 'error',
        'testID': testId,
        'error': 'boom',
        'stackTrace': '',
        'isFailure': t.result == 'failure',
      });
    }
    events.add({
      'type': 'testDone',
      'testID': testId,
      'result': t.result,
      'skipped': t.skip != null,
      'hidden': false,
    });
    if (id == 1) {
      // Событие из будущей версии репортёра: читатель обязан его пропустить.
      events.add({'type': 'futureEvent', 'payload': 1});
    }
  }
  events.add({'type': 'done', 'success': success});
  return '${events.map(jsonEncode).join('\n')}\n';
}

/// Описание `testcase` для построителя JUnit.
class J {
  const J(this.name, {this.failure, this.skipped});

  /// Имя фикстуры.
  final String name;

  /// Сообщение `failure`.
  final String? failure;

  /// Причина `skipped`.
  final String? skipped;
}

/// Собирает JUnit в формате `codelab test-scenario`.
String junitReport(List<J> cases) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  final body = StringBuffer();
  for (final c in cases) {
    body.write('<testcase classname="acp" name="${esc(c.name)}" time="0.1"');
    if (c.failure != null) {
      body.write(
        '><failure message="${esc(c.failure!)}">diff</failure>'
        '</testcase>',
      );
    } else if (c.skipped != null) {
      body.write('><skipped message="${esc(c.skipped!)}"/></testcase>');
    } else {
      body.write('/>');
    }
  }
  final failures = cases.where((c) => c.failure != null).length;
  final skipped = cases.where((c) => c.skipped != null).length;
  return '<?xml version="1.0" encoding="UTF-8"?>'
      '<testsuites><testsuite name="codelab test-scenario" '
      'tests="${cases.length}" failures="$failures" skipped="$skipped" '
      'time="1">$body</testsuite></testsuites>';
}

/// Временный каталог с записью файлов по относительным путям.
class Tree {
  Tree(String prefix) : dir = Directory.systemTemp.createTempSync(prefix);

  /// Корень дерева.
  final Directory dir;

  /// Путь корня.
  String get path => dir.path;

  /// Пишет файл [relative] с содержимым [content], создавая каталоги.
  File put(String relative, [String content = '']) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  /// Удаляет дерево.
  void dispose() => dir.deleteSync(recursive: true);
}
