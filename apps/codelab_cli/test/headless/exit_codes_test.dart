// Коды выхода headless (tasks 3.1; spec cli-headless «Коды выхода headless»;
// design.md change `add-codelab-cli`, D9).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  test('end_turn with an answer is 0', () {
    expect(
      exitCodeOf(const TurnCompleted(StopReason.endTurn, hadText: true)),
      0,
    );
  });

  test('end_turn without an answer is 1', () {
    expect(
      exitCodeOf(const TurnCompleted(StopReason.endTurn, hadText: false)),
      1,
    );
  });

  test('max_tokens, max_turn_requests, refusal and a missing stop reason '
      'are 1', () {
    for (final reason in [
      StopReason.maxTokens,
      StopReason.maxTurnRequests,
      StopReason.refusal,
      null,
    ]) {
      expect(
        exitCodeOf(TurnCompleted(reason, hadText: true)),
        1,
        reason: '$reason',
      );
    }
  });

  test('a cancelled turn is 130', () {
    expect(
      exitCodeOf(const TurnCompleted(StopReason.cancelled, hadText: true)),
      130,
    );
  });

  test('a failed turn and a failed connection are 1', () {
    expect(exitCodeOf(const TurnFailed('provider down')), 1);
    expect(exitCodeOf(const ConnectFailed('no agent')), 1);
  });

  test('a timeout is 130', () {
    expect(exitCodeOf(const TimedOut()), 130);
  });

  test('a signal keeps its code', () {
    expect(exitCodeOf(const Signalled(130)), 130);
    expect(exitCodeOf(const Signalled(143)), 143);
  });
}
