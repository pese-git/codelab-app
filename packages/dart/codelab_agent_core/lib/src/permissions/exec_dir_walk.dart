/// Обход команды `exec` с рабочим каталогом как множеством вариантов
/// (`agent-core/07-permissions.md` §7.6.2; change `harden-exec-cwd-tracking`,
/// D1–D18).
///
/// Почему отдельный файл: таблица §7.6 — чистая функция от строки, а модель
/// каталога — отдельная ответственность (состояние оболочки, связки, блоки,
/// происхождение вложенного текста). Обход не знает правил таблицы: каждый
/// сегмент он отдаёт проверке, переданной хостом обхода.
///
/// Для чего: идёт по дереву [ShellScript.commands] и для каждой простой
/// команды знает множество каталогов, в которых она может оказаться. Проверка
/// выполняется для каждого известного каталога; при «неизвестно» (⊤)
/// действует правило D9 и метка `write in unknown working directory`.
/// Общий предикат [mayChangeDirectory] — «сегмент может сменить каталог
/// текущей оболочки»: им пользуются и переход сегмента, и `trap`.
///
/// Как использовать: `findCritical` создаёт [ExecDirWalk] на команду и
/// вызывает [run]. Обход изменяет `ConfigCheck.environmentAssigned` (E1
/// навыков, Q47) в порядке записи, как делал прежний плоский обход. Бюджет
/// [maxDirWalkWork] ограничивает «сегменты × варианты»; сверх него —
/// [ShellParseException], то есть `unparsable command`.
library;

import 'agent_config_rules.dart';
import 'shell_dir_state.dart';
import 'shell_lexer.dart';
import 'shell_words.dart';

/// Общий бюджет проверок «сегменты × варианты» на одну команду (D17, A6): строка
/// до 128 KiB с 32 вариантами иначе стоила бы сотен тысяч проверок в UI-изоляте.
const maxDirWalkWork = 20000;

/// Правила таблицы §7.6, не зависящие от каталога: добавляют метки в [found].
typedef IndependentCheck =
    void Function(ShellSegment segment, Set<String> found);

/// Правила таблицы §7.6 для сегмента в каталоге [dir].
typedef DirectoryCheck =
    void Function(ShellSegment segment, String dir, Set<String> found);

/// Обход одной команды `exec` (D1).
final class ExecDirWalk {
  /// [checkIndependent] — правила, которым каталог не нужен (выполняются один
  /// раз на сегмент, D17 A6); [checkAt] — правила, зависящие от каталога;
  /// [unknownCritical] — критична ли простая команда при каталоге ⊤ (D9);
  /// [agentConfigLabel] и [unknownLabel] — метки таблицы: если известный
  /// вариант (или абсолютный путь) уже дал первую, вторая не ставится.
  ExecDirWalk({
    required this.config,
    required this.context,
    required this.checkIndependent,
    required this.checkAt,
    required this.unknownCritical,
    required this.found,
    required this.agentConfigLabel,
    required this.unknownLabel,
  });

  final ConfigCheck config;
  final DirContext context;
  final IndependentCheck checkIndependent;
  final DirectoryCheck checkAt;
  final bool Function(ShellSegment segment) unknownCritical;
  final Set<String> found;
  final String agentConfigLabel;
  final String unknownLabel;

  /// Раньше в строке определена функция, `alias` или `trap`, чьё действие
  /// может сменить каталог: любая следующая команда может оказаться их
  /// вызовом, состояние неизвестно до конца строки (D6, D17 H3).
  var _tainted = false;

  /// Переменные-команды из `export`/`declare`/…: сами объявления ничего не
  /// исполняют, значение проверяется там, где его запустит команда-
  /// потребитель — у следующего сегмента, не объявления (D8).
  final _pendingForeign = <ShellScript>[];

  /// Переменная-команда записана косвенно (`read EDITOR`, `printf -v`,
  /// `declare -n`, `${EDITOR:=…}`, цикл `for EDITOR`) или имя собрано при
  /// исполнении: первый следующий сегмент с командой проверяется как
  /// запускаемый в неизвестном каталоге (D17, A5).
  var _foreignNext = false;

  /// После динамической команды или скрытого текста `enable -n cd` мог
  /// подменить `cd`, `pushd`, `popd` (D18, W5); действует до конца оболочки.
  var _enableSeen = false;

