/// Построитель вида расширений агента: снимок конфигурации и прочитанные
/// файлы в `AgentExtensionsView` (design.md change `add-app-skills-page`, D4).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../config/agent_config_store.dart';
import 'agent_extensions_view.dart';

/// Префикс пути пользовательского `AGENTS.md` в промпте (D5 change
/// `add-agent-project-files`): на диске это `codelabHome` плюс остаток пути.
const _homePrefix = r'$CODELAB_HOME/';

/// Строит вид страницы по снимку [snapshot] и прочитанным файлам [extensions].
///
/// Почему чистая функция основного бареля: правила навыков, шаблонов и
/// бюджета контекста принадлежат ядру, поэтому мост лишь вызывает
/// `parseSkills`, `parseCommandTemplates` и `assembleProjectContext` — то же,
/// что делает сессия, — и не заводит второй реализации (SETUP-8). Без
/// `dart:io` работает и в web.
///
/// Как использовать: снимок обязан иметь `loaded.config` (читаемый конфиг;
/// иначе `StateError`). [userHome] — домашний каталог для подписи `~` в
/// источниках; [consents] — кандидаты согласия, их собирает
/// `readAgentExtensions` (нужен диск) и кладёт в раздел как есть. [extensions]
/// содержит тела файлов, поэтому вызывать внутри функции `io.dart`, а наружу
/// отдавать только вид (SETUP-25).
AgentExtensionsView agentExtensionsOf(
  AgentConfigSnapshot snapshot,
  ProjectExtensions extensions, {
  required String? userHome,
  List<SkillConsentView> consents = const [],
}) {
  final config = snapshot.loaded.config;
  if (config == null) {
    throw StateError('The config snapshot has no loaded configuration');
  }
  final project = extensions.projectFiles;
  final projectOutcome = _outcome(project);
  final files = project is PhaseLoaded<ProjectFiles> ? project.value : null;
  final templates = files == null
      ? null
      : parseCommandTemplates(files.templates);
  final parts = _splitFileDiagnostics(files?.diagnostics ?? const []);
  return AgentExtensionsView(
    folder: extensions.cwd,
    trusted: extensions.trusted,
    context: _chain(files, projectOutcome, extensions, config, parts.chain),
    skills: _skills(snapshot, extensions, config, userHome, consents),
    templates: TemplatesSectionView(
      outcome: projectOutcome,
      entries: [
        for (final t in templates?.templates ?? const <CommandTemplate>[])
          TemplateEntryView(
            command: '/${t.name}',
            argumentHint: t.argumentHint,
            description: t.description,
            sourcePath: t.path,
            scope: t.scope,
          ),
      ],
      warnings: _shown([...parts.templates, ...?templates?.diagnostics]),
    ),
  );
}

SectionOutcome _outcome(PhaseOutcome<Object?> phase) => switch (phase) {
  PhaseLoaded() => const SectionRead(),
  PhaseTimedOut() => const SectionTimedOut(),
  PhaseFailed(:final errorType) => SectionFailed(errorType),
};

/// Раскладывает диагностики файлов проекта по разделам страницы.
///
/// Файл `AGENTS.md`/`CLAUDE.md` — цепочка; диагностика каталога `prompts`
/// или файла непосредственно в нём — шаблоны; то же для `agents` —
/// определения агентов, которых на странице нет (диагностика не
/// показывается). Решает только каталог файла (последний или предпоследний
/// сегмент пути): каталоги выше проекта (`/work/agents/repo`) не влияют. Имя
/// файла проверяется первым. Прочее (диагностика самого обхода) относится к
/// цепочке.
({List<ExtensionDiagnostic> chain, List<ExtensionDiagnostic> templates})
_splitFileDiagnostics(List<ExtensionDiagnostic> all) {
  final chain = <ExtensionDiagnostic>[];
  final templates = <ExtensionDiagnostic>[];
  for (final d in all) {
    final segments = d.path.split('/');
    final name = segments.last;
    if (name == 'AGENTS.md' || name == 'CLAUDE.md') {
      chain.add(d);
    } else if (_inDir(segments, 'prompts')) {
      templates.add(d);
    } else if (!_inDir(segments, 'agents')) {
      chain.add(d);
    }
  }
  return (chain: chain, templates: templates);
}

/// Путь — сам каталог [dir] (последний сегмент) или файл в нём (предпоследний).
bool _inDir(List<String> segments, String dir) =>
    segments.last == dir ||
    (segments.length > 1 && segments[segments.length - 2] == dir);

