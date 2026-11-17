/// Разбор аргументов команд `exec`, общий для таблицы §7.6 и правил
/// конфигурации агента (PERM-11).
///
/// Почему отдельный файл: `critical_patterns.dart` (таблица и обход) и
/// `agent_config_rules.dart` (пути конфигурации, R5-4) разбирают одни и те же
/// формы аргументов — позиционные слова, цели `cp`/`mv`/`ln`, флаги, подкоманду
/// `git`. Дублировать их нельзя: расхождение разбора давало бы обход.
///
/// Для чего: чистые функции от списка слов сегмента; ничего не знают о
/// файловой системе и политике.
///
/// Как использовать: импортируется только внутри `permissions/`, наружу не
/// экспортируется.
library;

import 'shell_lexer.dart';

final shortFlagPattern = RegExp(r'^-[A-Za-z]+$');
final recursiveFlagPattern = RegExp(r'^-[A-Za-z]*[rR][A-Za-z]*$');

/// Назначение `cp`/`mv`/`ln`/`install` (`-t DIR` или последний позиционный
/// аргумент), источники и пути, которые появятся, если назначение — каталог
/// (`cp passwd /etc/`).
({List<String> destinations, List<String> targets, List<String> sources})
copyTargets(
  List<String> args, {
  Set<String> withValue = const {'-t', '-S', '--target-directory', '--suffix'},
}) {
  String? directory;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--') {
      break;
    }
    if (a == '-t' && i + 1 < args.length) {
      directory = args[i + 1];
    } else if (a.startsWith('--target-directory=')) {
      directory = a.substring('--target-directory='.length);
    }
  }
  final positionals = positionalArgs(args, withValue: withValue);
  final List<String> sources;
  final String destination;
  if (directory != null) {
    destination = directory;
    sources = positionals;
  } else if (positionals.length >= 2) {
    destination = positionals.last;
    sources = positionals.sublist(0, positionals.length - 1);
  } else {
    return (destinations: const [], targets: const [], sources: positionals);
  }
  return (
    sources: sources,
    destinations: [destination],
    targets: [
      destination,
      for (final source in sources) '$destination/${baseName(source)}',
    ],
  );
}

/// Позиционные аргументы: без опций и их значений из [withValue]; после
/// `--` все слова позиционные.
List<String> positionalArgs(
  List<String> args, {
  Set<String> withValue = const {},
}) {
  final result = <String>[];
  var options = true;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (options && a == '--') {
      options = false;
    } else if (options && a.startsWith('-') && a.length > 1) {
      if (withValue.contains(a)) {
        i++;
      }
    } else {
      result.add(a);
    }
  }
  return result;
}

/// Рекурсивный флаг §7.6: `-r`, `-R`, `--recursive` или кластер коротких
/// флагов с `r`/`R` (`-rf`, `-fR`).
bool hasRecursiveFlag(List<String> args) {
  for (final a in args) {
    if (a == '--') {
      return false;
    }
    if (a == '--recursive' || recursiveFlagPattern.hasMatch(a)) {
      return true;
    }
  }
  return false;
}

/// Подкоманда `git`, её аргументы и глобальные опции перед ней (`-C DIR`,
/// `-c k=v`, `--git-dir X`, …); `null` — подкоманды нет.
({String subcommand, List<String> rest, List<String> globals})? gitSubcommand(
  List<String> args,
) {
  var i = 0;
  while (i < args.length && args[i].startsWith('-')) {
    final a = args[i];
    i +=
        const {
          '-C',
          '-c',
          '--git-dir',
          '--work-tree',
          '--namespace',
        }.contains(a)
        ? 2
        : 1;
  }
  if (i >= args.length) {
    return null;
  }
  return (
    subcommand: args[i],
    rest: args.sublist(i + 1),
    globals: args.sublist(0, i),
  );
}

/// Кластер коротких флагов с [letter] до `--` (`-sf`, `-al`).
bool hasShortFlag(List<String> args, String letter) {
  for (final a in args) {
    if (a == '--') {
      return false;
    }
    if (!a.startsWith('--') && RegExp('^-[A-Za-z]*$letter').hasMatch(a)) {
      return true;
    }
  }
  return false;
}
