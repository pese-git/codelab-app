import '../../llm/messages.dart';
import '../../loop/agent_events.dart';
import '../../prompts/prompts.g.dart';
import '../../skills/skill_block.dart';
import '../../skills/skill_catalog.dart';
import '../../util/logger.dart';
import '../agent_tool.dart';
import 'common.dart';

/// `skill` — загрузка тела навыка по имени (design.md change
/// `add-agent-skills`, D7, D17; agent-skills «Инструмент skill»; решения Q10,
/// Q12; SKL-3, SKL-5).
///
/// Почему отдельный инструмент: модель выбирает навык по описанию из
/// каталога в системном промпте, а тело подгружается только по надобности
/// (прогрессивное раскрытие), не раздувая контекст.
///
/// Как использовать: рантайм создаёт экземпляр на сессию из снимка каталога
/// и регистрирует его в реестре сессии, только если `modelVisible` не пуст
/// (SKL-5). Файл навыка не перечитывается: результат строится из снимка.
/// `enum` схемы — имена `modelVisible`; имя вне `enum` обычно отсекает
/// исполнитель по схеме, а `Unknown skill` — защита для прямого вызова.
final class SkillTool extends AgentTool {
  SkillTool(this.catalog, {this.sessionId});

  /// Неизменяемый снимок каталога сессии (SKL-4).
  final SkillCatalog catalog;

  /// Сессия для поля `session_id` лога; у голого инструмента в тестах `null`.
  final SessionId? sessionId;

  @override
  String get name => 'skill';

  @override
  String get description => Prompts.toolDescriptionsSkill.render(const {});

  @override
  Map<String, Object?> get parameters => {
    'type': 'object',
    'properties': {
      'name': {
        'type': 'string',
        'enum': [for (final s in catalog.modelVisible) s.name],
        'description': 'Skill name exactly as listed in the Skills section.',
      },
    },
    'required': ['name'],
  };

  @override
  ToolTier get tier => ToolTier.read;

  @override
  ToolKind get kind => ToolKind.read;

  @override
  ToolExecutionMode get executionMode => ToolExecutionMode.parallel;

  /// Тело навыка — инструкция, допущенная гейтами доверия (D9).
  @override
  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.trusted;

  @override
  String permissionPattern(Map<String, Object?> args, String cwd) =>
      '${args['name']}';

  SkillDefinition? _find(Object? name) {
    for (final s in catalog.modelVisible) {
      if (s.name == name) {
        return s;
      }
    }
    return null;
  }

  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final skill = _find(args['name']);
    return ToolPresentation(
      title: 'Load skill ${args['name']}',
      locations: [if (skill != null) Location(skill.path)],
    );
  }

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final requested = '${args['name']}';
    final skill = _find(requested);
    if (skill == null) {
      final shown = String.fromCharCodes(requested.runes.take(64));
      final names = [for (final s in catalog.modelVisible) s.name].join(', ');
      return errorResult('Unknown skill: $shown. Available skills: $names.');
    }
    // В лог идут имя и способ активации; тело, описание и файлы — нет (D9).
    ctx.services.logger.log(
      LogLevel.info,
      'skill.activated',
      fields: {
        'session_id': sessionId?.value,
        'name': skill.name,
        'via': 'tool',
        'repeated': false,
      },
    );
    return ToolExecutionResult([TextContent(renderSkillBlock(skill))]);
  }
}
