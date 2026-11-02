// Composition root CLI (spec codelab-cli «Встроенный агент в CLI», «Выход»,
// «Отладка секретов»; design.md change `add-embedded-agent-mode`, D6;
// AGENTS.md §9, §12).

import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart'
    show AcpTransport;
import 'package:codelab_cli/src/composition_root.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_embedded/codelab_embedded.dart' as embedded;
import 'package:codelab_embedded/testing.dart';
import 'package:test/test.dart';

import 'support/fake_cli_io.dart';

const _script = {
  'model': {
    'provider': 'scripted',
    'modelId': 'scripted-1',
    'contextWindow': 32768,
  },
  'steps': <Object?>[],
};

/// Агент, чей `dispose` не возвращается, пока тест не отпустит его: повисший
/// агент не должен держать выход CLI вечно.
final class _HangingDispose implements embedded.EmbeddedAgent {
  _HangingDispose(this._inner);

  final embedded.EmbeddedAgent _inner;
  final release = Completer<void>();

  @override
  AcpTransport get clientTransport => _inner.clientTransport;

  @override
  Future<void> get closed => _inner.closed;

  @override
  Future<void> dispose() => release.future;

  Future<void> disposeInner() => _inner.dispose();
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('codelab_root_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('dispose of the runtime does not wait forever for a hanging embedded '
      'agent: it logs embedded.close_timeout and finishes', () async {
    final scripted = scriptedEmbeddedAgentOpener(
      llm: _script,
      codelabHome: '${tmp.path}/home',
      logger: const CliEmbeddedLogger.silent(),
    );
    _HangingDispose? hanging;
    final stderr = StringBuffer();
    final runtime = buildCliRuntime(
      environment: {'CODELAB_HOME': '${tmp.path}/home'},
      stderr: stderr,
      verbose: true,
      embeddedCloseTimeout: const Duration(milliseconds: 50),
      embeddedOpener: ({required cwd, required hostProfile}) async => hanging =
          _HangingDispose(await scripted(cwd: cwd, hostProfile: hostProfile)),
    );
    await runtime.workspace.connect(
      embeddedCliProfile,
      projectDirectory: tmp.path,
    );

    await runtime.dispose().timeout(const Duration(seconds: 20));

    expect(stderr.toString(), contains('embedded.close_timeout'));
    hanging!.release.complete();
    await hanging!.disposeInner();
  });

  test('a hanging embedded agent is announced by one stderr line even '
      'without --verbose (spec «Выход»)', () async {
    final scripted = scriptedEmbeddedAgentOpener(
      llm: _script,
      codelabHome: '${tmp.path}/home',
      logger: const CliEmbeddedLogger.silent(),
    );
    _HangingDispose? hanging;
    final stderr = StringBuffer();
    final runtime = buildCliRuntime(
      environment: {'CODELAB_HOME': '${tmp.path}/home'},
      stderr: stderr,
      verbose: false,
      embeddedCloseTimeout: const Duration(seconds: 1),
      embeddedOpener: ({required cwd, required hostProfile}) async => hanging =
          _HangingDispose(await scripted(cwd: cwd, hostProfile: hostProfile)),
    );
    await runtime.workspace.connect(
      embeddedCliProfile,
      projectDirectory: tmp.path,
    );

    await runtime.dispose().timeout(const Duration(seconds: 20));

    expect(
      stderr.toString(),
      'codelab: the embedded agent did not stop in 1 s\n',
    );
    hanging!.release.complete();
    await hanging!.disposeInner();
  });

  test('--debug-secrets without --verbose reaches the real opener as a '
      'secret-lookups-only logger: the lookup is on stderr, other agent '
      'events are not', () async {
    // Настоящий открыватель с конфигом, где провайдер просит ключ: запрос
    // уходит на закрытый порт, сети нет.
    Directory('${tmp.path}/home').createSync();
    File('${tmp.path}/home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: http://127.0.0.1:1/v1
    api_key_secret: codelab/p
    models:
      m: {}
agent:
  default_model: p/m
''');
    const value = 'sk-unit-secret-value';
    final io = FakeCliIo();
    final run = runCodelab(
      [
        '-a',
        'embedded',
        '--debug-secrets',
        '-p',
        'hi',
        '--timeout',
        '5s',
        '-C',
        tmp.path,
      ],
      environment: {
        'CODELAB_HOME': '${tmp.path}/home',
        'CODELAB_SECRET_CODELAB_P': value,
      },
      io: io,
    );
    // Ход упадёт на недоступном провайдере; нужен лишь след поиска ключа.
    await run.timeout(const Duration(seconds: 90));

    final text = io.stderrText;
    expect(text, contains('secrets.lookup'));
    expect(text, contains('name=codelab/p'));
    expect(text, isNot(contains(value)));
    expect(text, isNot(contains('host.plan')));
  });

  test('CODELAB_DEBUG_SECRETS=1 works like --debug-secrets', () async {
    Directory('${tmp.path}/home').createSync();
    File('${tmp.path}/home/config.yaml').writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: http://127.0.0.1:1/v1
    api_key_secret: codelab/p
    models:
      m: {}
agent:
  default_model: p/m
''');
    final io = FakeCliIo();

    await runCodelab(
      ['-a', 'embedded', '-p', 'hi', '--timeout', '5s', '-C', tmp.path],
      environment: {
        'CODELAB_HOME': '${tmp.path}/home',
        'CODELAB_SECRET_CODELAB_P': 'sk-unit-secret-value',
        'CODELAB_DEBUG_SECRETS': '1',
      },
      io: io,
    ).timeout(const Duration(seconds: 90));

    expect(io.stderrText, contains('secrets.lookup'));
    expect(io.stderrText, isNot(contains('sk-unit-secret-value')));
  });

  test('the workspace connects to the embedded profile', () async {
    final runtime = buildCliRuntime(
      environment: {'CODELAB_HOME': '${tmp.path}/home'},
      stderr: StringBuffer(),
      verbose: false,
      embeddedOpener: scriptedEmbeddedAgentOpener(
        llm: _script,
        codelabHome: '${tmp.path}/home',
        logger: const CliEmbeddedLogger.silent(),
      ),
    );
    addTearDown(runtime.dispose);

    await runtime.workspace.connect(
      embeddedCliProfile,
      projectDirectory: tmp.path,
    );

    expect(runtime.workspace.current.connection, isA<Connected>());
  });
}
