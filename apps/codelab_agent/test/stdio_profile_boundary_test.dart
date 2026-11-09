import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:test/test.dart';

import 'support/agent_process.dart';

/// Приёмочный тест границы «описание stdio-агента — бинарь»
/// (change `switch-default-agent-to-dart`, D10, задача 1.19; спецификация
/// `agent-transports`, сценарий «Описание подключается»).
///
/// Почему: `codelabAgentStdioProfile` — единственный источник аргументов и
/// env для запуска Dart-агента клиентами. Если бинарь перестанет принимать
/// `serve --stdio` или упадёт с `CODELAB_LOG_LEVEL=DEBUG`, описание станет
/// ложным, а юнит-тесты описания этого не заметят.
///
/// Как: команда `codelab-agent` заменена запуском бинаря из исходников
/// (`AgentProcess`), аргументы и env берутся строго из описания, плюс
/// `--llm-script` вместо настоящего провайдера. Это интеграционный тест на
/// Dart VM (`AGENTS.md` §21), исключение из TDD — дорожная карта §9.1.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_profile_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('process started with codelabAgentStdioProfile args and env answers '
      'initialize with protocolVersion 1', () async {
    final agent = await AgentProcess.start(
      [
        ...codelabAgentStdioProfile.args,
        '--llm-script',
        'test/llm_scripts/hello.json',
      ],
      // CODELAB_HOME — только изоляция теста от домашнего каталога
      // разработчика; значения описания идут как есть.
      environment: {
        ...codelabAgentStdioProfile.env,
        'CODELAB_HOME': '${temp.path}/home',
      },
    );
    // Если тест упадёт до closeStdin, процесс агента не должен пережить
    // тест и удалённый в tearDown CODELAB_HOME (testing.md, cleanup процессов).
    addTearDown(() => agent.kill(ProcessSignal.sigkill));
    agent.sendLine(
      '{"jsonrpc":"2.0","id":1,"method":"initialize",'
      '"params":{"protocolVersion":1}}',
    );

    final line = await agent.nextStdoutLine();
    final answer = jsonDecode(line!) as Map<String, Object?>;
    expect(answer['id'], 1);
    expect((answer['result']! as Map)['protocolVersion'], 1);

    await agent.closeStdin();
    expect(await agent.exitCode, 0);
  });
}
