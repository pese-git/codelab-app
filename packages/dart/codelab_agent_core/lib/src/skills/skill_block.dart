/// Блок навыка: единый вид тела навыка для модели (design.md change
/// `add-agent-skills`, D7, D9, D17; `agent-core-architecture` §17.2.3;
/// решения Q4, Q5, Q19, Q26, Q30).
///
/// Почему отдельный файл: один и тот же блок отдают результат инструмента
/// `skill`, сообщение `/skill:` и повторное приложение после сжатия; текст и
/// экранирование не должны расходиться между ними.
///
/// Как использовать: `renderSkillBlock(skill)`; `body` заменяет тело снимка,
/// когда команда подставила аргументы. `escapeSkillTags` общая для тела,
/// строк файлов и вывода `read` внутри каталога навыка (Q30).
library;

import 'skill_catalog.dart';

/// Открывающий или закрывающий тег `skill` без учёта регистра, с пробельными
/// символами внутри (включая перевод строки). Как и у `project-instructions`,
/// совпадение — по префиксу: лишнее экранирование безопаснее пропуска.
final _skillTag = RegExp(r'<\s*/?\s*skill', caseSensitive: false);

/// Строка о путях, одна для любого режима исполнения (решение Q26): верна и
/// без списка файлов, поэтому на него не ссылается.
const _pathsLine =
    "This skill's own files (scripts, references, assets and files named in "
    'its instructions) are relative to its directory; task data is relative '
    'to the project. In tool calls, refer to the skill\'s files by absolute '
    'path, and run its scripts with the project as the working directory.';

/// Ставит `\` после `<` у каждого тега `skill`: `</skill>` превращается в
/// `<\/skill>` и не закрывает блок (D7, приоритет 1).
String escapeSkillTags(String text) =>
    text.replaceAllMapped(_skillTag, (m) => '<\\${m[0]!.substring(1)}');

/// Значение атрибута: символы разметки и переводы строк заменяются на `_`.
String _attribute(String value) => value.replaceAll(RegExp(r'["<>\r\n]'), '_');

/// Блок навыка без завершающего перевода строки.
///
/// [body] — тело после подстановки аргументов; `null` — тело снимка
/// ([SkillDefinition.body], уже в обрезанной форме D4).
String renderSkillBlock(SkillDefinition skill, {String? body}) {
  final compatibility = skill.compatibility;
  final out = <String>[
    '<skill name="${_attribute(skill.name)}" dir="${_attribute(skill.dir)}"'
        '${compatibility == null ? '' : ' compatibility="${_attribute(compatibility)}"'}>',
    escapeSkillTags(body ?? skill.body),
    '</skill>',
    _pathsLine,
    // Имя файла приходит из файловой системы: перевод строки в нём не должен
    // начать новую строку списка, а тег — выйти из блока.
    for (final file in skill.companions)
      '- ${escapeSkillTags('${skill.dir}/$file').replaceAll(RegExp(r'[\r\n]'), '_')}',
    if (skill.companionsTruncated) '[more files not listed]',
  ];
  return out.join('\n');
}
