import 'package:codelab_setup/codelab_setup.dart';

import '../../../l10n/app_localizations.dart';
import 'message_markers.dart';

/// Разовое сообщение страницы «Providers» и мастера провайдера.
///
/// Почему закрытая иерархия: сообщение — исход действия или события, которое
/// не повторится («Provider X removed…», «Default model saved.», отказ записи
/// конфига), поэтому строку из входов не пересобрать. Состояние Cubit-а
/// хранит тип с аргументами, а текст строит [providerMessageText] по
/// каталогу текущего языка в presentation. Тогда уже показанный баннер
/// переводится вместе с деревом при смене языка
/// (`add-desktop-localization`, D5, вид «разовое сообщение»).
///
/// Для чего: единственное место, где перечислены баннеры страницы; тексты
/// ядра агента (`ConfigIssue.message`) и хранилища секретов остаются как есть
/// внутри переведённой рамки (D6, D7).
///
/// Как использовать: Cubit создаёт значение рядом с исходом (`ProviderBanner`),
/// presentation зовёт [providerMessageText] с `context.l10n`.
sealed class ProviderMessage {
  const ProviderMessage();
}

/// «Default model saved.»
final class DefaultModelSaved extends ProviderMessage {
  const DefaultModelSaved();
}

/// Провайдер [id] удалён; [secret] — что стало с его секретом, [secretName] —
/// имя секрета (для исходов, где оно называется).
final class ProviderRemovedMessage extends ProviderMessage {
  const ProviderRemovedMessage(this.id, this.secret, this.secretName);

  final String id;
  final SecretCleanup secret;
  final String? secretName;
}

/// Удаление отклонено политикой моста ([reason]).
final class ProviderRemovalRefusedMessage extends ProviderMessage {
  const ProviderRemovalRefusedMessage(this.reason);

  final ProviderRemovalRefusal reason;
}

/// Конфиг изменился на диске, запись не выполнена (SETUP-6).
final class ConfigConflictMessage extends ProviderMessage {
  const ConfigConflictMessage();
}

/// Конфиг отклонён проверкой ядра агента; [issues] — её тексты как есть,
/// склеенные через `; ` (D7: плейсхолдер в переведённой рамке).
final class ConfigRejectedMessage extends ProviderMessage {
  const ConfigRejectedMessage(this.issues);

  final String issues;
}

/// Конфиг отклонён: секрет значением по ключу [key].
final class ConfigInlineSecretMessage extends ProviderMessage {
  const ConfigInlineSecretMessage(this.key);

  final String key;
}

/// Мастер не открылся: конфиг агента не читается.
final class CannotOpenWizardMessage extends ProviderMessage {
  const CannotOpenWizardMessage();
}

/// Исход записи в мастере, который показывает баннер страницы.
enum WizardSavedKind {
  /// Агент не запущен: провайдер вступит в силу при следующем запуске.
  nextStart,

  /// Агент работает, перезапуск не нужен.
  plain,

  /// Ключ заменён: новый ключ вступит в силу после перезапуска.
  keyReplaced,

  /// Мост называет провайдера в `restartRequiredProviders`: модели появятся
  /// после перезапуска.
  needsRestart,
}

/// Баннер после мастера; [id] — id записанного провайдера.
final class WizardSavedMessage extends ProviderMessage {
  const WizardSavedMessage(this.id, this.kind);

  final String id;
  final WizardSavedKind kind;
}

/// Склеивает проблемы ядра агента в одну строку для плейсхолдера
/// `{issues}`: `ключ: текст` или просто текст, если ключа нет. Тексты
/// проверки — английские, как есть (D6, D7).
String configIssuesText(Iterable<ConfigIssue> issues) => [
  for (final i in issues) i.key.isEmpty ? i.message : '${i.key}: ${i.message}',
].join('; ');

/// Текст сообщения [message] на языке [l10n].
///
/// Идентификаторы (id провайдера, имя секрета, путь ключа) и команда
/// `codelab secret delete` — плейсхолдеры и не переводятся (D7; сценарий
/// «Команда в переведённой фразе»).
String providerMessageText(
  AppLocalizations l10n,
  ProviderMessage message,
) => switch (message) {
  DefaultModelSaved() => l10n.providersBannerDefaultModelSaved,
  ProviderRemovedMessage(:final id, :final secret, :final secretName) =>
    switch (secret) {
      SecretCleanup.stillReferenced => l10n.providersBannerRemovedKeyKept(
        id,
        secretName ?? '',
      ),
      SecretCleanup.deleted => l10n.providersBannerRemovedKeyDeleted(id),
      SecretCleanup.failed => l10n.providersBannerRemovedKeyFailed(
        id,
        secretName ?? '',
      ),
      _ => l10n.providersBannerRemoved(id),
    },
  ProviderRemovalRefusedMessage(:final reason) => providerRefusalText(
    l10n,
    reason,
  ),
  ConfigConflictMessage() => l10n.configConflict,
  ConfigRejectedMessage(:final issues) => l10n.configNotSavedRejected(issues),
  ConfigInlineSecretMessage(:final key) => l10n.configNotSavedInlineSecret(key),
  CannotOpenWizardMessage() => l10n.providersBannerCannotOpenWizard,
  WizardSavedMessage(:final id, :final kind) => switch (kind) {
    WizardSavedKind.nextStart => l10n.providersBannerSavedNextStart,
    WizardSavedKind.plain => l10n.providersBannerSaved(id),
    WizardSavedKind.keyReplaced => l10n.providersBannerSavedKeyRestart(id),
    WizardSavedKind.needsRestart => l10n.providersBannerSavedModelsRestart(id),
  },
};

