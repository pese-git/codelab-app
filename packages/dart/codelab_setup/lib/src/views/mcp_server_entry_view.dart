/// Строка страницы «MCP servers» (`dart-agent-and-clients` §12.4.6; design.md
/// change `add-provider-setup-ui`, D11 «Сверка с кодом», D17; R0-2, SETUP-1).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        ConfigLayer,
        KeyPath,
        displaySafeConfigValue,
        hidesConfigLiteral,
        maskMcpArgs,
        redactedMask;

import '../config/agent_config_store.dart';
import '../config/config_source_view.dart';
import '../mcp/mcp_layers.dart';
import '../mcp/mcp_transport_kind.dart';

/// Сервер в списке страницы «MCP servers».
///
/// Почему модель в мосте: строка строится по элементу слоя-источника, а не по
/// итоговому списку (элемент-переопределение `projectLocal` заменяет сервер
/// целиком), а значения `args`, `env` и `headers` проходят то же правило
/// показа, что `provider list`, `config get` и `SettingFieldView`
/// (`displaySafeConfigValue`, `maskMcpArgs`, `maskUrl` для URL): `codelab mcp
/// list` эти поля не печатает, образцом служить не может.
///
/// Для чего: общий вход страницы app и списка CLI. Значения уже очищены от
/// литеральных секретов; для правки используется сырой элемент слоя
/// ([mcpServerElementOf]), а не поля вида. Признак [masked] даёт мост: клиент
/// не сравнивает значения с литералом маски.
///
/// Как использовать: поля только для чтения; [editable] `false` у слоя 3 —
/// кнопок записи нет, вместо них «Disable here»; [disabledHere] — сервер
/// слоя 3 отключён переопределением `projectLocal`, вместо кнопки «Disable
/// here» показывается «Enable here» (Q21).
final class McpServerEntryView {
  const McpServerEntryView({
    required this.name,
    required this.kind,
    required this.command,
    required this.args,
    required this.url,
    required this.env,
    required this.headers,
    required this.enabled,
    required this.disabledHere,
    required this.source,
    required this.editable,
    required this.masked,
  });

  final String name;
  final McpTransportKind kind;

  /// Команда `stdio`; `null` у `http`.
  final String? command;
  final List<String> args;

  /// Адрес `http` без userinfo и секретных параметров; `null` у `stdio`.
  final String? url;
  final Map<String, String> env;
  final Map<String, String> headers;
  final bool enabled;
  final bool disabledHere;

  /// Файл слоя элемента, по которому построена строка.
  final ConfigSourceView source;

  /// Правится ли сервер записью конфига: слои `user` и `projectLocal`
  /// (SETUP-3), и не «disabled here».
  final bool editable;

  /// Хотя бы одно значение изменено маскированием секретов.
  final bool masked;

  /// Цель строки: команда с аргументами или адрес.
  String get target =>
      kind == McpTransportKind.http ? url ?? '' : [?command, ...args].join(' ');

  // Значения в строку не попадают намеренно (SETUP-1).
  @override
  String toString() =>
      'McpServerEntryView($name, ${kind.name}, ${source.kind.name})';
}

/// Строит строки страницы по [snapshot]: серверы эффективного конфига в
/// порядке слияния слоёв.
///
/// Почему не читает файлы сама: всё берётся из снимка; слой недоверенного
/// проекта (CFG-3) загрузчик не применил, и его серверов в списке нет.
List<McpServerEntryView> mcpServerEntriesOf(AgentConfigSnapshot snapshot) => [
  for (final server in effectiveMcpServers(snapshot))
    _entryOf(snapshot, server),
];

/// Сырой элемент `mcp.servers` слоя-источника (как в файле, со ссылками
/// `${secret:…}` и `${VAR}`) для правки и переключателя `enabled`.
///
/// Почему отдельно от вида: `UpsertMcpServer` заменяет элемент целиком, и
/// запись из замаскированного вида стёрла бы или испортила значения.
final class McpServerLayerElement {
  const McpServerLayerElement({required this.layer, required this.element});

  final ConfigLayer layer;
  final Map<String, Object?> element;

  // Элемент может нести `env` и `headers`: в строку не попадает (SETUP-1).
  @override
  String toString() => 'McpServerLayerElement(${layer.name})';
}

/// Элемент эффективного сервера [name] или `null`, если такого нет (в том
/// числе в слое недоверенного проекта).
McpServerLayerElement? mcpServerElementOf(
  AgentConfigSnapshot snapshot,
  String name,
) {
  final server = effectiveMcpServer(snapshot, name);
  return server == null
      ? null
      : McpServerLayerElement(layer: server.layer, element: server.element);
}

McpServerEntryView _entryOf(
  AgentConfigSnapshot snapshot,
  EffectiveMcpServer server,
) {
  // «disabled here»: описание берётся из проектного элемента под
  // переопределением, источник — проектный файл.
  final element = server.projectElement ?? server.element;
  final layer = server.disabledHere ? ConfigLayer.project : server.layer;
  final name = server.name;
  var masked = false;

  String text(String key, Object? raw) {
    final shown = displaySafeConfigValue(_path(name, key), '$raw');
    if (shown != '$raw') {
      masked = true;
    }
    return '$shown';
  }

  // Значение заголовка показывается только если это чистая ссылка `${…}`
  // (ревью 5a): токен лежит и под нейтральным именем (`X-Workspace`), которого
  // правило имён `displaySafeConfigValue` не опознает. Значения `env` идут по
  // правилу имён и шаблонов, как у `config get` и `provider list`: нейтральные
  // (`LOG_LEVEL`) показываются открыто и там.
  String header(String raw) {
    if (hidesConfigLiteral(raw)) {
      masked = true;
      return redactedMask;
    }
    return raw;
  }

  Map<String, String> table(String field) {
    final raw = element[field];
    if (raw is! Map<Object?, Object?>) {
      return const {};
    }
    return {
      for (final entry in raw.entries)
        '${entry.key}': field == 'headers'
            ? header('${entry.value}')
            : text('$field.${_segment('${entry.key}')}', entry.value),
    };
  }

  final rawArgs = element['args'];
  final args = rawArgs is List<Object?>
      ? [for (final item in maskMcpArgs(rawArgs)) '$item']
      : const <String>[];
  if (rawArgs is List<Object?> &&
      [for (final item in rawArgs) '$item'].join('\u0000') !=
          args.join('\u0000')) {
    masked = true;
  }
  final rawCommand = element['command'];
  final rawUrl = element['url'];
  final kind = mcpTransportKindOf(element);
  final entry = McpServerEntryView(
    name: name,
    kind: kind,
    command: rawCommand == null ? null : text('command', rawCommand),
    args: args,
    url: rawUrl == null ? null : text('url', rawUrl),
    env: table('env'),
    headers: table('headers'),
    enabled: !server.disabledHere && element['enabled'] != false,
    disabledHere: server.disabledHere,
    source: sourceOfLayer(snapshot, layer),
    editable: !server.disabledHere && server.layer != ConfigLayer.project,
    masked: masked,
  );
  return entry;
}

String _segment(String key) => KeyPath.root.child(key).value;

/// Путь листа строки в формате `KeyPath`: `mcp.servers[<name>].<поле>`.
String _path(String name, String field) =>
    '${KeyPath.root.child('mcp').child('servers').at(name).value}.$field';
