/// Правила «запись в конфигурацию агента» для команд `exec` (PERM-11,
/// `agent-core/07-permissions.md` §7.6.1; решение пользователя 2026-11-03,
/// R5-2 и R5-4, change `add-config-writer-and-reload`).
///
/// Почему отдельный файл: таблица §7.6 — чистая функция от строки команды, а
/// защита конфигурации знает пути хоста, каталог запуска и `cd`, белый список
/// чтения, маски, git, распаковку архивов. Вместе они раздували
/// `critical_patterns.dart` и мешали читать саму таблицу.
///
/// Для чего: [isAgentConfigPath] — проектные пути §7.6.1; [ConfigCheck] —
/// превращает слово команды в абсолютный путь и отвечает, защищён ли он;
/// функции `touchesConfig`, `writesViaBroadDirectory`, `gitWipesTree`,
/// `replacesConfigAncestor`, `hardLinksConfig` — отдельные способы записи, все
/// дают метку `write to agent configuration`.
///
/// Как использовать: `findCritical` создаёт [ConfigCheck] на команду и
/// вызывает функции для каждого сегмента с текущим каталогом `dir`.
/// Неизвестная переменная в пути не защищена (§7.6); маска и скобки —
/// fail closed (`shell_glob.dart`).
library;

import '../util/posix_path.dart';
import 'agent_config_paths.dart';
import 'command_args.dart';
import 'shell_glob.dart';
import 'shell_lexer.dart';

/// Является ли путь путём конфигурации агента в проекте (§7.6.1).
///
/// Почему: конфигурацию агента правят только человек и клиенты, модель — нет
/// (PERM-11); одно и то же правило нужно `exec` и `write`/`edit`.
///
/// Для чего: [relativePath] — уже нормализованный путь относительно корня
/// сессии (POSIX); начальный `./` допускается. Совпадают
/// `.codelab/config*.yaml` (в том числе `config.yaml` и `config.local.yaml`),
/// `.codelab/cli.yaml` и всё внутри `.codelab/agents`, `skills`, `prompts`,
/// `hooks` — включая сами каталоги, ведь копирование в каталог пишет в него.
/// Сравнение без учёта регистра: на macOS файловая система обычно к нему
/// нечувствительна, и `.CodeLab/Config.yaml` — тот же файл.
///
/// Как использовать: политика вызывает для цели `write`/`edit` после
/// `relativeTo(root, normalizePath(root, path))`.
bool isAgentConfigPath(String relativePath) {
  var path = relativePath.toLowerCase();
  while (path.startsWith('./')) {
    path = path.substring(2);
  }
  final segments = [
    for (final s in path.split('/'))
      if (s.isNotEmpty && s != '.') s,
  ];
  if (segments.length < 2 || segments.first != '.codelab') {
    return false;
  }
  final second = segments[1];
  if (const {'agents', 'skills', 'prompts', 'hooks'}.contains(second)) {
    return true;
  }
  return segments.length == 2 &&
      (second == 'cli.yaml' ||
          second.startsWith('config') && second.endsWith('.yaml'));
}

/// Разбор целей правила `write to agent configuration` (§7.6.1, PERM-11).
///
/// Почему отдельный объект: проектные пути (`.codelab/**` относительно
/// корня сессии) и пути хоста сравниваются по одним правилам и от одного
/// каталога команды, а `cd` сдвигает этот каталог внутри команды.
///
/// Для чего: превращает слово команды в абсолютный путь (раскрыв `~`,
/// `$HOME`, `${HOME}`, `$CODELAB_HOME`, `${CODELAB_HOME}` значениями хоста) и
/// отвечает, защищён ли он. Слово с другой переменной не защищено: её
/// значение неизвестно (§7.6).
final class ConfigCheck {
  ConfigCheck(this.root, this.scope);

  /// Корень сессии: проектные пути §7.6.1 считаются от него.
  final String root;

  /// Пути хоста; `null` — хост их не передал.
  final AgentConfigScope? scope;

  /// [_absolute] для проверок вне класса.
  String? absoluteOf(String target, String dir) => _absolute(target, dir);

