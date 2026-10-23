// Web-smoke entry point: compiled with `dart compile js` and
// `dart compile wasm` by `melos run web-compile` to prove the core stays
// web-safe (no dart:io, dart:isolate, dart:ffi, Flutter), and run on the
// Dart VM to prove one model step works through the public API.
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';

Future<void> main() async {
  final model = ScriptedStreamFunction.fromJson({
    'steps': [
      {
        'reply': [
          {
            'text':
                'web smoke: one scripted step of $codelabAgentCorePackageName',
          },
        ],
        'stopReason': 'stop',
      },
    ],
  });
  final StreamFunction stream = model.call;

  final answer = await stream(
    ModelRef(
      provider: 'scripted',
      id: 'scripted-1',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://localhost/'),
      contextWindow: 32768,
      maxOutputTokens: 4096,
    ),
    LlmContext(
      systemPrompt: '',
      messages: [
        UserMessage(const [TextContent('ping')], timestamp: DateTime.utc(2026)),
      ],
    ),
  ).result;
  model.verify();

  // ignore: avoid_print
  print((answer.content.single as TextContent).text);
}
