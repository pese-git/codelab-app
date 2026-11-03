/// Критические шаблоны команд `exec` (`agent-core/07-permissions.md` §7.6) и
/// пути конфигурации агента (§7.6.1).
///
/// Почему: некоторые команды необратимы или выводят агента из-под контроля
/// человека (`rm -rf /`, `curl … | sh`, правка `.codelab/config.yaml`). Для
/// них вопрос задаётся в любом режиме, даже после «разрешить всегда», а в
/// `autopilot` — отказ (PERM-2, PERM-9, PERM-11). Таблица меток и выражение
/// fork-бомбы взяты из нашего документа §7.6, а не из стороннего кода
/// (design.md change `add-agent-core-permission-policy`, D6; `AGENTS.md` §5).
///
/// Для чего: [findCritical] — шаг 3 алгоритма `decide` политики разрешений;
/// [isAgentConfigPath] — общая проверка путей §7.6.1 для `exec` и для
/// `write`/`edit` (живёт в `agent_config_rules.dart`, здесь реэкспорт). Здесь
/// остаются таблица §7.6 и обход сегментов; правила конфигурации агента —
/// `agent_config_rules.dart`, маски — `shell_glob.dart`, разбор аргументов —
/// `command_args.dart`.
///
/// Как использовать: политика вызывает `findCritical(command, cwd: root)` для
/// `exec` и показывает `reason: 'critical command: ${match.label}'`.
library;

import '../util/posix_path.dart';
import 'agent_config_paths.dart';
import 'agent_config_rules.dart';
import 'command_args.dart';
import 'shell_lexer.dart';

// `policy.dart` и тесты берут проверку проектных путей отсюда (§7.6.1).
export 'agent_config_rules.dart' show isAgentConfigPath;

/// Совпадение с критическими шаблонами.
///
/// Почему: в одной команде может совпасть несколько строк таблицы, а
/// `reason` перечисляет все метки через `; ` (§7.6).
///
/// Для чего: [labels] — метки в порядке строк таблицы §7.6 без повторов,
/// либо единственная `unparsable command`; [label] — готовый текст причины.
///
/// Как использовать: возвращается из [findCritical]; `null` там — «не
/// критическая».
final class CriticalMatch {
  /// Создаётся [findCritical]; в тестах политики — напрямую.
  const CriticalMatch(this.labels);

  /// Метки совпавших строк таблицы §7.6.
  final List<String> labels;

  /// Метки через `; ` для `reason`.
  String get label => labels.join('; ');

  @override
  String toString() => 'CriticalMatch($label)';
}

/// Метка сломанной или слишком глубокой команды (§7.6, правило 8; D6).
const unparsableCommandLabel = 'unparsable command';

const _rmProtected = 'recursive delete of a protected path';
const _gitDirectory = 'deletion of a .git directory';
const _findProtected = 'recursive find delete of a protected path';
const _permissionsProtected = 'recursive permission change of a protected path';
const _privileged = 'privileged command';
const _forkBombLabel = 'fork bomb';
const _diskDevice = 'write to a disk device';
const _format = 'filesystem format or wipe';
const _accountFile = 'overwrite of a system account file';
const _sshConfig = 'write to ssh configuration';
const _downloadExecute = 'download and execute';
const _shutdown = 'host shutdown or reboot';
const _killAll = 'kill of init or all processes';
const _agentConfig = 'write to agent configuration';
const _gitPush = 'git force push or remote branch deletion';
const _gitRewrite = 'git history rewrite';

/// Порядок строк таблицы §7.6 — порядок меток в [CriticalMatch.labels].
const _tableOrder = [
  _rmProtected,
  _gitDirectory,
  _findProtected,
  _permissionsProtected,
  _privileged,
  _forkBombLabel,
  _diskDevice,
  _format,
  _accountFile,
  _sshConfig,
  _downloadExecute,
  _shutdown,
  _killAll,
  _agentConfig,
  _gitPush,
  _gitRewrite,
];

/// Функция, которая в теле вызывает себя в конвейере и уходит в фон
/// (выражение `forkBomb` из §7.6). Применяется к исходной строке команды.
final forkBomb = RegExp(r'(\w+|:)\s*\(\s*\)\s*\{[^}]*\1\s*\|\s*\1\s*&');

