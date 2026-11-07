/// Порядок записи MCP-сервера: секрет, затем конфиг (`dart-agent-and-clients`
/// §12.4.6; design.md change `add-provider-setup-ui`, D9, D11 «Сверка с
/// кодом»; SETUP-5, SETUP-6).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigLayer, ConfigSnapshot, UpsertMcpServer;

import '../access/settings_access.dart';
import '../config/agent_config_store.dart';
import '../provider/provider_keys.dart';
import '../provider/provider_remover.dart' show SecretDeletion;
import '../provider/provider_setup_committer.dart' show KeyRollback;
import 'mcp_layers.dart';
import 'mcp_server_draft.dart';

/// Почему запись или удаление отклонены до обращения к файлу и хранилищу.
enum McpServerRefusal {
  /// Сервера нет в эффективном конфиге.
  unknownServer,

  /// Сервер определён слоем 3 или переопределён «Disable here»: файл слоя
  /// клиенты не пишут (SETUP-3).
  notEditable,

  /// «Disable here» применимо только к серверу слоя 3.
  notProject,

  /// «Enable here»: у сервера нет переопределения `{name, enabled: false}`
  /// в `projectLocal`.
  notDisabledHere,

  /// Файл слоя сервера не читается: основы для записи нет.
  layerUnreadable,

  /// Профиль не допускает запись в `projectLocal` (папка проекта неизвестна,
  /// `EditableSettings.targets` без этой цели): D5, SETUP-3.
  noProjectTarget,
}

/// Итог [McpServerCommitter.commit].
sealed class McpServerCommitOutcome {
  const McpServerCommitOutcome();
}

/// Записано. [replacedSecrets] — секреты, заменённые под тем же именем:
/// работающий агент держит прежнее значение до перезапуска сервера.
final class McpServerCommitted extends McpServerCommitOutcome {
  const McpServerCommitted({
    required this.saved,
    required this.replacedSecrets,
  });

  final ConfigSaved saved;
  final List<String> replacedSecrets;

  @override
  String toString() => 'McpServerCommitted(${replacedSecrets.length} replaced)';
}

/// Черновик не прошёл проверку: ничего не записано.
final class McpServerInvalid extends McpServerCommitOutcome {
  const McpServerInvalid(this.problems);

  final List<McpDraftProblem> problems;

  @override
  String toString() => 'McpServerInvalid(${problems.length})';
}

/// Секреты с такими именами появились после шага формы (другой процесс,
/// `secret set`, сервер `GitHub` при имени `github`); ничего не записано,
/// форма предлагает «Replace it» или другое имя.
final class McpSecretAppeared extends McpServerCommitOutcome {
  const McpSecretAppeared(this.names);

  final List<String> names;

  @override
  String toString() => 'McpSecretAppeared(${names.length})';
}

/// Хранилище отказало; конфиг не писался, созданные секреты откачены.
/// [reason] — текст без значения.
final class McpSecretNotStored extends McpServerCommitOutcome {
  const McpSecretNotStored(this.reason);

  final String reason;

  @override
  String toString() => 'McpSecretNotStored';
}

/// Конфиг не записан: [outcome] — конфликт, отказ валидатора или
/// inline-секрет; `null` — исключение `apply`, тогда [errorType] — имя его
/// типа (текст исключения никуда не идёт, SETUP-1).
final class McpServerNotSaved extends McpServerCommitOutcome {
  const McpServerNotSaved({
    required this.outcome,
    required this.errorType,
    required this.replacedSecrets,
    required this.rollback,
  });

  final ConfigSaveOutcome? outcome;
  final String? errorType;
  final List<String> replacedSecrets;
  final KeyRollback rollback;

  @override
  String toString() =>
      'McpServerNotSaved(${outcome ?? errorType}, '
      'rollback: ${rollback.name})';
}

/// Итог записи одной правки сервера без секретов (переключатель `enabled`,
/// «Disable here», «Enable here»).
sealed class McpServerWriteOutcome {
  const McpServerWriteOutcome();
}

