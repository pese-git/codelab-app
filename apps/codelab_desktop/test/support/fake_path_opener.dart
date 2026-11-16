// Двойники блока «Agent definitions» (задача 2.1 change
// `add-settings-agents-modes`; design.md D7, D8, D11): порт открытия пути и
// загрузчик определений без файлов и платформы.

import 'dart:async';

import 'package:codelab_desktop/core/platform/path_opener.dart';
import 'package:codelab_desktop/features/settings/application/agent_definitions_port.dart';
import 'package:codelab_setup/codelab_setup.dart';

/// Порт открытия пути: записывает вызовы, исход задаёт тест.
final class FakePathOpener implements PathOpener {
  /// Пути, переданные `open`.
  final files = <String>[];

  /// Вызовы `openDirectory`: путь и признак `create`.
  final directories = <({String path, bool create})>[];

  PathOpenOutcome fileOutcome = PathOpenOutcome.opened;

  /// Исход `openDirectory`; `null` — `created` при `create`, иначе `opened`.
  PathOpenOutcome? directoryOutcome;

  @override
  Future<PathOpenOutcome> open(String path) async {
    files.add(path);
    return fileOutcome;
  }

  @override
  Future<PathOpenOutcome> openDirectory(
    String path, {
    bool create = false,
  }) async {
    directories.add((path: path, create: create));
    return directoryOutcome ??
        (create ? PathOpenOutcome.created : PathOpenOutcome.opened);
  }

  bool get untouched => files.isEmpty && directories.isEmpty;
}

/// Загрузчик определений: возвращает [load] или то, что скажет [script].
final class FakeDefinitionsLoader {
  FakeDefinitionsLoader(this.load);

  AgentDefinitionsLoad load;

  /// Вызовы: токен отмены виден тесту.
  final tokens = <CancelToken?>[];

  /// Сценарий вызова с номером от 1 (удержание, исключение); `null` — [load].
  Future<AgentDefinitionsLoad> Function(int call)? script;

  Future<AgentDefinitionsLoad> call({
    required AgentConfigSnapshot snapshot,
    required EditableSettings access,
    required Map<String, String> environment,
    CancelToken? cancel,
  }) {
    tokens.add(cancel);
    return script?.call(tokens.length) ?? Future.value(load);
  }
}

/// Пользовательский каталог определений теста.
const userAgentsDir = '/home/u/.codelab/agents';
