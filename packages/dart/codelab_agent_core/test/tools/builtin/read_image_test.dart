import 'dart:convert';
import 'dart:typed_data';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:test/test.dart';

import '../capability_envs.dart';
import '../executor_harness.dart';

void main() {
  final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 1, 2, 3]);

  // Картинки `read` (§6.4, шаг 2): нужен env с `BinaryFiles` и модель с
  // `supportsImages`, иначе — текст ошибки.
  late BinaryMemoryEnv env;
  late ExecutorHarness h;

  setUp(() async {
    env = BinaryMemoryEnv(MemoryExecutionEnv(cwd: '/proj'));
    h = await ExecutorHarness.create([ReadTool()], base: env);
  });

  test('an image becomes ImageContent with a caption', () async {
    env.putBinary('/proj/img/logo.png', png);

    final outcome = await h.run('read', {
      'path': 'img/logo.png',
    }, invocation: h.invocation(supportsImages: true));

    expect(outcome.outcome, ToolOutcome.completed);
    final content = outcome.message.content;
    expect(content, hasLength(2));
    final image = content[0] as ImageContent;
    expect(image.mimeType, 'image/png');
    expect(base64Decode(image.base64), png);
    expect((content[1] as TextContent).text, 'Image img/logo.png (8 bytes)');
  });

  test('mime types by extension', () async {
    final types = {
      'a.jpg': 'image/jpeg',
      'a.jpeg': 'image/jpeg',
      'a.gif': 'image/gif',
      'a.webp': 'image/webp',
      'A.PNG': 'image/png',
    };
    for (final MapEntry(key: name, value: mime) in types.entries) {
      env.putBinary('/proj/$name', png);
      final outcome = await h.run('read', {
        'path': name,
      }, invocation: h.invocation(supportsImages: true));
      expect((outcome.message.content.first as ImageContent).mimeType, mime);
    }
  });

  test('a model without images gets an error', () async {
    env.putBinary('/proj/logo.png', png);

    final outcome = await h.run('read', {'path': 'logo.png'});

    expect(outcome.outcome, ToolOutcome.failed);
    expect(
      textOf(outcome),
      'Cannot show image logo.png: the current model or environment does not '
      'support images.',
    );
  });

  test('an env without BinaryFiles gets the same error', () async {
    final memory = MemoryExecutionEnv(cwd: '/proj')
      ..putBytes('/proj/logo.png', png);
    final plain = await ExecutorHarness.create([ReadTool()], memory: memory);

    final outcome = await plain.run('read', {
      'path': 'logo.png',
    }, invocation: plain.invocation(supportsImages: true));

    expect(
      textOf(outcome),
      'Cannot show image logo.png: the current model or environment does not '
      'support images.',
    );
  });

  test('an image above 4 MiB is too large', () async {
    env.putBinary('/proj/big.png', Uint8List(4 * 1024 * 1024 + 1));

    final outcome = await h.run('read', {
      'path': 'big.png',
    }, invocation: h.invocation(supportsImages: true));

    expect(outcome.outcome, ToolOutcome.failed);
    expect(textOf(outcome), 'Image is too large');
  });

  test('a missing image is the usual not found', () async {
    final outcome = await h.run('read', {
      'path': 'nope.png',
    }, invocation: h.invocation(supportsImages: true));

    expect(textOf(outcome), 'File not found: nope.png');
  });
}
