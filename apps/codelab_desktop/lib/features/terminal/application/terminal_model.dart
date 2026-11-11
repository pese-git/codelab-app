import 'package:xterm2_core/xterm2_core.dart';

/// Тип фабрики модели вкладки; Cubit принимает её параметром для тестов.
typedef TerminalModelFactory =
    Terminal Function({
      required void Function(String data) onOutput,
      void Function(int columns, int rows)? onResize,
    });

/// Создаёт модель эмулятора вкладки с политикой буфера обмена (Q13, D3).
///
/// Почему не «обработчики не заданы»: при `clipboardDecoder: null`
/// `xterm2_core` разбирает base64 сам, а `TerminalView.initState` ставит
/// `onClipboardStore ??=` и `onClipboardQuery ??=` на системный буфер: OSC 52
/// писал бы в буфер, а его содержимое уходило бы процессу (D15, п. 1).
/// Поэтому обработчики заданы явно (не `null`) и ничего не делают, а запись
/// OSC 52 отклоняется на разборе.
///
/// Для чего: единственное место создания `Terminal` в app; вывод процесса —
/// недоверенный поток. `onOpenUrl` не задан намеренно: адрес по OSC 1337
/// `OpenURL` не открывается, только через `onHyperlinkTap` и диалог (Q14).
///
/// Как использовать: [onOutput] получает и ввод пользователя, и ответы
/// эмулятора процессу (DA, DSR, запросы цвета) — его надо писать в PTY;
/// [onResize] — новый размер в колонках и строках.
Terminal terminalModel({
  required void Function(String data) onOutput,
  void Function(int columns, int rows)? onResize,
}) => Terminal(
  maxLines: 10000,
  clipboardDecoder: (_, _) => null,
  allowITerm2ClipboardCapture: false,
  allowKittyClipboard: false,
  onClipboardStore: (_, _) {},
  onClipboardQuery: (_) => null,
  onOutput: onOutput,
  onResize: onResize == null
      ? null
      : (columns, rows, _, _) => onResize(columns, rows),
);
