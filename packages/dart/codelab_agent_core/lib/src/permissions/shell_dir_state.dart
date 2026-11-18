/// Состояние рабочего каталога оболочки при проверке команды `exec`
/// (`agent-core/07-permissions.md` §7.6.2; change `harden-exec-cwd-tracking`,
/// D1, D3–D5).
///
/// Почему: PERM-11 сравнивает относительные пути команды с каталогом, в
/// котором она запустится. Одна строка каталога, уверенная в себе при
/// `cd -`, `popd`, неудачном `cd` или переменной в цели, пропускала запись в
/// каталог навыка или конфигурации. Здесь каталог — множество вариантов
/// состояния с признаком «неизвестно» (⊤), а переходы `cd`, `pushd`, `popd`,
/// `dirs` — чистые функции без обращения к файловой системе (ядро её не
/// видит, PKG-1).
///
/// Для чего: [ShellDirState] — вариант (каталог, `OLDPWD`, стек `pushd`);
/// [DirVariants] — множество вариантов не более [maxDirVariants] известных
/// плюс ⊤; [DirFlow] — состояния после успеха и неуспеха; [DirContext] —
/// признаки строки (`CDPATH`, `OLDPWD`, физические `..`) и хост;
/// [dirCommandFlow] — переход встроенной команды.
///
/// Как использовать: обход `exec_dir_walk.dart` держит [DirVariants] и для
/// сегмента `cd`/`pushd`/`popd`/`dirs` вызывает [dirCommandFlow]; прочие
/// сегменты состояние не меняют.
library;

import '../util/posix_path.dart';
import 'agent_config_rules.dart';
import 'shell_glob.dart';
import 'shell_lexer.dart';
import 'shell_words.dart';

final _physicalCluster = RegExp(r'^-[A-Za-z]*P');
final _rotation = RegExp(r'^[+-]\d+$');
final _cdOptions = RegExp(r'^-[LPe@]+$');

/// Предел числа известных вариантов (D1): `pushd` через `;` даёт 2ⁿ стеков, а
/// разбор идёт в UI-изоляте. Сверх предела множество схлопывается в «любой
/// каталог».
const maxDirVariants = 32;

/// Каталог для проверок, которые не должны зависеть от рабочего каталога:
/// абсолютные пути, `~`, `$HOME`. Относительные цели от него не попадают ни в
/// корень сессии, ни в защищаемые пути хоста.
const unknownWorkingDirectory = '/.unknown-working-directory';

/// Вариант состояния оболочки: каталог, `OLDPWD` и стек `pushd` (D1).
///
/// [oldPwd] и [stack] равны `null`, когда неизвестны: `OLDPWD` даёт
/// окружение исполнителя, а стек неизвестен после `dirs` с опциями и после
/// перехода из «неизвестного» каталога.
final class ShellDirState {
  /// Создаётся переходами; начальное состояние — `(cwd, null, [])`.
  const ShellDirState(this.dir, {this.oldPwd, this.stack = const []});

  /// Абсолютный нормализованный текущий каталог.
  final String dir;

  /// Предыдущий каталог (`cd -`) или `null`.
  final String? oldPwd;

  /// Стек `pushd`, вершина первая; `null` — неизвестен.
  final List<String>? stack;

  @override
  bool operator ==(Object other) =>
      other is ShellDirState &&
      other.dir == dir &&
      other.oldPwd == oldPwd &&
      _sameStack(other.stack, stack);

  @override
  int get hashCode =>
      Object.hash(dir, oldPwd, stack == null ? null : Object.hashAll(stack!));

  static bool _sameStack(List<String>? a, List<String>? b) {
    if (a == null || b == null) {
      return a == b;
    }
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}

/// Множество вариантов состояния: известные и, возможно, «неизвестно» (D1).
///
/// Почему: неудачный `cd` и стадия конвейера дают ровно два известных
/// варианта, и схлопывание их в ⊤ сделало бы критичными `cd sub; make` и
/// любую команду после `cd X;`.
final class DirVariants {
  DirVariants._(this.known, this.unknown);

  /// Известные варианты; сверх [maxDirVariants] — схлопываются в ⊤.
  factory DirVariants(Iterable<ShellDirState> known, {bool unknown = false}) {
    final set = {...known};
    if (set.length > maxDirVariants) {
      return onlyUnknown;
    }
    return DirVariants._(set, unknown);
  }

