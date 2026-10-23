import 'package:codelab_agent_core/src/llm/builtin_models.dart';
import 'package:test/test.dart';

void main() {
  test('the built-in table is not empty', () {
    expect(builtinModels, isNotEmpty);
  });

  for (final MapEntry(key: id, value: info) in builtinModels.entries) {
    test('$id: window > 0, max output < window, prices are complete', () {
      expect(info.contextWindow, isNotNull);
      expect(info.contextWindow, greaterThan(0));
      expect(info.maxOutputTokens, isNotNull);
      expect(info.maxOutputTokens, lessThan(info.contextWindow!));
      expect(info.cost, isNotNull);
      expect(info.cost!.input, greaterThan(0));
      expect(info.cost!.output, greaterThan(0));
    });
  }
}
