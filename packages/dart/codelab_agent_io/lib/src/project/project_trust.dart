/// Правило доверия к папке проекта, общее для `config check` и моста
/// (design.md change `add-settings-agents-modes`, D7; SETUP-8; CFG-3, D4 change
/// `add-agent-project-files`).
library;

import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';

import '../env/local_execution_env.dart';

/// Канонический путь папки проекта и её доверие.
typedef ProjectTrust = ({String cwd, bool trusted});

/// Разрешает [folder] через `realpath` и сверяет с `trusted_projects`.
///
/// Почему одна функция: доверие решает, прочитает ли агент определения и
/// файлы проекта, и `config check`, и страница настроек должны отвечать
/// одинаково (SETUP-8). Fail-closed: путь, который не разрешился, —
/// недоверенный, а `cwd` остаётся абсолютным путём без канонизации.
///
/// Как использовать: `await projectTrustAt(config: …, folder: dir,
/// environment: env)`; `cwd` передаётся порту чтения файлов, `trusted` —
/// `projectTrusted` запроса.
Future<ProjectTrust> projectTrustAt({
  required CoreConfig config,
  required String folder,
  required Map<String, String> environment,
}) async {
  final shown = Directory(folder).absolute.path;
  final local = LocalExecutionEnv(cwd: shown, hostEnvironment: environment);
  switch (await local.realpath(shown)) {
    case Ok(:final value):
      return (
        cwd: value,
        trusted: config.trustedProjects.any(
          (r) => r.replaceAll('\\', '/') == value,
        ),
      );
    case Err():
      return (cwd: local.cwd, trusted: false);
  }
}
