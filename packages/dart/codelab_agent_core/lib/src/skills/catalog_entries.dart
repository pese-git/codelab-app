/// Строки каталога навыков для системного промпта (design.md change
/// `add-agent-skills`, D6, D17; `agent-core-architecture` §17.2.5; решение
/// Q18).
///
/// Почему отдельная чистая функция: те же числа (`shortened`, `omitted`) нужны
/// рантайму для лога `skills.catalog.truncated`, а текст — `composeSystemPrompt`;
/// если бы они считались в двух местах, лог мог бы разойтись с промптом.
///
/// Как использовать: `skillsCatalogEntries(modelVisible, maxChars)`. Результат
/// зависит только от имён, описаний и бюджета: без путей, дат и счётчиков,
/// побайтово одинаков для одного снимка (SKL-4, PR-3). Длины — в рунах.
library;

import 'skill_catalog.dart';

/// Предел описания в каталоге, руны (D4).
const _descriptionLimit = 1024;

/// Строки `- <name>: <description>` в границах [maxChars].
///
/// [shortened] — число описаний, укороченных из-за бюджета (предел 1024 сюда
/// не входит: предупреждение о нём выдаётся при загрузке); [omitted] — число
/// навыков, не попавших в список даже одними именами.
({String entries, int shortened, int omitted}) skillsCatalogEntries(
  List<SkillDefinition> skills,
  int maxChars,
) {
  final sorted = [...skills]..sort((a, b) => a.name.compareTo(b.name));
  final names = [for (final s in sorted) s.name];
  final descriptions = [for (final s in sorted) _capped(s.description)];

  int cost(String line) => line.runes.length + 1;

  // Строки при общей доле [share] рун описания (D17, шаг 3).
  List<String> lines(int count, int share) => [
    for (var i = 0; i < count; i++) _line(names[i], descriptions[i], share),
  ];
  int total(List<String> ls) => ls.fold(0, (sum, l) => sum + cost(l));

  // Наибольшая доля, при которой строки помещаются в [budget]; `null` —
  // не помещаются даже одни имена.
  int? fitShare(int count, int budget) {
    if (total(lines(count, 0)) > budget) {
      return null;
    }
    // Стоимость монотонна по доле, поэтому ищем двоичным поиском.
    var low = 0, high = _descriptionLimit + 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (total(lines(count, mid)) <= budget) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  int shortenedBy(int count, int share) => [
    for (var i = 0; i < count; i++)
      if (descriptions[i].runes.length > share) i,
  ].length;

  final n = names.length;
  if (total(lines(n, _descriptionLimit + 1)) <= maxChars) {
    return (
      entries: lines(n, _descriptionLimit + 1).join('\n'),
      shortened: 0,
      omitted: 0,
    );
  }
  if (fitShare(n, maxChars) case final share?) {
    return (
      entries: lines(n, share).join('\n'),
      shortened: shortenedBy(n, share),
      omitted: 0,
    );
  }
  // Шаг 4: удаляем строки с конца. Строка об опущенных входит в бюджет.
  for (var k = n - 1; k >= 0; k--) {
    final marker = '[${n - k} more skills not listed]';
    final budget = maxChars - cost(marker);
    final share = fitShare(k, budget);
    if (share != null) {
      return (
        entries: [...lines(k, share), marker].join('\n'),
        shortened: shortenedBy(k, share),
        omitted: n - k,
      );
    }
  }
  // Не помещается и одна строка об опущенных: бюджет заведомо меньше нее.
  return (entries: '[$n more skills not listed]', shortened: 0, omitted: n);
}

String _capped(String description) {
  final runes = description.runes.toList();
  return runes.length > _descriptionLimit
      ? '${String.fromCharCodes(runes.take(_descriptionLimit))}…'
      : description;
}

/// Строка списка при доле [share]: короткое описание целиком, длинное — первые
/// `share - 1` рун и `…`, при нуле — одно имя.
String _line(String name, String description, int share) {
  final runes = description.runes.toList();
  if (runes.length <= share) {
    return '- $name: $description';
  }
  if (share == 0) {
    return '- $name';
  }
  return '- $name: ${String.fromCharCodes(runes.take(share - 1))}…';
}
