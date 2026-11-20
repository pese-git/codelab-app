/// Тексты проблем темы на языке интерфейса (design.md change
/// `add-app-appearance-page`, D15).
///
/// Почему здесь, а не в ядре клиента: ядро языконезависимо, оно отдаёт код,
/// позицию и аргументы (`ThemeIssue`), а текст строит клиент по ARB — CLI
/// строит свой (spec client-themes «Нестрогий разбор темы в app»). Английской
/// строки ядра у проблемы нет и использовать её нельзя.
///
/// Как использовать: страница «Appearance» зовёт [themeIssueTitle] и
/// [themeIssueNote] для предупреждений, [themeErrorReason] — для ошибки темы.
/// Ключи, значения и имена файлов из файла показываются как есть (экранирует
/// вызывающий).
library;

import 'package:codelab_client_core/codelab_client_core.dart';

import '../../../l10n/app_localizations.dart';

/// Заголовок строки списка предупреждений разбора:
/// `<file>:<line>:<col> unknown key "<key>"`.
String themeIssueTitle(AppLocalizations l10n, String file, ThemeIssue issue) =>
    switch (issue.code) {
      ThemeIssueCode.unknownKey => l10n.appearanceIssueUnknownKey(
        file,
        issue.line,
        issue.column,
        issue.key ?? '',
      ),
      ThemeIssueCode.duplicateKey => l10n.appearanceIssueDuplicateKey(
        file,
        issue.line,
        issue.column,
        issue.key ?? '',
      ),
      ThemeIssueCode.terminalColor => l10n.appearanceIssueTerminalColor(
        file,
        issue.line,
        issue.column,
        issue.value ?? '',
      ),
      // Ошибки сюда не попадают: их показывает [themeErrorTitle].
      _ => themeErrorTitle(l10n, file, issue),
    };

/// Пояснение под строкой предупреждения; `null` у ошибок.
String? themeIssueNote(AppLocalizations l10n, ThemeIssue issue) =>
    switch (issue.code) {
      ThemeIssueCode.unknownKey =>
        issue.hint == null
            ? l10n.appearanceIssueUnknownKeyNoHint
            : l10n.appearanceIssueUnknownKeyHint(issue.hint!),
      ThemeIssueCode.duplicateKey => l10n.appearanceIssueDuplicateKeyHint,
      ThemeIssueCode.terminalColor => l10n.appearanceIssueTerminalColorHint,
      _ => null,
    };

/// Причина ошибки темы без позиции: «The file is not valid JSON.».
String themeErrorReason(AppLocalizations l10n, ThemeIssue issue) =>
    switch (issue.code) {
      ThemeIssueCode.tooLarge => l10n.appearanceIssueTooLarge,
      ThemeIssueCode.notUtf8 => l10n.appearanceIssueNotUtf8,
      ThemeIssueCode.invalidJson => l10n.appearanceIssueInvalidJson,
      ThemeIssueCode.notAnObject => l10n.appearanceIssueNotAnObject,
      ThemeIssueCode.missingName => l10n.appearanceIssueMissingName,
      ThemeIssueCode.invalidName => l10n.appearanceIssueInvalidName,
      ThemeIssueCode.nameMismatch => l10n.appearanceIssueNameMismatch,
      ThemeIssueCode.reservedName => l10n.appearanceIssueReservedName,
      ThemeIssueCode.invalidExtends => l10n.appearanceIssueInvalidExtends,
      ThemeIssueCode.invalidValue => l10n.appearanceIssueInvalidValue,
      // Предупреждения не бывают причиной отказа загрузить тему.
      _ => l10n.appearanceIssueUnreadable,
    };

/// Ошибка темы с позицией и именем файла: `<file>:<line>:<col> <причина>`.
String themeErrorTitle(AppLocalizations l10n, String file, ThemeIssue issue) =>
    l10n.appearanceIssueWithPosition(
      file,
      issue.line,
      issue.column,
      themeErrorReason(l10n, issue),
    );

/// Ошибка темы с позицией без имени файла (InfoBar ошибки импорта, где файл
/// уже назван).
String themeErrorAt(AppLocalizations l10n, ThemeIssue issue) =>
    l10n.appearanceIssuePosition(
      issue.line,
      issue.column,
      themeErrorReason(l10n, issue),
    );

/// Причина, по которой файл темы не прочитан.
String themeReadErrorReason(AppLocalizations l10n, ThemeReadError error) =>
    switch (error) {
      ThemeReadError.tooLarge => l10n.appearanceIssueTooLarge,
      ThemeReadError.notUtf8 => l10n.appearanceIssueNotUtf8,
      ThemeReadError.unreadable => l10n.appearanceIssueUnreadable,
    };
