import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/startup_preferences.dart';

/// Состояние строки «Reopen the last project and its tabs».
///
/// [saveFailed] — запись не удалась: переключатель остаётся в выбранном
/// положении, страница показывает предупреждение с «Retry».
final class StartupSettingsState {
  const StartupSettingsState({
    this.reopenLastProject = true,
    this.saveFailed = false,
  });

  final bool reopenLastProject;
  final bool saveFailed;
}

/// Владелец значения «открывать последний проект» на странице «General»
/// (design.md change `add-app-general-page`, D9).
///
/// Заглушка итерации 3 (красные тесты 3.5): состояние не меняется. Реализация
/// — задача 3.6. Создаётся на открытие страницы; рабочего пространства и
/// подключения не знает, поэтому переключение не трогает текущую работу.
class StartupSettingsCubit extends Cubit<StartupSettingsState> {
  StartupSettingsCubit({
    required StartupPreferences preferences,
    Logger? logger,
  }) : super(const StartupSettingsState());

  /// Читает сохранённое значение.
  Future<void> load() async {}

  /// Выбор пользователя: записывает [value].
  Future<void> select(bool value) async {}

  /// Повторяет последнюю неудавшуюся запись.
  Future<void> retry() async {}
}
