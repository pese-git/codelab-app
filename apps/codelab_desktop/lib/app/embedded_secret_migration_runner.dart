// IO-барель встроенного агента разрешён сторожем только в `lib/app/`
// (design.md change `add-embedded-agent-mode`, D3). Мигратор отсюда же:
// app не импортирует `codelab_agent_*` (PKG-4).
import 'package:codelab_embedded/io.dart' as io;

import '../features/workbench/application/secret_migration_runner.dart';

/// Порт переноса секретов поверх движка `SecretMigrator` из
/// `package:codelab_embedded/io.dart`.
///
/// Почему в `lib/app/`: движок читает файлы конфига и пишет в хранилище
/// секретов — это IO composition root (`AGENTS.md` §6, §11); Cubit и виджеты
/// его не видят. Отчёт движка переводится в [SecretMigrationOutcome] без
/// типов `codelab_agent_*` (design.md change
/// `add-config-literal-secrets-and-migrate`, D8, п. 3).
///
/// Для чего: единственная реализация [SecretMigrationRunner]; параметры —
/// `--all` для папки проекта, без `--force` (замена существующего секрета в
/// app не предлагается, L7).
///
/// Как использовать: composition root создаёт её с **тем же** [environment],
/// что у `localEmbeddedAgentOpener` (`CODELAB_HOME`, `CODELAB_CONFIG`,
/// `CODELAB_SECRET_*`), иначе план построился бы по `~/.codelab`, а не по
/// файлам агента. [platform] — `Platform.operatingSystem`; он выбирает ветку
/// подсказки для `env` (на Windows файл-бэкенда нет, как у `secret set`).
/// Тексты в [SecretMigrationOutcome.problem] и `detail` строятся из
/// типизированного отчёта (строки `problems` — те же, что печатает CLI), а не
/// из `error.toString()`; в журнал эта реализация ничего не пишет.
final class EmbeddedSecretMigrationRunner implements SecretMigrationRunner {
  EmbeddedSecretMigrationRunner({
    required Map<String, String> environment,
    required String platform,
  }) : _environment = environment,
       _platform = platform;

  final Map<String, String> _environment;
  final String _platform;

  @override
  Future<SecretMigrationOutcome> plan(String cwd) => _run(cwd, dryRun: true);

  @override
  Future<SecretMigrationOutcome> apply(String cwd) => _run(cwd, dryRun: false);

  Future<SecretMigrationOutcome> _run(
    String cwd, {
    required bool dryRun,
  }) async {
    // Опции собирает мост: `--all`, без `--force`, хранилище тем же путём
    // `testStorePath`, что у открывателя агента.
    final report = await io.SecretMigrator(platform: _platform).run(
      io.secretMigrationOptionsFor(
        cwd: cwd,
        environment: _environment,
        dryRun: dryRun,
      ),
    );

    final items = [for (final item in report.items) item.describe()];
    if (report.readOnlyBackend) {
      return SecretMigrationOutcome(
        items: items,
        canApply: false,
        exitCode: report.exitCode,
        backendId: report.backendId,
        readOnlyBackend: true,
        detail: _readOnlyHint(report.home),
      );
    }
    if (report.nameConflict) {
      return SecretMigrationOutcome(
        items: items,
        canApply: false,
        exitCode: report.exitCode,
        backendId: report.backendId,
        nameConflict: true,
        detail: report.problems.join('\n'),
      );
    }
    if (report.exitCode != 0) {
      return SecretMigrationOutcome(
        items: items,
        canApply: false,
        exitCode: report.exitCode,
        backendId: report.backendId,
        movedAny: report.movedAny,
        problem: report.problems.isEmpty
            ? 'The secret migration failed (exit code ${report.exitCode}).'
            : report.problems.join('\n'),
      );
    }
    return SecretMigrationOutcome(
      items: items,
      canApply: report.canApply,
      backendId: report.backendId,
      movedAny: report.movedAny,
      onlyExtraLayerFindings: report.onlyExtraLayerFindings,
    );
  }

  /// Подсказка для бэкенда `env`: на Windows `secrets.backend: file` не
  /// поддержан, остаются только переменные — та же ветка, что у `secret set`
  /// (agent-workbench-ui «Перенос секретов встроенного агента»).
  String _readOnlyHint(String? home) {
    const head = 'Secrets cannot be stored: the env backend is read-only.';
    if (_platform == 'windows') {
      return '$head Set CODELAB_SECRET_* variables.';
    }
    return '$head Add secrets.backend: file to ${home ?? '~/.codelab'}/config.yaml, '
        'or set CODELAB_SECRET_* variables.';
  }
}
