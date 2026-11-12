import 'package:codelab_agent_core/codelab_agent_core.dart';

/// Файл навыка, каким его отдаёт хост: frontmatter уже разобран
/// (agent-skills «Порт файлов навыков»; design.md change `add-agent-skills`,
/// D1, D2). Без YAML: ядро его не знает (CFG-5).
///
/// [dir] — канонический каталог навыка; путь `SKILL.md` для диагностик —
/// `<dir>/SKILL.md`. [positions] — позиции ключей frontmatter в файле.
SkillFile skillFile(
  String dirName, {
  Map<String, Object?>? frontmatter = const {},
  Map<String, ConfigPosition> positions = const {},
  String body = 'Do the thing.',
  String root = '/home/.codelab/skills',
  ExtensionScope scope = ExtensionScope.user,
  int rootIndex = 0,
  bool repaired = false,
  List<ExtensionDiagnostic> parseErrors = const [],
  List<String> companions = const [],
  bool companionsTruncated = false,
}) => SkillFile(
  dir: '$root/$dirName',
  scope: scope,
  rootIndex: rootIndex,
  frontmatter: frontmatter == null
      ? null
      : ConfigTree(
          kind: ConfigLayerKind.user,
          source: '$root/$dirName/SKILL.md',
          values: frontmatter,
          positions: positions,
        ),
  parseErrors: parseErrors,
  repaired: repaired,
  body: body,
  bodyLine: 5,
  companions: companions,
  companionsTruncated: companionsTruncated,
);

/// Минимально валидный навык с именем [name] (имя каталога равно имени).
SkillFile validSkill(
  String name, {
  Map<String, Object?> extra = const {},
  String body = 'Do the thing.',
  String root = '/home/.codelab/skills',
  ExtensionScope scope = ExtensionScope.user,
  int rootIndex = 0,
}) => skillFile(
  name,
  frontmatter: {'name': name, 'description': 'About $name.', ...extra},
  body: body,
  root: root,
  scope: scope,
  rootIndex: rootIndex,
);

SkillCatalog parse(
  List<SkillFile> files, {
  SkillsConfig settings = const SkillsConfig(),
  PolicyRules rules = const PolicyRules(),
}) => parseSkills(SkillFiles(skills: files), settings, rules: rules);

/// Коды диагностик каталога, в порядке выдачи.
List<String> codes(SkillCatalog catalog) => [
  for (final d in catalog.diagnostics) d.code,
];

/// Диагностики с данным кодом.
List<ExtensionDiagnostic> withCode(SkillCatalog catalog, String code) => [
  for (final d in catalog.diagnostics)
    if (d.code == code) d,
];
