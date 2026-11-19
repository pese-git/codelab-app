import 'package:flutter/widgets.dart';

import '../application/message_markers.dart';

/// Собирает фрагменты текста из одного переведённого сообщения, в которое
/// подставлены стилизованные значения (путь, команда, id).
///
/// Почему: фраза с моноширинным путём внутри не должна склеиваться из
/// кусков `'Saved to ' + path + ' and shared…'`. Порядок слов у перевода
/// другой, и склейка ломает его (`add-desktop-localization`, D5, правило 7,
/// сценарий «Команда в переведённой фразе»). Сообщение остаётся одним, а
/// стиль получают только подставленные значения.
///
/// Разрез по меткам делает чистая `splitMessage` (application): числа в
/// самом тексте перевода («0600», «30 с») метками не считаются, порядок
/// значений определяет перевод, а метка вне диапазона `values` выводится
/// обычным текстом без `RangeError` (задача 4.4).
///
/// Как использовать: [build] получает только метки (по одной на значение) и
/// вызывает сообщение каталога (`l10n.addProfileSubtitle`); [values] —
/// фрагменты в том же порядке, они встают на место меток. Остальной текст —
/// обычные `TextSpan`-ы без стиля. Если перевод не использовал плейсхолдер,
/// значение пропадает.
List<InlineSpan> messageSpans(
  String Function(List<String> markers) build,
  List<InlineSpan> values,
) => [
  for (final part in splitMessage(build, values.length))
    if (part.slot case final slot?) values[slot] else TextSpan(text: part.text),
];
