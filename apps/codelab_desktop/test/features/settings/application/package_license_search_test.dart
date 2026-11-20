// Поиск по пакетам вкладки «Third-party notices» (задача 2.1 change
// `add-app-legal-page`; spec app-settings «Страница «Legal»: поиск по
// пакетам», сценарии «Совпадение без учёта регистра», «Все вхождения
// подсвечены», «Пустой запрос», «Ничего не найдено»; design.md D5).
//
// Реализация — задача 2.2: `features/settings/application/
// package_license_search.dart` (`PackageLicense`, `PackageSearch`,
// `PackageHit`, `searchPackageLicenses`). Функция чистая: виджетов не знает и
// не бросает; запрос — недоверенный ввод.

import 'package:codelab_desktop/features/settings/application/package_license_search.dart';
import 'package:flutter_test/flutter_test.dart';

PackageLicense _pkg(String name) =>
    PackageLicense(name: name, licenses: ['text of $name']);

void main() {
  final all = [
    _pkg('flutter'),
    _pkg('flutter_bloc'),
    _pkg('fpdart'),
    _pkg('http'),
  ];

  List<String> names(PackageSearch s) => [
    for (final hit in s.hits) hit.package.name,
  ];

  group('пустой запрос', () {
    test('возвращает все пакеты без диапазонов', () {
      final result = searchPackageLicenses(all, '');

      expect(names(result), ['flutter', 'flutter_bloc', 'fpdart', 'http']);
      expect(result.hits.every((h) => h.ranges.isEmpty), isTrue);
      expect(result.total, 4);
      expect(result.needle, isEmpty);
    });

    test('запрос из одних пробелов равен пустому', () {
      final result = searchPackageLicenses(all, '   ');

      expect(result.hits, hasLength(4));
      expect(result.needle, isEmpty);
    });
  });

  group('совпадение', () {
    test('без учёта регистра', () {
      final result = searchPackageLicenses(all, 'FLUT');

      expect(names(result), ['flutter', 'flutter_bloc']);
      expect(result.needle, 'flut');
    });

    test('пробелы по краям запроса отбрасываются', () {
      final result = searchPackageLicenses(all, '  bloc ');

      expect(names(result), ['flutter_bloc']);
      expect(result.hits.single.ranges, [(8, 12)]);
    });

    test('диапазон — границы вхождения в имени пакета', () {
      final result = searchPackageLicenses(all, 'flut');

      expect(result.hits.first.ranges, [(0, 4)]);
    });

    test('все вхождения слева направо', () {
      final result = searchPackageLicenses([_pkg('a_http_http')], 'http');

      expect(result.hits.single.ranges, [(2, 6), (7, 11)]);
    });

    test('вхождения не перекрываются: aaa по запросу aa — одно', () {
      final result = searchPackageLicenses([_pkg('aaa')], 'aa');

      expect(result.hits.single.ranges, [(0, 2)]);
    });

    test('порядок пакетов сохраняется', () {
      final shuffled = [_pkg('zeta_f'), _pkg('alpha_f'), _pkg('mid_f')];

      final result = searchPackageLicenses(shuffled, 'f');

      expect(names(result), ['zeta_f', 'alpha_f', 'mid_f']);
    });

    test('в выдаче остаётся исходный пакет с текстами лицензий', () {
      final result = searchPackageLicenses(all, 'http');

      expect(result.hits.single.package, same(all.last));
    });
  });

  group('ничего не найдено', () {
    test('выдача пуста, total остаётся числом всех пакетов', () {
      final result = searchPackageLicenses(all, 'reqwest');

      expect(result.hits, isEmpty);
      expect(result.total, 4);
    });
  });

  group('total', () {
    test('не зависит от запроса', () {
      for (final query in ['', 'flut', 'zzz', ' http ']) {
        expect(searchPackageLicenses(all, query).total, 4, reason: query);
      }
    });

    test('пустой список пакетов — total 0 и пустая выдача', () {
      final result = searchPackageLicenses(const [], 'a');

      expect(result.total, 0);
      expect(result.hits, isEmpty);
    });
  });

  group('Unicode-свёртка', () {
    test('имя, у которого нижний регистр меняет длину, попадает в выдачу '
        'без диапазонов', () {
      // «İ» (U+0130) в нижнем регистре становится двумя кодовыми единицами:
      // индексы совпадения не совпали бы с индексами исходной строки, а
      // неверная подсветка хуже её отсутствия (D5).
      final result = searchPackageLicenses([_pkg('İstanbul')], 'stan');

      expect(names(result), ['İstanbul']);
      expect(result.hits.single.ranges, isEmpty);
    });
  });
}
