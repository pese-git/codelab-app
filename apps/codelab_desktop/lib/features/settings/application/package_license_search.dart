/// Лицензии одного пакета: имя и тексты (design.md change
/// `add-app-legal-page`, D5).
///
/// Почему: вкладка «Third-party notices» показывает пакеты, а `LicenseEntry`
/// Flutter относит одну запись сразу к нескольким именам. Пакет здесь —
/// уникальное имя из `LicenseEntry.packages`.
///
/// Для чего: данные без виджетов; собирает их `collectPackageLicenses` в
/// composition root (D10), поиск — [searchPackageLicenses].
///
/// Как использовать: список упорядочен по [name] и собирается один раз;
/// [licenses] — тексты в порядке записей реестра.
final class PackageLicense {
  const PackageLicense({required this.name, required this.licenses});

  final String name;
  final List<String> licenses;
}

/// Пакет в выдаче поиска и диапазоны совпадений в его имени.
///
/// [ranges] — полуинтервалы `(start, end)` в индексах [PackageLicense.name];
/// пусты при пустом запросе и в защитной ветке Unicode-свёртки (D5).
final class PackageHit {
  const PackageHit({required this.package, required this.ranges});

  final PackageLicense package;
  final List<(int start, int end)> ranges;
}

/// Результат [searchPackageLicenses].
///
/// [total] — число всех пакетов, не зависит от запроса; [needle] — запрос
/// после `trim().toLowerCase()` (пуст, если фильтра нет); [hits] — выдача в
/// порядке исходного списка.
final class PackageSearch {
  const PackageSearch({
    required this.total,
    required this.needle,
    required this.hits,
  });

  /// Пустая выдача до сбора реестра.
  static const empty = PackageSearch(total: 0, needle: '', hits: []);

  final int total;
  final String needle;
  final List<PackageHit> hits;
}

/// Ищет пакеты, в имени которых есть [query], без учёта регистра (D5).
///
/// Почему чистая функция: пересчёт на сотне-другой имён дешевле дебаунса с
/// таймером, а проверяется она без виджетов. Запрос — недоверенный ввод:
/// функция не бросает и ничего не логирует (D11).
///
/// Как использовать: `searchPackageLicenses(all, query)` при каждом
/// изменении запроса. Пустой (после `trim`) запрос возвращает все пакеты без
/// диапазонов. Диапазоны — все вхождения слева направо без перекрытия
/// (`aaa` по `aa` — одно). Имя, у которого нижний регистр меняет длину или
/// есть не-ASCII символ (редкая Unicode-свёртка; имена pub — `[a-z0-9_]`),
/// попадает в выдачу без подсветки: индексы не обязаны совпасть с исходной
/// строкой, а неверная подсветка хуже её отсутствия. Проверка длины одна не
/// годится: в Dart `'İ'.toLowerCase()` длину не меняет, а свёртка зависит от
/// платформы.
PackageSearch searchPackageLicenses(List<PackageLicense> all, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) {
    return PackageSearch(
      total: all.length,
      needle: '',
      hits: [for (final p in all) PackageHit(package: p, ranges: const [])],
    );
  }
  final hits = <PackageHit>[];
  for (final package in all) {
    final lower = package.name.toLowerCase();
    if (!lower.contains(needle)) {
      continue;
    }
    if (lower.length != package.name.length || _hasNonAscii(package.name)) {
      hits.add(PackageHit(package: package, ranges: const []));
      continue;
    }
    final ranges = <(int, int)>[];
    var from = 0;
    while (true) {
      final at = lower.indexOf(needle, from);
      if (at < 0) {
        break;
      }
      ranges.add((at, at + needle.length));
      from = at + needle.length;
    }
    hits.add(PackageHit(package: package, ranges: ranges));
  }
  return PackageSearch(total: all.length, needle: needle, hits: hits);
}

bool _hasNonAscii(String name) => name.codeUnits.any((unit) => unit > 0x7f);
