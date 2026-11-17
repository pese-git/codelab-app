import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Правило имени MCP-сервера (design.md change `add-provider-setup-ui`, D11,
/// решение Q20): одно на `codelab mcp add` (`codelab_agent_io`) и форму
/// сервера клиентов (`McpServerDraft`). Прежнее приватное `_nameFormat`
/// io — `^[^\s\[\]"]+$`; тексты `codelab mcp` при переносе не меняются.
void main() {
  test('обычные имена допустимы', () {
    for (final name in ['github', 'GitHub', 'my-server_1', 'a.b', 'я']) {
      expect(isValidMcpServerName(name), isTrue, reason: name);
    }
  });

  test('пустое имя, пробелы, табуляция, скобки и кавычка недопустимы', () {
    for (final name in ['', ' ', 'a b', 'a\tb', 'a\nb', 'a[0]', 'a]', '"a"']) {
      expect(isValidMcpServerName(name), isFalse, reason: '"$name"');
    }
  });

  test('имя, которое различается только регистром, допустимо (проверка '
      'уникальности — дело формы, а не правила формата)', () {
    expect(isValidMcpServerName('GitHub'), isTrue);
    expect(isValidMcpServerName('github'), isTrue);
  });
}
