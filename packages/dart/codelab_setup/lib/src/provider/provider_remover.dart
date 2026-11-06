/// Удаление провайдера из конфига (`dart-agent-and-clients` §12.4.5, шаг 6;
/// design.md change `add-provider-setup-ui`, D10; SETUP-24).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigEdit, ConfigLayer, RemoveTable, SecretNames, SetValue;

import '../config/agent_config_store.dart';
import '../config/config_values.dart';
import '../views/provider_entry_view.dart';

/// Итог удаления секрета хранилищем.
enum SecretDeletion {
  /// Секрет был и удалён.
  deleted,

  /// Секрета уже не было.
  notSet,

  /// Хранилище отказало (только чтение, недоступно).
  failed,
}

/// Удаляет секрет по имени; порт основного бареля.
///
/// Почему функция, а не `SecretAdmin`: типы администрирования живут в
/// `codelab_agent_io` и основному бареле недоступны; адаптер composition root
/// превращает `ClientSecretAccess.admin.delete` в [SecretDeletion]
/// (`secretDeleterOf` в `lib/io.dart`). Значение секрета не нужно.
typedef SecretDeleter = Future<SecretDeletion> Function(String name);

/// Что стало с секретом провайдера после удаления.
enum SecretCleanup {
  /// Удаление не запрашивалось или секрет не принадлежит провайдеру.
  notRequested,

  /// Секрет удалён.
  deleted,

  /// Секрета уже не было.
  alreadyAbsent,

  /// Провайдер удалён, а секрет остался: хранилище отказало или свежий снимок
  /// конфига получить не удалось (без него безопасность удаления не доказана).
  failed,

  /// После записи в конфиге нашлась ссылка на секрет (другой слой, правка
  /// другого процесса): секрет не удалён (SETUP-24).
  stillReferenced,
}

/// Почему удаление отклонено до записи.
enum ProviderRemovalRefusal {
  /// Провайдера нет в конфиге.
  unknownProvider,

  /// Провайдер задан не только в слоях `user` и `projectLocal` (слой 3,
  /// `--config`, окружение): правкой файлов его не убрать.
  notEditable,

  /// Листья провайдера лежат в нескольких слоях: одним `apply` пишется один
  /// слой, а половина записи оставила бы неполного провайдера.
  multipleLayers,

  /// Файл слоя провайдера не читается: основы для записи нет.
  layerUnreadable,

  /// Это последний провайдер: агенту нужен хотя бы один (§12.4.5, шаг 6).
  lastProvider,

  /// Удаляется провайдер модели по умолчанию, а новая не выбрана.
  newDefaultRequired,

  /// Новая модель по умолчанию указывает на удаляемого или неизвестного
  /// провайдера.
  newDefaultInvalid,

  /// `agent.default_model` задан в слое выше слоя провайдера: правка нижнего
  /// слоя не сменит итоговую модель.
  defaultOverridden,
}

/// Итог [ProviderRemover.remove].
sealed class ProviderRemovalOutcome {
  const ProviderRemovalOutcome();
}

/// Провайдер удалён из конфига ([saved]); [secret] — судьба его ключа.
final class ProviderRemoved extends ProviderRemovalOutcome {
  const ProviderRemoved({required this.saved, required this.secret});

  final ConfigSaved saved;
  final SecretCleanup secret;

  @override
  String toString() => 'ProviderRemoved(${secret.name})';
}

/// Запись не состоялась ([outcome]: конфликт, отказ валидатора); секрет не
/// тронут (SETUP-24), автоповтора нет (SETUP-6).
final class ProviderRemovalNotSaved extends ProviderRemovalOutcome {
  const ProviderRemovalNotSaved(this.outcome);

  final ConfigSaveOutcome outcome;

  @override
  String toString() => 'ProviderRemovalNotSaved($outcome)';
}

/// Удаление отклонено до записи: файл и хранилище не тронуты.
final class ProviderRemovalRefused extends ProviderRemovalOutcome {
  const ProviderRemovalRefused(this.reason);

  final ProviderRemovalRefusal reason;

  @override
  String toString() => 'ProviderRemovalRefused(${reason.name})';
}

