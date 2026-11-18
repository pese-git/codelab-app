// Проверка актуальности сгенерированного кода локализации (скрипт Melos
// `l10n:check`, change `add-desktop-localization`, D3, риск R12).
//
// Почему: сгенерированный `*_localizations*.dart` коммитится (как
// `*.freezed.dart`), чтобы `dart analyze` работал без шага генерации. Значит,
// ARB можно изменить и забыть перегенерировать: в приложении останется старый
// текст. `flutter gen-l10n` такое расхождение не считает ошибкой.
//
// Для чего: перегенерирует каталоги пакета во временный каталог и сравнивает
// результат с рабочими файлами. Рабочее дерево не меняется.
//
// Как использовать:
//   fvm dart run tool/l10n_check.dart [--package <каталог>]...
// Без аргументов проверяются `apps/codelab_desktop` и
// `packages/flutter/codelab_ui`. Пакет без `l10n.yaml` пропускается с
// сообщением (так скрипт работает и до появления каталога у пакета).
// Расхождение или отсутствие файла — код выхода 1 и путь файла в выводе.

import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final packages = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--package' && i + 1 < args.length) {
      packages.add(args[++i]);
    } else {
      stderr.writeln('l10n_check: неизвестный аргумент ${args[i]}');
      exit(64);
    }
  }
  if (packages.isEmpty) {
    final root = File.fromUri(Platform.script).parent.parent.path;
    packages.addAll([
      p.join(root, 'apps', 'codelab_desktop'),
      p.join(root, 'packages', 'flutter', 'codelab_ui'),
    ]);
  }

  var failed = false;
  for (final package in packages) {
    if (!await _check(Directory(package))) failed = true;
  }
  if (failed) {
    stderr.writeln(
      'l10n_check: сгенерированный код устарел; '
      'выполните `fvm flutter gen-l10n` в пакете.',
    );
    exit(1);
  }
}

/// Проверяет один пакет; `true` — код актуален или пакет без каталога.
Future<bool> _check(Directory package) async {
  final config = File(p.join(package.path, 'l10n.yaml'));
  if (!config.existsSync()) {
    stdout.writeln('l10n_check: ${package.path}: нет l10n.yaml, пропущен');
    return true;
  }
  final arbDir = RegExp(
    r'^arb-dir:\s*(\S+)',
    multiLine: true,
  ).firstMatch(config.readAsStringSync())?.group(1);
  if (arbDir == null) {
    stderr.writeln('l10n_check: ${config.path}: нет arb-dir');
    return false;
  }

  // Каталог ARB — внутри пакета: `..` или абсолютный путь вывели бы чтение и
  // сравнение за его пределы.
  if (p.isAbsolute(arbDir) || !p.isWithin('.', p.normalize(arbDir))) {
    stderr.writeln(
      'l10n_check: ${config.path}: arb-dir «$arbDir» должен быть внутри пакета',
    );
    return false;
  }

  final temp = Directory.systemTemp.createTempSync('l10n_check_');
  try {
    // Во временный каталог идут только входы генерации: pubspec, настройки и
    // ARB. Сгенерированные файлы там появятся заново.
    for (final name in ['pubspec.yaml', 'l10n.yaml']) {
      File(p.join(package.path, name)).copySync(p.join(temp.path, name));
    }
    final tempArb = Directory(p.join(temp.path, arbDir))
      ..createSync(recursive: true);
    final sourceArb = Directory(p.join(package.path, arbDir));
    for (final file in sourceArb.listSync().whereType<File>()) {
      if (file.path.endsWith('.arb')) {
        file.copySync(p.join(tempArb.path, p.basename(file.path)));
      }
    }

    // `untranslated-messages-file` пишется в `build/`: gen-l10n сам каталог не
    // создаёт и падает.
    Directory(p.join(temp.path, 'build')).createSync();
    final generated = await Process.run('fvm', [
      'flutter',
      'gen-l10n',
    ], workingDirectory: temp.path);
    if (generated.exitCode != 0) {
      stderr.write('${generated.stdout}${generated.stderr}');
      stderr.writeln(
        'l10n_check: ${package.path}: gen-l10n завершился с ошибкой',
      );
      return false;
    }

    var ok = true;
    final fresh = tempArb
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.endsWith('.arb'))
        .toList();
    if (fresh.isEmpty) {
      stderr.writeln('l10n_check: ${package.path}: gen-l10n ничего не создал');
      return false;
    }
    // Сверка наборов: закоммиченный `*_localizations*.dart`, которого генерация
    // не создаёт (удалённый язык), тоже устарел.
    final expected = {for (final file in fresh) p.basename(file.path)};
    for (final file in sourceArb.listSync().whereType<File>()) {
      final name = p.basename(file.path);
      if (RegExp(r'_localizations(_\w+)?\.dart$').hasMatch(name) &&
          !expected.contains(name)) {
        stderr.writeln('l10n_check: лишний файл ${file.path}');
        ok = false;
      }
    }
    for (final file in fresh) {
      final committed = File(p.join(sourceArb.path, p.basename(file.path)));
      if (!committed.existsSync()) {
        stderr.writeln('l10n_check: нет файла ${committed.path}');
        ok = false;
      } else if (committed.readAsStringSync() != file.readAsStringSync()) {
        stderr.writeln('l10n_check: устарел ${committed.path}');
        ok = false;
      }
    }
    return ok;
  } finally {
    temp.deleteSync(recursive: true);
  }
}
