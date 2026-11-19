import 'package:codelab_setup/codelab_setup.dart'
    show
        SkillsListDisabledByProject,
        SkillsListLayerUnreadable,
        SkillsListNotEditable,
        SkillsListRefusal,
        SkillsListUntrustedProject;

import '../../../l10n/app_localizations.dart';
import '../application/skills_messages.dart';

/// Текст отказа моста для баннера и подсказки неактивного переключателя
/// (change `add-app-skills-page`, D5, D9). Переехал из состояния: баннер
/// хранит [SkillsListRefusal], а текст строит presentation (D5, «Уточнение
/// итерации 5»). [element] — элемент `extra_roots` для отказа «нужно доверие».
///
/// Почему в одном месте: Cubit показывает его баннером, когда отказ случился
/// на нажатии, а страница — подсказкой, когда мост отказал ещё при построении
/// вида; тексты не должны расходиться. Путь и элемент — без перевода.
String skillsRefusalText(
  AppLocalizations l10n,
  SkillsListRefusal refusal, {
  String? element,
}) => switch (refusal) {
  SkillsListNotEditable(:final source) => l10n.skillsRefusalNotEditable(source),
  SkillsListDisabledByProject(:final source) =>
    l10n.skillsRefusalDisabledByProject(source),
  SkillsListUntrustedProject() =>
    element == null
        ? l10n.skillsRefusalUntrustedFolder
        : l10n.skillsRefusalUntrusted(element),
  SkillsListLayerUnreadable() => l10n.skillsRefusalLayerUnreadable,
};

/// Размер файла: число по 1024-ичному правилу с одной цифрой после точки и
/// переведённая единица (`4.8 KB`, `4.8 КБ`; D8).
///
/// Почему число строкой: сокращение единицы с числом не согласуется, поэтому
/// `plural` не нужен; точка без локали — как числа usage (Q2 (а)).
String skillSizeText(AppLocalizations l10n, int bytes) {
  if (bytes < 1024) {
    return l10n.skillsSizeBytes('$bytes');
  }
  if (bytes < 1024 * 1024) {
    return l10n.skillsSizeKilobytes((bytes / 1024).toStringAsFixed(1));
  }
  return l10n.skillsSizeMegabytes((bytes / (1024 * 1024)).toStringAsFixed(1));
}

/// Текст баннера страницы «Skills & extensions» по сообщению. Тексты ядра
/// (`issues`) и пути — как есть.
String skillsMessageText(AppLocalizations l10n, SkillsMessage message) =>
    switch (message) {
      SkillsOpenFailedMessage(:final path) => l10n.skillsMsgOpenFailed(path),
      SkillsSavedMessage() => l10n.skillsMsgSaved,
      SkillsConflictMessage() => l10n.skillsMsgConflict,
      SkillsRejectedMessage(:final issues) => l10n.skillsMsgRejected(issues),
      SkillsInlineSecretMessage(:final key) => l10n.configNotSavedInlineSecret(
        key,
      ),
      SkillsNotSavedMessage() => l10n.skillsMsgNotSaved,
      SkillsRefusedMessage(:final refusal, :final element) => skillsRefusalText(
        l10n,
        refusal,
        element: element,
      ),
    };
