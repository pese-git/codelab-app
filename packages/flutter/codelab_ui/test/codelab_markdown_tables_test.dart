// Таблицы `CodeLabMarkdown`: перенос текста ячеек по ширине (change
// `add-app-legal-page`, ручная проверка macOS; `gpt_markdown` 1.4.1
// `TableOverflow.wrap`).
//
// Правовые документы Legal содержат таблицу из четырёх столбцов; с прокруткой
// по умолчанию два последних столбца прятались за горизонтальной
// прокруткой. Перенос включается параметром `wrapTables`; лента агента
// остаётся с прокруткой (широкая таблица ответа не должна сжиматься до
// нечитаемого).

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _table =
    '| Запрос | Куда уходит | Что уходит | Как избежать |\n'
    '|---|---|---|---|\n'
    '| Подключение к провайдеру | Адрес провайдера из настроек | '
    'Промпты, файлы проекта и результаты инструментов целиком | '
    'Не подключать провайдера или выбрать локальную модель |\n'
    '| Заметки о выпуске | Репозиторий CodeLab на GitHub | '
    'Только адрес страницы, без данных о проекте | '
    'Не нажимать «Release notes» в настройках |\n';

Widget _host({required bool wrap, double width = 600}) => FluentApp(
  home: ScaffoldPage(
    content: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: CodeLabMarkdown(
            id: 'table-doc',
            text: _table,
            wrapTables: wrap,
          ),
        ),
      ),
    ),
  ),
);

bool _hasHorizontalScrollable(WidgetTester tester) => tester
    .widgetList<Scrollable>(find.byType(Scrollable))
    .any((s) => s.axis == Axis.horizontal);

void main() {
  testWidgets('по умолчанию широкая таблица прокручивается по горизонтали', (
    tester,
  ) async {
    await tester.pumpWidget(_host(wrap: false));
    await tester.pump();

    expect(_hasHorizontalScrollable(tester), isTrue);
  });

  for (final width in [600.0, 320.0]) {
    testWidgets('wrapTables: четыре столбца в ${width.toInt()} px без '
        'горизонтальной прокрутки и переполнения', (tester) async {
      await tester.pumpWidget(_host(wrap: true, width: width));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_hasHorizontalScrollable(tester), isFalse);
      // Последний столбец виден в пределах ширины, а не за прокруткой.
      final last = find.textContaining('Как избежать', findRichText: true);
      expect(last, findsWidgets);
      expect(tester.getRect(last.first).right, lessThanOrEqualTo(width));
    });
  }

  testWidgets('смена wrapTables пересоздаёт конфигурацию', (tester) async {
    await tester.pumpWidget(_host(wrap: false));
    await tester.pump();
    expect(_hasHorizontalScrollable(tester), isTrue);

    await tester.pumpWidget(_host(wrap: true));
    await tester.pump();

    expect(_hasHorizontalScrollable(tester), isFalse);
  });
}
