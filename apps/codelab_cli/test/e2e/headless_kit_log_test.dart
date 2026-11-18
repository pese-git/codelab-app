// E2E `cli/headless-print-basic` (H-01; spec cli-headless «Вывод headless»;
// apps/codelab_cli/AGENTS.md: «В headless stdout несёт только ответ агента»):
// журнал kit (`ClientWorkspace`) не попадает в stdout headless.
//
// Почему: composition root собирал `ClientWorkspace` без логгера CLI, и kit
// писал свои записи (`usage.unknown_session`, `usage.ledger.*`) логгером по
// умолчанию — JSON в stdout процесса перед ответом агента. Модульные тесты
// этого не видят: `FakeAgent` собирает свой `ClientWorkspace`, а не
// `buildCliRuntime`. Поэтому тест процессный — собранный CLI против
// маленького stdio-агента, который шлёт `_codelab/session/usage`: снимок
// незнакомой сессии (kit отбрасывает его записью `usage.unknown_session`)
// или снимок своей сессии с битым `turnId` (запись `usage.decode_failed`
// уровня warning — её `--verbose` обязан показать в stderr).

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';

/// Агент без зависимостей: `initialize` с `_meta.codelab.usage` версии 1,
/// `session/new` → `s1`, ход — чанк ответа, снимок usage и `end_turn`.
/// Аргумент `unknown-session` — снимок чужой сессии; `bad-turn-id` — снимок
/// `s1` с `turnId` неверного типа.
const _agentSource = r'''
import 'dart:convert';
import 'dart:io';

void send(Map<String, Object?> message) =>
    stdout.writeln(jsonEncode({'jsonrpc': '2.0', ...message}));

Future<void> main(List<String> args) async {
  final unknownSession = args.single == 'unknown-session';
  await for (final line in stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final message = jsonDecode(line) as Map<String, Object?>;
    final id = message['id'];
    switch (message['method']) {
      case 'initialize':
        send({
          'id': id,
          'result': {
            'protocolVersion': 1,
            'agentCapabilities': {
              '_meta': {
                'codelab': {
                  'usage': {'version': 1},
                },
              },
            },
            'authMethods': <Object?>[],
          },
        });
      case 'session/new':
        send({
          'id': id,
          'result': {'sessionId': 's1'},
        });
      case 'session/prompt':
        send({
          'method': 'session/update',
          'params': {
            'sessionId': 's1',
            'update': {
              'sessionUpdate': 'agent_message_chunk',
              'content': {'type': 'text', 'text': 'answer'},
            },
          },
        });
        const tokens = {
          'input': 10,
          'output': 5,
          'cacheRead': 0,
          'cacheWrite': 0,
        };
        send({
          'method': '_codelab/session/usage',
          'params': {
            'sessionId': unknownSession ? 'unknown-session' : 's1',
            'seq': 1,
            'trigger': 'turn',
            'turnId': unknownSession ? 'turn-1' : 42,
            'turn': {'steps': 1, 'tokens': tokens, 'cost': '0.01'},
            'session': {
              'turns': 1,
              'steps': 1,
              'tokens': tokens,
              'cost': '0.01',
            },
            'currency': 'USD',
            'context': {'used': 15, 'size': 1000},
          },
        });
        send({
          'id': id,
          'result': {'stopReason': 'end_turn'},
        });
      default:
        if (id != null) {
          send({
            'id': id,
            'error': {'code': -32601, 'message': 'Method not found'},
          });
        }
    }
  }
}
''';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('codelab_kit_log_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<CliResult> runHeadless(String mode, {bool verbose = false}) {
    final agent = File('${tmp.path}/agent.dart')
      ..writeAsStringSync(_agentSource);
    return CliProcess.run(
      [
        '-p',
        'hello',
        '-a',
        "stdio:'${dartExecutable()}' '${agent.path}' $mode",
        '-C',
        tmp.path,
        if (verbose) '--verbose',
      ],
      environment: {'CODELAB_HOME': '${tmp.path}/home'},
      // Агент свой, а не из `CODELAB_E2E_AGENT`, поэтому тест одинаков во
      // всех вариантах прогона: рабочая точка входа — это и есть проверяемый
      // composition root (тестовая точка входа `embedded` требует сценарий
      // модели, которого здесь нет).
      entry: CliEntry.production,
    );
  }

  test('cli/headless-print-basic: a usage snapshot of an unknown session '
      'leaves only the answer in stdout', () async {
    final result = await runHeadless('unknown-session');

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, 'answer\n', reason: '$result');
  });

  // Ветка `--verbose` composition root: тот же логгер CLI доходит до kit —
  // warning kit виден в stderr строкой `CliLogger`, а stdout по-прежнему
  // только ответ. Сумма снимка в журнал не попадает (§16).
  test('cli/headless-print-basic: with --verbose a kit warning goes to '
      'stderr and stdout keeps only the answer', () async {
    final result = await runHeadless('bad-turn-id', verbose: true);

    expect(result.exitCode, 0, reason: '$result');
    expect(result.stdout, 'answer\n', reason: '$result');
    final line = result.stderr
        .split('\n')
        .singleWhere(
          (line) => line.startsWith('[warning] usage.decode_failed '),
          orElse: () => fail('no usage.decode_failed in stderr: $result'),
        );
    // Поля проверяются по отдельности: порядок задают `bind` и
    // `withCorrelation` kit, а не контракт журнала.
    expect(
      line,
      allOf([
        contains(' component=client'),
        contains(' session_id=s1'),
        contains(' field=turnId'),
      ]),
    );
    // В журнале — только имя поля и причина: ни сумм, ни счётчиков снимка.
    for (final leaked in ['0.01', 'cost', 'tokens', 'input=']) {
      expect(result.stderr, isNot(contains(leaked)), reason: '$result');
    }
  });
}
