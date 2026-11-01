import 'package:codelab_agent_core/codelab_agent_core.dart';

import 'jsonl_session_store.dart';

/// Журнал сессий хоста по настройкам загруженной конфигурации.
///
/// Почему одна функция: `codelab-agent` и встроенный агент
/// (`codelab_embedded/io.dart`) обязаны одинаково читать `sessions.dir` и
/// `sessions.fsync`, иначе журнал одного хоста лежал бы не там, где ищет
/// другой (change `add-embedded-agent-mode`, задача 2.8; §8.5).
///
/// Как использовать: [codelabHome] — `codelabHomeOf(environment)`, [settings]
/// — `ConfigLoadResult.host`. Без `sessions.dir` журнал в
/// `<codelabHome>/sessions`, без `sessions.fsync` — `checkpoints`.
JsonlSessionStore openHostSessions({
  required String codelabHome,
  required HostSettings settings,
  required Clock clock,
  required Logger logger,
}) => JsonlSessionStore(
  root: settings.sessionsDir ?? '$codelabHome/sessions',
  fsync: switch (settings.fsync) {
    final String name => FsyncPolicy.values.byName(name),
    null => FsyncPolicy.checkpoints,
  },
  clock: clock,
  logger: logger,
);
