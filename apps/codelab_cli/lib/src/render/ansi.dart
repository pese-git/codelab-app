/// Управляющие последовательности, которые создаёт сам рендер CLI.
///
/// Почему: текст сессии приходит в терминал без управляющих символов
/// (`sanitizeTerminalText`), поэтому все последовательности вывода — только
/// отсюда; атрибуты не переходят через границу строки (§12.2.11, TUI-9,
/// TUI-11; design.md change `add-codelab-cli`, D6).
library;

/// Сброс атрибутов (SGR 0).
const sgrReset = '\x1b[0m';

/// Приглушённый текст (SGR 2) — мысли модели.
const sgrDim = '\x1b[2m';

/// Курсор в начало строки и очистка строки.
const clearCurrentLine = '\r\x1b[2K';

/// Очистка от курсора до конца экрана.
const clearToScreenEnd = '\x1b[J';

/// Очистка экрана и курсор в левый верхний угол (Ctrl+L).
const clearScreen = '\x1b[2J\x1b[H';

/// Курсор на [rows] строк вверх; `0` — пустая строка.
String cursorUp(int rows) => rows > 0 ? '\x1b[${rows}A' : '';

/// Курсор на [columns] позиций вправо; `0` — пустая строка.
String cursorForward(int columns) => columns > 0 ? '\x1b[${columns}C' : '';

/// [text] с атрибутами [sgr]: каждый непустой отрезок между `\n`
/// окружается [sgr] и [sgrReset], переводы строк остаются снаружи — так
/// атрибут не переходит на следующую строку (TUI-9).
String styleLines(String text, String sgr) => text
    .split('\n')
    .map((line) => line.isEmpty ? line : '$sgr$line$sgrReset')
    .join('\n');
