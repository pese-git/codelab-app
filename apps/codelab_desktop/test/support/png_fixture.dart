import 'dart:convert';
import 'dart:typed_data';

// Минимальный PNG с корректной CRC: заголовок объявляет размер, а данных
// изображения почти нет — «бомба», которую нельзя декодировать.
Uint8List png(int width, int height) {
  final table = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });
  int crc(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return c ^ 0xFFFFFFFF;
  }

  List<int> u32(int v) =>
      [v >> 24, v >> 16, v >> 8, v].map((e) => e & 0xFF).toList();
  List<int> chunk(String type, List<int> data) {
    final body = [...ascii.encode(type), ...data];
    return [...u32(data.length), ...body, ...u32(crc(body))];
  }

  return Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ...chunk('IHDR', [...u32(width), ...u32(height), 8, 0, 0, 0, 0]),
    ...chunk('IDAT', [0x78, 0x9C, 0x03, 0x00, 0x00, 0x00, 0x00, 0x01]),
    ...chunk('IEND', const []),
  ]);
}
