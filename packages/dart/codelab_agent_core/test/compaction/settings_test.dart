import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/settings.dart';
import 'package:test/test.dart';

/// agent-compaction «Пороги сжатия» (задача 7.1, `agent-core-architecture`
/// §9.4).
void main() {
  group('forWindow matches the table of §9.4', () {
    const table = [
      (2048, 512, 1024, 1536),
      (8192, 2048, 4096, 6144),
      (32768, 8192, 16384, 24576),
      (128000, 16384, 20000, 111616),
      (200000, 16384, 20000, 183616),
    ];
    for (final (window, reserve, keep, threshold) in table) {
      test('window $window', () {
        final s = CompactionSettings.forWindow(window);
        expect(s.reserveTokens, reserve);
        expect(s.keepRecentTokens, keep);
        expect(s.keepRecentUserTurns, 1);
        expect(compactionThreshold(window, s), threshold);
      });
    }
  });

  test('shouldCompact is strictly above the threshold', () {
    final s = CompactionSettings.forWindow(8192);
    expect(shouldCompact(6144, 8192, s), isFalse);
    expect(shouldCompact(6145, 8192, s), isTrue);
  });

  test('overrides replace the computed values', () {
    final s = CompactionSettings.forWindow(
      32768,
      overrides: const CompactionOverrides(
        reserveTokens: 4000,
        keepRecentTokens: 3000,
        keepRecentUserTurns: 2,
      ),
    );
    expect(s.reserveTokens, 4000);
    expect(s.keepRecentTokens, 3000);
    expect(s.keepRecentUserTurns, 2);
  });

  test('an override above a quarter of the window is capped at w/4', () {
    final s = CompactionSettings.forWindow(
      8192,
      overrides: const CompactionOverrides(reserveTokens: 6000),
    );
    expect(s.reserveTokens, 2048);
  });

  test('an override above half of the window is capped at w/2', () {
    final s = CompactionSettings.forWindow(
      8192,
      overrides: const CompactionOverrides(keepRecentTokens: 7000),
    );
    expect(s.keepRecentTokens, 4096);
  });
}
