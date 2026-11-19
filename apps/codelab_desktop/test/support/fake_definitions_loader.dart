// Двойник загрузчика определений блока «Agent definitions» (change
// `add-settings-agents-modes`; design.md D7, D11): без файлов и платформы.
// Порт открытия каталогов — `FakeLocalFolderOpener` (D20.3).

import 'dart:async';

import 'package:codelab_desktop/features/settings/application/agent_definitions_port.dart';
import 'package:codelab_setup/codelab_setup.dart';

/// Загрузчик определений: возвращает [load] или то, что скажет [script].
final class FakeDefinitionsLoader {
  FakeDefinitionsLoader(this.load);

  AgentDefinitionsLoad load;

  /// Вызовы: токен отмены виден тесту.
  final tokens = <CancelToken?>[];

  /// Окружение агента каждого вызова: тест сверяет `env` профиля.
  final environments = <Map<String, String>>[];

  /// Сценарий вызова с номером от 1 (удержание, исключение); `null` — [load].
  Future<AgentDefinitionsLoad> Function(int call)? script;

  Future<AgentDefinitionsLoad> call({
    required AgentConfigSnapshot snapshot,
    required EditableSettings access,
    required Map<String, String> environment,
    CancelToken? cancel,
  }) {
    tokens.add(cancel);
    environments.add(environment);
    return script?.call(tokens.length) ?? Future.value(load);
  }
}

/// Пользовательский каталог определений теста.
const userAgentsDir = '/home/u/.codelab/agents';