/// Ищет критические шаблоны §7.6 в команде `exec`.
///
/// Почему: см. библиотеку; разбор — [parseShell], поэтому текст в кавычках
/// не считается командой, а `sh -c`, `eval` и подстановки — считаются.
///
/// Для чего: `null` — команда не критическая; иначе [CriticalMatch] со
/// всеми метками. Ошибка разбора или вложенность глубже 4 дают
/// `CriticalMatch(['unparsable command'])`.
///
/// Как использовать: [cwd] — абсолютный POSIX-корень сессии; от него
/// нормализуются цели правила `write to agent configuration` (§7.6.1) и
/// относительные пути защищённых целей. [commandCwd] — каталог, в котором
/// запускается команда (аргумент `cwd` инструмента `exec`), по умолчанию
/// [cwd]; `cd` внутри команды сдвигает его для следующих слов. [agentConfig] —
/// пути конфигурации агента от хоста (PERM-11, D8) в пересчитанном виде:
/// запись в них, жёсткая ссылка на них и подмена их каталогов-предков
/// совпадают с тем же правилом `write to agent configuration`.
CriticalMatch? findCritical(
  String command, {
  String cwd = '/',
  String? commandCwd,
  AgentConfigScope? agentConfig,
}) {
  final ShellScript script;
  try {
    script = parseShell(command);
  } on ShellParseException {
    return const CriticalMatch([unparsableCommandLabel]);
  }
  final root = normalizePath('/', cwd) ?? '/';
  final start = commandCwd == null
      ? root
      : normalizePath(root, commandCwd) ?? root;
  final config = ConfigCheck(root, agentConfig);
  final found = <String>{};
  if (forkBomb.hasMatch(command)) {
    found.add(_forkBombLabel);
  }
  for (final pipeline in script.allPipelines) {
    _checkPipeline(pipeline, found);
  }
  _walk(script, root, config, start, found);
  if (found.isEmpty) {
    return null;
  }
  return CriticalMatch([
    for (final label in _tableOrder)
      if (found.contains(label)) label,
  ]);
}

/// Обходит сегменты по порядку записи и ведёт текущий каталог: `cd` сдвигает
/// его для следующих сегментов, поэтому `cd ~/.codelab && echo x > config.yaml`
/// пишет в защищаемый файл (§7.6.1). Подоболочка и подстановка получают копию
/// каталога; ошибка в оценке `cd` (неизвестная переменная) каталог не меняет.
void _walk(
  ShellScript script,
  String root,
  ConfigCheck config,
  String dir,
  Set<String> found,
) {
  var current = dir;
  for (final pipeline in script.pipelines) {
    for (final segment in pipeline.stages) {
      // `env -C DIR cmd` / `sudo -D DIR cmd` запускают команду в DIR, но
      // следующие сегменты остаются в прежнем каталоге.
      final launcherDir = segment.launcherDir;
      final here = launcherDir == null
          ? current
          : config.cdTarget([launcherDir], current) ?? current;
      _checkSegment(segment, root, config, here, found);
      for (final nested in segment.nested) {
        _walk(nested, root, config, here, found);
      }
      if (const {'cd', 'pushd'}.contains(segment.commandName)) {
        current = config.cdTarget(segment.arguments, current) ?? current;
      }
    }
  }
}

const _downloaders = {'curl', 'wget', 'fetch'};
const _interpreters = {
  ...shellNames,
  'fish',
  'python',
  'python3',
  'perl',
  'ruby',
  'node',
};

/// Команды, которые исполняют свой вложенный текст: `eval`, `source`, `.`
/// и shell (`sh -c "$(curl u)"`, `bash <(curl u)`).
const _executesNested = {...shellNames, 'fish', 'eval', 'source', '.'};

const _protectedLiterals = {
  '/',
  '/*',
  '~',
  '~/',
  '~/*',
  r'$HOME',
  r'${HOME}',
  r'$HOME/',
  r'$HOME/*',
  r'${HOME}/',
  r'${HOME}/*',
  '.',
  './',
  '*',
  './*',
  '..',
  '../',
  '../*',
};

const _systemDirectories = {
  '/bin',
  '/boot',
  '/dev',
  '/etc',
  '/home',
  '/lib',
  '/lib64',
  '/opt',
  '/proc',
  '/root',
  '/sbin',
  '/sys',
  '/usr',
  '/var',
  '/Applications',
  '/Library',
  '/System',
  '/Users',
};

const _accountFiles = {
  '/etc/passwd',
  '/etc/shadow',
  '/etc/group',
  '/etc/sudoers',
};

final _diskDevicePath = RegExp(r'^/dev/(sd|hd|vd|xvd|nvme|disk|rdisk|mmcblk)');
const _protectedBranches = {'main', 'master', 'develop', 'trunk'};

