// PTY-e2e сегментов usage статус-строки TUI `cli/status-line-usage` (задача
// 3.6 change `add-usage-extension`; spec codelab-tui «Строка подсказок и
// статус-строка TUI»: «Сегменты usage», «Агент без usage»; U-13;
// design.md, D12, D23 Т3, Т6).
//
// Красный до задач 3.9 и 3.11: `CodelabCompatibleStdioAgentMode.withUsage`
// (режим `with_usage`, 3.9) не существует, файл и `support/e2e_agent.dart`
// не компилируются; затем нужны сегменты TUI (3.11) и, для `dart` и
// `embedded`, сценарий `llm_scripts/with_usage.json` (3.9).
//
// Числа scripted-агента зафиксированы его тестом
// `codelab_acp_testing/test/usage_agent_test.dart`: первый ход — `context`
// 18000 из 200000 (9 %), стоимость сессии `0.04`. Dart-агент и встроенный
// агент считают числа по сценарию модели, поэтому для них проверяется форма
// сегментов, а не значения. «Без usage» — только scripted-агент: остальные
// объявляют `usage` всегда (D3, D23 Т6).
@Timeout(Duration(seconds: 90))
library;

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart'
    show CodelabCompatibleStdioAgentMode;
import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';
import 'support/pty_process.dart';

Future<void> main() async {
  final skip = await PtyProcess.unavailableReason();
  final agentSkip = await E2eCliAgent.current.unavailable();
  late Directory dir;
  late E2eCliLaunch launch;

  setUp(() async => dir = await Directory.systemTemp.createTemp('cli_usage_'));
  tearDown(() => dir.delete(recursive: true));

  Future<PtyProcess> tui(
    CodelabCompatibleStdioAgentMode mode, {
    List<String> args = const [],
    String ui = 'tui',
  }) async {
    launch = await E2eCliAgent.current.launch(dir, mode: mode);
    return PtyProcess.start(
      'sh',
      [
        '-c',
        r'"$0" "$@"; code=$?; echo; exit $code',
        dartExecutable(),
        await CliProcess.kernel(),
        '--agent',
        launch.agent,
        '--cwd',
        dir.path,
        '--ui',
        ui,
        ...args,
      ],
      columns: 120,
      rows: 30,
      environment: {
        'HOME': '${dir.path}/home',
        'CODELAB_HOME': '${dir.path}/codelab',
        'LANG': 'en_US.UTF-8',
        ...launch.environment,
      },
    );
  }

  test(
    'cli/status-line-usage: контекст, токены и стоимость после хода',
    () async {
      final pty = await tui(
        CodelabCompatibleStdioAgentMode.withUsage,
        args: ['hello'],
      );
      await pty.waitFor(launch.answer);

      if (E2eCliAgent.current.kind == E2eAgentKind.scripted) {
        await pty.waitFor('ctx 9%');
        await pty.waitFor(r'$0.04');
      } else {
        // Числа задаёт сценарий модели `with_usage.json`.
        await pty.waitFor('ctx ');
        await pty.waitFor(r'$');
      }
      expect(pty.text, matches(RegExp(r'↑\S+ ↓\S+')));

      pty.write('\x04');
      expect(await pty.exitCode, 0);
    },
    skip: skip ?? agentSkip,
  );

  test(
    'cli/status-line-usage: агент без usage — сегментов и нуля нет',
    () async {
      final pty = await tui(
        CodelabCompatibleStdioAgentMode.normal,
        args: ['hello'],
      );
      await pty.waitFor(launch.answer);
      pty.write('\x04');
      expect(await pty.exitCode, 0);

      final text = pty.text;
      expect(text, isNot(contains('ctx ')));
      expect(text, isNot(contains('↑')));
      expect(text, isNot(contains('↓')));
      expect(text, isNot(contains(r'$0')));
    },
    skip: skip ?? agentSkip,
    tags: scriptedOnly,
  );

  // change `add-usage-ledger`, задача 3.7 (D8, D10; acp-client-kit «Снимок
  // load до регистрации сессии»). Scripted-агент `with_usage` отвечает на
  // `session/load` и сразу шлёт снимок `trigger: "load"` для незнакомой ему
  // сессии как для журнала из двух ходов (3.9); строка статуса после хода
  // без «~» (причина `beforeLoad` не должна появляться).
  //
  // ВАЖНО: на scripted-агенте этот тест ЗЕЛЁНЫЙ уже сейчас: ответ и снимок
  // приходят одним куском вывода, и порядок обработки не воспроизводит
  // D10 (на Dart-агенте они приходят раздельно). Он — регрессионный, как и
  // предполагал tasks.md; красным остаётся `cli/resume-last-session`
  // (`headless_exit_codes_test.dart`, `test:e2e:cli:dart-agent`):
  // `usage.unknown_session` уходит в stdout. Детерминированно порядок
  // воспроизводит `codelab_client_core/test/usage/session_usage_test.dart`.
  test(
    'cli/resume-usage: --resume — снимок load не теряется, строка без «~»',
    () async {
      final pty = await tui(
        CodelabCompatibleStdioAgentMode.withUsage,
        args: ['--resume', 'listed-session-1', '--verbose', 'hello'],
        ui: 'line',
      );
      await pty.waitFor('usage reply 3');
      await pty.waitFor('↑');
      pty.write('\x04');
      expect(await pty.exitCode, 0);

      final text = pty.text;
      expect(text, isNot(contains('usage.unknown_session')));
      expect(text, isNot(contains('~')));
      expect(text, matches(RegExp(r'↑\S+ ↓\S+')));
    },
    skip: skip ?? agentSkip,
    tags: scriptedOnly,
  );

  // Тот же снимок `load` на headless-пути: журнал kit по умолчанию уходит
  // в stdout, поэтому запись `usage.unknown_session` испортила бы вывод `-p`.
  // Регрессионный на scripted-агенте (см. комментарий выше).
  test(
    'cli/resume-usage: headless --resume — в stdout только ответ, '
    'без usage.unknown_session',
    () async {
      launch = await E2eCliAgent.current.launch(
        dir,
        mode: CodelabCompatibleStdioAgentMode.withUsage,
      );

      final result = await CliProcess.run(
        [
          '--agent',
          launch.agent,
          '--cwd',
          dir.path,
          '--resume',
          'listed-session-1',
          '-p',
          'hello',
        ],
        environment: {
          'CODELAB_HOME': '${dir.path}/codelab',
          ...launch.environment,
        },
      );

      expect(result.exitCode, 0, reason: '$result');
      expect(result.stdout, 'usage reply 3\n');
    },
    skip: agentSkip,
    tags: scriptedOnly,
  );
}
