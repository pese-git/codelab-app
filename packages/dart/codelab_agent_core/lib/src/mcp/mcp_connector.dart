import '../cancel/cancel_token.dart';
import '../loop/agent_events.dart';
import '../tools/agent_tool.dart';
import '../util/logger.dart';
import 'mcp_server_config.dart';

/// Подключение MCP-серверов сессии — сервис `AgentCoreServices.mcp`
/// (`agent-core-architecture` §10.3; design.md change `add-agent-mcp-client`,
/// D3, D6).
///
/// Почему порт «по списку серверов даёт инструменты», а не фабрика
/// транспортов: MCP-клиент живёт в пакете над ядром, ядро создать его не
/// может. Хосту нужна одна точка, а фабрики транспортов уходят внутрь
/// реализации (`McpClientConnector`).
///
/// Как использовать: ядро зовёт [connect] в `createSession` / `loadSession`
/// до возврата сессии; при сборке (`buildAgentCore`) проверяет, что
/// [transports] покрывает транспорты capability `mcp` (HOST-3).
abstract interface class McpConnector {
  /// Какие транспорты (`stdio`, `http`) умеет открывать коннектор.
  Set<String> get transports;

  /// Подключает серверы параллельно, каждый в своём `connectTimeout`; сбой
  /// сервера — лог `mcp.server.failed` и отсутствие его инструментов, а не
  /// исключение.
  Future<McpSessionTools> connect(McpConnectRequest request);
}

/// Запрос на подключение серверов одной сессии.
final class McpConnectRequest {
  McpConnectRequest({
    required this.sessionId,
    required this.cwd,
    required List<McpServerConfig> servers,
    required Set<String> reservedNames,
    required this.logger,
    required this.cancel,
    this.expandSecrets,
  }) : servers = List.unmodifiable(servers),
       reservedNames = Set.unmodifiable(reservedNames);

  final SessionId sessionId;

  /// Рабочая папка сессии: stdio-процесс стартует в ней.
  final String cwd;

  /// Уже слитый и отфильтрованный список (D6), в порядке регистрации.
  final List<McpServerConfig> servers;

  /// Имена базового реестра: имя MCP-инструмента, совпавшее с одним из них,
  /// отключает сервер (HOST-5).
  final Set<String> reservedNames;
  final Logger logger;

  /// Токен сессии: отменяется при `AgentSession.close()` и
  /// `AgentRuntime.dispose()`. Подключение (первое и в `replaceServers`)
  /// прерывается: не завершённый сервер закрывается, а закрытие сессии не
  /// ждёт `connectTimeout`.
  final CancelToken cancel;

  /// Раскрытие шаблонов `${secret:…}` сервера конфига перед каждой попыткой
  /// подключения, в том числе повторной (design.md change
  /// `add-config-writer-and-reload`, D11, «Секреты при переподключении»).
  ///
  /// Почему замыкание ядра, а не готовые значения: коннектор не должен
  /// хранить значение секрета между попытками, а после `SecretResolver.
  /// invalidate` новая попытка обязана взять новое значение. `null` —
  /// серверы пришли уже раскрытыми (или без шаблонов), и коннектор берёт их
  /// как есть.
  final McpSecretExpander? expandSecrets;
}

/// Раскрывает [McpServerConfig.secretValues] сервера в значения (ядро
/// строит замыкание над `SecretResolver`).
///
/// Как использовать: коннектор зовёт его перед каждой попыткой и использует
/// возвращённую копию только для этой попытки. Неудача — [McpSecretsException]
/// с текстом без значения секрета; коннектор делает её сбоем попытки.
typedef McpSecretExpander =
    Future<McpServerConfig> Function(McpServerConfig server);

/// Секрет сервера не раскрыт: не задан или хранилище недоступно.
///
/// Почему отдельный тип: причина попадает в `McpServerSummary.lastError` и в
/// лог, поэтому это готовый текст кода CodeLab (`secret <name> is not set`,
/// `secret <name> cannot be read: <backend> is unavailable`) — только имя
/// секрета, без значения (CFG-10).
final class McpSecretsException implements Exception {
  const McpSecretsException(this.reason);

  final String reason;

  @override
  String toString() => 'McpSecretsException: $reason';
}

/// Подключённые серверы одной сессии.
///
/// Как использовать: ядро кладёт [tools] в реестр сессии, берёт [servers]
/// для секции промпта `mcp`, на границе шага забирает [takeUpdate], в
/// `AgentSession.close()` зовёт [close].
abstract interface class McpSessionTools {
  /// В порядке регистрации (D6): серверы конфига, затем серверы клиента;
  /// внутри сервера — порядок `tools/list`.
  List<AgentTool> get tools;

  /// Все серверы сессии в порядке списка, в любом состоянии (D11): для
  /// секции промпта (§11.5; в неё входят серверы с инструментами) и таблицы
  /// `/mcp list`.
  List<McpServerSummary> get servers;

