import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// `McpServerConfig.enabled` (design.md change `add-config-writer-and-reload`,
/// D10): умолчание, сохранение при раскрытии секретов и независимость от
/// `sameConnection`.
void main() {
  test('a server is enabled by default', () {
    expect(const McpStdioServerConfig(name: 'a', command: 'c').enabled, isTrue);
    expect(
      McpHttpServerConfig(name: 'a', url: Uri.parse('https://a.test')).enabled,
      isTrue,
    );
  });

  test('withSecrets keeps enabled: the copy of a disabled server stays '
      'disabled', () {
    const stdio = McpStdioServerConfig(name: 'a', command: 'c', enabled: false);
    final http = McpHttpServerConfig(
      name: 'h',
      url: Uri.parse('https://a.test'),
      enabled: false,
    );

    expect(stdio.withSecrets({'env.K': 'v'}).enabled, isFalse);
    expect(http.withSecrets({'headers.X': 'v'}).enabled, isFalse);
  });

  test('sameConnection ignores enabled: it is a choice, not a parameter of '
      'the connection', () {
    const on = McpStdioServerConfig(name: 'a', command: 'c');
    const off = McpStdioServerConfig(name: 'a', command: 'c', enabled: false);

    expect(on.sameConnection(off), isTrue);
  });
}
