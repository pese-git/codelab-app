import 'dart:convert';

import '../config/config_tree.dart';
import '../config/key_path.dart';
import '../llm/model_catalog.dart';
import '../llm/model_ref.dart';
import '../permissions/modes.dart';
import '../project/project_files.dart';

/// Где определение агента доступно (`agent-core-architecture` §15.8; design.md
/// change `add-agent-project-files`, D10).
///
/// Почему три значения: одно определение может быть и профилем сессии (опция
/// `agent`), и типом субагента (`task`, §17.3). Инструмента `task` ещё нет,
/// поэтому `subagent` загружается, но в [AgentSession.agents] не входит.
enum AgentScope {
  /// Только опция `agent` сессии.
  session,

  /// Только тип субагента (после MVP).
  subagent,

  /// Оба места; значение по умолчанию.
  both,
}

/// Проверенное определение агента из Markdown-файла (§15.8; D10).
///
/// Почему отдельный тип: определение — не конфигурация и не промпт. Оно
/// выбирает модель, режим и набор инструментов и добавляет текст в системный
/// промпт, поэтому его поля проверяются один раз при загрузке, а применение
/// (`AgentSession.setAgent`, D11) работает с готовыми значениями.
///
/// Как использовать: получить из [parseAgentDefinitions]; конструктор открыт
/// для тестов и хостов без файлов.
final class AgentDefinition {
  AgentDefinition({
    required this.name,
    required this.description,
    required this.prompt,
    required this.source,
    this.model,
    this.mode,
    List<String>? tools,
    this.scope = AgentScope.both,
  }) : tools = tools == null ? null : List.unmodifiable(tools);

  /// `^[a-z][a-z0-9-]{0,47}$`, не `default`.
  final String name;

  /// 1–200 символов; показывается в описании варианта опции `agent`.
  final String description;

  /// Тело файла: попадает в системный промпт секцией `agent_profile`.
  /// В лог не пишется (D14).
  final String prompt;

  /// Путь файла для диагностики и лога `agent.selected`.
  final String source;

  /// Модель из каталога моделей сборки; `null` — модель сессии не меняется.
  final ModelRef? model;

  /// Режим определения; `null` — режим сессии не меняется. Применяется, только
  /// если не мягче режима конфигурации (D11, OQ3).
  final ModeId? mode;

  /// Имена инструментов; `*` в конце — префиксный шаблон. `null` — все
  /// инструменты сессии, пустой список — ни одного (CFG-7).
  final List<String>? tools;

  /// Где агент доступен: `session` — в опции `agent` сессии, `subagent` — как
  /// исполнитель для инструмента-делегата (позже), `both` — в обоих местах
  /// (по умолчанию). От значения зависит [forSession].
  final AgentScope scope;

  /// Определение показывается в опции `agent` сессии.
  bool get forSession => scope != AgentScope.subagent;

  /// Инструмент [toolName] входит в набор агента (CFG-7). Только сужает набор:
  /// существование инструмента и разрешения проверяются другими звеньями.
  bool allowsTool(String toolName) {
    final patterns = tools;
    if (patterns == null) {
      return true;
    }
    for (final pattern in patterns) {
      if (pattern.endsWith('*')
          ? toolName.startsWith(pattern.substring(0, pattern.length - 1))
          : toolName == pattern) {
        return true;
      }
    }
    return false;
  }

  @override
  String toString() => 'AgentDefinition($name)';
}

/// Результат [parseAgentDefinitions].
final class AgentParseResult {
  AgentParseResult(
    List<AgentDefinition> agents,
    List<ExtensionDiagnostic> diagnostics,
  ) : agents = List.unmodifiable(agents),
      diagnostics = List.unmodifiable(diagnostics);

  /// Принятые определения всех областей в байтовом порядке имён.
  final List<AgentDefinition> agents;

