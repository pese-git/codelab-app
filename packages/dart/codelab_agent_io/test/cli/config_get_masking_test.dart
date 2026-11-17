import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../support/fake_secret_process_runner.dart';

// Заведомо фиктивные значения в формате шаблонов §12.4.
const _skProj = 'sk-proj-AbCdEfGhIjKlMnOpQrStUvWx';
const _github = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';
const _slack = 'xoxb-1234567890-abcdefghij';

/// Маскер `config get` по правилу «все листья через `literalSecretTag` и
/// находки» (agent-configuration «Маскирование args MCP-серверов в выводе»,
/// сценарий «config get не печатает литеральный ключ»; design.md change
/// `add-config-literal-secrets-and-migrate`, D5, R8-8). Часть задачи 2.2,
/// сделанная в итерации 1 по ревью: листья реестра больше не пропускают
/// литерал.
void main() {
  late Directory root;
  late String home;
  late String cwd;

  setUp(() {
    root = Directory(
      Directory.systemTemp
          .createTempSync('config_get_mask')
          .resolveSymbolicLinksSync(),
    );
    home = '${root.path}/home';
    cwd = '${root.path}/proj';
    Directory(home).createSync();
    Directory(cwd).createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<Map<String, Object?>> get(String key, String yaml) async {
    File('$home/config.yaml').writeAsStringSync(yaml);
    final result =
        await ConfigCommands(processRunner: FakeSecretProcessRunner()).get(
          ConfigGetOptions(
            key: key,
            cwd: cwd,
            environment: {'CODELAB_HOME': home},
          ),
        );
    expect(result.exitCode, 0, reason: result.stderr.join('\n'));
    final lines = result.stdout.takeWhile((l) => !l.startsWith('layer:'));
    return jsonDecode(lines.join('\n')) as Map<String, Object?>;
  }

  const providers =
      '''
providers:
  p:
    kind: openai-compatible
    api_key: $_skProj
  q:
    kind: openai-compatible
    api_key_env: $_github
  s:
    kind: openai-compatible
    api_key_secret: $_github
  r:
    kind: openai-compatible
    api_key: \${KEY}
  v:
    kind: openai-compatible
    api_key: \${secret:codelab/v}
  w:
    kind: openai-compatible
    api_key: \${secret:$_github}
  u:
    kind: openai-compatible
    base_url: https://llm.test/$_github/v1
  z:
    kind: openai-compatible
    base_url: https://llm.test/v1?mode=a
  h:
    kind: openai-compatible
    api_key_env: OPENAI_API_KEY
    headers:
      X-Team: Bearer $_slack
      X-Ref: Bearer \${secret:$_github}
      X-Plain: blue
      Authorization: Bearer \${secret:codelab/h/auth}
''';

  test(
    'a literal key and a key written instead of a name are <redacted>',
    () async {
      final tree = await get('providers', providers);

      Map<String, Object?> at(String id) => tree[id]! as Map<String, Object?>;
      expect(at('p')['api_key'], '<redacted>');
      expect(at('q')['api_key_env'], '<redacted>');
      expect(at('s')['api_key_secret'], '<redacted>');
      expect('$tree', isNot(contains(_skProj)));
      expect('$tree', isNot(contains(_github)));
      expect('$tree', isNot(contains(_slack)));
    },
  );

  test('a token behind api_key \${secret:…} and in a base_url path is hidden, '
      'a plain address is not', () async {
    final tree = await get('providers', providers);

    Map<String, Object?> at(String id) => tree[id]! as Map<String, Object?>;
    expect(at('w')['api_key'], '<redacted>');
    expect(at('u')['base_url'], '<redacted>');
    expect(at('z')['base_url'], 'https://llm.test/v1?mode=a');
    expect('$tree', isNot(contains(_github)));
  });

  test('references are printed as is (R8-8)', () async {
    final tree = await get('providers', providers);

    Map<String, Object?> at(String id) => tree[id]! as Map<String, Object?>;
    expect(at('r')['api_key'], r'${KEY}');
    expect(at('v')['api_key'], r'${secret:codelab/v}');
    expect(at('h')['api_key_env'], 'OPENAI_API_KEY');
  });

  test('headers: a pattern match is hidden under any name, a reference to a '
      'proper secret name and a plain value are not', () async {
    final tree = await get(
      'providers.h.headers',
      providers.replaceFirst('providers:', 'providers:'),
    );

    expect(tree['X-Team'], '<redacted>');
    expect(tree['X-Ref'], '<redacted>');
    expect(tree['X-Plain'], 'blue');
    expect(tree['Authorization'], r'Bearer ${secret:codelab/h/auth}');
  });
}