/// `info` не показываются (как в `config check`).
List<ExtensionDiagnostic> _shown(List<ExtensionDiagnostic> all) => [
  for (final d in all)
    if (d.level != DiagnosticLevel.info) d,
];

ContextChainView _chain(
  ProjectFiles? files,
  SectionOutcome outcome,
  ProjectExtensions extensions,
  CoreConfig config,
  List<ExtensionDiagnostic> chainDiagnostics,
) {
  final context = files?.context ?? const <ContextFile>[];
  // Бюджет и усечение считает ядро (D4): мост сопоставляет результат с файлами
  // по пути и ничего не пересчитывает.
  final assembled = assembleProjectContext(
    context,
    config.projectContextMaxBytes,
  );
  final shown = {for (final f in assembled?.files ?? const []) f.path: f};
  var omitted = 0;
  final views = <ContextFileView>[];
  for (final file in context) {
    final entry = shown[file.path];
    final isOmitted = entry == null && file.content.trim().isNotEmpty;
    if (isOmitted && assembled == null) {
      omitted++;
    }
    views.add(
      ContextFileView(
        path: file.path,
        openDir: _openDir(file.path, extensions),
        bytes: file.totalBytes,
        shownBytes: entry?.shownBytes ?? 0,
        scope: file.scope,
        isClaudeAlias: file.path.split('/').last == 'CLAUDE.md',
        omitted: isOmitted,
      ),
    );
  }
  return ContextChainView(
    outcome: outcome,
    files: views,
    shownBytes: assembled?.bytes ?? 0,
    omittedCount: assembled?.omitted ?? omitted,
    truncatedCount: assembled?.truncated ?? 0,
    warnings: _shown(chainDiagnostics),
  );
}

/// Каталог файла на диске: `$CODELAB_HOME/…` — от домашнего каталога агента,
/// остальное — от корня обхода.
String? _openDir(String path, ProjectExtensions extensions) {
  final String disk;
  if (path.startsWith(_homePrefix)) {
    final home = extensions.codelabHome;
    if (home == null || home.isEmpty) {
      return null;
    }
    disk = '$home/${path.substring(_homePrefix.length)}';
  } else {
    final root = extensions.contextRoot;
    disk = '${root == '/' ? '' : root}/$path';
  }
  final slash = disk.lastIndexOf('/');
  return slash <= 0 ? '/' : disk.substring(0, slash);
}

SkillsSectionView _skills(
  AgentConfigSnapshot snapshot,
  ProjectExtensions extensions,
  CoreConfig config,
  String? userHome,
  List<SkillConsentView> consents,
) {
  final phase = extensions.skills;
  if (phase == null) {
    return SkillsSectionView(
      outcome: SectionOff(snapshot.originOf('skills.enabled')?.label ?? ''),
      entries: const [],
      warnings: const [],
      consents: consents,
    );
  }
  if (phase is! PhaseLoaded<SkillFiles>) {
    return SkillsSectionView(
      outcome: _outcome(phase),
      entries: const [],
      warnings: const [],
      consents: consents,
    );
  }
  final files = phase.value;
  final settings = config.skills;
  final rules = config.permissions.rules;
  final catalog = parseSkills(files, settings, rules: rules);
  // Победитель по имени без `skills.disabled` — строка, которую включит
  // выключатель (D4): выключение действует на все файлы с этим именем.
  final unfiltered = settings.disabled.isEmpty
      ? catalog
      : parseSkills(files, _withoutDisabled(settings), rules: rules);
  final byPath = {for (final f in files.skills) '${f.dir}/SKILL.md': f};
  // Диагностики: `error`/`warning` показанного навыка — в его строку, прочие —
  // в раздел; `info` отбрасываются.
  final all = _shown([...files.diagnostics, ...catalog.diagnostics]);

  SkillRootView rootOf(int index) =>
      _rootView(extensions, index, userHome: userHome);

  final entries = <SkillEntryView>[];
  final shownPaths = <String>{};
  void add(SkillDefinition s, SkillCatalog from, SkillAvailability how) {
    final file = byPath[s.path];
    if (file == null) {
      return;
    }
    shownPaths.add(s.path);
    final root = rootOf(file.rootIndex);
    final overrides = _overrides(from, files, byPath, s.name, rootOf);
    entries.add(
      SkillEntryView(
        name: s.name,
        description: s.description,
        argumentHint: s.argumentHint,
        invokeAs: s.userInvocable
            ? '/skill:${s.name}${s.argumentHint == null ? '' : ' ${s.argumentHint}'}'
            : null,
        availability: how,
        modelVisible: from.modelVisible.any((v) => v.name == s.name),
        userInvocable: s.userInvocable,
        root: root,
        overrides: overrides,
        overridesLabel: _overridesLabel(root, overrides),
        warnings: [
          for (final d in all)
            if (d.path == s.path) d,
        ],
      ),
    );
  }

  for (final s in catalog.skills) {
    add(s, catalog, SkillAvailability.enabled);
  }
  final disabled = settings.disabled.toSet();
  for (final s in unfiltered.skills) {
    if (disabled.contains(s.name) && catalog.skill(s.name) == null) {
      add(s, unfiltered, SkillAvailability.disabled);
    }
  }
  entries.sort((a, b) => a.name.compareTo(b.name));

  return SkillsSectionView(
    outcome: const SectionRead(),
    entries: entries,
    warnings: [
      for (final d in all)
        if (!shownPaths.contains(d.path)) d,
    ],
    consents: consents,
  );
}

