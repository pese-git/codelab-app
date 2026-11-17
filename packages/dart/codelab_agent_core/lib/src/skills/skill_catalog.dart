/// Каталог навыков сессии и чистая проверка `SKILL.md` (design.md change
/// `add-agent-skills`, D2, D4, D16; `agent-core-architecture` §17.2.3–§17.2.4).
///
/// Источники правил: формат и поля `SKILL.md` — спецификация Agent Skills
/// (`docs/protocols/agent-skills/specification.md`, разделы «name field»,
/// «description field», «compatibility field», «metadata field»); мягкая
/// проверка — руководство по реализации клиентов («Lenient validation»,
/// «Handling name collisions»). Код написан для CodeLab, сторонний код не
/// копировался (AGENTS.md §5).
///
/// Почему в ядре: проверка полей, приоритет, `disabled`, предел и сортировка —
/// чистая логика, общая для всех хостов; хост лишь читает файлы и разбирает
/// YAML (CFG-5).
library;

import 'dart:convert';

import '../config/config_tree.dart';
import '../config/key_path.dart';
import '../permissions/modes.dart';
import '../permissions/pattern.dart';
import '../permissions/policy.dart';
import '../project/project_files.dart';
import '../util/posix_path.dart';
import 'skill_files.dart';
import 'skills_config.dart';

/// Проверенный навык сессии.
///
/// Почему неизменяемый: каталог живой сессии не меняется до её закрытия
/// (SKL-4); все потребители читают один снимок.
///
/// Как использовать: получить из [parseSkills]; конструктор открыт для тестов
/// и хостов без файлов.
final class SkillDefinition {
  SkillDefinition({
    required this.name,
    required this.description,
    this.argumentHint,
    this.userInvocable = true,
    this.disableModelInvocation = false,
    this.compatibility,
    List<String> operative = const [],
    required this.body,
    required this.dir,
    required this.scope,
    List<String> companions = const [],
    this.companionsTruncated = false,
  }) : operative = List.unmodifiable(operative),
       companions = List.unmodifiable(companions);

  /// Из поля `name` или имя каталога (`missing_name`).
  final String name;

  /// Схлопнутые пробельные последовательности, без краевых; полная длина.
  final String description;

  /// Подсказка аргумента команды `/skill:<name>` (1–80 символов); `null` —
  /// подсказки нет.
  final String? argumentHint;

  /// У навыка есть команда `/skill:<name>` (`user-invocable`, по умолчанию
  /// `true`).
  final bool userInvocable;

  /// Навык скрыт от модели (`disable-model-invocation`): остаётся только
  /// команда.
  final bool disableModelInvocation;

  /// До 500 символов; пустое — `null`.
  final String? compatibility;

  /// Правила из `metadata.codelab-operative` (K-06); до его реализации не
  /// применяются.
  final List<String> operative;

  /// Обрезанная форма тела (D4): без краевых пробелов, `\n` вместо `\r\n`.
  final String body;

  /// Канонический каталог навыка (`realpath`); пути в блоке навыка и
  /// сопутствующие файлы отсчитываются от него.
  final String dir;

  /// Откуда навык: проект, пользователь или явный корень `extra_roots`.
  final ExtensionScope scope;

  /// Путь файла навыка.
  String get path => '$dir/SKILL.md';

  /// Сопутствующие файлы относительно [dir] (не больше 50, байтовый
  /// порядок); содержимое не читалось.
  final List<String> companions;

  /// Файлов в каталоге больше, чем в [companions].
  final bool companionsTruncated;
}

/// Неизменяемый снимок навыков сессии.
///
/// Почему снимок: секция промпта, инструмент `skill`, команды и повторное
/// приложение после сжатия обязаны видеть один и тот же набор до закрытия
/// сессии (SKL-4), иначе описание в промпте разошлось бы с тем, что вернёт
/// инструмент; перезагрузка конфигурации каталог живой сессии не меняет.
///
/// Как использовать: `AgentSession.skills` отдаёт снимок; секция промпта,
/// инструмент `skill`, команды и повторное приложение читают только его.
final class SkillCatalog {
  SkillCatalog({
    List<SkillDefinition> skills = const [],
    List<SkillDefinition> modelVisible = const [],
    List<ExtensionDiagnostic> diagnostics = const [],
  }) : skills = List.unmodifiable(skills),
       modelVisible = List.unmodifiable(modelVisible),
       diagnostics = List.unmodifiable(diagnostics);

  /// Каталог без навыков.
  static final empty = SkillCatalog();

  /// Все принятые навыки в байтовом порядке имён.
  final List<SkillDefinition> skills;

