import 'dart:ui' show Brightness;

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:fluent_ui/fluent_ui.dart' show FluentThemeData;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/appearance/app_appearance_cubit.dart';
import '../../../core/platform/local_folder_opener.dart';
import '../../../core/platform/theme_file_picker.dart';
import 'contrast_checks.dart';

/// Вид темы на карточке (`Built-in · default`, `Built-in`, `Custom · extends`).
enum AppearanceThemeKind { builtInDefault, builtIn, custom }

/// Карточка темы страницы «Appearance» (design.md change
/// `add-app-appearance-page`, D13, D14).
///
/// Почему данные, а не виджет: страница только рисует; разбор, контраст и
/// подсчёт предупреждений делает Cubit, потому что бейдж `N warnings`
/// учитывает и предупреждения разбора, и роли с низким контрастом.
///
/// Для чего: [theme] — готовая `FluentThemeData` для мини-превью и блока
/// «Preview» (`null` у темы, которая не загрузилась); [mode] — режим темы
/// (`null` у не загрузившейся); [extendsBase] — `extends` пользовательской
/// темы; [contrast] — проверки на фоне кода; [parseWarnings] — число
/// предупреждений разбора.
final class AppearanceThemeCard {
  const AppearanceThemeCard({
    required this.id,
    required this.kind,
    required this.loaded,
    this.mode,
    this.extendsBase,
    this.theme,
    this.contrast = const [],
    this.parseWarnings = 0,
  });

  final String id;
  final AppearanceThemeKind kind;
  final bool loaded;
  final Brightness? mode;
  final String? extendsBase;
  final FluentThemeData? theme;
  final List<ContrastCheck> contrast;
  final int parseWarnings;

  /// Роли ниже порога 4,5:1: они применяются как заданы, но дают предупреждение.
  int get lowContrast => contrast.where((c) => !c.passes).length;

  /// Число в бейдже `N warnings`: предупреждения разбора и низкий контраст.
  int get warningCount => parseWarnings + lowContrast;
}

/// Проблема выбранной темы: строка списка `settings-appearance-issue-<n>`.
sealed class AppearanceIssue {
  const AppearanceIssue();
}

/// Предупреждение разбора файла (код, позиция, ключ, подсказка — без текста).
final class AppearanceParseIssue extends AppearanceIssue {
  const AppearanceParseIssue(this.issue);

  final ThemeIssue issue;
}

/// Роль ниже порога контраста: `Low contrast` в списке и на карточке.
final class AppearanceLowContrastIssue extends AppearanceIssue {
  const AppearanceLowContrastIssue(this.role, this.ratio);

  final ThemeRole role;
  final double ratio;
}

/// Данные панели проблем и просмотра выбранной темы.
///
/// [fileText] — текст файла (до 64 КиБ, `null`, если файл не прочитан или тема
/// встроенная); [issues] — по порядку позиции; [unsetRoles] — справка о
/// незаданных ролях без `status_bg` и `approval_border`, которые app не
/// применяет (Q8); [error] — ошибка разбора, [readError] — ошибка чтения
/// файла: тогда тема не загрузилась и справки о ролях нет.
final class AppearanceSelection {
  const AppearanceSelection({
    required this.card,
    this.fileText,
    this.issues = const [],
    this.unsetRoles = const [],
    this.error,
    this.readError,
  });

  final AppearanceThemeCard card;
  final String? fileText;
  final List<AppearanceIssue> issues;
  final List<ThemeRole> unsetRoles;
  final ThemeIssue? error;
  final ThemeReadError? readError;

  /// Строки файла с предупреждением разбора (с 1) для `CodeLabFilePreview`.
  Set<int> get warningLines => {
    for (final issue in issues)
      if (issue is AppearanceParseIssue && issue.issue.line > 0)
        issue.issue.line,
  };
}

/// Исход импорта на странице: идёт ли он и что нужно показать.
enum AppearanceImportStatus { idle, importing, needsReplace, failed }

/// Состояние «Import JSON…» (spec app-settings «Импорт темы на странице»).
///
/// [name] — имя темы из файла (для диалога замены); [fileName] — имя
/// выбранного файла; [issue] — ошибка разбора с позицией (`failed`);
/// [writeFailed] — ошибка записи без текста исключения.
final class AppearanceImport {
  const AppearanceImport({
    this.status = AppearanceImportStatus.idle,
    this.name,
    this.fileName,
    this.issue,
    this.writeFailed = false,
  });

