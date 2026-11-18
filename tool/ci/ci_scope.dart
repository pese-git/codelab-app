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
///
/// У охвата два измерения: Dart-матрица [CiScope.jobs] и признак джоба сайта
/// [CiScope.site] (`site/`, ADR-0003; change `add-astro-site`, D13). Сайт
/// собирается из документации репозитория, поэтому его запускают и правки
/// документов, которые Dart-джобов не запускают.
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
    this.site = false,
  });

  final bool full;
  final List<CiJob> jobs;
  final Set<String> changed;
  final Set<String> affected;
  final String? reason;

  /// Нужен ли джоб `site` — сборка и проверка сайта (change
  /// `add-astro-site`, D13; ADR-0003).
  ///
  /// Почему отдельный признак, а не строка матрицы: джобу сайта не нужны FVM
  /// и Flutter из шага `prepare`, и его запускают файлы, которые Dart-матрицу
  /// не меняют (документация, `site/`).
  ///
  /// Для чего: `affected.dart` пишет его в `$GITHUB_OUTPUT` как `site=…`,
  /// а `ci.yml` запускает по нему джоб `site`. В полном прогоне всегда `true`.
  final bool site;
}

/// Джобы полного прогона — те же шаги, что у `melos run check`.
const fullJobs = [
  CiJob('format', 'check-format'),
  CiJob('analyze', 'analyze'),
  CiJob('test', 'test'),
  CiJob(
    'conformance',
    'protocol-conformance conformance:client conformance:agent '
        'conformance:embedded',
  ),
  CiJob('guard', 'guard prompts:check'),
  // Сгенерированный код локализации совпадает с ARB (change
  // add-desktop-localization, D3).
  CiJob('l10n', 'l10n:check'),
  CiJob('web-compile', 'web-compile'),
  // Тесты CLI против scripted-агента идут внутри `test`, здесь — те же
  // тесты против codelab-agent (change add-cli-e2e-agent-matrix).
  CiJob('e2e-cli-dart', 'test:e2e:cli:dart-agent'),
  // То же против встроенного агента: CLI из тестовой точки входа со
  // сценарием модели (change add-embedded-agent-mode, D10).
  CiJob('e2e-cli-embedded', 'test:e2e:cli:embedded'),
];

/// Корпус фикстур ACP на каждый ACP-слой: прогоняется, если слой затронут.
const _conformance = {
  'codelab_acp_protocol': 'protocol-conformance',
  'codelab_client_acp': 'conformance:client',
  'codelab_agent_acp': 'conformance:agent',
};

/// Пакеты, без которых не собирается бинарь CLI-e2e или сам CLI.
const _cliE2e = {'codelab_cli', 'codelab_agent'};

/// Пакеты, от которых зависит CLI со встроенным агентом: корпус фикстур и
/// e2e `embedded` играет CLI (`conformance:embedded`, `test:e2e:cli:embedded`).
const _embeddedCli = {'codelab_cli', 'codelab_embedded'};

/// Пакеты с каталогами локализации (`l10n.yaml`, ARB, сгенерированный код);
/// их правка запускает `l10n:check` (change add-desktop-localization, D3).
const _l10nPackages = {'codelab_desktop', 'codelab_ui'};

/// Файл каталога локализации, его сгенерированного кода или настроек
/// генерации (`pubspec.yaml`: `generate`, `flutter_localizations`, `intl`).
bool _isL10nFile(String file) {
  final name = file.split('/').last;
  return name == 'l10n.yaml' ||
      name == 'pubspec.yaml' ||
      name.endsWith('.arb') ||
      RegExp(r'_localizations(_\w+)?\.dart$').hasMatch(name);
}

/// Точка входа `web-compile` собирает ядро агента и его зависимости.
const _webSmoke = 'codelab_agent_core';

/// Матрица целей: документ, который разбирает `parity_evidence_test` сторожа.
///
/// Почему: разбор (`switch-default-agent-to-dart`, D2) ломается от правки
/// таблицы, а правка только документации обычно не запускает ни одного джоба —
/// поломка вскрылась бы лишь ночью (D7).
const _parityMatrix = 'docs/architecture/proposals/agent-parity-goals.md';

