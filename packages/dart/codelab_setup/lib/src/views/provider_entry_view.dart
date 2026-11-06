/// Строка страницы Providers (`dart-agent-and-clients` §12.4.5; design.md
/// change `add-provider-setup-ui`, D6, D10).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show KeyPath, SecretNames;

import '../config/agent_config_store.dart';
import '../config/config_source_view.dart';
import '../config/display_base_url.dart';
import 'key_status_view.dart';

/// Провайдер в списке «Configured providers».
///
/// Почему модель, а не `ProviderConfig` ядра: странице нужны источник и
/// признак редактируемости, статус ключа без чтения значения и список ссылок
/// на модели — и ничего, что содержит секреты (SETUP-1).
///
/// Для чего: общий вход страницы app и списка CLI. Строится
/// [providerEntriesOf] по снимку.
///
/// Как использовать: поля только для чтения; [editable] `false` у слоя 3,
/// файла `--config` и окружения — кнопок записи нет, подпись «defined in
/// [source].label».
final class ProviderEntryView {
  const ProviderEntryView({
    required this.id,
    required this.kind,
    required this.baseUrl,
    required this.displayBaseUrl,
    required this.key,
    required this.models,
    required this.source,
    required this.editable,
    required this.isDefault,
  });

  final String id;

  /// `openai-compatible` | `anthropic` | `gemini`; `null` — ключа `kind` нет.
  final String? kind;

  /// Адрес как в конфиге: для запроса Check; на экран и в журнал не выводится
  /// (в нём могут быть userinfo и ключ в query).
  final String? baseUrl;

  /// Адрес для показа: схема, хост, порт и путь без userinfo, query и
  /// fragment; `null` — адреса нет или он не разбирается (SETUP-1).
  final String? displayBaseUrl;
  final KeyStatusView key;

  /// Ссылки `<провайдер>/<модель>` по алфавиту.
  final List<String> models;

  /// Файл и слой, где определён провайдер; при чужом листе — первый чужой.
  final ConfigSourceView source;
  final bool editable;

  /// `agent.default_model` указывает на этого провайдера.
  final bool isDefault;

  @override
  String toString() => 'ProviderEntryView($id, ${key.label}, ${source.label})';
}

/// Строит список провайдеров страницы по [snapshot].
///
/// Почему не читает значения: статус ключа — по имени. [isSecretSet] отвечает
/// «есть ли секрет с таким именем» (`ClientSecretAccess.isSet`); [environment]
/// — окружение агента для `api_key_env` и переменных переопределения
/// `CODELAB_SECRET_<…>` (побеждают бэкенд, как у резолвера агента).
///
/// Для чего: единый список для app и CLI; порядок — по `id`.
///
/// Как использовать: после `AgentConfigStore.snapshot`; вызывается заново при
/// открытии страницы и после записи. Ошибка [isSecretSet] (хранилище
/// недоступно) пробрасывается вызывающему: Cubit показывает `storeUnavailable`.
Future<List<ProviderEntryView>> providerEntriesOf(
  AgentConfigSnapshot snapshot, {
  required Map<String, String> environment,
  required Future<bool> Function(String name) isSecretSet,
}) async {
  final ids = providerIdsOf(snapshot);
  final defaultModel = snapshot.defaultModel;
  final out = <ProviderEntryView>[];
  for (final id in ids) {
    final origins = providerOriginsOf(snapshot, id);
    final nonEditable = origins.where((o) => !o.editable);
    final base = _leaf(id, 'kind');
    final source = nonEditable.isNotEmpty
        ? nonEditable.first
        : snapshot.origins[base] ??
              (origins.isNotEmpty
                  ? origins.first
                  : const ConfigSourceView(
                      kind: ConfigSourceKind.environment,
                      label: 'unknown',
                    ));
    out.add(
      ProviderEntryView(
        id: id,
        kind: _string(snapshot, id, 'kind'),
        baseUrl: _string(snapshot, id, 'base_url'),
        displayBaseUrl: displayBaseUrl(_string(snapshot, id, 'base_url')),
        key: await _keyStatus(
          snapshot,
          id,
          environment: environment,
          isSecretSet: isSecretSet,
        ),
        models: modelsOf(snapshot, id),
        source: source,
        editable: origins.isNotEmpty && nonEditable.isEmpty,
        isDefault: defaultModel != null && defaultModel.startsWith('$id/'),
      ),
    );
  }
  return out;
}

