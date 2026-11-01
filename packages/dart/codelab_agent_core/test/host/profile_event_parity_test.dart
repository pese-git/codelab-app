import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

/// Паритет профилей хоста (agent-runtime «Профили хостов и сужение», сценарий
/// «Паритет профилей»; `agent-core-architecture` §10.12; design.md change
/// `add-embedded-agent-mode`, D1 (в), задача 2.7). Тест лежит в ядре: он
/// проверяет паритет самого ядра по профилям и не зависит от встроенного
/// агента; сборку `codelab_embedded` и бинаря сверяют их собственные тесты.
///
/// Один сценарий модели («прочитай файл, измени, покажи план») проходит через
/// ядро в профилях `agent-serve`, `embedded-app-desktop` и `embedded-cli` с
/// одинаковыми ответами на запросы разрешений. Последовательности `AgentEvent`
/// обязаны совпасть: профили различаются состоянием capability и режимом, но не
/// поведением цикла. Различаются только env и gate хоста (здесь они одинаковы
/// на всех трёх прогонах). Ядро собирается напрямую `buildAgentCore`, как это
/// делают хосты; сервер ACP и транспорт в сравнение не входят.
void main() {
  const profiles = ['agent-serve', 'embedded-app-desktop', 'embedded-cli'];

  final model = ModelRef(
    provider: 'p',
    id: 'm',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://p.invalid/v1'),
    contextWindow: 32000,
    maxOutputTokens: 4096,
  );

  Map<String, Object?> call(String id, String name, Object arguments) => {
    'reply': [
      {
        'toolCall': {'id': id, 'name': name, 'arguments': arguments},
      },
    ],
  };

  final steps = [
    call('c1', 'read', {'path': 'README.md'}),
    call('c2', 'edit', {
      'path': 'README.md',
      'oldText': 'draft',
      'newText': 'final',
    }),
    call('c3', 'update_plan', {
      'entries': [
        {'content': 'read', 'priority': 'high', 'status': 'completed'},
        {'content': 'edit', 'priority': 'medium', 'status': 'completed'},
      ],
    }),
    {
      'reply': [
        {'text': 'done'},
      ],
    },
  ];

  /// Что ядро сообщило хосту на шагах сценария, в порядке прихода. Поля,
  /// зависящие от времени и модели, в описание не входят.
  String describe(AgentEvent event) => switch (event) {
    ToolCallStarted(:final tool, :final input, :final kind) =>
      'ToolCallStarted $tool ${kind.name} ${jsonEncode(input)}',
    ToolCallFinished(:final toolCallId, :final outcome, :final diffs) =>
      'ToolCallFinished $toolCallId ${outcome.name} diffs=${diffs.length}',
    PlanUpdated(:final entries) =>
      'PlanUpdated ${[for (final e in entries) '${e.content}:${e.status.name}']}',
    MessageEnded(:final message) =>
      'MessageEnded ${message.runtimeType} ${_text(message)}',
    TurnEnded(:final reason) => 'TurnEnded ${reason.name}',
    AgentError(:final message) => 'AgentError $message',
    _ => event.runtimeType.toString(),
  };

  Future<({List<String> events, List<String> asked, String file})> run(
    String profile,
  ) async {
    final clock = FakeClock();
    final env = MemoryExecutionEnv(cwd: '/proj', clock: clock);
    await env.writeText('/proj/README.md', 'a draft\n');
    final asked = <String>[];
    final core = buildAgentCore(
      profile: HostProfile.of(profile).narrowed({
        // Журнал теста — в памяти (design.md ядра, D12), как у остальных
        // тестов сборки.
        HostCapability.sessionPersistence: const CapabilityOff('test'),
        HostCapability.shellExec: const CapabilityOff('test'),
      }),
      services: AgentCoreServices(
        baseEnv: env,
        gate: _RecordingGate(asked),
        logger: RecordingLogger(),
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: MemorySessionStore(),
      ),
      config: CoreConfig(defaultModel: model),
      streamFunction: ScriptedStreamFunction.fromJson({
        'steps': steps,
      }, clock: clock).call,
    );
    final session = await core.runtime.createSession(SessionSpec(cwd: '/proj'));
    final events = <String>[];
    final sub = session.events.listen((e) => events.add(describe(e)));
    await session.prompt([const TextContent('update the readme')]);
    await sub.cancel();
    await core.runtime.dispose();
    final file = await env.readText('/proj/README.md');
    return (
      events: events,
      asked: asked,
      file: switch (file) {
        Ok(:final value) => value,
        _ => 'unreadable',
      },
    );
  }

  test('the same model script gives the same AgentEvent sequence in '
      'agent-serve, embedded-app-desktop and embedded-cli', () async {
    final results = {for (final name in profiles) name: await run(name)};

    final reference = results['embedded-cli']!;
    expect(reference.file, 'a final\n');
    expect(reference.asked, ['edit'], reason: 'read is silent, edit asks');
    expect(
      reference.events,
      contains('PlanUpdated [read:completed, edit:completed]'),
    );
    expect(reference.events, contains(startsWith('TurnEnded')));
    expect(reference.events, isNot(contains(startsWith('AgentError'))));
    for (final name in profiles) {
      expect(results[name]!.events, reference.events, reason: name);
      expect(results[name]!.asked, reference.asked, reason: name);
      expect(results[name]!.file, reference.file, reason: name);
    }
  });
}

String _text(Message message) => switch (message) {
  AssistantMessage(:final content) || UserMessage(:final content) => [
    for (final block in content)
      if (block is TextContent) block.text,
  ].join(),
  _ => '',
};

/// Gate хоста с одинаковым ответом на всех прогонах: запрос разрешается один
/// раз, а его инструмент запоминается для сравнения.
final class _RecordingGate implements PermissionGate {
  _RecordingGate(this.asked);

  final List<String> asked;

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) async {
    asked.add(req.tool);
    return PermissionDecision.allowOnce;
  }
}