/// «Скачать и выполнить» в одном конвейере: стадия загрузчика и любая
/// последующая стадия интерпретатора (`curl x | sh`).
void _checkPipeline(ShellPipeline pipeline, Set<String> found) {
  var downloaded = false;
  for (final stage in pipeline.stages) {
    final name = stage.commandName;
    if (downloaded && _interpreters.contains(name)) {
      found.add(_downloadExecute);
      return;
    }
    if (_downloaders.contains(name)) {
      downloaded = true;
    }
  }
}

void _checkSegment(
  ShellSegment segment,
  String root,
  ConfigCheck config,
  String dir,
  Set<String> found,
) {
  final name = segment.commandName;
  final args = segment.arguments;
  if (segment.privileged) {
    found.add(_privileged);
  }
  final writes = _WriteTargets.of(segment);
  if (writes.redirections.any((t) => _isDiskDevice(t, root)) ||
      name == 'dd' &&
          args.any(
            (a) => a.startsWith('of=') && _isDiskDevice(a.substring(3), root),
          )) {
    found.add(_diskDevice);
  }
  if (writes.common.any((t) => _isAccountFile(t, root))) {
    found.add(_accountFile);
  }
  if (writes.common.any(_isSshPath)) {
    found.add(_sshConfig);
  }
  if (writes.agentConfig.any((t) => config.isConfig(t, dir)) ||
      writes.directories.any((t) => config.isConfigDirectory(t, dir)) ||
      replacesConfigAncestor(segment, config, dir) ||
      hardLinksConfig(segment, config, dir) ||
      touchesConfig(segment, config, dir) ||
      writesViaBroadDirectory(segment, config, dir)) {
    found.add(_agentConfig);
  }
  if (_executesNested.contains(name) &&
      segment.nested.any(
        (script) =>
            script.allSegments.any((s) => _downloaders.contains(s.commandName)),
      )) {
    found.add(_downloadExecute);
  }
  switch (name) {
    case 'rm':
      final recursive = hasRecursiveFlag(args);
      final targets = positionalArgs(args);
      if (args.contains('--no-preserve-root') ||
          recursive && targets.any((t) => _isProtected(t, root))) {
        found.add(_rmProtected);
      }
      if (recursive && targets.any(_isGitDirectory)) {
        found.add(_gitDirectory);
      }
    case 'find':
      if (_findDeletes(args) && _isProtected(_findStart(args), root)) {
        found.add(_findProtected);
      }
    case 'chmod' || 'chown' || 'chgrp':
      if (hasRecursiveFlag(args) &&
          positionalArgs(args).any((t) => _isProtected(t, root))) {
        found.add(_permissionsProtected);
      }
    case 'sudo' || 'doas' || 'su' || 'pkexec':
      found.add(_privileged);
    case 'shutdown' || 'reboot' || 'halt' || 'poweroff':
      found.add(_shutdown);
    case 'init':
      if (const {'0', '6'}.contains(positionalArgs(args).firstOrNull)) {
        found.add(_shutdown);
      }
    case 'systemctl':
      if (const {
        'poweroff',
        'reboot',
        'halt',
      }.contains(positionalArgs(args).firstOrNull)) {
        found.add(_shutdown);
      }
    case 'kill':
      if (_killTargets(args).any((t) => t == '1' || t == '-1')) {
        found.add(_killAll);
      }
    case 'git':
      _checkGit(args, found);
      if (gitWipesTree(args, config, dir)) {
        found.add(_agentConfig);
      }
    case final String n when _isFormatCommand(n, args, root):
      found.add(_format);
  }
}

/// Цели записи сегмента по видам: правила таблицы §7.6 различаются тем,
/// какие способы записи они учитывают.
final class _WriteTargets {
  _WriteTargets(
    this.redirections,
    this.common,
    this.agentConfig,
    this.directories,
  );

  /// Только перенаправления — для дисковых устройств.
  final List<String> redirections;

  /// Перенаправления, `tee`, `cp`/`mv` — для системных файлов и ssh.
  final List<String> common;

  /// [common], `ln` и `sed -i` — для конфигурации агента (§7.6.1).
  final List<String> agentConfig;

  /// Назначения `cp`/`mv`/`ln`/`install`: `mv evil .codelab` заменяет
  /// каталог конфигурации целиком.
  final List<String> directories;

