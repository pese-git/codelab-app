/// Порядок записи провайдера: секрет, затем конфиг (`dart-agent-and-clients`
/// §12.4.4, шаг 8; design.md change `add-provider-setup-ui`, D9; SETUP-5).
library;

import 'package:codelab_agent_core/codelab_agent_core.dart' show ConfigSnapshot;

import '../config/agent_config_store.dart';
import 'provider_keys.dart';
import 'provider_remover.dart' show SecretDeletion;
import 'provider_setup_plan.dart';

/// Что стало с созданным секретом после неудачной записи конфига.
enum KeyRollback {
  /// Откат не требовался (секрет не создавался или был заменён).
  none,

  /// Созданный секрет удалён.
  deleted,

  /// Удалить не удалось: секрет остался в хранилище.
  failed,
}

/// Итог [ProviderSetupCommitter.commit].
sealed class ProviderCommitOutcome {
  const ProviderCommitOutcome();
}

/// Записано. [keyReplaced] — ключ заменён под тем же именем: работающий агент
/// держит старое значение до перезапуска (D9).
final class ProviderCommitted extends ProviderCommitOutcome {
  const ProviderCommitted({required this.saved, required this.keyReplaced});

  final ConfigSaved saved;
  final bool keyReplaced;

  @override
  String toString() => 'ProviderCommitted(keyReplaced: $keyReplaced)';
}

/// Секрет появился после шага ключа; ничего не записано, мастер возвращается на
/// шаг ключа с вариантами «Use the stored key» / «Replace it».
final class ProviderKeyAppeared extends ProviderCommitOutcome {
  const ProviderKeyAppeared();

  @override
  String toString() => 'ProviderKeyAppeared';
}

/// Хранилище отказало; конфиг не писался. [reason] — текст без значения.
final class ProviderKeyNotStored extends ProviderCommitOutcome {
  const ProviderKeyNotStored(this.reason);

  final String reason;

  @override
  String toString() => 'ProviderKeyNotStored';
}

/// Конфиг не записан: [outcome] — конфликт, отказ валидатора или inline-секрет;
/// `null` — исключение `apply`, тогда [errorType] — имя его типа (текст
/// исключения никуда не идёт, SETUP-1).
final class ProviderConfigNotSaved extends ProviderCommitOutcome {
  const ProviderConfigNotSaved({
    required this.outcome,
    required this.errorType,
    required this.keyReplaced,
    required this.rollback,
  });

  final ConfigSaveOutcome? outcome;
  final String? errorType;
  final bool keyReplaced;
  final KeyRollback rollback;

  @override
  String toString() =>
      'ProviderConfigNotSaved(${outcome ?? errorType}, '
      'keyReplaced: $keyReplaced, rollback: ${rollback.name})';
}

/// Записывает провайдера: секрет, затем конфиг, с откатом созданного секрета.
///
/// Почему порядок «секрет → конфиг»: в обратном получился бы конфиг со ссылкой
/// на несуществующий секрет, а это ошибка при первом ходе агента. Заменённый
/// секрет не откатывается — прежнего значения клиент не знает (D9).
///
/// Как использовать: `ProviderSetupFlow` вызывает [commit] на `ConfirmSave`;
/// `base` — `ConfigSnapshot` слоя `plan.target` из свежего снимка.
final class ProviderSetupCommitter {
  ProviderSetupCommitter({
    required AgentConfigStore config,
    required ProviderKeys keys,
  }) : _config = config,
       _keys = keys;

  final AgentConfigStore _config;
  final ProviderKeys _keys;

  /// Перечитывает снимок конфига (после `ConfigConflict`, D9): повторный
  /// «Save» применяется к свежему отпечатку файла, а не к устаревшему.
  Future<AgentConfigSnapshot> reload({required String cwd}) =>
      _config.snapshot(cwd: cwd);

  Future<ProviderCommitOutcome> commit(
    ProviderSetupPlan plan,
    ConfigSnapshot base,
  ) async {
    var created = false;
    var replaced = false;
    final key = plan.key;
    final name = plan.secretName;
    if (key is StoreSecret && name != null) {
      // Имя могло появиться после шага ключа (другой процесс, `secret set`).
      if (!plan.replaceSecret && await _keys.stored(name)) {
        return const ProviderKeyAppeared();
      }
      switch (await _keys.write(name, key.value)) {
        case ProviderKeyCreated():
          created = true;
        case ProviderKeyReplaced():
          // Включая гонку в окне после перепроверки: заменой считается любой
          // `SecretUpdated`, откатывать нечего (D9).
          replaced = true;
        case ProviderKeyRefused(:final reason):
          return ProviderKeyNotStored(reason);
      }
    }

    ConfigSaveOutcome? outcome;
    String? errorType;
    try {
      outcome = await _config.apply(base, plan.toEdits());
    } on Object catch (error) {
      // Любое исключение: иначе созданный секрет остался бы сиротой. Текст
      // исключения мог процитировать значение — берём только тип.
      errorType = error.runtimeType.toString();
    }
    if (outcome case final ConfigSaved saved) {
      return ProviderCommitted(saved: saved, keyReplaced: replaced);
    }

    var rollback = KeyRollback.none;
    if (created && name != null) {
      try {
        rollback = switch (await _keys.delete(name)) {
          SecretDeletion.deleted ||
          SecretDeletion.notSet => KeyRollback.deleted,
          SecretDeletion.failed => KeyRollback.failed,
        };
      } on Object {
        // Сбой хранилища при откате не должен терять исход записи конфига
        // (конфликт, отказ валидатора): пользователь увидит «секрет остался».
        rollback = KeyRollback.failed;
      }
    }
    return ProviderConfigNotSaved(
      outcome: outcome,
      errorType: errorType,
      keyReplaced: replaced,
      rollback: rollback,
    );
  }
}
