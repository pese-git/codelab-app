// E2E `codelab mcp add --header-stdin | --env-stdin` против собранного
// `codelab-agent` (задача 3.7 change `add-config-literal-secrets-and-migrate`;
// spec codelab-cli «Флаги stdin у codelab mcp add»; design.md D11, R8-5).
//
// Критерий: stdout, stderr, код выхода и байты файлов совпадают; значение из
// stdin нигде не печатается и не попадает в конфиг. Значения выдуманные.
@Timeout(Duration(seconds: 240))
library;

import 'dart:io';

import 'package:test/test.dart';

import 'support/dual_binary.dart';
import 'support/e2e_agent.dart';

final _token = 'ghp_${'abcdef0123' * 3}abcdef';

const _base = '''
# my settings
secrets:
  backend: file
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
''';

void main() {
  late DualBinary dual;

  setUp(() => dual = DualBinary.create('codelab_cli_e2e_mcp_stdin_'));
  tearDown(() => dual.dispose());

  test('--header-stdin со схемой: код 0, вывод и байты как у агента', () async {
    final cli = await dual.expectSame(
      [
        'mcp',
        'add',
        'gh',
        '--type',
        'http',
        '--url',
        'https://h',
        '--header-stdin',
        'Authorization',
        '--header-scheme',
        'Bearer',
      ],
      files: {'config.yaml': _base},
      stdin: '$_token\n',
    );

    expect(cli.exitCode, 0, reason: '$cli');
    expect('${cli.stdout}${cli.stderr}', isNot(contains(_token)));
    final config = File('${dual.home}/config.yaml').readAsStringSync();
    expect(
      config,
      contains(
        r"Authorization: 'Bearer ${secret:codelab/mcp/gh/authorization}'",
      ),
    );
    expect(config, contains('# my settings'));
    expect(config, isNot(contains(_token)));
    expect(File('${dual.home}/secrets.yaml').existsSync(), isTrue);
  }, tags: scriptedOnly);

  test('--env-stdin: значение в хранилище, в конфиге ссылка', () async {
    final cli = await dual.expectSame(
      [
        'mcp',
        'add',
        'gh',
        '--type',
        'stdio',
        '--command',
        'gh-mcp',
        '--env-stdin',
        'GITHUB_TOKEN',
      ],
      files: {'config.yaml': _base},
      stdin: '$_token\n',
    );

    expect(cli.exitCode, 0, reason: '$cli');
    expect('${cli.stdout}${cli.stderr}', isNot(contains(_token)));
    final config = File('${dual.home}/config.yaml').readAsStringSync();
    expect(
      config,
      contains(r"GITHUB_TOKEN: '${secret:codelab/mcp/gh/github_token}'"),
    );
    expect(config, isNot(contains(_token)));
  }, tags: scriptedOnly);

  test('два -stdin флага и схема без --header-stdin: 64 как у агента, '
      'ничего не сохранено', () async {
    for (final extra in [
      ['--header-stdin', 'A', '--env-stdin', 'B'],
      ['--header-scheme', 'Bearer'],
    ]) {
      final cli = await dual.expectSame(
        ['mcp', 'add', 'gh', '--type', 'http', '--url', 'https://h', ...extra],
        files: {'config.yaml': _base},
        stdin: '$_token\n',
      );

      expect(cli.exitCode, 64, reason: '$extra $cli');
      expect('${cli.stdout}${cli.stderr}', isNot(contains(_token)));
      expect(File('${dual.home}/secrets.yaml').existsSync(), isFalse);
      expect(File('${dual.home}/config.yaml').readAsStringSync(), _base);
    }
  }, tags: scriptedOnly);

  test('справка mcp перечисляет флаги stdin', () async {
    final cli = await dual.runCli(['mcp']);

    expect(cli.exitCode, 64);
    expect(cli.stderr, contains('--header-stdin'));
    expect(cli.stderr, contains('--header-scheme'));
    expect(cli.stderr, contains('--env-stdin'));
  }, tags: scriptedOnly);
}
