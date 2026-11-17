import 'package:codelab_desktop/core/platform/usage_csv_saver.dart';

/// Двойник порта [UsageCsvSaver] для тестов панели Usage (change
/// `add-desktop-usage-pane`, D5).
///
/// Почему: настоящий адаптер открывает системный диалог `file_selector` и
/// пишет файл, а тест экспорта проверяет только то, ЧТО presentation передал
/// порту и как отреагировал на исход.
///
/// Для чего: журнал [saved] вызовов `save` и настраиваемый [result].
///
/// Как использовать: `CodeLabTestBinding(usageCsvSaver: fake)`; после нажатия
/// `Export CSV` проверять `fake.saved`.
final class FakeUsageCsvSaver implements UsageCsvSaver {
  FakeUsageCsvSaver({this.result = const UsageCsvSaved()});

  /// Результат, который вернёт следующий `save`.
  UsageCsvSaveResult result;

  /// Все вызовы `save` в порядке вызова: предложенное имя и содержимое.
  final List<({String suggestedName, String csv})> saved = [];

  @override
  Future<UsageCsvSaveResult> save({
    required String suggestedName,
    required String csv,
  }) async {
    saved.add((suggestedName: suggestedName, csv: csv));
    return result;
  }
}
