/// Свёртка отчётов прогонов в статусы доказательств матрицы целей.
///
/// Почему: «фикстура существует» не значит «агент её проходит». Ворота MVP
/// (`switch-default-agent-to-dart`, D5) требуют, чтобы у каждой строки Must
/// каждое доказательство было `pass` в обязательном источнике и не падало и
/// не пропускалось без причины в дополнительных. Источники и правила
/// сопоставления тестов с id — таблица D5.
///
/// Для чего: [computeVerdicts] читает отчёты каталога `parity-results/` и
/// возвращает по вердикту на каждое доказательство; [renderVerdictReport]
/// печатает итог (первой строкой `meta.json`, далее строки по id строки).
///
/// Как использовать: вызывает `parity_evidence_test` при заданной
/// `CODELAB_PARITY_RESULTS` (D4). Отсутствующий файл отчёта — это «нет
/// тестов» (`not-run`), а не ошибка: так упавший джоб выглядит в ночном
/// прогоне (`parity` идёт и после красного `checks`, D7). Битый файл —
/// [ReportFormatException].
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'evidence.dart';
import 'matrix_parser.dart';
import 'reports.dart';

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

/// Разрешённая причина пропуска в перечне `allowedSkips` (D5, Q5, Q8).
///
/// Почему: пропуск по правилу спецификации (например, `setup.mcp` не
/// передаётся процессу агента) не должен открывать строку, а неизвестный
/// пропуск — должен. Подстрока была бы дырой: чужая причина вроде
/// `TODO setup.mcp cannot be passed…` совпала бы с перечнем. Поэтому шаблон
/// сверяется с причиной ЦЕЛИКОМ (см. [matches]).
///
/// Как использовать: [reason] — [String] (точное равенство) или [RegExp]
/// (полное совпадение; якоря добавлять не нужно). [onName] — только для
/// заметки `[skipped: …]` в имени теста, у которого причины нет
/// (`testWidgets(skip: true)`): шаблон с [onName] проверяется по имени и
/// только когда причина пуста, остальные — только по причине.
class AllowedSkip {
  const AllowedSkip(this.reason, this.requirement, {this.onName = false});

  /// Формат причины (или имени теста при [onName]), полное совпадение.
  final Pattern reason;

  /// Требование спецификации, которое разрешает пропуск.
  final String requirement;

  /// Шаблон относится к имени теста без причины, а не к причине.
  final bool onName;

  /// Совпадает ли [text] с шаблоном целиком.
  bool matches(String text) {
    final pattern = reason;
    if (pattern is RegExp) {
      return RegExp(
        '^(?:${pattern.pattern})\$',
        caseSensitive: pattern.isCaseSensitive,
        multiLine: false,
        dotAll: pattern.isDotAll,
      ).hasMatch(text);
    }
    return text == pattern.toString();
  }
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
  String toLine() => [
    rowId,
    evidence,
    status.label,
    if (source != null && source!.isNotEmpty) source,
    if (reason != null && reason!.isNotEmpty) reason,
  ].join(' ');
}

/// Считает вердикты по всем доказательствам [rows] (D5).
///
/// [resultsDir] — каталог `parity-results/`; [appResultsDir] — корень отчётов
/// app (внутри `app/<режим>/<файл>.json`; допустим и каталог, где сразу лежат
/// `<режим>/<файл>.json`), без него `app:` — `deferred` (D9). Файл отчёта app
/// называется как тест с суффиксом `.json`: `fs_flow_test.dart.json`.
List<EvidenceVerdict> computeVerdicts({
  required List<MatrixRow> rows,
  required String repoRoot,
  required String resultsDir,
  String? appResultsDir,
  List<AllowedSkip> allowedSkips = const [],
}) {
  final judge = _Judge(
    repoRoot: repoRoot,
    resultsDir: resultsDir,
    appResultsDir: appResultsDir,
    allowedSkips: allowedSkips,
  );
  final verdicts = <EvidenceVerdict>[];
  for (final row in rows) {
    final evidence = extractEvidence(row.criterion);
    if (evidence.isEmpty) {
      verdicts.add(
        EvidenceVerdict(
          rowId: row.id,
          evidence: '(no evidence)',
          status: EvidenceStatus.missing,
        ),
      );
      continue;
    }
    for (final item in evidence) {
      verdicts.add(judge.judge(row.id, item));
    }
  }
  return verdicts;
}

