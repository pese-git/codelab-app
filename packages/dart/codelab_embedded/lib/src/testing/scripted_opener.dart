import 'dart:io';
import 'dart:math';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:codelab_agent_io/testing.dart';
import 'package:http/testing.dart';

import '../assemble.dart';
import '../embedded_agent.dart';
import '../embedded_agent_config.dart';

/// Открыватель встроенного агента со сценарием модели — блоком `llm` формата
/// фикстур (`agent-core-architecture` §14; design.md change
/// `add-embedded-agent-mode`, D8).
///
/// Почему: тестам app, CLI и драйверу `codelab test-scenario` нужен
/// детерминированный агент без сети и ключа. Разбор сценария и слой
/// провайдеров сценария — тот же код `codelab_agent_io` (`LlmScript`,
/// `withScriptedProviders`), что у `codelab-agent serve --llm-script`, поэтому
/// бинарь и встроенный агент читают файл сценария одинаково.
///
/// Для чего: единственный открыватель, который принимает профиль `agent-serve`
/// (файлы и команды через клиента, как у бинаря по stdio) и режим разрешений
/// [permissionMode] (`setup.mode` фикстуры). Конфигурация строится загрузчиком
/// со `scripted: true`: файлы `$CODELAB_HOME` и проекта не читаются, окружение —
/// только `CODELAB_HOME`, секретов нет, сеть закрыта.
///
/// Как использовать: `scriptedEmbeddedAgentOpener(llm: …, codelabHome: tmp,
/// logger: …)` и `await opener(cwd: …, hostProfile: …)`. [hostProfile], если
/// задан, заменяет профиль вызова. [sessionsDir] включает журнал JSONL, иначе
/// сессии в памяти (`sessionPersistence` сужается). Невалидный сценарий —
/// `LlmScriptException`. [clock] и [ids] — швы детерминизма (PKG-6); по
/// умолчанию системные.
EmbeddedAgentOpener scriptedEmbeddedAgentOpener({
  required Map<String, Object?> llm,
  required String codelabHome,
  required Logger logger,
  String? hostProfile,
  String? permissionMode,
  String? sessionsDir,
  Clock clock = const SystemClock(),
  IdGenerator? ids,
}) {
  // Параметр вызова называется так же, как параметр фабрики (тип
  // `EmbeddedAgentOpener`), поэтому заданный профиль запоминается заранее.
  final forcedProfile = hostProfile;
  return ({required String cwd, required String hostProfile}) async {
    final profile = forcedProfile ?? hostProfile;
    final store = CwdTrackingStore(switch (sessionsDir) {
      final root? => JsonlSessionStore(
        root: root,
        clock: clock,
        logger: logger,
      ),
      null => MemorySessionStore(),
    });
    final script = LlmScript.fromJson(
      llm,
      models: const [],
      clock: clock,
      cwdOf: store.cwdOf,
    );
    final environment = {'CODELAB_HOME': codelabHome};
    final loaded = ConfigLoader().load(
      cwd: cwd,
      environment: environment,
      flags: withScriptedProviders(
        ConfigTree(
          kind: ConfigLayerKind.flags,
          source: 'flags',
          values: {
            if (permissionMode != null) 'permissions': {'mode': permissionMode},
          },
        ),
        script.models,
      ),
      scripted: true,
    );
    if (loaded.issues.isNotEmpty) {
      throw EmbeddedAgentConfigException(loaded.issues, home: codelabHome);
    }
    final env = LocalExecutionEnv(cwd: cwd);
    return assembleEmbeddedAgent(
      config: EmbeddedAgentConfig(
        hostProfile: profile,
        core: loaded.config!,
        host: loaded.host!,
      ),
      services: EmbeddedHostServices(
        baseEnv: env,
        localEnv: (sessionCwd) => LocalExecutionEnv(cwd: sessionCwd),
        sessions: store,
        secrets: openHostSecrets(
          codelabHome: codelabHome,
          environment: environment,
          backend: 'env',
          debug: false,
          logger: logger,
          selectionReason: 'forced by scripted opener',
        ),
        // Сети у сценария нет: запрос к провайдеру — ошибка теста.
        http: MockClient(
          (_) async => throw StateError('the scripted agent has no network'),
        ),
        logger: logger,
        clock: clock,
        ids: ids ?? RandomIdGenerator(Random.secure()),
        random: Random(0),
        platform: Platform.operatingSystem,
        // Как у бинаря со сценарием: контекст проекта читается, а
        // `$CODELAB_HOME` — нет, прогон не зависит от файлов разработчика.
        projectFiles: ProjectFilesLoader(home: null, local: env),
      ),
      models: FixedModelCatalog(script.models),
      streamFunction: script.function.call,
      extraNarrowing: {
        if (sessionsDir == null)
          HostCapability.sessionPersistence: const CapabilityOff(
            'сценарий: сессии в памяти',
          ),
      },
    );
  };
}
