import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../support/config_writer_harness.dart';

/// Правило литералов писателя поверх `literalSecretTag` (agent-configuration
/// «Литеральные секреты в файле конфига», абзац про `ConfigWriter`, сценарий
/// «Литеральный токен в args через mcp add»; design.md change
/// `add-config-literal-secrets-and-migrate`, D5, OQ3, R8-5, R1-1).
///
/// Значения «секретов» выдуманные; ни одно не должно попасть в текст
/// исключения или предупреждения.
void main() {
  late ConfigWriterHarness h;

  setUp(() => h = ConfigWriterHarness.create());
  tearDown(() => h.dispose());

  const user = ConfigTarget.user();
  const token = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';

  Future<ConfigWriteResult> apply(List<ConfigEdit> edits) async =>
      h.writer.apply(await h.writer.read(user), edits);

  Map<String, Object?> server(Map<String, Object?> extra) => {
    'name': 'gh',
    'type': 'stdio',
    'command': 'gh-mcp',
    ...extra,
  };

  Matcher rejectedWithoutValue({String? hint}) =>
      isA<ConfigInlineSecretException>()
          .having((e) => e.toString(), 'toString', isNot(contains(token)))
          .having(
            (e) => e.issues.map((i) => i.message).join('\n'),
            'messages',
            allOf(
              isNot(contains(token)),
              hint == null ? anything : contains(hint),
            ),
          );

  group('headers и env: литеральные части по шаблону (R1-1)', () {
    test(
      'несекретное имя заголовка с токеном по шаблону отклоняется',
      () async {
        h.write(h.userPath, baseConfig);
        final before = h.read(h.userPath);

        await expectLater(
          apply([
            UpsertMcpServer(
              server({
                'type': 'http',
                'url': 'https://h.test/mcp',
                'headers': {'X-Team': 'Bearer $token'},
              })..remove('command'),
            ),
          ]),
          throwsA(rejectedWithoutValue()),
        );
        expect(h.read(h.userPath), before);
      },
    );

    test('несекретное имя env с токеном по шаблону отклоняется', () async {
      h.write(h.userPath, baseConfig);

      await expectLater(
        apply([
          UpsertMcpServer(
            server({
              'env': {'GREETING': token},
            }),
          ),
        ]),
        throwsA(rejectedWithoutValue()),
      );
    });

    test('смесь литерала и ссылки отклоняется', () async {
      h.write(h.userPath, baseConfig);

      await expectLater(
        apply([
          UpsertMcpServer(
            server({
              'env': {'GREETING': '$token \${X}'},
            }),
          ),
        ]),
        throwsA(rejectedWithoutValue()),
      );
    });

    test('ссылка и обычное значение проходят', () async {
      h.write(h.userPath, baseConfig);

      await apply([
        UpsertMcpServer(
          server({
            'env': {'GREETING': 'hello', 'REF': 'Bearer \${secret:codelab/gh}'},
          }),
        ),
      ]);

      expect(h.read(h.userPath), contains('hello'));
    });
  });

  group('элементы args (OQ3, R8-5)', () {
    test('токен по шаблону в args отклоняется с подсказкой --env', () async {
      h.write(h.userPath, baseConfig);
      final before = h.read(h.userPath);

      await expectLater(
        apply([
          UpsertMcpServer(
            server({
              'args': ['--token', token],
            }),
          ),
        ]),
        throwsA(
          rejectedWithoutValue(hint: "--env <NAME>='\${secret:codelab/mcp/gh/"),
        ),
      );
      expect(h.read(h.userPath), before);
    });

    test('подсказка и suggestedSecretName согласованы', () async {
      h.write(h.userPath, baseConfig);

      try {
        await apply([
          UpsertMcpServer(
            server({
              'args': [token],
            }),
          ),
        ]);
        fail('expected ConfigInlineSecretException');
      } on ConfigInlineSecretException catch (e) {
        expect(
          e.issues.single.message,
          contains('\${secret:${e.suggestedSecretName}}'),
        );
        expect(SecretNames.problem(e.suggestedSecretName), isNull);
      }
    });

    test('флаги, ссылки и обычные значения в args проходят', () async {
      h.write(h.userPath, baseConfig);

      await apply([
        UpsertMcpServer(
          server({
            'args': ['--verbose', '--token', '\${TOKEN}', 'plain-value'],
          }),
        ),
      ]);

      expect(h.read(h.userPath), contains('--verbose'));
    });
  });

  group('прежний литерал файла', () {
    const original =
        '''
agent:
  default_model: lm/m
providers:
  lm:
    base_url: https://h.test/v1
    kind: openai-compatible
    models:
      m: {}
mcp:
  servers:
    - name: gh
      type: stdio
      command: gh-mcp
      args: ["--token", "$token"]
      env:
        GREETING: "$token"
''';

    test('не блокирует запись и идёт предупреждением без значения', () async {
      h.write(h.userPath, original);

      final result = await apply([
        UpsertMcpServer(
          server({
            'args': ['--token', token],
            'env': {'GREETING': token},
            'enabled': false,
          }),
        ),
      ]);

      expect(h.read(h.userPath), contains('enabled: false'));
      // Предупреждение загрузки — по конкретному ключу env; по `args` его нет:
      // загрузка `args` не проверяет (OQ3, D5), поэтому литерал `args`
      // остаётся в файле молча, а отказ действует только на записи.
      final warnings = result.warnings
          .where((w) => w.event == 'config.secret.in_file')
          .map((w) => w.key);
      expect(warnings, contains('mcp.servers[gh].env.GREETING'));
      expect(warnings.where((k) => k.contains('args')), isEmpty);
      expect(
        result.warnings.map((w) => '${w.message}${w.key}').join(),
        isNot(contains(token)),
      );
    });

    test('config unset удаляет ключ с литералом', () async {
      h.write(h.userPath, original);

      await apply([const UnsetValue('mcp.servers[gh].env.GREETING')]);
      expect(h.read(h.userPath), isNot(contains('GREETING')));

      await apply([const UnsetValue('mcp.servers[gh].args')]);
      expect(h.read(h.userPath), isNot(contains(token)));
    });
  });
}
