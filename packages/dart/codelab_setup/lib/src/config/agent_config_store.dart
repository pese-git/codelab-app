/// Порт чтения и записи конфига агента для клиентов (client-agent-setup
/// «Снимок и запись конфига агента»; `dart-agent-and-clients` §12.4.2; design.md
/// change `add-provider-setup-ui`, D6).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        ConfigEdit,
        ConfigIssue,
        ConfigIssueKind,
        ConfigLayer,
        ConfigLoadResult,
        ConfigSnapshot,
        SecretBackendInfo;

import 'config_source_view.dart';
import 'config_values.dart';

/// Снимок конфига агента для страниц настроек и мастера.
///
/// Почему отдельный тип: странице нужны сразу слои (основа для записи), итог
/// загрузки с проблемами валидатора, источник каждого ключа и описание
/// хранилища секретов; собирать их из разных вызовов значило бы показывать
/// состояние, которого не было ни в один момент.
///
/// Для чего: единица, которую порт [AgentConfigStore.snapshot] отдаёт и
/// которую Cubit-ы перечитывают при открытии страницы, после своей записи и
/// после конфликта (D6). Слежения за файлом нет.
///
/// Как использовать: из `FileAgentConfigStore.snapshot`; в тестах — фабрикой
/// [AgentConfigSnapshot.fromLayers]. [layers] содержит только читаемые слои:
/// слой с битым YAML в карте отсутствует ([isReadable]), а причина — в
/// `loaded.issues`; страница тогда показывает ошибку и не пишет файл.
final class AgentConfigSnapshot {
  AgentConfigSnapshot({
    required this.cwd,
    required this.layers,
    required this.loaded,
    required this.origins,
    required this.secrets,
    this.externalSources = defaultExternalSources,
  });

  /// Строит снимок по слоям: источник листа — самый приоритетный файловый
  /// слой, чьё значение совпало с итоговым. Лист, пришедший не из файлов
  /// (`--config`, окружение), спрашивается у [externalOrigin].
  ///
  /// Почему сравнение значений: слой 3 недоверенного проекта и перекрытые
  /// значения в итог не попадают, и приписывать им источник нельзя.
  factory AgentConfigSnapshot.fromLayers({
    required String cwd,
    required Map<ConfigLayer, ConfigSnapshot> layers,
    required ConfigLoadResult loaded,
    required SecretBackendInfo secrets,
    ConfigSourceView? Function(String key)? externalOrigin,
    Set<String> externalSources = defaultExternalSources,
  }) {
    bool ignored(ConfigLayer layer, String key) =>
        isIgnoredByTrust(loaded, layer, key);
    final effective = loaded.values.isNotEmpty
        ? loaded.values
        : mergeLayerLeaves(layers, ignored: ignored);
    final flat = {
      for (final layer in configLayersByPriority)
        if (layers[layer] case final snapshot?)
          layer: flattenConfigValues(snapshot.values),
    };
    final origins = <String, ConfigSourceView>{};
    effective.forEach((key, value) {
      for (final layer in configLayersByPriority.reversed) {
        final leaves = flat[layer];
        if (leaves != null &&
            !ignored(layer, key) &&
            leaves.containsKey(key) &&
            sameConfigValue(leaves[key], value)) {
          origins[key] = ConfigSourceView(
            kind: switch (layer) {
              ConfigLayer.user => ConfigSourceKind.user,
              ConfigLayer.project => ConfigSourceKind.project,
              ConfigLayer.projectLocal => ConfigSourceKind.projectLocal,
            },
            label: layers[layer]!.path,
          );
          return;
        }
      }
      if (externalOrigin?.call(key) case final source?) {
        origins[key] = source;
      }
    });
    return AgentConfigSnapshot(
      cwd: cwd,
      layers: layers,
      loaded: loaded,
      origins: origins,
      secrets: secrets,
      externalSources: externalSources,
    );
  }

  /// Значения `ConfigIssue.source`, означающие НЕ файлы слоёв 2–4: окружение,
  /// флаги, хранилище приложения и файл `--config`. Проблема с таким
  /// источником — неверное значение внешнего ключа, а не отсутствие ключа.
  static const defaultExternalSources = {'env', 'flags', 'app-storage'};

  final Set<String> externalSources;

  /// Папка проекта, для которой прочитаны проектные слои.
  final String cwd;

  /// Прочитанные слои: основа для `apply`; отпечаток защищает от конфликта.
  /// `project` (слой 3) — только для чтения.
  final Map<ConfigLayer, ConfigSnapshot> layers;

  /// Итог загрузки (§15.5): `config`, `issues`, `warnings`, `sources`.
  final ConfigLoadResult loaded;

  /// Источник каждого листового ключа (путь формата `KeyPath`).
  final Map<String, ConfigSourceView> origins;

  /// Бэкенд секретов (`ClientSecretAccess.backend`) для строки «Key storage».
  final SecretBackendInfo secrets;

  /// Прочитан ли слой [layer]; `false` — файл не разобрался.
  bool isReadable(ConfigLayer layer) => layers.containsKey(layer);

  /// Проблемы, из-за которых конфиг нельзя прочитать и править: синтаксис,
  /// тип и значение существующих ключей, неизвестные ключи. Непустой список —
  /// страница показывает ошибку загрузчика и не пишет файл (`Unreadable`).
  List<ConfigIssue> get issues => [
    for (final issue in loaded.issues)
      if (!_isMissingKey(issue)) issue,
  ];