  /// Подпоследовательность [skills], видимая модели.
  final List<SkillDefinition> modelVisible;

  /// Диагностики проверки (`parseSkills`): те же, что печатает `config check` и
  /// пишет лог `project_files.diagnostic`.
  final List<ExtensionDiagnostic> diagnostics;

  /// Навык по имени или `null`.
  SkillDefinition? skill(String name) {
    for (final s in skills) {
      if (s.name == name) {
        return s;
      }
    }
    return null;
  }

  /// Корни только для чтения для `BoundedEnv`: каталоги загруженных навыков,
  /// которые не лежат в [sessionRoot] и не содержат его (design.md change
  /// `add-agent-skills`, D5, D17; SKL-9).
  ///
  /// Почему так: каталог навыка внутри рабочей папки — её обычная часть, и
  /// правку решает PERM-11; а каталог, внутри которого открыта сессия
  /// (правка своего навыка), — рабочая папка, иначе запись в ней стала бы
  /// `outsideWorkspace`. Сравнение по сегментам, порядок — как у [skills].
  List<String> readOnlyRoots(String sessionRoot) => [
    for (final s in skills)
      if (!isInside(sessionRoot, s.dir) && !isInside(s.dir, sessionRoot)) s.dir,
  ];

  /// Навыки с командой `/skill:<name>`.
  List<SkillDefinition> get commands => [
    for (final s in skills)
      if (s.userInvocable) s,
  ];
}

// Имя, годное для команды и `enum` схемы (D4): разбор команды ASCII.
final _commandName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$');
// Рекомендованное правило спецификации Agent Skills, суженное до ASCII.
final _specName = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');
final _spaces = RegExp(r'\s+');

const _maxCommandName = 128;
const _maxSpecName = 64;
const _maxDescription = 1024;
const _maxHint = 80;
const _maxCompatibility = 500;
const _maxBodyBytes = 64 * 1024;
const _maxOperativeRules = 16;
const _maxOperativeRule = 512;

/// Проверяет навыки, которые отдал хост, и строит каталог сессии.
///
/// Почему мягко: ошибка навыка не должна прерывать сессию, а нарушение
/// косметики — выкидывать навык (D4, Q11). Пропуск — только при `error`:
/// нет frontmatter, негодное имя, нет описания, тело больше 64 КиБ. На первой
/// причине проверка навыка останавливается: одна `error`, без предупреждений.
///
/// Порядок (D16, §17.2.4): стабильная сортировка по `rootIndex`; проверка
/// навыка; `skills.disabled`; перекрытие по имени (первый принятый побеждает,
/// пропущенный с `error` ничего не перекрывает — Q39); предел `max_skills`;
/// сортировка по имени. Сообщения — фиксированные тексты без фрагментов файла.
///
/// Как использовать: рантайм вызывает при открытии сессии, `config check` —
/// для вывода диагностик. [rules] определяют `modelVisible`
/// (`permissions.tools.skill: deny`, `permissions.deny skill:<name>`).
SkillCatalog parseSkills(
  SkillFiles files,
  SkillsConfig settings, {
  PolicyRules rules = const PolicyRules(),
}) {
  final diagnostics = <ExtensionDiagnostic>[];
  // Dart `List.sort` не стабилен: порядок внутри корня держит индекс.
  final indexed =
      [for (var i = 0; i < files.skills.length; i++) (i, files.skills[i])]
        ..sort((a, b) {
          final byRoot = a.$2.rootIndex.compareTo(b.$2.rootIndex);
          return byRoot != 0 ? byRoot : a.$1.compareTo(b.$1);
        });

  final accepted = <SkillDefinition>[];
  final winners = <String, SkillDefinition>{};
  final disabled = settings.disabled.toSet();
  for (final (_, file) in indexed) {
    final local = <ExtensionDiagnostic>[];
    final skill = _checkOne(file, local);
    diagnostics.addAll(local);
    if (skill == null) {
      continue;
    }
    if (disabled.contains(skill.name)) {
      diagnostics.add(
        ExtensionDiagnostic(
          path: file.path,
          level: DiagnosticLevel.info,
          code: 'disabled',
          message: 'the skill is disabled by skills.disabled',
        ),
      );
      continue;
    }
    final winner = winners[skill.name];
    if (winner != null) {
      diagnostics.add(
        ExtensionDiagnostic(
          path: file.path,
          level: DiagnosticLevel.warning,
          code: 'shadowed',
          message: 'the skill is shadowed by ${winner.path} with the same name',
        ),
      );
      continue;
    }
    winners[skill.name] = skill;
    accepted.add(skill);
  }

  var kept = accepted;
  if (accepted.length > settings.maxSkills) {
    kept = accepted.sublist(0, settings.maxSkills);
    diagnostics.add(
      ExtensionDiagnostic(
        path: accepted[settings.maxSkills].path,
        level: DiagnosticLevel.warning,
        code: 'limit_exceeded',
        message:
            'more skills than skills.max_skills; this and later skills are '
            'not loaded',
      ),
    );
  }

  final sorted = [...kept]..sort((a, b) => a.name.compareTo(b.name));
  final toolDenied = rules.toolPolicies['skill'] == ToolPolicy.deny;
  final visible = [
    for (final s in sorted)
      if (!toolDenied &&
          !s.disableModelInvocation &&
          !rules.denyPatterns.contains(PermissionKey('skill', s.name)))
        s,
  ];
  return SkillCatalog(
    skills: sorted,
    modelVisible: visible,
    diagnostics: diagnostics,
  );
}

