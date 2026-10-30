// Процессный тест сценариев «Тильда раскрывается в HOME» и «Тильда без
// домашнего каталога» (spec codelab-cli «Домашний каталог CLI CODELAB_HOME»;
// design.md change `add-agent-project-files`, D17).
//
// Юнит-тест `home_test.dart` проверяет `CodelabHome.resolve`; здесь тот же
// контракт проверяется на собранном бинаре: настоящий `argv`, окружение
// процесса, код выхода и stderr. Агент не нужен: `profiles add` и ошибка
// использования не запускают транспорт. Только временные каталоги.
@Timeout(Duration(seconds: 120))
library;

import 'dart:io';

import 'package:test/test.dart';

import '../support/cli_process.dart';
import 'support/e2e_agent.dart';

void main() {
  late Directory tmp;
  late Directory work;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_cli_tilde_');
    work = Directory('${tmp.path}/work')..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'CODELAB_HOME=~/cl is expanded with HOME; no ./~ folder appears',
    () async {
      final home = '${tmp.path}/home';
      Directory(home).createSync();

      final result = await CliProcess.run(
        ['profiles', 'add', 'default', 'stdio:agent'],
        environment: {'CODELAB_HOME': '~/cl', 'HOME': home},
        workingDirectory: work.path,
      );

      expect(result.exitCode, 0, reason: '$result');
      expect(File('$home/cl/profiles.json').existsSync(), isTrue);
      // Буквальный `~` не должен стать каталогом ни в cwd, ни в HOME.
      expect(Directory('${work.path}/~').existsSync(), isFalse);
      expect(Directory('$home/~').existsSync(), isFalse);
    },
    tags: scriptedOnly,
  );

  test(
    'CODELAB_HOME=~/cl without HOME and USERPROFILE is 64 and no agent starts',
    () async {
      // Хелпер всегда подставляет HOME по умолчанию, поэтому «не задан»
      // выражается пустым значением (spec: пустой HOME = неизвестный).
      final marker = '${tmp.path}/agent-started';
      final result = await CliProcess.run(
        ['-p', 'hi', '-a', 'touch $marker'],
        environment: {'CODELAB_HOME': '~/cl', 'HOME': '', 'USERPROFILE': ''},
        workingDirectory: work.path,
      );

      expect(result.exitCode, 64, reason: '$result');
      expect(
        result.stderr,
        contains(
          'CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, '
          'use an absolute path',
        ),
      );
      expect(File(marker).existsSync(), isFalse);
      expect(Directory('${work.path}/~').existsSync(), isFalse);
    },
    tags: scriptedOnly,
  );
}
