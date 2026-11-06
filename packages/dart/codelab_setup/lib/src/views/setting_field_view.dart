/// Строка экрана настроек `/settings` (client-agent-setup «Состав моста
/// codelab_setup для настройки агента»; `dart-agent-and-clients` §12.4.2;
/// design.md change `add-provider-setup-ui`, D17, Q15).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        KeyPath,
        SettingDescriptor,
        SettingScope,
        SettingType,
        SettingsRegistry;

import '../config/agent_config_store.dart';
import '../config/config_source_view.dart';
import 'provider_entry_view.dart' show modelsOf, providerIdsOf;

/// Строка списка настроек: ключ реестра, его итоговое значение и источник.
///
/// Почему модель в мосте: REPL `/settings`, экран `CliSettings` в TUI и
/// страница настроек app показывают одну и ту же таблицу `key · value ·
/// source`; разбирать слои, доверие к проекту и происхождение листьев в
/// каждом клиенте значило бы повторять логику загрузчика (SETUP-8).
///
/// Для чего: единица, которую строит [settingFieldsOf] по снимку. Значения
/// секретов в конфиге не хранятся (в ключе типа `secretName` лежит только
/// имя), а карты и списки карт (`mcp.servers`, `permissions.tools`) могут
/// нести токены в заголовках, поэтому у них значение не раскрывается — только
/// число записей ([entryCount]). [toString] не печатает значений вовсе
/// (SETUP-1).
///
/// Как использовать: поля только для чтения. Колонка `source` — [sourceName]
/// (`default`, `user`, `project`, `local`, `config`, `env`); править можно
/// строку с [editable] `true` — источник `default`, `user` или `local`.
/// Запись идёт через `AgentConfigStore.apply` в слой `user` или
/// `projectLocal` (слой `project` клиенты не пишут, SETUP-3). Новое значение
/// разбирает `SettingsRegistry.parseCliValue(descriptor, raw)`, ошибка —
/// `ConfigValueException`.
final class SettingFieldView {
  const SettingFieldView({
    required this.key,
    required this.descriptor,
    required this.value,
    required this.source,
    this.entryCount,
  });

  /// Конкретный путь ключа в формате `KeyPath`: `*` дескриптора заменён на
  /// id провайдера (и модели): `providers.gw.base_url`.
  final String key;

  /// Дескриптор реестра: тип редактора, границы, `restartRequired`, слои.
  final SettingDescriptor descriptor;

  /// Заданное значение: `bool`, `int`, `double`, строка или список; `null` —
  /// ключ нигде не задан ([source] тоже `null`) либо тип `map`/`mapList`
  /// (см. [entryCount]).
  final Object? value;

  /// Откуда пришло значение; `null` — значение по умолчанию. Ключ слоя
  /// недоверенного проекта (CFG-3) источником не считается: загрузчик его не
  /// применил.
  final ConfigSourceView? source;

  /// Число записей у ключей `map`/`mapList`; `null` у остальных. Содержимое
  /// записей не раскрывается: в заголовках и `env` могут быть токены.
  final int? entryCount;

  /// Значение задано умолчанием реестра.
  bool get isDefault => source == null;

  /// Итог для показа: заданное значение, иначе умолчание реестра.
  Object? get effectiveValue => value ?? descriptor.defaultValue;

  /// Колонка `source` REPL `/settings` (Q15): `default`, `user`, `project`,
  /// `local`, `config` (`CODELAB_CONFIG`/`--config`) или `env`.
  String get sourceName => switch (source?.kind) {
    null => 'default',
    ConfigSourceKind.user => 'user',
    ConfigSourceKind.project => 'project',
    ConfigSourceKind.projectLocal => 'local',
    ConfigSourceKind.extraFile => 'config',
    ConfigSourceKind.environment => 'env',
  };

  /// Можно ли записать значение из клиента: значение по умолчанию, слои
  /// `user` и `projectLocal`. Слой `project`, `--config` и окружение —
  /// только чтение (SETUP-3, Q15).
  bool get editable => source == null || source!.editable;

