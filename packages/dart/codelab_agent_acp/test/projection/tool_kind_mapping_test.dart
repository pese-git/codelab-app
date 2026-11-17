import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Регрессия change `tolerate-unknown-tool-kind` (D6): проекция агента
/// переводит вид ядра в ACP через `acp.ToolKind.values.byName(kind.name)`.
/// Новое значение `acp.ToolKind.switchMode` не должно ломать эту таблицу, а
/// в `ToolKind` ядра `switchMode` не появляется — агент такого вида не
/// порождает.
void main() {
  group('core ToolKind to acp.ToolKind by name', () {
    for (final kind in ToolKind.values) {
      test('${kind.name} maps with the same wire name', () {
        final mapped = acp.ToolKind.values.byName(kind.name);

        expect(mapped.wireName, kind.name);
      });
    }
  });

  test('the core ToolKind has no switchMode (D6)', () {
    expect(
      ToolKind.values.map((kind) => kind.name),
      isNot(contains('switchMode')),
    );
  });
}
