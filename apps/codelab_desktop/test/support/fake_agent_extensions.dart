// Строители вида «Skills & extensions» для тестов app (change
// `add-app-skills-page`, D4, D6): страница и Cubit показывают готовый
// `AgentExtensionsView` моста, а построитель и чтение файлов проверяет сам
// мост (`codelab_setup`, итерации 1–2). Здесь — только значения по умолчанию,
// чтобы тест называл лишь то, что проверяет.
//
// Пути — вымышленные, без реальных каталогов пользователя. Маркер
// `sk-test-leak-…` сюда НЕ кладётся: страница и журнал не должны видеть
// текстов файлов, а описание и подсказки в виде — это данные, которые
// страница обязана показать (D12), поэтому утечку проверяют отдельными
// тестами (`leakMarker` в описании/шаблоне).

import 'package:codelab_setup/codelab_setup.dart';

/// Корень проекта в тестах страницы.
const skillsFolder = '/work/app';

SkillRootView userSkillRoot({
  String label = '~/.agents/skills',
  String path = '/home/u/.agents/skills',
}) => SkillRootView(scope: ExtensionScope.user, label: label, path: path);

/// Корень навыков из `skills.extra_roots`: [extraEntry] — сам элемент списка,
/// по которому app строит подпись `(extra root)` на своём языке (D6, итерация
/// 5; прежняя подпись моста — `<элемент> (extra root)`).
SkillRootView extraSkillRoot({
  String entry = '.claude/skills',
  String path = '$skillsFolder/.claude/skills',
}) => SkillRootView(
  scope: ExtensionScope.extra,
  label: '$entry (extra root)',
  path: path,
  extraEntry: entry,
);

SkillRootView projectSkillRoot({
  String label = '.codelab/skills',
  String path = '$skillsFolder/.codelab/skills',
}) => SkillRootView(scope: ExtensionScope.project, label: label, path: path);

/// Строка навыка; по умолчанию включённый навык пользователя.
SkillEntryView skillEntry(
  String name, {
  String description = 'A skill',
  String? argumentHint,
  String? invokeAs,
  SkillAvailability availability = SkillAvailability.enabled,
  bool modelVisible = true,
  bool userInvocable = true,
  SkillRootView? root,
  String? directory,
  List<SkillRootView> overrides = const [],
  String? overridesLabel,
  ExtensionScope? overridesScope,
  List<ExtensionDiagnostic> warnings = const [],
  SkillToggle toggle = const SkillToggle.available(),
}) {
  final resolvedRoot = root ?? userSkillRoot();
  return SkillEntryView(
    name: name,
    description: description,
    argumentHint: argumentHint,
    invokeAs: userInvocable
        ? (invokeAs ??
              '/skill:$name${argumentHint == null ? '' : ' $argumentHint'}')
        : null,
    availability: availability,
    modelVisible: modelVisible,
    userInvocable: userInvocable,
    root: resolvedRoot,
    directory: directory ?? '${resolvedRoot.path}/$name',
    overrides: overrides,
    overridesLabel: overridesLabel,
    overridesScope: overridesScope,
    warnings: warnings,
    toggle: toggle,
  );
}

ExtensionDiagnostic diagnostic(
  String message, {
  String path = '/home/u/.agents/skills/a/SKILL.md',
  DiagnosticLevel level = DiagnosticLevel.warning,
  String code = 'skill_issue',
}) =>
    ExtensionDiagnostic(path: path, level: level, code: code, message: message);

ContextFileView contextFile(
  String path, {
  int bytes = 1000,
  int? shownBytes,
  String? openDir,
  ExtensionScope scope = ExtensionScope.project,
  bool isClaudeAlias = false,
  bool omitted = false,
  bool truncated = false,
}) => ContextFileView(
  path: path,
  openDir:
      openDir ?? '$skillsFolder/${_dirOf(path)}'.replaceAll(RegExp('/\$'), ''),
  bytes: bytes,
  shownBytes: omitted ? 0 : (shownBytes ?? bytes),
  scope: scope,
  isClaudeAlias: isClaudeAlias,
  omitted: omitted,
  truncated: truncated,
);

String _dirOf(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

TemplateEntryView templateEntry(
  String command, {
  String? argumentHint,
  String description = 'A template',
  String? sourcePath,
  ExtensionScope scope = ExtensionScope.project,
}) => TemplateEntryView(
  command: command,
  argumentHint: argumentHint,
  description: description,
  sourcePath:
      sourcePath ?? '$skillsFolder/.codelab/prompts/${command.substring(1)}.md',
  scope: scope,
);

/// Вид страницы: доверенный проект, пустые разделы, всё прочитано.
AgentExtensionsView extensionsView({
  String folder = skillsFolder,
  bool trusted = true,
  List<ContextFileView> files = const [],
  int omittedCount = 0,
  int truncatedCount = 0,
  SectionOutcome contextOutcome = const SectionRead(),
  List<ExtensionDiagnostic> contextWarnings = const [],
  SectionOutcome skillsOutcome = const SectionRead(),
  List<SkillEntryView> skills = const [],
  List<ExtensionDiagnostic> skillWarnings = const [],
  List<SkillConsentView> consents = const [],
  SectionOutcome templatesOutcome = const SectionRead(),
  List<TemplateEntryView> templates = const [],
  List<ExtensionDiagnostic> templateWarnings = const [],
}) => AgentExtensionsView(
  folder: folder,
  trusted: trusted,
  context: ContextChainView(
    outcome: contextOutcome,
    files: files,
    shownBytes: files.fold(0, (sum, f) => sum + f.shownBytes),
    omittedCount: omittedCount,
    truncatedCount: truncatedCount,
    warnings: contextWarnings,
  ),
  skills: SkillsSectionView(
    outcome: skillsOutcome,
    entries: skills,
    warnings: skillWarnings,
    consents: consents,
  ),
  templates: TemplatesSectionView(
    outcome: templatesOutcome,
    entries: templates,
    warnings: templateWarnings,
  ),
);
