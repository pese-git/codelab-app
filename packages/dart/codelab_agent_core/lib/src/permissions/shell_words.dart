/// Лексические предикаты слов команды и разбор записи переменных сегментом
/// (`agent-core/07-permissions.md` §7.6.2; change `harden-exec-cwd-tracking`,
/// D17, A2, A5).
///
/// Почему отдельный файл рядом с лексером: решения «это слово — динамическое
/// имя команды» и «этот сегмент пишет переменную» зависят только от текста
/// слов, а не от состояния каталога. Их общие потребители — `DirContext`
/// (признаки строки) и обход `exec_dir_walk.dart` (потребитель переменной-
/// команды); дублировать разбор в двух местах нельзя: правила разошлись бы.
///
/// Принцип — разрешённый список: слово считается «файлом» или «литералом»,
/// только если разбор в этом уверен; всё прочее с `$`, обратной кавычкой или
/// маской — динамическое (fail closed).
///
/// Как использовать: [isDynamicCommandWord] — для первого слова сегмента;
/// [variableWrites] — для любого сегмента; [visitScript] — обход дерева.
library;

import 'shell_lexer.dart';

/// Слово содержит `$` или обратную кавычку: значение известно только при
/// исполнении.
bool isNonLiteral(String word) => word.contains(r'$') || word.contains('`');

/// Слово — путь к файлу: буквальная `/` стоит до первого раскрытия или сразу
/// после простой `$NAME`/`${NAME}`/`~`, других `$` и обратных кавычек до неё
/// нет. Такое слово оболочка исполняет как файл, а не как встроенную команду,
/// поэтому им нельзя вызвать `cd`, `eval`, `trap`.
///
/// Регулярка смотрит только на структуру текста; разбиение незакавыченного
/// `$NAME` на слова ловит флаг `split` ([isDynamicCommandWord]).
final _fileWord = RegExp(
  r'^(~[^/$`]*|\$(\{[A-Za-z_]\w*\}|[A-Za-z_]\w*))?[^$`]*/',
);

/// Имя команды заранее неизвестно: в слове есть `$` или обратная кавычка и
/// оно не путь к файлу ([_fileWord]); либо в нём есть незакавыченная маска или
/// фигурные скобки ([glob], `{cd,x}`, `[c]d`); либо раскрытие до первой `/`
/// не закавычено ([split]): `d='cd '; $d/run` разбивается на `cd` и `/run`.
/// Раскрытия `$HOME`/`$CODELAB_HOME` и `~` слов не разбивают: значения знает
/// хост (D17, A2).
bool isDynamicCommandWord(
  String word, {
  bool glob = false,
  bool split = false,
}) => glob || split || isNonLiteral(word) && !_fileWord.hasMatch(word);

/// Имя в операнде `NAME=value`, `NAME[i]`, `NAME`; `null`, если имя собрано
/// при исполнении.
final _dynamicStart = RegExp(r'[$`]');
final _expansionWrite = RegExp(
  r'\$\{([A-Za-z_][A-Za-z0-9_]*)(?:\[[^\]]*\])?:?=',
);
final _refOption = RegExp(r'^-[A-Za-z]*n');

/// Имя переменной собрано при исполнении: `$` или обратная кавычка стоят
/// раньше `=` (`export "$(…)=x"`), а не в значении (`export PATH="$HOME/x"`).
bool _dynamicName(String word) {
  final at = word.indexOf(_dynamicStart);
  if (at < 0) {
    return false;
  }
  final eq = word.indexOf('=');
  return eq < 0 || at < eq;
}

const _readCommands = {'read', 'mapfile', 'readarray', 'getopts'};

/// Объявляющие переменные встроенные команды: сами ничего не исполняют.
bool isDeclarationCommand(String? name) =>
    name != null && declarationCommands.contains(baseName(name));

/// Что сегмент пишет в переменные (D17, A5).
///
/// [names] — имена, записанные литерально способом, который строка значения
/// не показывает (`read NAME`, `printf -v NAME`, `declare -n R=NAME`,
/// присваивание без команды, `${NAME:=…}`); значения у `export NAME=value`
/// разбирает лексер как вложенный текст, поэтому здесь их нет. [dynamic] —
/// имя собрано при исполнении (`read "$V"`, `export "${V}=x"`) или исполняется
/// нелитеральный `eval`. [shoptDynamic] и [setDynamic] — `shopt`/`set` с
/// нелитеральным аргументом (может включить `cdable_vars` или `-P`).
typedef VariableWrites = ({
  Set<String> names,
  bool dynamic,
  bool shoptDynamic,
  bool setDynamic,
});

