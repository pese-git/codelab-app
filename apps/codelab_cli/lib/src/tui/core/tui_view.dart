import 'dart:math';

import 'package:codelab_client_core/codelab_client_core.dart';

import '../../render/ansi.dart';
import '../../strings.dart';
import 'frame.dart';
import 'status_line.dart';
import 'tui_chrome.dart';
import 'tui_model.dart';

/// Кадр полноэкранного режима по модели экрана.
///
/// Почему: раскладку, ширину строк и сброс атрибутов решает одна чистая
/// функция — кадры проверяются модульными тестами как строки, а `dart_tui`
/// получает готовое содержимое (TUI-5, TUI-9, TUI-11; §12.2.7, «Раскладка
/// кадра»; design.md change `add-cli-tui`, D5).
///
/// Для чего: сверху вниз — транскрипт (прижат к низу окна), строки пикера
/// [TuiChrome.picker] (не выше половины экрана), строка «↓ N new» при
/// удержании, зона одобрения или композер (до 10 строк, дальше прокрутка
/// внутри), строка подсказок [TuiChrome.hints] (при высоте от 15 строк) и
/// статус-строка со значком хода [TuiChrome.spinner]. Ровно `size.rows`
/// строк, каждая — через `fitLine`.
///
/// Как использовать: `TuiApp.view` на каждом кадре; курсор кадра стоит в
/// композере после набранного, а при зоне одобрения скрыт.
Frame render(TuiModel model, TuiChrome chrome) {
  final width = model.size.columns;
  final color = model.color;
  final lines = <String>[];

  final picker = model.overlay == null
      ? const <String>[]
      : (chrome.picker ?? const <String>[]).take(model.size.rows ~/ 2).toList();
  final transcript = transcriptLines(model);
  final height = max(0, transcriptHeight(model) - picker.length);
  final window = _window(model, transcript, height);
  for (var i = window.length; i < height; i++) {
    lines.add('');
  }
  lines
    ..addAll(window)
    ..addAll(picker);

  if (!model.scroll.follow) {
    final count = newSinceHold(model);
    lines.add(count > 0 ? '↓ $count new' : '');
  }

  final (int, int)? cursor;
  if (approvalOf(model) case final prompt?) {
    lines.addAll(approvalLines(model, prompt));
    cursor = null;
  } else {
    cursor = _composer(model, lines);
  }

  if (hintsVisible(model)) {
    lines.add(_fitHints(chrome.hints ?? '', width));
  }

  final status = statusLine(statusInfoOf(model, chrome), width);
  lines.add(color ? '$sgrDim$status$sgrReset' : status);

  return Frame([
    for (final line in lines.take(model.size.rows))
      fitLine(line, width, color: color),
  ], cursor: cursor);
}

/// Строки композера в [lines]; результат — курсор кадра после набранного.
(int, int) _composer(TuiModel model, List<String> lines) {
  final width = model.size.columns;
  final composer = model.composer;
  final visible = composerRows(model);
  final first = composer.row >= visible ? composer.row - visible + 1 : 0;
  final composerTop = lines.length;
  for (var i = first; i < first + visible; i++) {
    lines.add(
      '${i == 0 ? inputPrompt : inputContinuation}${composer.lines[i]}',
    );
  }
  final cursorRow = composerTop + composer.row - first;
  final before = String.fromCharCodes(
    composer.lines[composer.row].runes.take(composer.column),
  );
  final cursorColumn = displayWidth(
    '${composer.row == 0 ? inputPrompt : inputContinuation}$before',
  );
  return (cursorRow, cursorColumn < width ? cursorColumn : width - 1);
}

/// Видимые строки транскрипта: последние при следовании, окно с [top]
/// при удержании.
List<String> _window(TuiModel model, List<String> lines, int height) {
  if (height <= 0) {
    return const [];
  }
  final scroll = model.scroll;
  final start = scroll.follow
      ? (lines.length > height ? lines.length - height : 0)
      : scroll.top.clamp(0, lines.isEmpty ? 0 : lines.length - 1);
  final end = start + height < lines.length ? start + height : lines.length;
  return lines.sublist(start, end);
}

/// Данные статус-строки модели: опции `mode` и `model` по id, затем по
/// категории (как `/mode` и `/model`), очередь kit и время хода.
StatusInfo statusInfoOf(TuiModel model, TuiChrome chrome) {
  final session = model.session;
  String? option(String name) {
    final options = session?.configOptions ?? const <ConfigOptionView>[];
    // Так же ищет `/mode` и `/model`: по id, затем по категории.
    return (options.where((o) => o.id == name).firstOrNull ??
            options.where((o) => o.category == name).firstOrNull)
        ?.currentValue;
  }

  final started = model.turnStartedAt;
  return StatusInfo(
    profile: model.profile,
    mode: option('mode'),
    model: option('model'),
    queued: session?.queue.length ?? 0,
    spinner: model.running ? chrome.spinner : null,
    elapsed: model.running && started != null
        ? chrome.now.difference(started)
        : null,
  );
}

/// Строка подсказок не шире экрана: лишние пункты отбрасываются с конца
/// целиком, чтобы не осталось обрезанной подписи вроде «exi».
String _fitHints(String hints, int width) {
  final entries = hints.split(' · ');
  while (entries.length > 1 && displayWidth(entries.join(' · ')) > width) {
    entries.removeLast();
  }
  return entries.join(' · ');
}