  final AppearanceImportStatus status;
  final String? name;
  final String? fileName;
  final ThemeIssue? issue;
  final bool writeFailed;
}

/// Состояние страницы «Appearance» (D13).
///
/// [loading] — каталог читается: карточки встроенных тем работают, на месте
/// пользовательских — индикатор; [cards] — встроенные, затем пользовательские в
/// порядке каталога; [selectedId] и [selection] — тема для превью и панели
/// проблем (по умолчанию действующая); [folder] — исход последнего «Open
/// folder».
final class AppearanceSettingsState {
  const AppearanceSettingsState({
    this.loading = true,
    this.cards = const [],
    this.selectedId,
    this.selection,
    this.import = const AppearanceImport(),
    this.folder,
    this.themesLabel,
  });

  final bool loading;
  final List<AppearanceThemeCard> cards;
  final String? selectedId;
  final AppearanceSelection? selection;
  final AppearanceImport import;
  final FolderOpenOutcome? folder;

  /// Путь каталога тем для показа: `~/.codelab/themes/*.json` (домашний
  /// каталог сокращён до `~`); `null` — каталог недоступен. Строит composition
  /// root: страница не знает окружения и `dart:io`.
  final String? themesLabel;

  AppearanceSettingsState copyWith({
    bool? loading,
    List<AppearanceThemeCard>? cards,
    String? selectedId,
    AppearanceSelection? selection,
    AppearanceImport? import,
    FolderOpenOutcome? folder,
    String? themesLabel,
  }) => AppearanceSettingsState(
    loading: loading ?? this.loading,
    cards: cards ?? this.cards,
    selectedId: selectedId ?? this.selectedId,
    selection: selection ?? this.selection,
    import: import ?? this.import,
    folder: folder ?? this.folder,
    themesLabel: themesLabel ?? this.themesLabel,
  );
}

/// Cubit страницы «Appearance»: каталог тем, выбор для превью, импорт, «Open
/// folder» (D9, D11, D13).
///
/// Почему отдельно от [AppAppearanceCubit]: тот владеет ПРИМЕНЁННЫМ
/// оформлением на весь процесс, а этот — временным состоянием страницы
/// (выбранная карточка, чтение каталога, диалог замены); его создаёт
/// composition root на открытие страницы (`createAppearanceSettingsCubit`),
/// закрывает страница.
///
/// Для чего: выбор карточки НЕ применяет тему; применение — «Use» и «Reset»,
/// которые вызывают [AppAppearanceCubit]. Чтение каталога несёт номер:
/// результат после нового «Reload» или `close()` отбрасывается с событием
/// `appearance.catalog_discarded`. Импорт блокирует повторный до завершения.
/// Файл темы приложение не открывает — «Open folder» открывает каталог через
/// `LocalFolderOpener` (D11).
///
/// ЗАГЛУШКА для красных тестов 5.3/5.5: форма API; методы пустые, реализация —
/// задача 5.4. Класс не `final`: тесты страницы подставляют наследника.
class AppearanceSettingsCubit extends Cubit<AppearanceSettingsState> {
  AppearanceSettingsCubit({
    required ThemeLibrary library,
    required AppAppearanceCubit appearance,
    required ThemeFilePicker picker,
    required LocalFolderOpener folderOpener,
    required Brightness Function() systemBrightness,
    String? themesDirectory,
    Logger? logger,
  }) : super(const AppearanceSettingsState());

  /// Читает каталог и выбирает действующую тему для превью.
  Future<void> load() async {}

  /// «Reload»: перечитывает каталог; если выбранная тема назначена режиму,
  /// применяет её файл заново.
  Future<void> reload() async {}

  /// Выбирает карточку для превью и панели проблем; тему НЕ применяет.
  Future<void> select(String id) async {}

  /// «Import JSON…»: диалог, импорт, превью импортированной темы.
  Future<void> importJson() async {}

  /// «Replace» в диалоге замены.
  Future<void> confirmReplace() async {}

  /// «Cancel» в диалоге замены.
  void cancelReplace() {}

  /// «Open folder»: каталог тем через `LocalFolderOpener` (`create: true`).
  Future<void> openFolder() async {}

  /// «Use `<name>`»: назначает выбранную тему её режиму.
  Future<void> useSelected() async {}

  /// «Reset»: возвращает режиму выбранной темы встроенную по умолчанию и
  /// выбирает её для превью.
  Future<void> resetSelected() async {}
}
