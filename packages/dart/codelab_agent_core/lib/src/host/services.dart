import '../config/config_source.dart';
import '../env/execution_env.dart';
import '../llm/model_catalog.dart';
import '../llm/stream_function.dart';
import 'last_model_store.dart';
import '../mcp/mcp_connector.dart';
import '../permissions/agent_config_paths.dart';
import '../permissions/gate.dart';
import '../project/project_files.dart';
import '../secrets/secret_resolver.dart';
import '../session/session_store.dart';
import '../util/clock.dart';
import '../util/ids.dart';
import '../util/logger.dart';

/// Функция модели и каталог, которые хост строит по `CoreConfig`
/// (design.md change `add-config-writer-and-reload`, D8).
///
/// Почему запись: `http.Client` и сервисы LLM принадлежат хосту (PKG-6), ядро
/// их не создаёт. Хост с источником конфига собирает пару одним замыканием
/// `modelsFor` для старта и для каждой применённой перезагрузки.
typedef ConfiguredModels = ({StreamFunction stream, ModelCatalog catalog});

/// Всё внешнее, что хост передаёт ядру (`agent-core-architecture` §10.3).
///
/// Почему одним объектом: ядро не создаёт порты само (PKG-6), а сборка
/// проверяет, что у каждой включённой capability есть её сервис (HOST-3).
///
/// Как использовать: хост заполняет поля и передаёт объект в
/// `buildAgentCore`; следующие этапы добавляют сервисы.
final class AgentCoreServices {
  const AgentCoreServices({
    required this.baseEnv,
    required this.logger,
    required this.clock,
    required this.ids,
    required this.sessions,
    this.gate,
    this.platform = 'unknown',
    this.models,
    this.mcp,
    this.projectFiles,
    this.secrets,
    this.config,
    this.agentConfigPaths,
    this.lastModel,
  });

  /// Local | ACP client | memory (tests).
  final ExecutionEnv baseEnv;

  /// `null` → `interactiveApproval` is off.
  final PermissionGate? gate;
  final Logger logger;
  final Clock clock;
  final IdGenerator ids;

  /// Хранилище журналов (§8.3). Обязательно: журнал пишется всегда, а
  /// выключенная `sessionPersistence` означает лишь «не на постоянном
  /// носителе» (design.md этапа 3, D12).
  final SessionStore sessions;

  /// Платформа хоста для системного промпта (`linux`, `macos`, `windows`,
  /// `web`). Почему сервис: ядро web-безопасно и не читает
  /// `Platform.operatingSystem`, а модели полезно знать, какой shell и какие
  /// пути её ждут (§11.5). Хост на `dart:io` передаёт
  /// `Platform.operatingSystem`.
  final String platform;

  /// Каталог моделей для опции `model` и смены модели сессии (§2.12.2,
  /// §13.6). `null` — каталог из одной `CoreConfig.defaultModel`: тесты и
  /// хосты без конфига провайдеров (design.md change
  /// `add-dart-agent-acp-server`, D3).
  final ModelCatalog? models;

  /// Подключение MCP-серверов сессии (§10.3; design.md change
  /// `add-agent-mcp-client`, D3). `null` — capability `mcp` выключена с
  /// причиной «сервис MCP не передан»: серверы сессии пропускаются, сессия
  /// создаётся.
  final McpConnector? mcp;

  /// Чтение файлов проекта при создании и загрузке сессии (design.md change
  /// `add-agent-project-files`, D1): `AGENTS.md`/`CLAUDE.md` в системный
  /// промпт, позже — шаблоны команд и определения агентов. `null` — файлов
  /// проекта нет (web, мобильные хосты, тесты): поведение прежнее.
  final ProjectFilesSource? projectFiles;

  /// Резолвер секретов хоста (design.md change `add-agent-secret-store`, D3,
  /// D4): ядро берёт через него значения `${secret:…}` в `env` и `headers`
  /// MCP-серверов конфигурации перед подключением. Хост передаёт тот же
  /// резолвер, что и в `createRoutedStreamFunction(…, secrets:)`: функцию
  /// модели он строит раньше ядра, а для переменных `CODELAB_SECRET_*` нужно
  /// окружение процесса, которого у ядра нет. `null` — секретов нет (web без
  /// хранилища, тесты): сервер со ссылкой не подключается, причина
  /// `no secret store`.
  final SecretResolver? secrets;

  /// Источник конфигурации работающего агента (design.md change
  /// `add-config-writer-and-reload`, D7, D8).
  ///
  /// Почему порт сервисов: файлы и наблюдатель — забота хоста, а ядро только
  /// подписывается на сигнал и вызывает загрузку. `null` — перезагрузки нет:
  /// подписки, `reloadConfig`/`checkConfig` и команды `/config` нет
  /// (`--llm-script`, тесты, мобильные и web-хосты). С источником
  /// `buildAgentCore` требует `modelsFor` (`HostWiringException`). Владелец —
  /// хост: он закрывает источник после `runtime.dispose()`.
  final ConfigSource? config;

  /// Пути конфигурации агента для PERM-11 (design.md change
  /// `add-config-writer-and-reload`, D8; `agent-core-architecture` §7.6.1):
  /// то, что агент перечитывает на лету, модель не правит без человека.
  /// Хост строит значение одной функцией (`agentConfigPathsFor` пакета
  /// `codelab_agent_io`) из тех же входов, что источник конфига. Почему поле
  /// сервисов, а не `HostProfile`: пути — данные запуска процесса, профиль
  /// описывает возможности платформы. `null` — хост пути не передал
  /// (`--llm-script`, web, тесты): действует список §7.6.1 относительно
  /// корня сессии.
  final AgentConfigPaths? agentConfigPaths;

  /// ЗАГЛУШКА (задача 2.2, D6): память последней явно выбранной модели.
  /// `null` — памяти нет: шаг 2 выбора пропускается, запись не выполняется.
  final LastModelStore? lastModel;
}