/// Идентификаторы провайдеров снимка по алфавиту.
List<String> providerIdsOf(AgentConfigSnapshot snapshot) {
  final ids = <String>{};
  for (final key in snapshot.leaves.keys) {
    if (_split(key) case final parts?) {
      ids.add(parts.id);
    }
  }
  return ids.toList()..sort();
}

/// Источники всех листьев провайдера [id] (без повторов, по порядку ключей).
List<ConfigSourceView> providerOriginsOf(
  AgentConfigSnapshot snapshot,
  String id,
) {
  final out = <ConfigSourceView>[];
  for (final key in snapshot.leaves.keys) {
    if (_split(key)?.id != id) {
      continue;
    }
    final origin = snapshot.origins[key];
    if (origin != null && !out.contains(origin)) {
      out.add(origin);
    }
  }
  return out;
}

/// Ссылки `<провайдер>/<модель>` провайдера [id] по алфавиту.
List<String> modelsOf(AgentConfigSnapshot snapshot, String id) {
  final models = <String>{};
  for (final key in snapshot.leaves.keys) {
    final parts = _split(key);
    if (parts == null || parts.id != id) {
      continue;
    }
    if (_modelOf(parts.rest) case final model?) {
      models.add('$id/$model');
    }
  }
  return models.toList()..sort();
}

/// Разбор плоского ключа `providers.<id>.<остаток>`.
///
/// Почему не `splitKeyPath`: ядро НЕ квотирует точку в обычном сегменте
/// (`models.qwen2.5-coder.context_window`, `KeyPath.child`), и разбор по
/// точкам разорвал бы id модели. Поэтому id провайдера — до первой точки (id
/// мастера — `[a-z0-9_-]+`) или в кавычках, а модель выделяется по известным
/// именам полей ([_modelOf]).
({String id, String rest})? _split(String key) {
  const prefix = 'providers.';
  if (!key.startsWith(prefix)) {
    return null;
  }
  final tail = key.substring(prefix.length);
  if (tail.startsWith('"')) {
    final end = tail.indexOf('"', 1);
    if (end < 0) {
      return null;
    }
    final rest = tail.length > end + 1 ? tail.substring(end + 2) : '';
    return (id: tail.substring(1, end), rest: rest);
  }
  final dot = tail.indexOf('.');
  if (dot < 0) {
    return tail.isEmpty ? null : (id: tail, rest: '');
  }
  return (id: tail.substring(0, dot), rest: tail.substring(dot + 1));
}

/// Поля записи модели (`providers.*.models.*.<поле>`, реестр настроек).
const _modelFields = ['context_window', 'max_output_tokens', 'name'];

/// Id модели из остатка ключа после id провайдера или `null`, если остаток не
/// про модель.
String? _modelOf(String rest) {
  const prefix = 'models.';
  if (!rest.startsWith(prefix)) {
    return null;
  }
  final tail = rest.substring(prefix.length);
  if (tail.startsWith('"')) {
    final end = tail.indexOf('"', 1);
    return end < 0 ? null : tail.substring(1, end);
  }
  for (final field in _modelFields) {
    if (tail.endsWith('.$field')) {
      return tail.substring(0, tail.length - field.length - 1);
    }
  }
  return tail.isEmpty ? null : tail;
}

/// Значение строкового листа `providers.<id>.<name>` или `null`.
String? providerString(AgentConfigSnapshot snapshot, String id, String name) =>
    _string(snapshot, id, name);

String _leaf(String id, String name) =>
    KeyPath.root.child('providers').child(id).child(name).value;

String? _string(AgentConfigSnapshot snapshot, String id, String name) {
  final value = snapshot.leaves[_leaf(id, name)];
  return value is String && value.isNotEmpty ? value : null;
}

Future<KeyStatusView> _keyStatus(
  AgentConfigSnapshot snapshot,
  String id, {
  required Map<String, String> environment,
  required Future<bool> Function(String name) isSecretSet,
}) async {
  final backendId = snapshot.secrets.id;
  if (_string(snapshot, id, 'api_key_secret') case final name?) {
    final override = environment[SecretNames.envOverride(name)];
    if (override != null && override.isNotEmpty) {
      return KeyInSecretStore(name: name, backendId: 'env');
    }
    return await isSecretSet(name)
        ? KeyInSecretStore(name: name, backendId: backendId)
        : KeySecretMissing(name: name, backendId: backendId);
  }
  if (_string(snapshot, id, 'api_key_env') case final name?) {
    final value = environment[name];
    return KeyFromEnv(name: name, isSet: value != null && value.isNotEmpty);
  }
  if (snapshot.leaves.containsKey(_leaf(id, 'api_key'))) {
    return const KeyLiteralInConfig();
  }
  return const KeyNone();
}
