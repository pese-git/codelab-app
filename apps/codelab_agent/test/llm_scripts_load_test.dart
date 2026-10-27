import 'dart:io';

import 'package:codelab_agent/src/cli/serve_args.dart';
import 'package:codelab_agent/src/host/llm_script.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
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
  /// (`E2eAgent.startWebSocketAgent`, задача 5.6 change
  /// `add-session-list-and-reload`).
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

  test('a broken scenario is a usage error', () {
    final temp = Directory.systemTemp.createTempSync('llm_script_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final file = File('${temp.path}/broken.json')
      ..writeAsStringSync('{"llm": {"steps": [{"reply": [{"txt": "x"}]}]}}');
    expect(
      () => LlmScript.load(
        file.path,
        models: const [],
        clock: const SystemClock(),
        cwdOf: (_) => null,
      ),
      throwsA(isA<UsageError>()),
    );
  });
}
