// Что диалог «Third-party notices» берёт из `THIRD_PARTY_NOTICES.md` (задача
// 7.7 change `add-app-general-page`; design.md D13, решение пользователя
// 2026-11-19; spec app-settings «Раздел «About» страницы «General»»).
//
// Красные тесты: `thirdPartyRecordsOf` — заглушка, реализация — задача 7.8.
//
// Показываются только записи раздела `## Записи`: заголовок первого уровня,
// вводная и раздел `## Формат записи` с шаблоном — правила для разработчиков,
// а не уведомления. Если раздела нет, юридический текст не должен пропасть:
// показывается весь файл без заголовка первого уровня.

import 'dart:io';

import 'package:codelab_desktop/features/settings/application/third_party_notices.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('настоящий реестр assets/legal/THIRD_PARTY_NOTICES.md', () {
    late String records;

    setUp(() {
      final file = File('assets/legal/THIRD_PARTY_NOTICES.md');
      expect(file.existsSync(), isTrue);
      records = thirdPartyRecordsOf(file.readAsStringSync());
    });

    test('начинается с первой записи и содержит остальные', () {
      expect(records, startsWith('### JetBrains Mono'));
      expect(records, contains('### Latin Modern'));
    });

    test('без заголовка первого уровня, вводной, формата записи и шаблона', () {
      expect(records, isNot(contains('# Third-party notices')));
      expect(records, isNot(contains('## Формат записи')));
      expect(records, isNot(contains('<Название источника>')));
      expect(records, isNot(contains('## Записи')));
    });
  });

  group('границы раздела', () {
    test('раздел обрывается на следующем заголовке второго уровня', () {
      const text =
          '# Title\n\nintro\n\n## Записи\n\n### A\nbody a\n\n### B\nbody b\n\n'
          '## Другое\ntail\n';

      final records = thirdPartyRecordsOf(text);

      expect(records, startsWith('### A'));
      expect(records, contains('### B'));
      expect(records, contains('body b'));
      expect(records, isNot(contains('Другое')));
      expect(records, isNot(contains('tail')));
      expect(records, isNot(contains('intro')));
    });

    test('заголовок третьего уровня раздел не обрывает', () {
      final records = thirdPartyRecordsOf('## Записи\n### A\nx\n### B\ny\n');

      expect(records, contains('### A'));
      expect(records, contains('### B'));
    });

    test('без раздела «Записи» — весь текст без заголовка первого уровня', () {
      final records = thirdPartyRecordsOf('# Title\n\nintro\n\n### A\nbody\n');

      expect(records, isNot(contains('# Title')));
      expect(records, contains('intro'));
      expect(records, contains('### A'));
      expect(records, contains('body'));
    });

    test('результат без пустых строк по краям', () {
      final records = thirdPartyRecordsOf('## Записи\n\n\n### A\nx\n\n\n');

      expect(records, records.trim());
      expect(records, startsWith('### A'));
    });
  });
}
