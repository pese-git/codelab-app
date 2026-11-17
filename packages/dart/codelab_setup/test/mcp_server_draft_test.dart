import 'dart:convert';

import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

/// Черновик MCP-сервера (client-agent-setup «Черновик MCP-сервера»;
/// design.md change `add-provider-setup-ui`, D11; SETUP-1, SETUP-5):
/// проверка до записи, одна правка `UpsertMcpServer`, секретное значение — в
/// хранилище под `SecretNames.forMcp`, в конфиг — ссылка `${secret:…}`.
///
/// Ожидаемый API (задача 5.8): `McpServerDraft`, `McpValueDraft`
/// (`McpTextValue`, `McpNewSecret`, `McpStoredSecret`), `McpTransportKind`,
/// `McpDraftProblem`/`McpDraftField`, `isValidMcpServerName` из ядра.
void main() {
  const leak = 'sk-test-leak-0123456789';
  const nameMessage = 'Use a name without spaces, [, ] or ".';

  McpServerDraft github({
    Map<String, McpValueDraft>? headers,
    String url = 'https://mcp.test/mcp',
  }) => McpServerDraft(
    name: 'github',
    kind: McpTransportKind.http,
    url: url,
    headers:
        headers ??
        {'Authorization': McpValueDraft.secret(SecretValue('Bearer $leak'))},
  );

  group('правка UpsertMcpServer', () {
    test('секретный заголовок → ссылка, секрет в secretsToWrite, значения '
        'нет ни в правках, ни в toString (сценарий «Секретный заголовок»)', () {
      final draft = github();

      final edits = draft.toEdits();

      expect(draft.validate(), isEmpty);
      expect(edits, hasLength(1));
      final upsert = edits.single as UpsertMcpServer;
      expect(upsert.server, {
        'name': 'github',
        'type': 'http',
        'url': 'https://mcp.test/mcp',
        'headers': {
          'Authorization': r'${secret:codelab/mcp/github/authorization}',
        },
      });
      expect(jsonEncode(upsert.server), isNot(contains(leak)));
      expect(draft.secretsToWrite().keys, ['codelab/mcp/github/authorization']);
      expect(
        draft.secretsToWrite()['codelab/mcp/github/authorization']!.reveal(),
        'Bearer $leak',
      );
      expect('$draft', isNot(contains(leak)));
      expect('$edits', isNot(contains(leak)));
    });

    test('stdio: команда, аргументы и окружение; секрет окружения получает '
        'имя от ключа', () {
      final draft = McpServerDraft(
        name: 'GitHub',
        kind: McpTransportKind.stdio,
        command: 'npx',
        args: const ['-y', 'server'],
        env: {
          'GITHUB_TOKEN': McpValueDraft.secret(SecretValue(leak)),
          'LOG_LEVEL': McpValueDraft.text('debug'),
        },
      );

      final server = (draft.toEdits().single as UpsertMcpServer).server;

      expect(server, {
        'name': 'GitHub',
        'type': 'stdio',
        'command': 'npx',
        'args': ['-y', 'server'],
        'env': {
          'GITHUB_TOKEN': r'${secret:codelab/mcp/github/github_token}',
          'LOG_LEVEL': 'debug',
        },
      });
      expect(draft.secretsToWrite().keys, ['codelab/mcp/github/github_token']);
    });

    test(r'значение со своей ссылкой (${VAR}, Bearer ${secret:…}) остаётся '
        'текстом и в хранилище не пишется', () {
      final draft = McpServerDraft(
        name: 'db',
        kind: McpTransportKind.http,
        url: 'https://db.test/mcp',
        headers: {
          'Authorization': McpValueDraft.text(r'Bearer ${secret:codelab/gh}'),
          'X-Team': McpValueDraft.text(r'${TEAM}'),
        },
      );

      final server = (draft.toEdits().single as UpsertMcpServer).server;

      expect(
        (server['headers']! as Map)['Authorization'],
        r'Bearer ${secret:codelab/gh}',
      );
      expect((server['headers']! as Map)['X-Team'], r'${TEAM}');
      expect(draft.secretsToWrite(), isEmpty);
    });

    test('enabled: false попадает в элемент, true — нет', () {
      final off = github(headers: const {}).copyWith(enabled: false);

      expect(
        (off.toEdits().single as UpsertMcpServer).server['enabled'],
        isFalse,
      );
      expect(
        (github(headers: const {}).toEdits().single as UpsertMcpServer).server,
        isNot(contains('enabled')),
      );
    });
  });

  group('правка существующего сервера', () {
    final raw = <String, Object?>{
      'name': 'github',
      'type': 'http',
      'url': 'https://mcp.test/mcp',
      'headers': {
        'Authorization': r'${secret:codelab/mcp/github/authorization}',
        'X-Team': 'core',
      },
      'call_timeout': '30s',
    };

    test('fromElement: ссылка на секрет — McpStoredSecret («stored»), '
        'остальное — текст', () {
      final draft = McpServerDraft.fromElement(raw);

      expect(draft.name, 'github');
      expect(draft.kind, McpTransportKind.http);
      expect(draft.url, 'https://mcp.test/mcp');
      expect(draft.headers['Authorization'], isA<McpStoredSecret>());
      expect(draft.headers['X-Team'], isA<McpTextValue>());
    });

    test('«не менять»: хранимый секрет не попадает в secretsToWrite, ссылка '
        'и неизвестные ключи элемента сохраняются', () {
      final draft = McpServerDraft.fromElement(
        raw,
      ).copyWith(url: 'https://mcp2.test/mcp');

      final server = (draft.toEdits().single as UpsertMcpServer).server;

      expect(draft.secretsToWrite(), isEmpty);
      expect(server['url'], 'https://mcp2.test/mcp');
      expect(
        (server['headers']! as Map)['Authorization'],
        r'${secret:codelab/mcp/github/authorization}',
      );
      expect(server['call_timeout'], '30s', reason: 'ключи не теряются');
    });

    test('замена хранимого секрета новым значением пишет его под тем же '
        'именем', () {
      final draft = McpServerDraft.fromElement(raw).copyWith(
        headers: {
          ...McpServerDraft.fromElement(raw).headers,
          'Authorization': McpValueDraft.secret(SecretValue(leak)),
        },
      );

      expect(draft.secretsToWrite().keys, ['codelab/mcp/github/authorization']);
    });

    test('fromElement stdio: args и env', () {
      final draft = McpServerDraft.fromElement({
        'name': 'pg',
        'type': 'stdio',
        'command': 'pg-mcp',
        'args': ['--ro'],
        'env': {'DATABASE_URL': r'${PG_URL}'},
        'enabled': false,
      });

      expect(draft.kind, McpTransportKind.stdio);
      expect(draft.command, 'pg-mcp');
      expect(draft.args, ['--ro']);
      expect(draft.env['DATABASE_URL'], isA<McpTextValue>());
      expect(draft.enabled, isFalse);
    });
  });

  group('таблица активного типа', () {
    test('stdio: секреты headers не пишутся и не попадают в элемент', () {
      final draft = McpServerDraft(
        name: 'a',
        kind: McpTransportKind.stdio,
        command: 'srv',
        env: {'TOKEN': McpValueDraft.secret(SecretValue('e'))},
        headers: {'Authorization': McpValueDraft.secret(SecretValue(leak))},
      );

      final server = (draft.toEdits().single as UpsertMcpServer).server;

      expect(draft.secretsToWrite().keys, ['codelab/mcp/a/token']);
      expect(server, isNot(contains('headers')));
      expect(jsonEncode(server), isNot(contains('authorization')));
    });

    test('http: секреты env не пишутся и не попадают в элемент', () {
      final draft = McpServerDraft(
        name: 'a',
        kind: McpTransportKind.http,
        url: 'https://h/mcp',
        env: {'TOKEN': McpValueDraft.secret(SecretValue(leak))},
        headers: {'Authorization': McpValueDraft.secret(SecretValue('h'))},
      );

      final server = (draft.toEdits().single as UpsertMcpServer).server;

      expect(draft.secretsToWrite().keys, ['codelab/mcp/a/authorization']);
      expect(server, isNot(contains('env')));
    });
  });

  group('validate()', () {
    List<String> fields(McpServerDraft draft, {Set<String> taken = const {}}) =>
        [for (final p in draft.validate(existingNames: taken)) p.field.name];

    test('имя с пробелом и URL с userinfo: проблемы имени и userinfo, '
        'правок нет (сценарий «Ошибки черновика»)', () {
      final draft = McpServerDraft(
        name: 'a b',
        kind: McpTransportKind.http,
        url: 'https://u:p@h/mcp',
      );

      final problems = draft.validate();

      expect(problems.map((p) => p.field), [
        McpDraftField.name,
        McpDraftField.url,
      ]);
      expect(problems.first.message, nameMessage);
      expect(draft.toEdits(), isEmpty);
    });

    test('сообщения о пользователе и пароле не цитируют URL', () {
      final problems = McpServerDraft(
        name: 'ok',
        kind: McpTransportKind.http,
        url: 'https://u:$leak@h/mcp',
      ).validate();

      expect(problems.map((p) => p.message).join(), isNot(contains(leak)));
    });

    test('правило имени — isValidMcpServerName ядра (реэкспорт моста)', () {
      for (final name in ['', 'a[0]', 'a"b', 'a\tb']) {
        expect(isValidMcpServerName(name), isFalse);
        expect(
          fields(
            McpServerDraft(
              name: name,
              kind: McpTransportKind.http,
              url: 'https://h/mcp',
            ),
          ),
          contains('name'),
          reason: '"$name"',
        );
      }
    });

    test('имя уникально в эффективном конфиге; правка не конфликтует с '
        'собой', () {
      final created = McpServerDraft(
        name: 'github',
        kind: McpTransportKind.http,
        url: 'https://h/mcp',
      );
      expect(fields(created, taken: {'github'}), ['name']);

      final edited = McpServerDraft.fromElement({
        'name': 'github',
        'type': 'http',
        'url': 'https://h/mcp',
      });
      expect(fields(edited, taken: {'github'}), isEmpty);
    });

    test('stdio без команды; http без URL, с другой схемой или без хоста', () {
      expect(fields(McpServerDraft(name: 'a', kind: McpTransportKind.stdio)), [
        'command',
      ]);
      for (final url in ['', 'ftp://h/mcp', 'mcp.test/mcp', 'https:///x']) {
        expect(
          fields(
            McpServerDraft(name: 'a', kind: McpTransportKind.http, url: url),
          ),
          ['url'],
          reason: url,
        );
      }
    });

    test('пустой ключ env или headers и пустое новое секретное значение', () {
      final draft = McpServerDraft(
        name: 'a',
        kind: McpTransportKind.http,
        url: 'https://h/mcp',
        headers: {
          '': McpValueDraft.text('x'),
          'Authorization': McpValueDraft.secret(SecretValue('')),
        },
      );

      expect(draft.validate().map((p) => p.field), [
        McpDraftField.headers,
        McpDraftField.headers,
      ]);
    });

    test('переименование при правке запрещено (originalName != name)', () {
      final renamed = McpServerDraft.fromElement({
        'name': 'github',
        'type': 'http',
        'url': 'https://h/mcp',
      }).copyWith(name: 'github2');

      final problems = renamed.validate();

      expect(problems.map((p) => p.field), [McpDraftField.name]);
      expect(
        problems.single.message,
        'Remove the server and add it again to rename it.',
      );
      expect(renamed.toEdits(), isEmpty);
    });

    test('правка без смены имени переименованием не считается', () {
      final same = McpServerDraft.fromElement({
        'name': 'github',
        'type': 'http',
        'url': 'https://h/mcp',
      }).copyWith(url: 'https://h2/mcp');

      expect(same.validate(), isEmpty);
    });

    test('коллизия имён секретов после нормализации forMcp — проблема '
        'таблицы', () {
      // `X Token` и `X-Token` дают один `codelab/mcp/a/x-token`.
      final draft = McpServerDraft(
        name: 'a',
        kind: McpTransportKind.http,
        url: 'https://h/mcp',
        headers: {
          'X Token': McpValueDraft.secret(SecretValue('one')),
          'X-Token': McpValueDraft.secret(SecretValue('two')),
        },
      );

      expect(draft.validate().map((p) => p.field), [McpDraftField.headers]);
      expect(draft.toEdits(), isEmpty);
    });

    test('новый секрет, совпавший по имени с хранимой ссылкой другого ключа '
        'той же таблицы, — коллизия', () {
      // `token` даёт `codelab/mcp/x/token`, а ключ `TOKEN` уже ссылается на
      // него же: запись нового значения затёрла бы чужой секрет.
      final draft = McpServerDraft(
        name: 'x',
        kind: McpTransportKind.stdio,
        command: 'srv',
        env: {
          'TOKEN': McpValueDraft.stored(r'${secret:codelab/mcp/x/token}'),
          'token': McpValueDraft.secret(SecretValue('new')),
        },
      );

      expect(draft.validate().map((p) => p.field), [McpDraftField.env]);
      expect(draft.toEdits(), isEmpty);
    });

    test('замена секрета под тем же ключом коллизией не считается', () {
      final draft = McpServerDraft(
        name: 'x',
        kind: McpTransportKind.stdio,
        command: 'srv',
        env: {'TOKEN': McpValueDraft.secret(SecretValue('new'))},
      );

      expect(draft.validate(), isEmpty);
    });

    test('неактивная таблица не проверяется', () {
      final draft = McpServerDraft(
        name: 'a',
        kind: McpTransportKind.http,
        url: 'https://h/mcp',
        env: {'': McpValueDraft.text('x')},
      );

      expect(draft.validate(), isEmpty);
    });

    test('корректный черновик проблем не имеет', () {
      expect(github().validate(existingNames: {'other'}), isEmpty);
    });
  });

  group('maskedValues и дубликаты ключей (ревью 5b)', () {
    // Набор ключей, которые список маскирует тем же правилом
    // (`mcp_masking.dart`); черновик хранит сырое значение.
    test('http: url с токеном в query и заголовок с литералом', () {
      final draft = McpServerDraft(
        name: 'gh',
        kind: McpTransportKind.http,
        url: 'https://mcp.test/mcp?token=$leak',
        headers: {
          'X-Workspace': McpValueDraft.text(leak),
          'X-Ref': McpValueDraft.text('\${TEAM}'),
          'Authorization': McpValueDraft.secret(SecretValue(leak)),
        },
      );

      expect(draft.maskedValues, {'url', 'headers.X-Workspace'});
      expect(draft.url, contains(leak), reason: 'сырое значение хранится');
      expect('${draft.maskedValues}', isNot(contains(leak)));
    });

    test('stdio: args и env по имени ключа', () {
      final draft = McpServerDraft(
        name: 'pg',
        kind: McpTransportKind.stdio,
        command: 'srv',
        args: ['--api-key', leak],
        env: {
          'API_TOKEN': McpValueDraft.text(leak),
          'LOG_LEVEL': McpValueDraft.text('debug'),
        },
      );

      expect(draft.maskedValues, {'args', 'env.API_TOKEN'});
    });

    test('обычный черновик: набор пуст', () {
      expect(
        McpServerDraft(
          name: 'a',
          kind: McpTransportKind.http,
          url: 'https://h/mcp',
        ).maskedValues,
        isEmpty,
      );
    });

    test('дубликат ключа после trim — проблема, а не молчаливое слияние', () {
      for (final field in ['env', 'headers']) {
        final table = {
          'TOKEN': McpValueDraft.text('a'),
          ' TOKEN ': McpValueDraft.text('b'),
        };
        final draft = field == 'env'
            ? McpServerDraft(
                name: 'a',
                kind: McpTransportKind.stdio,
                command: 'srv',
                env: table,
              )
            : McpServerDraft(
                name: 'a',
                kind: McpTransportKind.http,
                url: 'https://h/mcp',
                headers: table,
              );

        final problems = draft.validate();

        expect(problems, hasLength(1), reason: field);
        expect(
          problems.single.field,
          field == 'env' ? McpDraftField.env : McpDraftField.headers,
        );
      }
    });

    test('command с токеном маскируется тем же правилом, что в списке', () {
      final draft = McpServerDraft(
        name: 'gh',
        kind: McpTransportKind.stdio,
        command: '/usr/bin/srv --token=$leak',
      );

      expect(draft.maskedValues, contains('command'));
    });

    test('набор не зависит от активного типа: после переключения '
        'маскируется то же', () {
      final draft = McpServerDraft(
        name: 'gh',
        kind: McpTransportKind.http,
        url: 'https://mcp.test/mcp?token=$leak',
        command: 'srv',
        args: ['--api-key', leak],
        env: {'API_TOKEN': McpValueDraft.text(leak)},
        headers: {'X-Workspace': McpValueDraft.text(leak)},
      );

      final all = {'url', 'args', 'env.API_TOKEN', 'headers.X-Workspace'};
      expect(draft.maskedValues, all);
      expect(draft.copyWith(kind: McpTransportKind.stdio).maskedValues, all);
    });

    test('ключ с пробелами по краям — проблема черновика', () {
      final draft = McpServerDraft(
        name: 'a',
        kind: McpTransportKind.stdio,
        command: 'srv',
        env: {' TOKEN': McpValueDraft.text('a')},
      );

      final problems = draft.validate();

      expect(problems, hasLength(1));
      expect(problems.single.field, McpDraftField.env);
      expect(problems.single.message, 'Remove spaces around the name  TOKEN.');
    });
  });
}