  factory _WriteTargets.of(ShellSegment segment) {
    final redirections = [
      for (final r in segment.redirections)
        if (r.writes) r.target,
    ];
    final args = segment.arguments;
    final common = [...redirections];
    final agentConfig = <String>[];
    final directories = <String>[];
    switch (segment.commandName) {
      case 'tee':
        common.addAll(positionalArgs(args));
      case 'cp' || 'mv':
        final (:destinations, :targets, :sources) = copyTargets(args);
        common.addAll(targets);
        // Цели `dst/<имя источника>` проверяются и как каталоги: `cp -r
        // evil/.codelab .` вливает чужой `.codelab` в `./.codelab` (R5-4).
        directories.addAll([...destinations, ...targets]);
        if (segment.commandName == 'mv') {
          // Перенос защищаемого файла в другое место убирает его с пути.
          agentConfig.addAll(sources);
        }
      case 'install':
        final (:destinations, :targets, sources: _) = copyTargets(
          args,
          withValue: _installWithValue,
        );
        agentConfig.addAll(targets);
        directories.addAll(destinations);
      case 'ln':
        final (:destinations, :targets, sources: _) = copyTargets(args);
        agentConfig.addAll(targets);
        directories.addAll(destinations);
      case 'rename' || 'rm' || 'unlink':
        // Удаление или переименование защищаемого файла так же выводит
        // конфигурацию из-под контроля человека, как запись (решение
        // пользователя 2026-11-03).
        agentConfig.addAll(positionalArgs(args));
      case 'truncate':
        agentConfig.addAll(
          positionalArgs(
            args,
            withValue: const {'-s', '--size', '-r', '--reference'},
          ),
        );
      case 'dd':
        agentConfig.addAll([
          for (final a in args)
            if (a.startsWith('of=')) a.substring(3),
        ]);
      case 'sed' when _sedInPlace(args):
        agentConfig.addAll(_sedFiles(args));
    }
    return _WriteTargets(redirections, common, [
      ...common,
      ...agentConfig,
    ], directories);
  }
}

/// Опции `install` со значением сверх общих для `cp`/`mv`/`ln`.
const _installWithValue = {
  '-t',
  '-S',
  '--target-directory',
  '--suffix',
  '-m',
  '--mode',
  '-o',
  '--owner',
  '-g',
  '--group',
};

bool _sedInPlace(List<String> args) => args.any(
  (a) =>
      a == '--in-place' ||
      a.startsWith('--in-place=') ||
      !a.startsWith('--') && RegExp(r'^-[A-Za-z]*i').hasMatch(a),
);

/// Файлы `sed`: без `-e`/`-f` первое позиционное слово — сам скрипт.
List<String> _sedFiles(List<String> args) {
  final hasScriptOption = args.any(
    (a) =>
        a == '-e' ||
        a == '-f' ||
        a.startsWith('--expression') ||
        a.startsWith('--file'),
  );
  final positionals = positionalArgs(
    args,
    withValue: const {'-e', '-f', '-l', '--expression', '--file'},
  );
  return hasScriptOption ? positionals : positionals.skip(1).toList();
}

/// Защищённая цель `P` §7.6. Цель с переменной, кроме `$HOME`, не
/// защищена: её значение неизвестно (`/$DIR`).
///
/// Сверх буквального списка: путь без переменных и масок нормализуется от
/// [root], поэтому `//` и `/usr/../` — корень, а корень сессии и его
/// предки (`../..`, `/Users/me` при корне `/Users/me/proj`) тоже защищены —
/// это развитие `.` и `..` из списка.
bool _isProtected(String target, String root) {
  if (_protectedLiterals.contains(target)) {
    return true;
  }
  if (target.contains(r'$') || target.startsWith('~')) {
    return false;
  }
  final path = target.endsWith('/*')
      ? target.substring(0, target.length - 2)
      : target;
  if (path.contains('*') || path.contains('?') || path.contains('[')) {
    return false;
  }
  final absolute = normalizePath(root, path.isEmpty ? '/' : path);
  if (absolute == null) {
    return false;
  }
  return absolute == '/' ||
      _systemDirectories.contains(absolute) ||
      isInside(absolute, root);
}

bool _isGitDirectory(String target) => baseName(target) == '.git';

/// Первый путь `find` после опций `-H`, `-L`, `-P`, `-O<n>`, `-D <debug>`;
/// без пути `find` обходит `.`.
String _findStart(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-D') {
      i++;
    } else if (const {'-H', '-L', '-P'}.contains(a) || a.startsWith('-O')) {
      continue;
    } else if (a.startsWith('-') || a == '(' || a == '!') {
      return '.';
    } else {
      return a;
    }
  }
  return '.';
}

