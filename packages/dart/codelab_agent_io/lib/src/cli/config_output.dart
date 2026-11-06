import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../config/environment_layer.dart' show environmentLayerVariables;

/// Замена непрозрачного поддерева схемы (R0-2): схемы его листьев в этой
/// сборке нет, и правило имён не гарантирует, что секрет не лежит под
/// безобидным именем.
const opaqueMask = '<opaque: edit the file>';

/// Маскирует значение для вывода `config get` и `provider list` (R0-2;
/// design.md change `add-config-writer-and-reload`, D6; agent-configuration
/// «Подкоманды записи и чтения конфига»).
///
/// Почему отдельная функция: подкоманды печатают значения, а файл мог быть
/// правлен руками до редакции секретов (8.11), поэтому литеральный токен в
/// нём возможен. Маскирование одно на `config get` и `provider list`: два
/// правила разошлись бы, и один из выводов начал бы печатать то, что другой
/// скрывает.
///
/// Для чего: правила (по порядку проверки узла):
/// - непрозрачное поддерево реестра (`providers.*.auth`, `key_rotation`,
///   разделы после MVP) и узел без схемы листьев → [opaqueMask];
/// - значение слоя без файла ([layer] — окружение, флаги) → `<from env:…>` /
///   `<from flags>` вместо значения: переменная могла прийти из секретного
///   хранилища оркестратора;
/// - строковый лист (кроме адресов) с литералом по шаблону секрета, в том
///   числе в литеральной части смешанного значения и в `${secret:<токен>}`,
///   → [redactedMask] — независимо от имени и от реестра
///   (`literalSecretTag`, `hasInlineSecret`; D5);
/// - лист, чьё имя — ключ из `inlineSecretKeys` или секретное по нормализованному
///   правилу писателя (`isSecretLikeName`), без `${…}` → [redactedMask];
///   листья, описанные схемой (`api_key_secret`, `api_key_env`, `auth_header`,
///   `max_output_tokens`), хранят имена и счётчики и печатаются как есть,
///   кроме `api_key` (литерал) и значений по шаблону секрета;
/// - `base_url` и `url` — без userinfo, значения секретных query-параметров
///   → [redactedMask], неразбираемый адрес → [redactedMask] ([maskUrl]);
/// - элементы `mcp.servers[*].args` — по шаблону, после секретного флага и в
///   `--флаг=значение` ([_Masker._maskArgs]; R4-6, OQ3, D5 change
///   `add-config-literal-secrets-and-migrate`); путь на один элемент
///   (`…args[1]`) маскируется через родительский список;
/// - отображения и списки маскируются поэлементно на любой глубине.
///
/// Как использовать: [key] — путь ключа в форме `KeyPath` (`providers.p`,
/// `mcp.servers`), по нему ищутся дескрипторы реестра; [value] — значение
/// этого ключа из слоя [layer] (`null` — слой файла). Возвращает дерево той же
/// формы, пригодное для [renderConfigValue]. Значения в исключения и логи не
/// попадают.
Object? maskConfigValue(
  Object? value, {
  required String key,
  ConfigTree? layer,
}) {
  final segments = splitKeyPath(key);
  var name = '';
  if (segments != null) {
    for (final segment in segments.reversed) {
      if (!segment.isElement) {
        name = segment.value;
        break;
      }
    }
  }
  // Ключ приводится к каноническому виду по разобранным сегментам: правила
  // маскера (`args`, реестр) опознают позицию по строке, а человек может
  // написать `mcp."servers"[gh]."args"` (обход маски, ревью итерации 2).
  final canonical = segments == null
      ? key
      : segments.fold<String>('', (path, segment) {
          if (segment.isElement) {
            return '$path[${segment.value}]';
          }
          final part = _plainName.hasMatch(segment.value)
              ? segment.value
              : '"${segment.value}"';
          return path.isEmpty ? part : '$path.$part';
        });
  final masker = _Masker(layer);
  // Путь на элемент `args` (`mcp.servers[gh].args[1]`): маска зависит от
  // соседей (`--token` перед значением), поэтому маскируется родительский
  // список, а из него берётся элемент по индексу. Нет слоя, родителя или
  // индекса — fail closed (`_failClosedArg`).
  // Глубже элемента (`…args[0][0]`, `…args[0].k`) — вложенный элемент
  // невалидного `args`: непрозрачен, как и сам List/Map-элемент.
  if (_argsDeeperPath.hasMatch(canonical)) {
    return opaqueMask;
  }
  final element = _argsElementPath.firstMatch(canonical);
  if (element != null) {
    return masker.maskArgsElement(
      value,
      parentKey: element.group(1)!,
      index: int.tryParse(element.group(2)!),
    );
  }
  return masker.mask(value, canonical, name);
}

