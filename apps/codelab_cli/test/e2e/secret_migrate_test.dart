// E2E `codelab secret migrate` против собранного `codelab-agent` (задача 3.7
// change `add-config-literal-secrets-and-migrate`; spec codelab-cli
// «Подкоманда codelab secret», сценарии «migrate совпадает с бинарём
// агента», «--cwd подкоманды migrate и -C верхнего уровня», «Предупреждение
// о 1.0 в справке»; design.md D7, D13, R8-7).
//
// Критерий: stdout, код выхода и байты файлов обоих бинарей совпадают на
// одинаковых входах. Значения выдуманные; тег `scripted-only` — файл не
// зависит от агента матрицы.
@Timeout(Duration(seconds: 300))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/dual_binary.dart';
import 'support/e2e_agent.dart';

const _note =
    'Note: before 1.0, tool output, prompts and session logs are not '
    'redacted: secrets they contain reach the model provider and session '
    'files as is.';

final _key = 'sk-${'a1b2c3d4e5' * 3}';
final _projectKey = 'sk-${'f6e5d4c3b2' * 3}';

/// Глобальный конфиг с литеральным ключом провайдера. [project] объявлен
/// доверенным: недоверенный слой проекта не переносится (H4), а тесту нужен
/// именно перенос.
String _userLiteral(String project) =>
    '''
# my settings
secrets:
  backend: file
providers:
  lm:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key: $_key
    models:
      m: {}
agent:
  default_model: lm/m
trusted_projects:
  - $project
''';

/// Слой проекта с литеральным ключом другого провайдера.
final _projectLiteral =
    '''
providers:
  px:
    kind: openai-compatible
    base_url: https://px.test/v1
    api_key: $_projectKey
    models:
      m: {}
''';

String _clean(String project) =>
    '''
secrets:
  backend: file
providers:
  lm:
    kind: openai-compatible
    base_url: https://llm.test/v1
    api_key_secret: codelab/lm
    models:
      m: {}
agent:
  default_model: lm/m
trusted_projects:
  - $project
''';