  /// В строке был `trap` с действием: значения переменных-команд, которых
  /// никто не потребил, исполнит ловушка (D17, A7).
  var _trapSeen = false;

  /// Действия `trap`, которые каталог не меняют: проверяются в конце во всех
  /// состояниях строки (ловушка срабатывает позже, например при выходе).
  final _deferredTraps = <ShellScript>[];

  /// Все состояния, в которых побывала строка.
  var _seen = DirVariants.empty;

  var _work = 0;

  /// Проверяет [script] с начальным каталогом [start]. Начальное состояние:
  /// `OLDPWD` неизвестен (даёт окружение исполнителя), стек пуст — каждый
  /// `exec` запускает новый `/bin/sh -c` (D1).
  void run(ShellScript script, String start) {
    final initial = DirVariants({ShellDirState(start)});
    _shell(initial, () => _commands(script.commands, initial));
  }

  /// Обходит [body] как отдельную оболочку (D18, W1): подоболочку, подстановку,
  /// `sh -c`, `env -S`. У оболочки свои ловушки, определённые функции и
  /// `alias`, неизвестное значение переменной-команды и набор побывавших
  /// состояний; что случилось внутри, наружу не выходит, а ловушки и
  /// непотреблённые значения проверяются в состояниях этой оболочки плюс её
  /// конечном состоянии. [inheritTaint] — функции и `alias` родителя видны
  /// (подоболочка, подстановка); новый процесс начинает чистым.
  DirFlow _shell(
    DirVariants start,
    DirFlow Function() body, {
    bool inheritTaint = false,
  }) {
    final tainted = _tainted;
    final enableSeen = _enableSeen;
    final foreignNext = _foreignNext;
    final trapSeen = _trapSeen;
    final deferred = [..._deferredTraps];
    final pending = [..._pendingForeign];
    final seen = _seen;
    _tainted = inheritTaint && tainted;
    _enableSeen = inheritTaint && enableSeen;
    _foreignNext = false;
    _trapSeen = false;
    _deferredTraps.clear();
    _pendingForeign.clear();
    _seen = start;
    try {
      final last = body();
      // Ловушка `EXIT` исполняется в состоянии после последней команды.
      _seen = _seen.union(last.both);
      final values = _trapSeen ? [..._pendingForeign] : <ShellScript>[];
      final actions = [..._deferredTraps];
      _pendingForeign.clear();
      _deferredTraps.clear();
      for (final value in values) {
        _commands(value.commands, _seen.withUnknown());
      }
      for (final action in actions) {
        _commands(action.commands, _seen);
      }
      return last;
    } finally {
      _tainted = tainted;
      _enableSeen = enableSeen;
      _foreignNext = foreignNext;
      _trapSeen = trapSeen;
      _deferredTraps
        ..clear()
        ..addAll(deferred);
      _pendingForeign
        ..clear()
        ..addAll(pending);
      _seen = seen;
    }
  }

  /// Команды уровня со связками (D2), слева направо, как их группирует
  /// оболочка: `A && B || C` — `(A && B) || C`.
  ///
  /// `A && B`: `B` идёт из успеха `A`; успех — успех `B`, неуспех — неуспех
  /// `A` и `B`. `A || B` — зеркально. `;`, перевод строки и фон — из обоих
  /// исходов предыдущего списка; новый список начинается с этого состояния.
  ///
  /// `&` уводит в фон весь and-or список, а не последний конвейер: `A && B &`
  /// — это `{ A && B; } &` (POSIX), поэтому после него состояние такое же, как
  /// до начала списка (D17, B2).
  ///
  /// Пустой вход (`popd` с пустым стеком дал пустой успех) заменяется входом
  /// предыдущей команды того же уровня: безопасность не должна зависеть от
  /// точности модели стека, а `cd` после такой команды идёт от того же входа
  /// (D17, A4).
  DirFlow _commands(List<ShellCommand> commands, DirVariants input) {
    var acc = DirFlow.same(input);
    DirVariants? lastFrom;
    var i = 0;
    while (i < commands.length) {
      // Список — команды до `;`, перевода строки или `&`.
      var j = i;
      while (j < commands.length - 1 &&
          (commands[j].next == ShellConnector.and ||
              commands[j].next == ShellConnector.or)) {
        j++;
      }
      var listFrom = i == 0 ? input : acc.both;
      if (listFrom.isEmpty && lastFrom != null) {
        listFrom = lastFrom;
      }
      final list = commands.sublist(i, j + 1);
      if (commands[j].next == ShellConnector.background) {
        // Фон уводит весь список в подоболочку: у неё свои ловушки и функции,
        // а снаружи состояние такое же, как до списка (D17, B2; D18, W1).
        _shell(listFrom, () => _andOr(list, listFrom).$1, inheritTaint: true);
        acc = DirFlow.same(listFrom);
        lastFrom = listFrom;
      } else {
        final (flow, last) = _andOr(list, listFrom);
        acc = flow;
        lastFrom = last;
      }
      i = j + 1;
    }
    return acc;
  }