  /// Диагностика отброшенных и спорных определений (неверное поле, дубль
  /// имени, неизвестная модель). Содержит путь, код и позицию, но не тело
  /// файла (D14); ядро пишет её в лог `project_files.diagnostic`.
  final List<ExtensionDiagnostic> diagnostics;

  /// Определения для опции `agent` сессии: `session` и `both`.
  List<AgentDefinition> get sessionAgents => [
    for (final agent in agents)
      if (agent.forSession) agent,
  ];
}

final _nameRule = RegExp(r'^[a-z][a-z0-9-]{0,47}$');
final _toolRule = RegExp(r'^[A-Za-z0-9_-]+\*?$');
const _maxDescription = 200;
const _maxBodyBytes = 32 * 1024;
const _allowedKeys = {'name', 'description', 'model', 'mode', 'tools', 'scope'};

/// Имя, которым сессия называет отсутствие профиля агента (D11).
const defaultAgentName = 'default';

/// Проверяет файлы определений, которые отдал хост (D3, пункт 2; D10).
///
/// Почему в ядре: проверка ключей, имён, режима и модели — чистая логика,
/// общая для всех хостов; хост только читает файлы и разбирает frontmatter
/// (то же разделение, что у [parseCommandTemplates], CFG-5).
///
/// Для чего: дать список определений и диагностику. Ошибка файла — диагностика
/// уровня `error` и пропуск файла, а не исключение: она не должна прерывать
/// создание сессии. Сообщения строятся из фиксированных текстов, без значений
/// из файла (D14).
///
/// Правила: [models] — каталог моделей сборки, модель вне него — ошибка;
/// два файла с одним `name` в одной области пропускаются оба (`duplicate`);
/// определение проекта заменяет пользовательское независимо от порядка входа
/// (пользовательское получает `info` `shadowed`), а пользовательское не
/// заменяется проектным, которое не прошло проверку.
AgentParseResult parseAgentDefinitions(
  List<MarkdownFile> files, {
  required ModelCatalog models,
}) {
  final diagnostics = <ExtensionDiagnostic>[];
  final valid = <(MarkdownFile, AgentDefinition)>[];
  for (final file in files) {
    final agent = _parseOne(file, models, diagnostics);
    if (agent != null) {
      valid.add((file, agent));
    }
  }

  // Повтор имени в одном каталоге: оба файла отбрасываются, иначе выбор между
  // ними зависел бы от порядка листинга (D10).
  final dropped = <MarkdownFile>{};
  for (final bucket in [
    valid.where((e) => e.$1.scope == ExtensionScope.project),
    valid.where((e) => e.$1.scope != ExtensionScope.project),
  ]) {
    final byName = <String, List<(MarkdownFile, AgentDefinition)>>{};
    for (final entry in bucket) {
      byName.putIfAbsent(entry.$2.name, () => []).add(entry);
    }
    for (final twins in byName.values.where((list) => list.length > 1)) {
      final paths = [for (final (file, _) in twins) file.path]..sort();
      for (final (file, _) in twins) {
        dropped.add(file);
        diagnostics.add(
          ExtensionDiagnostic(
            path: file.path,
            level: DiagnosticLevel.error,
            code: 'duplicate',
            message:
                'the agent name is defined by several files in one directory '
                '(${paths.join(', ')}); all of them are skipped',
          ),
        );
      }
    }
  }

  final byName = <String, AgentDefinition>{};
  final ordered = [
    ...valid.where((e) => e.$1.scope == ExtensionScope.project),
    ...valid.where((e) => e.$1.scope != ExtensionScope.project),
  ];
  for (final (file, agent) in ordered) {
    if (dropped.contains(file)) {
      continue;
    }
    if (byName.containsKey(agent.name)) {
      diagnostics.add(
        ExtensionDiagnostic(
          path: file.path,
          level: DiagnosticLevel.info,
          code: 'shadowed',
          message: 'the agent is replaced by another one with the same name',
        ),
      );
      continue;
    }
    byName[agent.name] = agent;
  }
  final agents = byName.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return AgentParseResult(agents, diagnostics);
}

