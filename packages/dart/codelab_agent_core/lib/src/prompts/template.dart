/// Шаблон текста промпта (`agent-core-architecture` §11.4).
///
/// Почему без условий и циклов: шаблонизатор с логикой превращает промпт в
/// программу, которую трудно ревьюить. Необязательные части — это отдельные
/// секции, их состав выбирает `composeSystemPrompt` и показывает `CorePlan`.
///
/// Для чего: константы `Prompts` из сгенерированного `prompts.g.dart`;
/// текст пишется в `prompts/**/*.md`, а не литералом в коде (PR-2).
///
/// Как использовать: `Prompts.toolsRead.render({'maxLines': '2000',
/// 'maxKb': '50'})`. Набор значений должен совпадать с [vars] — иначе
/// [ArgumentError] (PR-4). `{{имя}}` заменяется значением как есть, без
/// повторной подстановки; `\{{` даёт литерал `{{`.
final class PromptTemplate {
  const PromptTemplate({
    required this.id,
    required this.vars,
    required this.text,
    this.tools = const {},
  });

  /// Путь файла через точки: `system/base.md` → `system.base`.
  final String id;

  /// Подстановки, объявленные во frontmatter.
  final Set<String> vars;
  final String text;

  /// Инструменты, которые описывает секция; секция входит в промпт, только
  /// если включены все они (PR-6). Пусто — секция не об инструментах.
  final Set<String> tools;

  String render(Map<String, String> values) {
    final given = values.keys.toSet();
    if (given.length != vars.length || !given.containsAll(vars)) {
      throw ArgumentError(
        '$id: expected {${(vars.toList()..sort()).join(', ')}}, '
        'got {${(given.toList()..sort()).join(', ')}}',
      );
    }
    final out = StringBuffer();
    var i = 0;
    while (i < text.length) {
      if (text.startsWith(r'\{{', i)) {
        out.write('{{');
        i += 3;
      } else if (text.startsWith('{{', i)) {
        final end = text.indexOf('}}', i + 2);
        out.write(values[text.substring(i + 2, end)]);
        i = end + 2;
      } else {
        out.write(text[i]);
        i++;
      }
    }
    return '$out';
  }
}