  /// Один and-or список: `A && B || C` — `(A && B) || C`. Возвращает поток и
  /// вход последней команды.
  (DirFlow, DirVariants) _andOr(List<ShellCommand> list, DirVariants input) {
    var acc = DirFlow.same(input);
    ShellConnector? previous;
    DirVariants? previousFrom;
    for (final command in list) {
      var from = switch (previous) {
        null => input,
        ShellConnector.and => acc.ok,
        ShellConnector.or => acc.fail,
        _ => acc.both,
      };
      if (from.isEmpty && previousFrom != null) {
        from = previousFrom;
      }
      final flow = _command(command, from);
      acc = switch (previous) {
        ShellConnector.and => DirFlow(flow.ok, acc.fail.union(flow.fail)),
        ShellConnector.or => DirFlow(acc.ok.union(flow.ok), flow.fail),
        _ => flow,
      };
      previous = command.next;
      previousFrom = from;
    }
    return (acc, previousFrom ?? input);
  }

  DirFlow _command(ShellCommand command, DirVariants from) {
    if (command.negated) {
      // Зарезервированное слово `!` отключало E1 навыков для следующих
      // сегментов, пока было командой (Q47); память о нём остаётся.
      config.environmentAssigned = true;
    }
    final DirFlow flow;
    if (command.stages.length == 1) {
      flow = _stage(command.stages.single, from);
    } else {
      // Стадии bash и dash исполняют в подоболочках, zsh и `lastpipe` —
      // последнюю в текущей: объединение верно для обоих (D6).
      var union = from;
      for (final stage in command.stages) {
        union = union.union(_stage(stage, from).both);
      }
      flow = DirFlow.same(union);
    }
    return command.negated ? flow.swapped : flow;
  }

  DirFlow _stage(ShellStage stage, DirVariants from) => switch (stage) {
    ShellSimple(:final segment) => _segment(segment, from),
    ShellBlock() => _block(stage, from),
  };

  /// Блок по таблице D6; перенаправления после закрывающего слова
  /// проверяются в состоянии на выходе (D10).
  DirFlow _block(ShellBlock block, DirVariants from) {
    final DirFlow out;
    switch (block.kind) {
      case ShellBlockKind.subshell:
        _shell(from, () => _commands(block.body, from), inheritTaint: true);
        out = DirFlow.same(from);
      case ShellBlockKind.group:
        // `{` и `}` — зарезервированные слова: по E1(4) §7.6.1 они отключают
        // исключение для следующих сегментов (fail closed, Q47).
        config.environmentAssigned = true;
        out = DirFlow.same(_commands(block.body, from).both);
      case ShellBlockKind.conditional:
        // `if`, `then` и `else` проходят одно множество: надмножество
        // настоящих ветвей. Зарезервированные слова раньше отключали E1.
        config.environmentAssigned = true;
        out = DirFlow.same(from.union(_commands(block.body, from).both));
      case ShellBlockKind.loop:
        config.environmentAssigned = true;
        if (commandEnvironmentVariables.contains(block.variable)) {
          // `for EDITOR in 'rm -rf /'`: цикл записывает переменную-команду.
          _foreignNext = true;
        }
        // Признак «тело меняет состояние» берём из потока, а не из имён
        // команд: `$C "$d"` с `C=cd` тоже меняет каталог (D17, A1). Если
        // состояние после тела отличается от входа, тело обходится повторно
        // от «вход ∪ конец ∪ ⊤»: повтор относительного `cd` не перечислить.
        // Тело может не выполниться ни разу, поэтому вход входит в итог.
        final tainted = _tainted;
        final pending = _pendingForeign.length;
        final foreignNext = _foreignNext;
        final first = _commands(block.body, from);
        var end = from.union(first.both);
        // Повтор нужен и тогда, когда тело изменило не каталог, а состояние
        // оболочки: определило функцию или `alias`, поставило `trap`, записало
        // переменную-команду (D18, W2). На втором проходе эти изменения уже
        // действуют на начало тела.
        final shellChanged =
            _tainted != tainted ||
            _pendingForeign.length > pending ||
            _foreignNext && !foreignNext;
        if (!first.both.sameAs(from) || shellChanged) {
          end = end.union(_commands(block.body, end.withUnknown()).both);
        }
        out = DirFlow.same(end);
      case ShellBlockKind.function:
        // Тело выполнится при вызове, в неизвестном состоянии; наружу ничего
        // не выходит, но любая следующая команда может быть вызовом.
        _commands(block.body, from.withUnknown());
        _tainted = true;
        out = DirFlow.same(from);
    }
    if (block.redirections case final redirections?) {
      _segment(redirections, out.both);
    }
    return out;
  }

