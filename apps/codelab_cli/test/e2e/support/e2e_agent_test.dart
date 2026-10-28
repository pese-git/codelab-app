// Выбор агента e2e CLI (tasks 1.1, 2.3 change `add-cli-e2e-agent-matrix`;
// testing-quality «PTY-e2e терминального клиента»; design.md, D1–D3).

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
}