  /// Изменение вступает в силу после перезапуска агента (`(applies after
  /// restart)` в ответе записи).
  bool get restartRequired => descriptor.restartRequired;

  /// Значение одной строкой для таблицы.
  String get displayValue {
    if (entryCount case final count?) {
      return count == 0
          ? _notSet
          : count == 1
          ? '1 entry'
          : '$count entries';
    }
    return switch (effectiveValue) {
      null => _notSet,
      final List<Object?> list => list.isEmpty ? '[]' : list.join(', '),
      final other => '$other',
    };
  }

  static const _notSet = '(not set)';

  // Значения в строку не попадают намеренно (SETUP-1): в журнал и отчёт
  // идут ключ и источник.
  @override
  String toString() => 'SettingFieldView($key, $sourceName)';
}

/// Строит строки `/settings` по [snapshot]: ключи реестра `scope: shared`
/// в порядке реестра.
///
/// Почему не читает файлы сама: всё берётся из снимка — итоговые листья
/// `leaves` и источники `origins`, уже очищенные от ключей недоверенного
/// проекта.
///
/// Для чего: единый список для CLI и app. Ключи `providers.*` раскрываются
/// по id провайдеров снимка, `providers.*.models.*` — ещё и по их моделям;
/// провайдера без записи в конфиге нет, значит, нет и строк. Порядок — по
/// дескрипторам реестра, внутри дескриптора — по алфавиту id.
/// `fileOnly`-ключи (литеральный `api_key`, `agent.fallback`) не
/// показываются.
///
/// Как использовать: после `AgentConfigStore.snapshot`; вызывается заново
/// после записи. Синхронна и значений секретов не читает.
List<SettingFieldView> settingFieldsOf(AgentConfigSnapshot snapshot) {
  final out = <SettingFieldView>[];
  for (final descriptor in SettingsRegistry.all) {
    if (descriptor.scope != SettingScope.shared) {
      continue;
    }
    for (final key in _expand(snapshot, descriptor.key)) {
      out.add(_rowOf(snapshot, descriptor, key));
    }
  }
  return out;
}

SettingFieldView _rowOf(
  AgentConfigSnapshot snapshot,
  SettingDescriptor descriptor,
  String key,
) {
  final collection =
      descriptor.type == SettingType.map ||
      descriptor.type == SettingType.mapList;
  if (!collection) {
    return SettingFieldView(
      key: key,
      descriptor: descriptor,
      value: snapshot.leaves[key],
      source: snapshot.origins[key],
    );
  }
  // `map` раскрывается в листья `key.<имя>…`, `mapList` — один лист-список.
  var count = 0;
  ConfigSourceView? source;
  final prefix = '$key.';
  snapshot.leaves.forEach((leaf, value) {
    if (leaf == key || leaf.startsWith(prefix)) {
      count += value is List<Object?> && leaf == key ? value.length : 1;
      source ??= snapshot.origins[leaf];
    }
  });
  return SettingFieldView(
    key: key,
    descriptor: descriptor,
    value: null,
    source: source,
    entryCount: count,
  );
}

/// Конкретные ключи для шаблона [pattern] (`providers.*.models.*.name`).
Iterable<String> _expand(AgentConfigSnapshot snapshot, String pattern) {
  final segments = pattern.split('.');
  if (!segments.contains('*')) {
    return [pattern];
  }
  // Первая `*` — провайдер, вторая — модель (реестр не знает других).
  final keys = <String>[];
  for (final id in providerIdsOf(snapshot)) {
    final models = segments.where((s) => s == '*').length > 1
        ? [
            for (final ref in modelsOf(snapshot, id))
              ref.substring(id.length + 1),
          ]
        : const <String>[];
    if (segments.where((s) => s == '*').length > 1 && models.isEmpty) {
      continue;
    }
    for (final model in models.isEmpty ? [''] : models) {
      var path = KeyPath.root;
      var wildcards = 0;
      for (final segment in segments) {
        path = path.child(
          segment == '*' ? (wildcards++ == 0 ? id : model) : segment,
        );
      }
      keys.add(path.value);
    }
  }
  return keys;
}
