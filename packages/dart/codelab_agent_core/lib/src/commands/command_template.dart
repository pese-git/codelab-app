import 'dart:convert';

import '../config/config_tree.dart';
import '../config/key_path.dart';
import '../project/project_files.dart';
import 'arguments.dart';
import 'slash_command.dart';

/// Проверенный шаблон команды (design.md change `add-agent-project-files`,
/// D3, D7; `agent-core/17-2-skills-and-templates.md` §17.2.2).
///
/// Как использовать: получить из [parseCommandTemplates]; конструктор открыт
/// для тестов и хостов без файлов (web, мобильные).
final class CommandTemplate {
  CommandTemplate({
    required this.name,
    required this.description,
    required this.body,
    required this.scope,
    required this.path,
    this.argumentHint,
  }) : usesArguments = usesPlaceholders(body);

  /// Имя файла без `.md`: `^[a-z0-9][a-z0-9-]{0,63}$`.
  final String name;
  final String description;
  final String? argumentHint;
  final String body;
  final ExtensionScope scope;

  /// Путь файла для диагностик и `config check`.
  final String path;

  /// Тело содержит `$ARGUMENTS` или `$1`…`$9`.
  final bool usesArguments;

  @override
  String toString() => 'CommandTemplate(/$name)';
}

/// Результат [parseCommandTemplates].
final class TemplateParseResult {
  TemplateParseResult(
    List<CommandTemplate> templates,
    List<ExtensionDiagnostic> diagnostics,
  ) : templates = List.unmodifiable(templates),
      diagnostics = List.unmodifiable(diagnostics);

  /// Принятые шаблоны в байтовом порядке имён.
  final List<CommandTemplate> templates;
  final List<ExtensionDiagnostic> diagnostics;
}

/// Имена, которые шаблон занять не может: встроенные команды §13.4 и `skill`
/// (design.md D7, SKL-7).
///
/// Почему резервируется весь список заранее, хотя встроенных команд ещё нет:
/// иначе шаблон `status.md` работал бы до change встроенных команд и молча
/// перестал бы после; встроенная команда не должна меняться от файла в
/// репозитории.
const reservedCommandNames = <String>{
  'compact',
  'mode',
  'model',
  'status',
  'usage',
  'redact',
  'config',
  'mcp',
  'rename',
  'branches',
  'branch',
  'rewind',
  'fork',
  'label',
  'approve',
  'timer',
  'memory',
  'tasks',
  'help',
  'skill',
};

final _nameRule = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');
const _maxDescription = 200;
const _maxHint = 80;
const _maxBodyBytes = 32 * 1024;
const _allowedKeys = {'description', 'argument-hint'};

/// Проверяет файлы шаблонов, которые отдал хост (D3, пункт 2; D7).
///
/// Почему в ядре: проверка ключей, имён и лимитов — чистая логика, общая для
/// настольного, мобильного и встроенного хостов; хост только читает файлы и
/// разбирает frontmatter (то же разделение, что `ConfigTree` →
/// `CoreConfig.fromLayers`).
///
/// Для чего: дать список шаблонов и диагностику. Ошибка файла — диагностика и
/// пропуск файла, а не исключение: она не должна прерывать создание сессии.
/// Сообщения строятся из фиксированных текстов, без содержимого файла и
/// значений ключей (D14).
///
/// Правила: проект перекрывает пользователя независимо от порядка входа
/// (перекрытый получает `info` `shadowed`); пользовательский шаблон не
/// перекрывается проектным, который не прошёл проверку.
TemplateParseResult parseCommandTemplates(List<MarkdownFile> files) {
  final diagnostics = <ExtensionDiagnostic>[];
  final ordered = [
    ...files.where((f) => f.scope == ExtensionScope.project),
    ...files.where((f) => f.scope != ExtensionScope.project),
  ];
  final byName = <String, CommandTemplate>{};
  for (final file in ordered) {
    final template = _parseOne(file, diagnostics);
    if (template == null) {
      continue;
    }
    if (byName.containsKey(template.name)) {
      diagnostics.add(
        ExtensionDiagnostic(
          path: file.path,
          level: DiagnosticLevel.info,
          code: 'shadowed',
          message: 'the template is replaced by another one with the same name',
        ),
      );
      continue;
    }
    byName[template.name] = template;
  }
  final templates = byName.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return TemplateParseResult(templates, diagnostics);
}

