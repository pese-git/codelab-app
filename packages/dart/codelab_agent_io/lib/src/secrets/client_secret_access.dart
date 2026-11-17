import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../config/config_loader.dart' show maxConfigBytes;
import '../config/yaml_reader.dart';
import 'env_secret_store.dart';
import 'open_secret_store.dart';
import 'secret_admin.dart';
import 'secret_process_runner.dart';

/// Клиентский доступ к секретам агента (design.md change
/// `add-provider-setup-ui`, D4; agent-secrets «Клиентский доступ к
/// секретам»).
///
/// Почему отдельный тип: codelab-app и CLI хранят в хранилище секретов агента
/// ключи провайдеров и токены профилей. Им нужны выбор бэкенда по
/// пользовательскому слою, запись, проверка наличия и чтение значения для
/// проверочного запроса или транспорта. `openHostSecrets` принадлежит хосту
/// агента (D15 change `add-agent-secret-store`) и кэширует найденное до конца
/// процесса, а клиенту кэш вреден: замена секрета в другом процессе
/// (`codelab secret set`) должна быть видна при следующем подключении.
///
/// Для чего: единственный путь клиентов к хранилищу. Порядок чтения тот же,
/// что у `SecretResolver` агента: непустая переменная
/// `SecretNames.envOverride(name)` побеждает бэкенд, иначе клиент и агент
/// разошлись бы.
///
/// Как использовать: `await ClientSecretAccess.open(codelabHome: …,
/// environment: Platform.environment, logger: …)` в composition root. Значение
/// [read] возвращается только адаптеру, который сразу отдаёт его транспорту
/// или `ProviderCheck`; в состояния, события и тексты оно не попадает
/// (SETUP-1). Запись, проверка и удаление — через [admin]. Ни один метод не
/// пишет значение в журнал, исключение или `toString()` (CFG-10).
final class ClientSecretAccess {
  ClientSecretAccess._({
    required DescribedSecretStore store,
    required Map<String, String> environment,
    required this.admin,
    required this.configProblem,
  }) : _store = store,
       _environment = environment;

  final DescribedSecretStore _store;

  // Окружение держим по ссылке, а не копией: вызывающий может менять его между
  // чтениями, и «без кэша» относится и к переменным.
  final Map<String, String> _environment;

  /// Администратор того же хранилища: `store`, `checkStore`, `delete`, `list`
  /// с типизированными результатами без значения.
  final SecretAdmin admin;

  /// Причина отката на `env` из-за пользовательского конфига, иначе `null`.
  ///
  /// Почему поле: клиент должен отличать «`secrets.backend` в config.yaml
  /// битый или недопустимый» (нужно показать ошибку, пока конфиг не
  /// починен) от обычного `auto → env`, у которого тоже есть
  /// `backend.unavailableReason`. Разбирать префикс текста причины хрупко.
  ///
  /// Для чего и как: не `null` только когда [open] откатился на `env` из-за
  /// нечитаемого файла, битого YAML, значения не строкой или недопустимого
  /// значения; это тот же фиксированный текст, что в
  /// `backend.unavailableReason` и в событии `secrets.client.fallback`, без
  /// строк файла и без эха значения. При отсутствии файла или ключа, `auto`,
  /// `env` и `file` — `null`.
  final String? configProblem;

