/// Команда, видимая клиенту (design.md change `add-agent-project-files`, D7,
/// D9; `agent-core/17-2-skills-and-templates.md` §17.2.6).
///
/// Почему отдельный тип от [CommandTemplate]: клиенту нужны только имя,
/// описание и подсказка ввода; тело шаблона и пути файлов наружу не идут.
///
/// Как использовать: хост (ACP-адаптер) читает `AgentSession.commands` и
/// публикует список как `available_commands_update`.
library;

/// Откуда команда. Новые источники (встроенные, skills, MCP prompts) добавят
/// свои значения в этот enum, не меняя [SlashCommand].
enum SlashCommandSource {
  /// Шаблон `*.md` из `$CODELAB_HOME/prompts` или `<cwd>/.codelab/prompts`.
  template('template');

  const SlashCommandSource(this.wire);

  /// Значение в журнале (`command.source`).
  final String wire;
}

/// Элемент `AgentSession.commands`.
final class SlashCommand {
  const SlashCommand({
    required this.name,
    required this.description,
    required this.source,
    this.inputHint,
  });

  /// Имя без `/`.
  final String name;
  final String description;

  /// Подсказка ввода: `argument-hint`, иначе `"arguments"`, если тело
  /// использует плейсхолдеры, иначе `null` (D7).
  final String? inputHint;
  final SlashCommandSource source;

  @override
  String toString() => 'SlashCommand(/$name)';
}