  /// Ни одного варианта: недостижимое состояние (`popd` с пустым стеком).
  static final empty = DirVariants._(const {}, false);

  /// Любой каталог, любой стек.
  static final onlyUnknown = DirVariants._(const {}, true);

  /// Известные варианты.
  final Set<ShellDirState> known;

  /// В множестве есть «неизвестно» (⊤).
  final bool unknown;

  bool get isEmpty => known.isEmpty && !unknown;

  /// Объединение; предел [maxDirVariants] применяется к результату.
  DirVariants union(DirVariants other) {
    if (other.isEmpty) {
      return this;
    }
    if (isEmpty) {
      return other;
    }
    return DirVariants({
      ...known,
      ...other.known,
    }, unknown: unknown || other.unknown);
  }

  /// Те же варианты и тот же признак «неизвестно».
  bool sameAs(DirVariants other) =>
      unknown == other.unknown &&
      known.length == other.known.length &&
      known.containsAll(other.known);

  /// То же множество с добавленным ⊤.
  DirVariants withUnknown() => unknown ? this : DirVariants._(known, true);
}

/// Состояния после успеха и неуспеха конвейера (D2).
final class DirFlow {
  const DirFlow(this.ok, this.fail);

  /// Одно состояние для обоих исходов.
  DirFlow.same(DirVariants both) : ok = both, fail = both;

  /// После успеха: следующий за `&&` конвейер идёт отсюда.
  final DirVariants ok;

  /// После неуспеха: следующий за `||` конвейер идёт отсюда.
  final DirVariants fail;

  /// Состояние после `;`, перевода строки и конца блока: оба исхода.
  DirVariants get both => ok.union(fail);

  /// `!` меняет исходы местами.
  DirFlow get swapped => DirFlow(fail, ok);
}

/// Признаки строки и данные хоста, нужные переходам (D4, D5).
///
/// Почему подстрока, а не разбор присваиваний: `CDPATH` и `OLDPWD` можно
/// задать десятком способов (`export`, `read`, `printf -v`, `eval`, префикс
/// `CDPATH=… cd`); упоминание в любом слове разбора ловит все формы ценой
/// ложного срабатывания на `echo $CDPATH`, что стоит одного вопроса.
final class DirContext {
  DirContext._(
    this.config,
    this.cdpath,
    this.oldpwd,
    this.physical,
    this.enable,
    this.dirstack,
  );

  /// Признаки по строке [command] и её разбору [script].
  factory DirContext.of(
    String command,
    ShellScript script,
    ConfigCheck config,
  ) {
    final segments = script.allSegments.toList();
    bool mentions(String name) =>
        command.contains(name) ||
        segments.any(
          (s) => [
            ...s.words,
            ...s.launcherWords,
            for (final r in s.redirections) r.target,
          ].any((w) => w.contains(name)),
        );
    // Имена переменных и опций, собранные при исполнении, подстрока не
    // видит: любая такая запись ставит признаки сразу (D17, A5).
    var dynamic = false;
    var shopt = false;
    var set = false;
    var physical = false;
    var enable = false;
    visitScript(
      script,
      onSegment: (s) {
        final writes = variableWrites(s, includePrefix: true);
        dynamic = dynamic || writes.dynamic;
        shopt = shopt || writes.shoptDynamic;
        set = set || writes.setDynamic;
        physical = physical || _setsPhysical(s);
        // `enable` — имя команды (после лаунчеров `builtin`, `command`), а не
        // подстрока слова: `./configure --enable-shared` не в счёт.
        enable = enable || s.words.firstOrNull == 'enable';
      },
    );
    return DirContext._(
      config,
      dynamic || shopt || mentions('CDPATH') || mentions('cdable_vars'),
      dynamic || mentions('OLDPWD'),
      physical || set,
      enable,
      // `DIRSTACK[1]=…` меняет стек в обход `pushd` (bash).
      dynamic || mentions('DIRSTACK'),
    );
  }

  /// `set -P` и `set -o physical` делают `cd` физическим: `..` идёт от цели
  /// ссылки, а нормализация лексическая (D3).
  static bool _setsPhysical(ShellSegment s) {
    if (s.words.firstOrNull != 'set') {
      return false;
    }
    final args = s.arguments;
    for (var i = 0; i < args.length; i++) {
      if (_physicalCluster.hasMatch(args[i]) ||
          args[i] == '-o' && i + 1 < args.length && args[i + 1] == 'physical') {
        return true;
      }
    }
    return false;
  }