/// Строки итога: первой — содержимое `meta.json`, далее вердикты по id строки.
///
/// Каталог без `meta.json` — [StateError] с текстом про `meta.json`
/// (testing-quality «Каталог отчётов без meta.json»): ночной джоб не должен
/// молча проверить пустоту (D4). При `run_attempt > 1` добавляется
/// предупреждение `rerun attempt: does not count for the three nights`.
List<String> renderVerdictReport({
  required String resultsDir,
  required List<EvidenceVerdict> verdicts,
  String? appResultsDir,
}) {
  final metaFile = File(p.join(resultsDir, 'meta.json'));
  if (!metaFile.existsSync()) {
    throw StateError(
      'meta.json not found in $resultsDir: the parity job writes it before '
      'the check (design.md, D6)',
    );
  }
  final meta = metaFile.readAsStringSync().trim();
  final Object? decoded;
  try {
    decoded = jsonDecode(meta);
  } on FormatException catch (e) {
    throw StateError('meta.json is not valid JSON: ${e.message}');
  }
  final attempt = decoded is Map ? decoded['run_attempt'] : null;

  final order = [for (final (i, v) in verdicts.indexed) (i, v)]
    ..sort((a, b) {
      final byRow = _naturalCompare(a.$2.rowId, b.$2.rowId);
      return byRow != 0 ? byRow : a.$1.compareTo(b.$1);
    });
  return [
    meta,
    if (attempt is num && attempt > 1)
      'rerun attempt: does not count for the three nights',
    if (appResultsDir != null) ..._appMetaLines(appResultsDir),
    for (final (_, v) in order) v.toLine(),
  ];
}

/// Строки `app <режим>: <meta.json>` для отчётов app: коммит, версия macOS и
/// время каждого из прогонов (D9). Файл лежит в `app/<режим>/meta.json`
/// (допустим и корень, где сразу `<режим>/meta.json`).
List<String> _appMetaLines(String appResultsDir) => [
  for (final mode in const ['dart-agent', 'embedded'])
    () {
      final file = [
        File(p.join(appResultsDir, 'app', mode, 'meta.json')),
        File(p.join(appResultsDir, mode, 'meta.json')),
      ].where((f) => f.existsSync()).firstOrNull;
      return 'app $mode: ${file?.readAsStringSync().trim() ?? 'meta.json not found'}';
    }(),
];

/// Сравнение id строк с учётом чисел: `R-9` раньше `R-10`.
int _naturalCompare(String a, String b) {
  final pa = RegExp(r'^(.*?)(\d+)$').firstMatch(a);
  final pb = RegExp(r'^(.*?)(\d+)$').firstMatch(b);
  if (pa == null || pb == null || pa[1] != pb[1]) return a.compareTo(b);
  return int.parse(pa[2]!).compareTo(int.parse(pb[2]!));
}

/// Причина пропуска группы статуса или `null`, если [environment] задаёт
/// `CODELAB_PARITY_RESULTS` (D4).
String? statusGroupSkipReason(Map<String, String> environment) {
  final value = environment['CODELAB_PARITY_RESULTS'];
  if (value != null && value.isNotEmpty) return null;
  return 'CODELAB_PARITY_RESULTS is not set: status is checked by the '
      'nightly parity job';
}

/// Источники отчётов одного доказательства (D5).
class _Sources {
  const _Sources({
    required this.obligatory,
    this.additional = const [],
    required this.belongs,
    this.suiteFailed = _never,
  });

  /// Обязательные источники (относительные пути в каталоге отчётов); нужен
  /// `pass`.
  final List<String> obligatory;

  /// Дополнительные источники: падение — `failed`, неразрешённый пропуск —
  /// `skipped`.
  final List<String> additional;

  /// Принадлежит ли тест отчёта доказательству.
  final bool Function(TestRecord) belongs;

  /// Относится ли набор, не загрузившийся в отчёте, к доказательству.
  final bool Function(String suitePath) suiteFailed;

  static bool _never(String _) => false;
}

