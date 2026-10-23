/// A unified-diff fragment of one replacement for the model
/// (`agent-core-architecture` §6.4, `edit`, step 7): three lines of context
/// before and after, removed lines with `-`, added with `+`, at most
/// [maxLines] lines, then `...`. No LCS: the replacement is single and its
/// bounds are known.
///
/// [oldText] and [newText] are whole LF files; the replaced part starts at
/// [index] and has [oldLength] characters in the old file and
/// [newLength] in the new one.
String replacementFragment({
  required String oldText,
  required String newText,
  required int index,
  required int oldLength,
  required int newLength,
  int context = 3,
  int maxLines = 40,
}) {
  final oldLines = _lines(oldText);
  final newLines = _lines(newText);
  final first = lineOf(oldText, index);
  final lastOld = lineOf(oldText, index + oldLength - 1);
  final lastNew = newLength == 0
      ? first - 1
      : lineOf(newText, index + newLength - 1);
  final start = first - context < 0 ? 0 : first - context;
  final endOld = lastOld + context >= oldLines.length
      ? oldLines.length - 1
      : lastOld + context;
  final after = oldLines.sublist(lastOld + 1, endOld + 1);
  final before = oldLines.sublist(start, first);
  final removed = oldLines.sublist(first, lastOld + 1);
  final added = newLines.sublist(first, lastNew + 1);
  final body = [
    '@@ -${start + 1},${before.length + removed.length + after.length} '
        '+${start + 1},${before.length + added.length + after.length} @@',
    for (final line in before) ' $line',
    for (final line in removed) '-$line',
    for (final line in added) '+$line',
    for (final line in after) ' $line',
  ];
  return body.length > maxLines
      ? [...body.take(maxLines), '...'].join('\n')
      : body.join('\n');
}

/// 0-based line of the character at [offset].
int lineOf(String text, int offset) {
  var line = 0;
  for (var i = 0; i < offset && i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      line++;
    }
  }
  return line;
}

List<String> _lines(String text) {
  final lines = text.split('\n');
  if (text.endsWith('\n')) {
    lines.removeLast();
  }
  return lines;
}
