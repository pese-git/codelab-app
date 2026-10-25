import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Разбор флагов и переменных `codelab-agent serve` (задача 4.6; agent-binary
/// «Минимальный конфиг из флагов», «Сценарий --llm-script»; design.md change
/// `add-codelab-agent-binary`, D1, D4).
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
      expect(options.provider, ProviderKind.openaiCompatible);
      expect(options.baseUrl, Uri.parse('http://localhost:4000/v1'));
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

    test('a foreign provider in --model is a usage error', () {
      expect(
        () => parse([...provider.take(6), '--model', 'openai/gpt-5']),
        usageError(contains('openai/gpt-5')),
      );
      expect(
        () => parse(['serve', '--stdio', '--model', 'openai/gpt-5']),
        usageError(contains('--provider')),
      );
    });

    test('--provider together with --llm-script is a usage error', () {
      expect(
        () => parse([...scripted, '--provider', 'anthropic']),
        usageError(contains('--llm-script')),
      );
    });

    test('neither a model nor a script is a usage error', () {
      expect(
        () => parse(provider.take(6).toList()),
        usageError(contains('--model')),
      );
      expect(
        () => parse(['serve', '--stdio']),
        usageError(contains('--provider')),
      );
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
        expect(anthropic.baseUrl, Uri.parse('https://api.anthropic.com'));
      },
    );

    test('the key comes only from CODELAB_API_KEY and is not shown', () {
      final options = parse(provider, {'CODELAB_API_KEY': 'sk-test-secret'});
      expect(options.apiKey, 'sk-test-secret');
      expect(options.toString(), isNot(contains('sk-test-secret')));
      expect(
        () => parse([...provider, '--api-key', 'sk-test-secret']),
        usageError(isNot(contains('sk-test-secret'))),
      );
    });
  });

  group('mode and logging', () {
    test('--permission-mode beats CODELAB_PERMISSION_MODE', () {
      expect(
        parse(scripted, {'CODELAB_PERMISSION_MODE': 'bypass'}).mode,
        ModeId.bypass,
      );
      expect(
        parse(
          [...scripted, '--permission-mode', 'accept-edits'],
          {'CODELAB_PERMISSION_MODE': 'bypass'},
        ).mode,
        ModeId.acceptEdits,
      );
      expect(parse(scripted).mode, isNull);
    });

    test('autopilot is a flag-only override', () {
      final options = parse([...scripted, '--permission-mode', 'autopilot']);
      expect(options.mode, isNull);
      expect(options.autopilot, isTrue);
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

    test('an unknown CODELAB_* variable is a warning', () {
      final options = parse(scripted, {
        'CODELAB_MODLE': 'x',
        'CODELAB_AGENT_TOKEN': 't',
        'CODELAB_HOME': '/tmp/home',
      });
      expect(options.warnings, [contains('CODELAB_MODLE')]);
      expect(options.codelabHome, '/tmp/home');
    });

    test('CODELAB_HOME defaults to ~/.codelab', () {
      expect(
        parse(scripted, {'HOME': '/home/u'}).codelabHome,
        '/home/u/.codelab',
      );
    });
  });

  test('the usage text hides --llm-script', () {
    expect(serveUsage(), contains('--stdio'));
    expect(serveUsage(), contains('--provider'));
    expect(serveUsage(), isNot(contains('llm-script')));
  });
}
