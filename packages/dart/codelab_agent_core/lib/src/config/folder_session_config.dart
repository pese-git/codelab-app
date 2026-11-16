import 'package:collection/collection.dart';

import 'config_issue.dart';
import 'config_reload_plan.dart';
import 'core_config.dart';
import 'key_path.dart';

/// Правило перекрытия для каждого поля [DeferredConfigParts]
/// (design.md change `defer-restart-keys-in-folder-sessions`, D5).
///
/// Почему карта: новое структурированное отложенное поле без правила
/// перекрытия оставило бы обход R0 в сессиях других папок. Тест читает поля
/// `DeferredConfigParts` из исходника и падает, если у поля нет записи здесь;
/// кто добавляет поле, обязан описать и реализовать правило в
/// [deferForFolderSession].
const folderSessionOverlapRules = <String, String>{
  'providers':
      'перекрыт, если каждый изменённый лист группы провайдера в полном '
      'снимке папки отличается от снимка без проекта (D3)',
  'servers':
      'перекрыт, если элемент mcp.servers[<имя>] в полном снимке папки '
      'отличается от снимка без проекта (D5)',
  'disabledServers': 'следует за servers: только для неперекрытых серверов',
  'disabledServersWithoutProject':
      'следует за servers: только для неперекрытых серверов',
  'permissions':
      'без проектных слоёв — раздел базы; с проектными слоями — отказ (D4)',
  'defaultModel':
      'перекрыта, если agent.default_model полного снимка папки отличается '
      'от снимка без проекта (D5)',
};

/// Итог [deferForFolderSession]: снимок сессии папки либо отказ.
///
/// Почему sealed: прежний вид «`config` и `problem` оба необязательные» допускал
/// невозможные состояния (оба `null` или оба заданы), и рантайм разворачивал
/// их через `!`. Два варианта делают исход явным.
///
/// Для чего: рантайм получает от [deferForFolderSession] либо
/// [FolderSessionAccepted] (снимок и ключи для лога
/// `config.session.restart_pending`), либо [FolderSessionRefused]
/// (`ProjectConfigException`, `config.session.project_invalid`).
///
/// Как использовать: `switch` по обоим вариантам; новых вариантов нет, а новый
/// исход добавляется веткой sealed-иерархии (§1.5).
sealed class FolderSessionConfig {
  const FolderSessionConfig();
}

/// Сессия папки открывается с [config].
final class FolderSessionAccepted extends FolderSessionConfig {
  const FolderSessionAccepted(this.config, {this.restartKeys = const []});

  /// Снимок сессии папки после подстановки.
  final CoreConfig config;

  /// Отсортированные ключи показа подставленных частей (`providers.<id>`,
  /// `mcp.servers[<имя>]`, `agent.default_model`, листья `permissions.*`),
  /// без значений (§16, CFG-2). Пусто — подставлять было нечего.
  final List<String> restartKeys;
}

/// Сессия папки не открывается: [problem] — причина отказа.
final class FolderSessionRefused extends FolderSessionConfig {
  const FolderSessionRefused(this.problem);

  /// Проблема без значений и адресов (CFG-2); рантайм превращает её в
  /// `ProjectConfigException`.
  final ConfigIssue problem;
}

/// Текст отказа по глобальным правам (design.md change
/// `defer-restart-keys-in-folder-sessions`, D4).
const _permissionsRefusal =
    'the global permissions changed after the agent started; restart the '
    'agent to open sessions in this folder';

