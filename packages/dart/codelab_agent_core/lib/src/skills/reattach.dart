/// Приложение навыков после сжатия: одна чистая функция «целиком / усечён /
/// выпал» (design.md change `add-agent-skills`, D15, D20; agent-compaction
/// «Навыки после сжатия»; решение Q6).
///
/// Почему отдельный файл: результат приложения нужен в двух местах —
/// `buildLlmContext` строит по нему сообщение после резюме, а `activeSkills`
/// (шаг 2 D15, `carried`) решает, какие навыки модель ещё видит и целиком ли.
/// Две копии расчёта разошлись бы, и повтор активации ссылался бы на текст,
/// которого в контексте нет.
///
/// Как использовать: `reattachSkills(record.skills, catalog, config)` даёт
/// [Reattachment]; `renderReattachedMessage` — текст сообщения по
/// `prompts/skills/reattached.md`. Функции чистые: ни файлов, ни журнала, ни
/// логов (логи пишут вызывающие). Внутренний файл, в барель не
/// экспортируется.
library;

import '../prompts/prompts.g.dart';
import '../session/records.dart' show CompactionSkill;
import 'skill_block.dart';
import 'skill_catalog.dart';
import 'skill_invocation.dart' show sha256Hex;
import 'skills_config.dart';

/// Навык, приложенный после резюме.
///
/// Почему отдельный тип: проекции нужен готовый блок, `activeSkills` — признак
/// «целиком или усечён», лог — признак смены отпечатка; один расчёт отдаёт
/// всё сразу, чтобы потребители не пересчитывали и не расходились.
///
/// Как использовать: получить из [Reattachment.attached]. [full] читает
/// `activeSkills` (шаг 2 D15: `full: false` — навык не активен для повтора),
/// [block] — `renderReattachedMessage`, [fingerprintChanged] — проекция, чтобы
/// написать `skills.reattach.changed`.
final class ReattachedSkill {
  const ReattachedSkill({
    required this.skill,
    required this.full,
    required this.block,
    required this.fingerprintChanged,
  });

  /// Определение из снимка каталога сессии (текущее тело).
  final SkillDefinition skill;

  /// `false` — тело усечено по `reattachPerSkillTokens` (пометка внутри
  /// блока).
  final bool full;

  /// Готовый блок навыка (в форме результата `skill`, без аргументов).
  final String block;

  /// Отпечаток в записи не совпал с телом снимка: файл правили между
  /// сохранением и загрузкой сессии (D15).
  final bool fingerprintChanged;
}

/// Итог приложения записи `compaction.skills`.
///
/// Почему отдельный тип: результат — функция только записи, каталога и
/// бюджетов (D15, D20), и им пользуются проекция, `activeSkills` и `compact`.
///
/// Как использовать: [attached] идёт в сообщение после резюме и в `carried`
/// шага 2; [dropped] и [truncated] — поля лога `skills.reattached` (пишет
/// `compact`).
final class Reattachment {
  const Reattachment(this.attached, this.dropped);

  static const empty = Reattachment([], 0);

  /// Приложенные навыки в порядке записи (от новой активации к старой).
  final List<ReattachedSkill> attached;

  /// Сколько навыков выпало по общему бюджету. Навыки, которых нет в
  /// каталоге, дубли имён и неразобранные элементы не считаются: они
  /// пропускаются молча (D20, п. 2 и LOW (а)).
  final int dropped;

  /// Сколько приложенных навыков усечено по бюджету на навык.
  int get truncated => attached.where((s) => !s.full).length;
}

/// Оценка §9.3: четыре символа на токен.
int _tokens(int chars) => (chars / 4).ceil();

/// Рассчитывает приложение [recorded] — элементов `compaction.skills`.
///
/// Правила D20: `0` в любом бюджете — ничего; навык ищется в [catalog] по
/// имени, нет — выпадает молча; бюджет на навык считается по телу, общий — по
/// блоку целиком, и первый блок, который не поместился, и все после него
/// выпадают (самые давние активации).
Reattachment reattachSkills(
  List<CompactionSkill> recorded,
  SkillCatalog catalog,
  SkillsConfig config,
) {
  if (recorded.isEmpty ||
      config.reattachPerSkillTokens <= 0 ||
      config.reattachTotalTokens <= 0) {
    return Reattachment.empty;
  }
  final attached = <ReattachedSkill>[];
  var spent = 0;
  var dropped = 0;
  var overflowed = false; // первый блок не поместился: дальше всё выпадает
  final seen = <String>{};
  for (final entry in recorded) {
    // Неразобранный элемент и повтор имени пропускаются без лога и счёта:
    // действует первое вхождение (D20, LOW). Журнал можно подложить.
    final name = entry.name;
    if (!entry.isValid || !seen.add(name!)) {
      continue;
    }
    final skill = catalog.skill(name);
    if (skill == null) {
      continue;
    }
    if (overflowed) {
      dropped++;
      continue;
    }
    final fits = _tokens(skill.body.length) <= config.reattachPerSkillTokens;
    final block = fits
        ? renderSkillBlock(skill)
        : renderSkillBlock(
            skill,
            body: _truncatedBody(
              skill,
              config.reattachPerSkillTokens,
              modelVisible: catalog.modelVisible.contains(skill),
            ),
          );
    spent += _tokens(block.length);
    if (spent > config.reattachTotalTokens) {
      overflowed = true;
      dropped++;
      continue;
    }
    attached.add(
      ReattachedSkill(
        skill: skill,
        full: fits,
        block: block,
        fingerprintChanged: sha256Hex(skill.body) != entry.fingerprint!,
      ),
    );
  }
  return Reattachment(attached, dropped);
}

/// Наибольший префикс целых строк тела, чья оценка не больше [budget], и
/// следующей строкой пометка по виду навыка: совет инструмента `skill` — для
/// [modelVisible], `/skill:<name>` — для вызываемого, иначе без совета (D15,
/// D20, п. 3).
String _truncatedBody(
  SkillDefinition skill,
  int budget, {
  required bool modelVisible,
}) {
  final mark = modelVisible
      ? '[skill truncated: load it again with the skill tool for the full '
            'text]'
      : skill.userInvocable
      ? '[skill truncated: the user can run /skill:${skill.name} for the '
            'full text]'
      : '[skill truncated]';
  final lines = skill.body.split('\n');
  var length = 0;
  var count = 0;
  for (final line in lines) {
    final next = length + (count == 0 ? 0 : 1) + line.length;
    if (_tokens(next) > budget) {
      break;
    }
    length = next;
    count++;
  }
  final kept = lines.take(count).join('\n');
  return count == 0 ? mark : '$kept\n$mark';
}

/// Текст сообщения после резюме: блоки через пустую строку (D20, п. 5).
String renderReattachedMessage(Reattachment result) => Prompts.skillsReattached
    .render({'blocks': result.attached.map((s) => s.block).join('\n\n')});
