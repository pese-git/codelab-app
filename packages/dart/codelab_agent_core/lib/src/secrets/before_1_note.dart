/// Строка о 1.0 для справок `serve`, `secret` и `codelab --help` (R8-7,
/// design.md change `add-config-literal-secrets-and-migrate`, D13).
///
/// Почему здесь: до 1.0 вывод инструментов, промпты и журналы сессий не
/// редактируются, поэтому секреты в них уходят провайдеру и в файлы сессий как
/// есть. Текст один для `codelab` и `codelab-agent`, иначе бинари разойдутся;
/// живёт в ядре: его берут оба бинаря и web-безопасный барель
/// `codelab_setup`, которым пользуется argv `codelab` (сторож запрещает там
/// `codelab_setup/io.dart`). Как использовать:
/// добавить строку в справку своей команды, не меняя текст.
const before1Note =
    'Note: before 1.0, tool output, prompts and session logs are not '
    'redacted: secrets they contain reach the model provider and session '
    'files as is.';
