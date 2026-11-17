import 'usage_pane_data.dart';

/// CSV журнала, показанного в панели Usage (design.md change
/// `add-desktop-usage-pane`, D5, Q2).
///
/// Почему в application: формат и защита от формульной инъекции — политика,
/// запись файла — порт `UsageCsvSaver` в `lib/core/platform/`.
///
/// Как использовать: `buildUsageCsv(data)` при `data.canExport`; результат
/// сохраняется как UTF-8 без BOM.
///
/// Заглушка задачи 1.4 (красные тесты `usage_csv_test.dart`).
String buildUsageCsv(UsagePaneData data) => throw UnimplementedError();