bool _findDeletes(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '-delete') {
      return true;
    }
    if (const {'-exec', '-execdir', '-ok', '-okdir'}.contains(a) &&
        i + 1 < args.length &&
        baseName(args[i + 1]) == 'rm') {
      return true;
    }
  }
  return false;
}

/// Цели `kill`: первое слово-опция — сигнал (`-9`, `-KILL`), `-s SIG` и
/// `-n N` забирают значение; `-1` после сигнала — «все процессы».
List<String> _killTargets(List<String> args) {
  var i = 0;
  if (args.isNotEmpty) {
    final first = args.first;
    if (first == '-s' || first == '-n') {
      i = 2;
    } else if (first == '--') {
      i = 1;
    } else if (first.startsWith('-') && args.length > 1) {
      i = 1;
    }
  }
  return i < args.length ? args.sublist(i) : const [];
}

bool _isFormatCommand(String name, List<String> args, String root) {
  if (const {
        'mkfs',
        'mke2fs',
        'wipefs',
        'fdisk',
        'sfdisk',
        'parted',
      }.contains(name) ||
      name.startsWith('mkfs.') ||
      name.startsWith('newfs')) {
    return true;
  }
  if (name == 'diskutil') {
    return const {
      'erasedisk',
      'erasevolume',
      'partitiondisk',
    }.contains(positionalArgs(args).firstOrNull?.toLowerCase());
  }
  if (name == 'shred') {
    return positionalArgs(args).any((t) {
      final path = t.contains(r'$') ? null : normalizePath(root, t);
      return path != null && path.startsWith('/dev/');
    });
  }
  return false;
}

void _checkGit(List<String> args, Set<String> found) {
  final parsed = gitSubcommand(args);
  if (parsed == null) {
    return;
  }
  final (:subcommand, :rest, globals: _) = parsed;
  bool shortFlag(String a, String letter) =>
      shortFlagPattern.hasMatch(a) && a.contains(letter);
  switch (subcommand) {
    case 'push':
      final force = rest.any(
        (a) =>
            a == '--force' ||
            a.startsWith('--force-with-lease') ||
            a == '--mirror' ||
            a == '--delete' ||
            shortFlag(a, 'f') ||
            shortFlag(a, 'd'),
      );
      final refspecs = positionalArgs(
        rest,
        withValue: const {'-o', '--push-option', '--repo', '--receive-pack'},
      );
      if (force ||
          refspecs.any((r) => r.startsWith('+') || r.startsWith(':'))) {
        found.add(_gitPush);
      }
    case 'filter-branch' || 'filter-repo':
      found.add(_gitRewrite);
    case 'reflog':
      if (positionalArgs(rest).firstOrNull == 'expire' &&
          rest.any(
            (a) => RegExp(r'^--expire(-unreachable)?=(now|all)$').hasMatch(a),
          )) {
        found.add(_gitRewrite);
      }
    case 'gc':
      if (rest.any((a) => a == '--prune=now' || a == '--prune=all')) {
        found.add(_gitRewrite);
      }
    case 'branch':
      final delete = rest.any(
        (a) => a == '-d' || a == '--delete' || shortFlag(a, 'd'),
      );
      final forced = rest.any(
        (a) => a == '-f' || a == '--force' || shortFlag(a, 'f'),
      );
      final forceDelete =
          rest.any((a) => shortFlag(a, 'D')) || delete && forced;
      if (forceDelete &&
          positionalArgs(rest).any(
            (b) => _protectedBranches.contains(b) || b.startsWith('release/'),
          )) {
        found.add(_gitRewrite);
      }
  }
}

bool _isDiskDevice(String target, String root) {
  if (target.contains(r'$')) {
    return false;
  }
  final path = normalizePath(root, target);
  return path != null && _diskDevicePath.hasMatch(path);
}

bool _isAccountFile(String target, String root) {
  if (target.contains(r'$')) {
    return false;
  }
  final path = normalizePath(root, target);
  return path != null &&
      (_accountFiles.contains(path) || path.startsWith('/etc/sudoers.d/'));
}

bool _isSshPath(String target) {
  for (final home in const ['~/', r'$HOME/', r'${HOME}/']) {
    if (target.startsWith(home)) {
      final rest = normalizePath('/', target.substring(home.length));
      return rest == '/.ssh' || (rest?.startsWith('/.ssh/') ?? false);
    }
  }
  return false;
}
