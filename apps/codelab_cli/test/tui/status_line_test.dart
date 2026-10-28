// Статус-строка TUI (tasks 2.5 change `add-cli-tui`; spec codelab-tui
// «Строка подсказок и статус-строка TUI»; §12.2.6; design.md, D11).

import 'package:codelab_cli/codelab_cli.dart';
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
}
