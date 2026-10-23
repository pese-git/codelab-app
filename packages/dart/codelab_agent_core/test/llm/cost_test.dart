import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/llm/stream_state.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

final _priced = ModelRef(
  provider: 'anthropic',
  id: 'claude-sonnet-4-5',
  api: ProviderApi.anthropicMessages,
  baseUrl: Uri.parse('https://api.anthropic.com'),
  contextWindow: 200000,
  maxOutputTokens: 16384,
  cost: const ModelCost(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75),
);

void main() {
  test('cost = Σ tokens × rate / 10⁶', () {
    final usage = calculateCost(
      const Usage(input: 1000, output: 500, cacheRead: 2000, cacheWrite: 100),
      _priced.cost,
    );

    expect(usage.cost.input, closeTo(0.003, 1e-12));
    expect(usage.cost.output, closeTo(0.0075, 1e-12));
    expect(usage.cost.cacheRead, closeTo(0.0006, 1e-12));
    expect(usage.cost.cacheWrite, closeTo(0.000375, 1e-12));
    expect(usage.cost.total, closeTo(0.011475, 1e-12));
    expect(usage.input, 1000, reason: 'tokens are kept');
  });

  test('unknown prices give zero cost', () {
    final usage = calculateCost(const Usage(input: 1000, output: 500), null);

    expect(usage.cost, UsageCost.zero);
  });

  test('reasoning is part of output and is not charged separately', () {
    final usage = calculateCost(
      const Usage(output: 1000, reasoning: 800),
      _priced.cost,
    );

    expect(usage.cost.total, closeTo(0.015, 1e-12));
  });

  test('the adapter charges in finish and in fail', () async {
    Future<AssistantMessage> run(bool success) async {
      final stream = runProvider(_priced, null, FakeClock(), (state) async {
        state
          ..start()
          ..setUsage(const Usage(input: 1000, output: 100));
        if (success) {
          state.finish(StopReason.stop);
        } else {
          state.fail(LlmErrorClass.network, 'reset');
        }
      });
      return stream.result;
    }

    expect((await run(true)).usage.cost.total, closeTo(0.0045, 1e-12));
    expect(
      (await run(false)).usage.cost.total,
      closeTo(0.0045, 1e-12),
      reason: 'a partial answer costs money too',
    );
  });
}