  /// Проблемы запуска агента из-за ОТСУТСТВИЯ ключа (`agent.default_model:
  /// required` на новой установке). Файл читается и правится, поэтому страница
  /// показывает пустое состояние, а не `Unreadable`; мастер провайдера как раз
  /// и создаёт недостающее.
  ///
  /// Почему по структуре, а не по тексту: проблема «нужен ключ» имеет вид
  /// `value`, как и «неверное значение», и отличается только тем, что ключа
  /// нет ни в одном применённом слое. Текст сообщения не разбирается.
  List<ConfigIssue> get startProblems => [
    for (final issue in loaded.issues)
      if (_isMissingKey(issue)) issue,
  ];

  bool _isMissingKey(ConfigIssue issue) {
    if (issue.kind != ConfigIssueKind.value ||
        issue.key.isEmpty ||
        externalSources.contains(issue.source)) {
      // Ключ задан извне (`--config`, окружение): файлы слоёв его не знают, но
      // он есть — это проблема значения, а не отсутствия.
      return false;
    }
    final prefix = '${issue.key}.';
    return !leaves.keys.any((k) => k == issue.key || k.startsWith(prefix));
  }

  /// Эффективные листья: итог загрузки, а при проблемах загрузки — слияние
  /// читаемых файловых слоёв (страница всё равно показывает, что править).
  late final Map<String, Object?> leaves = loaded.values.isNotEmpty
      ? loaded.values
      : mergeLayerLeaves(
          layers,
          ignored: (layer, key) => isIgnoredByTrust(loaded, layer, key),
        );

  /// Итоговый `agent.default_model` (`<провайдер>/<модель>`) или `null`.
  String? get defaultModel {
    final value = leaves['agent.default_model'];
    return value is String ? value : null;
  }

  /// Источник ключа [key] или `null`, если ключа нет.
  ConfigSourceView? originOf(String key) => origins[key];

  @override
  String toString() => 'AgentConfigSnapshot($cwd)';
}

/// Не применил ли загрузчик ключ [key] слоя [layer] из-за недоверенного
/// проекта (`config.project.untrusted_key`, CFG-3).
///
/// Почему по предупреждениям: файл слоя 3 или 4 лежит в репозитории, который
/// пользователь мог только что склонировать, и его значения не должны ни
/// попадать в списки настроек, ни считаться источником итогового значения,
/// даже если совпали с ним. Предупреждение называет раздел (`providers`,
/// `mcp.servers`) или ключ; слой определяется по имени файла источника.
bool isIgnoredByTrust(ConfigLoadResult loaded, ConfigLayer layer, String key) {
  final suffix = switch (layer) {
    ConfigLayer.user => null,
    ConfigLayer.project => '.codelab/config.yaml',
    ConfigLayer.projectLocal => '.codelab/config.local.yaml',
  };
  if (suffix == null) {
    return false;
  }
  for (final warning in loaded.warnings) {
    if (warning.event == 'config.project.untrusted_key' &&
        warning.source.replaceAll(r'\', '/').endsWith(suffix) &&
        (key == warning.key || key.startsWith('${warning.key}.'))) {
      return true;
    }
  }
  return false;
}

/// Читает и записывает конфиг агента (порт клиента).
///
/// Почему порт: страницы и мастер тестируются на фейке, а файловая реализация
/// (`FileAgentConfigStore`, `lib/io.dart`) опирается на `ConfigWriter` и
/// `dart:io`.
///
/// Как использовать: `snapshot(cwd:)` при открытии страницы и после записи;
/// `apply(base, edits)` с `base` — снимком слоя из `snapshot.layers`.
abstract interface class AgentConfigStore {
  /// Все слои с происхождением ключей; `loaded.issues` — ошибки валидатора.
  Future<AgentConfigSnapshot> snapshot({required String cwd});

  /// Записывает [edits] в слой [base] одним вызовом; отпечаток [base]
  /// защищает от перезаписи чужой правки (SETUP-6).
  Future<ConfigSaveOutcome> apply(ConfigSnapshot base, List<ConfigEdit> edits);
}

/// Результат записи конфига: переведённые исключения `ConfigWriter`.
sealed class ConfigSaveOutcome {
  const ConfigSaveOutcome();
}

/// Записано.
final class ConfigSaved extends ConfigSaveOutcome {
  const ConfigSaved({
    required this.fingerprint,
    required this.warnings,
    required this.restartRequiredKeys,
  });

  /// Отпечаток записанного файла: основа следующей правки.
  final String fingerprint;

  /// Записано с оговорками (незаданная `${VAR}` и т. п.); значений нет.
  final List<ConfigIssue> warnings;

  /// Ключи, вступающие в силу только после перезапуска агента.
  final List<String> restartRequiredKeys;

  @override
  String toString() => 'ConfigSaved';
}

/// Файл изменился после чтения или занят другим писателем (SETUP-6): черновик
/// сохраняется, снимок перечитывается, автоповтора нет.
final class ConfigConflict extends ConfigSaveOutcome {
  const ConfigConflict(this.path);

  final String path;

  @override
  String toString() => 'ConfigConflict($path)';
}

/// Валидатор отклонил правку; файл не изменён.
final class ConfigRejected extends ConfigSaveOutcome {
  const ConfigRejected(this.issues);

  final List<ConfigIssue> issues;

  @override
  String toString() => 'ConfigRejected(${issues.length})';
}

/// В правке секрет значением (CFG-2): [suggestedSecretName] — куда его
/// сохранить вместо этого.
final class ConfigInlineSecret extends ConfigSaveOutcome {
  const ConfigInlineSecret({
    required this.key,
    required this.suggestedSecretName,
  });

  /// Путь ключа с секретом; самого значения нет.
  final String key;
  final String suggestedSecretName;

  @override
  String toString() => 'ConfigInlineSecret($key)';
}