  DirFlow _segment(ShellSegment segment, DirVariants from) {
    final input = _tainted ? from.withUnknown() : from;
    _seen = _seen.union(input);
    final declaration = isDeclarationCommand(segment.words.firstOrNull);
    // Косвенно записанная переменная-команда: сегмент с командой — потребитель
    // (D17); варианты — известные ∪ ⊤, как у `foreign`.
    final consumer = _foreignNext && !declaration && segment.words.isNotEmpty;
    if (consumer) {
      _foreignNext = false;
    }
    _checkVariants(
      segment,
      consumer ? input.withUnknown() : input,
      forceUnknown: consumer,
    );
    // Вложенный текст исполняется после присваиваний и лаунчеров внешнего
    // сегмента и после всего, что выполнено раньше. E1 навыков он получает
    // только как `sh|bash|dash -c` без startup-файлов (Q47). Изменения
    // окружения во вложенном тексте (`eval "export X=1"`) остаются и для
    // следующих сегментов: fail closed.
    final outerEnvironment = config.environmentAssigned;
    if (segment.nested.isNotEmpty &&
        (segment.launcherWords.isNotEmpty ||
            !ConfigCheck.nestedKeepsSkillExceptions(segment))) {
      config.environmentAssigned = true;
    }
    if (!declaration && _pendingForeign.isNotEmpty) {
      final start = _nestedStart(segment, ShellOrigin.foreign, input);
      // Очередь очищается до обхода: сегменты самого значения — потребители
      // не себя.
      final pending = [..._pendingForeign];
      _pendingForeign.clear();
      for (final script in pending) {
        _commands(script.commands, start);
      }
    }
    final first = segment.words.firstOrNull;
    DirFlow? evalFlow;
    for (final nested in segment.nested) {
      if (declaration && nested.origin == ShellOrigin.foreign) {
        _pendingForeign.add(nested);
        continue;
      }
      final start = _nestedStart(segment, nested.origin, input);
      if (first == 'trap' && nested.origin == ShellOrigin.foreign) {
        _trapSeen = true;
        if (!_scriptChangesShellState(nested)) {
          // Ловушка состояние оболочки не меняет (`rm -f "$tmp"`): проверяется
          // в конце во всех состояниях строки, без ⊤ (D17, A8).
          _deferredTraps.add(nested);
          continue;
        }
        // Действие исполнится позже в той же оболочке: до конца строки любая
        // команда идёт в неизвестном состоянии (D17, H3; D18, W3).
        _tainted = true;
        _commands(nested.commands, start);
        continue;
      }
      final DirFlow flow;
      if (nested.origin == ShellOrigin.eval &&
          _launcherMode(segment) != _LauncherMode.external) {
        // `eval` — текущая оболочка: состояние общее.
        flow = _commands(nested.commands, start);
        evalFlow = flow;
        continue;
      }
      // Подстановка видит функции родителя, новый процесс — нет (W1).
      _shell(
        start,
        () => _commands(nested.commands, start),
        inheritTaint: nested.origin == ShellOrigin.substitution,
      );
    }
    config.environmentAssigned = outerEnvironment || config.environmentAssigned;
    // Сам сегмент учитывается после вложенного текста: он влияет на
    // следующие сегменты, а не на собственный вложенный.
    config.noteEnvironment(segment);
    if (first == 'alias') {
      // `alias` в dash раскрывается на следующей строке (D6).
      _tainted = true;
    }
    final writes = variableWrites(segment, includePrefix: first == null);
    if (writes.dynamic ||
        writes.names.any(commandEnvironmentVariables.contains)) {
      _foreignNext = true;
    }
    return _flow(segment, input, evalFlow);
  }

