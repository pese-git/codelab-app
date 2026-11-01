/// Сценарий модели для тестов встроенного агента (design.md change
/// `add-embedded-agent-mode`, D8).
///
/// Почему отдельная точка входа: основной барель и `io.dart` не принимают
/// функцию модели и сценарий, а импорт `testing.dart` разрешён сторожем только
/// тестам и драйверу фикстур `codelab test-scenario` (D3). Так сценарий не
/// попадает в релизную сборку структурно, без dart-define.
library;

export 'src/testing/scripted_opener.dart' show scriptedEmbeddedAgentOpener;
