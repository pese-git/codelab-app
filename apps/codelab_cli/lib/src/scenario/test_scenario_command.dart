import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart';

import '../cli_args.dart';
import '../exit_codes.dart';
import '../profiles/profile_arg.dart';
import 'agent_connector.dart';

/// `codelab test-scenario <файл-или-папка>... --agent <профиль>` — golden-
/// фикстуры ACP против агента профиля.
///
/// Почему: эталон поведения агента — фикстуры корпуса, и любой агент
/// (`codelab-agent`, Python-агент, сторонний) должен проверяться ими из
/// рабочего бинаря тем же алгоритмом, что у тестов агента (H-04; spec
/// cli-scenario-driver; design.md change `add-codelab-cli`, D12).
///
/// Для чего: на фикстуру — строка `PASS|FAIL|SKIP <id> (<время>)` в stdout
/// в порядке id, под `SKIP` — причина, под `FAIL` — расхождение с
/// ожидаемым и фактическим кадром в JSON с отступами; в конце —
/// `<passed> passed, <failed> failed, <skipped> skipped`.
///
/// Как использовать: `runCodelab` передаёт разобранные [options] и профиль;
/// код `0` — без `FAIL`, `1` — есть `FAIL` (в том числе агент не
/// запустился) и `1`, если не сыграна ни одна фикстура. Ошибки использования
/// (нет пути, путь не существует, битая фикстура) — [UsageError], код `64`. [quietPeriod] — тишина в конце
/// фикстуры (§14.9).
Future<int> runTestScenario(
  CliOptions options, {
  required ConnectionProfile profile,
  required Map<String, String> environment,
  required StringSink stdout,
  required StringSink stderr,
  ProfileSecrets? profileSecrets,
  Duration quietPeriod = const Duration(milliseconds: 200),
}) async {
  final List<AcpFixture> fixtures;
  try {
    fixtures = _load(options.positional);
  } on UsageError {
    // Путь фикстуры — слово argv: если среди слов есть `secret`, оно могло
    // быть значением секрета, и текст ошибки его не цитирует (D8).
    if (options.argvHasSecret) {
      throw const UsageError('Cannot load the fixtures');
    }
    rethrow;
  }
  final filter = options.filter;
  final selected = [
    for (final fixture in fixtures)
      if (filter == null || _glob(filter).hasMatch(fixture.id)) fixture,
  ];
  // Пустой секрет `secret:` профиля — то же предупреждение, что у остальных
  // режимов (spec codelab-cli «Профили подключения CLI»).
  if (profileSecrets != null &&
      await ProfileSecretSource(
        environment,
        stored: profileSecrets,
      ).isSecretMissing(profile)) {
    stderr.writeln(secretMissingMessage(profile.id));
  }
  final agent = ScenarioAgent(
    profile,
    environment: environment,
    profileSecrets: profileSecrets,
  );
  var passed = 0;
  var failed = 0;
  var skipped = 0;
  for (final fixture in selected) {
    final watch = Stopwatch()..start();
    final _Outcome outcome;
    final reason = agent.skipReason(fixture);
    if (reason != null) {
      outcome = _Outcome.skip(reason);
    } else {
      outcome = await _play(
        fixture,
        agent,
        frameTimeout: options.timeout ?? const Duration(seconds: 30),
        quietPeriod: quietPeriod,
      );
    }
    final seconds = (watch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    stdout.writeln('${outcome.status} ${fixture.id} (${seconds}s)');
    for (final line in outcome.details) {
      stdout.writeln('    $line');
    }
    switch (outcome.status) {
      case 'PASS':
        passed++;
      case 'FAIL':
        failed++;
      default:
        skipped++;
    }
  }
  stdout.writeln('$passed passed, $failed failed, $skipped skipped');
  if (passed + failed == 0) {
    // Прогон, где ничего не сыграно (всё пропущено или фильтр пуст), не
    // доказывает ничего: зелёный код скрыл бы пустой корпус (решение
    // пользователя 2026-11-02, U4).
    stderr.writeln('codelab: no fixtures were played');
    return failureExit;
  }
  return failed == 0 ? okExit : failureExit;
}

/// Играет одну фикстуру и превращает любой сбой в строки `FAIL`.
///
/// Почему причина запуска процесса — только `ProcessException.message`:
/// `ProcessException.toString()` печатает `Command: <команда и аргументы>`, а
/// аргументы агента могут нести ключ (`--api-key sk-…`), который
/// `SecretRedactor` не маскирует. Основная защита — `StdioAcpTransport`
/// (D8), здесь вторая линия на случай ошибки не из транспорта (connector
/// драйвера, будущие транспорты): строка `Command: …` в stdout не попадает
/// никогда (design.md change `redact-cli-stdio-profile-args`, D9).
///
/// Имя команды строка `FAIL` не называет: она стоит под id фикстуры, а
/// профиль задан флагом `--agent` того же запуска.
Future<_Outcome> _play(
  AcpFixture fixture,
  ScenarioAgent agent, {
  required Duration frameTimeout,
  required Duration quietPeriod,
}) async {
  try {
    final result = await runAgentFixtureOver(
      fixture,
      agent.connector(fixturePath: fixture.sourcePath!),
      frameTimeout: frameTimeout,
      quietPeriod: quietPeriod,
      transportFixtures: false,
    );
    return result.skipped
        ? _Outcome.skip(result.skipReason ?? 'skipped by the driver')
        : const _Outcome('PASS', []);
  } on AgentFixtureFailure catch (failure) {
    return _Outcome('FAIL', _diff(failure));
  } on Object catch (error) {
    final reason = error is ProcessException
        ? error.message
        : describeFailure(error);
    return _Outcome('FAIL', ['the agent did not run the fixture: $reason']);
  }
}

/// Расхождение для человека: где, что не так и оба кадра с отступами.
List<String> _diff(AgentFixtureFailure failure) {
  const json = JsonEncoder.withIndent('  ');
  final where = failure.frameIndex < 0
      ? 'handshake frame'
      : 'frame #${failure.frameIndex}';
  return [
    '$where${failure.note == null ? '' : ' (${failure.note})'}: '
        '${failure.message}',
    for (final mismatch in failure.mismatches) '- $mismatch',
    if (failure.expected != null) ...[
      'expected:',
      ...json.convert(failure.expected).split('\n'),
    ],
    if (failure.actual != null) ...[
      'actual:',
      ...json.convert(failure.actual).split('\n'),
    ],
  ];
}

/// Фикстуры путей [paths] без повторов, по id; ошибка пути или формата —
/// [UsageError] с путём и причиной.
List<AcpFixture> _load(List<String> paths) {
  if (paths.isEmpty) {
    throw const UsageError(
      'Pass fixture files or folders: codelab test-scenario <path>... '
      '--agent <profile>',
    );
  }
  final byId = <String, AcpFixture>{};
  for (final path in paths) {
    try {
      final fixtures = switch (FileSystemEntity.typeSync(path)) {
        FileSystemEntityType.directory => loadFixtureCorpus(directory: path),
        FileSystemEntityType.file => [loadFixtureFile(path)],
        _ => throw UsageError('No such file or folder: $path'),
      };
      for (final fixture in fixtures) {
        byId.putIfAbsent(fixture.id, () => fixture);
      }
    } on FixtureFormatException catch (error) {
      throw UsageError('$path: $error');
    }
  }
  return [for (final id in byId.keys.toList()..sort()) byId[id]!];
}

/// Glob по id: `*` — любые символы, `?` — один символ.
RegExp _glob(String pattern) => RegExp(
  '^${pattern.split('').map((c) => switch (c) {
    '*' => '.*',
    '?' => '.',
    _ => RegExp.escape(c),
  }).join()}\$',
);

final class _Outcome {
  const _Outcome(this.status, this.details);

  _Outcome.skip(String reason) : this('SKIP', [reason]);

  final String status;
  final List<String> details;
}
