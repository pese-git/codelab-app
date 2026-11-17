// Красные тесты задачи 3.2 change `add-usage-extension`: маппер app строит
// данные строки статуса из `SessionView.usage` и опций сессии (design.md D11,
// D23 Т1, D24; agent-workbench-ui «Строка статуса сессии под композером»:
// «Агент без расширения», «Два хода», «Контекст близко к пределу», «Скоро
// сжатие», «Процент вниз», «Меньше одного процента», «Формат денег», «Цена
// хода неизвестна, сессии известна», «Неполная сумма после загрузки», «Цена
// неизвестна»).
//
// Отсутствующий пока API (файл не компилируется до задачи 3.10):
// `sessionStatusDataOf(SessionView)` в `ui_mappers.dart` →
// `CodeLabSessionStatusData`/`CodeLabStatusSegment` из `codelab_ui` (см. тест
// 3.1). Имя функции рабочее — при расхождении переименовать здесь.
//
// Формат денег и токенов даёт функция kit (D24, задача 3.0a): здесь
// проверяются её применения в строке, а токены в проверках подписи взяты
// меньше 1000 — там формат совпадает с «как есть». Маппер ничего не
// суммирует и не оценивает сам: числа берутся из `UsageView` как есть.
//
// Подписи по спецификации: токены `<вход> → <выход>` (вход = `input +
// cacheRead + cacheWrite`), контекст `<N>% context[ · compaction soon]`,
// подсказка токенов — пять счётчиков словами `input`, `output`, `cache read`,
// `cache write`, `reasoning`.

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/ui_mappers.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const _model = ConfigOptionView(
  id: 'model',
  name: 'Model',
  currentValue: 'gpt-5',
  category: 'model',
  values: [
    ConfigOptionValueView(value: 'gpt-4', name: 'GPT-4'),
    ConfigOptionValueView(value: 'gpt-5', name: 'GPT-5'),
  ],
);
const _mode = ConfigOptionView(
  id: 'mode',
  name: 'Mode',
  currentValue: 'standard',
  category: 'mode',
  values: [ConfigOptionValueView(value: 'standard', name: 'Standard')],
);

const _noCache = TokenCounts(
  input: 120,
  output: 30,
  cacheRead: 0,
  cacheWrite: 0,
);

Money _usd(int micros) => Money(micros: micros, currency: 'USD');

SessionView _view({
  UsageView usage = const UsageView(),
  SessionStatusView status = SessionStatusView.idle,
  List<ConfigOptionView> options = const [_model, _mode],
}) => SessionView(
  revision: 1,
  status: status,
  configOptions: options,
  usage: usage,
);

UsageView _reported({
  UsageTotals? lastTurn,
  UsageTotals? session,
  ContextFillView? context,
}) => UsageView(
  support: UsageSupport.reported,
  lastTurn: lastTurn,
  session: session,
  context: context,
  lastSeq: 1,
);

CodeLabSessionStatusData _of(UsageView usage) =>
    sessionStatusDataOf(_view(usage: usage));

CodeLabSessionStatusData _context(ContextFillView context) => _of(
  _reported(
    lastTurn: const UsageTotals(tokens: _noCache),
    session: const UsageTotals(tokens: _noCache),
    context: context,
  ),
);