class _Judge {
  _Judge({
    required this.repoRoot,
    required this.resultsDir,
    required this.appResultsDir,
    required this.allowedSkips,
  }) : index = TestNameIndex(repoRoot);

  final String repoRoot;
  final String resultsDir;
  final String? appResultsDir;
  final List<AllowedSkip> allowedSkips;
  final TestNameIndex index;
  final _reports = <String, ReportSource?>{};

  /// Корни отчётов и путь внутри них; `.xml` читается как JUnit.
  ReportSource? _load(String root, String relative) =>
      _reports.putIfAbsent(p.join(root, relative), () {
        final file = File(p.join(root, relative));
        if (!file.existsSync()) return null;
        return relative.endsWith('.xml')
            ? readJunitReport(file)
            : readJsonReport(file);
      });

  EvidenceVerdict judge(String rowId, Evidence evidence) {
    EvidenceVerdict verdict(
      EvidenceStatus status, {
      String? source,
      String? reason,
    }) => EvidenceVerdict(
      rowId: rowId,
      evidence: evidence.label,
      status: status,
      source: source,
      reason: reason,
    );

    if (!evidenceExists(evidence, repoRoot, index: index)) {
      return verdict(EvidenceStatus.missing);
    }
    switch (evidence.kind) {
      case EvidenceKind.allAcp:
        return _combine(rowId, evidence, [
          for (final id in agentFixtureIds(repoRoot))
            judge(rowId, Evidence(EvidenceKind.acp, 'acp/$id')),
        ]);
      case EvidenceKind.allApp:
        return _combine(rowId, evidence, [
          for (final file in appTestFiles(repoRoot))
            judge(rowId, Evidence(EvidenceKind.app, 'app:$file')),
        ]);
      case EvidenceKind.app when appResultsDir == null:
        return verdict(EvidenceStatus.deferred);
      default:
        return _fold(rowId, evidence, _sourcesOf(evidence));
    }
  }

  _Sources _sourcesOf(Evidence evidence) {
    switch (evidence.kind) {
      case EvidenceKind.acp:
        final fixture = File(
          p.join(repoRoot, acpFixturesDir, '${evidence.id}.json'),
        );
        final transport = _hasTransport(fixture);
        const client = [
          'dart/codelab_client_acp.conformance.json',
          'dart/codelab_client_acp.json',
          'flutter/codelab_client_acp.json',
        ];
        return _Sources(
          // Транспортные фикстуры in-process корпус пропускает (их играет
          // драйвер бинаря), поэтому для них обязателен codelab_agent.json.
          obligatory: transport
              ? const ['dart/codelab_agent.json', 'flutter/codelab_agent.json']
              : const [
                  'dart/codelab_agent_acp.conformance.json',
                  'dart/codelab_agent_acp.json',
                  'flutter/codelab_agent_acp.json',
                ],
          additional: const ['scenario-embedded.xml', ...client],
          belongs: (t) => nameBelongsToId(t.name, evidence.label),
          // Набор корпуса, не загрузившийся или упавший в setUpAll, роняет
          // все его фикстуры, даже если их тестов в отчёте нет.
          suiteFailed: (suite) =>
              _suiteMatches(
                suite,
                transport
                    ? 'apps/codelab_agent/test/transport_conformance_test.dart'
                    : 'packages/dart/codelab_agent_acp/test/conformance_test.dart',
              ) ||
              _suiteMatches(
                suite,
                'packages/dart/codelab_client_acp/test/fixtures/'
                'client_fixture_conformance_test.dart',
              ),
        );
      case EvidenceKind.cli:
        final files = index.filesWithId(EvidenceKind.cli, evidence.id);
        return _Sources(
          obligatory: const ['cli-dart.json'],
          additional: const [
            'cli-embedded.json',
            'dart/codelab_cli.json',
            'flutter/codelab_cli.json',
          ],
          belongs: (t) => nameBelongsToId(t.name, evidence.label),
          suiteFailed: (suite) => files.any((f) => _suiteMatches(suite, f)),
        );
      case EvidenceKind.core:
        final files = index.filesWithId(EvidenceKind.core, evidence.id);
        return _Sources(
          obligatory: [
            for (final pkg in {for (final f in files) _packageOf(f)})
              for (final dir in const ['dart', 'flutter']) '$dir/$pkg.json',
          ],
          belongs: (t) => nameBelongsToId(t.name, evidence.label),
          suiteFailed: (suite) => files.any((f) => _suiteMatches(suite, f)),
        );
      case EvidenceKind.testFile:
        final pkg = _packageOf(evidence.id);
        return _Sources(
          obligatory: ['dart/$pkg.json', 'flutter/$pkg.json'],
          belongs: (t) =>
              t.suitePath != null && _suiteMatches(t.suitePath!, evidence.id),
          suiteFailed: (suite) => _suiteMatches(suite, evidence.id),
        );
      case EvidenceKind.app:
        final name = '${evidence.id}.json';
        return _Sources(
          obligatory: ['app/dart-agent/$name'],
          additional: ['app/embedded/$name'],
          belongs: (_) => true,
          suiteFailed: (_) => true,
        );
      case EvidenceKind.allAcp || EvidenceKind.allApp:
        throw StateError('unreachable: ${evidence.kind}');
    }
  }

