import 'package:codelab_agent_core/src/tools/glob.dart';
import 'package:test/test.dart';

void main() {
  // Таблица синтаксиса glob инструмента search (§6.4, шаг 3).
  final table = <(String glob, String path, bool matches)>[
    ('*.dart', 'a.dart', true),
    ('*.dart', 'lib/a.dart', true), // glob без `/` сравнивается с именем
    ('*.dart', 'a.dart.bak', false),
    ('lib/*.dart', 'lib/a.dart', true),
    ('lib/*.dart', 'lib/src/a.dart', false), // `*` не проходит `/`
    ('**/*.dart', 'a.dart', true), // `**/` соответствует пустой строке
    ('**/*.dart', 'lib/src/a.dart', true),
    ('lib/**', 'lib/src/a.dart', true),
    ('lib/**/a.dart', 'lib/a.dart', true),
    ('lib/**/a.dart', 'lib/x/y/a.dart', true),
    ('a?.txt', 'ab.txt', true),
    ('a?.txt', 'a/.txt', false), // `?` не соответствует `/`
    ('*.{dart,yaml}', 'pubspec.yaml', true),
    ('*.{dart,yaml}', 'README.md', false),
    ('{lib,test}/**/*.dart', 'test/a_test.dart', true),
    ('{lib,test}/**/*.dart', 'tool/a.dart', false),
    ('[abc].txt', 'b.txt', true),
    ('[abc].txt', 'd.txt', false),
    ('[!abc].txt', 'd.txt', true),
    ('file(1).txt', 'file(1).txt', true), // символы regex экранируются
    ('a+b.txt', 'aab.txt', false),
  ];

  for (final (glob, path, matches) in table) {
    test('"$glob" ${matches ? 'matches' : 'does not match'} "$path"', () {
      expect(Glob(glob).matches(path), matches);
    });
  }

  test('an unclosed brace or bracket is taken literally', () {
    expect(Glob('{a').matches('{a'), isTrue);
    expect(Glob('[a').matches('[a'), isTrue);
  });
}
