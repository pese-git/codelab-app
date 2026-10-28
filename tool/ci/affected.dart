/// Джоб `scope` в `.github/workflows/ci.yml`: матрица проверок по затронутому.
///
/// Почему: pull request из `feature/*` проверяется по затронутым пакетам, а не
/// полным `melos run check` (`AGENTS.md` §21); решение принимается до тяжёлой
/// подготовки (FVM, `pub get`, кодоген), чтобы ненужные джобы не стартовали.
///
/// Как использовать:
/// `dart --packages=<пустой package_config.json> tool/ci/affected.dart
/// --base origin/develop [--full-reason <текст>]` из корня репозитория с
/// полной историей (`fetch-depth: 0`). Пустой `--packages` нужен потому, что
/// `dart run` на чистом checkout разрешает весь pub workspace, а для него
/// нужен Flutter SDK из FVM; локально можно `fvm dart run tool/ci/affected.dart`. Пишет
/// `matrix=<json>` в `$GITHUB_OUTPUT` и таблицу в `$GITHUB_STEP_SUMMARY`; без
/// этих переменных — в stdout, для локальной проверки.
library;

import 'dart:convert';
import 'dart:io';

import 'ci_scope.dart';

Future<void> main(List<String> args) async {
  String? option(String name) {
    final index = args.indexOf(name);
    return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
  }

  final base = option('--base') ?? 'origin/develop';
  var fullReason = option('--full-reason');
  if (fullReason != null && fullReason.isEmpty) fullReason = null;

  var files = const <String>[];
  if (fullReason == null) {
    final diff = await Process.run('git', [
      'diff',
      '--name-only',
      '$base...HEAD',
    ]);
    if (diff.exitCode == 0) {
      files = const LineSplitter()
          .convert(diff.stdout as String)
          .where((line) => line.isNotEmpty)
          .toList();
    } else {
      // Без списка изменений сужать нечего: безопаснее проверить всё.
      fullReason = 'git diff $base...HEAD failed: ${diff.stderr}'.trim();
    }
  }

  final scope = ciScope(
    packages: readWorkspace(Directory.current.path),
    changedFiles: files,
    fullReason: fullReason,
  );

  final matrix = jsonEncode([for (final job in scope.jobs) job.toJson()]);
  final summary = StringBuffer()
    ..writeln('### CI scope: ${scope.full ? 'full' : 'affected'}')
    ..writeln()
    ..writeln(
      scope.full
          ? 'Reason: ${scope.reason}'
          : 'Changed packages: ${_list(scope.changed)}; '
                'affected: ${_list(scope.affected)}.',
    )
    ..writeln()
    ..writeln('| job | scripts | packages |')
    ..writeln('|---|---|---|');
  for (final job in scope.jobs) {
    summary.writeln(
      '| ${job.job} | ${job.scripts} | ${job.packages ?? 'all'} |',
    );
  }
  if (scope.jobs.isEmpty) summary.writeln('| — | documentation only | — |');

  _append('GITHUB_OUTPUT', 'matrix=$matrix\n');
  _append('GITHUB_STEP_SUMMARY', summary.toString());
}

String _list(Set<String> names) =>
    names.isEmpty ? 'none' : (names.toList()..sort()).join(', ');

/// Дописывает в файл из переменной окружения [name], а без неё — в stdout.
void _append(String name, String text) {
  final path = Platform.environment[name];
  if (path == null || path.isEmpty) {
    stdout.write(text);
  } else {
    File(path).writeAsStringSync(text, mode: FileMode.append);
  }
}
