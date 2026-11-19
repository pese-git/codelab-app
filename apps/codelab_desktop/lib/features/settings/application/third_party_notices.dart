/// Записи реестра сторонних уведомлений для диалога «Third-party notices»
/// (design.md change `add-app-general-page`, D13).
///
/// Почему: `THIRD_PARTY_NOTICES.md` начинается заголовком, вводной и разделом
/// `## Формат записи` с шаблоном — это правила для разработчиков, а не
/// уведомления; пользователю диалог показывает только записи.
library;

/// Записи раздела `## Записи` из текста `THIRD_PARTY_NOTICES.md`: от строки
/// после заголовка до следующего заголовка второго уровня или до конца.
///
/// Для чего: чистая функция для диалога. Заголовок `## Записи` ищется по
/// целой строке; заголовки третьего уровня (`### …`) раздел не обрывают.
/// Если раздела нет, юридический текст не должен пропасть молча: возвращается
/// весь текст без заголовка первого уровня. Пустые строки по краям убираются.
///
/// Как использовать: `thirdPartyRecordsOf(notices)` — текст ресурса
/// `assets/legal/THIRD_PARTY_NOTICES.md`; ровно один `## Записи` в нём
/// проверяет тест ресурсов.
String thirdPartyRecordsOf(String notices) {
  final lines = notices.split('\n');
  final start = lines.indexWhere((l) => l.trimRight() == '## Записи');
  final Iterable<String> kept;
  if (start < 0) {
    kept = lines.where((l) => !l.startsWith('# '));
  } else {
    final tail = lines.skip(start + 1).toList();
    final end = tail.indexWhere((l) => l.startsWith('## '));
    kept = end < 0 ? tail : tail.take(end);
  }
  return kept.join('\n').trim();
}
