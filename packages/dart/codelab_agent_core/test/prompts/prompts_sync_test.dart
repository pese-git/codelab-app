import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gen_prompts.dart';
import '../support/package_dir.dart';

void main() {
  // PR-1: сгенерированный файл соответствует исходникам. Обновить его —
  // `fvm dart run tool/gen_prompts.dart` в каталоге пакета.
  test('prompts.g.dart matches prompts/**/*.md', () {
    final files = readPromptFiles(Directory(corePath('prompts')));
    final generated = generatePrompts(files);

    expect(
      generated,
      File(corePath('lib/src/prompts/prompts.g.dart')).readAsStringSync(),
    );
  });

  test('every stage 2 prompt file exists', () {
    final files = readPromptFiles(Directory(corePath('prompts'))).keys;

    expect(
      files,
      containsAll([
        'system/base.md',
        'system/untrusted.md',
        'modes/plan.md',
        'tools/read.md',
        'tools/edit.md',
        'tools/listing.md',
        'tools/exec.md',
        'tools/tasks.md',
        for (final tool in [
          'read',
          'write',
          'edit',
          'ls',
          'search',
          'exec',
          'task_create',
          'task_update',
          'task_list',
          'task_get',
        ])
          'tool_descriptions/$tool.md',
      ]),
    );
    // D13: update_plan и его секция удалены.
    expect(files, isNot(contains('tools/plan.md')));
    expect(files, isNot(contains('tool_descriptions/update_plan.md')));
  });
}
