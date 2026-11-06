/// Готовность провайдера по снимку конфига (`dart-agent-and-clients` §12.4.2;
/// design.md change `add-provider-setup-ui`, D26).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show ConfigIssue, ConfigIssueKind, SecretBackendInfo, SecretNames;

import '../config/agent_config_store.dart';
import '../views/provider_entry_view.dart';
import 'provider_keys.dart';

/// Годен ли конфиг к запуску агента.
sealed class ProviderReadiness {
  const ProviderReadiness();
}

/// Провайдер модели по умолчанию [model] готов.
final class ProviderReady extends ProviderReadiness {
  const ProviderReady(this.model);

  final String model;

  @override
  String toString() => 'ProviderReady($model)';
}

/// Нет провайдеров или `agent.default_model`, других проблем нет: нужен мастер.
final class NoProviderConfigured extends ProviderReadiness {
  const NoProviderConfigured();

  @override
  String toString() => 'NoProviderConfigured';
}

/// У провайдера модели по умолчанию нет ключа; [reference] — `secret
/// codelab/openai` или `env OPENAI_API_KEY`, [backend] — куда предлагать
/// сохранить ключ.
final class ProviderKeyMissing extends ProviderReadiness {
  const ProviderKeyMissing({
    required this.providerId,
    required this.reference,
    required this.backend,
  });

  final String providerId;
  final String reference;
  final SecretBackendInfo backend;

  @override
  String toString() => 'ProviderKeyMissing($providerId, $reference)';
}

/// В конфиге другие проблемы валидатора.
final class ConfigBroken extends ProviderReadiness {
  const ConfigBroken(this.issues);

  final List<ConfigIssue> issues;

  @override
  String toString() => 'ConfigBroken(${issues.length})';
}

/// Нужен ли мастер первого провайдера: «нет провайдера» по снимку.
///
/// Почему по типизированным проблемам: текст проблем не разбирается (он
/// меняется вместе с валидатором). Условие: проблемы загрузки есть, все они —
/// вида `value` ключа `agent.default_model`, и при этом ключа нет ни в одном
/// применённом слое либо в конфиге нет ни одного провайдера. Любая другая
/// проблема (`budget.max_steps: 0`) или модель, указывающая на неверное имя
/// при существующих провайдерах, мастером не лечится (D26).
///
/// Как использовать: один признак для CLI (первый запуск) и app (баннер
/// «Add provider»); `checkProviderReadiness` построен на нём.
bool providerSetupNeeded(AgentConfigSnapshot snapshot) {
  final issues = snapshot.loaded.issues;
  if (issues.isEmpty) {
    return false;
  }
  final onlyDefaultModel = issues.every(
    (issue) =>
        issue.kind == ConfigIssueKind.value &&
        issue.key == 'agent.default_model',
  );
  if (!onlyDefaultModel) {
    return false;
  }
  return !snapshot.leaves.containsKey('agent.default_model') ||
      providerIdsOf(snapshot).isEmpty;
}

/// Готовность провайдера модели по умолчанию.
///
/// Почему порт [keys], а не `DescribedSecretStore`: клиенты не держат хранилище
/// ядра, у них `ClientSecretAccess`; `ProviderKeys.stored` отвечает «имя есть в
/// бэкенде» без чтения значения. Переопределение `CODELAB_SECRET_<…>` смотрит
/// эта функция по [env] (резолвер агента читает его раньше бэкенда).
///
/// Для чего: мастер первого запуска CLI и баннер app. Значения ключей не
/// читаются.
Future<ProviderReadiness> checkProviderReadiness(
  AgentConfigSnapshot snapshot,
  ProviderKeys keys,
  Map<String, String> env,
) async {
  if (providerSetupNeeded(snapshot)) {
    return const NoProviderConfigured();
  }
  if (snapshot.loaded.issues.isNotEmpty) {
    return ConfigBroken(snapshot.loaded.issues);
  }
  final model = snapshot.defaultModel;
  if (model == null) {
    return const NoProviderConfigured();
  }
  final id = model.split('/').first;
  if (providerString(snapshot, id, 'api_key_secret') case final name?) {
    final override = env[SecretNames.envOverride(name)];
    if ((override == null || override.isEmpty) && !await keys.stored(name)) {
      return ProviderKeyMissing(
        providerId: id,
        reference: 'secret $name',
        backend: keys.backend,
      );
    }
  } else if (providerString(snapshot, id, 'api_key_env') case final name?) {
    final value = env[name];
    if (value == null || value.isEmpty) {
      return ProviderKeyMissing(
        providerId: id,
        reference: 'env $name',
        backend: keys.backend,
      );
    }
  }
  return ProviderReady(model);
}