/// Записано.
final class McpServerWritten extends McpServerWriteOutcome {
  const McpServerWritten(this.saved);

  final ConfigSaved saved;

  @override
  String toString() => 'McpServerWritten';
}

/// Не записано: [outcome] — конфликт, отказ валидатора или inline-секрет;
/// `null` — исключение `apply`, [errorType] — имя его типа.
final class McpServerNotWritten extends McpServerWriteOutcome {
  const McpServerNotWritten({required this.outcome, required this.errorType});

  final ConfigSaveOutcome? outcome;
  final String? errorType;

  @override
  String toString() => 'McpServerNotWritten(${outcome ?? errorType})';
}

/// Отклонено до записи: файлы и хранилище не тронуты.
final class McpServerRefused extends McpServerWriteOutcome {
  const McpServerRefused(this.reason);

  final McpServerRefusal reason;

  @override
  String toString() => 'McpServerRefused(${reason.name})';
}

/// Записывает MCP-сервер: секреты, затем конфиг, с откатом созданных секретов.
///
/// Почему порядок «секрет → конфиг»: в обратном получился бы конфиг со
/// ссылкой на несуществующий секрет, а сервер с такой ссылкой не стартует.
/// Заменённый секрет не откатывается — прежнего значения клиент не знает
/// (D9). Порт секретов — тот же `ProviderKeys` (`stored`, `write`, `delete`
/// работают с любым именем), второго порта нет.
///
/// Для чего: единственное место порядка записи сервера для app и CLI. Правка
/// и переключатель пишут СЫРОЙ элемент слоя целиком с изменённым полем:
/// `UpsertMcpServer` заменяет элемент по `name`, и `{name, enabled}` стёр бы
/// команду, URL, `env` и `headers` (D11).
///
/// Как использовать: `commit(draft, base)` с `base` — снимок слоя из
/// `AgentConfigSnapshot.layers`; `setEnabled`, `disableHere` — по снимку.
/// Конфликт файла возвращается исходом, автоповтора нет (SETUP-6).
final class McpServerCommitter {
  McpServerCommitter({
    required AgentConfigStore config,
    required ProviderKeys keys,
  }) : _config = config,
       _keys = keys;

  final AgentConfigStore _config;
  final ProviderKeys _keys;

  /// Записывает [draft] в слой [base]. [replaceSecrets] — имена, которые
  /// пользователь выбрал заменить («Replace it»): для них перепроверка
  /// `stored` не выполняется.
  Future<McpServerCommitOutcome> commit(
    McpServerDraft draft,
    ConfigSnapshot base, {
    Set<String> replaceSecrets = const {},
  }) async {
    final problems = draft.validate();
    if (problems.isNotEmpty) {
      return McpServerInvalid(problems);
    }
    final secrets = draft.secretsToWrite();
    // Имена проверяются все до первой записи: частичной записи нет.
    final appeared = <String>[];
    for (final name in secrets.keys) {
      if (!replaceSecrets.contains(name) && await _keys.stored(name)) {
        appeared.add(name);
      }
    }
    if (appeared.isNotEmpty) {
      return McpSecretAppeared(appeared);
    }

    final created = <String>[];
    final replaced = <String>[];
    for (final MapEntry(:key, :value) in secrets.entries) {
      switch (await _keys.write(key, value)) {
        case ProviderKeyCreated():
          created.add(key);
        case ProviderKeyReplaced():
          // Включая гонку в окне после перепроверки: заменой считается любой
          // `SecretUpdated`, откатывать нечего (D9).
          replaced.add(key);
        case ProviderKeyRefused(:final reason):
          await _rollback(created);
          return McpSecretNotStored(reason);
      }
    }

    ConfigSaveOutcome? outcome;
    String? errorType;
    try {
      outcome = await _config.apply(base, draft.toEdits());
    } on Object catch (error) {
      // Любое исключение: иначе созданные секреты остались бы сиротами. Текст
      // исключения мог процитировать значение — берём только тип.
      errorType = error.runtimeType.toString();
    }
    if (outcome case final ConfigSaved saved) {
      return McpServerCommitted(saved: saved, replacedSecrets: replaced);
    }
    return McpServerNotSaved(
      outcome: outcome,
      errorType: errorType,
      replacedSecrets: replaced,
      rollback: await _rollback(created),
    );
  }