  String? _absolute(String target, String dir) {
    final expanded = scope?.expand(target) ?? target;
    if (expanded.contains(r'$') || expanded.startsWith('~')) {
      return null;
    }
    return normalizePath(dir, expanded);
  }

  /// Новый текущий каталог после `cd`/`pushd`; `null`, если путь неизвестен
  /// (`cd -`, `cd $X`) или это не путь.
  String? cdTarget(List<String> args, String dir) {
    final target = args.where((a) => !a.startsWith('-')).firstOrNull;
    if (target == null) {
      return scope?.expansions['HOME'];
    }
    return _absolute(target, dir);
  }

  /// Правка этого пути меняет конфигурацию агента: проектный путь §7.6.1 или
  /// путь хоста (сам или внутри защищаемого каталога). Слово с маской или
  /// фигурными скобками раскрывается консервативно: критично, если оно может
  /// указать на защищаемый путь (R5-4).
  bool isConfig(String target, String dir) {
    for (final variant in braceExpand(target)) {
      final expanded = scope?.expand(variant) ?? variant;
      if (hasMask(expanded)) {
        if (_maskHits(expanded, dir)) {
          return true;
        }
        continue;
      }
      final abs = _absolute(expanded, dir);
      if (abs == null) {
        continue;
      }
      if (_isProjectConfig(abs) || (scope?.covers(abs) ?? false)) {
        return true;
      }
    }
    return false;
  }

  /// Каталог конфигурации: `.codelab` проекта, защищаемый путь хоста (или
  /// каталог внутри него) либо непосредственный родитель защищаемого пути
  /// хоста (`~/.codelab`). Команда вне белого списка чтения с таким
  /// назначением или значением опции (`cp -r x/. ~/.codelab`, `tar -C …`)
  /// пишет в него (R5-4).
  bool isConfigDirectory(String target, String dir) {
    for (final variant in braceExpand(target)) {
      final expanded = scope?.expand(variant) ?? variant;
      if (hasMask(expanded)) {
        if (_maskHits(expanded, dir)) {
          return true;
        }
        continue;
      }
      final abs = _absolute(expanded, dir);
      if (abs != null && isConfigDirectoryAbs(abs)) {
        return true;
      }
    }
    return false;
  }

  /// [isConfigDirectory] для готового абсолютного пути; им же проверяется
  /// каталог запуска команды: всё, что команда вне белого списка читает или
  /// распаковывает «сюда», попадает в каталог конфигурации (R5-4).
  bool isConfigDirectoryAbs(String abs) =>
      _isProjectCodelab(abs) ||
      _isProjectConfig(abs) ||
      (scope?.covers(abs) ?? false) ||
      (scope?.isConfigParent(abs, root: root) ?? false);

  bool _isProjectConfig(String abs) =>
      isInside(root, abs) &&
      abs != root &&
      isAgentConfigPath(relativeTo(root, abs));

  /// Маска (`*?[`) или нераскрытые фигурные скобки в слове: fail closed
  /// (R5-4, PERM-11).
  ///
  /// Первая компонента с маской сравнивается с именами защищаемых потомков
  /// каталога перед ней: у хоста это `childNames`, у проекта — `.codelab` в
  /// корне и известные имена внутри `.codelab` (для `config*.yaml` ещё и
  /// совместимость литерального префикса и суффикса). Внутри уже
  /// защищаемого поддерева (`~/.codelab/agents/*.md`) критичен любой
  /// маскированный путь. `*`, `?`, `[` не совпадают с именем на точку, поэтому
  /// `rm *.o` в корне проекта обычная команда, а `rm .*` — нет.
  /// Широкий каталог-приёмник: корень запуска и всё выше него, любой предок
  /// защищаемого пути хоста или каталог конфигурации. Распаковка или
  /// синхронизация в него кладёт файлы с именами из содержимого архива, так
  /// что `.codelab/config.yaml` может появиться без единого слова-пути в
  /// команде (R5-4, повторное ревью).
  bool isBroadDestination(String target, String dir) {
    final abs = _absolute(target, dir);
    if (abs == null) {
      return false;
    }
    return isInside(abs, '${root == '/' ? '' : root}/.codelab') ||
        isConfigDirectoryAbs(abs) ||
        (scope?.isAncestor(abs) ?? false);
  }

