/// Предел длины значения секрета в байтах UTF-8 (64 КиБ).
///
/// Почему: настоящему ключу или токену хватает сотен байт; предел защищает
/// `secrets.yaml` (общий предел 1 МиБ) от случайной вставки файла в
/// `secret set` и держит запись быстрой (design.md change
/// `add-agent-secret-store`, D14).
const maxSecretValueBytes = 64 * 1024;

/// Проверка значения секрета, общая для `SecretAdmin` и `FileSecretStore`
/// (последний — защита в глубину: хранилище не доверяет вызывающему).
///
/// Почему отдельная функция: тексты причин должны совпадать у обеих проверок.
/// Возвращает английскую причину без самого значения или `null`, если значение
/// допустимо. Пустое значение проверяет вызывающий: для `file` оно не ошибка
/// формата.
///
/// Непарный суррогат отвергается, а не «чинится»: YAML-запись его не
/// воспроизводит, и молчаливая подмена значения испортила бы секрет.
String? secretValueProblem(String value) {
  if (value.contains('\n') || value.contains('\r')) {
    return 'secret value must be a single line';
  }
  if (_hasLoneSurrogate(value)) {
    return 'secret value is not valid Unicode (unpaired surrogate)';
  }
  // Число кодовых единиц — нижняя оценка числа байт: кодировать длинную
  // строку целиком незачем.
  if (value.length > maxSecretValueBytes ||
      _utf8Length(value) > maxSecretValueBytes) {
    return 'secret value is longer than 64 KiB';
  }
  return null;
}

bool _hasLoneSurrogate(String value) {
  final units = value.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (i + 1 < units.length &&
          units[i + 1] >= 0xdc00 &&
          units[i + 1] <= 0xdfff) {
        i++;
        continue;
      }
      return true;
    }
    if (unit >= 0xdc00 && unit <= 0xdfff) {
      return true;
    }
  }
  return false;
}

int _utf8Length(String value) {
  var bytes = 0;
  for (final rune in value.runes) {
    bytes += rune < 0x80
        ? 1
        : rune < 0x800
        ? 2
        : rune < 0x10000
        ? 3
        : 4;
  }
  return bytes;
}
