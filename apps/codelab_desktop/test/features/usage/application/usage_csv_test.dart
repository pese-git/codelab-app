// Красные тесты задачи 1.4 change `add-desktop-usage-pane`: сборка CSV
// `buildUsageCsv` (agent-workbench-ui «Экспорт usage в CSV»: «Точные числа»,
// «Неизвестная цена», «Формула в подписи хода»; design.md, D5, Q2).
//
// Данные идут тем же путём, что в панели: `usagePaneDataOf` из `SessionView`
// (CSV экспортирует то, что видно, D5), поэтому тест не знает полей
// `UsagePaneData`, кроме `canExport`. Деньги пишет `formatUsageMoneyExact` kit
// (задачи 1.2–1.3, `client`): точные строки `0.000041`, `2.26`; пока функция
// не реализована, тесты с деньгами красны и по её причине тоже.
//
// Формат: RFC 4180, разделитель `,`, CRLF, без BOM; поле с `,`, `"`, CR или LF
// в кавычках, кавычка удваивается; значение с `=`, `+`, `-`, `@`, TAB, CR
// в начале получает префикс `'`. Первая строка — заголовок; строки
// хронологически: turn, его step и subagents, затем model, группы сессии и
// последней — total.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show SessionId, ToolCallId, ToolKind;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/usage/application/usage_csv.dart';
import 'package:codelab_desktop/features/usage/application/usage_pane_data.dart';
import 'package:flutter_test/flutter_test.dart';

const _header =
    'kind,turn,step,title,model,input,output,cache_read,cache_write,'
    'reasoning,cost,currency,partial';

TokenCounts _tokens(
  int input,
  int output, {
  int cacheRead = 0,
  int cacheWrite = 0,
  int? reasoning,
}) => TokenCounts(
  input: input,
  output: output,
  cacheRead: cacheRead,
  cacheWrite: cacheWrite,
  reasoning: reasoning,
);

Money _usd(int micros) => Money(micros: micros, currency: 'USD');

UsageTotals _totals(
  TokenCounts tokens, {
  Money? cost,
  int steps = 1,
  Set<UsagePartial> partial = const {},
}) => UsageTotals(tokens: tokens, cost: cost, steps: steps, partial: partial);

String _csvOf(
  UsageLedgerView ledger, {
  List<TranscriptItem> transcript = const [],
}) {
  final data = usagePaneDataOf(
    SessionView(
      revision: 1,
      status: SessionStatusView.idle,
      usage: const UsageView(support: UsageSupport.reported),
      usageLedger: UsageLedgerState.loaded(ledger),
      transcript: transcript,
    ),
    cwd: '/work',
  );
  expect(data.canExport, isTrue);
  return buildUsageCsv(data);
}

/// Строки CSV без хвостового перевода строки; пустое поле — `''`.
List<String> _lines(String csv) => csv.endsWith('\r\n')
    ? csv.substring(0, csv.length - 2).split('\r\n')
    : csv.split('\r\n');

UsageLedgerView _ledger({
  List<UsageLedgerTurn> turns = const [],
  List<UsageLedgerModel> models = const [],
  UsageLedgerGroup? subagents,
  UsageLedgerGroup? summaries,
  UsageTotals? total,
}) => UsageLedgerView(
  sessionId: const SessionId('s-1'),
  seq: 5,
  total: total ?? _totals(_tokens(10, 2)),
  turnCount: turns.length,
  turns: turns,
  models: models,
  subagents: subagents,
  summaries: summaries,
);

