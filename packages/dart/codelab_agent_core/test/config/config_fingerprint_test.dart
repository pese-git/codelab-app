import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Отпечаток файла конфигурации для оптимистичной записи (`ConfigSnapshot.
/// fingerprint`; design.md change `add-config-writer-and-reload`, D5,
/// `agent-core-architecture` §17.5.5, шаг 4) и разбор пути ключа, нужный
/// писателю `codelab_agent_io` (D5).
void main() {
  test('configFingerprint is the lowercase hex sha256 of the bytes', () {
    // Известный вектор sha256("abc"), FIPS 180-2.
    expect(
      configFingerprint(utf8.encode('abc')),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('configFingerprint of an empty file is the sha256 of no bytes', () {
    expect(
      configFingerprint(const []),
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('splitKeyPath is public: quoted segment and list element', () {
    final segments = splitKeyPath(
      'providers.local.models."qwen2.5-coder-32b".context_window',
    );
    expect(
      [for (final s in segments!) s.value],
      ['providers', 'local', 'models', 'qwen2.5-coder-32b', 'context_window'],
    );
    expect(splitKeyPath('mcp.servers[github].url')!.map((s) => s.isElement), [
      false,
      false,
      true,
      false,
    ]);
    expect(splitKeyPath('a..b'), isNull);
  });

  test('inlineSecretKeys is public: writer and output share one list', () {
    expect(inlineSecretKeys, {
      'api_key',
      'apiKey',
      'token',
      'secret',
      'password',
    });
  });
}
