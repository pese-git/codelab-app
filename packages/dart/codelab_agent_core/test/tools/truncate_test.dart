import 'dart:convert';

import 'package:codelab_agent_core/src/tools/truncate.dart';
import 'package:test/test.dart';

String _lines(int count, {String prefix = 'line'}) =>
    [for (var i = 1; i <= count; i++) '$prefix $i'].join('\n');

void main() {
  test('head keeps whole lines up to 2000', () {
    final result = truncateHead(_lines(9312));

    expect(result.truncated, isTrue);
    expect(result.keptLines, 2000);
    expect(result.totalLines, 9312);
    expect(result.text.split('\n').last, 'line 2000');
  });

  test('tail keeps the last 2000 lines', () {
    final result = truncateTail(_lines(15000));

    expect(result.truncated, isTrue);
    expect(result.keptLines, 2000);
    expect(result.text.split('\n').first, 'line 13001');
    expect(result.text.split('\n').last, 'line 15000');
  });

  test('the byte limit cuts at a line boundary', () {
    final text = _lines(100, prefix: 'x' * 1000);

    final result = truncateHead(text);

    expect(utf8.encode(result.text).length, lessThanOrEqualTo(50 * 1024));
    // 9 lines of 1002 bytes, 42 of 1003 and 50 newlines: 51 194 bytes.
    expect(result.keptLines, 51);
    expect(result.text.split('\n').last, '${'x' * 1000} 51');
  });

  test('a first line longer than the byte limit is cut by characters', () {
    final text = 'é' * 40000;

    final result = truncateHead(text);

    expect(result.truncated, isTrue);
    expect(utf8.encode(result.text).length, lessThanOrEqualTo(50 * 1024));
    expect(result.text, endsWith(' [line truncated]'));
    expect(result.keptLines, 1);
  });

  test('text within limits is unchanged', () {
    final result = truncateHead('a\nb');

    expect(result.truncated, isFalse);
    expect(result.text, 'a\nb');
    expect(result.totalLines, 2);
  });

  test('null limits mean no limit', () {
    final result = truncateHead(_lines(3000), maxLines: null, maxBytes: null);

    expect(result.truncated, isFalse);
  });

  test('notice texts of §6.3.5', () {
    expect(
      TruncationNotices.read(first: 1, last: 2000, total: 9312),
      '[Showing lines 1-2000 of 9312. Use offset=2001 to continue.]',
    );
    expect(
      TruncationNotices.read(first: 1, last: 2000),
      '[Showing lines 1-2000. More lines may follow: use offset=2001.]',
    );
    expect(
      TruncationNotices.ls(shown: 500, total: 1834),
      '[Showing 500 of 1834 entries. Use a more specific path.]',
    );
    expect(
      TruncationNotices.search(),
      '[Showing first 100 matches. Narrow the pattern or the glob.]',
    );
    expect(
      TruncationNotices.exec(kept: 2000, total: 15000),
      '[Output truncated: showing the last 2000 lines of 15000.]',
    );
  });
}