  /// Каталог запуска команды — каталог конфигурации (R5-4).
  bool isConfigWorkingDir(String dir) => isConfigDirectoryAbs(dir);

  bool _maskHits(String expanded, String dir) {
    if (expanded.contains(r'$')) {
      return false;
    }
    final parts = expanded.split('/');
    final k = parts.indexWhere(hasMask);
    if (k < 0) {
      return false;
    }
    final head = parts.sublist(0, k).join('/');
    final base = head.isEmpty ? (expanded.startsWith('/') ? '/' : '.') : head;
    final abs = _absolute(base, dir);
    if (abs == null) {
      return false;
    }
    final glob = parts[k];
    if (_isProjectConfig(abs) || (scope?.covers(abs) ?? false)) {
      return true;
    }
    if (abs == root && globMatches(glob, '.codelab', ignoreCase: true)) {
      return true;
    }
    if (_isProjectCodelab(abs) && _globMayHitProjectConfig(glob)) {
      return true;
    }
    final insensitive = scope?.caseInsensitive ?? false;
    return (scope?.childNames(abs) ?? const <String>{}).any(
      (name) => globMatches(glob, name, ignoreCase: insensitive),
    );
  }

  /// Каталог-предок защищаемых путей: `.codelab` проекта либо родитель
  /// защищаемого пути хоста.
  bool isAncestor(String target, String dir, {bool destination = false}) {
    final abs = _absolute(target, dir);
    if (abs == null) {
      return false;
    }
    if (_isProjectCodelab(abs)) {
      return true;
    }
    final scope = this.scope;
    if (scope == null) {
      return false;
    }
    return destination ? scope.isMissingAncestor(abs) : scope.isAncestor(abs);
  }

  bool _isProjectCodelab(String abs) =>
      isInside(root, abs) &&
      abs != root &&
      relativeTo(root, abs).toLowerCase() == '.codelab';
}

/// `ln`, `mv`, `rm`, `rmdir`, `mkdir`, `rename` с каталогом-предком
/// защищаемых путей создают, переименовывают, удаляют каталог или подменяют
/// его ссылкой: после этого путь конфигурации указывает в другое место
/// (§7.6.1, «подмена предка ссылкой»).
bool replacesConfigAncestor(
  ShellSegment segment,
  ConfigCheck config,
  String dir,
) {
  final args = segment.arguments;
  if (const {'ln', 'mv'}.contains(segment.commandName)) {
    // Назначение-предок опасно, только если его ещё нет; источник — всегда.
    final (:destinations, :sources, targets: _) = copyTargets(args);
    return sources.any((t) => config.isAncestor(t, dir)) ||
        destinations.any((t) => config.isAncestor(t, dir, destination: true));
  }
  final paths = switch (segment.commandName) {
    'rm' || 'rmdir' || 'rename' => positionalArgs(args),
    'mkdir' => positionalArgs(args, withValue: const {'-m', '--mode'}),
    _ => null,
  };
  return paths != null && paths.any((t) => config.isAncestor(t, dir));
}

/// Жёсткая ссылка: `ln` без `-s` и `cp -l`/`cp --link`. Защищаемый путь в
/// любой позиции (источник или цель) — критический: ссылка из другого места
/// позволила бы править файл в обход сравнения путей (§7.6.1).
bool hardLinksConfig(ShellSegment segment, ConfigCheck config, String dir) {
  final args = segment.arguments;
  final hard = switch (segment.commandName) {
    'ln' => !hasShortFlag(args, 's') && !args.contains('--symbolic'),
    'cp' => hasShortFlag(args, 'l') || args.contains('--link'),
    _ => false,
  };
  return hard && _linkedPaths(args).any((t) => config.isConfig(t, dir));
}

/// Источники и назначение `cp`/`mv`/`ln` (с учётом `-t DIR`).
List<String> _linkedPaths(List<String> args) {
  final (:destinations, :sources, targets: _) = copyTargets(args);
  return [...sources, ...destinations];
}

