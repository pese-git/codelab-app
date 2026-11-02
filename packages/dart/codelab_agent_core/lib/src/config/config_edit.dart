/// Типы программной правки конфигурации (`agent-core-architecture` §17.5.2;
/// design.md change `add-config-writer-and-reload`, D5).
///
/// Почему в ядре: писатель `ConfigWriter` живёт в `codelab_agent_io`
/// (`dart:io`), но правки строят и сравнивают клиенты (`codelab_setup`
/// реэкспортирует эти типы без зависимости от `codelab_agent_io`), а
/// мобильный и web-хосты пишут конфиг в своё хранилище (PKG-1: здесь нет
/// ни файлов, ни `package:yaml_edit`, CFG-5).
///
/// Для чего: чистые значения «куда писать» ([ConfigTarget]), «что прочитано»
/// ([ConfigSnapshot]), «что изменить» ([ConfigEdit]) и исключение
/// [ConfigConflictException], по которому клиент перечитывает файл и
/// повторяет правки.
///
/// Как использовать: клиент читает снимок цели, строит список правок и
/// передаёт оба писателю: `apply(snapshot, [SetValue('budget.max_steps',
/// 40)])`. Какие ключи можно писать и в какие слои — решает
/// `SettingsRegistry`, а не эти типы.
library;

import 'package:collection/collection.dart';

import 'key_path.dart';

/// Слой, в который писатель может записать ключ (§15.2: слои 2, 3, 4).
///
/// Почему три значения, а не `ConfigLayerKind`: остальные слои (`--config`,
/// окружение, флаги, хранилище приложения) пользователь программно не
/// правит — их задаёт тот, кто запускает агента.
enum ConfigLayer {
  /// Глобальный `$CODELAB_HOME/config.yaml` (слой 2).
  user,

  /// Проектный `<cwd>/.codelab/config.yaml` (слой 3).
  project,

  /// Локальный проектный `<cwd>/.codelab/config.local.yaml` (слой 4).
  projectLocal,
}

/// Куда писать: слой и, для проектных слоёв, каталог проекта.
///
/// Как использовать: `const ConfigTarget.user()` — умолчание подкоманд;
/// `ConfigTarget.project(cwd)` — флаг `--project`,
/// `ConfigTarget.projectLocal(cwd)` — флаг `--local`. Путь к файлу по цели
/// строит писатель хоста.
final class ConfigTarget {
  const ConfigTarget.user() : layer = ConfigLayer.user, cwd = null;

  const ConfigTarget.project(String this.cwd) : layer = ConfigLayer.project;

  const ConfigTarget.projectLocal(String this.cwd)
    : layer = ConfigLayer.projectLocal;

  final ConfigLayer layer;

  /// Каталог проекта; `null` у слоя `user`.
  final String? cwd;

  @override
  bool operator ==(Object other) =>
      other is ConfigTarget && other.layer == layer && other.cwd == cwd;

  @override
  int get hashCode => Object.hash(layer, cwd);

  @override
  String toString() =>
      'ConfigTarget(${layer.name}${cwd == null ? '' : ', $cwd'})';
}

/// Прочитанный слой: основа оптимистичной записи (§17.5.5, шаг 4).
///
/// Почему отпечаток: между `read` и `apply` файл мог измениться руками или
/// другим писателем; `apply` сравнивает sha256 байтов с [fingerprint] и при
/// расхождении бросает [ConfigConflictException], а не затирает чужую правку.
///
/// Как использовать: получает от писателя `read(target)`; клиент читает
/// значения через [get] и возвращает тот же снимок в `apply`.
final class ConfigSnapshot {
  const ConfigSnapshot({
    required this.target,
    required this.path,
    required this.fingerprint,
    required this.values,
  });

  final ConfigTarget target;

  /// Путь файла после разрешения символической ссылки.
  final String path;

  /// sha256 байтов файла; `null` — файла нет.
  final String? fingerprint;

  /// Разобранный слой без слияния с остальными.
  final Map<String, Object?> values;

  /// Значение по пути ключа: `providers.openai.base_url`,
  /// `mcp.servers[github].url` (элемент списка по `name` или номеру),
  /// `providers.local.models."qwen2.5-coder-32b".context_window` (сегмент в
  /// кавычках — одно имя). Поддерево возвращается целиком; нет ключа,
  /// сервера или индекса, а также путь с пустым сегментом или незакрытой
  /// кавычкой или скобкой — `null`.
  Object? get(String key) {
    final segments = splitKeyPath(key);
    if (segments == null) {
      return null;
    }
    Object? node = values;
    for (final segment in segments) {
      if (segment.isElement) {
        node = _element(node, segment.value);
      } else if (node is Map<String, Object?>) {
        node = node[segment.value];
      } else {
        return null;
      }
      if (node == null) {
        return null;
      }
    }
    return node;
  }