/// Строки для stdout: скаляр — одна строка, отображение и список — JSON с
/// отступом (подстановки `${VAR}` JSON не экранирует, поэтому печатаются как
/// в файле).
List<String> renderConfigValue(Object? value) => switch (value) {
  Map<Object?, Object?>() || List<Object?>() => const JsonEncoder.withIndent(
    '  ',
  ).convert(value).split('\n'),
  _ => ['$value'],
};

/// Имя слоя в выводе `config get`: `user`, `project`, `local`, `extra`
/// (файл `CODELAB_CONFIG`), `env`, `flags`.
String configLayerName(ConfigLayerKind kind) => switch (kind) {
  ConfigLayerKind.defaults => 'defaults',
  ConfigLayerKind.user => 'user',
  ConfigLayerKind.project => 'project',
  ConfigLayerKind.projectLocal => 'local',
  ConfigLayerKind.extra => 'extra',
  ConfigLayerKind.environment => 'env',
  ConfigLayerKind.flags => 'flags',
  ConfigLayerKind.appStorage => 'app',
};

final _plainName = RegExp(r'^[A-Za-z0-9_\-]+$');
final _reference = RegExp(r'\$\{[^}]+\}');

/// Путь списка `args` сервера MCP: `mcp.servers[gh].args`, `mcp.servers[0].args`.
final _argsPath = RegExp(r'^mcp\.servers\[[^\]]+\]\.args$');

/// Путь на элемент списка `args`: группа 1 — путь списка, группа 2 — селектор.
final _argsElementPath = RegExp(
  r'^(mcp\.servers\[[^\]]+\]\.args)\[([^\]]+)\]$',
);

/// Путь глубже элемента `args`.
final _argsDeeperPath = RegExp(r'^mcp\.servers\[[^\]]+\]\.args\[[^\]]+\][.\[]');

/// Ведущие дефисы имени флага.
final _leadingDashes = RegExp(r'^-+');

/// Шаблоны ключей реестра по сегментам: нужны проверке «под узлом есть схема».
final List<List<String>> _patterns = [
  for (final d in SettingsRegistry.all) d.key.split('.'),
];

final class _Masker {
  const _Masker(this._layer);

  final ConfigTree? _layer;

  Object? mask(Object? node, String path, String name) {
    if (_isOpaque(path)) {
      return opaqueMask;
    }
    switch (node) {
      case Map<Object?, Object?>():
        if (_unknownContainer(path)) {
          return opaqueMask;
        }
        return {
          for (final MapEntry(:key, :value) in node.entries)
            '$key': mask(value, _child(path, '$key'), '$key'),
        };
      case List<Object?>():
        if (_unknownContainer(path)) {
          return opaqueMask;
        }
        if (_argsPath.hasMatch(path)) {
          return _maskArgs(node);
        }
        final names = [
          for (final item in node) item is Map ? item['name'] : null,
        ];
        return [
          for (var i = 0; i < node.length; i++)
            mask(node[i], _element(path, names, i), name),
        ];
      default:
        return _leaf(node, path);
    }
  }