/// Подставляет в конфигурацию папки сессии то, что перезагрузка корня
/// отложила до перезапуска (design.md change
/// `defer-restart-keys-in-folder-sessions`, D1–D5, D9; требование
/// agent-runtime «Сессии других папок при перезагрузке корня»).
///
/// Почему: сессия другой папки читает файлы заново на каждом открытии и без
/// этой функции получала бы сразу то, что сессии корня до перезапуска не
/// действует: группу провайдера с ключом (R0-4), stdio-серверы (R0-1),
/// глобальные `permissions` (R0-1). Правила R0 живут в одном месте —
/// [planConfigReload] и [CoreConfig.withDeferred]; здесь только выбор того,
/// чего проектный слой папки не перекрыл.
///
/// Как использовать: [applied] и [appliedValues] — применённый снимок
/// процесса на начало открытия (рантайм захватывает его до `await
/// loadForProject`, D9); [folder] — успешный результат
/// `ProjectConfigLoader.loadForProject` с непустым `config`. Базой служит
/// снимок без проекта корня (или полный, если у корня проектных слоёв нет);
/// сравнивается он со снимком без проекта загрузки папки. Перекрытие
/// определяется по паре снимков самой загрузки, без второго чтения файлов;
/// совпадение значений не считается перекрытием (fail closed, D1). Функция
/// чистая и синхронная: гонок и отмены нет (D9).
FolderSessionConfig deferForFolderSession({
  required CoreConfig applied,
  required Map<String, Object?> appliedValues,
  required ConfigLoadResult folder,
}) {
  final full = folder.config!;
  final folderBareConfig = full.withoutProject;
  // Нет проектных слоёв — полный снимок папки и есть глобальный: перекрытия
  // нет (D1).
  final hasProject = folderBareConfig != null;
  final bare = folderBareConfig ?? full;
  // Недостающая карта при наличии снимка без проекта — пустая: всё различие
  // откладывается (D9, как у `planConfigReload`).
  final bareValues = hasProject
      ? full.withoutProjectValues ?? const <String, Object?>{}
      : folder.values;
  final appliedBare = applied.withoutProject;
  final base = appliedBare ?? applied;
  final baseValues = appliedBare == null
      ? appliedValues
      : applied.withoutProjectValues ?? const <String, Object?>{};

  final plan = planConfigReload(
    previousValues: baseValues,
    previous: base,
    nextValues: bareValues,
    next: bare,
  );
  final planned = plan.deferred;

  const equality = DeepCollectionEquality();
  // Лист полного снимка отличается от листа снимка без проекта: значение дал
  // проектный слой (отсутствующий лист — тоже значение).
  //
  // Нет `withoutProjectValues` при наличии снимка без проекта: пара неизвестна,
  // ничто не считается перекрытым (D9, fail closed). Иначе пустая карта
  // «отличалась» бы от каждого листа и всё выглядело бы перекрытым.
  final pairKnown = !hasProject || full.withoutProjectValues != null;
  bool projectChanged(String key) =>
      hasProject &&
      pairKnown &&
      (folder.values.containsKey(key) != bareValues.containsKey(key) ||
          !equality.equals(folder.values[key], bareValues[key]));

  if (planned.permissions && hasProject) {
    return const FolderSessionRefused(
      ConfigIssue(
        kind: ConfigIssueKind.semantic,
        key: 'permissions',
        source: 'config reload',
        message: _permissionsRefusal,
      ),
    );
  }

  final baseProviders = {for (final p in base.providers) p.config.name};
  final fullProviders = {for (final p in full.providers) p.config.name};
  // Кандидаты: отложенные планом (ключ дал глобальный слой) и провайдеры,
  // у которых ключ даёт только проектный слой папки (D23, условие (a)):
  // `planConfigReload` смотрит лишь глобальные значения и их не видит, а
  // секрет проекта ушёл бы на изменившийся глобальный адрес (R0-4, D3).
  final candidates = <String>{
    ...planned.providers,
    for (final id in fullProviders)
      if (providerWithKey(folder.values, id)) id,
  };
  final providers = <String>{};
  for (final id in candidates) {
    // C — листы группы, изменившиеся относительно базы; у нового провайдера
    // базы нет, и это все листы его группы (D3).
    final isNew = !baseProviders.contains(id);
    final changed = <String>{
      for (final key in {...bareValues.keys, ...baseValues.keys})
        if (providerGroupField(key, id) != null &&
            (isNew
                ? bareValues.containsKey(key)
                : baseValues.containsKey(key) != bareValues.containsKey(key) ||
                      !equality.equals(baseValues[key], bareValues[key])))
          key,
    };
    if (changed.isEmpty) {
      continue; // группа не менялась после старта: откладывать нечего
    }
    final overlapped =
        fullProviders.contains(id) && changed.every(projectChanged);
    if (!overlapped) {
      providers.add(id);
    }
  }

  final servers = {
    for (final name in planned.servers)
      if (!projectChanged(KeyPath('mcp.servers').at(name).value)) name,
  };
  final parts = DeferredConfigParts(
    providers: providers,
    servers: servers,
    disabledServers: planned.disabledServers.intersection(servers),
    // План однослойный (у обоих его снимков `withoutProject == null`), поэтому
    // наборы `disabledServers` и `disabledServersWithoutProject` совпадают;
    // берётся тот, что относится к снимку без проекта.
    disabledServersWithoutProject: planned.disabledServersWithoutProject
        .intersection(servers),
    permissions: planned.permissions,
    defaultModel:
        planned.defaultModel && !projectChanged('agent.default_model'),
  );
  if (parts.isEmpty) {
    return FolderSessionAccepted(full);
  }

  // Ключ провайдера строится из идентификатора, а не берётся из плана: план
  // не знает о провайдерах с ключом из проектного слоя.
  final keys = <String>{
    for (final id in providers) KeyPath('providers').child(id).value,
    for (final key in plan.restartRequiredKeys)
      if (servers.any((name) => key == KeyPath('mcp.servers').at(name).value) ||
          (parts.permissions &&
              (key == 'permissions' || key.startsWith('permissions.'))) ||
          (parts.defaultModel && key == 'agent.default_model'))
        key,
  };
  return FolderSessionAccepted(
    // Вложенный снимок без проекта сессии папки не читается (`forSessionCwd`
    // нужен только корню), а после подстановки он может расходиться с
    // основным (проект задал свою `agent.default_model`).
    CoreConfig.withDeferred(base, full, parts).withoutNestedProject(),
    restartKeys: keys.toList()..sort(),
  );
}
