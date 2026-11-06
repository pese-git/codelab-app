/// Выбор ключа и план записи провайдера (`dart-agent-and-clients` §12.4.4,
/// шаг 7; design.md change `add-provider-setup-ui`, D7).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigEdit, ConfigTarget, SetValue, UnsetValue;

import '../secret/secret_value.dart';

/// Откуда провайдер берёт ключ.
sealed class KeyChoice {
  const KeyChoice();
}

/// Записать значение в хранилище под именем `codelab/<id>`; только при
/// записываемом бэкенде. [value] не печатается (SETUP-1).
final class StoreSecret extends KeyChoice {
  const StoreSecret(this.value);

  final SecretValue value;

  @override
  String toString() => 'StoreSecret';
}

/// Оставить ключ как есть: при правке — прежнюю ссылку, для нового провайдера —
/// уже сохранённый секрет `codelab/<id>`.
final class KeepStoredSecret extends KeyChoice {
  const KeepStoredSecret();

  @override
  String toString() => 'KeepStoredSecret';
}

/// Брать ключ из переменной окружения агента [name] (`api_key_env`).
final class UseEnvVar extends KeyChoice {
  const UseEnvVar(this.name);

  final String name;

  @override
  String toString() => 'UseEnvVar($name)';
}

/// Без ключа (локальные серверы).
final class NoKey extends KeyChoice {
  const NoKey();

  @override
  String toString() => 'NoKey';
}

/// Модель, которую план объявляет в конфиге.
///
/// Почему не `ModelEntry`: это имя занято каталогом ядра.
final class PlannedModel {
  const PlannedModel({
    required this.id,
    required this.contextWindow,
    this.maxOutputTokens,
  });

  final String id;
  final int contextWindow;
  final int? maxOutputTokens;

  @override
  String toString() => 'PlannedModel($id, $contextWindow)';
}

/// Итоговый план записи: что именно мастер запишет и куда.
///
/// Почему отдельный тип: `Reviewing` показывает его пользователю, committer
/// исполняет, а `toEdits()` даёт ровно те листовые правки, что и
/// `codelab provider add` (§12.4.4, шаг 7). Значения ключа в плане нет в
/// тексте: [key] печатается без значения (SETUP-1).
///
/// Как использовать: строит `ProviderSetupFlow`; клиенты читают поля для
/// сводки «Review». [unsetKeys] — листья, которые правка убирает (второй из
/// пары `api_key_*`, литеральный `api_key`).
final class ProviderSetupPlan {
  const ProviderSetupPlan({
    required this.providerId,
    required this.kind,
    required this.baseUrl,
    required this.key,
    required this.secretName,
    required this.replaceSecret,
    required this.model,
    required this.makeDefault,
    required this.target,
    this.unsetKeys = const [],
  });

  final String providerId;
  final String kind;
  final String? baseUrl;
  final KeyChoice key;

  /// Имя секрета `codelab/<id>` для [StoreSecret] и для «Use the stored key»
  /// нового провайдера; `null` — секрет не используется или (при правке)
  /// прежняя ссылка остаётся.
  final String? secretName;

  /// Явное «Replace it»: существующий секрет перезаписывается (SETUP-5).
  final bool replaceSecret;
  final PlannedModel model;
  final bool makeDefault;
  final ConfigTarget target;

  /// Полные ключи листьев, которые правка удаляет.
  final List<String> unsetKeys;

  ProviderSetupPlan copyWith({
    String? providerId,
    String? secretName,
    bool? replaceSecret,
    bool? makeDefault,
    ConfigTarget? target,
  }) => ProviderSetupPlan(
    providerId: providerId ?? this.providerId,
    kind: kind,
    baseUrl: baseUrl,
    key: key,
    secretName: secretName ?? this.secretName,
    replaceSecret: replaceSecret ?? this.replaceSecret,
    model: model,
    makeDefault: makeDefault ?? this.makeDefault,
    target: target ?? this.target,
    unsetKeys: unsetKeys,
  );

  /// План без значения ключа: `StoreSecret` заменяется на `KeepStoredSecret` с
  /// тем же [secretName] (правки `toEdits()` те же).
  ///
  /// Для чего: `Done` и `Cancelled` сбрасывают ссылку на `SecretValue` (D7), а
  /// клиенту для итоговой сводки значение не нужно.
  ProviderSetupPlan withoutSecretValue() => key is StoreSecret
      ? ProviderSetupPlan(
          providerId: providerId,
          kind: kind,
          baseUrl: baseUrl,
          key: const KeepStoredSecret(),
          secretName: secretName,
          replaceSecret: false,
          model: model,
          makeDefault: makeDefault,
          target: target,
          unsetKeys: unsetKeys,
        )
      : this;

  /// Листовые правки одним `apply`: `kind`, `base_url`, ключ, окно модели,
  /// модель по умолчанию, затем удаления. `api_key_secret` и `api_key_env`
  /// взаимоисключающие (§15.4).
  List<ConfigEdit> toEdits() {
    final prefix = 'providers.$providerId';
    final modelKey = '$prefix.models.${_segment(model.id)}';
    return [
      SetValue('$prefix.kind', kind),
      if (baseUrl case final url?) SetValue('$prefix.base_url', url),
      if (key is StoreSecret || (key is KeepStoredSecret && secretName != null))
        SetValue('$prefix.api_key_secret', secretName!),
      if (key case UseEnvVar(:final name))
        SetValue('$prefix.api_key_env', name),
      SetValue('$modelKey.context_window', model.contextWindow),
      if (model.maxOutputTokens case final max?)
        SetValue('$modelKey.max_output_tokens', max),
      if (makeDefault)
        SetValue('agent.default_model', '$providerId/${model.id}'),
      for (final key in unsetKeys) UnsetValue(key),
    ];
  }

  @override
  String toString() =>
      'ProviderSetupPlan($providerId, ${key.runtimeType}, ${model.id}, '
      '${target.layer.name})';
}

final _plainSegment = RegExp(r'^[A-Za-z0-9_\-]+$');

/// Сегмент ключа в кавычках, если в нём есть `.`, `/` и т. п. (§17.5.5, как у
/// `codelab provider add`).
String _segment(String name) => _plainSegment.hasMatch(name) ? name : '"$name"';
