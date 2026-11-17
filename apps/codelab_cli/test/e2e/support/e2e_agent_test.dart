// Выбор агента e2e CLI (tasks 1.1, 2.3, 4.1 change `add-cli-e2e-agent-matrix`;
// testing-quality «PTY-e2e терминального клиента»; design.md, D1–D4).

import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart'
    show CodelabCompatibleStdioAgentMode;
import 'package:test/test.dart';

import 'e2e_agent.dart';

typedef _Mode = CodelabCompatibleStdioAgentMode;

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('e2e_agent_'));
  tearDown(() => dir.delete(recursive: true));

  test('without CODELAB_E2E_AGENT the agent is scripted', () {
    expect(E2eCliAgent.fromEnvironment(const {}).kind, E2eAgentKind.scripted);
    expect(
      E2eCliAgent.fromEnvironment(const {'CODELAB_E2E_AGENT': 'dart'}).kind,
      E2eAgentKind.dart,
    );
  });

  test('an unknown CODELAB_E2E_AGENT is an error', () {
    expect(
      () => E2eCliAgent.fromEnvironment(const {'CODELAB_E2E_AGENT': 'rust'}),
      throwsArgumentError,
    );
  });

  test('scripted: the agent of codelab_acp_testing and its texts', () async {
    final agent = E2eCliAgent.fromEnvironment(const {});

    final normal = await agent.launch(dir);
    final permission = await agent.launch(
      dir,
      mode: _Mode.withPermissionRequest,
    );
    final models = await agent.launch(dir, mode: _Mode.withConfigOptions);

    expect(normal.agent, startsWith('stdio:'));
    expect(normal.agent, contains('codelab_compatible_stdio_agent.dart'));
    expect(normal.answer, 'hello from compatible stdio agent');
    expect(permission.permissionTitle, 'Run test command');
    expect(permission.permissionCommand, 'echo hello');
    expect(permission.allowedMarker, 'approved: allow_once');
    expect(models.models, ['gpt-5', 'gpt-4']);
  });

  test('dart: codelab-agent from the kernel with the script of the '
      'mode', () async {
    final agent = E2eCliAgent.fromEnvironment(const {
      'CODELAB_E2E_AGENT': 'dart',
    });

    final permission = await agent.launch(
      dir,
      mode: _Mode.withPermissionRequest,
    );
    final models = await agent.launch(dir, mode: _Mode.withConfigOptions);

    expect(permission.agent, contains('codelab_agent.dill'));
    expect(permission.agent, contains('serve --stdio --llm-script'));
    expect(permission.agent, contains('with_permission_request.json'));
    expect(permission.agent, contains('--permission-mode standard'));
    expect(permission.permissionTitle, 'echo hello');
    expect(permission.allowedMarker, '✓ echo hello');
    expect(models.agent, contains('--model gpt-5 --model gpt-4'));
    expect(models.models, ['scripted/gpt-5', 'scripted/gpt-4']);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('dart: a mode without a script is a state error', () async {
    final agent = E2eCliAgent.fromEnvironment(const {
      'CODELAB_E2E_AGENT': 'dart',
    });

    expect(
      agent.launch(dir, mode: _Mode.withAvailableCommands),
      throwsStateError,
    );
  });

  test('embedded: the script, permission mode and models go to the test '
      'entry point through the environment, the agent is the word '
      '"embedded"', () async {
    final agent = E2eCliAgent.fromEnvironment(const {
      'CODELAB_E2E_AGENT': 'embedded',
    });

    final permission = await agent.launch(
      dir,
      mode: _Mode.withPermissionRequest,
    );
    final models = await agent.launch(dir, mode: _Mode.withConfigOptions);

    expect(agent.kind, E2eAgentKind.embedded);
    expect(permission.agent, 'embedded');
    expect(
      permission.environment['CODELAB_E2E_LLM_SCRIPT'],
      endsWith('llm_scripts/with_permission_request.json'),
    );
    expect(permission.environment['CODELAB_E2E_PERMISSION_MODE'], 'standard');
    expect(
      permission.environment['CODELAB_E2E_SESSIONS_DIR'],
      contains(dir.path),
    );
    expect(permission.permissionTitle, 'echo hello');
    expect(
      models.environment['CODELAB_E2E_MODELS'],
      'scripted/gpt-5,scripted/gpt-4',
    );
    expect(models.models, ['scripted/gpt-5', 'scripted/gpt-4']);
    expect(agent.needsStoredProfile, isNotNull);
  });

  test('embedded: a mode without a script is a state error', () async {
    final agent = E2eCliAgent.fromEnvironment(const {
      'CODELAB_E2E_AGENT': 'embedded',
    });

    expect(
      agent.launch(dir, mode: _Mode.withAvailableCommands),
      throwsStateError,
    );
  });

  group('python', () {
    /// `codelab` в своём каталоге `PATH`: печатает [help] на `serve --help`.
    Future<Map<String, String>> fakeCodelab(String help, {int code = 0}) async {
      final bin = await Directory('${dir.path}/bin').create();
      final file = File('${bin.path}/codelab')
        ..writeAsStringSync('#!/bin/sh\necho "$help"\nexit $code\n');
      await Process.run('chmod', ['+x', file.path]);
      return {'CODELAB_E2E_AGENT': 'python', 'PATH': bin.path};
    }

    test('another codelab in PATH is a skip reason', () async {
      final agent = E2eCliAgent.fromEnvironment(
        await fakeCodelab('Usage: codelab [options]', code: 64),
      );

      expect(
        await agent.unavailable(),
        'Python agent (codelab serve) is not installed',
      );
    });

    // Задача 1.9 change `retire-python-agent`, D12: Dart CLI с алиасом на
    // `serve --help` уходит в `codelab-agent serve --help` — код 64, справка
    // в stderr, пустой stdout. Признака Python-агента (код 0 и `--stdio` в
    // stdout) нет. Тест закрепляет зависимость от того, что у
    // `codelab-agent serve` нет `--help` с кодом 0.
    test('codelab with the serve alias (codelab-agent help in stderr, '
        'code 64) is a skip reason', () async {
      final bin = await Directory('${dir.path}/bin').create();
      final file = File('${bin.path}/codelab')
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'echo \'codelab: "codelab serve" is deprecated and will be removed '
          'in a future release; use "codelab-agent serve" instead.\' >&2\n'
          'echo "Usage: codelab-agent serve [--stdio] [--port <n>]" >&2\n'
          'exit 64\n',
        );
      await Process.run('chmod', ['+x', file.path]);
      final agent = E2eCliAgent.fromEnvironment({
        'CODELAB_E2E_AGENT': 'python',
        'PATH': bin.path,
      });

      expect(
        await agent.unavailable(),
        'Python agent (codelab serve) is not installed',
      );
    });

    test('the Python agent starts with the mock provider in its own '
        'CODELAB_HOME', () async {
      final agent = E2eCliAgent.fromEnvironment(
        await fakeCodelab('usage: codelab serve [-h] [--stdio] [--no-web]'),
      );

      expect(await agent.unavailable(), isNull);
      final launch = await agent.launch(dir);
      final home = '${dir.path}/python-home';
      expect(
        launch.agent,
        "stdio:env CODELAB_HOME='$home' codelab serve --stdio",
      );
      expect(
        File('$home/codelab.toml').readAsStringSync(),
        contains('provider = "mock"'),
      );
      expect(launch.answer, 'Mock response');
    });

    test('a mode with tools is a state error', () async {
      final agent = E2eCliAgent.fromEnvironment(
        await fakeCodelab('usage: codelab serve [-h] [--stdio]'),
      );

      expect(
        agent.launch(dir, mode: _Mode.withPermissionRequest),
        throwsStateError,
      );
    });
  });

  test('scripted and dart are always available', () async {
    expect(await E2eCliAgent.fromEnvironment(const {}).unavailable(), isNull);
  });
}