/// Имена проекта, на которые маска внутри `.codelab` может указать (§7.6.1).
const _projectConfigNames = [
  'config.yaml',
  'config.local.yaml',
  'cli.yaml',
  'agents',
  'skills',
  'prompts',
  'hooks',
];

/// Может ли маска [glob] внутри `.codelab` проекта совпасть с `cli.yaml`,
/// каталогами или `config*.yaml`: для последнего достаточно, чтобы
/// литеральный префикс маски был совместим с `config`, а суффикс — с `.yaml`
/// (`config.tmp*` может быть `config.tmp.yaml`).
bool _globMayHitProjectConfig(String glob) {
  if (_projectConfigNames.any((n) => globMatches(glob, n, ignoreCase: true))) {
    return true;
  }
  final lower = glob.toLowerCase();
  final first = lower.indexOf(maskChars);
  final last = lower.lastIndexOf(maskChars);
  if (first < 0) {
    return false;
  }
  final prefix = lower.substring(0, first);
  final suffix = lower.substring(last + 1);
  return (prefix.startsWith('config') || 'config'.startsWith(prefix)) &&
      (suffix.isEmpty || suffix.endsWith('.yaml') || '.yaml'.endsWith(suffix));
}

/// Команды только чтения: слово-аргумент в защищаемый путь их не делает
/// критичными (белый список чтения для `exec`, R5-4, PERM-11, §7.6.1).
const _readOnlyCommands = {
  'cat', 'less', 'more', 'head', 'tail', 'grep', 'egrep', 'fgrep', 'rg', 'ag',
  'ls', 'stat', 'file', 'wc', 'diff', 'cmp', 'sha256sum', 'shasum', 'md5sum',
  'realpath', 'readlink', 'dirname', 'basename', 'echo', 'printf', 'test', //
  '[', '[[',
};

/// Встроенные команды, которые сами ничего не пишут: `cd` сдвигает каталог
/// (его ведёт `_walk`), `eval`/`source`/`.` и `sh -c` исполняют вложенный
/// текст, который проверяется как отдельные сегменты.
const _noWriteBuiltins = {'cd', 'pushd', 'popd', 'eval', 'source', '.', ':'};

/// Команда сегмента — только чтение (R5-4). `jq`/`yq` без правки на месте,
/// `git` — только `diff|log|show|status|blame` без `--output`, `less` без
/// файла журнала; `sed`, `sort`, `find`, `cp`, `tar` и прочее не в списке.
bool _isReadOnly(ShellSegment segment) {
  final name = segment.commandName;
  final args = segment.arguments;
  if (name == null) {
    return true;
  }
  if (_noWriteBuiltins.contains(name)) {
    return true;
  }
  if (shellNames.contains(name) && segment.nested.isNotEmpty) {
    return true;
  }
  // Исключения списка: у «читателей» есть опции, которые пишут файлы или
  // исполняют команды (`yq -i`, `rg --pre`, `git -c core.pager=…`), поэтому
  // такая форма уже не «только чтение» (R5-4, повторное ревью).
  bool anyArg(bool Function(String a) test) =>
      args.any((a) => a != '--' && test(a));
  bool shortCluster(String a, String letters) =>
      !a.startsWith('--') && RegExp('^-[A-Za-z]*[$letters]').hasMatch(a);
  bool longOption(String a, Iterable<String> names) =>
      names.any((n) => a == n || a.startsWith('$n='));
  switch (name) {
    case 'less':
      return !anyArg(
        (a) =>
            longOption(a, const ['--log-file', '--LOG-FILE']) ||
            shortCluster(a, 'oO'),
      );
    case 'jq' || 'yq':
      return !anyArg(
        (a) =>
            a.startsWith('--in-place') ||
            a.startsWith('--inplace') ||
            a.startsWith('--split-exp') ||
            shortCluster(a, 'is'),
      );
    case 'rg' || 'ag':
      return !anyArg(
        (a) =>
            longOption(a, const ['--pre', '--pre-glob', '--search-zip']) ||
            shortCluster(a, 'z'),
      );
    case 'file':
      return !anyArg((a) => a == '--compile' || shortCluster(a, 'C'));
    case 'git':
      final parsed = gitSubcommand(args);
      return parsed != null &&
          const {
            'diff',
            'log',
            'show',
            'status',
            'blame',
          }.contains(parsed.subcommand) &&
          // Глобальные опции, подменяющие конфиг или каталог (`-c`,
          // `--config-env`, `--exec-path`, `--git-dir`, `--work-tree`),
          // запускают произвольные команды (`core.pager`, `core.fsmonitor`).
          !parsed.globals.any(
            (g) =>
                g == '-c' ||
                g.length > 2 && g.startsWith('-c') && !g.startsWith('--') ||
                longOption(g, const [
                  '--config-env',
                  '--exec-path',
                  '--git-dir',
                  '--work-tree',
                ]),
          ) &&
          !parsed.rest.any(
            (a) =>
                a.startsWith('--output') ||
                a == '--ext-diff' ||
                a == '--textconv',
          );
  }
  return _readOnlyCommands.contains(name);
}

