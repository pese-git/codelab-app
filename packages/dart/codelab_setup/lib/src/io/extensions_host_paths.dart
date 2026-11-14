/// Перевод путей вида расширений из формы ядра в форму хоста (design.md
/// change `add-app-skills-page`, D8 «Форма путей вида»).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ExtensionDiagnostic;
import 'package:codelab_agent_io/codelab_agent_io.dart' show toHostPath;

import '../extensions/agent_extensions_view.dart';

/// Возвращает копию [view], где все пути на диске — в форме хоста.
///
/// Почему: ядро работает с путями через `/` (`C:\p` → `/c/p`), а клиент
/// открывает каталог платформой; без перевода «Open» на Windows получил бы
/// несуществующий путь (`AGENTS.md` §11). Построитель `agentExtensionsOf`
/// web-безопасен и перевода не знает, поэтому его делает `io.dart` одним
/// проходом, чтобы ни одно поле не забыть.
///
/// Как использовать: `readAgentExtensions` вызывает с
/// `windows: Platform.isWindows`; на POSIX перевод тождественен. Тест
/// передаёт `windows: true`. Переводятся только абсолютные пути (начинаются с
/// `/`): `ContextFileView.path` — путь для промпта (`$CODELAB_HOME/…` или
/// от корня репозитория), не путь диска, и остаётся как есть; тексты
/// диагностик и подписи (`label`) не трогаются.
///
/// Правило для разработчика: любое НОВОЕ поле вида, хранящее путь на диске
/// (в `AgentExtensionsView` и его строках), ДОЛЖНО переводиться здесь, иначе
/// «Open» на Windows получит путь ядра. Полноту перевода проверяет
/// `test/io/extensions_host_paths_test.dart`: добавляя поле-путь, добавьте в
/// этот тест его проверку.
AgentExtensionsView extensionsInHostForm(
  AgentExtensionsView view, {
  required bool windows,
}) {
  String host(String p) =>
      p.startsWith('/') ? toHostPath(p, windows: windows) : p;
  String? hostOrNull(String? p) => p == null ? null : host(p);

  ExtensionDiagnostic diag(ExtensionDiagnostic d) => ExtensionDiagnostic(
    path: host(d.path),
    level: d.level,
    code: d.code,
    message: d.message,
    line: d.line,
    column: d.column,
  );
  List<ExtensionDiagnostic> diags(List<ExtensionDiagnostic> l) => [
    for (final d in l) diag(d),
  ];
  SkillRootView root(SkillRootView r) =>
      SkillRootView(scope: r.scope, label: r.label, path: host(r.path));

  final context = view.context;
  final skills = view.skills;
  final templates = view.templates;
  return AgentExtensionsView(
    folder: host(view.folder),
    trusted: view.trusted,
    context: ContextChainView(
      outcome: context.outcome,
      files: [
        for (final f in context.files)
          ContextFileView(
            path: f.path,
            openDir: hostOrNull(f.openDir),
            bytes: f.bytes,
            shownBytes: f.shownBytes,
            scope: f.scope,
            isClaudeAlias: f.isClaudeAlias,
            omitted: f.omitted,
          ),
      ],
      shownBytes: context.shownBytes,
      omittedCount: context.omittedCount,
      truncatedCount: context.truncatedCount,
      warnings: diags(context.warnings),
    ),
    skills: SkillsSectionView(
      outcome: skills.outcome,
      entries: [
        for (final e in skills.entries)
          SkillEntryView(
            name: e.name,
            description: e.description,
            argumentHint: e.argumentHint,
            invokeAs: e.invokeAs,
            availability: e.availability,
            modelVisible: e.modelVisible,
            userInvocable: e.userInvocable,
            root: root(e.root),
            directory: host(e.directory),
            overrides: [for (final o in e.overrides) root(o)],
            overridesLabel: e.overridesLabel,
            warnings: diags(e.warnings),
            toggle: e.toggle,
          ),
      ],
      warnings: diags(skills.warnings),
      consents: [
        for (final c in skills.consents)
          SkillConsentView(
            entry: c.entry,
            path: host(c.path),
            skillDirs: c.skillDirs,
            granted: c.granted,
            toggle: c.toggle,
          ),
      ],
    ),
    templates: TemplatesSectionView(
      outcome: templates.outcome,
      entries: [
        for (final t in templates.entries)
          TemplateEntryView(
            command: t.command,
            argumentHint: t.argumentHint,
            description: t.description,
            sourcePath: host(t.sourcePath),
            scope: t.scope,
          ),
      ],
      warnings: diags(templates.warnings),
    ),
  );
}
