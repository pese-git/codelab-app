import 'package:fluent_ui/fluent_ui.dart';

/// Ключи диалога ссылки OSC 8 (контракт тестов `terminal_link_test.dart`).
const terminalLinkDialogKey = ValueKey('terminal-link-dialog');
const terminalLinkAddressKey = ValueKey('terminal-link-address');
const terminalLinkOpenKey = ValueKey('terminal-link-open');
const terminalLinkCancelKey = ValueKey('terminal-link-cancel');

/// Сообщение отказа для схем, кроме `http`/`https` (spec `integrated-terminal`
/// «Ссылки в выводе терминала»).
const terminalLinkRefusal = 'Only http and https links can be opened.';

/// Показывает диалог подтверждения ссылки OSC 8 и возвращает `true`, только
/// если пользователь нажал «Open».
///
/// Почему: текст ссылки задаёт процесс и может не совпадать с адресом, поэтому
/// диалог показывает ПОЛНЫЙ адрес как есть, без обрезки и подписи (D3, Q14).
///
/// Для чего: виджет только получает решение пользователя; опасно ли действие,
/// решил application ([canOpen] из `terminalLinkDecision`). При `canOpen:
/// false` кнопки «Open» нет. Отмена, Esc и клик по фону дают `false`.
///
/// Как использовать: `await showTerminalLinkDialog(context, uri: u, canOpen: c)`.
Future<bool> showTerminalLinkDialog(
  BuildContext context, {
  required String uri,
  required bool canOpen,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      key: terminalLinkDialogKey,
      title: const Text('Open link?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(uri, key: terminalLinkAddressKey),
          if (!canOpen) ...[
            const SizedBox(height: 8),
            const Text(terminalLinkRefusal),
          ],
        ],
      ),
      actions: [
        Button(
          key: terminalLinkCancelKey,
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        if (canOpen)
          FilledButton(
            key: terminalLinkOpenKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open'),
          ),
      ],
    ),
  );
  return result ?? false;
}
