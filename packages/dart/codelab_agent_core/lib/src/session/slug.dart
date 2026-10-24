import 'dart:convert';

import '../util/posix_path.dart';

/// Имя каталога журналов одной рабочей папки (`agent-core-architecture`
/// §8.9).
///
/// Почему читаемая часть и хеш: по последним двум сегментам человек находит
/// каталог глазами, а хеш полного пути исключает коллизии (`/a/b-c` и
/// `/a-b/c`). Слаг необратим, поэтому истинный `cwd` хранится в заголовке.
///
/// Как использовать: файловое хранилище раскладывает журналы по
/// `<root>/<cwdSlug(cwd)>/`; MVP поддерживает только POSIX-пути.
String cwdSlug(String cwd) {
  final path = normalizePath('/', cwd) ?? cwd;
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  final readable = segments.isEmpty
      ? 'root'
      : segments.skip(segments.length < 2 ? 0 : segments.length - 2).join('-');
  var tail = readable
      .replaceAll(RegExp('[^A-Za-z0-9._-]'), '-')
      .replaceAll(RegExp('-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (tail.length > 48) {
    tail = tail.substring(0, 48);
  }
  return '$tail-${fnv1a32Hex(utf8.encode(path))}';
}

/// FNV-1a 32 бит, 8 шестнадцатеричных цифр в нижнем регистре.
///
/// Почему FNV-1a: несколько строк без зависимостей. Умножение на простое
/// число FNV `0x01000193` разбито на `0x193` и `0x01000000`: прямое
/// произведение 32-битного числа на него доходит до 2^56 и в dart2js теряет
/// младшие биты (точность double — 53 бита). Части меньше 2^42, поэтому
/// результат одинаков на Dart VM и в JavaScript.
String fnv1a32Hex(List<int> bytes) {
  var h = 0x811c9dc5;
  for (final b in bytes) {
    h ^= b;
    h = (h * 0x193 + (h & 0xff) * 0x01000000) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}