  /// Открывает доступ по пользовательскому слою конфига.
  ///
  /// Читает из `$codelabHome/config.yaml` только `secrets.backend` (ключ
  /// допустим лишь в слое `user`). Нечитаемый файл, синтаксическая ошибка или
  /// недопустимое значение дают бэкенд `env` с `unavailableReason`, а не
  /// исключение: пока конфиг сломан, клиент ничего не записывает. Причина —
  /// фиксированный текст без строк файла и без эха значения.
  ///
  /// [runner] и [platform] — швы для тестов бэкенда `file`.
  static Future<ClientSecretAccess> open({
    required String codelabHome,
    required Map<String, String> environment,
    required Logger logger,
    SecretProcessRunner? runner,
    String? platform,
  }) async {
    final choice = _readBackendChoice(codelabHome);
    DescribedSecretStore? opened;
    String? problem = choice.problem;
    if (problem == null) {
      try {
        opened = openSecretStore(
          choice: choice.value,
          environment: environment,
          home: codelabHome,
          logger: logger,
          runner: runner,
          platform: platform,
        );
      } on SecretStoreUnavailableException catch (error) {
        problem = 'secrets.backend: ${error.reason}';
      }
    }
    final DescribedSecretStore store;
    if (opened != null) {
      store = opened;
    } else {
      logger.log(
        LogLevel.warning,
        'secrets.client.fallback',
        fields: {'backend': 'env', 'reason': problem},
      );
      store = EnvSecretStore(
        environment: environment,
        unavailableReason: problem,
      );
    }
    return ClientSecretAccess._(
      store: store,
      environment: environment,
      configProblem: opened == null ? problem : null,
      admin: SecretAdmin(
        store: store,
        environment: environment,
        platform: platform,
      ),
    );
  }

  /// Описание выбранного бэкенда: `id`, `writable`, `unavailableReason`.
  SecretBackendInfo get backend => _store.backend;

  /// Есть ли значение под [name]: непустая переменная переопределения или имя
  /// в `names()` бэкенда. Значение не читается.
  Future<bool> isSet(String name) async {
    if (SecretNames.problem(name) != null) {
      return false;
    }
    if (_override(name) != null) {
      return true;
    }
    try {
      return (await _store.names()).contains(name);
    } on SecretStoreUnavailableException {
      rethrow;
    } on Object catch (error) {
      throw _unavailable(error);
    }
  }

  /// Значение секрета: непустая переменная переопределения, иначе значение
  /// бэкенда, иначе `null`. Без кэша.
  ///
  /// Ошибка бэкенда — `SecretStoreUnavailableException` с причиной без
  /// значения; чужое исключение заменяется нашим текстом с типом ошибки (оно
  /// могло процитировать значение).
  Future<String?> read(String name) async {
    if (SecretNames.problem(name) != null) {
      return null;
    }
    if (_override(name) case final value?) {
      return value;
    }
    try {
      return await _store.read(name);
    } on SecretStoreUnavailableException {
      rethrow;
    } on Object catch (error) {
      throw _unavailable(error);
    }
  }

  @override
  String toString() => 'ClientSecretAccess(backend: ${_store.backend.id})';

  String? _override(String name) {
    final value = _environment[SecretNames.envOverride(name)];
    return value == null || value.isEmpty ? null : value;
  }

  SecretStoreUnavailableException _unavailable(Object error) =>
      SecretStoreUnavailableException(
        backend: _store.backend.id,
        reason: 'secret store failed: ${error.runtimeType}',
      );

  /// Значение `secrets.backend` пользовательского слоя либо причина, по
  /// которой слой не прочитан. Остальные ключи файла не разбираются (D4).
  static ({String? value, String? problem}) _readBackendChoice(String home) {
    final path = '$home/config.yaml';
    if (!FileSystemEntity.isFileSync(path)) {
      return (value: null, problem: null);
    }
    final String text;
    try {
      if (File(path).statSync().size > maxConfigBytes) {
        throw const FormatException('larger than 1 MiB');
      }
      text = utf8.decode(File(path).readAsBytesSync());
    } on FileSystemException {
      return (value: null, problem: _unreadable);
    } on FormatException {
      return (value: null, problem: _unreadable);
    }
    final tree = readYamlTree(text, source: path, kind: ConfigLayerKind.user);
    if (tree.tree == null) {
      return (value: null, problem: _unreadable);
    }
    final secrets = tree.tree!.values['secrets'];
    if (secrets is Map<String, Object?> && secrets.containsKey('backend')) {
      final backend = secrets['backend'];
      // Не строка — недопустимое значение: `openSecretStore` назовёт
      // допустимые, не цитируя ввод.
      return (value: backend is String ? backend : '', problem: null);
    }
    return (value: null, problem: null);
  }

  static const _unreadable =
      'the user config file cannot be read, so secrets are read-only until '
      'it is fixed';
}