  /// Сначала по полю `name`, и только если элемента с таким именем нет и
  /// селектор — число, по индексу. Так сервер, названный `0`, не
  /// перекрывается первым элементом списка (имя в конфиге — то, что видит
  /// человек).
  static Object? _element(Object? list, String selector) {
    if (list is! List<Object?>) {
      return null;
    }
    for (final item in list) {
      if (item is Map<String, Object?> && item['name'] == selector) {
        return item;
      }
    }
    final index = int.tryParse(selector);
    if (index != null && index >= 0 && index < list.length) {
      return list[index];
    }
    return null;
  }
}

const _deepEquality = DeepCollectionEquality();

/// Одна правка конфигурации (§17.5.2). Запечатанная иерархия: писатель
/// разбирает её `switch`-ом без `default`, и новая правка не пройдёт
/// мимо компилятора.
///
/// Равенство — по значению, включая вложенные списки и отображения: тесты
/// и клиентские Cubit сравнивают списки правок.
sealed class ConfigEdit {
  const ConfigEdit();
}

/// Записывает [value] по пути [key]; недостающие предки создаются.
final class SetValue extends ConfigEdit {
  const SetValue(this.key, this.value);

  final String key;
  final Object value;

  @override
  bool operator ==(Object other) =>
      other is SetValue &&
      other.key == key &&
      _deepEquality.equals(other.value, value);

  @override
  int get hashCode => Object.hash(key, _deepEquality.hash(value));

  @override
  String toString() => 'SetValue($key)';
}

/// Удаляет ключ. Принимает и ключ вне реестра, если он есть в файле: так
/// убираются опечатки и запрещённые ключи вроде `api_key` (§17.5.5).
final class UnsetValue extends ConfigEdit {
  const UnsetValue(this.key);

  final String key;

  @override
  bool operator ==(Object other) => other is UnsetValue && other.key == key;

  @override
  int get hashCode => Object.hash(UnsetValue, key);

  @override
  String toString() => 'UnsetValue($key)';
}

/// Добавляет или заменяет элемент `mcp.servers` по полю `name`.
final class UpsertMcpServer extends ConfigEdit {
  const UpsertMcpServer(this.server);

  final Map<String, Object?> server;

  @override
  bool operator ==(Object other) =>
      other is UpsertMcpServer && _deepEquality.equals(other.server, server);

  @override
  int get hashCode => _deepEquality.hash(server);

  /// Без значений: в `server` могут быть `env` и `headers`.
  @override
  String toString() => 'UpsertMcpServer(${server['name']})';
}

/// Удаляет элемент `mcp.servers` с данным `name`.
final class RemoveMcpServer extends ConfigEdit {
  const RemoveMcpServer(this.name);

  final String name;

  @override
  bool operator ==(Object other) =>
      other is RemoveMcpServer && other.name == name;

  @override
  int get hashCode => Object.hash(RemoveMcpServer, name);

  @override
  String toString() => 'RemoveMcpServer($name)';
}

/// Удаляет ключ-отображение целиком со всем поддеревом:
/// `providers.local-1234` убирает и `providers.local-1234.models.*`.
final class RemoveTable extends ConfigEdit {
  const RemoveTable(this.key);

  final String key;

  @override
  bool operator ==(Object other) => other is RemoveTable && other.key == key;

  @override
  int get hashCode => Object.hash(RemoveTable, key);

  @override
  String toString() => 'RemoveTable($key)';
}

/// Файл изменился после `read` или занят блокировкой другого писателя.
///
/// Почему тип ядра, а не `codelab_agent_io`: клиенты ловят его через
/// реэкспорт моста `codelab_setup`, не видя пакет с `dart:io` (D5,
/// `dart-agent-and-clients` §12.4.2). Намеренно не подкласс
/// `ConfigException`: это не проблема содержимого конфига, а гонка записи.
///
/// Как использовать: поймав исключение, клиент перечитывает снимок и
/// повторяет правки (§17.5.5, шаг 4).
final class ConfigConflictException implements Exception {
  const ConfigConflictException(this.path);

  /// Файл конфигурации, из-за которого записи не вышло.
  final String path;

  @override
  String toString() =>
      'ConfigConflictException: $path changed since it was read or is '
      'being written by another process';
}