void main() {
  group('формат (D5, Q2)', () {
    test('первая строка — заголовок, перевод строки — CRLF, без BOM', () {
      final csv = _csvOf(_ledger());

      expect(csv.startsWith('﻿'), isFalse);
      expect(_lines(csv).first, _header);
      expect(
        RegExp(r'(?<!\r)\n').hasMatch(csv),
        isFalse,
        reason: 'только CRLF',
      );
    });

    test('последняя строка — total, строка итога сессии', () {
      final csv = _csvOf(
        _ledger(
          total: _totals(
            _tokens(
              184200,
              3000,
              cacheRead: 500,
              cacheWrite: 100,
              reasoning: 40,
            ),
            cost: _usd(2260000),
            partial: {UsagePartial.noUsage},
          ),
        ),
      );

      expect(
        _lines(csv).last,
        'total,,,,,184200,3000,500,100,40,2.26,USD,noUsage',
      );
    });
  });

  group('строки и их порядок', () {
    late String csv;
    late List<String> lines;

    setUp(() {
      csv = _csvOf(
        _ledger(
          turns: [
            UsageLedgerTurn(
              index: 1,
              title: 'Fix',
              total: _totals(
                _tokens(184200, 3000),
                cost: _usd(41),
                steps: 2,
                partial: {UsagePartial.noUsage},
              ),
              steps: [
                UsageLedgerStep(
                  index: 0,
                  model: 'openai/gpt-5',
                  tokens: _tokens(100, 20, reasoning: 5),
                  cost: _usd(10),
                  toolCallIds: const ['c1'],
                ),
                UsageLedgerStep(
                  index: 1,
                  model: 'openai/gpt-5',
                  tokens: _tokens(10, 2),
                ),
              ],
              subagents: UsageLedgerGroup(
                count: 2,
                tokens: _tokens(7, 3),
                cost: _usd(5),
              ),
            ),
            UsageLedgerTurn(
              index: 2,
              total: _totals(_tokens(1, 1)),
              steps: [UsageLedgerStep(index: 0, tokens: _tokens(1, 1))],
            ),
          ],
          models: [
            UsageLedgerModel(
              model: 'openai/gpt-5',
              steps: 3,
              tokens: _tokens(120, 25),
              cost: _usd(15),
            ),
          ],
          subagents: UsageLedgerGroup(count: 2, tokens: _tokens(7, 3)),
          summaries: UsageLedgerGroup(
            count: 1,
            tokens: _tokens(4, 1),
            cost: _usd(1),
            partial: {UsagePartial.noPrice},
          ),
          total: _totals(_tokens(300, 40), cost: _usd(60), steps: 5),
        ),
        transcript: [
          ToolCallItem(
            id: 'tool-c1',
            toolCallId: const ToolCallId('c1'),
            title: 'Read',
            details: ToolCallView(
              kind: ToolKind.read,
              status: ToolCallStatusView.succeeded,
              rawInput: const {'path': '/work/lib/a.dart'},
            ),
          ),
        ],
      );
      lines = _lines(csv);
    });

    test('хронологический порядок: turn, его steps и subagents, затем '
        'model, группы сессии, total', () {
      expect(
        [for (final l in lines.skip(1)) l.split(',').first],
        [
          'turn',
          'step',
          'step',
          'subagents',
          'turn',
          'step',
          'model',
          'subagents',
          'summaries',
          'total',
        ],
      );
    });

    test('точные числа и деньги: 184200, 0.000041, USD, noUsage', () {
      expect(lines[1], 'turn,1,,Fix,,184200,3000,0,0,,0.000041,USD,noUsage');
    });

    test('шаг: номер с 1, подпись шага по транскрипту, модель, reasoning', () {
      expect(
        lines[2],
        'step,1,1,Read lib/a.dart,openai/gpt-5,100,20,0,0,5,0.00001,USD,',
      );
    });

    test('неизвестная цена — пустые cost и currency, а не 0', () {
      expect(lines[3], 'step,1,2,reply,openai/gpt-5,10,2,0,0,,,,');
    });

    test('строка субагентов хода: пустой title и model', () {
      expect(lines[4], 'subagents,1,,,,7,3,0,0,,0.000005,USD,');
    });

    test('ход без title и без цены', () {
      expect(lines[5], 'turn,2,,,,1,1,0,0,,,,');
    });

    test('строка модели: model в колонке model, turn и step пустые', () {
      expect(lines[7], 'model,,,,openai/gpt-5,120,25,0,0,,0.000015,USD,');
    });

    test('группы сессии: subagents с пустым turn и summaries с причиной', () {
      expect(lines[8], 'subagents,,,,,7,3,0,0,,,,');
      expect(lines[9], 'summaries,,,,,4,1,0,0,,0.000001,USD,noPrice');
    });

    test('total', () {
      expect(lines.last, 'total,,,,,300,40,0,0,,0.00006,USD,');
    });
  });

  test(
    'причины partial — через «;» в порядке noUsage, noPrice, beforeLoad',
    () {
      final csv = _csvOf(
        _ledger(
          total: _totals(
            _tokens(1, 1),
            partial: {
              UsagePartial.beforeLoad,
              UsagePartial.noUsage,
              UsagePartial.noPrice,
            },
          ),
        ),
      );

      expect(_lines(csv).last, endsWith(',,,noUsage;noPrice;beforeLoad'));
    },
  );

  group('кавычки и защита от формул (D5)', () {
    String titleCell(String title) {
      final csv = _csvOf(
        _ledger(
          turns: [
            UsageLedgerTurn(
              index: 1,
              title: title,
              total: _totals(_tokens(1, 1)),
            ),
          ],
        ),
      );
      // Строка хода — вторая; ячейка title — после `turn,1,,`.
      final line = _lines(csv)[1];
      final prefix = 'turn,1,,';
      expect(line, startsWith(prefix));
      return line.substring(prefix.length, line.indexOf(',,1,1,'));
    }

    test('запятая и кавычка: поле в кавычках, кавычка удваивается', () {
      expect(titleCell('Fix, "quoted"'), '"Fix, ""quoted"""');
    });

    test('одиночный CR внутри значения: поле в кавычках', () {
      // Табличный редактор считает голый CR концом записи; без кавычек
      // подпись хода разорвала бы строку CSV (RFC 4180, D5).
      expect(titleCell('Fix\rbuild'), '"Fix\rbuild"');
    });

    test('обычный текст кавычек не получает', () {
      expect(titleCell('Fix the build'), 'Fix the build');
    });

    test('формула: префикс \' и затем обычное квотирование', () {
      expect(
        titleCell('=HYPERLINK("http://x")'),
        '"\'=HYPERLINK(""http://x"")"',
      );
    });

    test('префикс получают +, -, @', () {
      expect(titleCell('+1'), "'+1");
      expect(titleCell('-rf'), "'-rf");
      expect(titleCell('@cmd'), "'@cmd");
    });

    test('модель агента с формулой тоже защищена', () {
      final csv = _csvOf(
        _ledger(
          models: [
            UsageLedgerModel(model: '=bad', steps: 1, tokens: _tokens(1, 1)),
          ],
        ),
      );

      expect(_lines(csv)[1], startsWith("model,,,,'=bad,"));
    });

    test('числа префикса не получают', () {
      final csv = _csvOf(_ledger(total: _totals(_tokens(5, 3))));

      expect(_lines(csv).last, 'total,,,,,5,3,0,0,,,,');
    });
  });

  group('«немая» строка без usage (D5, DSK-11)', () {
    test('шаг без usage при цене 0: токены, cost и currency пустые, '
        'как «—» в панели', () {
      final csv = _csvOf(
        _ledger(
          turns: [
            UsageLedgerTurn(
              index: 1,
              total: _totals(
                _tokens(0, 0),
                cost: _usd(0),
                partial: {UsagePartial.noUsage},
              ),
              steps: [
                UsageLedgerStep(
                  index: 0,
                  tokens: _tokens(0, 0),
                  cost: _usd(0),
                  partial: const {UsagePartial.noUsage},
                ),
              ],
            ),
          ],
        ),
      );

      expect(_lines(csv)[1], 'turn,1,,,,,,,,,,,noUsage');
      expect(_lines(csv)[2], 'step,1,1,reply,,,,,,,,,noUsage');
    });

    test('ход с ценами и usage остаётся с деньгами', () {
      final csv = _csvOf(
        _ledger(
          turns: [
            UsageLedgerTurn(
              index: 1,
              total: _totals(_tokens(10, 2), cost: _usd(41)),
              steps: const [],
            ),
          ],
        ),
      );

      expect(_lines(csv)[1], 'turn,1,,,,10,2,0,0,,0.000041,USD,');
    });
  });
}