void main() {
  group('model and mode', () {
    test('the model is the selected value of the option of category model', () {
      final data = _view();
      expect(sessionStatusDataOf(data).modelLabel, 'GPT-5');
      expect(sessionStatusDataOf(data).modeLabel, 'Standard');
    });

    test('without options there are no labels; unknown value is shown raw', () {
      final empty = sessionStatusDataOf(_view(options: const []));
      expect(empty.modelLabel, isNull);
      expect(empty.modeLabel, isNull);

      final raw = sessionStatusDataOf(
        _view(
          options: const [
            ConfigOptionView(
              id: 'model',
              name: 'Model',
              currentValue: 'custom-x',
              category: 'model',
              values: [],
            ),
          ],
        ),
      );
      expect(raw.modelLabel, 'custom-x');
    });
  });

  group('support', () {
    test('unknown: «usage: —» with a hint, no cost, no context, no busy', () {
      final data = _of(const UsageView());

      expect(data.usage?.label, 'usage: —');
      expect(data.usage?.tooltip, 'agent does not report usage');
      expect(data.cost, isNull);
      expect(data.context, isNull);
      expect(data.busy, isFalse);
    });

    test('awaiting: no usage segments; busy only while the turn runs', () {
      const awaiting = UsageView(support: UsageSupport.awaiting);

      final idle = sessionStatusDataOf(_view(usage: awaiting));
      expect(idle.usage, isNull);
      expect(idle.cost, isNull);
      expect(idle.context, isNull);
      expect(idle.busy, isFalse);

      final running = sessionStatusDataOf(
        _view(usage: awaiting, status: SessionStatusView.running),
      );
      expect(running.usage, isNull);
      expect(running.busy, isTrue);
    });

    test('awaiting: busy also while the turn is being cancelled', () {
      final cancelling = sessionStatusDataOf(
        _view(
          usage: const UsageView(support: UsageSupport.awaiting),
          status: SessionStatusView.cancelling,
        ),
      );
      expect(cancelling.busy, isTrue);
    });

    test('reported: never busy, whatever the session status', () {
      for (final status in [
        SessionStatusView.running,
        SessionStatusView.cancelling,
      ]) {
        final data = sessionStatusDataOf(
          _view(
            usage: _reported(lastTurn: const UsageTotals(tokens: _noCache)),
            status: status,
          ),
        );
        expect(data.busy, isFalse, reason: status.name);
      }
    });
  });

  group('two turns', () {
    test('the turn field is the last turn, the session field is the sum', () {
      final data = _of(
        _reported(
          lastTurn: UsageTotals(
            tokens: const TokenCounts(
              input: 120,
              output: 30,
              cacheRead: 40,
              cacheWrite: 5,
              reasoning: 7,
            ),
            cost: _usd(4100),
          ),
          session: UsageTotals(
            tokens: const TokenCounts(
              input: 900,
              output: 90,
              cacheRead: 0,
              cacheWrite: 0,
            ),
            cost: _usd(1200000),
          ),
        ),
      );

      // Вход = input + cacheRead + cacheWrite = 120 + 40 + 5.
      expect(data.usage?.label, '165 → 30');
      expect(data.cost?.label, r'$0.0041 · session $1.20');
    });

    test('the tooltip lists all five counters; reasoning only when known', () {
      final full = _of(
        _reported(
          lastTurn: const UsageTotals(
            tokens: TokenCounts(
              input: 120,
              output: 31,
              cacheRead: 40,
              cacheWrite: 5,
              reasoning: 7,
            ),
          ),
          session: const UsageTotals(tokens: _noCache),
        ),
      ).usage!.tooltip!;

      expect(full, contains('input 120'));
      expect(full, contains('output 31'));
      expect(full, contains('cache read 40'));
      expect(full, contains('cache write 5'));
      expect(full, contains('reasoning 7'));

      final noReasoning = _of(
        _reported(
          lastTurn: const UsageTotals(tokens: _noCache),
          session: const UsageTotals(tokens: _noCache),
        ),
      ).usage!.tooltip!;
      expect(noReasoning, isNot(contains('reasoning')));
    });
  });

  group('zero turn tokens', () {
    test('↑0 ↓0 hides the token segment, the cost stays', () {
      final data = _of(
        _reported(
          lastTurn: UsageTotals(
            tokens: const TokenCounts(
              input: 0,
              output: 0,
              cacheRead: 0,
              cacheWrite: 0,
            ),
            cost: _usd(4100),
          ),
          session: UsageTotals(tokens: _noCache, cost: _usd(1200000)),
        ),
      );
      expect(data.usage, isNull);
      expect(data.cost?.label, r'$0.0041 · session $1.20');
    });

    test('a single non-zero counter keeps the segment', () {
      final data = _of(
        _reported(
          lastTurn: const UsageTotals(
            tokens: TokenCounts(
              input: 0,
              output: 5,
              cacheRead: 0,
              cacheWrite: 0,
            ),
          ),
        ),
      );
      expect(data.usage?.label, '0 → 5');
    });
  });

  group('huge counters', () {
    test('the input sum saturates: no negative number, segment stays', () {
      const huge = 9223372036854775807; // int64 max на VM
      final data = _of(
        _reported(
          lastTurn: const UsageTotals(
            tokens: TokenCounts(
              input: huge,
              output: 5,
              cacheRead: 1,
              cacheWrite: 0,
            ),
          ),
        ),
      );
      // Ручная сумма дала бы int64 min (отрицательное); kit насыщает на
      // 2^53 − 1.
      expect(data.usage?.label, '9007199254.7M → 5');
    });
  });

  group('partial reasons in the hint', () {
    test('«Подсказка причин неполноты»: two lines, exact text', () {
      final data = _of(
        _reported(
          lastTurn: const UsageTotals(
            tokens: TokenCounts(
              input: 1200,
              output: 300,
              cacheRead: 0,
              cacheWrite: 0,
            ),
            partial: {UsagePartial.noUsage, UsagePartial.beforeLoad},
          ),
        ),
      );
      expect(data.usage?.label, '~1.2k → 300');
      expect(
        data.usage?.tooltip,
        'input 1200 · output 300 · cache read 0 · cache write 0\n'
        'approximate: agent sent no usage for some steps, '
        'before the session was loaded',
      );
    });

    test('«Причина noPrice в подсказке токенов»: no «~», reason in hint', () {
      final data = _of(
        _reported(
          lastTurn: const UsageTotals(
            tokens: _noCache,
            partial: {UsagePartial.noPrice},
          ),
        ),
      );
      expect(data.usage?.label, '120 → 30');
      expect(
        data.usage?.tooltip,
        contains('approximate: price unknown for some steps'),
      );
    });
  });

  group('session total without a turn snapshot', () {
    test('«Итог сессии без снимка хода»: no tokens, «— · session ~\$1.20»', () {
      final data = _of(
        _reported(
          session: UsageTotals(
            tokens: _noCache,
            cost: _usd(1200000),
            partial: const {UsagePartial.beforeLoad},
          ),
        ),
      );
      expect(data.usage, isNull);
      expect(data.cost?.label, r'— · session ~$1.20');
    });

    // Задача 3.6 add-usage-ledger (D8, D23 Т9 п. 3 add-usage-extension):
    // после загрузки со снимком `load` сумма полная из журнала, без
    // `beforeLoad`, снимка хода ещё нет. Регрессионная страховка: маппер
    // правило уже соблюдает.
    test('«Полная сумма после load»: «— · session \$1.20» без «~»', () {
      final data = _of(
        _reported(
          session: UsageTotals(tokens: _noCache, cost: _usd(1200000)),
        ),
      );
      expect(data.usage, isNull);
      expect(data.cost?.label, r'— · session $1.20');
      expect(data.cost?.label, isNot(contains('~')));
    });

    test('without session.cost there is no cost segment', () {
      final data = _of(
        _reported(
          session: const UsageTotals(
            tokens: _noCache,
            partial: {UsagePartial.beforeLoad},
          ),
        ),
      );
      expect(data.usage, isNull);
      expect(data.cost, isNull);
    });
  });

  group('approximation marks', () {
    UsageTotals turn(Set<UsagePartial> partial, {Money? cost}) =>
        UsageTotals(tokens: _noCache, cost: cost, partial: partial);

    test('noUsage and beforeLoad put «~» before the tokens', () {
      for (final reason in [UsagePartial.noUsage, UsagePartial.beforeLoad]) {
        final data = _of(
          _reported(
            lastTurn: turn({reason}),
            session: const UsageTotals(tokens: _noCache),
          ),
        );
        expect(data.usage?.label, '~120 → 30', reason: reason.name);
      }
    });

    test('noPrice does not mark the tokens', () {
      final data = _of(
        _reported(
          lastTurn: turn({UsagePartial.noPrice}),
          session: const UsageTotals(tokens: _noCache),
        ),
      );
      expect(data.usage?.label, '120 → 30');
    });

    test('«Неполная сумма после загрузки»: «~» before the session cost', () {
      final data = _of(
        _reported(
          lastTurn: turn(const {}, cost: _usd(4100)),
          session: UsageTotals(
            tokens: _noCache,
            cost: _usd(1200000),
            partial: const {UsagePartial.beforeLoad},
          ),
        ),
      );
      expect(data.cost?.label, r'$0.0041 · session ~$1.20');
    });

    test('any reason of the turn marks the turn cost', () {
      final data = _of(
        _reported(
          lastTurn: turn({UsagePartial.noPrice}, cost: _usd(4100)),
          session: UsageTotals(tokens: _noCache, cost: _usd(1200000)),
        ),
      );
      expect(data.cost?.label, r'~$0.0041 · session $1.20');
    });
  });

  group('cost', () {
    test('«Цена хода неизвестна, сессии известна»', () {
      final data = _of(
        _reported(
          lastTurn: const UsageTotals(tokens: _noCache),
          session: UsageTotals(tokens: _noCache, cost: _usd(1200000)),
        ),
      );
      expect(data.cost?.label, r'— · session $1.20');
    });

    test('«Цена неизвестна»: «—» with the hint, never \$0', () {
      final data = _of(
        _reported(
          lastTurn: const UsageTotals(tokens: _noCache),
          session: const UsageTotals(tokens: _noCache),
        ),
      );
      expect(data.cost?.label, '—');
      expect(data.cost?.tooltip, 'price unknown');
      expect(data.usage?.label, '120 → 30');
    });

    test('the session price is unknown: only the turn cost', () {
      final data = _of(
        _reported(
          lastTurn: UsageTotals(tokens: _noCache, cost: _usd(4100)),
          session: const UsageTotals(tokens: _noCache),
        ),
      );
      expect(data.cost?.label, r'$0.0041');
    });

    test('a known zero is \$0.00, not «—»', () {
      final data = _of(
        _reported(
          lastTurn: UsageTotals(tokens: _noCache, cost: _usd(0)),
          session: UsageTotals(tokens: _noCache, cost: _usd(0)),
        ),
      );
      expect(data.cost?.label, r'$0.00 · session $0.00');
    });

    test('a non-USD currency is a suffix', () {
      final data = _of(
        _reported(
          lastTurn: const UsageTotals(tokens: _noCache),
          session: UsageTotals(
            tokens: _noCache,
            cost: const Money(micros: 12340000, currency: 'EUR'),
          ),
        ),
      );
      expect(data.cost?.label, '— · session 12.34 EUR');
    });
  });

  group('context', () {
    test('«Контекст близко к пределу»: 85% is warning', () {
      final segment = _context(
        const ContextFillView(used: 170000, size: 200000),
      ).context;
      expect(segment?.label, '85% context');
      expect(segment?.tone, CodeLabTone.warning);
    });

    test('96% is danger; 95% is already danger, 94% is warning', () {
      expect(
        _context(
          const ContextFillView(used: 192000, size: 200000),
        ).context?.tone,
        CodeLabTone.danger,
      );
      expect(
        _context(
          const ContextFillView(used: 190000, size: 200000),
        ).context?.tone,
        CodeLabTone.danger,
      );
      expect(
        _context(
          const ContextFillView(used: 188000, size: 200000),
        ).context?.tone,
        CodeLabTone.warning,
      );
    });

    test('«Процент вниз»: 79.6% is 79% and has no tone', () {
      final segment = _context(
        const ContextFillView(used: 159200, size: 200000),
      ).context;
      expect(segment?.label, '79% context');
      expect(segment?.tone, CodeLabTone.neutral);
    });

    test('«Меньше одного процента»: <1%; used = 0 hides the segment', () {
      expect(
        _context(const ContextFillView(used: 500, size: 200000)).context?.label,
        '<1% context',
      );
      expect(
        _context(const ContextFillView(used: 0, size: 200000)).context,
        isNull,
      );
    });

    test('without a window size the segment is hidden', () {
      expect(_context(const ContextFillView(used: 5000)).context, isNull);
      expect(
        _context(const ContextFillView(used: 5000, size: 0)).context,
        isNull,
      );
      expect(_of(_reported()).context, isNull);
    });

    test('«Скоро сжатие» only with a known compactAt', () {
      final soon = _context(
        const ContextFillView(used: 168000, size: 200000, compactAt: 183616),
      ).context;
      expect(soon?.label, '84% context · compaction soon');
      expect(soon?.tone, CodeLabTone.warning);

      final off = _context(
        const ContextFillView(used: 168000, size: 200000),
      ).context;
      expect(off?.label, '84% context');

      final far = _context(
        const ContextFillView(used: 100000, size: 200000, compactAt: 183616),
      ).context;
      expect(far?.label, '50% context');
    });

    test('a window overflow is shown as is', () {
      final segment = _context(
        const ContextFillView(used: 210000, size: 200000),
      ).context;
      expect(segment?.label, '105% context');
      expect(segment?.tone, CodeLabTone.danger);
    });
  });
}
