/// Активные навыки сессии: одна чистая функция над журналом (design.md change
/// `add-agent-skills`, D7, D8, D15, D18; agent-skills «Активные навыки»;
/// решения Q10, Q48 (б); K-06).
///
/// Почему отдельный файл: повтор активации в инструменте `skill` и команде
/// `/skill:`, приложение навыков после сжатия (D20, `reattachSkills`) и
/// закреплённые строки K-06 должны отвечать на вопрос «какие навыки сейчас в
/// контексте модели» одинаково. Новых записей журнала для этого нет: ответ
/// выводится из сообщений активной ветки.
///
/// Как использовать: `activeSkills(snapshot, catalog, settings)`; навык
/// **активен**, если входит в результат с `full: true`. Функция не меняет
/// снимок и не читает файлы; одинаковые входы дают одинаковый результат.
/// Внутренняя: в барель не экспортируется (D10, D18).
library;

import '../llm/messages.dart';
import '../session/projections.dart' show keptPath, lastCompactionIndex;
import '../session/records.dart';
import '../session/session_store.dart';
import '../session/tree.dart';
import 'reattach.dart';
import 'skill_block.dart';
import 'skill_catalog.dart';
import 'skill_invocation.dart';
import 'skills_config.dart';

/// Навык, тело которого есть в контексте модели.
///
/// [full] — тело приложено целиком; усечённое после сжатия (D20) даёт
/// `false` и активным для повтора не считается. [content] — SHA-256 UTF-8
/// текста активации (hex, нижний регистр): для инструмента — тело снимка
/// (`SkillDefinition.body`), для команды — тело после подстановки её
/// аргументов без хвоста `ARGUMENTS:`.
final class ActiveSkill {
  const ActiveSkill({
    required this.name,
    required this.full,
    required this.content,
  });

  final String name;
  final bool full;
  final String content;
}

/// Активные навыки активной ветки [snapshot], от новой активации к старой.
///
/// Активация — одно из двух (D15, D18):
/// - успешный результат инструмента `skill` (`isError == false`), который
///   равен блоку навыка из текущего [catalog]; строка повтора инструмента не
///   активация;
/// - сообщение пользователя с `command.source == "skill"`, чей первый
///   текстовый блок целиком равен тексту команды по текущему снимку вместе с
///   хвостом `ARGUMENTS:` (Q48 (б)); сообщение повтора команды не активация:
///   тела в нём нет, и сжатие, оставившее в хвосте один повтор, не приложило
///   бы навык.
///
/// Учитываются только записи, которые видит модель: `keptPath` от
/// `firstKeptId` последнего сжатия (D15, шаги 1 и 3), плюс `carried` —
/// навыки записи `last.skills`, которые приложение после резюме приложило
/// (шаг 2, D20): целиком — `full: true`, усечённым — `full: false`; выпавшие
/// по общему бюджету и отсутствующие в каталоге не входят, а `content` —
/// SHA-256 текущего тела снимка. Расчёт общий с `buildLlmContext`
/// (`reattachSkills`).
///
/// Запись, не совпавшая с текущим снимком (правили `SKILL.md` между сессиями
/// или сменился `dir`), активацией не считается: следующий вызов вставит
/// новое тело целиком — безопасная сторона. Имя вне [catalog] и нестроковое
/// имя вызова пропускаются. Более новая запись о навыке заменяет более
/// старую. Параметр [settings] — бюджеты приложения после сжатия
/// (`reattachPerSkillTokens`, `reattachTotalTokens`).
List<ActiveSkill> activeSkills(
  SessionSnapshot snapshot,
  SkillCatalog catalog,
  SkillsConfig settings,
) {
  final calls = <String, Object?>{};
  // От старой к новой: каждая активация переставляет навык в начало списка.
  final result = <ActiveSkill>[];
  void activate(ActiveSkill skill) {
    result
      ..removeWhere((s) => s.name == skill.name)
      ..insert(0, skill);
  }

  // Только то, что модель ещё видит: от `firstKeptId` последнего сжатия
  // (D15, шаги 1 и 3). Тот же срез, что у `buildLlmContext`.
  final path = pathToLeaf(snapshot);
  final visible = keptPath(path, compactionIndex: lastCompactionIndex(path));
  // Шаг 2 D15: приложенные после сжатия навыки идут первыми в порядке записи;
  // более новая активация в хвосте заменит элемент через `activate`.
  final recorded = visible.compaction?.skills;
  if (recorded != null) {
    final carried = reattachSkills(recorded, catalog, settings);
    for (final s in carried.attached) {
      result.add(
        ActiveSkill(
          name: s.skill.name,
          full: s.full,
          content: sha256Hex(s.skill.body),
        ),
      );
    }
  }
  for (final record in visible.kept) {
    if (record is! MessageRecord) {
      continue;
    }
    final message = record.message;
    if (message is AssistantMessage) {
      for (final call in message.toolCalls) {
        calls[call.id] = call.arguments['name'];
      }
    } else if (message is ToolResultMessage) {
      if (message.toolName != 'skill' || message.isError) {
        continue;
      }
      final name = calls[message.toolCallId];
      final skill = name is String ? catalog.skill(name) : null;
      if (skill != null && _text(message) == renderSkillBlock(skill)) {
        activate(
          ActiveSkill(
            name: skill.name,
            full: true,
            content: sha256Hex(skill.body),
          ),
        );
      }
    } else if (message is UserMessage) {
      final command = record.command;
      if (command == null || command.source != 'skill') {
        continue;
      }
      final skill = catalog.skill(command.name);
      if (skill == null) {
        continue;
      }
      final invocation = invokeSkill(skill, command.args);
      // Сообщение сверяется целиком: первый текстовый блок равен тексту,
      // который дала бы команда по текущему снимку (Q48 (б)). Сообщение
      // повтора под это равенство не подходит само: тела в нём нет, а потому
      // оно не активация (иначе сжатие, оставившее в хвосте один повтор,
      // решило бы, что тело «и так в контексте»). Другое число сопутствующих
      // файлов или другой `dir` — тоже несовпадение: безопасная сторона.
      if (_firstText(message) == invocation.full) {
        activate(
          ActiveSkill(
            name: skill.name,
            full: true,
            content: invocation.content,
          ),
        );
      }
    }
  }
  return List.unmodifiable(result);
}

/// Первый текстовый блок сообщения: на его место команда кладёт развёрнутый
/// текст (остальные блоки промпта идут после него).
String _firstText(Message message) =>
    message.content.whereType<TextContent>().firstOrNull?.text ?? '';

/// Текстовые блоки сообщения подряд: так модель видит развёрнутый текст.
String _text(Message message) =>
    message.content.whereType<TextContent>().map((b) => b.text).join();
