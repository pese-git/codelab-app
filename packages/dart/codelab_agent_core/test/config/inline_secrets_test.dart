import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

// Заведомо фиктивные значения в формате шаблонов §12.4 (не настоящие ключи).
const _skProj = 'sk-proj-AbCdEfGhIjKlMnOpQrStUvWx';
const _github = 'ghp_abcdefghijklmnopqrstuvwxyz0123456789';
const _aws = 'AKIAABCDEFGHIJKLMNOP';
const _google = 'AIzaAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'; // AIza + 35
const _slack = 'xoxb-1234567890-abcdefghij';
const _jwt =
    'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcdefghijklmnop';

/// Распознавание литеральных секретов конфига (agent-configuration
/// «Литеральные секреты в файле конфига»; design.md change
/// `add-config-literal-secrets-and-migrate`, D3; задача 1.1, находки №8, №10).
/// Шаблоны написаны по §12.4 документа ядра и публичным описаниям форматов.
void main() {
  group('literalSecretTag: patterns', () {
    final positives = <String, String>{
      'sk': _skProj,
      'sk (plain)': 'sk-${'A1b2C3d4E5f6G7h8I9j0'}K',
      'github': _github,
      'github (fine-grained)': 'github_pat_${'A' * 60}',
      'aws': _aws,
      'google': _google,
      'slack': _slack,
      'jwt': _jwt,
      'bearer': 'Bearer abcdefghijkl',
      'private-key': '-----BEGIN RSA PRIVATE KEY-----\nMIIB\n',
      'assignment': 'API_KEY=abcdefgh12345678',
      'assignment (colon, quoted)': 'password: "hunter2hunter2"',
      'connection-string': 'postgres://app:s3cretpw@localhost/db',
    };
    const expectedTag = {
      'sk': 'sk',
      'sk (plain)': 'sk',
      'github': 'github',
      'github (fine-grained)': 'github',
      'aws': 'aws',
      'google': 'google',
      'slack': 'slack',
      'jwt': 'jwt',
      'bearer': 'bearer',
      'private-key': 'private-key',
      'assignment': 'assignment',
      'assignment (colon, quoted)': 'assignment',
      'connection-string': 'connection-string',
    };
    for (final MapEntry(:key, :value) in positives.entries) {
      test('$key: matched, the tag is a short label', () {
        final tag = literalSecretTag(value);
        expect(tag, expectedTag[key]);
        expect(tag, matches(RegExp(r'^[a-z]+(-[a-z]+)*$')), reason: 'a label');
      });
    }

    for (final value in [
      'task-list', // `sk-` внутри слова: нет границы слова
      'sk-test-secret-123', // после префикса меньше 20 символов
      'sk-Test Secret',
      'https://example.com/path',
      'X-Team',
      'ghp_short',
      'Bearer short',
      'postgres://localhost/db', // без пароля
      'postgres://user@localhost/db', // userinfo без пароля
      'token = ',
      'MAX_TOKENS=4096', // меньше 8 символов в значении
      '',
    ]) {
      test('negative: "$value"', () {
        expect(literalSecretTag(value), isNull);
      });
    }
  });

  group('literalSecretTag: literal parts between substitutions', () {
    test('a reference next to a scheme prefix is not a secret', () {
      expect(literalSecretTag(r'Bearer ${secret:codelab/mcp/gh/x}'), isNull);
      expect(literalSecretTag(r'${X}'), isNull);
      expect(literalSecretTag(r'${secret:codelab/x}'), isNull);
    });

    test('a mixed value: the literal part is found (R1-1)', () {
      expect(literalSecretTag('Bearer $_github \${X}'), 'github');
      expect(literalSecretTag('\${X} $_skProj'), 'sk');
    });

    test('a substitution does not glue two short literals into a match', () {
      // `sk-` + `AAAA…` порознь не секрет; склейка через подстановку дала бы
      // ложное совпадение.
      expect(literalSecretTag(r'sk-${X}AAAAAAAAAAAAAAAAAAAAAAAAAAAA'), isNull);
    });

    test('a DSN with a password split by a substitution (L5)', () {
      expect(
        literalSecretTag(r'postgres://app:pw-lit${SUFFIX}@localhost/db'),
        'connection-string',
      );
      expect(
        literalSecretTag(r'postgres://app:${PW}@localhost/db'),
        isNull,
        reason: 'the password is one substitution',
      );
      expect(literalSecretTag(r'postgres://app:${A}${B}@localhost/db'), isNull);
    });

    test('an escaped \$\${ is literal text, not a substitution', () {
      // `$${` после раскрытия — литерал `${`; сам он секретом не является.
      expect(literalSecretTag(r'$${X}'), isNull);
    });
  });

  group('literalSecretTag: built-in allowlist', () {
    test('a git sha and a uuid as the value are not secrets', () {
      expect(literalSecretTag('API_KEY=${'a1' * 20}'), isNull);
      expect(literalSecretTag('TOKEN=${'0f' * 32}'), isNull);
      expect(
        literalSecretTag('TOKEN=123e4567-e89b-12d3-a456-426614174000'),
        isNull,
      );
    });

    test('a value that only starts like a sha is still a secret', () {
      expect(literalSecretTag('API_KEY=${'a1' * 20}zz'), 'assignment');
    });
  });

  group('literalSecretTag: hostile input', () {
    final stopwatch = Stopwatch();
    final mebibyte = 1 << 20;

    for (final MapEntry(:key, :value) in <String, String>{
      // Много «ключей присваивания» без значения и длинные идентификаторы.
      'assignment: long identifier': 'A' * mebibyte,
      'assignment: repeated names': 'TOKEN ' * (mebibyte ~/ 6),
      'assignment: names without separator': 'a_api_key_b ' * (mebibyte ~/ 12),
      'assignment: spaces after a name': 'TOKEN${' ' * mebibyte}',
      'jwt-like runs': 'eyJ-' * (mebibyte ~/ 4),
      'jwt-like runs with one anchor': '${'eyJ-' * (mebibyte ~/ 4)}.eyJ',
      'jwt anchors': '.eyJ' * (mebibyte ~/ 4),
      'pem-like markers': '-----BEGIN PRIVATE KEY-----' * (mebibyte ~/ 27),
      'url-like': 'a://b:' * (mebibyte ~/ 6),
    }.entries) {
      // 2 с — с большим запасом на медленный CI: измеренное время ~0,1 с, а
      // квадратичный перебор давал минуты.
      test('1 MiB "$key" is checked in under 2 s', () {
        stopwatch
          ..reset()
          ..start();
        literalSecretTag(value);
        stopwatch.stop();
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      });
    }
  });

  group('names (L3)', () {
    test('sk- counts in a name only at its start', () {
      expect(
        literalSecretTag('codelab/sk-anthropic-production-key', asName: true),
        isNull,
      );
      expect(literalSecretTag(_skProj, asName: true), 'sk');
      expect(literalSecretTag(_github, asName: true), 'github');
    });
  });

  group('hasInlineSecret', () {
    test('literal parts and tokens written as names', () {
      expect(hasInlineSecret('Bearer $_github'), isTrue);
      expect(hasInlineSecret('Bearer $_github \${X}'), isTrue);
      expect(hasInlineSecret('Bearer \${secret:$_github}'), isTrue);
      expect(hasInlineSecret('\${$_github}'), isTrue);
    });

    test('references and plain values are not secrets', () {
      expect(hasInlineSecret(r'${KEY}'), isFalse);
      expect(hasInlineSecret(r'Bearer ${secret:codelab/p}'), isFalse);
      expect(hasInlineSecret('blue'), isFalse);
    });
  });

  group('findInlineSecrets: more shapes', () {
    InlineSecretFinding envOnly(String value) => findInlineSecrets(
      layer({
        'mcp': {
          'servers': [
            {
              'name': 'db',
              'type': 'stdio',
              'command': 'x',
              'env': {'V': value},
            },
          ],
        },
      }),
    ).single;

    test('a PEM block: the span reaches the END marker (4)', () {
      const pem =
          '-----BEGIN RSA PRIVATE KEY-----\nMIIBVgIBADAN\n-----END RSA PRIVATE KEY-----';
      final value = 'x $pem tail';
      final finding = envOnly(value);
      expect(finding.tag, 'private-key');
      final (start, end) = finding.spans.single;
      expect(value.substring(start, end), pem);
    });

    test('a PEM block without END: the span reaches the end of the value', () {
      const value = 'k -----BEGIN PRIVATE KEY-----\nMIIBVgIBADAN';
      final (start, end) = envOnly(value).spans.single;
      expect(end, value.length);
      expect(value.substring(start, start + 5), '-----');
    });

    test('a token written as a variable name \${ghp_…} is a referenceName '
        '(6)', () {
      final value = 'Bearer \${$_github}';
      final finding = envOnly(value);
      expect(finding.kind, InlineSecretKind.referenceName);
      expect(finding.tag, 'github');
      final (start, end) = finding.spans.single;
      expect(value.substring(start, end), _github);
    });

    test('many matches: spans are capped and flagged, and it is fast', () {
      final value = 'AKIAABCDEFGHIJKLMNOP ' * 50000;
      final stopwatch = Stopwatch()..start();
      final finding = envOnly(value);
      stopwatch.stop();
      expect(finding.spans.length, lessThanOrEqualTo(64));
      expect(finding.spansTruncated, isTrue);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    });

    test('api_key as a reference is not a finding (R8-8)', () {
      for (final ref in [r'${OPENAI_KEY}', r'${secret:codelab/p}']) {
        expect(
          findInlineSecrets(
            layer({
              'providers': {
                'p': {'api_key': ref},
              },
            }),
          ),
          isEmpty,
          reason: ref,
        );
      }
    });

    test('api_key mixing a literal and a reference stays a finding', () {
      final finding = findInlineSecrets(
        layer({
          'providers': {
            'p': {'api_key': '$_skProj \${X}'},
          },
        }),
      ).single;
      expect(finding.keyPath, 'providers.p.api_key');
      expect(finding.kind, InlineSecretKind.literalPart);
    });
  });

  group('findInlineSecrets', () {
    InlineSecretFinding only(Map<String, Object?> values) =>
        findInlineSecrets(layer(values)).single;

    test('provider api_key: inlineKey with the provider secret name', () {
      final finding = only({
        'providers': {
          'openai': {'kind': 'openai-compatible', 'api_key': _skProj},
        },
      });
      expect(finding.keyPath, 'providers.openai.api_key');
      expect(finding.kind, InlineSecretKind.inlineKey);
      expect(finding.tag, 'inline-key');
      expect(finding.suggestedSecretName, 'codelab/openai');
    });

    test('the key is a finding whatever the value looks like (CFG-9 p.1)', () {
      final finding = only({
        'providers': {
          'p': {'api_key': 'sk-test-secret-123'},
        },
      });
      expect(finding.kind, InlineSecretKind.inlineKey);
    });

    test('an empty literal key is not a secret', () {
      expect(
        findInlineSecrets(
          layer({
            'providers': {
              'p': {'api_key': ''},
            },
          }),
        ),
        isEmpty,
      );
    });

    test('every inlineSecretKeys name at a provider and at a server', () {
      final findings = findInlineSecrets(
        layer({
          'providers': {
            'p': {for (final key in inlineSecretKeys) key: 'value-$key'},
          },
          'mcp': {
            'servers': [
              {
                'name': 'gh',
                'type': 'http',
                'url': 'https://gh.test/mcp',
                for (final key in inlineSecretKeys) key: 'value-$key',
              },
            ],
          },
        }),
      );
      expect(
        findings.map((f) => f.keyPath),
        unorderedEquals([
          for (final key in inlineSecretKeys) 'providers.p.$key',
          for (final key in inlineSecretKeys) 'mcp.servers[gh].$key',
        ]),
      );
      expect(
        findings
            .where((f) => f.keyPath.startsWith('mcp'))
            .map((f) => f.suggestedSecretName),
        everyElement(startsWith('codelab/mcp/gh/')),
      );
    });

    test('a mixed header: literalPart with the span of the token (R1-1)', () {
      final value = 'Bearer $_github \${X}';
      final finding = only({
        'mcp': {
          'servers': [
            {
              'name': 'gh',
              'type': 'http',
              'url': 'https://gh.test/mcp',
              'headers': {'Authorization': value},
            },
          ],
        },
      });
      expect(finding.keyPath, 'mcp.servers[gh].headers.Authorization');
      expect(finding.kind, InlineSecretKind.literalPart);
      expect(finding.tag, 'github');
      expect(finding.suggestedSecretName, 'codelab/mcp/gh/authorization');
      expect(finding.spans, [(7, 7 + _github.length)]);
      expect(value.substring(7, 7 + _github.length), _github);
    });

    test('env of a server and headers of a provider are covered', () {
      final findings = findInlineSecrets(
        layer({
          'providers': {
            'gw': {
              'headers': {'X-Api-Key': _skProj, 'X-Team': 'blue'},
            },
          },
          'mcp': {
            'servers': [
              {
                'name': 'db',
                'type': 'stdio',
                'command': 'db-mcp',
                'env': {'GITHUB_TOKEN': _github, 'LOG': 'debug'},
              },
            ],
          },
        }),
      );
      expect(findings.map((f) => f.keyPath), [
        'providers.gw.headers.X-Api-Key',
        'mcp.servers[db].env.GITHUB_TOKEN',
      ]);
      expect(findings.last.suggestedSecretName, 'codelab/mcp/db/github_token');
    });

    test('a DSN cut by a substitution: spans cover the literal password '
        'chunk only (L5)', () {
      const value = r'postgres://app:pw-lit${SUFFIX}@localhost/db';
      final finding = only({
        'mcp': {
          'servers': [
            {
              'name': 'db',
              'type': 'stdio',
              'command': 'db-mcp',
              'env': {'DATABASE_URL': value},
            },
          ],
        },
      });
      expect(finding.tag, 'connection-string');
      expect(finding.spans, hasLength(1));
      final (start, end) = finding.spans.single;
      expect(value.substring(start, end), 'pw-lit');
    });

    test('a pure substitution password is not a finding', () {
      expect(
        findInlineSecrets(
          layer({
            'mcp': {
              'servers': [
                {
                  'name': 'db2',
                  'type': 'stdio',
                  'command': 'db-mcp',
                  'env': {'DATABASE_URL': r'postgres://app:${PW}@localhost/db'},
                },
              ],
            },
          }),
        ),
        isEmpty,
      );
    });

    test('url and base_url with userinfo are not recognised (L5)', () {
      expect(
        findInlineSecrets(
          layer({
            'providers': {
              'gw': {'base_url': 'https://u:s3cretpw@llm.test/v1'},
            },
            'mcp': {
              'servers': [
                {
                  'name': 'h',
                  'type': 'http',
                  'url': 'https://u:s3cretpw@gh.test/mcp',
                },
              ],
            },
          }),
        ),
        isEmpty,
      );
    });

    test('references and plain values are not findings', () {
      expect(
        findInlineSecrets(
          layer({
            'providers': {
              'p': {
                'api_key_secret': 'codelab/p',
                'api_key_env': 'OPENAI_API_KEY',
                'headers': {
                  'Authorization': r'Bearer ${secret:codelab/p/auth}',
                  'X-Org': r'${ORG}',
                },
              },
            },
          }),
        ),
        isEmpty,
      );
    });

    test('api_key_env and api_key_secret: a name that matches a pattern is a '
        'nameLiteral (CFG-9 p.3); one that does not is not', () {
      final findings = findInlineSecrets(
        layer({
          'providers': {
            'a': {'api_key_env': 'sk-test-secret-123'}, // не по шаблону
            'b': {'api_key_env': _skProj},
            'c': {'api_key_secret': 'sk-Test Secret'}, // не по шаблону
            'd': {'api_key_secret': _github},
          },
        }),
      );
      expect(findings.map((f) => (f.keyPath, f.kind, f.tag)), [
        ('providers.b.api_key_env', InlineSecretKind.nameLiteral, 'sk'),
        ('providers.d.api_key_secret', InlineSecretKind.nameLiteral, 'github'),
      ]);
      expect(findings.first.suggestedSecretName, 'codelab/b');
    });

    test('${r'${secret:<literal>}'}: referenceName with the span of the '
        'literal name', () {
      final value = 'Bearer \${secret:$_github}';
      final finding = only({
        'mcp': {
          'servers': [
            {
              'name': 'gh',
              'type': 'http',
              'url': 'https://gh.test/mcp',
              'headers': {'Authorization': value},
            },
          ],
        },
      });
      expect(finding.kind, InlineSecretKind.referenceName);
      expect(finding.tag, 'github');
      expect(
        value.substring(finding.spans.single.$1, finding.spans.single.$2),
        _github,
      );
    });

    test('a disabled server is covered: findings are per layer', () {
      final findings = findInlineSecrets(
        layer({
          'mcp': {
            'servers': [
              {
                'name': 'off',
                'type': 'http',
                'url': 'https://gh.test/mcp',
                'enabled': false,
                'headers': {'Authorization': 'Bearer $_github'},
              },
            ],
          },
        }),
      );
      expect(findings, hasLength(1));
    });

    test('findings and their text carry no part of the value', () {
      final findings = findInlineSecrets(
        layer({
          'providers': {
            'p': {
              'api_key': _skProj,
              'api_key_env': _github,
              'headers': {'Authorization': 'Bearer $_slack'},
            },
          },
        }),
      );
      expect(findings, hasLength(3));
      for (final finding in findings) {
        final text = [
          finding.keyPath,
          finding.tag,
          finding.suggestedSecretName,
          '${finding.kind}',
        ].join(' ');
        for (final secret in [_skProj, _github, _slack]) {
          expect(text, isNot(contains(secret)));
          expect(text, isNot(contains(secret.substring(0, 12))));
        }
      }
    });
  });
}