  /// Удаляет созданные секреты; сбой хранилища не теряет исход записи.
  Future<KeyRollback> _rollback(List<String> created) async {
    if (created.isEmpty) {
      return KeyRollback.none;
    }
    var failed = false;
    for (final name in created) {
      try {
        final deletion = await _keys.delete(name);
        failed = failed || deletion == SecretDeletion.failed;
      } on Object {
        failed = true;
      }
    }
    return failed ? KeyRollback.failed : KeyRollback.deleted;
  }

  /// Переключатель `enabled`: сырой элемент слоя сервера [name] целиком с
  /// изменённым `enabled`. Сервер слоя 3 и «disabled here» — отказ
  /// `notEditable` (для них «Disable here» и «Enable here»).
  Future<McpServerWriteOutcome> setEnabled(
    AgentConfigSnapshot snapshot,
    String name, {
    required bool enabled,
  }) async {
    final server = effectiveMcpServer(snapshot, name);
    if (server == null) {
      return const McpServerRefused(McpServerRefusal.unknownServer);
    }
    if (server.layer == ConfigLayer.project || server.disabledHere) {
      return const McpServerRefused(McpServerRefusal.notEditable);
    }
    final base = snapshot.layers[server.layer];
    if (base == null) {
      return const McpServerRefused(McpServerRefusal.layerUnreadable);
    }
    return _write(base, [
      UpsertMcpServer({...server.element, 'enabled': enabled}),
    ]);
  }

  /// «Disable here» (Q21): `{name, enabled: false}` в `projectLocal` для
  /// сервера слоя 3; проектный файл не меняется.
  ///
  /// [access] — доступ профиля (D5): запись допустима, только если среди
  /// `EditableSettings.targets` есть `projectLocal`; иначе отказ
  /// `noProjectTarget` до обращения к файлу (SETUP-3). Остальные записи
  /// (`commit`, `setEnabled`) идут в слой, который вызывающий взял из тех же
  /// `targets`. Нечитаемый `config.local.yaml` (слоя нет в снимке) — отказ
  /// `layerUnreadable`, а не конфликт записи.
  Future<McpServerWriteOutcome> disableHere(
    AgentConfigSnapshot snapshot,
    String name, {
    required EditableSettings access,
  }) async {
    if (!access.targets.any((t) => t.layer == ConfigLayer.projectLocal)) {
      return const McpServerRefused(McpServerRefusal.noProjectTarget);
    }
    final server = effectiveMcpServer(snapshot, name);
    if (server == null) {
      return const McpServerRefused(McpServerRefusal.unknownServer);
    }
    if (server.layer != ConfigLayer.project) {
      return const McpServerRefused(McpServerRefusal.notProject);
    }
    // Отсутствующий файл читается как пустой слой (`fingerprint: null`);
    // слой, которого нет в снимке, — файл не разобрался.
    final base = snapshot.layers[ConfigLayer.projectLocal];
    if (base == null) {
      return const McpServerRefused(McpServerRefusal.layerUnreadable);
    }
    return _write(base, [
      UpsertMcpServer({'name': name, 'enabled': false}),
    ]);
  }

  Future<McpServerWriteOutcome> _write(
    ConfigSnapshot base,
    List<UpsertMcpServer> edits,
  ) async {
    try {
      final outcome = await _config.apply(base, edits);
      return outcome is ConfigSaved
          ? McpServerWritten(outcome)
          : McpServerNotWritten(outcome: outcome, errorType: null);
    } on Object catch (error) {
      return McpServerNotWritten(
        outcome: null,
        errorType: error.runtimeType.toString(),
      );
    }
  }
}