SkillDefinition? _checkOne(SkillFile file, List<ExtensionDiagnostic> out) {
  void report(
    DiagnosticLevel level,
    String code,
    String message, {
    int? line,
    int? column,
  }) => out.add(
    ExtensionDiagnostic(
      path: file.path,
      line: line,
      column: column,
      level: level,
      code: code,
      message: message,
    ),
  );

  if (file.parseErrors.isNotEmpty) {
    out.addAll(file.parseErrors);
    return null;
  }
  final tree = file.frontmatter;
  if (tree == null) {
    report(
      DiagnosticLevel.error,
      'missing_frontmatter',
      'SKILL.md has no YAML frontmatter; the skill is skipped',
    );
    return null;
  }
  final values = tree.values;
  // Позиции хоста кладут ключ либо как `KeyPath` (с кавычками у имён с `-`),
  // либо как есть; запасной поиск по голому имени нужен хостам без кавычек
  // (тесты, мобильные разборщики).
  ConfigPosition? at(String key) =>
      tree.positions[KeyPath.root.child(key).value] ?? tree.positions[key];
  void field(DiagnosticLevel level, String code, String key, String message) {
    final p = at(key);
    report(level, code, message, line: p?.line, column: p?.column);
  }

  final dirName = file.dir.split(RegExp(r'[/\\]')).last;

  // 1. Имя: пропуск, только если его нельзя сделать командой.
  final rawName = values['name'];
  final String name;
  if (values.containsKey('name')) {
    if (rawName is! String ||
        !_commandName.hasMatch(rawName) ||
        rawName.length > _maxCommandName) {
      field(
        DiagnosticLevel.error,
        'invalid_name',
        'name',
        'the skill name must start with a Latin letter or a digit and contain '
            'only Latin letters, digits, "-" and "_", at most 128 characters; '
            'the skill is skipped',
      );
      return null;
    }
    name = rawName;
  } else {
    if (!_commandName.hasMatch(dirName) || dirName.length > _maxCommandName) {
      report(
        DiagnosticLevel.error,
        'invalid_name',
        'the skill name must start with a Latin letter or a digit and contain '
            'only Latin letters, digits, "-" and "_", at most 128 characters; '
            'the skill is skipped',
      );
      return null;
    }
    name = dirName;
  }

  // 2. Описание: схлопнутые пробелы; пустое — пропуск.
  final rawDescription = values['description'];
  final description = rawDescription is String
      ? rawDescription.replaceAll('\r', '').replaceAll(_spaces, ' ').trim()
      : '';
  if (description.isEmpty) {
    report(
      DiagnosticLevel.error,
      'missing_description',
      'the skill has no description; the skill is skipped',
    );
    return null;
  }

  // 3. Тело: обрезанная форма D4 и предел размера.
  final body = file.body.replaceAll('\r\n', '\n').trim();
  if (utf8.encode(body).length > _maxBodyBytes) {
    report(
      DiagnosticLevel.error,
      'too_large',
      'the skill body is larger than 64 KiB; the skill is skipped',
      line: file.bodyLine,
    );
    return null;
  }

  // Предупреждения: yaml_repaired, поля в порядке ключей файла, empty_body.
  if (file.repaired) {
    report(
      DiagnosticLevel.warning,
      'yaml_repaired',
      'the frontmatter was parsed after quoting values that contain ": "; '
          'check the values',
    );
  }
  if (!values.containsKey('name')) {
    report(
      DiagnosticLevel.warning,
      'missing_name',
      'the frontmatter has no name; the directory name is used',
    );
  }

  String? argumentHint;
  var userInvocable = true;
  var disableModelInvocation = false;
  String? compatibility;
  var operative = const <String>[];
  for (final MapEntry(key: key, value: value) in values.entries) {
    switch (key) {
      case 'name':
        if (!_specName.hasMatch(name) || name.length > _maxSpecName) {
          field(
            DiagnosticLevel.warning,
            'invalid_name',
            key,
            'the skill name should be lowercase Latin letters, digits and '
                'single hyphens, at most 64 characters (Agent Skills)',
          );
        }
        if (name != dirName) {
          field(
            DiagnosticLevel.warning,
            'name_mismatch',
            key,
            'the skill name differs from its directory name; the name from '
                'the frontmatter is used',
          );
        }
      case 'description':
        if (description.runes.length > _maxDescription) {
          field(
            DiagnosticLevel.warning,
            'invalid_value',
            key,
            '"description" is longer than 1024 characters; the catalog shows '
                'the first 1024',
          );
        }
      case 'argument-hint':
        if (value is String &&
            value.isNotEmpty &&
            value.runes.length <= _maxHint) {
          argumentHint = value;
        } else {
          field(
            DiagnosticLevel.warning,
            'invalid_value',
            key,
            '"argument-hint" must be a string of 1 to 80 characters; no hint '
                'is used',
          );
        }
      case 'user-invocable' || 'disable-model-invocation':
        if (value is bool) {
          if (key == 'user-invocable') {
            userInvocable = value;
          } else {
            disableModelInvocation = value;
          }
        } else {
          field(
            DiagnosticLevel.warning,
            'invalid_value',
            key,
            '"$key" must be true or false; the default is used',
          );
        }
      case 'compatibility':
        if (value is! String) {
          field(
            DiagnosticLevel.warning,
            'invalid_value',
            key,
            '"compatibility" must be a string; it is ignored',
          );
        } else if (value.trim().isEmpty) {
          field(
            DiagnosticLevel.warning,
            'invalid_value',
            key,
            '"compatibility" must not be empty; it is ignored',
          );
        } else if (value.runes.length > _maxCompatibility) {
          field(
            DiagnosticLevel.warning,
            'invalid_value',
            key,
            '"compatibility" is longer than 500 characters; it is cut to 500 '
                'characters',
          );
          compatibility = String.fromCharCodes(
            value.runes.take(_maxCompatibility),
          );
        } else {
          compatibility = value;
        }
      case 'metadata':
        if (value is Map<String, Object?> &&
            value.containsKey('codelab-operative')) {
          operative = _operative(value['codelab-operative'], (code, level, m) {
            final p =
                tree.positions[KeyPath.root
                    .child('metadata')
                    .child('codelab-operative')
                    .value] ??
                at('metadata');
            report(level, code, m, line: p?.line, column: p?.column);
          });
        }
      case 'license' || 'allowed-tools':
        break;
      default:
        field(
          DiagnosticLevel.warning,
          'unknown_key',
          key,
          'unknown frontmatter key; the skill is loaded',
        );
    }
  }
  if (body.isEmpty) {
    report(
      DiagnosticLevel.warning,
      'empty_body',
      'the skill body is empty',
      line: file.bodyLine,
    );
  }

  return SkillDefinition(
    name: name,
    description: description,
    argumentHint: argumentHint,
    userInvocable: userInvocable,
    disableModelInvocation: disableModelInvocation,
    compatibility: compatibility,
    operative: operative,
    body: body,
    dir: file.dir,
    scope: file.scope,
    companions: file.companions,
    companionsTruncated: file.companionsTruncated,
  );
}

/// Закреплённые строки навыка из `metadata.codelab-operative` (Q32): каждая
/// непустая строка после обрезки — правило; не больше 16 правил по 1–512
/// символов. Нарушение — `warning`, правил нет; непустой список — `info`
/// `not_applied` (секция закреплённых строк появится с K-06).
List<String> _operative(
  Object? value,
  void Function(String code, DiagnosticLevel level, String message) report,
) {
  if (value is! String) {
    report(
      'invalid_value',
      DiagnosticLevel.warning,
      '"metadata.codelab-operative" must be a string; it is ignored',
    );
    return const [];
  }
  final rules = [
    for (final line in value.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (rules.length > _maxOperativeRules ||
      rules.any((r) => r.runes.length > _maxOperativeRule)) {
    report(
      'invalid_value',
      DiagnosticLevel.warning,
      '"metadata.codelab-operative" must have at most 16 lines of 1 to 512 '
          'characters; it is ignored',
    );
    return const [];
  }
  if (rules.isNotEmpty) {
    report(
      'not_applied',
      DiagnosticLevel.info,
      'metadata.codelab-operative is recognized but not applied in this '
          'version',
    );
  }
  return rules;
}
