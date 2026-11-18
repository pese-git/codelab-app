import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, ConnectionProfile;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'agent_defaults_state.dart';
import 'provider_settings_session.dart';

export 'agent_defaults_state.dart';

/// Блок «Agent defaults» страницы «General» (design.md change
/// `add-app-general-page`, D7).
///
/// Заглушка итерации 2 (красные тесты 2.3): состояние всегда
/// [AgentDefaultsLoading], методы ничего не делают. Реализация — задача 2.4
/// по образцу `AgentsModesCubit`.
class AgentDefaultsCubit extends Cubit<AgentDefaultsState> {
  AgentDefaultsCubit({
    required ClientWorkspace workspace,
    required Future<ConnectionProfile> Function() defaultProfile,
    required ProviderSettingsOpener open,
    required Map<String, String> environment,
    required String? codelabHome,
    required String? Function() projectDirectory,
    Logger? logger,
  }) : super(const AgentDefaultsLoading());

  /// Читает доступ и снимок конфига.
  Future<void> reload() async {}

  /// Применяет введённый текст [raw] к ключу [key]: `SettingsRegistry.
  /// parseCliValue`, затем одна запись в слой `user`. Переключатель и список
  /// передают `true`/`false` и значение из `enumValues`; пустая строка
  /// сбрасывает ключ слоя `user`.
  Future<void> submit(String key, String raw) async {}
}