  /// Начальное состояние вложенного текста по его происхождению (D8).
  DirVariants _nestedStart(
    ShellSegment segment,
    ShellOrigin origin,
    DirVariants input,
  ) => switch (origin) {
    ShellOrigin.root || ShellOrigin.substitution => input,
    ShellOrigin.eval =>
      _launcherMode(segment) == _LauncherMode.external
          ? _newProcess(segment, input)
          : input,
    ShellOrigin.command => _newProcess(segment, input),
    // Каталог исполнения неизвестен (D8), но известные каталоги остаются в
    // множестве: когда git или `find -execdir` идёт из `cwd`, метка
    // `write to agent configuration` точнее метки неизвестного каталога, а
    // проверка не слабее.
    ShellOrigin.foreign => _newProcess(segment, input).withUnknown(),
  };

  /// Новый процесс: каталоги (с учётом `env -C`/`sudo -D`), пустой стек,
  /// неизвестный `OLDPWD` (D8).
  DirVariants _newProcess(ShellSegment segment, DirVariants input) {
    var unknown = input.unknown;
    final states = <ShellDirState>{};
    for (final v in input.known) {
      final dir = _commandDirectory(segment, v.dir);
      if (dir == null) {
        unknown = true;
      } else {
        states.add(ShellDirState(dir));
      }
    }
    return DirVariants(states, unknown: unknown);
  }

  /// Каталог, в котором [segment] запустится из каталога [dir]; `null` —
  /// неизвестен (`env -C "$X"`).
  String? _commandDirectory(ShellSegment segment, String dir) {
    final launcherDir = segment.launcherDir;
    return launcherDir == null ? dir : context.target(launcherDir, dir);
  }

  /// Проверка сегмента: правила без каталога — один раз; правила с каталогом —
  /// для каждого известного каталога; правило D9 — для ⊤.
  ///
  /// [forceUnknown] — сегмент потребляет косвенно записанное значение
  /// переменной-команды: оно неизвестно, поэтому сегмент считается командой
  /// не из белого списка чтения, даже если сам только читает (D17, A5/L1).
  void _checkVariants(
    ShellSegment segment,
    DirVariants input, {
    bool forceUnknown = false,
  }) {
    final local = <String>{};
    // Пары (каталог, OLDPWD): `~-` в пути зависит от второго (D17, N9).
    final variants = <(String, String?)>{};
    var unknown = input.unknown;
    for (final v in input.known) {
      final dir = _commandDirectory(segment, v.dir);
      if (dir == null) {
        // `env -C "$X" cmd`, `sudo -D "$X" cmd`: ⊤ для одной простой команды.
        unknown = true;
      } else {
        variants.add((dir, v.oldPwd));
      }
    }
    if (variants.isEmpty && !unknown) {
      // Вход пуст только у самого первого сегмента пустого вложенного обхода:
      // метки, не зависящие от каталога, терять нельзя.
      variants.add((unknownWorkingDirectory, null));
    }
    _work += variants.length + 2;
    if (_work > maxDirWalkWork) {
      throw const ShellParseException('too many segment checks');
    }
    checkIndependent(segment, local);
    for (final (dir, oldPwd) in variants) {
      config.oldPwd = oldPwd;
      checkAt(segment, dir, local);
    }
    if (unknown) {
      // Абсолютные пути, `~`, `$HOME` не зависят от каталога (D9).
      config.oldPwd = null;
      checkAt(segment, unknownWorkingDirectory, local);
      if (!local.contains(agentConfigLabel) &&
          (forceUnknown || unknownCritical(segment))) {
        local.add(unknownLabel);
      }
    }
    config.oldPwd = null;
    found.addAll(local);
  }