  bool _hasTransport(File fixture) {
    try {
      final json = jsonDecode(fixture.readAsStringSync());
      final setup = json is Map ? json['setup'] : null;
      return setup is Map && setup['transport'] != null;
    } on FormatException {
      return false;
    }
  }

  ReportSource? _read(Evidence evidence, String relative) {
    if (evidence.kind == EvidenceKind.app) {
      final root = appResultsDir!;
      final nested = _load(root, relative);
      // Каталог отчётов app допускает и корень с `app/<режим>/…`, и сам `app/`.
      return nested ?? _load(root, relative.replaceFirst('app/', ''));
    }
    return _load(resultsDir, relative);
  }

  EvidenceVerdict _fold(String rowId, Evidence evidence, _Sources s) {
    EvidenceVerdict verdict(
      EvidenceStatus status, {
      String? source,
      String? reason,
    }) => EvidenceVerdict(
      rowId: rowId,
      evidence: evidence.label,
      status: status,
      source: source,
      reason: reason,
    );

    final obligatory = [
      for (final path in s.obligatory) ?_read(evidence, path),
    ];
    final additional = [
      for (final path in s.additional) ?_read(evidence, path),
    ];

    // 1. Падение в любом источнике сильнее всего остального.
    for (final source in [...obligatory, ...additional]) {
      if (source.tests.any(
        (t) => s.belongs(t) && t.outcome == TestOutcome.failed,
      )) {
        return verdict(EvidenceStatus.failed, source: source.name);
      }
      if (source.failedSuitePaths.any(s.suiteFailed)) {
        return verdict(
          EvidenceStatus.failed,
          source: source.name,
          reason: 'suite failed to load or its setUpAll failed',
        );
      }
    }

    // 1а. Оборванный отчёт (нет `done`) нельзя читать как «прошло» ни при
    // каких обстоятельствах: чужое падение не объясняет обрыва. А
    // `done.success == false` без единого упавшего теста или набора
    // объяснения не имеет и роняет всё, что в источнике (D5).
    for (final source in obligatory) {
      if (!source.complete) {
        return verdict(
          EvidenceStatus.failed,
          source: source.name,
          reason: 'report incomplete',
        );
      }
      final explained =
          source.tests.any((t) => t.outcome == TestOutcome.failed) ||
          source.failedSuitePaths.isNotEmpty;
      if (!source.success && !explained) {
        return verdict(
          EvidenceStatus.failed,
          source: source.name,
          reason: 'suite reported failure',
        );
      }
    }

    // 2. В обязательном источнике нужен хотя бы один тест id. Для
    // доказательства-пути (Q8) пропуск с причиной из `allowedSkips` не
    // открывает строку, но и не доказывает её: такой тест не учитывается, а
    // файл, где все тесты пропущены по перечню, — `not-run` (нет ни одного
    // `pass`, D5).
    final required = [
      for (final source in obligatory)
        for (final test in source.tests)
          if (s.belongs(test) &&
              !(evidence.kind == EvidenceKind.testFile &&
                  test.outcome == TestOutcome.skipped &&
                  _isAllowedSkip(test, evidence)))
            (source, test),
    ];
    if (required.isEmpty) return verdict(EvidenceStatus.notRun);

    // 3. Пропуск в обязательном источнике открывает строку всегда.
    for (final (source, test) in required) {
      if (test.outcome == TestOutcome.skipped) {
        return verdict(
          EvidenceStatus.skipped,
          source: source.name,
          reason: test.skipReason,
        );
      }
    }

    // 4. В дополнительном — только по перечню allowedSkips (Q5).
    for (final source in additional) {
      for (final test in source.tests) {
        if (s.belongs(test) &&
            test.outcome == TestOutcome.skipped &&
            !_isAllowedSkip(test, evidence)) {
          return verdict(
            EvidenceStatus.skipped,
            source: source.name,
            reason: test.skipReason,
          );
        }
      }
    }
    return verdict(EvidenceStatus.pass);
  }