/// Разбор записи переменных сегментом. [includePrefix] — учитывать префиксные
/// присваивания `NAME=… cmd`: для самой команды они не постоянны, а у сегмента
/// из одних присваиваний остаются в оболочке.
VariableWrites variableWrites(
  ShellSegment segment, {
  bool includePrefix = false,
}) {
  final names = <String>{};
  var dynamic = false;
  void operand(String word) {
    if (_dynamicName(word)) {
      dynamic = true;
    } else if (variableNamePattern.firstMatch(word) case final m?) {
      names.add(m[0]!);
    }
  }

  if (includePrefix) {
    for (final w in segment.launcherWords) {
      // Литеральное значение — не косвенная запись: лексер разобрал его как
      // вложенный текст и проверил само значение (D18, F1).
      if (assignmentWord.hasMatch(w) &&
          isNonLiteral(w.substring(w.indexOf('=')))) {
        operand(w);
      }
    }
  }
  for (final w in [
    ...segment.words,
    ...segment.launcherWords,
    for (final r in segment.redirections) r.target,
  ]) {
    for (final m in _expansionWrite.allMatches(w)) {
      names.add(m[1]!);
    }
  }
  final first = segment.words.firstOrNull;
  final args = segment.arguments;
  var shopt = false;
  var set = false;
  switch (first) {
    case final String name when isDeclarationCommand(name):
      for (final a in args) {
        if (a.startsWith('-') || a.startsWith('+')) {
          continue;
        }
        if (_dynamicName(a)) {
          dynamic = true;
        }
      }
      // `declare -n R=NAME`: `R` — ссылка на `NAME`, запись в `R` пишет в него.
      // Без `=` (`declare -n R; R=EDITOR`) цель известна только при
      // исполнении: fail closed (D18, W4).
      if (args.any(_refOption.hasMatch)) {
        for (final a in args) {
          final eq = a.indexOf('=');
          if (a.startsWith('-')) {
            continue;
          }
          if (eq > 0) {
            operand(a.substring(eq + 1));
          } else {
            dynamic = true;
          }
        }
      }
    case final String name when _readCommands.contains(name):
      args.where((a) => !a.startsWith('-')).forEach(operand);
    case 'printf':
      for (var i = 0; i < args.length; i++) {
        if (args[i] == '-v' && i + 1 < args.length) {
          operand(args[i + 1]);
        } else if (args[i].startsWith('-v') && args[i].length > 2) {
          operand(args[i].substring(2));
        }
      }
    case 'eval':
      dynamic = dynamic || args.any(isNonLiteral);
    case 'shopt':
      shopt = args.any(isNonLiteral);
    case 'set':
      set = args.any(isNonLiteral);
  }
  return (names: names, dynamic: dynamic, shoptDynamic: shopt, setDynamic: set);
}

/// Обходит дерево [script] со всеми блоками и вложенными текстами: [onSegment]
/// получает каждый сегмент, [onBlock] — каждый блок.
void visitScript(
  ShellScript script, {
  required void Function(ShellSegment segment) onSegment,
  void Function(ShellBlock block)? onBlock,
}) {
  void segment(ShellSegment s) {
    onSegment(s);
    for (final nested in s.nested) {
      visitScript(nested, onSegment: onSegment, onBlock: onBlock);
    }
  }

  void commands(List<ShellCommand> list) {
    for (final command in list) {
      for (final stage in command.stages) {
        switch (stage) {
          case ShellSimple(segment: final s):
            segment(s);
          case ShellBlock(:final body, :final redirections):
            onBlock?.call(stage);
            commands(body);
            if (redirections != null) {
              segment(redirections);
            }
        }
      }
    }
  }

  commands(script.commands);
}

/// Сегмент исполняет текст, которого разбор не видит: `fc` и `history -s`
/// (правка и повтор истории), `mapfile`/`readarray -C CALLBACK`. Для каталога
/// это нелитеральный `eval` (D18, W4).
bool runsHiddenText(ShellSegment segment) {
  final first = segment.words.firstOrNull;
  final args = segment.arguments;
  return switch (first) {
    'fc' => true,
    'history' => args.any((a) => RegExp(r'^-[A-Za-z]*s').hasMatch(a)),
    'mapfile' ||
    'readarray' => args.any((a) => RegExp(r'^-[A-Za-z]*C').hasMatch(a)),
    _ => false,
  };
}
