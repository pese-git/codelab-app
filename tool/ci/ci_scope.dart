/// Охват проверок GitHub CI по затронутому изменением.
///
/// Почему: полный `melos run check` идёт больше 10 минут, а pull request из
/// `feature/*` обычно меняет один-два пакета. Правило «проверять затронутое»
/// (`AGENTS.md` §21, «Проверка перед pull request») действует и в CI; полный
/// прогон остаётся для `release/*`, push в `develop` и `master` и ночного
/// запуска (`docs/architecture/testing.md` §74).
///
/// Для чего: единственное место, где список изменённых файлов превращается в
/// матрицу джобов `ci.yml` — какие скрипты Melos запускать и для каких
/// пакетов. Файл без зависимостей, кроме `dart:io`: джоб `scope` запускает его
/// на SDK из `setup-dart`, до установки FVM и `pub get`.
///
/// Как использовать: CI вызывает `tool/ci/affected.dart`, который читает граф
/// через [readWorkspace], берёт изменённые файлы из `git diff` и передаёт их в
/// [ciScope]. Тесты — `codelab_architecture_tests/test/ci_scope_test.dart`.
library;

import 'dart:io';

/// Член pub workspace и его зависимости на другие члены workspace.
///
/// Почему: «затронутое» — это изменённые пакеты и все, кто от них зависит;
/// внешние зависимости на это не влияют (их меняет `pubspec.lock`, а он
/// запускает полный прогон).
///
/// Для чего: вершина графа для [ciScope]. Учитываются и `dev_dependencies`:
/// тест пакета, использующий другой пакет как фикстуру, тоже может сломаться.
///
/// Как использовать: в тестах — конструктором, в CI — через [readWorkspace]
/// или [WorkspacePackage.fromPubspec]; [dir] — путь от корня репозитория.
final class WorkspacePackage {
  WorkspacePackage(this.name, this.dir, [Set<String>? dependencies])
    : dependencies = dependencies ?? const {};

  /// Разбирает `pubspec.yaml` пакета без пакета `yaml`.
  ///
  /// Берутся ключи второго уровня секций `dependencies:` и
  /// `dev_dependencies:`, имена которых есть в [workspace]; остальные секции
  /// (`flutter:`, `dependency_overrides:`) не считаются.
  factory WorkspacePackage.fromPubspec(
    String dir,
    String pubspec, {
    required Set<String> workspace,
  }) {
    String? name;
    final dependencies = <String>{};
    var inDependencies = false;
    for (final line in pubspec.split('\n')) {
      final top = RegExp(r'^([A-Za-z_]\w*):(.*)$').firstMatch(line);
      if (top != null) {
        if (top[1] == 'name') name = top[2]!.trim();
        inDependencies =
            top[1] == 'dependencies' || top[1] == 'dev_dependencies';
        continue;
      }
      if (!inDependencies) continue;
      final entry = RegExp(r'^  ([a-z_][a-z0-9_]*):').firstMatch(line);
      if (entry != null && workspace.contains(entry[1])) {
        dependencies.add(entry[1]!);
      }
    }
    if (name == null) {
      throw FormatException('No name: in $dir/pubspec.yaml');
    }
    return WorkspacePackage(name, dir, dependencies);
  }

  final String name;
  final String dir;
  final Set<String> dependencies;
}

/// Один джоб матрицы `ci.yml`.
///
/// Почему: состав джобов и их скрипты живут здесь, а не в YAML, чтобы полный
/// и суженный прогоны не расходились.
///
/// Для чего: [scripts] — скрипты Melos через пробел; [packages] — значение
/// `MELOS_PACKAGES` (имена через запятую) или `null`, если скрипт идёт по
/// всему репозиторию. Пустую строку Melos понимает как «ни одного пакета»,
/// поэтому её не бывает.
final class CiJob {
  const CiJob(this.job, this.scripts, {this.packages});

  final String job;
  final String scripts;
  final String? packages;

  Map<String, String> toJson() => {
    'job': job,
    'scripts': scripts,
    'packages': packages ?? '',
  };
}

/// Результат расчёта охвата.
///
/// [changed] — пакеты с изменёнными файлами, [affected] — они и все их
/// зависимые (транзитивно); [reason] объясняет полный прогон и пишется в
/// summary джоба.
final class CiScope {
  const CiScope({
    required this.full,
    required this.jobs,
    this.changed = const {},
    this.affected = const {},
    this.reason,
  });

  final bool full;
  final List<CiJob> jobs;
  final Set<String> changed;
  final Set<String> affected;
  final String? reason;
}

/// Джобы полного прогона — те же шаги, что у `melos run check`.
const fullJobs = [
  CiJob('format', 'check-format'),
  CiJob('analyze', 'analyze'),
  CiJob('test', 'test'),
  CiJob(
    'conformance',
    'protocol-conformance conformance:client conformance:agent',
  ),
  CiJob('guard', 'guard prompts:check'),
  CiJob('web-compile', 'web-compile'),
  // Тесты CLI против scripted-агента идут внутри `test`, здесь — те же
  // тесты против codelab-agent (change add-cli-e2e-agent-matrix).
  CiJob('e2e-cli-dart', 'test:e2e:cli:dart-agent'),
];

/// Корпус фикстур ACP на каждый ACP-слой: прогоняется, если слой затронут.
const _conformance = {
  'codelab_acp_protocol': 'protocol-conformance',
  'codelab_client_acp': 'conformance:client',
  'codelab_agent_acp': 'conformance:agent',
};

