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
    _tree.put('a.json', _marker);

    expect(_scan({'FOO_PATH': _marker, 'HOME': _marker}), isEmpty);
  });

  test('чистый каталог не даёт сообщений', () {
    _tree.put('a.json', 'clean');

    expect(_scan({'FOO_TOKEN': _marker}), isEmpty);
  });
}