/// Можно ли править или удалять провайдера [id] записью конфига.
///
/// Почему одна функция: правило «провайдер лежит в одном редактируемом слое,
/// файл которого читается» общее для удаления ([ProviderRemover.remove]) и
/// правки в мастере (`ProviderSetupFlow`, `ConfirmSave` при `editing`); две
/// копии расходились бы (ревью итерации 3).
///
/// Отказы: `unknownProvider` (нет в снимке), `notEditable` (лист в слое 3,
/// `--config` или окружении), `multipleLayers` (листья в нескольких слоях: один
/// `apply` пишет один слой), `layerUnreadable` (файл слоя не читается).
/// `null` — править можно.
ProviderRemovalRefusal? providerEditRefusal(
  AgentConfigSnapshot snapshot,
  String id,
) {
  if (!providerIdsOf(snapshot).contains(id)) {
    return ProviderRemovalRefusal.unknownProvider;
  }
  final origins = providerOriginsOf(snapshot, id);
  if (origins.isEmpty || origins.any((o) => !o.editable)) {
    return ProviderRemovalRefusal.notEditable;
  }
  if (origins.map((o) => o.kind).toSet().length > 1) {
    return ProviderRemovalRefusal.multipleLayers;
  }
  if (snapshot.layers[origins.single.layer!] == null) {
    return ProviderRemovalRefusal.layerUnreadable;
  }
  return null;
}

/// Порядок удаления провайдера: одна запись конфига, затем (по желанию)
/// секрет.
///
/// Почему отдельный класс: порядок общий для app и CLI и важен для целостности
/// данных. Правки идут ОДНИМ `apply` — `RemoveTable` и новая модель по
/// умолчанию, — иначе между ними конфиг остался бы без допустимой
/// `agent.default_model`. Секрет удаляется только после `ConfigSaved`
/// (SETUP-24): отказ записи не должен оставить провайдера без ключа.
///
/// Для чего: единственное место этой логики; страница передаёт выбор
/// пользователя («Also delete the stored key», «New default model»).
///
/// Как использовать: `ProviderRemover(config: store, deleteSecret: deleter)`,
/// затем `remove(snapshot, providerId: …, newDefaultModel: …, deleteStoredKey:
/// …)`. Проверки выполняются до записи; при `ProviderRemovalRefused` ничего
/// не изменено. [ownedSecretName] даёт значение по умолчанию флажка.
final class ProviderRemover {
  ProviderRemover({
    required AgentConfigStore config,
    required SecretDeleter deleteSecret,
  }) : _config = config,
       _deleteSecret = deleteSecret;

  final AgentConfigStore _config;
  final SecretDeleter _deleteSecret;

  /// Имя секрета, которое можно удалить вместе с провайдером [providerId]:
  /// `api_key_secret` равен `codelab/<id>` (собственный секрет, его создал
  /// мастер) и другие провайдеры на него не ссылаются. Иначе `null` — флажок
  /// «Also delete the stored key» не предлагается: общий и чужой секрет не
  /// удаляются (SETUP-5, SETUP-24).
  static String? ownedSecretName(
    AgentConfigSnapshot snapshot,
    String providerId,
  ) {
    final name = providerString(snapshot, providerId, 'api_key_secret');
    if (name == null ||
        name != SecretNames.suggestFor('providers.$providerId.api_key')) {
      return null;
    }
    // Ссылка `${secret:<name>}` может стоять в любой строке конфига (заголовки
    // и `env` MCP-серверов, заголовки других провайдеров), а `api_key_secret`
    // другого провайдера — тоже ссылка: общий секрет не удаляется.
    return _isReferenced(snapshot, name, exceptProvider: providerId)
        ? null
        : name;
  }

  /// Есть ли в конфиге ссылка на секрет [name]: значение, равное имени
  /// (`api_key_secret`), или подстановка `${secret:<name>}` в любой строке.
  ///
  /// Почему по всем строкам и слоям, включая недоверенный проект: пропустить
  /// ссылку значит удалить секрет, который кто-то использует; лишняя ссылка
  /// стоит только неудалённого секрета (SETUP-24, fail-safe). Экранированный
  /// литерал тоже считается ссылкой по той же причине.
  static bool _isReferenced(
    AgentConfigSnapshot snapshot,
    String name, {
    String? exceptProvider,
  }) {
    final marker = '\${secret:$name}';
    bool inValue(Object? value) => switch (value) {
      String() => value == name || value.contains(marker),
      List<Object?>() => value.any(inValue),
      Map<Object?, Object?>() => value.values.any(inValue),
      _ => false,
    };
    final own = exceptProvider == null ? null : 'providers.$exceptProvider.';
    bool inLeaves(Map<String, Object?> leaves) => leaves.entries.any(
      (e) => (own == null || !e.key.startsWith(own)) && inValue(e.value),
    );
    return inLeaves(snapshot.leaves) ||
        snapshot.layers.values.any(
          (layer) => inLeaves(flattenConfigValues(layer.values)),
        );
  }

