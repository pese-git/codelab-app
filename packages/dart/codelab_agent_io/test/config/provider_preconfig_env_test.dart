import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Предконфигурация провайдера из окружения (agent-configuration
/// «Предконфигурация провайдера из окружения», все сценарии; `agent-core-
/// architecture` §17.5.3; design.md change `add-config-writer-and-reload`,
/// D3, D5; критерий `core/provider-preconfig-from-env`, L-25).
///
/// Файлы — во временных `CODELAB_HOME` и `cwd`, окружение передаётся
/// загрузчику явно, настоящий `~/.codelab` не читается. Значения в тестах
/// выдуманные (`not-a-real-key-…`): проверяется, что ни проблема, ни запись
/// лога их не цитируют (CFG-12).
void main() {
  late Directory root;
  late String home;
  late String cwd;

  const typeVar = 'CODELAB_PROVIDER_TYPE';
  const configVar = 'CODELAB_PROVIDER_CONFIG';
  const base64Var = 'CODELAB_PROVIDER_CONFIG_BASE64';

  // Образец из сценария «Провайдер без файла конфига».
  const gateway =
      '{"id":"gw","base_url":"https://llm.internal/v1","model":"qwen3-coder",'
      '"context_window":131072,"api_key_env":"GW_KEY"}';

  setUp(() {
    final created = Directory.systemTemp.createTempSync('provider_preconfig_');
    root = Directory(created.resolveSymbolicLinksSync());
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  ConfigLoadResult load(Map<String, String> environment) => ConfigLoader().load(
    cwd: cwd,
    environment: {'CODELAB_HOME': home, ...environment},
  );

  void writeHome(String text) =>
      File('$home/config.yaml').writeAsStringSync(text);

  /// Всё, что видит потребитель каталога, одним значением: два конфига
  /// «совпадают», если совпадает эта проекция.
  Map<String, Object?> summary(CoreConfig config) => {
    'default': '${config.defaultModel.provider}/${config.defaultModel.id}',
    'providers': {
      for (final p in config.providers)
        p.config.name: {
          'url': '${p.config.baseUrl}',
          'name': p.models.values.map((m) => m.displayName).toList(),
          'models': {
            for (final m in p.models.entries) m.key: m.value.contextWindow,
          },
        },
    },
  };

  /// Проблема не цитирует [secret] ни в `toString`, ни в записях лога, куда
  /// хост переписывает предупреждения (`logConfigWarnings`).
  void expectNoLeak(ConfigLoadResult result, String secret) {
    final logger = RecordingLogger();
    logConfigWarnings(logger, result);
    for (final issue in [...result.issues, ...result.warnings]) {
      expect('$issue ${issue.fields}', isNot(contains(secret)));
    }
    for (final record in logger.records) {
      expect('${record.event} ${record.fields}', isNot(contains(secret)));
    }
  }

  group('a provider without any file', () {
    test(
      'TYPE and CONFIG give the catalog, the default model and the source',
      () {
        final result = load({typeVar: 'openai-compatible', configVar: gateway});

        expect(result.issues, isEmpty);
        final config = result.config!;
        expect(summary(config), {
          'default': 'gw/qwen3-coder',
          'providers': {
            'gw': {
              'url': 'https://llm.internal/v1',
              'name': [null],
              'models': {'qwen3-coder': 131072},
            },
          },
        });
        expect(result.sources, contains('env:CODELAB_PROVIDER_CONFIG'));
      },
    );

    test('the id defaults to env', () {
      final result = load({
        typeVar: 'openai-compatible',
        configVar:
            '{"base_url":"https://llm.internal/v1","model":"m",'
            '"context_window":8000}',
      });

      expect(result.issues, isEmpty);
      expect(result.config!.defaultModel.provider, 'env');
    });

    test('anthropic needs no base_url', () {
      final result = load({
        typeVar: 'anthropic',
        configVar: '{"model":"claude-x","context_window":200000}',
      });

      expect(result.issues, isEmpty);
      expect(result.config!.providers.single.config.name, 'env');
    });

    test('optional fields reach the model and the provider', () {
      final result = load({
        typeVar: 'openai-compatible',
        configVar:
            '{"id":"gw","base_url":"https://llm.internal/v1","model":"m",'
            '"context_window":1000,"max_output_tokens":500,"name":"Gateway M",'
            '"image":true,"reasoning":true,"api_key_secret":"codelab/gw",'
            '"auth_header":"X-Auth","connect_timeout":"5s","idle_timeout":"2m",'
            '"headers":{"X-Team":"core"}}',
      });

      expect(result.issues, isEmpty);
      final provider = result.config!.providers.single;
      final model = provider.models['m']!;
      expect(model.maxOutputTokens, 500);
      expect(model.displayName, 'Gateway M');
      expect(model.supportsImages, isTrue);
      expect(model.supportsReasoning, isTrue);
      expect(provider.config.authHeader, 'X-Auth');
      expect(provider.config.headers['X-Team'], 'core');
    });

    test('an empty variable is the same as an absent one', () {
      final result = load({typeVar: '', configVar: '', base64Var: ''});

      expect(result.issues.map((i) => i.key), ['agent.default_model']);
      expect(result.sources, isNot(contains('env:CODELAB_PROVIDER_CONFIG')));
    });
  });

  group('CONFIG_BASE64', () {
    test('the standard alphabet without "=" gives the same CoreConfig', () {
      final plain = load({typeVar: 'openai-compatible', configVar: gateway});
      final encoded = base64.encode(utf8.encode(gateway)).replaceAll('=', '');

      final result = load({typeVar: 'openai-compatible', base64Var: encoded});

      expect(result.issues, isEmpty);
      expect(summary(result.config!), summary(plain.config!));
      expect(result.sources, contains('env:CODELAB_PROVIDER_CONFIG_BASE64'));
    });

    test('the URL-safe alphabet gives the same CoreConfig', () {
      // `???` кодируется в `Pz8/`: стандартный и URL-safe алфавиты различаются.
      final json = gateway.replaceFirst('"gw"', '"gw","name":"???>>>"');
      final standard = base64.encode(utf8.encode(json));
      final urlSafe = base64Url.encode(utf8.encode(json));
      expect(standard, isNot(urlSafe), reason: 'the sample must differ');

      final a = load({typeVar: 'openai-compatible', base64Var: standard});
      final b = load({typeVar: 'openai-compatible', base64Var: urlSafe});
      final c = load({
        typeVar: 'openai-compatible',
        base64Var: urlSafe.replaceAll('=', ''),
      });

      expect(a.issues, isEmpty);
      expect(summary(b.config!), summary(a.config!));
      expect(summary(c.config!), summary(a.config!));
    });
  });

  group('priority', () {
    const openai = '''
providers:
  openai:
    kind: openai-compatible
    base_url: https://api.openai.test/v1
    models:
      gpt-4o: {}
agent:
  default_model: openai/gpt-4o
''';
    const gwM1 =
        '{"id":"gw","base_url":"https://llm.internal/v1","model":"m1",'
        '"context_window":1000}';

    test('the environment beats the file; CODELAB_MODEL beats the '
        'preconfiguration', () {
      writeHome(openai);
      final base = {typeVar: 'openai-compatible', configVar: gwM1};

      final withoutModel = load(base);
      final withModel = load({...base, 'CODELAB_MODEL': 'openai/gpt-4o'});

      expect(withoutModel.issues, isEmpty);
      expect(withoutModel.config!.defaultModel.provider, 'gw');
      expect(withoutModel.config!.defaultModel.id, 'm1');
      expect(withModel.config!.defaultModel.provider, 'openai');
      for (final result in [withoutModel, withModel]) {
        expect(
          result.config!.providers.map((p) => p.config.name),
          containsAll(['openai', 'gw']),
        );
      }
    });

    test('the table of the same provider is merged with the file; the '
        'fields of the environment win', () {
      writeHome('''
providers:
  gw:
    kind: openai-compatible
    base_url: https://from-file.test/v1
    models:
      from-file: {}
''');

      final result = load({typeVar: 'openai-compatible', configVar: gwM1});

      expect(result.issues, isEmpty);
      final provider = result.config!.providers.single;
      expect('${provider.config.baseUrl}', 'https://llm.internal/v1');
      expect(provider.models.keys, containsAll(['from-file', 'm1']));
    });
  });

  group('problems', () {
    ConfigIssue single(Map<String, String> environment) {
      final result = load(environment);
      expect(result.config, isNull);
      return result.issues.single;
    }

    test('both CONFIG and CONFIG_BASE64 are a problem naming both', () {
      final issue = single({
        typeVar: 'openai-compatible',
        configVar: gateway,
        base64Var: base64.encode(utf8.encode(gateway)),
      });

      expect(issue.line, isNull);
      expect(issue.source, startsWith('env:CODELAB_PROVIDER_CONFIG'));
      expect(issue.message, contains(configVar));
      expect(issue.message, contains(base64Var));
    });

    test('TYPE without CONFIG and CONFIG without TYPE name both variables', () {
      for (final environment in [
        {typeVar: 'openai-compatible'},
        {configVar: gateway},
        {base64Var: base64.encode(utf8.encode(gateway))},
      ]) {
        final issue = single(environment);
        expect(issue.message, contains(typeVar), reason: '$environment');
        expect(issue.message, contains('CODELAB_PROVIDER_CONFIG'));
      }
    });

    test('an unknown type lists the allowed ones, without the value', () {
      final result = load({typeVar: 'not-a-real-kind-1', configVar: gateway});

      final issue = result.issues.single;
      expect(issue.message, contains(typeVar));
      expect(
        issue.message,
        contains('expected one of: openai-compatible, anthropic'),
      );
      expectNoLeak(result, 'not-a-real-kind-1');
    });

    test('not base64', () {
      final result = load({
        typeVar: 'openai-compatible',
        base64Var: '!!not-a-real-key-b64!!',
      });

      final issue = result.issues.single;
      expect(issue.message, 'CODELAB_PROVIDER_CONFIG_BASE64: not base64');
      expectNoLeak(result, 'not-a-real-key-b64');
    });

    test('broken JSON: the offset, no quotation of the value (spec «Битый '
        'JSON не цитируется»)', () {
      final result = load({
        typeVar: 'openai-compatible',
        configVar: '{"id":"gw","headers":{"Authorization":"Bearer sk-live-123"',
      });

      final issue = result.issues.single;
      expect(issue.source, 'env:CODELAB_PROVIDER_CONFIG');
      expect(issue.line, isNull);
      expect(
        issue.message,
        matches(r'^CODELAB_PROVIDER_CONFIG: invalid JSON at offset \d+$'),
      );
      expectNoLeak(result, 'sk-live-123');
    });

    test('a JSON root that is not an object', () {
      final issue = single({typeVar: 'anthropic', configVar: '["a"]'});

      expect(issue.message, 'CODELAB_PROVIDER_CONFIG: expected a JSON object');
    });

    test('an unknown field is named with its nearest neighbour (spec '
        '«Опечатка в поле»)', () {
      final result = load({
        typeVar: 'openai-compatible',
        configVar:
            '{"id":"gw","base_url":"https://llm.internal/v1","model":"m",'
            '"contex_window":1000}',
      });

      final messages = result.issues.map((i) => i.message).toList();
      expect(
        messages,
        contains(
          'CODELAB_PROVIDER_CONFIG.contex_window: unknown key '
          '(did you mean context_window?)',
        ),
      );
    });

    test('a wrong type names the expected one, not the value', () {
      final result = load({
        typeVar: 'openai-compatible',
        configVar:
            '{"base_url":"https://llm.internal/v1","model":"m",'
            '"context_window":"not-a-real-value-9"}',
      });

      final issue = result.issues.single;
      expect(issue.message, contains('CODELAB_PROVIDER_CONFIG.context_window'));
      expect(issue.message, contains('integer'));
      expectNoLeak(result, 'not-a-real-value-9');
    });

    test('required fields: model, context_window and, for '
        'openai-compatible, base_url', () {
      final result = load({typeVar: 'openai-compatible', configVar: '{}'});

      final text = result.issues.map((i) => i.message).join('\n');
      expect(text, contains('CODELAB_PROVIDER_CONFIG.model'));
      expect(text, contains('CODELAB_PROVIDER_CONFIG.context_window'));
      expect(text, contains('CODELAB_PROVIDER_CONFIG.base_url'));
    });

    test('api_key_env together with api_key_secret is a problem', () {
      final result = load({
        typeVar: 'anthropic',
        configVar:
            '{"model":"m","context_window":1000,"api_key_env":"A_KEY",'
            '"api_key_secret":"codelab/env"}',
      });

      final text = result.issues.map((i) => i.message).join('\n');
      expect(text, contains('api_key_env'));
      expect(text, contains('api_key_secret'));
    });

    test('an id outside [a-z0-9_-]+ is a problem', () {
      final result = load({
        typeVar: 'anthropic',
        configVar: '{"id":"Not Valid","model":"m","context_window":1000}',
      });

      expect(result.issues.single.message, contains('id'));
      expectNoLeak(result, 'Not Valid');
    });
  });

  group('a secret as a value (CFG-9, CFG-12)', () {
    for (final field in [
      'api_key',
      'apiKey',
      'key',
      'token',
      'secret',
      'password',
    ]) {
      test('the field $field is inlineSecret with the suggested name '
          'codelab/gw', () {
        final result = load({
          typeVar: 'anthropic',
          configVar:
              '{"id":"gw","model":"m","context_window":1000,'
              '"$field":"not-a-real-key-777"}',
        });

        expect(result.config, isNull);
        final issue = result.issues.single;
        expect(issue.kind, ConfigIssueKind.inlineSecret);
        expect(issue.message, contains('codelab secret set codelab/gw'));
        expect(issue.message, contains('CODELAB_PROVIDER_CONFIG.$field'));
        expect(
          () => result.orThrow(),
          throwsA(
            isA<ConfigInlineSecretException>().having(
              (e) => e.suggestedSecretName,
              'suggestedSecretName',
              'codelab/gw',
            ),
          ),
        );
        expectNoLeak(result, 'not-a-real-key-777');
      });
    }

    test('a secret-like unknown top-level field is inlineSecret, not a '
        '"did you mean" hint (D5 rule)', () {
      for (final field in [
        'API_KEY',
        'api-key',
        'access_token',
        'Authorization',
      ]) {
        final result = load({
          typeVar: 'anthropic',
          configVar:
              '{"id":"gw","model":"m","context_window":1000,'
              '"$field":"not-a-real-key-top"}',
        });

        final issue = result.issues.single;
        expect(issue.kind, ConfigIssueKind.inlineSecret, reason: field);
        expect(issue.message, isNot(contains('did you mean')));
        expectNoLeak(result, 'not-a-real-key-top');
      }
    });

    test('the hint name equals suggestedSecretName of the exception', () {
      final result = load({
        typeVar: 'anthropic',
        configVar:
            '{"id":"my-gw","model":"m","context_window":1000,'
            '"api_key":"not-a-real-key-n"}',
      });
      final issue = result.issues.single;
      final name = SecretNames.suggestFor(issue.key);

      expect(issue.message, contains('codelab secret set $name,'));
      expect(
        () => result.orThrow(),
        throwsA(
          isA<ConfigInlineSecretException>().having(
            (e) => e.suggestedSecretName,
            'name',
            name,
          ),
        ),
      );
    });

    test('a literal token in a secret header is inlineSecret for '
        'headers.Authorization (spec «Литеральный токен в заголовке»)', () {
      final result = load({
        typeVar: 'openai-compatible',
        configVar:
            '{"id":"gw","base_url":"https://llm.internal/v1","model":"m",'
            '"context_window":1000,'
            '"headers":{"Authorization":"Bearer sk-live-1"}}',
      });

      expect(result.config, isNull);
      final issue = result.issues.single;
      expect(issue.kind, ConfigIssueKind.inlineSecret);
      expect(issue.key, contains('headers.Authorization'));
      expect(issue.source, 'env:CODELAB_PROVIDER_CONFIG');
      expectNoLeak(result, 'sk-live-1');
    });

    test('the name is normalized: case, "-" and "_" do not hide a secret', () {
      for (final name in [
        'x_api_key',
        'X-API-KEY',
        'Proxy-Authorization',
        'Cookie',
        'X-Private-Token',
        'client_SECRET',
      ]) {
        final result = load({
          typeVar: 'anthropic',
          configVar:
              '{"id":"gw","model":"m","context_window":1000,'
              '"headers":{"$name":"not-a-real-key-hdr"}}',
        });

        expect(
          result.issues.single.kind,
          ConfigIssueKind.inlineSecret,
          reason: name,
        );
        expectNoLeak(result, 'not-a-real-key-hdr');
      }
    });

    test('a reference passes: \${secret:…}, \${VAR}; a plain header too', () {
      final result = load({
        typeVar: 'anthropic',
        configVar:
            '{"id":"gw","model":"m","context_window":1000,"headers":{'
            '"Authorization":"Bearer \${secret:codelab/gw}",'
            '"X-Api-Key":"\${GW_TOKEN}","X-Team":"core"}}',
        'GW_TOKEN': 'not-a-real-key-env',
      });

      expect(result.issues, isEmpty);
      final provider = result.config!.providers.single;
      expect(provider.config.headers['X-Team'], 'core');
      expect(provider.headerTemplates, contains('Authorization'));
    });

    // Характеризационный тест (design.md change `add-config-writer-and-reload`,
    // D5, R1-1): значение с литералом и ссылкой одновременно проходит правило
    // — известная граница до 8.11 (пункты 2–3 CFG-9 по шаблонам §12.4). Тест
    // закрепляет текущее поведение; при появлении проверки 8.11 его меняют
    // осознанно.
    test('R1-1: a mixed value "Bearer <literal> \${X}" passes the rule until '
        '8.11', () {
      final result = load({
        typeVar: 'anthropic',
        configVar:
            '{"id":"gw","model":"m","context_window":1000,'
            '"headers":{"Authorization":"Bearer not-a-real-key-x \${X}"}}',
        'X': 'not-a-real-key-env',
      });

      expect(result.issues, isEmpty);
    });

    test('the same rule works in the BASE64 variant', () {
      final json =
          '{"id":"gw","model":"m","context_window":1000,'
          '"headers":{"Authorization":"Bearer sk-live-b64"}}';

      final result = load({
        typeVar: 'anthropic',
        base64Var: base64.encode(utf8.encode(json)),
      });

      final issue = result.issues.single;
      expect(issue.kind, ConfigIssueKind.inlineSecret);
      expect(issue.source, 'env:CODELAB_PROVIDER_CONFIG_BASE64');
      expectNoLeak(result, 'sk-live-b64');
    });
  });
}