  /// Полный список сводок [servers] после каждой смены состояния сервера
  /// (`connecting`, `connected`, `failed`, `disabled`), числа его
  /// инструментов, `lastError` или состава серверов (`replaceServers`,
  /// `setEnabled`, `reconnect`) (design.md change `add-provider-setup-ui`,
  /// D12; `17-5-agent-setup.md`, OQ4).
  ///
  /// Поток широковещательный, НЕ повторяет последнее значение новому
  /// подписчику (снимок — [servers]) и закрывается в [close]. Сводки
  /// подчиняются правилам [servers]: `lastError` — текст кода CodeLab без
  /// текстов сервера и секретов. Хост получает его через `McpStatusPort`
  /// рантайма, а не напрямую.
  Stream<List<McpServerSummary>> get changes;

  /// Ожидающий результат `notifications/tools/list_changed`; забирает и
  /// очищает (D6). Ядро зовёт его только на границе шага и перед ходом.
  McpToolsUpdate? takeUpdate();

  /// Приводит подключённые серверы к [servers] (повторный `session/load`,
  /// `AgentSession.setMcpServers`, D11): совпавшие по `name` и параметрам
  /// (`McpServerConfig.sameConnection`) остаются, исчезнувшие закрываются,
  /// новые подключаются.
  ///
  /// [servers] — полный желаемый список после слияния и фильтра ядра (D6):
  /// серверы конфига, затем серверы клиента в порядке регистрации. Серверы
  /// конфига в нём совпадают с уже подключёнными, поэтому остаются
  /// нетронутыми; сервер конфига, вытесненный клиентом, в списке отсутствует
  /// и закрывается. Новые серверы занимают имена инструментов последними
  /// (коллизия отключает новый, а не работающий сервер). Сбой сервера — лог
  /// `mcp.server.failed`, а не исключение.
  ///
  /// Смена `McpServerConfig.enabled` — другой сервер: `true → false` закрывает
  /// сервер, `false → true` подключает новый (D10). Неизменённый сервер в
  /// `failed` подключается сразу, не дожидаясь таймера повтора (OQ8), а
  /// отключённый коллизией пробуется заново; отключённый `/mcp disable`
  /// остаётся выключенным до `setEnabled`.
  Future<void> replaceServers(List<McpServerConfig> servers);

  /// Разрывает соединение сервера [name] и подключает его сразу, не дожидаясь
  /// таймера повтора (D11; `/mcp reload`, `/mcp restart`). Неизвестное имя —
  /// ничего. Возвращается после первой попытки; её сбой — состояние `failed`
  /// и обычный повтор, а не исключение.
  Future<void> reconnect(String name);

  /// Включает или выключает сервер [name] только в этой сессии и в памяти
  /// (D11; `/mcp enable|disable`). `false` закрывает транспорт, снимает
  /// таймер и даёт `disabled` с `lastError` `disabled by /mcp disable`;
  /// `true` подключает сервер, выключенный командой, конфигом
  /// (`McpServerConfig.enabled == false`) или коллизией имён (повторная
  /// коллизия снова даёт `disabled`). Конфиг и журнал не меняются. Это
  /// действие человека: R0-1 к нему не относится.
  Future<void> setEnabled(String name, bool enabled);

  /// Идемпотентно; закрывает транспорты параллельно, отменяет таймеры и
  /// идущие подключения (D11).
  Future<void> close();
}

/// Новый полный набор MCP-инструментов сессии вместо прежнего.
final class McpToolsUpdate {
  McpToolsUpdate({
    required List<AgentTool> tools,
    required List<McpServerSummary> servers,
  }) : tools = List.unmodifiable(tools),
       servers = List.unmodifiable(servers);

  final List<AgentTool> tools;
  final List<McpServerSummary> servers;
}

/// Состояние сервера сессии (`agent-core-architecture` §17.5.7; design.md
/// change `add-config-writer-and-reload`, D11).
enum McpServerState {
  /// Идёт попытка подключения (первая или повторная).
  connecting,

  /// Рукопожатие выполнено, вызовы идут на сервер.
  connected,

  /// Сбой: процесс вышел, транспорт закрыт, подключение не удалось;
  /// следующая попытка — по таймеру.
  failed,

  /// Не подключается: `enabled: false`, `/mcp disable` или коллизия имён.
  disabled,
}

/// Строка секции промпта `mcp` (§11.5, D12) и таблицы `/mcp list` (D11):
/// сервер, число его инструментов, происхождение и состояние.
///
/// Почему новые поля имеют умолчания: конструктор остаётся совместимым для
/// фейков и тестов, которым состояние не важно (`session`, `stdio`,
/// `connected`, без ошибки).
///
/// Как использовать: коннектор возвращает сводку каждого сервера сессии в
/// порядке списка. [lastError] — текст кода CodeLab (не длиннее 200
/// символов), без текстов сервера и секретов; [retryIn] есть только у
/// [McpServerState.failed].
final class McpServerSummary {
  const McpServerSummary({
    required this.name,
    required this.toolCount,
    this.origin = McpServerOrigin.session,
    this.transport = 'stdio',
    this.state = McpServerState.connected,
    this.lastError,
    this.retryIn,
  });

  final String name;
  final int toolCount;

  /// Откуда сервер: конфиг или `session/new`.
  final McpServerOrigin origin;

  /// `stdio` или `http`.
  final String transport;
  final McpServerState state;
  final String? lastError;
  final Duration? retryIn;
}