  /// Маскирует элементы `mcp.servers[*].args` (R4-6, OQ3; design.md change
  /// `add-config-literal-secrets-and-migrate`, D5).
  ///
  /// Почему отдельно от листьев: аргументы — плоский список строк, имени у
  /// элемента нет, а токен приходит парой `--token <значение>` или
  /// `--token=<значение>`. Правила по порядку для элемента:
  /// - значение слоя без файла (`env`, флаги) → метка источника, как у
  ///   прочих листьев ([_foreignLabel]), проверяется один раз для списка;
  /// - литерал по шаблону §12.4 ([literalSecretTag]) → [redactedMask];
  /// - элемент (любого типа) после флага `-…` с секретным именем (то же
  ///   правило, что у заголовков, [isSecretLikeName]; ложные срабатывания
  ///   вроде `--max-tokens` допустимы: скрыть лишнее дешевле) →
  ///   [redactedMask]; исключения: следующий `--флаг` и чистая ссылка
  ///   `${…}` без литеральной части (fail closed: `${X}literal` скрывается);
  /// - `--<секретное имя>=<значение>` → `--<имя>=<redacted>` с теми же
  ///   исключениями;
  /// - прочее, включая ссылки и несекретные флаги, — как есть.
  /// Граница: короткие флаги (`-p hunter2`) не маскируются — по имени
  /// `p` секретность не определить. Действует при любом `--layer`: слой
  /// выбирает значение, а не правила.
  List<Object?> _maskArgs(List<Object?> args) {
    if (_foreignLabel('mcp.servers') case final label?) {
      return [for (final _ in args) label];
    }
    final result = <Object?>[];
    var afterSecretFlag = false;
    for (final item in args) {
      final wasSecretFlag = afterSecretFlag;
      afterSecretFlag = false;
      // Вложенный список или отображение — невалидный `args` ручной правки.
      // Схемы листьев нет, секрет под любым именем не отличить, поэтому
      // [opaqueMask], как у прочих неописанных поддеревьев ([_unknownContainer]).
      if (item is Map || item is List) {
        result.add(opaqueMask);
        continue;
      }
      if (item is! String) {
        result.add(wasSecretFlag ? redactedMask : item);
        continue;
      }
      if (literalSecretTag(item) != null) {
        result.add(redactedMask);
        continue;
      }
      // Значение после секретного флага: не `--флаг`, не пусто и не чистая
      // ссылка. Один дефис (`-s3cr3t`) значение, а не флаг известной формы.
      if (wasSecretFlag && !item.startsWith('--')) {
        result.add(_hidesLiteral(item) ? redactedMask : item);
        continue;
      }
      if (!item.startsWith('-')) {
        result.add(item);
        continue;
      }
      final eq = item.indexOf('=');
      final flagName = (eq < 0 ? item : item.substring(0, eq)).replaceFirst(
        _leadingDashes,
        '',
      );
      final secretFlag = isSecretLikeName(flagName);
      if (eq < 0) {
        afterSecretFlag = secretFlag;
        result.add(item);
      } else if (secretFlag && _hidesLiteral(item.substring(eq + 1))) {
        result.add('${item.substring(0, eq)}=$redactedMask');
      } else {
        result.add(item);
      }
    }
    return result;
  }

  /// Значение секретного флага содержит литерал: оно не пусто и вне ссылок
  /// `${…}` остаётся текст.
  bool _hidesLiteral(String value) =>
      value.replaceAll(_reference, '').isNotEmpty;

  /// Один элемент `args`, адресованный путём `…args[<индекс>]` (см.
  /// [maskConfigValue]): родительский список берётся из слоя, маскируется
  /// целиком, и из результата читается элемент по индексу.
  Object? maskArgsElement(
    Object? value, {
    required String parentKey,
    required int? index,
  }) {
    final parent = _layer == null
        ? null
        : ConfigSnapshot(
            target: const ConfigTarget.user(),
            path: _layer.source,
            fingerprint: null,
            values: _layer.values,
          ).get(parentKey);
    if (parent is List<Object?> && index != null) {
      final masked = _maskArgs(parent);
      if (index >= 0 && index < masked.length) {
        return masked[index];
      }
    }
    // Родителя не получить: без соседей `--token` не узнать, поэтому
    // скрывается всё, кроме чистой ссылки и флага без значения.
    if (_foreignLabel('mcp.servers') case final label?) {
      return label;
    }
    if (value is! String) {
      return value == null ? null : redactedMask;
    }
    if (literalSecretTag(value) != null) {
      return redactedMask;
    }
    // Как есть — только `--флаг` без значения; одиночный `-x` без соседей
    // мог быть значением секретного флага, поэтому идёт по правилу значения.
    if (value.startsWith('--')) {
      final eq = value.indexOf('=');
      return eq < 0 || !_hidesLiteral(value.substring(eq + 1))
          ? value
          : '${value.substring(0, eq)}=$redactedMask';
    }
    return _hidesLiteral(value) ? redactedMask : value;
  }

