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
      // D2: стоп-слово `key` сравнивается с целым сегментом.
      'monkey_tokens': 5,
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
      // D2: `key` — стоп-слово, порядок частей имени не важен.
      'tokens_key': 1,
      'key_tokens': 1,
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

  group('a key-like name is redacted', () {
    // D1: три признака — последний сегмент `key`, `access[_-]?key`,
    // camelCase `…Key`.
    const names = [
      'OPENAI_KEY',
      'STRIPE_KEY',
      'ENCRYPTION_KEY',
      'SIGNING_KEY',
      'openai-key',
      'openaiKey',
      'signingKey',
      'subscriptionKey',
      'AWS_ACCESS_KEY_ID',
      'aws_access_key',
      'accessKeyId',
      'Ocp-Apim-Subscription-Key',
      'X-Functions-Key',
    ];
    for (final name in names) {
      test(name, () {
        expect(redactor.redact('sk-secret', key: name), redactedSecret);
      });
    }

    test('redactMap of a nested map hides the same values', () {
      expect(
        redactor.redactMap({
          'env': {for (final name in names) name: 'v'},
        }),
        {
          'env': {for (final name in names) name: redactedSecret},
        },
      );
    });
  });

  group('a key-like name that is not a secret stays visible', () {
    // Страж D1: зелёный до и после реализации.
    const names = [
      'key',
      'keyboard',
      'monkey',
      'turnkey',
      'hotkey',
      'keys',
      'key_count',
      'keyId',
      'KEY_ID',
      'signing_key_id',
    ];
    for (final name in names) {
      test(name, () {
        expect(redactor.redact('visible', key: name), 'visible');
      });
    }

    test('a settings key path under `key` stays visible', () {
      expect(
        redactor.redact('providers.openai.api_key', key: 'key'),
        'providers.openai.api_key',
      );
    });

    for (final text in ['keyboard=us', 'key_count=3', 'hotkey=ctrl+k']) {
      test('text "$text" is unchanged', () {
        expect(redactor.redactText(text), text);
      });
    }
  });

  group('an identifier under a key name is redacted by design', () {
    // D1: осознанная цена правила (Q4), а не дефект: отличить `cache_key`
    // от `signing_key` по имени нельзя.
    const names = [
      'cache_key',
      'primary_key',
      'idempotency_key',
      'public_key',
      'hotKey',
    ];
    for (final name in names) {
      test(name, () {
        expect(redactor.redact('id-1', key: name), redactedSecret);
      });
    }
  });

  group('a key assignment in text is redacted', () {
    const cases = <String, String>{
      'OPENAI_KEY=sk-1': 'OPENAI_KEY=$redactedSecret',
      'X-Functions-Key: abc': 'X-Functions-Key: $redactedSecret',
      'export AWS_ACCESS_KEY_ID=AKIA1':
          'export AWS_ACCESS_KEY_ID=$redactedSecret',
      'openaiKey: sk-2': 'openaiKey: $redactedSecret',
      // Страж прежнего поведения: значение несекретного имени не
      // поглощает вложенное присваивание (D3).
      'url=https://h/x?access_token=abc':
          'url=https://h/x?access_token=$redactedSecret',
      'token=foo=abc': 'token=$redactedSecret',
      'my_api_key=x': 'my_api_key=$redactedSecret',
    };
    for (final entry in cases.entries) {
      test(entry.key, () {
        expect(redactor.redactText(entry.key), entry.value);
      });
    }
  });

  group('URL userinfo is redacted', () {
    test('a string under a non-secret key', () {
      expect(
        redactor.redact(
          'postgres://user:pass@db.local:5432/app',
          key: 'DATABASE_URL',
        ),
        'postgres://$redactedSecret@db.local:5432/app',
      );
    });

    const hidden = <String, String>{
      'REDIS_DSN=redis://:pw@cache:6379/0':
          'REDIS_DSN=redis://$redactedSecret@cache:6379/0',
      'clone https://ghp_abc@github.com/org/repo.git':
          'clone https://$redactedSecret@github.com/org/repo.git',
      'mysql://u:p@ss@h/db': 'mysql://$redactedSecret@h/db',
      'ssh://git@host/repo': 'ssh://$redactedSecret@host/repo',
      // `\` — не граница: разбор по RFC 3986 (Python-агенты) видит здесь
      // userinfo `h\user:pass` (D4).
      r'https://h\user:pass@host/x': 'https://$redactedSecret@host/x',
    };
    for (final entry in hidden.entries) {
      test(entry.key, () {
        expect(redactor.redactText(entry.key), entry.value);
      });
    }

    const unchanged = [
      '{"url":"https://h","mail":"a@b.c"}',
      'https://example.com/a?u=a@b',
      'https://example.com/@user',
      'git@github.com:org/repo.git',
      'mailto:a@b.c',
      'https://example.com',
    ];
    for (final text in unchanged) {
      test('unchanged: $text', () {
        expect(redactor.redactText(text), text);
      });
    }

    test('is idempotent', () {
      const text = 'clone https://u:p@h/x and ssh://git@host/repo';
      final once = redactor.redactText(text);
      expect(redactor.redactText(once), once);
    });
  });

  group('masking is linear in input length', () {
    // D5: бюджет 2 с на строку. До 2.2 ожидаемо красные (квадратичный
    // ведущий префикс и хвост прежнего шаблона): `a`, `_key`, `access_key`,
    // `token`; остальные — стражи.
    final inputs = <String, String>{
      'a x 262144': 'a' * 262144,
      '_key x 65536': '_key' * 65536,
      'access_key x 26214': 'access_key' * 26214,
      'token x 52428': 'token' * 52428,
      '://  x 87381': '://' * 87381,
      'a:// + b x 262140': 'a://${'b' * 262140}',
      'x= x 131072': 'x=' * 131072,
      'OPENAI_KEY=v...': 'OPENAI_KEY=${'v' * 262133}',
      // D8: много `BEGIN` без `END` не должны сканировать текст до конца
      // каждое.
      'BEGIN x 8192': '-----BEGIN RSA PRIVATE KEY-----' * 8192,
    };
    for (final entry in inputs.entries) {
      test(entry.key, () {
        final watch = Stopwatch()..start();
        final result = redactor.redactText(entry.value);
        watch.stop();
        expect(
          watch.elapsed,
          lessThan(const Duration(seconds: 2)),
          reason: 'redactText on ${entry.key}',
        );
        if (entry.key == 'OPENAI_KEY=v...') {
          expect(result, 'OPENAI_KEY=$redactedSecret');
        }
      });
    }
  });

  group('a private key block is redacted', () {
    // D8 change `extend-secret-name-redaction`: блок без строки `END`
    // (вывод оборван или усечён) скрывается до конца текста.
    test('an unterminated block hides everything after BEGIN', () {
      expect(
        redactor.redactText(
          'out: -----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA\nabc',
        ),
        'out: $redactedSecret',
      );
    });

    test('a closed block is replaced and the tail stays visible', () {
      expect(
        redactor.redactText(
          'a -----BEGIN PRIVATE KEY-----\nMII\n-----END PRIVATE KEY----- b',
        ),
        'a $redactedSecret b',
      );
    });

    test('a closed block followed by an unterminated one', () {
      expect(
        redactor.redactText(
          '-----BEGIN PRIVATE KEY-----x-----END PRIVATE KEY----- mid '
          '-----BEGIN EC PRIVATE KEY-----\nleak',
        ),
        '$redactedSecret mid $redactedSecret',
      );
    });
  });
}
