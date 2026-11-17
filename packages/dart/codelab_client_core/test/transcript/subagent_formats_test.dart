// Формат токенов и разбор `failure` субагента (итерация 5b, ревью): общие для
// REPL, TUI и desktop (D24, D33).
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

void main() {
  SubagentSummaryView summary(int input, int output) => SubagentSummaryView(
    toolCalls: 4,
    inputTokens: input,
    outputTokens: output,
    duration: const Duration(seconds: 48),
  );

  test('tokensText: меньше тысячи — число, иначе k с одним знаком', () {
    expect(summary(500, 350).tokensText, '850');
    expect(summary(15000, 3200).tokensText, '18.2k');
  });

  test('text и shortText строятся на tokensText', () {
    final s = summary(15000, 3200);
    expect(s.text, '4 tool calls · 18.2k tokens · 48s');
    expect(s.shortText, '4 tool calls · 18.2k · 48s');
  });

  test('parseSubagentFailure: непустая строка или null', () {
    expect(parseSubagentFailure({'failure': 'boom'}), 'boom');
    expect(parseSubagentFailure({'failure': ''}), isNull);
    expect(parseSubagentFailure({'failure': 3}), isNull);
    expect(parseSubagentFailure(null), isNull);
  });
}
