import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

String _hash7(String raw) =>
    sha256.convert(utf8.encode(raw)).toString().substring(0, 7);

void main() {
  // core/mcp-tool-name-sanitized (E-05; agent-tools «MCP-инструменты»).
  test('characters outside [A-Za-z0-9_-] become underscores', () {
    expect(mcpToolName('my.srv', 'get issue'), 'mcp__my_srv__get_issue');
  });

  test('a name of up to 64 characters is kept as is', () {
    final name = mcpToolName('fake', 'a' * 50);

    expect(name, 'mcp__fake__${'a' * 50}');
    expect(name.length, lessThanOrEqualTo(64));
  });

  test('a long name is 56 characters, "_" and 7 hex of SHA-256', () {
    final tool = 't' * (100 - 'mcp__srv__'.length);
    final raw = 'mcp__srv__$tool';
    expect(raw.length, 100);

    final name = mcpToolName('srv', tool);

    expect(name.length, 64);
    expect(name, '${raw.substring(0, 56)}_${_hash7(raw)}');
  });

  test('names sharing the first 56 characters stay different', () {
    final a = mcpToolName('srv', '${'x' * 60}a');
    final b = mcpToolName('srv', '${'x' * 60}b');

    expect(a.length, 64);
    expect(b.length, 64);
    expect(a.substring(0, 56), b.substring(0, 56));
    expect(a, isNot(b));
  });

  test('the hash is computed from the raw name, before substitution', () {
    // `a.b` и `a_b` дают одну санитизированную форму, но разные хэши.
    final dotted = mcpToolName('srv', '${'z' * 60}.b');
    final underscored = mcpToolName('srv', '${'z' * 60}_b');

    expect(dotted.length, 64);
    expect(dotted, isNot(underscored));
    expect(dotted.endsWith(_hash7('mcp__srv__${'z' * 60}.b')), isTrue);
  });

  test('the result is deterministic and matches the registry pattern', () {
    final name = mcpToolName('сервер', 'инструмент ${'я' * 80}');

    expect(name, mcpToolName('сервер', 'инструмент ${'я' * 80}'));
    expect(RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(name), isTrue);
  });

  test('mcpServerPrefix names the sanitized server prefix', () {
    expect(mcpServerPrefix('my.srv'), 'mcp__my_srv__');
  });
}