AgentDefinition? _parseOne(
  MarkdownFile file,
  ModelCatalog models,
  List<ExtensionDiagnostic> diagnostics,
) {
  var ok = true;
  void fail(String code, String message, {int? line, int? column}) {
    ok = false;
    diagnostics.add(
      ExtensionDiagnostic(
        path: file.path,
        line: line,
        column: column,
        level: DiagnosticLevel.error,
        code: code,
        message: message,
      ),
    );
  }

  final tree = file.frontmatter;
  if (tree == null) {
    fail(
      'invalid_value',
      'the file has no frontmatter; name and description are required',
      line: 1,
    );
    return null;
  }
  final values = tree.values;
  ConfigPosition? at(String key) =>
      tree.positions[KeyPath.root.child(key).value];
  void invalid(String key, String message) {
    final p = at(key);
    fail('invalid_value', message, line: p?.line, column: p?.column);
  }

  for (final key in values.keys) {
    if (!_allowedKeys.contains(key)) {
      final p = at(key);
      fail(
        'unknown_key',
        'unknown frontmatter key; allowed: name, description, model, mode, '
            'tools, scope',
        line: p?.line,
        column: p?.column,
      );
    }
  }

  String? name;
  if (values['name'] case final String value
      when _nameRule.hasMatch(value) && value != defaultAgentName) {
    name = value;
  } else {
    invalid(
      'name',
      '"name" is required: ^[a-z][a-z0-9-]{0,47}\$, not "default"',
    );
  }

  String? description;
  if (values['description'] case final String value
      when value.isNotEmpty && value.runes.length <= _maxDescription) {
    description = value;
  } else {
    invalid(
      'description',
      '"description" is required: a string of 1 to $_maxDescription '
          'characters',
    );
  }

  ModelRef? model;
  if (values.containsKey('model')) {
    final value = values['model'];
    final slash = value is String ? value.indexOf('/') : -1;
    model = value is String && slash > 0 && slash < value.length - 1
        ? models.resolve(ModelId(value))
        : null;
    if (model == null) {
      invalid(
        'model',
        '"model" must be a model of the catalog: <provider>/<id>',
      );
    }
  }

  ModeId? mode;
  if (values.containsKey('mode')) {
    final value = values['mode'];
    mode = ModeId.values.where((m) => m.value == value).firstOrNull;
    if (mode == null) {
      invalid(
        'mode',
        '"mode" must be one of plan, ask, standard, accept-edits, bypass; '
            'autopilot is enabled only by a launch flag',
      );
    }
  }

  List<String>? tools;
  if (values.containsKey('tools')) {
    final value = values['tools'];
    if (value is List &&
        value.every((e) => e is String && _toolRule.hasMatch(e))) {
      tools = [for (final e in value) e as String];
    } else {
      invalid(
        'tools',
        '"tools" must be a list of tool names; "*" is allowed only at the end '
            'of a name',
      );
    }
  }

  var scope = AgentScope.both;
  if (values.containsKey('scope')) {
    final value = values['scope'];
    final parsed = AgentScope.values.where((s) => s.name == value).firstOrNull;
    if (parsed == null) {
      invalid('scope', '"scope" must be one of session, subagent, both');
    } else {
      scope = parsed;
    }
  }

  if (file.body.trim().isEmpty) {
    fail('empty_body', 'the agent body is empty', line: file.bodyLine);
  } else if (utf8.encode(file.body).length > _maxBodyBytes) {
    fail(
      'too_large',
      'the agent body is larger than 32 KiB',
      line: file.bodyLine,
    );
  }

  if (!ok || name == null || description == null) {
    return null;
  }
  return AgentDefinition(
    name: name,
    description: description,
    prompt: file.body,
    source: file.path,
    model: model,
    mode: mode,
    tools: tools,
    scope: scope,
  );
}