/// Предел длины слова-кластера коротких флагов (`-sSo…`): перебор суффиксов
/// квадратичен по длине, а настоящие кластеры короче. Более длинное слово
/// у команды вне белого списка чтения даёт `unparsable command`
/// ([touchesConfig]): метка «write to agent configuration» вводила бы в
/// заблуждение на длинных `-I<путь>` и `-d{json}`, а неразбираемая команда
/// и так требует решения человека (правило 8 §7.6, fail closed).
const _maxClusterLength = 256;

/// Значения слова-аргумента, которые могут быть путём: само слово, значение
/// после `=` (`--output=FILE`, `of=FILE`) и приклеенное к короткой опции
/// (`-oFILE`).
///
/// Кластер коротких флагов со значением у последнего (`curl -sSo/path`,
/// `wget -q4O$VAR/f`): значение начинается после любого символа кластера
/// (флаги бывают и цифрами: `-1`, `-4`), а какая опция его берёт, неизвестно,
/// поэтому перебираются суффиксы, похожие на путь: начинаются с `/`, `~`, `.`
/// или `$` либо содержат `/`. Относительное имя без этих признаков
/// (`-sSoconfig.yaml`) ловится правилом «команда в каталоге конфигурации».
/// Лишние кандидаты дают ложные срабатывания, но не пропуски (PERM-11,
/// `07-permissions` §7.6.1). Слово длиннее [_maxClusterLength] сюда не
/// попадает — [touchesConfig] считает его неразбираемым.
Iterable<String> _pathCandidates(String word) sync* {
  yield word;
  final eq = word.indexOf('=');
  if (eq > 0) {
    yield word.substring(eq + 1);
  }
  if (_isShortCluster(word) && word.length <= _maxClusterLength) {
    yield word.substring(2);
    final lastSlash = word.lastIndexOf('/');
    for (var i = 3; i < word.length; i++) {
      if ('/~.\$'.contains(word[i]) || lastSlash >= i) {
        yield word.substring(i);
      }
    }
  }
}

/// Слово — кластер коротких флагов (`-sSo…`): один дефис и не менее двух
/// символов после него; длинные опции (`--…`) и одиночный `-` не в счёт.
bool _isShortCluster(String word) =>
    word.startsWith('-') && !word.startsWith('--') && word.length > 2;

/// Правило R5-4: команда вне белого списка чтения, у которой слово-аргумент
/// или значение опции — защищаемый путь либо каталог конфигурации, либо
/// запущенная в каталоге конфигурации, пишет в конфигурацию агента
/// (`curl -o`, `tar -C`, `git checkout --`, `perl -pi`, `unzip -d`, …).
///
/// Корень запуска и `HOME` не каталоги конфигурации: `cp -r src dst`,
/// `make`, `npm test` в корне остаются обычными (запись внутрь них ловится
/// сравнением конкретных путей, разрушение — `replacesConfigAncestor`).
bool touchesConfig(ShellSegment segment, ConfigCheck config, String dir) {
  if (segment.launcherOutputs.any((t) => config.isConfig(t, dir))) {
    return true;
  }
  if (_isReadOnly(segment)) {
    return false;
  }
  if (config.isConfigWorkingDir(dir)) {
    return true;
  }
  for (final word in segment.arguments) {
    if (_isShortCluster(word) && word.length > _maxClusterLength) {
      throw const ShellParseException('option cluster is too long');
    }
    for (final candidate in _pathCandidates(word)) {
      if (config.isConfig(candidate, dir) ||
          config.isConfigDirectory(candidate, dir)) {
        return true;
      }
    }
  }
  return false;
}