void main() {
  late DualBinary dual;

  setUp(() => dual = DualBinary.create('codelab_cli_e2e_migrate_'));
  tearDown(() => dual.dispose());

  void expectNoLeak(CliResult result) {
    expect('${result.stdout}${result.stderr}', isNot(contains(_key)));
    expect('${result.stdout}${result.stderr}', isNot(contains(_projectKey)));
  }

  test(
    'перенос провайдера: вывод, код и байты файлов как у codelab-agent',
    () async {
      final cli = await dual.expectSame(
        ['secret', 'migrate'],
        files: {'config.yaml': _userLiteral(dual.project)},
      );

      expect(cli.exitCode, 0, reason: '$cli');
      expect(cli.stdout, contains('Moved providers.lm.api_key in '));
      expect(
        cli.stdout,
        contains('restart the agent to use the moved secrets'),
      );
      expectNoLeak(cli);
      // Состояние после последнего прогона — агентского; ключ в конфиге заменён.
      final config = File('${dual.home}/config.yaml').readAsStringSync();
      expect(config, contains('# my settings'));
      expect(config, contains('api_key_secret: codelab/lm'));
      expect(config, isNot(contains(_key)));
    },
    tags: scriptedOnly,
  );

  test('--dry-run: план совпадает, файлы не меняются', () async {
    final cli = await dual.expectSame(
      ['secret', 'migrate', '--dry-run'],
      files: {'config.yaml': _userLiteral(dual.project)},
    );

    expect(cli.exitCode, 0, reason: '$cli');
    expect(cli.stdout, contains('providers.lm.api_key'));
    expectNoLeak(cli);
    expect(
      File('${dual.home}/config.yaml').readAsStringSync(),
      _userLiteral(dual.project),
    );
    expect(File('${dual.home}/secrets.yaml').existsSync(), isFalse);
  }, tags: scriptedOnly);

  test('--all --dry-run --cwd: все слои, вывод совпадает', () async {
    final cli = await dual.expectSame(
      ['secret', 'migrate', '--all', '--dry-run', '--cwd', dual.project],
      files: {
        'config.yaml': _userLiteral(dual.project),
        'project/.codelab/config.yaml': _projectLiteral,
      },
    );

    expect(cli.exitCode, 0, reason: '$cli');
    expect(cli.stdout, contains('providers.lm.api_key'));
    expect(cli.stdout, contains('providers.px.api_key'));
    expectNoLeak(cli);
  }, tags: scriptedOnly);

  test('--all переносит слои пользователя и проекта одинаково', () async {
    final cli = await dual.expectSame(
      ['secret', 'migrate', '--all', '--cwd', dual.project],
      files: {
        'config.yaml': _userLiteral(dual.project),
        'project/.codelab/config.yaml': _projectLiteral,
      },
    );

    expect(cli.exitCode, 0, reason: '$cli');
    expectNoLeak(cli);
  }, tags: scriptedOnly);

  test('--project --local вместе разрешены и совпадают с агентом', () async {
    final cli = await dual.expectSame(
      ['secret', 'migrate', '--project', '--local', '--dry-run'],
      files: {
        'config.yaml': _userLiteral(dual.project),
        'project/.codelab/config.yaml': _projectLiteral,
      },
    );

    expect(cli.exitCode, 0, reason: '$cli');
    expect(cli.stdout, contains('providers.px.api_key'));
    expect(cli.stdout, isNot(contains('providers.lm.api_key')));
  }, tags: scriptedOnly);

  test('нечего переносить: одинаковый вывод и код 0', () async {
    final cli = await dual.expectSame(
      ['secret', 'migrate'],
      files: {'config.yaml': _clean(dual.project)},
    );

    expect(cli.exitCode, 0, reason: '$cli');
    expect(cli.stdout, contains('Nothing to migrate'));
  }, tags: scriptedOnly);

  test(
    'ошибки использования: 64 и то же сообщение, слова не цитируются',
    () async {
      for (final args in [
        ['secret', 'migrate', '--all', '--project'],
        ['secret', 'migrate', '--all', '--local'],
        ['secret', 'migrate', 'sk-leaked-word'],
      ]) {
        final cli = await dual.expectSame(
          args,
          files: {'config.yaml': _userLiteral(dual.project)},
          stderrBeforeUsageOnly: true,
        );

        expect(cli.exitCode, 64, reason: '$args $cli');
        expect(cli.stdout, isEmpty);
        expect(
          cli.stderr,
          contains('Usage: codelab secret set|delete|list|migrate'),
        );
        expect('${cli.stdout}${cli.stderr}', isNot(contains('sk-leaked')));
      }
      expect(File('${dual.home}/secrets.yaml').existsSync(), isFalse);
    },
    tags: scriptedOnly,
  );

  test(
    'неизвестный флаг migrate: 64, без цитаты и текста package:args',
    () async {
      dual.reset({'config.yaml': _userLiteral(dual.project)});
      final cli = await dual.runCli(['secret', 'migrate', '--sk-leaked-flag']);

      expect(cli.exitCode, 64, reason: '$cli');
      expect(cli.stdout, isEmpty);
      expect(cli.stderr, startsWith('codelab: invalid arguments for secret'));
      expect(
        cli.stderr,
        contains('Usage: codelab secret set|delete|list|migrate'),
      );
      expect(cli.stderr, isNot(contains('sk-leaked')));
      expect(cli.stderr, isNot(contains('Could not find')));
      expect(
        File('${dual.home}/config.yaml').readAsStringSync(),
        _userLiteral(dual.project),
      );
    },
    tags: scriptedOnly,
  );

  test('--cwd подкоманды разрешён, -C верхнего уровня с secret — 64', () async {
    dual.reset({
      'config.yaml': _clean(dual.project),
      'project/.codelab/config.yaml': _projectLiteral,
    });

    final own = await dual.runCli([
      'secret',
      'migrate',
      '--project',
      '--cwd',
      dual.project,
    ]);
    expect(own.exitCode, 0, reason: '$own');
    expect(own.stdout, contains('providers.px.api_key'));
    expectNoLeak(own);

    for (final flag in ['-C', '--cwd']) {
      final top = await dual.runCli([flag, dual.project, 'secret', 'migrate']);
      expect(top.exitCode, 64, reason: '$flag $top');
      expect(top.stdout, isEmpty);
      expect(top.stderr, contains('codelab: --cwd does not apply to secret'));
      expect(
        top.stderr,
        contains('Usage: codelab secret set|delete|list|migrate'),
      );
    }
  }, tags: scriptedOnly);

  test('справки secret и --help несут строку о 1.0 и строку migrate', () async {
    final noSub = await dual.runCli(['secret']);
    expect(noSub.exitCode, 64);
    expect(
      noSub.stderr,
      startsWith(
        'codelab: secret needs a subcommand: set, delete, list or migrate',
      ),
    );
    expect(
      noSub.stderr,
      contains('Usage: codelab secret set|delete|list|migrate'),
    );
    expect(noSub.stderr, contains(_note));

    final help = await dual.runCli(['--help']);
    expect(help.exitCode, 0);
    expect('${help.stdout}${help.stderr}', contains(_note));
    expect(
      '${help.stdout}${help.stderr}',
      contains(
        'codelab secret set|delete|list|migrate   manage secrets '
        '(set reads the value on stdin)',
      ),
    );
  }, tags: scriptedOnly);
}
