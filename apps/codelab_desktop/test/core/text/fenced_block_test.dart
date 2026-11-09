// Снятие одного внешнего ограждения (задача 6.1i-1, Q34/Q37, D27 change
// `add-provider-setup-ui`): те же случаи, что у `McpSettingsCubit._unfenced`
// (6.1e). `null` — «не один огороженный блок, текст как есть».

import 'package:codelab_desktop/core/text/fenced_block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('unfenceSingleBlock', () {
    test('strips a fence with a language word', () {
      expect(
        unfenceSingleBlock('```text\nMCP servers (1)\n  a  ok\n```'),
        'MCP servers (1)\n  a  ok',
      );
    });

    test('strips a fence without a language word', () {
      expect(unfenceSingleBlock('```\nline 1\nline 2\n```'), 'line 1\nline 2');
    });

    test('ignores blank lines around the block', () {
      expect(unfenceSingleBlock('\n  \n```text\nbody\n```\n\n  \n'), 'body');
    });

    test('handles CRLF line breaks', () {
      expect(unfenceSingleBlock('```text\r\none\r\ntwo\r\n```'), 'one\ntwo');
    });

    test('prose before or after the block is left as is', () {
      expect(unfenceSingleBlock('Here:\n```text\nbody\n```'), isNull);
      expect(unfenceSingleBlock('```text\nbody\n```\nDone.'), isNull);
    });

    test('two blocks are left as is', () {
      expect(unfenceSingleBlock('```text\na\n```\n\n```text\nb\n```'), isNull);
    });

    test('only the opening line is left as is', () {
      expect(unfenceSingleBlock('```text\nbody still streaming'), isNull);
    });

    test('plain text and a single line are left as is', () {
      expect(unfenceSingleBlock('Just an answer.'), isNull);
      expect(unfenceSingleBlock('```'), isNull);
    });
  });
}
