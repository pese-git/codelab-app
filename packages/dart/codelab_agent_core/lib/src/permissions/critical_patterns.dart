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
/// `write`/`edit`.
///
/// Как использовать: политика вызывает `findCritical(command, cwd: root)` для
/// `exec` и показывает `reason: 'critical command: ${match.label}'`.
library;

import '../util/posix_path.dart';
import 'shell_lexer.dart';

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
/// относительные пути защищённых целей. `cd` внутри команды не учитывается.
CriticalMatch? findCritical(String command, {String cwd = '/'}) {
  final ShellScript script;
  try {
    script = parseShell(command);
  } on ShellParseException {
    return const CriticalMatch([unparsableCommandLabel]);
  }
  final root = normalizePath('/', cwd) ?? '/';
  final found = <String>{};
  if (forkBomb.hasMatch(command)) {
    found.add(_forkBombLabel);
  }
  for (final pipeline in script.allPipelines) {
    _checkPipeline(pipeline, found);
    for (final segment in pipeline.stages) {
      _checkSegment(segment, root, found);
    }
  }
  if (found.isEmpty) {
    return null;
  }
  return CriticalMatch([
    for (final label in _tableOrder)
      if (found.contains(label)) label,
  ]);
}

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
final _shortFlags = RegExp(r'^-[A-Za-z]+$');
final _recursiveFlag = RegExp(r'^-[A-Za-z]*[rR][A-Za-z]*$');
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

void _checkSegment(ShellSegment segment, String root, Set<String> found) {
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
  if (writes.agentConfig.any((t) => _isInAgentConfig(t, root)) ||
      writes.directories.any((t) => _isCodelabDirectory(t, root))) {
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
      final recursive = _hasRecursiveFlag(args);
      final targets = _positionals(args);
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
      if (_hasRecursiveFlag(args) &&
          _positionals(args).any((t) => _isProtected(t, root))) {
        found.add(_permissionsProtected);
      }
    case 'sudo' || 'doas' || 'su' || 'pkexec':
      found.add(_privileged);
    case 'shutdown' || 'reboot' || 'halt' || 'poweroff':
      found.add(_shutdown);
    case 'init':
      if (const {'0', '6'}.contains(_positionals(args).firstOrNull)) {
        found.add(_shutdown);
      }
    case 'systemctl':
      if (const {
        'poweroff',
        'reboot',
        'halt',
      }.contains(_positionals(args).firstOrNull)) {
        found.add(_shutdown);
      }
    case 'kill':
      if (_killTargets(args).any((t) => t == '1' || t == '-1')) {
        found.add(_killAll);
      }
    case 'git':
      _checkGit(args, found);
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

  /// Назначения `cp`/`mv`/`ln`: `mv evil .codelab` заменяет каталог
  /// конфигурации целиком.
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
        common.addAll(_positionals(args));
      case 'cp' || 'mv':
        final (:destinations, :targets) = _copyTargets(args);
        common.addAll(targets);
        directories.addAll(destinations);
      case 'ln':
        final (:destinations, :targets) = _copyTargets(args);
        agentConfig.addAll(targets);
        directories.addAll(destinations);
      case 'sed' when _sedInPlace(args):
        agentConfig.addAll(_sedFiles(args));
    }
    return _WriteTargets(redirections, common, [
      ...common,
      ...agentConfig,
    ], directories);
  }
}

/// Назначение `cp`/`mv`/`ln` (`-t DIR` или последний позиционный аргумент)
/// и пути, которые появятся, если назначение — каталог (`cp passwd /etc/`).
({List<String> destinations, List<String> targets}) _copyTargets(
  List<String> args,
) {
  const withValue = {'-t', '-S', '--target-directory', '--suffix'};
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
  final positionals = _positionals(args, withValue: withValue);
  final List<String> sources;
  final String destination;
  if (directory != null) {
    destination = directory;
    sources = positionals;
  } else if (positionals.length >= 2) {
    destination = positionals.last;
    sources = positionals.sublist(0, positionals.length - 1);
  } else {
    return (destinations: const [], targets: const []);
  }
  return (
    destinations: [destination],
    targets: [
      destination,
      for (final source in sources) '$destination/${baseName(source)}',
    ],
  );
}

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
  final positionals = _positionals(
    args,
    withValue: const {'-e', '-f', '-l', '--expression', '--file'},
  );
  return hasScriptOption ? positionals : positionals.skip(1).toList();
}

/// Позиционные аргументы: без опций и их значений из [withValue]; после
/// `--` все слова позиционные.
List<String> _positionals(
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
bool _hasRecursiveFlag(List<String> args) {
  for (final a in args) {
    if (a == '--') {
      return false;
    }
    if (a == '--recursive' || _recursiveFlag.hasMatch(a)) {
      return true;
    }
  }
  return false;
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
    }.contains(_positionals(args).firstOrNull?.toLowerCase());
  }
  if (name == 'shred') {
    return _positionals(args).any((t) {
      final path = t.contains(r'$') ? null : normalizePath(root, t);
      return path != null && path.startsWith('/dev/');
    });
  }
  return false;
}

void _checkGit(List<String> args, Set<String> found) {
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
    return;
  }
  final subcommand = args[i];
  final rest = args.sublist(i + 1);
  bool shortFlag(String a, String letter) =>
      _shortFlags.hasMatch(a) && a.contains(letter);
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
      final refspecs = _positionals(
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
      if (_positionals(rest).firstOrNull == 'expire' &&
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
          _positionals(rest).any(
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

/// Путь внутри корня сессии относительно него или `null` для целей с
/// переменной, `~` или вне корня (§7.6.1: правило — про проект).
String? _workspaceRelative(String target, String root) {
  if (target.contains(r'$') || target.startsWith('~')) {
    return null;
  }
  final path = normalizePath(root, target);
  if (path == null || !isInside(root, path) || path == root) {
    return null;
  }
  return relativeTo(root, path);
}

bool _isInAgentConfig(String target, String root) {
  final relative = _workspaceRelative(target, root);
  return relative != null && isAgentConfigPath(relative);
}

bool _isCodelabDirectory(String target, String root) =>
    _workspaceRelative(target, root)?.toLowerCase() == '.codelab';