/// Копия настроек без `skills.disabled`. Копируются все поля вручную: у
/// `SkillsConfig` нет `copyWith`, поэтому НОВОЕ поле класса нужно добавить и
/// сюда, иначе второй вызов `parseSkills` молча получит значение по
/// умолчанию.
SkillsConfig _withoutDisabled(SkillsConfig s) => SkillsConfig(
  enabled: s.enabled,
  extraRoots: s.extraRoots,
  maxSkills: s.maxSkills,
  catalogMaxChars: s.catalogMaxChars,
  reattachPerSkillTokens: s.reattachPerSkillTokens,
  reattachTotalTokens: s.reattachTotalTokens,
);

/// Корни навыков, перекрытых навыком [winner]: по диагностикам `shadowed`
/// ядра (путь диагностики — `SKILL.md` проигравшего), без разбора текста.
/// Имя проигравшего даёт одиночный `parseSkills` его файла.
List<SkillRootView> _overrides(
  SkillCatalog catalog,
  SkillFiles files,
  Map<String, SkillFile> byPath,
  String winner,
  SkillRootView Function(int) rootOf,
) {
  final result = <SkillRootView>[];
  for (final d in catalog.diagnostics) {
    if (d.code != 'shadowed') {
      continue;
    }
    final loser = byPath[d.path];
    if (loser == null) {
      continue;
    }
    final parsed = parseSkills(
      SkillFiles(skills: [loser]),
      const SkillsConfig(),
    ).skills;
    if (parsed.length == 1 && parsed.single.name == winner) {
      result.add(rootOf(loser.rootIndex));
    }
  }
  return result;
}

String? _overridesLabel(SkillRootView root, List<SkillRootView> overrides) {
  if (overrides.isEmpty) {
    return null;
  }
  for (final o in overrides) {
    if (o.scope != root.scope) {
      return 'Overrides ${o.scope.name} skill';
    }
  }
  return 'Overrides another skill';
}

SkillRootView _rootView(
  ProjectExtensions extensions,
  int index, {
  required String? userHome,
}) {
  final roots = extensions.skillRoots;
  if (index < 0 || index >= roots.length) {
    return SkillRootView(
      scope: ExtensionScope.extra,
      label: '(unknown root)',
      path: '',
    );
  }
  final root = roots[index];
  final label = switch (root.scope) {
    ExtensionScope.project => _relative(extensions.cwd, root.path),
    ExtensionScope.user => _tilde(root.path, userHome),
    ExtensionScope.extra => '${root.extraRoot ?? root.path} (extra root)',
  };
  return SkillRootView(scope: root.scope, label: label, path: root.path);
}

/// Путь [target] от папки [from] через `/`, с `..` для уровней выше.
String _relative(String from, String target) {
  final a = from.split('/').where((s) => s.isNotEmpty).toList();
  final b = target.split('/').where((s) => s.isNotEmpty).toList();
  var common = 0;
  while (common < a.length && common < b.length && a[common] == b[common]) {
    common++;
  }
  return [
    for (var i = common; i < a.length; i++) '..',
    ...b.sublist(common),
  ].join('/');
}

/// Путь с `~` вместо домашнего каталога; вне него — абсолютный.
String _tilde(String path, String? userHome) {
  if (userHome == null || userHome.isEmpty) {
    return path;
  }
  if (path == userHome) {
    return '~';
  }
  return path.startsWith('$userHome/')
      ? '~${path.substring(userHome.length)}'
      : path;
}