/// Подкоманды `git`, которые массово стирают или откатывают рабочее дерево
/// (R5-4, R5-2, PERM-11): вместе с деревом уходит и `.codelab` проекта.
/// Хоста и файловой системы ядро не видит, поэтому корень запуска считается
/// содержащим `.codelab` всегда (консервативно). Безопасные формы
/// (`status`, `diff`, `add`, `commit`, `checkout <ветка>` без force,
/// `stash list|show`, `clean -n`) не затрагиваются.
bool gitWipesTree(List<String> args, ConfigCheck config, String dir) {
  final parsed = gitSubcommand(args);
  if (parsed == null) {
    return false;
  }
  final (:subcommand, :rest, globals: _) = parsed;
  bool flag(String letter, Set<String> long) => rest.any(
    (a) => a == '--'
        ? false
        : long.contains(a) ||
              shortFlagPattern.hasMatch(a) && a.contains(letter),
  );
  final force = flag('f', const {'--force', '--discard-changes'});
  // Путь, покрывающий `.codelab` проекта: `.`, корень, `..` и выше.
  bool coversCodelab() {
    final codelab = '${config.root == '/' ? '' : config.root}/.codelab';
    return positionalArgs(rest).any((p) {
      final abs = config.absoluteOf(p, dir);
      return abs != null && isInside(abs, codelab);
    });
  }

  switch (subcommand) {
    case 'clean':
      return force;
    case 'checkout':
      return force || coversCodelab();
    case 'switch':
      return force;
    case 'restore':
      return coversCodelab();
    case 'reset':
      return rest.contains('--hard');
    case 'checkout-index':
      return flag('a', const {'--all'}) || force;
    case 'read-tree':
      return flag('u', const {});
    case 'stash':
      final sub = positionalArgs(rest).firstOrNull;
      return !const {'list', 'show'}.contains(sub);
  }
  return false;
}

