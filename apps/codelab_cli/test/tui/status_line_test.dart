// Статус-строка TUI (tasks 2.5 change `add-cli-tui`; spec codelab-tui
// «Строка подсказок и статус-строка TUI»; §12.2.6; design.md, D11).
//
// Дополнено задачей 3.4 change `add-usage-extension` (spec codelab-tui,
// сценарии «Сегменты usage», «Форматы чисел», «Цвет по целому проценту»,
// «Порядок отбрасывания», «Агент без usage»; design.md, D12, D23 Т4, D24).
// Красные тесты группы usage: `StatusInfo.usage` (`UsageView?`), функции
// форматирования `codelab_client_core` (3.0a), перенос `SessionView.usage` в
// `statusInfoOf` и цвета порогов в `render` (константы `sgrYellow`, `sgrRed`
// в `render/ansi.dart`) ещё нет (3.11). До 3.11 файл не компилируется из-за
// параметра `usage`; прежние тесты не менялись.

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

void main() {
  const full = StatusInfo(
    profile: 'default',
    mode: 'plan',
    model: 'openrouter/qwen3.6-plus',
    queued: 2,
  );

  test('segments in order with a dot separator', () {
    expect(
      statusLine(full, 100),
      'default · plan · openrouter/qwen3.6-plus · queue: 2',
    );
  });

  test('an empty queue and missing options are not shown', () {
    expect(statusLine(const StatusInfo(profile: 'p'), 100), 'p');
  });

  test('during a turn the spinner and the time go first', () {
    expect(
      statusLine(
        const StatusInfo(
          profile: 'p',
          mode: 'plan',
          spinner: '⠋',
          elapsed: Duration(seconds: 12),
        ),
        100,
      ),
      '⠋ 12s · p · plan',
    );
  });

  test('a narrow terminal drops the profile, shortens and drops the model, '
      'keeps the mode and the queue', () {
    expect(statusLine(full, 45), 'plan · openrouter/qwen3.6-plus · queue: 2');
    expect(statusLine(full, 30), 'plan · qwen3.6-plus · queue: 2');
    expect(statusLine(full, 20), 'plan · queue: 2');
    final cut = statusLine(full, 10);
    expect(cut, endsWith('…'));
    expect(displayWidth(cut), lessThanOrEqualTo(10));
  });

  group('usage (add-usage-extension, 3.4)', () {
    UsageView reported({
      TokenCounts tokens = const TokenCounts(
        input: 94049,
        output: 7249,
        cacheRead: 0,
        cacheWrite: 0,
      ),
      Money? cost = const Money(micros: 125000, currency: 'USD'),
      Set<UsagePartial> partial = const {},
      ContextFillView? context = const ContextFillView(
        used: 162000,
        size: 200000,
      ),
    }) => UsageView(
      support: UsageSupport.reported,
      session: UsageTotals(tokens: tokens, cost: cost, partial: partial),
      context: context,
      lastSeq: 1,
    );

    StatusInfo info(
      UsageView? usage, {
      String profile = 'default',
      String mode = 'standard',
      String model = 'anthropic/claude-sonnet-4',
      int queued = 0,
      bool approvalPending = false,
    }) => StatusInfo(
      profile: profile,
      mode: mode,
      model: model,
      queued: queued,
      approvalPending: approvalPending,
      usage: usage,
    );

    test('сегменты после модели: контекст, токены, стоимость', () {
      expect(
        statusLine(info(reported(partial: {UsagePartial.noPrice})), 120),
        'default · standard · anthropic/claude-sonnet-4 · ctx 81% · '
        '↑94.0k ↓7.2k · ~\$0.13',
      );
    });

    test('вход — input + cacheRead + cacheWrite', () {
      final usage = reported(
        tokens: const TokenCounts(
          input: 90000,
          output: 7249,
          cacheRead: 3000,
          cacheWrite: 1049,
        ),
      );
      expect(statusLine(info(usage), 120), contains('↑94.0k ↓7.2k'));
    });

    test('«~» у токенов — при noUsage и beforeLoad, не при noPrice', () {
      expect(
        statusLine(info(reported(partial: {UsagePartial.noUsage})), 120),
        contains('~↑94.0k ↓7.2k · ~\$0.13'),
      );
      expect(
        statusLine(info(reported(partial: {UsagePartial.beforeLoad})), 120),
        contains('~↑94.0k ↓7.2k · ~\$0.13'),
      );
      final noPrice = statusLine(
        info(reported(partial: {UsagePartial.noPrice})),
        120,
      );
      expect(noPrice, contains(' · ↑94.0k ↓7.2k · ~\$0.13'));
      expect(noPrice, isNot(contains('~↑')));
    });

    test('форматы чисел: ctx <1%, тысячи, четыре знака стоимости', () {
      final usage = reported(
        cost: const Money(micros: 4567, currency: 'USD'),
        context: const ContextFillView(used: 500, size: 200000),
      );
      expect(
        statusLine(info(usage), 120),
        contains('ctx <1% · ↑94.0k ↓7.2k · \$0.0046'),
      );
    });

    test('известный ноль стоимости — \$0.00', () {
      final usage = reported(cost: const Money(micros: 0, currency: 'USD'));
      expect(statusLine(info(usage), 120), endsWith('\$0.00'));
    });

    test('порядок отбрасывания: профиль, стоимость, токены, контекст, затем '
        'модель (сначала сокращается)', () {
      final usage = reported();
      final full = info(usage);
      expect(statusLine(full, 120), contains('default · standard'));
      // 60: нет профиля, стоимости и токенов — контекст ещё помещается.
      expect(
        statusLine(full, 60),
        'standard · anthropic/claude-sonnet-4 · ctx 81%',
      );
      // 40: нет и контекста.
      expect(statusLine(full, 40), 'standard · anthropic/claude-sonnet-4');
      // 25: модель сначала сокращается (26 колонок), затем отбрасывается.
      expect(statusLine(full, 25), 'standard');
    });

    test('по одному сегменту за шаг на коротких данных', () {
      final usage = reported(partial: const {});
      final short = info(usage, mode: 'plan', model: 'gpt-5');
      expect(
        statusLine(short, 56),
        'default · plan · gpt-5 · ctx 81% · ↑94.0k ↓7.2k · \$0.13',
      );
      expect(
        statusLine(short, 50),
        'plan · gpt-5 · ctx 81% · ↑94.0k ↓7.2k · \$0.13',
      );
      expect(statusLine(short, 40), 'plan · gpt-5 · ctx 81% · ↑94.0k ↓7.2k');
      expect(statusLine(short, 30), 'plan · gpt-5 · ctx 81%');
      expect(statusLine(short, 15), 'plan · gpt-5');
    });

    test('режим и очередь не отбрасываются при любой ширине', () {
      final usage = reported();
      for (final width in [60, 40, 25, 20]) {
        final line = statusLine(info(usage, queued: 2), width);
        expect(line, contains('standard'), reason: 'width $width');
        expect(line, contains('queue: 2'), reason: 'width $width');
        expect(displayWidth(line), lessThanOrEqualTo(width));
      }
    });

    test('approval pending · esc to answer не отбрасывается', () {
      final line = statusLine(info(reported(), approvalPending: true), 70);
      expect(line, contains('approval pending · esc to answer'));
      expect(line, contains('standard'));
      expect(line, isNot(contains('default')));
      expect(displayWidth(line), lessThanOrEqualTo(70));
    });

    group('без данных сегмента нет, 0 не печатается (VIEW-6)', () {
      final cases = <String, UsageView?>{
        'usage == null': null,
        'агент не объявил usage': const UsageView(),
        'объявил, снимков нет': const UsageView(support: UsageSupport.awaiting),
        'снимок без суммы и контекста': const UsageView(
          support: UsageSupport.reported,
          lastSeq: 1,
        ),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        test(key, () {
          final line = statusLine(
            info(value, profile: 'p', mode: 'plan', model: 'm'),
            100,
          );
          expect(line, 'p · plan · m');
          for (final mark in ['ctx', '↑', '↓', r'$', '0', '~']) {
            expect(line, isNot(contains(mark)));
          }
        });
      }

      test(
        'нет размера окна и used = 0 — без ctx; цена неизвестна — без \$',
        () {
          final line = statusLine(
            info(
              reported(
                cost: null,
                context: const ContextFillView(used: 0, size: 200000),
              ),
              profile: 'p',
              mode: 'plan',
              model: 'm',
            ),
            100,
          );
          expect(line, 'p · plan · m · ↑94.0k ↓7.2k');
          expect(
            statusLine(
              info(
                reported(context: const ContextFillView(used: 5000)),
                profile: 'p',
                mode: 'plan',
                model: 'm',
              ),
              100,
            ),
            isNot(contains('ctx')),
          );
        },
      );
    });

    group('цвет контекста в render — по целому проценту', () {
      final yellow = RegExp('\x1b\\[33mctx 80%');
      final red = RegExp('\x1b\\[31mctx 95%');

      String statusRow(int used, {bool color = true}) {
        final (model, _) = reduce(
          TuiModel.initial(
            profile: 'default',
            size: const TerminalSize(columns: 120, rows: 30),
            color: color,
          ),
          SessionViewMsg(
            SessionView(
              revision: 1,
              status: SessionStatusView.idle,
              usage: reported(
                context: ContextFillView(used: used, size: 200000),
              ),
            ),
            at: DateTime.utc(2026, 11, 16),
          ),
        );
        return render(
          model,
          TuiChrome(now: DateTime.utc(2026, 11, 16)),
        ).lines.last;
      }

      test('79 % — без жёлтого', () {
        final row = statusRow(159200);
        expect(row, contains('ctx 79%'));
        expect(row, isNot(contains('\x1b[33m')));
        expect(row, isNot(contains('\x1b[31m')));
      });

      test('80 % — жёлтый, сегмент внутри приглушённой строки', () {
        final row = statusRow(160000);
        expect(row, matches(RegExp('.*\x1b\\[33mctx 80%.*')));
        expect(yellow.hasMatch(row), isTrue);
        expect(row, startsWith('\x1b[2m'));
      });

      test('95 % — красный', () {
        expect(red.hasMatch(statusRow(190000)), isTrue);
      });

      test('без цвета SGR нет совсем', () {
        final row = statusRow(190000, color: false);
        expect(row, contains('ctx 95%'));
        expect(row, isNot(contains('\x1b')));
      });
    });
    group('очистка сегментов от управляющих символов', () {
      const leak = 'sk-test-leak-0123456789';

      test('ESC в профиле, режиме и модели не попадает в строку', () {
        final line = statusLine(
          StatusInfo(
            profile: 'pr\x1b[2Jo',
            mode: 'pl\x1b[31man\x07',
            model: 'm\x1b]0;$leak\x07odel',
          ),
          120,
        );
        expect(line, 'pr[2Jo · pl[31man · m]0;${leak}odel');
        expect(line, isNot(contains('\x1b')));
        expect(line, isNot(contains('\x07')));
      });

      test('перевод строки в режиме и модели заменён пробелом', () {
        final line = statusLine(
          const StatusInfo(profile: 'p', mode: 'pl\nan', model: 'evil\nmodel'),
          120,
        );
        expect(line, 'p · pl an · evil model');
        expect(line, isNot(contains('\n')));
      });

      test('ESC в валюте стоимости не попадает в строку', () {
        final usage = reported(
          cost: const Money(micros: 125000, currency: 'E\x1b[31mUR\x07'),
        );
        final line = statusLine(info(usage), 120);
        expect(line, contains('0.13 E[31mUR'));
        expect(line, isNot(contains('\x1b')));
        expect(line, isNot(contains('\x07')));
      });

      test('statusInfoOf + render: ESC из опций сессии вырезан', () {
        final (model, _) = reduce(
          TuiModel.initial(
            profile: 'default',
            size: const TerminalSize(columns: 120, rows: 30),
            color: false,
          ),
          SessionViewMsg(
            SessionView(
              revision: 1,
              status: SessionStatusView.idle,
              configOptions: [
                ConfigOptionView(
                  id: 'mode',
                  name: 'Mode',
                  currentValue: 'pl\x1b[31man',
                  values: const [],
                ),
                ConfigOptionView(
                  id: 'model',
                  name: 'Model',
                  currentValue: 'm\x1b]0;$leak\x07odel',
                  values: const [],
                ),
              ],
            ),
            at: DateTime.utc(2026, 11, 16),
          ),
        );
        final row = render(
          model,
          TuiChrome(now: DateTime.utc(2026, 11, 16)),
        ).lines.last;
        expect(row, contains('pl[31man'));
        expect(row, isNot(contains('\x1b')));
        expect(row, isNot(contains('\x07')));
      });
    });

    test('нулевые токены хода скрыты, стоимость остаётся', () {
      final usage = reported(
        tokens: const TokenCounts(
          input: 0,
          output: 0,
          cacheRead: 0,
          cacheWrite: 0,
        ),
      );
      final line = statusLine(info(usage, profile: 'p'), 120);
      expect(line, isNot(contains('↑')));
      expect(line, isNot(contains('↓')));
      expect(line, contains('\$0.13'));
    });

    test('сумма входа насыщается, а не переполняет int', () {
      const max = 0x7fffffffffffffff;
      final usage = reported(
        tokens: const TokenCounts(
          input: max,
          output: 1,
          cacheRead: max,
          cacheWrite: 5,
        ),
      );
      final line = statusLine(info(usage), 120);
      expect(line, contains('↑9007199254.7M'));
    });
  });
}