/// Текст отказа удаления или правки провайдера по [reason] (политика — мост,
/// здесь только слова).
String providerRefusalText(
  AppLocalizations l10n,
  ProviderRemovalRefusal reason,
) => switch (reason) {
  ProviderRemovalRefusal.lastProvider => l10n.providersRemoveLast,
  ProviderRemovalRefusal.newDefaultRequired ||
  ProviderRemovalRefusal.newDefaultInvalid => l10n.providersRefusalNewDefault,
  ProviderRemovalRefusal.defaultOverridden =>
    l10n.providersRefusalDefaultOverridden,
  ProviderRemovalRefusal.notEditable => l10n.providersRefusalNotEditable,
  ProviderRemovalRefusal.multipleLayers => l10n.providersRefusalSeveralFiles,
  ProviderRemovalRefusal.unknownProvider ||
  ProviderRemovalRefusal.layerUnreadable => l10n.providersRefusalChanged,
};

/// Подпись статуса ключа без значения (`Key: in file`) по виду [key] на языке
/// [l10n].
///
/// Почему не `KeyStatusView.label`: он английский и нужен CLI; app строит
/// подпись по виду, а не по готовой строке (`add-desktop-localization`, D6,
/// «Тексты моста настроек»). Одно сообщение на случай, без склейки.
String keyStatusLabel(AppLocalizations l10n, KeyStatusView key) =>
    switch (key) {
      KeyInSecretStore(:final backendId) => l10n.providersKeyLabelInStore(
        backendId,
      ),
      KeySecretMissing(:final backendId) => l10n.providersKeyLabelMissing(
        backendId,
      ),
      KeyFromEnv(:final name, :final isSet) =>
        isSet
            ? l10n.providersKeyLabelEnvSet(name)
            : l10n.providersKeyLabelEnvNotSet(name),
      KeyLiteralInConfig() => l10n.providersKeyLabelLiteral,
      KeyNone() => l10n.providersKeyLabelNone,
    };

/// Строка «Key» раскрытой карточки: [text] до значения, [mono] — само значение
/// (имя секрета), которое набирается моноширинным шрифтом, и [tail] — обычный
/// текст после него (например, закрывающая «ёлочка»). Вместе
/// `text + mono + tail` дают одно сообщение каталога целиком, без склейки
/// фраз; [mono] `null` — значения в сообщении нет.
///
/// Как устроено: сообщение собирается с меткой вместо имени секрета и режется
/// по ней (`splitMessage`). Если перевод метку не использовал, всё сообщение
/// остаётся обычным текстом.
({String text, String? mono, String tail}) keyStatusDetail(
  AppLocalizations l10n,
  KeyStatusView key,
) {
  ({String text, String? mono, String tail}) split(
    String Function(String marker) build,
    String name,
  ) {
    final parts = splitMessage((m) => build(m[0]), 1);
    final before = StringBuffer();
    final after = StringBuffer();
    var found = false;
    for (final part in parts) {
      if (part.slot != null) {
        found = true;
      } else {
        (found ? after : before).write(part.text);
      }
    }
    return found
        ? (text: '$before', mono: name, tail: '$after')
        : (text: '$before', mono: null, tail: '');
  }

  return switch (key) {
    KeyInSecretStore(:final name, :final backendId) => split(
      (m) => l10n.providersKeyInStore(backendId, m),
      name,
    ),
    KeySecretMissing(:final name, :final backendId) => split(
      (m) => l10n.providersKeyNotStored(backendId, m),
      name,
    ),
    KeyFromEnv(:final name, :final isSet) => (
      text: isSet
          ? l10n.providersKeyEnvSet(name)
          : l10n.providersKeyEnvNotSet(name),
      mono: null,
      tail: '',
    ),
    KeyLiteralInConfig() => (
      text: l10n.providersKeyLiteral,
      mono: null,
      tail: '',
    ),
    KeyNone() => (text: l10n.providersKeyLabelNone, mono: null, tail: ''),
  };
}