  /// Удаляет провайдера [providerId] из конфига по [snapshot].
  ///
  /// [newDefaultModel] — `<провайдер>/<модель>` оставшегося провайдера;
  /// обязателен, если удаляется провайдер модели по умолчанию. [deleteStoredKey]
  /// — удалить собственный секрет ([ownedSecretName]) после `ConfigSaved`.
  Future<ProviderRemovalOutcome> remove(
    AgentConfigSnapshot snapshot, {
    required String providerId,
    String? newDefaultModel,
    bool deleteStoredKey = false,
  }) async {
    final ids = providerIdsOf(snapshot);
    if (providerEditRefusal(snapshot, providerId) case final refusal?) {
      return _refuse(refusal);
    }
    final layer = providerOriginsOf(snapshot, providerId).single.layer!;
    final base = snapshot.layers[layer]!;
    if (ids.length == 1) {
      return _refuse(ProviderRemovalRefusal.lastProvider);
    }

    final edits = <ConfigEdit>[RemoveTable('providers.$providerId')];
    final current = snapshot.defaultModel;
    if (current != null && current.startsWith('$providerId/')) {
      if (newDefaultModel == null) {
        return _refuse(ProviderRemovalRefusal.newDefaultRequired);
      }
      final remaining = [
        for (final id in ids)
          if (id != providerId) ...modelsOf(snapshot, id),
      ];
      if (!remaining.contains(newDefaultModel)) {
        return _refuse(ProviderRemovalRefusal.newDefaultInvalid);
      }
      if (_defaultIsAbove(snapshot, layer)) {
        return _refuse(ProviderRemovalRefusal.defaultOverridden);
      }
      edits.add(SetValue('agent.default_model', newDefaultModel));
    }

    final secretName = deleteStoredKey
        ? ownedSecretName(snapshot, providerId)
        : null;
    final outcome = await _config.apply(base, edits);
    if (outcome is! ConfigSaved) {
      return ProviderRemovalNotSaved(outcome);
    }
    if (secretName == null) {
      return ProviderRemoved(
        saved: outcome,
        secret: SecretCleanup.notRequested,
      );
    }
    // Между снимком и записью другой процесс мог добавить ссылку: перед
    // удалением конфиг читается заново (SETUP-24).
    final AgentConfigSnapshot fresh;
    try {
      fresh = await _config.snapshot(cwd: snapshot.cwd);
    } on Object {
      return ProviderRemoved(saved: outcome, secret: SecretCleanup.failed);
    }
    if (_isReferenced(fresh, secretName)) {
      return ProviderRemoved(
        saved: outcome,
        secret: SecretCleanup.stillReferenced,
      );
    }
    final deletion = await _deleteSecret(secretName);
    return ProviderRemoved(
      saved: outcome,
      secret: switch (deletion) {
        SecretDeletion.deleted => SecretCleanup.deleted,
        SecretDeletion.notSet => SecretCleanup.alreadyAbsent,
        SecretDeletion.failed => SecretCleanup.failed,
      },
    );
  }

  ProviderRemovalRefused _refuse(ProviderRemovalRefusal reason) =>
      ProviderRemovalRefused(reason);

  /// Задан ли `agent.default_model` слоем, который приоритетнее [layer] (или
  /// не файлом слоёв 2–4: `--config`, окружение).
  bool _defaultIsAbove(AgentConfigSnapshot snapshot, ConfigLayer layer) {
    final origin = snapshot.originOf('agent.default_model');
    if (origin == null) {
      return false;
    }
    final defaultLayer = origin.layer;
    if (defaultLayer == null) {
      return true;
    }
    return configLayersByPriority.indexOf(defaultLayer) >
        configLayersByPriority.indexOf(layer);
  }
}
