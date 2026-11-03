/// Источник конфига живого агента на файлах (design.md change
/// `add-config-writer-and-reload`, D7, D8; agent-configuration «Наблюдение за
/// файлами конфига»).
library;

import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'agent_config_paths.dart';
import 'config_loader.dart';
import 'config_watcher.dart';
import 'provider_preconfig.dart';

/// [ConfigSource] хоста `dart:io`: тот же `ConfigLoader` с теми же слоями,
/// окружением и флагами, что при старте, плюс [ConfigWatcher].
///
/// Почему: ядро перезагружает конфиг по сигналу, не зная ни файлов, ни
/// `Clock` debounce. Параметры запуска (корень, окружение, флаги) у процесса
/// не меняются, поэтому источник запоминает их один раз и каждая [load]
/// читает слои заново теми же параметрами.
///
/// Доверие: каждая [load] передаёт загрузчику
/// `pinnedTrustedProjects: initial.config.trustedProjects` — доверие
/// проектам закреплено на стартовом снимке до перезапуска, а новое значение
/// `trusted_projects` попадает только в `values` (D8, «Пересборка снимка»).
/// Загрузчик список лишь передаёт, доверие вычисляет ядро.
///
/// Наблюдение: список файлов — `watchedConfigFiles(...)` (наблюдаемое ⊆
/// защищаемому, R5-1; `secrets.yaml` — при `secrets.backend: file`).
/// `config.watch: false` в [initial] — наблюдателя нет, [changes] молчит, а
/// `/config reload` работает. Период опроса — `config.poll_interval`
/// (умолчания `true` и `2s`, когда ключей нет).
///
/// Как использовать: хост (`AgentHost` или открыватель встроенного агента)
/// после стартовой загрузки создаёт
/// `FileConfigSource(initial: result, cwd: …, environment: …, flags: …,
/// preconfigFlags: …, extraConfig: …, knownVariables: …, clock: …,
/// logger: …)`, кладёт его в `AgentCoreServices.config` и владеет им: после
/// `runtime.dispose()` вызывает [close]. Сценарий `--llm-script` источника не
/// создаёт.
final class FileConfigSource implements ConfigSource {
  FileConfigSource({
    required this.initial,
    required String cwd,
    required Map<String, String> environment,
    required Clock clock,
    required Logger logger,
    ConfigTree? flags,
    ProviderPreconfigFlags? preconfigFlags,
    String? extraConfig,
    Set<String> knownVariables = const {},
    String? platform,
    ConfigLoader? loader,
    DirectoryEventsFactory? directoryEvents,
    ConfigFileProbe? probe,
  }) : _cwd = cwd,
       _environment = Map.unmodifiable(environment),
       _flags = flags,
       _preconfigFlags = preconfigFlags,
       _extraConfig = extraConfig,
       _knownVariables = knownVariables,
       _platform = platform,
       _loader = loader ?? ConfigLoader() {
    final host = initial.host;
    if (host?.configWatch ?? true) {
      _watcher = ConfigWatcher(
        files: watchedConfigFiles(
          cwd: cwd,
          environment: environment,
          extraConfig: extraConfig,
          secretsFile: host?.secretsBackend == 'file',
        ),
        clock: clock,
        logger: logger,
        pollInterval: host?.configPollInterval ?? const Duration(seconds: 2),
        directoryEvents: directoryEvents,
        probe: probe,
      );
      _watcher!.start();
    }
  }

  @override
  final ConfigLoadResult initial;

  final String _cwd;
  final Map<String, String> _environment;
  final ConfigTree? _flags;
  final ProviderPreconfigFlags? _preconfigFlags;
  final String? _extraConfig;
  final Set<String> _knownVariables;
  final String? _platform;
  final ConfigLoader _loader;
  ConfigWatcher? _watcher;

  /// Без наблюдателя (`config.watch: false`) сигнал никогда не приходит; поток
  /// закрывается в [close].
  final _silent = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _watcher?.changes ?? _silent.stream;

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async {
    // Снимок содержимого до чтения: собственное чтение не даёт сигнала, а
    // правка во время чтения — даёт (см. `ConfigWatcher.rebase`). Проверка
    // (`rebase: false`, `/config check`) базу НЕ переносит: иначе в окне
    // debounce `_fire` увидел бы те же sha256 и сигнал о неприменённой правке
    // терялся (D7, D8).
    if (rebase) {
      _watcher?.rebase();
    }
    return _loader.load(
      cwd: _cwd,
      environment: _environment,
      flags: _flags,
      preconfigFlags: _preconfigFlags,
      extraConfig: _extraConfig,
      knownVariables: _knownVariables,
      platform: _platform,
      pinnedTrustedProjects: initial.config?.trustedProjects,
    );
  }

  /// Останавливает наблюдение и таймеры; после вызова сигналов нет.
  /// Повторный вызов безопасен.
  Future<void> close() async {
    await _watcher?.close();
    await _silent.close();
  }
}
