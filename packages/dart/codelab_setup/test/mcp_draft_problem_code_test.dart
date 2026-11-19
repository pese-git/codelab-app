import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import 'support/provider_setup_fakes.dart';

/// Типизированные проблемы черновика MCP-сервера (spec `client-agent-setup`
/// «Типизированные проблемы черновика MCP-сервера»; design.md change
/// `add-desktop-localization`, D6 «Тексты моста настроек (итерация 5)»;
/// SETUP-1).
///
/// Почему: app строит текст проблемы на своём языке по `code` и `argument`,
/// а `message` остаётся прежним английским текстом для CLI. Тесты красные до
/// 5.1b: `validate()` пока не заполняет `code` и `argument`, а фабрика
/// `McpDraftProblem.of` — заглушка. Порты — фейки, таймеров нет.
void main() {
  const leak = 'sk-test-leak-0123456789';
  const url = 'https://mcp.test/mcp';

  /// Прежний английский текст кода (11 фраз `validate()`): фиксируется здесь
  /// дословно, чтобы 5.1b не изменил вывод CLI.
  String textOf(McpDraftProblemCode code, String? key) => switch (code) {
    McpDraftProblemCode.nameInvalid => 'Use a name without spaces, [, ] or ".',
    McpDraftProblemCode.renameNotAllowed =>
      'Remove the server and add it again to rename it.',
    McpDraftProblemCode.nameTaken => 'A server with this name already exists.',
    McpDraftProblemCode.commandEmpty => 'Enter the command.',
    McpDraftProblemCode.urlInvalid => 'Enter an http or https URL.',
    McpDraftProblemCode.urlHasUserinfo =>
      'Remove the user name and password from the URL.',
    McpDraftProblemCode.keyHasSpaces => 'Remove spaces around the name $key.',
    McpDraftProblemCode.keyDuplicate => 'Two values are named $key.',
    McpDraftProblemCode.keyEmpty => 'Enter a name for every value.',
    McpDraftProblemCode.secretValueEmpty => 'Enter the secret value for $key.',
    McpDraftProblemCode.secretNameCollision =>
      'Two secret values get the same secret name; rename $key.',
  };

  /// Коды, у которых проблема несёт имя ключа.
  const keyCodes = {
    McpDraftProblemCode.keyHasSpaces,
    McpDraftProblemCode.keyDuplicate,
    McpDraftProblemCode.secretValueEmpty,
    McpDraftProblemCode.secretNameCollision,
  };

  McpServerDraft http({
    String name = 'docs',
    String address = url,
    Map<String, McpValueDraft> headers = const {},
  }) => McpServerDraft(
    name: name,
    kind: McpTransportKind.http,
    url: address,
    headers: headers,
  );

  McpServerDraft stdio({
    String command = 'srv',
    Map<String, McpValueDraft> env = const {},
  }) => McpServerDraft(
    name: 'docs',
    kind: McpTransportKind.stdio,
    command: command,
    env: env,
  );

  /// Черновик для каждого кода, который `validate()` способен вернуть, и
  /// ожидаемые поле, аргумент. `keyDuplicate` здесь нет: ключи, равные после
  /// `trim`, `validate()` отдаёт как `keyHasSpaces` (второй ключ с пробелами),
  /// а «два значения с одним именем» клиент находит до построения черновика
  /// (D6) и строит фабрикой, см. группу ниже.
  final cases =
      <
        ({
          String title,
          McpDraftProblemCode code,
          McpDraftField field,
          String? argument,
          List<McpDraftProblem> Function() problems,
        })
      >[
        (
          title: 'имя с пробелом',
          code: McpDraftProblemCode.nameInvalid,
          field: McpDraftField.name,
          argument: null,
          problems: () => http(name: 'a b').validate(),
        ),
        (
          title: 'переименование при правке',
          code: McpDraftProblemCode.renameNotAllowed,
          field: McpDraftField.name,
          argument: null,
          problems: () => McpServerDraft.fromElement({
            'name': 'old',
            'type': 'http',
            'url': url,
          }).copyWith(name: 'new').validate(),
        ),
        (
          title: 'имя уже есть в эффективном конфиге',
          code: McpDraftProblemCode.nameTaken,
          field: McpDraftField.name,
          argument: null,
          problems: () => http().validate(existingNames: {'docs'}),
        ),
        (
          title: 'пустая команда stdio',
          code: McpDraftProblemCode.commandEmpty,
          field: McpDraftField.command,
          argument: null,
          problems: () => stdio(command: ' ').validate(),
        ),
        (
          title: 'URL не http и не https',
          code: McpDraftProblemCode.urlInvalid,
          field: McpDraftField.url,
          argument: null,
          problems: () => http(address: 'ftp://h/mcp').validate(),
        ),
        (
          title: 'URL без хоста',
          code: McpDraftProblemCode.urlInvalid,
          field: McpDraftField.url,
          argument: null,
          problems: () => http(address: 'https://').validate(),
        ),
        (
          title: 'URL с userinfo',
          code: McpDraftProblemCode.urlHasUserinfo,
          field: McpDraftField.url,
          argument: null,
          problems: () => http(address: 'https://u:p@h/mcp').validate(),
        ),
        (
          title: 'ключ env с пробелом по краю',
          code: McpDraftProblemCode.keyHasSpaces,
          field: McpDraftField.env,
          argument: ' TOKEN',
          problems: () =>
              stdio(env: {' TOKEN': McpValueDraft.text('a')}).validate(),
        ),
        (
          title: 'пустое имя ключа headers',
          code: McpDraftProblemCode.keyEmpty,
          field: McpDraftField.headers,
          argument: null,
          problems: () =>
              http(headers: {'': McpValueDraft.text('x')}).validate(),
        ),
        (
          title: 'пустое значение нового секрета',
          code: McpDraftProblemCode.secretValueEmpty,
          field: McpDraftField.env,
          argument: 'TOKEN',
          problems: () => stdio(
            env: {'TOKEN': McpValueDraft.secret(SecretValue(''))},
          ).validate(),
        ),
        (
          title: 'два новых секрета с одним именем секрета',
          code: McpDraftProblemCode.secretNameCollision,
          field: McpDraftField.headers,
          argument: 'X-Token',
          problems: () => http(
            headers: {
              'X Token': McpValueDraft.secret(SecretValue('one')),
              'X-Token': McpValueDraft.secret(SecretValue('two')),
            },
          ).validate(),
        ),
      ];

  group('коды validate() (сценарии «Ошибки черновика с кодами», «Код с '
      'именем ключа»)', () {
    for (final c in cases) {
      test('${c.title}: код ${c.code.name}, текст прежний', () {
        final problem = c.problems().single;

        expect(problem.code, c.code);
        expect(problem.field, c.field);
        expect(problem.argument, c.argument);
        expect(problem.message, textOf(c.code, c.argument));
      });
    }

    test('имя `a b` и URL с userinfo: два кода, аргументов нет', () {
      final problems = http(
        name: 'a b',
        address: 'https://u:p@h/mcp',
      ).validate();

      expect(problems.map((p) => p.code), [
        McpDraftProblemCode.nameInvalid,
        McpDraftProblemCode.urlHasUserinfo,
      ]);
      expect(problems.map((p) => p.argument), [null, null]);
      expect(problems.first.message, 'Use a name without spaces, [, ] or ".');
      expect(
        problems.last.message,
        'Remove the user name and password from the URL.',
      );
    });

    test('новый секрет TOKEN с пустым значением: поле env, аргумент TOKEN', () {
      final problem = stdio(
        env: {'TOKEN': McpValueDraft.secret(SecretValue(''))},
      ).validate().single;

      expect(problem.field, McpDraftField.env);
      expect(problem.code, McpDraftProblemCode.secretValueEmpty);
      expect(problem.argument, 'TOKEN');
      expect(problem.message, 'Enter the secret value for TOKEN.');
    });

    test('ключи, равные после trim, validate() отдаёт как keyHasSpaces '
        '(keyDuplicate строит только фабрика до черновика)', () {
      final problem = stdio(
        env: {
          'TOKEN': McpValueDraft.text('a'),
          ' TOKEN ': McpValueDraft.text('b'),
        },
      ).validate().single;

      expect(problem.code, McpDraftProblemCode.keyHasSpaces);
    });

    test('значения env, headers, URL и секрета не попадают в аргумент и '
        'toString (SETUP-1)', () {
      final problems = [
        ...http(
          address: 'https://u:$leak@h/mcp',
          headers: {
            'X Token': McpValueDraft.secret(SecretValue(leak)),
            'X-Token': McpValueDraft.secret(SecretValue(leak)),
            ' Pad': McpValueDraft.text(leak),
          },
        ).validate(),
        ...stdio(
          env: {'EMPTY': McpValueDraft.secret(SecretValue(''))},
        ).validate(),
      ];

      expect(problems, isNotEmpty);
      expect(problems.every((p) => p.code != null), isTrue);
      for (final p in problems) {
        expect(p.argument ?? '', isNot(contains(leak)));
        expect(p.message, isNot(contains(leak)));
        expect('$p', isNot(contains(leak)));
      }
    });
  });

  group('фабрика McpDraftProblem.of (сценарий «Совпавшие ключи до '
      'черновика»)', () {
    test('два значения Authorization: код keyDuplicate, аргумент и текст', () {
      final problem = McpDraftProblem.of(
        McpDraftProblemCode.keyDuplicate,
        McpDraftField.headers,
        argument: 'Authorization',
      );

      expect(problem.field, McpDraftField.headers);
      expect(problem.code, McpDraftProblemCode.keyDuplicate);
      expect(problem.argument, 'Authorization');
      expect(problem.message, 'Two values are named Authorization.');
    });

    test('фабрика строит код и тот же текст для каждого кода', () {
      for (final code in McpDraftProblemCode.values) {
        final key = keyCodes.contains(code) ? 'K' : null;

        final problem = McpDraftProblem.of(
          code,
          McpDraftField.env,
          argument: key,
        );

        expect(problem.code, code, reason: code.name);
        expect(problem.argument, key, reason: code.name);
        expect(problem.message, textOf(code, key), reason: code.name);
      }
    });

    test('позиционный конструктор остаётся: код необязателен (чужой '
        'источник)', () {
      const problem = McpDraftProblem(McpDraftField.name, 'Custom text.');

      expect(problem.code, isNull);
      expect(problem.argument, isNull);
      expect(problem.message, 'Custom text.');
    });
  });

  group('инвариант «текст ⇔ код» (сценарий «Инвариант кода»)', () {
    /// Черновики этого файла и сценариев `mcp_server_draft_test.dart`.
    final drafts = <McpServerDraft>[
      http(name: 'a b', address: 'https://u:p@h/mcp'),
      http(address: 'ftp://h/mcp'),
      http(headers: {'': McpValueDraft.text('x')}),
      http(
        headers: {
          '': McpValueDraft.text('x'),
          'Authorization': McpValueDraft.secret(SecretValue('')),
        },
      ),
      http(
        headers: {
          'X Token': McpValueDraft.secret(SecretValue('one')),
          'X-Token': McpValueDraft.secret(SecretValue('two')),
        },
      ),
      stdio(command: ''),
      stdio(
        env: {
          'TOKEN': McpValueDraft.stored(r'${secret:codelab/mcp/docs/token}'),
          'token': McpValueDraft.secret(SecretValue('new')),
        },
      ),
      stdio(env: {' TOKEN': McpValueDraft.text('a')}),
      stdio(
        env: {
          'TOKEN': McpValueDraft.text('a'),
          ' TOKEN ': McpValueDraft.text('b'),
        },
      ),
    ];

    void expectInvariant(List<McpDraftProblem> problems) {
      for (final p in problems) {
        final code = p.code;
        expect(code, isNotNull, reason: '$p');
        if (code == null) {
          continue;
        }
        expect(
          p.argument != null,
          keyCodes.contains(code),
          reason: 'аргумент ровно у кодов о ключе: $p',
        );
        expect(p.message, textOf(code, p.argument), reason: '$p');
      }
    }

    test('каждая проблема validate() имеет код, аргумент ровно у кодов о '
        'ключе, текст прежний', () {
      final all = [
        for (final draft in drafts) ...draft.validate(),
        for (final c in cases) ...c.problems(),
        ...http().validate(existingNames: {'docs'}),
      ];

      expect(all, isNotEmpty);
      expectInvariant(all);
    });

    test('McpServerInvalid.problems из commit несёт коды', () async {
      final committer = McpServerCommitter(
        config: FakeConfigStore([]),
        keys: FakeProviderKeys(),
      );

      final outcome = await committer.commit(
        http(name: 'a b', address: 'https://u:p@h/mcp'),
        const ConfigSnapshot(
          target: ConfigTarget.user(),
          path: '/h/config.yaml',
          fingerprint: 'fp',
          values: {},
        ),
        cwd: '/work/project',
      );

      final invalid = outcome as McpServerInvalid;
      expect(invalid.problems.map((p) => p.code), [
        McpDraftProblemCode.nameInvalid,
        McpDraftProblemCode.urlHasUserinfo,
      ]);
      expectInvariant(invalid.problems);
    });
  });
}
