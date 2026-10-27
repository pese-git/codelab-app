import 'dart:convert';

/// История отправленных промптов REPL.
///
/// Почему: ↑/↓ возвращают прошлые промпты и между запусками (U-07); модель
/// отделена от файла, чтобы редактор строки тестировался без диска
/// (design.md change `add-codelab-cli`, D5).
///
/// Как использовать: `History(entries)` из [HistoryStore.load]; редактор
/// вызывает [add] при отправке; после изменения REPL сохраняет [entries].
/// Повтор последней записи не добавляется; хранятся последние [limit].
final class History {
  History(Iterable<String> entries, {this.limit = 1000}) {
    for (final entry in entries) {
      add(entry);
    }
  }

  final int limit;
  final _entries = <String>[];

  List<String> get entries => List.unmodifiable(_entries);

  void add(String entry) {
    if (entry.trim().isEmpty ||
        (_entries.isNotEmpty && _entries.last == entry)) {
      return;
    }
    _entries.add(entry);
    if (_entries.length > limit) {
      _entries.removeRange(0, _entries.length - limit);
    }
  }
}

/// Хранилище истории между запусками; в процессе — файл `cli_history`
/// (`HistoryFile`), в тестах — память.
abstract interface class HistoryStore {
  Future<List<String>> load();

  Future<void> save(List<String> entries);
}

/// Строки файла истории: по записи на строку в виде JSON-строки — так
/// многострочный промпт и `\` переживают запись без своего экранирования.
String encodeHistory(List<String> entries) =>
    entries.map((entry) => '${jsonEncode(entry)}\n').join();

/// Записи файла истории; повреждённая строка пропускается, а не роняет
/// REPL.
List<String> decodeHistory(String text) => [
  for (final line in const LineSplitter().convert(text)) ?_decode(line),
];

String? _decode(String line) {
  try {
    final value = jsonDecode(line);
    return value is String ? value : null;
  } on FormatException {
    return null;
  }
}
