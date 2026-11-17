/// Описание MCP-сервера сессии (`agent-core-architecture` §1.2, §6.4;
/// design.md change `add-agent-mcp-client`, D3).
///
/// Почему в ядре: серверы приходят из трёх источников — `session/new` ACP,
/// конфигурации и встроенного режима, — и все они должны проходить одни и те
/// же правила слияния и фильтра по capability (D6). Ядро знает только «что
/// запускать», а не протокол MCP.
library;

import '../secrets/secret_template.dart';

/// Откуда пришёл сервер: сервер клиента заменяет сервер конфига с тем же
/// именем (§13.4, шаг 2), а `AgentSession.setMcpServers` меняет только
/// серверы `session` (D11).
enum McpServerOrigin { config, session }

/// Сервер MCP: общая часть и две ветки транспорта.
///
/// Как использовать: хост (ACP-адаптер, конфигурация) создаёт значения и
/// передаёт в `SessionSpec.mcpServers` / `CoreConfig.mcpServers`. [name] —
/// ключ слияния и часть имён инструментов; [connectTimeout] — предел всего
/// подключения одного сервера (по умолчанию 10 с, §13.4, §15).
///
/// Значения [McpStdioServerConfig.env] и [McpHttpServerConfig.headers] —
/// секреты: их нельзя писать в логи и журнал (D6, D13), поэтому
/// `toString()` ветвей их не раскрывает.
sealed class McpServerConfig {
  const McpServerConfig({
    required this.name,
    this.origin = McpServerOrigin.session,
    this.connectTimeout = defaultMcpConnectTimeout,
    this.callTimeout,
    this.secretValues = const {},
    this.enabled = true,
    this.blockedReason,
  });

  final String name;
  final McpServerOrigin origin;

  /// `false` — ключ конфигурации `mcp.servers[*].enabled: false`: сервер
  /// доходит до коннектора, держится в состоянии `disabled` без подключения,
  /// и `/mcp list` его показывает; `setEnabled(name, true)` подключает его в
  /// сессии, не меняя конфиг (design.md change `add-config-writer-and-reload`,
  /// D10, D11).
  ///
  /// Не входит в [sameConnection]: это не параметр соединения, а выбор, нужен
  /// ли процесс. Смену признака сравнивают отдельно (`replaceServers`,
  /// `planConfigReload`): `true → false` закрывает сервер, `false → true` —
  /// новый сервер (для stdio — после перезапуска, R0-1).
  final bool enabled;

  /// Причина, по которой загрузка запретила подключать сервер, или `null`
  /// (change `bind-mcp-secrets-to-origin`, D4, D5; agent-secrets «Ссылки
  /// MCP-сервера проектного слоя привязаны к адресу»).
  ///
  /// Почему поле, а не отбрасывание сервера: сервер проектного слоя со
  /// ссылкой `${secret:…}` / `${ENV}`, не привязанной к его адресу, отдал бы
  /// ключ пользователя чужому хосту. Загрузка не раскрывает такие ссылки (в
  /// объекте нет ни значения, ни шаблона), но оставляет сервер в списке:
  /// пользователь видит `failed` и совет в `/mcp list` и панели статуса.
  ///
  /// Для чего: коннектор (`codelab_agent_mcp`) проверяет поле первым в
  /// попытке подключения, до раскрытия секретов и до транспорта, и переводит
  /// сервер в `failed` с `lastError` = этому тексту. Текст без значений
  /// секретов и без пути файла; `lastError` обрезается до 200 символов, поэтому
  /// совет стоит до имени ссылки.
  ///
  /// Как использовать: задаёт только загрузка конфигурации. Входит в
  /// [sameConnection]: правка глобального слоя меняет вердикт для неизменённого
  /// проектного сервера, и перезагрузка заменяет его в живых сессиях (D6).
  /// `withEnabled` и `withSecrets` поле сохраняют.
  final String? blockedReason;
  final Duration connectTimeout;

  /// Предел одного `tools/call` этого сервера (ключ конфигурации
  /// `mcp.servers[*].call_timeout`, design.md change
  /// `add-agent-configuration`, D10). `null` — умолчание коннектора
  /// (`McpClientOptions.callTimeout`): так у серверов `session/new`, в ACP
  /// такого параметра нет, и новые поля не придумываются. Не входит в
  /// [sameConnection]: срок вызова не влияет на соединение.
  final Duration? callTimeout;

  /// Значения `env.<KEY>` / `headers.<Name>` со ссылками `${secret:<name>}`
  /// (design.md change `add-agent-secret-store`, D4): шаблоны, которые
  /// рантайм раскрывает перед `connect`. Пусто у серверов клиента ACP —
  /// `${secret:…}` от клиента литерал, иначе он вытянул бы любой секрет
  /// хранилища на свой адрес. Эти значения НЕ входят в `env`/`headers`.
  final Map<String, SecretTemplate> secretValues;

  /// Копия сервера, где шаблоны [secretValues] раскрыты в значения [values]
  /// (ключ как в [secretValues]) и добавлены к `env`/`headers`; шаблонов у
  /// копии нет, а [enabled] и остальные параметры сохраняются. Значения живут только в объекте, переданном коннектору
  /// (D4): `toString` их не раскрывает.
  McpServerConfig withSecrets(Map<String, String> values);

  /// Копия с другим [enabled]; остальные параметры прежние. Нужна перезагрузке
  /// конфига (R6-1): выключение применяется сразу, а правка соединения того
  /// же элемента ждёт перезапуска, поэтому в снимке остаётся прежний элемент
  /// с `enabled: false`.
  McpServerConfig withEnabled(bool enabled);