  Object? _leaf(Object? value, String path) {
    if (value == null) {
      return null;
    }
    if (_foreignLabel(path) case final label?) {
      return label;
    }
    // Правила листа общие с `/settings` клиентов — в ядре
    // (`displaySafeConfigValue`, R0-2): вывод не расходится с мостом.
    return displaySafeConfigValue(path, value);
  }

  String? _foreignLabel(String path) {
    final layer = _layer;
    if (layer == null) {
      return null;
    }
    switch (layer.kind) {
      case ConfigLayerKind.flags:
        return '<from flags>';
      case ConfigLayerKind.environment:
        if (layer.source.startsWith('env:')) {
          return '<from ${layer.source}>';
        }
        final variable = environmentLayerVariables[path];
        return variable == null ? '<from env>' : '<from env:$variable>';
      default:
        return null;
    }
  }

  /// Непрозрачное поддерево реестра: ключ типа `map`, помеченный «не
  /// поддерживается в этой сборке» (`_opaque` реестра). Подсказка файлу
  /// (`providers.*.headers`, `exec`) под это не подпадает.
  bool _isOpaque(String path) {
    final d = SettingsRegistry.lookup(path);
    return d != null &&
        d.scope == SettingScope.fileOnly &&
        d.type == SettingType.map &&
        (d.fileOnlyReason ?? '').startsWith('not supported in this version');
  }

  /// Узел-контейнер, про который реестр ничего не знает: ни дескриптора, ни
  /// листьев ниже. Секрет под безобидным именем здесь не отличить, поэтому
  /// поддерево скрывается целиком (fail closed).
  bool _unknownContainer(String path) {
    if (SettingsRegistry.lookup(path) != null) {
      return false;
    }
    final segments = splitKeyPath(path);
    if (segments == null) {
      return true;
    }
    final names = [
      for (final s in segments) s.isElement ? '[${s.value}]' : s.value,
    ];
    for (final pattern in _patterns) {
      if (pattern.length <= names.length) {
        continue;
      }
      var matches = true;
      for (var i = 0; i < names.length && matches; i++) {
        matches = pattern[i] == '*'
            ? !names[i].startsWith('[')
            : pattern[i] == names[i];
      }
      if (matches) {
        return false;
      }
    }
    return true;
  }

  /// Дочерний путь: имя с точкой или иными знаками берётся в кавычки, иначе
  /// `KeyPath.child` склеил бы `gpt-4.1` в два сегмента.
  String _child(String path, String name) {
    final segment = _plainName.hasMatch(name) ? name : '"$name"';
    return path.isEmpty ? segment : '$path.$segment';
  }

  /// Путь элемента списка: по `name`, пока оно уникально, иначе по номеру (как
  /// в правиле литеральных секретов писателя).
  String _element(String path, List<Object?> names, int index) {
    final name = names[index];
    final unique =
        name is String &&
        name.isNotEmpty &&
        names.where((other) => other == name).length == 1;
    return '$path[${unique ? name : index}]';
  }
}

/// Значение ключа в слое и сам слой (`config get`, `provider list`).
typedef LayerValue = ({Object? value, ConfigTree layer});

/// Находит значение [key] в слоях [layers] (порядок возрастания приоритета):
/// победитель — старший слой, где ключ задан; при [only] смотрится слой
/// такого вида.
///
/// Почему сырое значение слоя, а не итог загрузки: `config get` не должен
/// раскрывать `${VAR}` и `${secret:…}` (agent-configuration «get не раскрывает
/// переменную»), а итог `CoreConfig` уже содержит подстановки. Для списка
/// `mcp.servers` победителем остаётся слой целиком: слияние по `name`
/// подкоманда не воспроизводит.
///
/// Как использовать: `null` — ключа нет ни в одном подходящем слое; иначе
/// значение печатается через [maskConfigValue] с тем же слоем.
LayerValue? findLayerValue(
  List<ConfigTree> layers,
  String key, {
  ConfigLayerKind? only,
}) {
  for (final layer in layers.reversed) {
    if (only != null && layer.kind != only) {
      continue;
    }
    final value = ConfigSnapshot(
      target: const ConfigTarget.user(),
      path: layer.source,
      fingerprint: null,
      values: layer.values,
    ).get(key);
    if (value != null) {
      return (value: value, layer: layer);
    }
  }
  return null;
}
