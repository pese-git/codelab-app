import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// `builtinSubagentTypes` доступна из основного бареля ядра (design.md change
/// `add-settings-agents-modes`, D7): мост `codelab_setup` строит по ней
/// встроенные строки таблицы определений агентов и не копирует список имён.
///
/// Красный до задачи 2.2: функция из барелем не экспортируется, файл не
/// компилируется (`undefined_function`).
void main() {
  test('встроенные типы субагентов видны из основного бареля', () {
    final types = builtinSubagentTypes();

    expect(
      [for (final type in types) type.name],
      ['general', 'explore', 'review', 'plan'],
    );
    expect(types.every((type) => type.source.startsWith('builtin:')), isTrue);
  });
}