  /// Ключ транспорта для capability `mcp`: `stdio` или `http`.
  String get transport;

  /// Совпадают ли параметры подключения (без [origin]): по ним
  /// `setMcpServers` решает, оставить ли уже подключённый сервер (D11).
  bool sameConnection(McpServerConfig other);
}

/// Предел подключения одного сервера по умолчанию (§13.4, §15).
const defaultMcpConnectTimeout = Duration(seconds: 10);

/// Локальный процесс, говорящий с агентом по stdin/stdout (ACP: stdio —
/// обязательный транспорт, `03-Session Setup.md`).
final class McpStdioServerConfig extends McpServerConfig {
  const McpStdioServerConfig({
    required super.name,
    required this.command,
    this.args = const [],
    this.env = const {},
    super.origin,
    super.connectTimeout,
    super.callTimeout,
    super.secretValues,
    super.enabled,
    super.blockedReason,
  });

  final String command;
  final List<String> args;

  /// Переменные окружения сервера поверх базового набора §4.5 (ENV-6).
  final Map<String, String> env;

  @override
  String get transport => 'stdio';

  @override
  McpStdioServerConfig withSecrets(Map<String, String> values) =>
      McpStdioServerConfig(
        name: name,
        command: command,
        args: args,
        env: {
          ...env,
          for (final MapEntry(:key, :value) in values.entries)
            if (key.startsWith('env.')) key.substring(4): value,
        },
        origin: origin,
        connectTimeout: connectTimeout,
        callTimeout: callTimeout,
        enabled: enabled,
        blockedReason: blockedReason,
      );

  @override
  McpStdioServerConfig withEnabled(bool enabled) => McpStdioServerConfig(
    name: name,
    command: command,
    args: args,
    env: env,
    origin: origin,
    connectTimeout: connectTimeout,
    callTimeout: callTimeout,
    secretValues: secretValues,
    enabled: enabled,
    blockedReason: blockedReason,
  );

  @override
  bool sameConnection(McpServerConfig other) =>
      other is McpStdioServerConfig &&
      other.blockedReason == blockedReason &&
      other.name == name &&
      other.command == command &&
      _listEquals(other.args, args) &&
      _mapEquals(other.env, env) &&
      _mapEquals(other.secretValues, secretValues);

  @override
  String toString() => 'McpStdioServerConfig($name)';
}

/// Удалённый сервер streamable HTTP.
final class McpHttpServerConfig extends McpServerConfig {
  const McpHttpServerConfig({
    required super.name,
    required this.url,
    this.headers = const [],
    super.origin,
    super.connectTimeout,
    super.callTimeout,
    super.secretValues,
    super.enabled,
    super.blockedReason,
    this.secretHeaderPositions = const {},
  });

  final Uri url;

  /// Заголовки в порядке, присланном клиентом (или заданном в конфиге, без
  /// заголовков-шаблонов — те в [secretValues]).
  final List<(String, String)> headers;

  /// Имя заголовка-шаблона → его индекс среди ВСЕХ заголовков в порядке
  /// файла конфига.
  ///
  /// Почему: шаблоны лежат отдельно от [headers], и без индекса раскрытый
  /// заголовок попал бы в конец списка. Порядок заголовков наблюдаем
  /// сервером, поэтому перестановка из-за способа хранения была бы скрытым
  /// изменением поведения (design.md change `add-agent-secret-store`, D4).
  /// Использует [withSecrets]; у серверов клиента пусто.
  final Map<String, int> secretHeaderPositions;

  @override
  String get transport => 'http';

  @override
  McpHttpServerConfig withSecrets(Map<String, String> values) {
    // Вставка по возрастанию индекса возвращает каждый заголовок на его
    // место в файле конфига; заголовок без индекса уходит в конец.
    final resolved = [
      for (final MapEntry(:key, :value) in values.entries)
        if (key.startsWith('headers.')) (key.substring(8), value),
    ]..sort((a, b) => _position(a.$1).compareTo(_position(b.$1)));
    final all = [...headers];
    for (final header in resolved) {
      final at = secretHeaderPositions[header.$1];
      all.insert(at == null || at > all.length ? all.length : at, header);
    }
    return McpHttpServerConfig(
      name: name,
      url: url,
      headers: all,
      origin: origin,
      connectTimeout: connectTimeout,
      callTimeout: callTimeout,
      enabled: enabled,
      blockedReason: blockedReason,
    );
  }

  @override
  McpHttpServerConfig withEnabled(bool enabled) => McpHttpServerConfig(
    name: name,
    url: url,
    headers: headers,
    origin: origin,
    connectTimeout: connectTimeout,
    callTimeout: callTimeout,
    secretValues: secretValues,
    secretHeaderPositions: secretHeaderPositions,
    enabled: enabled,
    blockedReason: blockedReason,
  );

  int _position(String header) =>
      secretHeaderPositions[header] ?? 1 << 30; // без индекса — в конец

  @override
  bool sameConnection(McpServerConfig other) =>
      other is McpHttpServerConfig &&
      other.blockedReason == blockedReason &&
      other.name == name &&
      other.url == url &&
      _listEquals(other.headers, headers) &&
      _mapEquals(other.secretValues, secretValues) &&
      _mapEquals(other.secretHeaderPositions, secretHeaderPositions);

  @override
  String toString() => 'McpHttpServerConfig($name)';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _mapEquals<V>(Map<String, V> a, Map<String, V> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
