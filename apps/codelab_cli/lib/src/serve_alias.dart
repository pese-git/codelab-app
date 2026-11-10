/// Переходный алиас `codelab serve` → `codelab-agent serve`.
///
/// ЗАГЛУШКА шага «красные тесты» (change `retire-python-agent`, задачи 1.1–1.9):
/// сигнатуры фиксируют контракт для тестов, тела бросают [UnimplementedError].
/// Реализация — задачи 1.4 и 1.6 (design.md, D6–D10).
library;

/// Предупреждение об алиасе: одна строка в stderr до запуска (D9).
const serveAliasWarning =
    'codelab: "codelab serve" is deprecated and will be removed in a future '
    'release; use "codelab-agent serve" instead.';

/// Сообщение «бинарь не найден» (D9); `PATH` в него не печатается.
const serveAliasNotFound =
    'codelab: codelab-agent was not found next to codelab or in PATH; '
    'install it or run "codelab-agent serve" directly';

/// Сообщение о сбое `Process.start`; [message] — `ProcessException.message`
/// без аргументов (D9).
String serveAliasStartFailure(String message) =>
    throw UnimplementedError('serveAliasStartFailure');

/// Код выхода `codelab` по коду дочернего процесса: отрицательный код — смерть
/// от сигнала `N` → `128 + N` (D9).
int serveAliasExitCode(int childExitCode) =>
    throw UnimplementedError('serveAliasExitCode');

/// Ищет `codelab-agent` (D7): сначала каталог [codelabExecutable], затем
/// абсолютные записи [path]; кандидат, канонический путь которого совпадает с
/// каноническим путём [codelabExecutable], отбрасывается. `null` — не найден.
///
/// Чистая функция: файловая система приходит функциями [isExecutableFile] и
/// [canonicalize].
String? locateAgentExecutable({
  required String codelabExecutable,
  required String? path,
  required String pathSeparator,
  required bool isWindows,
  required bool Function(String file) isExecutableFile,
  required String Function(String file) canonicalize,
}) => throw UnimplementedError('locateAgentExecutable');
