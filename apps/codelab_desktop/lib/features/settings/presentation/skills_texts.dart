import 'package:codelab_setup/codelab_setup.dart' show SkillsListRefusal;

import '../../../l10n/app_localizations.dart';
import '../application/skills_messages.dart';

/// Текст отказа моста для баннера и подсказки неактивного переключателя
/// (change `add-app-skills-page`, D5, D9). Переехал из состояния: баннер
/// хранит [SkillsListRefusal], а текст строит presentation (D5, «Уточнение
/// итерации 5»). [element] — элемент `extra_roots` для отказа «нужно доверие».
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String skillsRefusalText(
  AppLocalizations l10n,
  SkillsListRefusal refusal, {
  String? element,
}) => '';

/// Размер файла контекста: число по 1024-ичному правилу с одной цифрой после
/// точки и переведённая единица (`4.8 KB`, `4.8 КБ`; D8).
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String skillSizeText(AppLocalizations l10n, int bytes) => '';

/// Текст баннера страницы «Skills & extensions» по сообщению.
///
/// Заглушка задачи 5.1c: возвращает пустую строку; реализация — задача 5.2.
String skillsMessageText(AppLocalizations l10n, SkillsMessage message) => '';
