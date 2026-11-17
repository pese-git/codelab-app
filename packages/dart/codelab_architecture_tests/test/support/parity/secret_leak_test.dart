// Тест проверки утечки секретов окружения в отчёты (задача 1.7 change
// `switch-default-agent-to-dart`; testing-quality «Секрет окружения в отчёте»;
// design.md, D16). Маркер утечки — вымышленный `sk-test-leak-0123456789`.

import 'dart:io';

import 'package:test/test.dart';

import 'parity_test_kit.dart';
import 'reports.dart';

const _marker = 'sk-test-leak-0123456789';

late Tree _tree;

List<String> _scan(Map<String, String> env) =>
    findSecretLeaks(resultsDir: Directory(_tree.path), environment: env);

void main() {
  setUp(() => _tree = Tree('parity_leak_'));
  tearDown(() => _tree.dispose());

  test(
    'Секрет окружения в отчёте: сообщение называет файл, но не значение',
    () {
      _tree.put('dart/leaky.json', 'print: token is $_marker end\n');
      _tree.put('dart/clean.json', 'nothing here\n');

      final leaks = _scan({'FOO_TOKEN': _marker});

      expect(leaks, hasLength(1));
      expect(leaks.single, contains('leaky.json'));
      expect(leaks.single, isNot(contains(_marker)));
    },
  );

  test('проверяются суффиксы _TOKEN, _KEY и _SECRET', () {
    _tree.put('a.json', '$_marker-1 $_marker-2 $_marker-3');

    final leaks = _scan({
      'A_TOKEN': '$_marker-1',
      'B_KEY': '$_marker-2',
      'C_SECRET': '$_marker-3',
    });

    expect(leaks, hasLength(3));
    expect(leaks.join('\n'), isNot(contains(_marker)));
  });

  test('значения короче 8 символов не проверяются', () {
    _tree.put('a.json', 'short1234567 abc');

    expect(_scan({'FOO_TOKEN': 'abc', 'BAR_KEY': '1234567'}), isEmpty);
  });

  test('значение ровно из 8 символов проверяется', () {
    _tree.put('a.json', 'xx 12345678 xx');

    expect(_scan({'FOO_TOKEN': '12345678'}), hasLength(1));
  });

  test('переменные с другими именами не проверяются', () {
    _tree.put('a.json', 'plain-value-12345');

    expect(
      _scan({'FOO_PATH': 'plain-value-12345', 'HOME': 'plain-value-12345'}),
      isEmpty,
    );
  });

  test('чистый каталог не даёт сообщений', () {
    _tree.put('a.json', 'clean');

    expect(_scan({'FOO_TOKEN': _marker}), isEmpty);
  });

  test('маркер без секретов окружения в отчётах CI — предупреждение', () {
    _tree.put('a.json', 'x $_marker y');
    final warnings = <String>[];

    final leaks = findSecretLeaks(
      resultsDir: Directory(_tree.path),
      environment: const {},
      warnings: warnings,
    );

    expect(leaks, isEmpty);
    expect(warnings, hasLength(1));
    expect(warnings.single, contains('a.json'));
    expect(warnings.single, isNot(contains(_marker)));
  });

  test('маркер в отчётах app (checkHomePaths) — утечка', () {
    _tree.put('a.json', 'x $_marker y');

    final leaks = findSecretLeaks(
      resultsDir: Directory(_tree.path),
      environment: const {},
      checkHomePaths: true,
    );

    expect(leaks, hasLength(1));
    expect(leaks.single, contains('a.json'));
    expect(leaks.single, isNot(contains(_marker)));
  });

  test('символическая ссылка в каталоге отчётов — ошибка', () {
    _tree.put('real.json', 'clean');
    Link('${_tree.path}/link.json').createSync('${_tree.path}/real.json');

    final leaks = _scan(const {});

    expect(leaks, hasLength(1));
    expect(leaks.single, contains('link.json'));
  });

  test('ищутся JSON- и XML-экранированные формы значения', () {
    const value = 'tok"en&<1234>';
    _tree.put('a.json', r'{"m":"tok\"en&<1234>"}');
    _tree.put('b.xml', '<x a="tok&quot;en&amp;&lt;1234&gt;"/>');
    _tree.put('c.json', 'clean');

    final leaks = _scan({'FOO_TOKEN': value});

    expect(leaks, hasLength(2));
    expect(leaks.join(), allOf(contains('a.json'), contains('b.xml')));
  });

  test('имена секретов: регистр и расширенный перечень', () {
    for (final name in [
      'db_password',
      'DB_PASS',
      'GH_PAT',
      'AWS_CREDENTIALS',
      'MY_CREDENTIAL',
      'SERVICE_AUTH',
      'AUTH',
      'Api_Key',
    ]) {
      _tree.put('$name.json', 'v $_marker-$name v');
    }
    final env = {
      for (final n in [
        'db_password',
        'DB_PASS',
        'GH_PAT',
        'AWS_CREDENTIALS',
        'MY_CREDENTIAL',
        'SERVICE_AUTH',
        'AUTH',
        'Api_Key',
      ])
        n: '$_marker-$n',
    };

    final leaks = findSecretLeaks(
      resultsDir: Directory(_tree.path),
      environment: env,
    );

    // Файл name.json содержит значение своей переменной; значения
    // остальных переменных в нём нет, а маркер-префикс даёт ещё по одной
    // записи на файл, поэтому проверяем именно значения по именам.
    for (final name in env.keys) {
      expect(
        leaks.where((l) => l.contains('of $name')),
        isNotEmpty,
        reason: name,
      );
    }
  });

  test('следы домашнего каталога ищутся только по флагу', () {
    _tree.put('a.json', '{"path":"/Users/ivan/work/x_test.dart"}');
    _tree.put('b.json', '{"path":"/home/dev/work/x_test.dart"}');
    _tree.put('c.json', 'HOME=/opt/me/dir');

    expect(_scan(const {'HOME': '/opt/me/dir'}), isEmpty);

    final leaks = findSecretLeaks(
      resultsDir: Directory(_tree.path),
      environment: const {'HOME': '/opt/me/dir'},
      checkHomePaths: true,
    );

    expect(leaks, hasLength(3));
    expect(leaks.join(), isNot(contains('ivan')));
    expect(leaks.join(), isNot(contains('/opt/me/dir')));
  });
}