CommandTemplate? _parseOne(
  MarkdownFile file,
  List<ExtensionDiagnostic> diagnostics,
) {
  void report(
    DiagnosticLevel level,
    String code,
    String message, {
    int? line,
    int? column,
  }) => diagnostics.add(
    ExtensionDiagnostic(
      path: file.path,
      line: line,
      column: column,
      level: level,
      code: code,
      message: message,
    ),
  );

  final base = file.path.split(RegExp(r'[/\\]')).last;
  final name = base.endsWith('.md')
      ? base.substring(0, base.length - '.md'.length)
      : base;
  if (!_nameRule.hasMatch(name)) {
    report(
      DiagnosticLevel.warning,
      'invalid_name',
      'the file name is not a valid command name '
          '(^[a-z0-9][a-z0-9-]{0,63}\$); the template is skipped',
    );
    return null;
  }
  if (reservedCommandNames.contains(name)) {
    report(
      DiagnosticLevel.warning,
      'reserved_name',
      'the name belongs to a builtin command; the template is skipped',
    );
    return null;
  }

  final tree = file.frontmatter;
  final values = tree?.values ?? const <String, Object?>{};
  ConfigPosition? at(String key) =>
      tree?.positions[KeyPath.root.child(key).value];

  var ok = true;
  for (final key in values.keys) {
    if (!_allowedKeys.contains(key)) {
      final p = at(key);
      report(
        DiagnosticLevel.error,
        'unknown_key',
        'unknown frontmatter key; allowed: description, argument-hint',
        line: p?.line,
        column: p?.column,
      );
      ok = false;
    }
  }
  String? text(String key, int max) {
    if (!values.containsKey(key)) {
      return null;
    }
    final v = values[key];
    if (v is! String || v.isEmpty || v.runes.length > max) {
      final p = at(key);
      report(
        DiagnosticLevel.error,
        'invalid_value',
        '"$key" must be a string of 1 to $max characters',
        line: p?.line,
        column: p?.column,
      );
      ok = false;
      return null;
    }
    return v;
  }

  final description = text('description', _maxDescription);
  final hint = text('argument-hint', _maxHint);
  if (!ok) {
    return null;
  }

  if (file.body.trim().isEmpty) {
    report(
      DiagnosticLevel.error,
      'empty_body',
      'the template body is empty',
      line: file.bodyLine,
    );
    return null;
  }
  if (utf8.encode(file.body).length > _maxBodyBytes) {
    report(
      DiagnosticLevel.error,
      'too_large',
      'the template body is larger than 32 KiB',
      line: file.bodyLine,
    );
    return null;
  }

  return CommandTemplate(
    name: name,
    description: description ?? _firstLine(file.body),
    argumentHint: hint,
    body: file.body,
    scope: file.scope,
    path: file.path,
  );
}

/// Первая непустая строка тела, обрезанная до 200 символов (D7).
String _firstLine(String body) {
  for (final line in body.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      final runes = trimmed.runes.toList();
      return runes.length <= _maxDescription
          ? trimmed
          : String.fromCharCodes(runes.take(_maxDescription));
    }
  }
  return '';
}

/// Команды сессии из принятых шаблонов, в байтовом порядке имён (D7).
///
/// Подсказка ввода: `argument-hint`, иначе `"arguments"` для шаблона с
/// плейсхолдерами, иначе `null`. Инструменты модели в список не попадают
/// (R-07): функция видит только шаблоны.
List<SlashCommand> availableCommands(List<CommandTemplate> templates) {
  final sorted = [...templates]..sort((a, b) => a.name.compareTo(b.name));
  return List.unmodifiable([
    for (final t in sorted)
      SlashCommand(
        name: t.name,
        description: t.description,
        source: SlashCommandSource.template,
        inputHint: t.argumentHint ?? (t.usesArguments ? 'arguments' : null),
      ),
  ]);
}
