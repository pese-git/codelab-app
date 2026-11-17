/// Команды `skill:<name>` для списка команд сессии (design.md change
/// `add-agent-skills`, D8, D18; agent-slash-commands «Список команд сессии»).
///
/// Почему отдельный файл: список строится из снимка навыков при открытии
/// сессии, а разворачивание и журнал — в рантайме; здесь только то, что видит
/// клиент (имя, описание, подсказка), без тела навыка и путей.
///
/// Как использовать: рантайм добавляет результат [skillSlashCommands] в
/// `AgentSession.commands` после команд шаблонов.
library;

import '../commands/slash_command.dart';
import 'skill_catalog.dart';

/// Префикс слова команды навыка (`/skill:<name>`): одна константа для списка,
/// разбора и журнала (D8, D18).
const skillCommandPrefix = 'skill:';

/// Предел описания команды в рунах (как строка каталога, D4, D17): ACP-список
/// не должен нести описание в десятки килобайт.
const _descriptionLimit = 1024;

/// Команды навыков с `user-invocable` в порядке снимка (байтовом).
///
/// `inputHint` — `argument-hint`, иначе `"arguments"` (D8). Навык с
/// `disable-model-invocation` остаётся командой: запрет модели не ограничивает
/// человека (D7). Инструмент `skill` в список не попадает (R-07, SKL-6).
List<SlashCommand> skillSlashCommands(SkillCatalog catalog) =>
    List.unmodifiable([
      for (final skill in catalog.commands)
        SlashCommand(
          name: '$skillCommandPrefix${skill.name}',
          description: _cut(skill.description),
          source: SlashCommandSource.skill,
          inputHint: skill.argumentHint ?? 'arguments',
        ),
    ]);

String _cut(String text) {
  final runes = text.runes;
  return runes.length <= _descriptionLimit
      ? text
      : '${String.fromCharCodes(runes.take(_descriptionLimit))}…';
}
