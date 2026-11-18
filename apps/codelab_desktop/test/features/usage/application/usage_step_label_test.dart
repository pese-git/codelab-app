// Красные тесты задачи 1.4 change `add-desktop-usage-pane`: подписи шагов
// журнала по транскрипту (agent-workbench-ui «Подпись шага в панели Usage»:
// «Шаг с одним вызовом», «Шаг с несколькими вызовами», «Ответ без вызовов и
// вызовы вне транскрипта»; design.md, D4, Q6).
//
// Подпись строки вызова даёт `ToolRowFormatter` kit (`<label> <detail>`): тест
// не повторяет его правил, а берёт метку и деталь строки ленты для того же
// вызова. Журнал заголовков вызовов не несёт (D1 п. 4 change
// `add-usage-ledger`), поэтому единственный источник подписи — транскрипт.
//
// Проверяется `UsageStepLabeler` — индекс `toolCallId → item`, который
// строится один раз на ревизию `SessionView` (D4).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show ToolCallId, ToolKind;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/usage/application/usage_step_label.dart';
import 'package:flutter_test/flutter_test.dart';

const _cwd = '/work';

ToolCallItem _read(String id, String path, {List<TranscriptItem>? children}) =>
    ToolCallItem(
      id: 'tool-$id',
      toolCallId: ToolCallId(id),
      title: 'Read',
      details: ToolCallView(
        kind: ToolKind.read,
        status: ToolCallStatusView.succeeded,
        rawInput: {'path': path},
      ),
      children: children ?? const [],
    );

/// Подпись той же строки ленты: метка и деталь формата kit.
String _rowLabel(ToolCallItem item) {
  final row = ToolRowFormatter.format(item, cwd: _cwd);
  return '${row.label} ${row.detail}';
}

UsageLedgerStep _step(List<String> ids, {int index = 0}) => UsageLedgerStep(
  index: index,
  tokens: const TokenCounts(input: 1, output: 1, cacheRead: 0, cacheWrite: 0),
  toolCallIds: ids,
);

void main() {
  group('подпись шага (D4)', () {
    test('шаг с одним вызовом: метка и деталь строки ленты', () {
      final call = _read('call_1', '/work/lib/acp_transcript_panel.dart');
      final labeler = UsageStepLabeler([call], cwd: _cwd);

      expect(
        labeler.labelOf(_step(['call_1'])).englishText,
        'Read lib/acp_transcript_panel.dart',
      );
      expect(labeler.labelOf(_step(['call_1'])).englishText, _rowLabel(call));
    });

    test('шаг с тремя вызовами: подпись первого найденного и суффикс +2', () {
      final first = _read('call_1', '/work/lib/a.dart');
      final labeler = UsageStepLabeler([
        first,
        _read('call_2', '/work/lib/b.dart'),
        _read('call_3', '/work/lib/c.dart'),
      ], cwd: _cwd);

      expect(
        labeler.labelOf(_step(['call_1', 'call_2', 'call_3'])).englishText,
        '${_rowLabel(first)} +2',
      );
    });

    test('шаг без вызовов — reply', () {
      final labeler = UsageStepLabeler([_read('call_1', '/work/a')], cwd: _cwd);

      expect(labeler.labelOf(_step(const [])).englishText, 'reply');
    });

    test('вызовы не найдены в транскрипте — N tool calls', () {
      final labeler = UsageStepLabeler([_read('call_1', '/work/a')], cwd: _cwd);

      expect(labeler.labelOf(_step(['x1', 'x2'])).englishText, '2 tool calls');
    });

    test('вызов потомка не ищется на вложенном уровне: вызов только корня', () {
      final child = _read('call_1/call_1', '/work/lib/inner.dart');
      final root = _read('call_1', '/work/lib/outer.dart', children: [child]);
      final labeler = UsageStepLabeler([root], cwd: _cwd);

      expect(
        labeler.labelOf(_step(['call_1/call_1', 'call_1/call_2'])).englishText,
        '2 tool calls',
      );
    });

    test('первый вызов шага не найден, найден второй: подпись второго', () {
      final second = _read('call_2', '/work/lib/b.dart');
      final labeler = UsageStepLabeler([second], cwd: _cwd);

      expect(
        labeler.labelOf(_step(['missing', 'call_2', 'call_3'])).englishText,
        '${_rowLabel(second)} +2',
      );
    });

    test('пустой транскрипт даёт N tool calls, а не ошибку', () {
      final labeler = UsageStepLabeler(const [], cwd: _cwd);

      expect(
        labeler.labelOf(_step(['a', 'b', 'c'])).englishText,
        '3 tool calls',
      );
    });
  });
}