/// Считает джобы CI для [changedFiles] (пути от корня репозитория).
///
/// Правила (`AGENTS.md` §21):
/// * [fullReason] задан (push, `release/*`, ночной запуск) или изменён файл
///   вне пакетов workspace, вне документации и вне `site/` — полный прогон
///   [fullJobs] и джоб сайта;
/// * только документация (`docs/`, `openspec/`, `.claude/`, `*.md` в корне,
///   `AGENTS.md`, `README.md` и `CHANGELOG.md` пакетов) — без джобов, кроме
///   матрицы целей [_parityMatrix]: её правка добавляет `guard` (D7);
/// * иначе `format` по всему репозиторию (он быстрый), `analyze` и `test`
///   для затронутых пакетов, `guard` всегда, остальное — по границе.
///
/// Независимо от матрицы [CiScope.site] — `true`, если хотя бы один файл
/// влияет на сайт ([_affectsSite], D13). Файлы `site/` Dart-матрицу не
/// меняют: правка только сайта не запускает Dart-джобов.
CiScope ciScope({
  required List<WorkspacePackage> packages,
  required Iterable<String> changedFiles,
  String? fullReason,
}) {
  if (fullReason != null) {
    return CiScope(full: true, jobs: fullJobs, reason: fullReason, site: true);
  }

  final site = changedFiles.any(_affectsSite);
  final changed = <String>{};
  var l10nChanged = false;
  final outside = <String>[];
  var matrixChanged = false;
  for (final file in changedFiles) {
    if (file == _parityMatrix) matrixChanged = true;
    // Файлы сайта не принадлежат pub workspace (ADR-0003), но и не «вне
    // пакетов»: иначе правка `site/` давала бы полный Dart-прогон (D13).
    if (_isDocumentation(file) || file.startsWith('site/')) continue;
    final owner = packages
        .where((pkg) => file.startsWith('${pkg.dir}/'))
        .firstOrNull;
    if (owner == null) {
      outside.add(file);
    } else {
      changed.add(owner.name);
      if (_l10nPackages.contains(owner.name) && _isL10nFile(file)) {
        l10nChanged = true;
      }
    }
  }
  if (outside.isNotEmpty) {
    return CiScope(
      full: true,
      jobs: fullJobs,
      reason: 'changed outside workspace packages: ${outside.join(', ')}',
      site: true,
    );
  }
  if (changed.isEmpty) {
    return CiScope(
      full: false,
      jobs: [if (matrixChanged) const CiJob('guard', 'guard')],
      site: site,
    );
  }

  final affected = _withDependents(changed, packages);
  final scoped = (affected.toList()..sort()).join(',');
  final conformance = [
    for (final entry in _conformance.entries)
      if (affected.contains(entry.key)) entry.value,
    if (affected.any(_embeddedCli.contains)) 'conformance:embedded',
  ];
  final webDependencies = _withDependencies({_webSmoke}, packages);

  return CiScope(
    full: false,
    changed: changed,
    affected: affected,
    site: site,
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
      if (l10nChanged) const CiJob('l10n', 'l10n:check'),
      if (changed.any(webDependencies.contains))
        const CiJob('web-compile', 'web-compile'),
      if (affected.any(_cliE2e.contains))
        const CiJob('e2e-cli-dart', 'test:e2e:cli:dart-agent'),
      if (affected.any(_embeddedCli.contains))
        const CiJob('e2e-cli-embedded', 'test:e2e:cli:embedded'),
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

/// Влияет ли [file] на сборку сайта — запускать ли джоб `site` (D13).
///
/// Почему: сайт строит страницы из документации репозитория и переводит её
/// относительные ссылки (D3, D5), поэтому сломать его может не только
/// `site/`, но и правка опубликованного документа или перенос файла, на
/// который документ ссылается. Шаблоны — path-фильтр из решения
/// пользователя плюс весь `openspec/**`: точный разбор ссылок на Dart был бы
/// второй реализацией плагина сайта (D13, ответ на Q6).
///
/// Для чего: единственный предикат «файл сайта» для [ciScope]; на
/// Dart-матрицу он не влияет — её по-прежнему решает [_isDocumentation] и
/// владелец-пакет.
bool _affectsSite(String file) {
  if (file.startsWith('site/') ||
      file.startsWith('docs/') ||
      file.startsWith('openspec/')) {
    return true;
  }
  final parts = file.split('/');
  if (parts.first == 'apps' && parts.length >= 3) {
    // `apps/*/README.md` и `apps/*/doc/**`.
    return (parts.length == 3 && parts[2] == 'README.md') || parts[2] == 'doc';
  }
  if (parts.first == 'packages') {
    // `packages/**/README.md` и `packages/**/doc/**`.
    return parts.last == 'README.md' ||
        parts.sublist(1, parts.length - 1).contains('doc');
  }
  return false;
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