/// Пакеты, без которых не собирается бинарь CLI-e2e или сам CLI.
const _cliE2e = {'codelab_cli', 'codelab_agent'};

/// Точка входа `web-compile` собирает ядро агента и его зависимости.
const _webSmoke = 'codelab_agent_core';

/// Считает джобы CI для [changedFiles] (пути от корня репозитория).
///
/// Правила (`AGENTS.md` §21):
/// * [fullReason] задан (push, `release/*`, ночной запуск) или изменён файл
///   вне пакетов workspace и вне документации — полный прогон [fullJobs];
/// * только документация (`docs/`, `openspec/`, `.claude/`, `*.md` в корне,
///   `AGENTS.md`, `README.md` и `CHANGELOG.md` пакетов) — без джобов;
/// * иначе `format` по всему репозиторию (он быстрый), `analyze` и `test`
///   для затронутых пакетов, `guard` всегда, остальное — по границе.
CiScope ciScope({
  required List<WorkspacePackage> packages,
  required Iterable<String> changedFiles,
  String? fullReason,
}) {
  if (fullReason != null) {
    return CiScope(full: true, jobs: fullJobs, reason: fullReason);
  }

  final changed = <String>{};
  final outside = <String>[];
  for (final file in changedFiles) {
    if (_isDocumentation(file)) continue;
    final owner = packages
        .where((pkg) => file.startsWith('${pkg.dir}/'))
        .firstOrNull;
    if (owner == null) {
      outside.add(file);
    } else {
      changed.add(owner.name);
    }
  }
  if (outside.isNotEmpty) {
    return CiScope(
      full: true,
      jobs: fullJobs,
      reason: 'changed outside workspace packages: ${outside.join(', ')}',
    );
  }
  if (changed.isEmpty) return const CiScope(full: false, jobs: []);

  final affected = _withDependents(changed, packages);
  final scoped = (affected.toList()..sort()).join(',');
  final conformance = [
    for (final entry in _conformance.entries)
      if (affected.contains(entry.key)) entry.value,
  ];
  final webDependencies = _withDependencies({_webSmoke}, packages);

  return CiScope(
    full: false,
    changed: changed,
    affected: affected,
    jobs: [
      const CiJob('format', 'check-format'),
      CiJob('analyze', 'analyze:packages', packages: scoped),
      CiJob('test', 'test', packages: scoped),
      if (conformance.isNotEmpty) CiJob('conformance', conformance.join(' ')),
      // Сторож дешёвый и проверяет импорты, которые может добавить любой
      // файл; промпты живут только в ядре агента.
      CiJob(
        'guard',
        changed.contains(_webSmoke) ? 'guard prompts:check' : 'guard',
      ),
      if (changed.any(webDependencies.contains))
        const CiJob('web-compile', 'web-compile'),
      if (affected.any(_cliE2e.contains))
        const CiJob('e2e-cli-dart', 'test:e2e:cli:dart-agent'),
    ],
  );
}

/// Документация не влияет на код. Внутри пакета это только его описания:
/// остальные `*.md` там — данные, например промпты ядра агента
/// (`codelab_agent_core/prompts/**`), их проверяет `prompts:check`.
bool _isDocumentation(String file) {
  if (file.startsWith('docs/') ||
      file.startsWith('openspec/') ||
      file.startsWith('.claude/')) {
    return true;
  }
  final name = file.split('/').last;
  if (!file.contains('/')) return name.endsWith('.md');
  return const {'AGENTS.md', 'README.md', 'CHANGELOG.md'}.contains(name);
}

/// [roots] и все пакеты, которые от них зависят, транзитивно.
Set<String> _withDependents(Set<String> roots, List<WorkspacePackage> graph) {
  final result = {...roots};
  for (var grown = true; grown;) {
    grown = false;
    for (final pkg in graph) {
      if (!result.contains(pkg.name) && pkg.dependencies.any(result.contains)) {
        grown = result.add(pkg.name);
      }
    }
  }
  return result;
}

/// [roots] и все их зависимости внутри workspace, транзитивно.
Set<String> _withDependencies(Set<String> roots, List<WorkspacePackage> graph) {
  final byName = {for (final pkg in graph) pkg.name: pkg};
  final result = <String>{};
  final pending = [...roots];
  while (pending.isNotEmpty) {
    final name = pending.removeLast();
    if (!result.add(name)) continue;
    pending.addAll(byName[name]?.dependencies ?? const {});
  }
  return result;
}

/// Читает граф pub workspace из корня репозитория [root].
///
/// Список членов — секция `workspace:` корневого `pubspec.yaml`, как у `pub`:
/// новый пакет попадает в охват CI без правки этого файла.
List<WorkspacePackage> readWorkspace(String root) {
  final dirs = <String>[];
  var inWorkspace = false;
  for (final line in File('$root/pubspec.yaml').readAsLinesSync()) {
    if (line.startsWith('workspace:')) {
      inWorkspace = true;
      continue;
    }
    if (!inWorkspace) continue;
    final member = RegExp(r'^\s+-\s+(\S+)').firstMatch(line);
    if (member != null) {
      dirs.add(member[1]!);
    } else if (line.trim().isNotEmpty && !line.startsWith(' ')) {
      break;
    }
  }
  final pubspecs = {
    for (final dir in dirs)
      dir: File('$root/$dir/pubspec.yaml').readAsStringSync(),
  };
  final names = {
    for (final text in pubspecs.values)
      RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(text)![1]!,
  };
  return [
    for (final MapEntry(key: dir, value: text) in pubspecs.entries)
      WorkspacePackage.fromPubspec(dir, text, workspace: names),
  ];
}
