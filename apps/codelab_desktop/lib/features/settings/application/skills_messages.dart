import 'package:codelab_setup/codelab_setup.dart' show SkillsListRefusal;

/// Разовое сообщение баннера страницы «Skills & extensions» (`skills-banner`).
///
/// Почему закрытая иерархия: как у `ProviderMessage` (D5): баннер — исход
/// действия, состояние хранит аргументы, текст строит presentation. Отказ
/// списка навыков хранится как [SkillsListRefusal] с элементом `extra_roots`,
/// а не готовой фразой: подсказка неактивного переключателя и баннер строятся
/// одной функцией presentation (change `add-app-skills-page`, D5, D9).
sealed class SkillsMessage {
  const SkillsMessage();
}

/// `Could not open <path>.`
final class SkillsOpenFailedMessage extends SkillsMessage {
  const SkillsOpenFailedMessage(this.path);

  final String path;
}

/// Запись `skills.*` сохранена.
final class SkillsSavedMessage extends SkillsMessage {
  const SkillsSavedMessage();
}

/// Файл конфига изменился на диске.
final class SkillsConflictMessage extends SkillsMessage {
  const SkillsConflictMessage();
}

/// Конфиг отклонён ядром; [issues] — тексты проверки как есть.
final class SkillsRejectedMessage extends SkillsMessage {
  const SkillsRejectedMessage(this.issues);

  final String issues;
}

/// Секрет значением по ключу [key].
final class SkillsInlineSecretMessage extends SkillsMessage {
  const SkillsInlineSecretMessage(this.key);

  final String key;
}

/// `The config was not saved.`
final class SkillsNotSavedMessage extends SkillsMessage {
  const SkillsNotSavedMessage();
}

/// Мост отказал в записи списка; [element] — элемент `extra_roots`.
final class SkillsRefusedMessage extends SkillsMessage {
  const SkillsRefusedMessage(this.refusal, {this.element});

  final SkillsListRefusal refusal;
  final String? element;
}
