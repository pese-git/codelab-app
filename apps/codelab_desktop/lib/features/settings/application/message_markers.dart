/// Часть сообщения после разреза по меткам: либо обычный [text], либо место
/// подставленного значения с номером [slot].
typedef MessagePart = ({String? text, int? slot});

/// Режет одно переведённое сообщение на текст и места подставленных значений.
///
/// Почему: фраза со стилизованным значением внутри (путь, id, имя секрета)
/// должна остаться одним сообщением каталога: порядок слов принадлежит
/// переводу, склейка кусков его ломает (`add-desktop-localization`, D5,
/// правило 7). Значения подставляются метками, а потом сообщение режется по
/// ним. Чистая функция без Flutter: её используют `messageSpans`
/// (presentation) и `keyStatusDetail` (application).
///
/// Метки — символы области Unicode Private Use: `<номер>`.
/// Разбор ищет только такую обрамлённую метку, поэтому числа в самом тексте
/// перевода («0600», «30 с») метками не считаются. Метка с номером вне
/// `0..count-1` не может быть выдана [build], поэтому показывается обычным
/// текстом (её номером), а не падает с `RangeError`.
///
/// Как использовать: [build] получает ровно [count] меток (по одной на
/// значение) и возвращает сообщение каталога; метки вставляются в него как
/// значения плейсхолдеров. Результат — подряд идущие части; значение,
/// которого нет в переводе, в результате не появляется.
List<MessagePart> splitMessage(
  String Function(List<String> markers) build,
  int count,
) {
  final message = build([for (var i = 0; i < count; i++) '$i']);
  final parts = <MessagePart>[];
  var cursor = 0;
  for (final match in RegExp('(\\d+)').allMatches(message)) {
    if (match.start > cursor) {
      parts.add((text: message.substring(cursor, match.start), slot: null));
    }
    final slot = int.parse(match.group(1)!);
    parts.add(
      slot < count
          ? (text: null, slot: slot)
          : (text: match.group(1), slot: null),
    );
    cursor = match.end;
  }
  if (cursor < message.length) {
    parts.add((text: message.substring(cursor), slot: null));
  }
  return parts;
}
