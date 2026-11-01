import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Разбор флагов и переменных `codelab-agent serve` (задача 4.6; agent-binary
/// «Минимальный конфиг из флагов», «Сценарий --llm-script»; design.md change
/// `add-codelab-agent-binary`, D1, D4; `--sessions-dir` — D1 change
/// `add-llm-script-session-store`).
void main() {
  const scripted = ['serve', '--stdio', '--llm-script', 'hello.json'];
  const provider = [
    'serve',
    '--stdio',
    '--provider',
    'openai-compatible',
    '--base-url',
    'http://localhost:4000/v1',
    '--model',
    'gpt-5',
  ];

  ServeOptions parse(List<String> args, [Map<String, String> env = const {}]) =>
      parseServeArgs(args, environment: env);

  Matcher usageError(Object message) =>
      throwsA(isA<UsageError>().having((e) => e.message, 'message', message));

  test('the general usage names `config check`', () {
    expect(serveUsage(), contains('codelab-agent config check [--cwd <dir>]'));
  });

  group('--debug-secrets (change add-agent-secret-store, D11)', () {
    test('the flag turns the mode on, the default is off', () {
      expect(parse(scripted).debugSecrets, isFalse);
      expect(parse([...scripted, '--debug-secrets']).debugSecrets, isTrue);
    });

    test('CODELAB_DEBUG_SECRETS=1 turns it on; other values do not', () {
      expect(
        parse(scripted, {'CODELAB_DEBUG_SECRETS': '1'}).debugSecrets,
        isTrue,
      );
      for (final other in ['0', 'true', '', 'yes']) {
        expect(
          parse(scripted, {'CODELAB_DEBUG_SECRETS': other}).debugSecrets,
          isFalse,
          reason: other,
        );
      }
    });

    test('the flag takes no value', () {
      expect(
        () => parse([...scripted, '--debug-secrets=1']),
        throwsA(isA<UsageError>()),
      );
    });

    test(
      'the general usage names --debug-secrets and secret set|delete|list',
      () {
        expect(serveUsage(), contains('--debug-secrets'));
        expect(serveUsage(), contains('codelab-agent secret set|delete|list'));
      },
    );
  });

  group('transport', () {
    test('--stdio and --ws with defaults', () {
      expect(parse(scripted).transport, ServeTransport.stdio);
      final ws = parse(['serve', '--ws', '--llm-script', 'hello.json']);
      expect(ws.transport, ServeTransport.ws);
      expect(ws.host, '127.0.0.1');
      expect(ws.port, 8765);
      expect(ws.tokenEnv, 'CODELAB_AGENT_TOKEN');
    });

    test('--host, --port and --token-env', () {
      final ws = parse([
        'serve',
        '--ws',
        '--host',
        '0.0.0.0',
        '--port',
        '0',
        '--token-env',
        'MY_TOKEN',
        '--llm-script',
        'hello.json',
      ]);
      expect((ws.host, ws.port, ws.tokenEnv), ('0.0.0.0', 0, 'MY_TOKEN'));
    });

    test('both transports or none is a usage error', () {
      expect(
        () => parse(['serve', '--stdio', '--ws', '--llm-script', 'x.json']),
        usageError(contains('--stdio')),
      );
      expect(
        () => parse(['serve', '--llm-script', 'x.json']),
        usageError(contains('--stdio')),
      );
    });

    test('a missing command and an unknown flag are usage errors', () {
      expect(() => parse(const []), usageError(contains('serve')));
      expect(
        () => parse([...scripted, '--verbose']),
        usageError(contains('--verbose')),
      );
      expect(
        () => parse(['serve', '--stdio', '--port', 'abc', '--llm-script', 'x']),
        throwsA(isA<UsageError>()),
      );
    });
  });

  group('models and providers', () {
    test('--model repeats: the first is the default', () {
      final options = parse([...provider, '--model', 'gpt-4']);
      expect(options.models, [
        const ModelId('cli/gpt-5'),
        const ModelId('cli/gpt-4'),
      ]);
    });

    test('cli/<id> with --provider and scripted/<id> with --llm-script', () {
      expect(parse([...provider.take(6), '--model', 'cli/gpt-5']).models, [
        const ModelId('cli/gpt-5'),
      ]);
      expect(
        parse([
          ...scripted,
          '--model',
          'scripted/gpt-5',
          '--model',
          'gpt-4',
        ]).models,
        [const ModelId('scripted/gpt-5'), const ModelId('scripted/gpt-4')],
      );
    });

    test('CODELAB_MODEL is --model when the flag is absent', () {
      expect(
        parse(provider.take(6).toList(), {'CODELAB_MODEL': 'gpt-5'}).models,
        [const ModelId('cli/gpt-5')],
      );
      expect(parse(provider, {'CODELAB_MODEL': 'other'}).models, [
        const ModelId('cli/gpt-5'),
      ]);
    });

    test('a foreign provider in --model with --provider is a usage error', () {
      expect(
        () => parse([...provider.take(6), '--model', 'openai/gpt-5']),
        usageError(contains('openai/gpt-5')),
      );
    });

    // agent-binary «Конфиг бинаря из файлов, окружения и флагов»: `--model
    // <provider>/<model>` без `--provider` выбирает модель конфига (задача
    // 9.2; design.md change `add-agent-configuration`, D4). Прежняя ошибка
    // «named providers come with the config of stage 8» ушла.
    test('--model <provider>/<model> without --provider selects a config '
        'model', () {
      final options = parse(['serve', '--stdio', '--model', 'anthropic/x']);

      expect(options.flags.values['providers'], isNull);
      expect(options.models, [const ModelId('anthropic/x')]);
      expect(options.flags.kind, ConfigLayerKind.flags);
      expect(options.flags.values, {
        'agent': {'default_model': 'anthropic/x'},
      });
    });

    test('--model without a slash and without --provider is a usage error', () {
      expect(
        () => parse(['serve', '--stdio', '--model', 'gpt']),
        usageError('--model needs <provider>/<model> without --provider'),
      );
    });

    test('--model repeated without --provider is a usage error', () {
      expect(
        () => parse(['serve', '--stdio', '--model', 'a/x', '--model', 'b/y']),
        usageError(contains('--provider')),
      );
    });

    test('without CODELAB_API_KEY the layer has no api_key_env', () {
      final options = parse([...provider, '--model', 'gpt-4']);

      final cli = (options.flags.values['providers']! as Map)['cli']! as Map;
      expect(cli, isNot(contains('api_key_env')));
      final empty = parse(
        [...provider, '--model', 'gpt-4'],
        {'CODELAB_API_KEY': ''},
      );
      expect(
        ((empty.flags.values['providers']! as Map)['cli']! as Map).keys,
        isNot(contains('api_key_env')),
      );
    });

    test('the provider flags become the layer of flags', () {
      final options = parse(
        [...provider, '--model', 'gpt-4'],
        {'CODELAB_API_KEY': 'sk-test-secret'},
      );

      expect(options.flags.source, 'flags');
      expect(options.flags.values, {
        'providers': {
          'cli': {
            'kind': 'openai-compatible',
            'base_url': 'http://localhost:4000/v1',
            'api_key_env': 'CODELAB_API_KEY',
            'models': {
              'gpt-5': <String, Object?>{},
              'gpt-4': <String, Object?>{},
            },
          },
        },
        'agent': {'default_model': 'cli/gpt-5'},
      });
    });

    test('the layer of flags never holds the key itself', () {
      final options = parse(provider, {'CODELAB_API_KEY': 'sk-test-secret'});

      expect('${options.flags.values}', isNot(contains('sk-test-secret')));
    });

    test('--provider together with --llm-script is a usage error', () {
      expect(
        () => parse([...scripted, '--provider', 'anthropic']),
        usageError(contains('--llm-script')),
      );
    });

    test('--sessions-dir: the journal root of the script', () {
      expect(parse(scripted).sessionsDir, isNull);
      expect(
        parse([...scripted, '--sessions-dir', '/tmp/s']).sessionsDir,
        '/tmp/s',
      );
    });

    test('--sessions-dir without --llm-script is a usage error', () {
      expect(
        () => parse([...provider, '--sessions-dir', '/tmp/s']),
        usageError('--sessions-dir requires --llm-script'),
      );
    });

    // Правка характеризационного теста в фазе реализации 9.3: запуск без
    // модели больше не ошибка разбора флагов, а проблема конфига
    // `agent.default_model: required` (agent-binary «Конфиг бинаря…»,
    // требование «Минимальный конфиг из флагов» удалено).
    test('--provider without a model is a usage error; no model source is '
        'left to the config', () {
      expect(
        () => parse(provider.take(6).toList()),
        usageError(contains('--model')),
      );
      expect(parse(['serve', '--stdio']).models, isEmpty);
    });

    // §15.4: `base_url` обязателен для openai-compatible, у anthropic есть
    // значение по умолчанию.
    test(
      '--base-url: required for openai-compatible, default for anthropic',
      () {
        expect(
          () => parse([
            'serve',
            '--stdio',
            '--provider',
            'openai-compatible',
            '--model',
            'gpt-5',
          ]),
          usageError(contains('--base-url')),
        );
        final anthropic = parse([
          'serve',
          '--stdio',
          '--provider',
          'anthropic',
          '--model',
          'claude-sonnet-5-5',
        ]);
        expect(
          ((anthropic.flags.values['providers']! as Map)['cli']!
              as Map)['base_url'],
          'https://api.anthropic.com',
        );
      },
    );

    test('the key comes only from CODELAB_API_KEY and is not shown', () {
      final options = parse(provider, {'CODELAB_API_KEY': 'sk-test-secret'});
      final cli = (options.flags.values['providers']! as Map)['cli']! as Map;
      expect(cli['api_key_env'], 'CODELAB_API_KEY');
      expect(options.toString(), isNot(contains('sk-test-secret')));
      expect(
        () => parse([...provider, '--api-key', 'sk-test-secret']),
        usageError(isNot(contains('sk-test-secret'))),
      );
    });
  });

  group('config file and limits', () {
    test('--config keeps the path; no flag means none', () {
      expect(parse(scripted).configPath, isNull);
      expect(
        parse([...scripted, '--config', '/tmp/c.yaml']).configPath,
        '/tmp/c.yaml',
      );
      expect(parse([...scripted, '--config', 'c.yml']).configPath, 'c.yml');
    });

    test('--config with .toml is a usage error', () {
      expect(
        () => parse([...scripted, '--config', 'a.toml']),
        usageError(allOf(contains('codelab.toml'), contains('--config'))),
      );
    });

    test('--config with another extension is a usage error', () {
      expect(
        () => parse([...scripted, '--config', 'a.json']),
        usageError(contains('.yaml')),
      );
    });

    test('--max-steps goes to budget.max_steps of the flags', () {
      final options = parse([...scripted, '--max-steps', '7']);

      expect(options.flags.values['budget'], {'max_steps': 7});
      expect(parse(scripted).flags.values['budget'], isNull);
    });

    test('--max-steps must be a positive integer', () {
      for (final bad in ['0', '-1', 'abc', '2.5']) {
        expect(
          () => parse([...scripted, '--max-steps', bad]),
          usageError(contains('--max-steps')),
          reason: bad,
        );
      }
    });

    test('flag values reach the layer; variables stay out of it', () {
      final options = parse(
        [
          ...scripted,
          '--permission-mode',
          'plan',
          '--log-level',
          'debug',
          '--log-file',
          '/tmp/f.log',
        ],
        {'CODELAB_LOG_LEVEL': 'error', 'CODELAB_MAX_STEPS': '3'},
      );

      expect(options.flags.values, {
        'permissions': {'mode': 'plan'},
        'logging': {'level': 'debug', 'file': '/tmp/f.log'},
      });
    });

    test('autopilot reaches the layer only as a flag', () {
      final options = parse([...scripted, '--permission-mode', 'autopilot']);

      expect(options.flags.values['permissions'], {'mode': 'autopilot'});
    });
  });

  group('mode and logging', () {
    // Приоритет «флаг сильнее переменной» обеспечивает порядок слоёв
    // загрузчика; здесь флаг попадает в слой, а переменная — нет.
    test(
      '--permission-mode goes to the flags layer, the variable does not',
      () {
        final byFlag = parse(
          [...scripted, '--permission-mode', 'accept-edits'],
          {'CODELAB_PERMISSION_MODE': 'bypass'},
        );

        expect(byFlag.flags.values['permissions'], {'mode': 'accept-edits'});
        expect(
          parse(scripted, {
            'CODELAB_PERMISSION_MODE': 'bypass',
          }).flags.values['permissions'],
          isNull,
        );
      },
    );

    test('autopilot is a flag-only override', () {
      final options = parse([...scripted, '--permission-mode', 'autopilot']);

      expect(options.flags.values['permissions'], {'mode': 'autopilot'});
      expect(
        () => parse(scripted, {'CODELAB_PERMISSION_MODE': 'autopilot'}),
        usageError(contains('autopilot')),
      );
    });

    test('an unknown mode is a usage error', () {
      expect(
        () => parse([...scripted, '--permission-mode', 'yolo']),
        usageError(contains('yolo')),
      );
    });

    test('--log-level and --log-file beat their variables', () {
      final byEnv = parse(scripted, {
        'CODELAB_LOG_LEVEL': 'debug',
        'CODELAB_LOG_FILE': '/tmp/env.log',
      });
      expect((byEnv.logLevel, byEnv.logFile), (LogLevel.debug, '/tmp/env.log'));
      final byFlag = parse(
        [...scripted, '--log-level', 'warning', '--log-file', '/tmp/flag.log'],
        {'CODELAB_LOG_LEVEL': 'debug', 'CODELAB_LOG_FILE': '/tmp/env.log'},
      );
      expect(
        (byFlag.logLevel, byFlag.logFile),
        (LogLevel.warning, '/tmp/flag.log'),
      );
      expect(parse(scripted).logLevel, LogLevel.info);
    });

    // Профиль codelab-app по умолчанию передаёт `CODELAB_LOG_LEVEL=DEBUG`
    // (Python-агент принимал верхний регистр), поэтому уровень разбирается
    // без учёта регистра.
    test('the log level is case-insensitive', () {
      expect(
        parse(scripted, {'CODELAB_LOG_LEVEL': 'DEBUG'}).logLevel,
        LogLevel.debug,
      );
      expect(
        parse([...scripted, '--log-level', 'INFO']).logLevel,
        LogLevel.info,
      );
      expect(
        () => parse([...scripted, '--log-level', 'LOUD']),
        usageError('unknown log level: LOUD'),
      );
    });

    test('CODELAB_HOME is taken from the environment', () {
      // Неизвестные `CODELAB_*` распознаёт `ConfigLoader` (D13): разбор
      // флагов их не проверяет, чтобы правило было одно для `serve` и
      // `config check`.
      final options = parse(provider, {
        'CODELAB_MODLE': 'x',
        'CODELAB_HOME': '/tmp/home',
      });
      expect(options.codelabHome, '/tmp/home');
    });

    test('CODELAB_HOME is neither expanded nor checked under --llm-script', () {
      // D17: под сценарием `$CODELAB_HOME` не читается, ошибки тильды нет.
      expect(parse(scripted, {'CODELAB_HOME': '~bob/cl'}).codelabHome, isEmpty);
    });

    test('CODELAB_HOME with ~user is a usage error', () {
      expect(
        () => parse(provider, {'CODELAB_HOME': '~bob/cl', 'HOME': '/h'}),
        usageError(
          'CODELAB_HOME: ~user is not supported, use an absolute path',
        ),
      );
    });

    test('CODELAB_HOME defaults to ~/.codelab', () {
      expect(
        parse(provider, {'HOME': '/home/u'}).codelabHome,
        '/home/u/.codelab',
      );
    });
  });

  test('the usage text hides --llm-script and --sessions-dir', () {
    expect(serveUsage(), contains('--stdio'));
    expect(serveUsage(), contains('--provider'));
    expect(serveUsage(), isNot(contains('llm-script')));
    expect(serveUsage(), isNot(contains('sessions-dir')));
  });
}
