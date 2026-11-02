import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Подсказка «did you mean» для неизвестного ключа (`nearestKey`; design.md
/// change `add-config-writer-and-reload`, D3: общая для валидатора ядра и
/// предконфигурации хоста).
void main() {
  const keys = ['context_window', 'max_output_tokens', 'model'];

  test('a typo within distance 2 gets the nearest key', () {
    expect(nearestKey('contex_window', keys), 'context_window');
    expect(nearestKey('modle', keys), 'model');
  });

  test('a key farther than 2 edits gets no hint', () {
    expect(nearestKey('something_else', keys), isNull);
    expect(nearestKey('x', const []), isNull);
  });
}