  /// Пути хоста и корень сессии.
  final ConfigCheck config;

  /// Строка упоминает `CDPATH`: относительная цель без `./` и `../`
  /// неизвестна (D5).
  final bool cdpath;

  /// Строка упоминает `OLDPWD`: `cd -` неизвестен.
  final bool oldpwd;

  /// В строке есть `set -P` или `set -o physical`.
  final bool physical;

  /// В строке есть команда `enable`: её имя после снятия лаунчеров (`builtin
  /// enable`, `command enable`), в том числе во вложенных текстах. Тогда `cd`,
  /// `pushd`, `popd` могут быть отключены или подменены, результат неизвестен
  /// (D17, H6; D18, W5). Подстрока в других словах (`--enable-shared`) не в
  /// счёт. Имя, собранное при исполнении, ловит обход сам: после динамической
  /// команды (`_enableSeen`).
  final bool enable;

  /// Строка упоминает `DIRSTACK`: стек `pushd` неизвестен (D17, H6).
  final bool dirstack;

  /// Каталог `HOME` из значений хоста или `null`.
  String? get home => config.scope?.expansions['HOME'];

  /// Абсолютный путь цели [word] от каталога [from] (`null` — каталог
  /// неизвестен, годятся только абсолютные цели); `null`, если цель
  /// неизвестна: переменная, подстановка, `~user`, маска, фигурные скобки,
  /// `CDPATH`, физический `..` (D4, D5).
  String? target(String word, String? from, {bool physicalOption = false}) {
    final expanded = config.scope?.expand(word) ?? word;
    if (expanded.contains(r'$') ||
        expanded.contains('`') ||
        expanded.startsWith('~') ||
        hasMask(expanded)) {
      return null;
    }
    final relativeToCdpath =
        !expanded.startsWith('/') &&
        !expanded.startsWith('./') &&
        !expanded.startsWith('../') &&
        expanded != '.' &&
        expanded != '..';
    if (cdpath && relativeToCdpath) {
      return null;
    }
    final parts = expanded.split('/');
    if ((physical || physicalOption) && parts.contains('..')) {
      return null;
    }
    // `..` после обычной компоненты: если компонента — ссылка, физический
    // `cd` (bash вне POSIX-режима откатывается к нему) уйдёт в другое место,
    // чем лексическая нормализация (D17, A5).
    for (var i = 1; i < parts.length; i++) {
      if (parts[i] == '..' &&
          parts[i - 1].isNotEmpty &&
          parts[i - 1] != '.' &&
          parts[i - 1] != '..') {
        return null;
      }
    }
    final path = from == null
        ? (expanded.startsWith('/') ? normalizePath('/', expanded) : null)
        : normalizePath(from, expanded);
    // Путь длиннее `PATH_MAX` оболочка не откроет; цепочка `pushd a && …` иначе
    // растила бы строку без предела (D18, W7).
    return path == null || path.length > maxDirPathLength ? null : path;
  }
}

/// Переход встроенной `cd`, `pushd`, `popd` или `dirs` с аргументами [args]
/// из состояния [input] (D3).
///
/// Почему не `null` = «без изменений»: неизвестная цель при успехе — это ⊤, а
/// не прежний каталог (пробел 5 proposal).
///
/// Для чего: успех даёт новые состояния, неуспех — прежние (`cd` в
/// несуществующий каталог оставляет всё как было). `pushd` без аргумента и
/// `popd` с пустым стеком — неуспех (bash); для `dirs` исходов два одинаковых.
///
/// Как использовать: вызывает обход для сегмента, где первое слово — один из
/// четырёх встроенных и лаунчеры не сделали его внешней программой.
DirFlow dirCommandFlow(
  String name,
  List<String> args,
  DirVariants input,
  DirContext context, {
  bool enabled = false,
}) {
  if (name == 'dirs') {
    // `dirs -c`, `dirs +N`: стек после опций неизвестен.
    if (args.isEmpty) {
      return DirFlow.same(input);
    }
    return DirFlow.same(
      DirVariants({
        for (final v in input.known)
          ShellDirState(v.dir, oldPwd: v.oldPwd, stack: null),
      }, unknown: input.unknown),
    );
  }
  if (enabled || context.enable) {
    // `enable -n cd`: встроенная команда могла быть заменена.
    return DirFlow(DirVariants.onlyUnknown, input);
  }
  final parsed = _parse(name, args);
  final success = <ShellDirState>{};
  var successUnknown = false;
  // ⊤ на входе: известен только абсолютный путь цели.
  final states = <ShellDirState?>[...input.known, if (input.unknown) null];
  for (final state in states) {
    final result = _succeed(name, parsed, state, context);
    successUnknown = successUnknown || result.unknown;
    success.addAll(result.states);
  }
  return DirFlow(DirVariants(success, unknown: successUnknown), input);
}

/// Разобранные аргументы встроенной (D3).
typedef _Parsed = ({List<String> operands, bool unknown, bool physical});

/// Опции `-L -P -e -@` пропускаются (кластером тоже), `--` завершает опции,
/// `+N`/`-N` у `pushd`/`popd` и любая другая опция дают «неизвестно».
_Parsed _parse(String name, List<String> args) {
  final operands = <String>[];
  var unknown = false;
  var physical = false;
  var options = true;
  for (final word in args) {
    if (!options) {
      operands.add(word);
    } else if (word == '--') {
      options = false;
    } else if (word == '-') {
      operands.add(word);
    } else if (name != 'cd' && _rotation.hasMatch(word)) {
      // Вращение стека: точное состояние не стоит кода (D3).
      unknown = true;
    } else if (word.startsWith('-') && word.length > 1) {
      if (_cdOptions.hasMatch(word)) {
        physical = physical || word.contains('P');
      } else {
        unknown = true;
      }
    } else {
      operands.add(word);
    }
  }
  return (operands: operands, unknown: unknown, physical: physical);
}

/// Состояния, в которые команда приходит при успехе из [state] (`null` — ⊤).
({List<ShellDirState> states, bool unknown}) _succeed(
  String name,
  _Parsed parsed,
  ShellDirState? state,
  DirContext context,
) {
  const none = (states: <ShellDirState>[], unknown: false);
  const top = (states: <ShellDirState>[], unknown: true);
  if (parsed.unknown) {
    return top;
  }
  ShellDirState moved(String dir, {List<String>? stack}) =>
      ShellDirState(dir, oldPwd: state?.dir, stack: stack);
  final operands = parsed.operands;
  switch (name) {
    case 'popd':
      if (operands.isNotEmpty) {
        return top;
      }
      final stack = context.dirstack ? null : state?.stack;
      if (state == null || stack == null) {
        return top;
      }
      return stack.isEmpty
          ? none
          : (
              states: [moved(stack.first, stack: stack.sublist(1))],
              unknown: false,
            );
    case 'pushd' when operands.isEmpty:
      final stack = context.dirstack ? null : state?.stack;
      if (state == null || stack == null) {
        return top;
      }
      return stack.isEmpty
          ? none
          : (
              states: [
                moved(stack.first, stack: [state.dir, ...stack.skip(1)]),
              ],
              unknown: false,
            );
  }
  // `cd` и `pushd DIR`.
  final String? dir;
  if (operands.length > 1) {
    return top;
  } else if (operands.isEmpty) {
    dir = context.home;
  } else if (operands.single == '-') {
    // `pushd -` и `cd -` без известного `OLDPWD` строки — «неизвестно».
    dir = name == 'cd' && !context.oldpwd ? state?.oldPwd : null;
  } else {
    dir = context.target(
      operands.single,
      state?.dir,
      physicalOption: parsed.physical,
    );
  }
  if (dir == null) {
    return top;
  }
  final stack = context.dirstack ? null : state?.stack;
  return (
    states: [
      moved(dir, stack: name == 'pushd' ? _pushed(state?.dir, stack) : stack),
    ],
    unknown: false,
  );
}

/// Наибольшая длина известного стека `pushd`: длиннее стек становится
/// неизвестным (D18, W7). Иначе `pushd a && …` тысячи раз давало бы квадратичное
/// копирование списков.
const maxKnownDirStack = 64;

/// Наибольшая длина известного пути каталога (`PATH_MAX`).
const maxDirPathLength = 4096;

List<String>? _pushed(String? dir, List<String>? stack) {
  if (dir == null || stack == null || stack.length >= maxKnownDirStack) {
    return null;
  }
  return [dir, ...stack];
}