/// Распаковка, синхронизация и применение патчей в широкий каталог
/// (корень запуска, каталог запуска, предок защищаемого пути, каталог
/// конфигурации): состав записываемых путей задан содержимым архива, патча
/// или источником, а не словами команды, поэтому критично всегда, когда
/// приёмник широкий (R5-4, PERM-11, §7.6.1).
///
/// Приёмник по умолчанию — каталог запуска [dir]. `git apply`, `git am` и
/// `patch` критичны в любой форме: пути лежат внутри патча.
bool writesViaBroadDirectory(
  ShellSegment segment,
  ConfigCheck config,
  String dir,
) {
  if (segment.riskyEnvironment) {
    return true;
  }
  final name = segment.commandName;
  final args = segment.arguments;
  if (name == null) {
    return false;
  }
  bool broad(String? target) => config.isBroadDestination(target ?? '.', dir);
  switch (name) {
    case 'patch':
      return true;
    case 'git':
      final parsed = gitSubcommand(args);
      // `--config-env` подставляет значение из окружения, которого ядро не
      // видит: что git исполнит, неизвестно — критично всегда (fail closed).
      return parsed != null &&
              (parsed.subcommand == 'apply' || parsed.subcommand == 'am') ||
          args.any(
            (a) => a == '--config-env' || a.startsWith('--config-env='),
          ) ||
          _gitRiskyConfig(args);
    case 'tar' || 'bsdtar' || 'gtar':
      final extract = args.any(
        (a) =>
            a == '--extract' ||
            a == '--get' ||
            !a.startsWith('--') &&
                RegExp(r'^-?[A-Za-z]*x').hasMatch(a) &&
                a == args.first ||
            !a.startsWith('--') && RegExp(r'^-[A-Za-z]*x').hasMatch(a),
      );
      return extract &&
          broad(_optionValue(args, const {'-C'}, const {'--directory'}));
    case 'ditto':
      // `ditto` всегда сливает содержимое источника в приёмник.
      return broad(positionalArgs(args).lastOrNull);
    case 'jar':
      final mode = args.firstOrNull ?? '';
      return RegExp(r'^-?[A-Za-z]*x').hasMatch(mode) && broad(null);
    case 'unzip':
      final listing = args.any(
        (a) => !a.startsWith('-')
            ? false
            : RegExp(r'^-[A-Za-z]*[ltpvZ]').hasMatch(a),
      );
      return !listing && broad(_optionValue(args, const {'-d'}, const {}));
    case 'cpio':
      final pass = args.any(
        (a) => !a.startsWith('--') && RegExp(r'^-[A-Za-z]*p').hasMatch(a),
      );
      if (pass) {
        return broad(positionalArgs(args).lastOrNull);
      }
      final extract = args.any(
        (a) =>
            a == '--extract' ||
            !a.startsWith('--') && RegExp(r'^-[A-Za-z]*i').hasMatch(a),
      );
      return extract &&
          broad(_optionValue(args, const {'-D'}, const {'--directory'}));
    case '7z' || '7za' || '7zr' || '7zz':
      final mode = positionalArgs(args).firstOrNull;
      if (mode != 'x' && mode != 'e') {
        return false;
      }
      final out = args.where((a) => a.startsWith('-o') && a.length > 2);
      return broad(out.isEmpty ? null : out.last.substring(2));
    case 'rsync':
      const withValue = {
        '-e',
        '--rsh',
        '--exclude',
        '--include',
        '-f',
        '--filter',
        '--exclude-from',
        '--include-from',
        '--files-from',
        '--backup-dir',
        '-T',
        '--temp-dir',
        '--partial-dir',
        '--log-file',
        '--port',
        '--bwlimit',
        '--max-size',
        '--min-size',
        '--compare-dest',
        '--copy-dest',
        '--link-dest',
        '--suffix',
      };
      final positional = positionalArgs(args, withValue: withValue);
      return positional.length >= 2 && broad(positional.last);
    case 'cp':
      // Слияние содержимого (`cp -r evil/. .`, `cp -r evil/* .`) пишет файлы
      // с именами из источника; `cp -r src .` кладёт только `./src`, это
      // ловит сравнение целей.
      final recursive =
          hasRecursiveFlag(args) ||
          hasShortFlag(args, 'a') ||
          args.contains('--archive');
      final (:destinations, :sources, targets: _) = copyTargets(args);
      return recursive &&
          destinations.any((d) => broad(d)) &&
          sources.any(
            (src) =>
                src == '.' ||
                src.endsWith('/.') ||
                src.endsWith('/..') ||
                // BSD `cp` (macOS): `src/` с косой чертой сливает содержимое.
                src.endsWith('/') ||
                hasMask(src),
          );
  }
  return false;
}

/// Значение опции [short]/[long] (`-C DIR`, `--directory=DIR`,
/// `--directory DIR`); последнее вхождение, `null` — опции нет.
String? _optionValue(List<String> args, Set<String> short, Set<String> long) {
  String? value;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (short.contains(a) || long.contains(a)) {
      if (i + 1 < args.length) {
        value = args[i + 1];
      }
    } else {
      for (final l in long) {
        if (a.startsWith('$l=')) {
          value = a.substring(l.length + 1);
        }
      }
    }
  }
  return value;
}

/// Ключи `git -c`, подгружающие чужой конфиг или хуки (`core.hooksPath`,
/// `include.path`, `includeIf.*`): что исполнится, неизвестно — критично
/// всегда (fail closed, R5-4).
bool _gitRiskyConfig(List<String> args) {
  final risky = RegExp(
    r'^(core\.hookspath|include\.path|includeif\..*)=',
    caseSensitive: false,
  );
  final globals = gitSubcommand(args)?.globals ?? const <String>[];
  for (var i = 0; i < globals.length; i++) {
    final g = globals[i];
    if (g == '-c' && i + 1 < globals.length && risky.hasMatch(globals[i + 1]) ||
        g.length > 2 &&
            g.startsWith('-c') &&
            !g.startsWith('--') &&
            risky.hasMatch(g.substring(2))) {
      return true;
    }
  }
  return false;
}