  /// Пропуск разрешён перечнем: причина совпадает с шаблоном целиком (D5, Q5, Q8).
  ///
  /// Запасной признак по имени (заметка `[skipped: …]`) — только когда
  /// причины нет и только не для доказательства-пути: у файла-доказательства
  /// пропуск без причины перечнем не оправдывается (Q8).
  bool _isAllowedSkip(TestRecord test, Evidence evidence) {
    final reason = test.skipReason ?? '';
    if (reason.isNotEmpty) {
      return allowedSkips.any((a) => !a.onName && a.matches(reason));
    }
    if (evidence.kind == EvidenceKind.testFile) return false;
    return allowedSkips.any((a) => a.onName && a.matches(test.name));
  }

  /// Сводит вердикты фикстур или файлов шаблона в один: берётся худший.
  EvidenceVerdict _combine(
    String rowId,
    Evidence evidence,
    List<EvidenceVerdict> parts,
  ) {
    const severity = [
      EvidenceStatus.failed,
      EvidenceStatus.missing,
      EvidenceStatus.skipped,
      EvidenceStatus.notRun,
      EvidenceStatus.deferred,
      EvidenceStatus.pass,
    ];
    if (parts.isEmpty) {
      return EvidenceVerdict(
        rowId: rowId,
        evidence: evidence.label,
        status: EvidenceStatus.missing,
      );
    }
    final worst = parts.reduce(
      (a, b) => severity.indexOf(b.status) < severity.indexOf(a.status) ? b : a,
    );
    if (worst.status == EvidenceStatus.pass ||
        worst.status == EvidenceStatus.deferred) {
      return EvidenceVerdict(
        rowId: rowId,
        evidence: evidence.label,
        status: worst.status,
      );
    }
    final count = parts.where((v) => v.status == worst.status).length;
    return EvidenceVerdict(
      rowId: rowId,
      evidence: evidence.label,
      status: worst.status,
      source: worst.source,
      reason: [
        '${worst.evidence}${count > 1 ? ' (+${count - 1} more)' : ''}',
        if (worst.reason != null) worst.reason!,
      ].join(' '),
    );
  }
}

/// Имя пакета по пути файла от корня репозитория: каталог пакета или app.
String _packageOf(String repoRelativePath) {
  final parts = p.posix.split(repoRelativePath.replaceAll(r'\', '/'));
  return parts.length >= 3 && parts.first == 'packages' ? parts[2] : parts[1];
}

/// Совпадает ли путь набора из отчёта [suite] с файлом теста [file] (путь от
/// корня репозитория).
///
/// Репортёр пишет `suite.path` по-разному: абсолютным (Flutter), от корня
/// репозитория (`dart test` из корня) или от каталога пакета (`dart test` в
/// пакете: `test/a_test.dart`). Поэтому полный путь сравнивается по хвосту на
/// границе каталога, а путь от пакета — только целиком: иначе
/// `/other/test/a_test.dart` совпал бы с одноимённым файлом чужого пакета.
bool _suiteMatches(String suite, String file) {
  final normalized = suite.replaceAll(r'\', '/');
  final parts = p.posix.split(file);
  final inPackage = parts.first == 'packages'
      ? parts.skip(3).join('/')
      : parts.skip(2).join('/');
  return normalized == file ||
      normalized.endsWith('/$file') ||
      normalized == inPackage;
}