  /// Состояние после сегмента (D3, D7).
  DirFlow _flow(ShellSegment segment, DirVariants input, DirFlow? evalFlow) {
    if (!mayChangeDirectory(segment)) {
      return DirFlow.same(input);
    }
    final first = segment.words.first;
    final mode = _launcherMode(segment);
    final DirFlow base;
    if (runsHiddenText(segment) ||
        isDynamicCommandWord(
          first,
          glob: segment.commandWordGlob,
          split: segment.commandWordSplit,
        )) {
      // Имя команды известно только при исполнении: это может быть `cd`
      // (D17, A2).
      _enableSeen = true;
      base = DirFlow.same(input.withUnknown());
    } else if (first == 'eval') {
      if (evalFlow == null || segment.arguments.any(isNonLiteral)) {
        // Нелитеральный текст `eval` может содержать любую встроенную.
        _enableSeen = true;
        base = DirFlow.same(input.union(evalFlow?.both ?? input).withUnknown());
      } else {
        base = evalFlow;
      }
    } else if (const {'cd', 'pushd', 'popd', 'dirs'}.contains(first)) {
      base = dirCommandFlow(
        first,
        segment.arguments,
        input,
        context,
        enabled: _enableSeen,
      );
    } else {
      return DirFlow.same(input);
    }
    // `time` — ключевое слово bash и внешняя программа dash: объединение
    // прежнего и нового без сужения по `&&`/`||` (D7).
    return mode == _LauncherMode.time
        ? DirFlow.same(input.union(base.both))
        : base;
  }

  /// Действие `trap` меняет состояние оболочки: может сменить каталог,
  /// определяет `alias` или функцию, пишет переменную-команду или переменную с
  /// динамическим именем (D18, W3).
  bool _scriptChangesShellState(ShellScript script) {
    var changes = false;
    visitScript(
      script,
      onSegment: (s) {
        final writes = variableWrites(s, includePrefix: s.words.isEmpty);
        changes =
            changes ||
            mayChangeDirectory(s) ||
            s.words.firstOrNull == 'alias' ||
            writes.dynamic ||
            writes.names.any(commandEnvironmentVariables.contains);
      },
      onBlock: (b) => changes = changes || b.kind == ShellBlockKind.function,
    );
    return changes;
  }
}

/// Сегмент может сменить каталог текущей оболочки (D17, A1, A2, A8): встроенные
/// `cd`/`pushd`/`popd`/`dirs`, `eval`, `trap` с действием, динамическое имя
/// команды, скрытый текст (`fc`, `history -s`, `mapfile -C`).
///
/// Почему общий предикат: переход сегмента (`_flow`) и проверка действия `trap`
/// должны решать одно и то же, иначе они расходятся. Цикл предикатом не
/// пользуется: его признак «тело меняет состояние» берётся по потоку (A1).
///
/// Внешний лаунчер (`env cd`, `/usr/bin/cd`) и `command -v` каталог не меняют.
bool mayChangeDirectory(ShellSegment segment) {
  final first = segment.words.firstOrNull;
  if (first == null ||
      segment.lookupOnly ||
      _launcherMode(segment) == _LauncherMode.external) {
    return false;
  }
  return runsHiddenText(segment) ||
      isDynamicCommandWord(
        first,
        glob: segment.commandWordGlob,
        split: segment.commandWordSplit,
      ) ||
      const {'cd', 'pushd', 'popd', 'dirs', 'eval'}.contains(first) ||
      first == 'trap' &&
          segment.nested.any((n) => n.origin == ShellOrigin.foreign);
}

_LauncherMode _launcherMode(ShellSegment segment) {
  var mode = _LauncherMode.builtin;
  for (final launcher in segment.launchers) {
    if (launcher == 'time') {
      mode = _LauncherMode.time;
    } else if (launcher != 'command' && launcher != 'builtin') {
      // В том числе `external command` (`/usr/bin/command`).
      return _LauncherMode.external;
    }
  }
  return mode;
}

/// Как лаунчеры сегмента влияют на встроенную команду (D7).
enum _LauncherMode {
  /// Без лаунчера, `command`, `builtin`: встроенная команда оболочки.
  builtin,

  /// `time`: объединение прежнего и нового состояния.
  time,

  /// `env`, `sudo`, `nohup`, `xargs` и другие: внешняя программа, каталог
  /// оболочки не меняется.
  external,
}
