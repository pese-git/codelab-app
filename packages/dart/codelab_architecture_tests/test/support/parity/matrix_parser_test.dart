// Модульный тест разбора матрицы целей на временной матрице (задача 1.1
// change `switch-default-agent-to-dart`; testing-quality «Проверка доказательств
// матрицы целей»; design.md, D2). Настоящая матрица не нужна: каждый тест
// собирает свой небольшой документ.

import 'package:test/test.dart';

import 'matrix_parser.dart';

const _h3 =
    '| ID | Возможность | Целевое поведение | Приоритет | Этап | '
    'Как видно клиенту | Критерий приёмки | Py / app |';
const _h41 =
    '| ID | Возможность | Целевое поведение | Этап | Как видно клиенту | '
    'Критерий приёмки | Py / app |';
const _sub = '| ID | Дано | Когда | Тогда |';

String _row3(String id, String priority, String criterion) =>
    '| $id | cap | goal | $priority | 1 | — | $criterion | есть |';

String _row41(String id, String criterion) =>
    '| $id | cap | goal | 4 | — | $criterion | есть |';

/// Собирает документ: §3 (по умолчанию две строки), §4.1, §4.2, §7.
List<String> _doc({
  List<String>? rows3,
  List<String>? rows41,
  List<String>? rows42,
  String summary = '| **Итого** | **3** | **1** | Could — 0 |',
}) => [
  '# Матрица',
  '',
  '## 3. Матрица целей',
  '',
  '### 3.1. Первая группа',
  '',
  _h3,
  '|---|---|---|---|---|---|---|---|',
  ...(rows3 ??
      [
        _row3('L-01', 'Must', '`acp/a`'),
        _row3('L-02', 'Should', '`acp/b`'),
        _row3('L-03', 'Must', '`cli/c`'),
      ]),
  '',
  'Сценарии приёмки Must:',
  '',
  _sub,
  '|---|---|---|---|',
  '| L-01 | дано | когда | тогда |',
  '| L-03 | дано | когда | тогда |',
  '',
  '## 4. Не регрессировать',
  '',
  '### 4.1. Сохранить',
  '',
  _h41,
  '|---|---|---|---|---|---|---|',
  ...(rows41 ?? [_row41('D-01', '`core/d`')]),
  '',
  '### 4.2. Исправить',
  '',
  '| ID | Дефект | Правильное поведение | Где закрывается | Критерий приёмки |',
  '|---|---|---|---|---|',
  ...(rows42 ?? ['| X-01 | дефект | поведение | L-01 | `acp/never-counted` |']),
  '',
  '## 7. Сводка по этапам',
  '',
  '| Этап | Must | Should | Must-строки |',
  '|---|---|---|---|',
  summary,
];

String _join(List<String> lines) => '${lines.join('\n')}\n';

void main() {
  group('выбор строк Must', () {
    test('берёт Must из таблиц §3 и все строки §4.1', () {
      final parsed = parseMatrix(_join(_doc()));

      expect(parsed.mustRows.map((r) => r.id), ['L-01', 'L-03', 'D-01']);
      expect(parsed.mustRows.map((r) => r.criterion), [
        '`acp/a`',
        '`cli/c`',
        '`core/d`',
      ]);
    });

    test('пропускает подтаблицы «Дано / Когда / Тогда» и §4.2', () {
      final parsed = parseMatrix(_join(_doc()));

      final ids = parsed.mustRows.map((r) => r.id);
      // L-01 и L-03 есть в подтаблице, но учтены по одному разу;
      // X-01 из §4.2 не учитывается совсем.
      expect(ids.where((id) => id == 'L-01'), hasLength(1));
      expect(ids.where((id) => id == 'L-03'), hasLength(1));
      expect(ids, isNot(contains('X-01')));
    });

    test('запоминает номер строки файла', () {
      final lines = _doc();
      final parsed = parseMatrix(_join(lines));

      final l03 = lines.indexWhere((l) => l.startsWith('| L-03 | cap')) + 1;
      expect(parsed.mustRows.firstWhere((r) => r.id == 'L-03').line, l03);
    });

    test('читает итог Must из сводки §7', () {
      expect(parseMatrix(_join(_doc())).summaryMust, 3);
    });
  });

  group('ячейки', () {
    test(r'«\|» в ячейке не делит её и снимается при чтении', () {
      final parsed = parseMatrix(
        _join(
          _doc(
            rows3: [
              _row3('L-01', 'Must', r'`secret set\|delete`'),
              _row3('L-02', 'Must', '`acp/b`'),
            ],
            summary: '| **Итого** | **3** | **0** | — |',
          ),
        ),
      );

      expect(parsed.mustRows.first.criterion, '`secret set|delete`');
    });
  });

  group('ошибки разбора', () {
    test('Сломанная строка таблицы: лишняя ячейка из-за «|» в кавычках — '
        'ошибка с номером строки', () {
      final broken = _row3('L-02', 'Must', '`secret set|delete`');
      final lines = _doc(rows3: [_row3('L-01', 'Must', '`acp/a`'), broken]);
      final lineNo = lines.indexOf(broken) + 1;

      expect(
        () => parseMatrix(_join(lines)),
        throwsA(
          isA<MatrixParseException>()
              .having((e) => e.line, 'line', lineNo)
              .having((e) => e.toString(), 'text', contains('$lineNo')),
        ),
      );
    });

    test('сломанная строка Should тоже ошибка: по ней нельзя понять, '
        'Must ли она', () {
      final broken = _row3('L-02', 'Should', '`secret set|delete`');
      final lines = _doc(rows3: [_row3('L-01', 'Must', '`acp/a`'), broken]);

      expect(
        () => parseMatrix(_join(lines)),
        throwsA(
          isA<MatrixParseException>().having(
            (e) => e.line,
            'line',
            lines.indexOf(broken) + 1,
          ),
        ),
      );
    });

    test('строка с недостающими ячейками тоже ошибка', () {
      const short = '| L-02 | cap | goal | Must |';
      final lines = _doc(rows3: [_row3('L-01', 'Must', '`acp/a`'), short]);

      expect(
        () => parseMatrix(_join(lines)),
        throwsA(isA<MatrixParseException>()),
      );
    });

    test('Число строк Must не совпадает со сводкой: 3 против 4', () {
      final lines = _doc(summary: '| **Итого** | **4** | **1** | — |');

      expect(
        () => parseMatrix(_join(lines)),
        throwsA(
          isA<MatrixParseException>().having(
            (e) => e.message,
            'message',
            allOf(contains('3'), contains('4')),
          ),
        ),
      );
    });

    test('нет сводки §7 — ошибка, а не молчаливое совпадение', () {
      final lines = _doc()..removeLast();

      expect(
        () => parseMatrix(_join(lines)),
        throwsA(isA<MatrixParseException>()),
      );
    });
  });
}
