import '../agents/agent_definition.dart';
import '../permissions/modes.dart';
import '../prompts/prompts.g.dart';
import '../util/logger.dart';

/// Типы субагентов сессии: встроенные плюс определения агентов (`agent-core/
/// 17-3-subagents.md` §17.3.2; design.md change `add-subagents-and-tasks`,
/// D36 Т1).
///
/// Почему снимок: схема `agent` и её `enum` не должны меняться посреди сессии
/// (кэш промпта), поэтому набор строится один раз при создании сессии.
///
/// Для чего: [definitions] — определения со `scope` `subagent` и `both`;
/// пользовательское с именем встроенного заменяет его (лог
/// `subagent.type_overridden`). Результат отсортирован по имени.
///
/// Как использовать: рантайм вызывает при открытии сессии и передаёт
/// `SubagentTool`.
List<AgentDefinition> buildSubagentTypes(
  List<AgentDefinition> definitions, {
  Logger? logger,
}) {
  final byName = {for (final type in builtinSubagentTypes()) type.name: type};
  for (final definition in definitions) {
    if (definition.scope == AgentScope.session) {
      continue;
    }
    if (byName.containsKey(definition.name) &&
        byName[definition.name]!.source.startsWith('builtin:')) {
      logger?.log(
        LogLevel.info,
        'subagent.type_overridden',
        fields: {'name': definition.name, 'source': definition.source},
      );
    }
    byName[definition.name] = definition;
  }
  return [for (final name in byName.keys.toList()..sort()) byName[name]!];
}

/// Встроенные типы `general`, `explore`, `review`, `plan` (`source:
/// builtin:<имя>`); тела — `prompts/subagent/types/*.md`.
List<AgentDefinition> builtinSubagentTypes() => [
  AgentDefinition(
    name: 'general',
    description:
        'General-purpose agent for multi-step tasks that may read, edit '
        'files and run commands.',
    prompt: Prompts.subagentTypesGeneral.render({}),
    source: 'builtin:general',
  ),
  AgentDefinition(
    name: 'explore',
    description:
        'Read-only search of the codebase. Returns findings with file paths '
        'and line numbers.',
    prompt: Prompts.subagentTypesExplore.render({}),
    source: 'builtin:explore',
    tools: const ['read', 'ls', 'search'],
    mode: ModeId.plan,
  ),
  AgentDefinition(
    name: 'review',
    description:
        'Reviews changes for defects. Reads files and may run read-only '
        'commands such as git diff.',
    prompt: Prompts.subagentTypesReview.render({}),
    source: 'builtin:review',
    tools: const ['read', 'ls', 'search', 'exec'],
    mode: ModeId.standard,
  ),
  AgentDefinition(
    name: 'plan',
    description:
        'Investigates the code and returns an implementation plan without '
        'changing files.',
    prompt: Prompts.subagentTypesPlan.render({}),
    source: 'builtin:plan',
    tools: const ['read', 'ls', 'search'],
    mode: ModeId.plan,
  ),
];
