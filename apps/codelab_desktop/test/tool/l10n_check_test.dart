// Красные тесты скрипта `l10n:check` (задача 1.7 change
// `add-desktop-localization`; spec workspace-architecture «Устаревший
// сгенерированный код»; design.md D3).
//
// Скрипт `tool/l10n_check.dart` перегенерирует каталоги во временный каталог и
// сравнивает с рабочими файлами. Тест гоняет его на временной копии пакета:
// рабочее дерево не меняется. Тест медленный (запускает `flutter gen-l10n`),
// поэтому живёт отдельным файлом.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Копия каталога локализации пакета app: `pubspec.yaml`, `l10n.yaml`,
/// `lib/l10n/`. Всё остальное скрипту для генерации не нужно.
Directory _copyPackage() {
  final source = Directory.current; // корень apps/codelab_desktop
  final target = Directory.systemTemp.createTempSync('l10n_check_');
  addTearDown(() => target.deleteSync(recursive: true));
  for (final name in ['pubspec.yaml', 'l10n.yaml']) {
    File(p.join(source.path, name)).copySync(p.join(target.path, name));
  }
  final l10n = Directory(p.join(target.path, 'lib', 'l10n'))
    ..createSync(recursive: true);
  for (final file in Directory(
    p.join(source.path, 'lib', 'l10n'),
  ).listSync().whereType<File>()) {
    file.copySync(p.join(l10n.path, p.basename(file.path)));
  }
  return target;
}

Future<ProcessResult> _check(Directory package) => Process.run('fvm', [
  'dart',
  'run',
  p.join(Directory.current.path, '..', '..', 'tool', 'l10n_check.dart'),
  '--package',
  package.path,
]);

void main() {
  test('актуальные каталоги: проверка проходит', () async {
    final package = _copyPackage();

    final result = await _check(package);

    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'ARB изменён без перегенерации: проверка падает и называет файл',
    () async {
      final package = _copyPackage();
      final arb = File(p.join(package.path, 'lib', 'l10n', 'app_en.arb'));
      arb.writeAsStringSync(
        arb.readAsStringSync().replaceFirst(
          '"Language"',
          '"Interface language"',
        ),
      );

      final result = await _check(package);

      expect(result.exitCode, isNot(0));
      expect(
        '${result.stdout}${result.stderr}',
        contains('app_localizations_en.dart'),
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('arb-dir с .. отклоняется: каталог вне пакета не читается', () async {
    final package = _copyPackage();
    final config = File(p.join(package.path, 'l10n.yaml'));
    config.writeAsStringSync(
      config.readAsStringSync().replaceFirst(
        'arb-dir: lib/l10n',
        'arb-dir: ../outside',
      ),
    );

    final result = await _check(package);

    expect(result.exitCode, isNot(0));
    expect('${result.stdout}${result.stderr}', contains('arb-dir'));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('лишний закоммиченный *_localizations*.dart: проверка падает и '
      'называет файл', () async {
    final package = _copyPackage();
    final l10n = p.join(package.path, 'lib', 'l10n');
    File(
      p.join(l10n, 'app_localizations_en.dart'),
    ).copySync(p.join(l10n, 'app_localizations_de.dart'));

    final result = await _check(package);

    expect(result.exitCode, isNot(0));
    expect(
      '${result.stdout}${result.stderr}',
      contains('app_localizations_de.dart'),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));

  test(
    'отличие только в форматировании не считается устаревшим кодом',
    () async {
      // В CI встроенное форматирование gen-l10n могло не сработать (несовпадение
      // версий ядра Dart), и сырой вывод отличался от отформатированного
      // рабочего файла только переносами.
      final package = _copyPackage();
      final file = File(
        p.join(package.path, 'lib', 'l10n', 'app_localizations_en.dart'),
      );
      final text = file.readAsStringSync();
      final collapsed = text.replaceAll('=>\n      ', '=> ');
      expect(collapsed, isNot(text), reason: 'в файле есть перенос после =>');
      file.writeAsStringSync(collapsed);

      final result = await _check(package);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test('вывод называет первую отличающуюся строку: номер, ожидаемое и '
      'фактическое', () async {
    final package = _copyPackage();
    final arb = File(p.join(package.path, 'lib', 'l10n', 'app_en.arb'));
    arb.writeAsStringSync(
      arb.readAsStringSync().replaceFirst('"Language"', '"Interface language"'),
    );

    final result = await _check(package);

    final output = '${result.stdout}${result.stderr}';
    expect(output, contains('app_localizations_en.dart'));
    expect(output, matches(RegExp(r'строка \d+')));
    expect(output, contains("'Language'"));
    expect(output, contains("'Interface language'"));
    expect(output.length, lessThan(2000), reason: 'без больших дампов');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
