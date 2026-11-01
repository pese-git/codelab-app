import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/testing.dart';
import 'package:test/test.dart';

import 'support/agent_process.dart';

/// Сценарии e2e codelab-app для режима `dart` (задача 7.1; design.md change
/// `add-codelab-agent-binary`, D9).
///
/// Почему здесь, а не в `apps/codelab_desktop/test`: приложению запрещено
/// импортировать `codelab_agent_*` (сторож импортов), а проверить файл можно
/// только загрузчиком `--llm-script`. Тест читает сценарии по пути файла.
///
/// Прогон на устройстве — только в `release/<version>` (`AGENTS.md` §21),
/// поэтому битый сценарий ловится здесь, на Dart VM.
void main() {
  final directory = Directory(
    '$appDirectory/../codelab_desktop/integration_test/llm_scripts',
  );

  /// Режимы `CodelabCompatibleStdioAgentMode`, тесты которых идут против
  /// Dart-агента (таблица контракта e2e, `09-09`).
  const wireNames = [
    'normal',
    'with_config_options',
    'with_permission_request',
    'with_fs_access',
    'with_terminal_execution',
    'with_plan',
    'with_queued_prompt_drain',
    'with_concurrent_sessions',
    'echoes_cwd',
    'with_session_list',
  ];

  /// Сценарии e2e вне таблицы режимов: агента запускает сам тест app
  /// (`E2eAgent.startWebSocketAgent`, change `cancel-turn-on-ws-disconnect`).
  const ownScripts = ['reconnect_mid_turn'];

  test('every mode of the e2e contract has a scenario', () {
    final present = directory.existsSync()
        ? {
            for (final file in directory.listSync().whereType<File>())
              if (file.path.endsWith('.json'))
                file.uri.pathSegments.last.replaceAll('.json', ''),
          }
        : <String>{};
    expect(present, containsAll(wireNames));
  });

  for (final name in [...wireNames, ...ownScripts]) {
    test('$name.json loads as --llm-script', () {
      final script = LlmScript.load(
        '${directory.path}/$name.json',
        models: const [],
        clock: const SystemClock(),
        cwdOf: (_) => null,
      );
      expect(script.models, isNotEmpty);
    }, skip: directory.existsSync() ? null : 'no ${directory.path}');
  }

  // Сценарии e2e терминального клиента для `CODELAB_E2E_AGENT=dart`
  // (testing-quality «PTY-e2e терминального клиента»; design.md change
  // `add-cli-e2e-agent-matrix`, D3). Список — режимы, для которых
  // `E2eCliAgent` запускает Dart-агента.
  group('codelab_cli e2e scripts', () {
    final cli = Directory('$appDirectory/../codelab_cli/test/e2e/llm_scripts');
    const cliScripts = [
      'normal',
      'with_permission_request',
      'with_critical_permission',
      'with_config_options',
      'with_session_list',
      'with_tool_calls',
      'hangs_until_cancel',
      'prompt_error',
      'empty_response',
    ];

    test('every mode has a scenario and nothing else is there', () {
      final present = cli.existsSync()
          ? {
              for (final file in cli.listSync().whereType<File>())
                if (file.path.endsWith('.json'))
                  file.uri.pathSegments.last.replaceAll('.json', ''),
            }
          : <String>{};
      expect(present, unorderedEquals(cliScripts));
    });

    for (final name in cliScripts) {
      test('$name.json loads as --llm-script', () {
        final script = LlmScript.load(
          '${cli.path}/$name.json',
          models: const [],
          clock: const SystemClock(),
          cwdOf: (_) => null,
        );
        expect(script.models, isNotEmpty);
      });
    }
  });

  // Случай «битый сценарий» разбора перенесён в
  // `codelab_agent_io/test/scripted/llm_script_test.dart`; перевод в
  // `UsageError` (код 64) проверяет `agent_host_test.dart`.
}
