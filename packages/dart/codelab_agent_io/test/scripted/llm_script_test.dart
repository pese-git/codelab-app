import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/testing.dart';
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

    // Цены модели сценария (задача 1.5b change `add-usage-extension`; D18 Т8):
    // `llm.model.cost` — доллары за 10^6 токенов, как `ModelCost`.
    Map<String, Object?> withCost(Map<String, Object?>? cost) => {
      ...hello,
      'model': {
        ...(hello['model']! as Map<String, Object?>),
        if (cost != null) 'cost': cost,
      },
    };

    test('llm.model.cost becomes ModelRef.cost', () {
      final script = load(
        write(withCost({'input': 3, 'output': 15.5, 'cacheRead': 0.3})),
      );

      expect(
        script.models.single.cost,
        const ModelCost(input: 3, output: 15.5, cacheRead: 0.3),
      );
    });

    test('cacheWrite is read too, absent cache prices are zero', () {
      final script = load(
        write(withCost({'input': 1, 'output': 2, 'cacheWrite': 1.25})),
      );

      expect(
        script.models.single.cost,
        const ModelCost(input: 1, output: 2, cacheWrite: 1.25),
      );
    });

    test('without llm.model.cost the prices are unknown', () {
      expect(load(write(hello)).models.single.cost, isNull);
      expect(load(write(withCost(null))).models.single.cost, isNull);
    });

    test('modelsOf gives the same prices', () {
      final path = write(withCost({'input': 3, 'output': 15}));

      expect(
        LlmScript.modelsOf(path, models: const []).single.cost,
        const ModelCost(input: 3, output: 15),
      );
    });

    test('models from --model keep the prices of the file', () {
      final script = load(
        write(withCost({'input': 3, 'output': 15})),
        models: [ModelId('scripted/other')],
      );

      expect(script.models.single.cost, const ModelCost(input: 3, output: 15));
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

    // Задача 1.5b (D18 Т8): цены модели сценария доходят до конфига ключами
    // `cost_input`/`cost_output`/`cost_cache_read`/`cost_cache_write`.
    ModelRef priced(String id, ModelCost? cost) => ModelRef(
      provider: ModelId(id).provider,
      id: ModelId(id).model,
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('http://scripted.invalid/v1'),
      contextWindow: 1000,
      maxOutputTokens: 200,
      cost: cost,
    );

    Map<String, Object?> modelEntry(ConfigTree layer, String p, String m) =>
        (((layer.values['providers']! as Map<String, Object?>)[p]!
                    as Map<String, Object?>)['models']!
                as Map<String, Object?>)[m]!
            as Map<String, Object?>;

    const flags = ConfigTree(
      kind: ConfigLayerKind.flags,
      source: 'flags',
      values: {},
    );

    test('writes the price keys of a priced model', () {
      final layer = withScriptedProviders(flags, [
        priced(
          'scripted/a',
          const ModelCost(
            input: 3,
            output: 15,
            cacheRead: 0.3,
            cacheWrite: 3.75,
          ),
        ),
      ]);

      expect(modelEntry(layer, 'scripted', 'a'), {
        'context_window': 1000,
        'max_output_tokens': 200,
        'cost_input': 3,
        'cost_output': 15,
        'cost_cache_read': 0.3,
        'cost_cache_write': 3.75,
      });
    });

    test('a model without prices gets no price keys', () {
      final layer = withScriptedProviders(flags, [priced('scripted/a', null)]);

      expect(modelEntry(layer, 'scripted', 'a'), {
        'context_window': 1000,
        'max_output_tokens': 200,
      });
    });

    test('the loaded config gives the same ModelCost', () {
      const cost = ModelCost(
        input: 3,
        output: 15,
        cacheRead: 0.3,
        cacheWrite: 3.75,
      );
      final layer = withScriptedProviders(flags, [
        priced('scripted/a', cost),
        priced('scripted/free', null),
      ]);

      final result = CoreConfig.fromLayers([layer], environment: const {});

      expect(result.issues, isEmpty);
      final models = result.config!.providers
          .singleWhere((p) => p.config.name == 'scripted')
          .models;
      expect(models['a']!.cost, cost);
      expect(models['free']!.cost, isNull);
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
