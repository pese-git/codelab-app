// Спайк 1.1 (D3, Q13): единая сборка модели эмулятора с запретом буфера обмена.
import 'package:xterm2_core/xterm2_core.dart';

/// Создаёт [Terminal] с политикой Q13: ни записи, ни чтения буфера обмена
/// через OSC 52 / 1337 / 5522.
///
/// Почему не «`clipboardDecoder: null` и всё»: при `null` `xterm2_core`
/// использует встроенный разбор base64 и вызывает `onClipboardStore`, если он
/// задан, а `TerminalView` выставляет его сам (`terminal.onClipboardStore ??=`
/// в `initState`) и пишет в системный буфер. Поэтому обработчики задаются
/// явно (не `null`) и ничего не делают: `??=` их не заменит.
///
/// [onOutput] — ответы эмулятора shell-у (DA, DSR, запросы цвета): их надо
/// писать в PTY, иначе приложения вроде `vim` зависают на ожидании ответа.
Terminal buildPolicyTerminal({
  required void Function(String data) onOutput,
  void Function(int cols, int rows)? onResize,
  void Function(String selector)? onClipboardAttempt,
}) {
  return Terminal(
    maxLines: 10000,
    allowITerm2ClipboardCapture: false,
    allowKittyClipboard: false,
    clipboardDecoder: (selector, data) {
      onClipboardAttempt?.call('decoder($selector)');
      return null;
    },
    onClipboardStore: (selector, text) =>
        onClipboardAttempt?.call('store($selector)'),
    onClipboardQuery: (selector) {
      onClipboardAttempt?.call('query($selector)');
      return null;
    },
    onOutput: onOutput,
    onResize: onResize == null ? null : (w, h, _, _) => onResize(w, h),
  );
}
