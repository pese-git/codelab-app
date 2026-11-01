import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Разбор сценария модели и его слой провайдеров (embedded-agent «Сценарий
/// модели для тестов», сценарий «Сценарий бинаря и встроенного агента
/// разбирается одинаково»; design.md change `add-embedded-agent-mode`, D8).
///
/// Случаи перенесены из `apps/codelab_agent/test` (`llm_scripts_load_test`,
/// `agent_host_test`): код разбора общий у бинаря `--llm-script` и
/// встроенного агента, поэтому и проверяется на уровне `codelab_agent_io`.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('llm_script_'));
  tearDown(() => temp.deleteSync(recursive: true));

  const hello = <String, Object?>{
    'model': {
      'provider': 'scripted',
      'modelId': 'scripted-1',
      'contextWindow': 32768,
    },
    'steps': [
      {
        'reply': [
          {'text': 'hello'},
        ],
        'stopReason': 'stop',
      },
    ],
  };

  String write(Object? llm, {String name = 'script.json'}) {
    final file = File('${temp.path}/$name')
      ..writeAsStringSync(jsonEncode({'llm': llm}));
    return file.path;
  }

  LlmScript load(String path, {List<ModelId> models = const []}) =>
      LlmScript.load(
        path,
        models: models,
        clock: FakeClock(),
        cwdOf: (_) => null,
      );

  group('LlmScript.load', () {
    test('reads the models of the scenario file', () {
      final script = load(write(hello));

      expect(script.models, hasLength(1));
      expect(script.models.single.provider, 'scripted');
      expect(script.models.single.id, 'scripted-1');
      expect(script.models.single.contextWindow, 32768);
      expect(script.models.single.baseUrl.host, 'scripted.invalid');
    });

    test('models from --model replace the model of the file', () {
      final script = load(
        write(hello),
        models: [ModelId('scripted/other'), ModelId('acme/big')],
      );

      expect(
        [for (final m in script.models) '${m.provider}/${m.id}'],
        ['scripted/other', 'acme/big'],
      );
    });

    test('modelsOf gives the models without building the function', () {
      final path = write(hello);

      expect(
        [for (final m in LlmScript.modelsOf(path, models: const [])) m.id],
        [for (final m in load(path).models) m.id],
      );
    });

    test('the same block as a file and as a map gives the same models', () {
      final fromFile = load(write(hello));
      final fromMap = LlmScript.fromJson(
        hello,
        models: const [],
        clock: FakeClock(),
        cwdOf: (_) => null,
      );

      expect(
        [for (final m in fromMap.models) '${m.provider}/${m.id}'],
        [for (final m in fromFile.models) '${m.provider}/${m.id}'],
      );
    });

    test('the function answers with the scripted reply', () async {
      final script = load(write(hello));

      final stream = script.function.call(
        script.models.single,
        LlmContext(systemPrompt: '', messages: const []),
      );
      final events = await stream.toList();

      expect(events, isNotEmpty);
    });
  });

  group('LlmScriptException', () {
    LlmScriptException failure(void Function() body) {
      try {
        body();
      } on LlmScriptException catch (error) {
        return error;
      }
      fail('LlmScriptException expected');
    }

    test('an invalid step names the field path and the file', () {
      final path = write({'steps': 'not a list'});

      final error = failure(() => load(path));

      expect(error.message, contains('llm.steps'));
      expect(error.message, contains(path));
      expect(error.message, startsWith('--llm-script $path: '));
    });

    test('a broken reply of a step is an error, not a crash', () {
      final path = write({
        'steps': [
          {
            'reply': [
              {'txt': 'x'},
            ],
          },
        ],
      });

      expect(() => load(path), throwsA(isA<LlmScriptException>()));
    });

    test('a missing file is an error with the path', () {
      final path = '${temp.path}/missing.json';

      expect(failure(() => load(path)).message, contains(path));
      expect(
        () => LlmScript.modelsOf(path, models: const []),
        throwsA(isA<LlmScriptException>()),
      );
    });

    test('invalid JSON is an error', () {
      final file = File('${temp.path}/bad.json')..writeAsStringSync('{');

      expect(failure(() => load(file.path)).message, contains('invalid JSON'));
    });

    test('a file without the llm block is an error', () {
      final file = File('${temp.path}/no_llm.json')
        ..writeAsStringSync('{"steps": []}');

      expect(
        failure(() => load(file.path)).message,
        contains('{"llm": {"model"'),
      );
    });

    test('a map and a file give the same text apart from the source', () {
      const broken = <String, Object?>{'steps': 'not a list'};
      final path = write(broken);

      final fromFile = failure(() => load(path)).message;
      final fromMap = failure(
        () => LlmScript.fromJson(
          broken,
          models: const [],
          clock: FakeClock(),
          cwdOf: (_) => null,
        ),
      ).message;

      expect(fromFile.replaceFirst('--llm-script $path', 'llm'), fromMap);
    });
  });

  group('withScriptedProviders', () {
    final models = [
      for (final id in ['scripted/a', 'scripted/b', 'acme/c'])
        ModelRef(
          provider: ModelId(id).provider,
          id: ModelId(id).model,
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://scripted.invalid/v1'),
          contextWindow: 1000,
          maxOutputTokens: 200,
        ),
    ];

    test('describes every model as a provider model and selects the first', () {
      const flags = ConfigTree(
        kind: ConfigLayerKind.flags,
        source: 'flags',
        values: {
          'logging': {'level': 'debug'},
        },
      );

      final layer = withScriptedProviders(flags, models);

      expect(layer.kind, ConfigLayerKind.flags);
      expect(layer.source, 'flags');
      expect(layer.values['logging'], {'level': 'debug'});
      expect(layer.values['agent'], {'default_model': 'scripted/a'});
      final providers = layer.values['providers']! as Map<String, Object?>;
      expect(providers.keys, ['scripted', 'acme']);
      expect(providers['scripted'], {
        'kind': 'openai-compatible',
        'base_url': 'http://scripted.invalid/v1',
        'models': {
          'a': {'context_window': 1000, 'max_output_tokens': 200},
          'b': {'context_window': 1000, 'max_output_tokens': 200},
        },
      });
    });
  });

  group('CwdTrackingStore', () {
    SessionHeader header(String id, String cwd) => SessionHeader(
      id: SessionId(id),
      cwd: cwd,
      created: DateTime.utc(2026),
      agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
    );

    test('remembers the cwd on create and on open', () async {
      final inner = MemorySessionStore();
      final store = CwdTrackingStore(inner);

      await store.create(header('s1', '/work/a'));
      expect(store.cwdOf('s1'), '/work/a');

      // Сессию, загруженную после перезапуска, никто не создаёт заново.
      await inner.create(header('s2', '/work/b'));
      expect(store.cwdOf('s2'), isNull);
      await store.open(SessionId('s2'));
      expect(store.cwdOf('s2'), '/work/b');
    });
  });
}
