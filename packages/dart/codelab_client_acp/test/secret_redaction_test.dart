// Числовые счётчики токенов в `SecretRedactor` (задача 2.21 change
// `add-subagents-and-tasks`; design.md, D41 п. 7; approval-safety
// «Редактирование секретов»).
//
// Красные тесты: сейчас любое поле с `token` в имени скрывается, поэтому
// `tokens_in: 900` превращается в `<redacted>`, а должно остаться видимым.
// Строки под теми же именами и любые значения под именами секретов
// (`token`, `access_token`, `session_token`, `api_key`) по-прежнему скрыты.

import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:test/test.dart';

void main() {
  const redactor = SecretRedactor();

  group('a token counter stays visible', () {
    const visible = <String, Object?>{
      'tokens': 1200,
      'tokens_in': 900,
      'tokens_out': 300,
      'tokens_before': 4000,
      'input_tokens': 55,
      'max_output_tokens': 4096,
      'Tokens-In': 7,
      // Стоп-слово сравнивается с целым сегментом, а не с подстрокой:
      // `hidden` содержит `id`, `spinning` — `pin`, но это не учётные данные.
      'hidden_tokens': 12,
      'tokens_spinning': 3,
    };
    for (final entry in visible.entries) {
      test('${entry.key}: ${entry.value}', () {
        expect(redactor.redact(entry.value, key: entry.key), entry.value);
      });
    }

    test('redactMap of a nested map keeps the numbers', () {
      expect(
        redactor.redactMap({
          'usage': {'tokens_in': 900, 'tokens_out': 300},
        }),
        {
          'usage': {'tokens_in': 900, 'tokens_out': 300},
        },
      );
    });
  });

  group('a secret under a similar name is redacted', () {
    const hidden = <String, Object?>{
      'tokens': 'abc123',
      'tokens_in': 'sk-abc',
      'input_tokens': 'sk-abc',
      'token': 123,
      'access_token': 5,
      'session_token': 's',
      'api_key': 42,
      // Число под именем с секретным словом и частью `tokens` — не счётчик.
      'secret_tokens': 1,
      'tokens_api_key': 1,
      'auth_tokens': 1,
      'password_tokens': 1,
      'session_tokens': 1,
      // Стоп-слова учётных данных как отдельный сегмент (D41 п. 7).
      'access_tokens': 1,
      'refresh_tokens': 1,
      'id_tokens': 1,
      'csrf_tokens': 1,
      'otp_tokens': 1,
      'pin_tokens': 1,
      'tokens_session': 1,
      'session__tokens': 1,
      'Access-Tokens': 1,
    };
    for (final entry in hidden.entries) {
      test('${entry.key}: ${entry.value}', () {
        expect(redactor.redact(entry.value, key: entry.key), redactedSecret);
      });
    }

    test('redactMap of a nested map hides the same values', () {
      expect(
        redactor.redactMap({
          'usage': {'tokens': 'abc123', 'token': 123, 'tokens_in': 900},
        }),
        {
          'usage': {
            'tokens': redactedSecret,
            'token': redactedSecret,
            'tokens_in': 900,
          },
        },
      );
    });

    test('text "tokens_in=sk-abc" hides the value', () {
      expect(
        redactor.redactText('tokens_in=sk-abc'),
        'tokens_in=$redactedSecret',
      );
    });
  });

  // Пара `{name, value}` (задача 1.1 `[client]` change `redesign-protocol-pane`;
  // design.md, D4; approval-safety «Секрет в паре name/value»).
  //
  // Красные тесты: `HttpHeader` и `EnvVariable` ACP несут секрет не под
  // ключом, а в значении `value` при секретном `name`; сейчас редактор
  // смотрит только на ключ `value` и значение остаётся открытым.
  group('a name/value pair with a secret name', () {
    Map<String, Object?> pair(String name, String value) => {
      'name': name,
      'value': value,
    };

    for (final name in const [
      'Authorization',
      'GITHUB_TOKEN',
      'OPENAI_API_KEY',
      'X-Api-Key',
    ]) {
      test('$name: value is hidden, name is kept', () {
        expect(redactor.redact(pair(name, 'ghp_abc123')), {
          'name': name,
          'value': redactedSecret,
        });
      });
    }

    test('an ordinary variable stays visible', () {
      expect(redactor.redact(pair('PATH', '/usr/bin')), {
        'name': 'PATH',
        'value': '/usr/bin',
      });
    });

    test('a token counter name is not a secret name', () {
      // Исключение счётчиков токенов то же, что у правила по ключу (D4).
      expect(redactor.redact(pair('tokens_in', '900')), {
        'name': 'tokens_in',
        'value': '900',
      });
    });

    test('other fields of the pair object are processed as before', () {
      expect(
        redactor.redact({
          'name': 'Authorization',
          'value': 'ghp_abc123',
          'description': 'plain text',
          'api_key': 'sk-1',
        }),
        {
          'name': 'Authorization',
          'value': redactedSecret,
          'description': 'plain text',
          'api_key': redactedSecret,
        },
      );
    });

    test('nested headers and env arrays of params.mcpServers', () {
      final redacted = redactor.redactMap({
        'method': 'session/new',
        'params': {
          'cwd': '/workspace',
          'mcpServers': [
            {
              'type': 'http',
              'name': 'github',
              'url': 'https://example.test/mcp',
              'headers': [
                pair('Authorization', 'Bearer ghp_abc123'),
                pair('Accept', 'application/json'),
              ],
            },
            {
              'name': 'local',
              'command': '/usr/bin/server',
              'args': ['--stdio'],
              'env': [
                pair('GITHUB_TOKEN', 'abc'),
                pair('OPENAI_API_KEY', 'sk-1'),
                pair('PATH', '/usr/bin'),
              ],
            },
          ],
        },
      });

      final servers = (redacted['params']! as Map)['mcpServers']! as List;
      final http = servers[0] as Map;
      final stdio = servers[1] as Map;
      expect(http['name'], 'github');
      expect(http['headers'], [
        {'name': 'Authorization', 'value': redactedSecret},
        {'name': 'Accept', 'value': 'application/json'},
      ]);
      expect(stdio['env'], [
        {'name': 'GITHUB_TOKEN', 'value': redactedSecret},
        {'name': 'OPENAI_API_KEY', 'value': redactedSecret},
        {'name': 'PATH', 'value': '/usr/bin'},
      ]);
    });
  });
}
