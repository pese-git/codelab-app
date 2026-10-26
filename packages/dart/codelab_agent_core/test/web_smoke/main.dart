// Точка входа web-smoke: `melos run web-compile` компилирует её в JS и Wasm
// и так доказывает, что ядро остаётся web-безопасным (без dart:io,
// dart:isolate, dart:ffi и Flutter). На Dart VM тот же код проводит ход
// через публичный API (`web_smoke_turn_test.dart`).
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';

/// Итог web-smoke хода.
///
/// Почему отдельный тип: тест на VM проверяет те же факты, которые `main`
/// печатает в браузере, не разбирая текст.
final class WebSmokeReport {
  const WebSmokeReport({
    required this.toolCalls,
    required this.toolOutput,
    required this.answer,
    required this.reason,
  });

  final List<String> toolCalls;
  final String toolOutput;
  final String answer;
  final String reason;
}

/// Ход через `buildAgentCore` на `MemoryExecutionEnv`: scripted модель
/// вызывает `read`, затем отвечает текстом. Профиль сужен до того, что есть
/// в браузере: без shell и без интерфейса одобрения, режим `bypass`.
Future<WebSmokeReport> runWebSmoke() async {
  final clock = FakeClock();
  final env = MemoryExecutionEnv(cwd: '/web', clock: clock);
  await env.writeText('/web/hello.txt', 'hello from memory\n');
  final model = ScriptedStreamFunction.fromJson({
    'steps': [
      {
        'reply': [
          {
            'toolCall': {
              'id': 'c1',
              'name': 'read',
              'arguments': {'path': 'hello.txt'},
            },
          },
        ],
      },
      {
        'expect': {
          'toolResult': {'toolCallId': 'c1', 'isError': false},
        },
        'reply': [
          {'text': 'web smoke: read hello from memory'},
        ],
      },
    ],
  }, clock: clock);
  final core = buildAgentCore(
    profile: HostProfile.of('agent-serve').narrowed(const {
      HostCapability.shellExec: CapabilityOff('браузер без shell'),
      HostCapability.sessionPersistence: CapabilityOff('журнал в памяти'),
    }),
    services: AgentCoreServices(
      baseEnv: env,
      logger: RecordingLogger(),
      clock: clock,
      ids: SequentialIdGenerator(),
      sessions: MemorySessionStore(),
      platform: 'web',
    ),
    config: CoreConfig(
      defaultModel: ModelRef(
        provider: 'scripted',
        id: 'scripted-1',
        api: ProviderApi.openaiChat,
        baseUrl: Uri.parse('http://localhost/'),
        contextWindow: 32768,
        maxOutputTokens: 4096,
      ),
    ),
    streamFunction: model.call,
  );
  final session = await core.runtime.createSession(
    SessionSpec(cwd: '/web', mode: ModeId.bypass),
  );
  final calls = <String>[];
  var output = '';
  var answer = '';
  final subscription = session.events.listen((event) {
    switch (event) {
      case ToolCallStarted(:final tool):
        calls.add(tool);
      case ToolCallFinished(:final content):
        output = content.whereType<TextContent>().map((b) => b.text).join();
      case MessageEnded(message: AssistantMessage(:final content)):
        answer = content.whereType<TextContent>().map((b) => b.text).join();
      default:
        break;
    }
  });
  final result = await session.prompt(const [TextContent('read hello.txt')]);
  await subscription.cancel();
  await core.runtime.dispose();
  model.verify();
  return WebSmokeReport(
    toolCalls: calls,
    toolOutput: output,
    answer: answer,
    reason: result.reason.name,
  );
}

Future<void> main() async {
  final report = await runWebSmoke();
  // ignore: avoid_print — web-smoke печатает итог в консоль браузера
  print('${report.answer} (${report.reason})');
}
