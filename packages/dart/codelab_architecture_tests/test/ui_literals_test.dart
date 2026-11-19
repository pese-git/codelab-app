import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repo_root.dart';
import 'support/ui_literals.dart';

/// Тест литералов интерфейса (design.md change `add-desktop-localization`,
/// D10, R3/R8): в presentation desktop и в ките `codelab_ui` нет английских
/// строк мимо каталога ARB, кроме allowlist с причиной.
void main() {
  final root = repoRoot();
  final allowlistFile = File(
    p.join(
      root,
      'packages/dart/codelab_architecture_tests/test/support/'
      'ui_literals_allowlist.txt',
    ),
  );

  test('в presentation нет литералов интерфейса вне allowlist', () {
    final allow = parseAllowlist(allowlistFile.readAsStringSync()).keys;
    final violations = [
      for (final l in scanUiLiterals(root))
        if (!allow.contains(uiLiteralKey(l)))
          "${l.file}:${l.line} -> '${l.literal}'",
    ];
    expect(
      violations,
      isEmpty,
      reason:
          '${violations.length} литералов вне каталога ARB. Вынесите их в '
          'ARB (`context.l10n`) или добавьте в ui_literals_allowlist.txt '
          'с причиной:\n${violations.join('\n')}',
    );
  });

  test('allowlist: у каждой записи есть причина и запись жива', () {
    final parsed = parseAllowlist(allowlistFile.readAsStringSync());
    final live = {for (final l in scanUiLiterals(root)) uiLiteralKey(l)};
    expect(
      parsed.withoutReason,
      isEmpty,
      reason: 'записи без причины:\n${parsed.withoutReason.join('\n')}',
    );
    final dead = parsed.keys.where((k) => !live.contains(k)).toList();
    expect(dead, isEmpty, reason: 'в коде записей нет:\n${dead.join('\n')}');
  });

  group('сканер', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('literals_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    List<UiLiteral> scanFiles(Map<String, String> files) {
      files.forEach((path, source) {
        File(p.join(tmp.path, 'apps/codelab_desktop/lib/features', path))
          ..createSync(recursive: true)
          ..writeAsStringSync(source);
      });
      return scanUiLiterals(tmp.path);
    }

    test('находит Text, CodeLabText и именованные позиции', () {
      final found = scanFiles({
        'a/presentation/page.dart': '''
final w = [
  const Text('Hello'),
  CodeLabText(
    "Wait",
  ),
  Tip(label: 'Save', tooltip: 'Close it'),
  Info(title: 'T', message: 'Failed', placeholder: 'Type', content: Text('C')),
];
''',
      });

      expect(found.map((l) => l.literal), [
        'Hello',
        'Wait',
        'Save',
        'Close it',
        'T',
        'Failed',
        'Type',
        'C',
      ]);
    });

    test('игнорирует интерполяцию, идентификаторы, комментарии', () {
      final found = scanFiles({
        'a/presentation/page.dart': r'''
// Text('In comment')
final w = [
  Text('$count items'),
  Text(l10n.save),
  Tip(label: '123'),
  Tip(label: name),
];
''',
      });

      expect(found, isEmpty);
    });

    test('пропускает previews и l10n', () {
      final found = scanFiles({
        'a/presentation/x_previews.dart': "final w = Text('Preview');\n",
        'a/l10n/x.dart': "final w = Text('Catalog');\n",
      });

      expect(found, isEmpty);
    });
  });

  test('parseAllowlist: комментарии, причина обязательна', () {
    final parsed = parseAllowlist('''
# коммент
a.dart | Foo | имя собственное
b.dart | Bar |
''');

    expect(parsed.keys, {'a.dart|Foo'});
    expect(parsed.withoutReason, ['b.dart | Bar |']);
  });
}
